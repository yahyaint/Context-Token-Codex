# SPDX-License-Identifier: MIT
param([string]$Archive)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if (-not $Archive) {$Archive=Join-Path $root 'dist/Context-Token-Codex-Windows-v6.5.0.zip'}
& (Join-Path $root 'Install-FromGitHub.ps1') -Archive $Archive -VerifyOnly
$bad=Join-Path $env:TEMP ('ctc-bad-hash-'+[guid]::NewGuid().ToString('N')+'.sha256')
[IO.File]::WriteAllText($bad,('0'*64)+'  '+[IO.Path]::GetFileName($Archive))
$rejected=$false
try { & (Join-Path $root 'Install-FromGitHub.ps1') -Archive $Archive -Checksum $bad -VerifyOnly } catch { $rejected=$_.Exception.Message -match 'SHA256 mismatch' }
if (-not $rejected) {throw 'Corrupt release was not rejected.'}
'PASS: local release verification and checksum rejection; remote publication not yet tested.'
