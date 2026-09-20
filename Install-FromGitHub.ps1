# SPDX-License-Identifier: MIT
[CmdletBinding()]
param(
 [string]$Repository='yahyaint/Context-Token-Codex',
 [string]$Version='latest',
 [string]$Archive='',
 [string]$Checksum='',
 [switch]$VerifyOnly
)
$ErrorActionPreference='Stop'
if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Use an owner/repository name.' }
$stage=Join-Path $env:TEMP ('ctc-install-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($stage)
if (-not $Archive) {
 [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
 $endpoint=if ($Version -eq 'latest') {'latest'} else {'tags/'+[Uri]::EscapeDataString($Version)}
 $release=Invoke-RestMethod "https://api.github.com/repos/$Repository/releases/$endpoint" -Headers @{'User-Agent'='Context-Token-Codex-Installer'}
 if ($release.tag_name -notmatch '^v\d+\.\d+\.\d+$') { throw 'Release tag format is not supported.' }
 $name='Context-Token-Codex-Windows-'+$release.tag_name+'.zip'
 foreach ($file in @($name,($name+'.sha256'))) {
  $asset=@($release.assets|Where-Object name -eq $file)
  if ($asset.Count -ne 1) { throw "Release is missing $file." }
  $expected="https://github.com/$Repository/releases/download/$($release.tag_name)/$file"
  if ($asset[0].browser_download_url -cne $expected) { throw 'Unexpected release asset URL.' }
  Invoke-WebRequest $expected -OutFile (Join-Path $stage $file) -UseBasicParsing
 }
 $Archive=Join-Path $stage $name; $Checksum=$Archive+'.sha256'
}
if (-not $Checksum) { $Checksum=$Archive+'.sha256' }
$line=[IO.File]::ReadAllText([IO.Path]::GetFullPath($Checksum)).Trim()
if ($line -notmatch '^([a-fA-F0-9]{64})\s+(.+)$' -or $Matches[2] -ne [IO.Path]::GetFileName($Archive)) { throw 'Invalid SHA256 file.' }
$expectedHash=$Matches[1]
if ((Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash -ne $expectedHash) { throw 'SHA256 mismatch. Installation stopped.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($Archive))
try {
 $bytes=0L
 foreach ($entry in $zip.Entries) {
  if ($entry.FullName -notmatch '^ContextWidget/' -or $entry.FullName -match '(^|[/\\])\.\.([/\\]|$)|\\|:') { throw 'Unexpected archive path.' }
  $bytes+=$entry.Length
 }
 if ($bytes -gt 50MB) { throw 'Release is larger than the allowed payload.' }
} finally { $zip.Dispose() }
Expand-Archive -LiteralPath $Archive -DestinationPath $stage
$payload=Join-Path $stage 'ContextWidget'
foreach ($file in @('Setup.exe','Install.Core.ps1','LICENSE','THIRD_PARTY_NOTICES.md')) {
 if (-not (Test-Path -LiteralPath (Join-Path $payload $file))) { throw "Missing release file: $file" }
}
if ($VerifyOnly) { Write-Output "Verified: $payload"; return }
Start-Process -FilePath (Join-Path $payload 'Setup.exe')
Write-Output 'Verified. The installation wizard is open.'
