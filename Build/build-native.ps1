# SPDX-License-Identifier: MIT
[CmdletBinding()]
param([string]$Dotnet='dotnet',[string]$Runtime='win-x64',[switch]$SkipTests)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Join-Path $root 'NuGet.Config'
$app=Join-Path $root 'src/CTC.App/CTC.App.csproj'
$tests=Join-Path $root 'tests/CTC.Tests/CTC.Tests.csproj'
if(-not $SkipTests){
 & $Dotnet restore $tests --configfile $config
 if($LASTEXITCODE){throw 'Native test restore failed.'}
 & $Dotnet run --project $tests --configuration Release --no-restore
 if($LASTEXITCODE){throw 'Native checks failed.'}
}
$output=Join-Path $root ('dist/native-'+$Runtime)
if(Test-Path -LiteralPath $output){
 $absoluteOutput=[IO.Path]::GetFullPath($output)
 $distPrefix=[IO.Path]::GetFullPath((Join-Path $root 'dist'))+[IO.Path]::DirectorySeparatorChar
 if(-not $absoluteOutput.StartsWith($distPrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'The build output path is incorrect.'}
 Remove-Item -LiteralPath $absoluteOutput -Recurse -Force
}
& $Dotnet restore $app --runtime $Runtime --configfile $config
if($LASTEXITCODE){throw 'WPF restore failed.'}
& $Dotnet publish $app --configuration Release --runtime $Runtime --self-contained true --no-restore -p:PublishSingleFile=false -p:DebugType=None -p:DebugSymbols=false --output $output
if($LASTEXITCODE){throw 'WPF publish failed.'}
foreach($file in @('LICENSE','THIRD_PARTY_NOTICES.md','ACKNOWLEDGMENTS.md','UI-WRITING.md','UPDATE-RECOVERY.md','NATIVE-VERIFICATION.md','INSTALL.md','Quota.Rates.json')){
 Copy-Item -LiteralPath (Join-Path $root $file) -Destination $output
}
Copy-Item -LiteralPath (Join-Path $output 'ContextTokenCodex.exe') -Destination (Join-Path $output 'Setup.exe')
$runtimePack=Get-ChildItem -LiteralPath (Join-Path $root ('.packages/microsoft.netcore.app.runtime.'+$Runtime)) -Directory | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
Copy-Item -LiteralPath (Join-Path $runtimePack.FullName 'LICENSE.TXT') -Destination (Join-Path $output 'DOTNET-LICENSE.txt')
Copy-Item -LiteralPath (Join-Path $runtimePack.FullName 'THIRD-PARTY-NOTICES.TXT') -Destination (Join-Path $output 'DOTNET-THIRD-PARTY-NOTICES.txt')
$files=@{}
foreach($file in Get-ChildItem -LiteralPath $output -File -Recurse){
 $relative=$file.FullName.Substring($output.Length).TrimStart('\','/').Replace('\','/')
 if($relative -eq 'native-files.json'){continue}
 $files[$relative]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}
[IO.File]::WriteAllText((Join-Path $output 'native-files.json'),(@{Schema=1;Files=$files}|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
Write-Output "Compiled release: $output"
