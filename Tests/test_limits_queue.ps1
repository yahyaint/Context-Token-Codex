$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Restart.Core.ps1')
function Assert($value,$message){if(-not $value){throw $message}}
$fixture=Join-Path $env:TEMP ('ctc-queue-'+[guid]::NewGuid().ToString('N'))
$path=Join-Path $fixture 'limits-queue.json'
$project=Join-Path $fixture 'project/.codex/config.toml'
$global=Join-Path $fixture 'config.toml'
Assert (@(Read-LimitsQueue $path).Count -eq 0) 'Fresh queue was not empty.'
Save-LimitsQueueEntry $path $project 400000 360000
$entries=@(Read-LimitsQueue $path)
Assert ($entries.Count -eq 1 -and $entries[0].Window -eq 400000) 'Saved project missing after read.'
Save-LimitsQueueEntry $path $project 600000 540000
Save-LimitsQueueEntry $path $global $null $null
$entries=@(Read-LimitsQueue $path)
Assert ($entries.Count -eq 2 -and @($entries|Where-Object {$_.Window -eq 600000}).Count -eq 1) 'Repeat save created duplicate entries or lost an entry.'
Assert (@($entries|Where-Object {$_.Path -eq $global -and $null -eq $_.Window -and $null -eq $_.Compact}).Count -eq 1) 'Default reset was lost.'
Assert ([DateTimeOffset]::Parse($entries[0].SavedAt) -le [DateTimeOffset]::UtcNow) 'Save time was invalid.'
$bad='{"Version":99,"Entries":[]}'
[IO.File]::WriteAllText($path,$bad)
$rejected=$false;try{Save-LimitsQueueEntry $path $project 1 1}catch{$rejected=$true}
Assert ($rejected -and [IO.File]::ReadAllText($path) -eq $bad) 'Unknown queue format was overwritten.'
foreach($bad in @('{"Version":1}','{"Version":1,"Entries":[null]}','{"Version":1,"Entries":[{"Path":"relative.toml"}]}')){
    [IO.File]::WriteAllText($path,$bad);$rejected=$false
    try{Save-LimitsQueueEntry $path $project 1 1}catch{$rejected=$true}
    Assert ($rejected -and [IO.File]::ReadAllText($path) -eq $bad) 'Malformed queue entries were accepted or overwritten.'
}
foreach($badLimit in @(-1,1.5,$true,'huge')){
    $bad=@{Version=1;Entries=@(@{Path=$project;Window=$badLimit;Compact=$null})}|ConvertTo-Json -Depth 4 -Compress
    [IO.File]::WriteAllText($path,$bad);$rejected=$false
    try{Save-LimitsQueueEntry $path $project 1 1}catch{$rejected=$true}
    Assert ($rejected -and [IO.File]::ReadAllText($path) -eq $bad) 'Invalid stored queue limit was accepted or overwritten.'
}
'PASS: durable queue, repeat saves, separate scopes, default reset and corrupt format preservation.'

$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Monitor.Core.ps1') -CodexHome $fixture
. (Join-Path $root 'Monitor.Data.ps1')
[void][IO.Directory]::CreateDirectory((Split-Path $project -Parent))
[IO.File]::WriteAllText($global,"model_context_window = 400000`nmodel_auto_compact_token_limit = 360000`n")
[IO.File]::WriteAllText($project,"model_context_window = 600000`nmodel_auto_compact_token_limit = 540000`n")
$card=[pscustomobject]@{Id='chat';Title='Fixture';Cwd=(Join-Path $fixture 'project/child');Window=570000;Saved=[pscustomobject]@{Path=$project;Status='Confirmed'}}
$globalEntry=[pscustomobject]@{Path=$global;Window=400000;Compact=360000}
$projectEntry=[pscustomobject]@{Path=$project;Window=600000;Compact=540000}
$view=Get-LimitsQueueEntryView $globalEntry @($card) $global
Assert ($view.Rows[0].Status -eq 'Project override') 'Project confirmation was used for a global queue entry.'
$view=Get-LimitsQueueEntryView $projectEntry @($card) $global
Assert ($view.Rows.Count -eq 1 -and $view.Rows[0].Status -eq 'Confirmed' -and -not $view.Changed) 'Matching nested project confirmation was lost.'
[IO.File]::WriteAllText($project,"model_context_window = 500000`nmodel_auto_compact_token_limit = 450000`n")
$view=Get-LimitsQueueEntryView $projectEntry @($card) $global
Assert ($view.Changed -and $view.CurrentWindow -eq 500000 -and $view.Rows[0].Status -eq 'Settings changed') 'External edit left queued values falsely current or confirmed.'
[IO.File]::Delete($project)
$view=Get-LimitsQueueEntryView $projectEntry @($card) $global
Assert ($view.Changed -and $null -eq $view.CurrentWindow) 'Removed overrides remained saved in the queue view.'
[IO.File]::WriteAllText($project,'model_context_window = broken')
$view=Get-LimitsQueueEntryView $projectEntry @($card) $global
Assert ($view.ReadError -and $view.Rows[0].Status -eq 'Unverified') 'Unreadable settings remained confirmed.'
$card.Saved=[pscustomobject]@{Path=$global;Status='Confirmed'}
[IO.File]::WriteAllText($project,'# inherit the window')
$projectEntry.Window=$null;$projectEntry.Compact=$null
$view=Get-LimitsQueueEntryView $projectEntry @($card) $global
Assert ($view.Rows[0].Status -eq 'Inherited window') 'Inherited global confirmation was used for a project reset.'
'PASS: queue scope confirmation, nested projects, external edits, default resets and unreadable files.'
