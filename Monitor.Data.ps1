# SPDX-License-Identifier: MIT
# Dot-source after Monitor.Core.ps1. One scan produces an immutable UI snapshot.
function Read-WidgetPreferences([string]$Path, [hashtable]$Defaults) {
    $result=@{}; foreach ($key in $Defaults.Keys) {$result[$key]=$Defaults[$key]}
    if (-not [IO.File]::Exists($Path)) {return $result}
    $invalid=$false
    try {$loaded=[IO.File]::ReadAllText($Path)|ConvertFrom-Json -ErrorAction Stop} catch {$loaded=$null; $invalid=$true}
    foreach ($key in $Defaults.Keys) {
        $value=$loaded.$key; if ($null -eq $value) {continue}
        if ($key -in @('AutoOpen','Topmost','Compact','StartParked')) {if ($value -is [bool]) {$result[$key]=$value};continue}
        $choices=switch($key){'Mode'{@('Context','Tokens')};'Target'{@('Either','Codex','ChatGPT')};'Corner'{@('Free','TopLeft','TopRight','BottomLeft','BottomRight')}}
        if ($choices) {if ($value -in $choices) {$result[$key]=[string]$value};continue}
        $number=0.0
        if (-not [double]::TryParse([string]$value,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$number) -or [double]::IsNaN($number) -or [double]::IsInfinity($number)) {continue}
        switch ($key) {
            'Opacity' {if($number -ge .4 -and $number -le 1){$result[$key]=$number}}
            'Width' {if($number -ge 360 -and $number -le 8192){$result[$key]=$number}}
            'Height' {if($number -ge 320 -and $number -le 8192){$result[$key]=[Math]::Max(520,$number)}}
            default {if($key -in @('Left','Top') -and [Math]::Abs($number) -le 100000){$result[$key]=$number}}
        }
    }
    foreach ($key in $Defaults.Keys) {if ($null -ne $loaded.$key -and [string]$loaded.$key -cne [string]$result[$key]) {$invalid=$true}}
    if ($invalid) {
        Copy-Item -LiteralPath $Path -Destination ($Path+'.invalid-'+[guid]::NewGuid().ToString('N')+'.bak') -ErrorAction Stop
    }
    return $result
}
function Get-KnownProjectPaths {
    if ($script:projectPaths -and ([DateTime]::UtcNow-$script:projectPathsAt).TotalSeconds -lt 30) { return $script:projectPaths }
    $paths=@{}
    foreach ($state in $script:rollouts.Values) { if ($state.Cwd) { $paths[$state.Cwd]=$true } }
    if ($script:sqlite -and $script:stateDatabase) {
        foreach ($row in @(Invoke-Sqlite 'SELECT DISTINCT cwd FROM threads WHERE cwd IS NOT NULL;' $script:stateDatabase)) { if ($row.cwd) {$paths[[string]$row.cwd]=$true} }
        foreach ($row in @(Invoke-Sqlite 'SELECT DISTINCT path FROM project_roots;' $script:stateDatabase)) { if ($row.path) {$paths[[string]$row.path]=$true} }
    }
    $globalState=Join-Path $CodexHome '.codex-global-state.json'
    if (Test-Path -LiteralPath $globalState) {
        try {
            $saved=Get-Content -LiteralPath $globalState -Raw -Encoding UTF8|ConvertFrom-Json
            foreach ($path in @($saved.'electron-saved-workspace-roots')) { if ($path -is [string]) {$paths[$path]=$true} }
            foreach ($project in $saved.'local-projects'.PSObject.Properties) { foreach ($path in @($project.Value.rootPaths)) { if ($path -is [string]) {$paths[$path]=$true} } }
        } catch {}
    }
    $script:projectPaths=@($paths.Keys|Where-Object {[IO.Path]::IsPathRooted($_)}|Sort-Object)
    $script:projectPathsAt=[DateTime]::UtcNow
    return $script:projectPaths
}
function Get-MonitorSnapshot([switch]$QuickStart) {
    Refresh-DatabasePaths
    foreach ($file in @(Get-RolloutFiles)) { Update-Rollout $file -QuickStart:$QuickStart }
    Remove-ExpiredRolloutStates
    Update-IndexTitles
    if ($script:sqlite) {
        if ($LogDatabase -and (Test-Path -LiteralPath $LogDatabase)) {
            if ($script:lastLogId -eq 0L) {
                $since = [DateTimeOffset]::UtcNow.AddMinutes(-3).ToUnixTimeSeconds()
                $rows = Invoke-Sqlite "SELECT min(id) AS id FROM logs WHERE ts >= $since;"
                if ($rows.Count -gt 0 -and $rows[0].id) { $script:lastLogId = [long]$rows[0].id - 1L }
            }
            Update-CompactionLog
        }
        Update-Titles
    }
    $cards = @(foreach ($state in @(Get-DisplayStates)) {
        $identity = $script:titleCache[$state.ThreadId]
        $title = if ($identity.UiName) { $identity.UiName } elseif ($identity.Initial) { $identity.Initial } else { $state.ThreadId }
        $status = 'RUNNING'
        if ($state.ReadError) { $status = 'READ ERROR' }
        elseif ($state.CompactingAt -gt $state.LastCompactAt -and $state.CompactingAt -ge $state.StartedAt) { $status = 'COMPACTING' }
        elseif (([DateTimeOffset]::Now - $state.LastEventAt).TotalMinutes -gt 10) { $status = 'NO RECENT EVENTS' }
        $percent = $null
        if ($null -ne $state.ContextInput -and $state.ContextWindow -gt 0) { $percent = 100.0 * $state.ContextInput / $state.ContextWindow }
        $count = 0
        foreach ($other in $script:rollouts.Values) { if ($other.ThreadId -eq $state.ThreadId) { $count += $other.CompactCount } }
        [pscustomobject]@{ Id=$state.ThreadId; Title=$title; Initial=$identity.Initial; Model=$state.Model;
            Cwd=$state.Cwd; Status=$status; Percent=$percent; Input=$state.ContextInput; Window=$state.ContextWindow;
            Cached=$state.CachedInput; Output=$state.OutputTokens; Compactions=$count;
            LastEvent=$state.LastEventAt.ToLocalTime().ToString('HH:mm:ss'); Saved=(Get-SavedWindowStatus $state);
            Error=$state.ReadError }
    })
    $tokens=if (Test-Path Function:\Get-RecordedTokenSummary) { Get-RecordedTokenSummary } else { $null }
    [pscustomobject]@{ Updated=[DateTimeOffset]::Now; Cards=$cards; Projects=@(Get-KnownProjectPaths); Quota=(Get-QuotaLine); Tokens=$tokens;
        Restart=$(if(Test-Path Function:\Get-RestartReadiness){Get-RestartReadiness @($script:rollouts.Values) $MaxRecentRollouts}else{$null}); Discovery=$script:discoveryMode; Warning=$script:discoveryWarning; Compaction=$script:logStatus }
}

function Get-LimitsQueueEntryView($Entry,$Cards,[string]$GlobalPath) {
    $globalScope=$Entry.Path -ieq $GlobalPath
    $project=Split-Path (Split-Path $Entry.Path -Parent) -Parent
    $currentWindow=$null;$currentCompact=$null;$readError=''
    try {
        $currentWindow=Get-TopLevelContextWindow $Entry.Path
        $currentCompact=Get-TopLevelAutoCompactLimit $Entry.Path
    }catch{$readError=$_.Exception.Message}
    $changed=([string]$Entry.Window -cne [string]$currentWindow -or [string]$Entry.Compact -cne [string]$currentCompact)
    $rows=@(foreach($card in @($Cards)){
        $cwd=[string]$card.Cwd
        $inProject=$cwd -ieq $project -or ($cwd -and $cwd.StartsWith($project.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase))
        if(-not $globalScope -and -not $inProject -and $card.Saved.Path -ine $Entry.Path){continue}
        # A project override cannot confirm a queued global setting.
        $sameScope=$card.Saved.Path -ieq $Entry.Path
        $status=if($readError){'Unverified'}elseif($changed){'Settings changed'}elseif($sameScope -and $card.Saved.Status){[string]$card.Saved.Status}elseif($globalScope -and $card.Saved.Path){'Project override'}elseif($card.Saved.Path){'Inherited window'}else{'Unverified'}
        [pscustomobject]@{Id=$card.Id;Title=$card.Title;Window=$card.Window;Status=$status}
    })
    [pscustomobject]@{Changed=$changed;ReadError=$readError;CurrentWindow=$currentWindow;CurrentCompact=$currentCompact;Rows=$rows}
}

function Get-TargetAppInstances([string]$target, $Processes=$null) {
    if ($target -notin @('Codex','ChatGPT','Either')) {$target='Either'}
    if ($null -eq $Processes) {$Processes=@(Get-Process -ErrorAction SilentlyContinue)}
    foreach ($process in $Processes) {
        try {
            if([long]$process.MainWindowHandle -eq 0){continue}
            $path=[string]$process.Path
            if (-not $path) {continue}
            $isCodex=$path -match '\\OpenAI\.Codex_[^\\]+\\app\\[^\\]+\.exe$|\\(?:OpenAI[.\\])?Codex\\(?:app\\)?(?:Codex|ChatGPT)\.exe$'
            $isChatGPT=$path -match '\\OpenAI\.ChatGPT[^\\]*\\app\\[^\\]+\.exe$|\\(?:OpenAI[.\\])?ChatGPT\\(?:app\\)?ChatGPT\.exe$'
            if (-not $isCodex -and -not $isChatGPT) {continue}
            $kind=if ($isCodex) {'Codex'} else {'ChatGPT'}
            if ($target -ne 'Either' -and $target -ne $kind) {continue}
            # No package version is cached: replacement processes/windows are new instances.
            "$kind/$($process.Id)/$($process.StartTime.ToUniversalTime().Ticks)/$($process.MainWindowHandle)"
        } catch {continue}
    }
}
function Test-TargetApp([string]$target) { return @(Get-TargetAppInstances $target).Count -gt 0 }
function Get-NewAppInstances($Current,$Previous) {
    @($Current|Where-Object {$_ -notin @($Previous)})
}
function Test-OverlayReady {
    try {$ready=[Threading.EventWaitHandle]::OpenExisting('Local\CodexContextOverlayReady-'+[Environment]::UserName);try{return $ready.WaitOne(0)}finally{$ready.Dispose()}}catch [Threading.WaitHandleCannotBeOpenedException]{return $false}
}
function Get-WatcherLaunchAction($state,$current,[bool]$ready,$now=[DateTimeOffset]::Now) {
    if(@(Get-NewAppInstances $current $state.Previous).Count -gt 0){
        $state.Pending=-not $ready;$state.Next=$now.AddSeconds(15);$state.Previous=@($current);return $true
    }
    $state.Previous=@($current)
    if($state.Pending -and $ready){$state.Pending=$false;return $false}
    if($state.Pending -and @($current).Count -gt 0 -and $now -ge $state.Next){$state.Next=$now.AddSeconds(15);return $true}
    return $false
}
function Get-StartupShortcut { Join-Path ([Environment]::GetFolderPath('Startup')) 'Context-Token Codex.lnk' }
function Update-CtcShortcutIcon([string]$Path) {
    # Notify Explorer about this shortcut only. Do not clear the user's icon cache.
    if(-not ('CtcShellIcons' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CtcShellIcons {
 [DllImport("shell32.dll", CharSet=CharSet.Unicode)]
 public static extern void SHChangeNotify(uint change, uint flags, string path, IntPtr unused);
}
'@
    }
    [CtcShellIcons]::SHChangeNotify(0x2000,0x5,$Path,[IntPtr]::Zero)
}
function Set-OverlayStartup([bool]$enabled, [string]$folder) {
    $path = Get-StartupShortcut
    if ($enabled) {
        $shell = New-Object -ComObject WScript.Shell
        $link = $shell.CreateShortcut($path)
        $link.TargetPath = Join-Path $folder 'ContextWidget.exe'
        $link.Arguments = '/watch'
        $link.IconLocation = (Join-Path $folder 'ContextWidget.exe') + ',0'
        $link.WorkingDirectory = $folder
        $link.Description = 'Open the widget when the selected app starts.'
        $link.Save()
        Update-CtcShortcutIcon $path
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    } elseif (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
}
