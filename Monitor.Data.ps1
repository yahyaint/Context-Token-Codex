# SPDX-License-Identifier: MIT
# Dot-source after Monitor.Core.ps1. One scan produces an immutable UI snapshot.
function Read-WidgetPreferences([string]$Path, [hashtable]$Defaults) {
    $result=@{}; foreach ($key in $Defaults.Keys) {$result[$key]=$Defaults[$key]}
    if (-not [IO.File]::Exists($Path)) {return $result}
    $invalid=$false
    try {$loaded=[IO.File]::ReadAllText($Path)|ConvertFrom-Json -ErrorAction Stop} catch {$loaded=$null; $invalid=$true}
    foreach ($key in $Defaults.Keys) {
        $value=$loaded.$key; if ($null -eq $value) {continue}
        if ($key -in @('AutoOpen','Topmost','Compact')) {if ($value -is [bool]) {$result[$key]=$value};continue}
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
function Get-MonitorSnapshot {
    Refresh-DatabasePaths
    foreach ($file in @(Get-RolloutFiles)) { Update-Rollout $file }
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
    $tokens=if (Get-Command Get-RecordedTokenSummary -ErrorAction SilentlyContinue) { Get-RecordedTokenSummary } else { $null }
    [pscustomobject]@{ Updated=[DateTimeOffset]::Now; Cards=$cards; Projects=@(Get-KnownProjectPaths); Quota=(Get-QuotaLine); Tokens=$tokens;
        Discovery=$script:discoveryMode; Warning=$script:discoveryWarning; Compaction=$script:logStatus }
}

function Get-TargetAppInstances([string]$target, $Processes=$null) {
    if ($target -notin @('Codex','ChatGPT','Either')) {$target='Either'}
    if ($null -eq $Processes) {$Processes=@(Get-Process -Name ChatGPT,Codex -ErrorAction SilentlyContinue)}
    foreach ($process in $Processes) {
        try {
            $path=[string]$process.Path
            if (-not $path -or ([long]$process.MainWindowHandle -eq 0)) {continue}
            $isCodex=$path -match 'OpenAI[.\\]Codex|\\Codex\\|\\Codex\.exe$'
            $isChatGPT=$path -match 'OpenAI[.\\]ChatGPT|\\ChatGPT\\|\\ChatGPT\.exe$'
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
function Get-StartupShortcut { Join-Path ([Environment]::GetFolderPath('Startup')) 'Context-Token Codex.lnk' }
function Set-OverlayStartup([bool]$enabled, [string]$folder) {
    $path = Get-StartupShortcut
    if ($enabled) {
        $shell = New-Object -ComObject WScript.Shell
        $link = $shell.CreateShortcut($path)
        $link.TargetPath = Join-Path $folder 'ContextWidget.exe'
        $link.Arguments = '/watch'
        $link.IconLocation = (Join-Path $folder 'Context.ico') + ',0'
        $link.WorkingDirectory = $folder
        $link.Description = 'Open the context overlay when your selected app starts.'
        $link.Save()
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    } elseif (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
}
