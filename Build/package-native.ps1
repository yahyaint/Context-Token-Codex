# SPDX-License-Identifier: MIT
[CmdletBinding()]
param([string]$Runtime='win-x64',[string]$Version='')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(-not $Version){$Version=([xml](Get-Content -LiteralPath (Join-Path $root 'Directory.Build.props') -Raw)).Project.PropertyGroup.Version}
if($Version -notmatch '^\d+\.\d+\.\d+$'){throw 'The package version is incorrect.'}
$dist=Join-Path $root 'dist'
$source=Join-Path $dist ('native-'+$Runtime)
if(-not (Test-Path -LiteralPath (Join-Path $source 'ContextTokenCodex.exe'))){throw 'Build the compiled release first.'}
$stage=Join-Path $dist ('native-package-'+[guid]::NewGuid().ToString('N'))
$payload=Join-Path $stage 'ContextWidget'
[void][IO.Directory]::CreateDirectory($payload)
try{
 Get-ChildItem -LiteralPath $source | Copy-Item -Destination $payload -Recurse
 $name='Context-Token-Codex-Windows-v'+$Version+'.zip'
 $archive=Join-Path $dist $name
 Compress-Archive -LiteralPath $payload -DestinationPath $archive -Force
 $hash=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
 [IO.File]::WriteAllText($archive+'.sha256',($hash+'  '+$name+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
 [pscustomobject]@{Version=$Version;Runtime=$Runtime;Bytes=(Get-Item -LiteralPath $archive).Length;SHA256=$hash;File=$archive}|ConvertTo-Json
}finally{
 $fullStage=[IO.Path]::GetFullPath($stage)
 $fullDist=[IO.Path]::GetFullPath($dist)+[IO.Path]::DirectorySeparatorChar
 if($fullStage.StartsWith($fullDist,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $fullStage -Recurse -Force}
}
