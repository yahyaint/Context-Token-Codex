# SPDX-License-Identifier: MIT
function Install-ContextWidget {
 param([string]$Source,[string]$Destination,[bool]$AutoOpen=$true,[bool]$DesktopShortcut=$true,[string]$TestRoot='')
 $ErrorActionPreference='Stop'
 if (-not [IO.Path]::IsPathRooted($Destination)) { throw 'Choose an absolute installation folder.' }
 $destinationPath=[IO.Path]::GetFullPath($Destination).TrimEnd('\')
 if ($destinationPath -eq [IO.Path]::GetPathRoot($destinationPath).TrimEnd('\')) { throw 'Choose a dedicated subfolder, not a drive root.' }
 $files=@('ContextWidget.exe','Context.ico','Overlay.ps1','Monitor.Core.ps1','Monitor.Data.ps1','Usage.Provider.ps1','USAGE-METHODS.md','ACKNOWLEDGMENTS.md','THIRD_PARTY_NOTICES.md','UI-WRITING.md','INSTALL.md','RECOVERY.md','ERROR-AUDIT.md','Watch-App.ps1','Theme.xaml','Open-Overlay.vbs','Open-Overlay.cmd','README.md','LICENSE','METHODS.md','BRANDING.md')
 foreach ($file in $files) { if (-not (Test-Path -LiteralPath (Join-Path $Source $file) -PathType Leaf)) { throw "Installer payload missing $file" } }
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
  $backup=Join-Path $destinationPath ('Versions\before-6.3.6-'+[guid]::NewGuid().ToString('N').Substring(0,8))
  [void][IO.Directory]::CreateDirectory($backup)
  foreach ($file in $files) { $old=Join-Path $destinationPath $file; if (Test-Path -LiteralPath $old) { Copy-Item -LiteralPath $old -Destination $backup } }
 }
 [void][IO.Directory]::CreateDirectory($destinationPath)
 if (-not $sameSource) { foreach ($file in $files) { Copy-Item -LiteralPath (Join-Path $Source $file) -Destination (Join-Path $destinationPath $file) -Force } }
 $prefs=@{AutoOpen=$AutoOpen;Target='Either';Compact=$true;Topmost=$true;Opacity=0.92;Width=460;Height=620;Left=-1;Top=-1;Corner='BottomRight'}
 if (Test-Path -LiteralPath $preferences) {
  $prior=Get-Content -LiteralPath $preferences -Raw | ConvertFrom-Json
  foreach ($property in $prior.PSObject.Properties) { $prefs[$property.Name]=$property.Value }
  $prefs.AutoOpen=$AutoOpen
 }
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
   $link.WorkingDirectory=$destinationPath; $link.IconLocation=(Join-Path $destinationPath 'Context.ico')+',0'; $link.Description='Context-Token Codex - live context and token monitor'; $link.Save()
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
 $manifest=@{Version='6.3.6';Files=$files;AutoOpen=$AutoOpen;InstalledAt=[DateTimeOffset]::Now.ToString('o')}
 [IO.File]::WriteAllText((Join-Path $destinationPath 'installation.json'),($manifest|ConvertTo-Json -Depth 4))
 [pscustomobject]@{Destination=$destinationPath;Backup=$backup;Files=$files.Count;Preferences=$preferences;Bytes=($files|ForEach-Object {(Get-Item -LiteralPath (Join-Path $destinationPath $_)).Length}|Measure-Object -Sum).Sum}
}
