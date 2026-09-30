# SPDX-License-Identifier: MIT
# This gate uses recorded lifecycle data. Unknown data always block a restart.
function Select-CodexDesktopProcesses($Processes) {
    foreach($process in @($Processes)){
        try {
            $path=[string]$process.Path
            # New desktop builds can use ChatGPT.exe inside OpenAI.Codex.
            # Identity comes from the app path, not the process display name.
            $packageMain='\\OpenAI\.Codex_[^\\]+\\app\\[^\\]+\.exe$'
            $legacyMain='\\(?:OpenAI[.\\])?Codex\\(?:app\\)?(?:Codex|ChatGPT)\.exe$'
            if($path -and ($path -match $packageMain -or $path -match $legacyMain)){$process}
        }catch{continue}
    }
}
function Get-RestartReadiness($States,[int]$FileLimit=1024) {
    $all=@($States)
    if(-not $all.Count){return [pscustomobject]@{Ready=$false;Active=$null;Reason='No chat state is available.'}}
    if($all.Count -ge $FileLimit){return [pscustomobject]@{Ready=$false;Active=$null;Reason='The scan limit was reached. Quit Codex manually.'}}
    if(@($all|Where-Object {-not $_.HasMetadata -or -not $_.LifecycleKnown -or $_.ReadError -or $_.NeedsBackfill -or $_.Partial}).Count){return [pscustomobject]@{Ready=$false;Active=$null;Reason='CTC cannot verify all chat records.'}}
    $latest=@{}
    foreach($state in $all){
        if(-not $state.ThreadId){return [pscustomobject]@{Ready=$false;Active=$null;Reason='A chat ID is unavailable.'}}
        if(-not $latest.ContainsKey($state.ThreadId) -or $state.LastEventAt -gt $latest[$state.ThreadId].LastEventAt){$latest[$state.ThreadId]=$state}
    }
    $active=@($latest.Values|Where-Object Active).Count
    [pscustomobject]@{Ready=($active -eq 0);Active=$active;Reason=$(if($active){'CTC waits for running chats to stop.'}else{'Recorded chats are idle.'})}
}
function Write-RestartStatus([string]$Path,[string]$Status,[string]$Message) {
    [void][IO.Directory]::CreateDirectory((Split-Path $Path -Parent))
    $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.File]::WriteAllText($temp,(@{Status=$Status;Message=$Message;Updated=[DateTimeOffset]::Now.ToString('o')}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
        if([IO.File]::Exists($Path)){[IO.File]::Replace($temp,$Path,[NullString]::Value)}else{[IO.File]::Move($temp,$Path)}
    }finally{if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}}
}
function Read-LimitsQueue([string]$Path) {
    if(-not [IO.File]::Exists($Path)){return @()}
    $data=[IO.File]::ReadAllText($Path)|ConvertFrom-Json
    if($data.Version -ne 1){throw 'CTC cannot read this queue format. Keep the file for repair.'}
    # New PowerShell releases can deserialize ISO dates as DateTime. Keep the
    # stored representation stable across runtimes and regional formats.
    foreach($entry in @($data.Entries)){
        if($entry.SavedAt -is [DateTime]){$entry.SavedAt=$entry.SavedAt.ToUniversalTime().ToString('o')}
    }
    return @($data.Entries)
}
function Save-LimitsQueueEntry([string]$Path,[string]$ConfigPath,$Window,$Compact) {
    $entries=@(Read-LimitsQueue $Path)
    $resolved=[IO.Path]::GetFullPath($ConfigPath)
    $entries=@($entries|Where-Object {$_.Path -ine $resolved})
    $entries+= [pscustomobject]@{Path=$resolved;Window=$Window;Compact=$Compact;SavedAt=[DateTimeOffset]::UtcNow.ToString('o')}
    [void][IO.Directory]::CreateDirectory((Split-Path $Path -Parent))
    $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.File]::WriteAllText($temp,(@{Version=1;Entries=$entries}|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
        if([IO.File]::Exists($Path)){[IO.File]::Replace($temp,$Path,[NullString]::Value)}else{[IO.File]::Move($temp,$Path)}
    }finally{if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}}
}
