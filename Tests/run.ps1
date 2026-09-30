# SPDX-License-Identifier: MIT
[CmdletBinding()]
param([switch]$Desktop,[string]$Archive='',[string]$Report='')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(-not [IO.File]::Exists((Join-Path $root 'ContextWidget.exe'))){throw 'Run Build/build.ps1 before the tests.'}
$shell=(Get-Process -Id $PID).Path
$names=@('settings','context_editor','limits_matrix','limits_queue','account_quota','usage','activity','exec_activity','estimator','compatibility','startup','watcher','restart','regressions','repository','branding','transport')
if($Desktop){$names+=@('theme','overlay','install','restart_flow')}
if($Archive){$Archive=[IO.Path]::GetFullPath($Archive);$names+='bootstrap'}
$results=@()
foreach($name in $names){
 $timer=[Diagnostics.Stopwatch]::StartNew(); $passed=$false; $output=''
 try {
  $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',(Join-Path $PSScriptRoot "test_$name.ps1"))
  if($name -eq 'bootstrap'){$arguments+=@('-Archive',$Archive)}
  $output=(& $shell @arguments 2>&1 | Out-String)
  $passed=($LASTEXITCODE -eq 0)
 }catch{$output=$_.Exception.Message}
 $timer.Stop()
 $results+=[pscustomobject]@{Name=$name;Passed=$passed;Seconds=[Math]::Round($timer.Elapsed.TotalSeconds,2);Output=$output.Trim()}
 if($passed){Write-Output "PASS: $name"}else{Write-Output "FAIL: $name`n$output"}
}
if($Report){
 $Report=[IO.Path]::GetFullPath($Report);[void][IO.Directory]::CreateDirectory((Split-Path $Report -Parent))
 [IO.File]::WriteAllText($Report,(@{Runtime=$PSVersionTable.PSVersion.ToString();Desktop=[bool]$Desktop;Tests=$results}|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
}
if(@($results|Where-Object {-not $_.Passed}).Count){throw 'One or more CTC checks failed.'}
Write-Output "PASS: $($results.Count) CTC checks in PowerShell $($PSVersionTable.PSVersion)."
