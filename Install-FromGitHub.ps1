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
$ProgressPreference='SilentlyContinue'
if ($Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Use an owner/repository name.' }
$stage=Join-Path $env:TEMP ('ctc-install-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($stage)
if (-not $Archive) {
 [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
 $endpoint=if ($Version -eq 'latest') {'latest'} else {'tags/'+[Uri]::EscapeDataString($Version)}
 $release=Invoke-RestMethod "https://api.github.com/repos/$Repository/releases/$endpoint" -Headers @{'User-Agent'='Context-Token-Codex-Installer'} -TimeoutSec 30
 if ($release.tag_name -notmatch '^v\d+\.\d+\.\d+$') { throw 'CTC cannot use this release tag format.' }
 $name='Context-Token-Codex-Windows-'+$release.tag_name+'.zip'
 foreach ($file in @($name,($name+'.sha256'))) {
  $asset=@($release.assets|Where-Object name -eq $file)
  if ($asset.Count -ne 1) { throw "Release is missing $file." }
  $expected="https://github.com/$Repository/releases/download/$($release.tag_name)/$file"
  if ($asset[0].browser_download_url -cne $expected) { throw 'The release file URL is incorrect. Installation stopped.' }
  Invoke-WebRequest $expected -OutFile (Join-Path $stage $file) -UseBasicParsing -TimeoutSec 180
 }
 $Archive=Join-Path $stage $name; $Checksum=$Archive+'.sha256'
}
if (-not $Checksum) { $Checksum=$Archive+'.sha256' }
$line=[IO.File]::ReadAllText([IO.Path]::GetFullPath($Checksum)).Trim()
if ($line -notmatch '^([a-fA-F0-9]{64})\s+(.+)$' -or $Matches[2] -ne [IO.Path]::GetFileName($Archive)) { throw 'The SHA256 file is incorrect. Installation stopped.' }
$expectedHash=$Matches[1]
if ((Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash -ne $expectedHash) { throw 'SHA256 mismatch. Installation stopped.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($Archive))
try {
 $bytes=0L
 $paths=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
 if($zip.Entries.Count -gt 2048){throw 'The ZIP has too many files. Installation stopped.'}
 foreach ($entry in $zip.Entries) {
  if ($entry.FullName -notmatch '^ContextWidget/' -or $entry.FullName -match '(^|[/\\])\.\.([/\\]|$)|\\|:') { throw 'The ZIP contains an incorrect path. Installation stopped.' }
  if(-not $paths.Add($entry.FullName)){throw 'The ZIP contains a repeated path. Installation stopped.'}
  $bytes+=$entry.Length
 }
 if ($bytes -gt 256MB) { throw 'The release is larger than 256 MB. Installation stopped.' }
} finally { $zip.Dispose() }
[IO.Compression.ZipFile]::ExtractToDirectory([IO.Path]::GetFullPath($Archive),$stage)
$payload=Join-Path $stage 'ContextWidget'
$required=@('Setup.exe','LICENSE','THIRD_PARTY_NOTICES.md')
if(Test-Path -LiteralPath (Join-Path $payload 'ContextTokenCodex.exe')){$required+=@('ContextTokenCodex.dll','CTC.Core.dll','hostfxr.dll','coreclr.dll','PresentationFramework.dll','Quota.Rates.json','native-files.json','DOTNET-LICENSE.txt','DOTNET-THIRD-PARTY-NOTICES.txt')}
else{$required+='Install.Core.ps1'}
foreach ($file in $required) {
 if (-not (Test-Path -LiteralPath (Join-Path $payload $file))) { throw "Missing release file: $file" }
}
if ($VerifyOnly) { Write-Output "Verified: $payload"; return }
Start-Process -FilePath (Join-Path $payload 'Setup.exe')
Write-Output 'CTC checked the release files. The setup window is open.'
