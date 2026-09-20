$ErrorActionPreference='Stop'
$source=Split-Path $PSScriptRoot -Parent
. (Join-Path $source 'Install.Core.ps1')
$fixture=Join-Path $env:TEMP ('context-install-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
function Assert($condition,$message) { if (-not $condition) { throw $message } }
& (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $source 'Install.ps1') -TestRoot $fixture
Assert ($LASTEXITCODE -eq 0) 'Wizard process failed.'
$wizard=Get-Content (Join-Path $fixture 'wizard-result.json') -Raw | ConvertFrom-Json
Assert ($wizard.Page -eq 2 -and -not $wizard.Error -and $wizard.AutoOpen) 'Wizard did not finish with startup default enabled.'
$destination=Join-Path $fixture 'installed'
$shell=New-Object -ComObject WScript.Shell
try {
 $link=$shell.CreateShortcut((Join-Path $fixture 'startup\Context-Token Codex.lnk'))
 Assert ($link.TargetPath -eq (Join-Path $destination 'ContextWidget.exe') -and $link.Arguments -eq '/watch') 'Startup shortcut is incorrect.'
 Assert ($link.IconLocation -like '*Context.ico*') 'Shortcut does not use custom icon.'
 $legacy=$shell.CreateShortcut((Join-Path $fixture 'startup\Codex Context Overlay.lnk')); $legacy.TargetPath=Join-Path $destination 'ContextWidget.exe'; $legacy.Save()
 $unrelated=$shell.CreateShortcut((Join-Path $fixture 'desktop\Context Widget.lnk')); $unrelated.TargetPath=Join-Path $env:WINDIR 'notepad.exe'; $unrelated.Save()
} finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
$prefsPath=Join-Path $fixture 'preferences\overlay.json'
$prefs=Get-Content $prefsPath -Raw | ConvertFrom-Json; $prefs.Opacity=0.61
$prefs | ConvertTo-Json | Set-Content $prefsPath
$upgrade=Install-ContextWidget -Source $source -Destination $destination -AutoOpen $false -TestRoot $fixture
Assert (Test-Path (Join-Path $upgrade.Backup 'Overlay.ps1')) 'Upgrade did not preserve previous version.'
$prefs=Get-Content $prefsPath -Raw | ConvertFrom-Json
Assert ($prefs.Opacity -eq 0.61 -and -not $prefs.AutoOpen) 'Upgrade lost preferences or ignored startup choice.'
Assert (-not (Test-Path (Join-Path $fixture 'startup\Context-Token Codex.lnk'))) 'Startup removal failed.'
Assert (-not (Test-Path (Join-Path $fixture 'startup\Codex Context Overlay.lnk'))) 'Owned legacy shortcut was not migrated.'
Assert (Test-Path (Join-Path $fixture 'desktop\Context Widget.lnk')) 'Unrelated shortcut was removed.'
$rejected=$false
try { Install-ContextWidget -Source $source -Destination 'C:\' -TestRoot $fixture } catch { $rejected=$true }
Assert $rejected 'Drive-root install was not rejected.'
$colors=@(Get-Content (Join-Path $source 'Theme.xaml') -Raw | ForEach-Object { [regex]::Matches($_,'#[0-9A-Fa-f]{6}') } | ForEach-Object Value | Sort-Object -Unique)
Assert (($colors -join ',') -eq '#0D1B2A,#1B263B,#415A77,#778DA9,#E0E1DD') 'Theme does not match the selected five-color palette.'
'PASS: actual wizard, startup default, installed files, custom-icon shortcuts, upgrade backup, preference retention, disable startup, path validation, five-color theme.'
"Test fixture: $fixture"
