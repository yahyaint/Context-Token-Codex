$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
function Assert($condition,$message) { if (-not $condition) { throw $message } }
foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter *.ps1 -Recurse | Where-Object FullName -NotMatch '\\dist\\')) {
 $errors=$null; [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$null,[ref]$errors)
 Assert ($errors.Count -eq 0) "PowerShell syntax error in $($file.Name)"
}
# Windows PowerShell 5.1 treats BOM-less source as ANSI, not UTF-8.
foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter *.ps1)) {
 $bytes=[IO.File]::ReadAllBytes($file.FullName)
 $hasBom=$bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
 $hasNonAscii=@($bytes | Where-Object {$_ -gt 127}).Count -gt 0
 Assert (-not $hasNonAscii -or $hasBom) "PowerShell 5.1 requires a UTF-8 BOM for non-ASCII source: $($file.Name)"
}
Assert ((Get-Content (Join-Path $root 'LICENSE') -Raw) -match 'MIT License[\s\S]*Permission is hereby granted') 'MIT license missing.'
foreach ($name in @('ContextWidget.exe','Setup.exe')) { Assert (Test-Path (Join-Path $root $name)) "Build first: $name missing." }
. (Join-Path $root 'Install.Core.ps1')
$fixture=Join-Path $env:TEMP ('context-repository-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$result=Install-ContextWidget -Source $root -Destination (Join-Path $fixture 'installed') -TestRoot $fixture
Assert ($result.Files -eq 24) 'Unexpected runtime manifest.'
foreach ($name in @('ACKNOWLEDGMENTS.md','THIRD_PARTY_NOTICES.md','UI-WRITING.md')) {
 Assert (Test-Path (Join-Path $fixture "installed/$name")) "Installed distribution missing $name."
}
$credits=Get-Content (Join-Path $root 'THIRD_PARTY_NOTICES.md') -Raw
foreach ($author in @('ryoppippi','Peter Steinberger','Codex Monitor HUD Contributors','Craig Constable')) {
 Assert ($credits.Contains($author)) "Missing upstream copyright: $author"
}
Assert (Test-Path (Join-Path $fixture 'startup\Context-Token Codex.lnk')) 'Default startup shortcut missing.'
Assert ((Get-Content $result.Preferences -Raw | ConvertFrom-Json).AutoOpen) 'Startup default should be enabled.'
'PASS: source syntax, MIT license, build outputs, isolated runtime installation and startup default.'
