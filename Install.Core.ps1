# SPDX-License-Identifier: MIT
function Get-CtcLegacyInstallFiles {
 return @('ContextWidget.exe','Context.ico','Branding.ps1','Overlay.ps1','Monitor.Core.ps1','Monitor.Data.ps1','Restart.Core.ps1','Restart-Codex.ps1','Usage.Provider.ps1','Quota.Estimator.ps1','Quota.Rates.json','ACKNOWLEDGMENTS.md','THIRD_PARTY_NOTICES.md','INSTALL.md','RECOVERY.md','Watch-App.ps1','Theme.xaml','Open-Overlay.vbs','Open-Overlay.cmd','README.md','LICENSE','UPDATE-RECOVERY.md','COMPATIBILITY.md','SECURITY.md','CHANGELOG.md','docs/USER-GUIDE.md','docs/DATA.md','docs/images/context.png','docs/images/limits-native.png','docs/images/parked-native.png','docs/images/tokens-native.png','docs/images/tokens-breakdown-native.png','docs/images/queue-native.png','Build/ctc-logo.png')
}
function Invoke-ContextWidgetInstall {
 param([string]$Source,[string]$Destination,[bool]$AutoOpen=$true,[bool]$DesktopShortcut=$true,[string]$TestRoot='')
 $ErrorActionPreference='Stop'
 if (-not [IO.Path]::IsPathRooted($Destination)) { throw 'Enter a full path for the installation folder.' }
 $destinationPath=[IO.Path]::GetFullPath($Destination).TrimEnd('\')
 if ($destinationPath -eq [IO.Path]::GetPathRoot($destinationPath).TrimEnd('\')) { throw 'Select a subfolder for CTC. Do not select the drive root.' }
 $files=Get-CtcLegacyInstallFiles
 foreach ($file in $files) { if (-not (Test-Path -LiteralPath (Join-Path $Source $file) -PathType Leaf)) { throw "The installation file is missing: $file." } }
 if ($TestRoot) {
  $localRoot=[IO.Path]::GetFullPath($TestRoot).TrimEnd('\')+'\'
  if (-not $destinationPath.StartsWith($localRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Test install must remain inside its fixture.' }
  $preferences=Join-Path $TestRoot 'preferences\overlay.json'; $startup=Join-Path $TestRoot 'startup'; $desktop=Join-Path $TestRoot 'desktop'; $menu=Join-Path $TestRoot 'menu'
 } else {
  $preferences=Join-Path $env:LOCALAPPDATA 'CodexContextMonitor\overlay.json'
  $startup=[Environment]::GetFolderPath('Startup'); $desktop=[Environment]::GetFolderPath('DesktopDirectory'); $menu=Join-Path ([Environment]::GetFolderPath('Programs')) 'Context-Token Codex'
 }
 # Validate everything before overwriting an existing installation.
 $sameSource=([IO.Path]::GetFullPath($Source).TrimEnd('\') -eq $destinationPath)
 $backup=$null
 if (-not $sameSource -and (Test-Path -LiteralPath (Join-Path $destinationPath 'Overlay.ps1'))) {
  $backup=Join-Path $destinationPath ('Versions\before-6.8.9-'+[guid]::NewGuid().ToString('N').Substring(0,8))
  [void][IO.Directory]::CreateDirectory($backup)
  foreach ($file in $files) { $old=Join-Path $destinationPath $file; if (Test-Path -LiteralPath $old) { [void][IO.Directory]::CreateDirectory((Split-Path (Join-Path $backup $file) -Parent)); Copy-Item -LiteralPath $old -Destination (Join-Path $backup $file) } }
 }
 [void][IO.Directory]::CreateDirectory($destinationPath)
 if (-not $sameSource) { foreach ($file in $files) { [void][IO.Directory]::CreateDirectory((Split-Path (Join-Path $destinationPath $file) -Parent)); Copy-Item -LiteralPath (Join-Path $Source $file) -Destination (Join-Path $destinationPath $file) -Force } }
 $prefs=@{AutoOpen=$AutoOpen;Target='Either';Mode='Context';Compact=$true;StartParked=$true;Topmost=$true;Opacity=0.85;Width=460;Height=620;Left=-1;Top=-1;Corner='BottomRight'}
 . (Join-Path $Source 'Monitor.Data.ps1')
 $prefs=Read-WidgetPreferences $preferences $prefs
 $prefs.AutoOpen=$AutoOpen
 [void][IO.Directory]::CreateDirectory((Split-Path $preferences -Parent))
 [IO.File]::WriteAllText($preferences,($prefs|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
 $shell=New-Object -ComObject WScript.Shell
 try {
  foreach ($folder in @($menu,$startup,$desktop)) { [void][IO.Directory]::CreateDirectory($folder) }
  $links=@(@{Path=(Join-Path $menu 'Context-Token Codex.lnk');Args=''})
  if ($DesktopShortcut) { $links+=@{Path=(Join-Path $desktop 'Context-Token Codex.lnk');Args=''} }
  $startupLink=Join-Path $startup 'Context-Token Codex.lnk'
  if ($AutoOpen) { $links+=@{Path=$startupLink;Args='/watch'} } elseif (Test-Path -LiteralPath $startupLink) { Remove-Item -LiteralPath $startupLink }
  foreach ($entry in $links) {
   $link=$shell.CreateShortcut($entry.Path); $link.TargetPath=Join-Path $destinationPath 'ContextWidget.exe'; $link.Arguments=$entry.Args
   $link.WorkingDirectory=$destinationPath; $link.IconLocation=(Join-Path $destinationPath 'ContextWidget.exe')+',0'; $link.Description='Context-Token Codex - live context and token monitor'; $link.Save()
   Update-CtcShortcutIcon $entry.Path
  }
  # Remove only legacy shortcuts that point to this same installation.
  $legacy=@((Join-Path $startup 'Codex Context Overlay.lnk'),(Join-Path $desktop 'Context Widget.lnk'),(Join-Path $menu 'Context Widget.lnk'))
  if (-not $TestRoot) { $legacy+=Join-Path ([Environment]::GetFolderPath('Programs')) 'Context Widget/Context Widget.lnk' }
  foreach ($path in $legacy) {
   if (Test-Path -LiteralPath $path) {
    $oldLink=$shell.CreateShortcut($path)
    if ($oldLink.TargetPath -eq (Join-Path $destinationPath 'ContextWidget.exe')) { Remove-Item -LiteralPath $path }
   }
  }
 } finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
 $manifest=@{Version='6.8.9';Files=$files;AutoOpen=$AutoOpen;InstalledAt=[DateTimeOffset]::Now.ToString('o')}
 [IO.File]::WriteAllText((Join-Path $destinationPath 'installation.json'),($manifest|ConvertTo-Json -Depth 4))
 [pscustomobject]@{Destination=$destinationPath;Backup=$backup;Files=$files.Count;Preferences=$preferences;Bytes=($files|ForEach-Object {(Get-Item -LiteralPath (Join-Path $destinationPath $_)).Length}|Measure-Object -Sum).Sum}
}

function Install-ContextWidget {
 param([string]$Source,[string]$Destination,[bool]$AutoOpen=$true,[bool]$DesktopShortcut=$true,[string]$TestRoot='')
 $ErrorActionPreference='Stop'
 if (-not [IO.Path]::IsPathRooted($Destination)) {throw 'Enter a full path for the installation folder.'}
 $destinationPath=[IO.Path]::GetFullPath($Destination).TrimEnd('\')
 if ($destinationPath -eq [IO.Path]::GetPathRoot($destinationPath).TrimEnd('\')) {throw 'Select a subfolder for CTC.'}
 if ($TestRoot) {
  if (-not ($destinationPath+'\').StartsWith([IO.Path]::GetFullPath($TestRoot).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'Test install must remain inside its fixture.'}
  $preferences=Join-Path $TestRoot 'preferences/overlay.json';$startup=Join-Path $TestRoot 'startup';$desktop=Join-Path $TestRoot 'desktop';$menu=Join-Path $TestRoot 'menu'
 } else {
  $preferences=Join-Path $env:LOCALAPPDATA 'CodexContextMonitor/overlay.json';$startup=[Environment]::GetFolderPath('Startup');$desktop=[Environment]::GetFolderPath('DesktopDirectory');$menu=Join-Path ([Environment]::GetFolderPath('Programs')) 'Context-Token Codex'
 }
 # Snapshot every file the installation may replace/remove before touching the runtime.
 $targets=@($preferences,(Join-Path $destinationPath 'installation.json'))
 foreach($file in @(Get-CtcLegacyInstallFiles)) {$targets+=Join-Path $destinationPath $file}
 foreach($folder in @($startup,$desktop,$menu)) {foreach($name in @('Context-Token Codex.lnk','Context Widget.lnk','Codex Context Overlay.lnk')){$targets+=Join-Path $folder $name}}
 if(-not $TestRoot){$targets+=Join-Path ([Environment]::GetFolderPath('Programs')) 'Context Widget/Context Widget.lnk'}
 $original=@{}
 foreach($path in @($targets|Select-Object -Unique)) {$original[$path]=if([IO.File]::Exists($path)){[IO.File]::ReadAllBytes($path)}else{$null}}
 try {Invoke-ContextWidgetInstall -Source $Source -Destination $destinationPath -AutoOpen $AutoOpen -DesktopShortcut $DesktopShortcut -TestRoot $TestRoot}
 catch {
  $failure=$_; $rollbackErrors=@()
  foreach($path in $original.Keys) {
   try {
    if($null -ne $original[$path]){if(-not [IO.File]::Exists($path) -or [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) -cne [Convert]::ToBase64String([byte[]]$original[$path])){[IO.File]::WriteAllBytes($path,[byte[]]$original[$path])}}
    elseif([IO.File]::Exists($path)){[IO.File]::Delete($path)}
   } catch {$rollbackErrors+=$path}
  }
  if($rollbackErrors.Count){throw ('Installation failed. Restore these files: '+($rollbackErrors -join ', ')+'. Original error: '+$failure.Exception.Message)}
  throw $failure
 }
}
