# SPDX-License-Identifier: MIT
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$overlay=[IO.File]::ReadAllText((Join-Path $root 'Overlay.ps1'))
$count=0
foreach($pair in @(@('Main','xaml'),@('Parked','tabXaml'),@('Settings','settingsXaml'),@('ToolCalls','activityTemplate'))){
 $pattern='(?s)\[xml\]\$'+$pair[1]+'\s*=\s*@''\r?\n(.*?)\r?\n''@'
 $match=[regex]::Match($overlay,$pattern)
 if(-not $match.Success){throw ('Missing preserved layout: '+$pair[0])}
 $actual=[IO.File]::ReadAllText((Join-Path $root ('src/CTC.App/Layouts/'+$pair[0]+'.xaml')))
 if($actual.Replace([string][char]13,'') -cne $match.Groups[1].Value.Replace([string][char]13,'')){throw ('Native layout differs from preserved PowerShell layout: '+$pair[0])}
 $count++;Write-Output ('PASS Original '+$pair[0]+' layout')
}
$install=[IO.File]::ReadAllText((Join-Path $root 'Install.ps1'))
$expected=[regex]::Match($install,'(?s)\[xml\]\$xaml\s*=\s*@''\r?\n(.*?)\r?\n''@').Groups[1].Value
$expected=$expected.Replace('Text="Setup 6.8.9  /  Windows"','x:Name="SetupVersion" Text="Setup  /  Windows"').Replace('Windows supplies the required runtime.','The release includes the required runtime.')
$actual=[IO.File]::ReadAllText((Join-Path $root 'src/CTC.App/Layouts/Setup.xaml'))
if($actual.Replace([string][char]13,'') -cne $expected.Replace([string][char]13,'')){throw 'Native setup layout differs. Only runtime and version text can change.'}
$count++;Write-Output 'PASS Original setup layout'
$project=[IO.File]::ReadAllText((Join-Path $root 'src/CTC.App/CTC.App.csproj'))
foreach($resource in @('../../Theme.xaml','../../Context.ico')){
 if(-not $project.Contains('Include="'+$resource+'"')){throw ('Missing original resource: '+$resource)}
 $count++;Write-Output ('PASS Original resource '+$resource)
}
Write-Output ("PASS $count visual reference checks")
