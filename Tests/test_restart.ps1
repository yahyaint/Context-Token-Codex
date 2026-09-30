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
$processes=@(
    [pscustomobject]@{Id=1;Path='C:\Program Files\WindowsApps\OpenAI.Codex_26.928_x64__publisher\app\ChatGPT.exe';MainWindowHandle=123},
    [pscustomobject]@{Id=2;Path='C:\Program Files\WindowsApps\OpenAI.ChatGPT_26.928_x64__publisher\app\ChatGPT.exe';MainWindowHandle=456},
    [pscustomobject]@{Id=3;Path='C:\Apps\Codex\Codex.exe';MainWindowHandle=789},
    [pscustomobject]@{Id=4;Path='C:\Apps\ChatGPT\ChatGPT.exe';MainWindowHandle=111},
    [pscustomobject]@{Id=5;Path='C:\Program Files\WindowsApps\OpenAI.Codex_27.001_x64__publisher\app\RenamedDesktop.exe';MainWindowHandle=222},
    [pscustomobject]@{Id=6;Path='';MainWindowHandle=333},
    [pscustomobject]@{Id=7;Path='C:\Users\Example\AppData\Local\OpenAI\Codex\bin\hash\codex.exe';MainWindowHandle=444},
    [pscustomobject]@{Id=8;Path='C:\Program Files\WindowsApps\OpenAI.Codex_27.001_x64__publisher\app\resources\node.exe';MainWindowHandle=555}
)
$selected=@(Select-CodexDesktopProcesses $processes)
Assert ($selected.Count -eq 3 -and $selected.Id -contains 1 -and $selected.Id -contains 3 -and $selected.Id -contains 5) 'Package identity failed after a process name or version change.'
Assert ($selected.Id -notcontains 2 -and $selected.Id -notcontains 4 -and $selected.Id -notcontains 6) 'Other apps or unknown paths were selected.'
Assert ($selected.Id -notcontains 7 -and $selected.Id -notcontains 8) 'CLI or bundled helper was selected.'
'PASS: restart gate blocks active, unknown, partial, unreadable and capped scans; latest lifecycle wins. No apps were closed.'
$fixture=Join-Path $env:TEMP ('ctc-expiry-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$statusPath=Join-Path $fixture 'restart.json';$expiry=$now.AddHours(2).ToUniversalTime().ToString('o')
Write-RestartStatus $statusPath 'Waiting' 'Fixture waiting.' $expiry
Write-RestartStatus $statusPath 'Blocked' 'Fixture blocked.'
$stored=[IO.File]::ReadAllText($statusPath)|ConvertFrom-Json
Assert (([DateTimeOffset]$stored.ExpiresAt) -eq ([DateTimeOffset]$expiry)) 'Status update extended or removed request expiry.'
$newExpiry=$now.AddHours(24).ToUniversalTime().ToString('o')
Write-RestartStatus $statusPath 'Waiting' 'New fixture request.' $newExpiry
Assert (([DateTimeOffset]([IO.File]::ReadAllText($statusPath)|ConvertFrom-Json).ExpiresAt) -eq ([DateTimeOffset]$newExpiry)) 'A new explicit request did not get its own expiry.'
'PASS: restart expiry persists across helper status updates; new requests get a new expiry.'
