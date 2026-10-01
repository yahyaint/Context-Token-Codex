# SPDX-License-Identifier: MIT
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Executable,[Parameter(Mandatory=$true)][string]$FixtureHome,[Parameter(Mandatory=$true)][string]$Output,[string]$ReplacementExecutable='')
$ErrorActionPreference='Stop'
$Output=[IO.Path]::GetFullPath($Output)
[void][IO.Directory]::CreateDirectory($Output)
$widget=$null;$watcher=$null
function Find-FixtureWidget{
 $matches=@(Get-CimInstance Win32_Process | Where-Object {$_.Name -eq 'ContextTokenCodex.exe' -and $_.ProcessId -ne $watcher.Id -and $_.CommandLine -like ('*'+$Output+'*')})
 if($matches.Count){return Get-Process -Id $matches[0].ProcessId -ErrorAction SilentlyContinue}
 return $null
}
try{
 $watcher=Start-Process -FilePath $Executable -ArgumentList @('--watch','--home',('"'+$FixtureHome+'"'),'--data',('"'+$Output+'"')) -WindowStyle Hidden -PassThru
 $deadline=[DateTimeOffset]::Now.AddSeconds(15)
 do{$widget=Find-FixtureWidget;if($widget){break};Start-Sleep -Milliseconds 250}while([DateTimeOffset]::Now -lt $deadline)
 if(-not $widget){throw 'The watcher did not open the fixture widget. Open Codex before this test.'}
 $first=$widget.Id
 Stop-Process -Id $widget.Id
 $deadline=[DateTimeOffset]::Now.AddSeconds(25)
 do{Start-Sleep -Milliseconds 500;$widget=Find-FixtureWidget}while((-not $widget -or $widget.Id -eq $first) -and [DateTimeOffset]::Now -lt $deadline)
 if(-not $widget -or $widget.Id -eq $first){throw 'The watcher did not recover the fixture widget.'}
 $result=@{OpenedWithUpdatedApp=$true;RecoveredAfterFailure=$true;Watcher=$watcher.Id;FixtureWidget=$widget.Id}
 if($ReplacementExecutable){
  $replacementPath=[IO.Path]::GetFullPath($ReplacementExecutable)
  $installFolder=Split-Path (Split-Path (Split-Path $replacementPath -Parent) -Parent) -Parent
  [IO.File]::WriteAllText((Join-Path $Output 'native-installation.json'),(@{Folder=$installFolder;Executable=$replacementPath;Version='7.0.0'}|ConvertTo-Json))
  $deadline=[DateTimeOffset]::Now.AddSeconds(15)
  $newWatcher=$null
  do{
   Start-Sleep -Milliseconds 250
   $newWatcher=@(Get-CimInstance Win32_Process|Where-Object {$_.ExecutablePath -eq $replacementPath -and $_.CommandLine -like '*--watch*' -and $_.CommandLine -like ('*'+$Output+'*')})|Select-Object -First 1
  }while(-not $newWatcher -and [DateTimeOffset]::Now -lt $deadline)
  if(-not $newWatcher){throw 'The installed update did not take over the watcher.'}
  if(-not $watcher.WaitForExit(5000)){throw 'The earlier watcher did not exit.'}
  $watcher=Get-Process -Id $newWatcher.ProcessId
  $result.UpdateTookOverWatcher=$true;$result.Watcher=$watcher.Id
 }
 [IO.File]::WriteAllText((Join-Path $Output 'watcher-checks.json'),($result|ConvertTo-Json))
 $result|ConvertTo-Json
}finally{
 if($watcher -and -not $watcher.HasExited){Stop-Process -Id $watcher.Id}
 if($widget -and -not $widget.HasExited){Stop-Process -Id $widget.Id}
}
