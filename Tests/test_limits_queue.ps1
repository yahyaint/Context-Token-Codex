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
'PASS: durable queue, repeat saves, separate scopes, default reset and corrupt format preservation.'
