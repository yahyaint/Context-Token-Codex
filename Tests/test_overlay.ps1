$ErrorActionPreference='Stop'
$folder=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $env:TEMP ('context-overlay-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'sessions'))
[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'idle-project'))
[IO.File]::WriteAllText((Join-Path $fixture '.codex-global-state.json'),(@{'local-projects'=@{idle=@{rootPaths=@((Join-Path $fixture 'idle-project'))}}}|ConvertTo-Json -Depth 5))
[IO.File]::WriteAllText((Join-Path $fixture '.overlay-test-fixture'),'test')
function Assert($condition,$message) { if (-not $condition) { throw $message } }
function Event($type,$payload) { @{ timestamp=[DateTimeOffset]::Now.ToString('o'); type=$type; payload=$payload } | ConvertTo-Json -Depth 10 -Compress }
$id='11111111-1111-4111-8111-111111111111'
$rollout=Join-Path $fixture 'sessions\test.jsonl'
$events=@(
    (Event 'session_meta' @{ id=$id; cwd=$fixture; source='vscode' }),
    (Event 'turn_context' @{ model='gpt-6-astra'; cwd=$fixture }),
    (Event 'event_msg' @{type='task_started'}),
    (Event 'response_item' @{type='function_call';name='functions.exec';call_id='exec-wrapper';arguments='text(await tools.exec_command({cmd:"rg --files"})); await tools.apply_patch("private");'}),
    (Event 'response_item' @{type='function_call';name='exec_command';call_id='exec-shell';arguments='{"cmd":"Get-Content private; rg private"}'}),
    (Event 'response_item' @{type='function_call';name='apply_patch';call_id='patch'}),
    (Event 'response_item' @{type='function_call_output';call_id='exec-wrapper';output="Script completed`nWall time: 2.5 seconds`nOutput:`nprivate"}),
    (Event 'response_item' @{type='function_call_output';call_id='exec-shell';output='{"exit_code":1,"wall_time_seconds":1.5,"output":"private"}'}),
    (Event 'event_msg' @{type='token_count'; info=@{ model_context_window=100000; last_token_usage=@{input_tokens=85000; cached_input_tokens=20000; output_tokens=800}; total_token_usage=@{total_tokens=85800} } })
)
[IO.File]::WriteAllText($rollout,($events -join "`n")+"`n")
[IO.File]::WriteAllText((Join-Path $fixture 'session_index.jsonl'),(@{id=$id;thread_name='Build a portable overlay'} | ConvertTo-Json -Compress)+"`n")
$previousSqlite=$env:CODEX_SQLITE_HOME
$env:CODEX_SQLITE_HOME=$null
try {
    . (Join-Path $folder 'Monitor.Core.ps1') -CodexHome $fixture
    . (Join-Path $folder 'Monitor.Data.ps1')
    $snapshot=Get-MonitorSnapshot
    Assert ($snapshot.Projects -contains (Join-Path $fixture 'idle-project')) 'Idle saved project missing from limits discovery.'
    Assert ($snapshot.Cards.Count -eq 1) 'Expected one active card.'
    Assert ($snapshot.Cards[0].Title -eq 'Build a portable overlay') 'Current task name missing.'
    Assert ($snapshot.Cards[0].Percent -eq 85) 'Context percentage incorrect.'
    [IO.File]::AppendAllText($rollout,(Event 'compacted' @{})+"`n")
    $snapshot=Get-MonitorSnapshot
    Assert ($snapshot.Cards[0].Compactions -eq 1) 'Compaction was not counted.'
    [IO.File]::AppendAllText($rollout,$events[-1]+"`n")
    $report=Join-Path $fixture 'ui-report.json'
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $folder 'Overlay.ps1') -CodexHome $fixture -PreferencesPath (Join-Path $fixture 'prefs.json') -TestSeconds 5 -TestSettings -TestReport $report
    Assert ($LASTEXITCODE -eq 0) "Overlay failed: $(Get-Content $report -Raw -ErrorAction SilentlyContinue)"
    $result=Get-Content $report -Raw | ConvertFrom-Json
    Assert ($result.Passed -and $result.SettingsPassed -and $result.CompactPassed -and $result.SnapPassed -and $result.WidgetSettingsPassed -and $result.Cards -eq 1) 'UI integration failed.'
    [IO.File]::AppendAllText($rollout,(Event 'event_msg' @{type='task_complete'})+"`n")
    $snapshot=Get-MonitorSnapshot
    Assert ($snapshot.Cards.Count -eq 0) 'Completed task card did not disappear.'
    Write-Output "PASS: snapshot, title, usage, compaction, completion, borderless WPF render, expand/collapse, corner snap, opacity and corner persistence, minimize, tray hide/restore, invalid input, settings save."
    Write-Output "Fixture/report/screenshot: $fixture"
} finally { $env:CODEX_SQLITE_HOME=$previousSqlite }
