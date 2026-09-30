$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Restart.Core.ps1')
function Assert($value,$message){if(-not $value){throw $message}}
function State($id,$active,$when){[pscustomobject]@{ThreadId=$id;HasMetadata=$true;LifecycleKnown=$true;ReadError='';NeedsBackfill=$false;Partial='';Active=$active;LastEventAt=$when}}
$now=[DateTimeOffset]::Now
Assert (-not (Get-RestartReadiness @()).Ready) 'Empty records allow restart.'
$idle=State 'chat' $false $now
Assert (Get-RestartReadiness @($idle)).Ready 'Idle chat blocks restart.'
$active=State 'other' $true $now
Assert (-not (Get-RestartReadiness @($idle,$active)).Ready) 'Active chat allows restart.'
$resumed=State 'chat' $true $now.AddSeconds(-1)
Assert (Get-RestartReadiness @($idle,$resumed)).Ready 'Old rollout resurrects an active turn.'
$idle.ReadError='IOException'
Assert (-not (Get-RestartReadiness @($idle)).Ready) 'Read error allows restart.'
$idle.ReadError='';$idle.NeedsBackfill=$true
Assert (-not (Get-RestartReadiness @($idle)).Ready) 'Incomplete scan allows restart.'
$idle.NeedsBackfill=$false;$idle.Partial='unfinished'
Assert (-not (Get-RestartReadiness @($idle)).Ready) 'Partial record allows restart.'
$idle.Partial='';$idle.LifecycleKnown=$false
Assert (-not (Get-RestartReadiness @($idle)).Ready) 'Unknown lifecycle allows restart.'
$idle.LifecycleKnown=$true
Assert (-not (Get-RestartReadiness @($idle) 1).Ready) 'Scan limit allows restart.'
'PASS: restart gate blocks active, unknown, partial, unreadable and capped scans; latest lifecycle wins. No apps were closed.'
