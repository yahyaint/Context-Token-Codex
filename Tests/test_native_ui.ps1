# SPDX-License-Identifier: MIT
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Executable,[string]$Output=(Join-Path $env:TEMP ('ctc-ui-output-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$Output=[IO.Path]::GetFullPath($Output)
$homePath=Join-Path $Output 'home'
$dataPath=Join-Path $Output 'data'
$projectPath=Join-Path $homePath 'project'
foreach($folder in @((Join-Path $homePath 'sessions'),(Join-Path $projectPath '.codex'),$dataPath)){[void][IO.Directory]::CreateDirectory($folder)}
[IO.File]::WriteAllText((Join-Path $Output 'ctc-native-ui.fixture'),'CTC isolated UI fixture')
function Record($kind,$payload){@{type=$kind;timestamp=[DateTimeOffset]::Now.ToString('o');payload=$payload}|ConvertTo-Json -Depth 12 -Compress}
$code='await tools.exec_command({cmd:"rg private"}); await tools.apply_patch("private");'
$records=@(
 (Record 'session_meta' @{id='fixture-chat';cwd=$projectPath;originator='Codex Desktop'}),
 (Record 'turn_context' @{model='fixture-model'}),
 (Record 'event_msg' @{type='task_started';model_context_window=190000}),
 (Record 'event_msg' @{type='token_count';info=@{model_context_window=190000;last_token_usage=@{input_tokens=85000;cached_input_tokens=75000;output_tokens=1500;reasoning_output_tokens=500};total_token_usage=@{input_tokens=1000000;cached_input_tokens=900000;output_tokens=30000;reasoning_output_tokens=10000}}}),
 (Record 'response_item' @{type='custom_tool_call';name='functions.exec';call_id='1';input=$code}),
 (Record 'response_item' @{type='custom_tool_call_output';call_id='1';output=@(@{type='input_text';text='Script completed';},@{type='input_text';text='{"chunk_id":"abcdef12","wall_time_seconds":1.2,"exit_code":0}'})}),
 (Record 'response_item' @{type='function_call';name='exec_command';call_id='2';arguments='{"cmd":"dotnet test"}'}),
 (Record 'response_item' @{type='function_call_output';call_id='2';output='{"exit_code":1,"wall_time_seconds":2}'})
)
[IO.File]::WriteAllText((Join-Path $homePath 'sessions/fixture.jsonl'),($records -join [Environment]::NewLine)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $homePath 'session_index.jsonl'),'{"id":"fixture-chat","thread_name":"Fixture chat"}'+[Environment]::NewLine)
[IO.File]::WriteAllText((Join-Path $homePath 'models_cache.json'),'{"models":[{"slug":"fixture-model","context_window":200000,"max_context_window":600000,"effective_context_window_percent":95}]}')
[IO.File]::WriteAllText((Join-Path $homePath 'config.toml'),"model = 'fixture-model'"+[Environment]::NewLine)
[IO.File]::WriteAllText((Join-Path $projectPath '.codex/config.toml'),('model_context_window = 200000','model_auto_compact_token_limit = 180000' -join [Environment]::NewLine)+[Environment]::NewLine)
[IO.File]::WriteAllText((Join-Path $homePath 'quota-fixture.json'),'{"rateLimits":{"planType":"plus","primary":{"usedPercent":27,"windowDurationMins":300,"resetsAt":1900000000},"secondary":{"usedPercent":40,"windowDurationMins":10080,"resetsAt":1900000000}}}')
$arguments=@('--ui-test',('"'+$Output+'"'),'--home',('"'+$homePath+'"'),'--data',('"'+$dataPath+'"'))
$process=Start-Process -FilePath $Executable -ArgumentList $arguments -WindowStyle Hidden -PassThru
if(-not $process.WaitForExit(60000)){Stop-Process -Id $process.Id;throw 'Native UI fixture timed out.'}
$resultPath=Join-Path $Output 'checks.json'
if(-not (Test-Path -LiteralPath $resultPath)){throw 'Native UI fixture has no report.'}
$report=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json
if($report.Error){throw $report.Error}
$report|ConvertTo-Json -Depth 6
