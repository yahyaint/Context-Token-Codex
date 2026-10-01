# SPDX-License-Identifier: MIT
param([string]$OutputDirectory='')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if (-not $OutputDirectory) { $OutputDirectory=Join-Path $root 'dist' }
& (Join-Path $PSScriptRoot 'build.ps1')
if ($LASTEXITCODE) { throw 'Build failed.' }
$files=@('ContextWidget.exe','Context.ico','Branding.ps1','Overlay.ps1','Monitor.Core.ps1','Monitor.Data.ps1','Restart.Core.ps1','Restart-Codex.ps1','Usage.Provider.ps1','Quota.Estimator.ps1','Quota.Rates.json','ACKNOWLEDGMENTS.md','THIRD_PARTY_NOTICES.md','UI-WRITING.md','INSTALL.md','RECOVERY.md','Watch-App.ps1','Theme.xaml','Open-Overlay.vbs','Open-Overlay.cmd','README.md','LICENSE','UPDATE-RECOVERY.md','COMPATIBILITY.md','SECURITY.md','CHANGELOG.md','docs/USER-GUIDE.md','docs/DATA.md','docs/images/context.png','docs/images/limits-native.png','docs/images/parked-native.png','Build/ctc-logo.png','Install-FromGitHub.ps1','Setup.exe','Install.ps1','Install.Core.ps1')
$stage=Join-Path $env:TEMP ('context-release-'+[guid]::NewGuid().ToString('N'))
$payload=Join-Path $stage 'ContextWidget'
[void][IO.Directory]::CreateDirectory($payload)
foreach ($name in $files) {
 $target=Join-Path $payload $name
 [void][IO.Directory]::CreateDirectory((Split-Path $target -Parent))
 Copy-Item -LiteralPath (Join-Path $root $name) -Destination $target
}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$zip=Join-Path $OutputDirectory 'Context-Token-Codex-Windows-v6.8.9.zip'
# Windows PowerShell 5.1 Compress-Archive can emit backslash paths. Use
# canonical ZIP separators on every runtime so strict installer checks agree.
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$zipStream=[IO.File]::Create($zip)
$archive=[IO.Compression.ZipArchive]::new($zipStream,[IO.Compression.ZipArchiveMode]::Create)
try {
    $prefix=[IO.Path]::GetFullPath($payload).TrimEnd('\')+'\'
    foreach($file in @(Get-ChildItem -LiteralPath $payload -File -Recurse)) {
        $relative=$file.FullName.Substring($prefix.Length).Replace('\','/')
        $entry=$archive.CreateEntry('ContextWidget/'+$relative,[IO.Compression.CompressionLevel]::Optimal)
        $inputStream=[IO.File]::OpenRead($file.FullName);$outputStream=$entry.Open()
        try {$inputStream.CopyTo($outputStream)} finally {$outputStream.Dispose();$inputStream.Dispose()}
    }
} finally {$archive.Dispose();$zipStream.Dispose()}
& (Join-Path $root 'Tests/test_public_distribution.ps1') -Archive $zip
$hash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText(($zip+'.sha256'),$hash+'  '+[IO.Path]::GetFileName($zip)+"`n",[Text.UTF8Encoding]::new($false))
Write-Output "Package: $zip"
Write-Output "SHA256: $hash"
