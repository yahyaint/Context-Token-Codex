$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $env:TEMP ('ctc-exec-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'sessions'))
. (Join-Path $root 'Monitor.Core.ps1') -CodexHome $fixture
. (Join-Path $root 'Usage.Provider.ps1')
function Assert($value,$message){if(-not $value){throw $message}}
function Record($payload,$second){@{timestamp=([DateTimeOffset]::UtcNow.AddSeconds($second).ToString('o'));type='response_item';payload=$payload}|ConvertTo-Json -Depth 8 -Compress}
$path=Join-Path $fixture 'sessions/exec.jsonl'
$code=@'
// tools.fake_comment()
text(await tools.exec_command({cmd:"rg private-file"}));
const sample="tools.fake_string()";
/* tools.fake_block() */
await tools.apply_patch("private patch");
'@
$lines=@(
 (@{type='session_meta';payload=@{id='exec'}}|ConvertTo-Json -Compress),
 (Record @{type='custom_tool_call';name='functions.exec';call_id='script';input=$code} 0),
 (Record @{type='custom_tool_call_output';call_id='script';output="Script completed`nWall time: 2.5 seconds`nOutput:`nprivate output"} 3),
 (Record @{type='custom_tool_call_output';call_id='script';output='duplicate'} 3),
 (Record @{type='function_call';name='exec_command';call_id='shell';arguments=(@{cmd='Get-Content private-file; rg private-pattern'}|ConvertTo-Json -Compress)} 4),
 (Record @{type='function_call_output';call_id='shell';output=(@{exit_code=1;wall_time_seconds=1.5;output='private stdout'}|ConvertTo-Json -Compress)} 6),
 (Record @{type='function_call';name='write_stdin';call_id='poll';arguments='{"session_id":42,"chars":""}'} 7),
 (Record @{type='function_call_output';call_id='poll';output="Final output:`nProcess exited with code 0`nWall time: 999 seconds"} 8),
 (Record @{type='function_call';name='exec_command';call_id='pending';arguments='bad json'} 9),
 (Record @{type='function_call_output';call_id='unmatched';output='{"exit_code":0}'} 10)
)
[IO.File]::WriteAllText($path,($lines -join "`n")+"`n")
Update-Rollout (Get-Item $path)
$state=$script:rollouts[$path];$a=Get-RecordedToolActivity $state;$e=$a.Exec
Assert ($a.Calls -eq 4 -and $e.Results -eq 3 -and $e.Success -eq 1 -and $e.Errors -eq 1 -and $e.UnknownStatus -eq 1) 'Call/result correlation or output deduplication failed.'
Assert ($e.Timed -eq 2 -and $e.Seconds -eq 4 -and $e.Spans -eq 3) 'Recorded time or stdout exclusion failed.'
Assert ($e.Kinds.Search -eq 1 -and $e.Kinds.'Read files' -eq 1 -and $e.Kinds.'Process checks' -eq 1 -and $e.Kinds.'Other commands' -eq 1) 'Command request categories failed.'
Assert ($e.ScriptTools.exec_command -eq 1 -and $e.ScriptTools.apply_patch -eq 1 -and $e.ScriptTools.Count -eq 2) 'Nested script references counted comments or strings.'
Assert (-not ($state.SeenCalls|ConvertTo-Json -Depth 8).Contains('private') -and -not ($e|ConvertTo-Json -Depth 8).Contains('private')) 'Exec details kept private arguments or output.'
$refs=Get-ScriptToolReferences 'tools[name](); const x=`tools.fake_template()`; tools.exec_command({cmd:"private"})'
Assert ($refs.Partial -and $refs.Tools.Count -eq 1 -and $refs.Tools[0] -eq 'exec_command') 'Dynamic calls and templates were not marked incomplete.'
$refs=Get-ScriptToolReferences ('x'*65537)
Assert ($refs.Partial -and $refs.Tools.Count -eq 0) 'Large script scan was not bounded.'
[IO.File]::AppendAllText($path,(Record @{type='function_call_output';call_id='pending';output='{"exit_code":0,"wall_time_seconds":0.5}'} 12)+"`n")
Update-Rollout (Get-Item $path)
Assert ($state.ExecActivity.Results -eq 4 -and $state.ExecActivity.Success -eq 2 -and $state.ExecActivity.Seconds -eq 4.5) 'Live result append failed.'
$state.NeedsBackfill=$true;Update-Rollout (Get-Item $path)
Assert ($script:rollouts[$path].ExecActivity.Results -eq 4) 'Backfill duplicated results.'
$shellResult=@{chunk_id='abcdef12';exit_code=2;wall_time_seconds=1.2;output='private shell output'}|ConvertTo-Json -Compress
$blocks=@(@{type='input_text';text='Script completed'},@{type='input_text';text=$shellResult},@{type='input_text';text=$shellResult})
[IO.File]::AppendAllText($path,(Record @{type='function_call';name='functions.exec';call_id='blocks';arguments='await tools.exec_command({cmd:"rg private"})'} 14)+"`n"+(Record @{type='function_call_output';call_id='blocks';output=$blocks} 15)+"`n")
Update-Rollout (Get-Item $path)
$e=(Get-RecordedToolActivity $script:rollouts[$path]).Exec
Assert ($e.Success -eq 3 -and $e.Shell.Results -eq 1 -and $e.Shell.Errors -eq 1 -and $e.Shell.Seconds -eq 1.2) 'Native text-block results or nested shell metadata failed.'
Assert ($e.ScriptKinds.Search -eq 2 -and -not $e.ContainsKey('SeenShellResults')) 'Script command references or snapshot privacy failed.'
$e.ScriptTools.exec_command=999
Assert ($script:rollouts[$path].ExecActivity.ScriptTools.exec_command -ne 999) 'UI snapshot shared a mutable collector table.'
$huge=@(@{type='input_text';text='Script completed'},@{type='input_text';text=('private '*20000)})
[IO.File]::AppendAllText($path,(Record @{type='function_call';name='functions.exec';call_id='large';arguments='text("private")'} 16)+"`n"+(Record @{type='function_call_output';call_id='large';output=$huge} 17)+"`n")
Update-Rollout (Get-Item $path)
$e=(Get-RecordedToolActivity $script:rollouts[$path]).Exec
Assert ($e.Success -eq 4 -and $e.Shell.Partial -and -not ($e|ConvertTo-Json -Depth 8).Contains('private')) 'Large output header handling or privacy failed.'
'PASS: exec requests, categories, bounded script references, results, errors, unknown status, time, privacy, live append and backfill.'
