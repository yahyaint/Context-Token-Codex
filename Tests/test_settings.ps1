$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'Monitor.Core.ps1'
if (-not (Test-Path -LiteralPath $scriptPath)) {
    $scriptPath = Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'Monitor.Core.ps1'
}
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ('Parse failed: ' + ($errors -join '; ')) }
foreach ($name in @('Find-VersionedDatabase', 'Get-ConfiguredSqliteHome',
        'Get-TopLevelNumericSetting', 'Set-TopLevelNumericSetting',
        'Get-TopLevelAutoCompactLimit', 'Set-TopLevelAutoCompactLimit',
        'Get-TopLevelContextWindow', 'Set-TopLevelContextWindow',
        'Get-TopLevelAutoCompactScope', 'ConvertTo-TokenLimit',
        'Get-ModelCatalogInfo', 'Get-ModelWindow',
        'Get-SavedWindowStatus')) {
    $function = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    if (-not $function) { throw "Missing function: $name" }
    . ([scriptblock]::Create($function.Extent.Text))
}
$folder = Join-Path $env:TEMP ('codex-context-settings-test-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $folder)
try {
    $path = Join-Path $folder 'config.toml'
    [System.IO.File]::WriteAllText($path, "model = 'gpt-5.6-sol'`n[projects.'x']`ntrust_level = 'trusted'`n")
    if (-not (Set-TopLevelAutoCompactLimit $path ([Nullable[long]]180000))) { throw 'Insert missed' }
    if ((Get-TopLevelAutoCompactLimit $path) -ne 180000) { throw 'Insert readback failed' }
    if (-not (Set-TopLevelAutoCompactLimit $path ([Nullable[long]]200000))) { throw 'Update missed' }
    if ((Get-TopLevelAutoCompactLimit $path) -ne 200000) { throw 'Update readback failed' }
    if (-not (Set-TopLevelContextWindow $path ([Nullable[long]]600000))) { throw 'Window insert missed' }
    if ((Get-TopLevelContextWindow $path) -ne 600000) { throw 'Window readback failed' }
    if (-not (Set-TopLevelAutoCompactLimit $path $null)) { throw 'Remove missed' }
    if ($null -ne (Get-TopLevelAutoCompactLimit $path)) { throw 'Remove readback failed' }
    if (-not (Set-TopLevelContextWindow $path $null)) { throw 'Window remove missed' }
    if ($null -ne (Get-TopLevelContextWindow $path)) { throw 'Window remove readback failed' }
    $content = [System.IO.File]::ReadAllText($path)
    if ($content -notmatch "trust_level = 'trusted'") { throw 'Existing table altered' }
    if (@(Get-ChildItem -LiteralPath $folder -Filter 'config.toml.bak-*').Count -ne 5) { throw 'Backup missing' }
    foreach ($case in @(
        @{ Input = '180000'; Expected = 180000 },
        @{ Input = '180,000'; Expected = 180000 },
        @{ Input = '180k'; Expected = 180000 },
        @{ Input = '70%'; Expected = 190400 }
    )) {
        $actual = ConvertTo-TokenLimit $case.Input 272000
        if ($actual.Limit -ne $case.Expected) { throw "Bad parse: $($case.Input)" }
    }
    if (-not (ConvertTo-TokenLimit 'default' 272000).IsDefault) { throw 'Default parse failed' }
    try { [void](ConvertTo-TokenLimit '70%' $null); throw 'Expected percent failure' }
    catch { if ($_.Exception.Message -eq 'Expected percent failure') { throw } }
    $script:modelCachePath = Join-Path $folder 'models_cache.json'
    [System.IO.File]::WriteAllText($script:modelCachePath,
        '{"models":[{"slug":"gpt-6-astra","context_window":272000,"max_context_window":872000,"effective_context_window_percent":95},{"slug":"model-without-percent","context_window":100000,"max_context_window":200000}]}')
    $astra = Get-ModelCatalogInfo 'gpt-6-astra'
    if ($astra.Window -ne 272000 -or $astra.Maximum -ne 872000) { throw 'Astra catalog read failed' }
    $withoutPercent = Get-ModelCatalogInfo 'model-without-percent'
    if ($null -ne $withoutPercent.EffectivePercent) { throw 'Unknown usable percentage was guessed' }
    $script:configPath = Join-Path $folder 'global.toml'
    $projectFolder = Join-Path $folder '.codex'
    [void](New-Item -ItemType Directory -Path $projectFolder)
    [System.IO.File]::WriteAllText((Join-Path $projectFolder 'config.toml'),
        "model_context_window = 150000`n")
    $status = Get-SavedWindowStatus ([pscustomobject]@{ Cwd = $folder;
        Model = 'model-without-percent'; ContextWindow = 100000 })
    if ($status.Requested -ne 150000 -or $null -ne $status.Expected) {
        throw 'Unknown effective window should remain unknown'
    }
    $scopePath = Join-Path $folder 'scope.toml'
    [System.IO.File]::WriteAllText($scopePath,
        "model_auto_compact_token_limit_scope = 'body_after_prefix'`n[other]`nvalue = 1`n")
    if ((Get-TopLevelAutoCompactScope $scopePath) -ne 'body_after_prefix') {
        throw 'Compaction scope read failed'
    }
    $sqlitePath = Join-Path $folder 'sqlite home.toml'
    [System.IO.File]::WriteAllText($sqlitePath,
        "sqlite_home = 'D:\Codex State'`n[other]`nvalue = 1`n")
    if ((Get-ConfiguredSqliteHome $sqlitePath) -ne 'D:\Codex State') {
        throw 'SQLite home config read failed'
    }
    $plainDb = Join-Path $folder 'state.sqlite'
    [System.IO.File]::WriteAllText($plainDb, '')
    if ((Find-VersionedDatabase $folder 'state') -ne $plainDb) {
        throw 'Unversioned SQLite database was missed'
    }
    Write-Host 'Settings edit tests passed.'
}
finally { Remove-Item -LiteralPath $folder -Recurse -Force }
