# SPDX-License-Identifier: MIT
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $env:TEMP ('ctc-startup-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'sessions'))
. (Join-Path $root 'Monitor.Core.ps1') -CodexHome $fixture -SqliteHome $fixture
function Assert($value,$message) {if(-not $value){throw $message}}
$base=[DateTimeOffset]::Now.AddMinutes(-5)
function Record($type,$payload,$second) { @{timestamp=$base.AddSeconds($second).ToString('o');type=$type;payload=$payload}|ConvertTo-Json -Depth 8 -Compress }
$path=Join-Path $fixture 'sessions/large.jsonl'
$lines=New-Object 'Collections.Generic.List[string]'
$lines.Add((Record 'session_meta' @{id='startup-fixture';cwd=$fixture} 0))
$reordered=[ordered]@{payload=@{id='startup-fixture';cwd=$fixture;extra=('x'*2000)};type='session_meta';timestamp=$base.ToString('o')}
$lines.Add(($reordered|ConvertTo-Json -Depth 8 -Compress))
$lines.Add((Record 'turn_context' @{model='gpt-6-astra'} 1))
$lines.Add((Record 'event_msg' @{type='task_started';model_context_window=200000} 2))
$lines.Add((Record 'event_msg' @{type='token_count';info=@{model_context_window=200000;last_token_usage=@{input_tokens=70000;cached_input_tokens=50000;output_tokens=10};total_token_usage=@{total_tokens=70010;input_tokens=70000;cached_input_tokens=50000;output_tokens=10}}} 3))
$padding='fixture progress '+('x'*1000)
for($i=0;$i -lt 1000;$i++){$lines.Add((Record 'event_msg' @{type='agent_message';message=$padding} 4))}
$lines.Add((Record 'compacted' @{} 5))
$lines.Add((Record 'compacted' @{} 6))
$lines.Add((Record 'event_msg' @{type='token_count';info=@{model_context_window=200000;last_token_usage=@{input_tokens=60000;cached_input_tokens=40000;output_tokens=100};total_token_usage=@{total_tokens=130110;input_tokens=130000;cached_input_tokens=90000;output_tokens=110}}} 7))
# A totals-only record must not erase the latest request or window.
$lines.Add((Record 'event_msg' @{type='token_count';info=@{total_token_usage=@{total_tokens=140120;input_tokens=140000;cached_input_tokens=95000;output_tokens=120}}} 8))
$lines.Add((Record 'event_msg' @{type='token_count';info=$null;rate_limits=@{primary=@{used_percent=30;window_minutes=300}}} 9))
$lines.Add((Record 'event_msg' @{type='agent_message';message='Latest progress'} 10))
[IO.File]::WriteAllText($path,($lines -join "`n")+"`n")
$fields=@('ThreadId','Cwd','Model','Active','StartedAt','LastEventAt','ContextInput','ContextWindow','CachedInput','OutputTokens','ThreadTokens','UsageAt','TotalUsageAt','CompactCount','LastCompactAt','RateLimitAt')
function Compare-QuickAndFull {
    $script:rollouts.Clear()
    Update-Rollout (Get-Item $path) -QuickStart
    $quick=$script:rollouts[$path]
    Assert ($quick.NeedsBackfill) 'Large file did not use quick startup.'
    Assert (-not $quick.ReadError) 'Quick scan failed.'
    Update-Rollout (Get-Item $path)
    $full=$script:rollouts[$path]
    Assert (-not $full.NeedsBackfill -and -not $full.ReadError) 'Full history backfill failed.'
    foreach($field in $fields){Assert ($quick.$field -eq $full.$field) "Quick/full state mismatch: $field"}
    Assert (($quick.TotalUsage|ConvertTo-Json -Compress) -eq ($full.TotalUsage|ConvertTo-Json -Compress)) 'Cumulative counters changed after backfill.'
    Assert (($quick.RateLimits|ConvertTo-Json -Compress) -eq ($full.RateLimits|ConvertTo-Json -Compress)) 'Quota changed after backfill.'
    Assert ($full.TokenEvents.Count -gt $quick.TokenEvents.Count) 'Detailed history was not restored.'
}
Compare-QuickAndFull
Assert ($script:rollouts[$path].Active -and $script:rollouts[$path].CompactCount -eq 2 -and $script:rollouts[$path].ContextInput -eq 60000) 'Long running chat state incorrect.'
[IO.File]::AppendAllText($path,(Record 'event_msg' @{type='task_complete'} 11)+"`n")
Compare-QuickAndFull
Assert (-not $script:rollouts[$path].Active) 'Completed chat remained active.'
[IO.File]::AppendAllText($path,(Record 'event_msg' @{type='task_started';model_context_window=1000000} 12)+"`n")
Compare-QuickAndFull
Assert ($script:rollouts[$path].Active -and $null -eq $script:rollouts[$path].ContextInput) 'Changed window retained incompatible usage.'
[IO.File]::AppendAllText($path,'{"type":"event_msg","payload":{"type":"task_')
$script:rollouts.Clear()
Update-Rollout (Get-Item $path) -QuickStart
Assert ($script:rollouts[$path].Partial) 'Partial record lost during quick scan.'
[IO.File]::AppendAllText($path,"complete""}}`n")
Update-Rollout (Get-Item $path)
Assert (-not $script:rollouts[$path].Active -and -not $script:rollouts[$path].ReadError) 'Partial append/backfill completion failed.'
'PASS: quick/full parity, long running chat, separate request/totals/quota records, compactions, completed chat, changed window, detailed history and partial append.'
