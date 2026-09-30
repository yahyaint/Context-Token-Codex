# SPDX-License-Identifier: MIT
param([string]$OutputDirectory='')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if (-not $OutputDirectory) { $OutputDirectory=Join-Path $root 'dist' }
& (Join-Path $PSScriptRoot 'build.ps1')
if ($LASTEXITCODE) { throw 'Build failed.' }
$files=@('WORK-QUEUE.md','ARCHITECTURE-REVIEW.md','AGENTS.md','Install-FromGitHub.ps1','Setup.exe','ContextWidget.exe','Context.ico','Install.ps1','Install.Core.ps1','Overlay.ps1','Monitor.Core.ps1','Monitor.Data.ps1','Restart.Core.ps1','Restart-Codex.ps1','Usage.Provider.ps1','Quota.Estimator.ps1','Quota.Rates.json','USAGE-METHODS.md','ACKNOWLEDGMENTS.md','THIRD_PARTY_NOTICES.md','UI-WRITING.md','INSTALL.md','RECOVERY.md','ERROR-AUDIT.md','Watch-App.ps1','Theme.xaml','Open-Overlay.vbs','Open-Overlay.cmd','README.md','LICENSE','METHODS.md','BRANDING.md','AUDIT.md','QUOTA-RESEARCH.md','CHANGELOG.md')
$stage=Join-Path $env:TEMP ('context-release-'+[guid]::NewGuid().ToString('N'))
$payload=Join-Path $stage 'ContextWidget'
[void][IO.Directory]::CreateDirectory($payload)
foreach ($name in $files) { Copy-Item -LiteralPath (Join-Path $root $name) -Destination $payload }
# Include build source to keep the binary package auditable and reproducible.
Copy-Item -LiteralPath (Join-Path $root 'Build') -Destination $payload -Recurse
Copy-Item -LiteralPath (Join-Path $root 'Tests') -Destination $payload -Recurse
Copy-Item -LiteralPath (Join-Path $root 'CONTRIBUTING.md') -Destination $payload
Copy-Item -LiteralPath (Join-Path $root 'COMPATIBILITY.md') -Destination $payload
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$zip=Join-Path $OutputDirectory 'Context-Token-Codex-Windows-v6.8.0.zip'
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
$hash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText(($zip+'.sha256'),$hash+'  '+[IO.Path]::GetFileName($zip)+"`n",[Text.UTF8Encoding]::new($false))
Write-Output "Package: $zip"
Write-Output "SHA256: $hash"
