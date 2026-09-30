$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $env:TEMP ('ctc-activity-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'sessions'))
. (Join-Path $root 'Monitor.Core.ps1') -CodexHome $fixture
. (Join-Path $root 'Usage.Provider.ps1')
function Assert($value,$message){if(-not $value){throw $message}}
function Record($kind,$payload){@{timestamp=[DateTimeOffset]::Now.ToString('o');type=$kind;payload=$payload}|ConvertTo-Json -Depth 8 -Compress}
$path=Join-Path $fixture 'sessions/calls.jsonl'
$lines=@(
 (Record 'session_meta' @{id='chat';originator='Codex Desktop'}),
 (Record 'response_item' @{type='function_call';call_id='1';name='exec_command';arguments='private input'}),
 (Record 'response_item' @{type='function_call';call_id='1';name='exec_command'}),
 (Record 'response_item' @{type='function_call_output';call_id='1';output='private output'}),
 (Record 'response_item' @{type='custom_tool_call';call_id='2';name='apply_patch'}),
 (Record 'response_item' @{type='web_search_call';id='3'}),
 (Record 'response_item' @{type='function_call';name='missing id'})
)
[IO.File]::WriteAllText($path,($lines -join "`n")+"`n")
Update-Rollout (Get-Item $path)
$state=$script:rollouts[$path];$a=Get-RecordedToolActivity $state
Assert ($a.Ready -and $a.Calls -eq 3 -and $a.Partial -and $a.Tools.Count -eq 3) 'Tool calls double counted or outputs included.'
Assert ($state.ToolCounts.exec_command -eq 1 -and -not ($a|ConvertTo-Json -Depth 5).Contains('private')) 'Tool activity kept input or output text.'
[IO.File]::AppendAllText($path,(Record 'response_item' @{type='function_call';call_id='4';name='exec_command'})+"`n")
Update-Rollout (Get-Item $path)
Assert ((Get-RecordedToolActivity $state).Calls -eq 4) 'Live append missed a call.'
$state.NeedsBackfill=$true
Assert ($null -eq (Get-RecordedToolActivity $state).Calls) 'Incomplete backfill reported exact counts.'
Update-Rollout (Get-Item $path)
Assert ((Get-RecordedToolActivity $script:rollouts[$path]).Calls -eq 4) 'Backfill double counted calls.'
Assert ((Format-ShortTokenValue 1250000) -match '^1[.,]3M$' -and (Format-ShortTokenValue $null) -eq '--') 'Compact token formatting failed.'
foreach($name in @('functions.exec','exec_command','functions.write_stdin')){Assert (Test-ExecToolName $name) "Exec call was omitted: $name"}
foreach($name in @('apply_patch','execute_query','web.run','functions.execExtra')){Assert (-not (Test-ExecToolName $name)) "Other call was counted as exec: $name"}
'PASS: deduplicated calls, output exclusion, missing IDs, live append, unknown backfill, private data exclusion and token formatting.'
