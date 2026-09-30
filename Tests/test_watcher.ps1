# SPDX-License-Identifier: MIT
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Monitor.Data.ps1')
function Assert($value,$message) {if (-not $value) {throw $message}}
function App($id,$path,$handle=100) {[pscustomobject]@{Id=$id;Path=$path;MainWindowHandle=[IntPtr]$handle;StartTime=[DateTime]'2026-09-20'}}
$codex=App 1 'C:\Program Files\WindowsApps\OpenAI.Codex_26.915.0_x64__family\app\ChatGPT.exe'
$chat=App 2 'C:\Program Files\WindowsApps\OpenAI.ChatGPT-Desktop_1.0.0_x64__family\app\ChatGPT.exe'
$old=@(Get-TargetAppInstances Either @($codex))
$both=@(Get-TargetAppInstances Either @($codex,$chat))
Assert ($old.Count -eq 1 -and $both.Count -eq 2) 'App identity detection failed.'
Assert (@(Get-NewAppInstances $both $old).Count -eq 1) 'ChatGPT launch while Codex runs was missed.'
Assert (@(Get-NewAppInstances $both $both).Count -eq 0) 'Repeated poll launches duplicate widget.'
Assert (@(Get-TargetAppInstances ChatGPT @($codex,$chat)).Count -eq 1) 'ChatGPT selection includes Codex.'
$new=App 3 'C:\Program Files\WindowsApps\OpenAI.Codex_99.999.0_x64__family\app\ChatGPT.exe'
Assert (@(Get-NewAppInstances @(Get-TargetAppInstances Either @($new,$chat)) $both).Count -eq 1) 'App update/restart missed.'
$renamed=App 9 'C:\Program Files\WindowsApps\OpenAI.Codex_100.001_x64__family\app\RenamedDesktop.exe'
Assert (@(Get-TargetAppInstances Codex @($renamed)).Count -eq 1) 'Renamed desktop executable was missed.'
$helper=App 10 'C:\Program Files\WindowsApps\OpenAI.Codex_100.001_x64__family\app\resources\node.exe'
Assert (@(Get-TargetAppInstances Either @($helper)).Count -eq 0) 'Bundled helper window triggered desktop startup.'
$chat.MainWindowHandle=200
Assert (@(Get-NewAppInstances @(Get-TargetAppInstances Either @($codex,$chat)) $both).Count -eq 1) 'Reopened window in existing process missed.'
$chat.MainWindowHandle=0
Assert (@(Get-TargetAppInstances ChatGPT @($chat)).Count -eq 0) 'Background process triggered open.'
Assert (@(Get-NewAppInstances $old @()).Count -eq 1) 'Watcher start with app already open failed.'
Assert (@(Get-TargetAppInstances Either @((App 4 ''),(App 5 'C:\tools\codex.exe' 0))).Count -eq 0) 'Unavailable paths or CLI helper detected.'
'PASS: independent app launches, process/window replacement, changed package version, background exclusion, duplicate suppression.'
$now=[DateTimeOffset]::Now
$state=@{Previous=@();Pending=$false;Next=[DateTimeOffset]::MinValue}
Assert (Get-WatcherLaunchAction $state $old $false $now) 'Initial app should request a launch'
Assert (-not (Get-WatcherLaunchAction $state $old $false $now.AddSeconds(2))) 'Launch retried before its deadline'
Assert (Get-WatcherLaunchAction $state $old $false $now.AddSeconds(16)) 'Failed first launch was not retried'
Assert (-not (Get-WatcherLaunchAction $state $old $true $now.AddSeconds(17))) 'Ready overlay should settle launch tracking'
Assert (-not (Get-WatcherLaunchAction $state $old $false $now.AddSeconds(35))) 'Intentional close reopened without a new app instance'
Assert (Get-WatcherLaunchAction $state $both $true $now.AddSeconds(36)) 'New app should restore an existing hidden overlay'
'PASS: launch readiness, delayed retry, intentional close and existing-window restore.'
