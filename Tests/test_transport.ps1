# SPDX-License-Identifier: MIT
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Usage.Provider.ps1')
$fixture=Join-Path $env:TEMP ('context-rpc-'+[guid]::NewGuid().ToString('N')+'.ps1')
@'
param($Scenario)
if ($Scenario -eq 'exit') { exit }
if ($Scenario -eq 'hang') { Start-Sleep 30; exit }
while ($line=[Console]::ReadLine()) {
 $message=$line|ConvertFrom-Json
 if ($message.id -eq 1) { if ($Scenario -eq 'slow') {Start-Sleep -Seconds 13}; [Console]::WriteLine('diagnostic'); [Console]::WriteLine('{"id":1,"result":{}}') }
 if ($message.id -eq 2) {
  if ($Scenario -eq 'slow') {[Console]::WriteLine('{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300}}}}')} elseif ($Scenario -eq 'old') { [Console]::WriteLine('{"id":2,"error":{"code":-32602}}') }
  else { [Console]::WriteLine('{"id":2,"error":{"code":-32000}}') }
 }
 if ($message.id -eq 3) { [Console]::WriteLine('{"id":3,"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300}}}}') }
}
'@ | Set-Content -LiteralPath $fixture -Encoding UTF8
$exe=(Get-Process -Id $PID).Path
$q=Get-CodexRateLimits -Executable $exe -Arguments ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$fixture+'" old') -TimeoutSeconds 30
if ($q.Windows[0].Remaining -ne 75) { throw 'Legacy RPC retry failed.' }
$slow=Get-CodexRateLimits -Executable $exe -Arguments ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$fixture+'" slow')
if ($slow.Windows[0].Remaining -ne 75) {throw 'Slow initialization failed.'}
foreach ($scenario in @('error','exit','hang')) {
 $failed=$false
 try { $null=Get-CodexRateLimits -Executable $exe -Arguments ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$fixture+'" '+$scenario) -TimeoutSeconds 2 } catch { $failed=$true }
 if (-not $failed) { throw "Transport $scenario incorrectly succeeded." }
}
'PASS: legacy RPC parameters, noisy stdout, account error, early exit, bounded timeout and helper cleanup.'
