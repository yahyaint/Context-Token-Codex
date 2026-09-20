# SPDX-License-Identifier: MIT
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $env:TEMP ('context compatibility '+[char]0x03A9+' '+[guid]::NewGuid().ToString('N'))
. (Join-Path $root 'Monitor.Core.ps1') -CodexHome $fixture -SqliteHome $fixture
. (Join-Path $root 'Usage.Provider.ps1')
function Assert($condition,$message) { if (-not $condition) { throw $message } }
Assert (@(Get-RolloutFiles).Count -eq 0) 'Missing profile failed.'
[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'sessions'))
$path=Join-Path $fixture 'sessions/task.jsonl'
[IO.File]::WriteAllText($path,'')
$state=New-RolloutState (Get-Item $path)
Read-RolloutLine $state '{"type":"event_msg","payload":{"model_context_window":100000,"type":"task_started"}}'
Assert ($state.Active -and $state.ContextWindow -eq 100000) 'Reordered payload fields failed.'
Read-RolloutLine $state '{"type":"event_msg","payload":{"info":{"last_token_usage":{"input_tokens":"future","output_tokens":-1},"total_token_usage":{"total_tokens":"bad"}},"type":"token_count"}}'
Assert ($null -eq $state.ContextInput -and $null -eq $state.ThreadTokens) 'Invalid tokens became zero or crashed.'
Read-RolloutLine $state '{broken'
Read-RolloutLine $state '{"type":"future_event","payload":{}}'
$script:sqlite=$null
Assert (@(Get-RolloutFiles).Count -eq 1) 'No-SQLite folder discovery failed.'
$sqliteCommand=Get-Command sqlite3.exe -ErrorAction SilentlyContinue
if ($sqliteCommand) {
 $script:sqlite=$sqliteCommand.Source
 $dbFolder=Join-Path $env:TEMP ('context-sqlite-'+[guid]::NewGuid().ToString('N'))
 [void][IO.Directory]::CreateDirectory($dbFolder)
 $script:stateDatabase=Join-Path $dbFolder 'state_999.sqlite'
 & $script:sqlite $script:stateDatabase 'CREATE TABLE future_threads (id TEXT);'
 $script:lastReconcile=[DateTimeOffset]::MinValue
 Assert (@(Get-RolloutFiles).Count -eq 1) 'Changed SQLite schema blocked folder fallback.'
 $script:LogDatabase=$script:stateDatabase
 Update-CompactionLog
 Assert ($script:logStatus -match 'completion only') 'Incompatible logs falsely claim live compaction.'
 Assert ((Find-VersionedDatabase $dbFolder 'state') -eq $script:stateDatabase) 'Future database version not discovered.'
 'PASS: real SQLite incompatible schema fallback and future database version discovery.'
}
[IO.File]::WriteAllText($path,'{"type":"event_msg","payload":{"type":"task_')
Update-Rollout (Get-Item $path)
Assert (-not $script:rollouts[$path].Active) 'Partial event processed early.'
[IO.File]::AppendAllText($path,"started""}}`n")
Update-Rollout (Get-Item $path)
Assert ($script:rollouts[$path].Active) 'Partial event never completed.'
[IO.File]::WriteAllText($path,"{}`n")
Update-Rollout (Get-Item $path)
Assert (-not $script:rollouts[$path].Active) 'Truncated rollout retained old state.'
[IO.File]::WriteAllText($script:sessionIndexPath,'{"id":"one","thread_name":"Before"}')
Update-IndexTitles
[IO.File]::WriteAllText($script:sessionIndexPath,'{"id":"one","thread_name":"After"}')
$script:lastIndexWrite=[DateTime]::MinValue
Update-IndexTitles
Assert ($script:titleCache.one.UiName -eq 'After') 'Index rename remained stale.'
foreach ($culture in @('en-US','de-DE')) {
 [Threading.Thread]::CurrentThread.CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo($culture)
 $q=ConvertTo-QuotaSnapshot ('{"rateLimits":{"primary":{"usedPercent":12.5},"secondary":{"usedPercent":"NaN"}}}'|ConvertFrom-Json) 'fixture' ([DateTimeOffset]::Now)
 Assert ($q.Windows.Count -eq 1 -and $q.Windows[0].Remaining -eq 87.5) "Quota parsing failed under $culture."
}
'PASS: missing profile, Unicode/spaced paths, reordered/unknown/malformed events, missing SQLite, partial append, truncation, task rename, en-US/de-DE quotas.'
