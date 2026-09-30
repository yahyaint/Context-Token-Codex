# SPDX-License-Identifier: MIT
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Monitor.Core.ps1'),[ref]$null,[ref]$null)
foreach ($name in @('Get-TomlStatements','Get-TomlRootSettings','Get-TopLevelNumericSetting','Get-TopLevelContextWindow','Get-TopLevelAutoCompactLimit','Get-TopLevelModel','Get-ModelCatalogInfo','ConvertTo-TokenLimit','Get-LimitEditorBaseline','ConvertTo-ContextDraft','Get-ScaledContextDraft','Get-ContextConfigPaths')) {
    $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
    . ([scriptblock]::Create($fn.Extent.Text))
}
function Assert($condition,$message) { if (-not $condition) { throw $message } }
function Reject($operation,$message) { $rejected=$false; try { & $operation } catch { $rejected=$true }; Assert $rejected $message }
$fixture=Join-Path $env:TEMP ('ctc-context-editor-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$script:configPath=Join-Path $fixture 'global.toml'
$script:modelCachePath=Join-Path $fixture 'models_cache.json'
$project=Join-Path $fixture 'project.toml'
[IO.File]::WriteAllText($script:modelCachePath,'{"models":[{"slug":"fixture-model","context_window":200000,"max_context_window":600000}]}')
[IO.File]::WriteAllText($script:configPath,"model = 'fixture-model'`nmodel_context_window = 250000`n")
$card=[pscustomobject]@{Model='fixture-model';Window=190000}
$state=Get-LimitEditorBaseline $project $card
Assert ($state.Base -eq 250000 -and $state.Source -eq 'global fallback' -and $state.Live -eq 190000 -and $state.Maximum -eq 600000) 'Inherited raw settings must be separate from live usable capacity.'
[IO.File]::WriteAllText($project,"model_context_window = 300000`nmodel_auto_compact_token_limit = 270000`n")
$state=Get-LimitEditorBaseline $project $card
Assert ($state.Base -eq 300000 -and $state.SavedCompact -eq 270000) 'Project override must win.'
[IO.File]::WriteAllText($script:configPath,"model = 'fixture-model'`n")
Assert ((Get-LimitEditorBaseline (Join-Path $fixture 'idle.toml') $null).Base -eq 200000) 'Idle project should use catalog default when available.'
$draft=Get-ScaledContextDraft 200000 2 '200k' '180k'
Assert ($draft.Window -eq '400000' -and $draft.Compact -eq '360000') 'Numeric compaction ratio must scale with window.'
$draft=Get-ScaledContextDraft 200000 3 $draft.Window $draft.Compact
Assert ($draft.Window -eq '600000' -and $draft.Compact -eq '540000') '3x must anchor to base and preserve ratio after 2x.'
$draft=Get-ScaledContextDraft 200000 2 'default' '95%'
Assert ($draft.Compact -eq '95%') 'Exact percentage must stay intact.'
Assert ((Get-ScaledContextDraft 200000 2 '200k' 'default').Compact -eq 'default') 'Default compaction must not become a guessed threshold.'
Assert ((ConvertTo-ContextDraft '200k' '90%').Compact -eq 180000) 'Percentage draft parse failed.'
Reject { ConvertTo-ContextDraft '200k' '201k' } 'Threshold above window accepted.'
Reject { ConvertTo-ContextDraft 'default' '90%' } 'Percentage without denominator accepted.'
Reject { Get-ScaledContextDraft ([long]::MaxValue) 3 '200k' 'default' } 'Overflow accepted.'
Reject { Get-ScaledContextDraft $null 2 'default' 'default' } 'Unknown base invented.'
$script:configPath=Join-Path $fixture 'missing.toml'
$script:modelCachePath=Join-Path $fixture 'missing-cache.json'
Assert ((Get-LimitEditorBaseline (Join-Path $fixture 'missing-project.toml') ([pscustomobject]@{Model='future-model';Window=123456})).Source -eq 'live usable window') 'Unknown model should use labeled live fallback.'
Assert ($null -eq (Get-LimitEditorBaseline (Join-Path $fixture 'missing-project.toml') $null).Base) 'Idle unknown model must stay unknown.'
'PASS: editor scope precedence, unknown-model fallbacks, anchored multipliers, preserved compaction ratio, percentages, invalid limits and overflow.'
