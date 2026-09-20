$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Usage.Provider.ps1')
function Assert($condition,$message) { if (-not $condition) { throw $message } }
$now=[DateTimeOffset]::Now
$response=[pscustomobject]@{rateLimitsByLimitId=[pscustomobject]@{
 codex=[pscustomobject]@{limitId='codex';planType='plus';primary=[pscustomobject]@{usedPercent=72;windowDurationMins=10080;resetsAt=$now.AddDays(2).ToUnixTimeSeconds()};secondary=$null}
 extra=[pscustomobject]@{limitName='Extra';primary=[pscustomobject]@{usedPercent=125;windowDurationMins=300};secondary=[pscustomobject]@{usedPercent=$null}}
};rateLimitResetCredits=[pscustomobject]@{availableCount=0}}
$quota=ConvertTo-QuotaSnapshot $response 'fixture' $now
Assert ($quota.Windows.Count -eq 2) 'Missing or unknown windows were fabricated.'
Assert ($quota.Windows[0].Remaining -eq 28 -and $quota.Windows[1].Remaining -eq 0) 'Used-to-remaining conversion/clamping failed.'
Assert ($quota.Windows[0].Minutes -eq 10080) 'Weekly-only primary mislabeled.'
Assert ($quota.ResetCredits -eq 0) 'Known zero reset credits lost.'
$empty=ConvertTo-QuotaSnapshot ([pscustomobject]@{rateLimits=$null}) 'empty' $now
Assert ($empty.Windows.Count -eq 0) 'Empty quota should remain unavailable.'
Assert ((Format-QuotaReset $now.AddMinutes(-1).ToUnixTimeSeconds()) -match 'awaiting') 'Past reset should not claim quota recovery.'
$script:rollouts=@{}
$old=[pscustomobject]@{ThreadId='same';IsSubagent=$false;ThreadTokens=100;UsageAt=$now.AddMinutes(-1);TotalUsage=@{input_tokens=80;cached_input_tokens=20;output_tokens=20};RateLimits=$null}
$new=[pscustomobject]@{ThreadId='same';IsSubagent=$false;ThreadTokens=150;UsageAt=$now;TotalUsage=@{input_tokens=120;cached_input_tokens=40;output_tokens=30};RateLimits=$null}
$agent=[pscustomobject]@{ThreadId='child';IsSubagent=$true;ThreadTokens=999;UsageAt=$now;TotalUsage=$null;RateLimits=$null}
$script:rollouts=@{a=$old;b=$new;c=$agent}; $LookbackHours=24;$MaxRecentRollouts=128
$summary=Get-RecordedTokenSummary
Assert ($summary.Total -eq 150 -and $summary.Tasks -eq 1) 'Duplicate rollouts or child usage double counted.'
Assert ($summary.Input -eq 120 -and $summary.Cached -eq 40 -and $summary.Output -eq 30) 'Cached input incorrectly added to total.'
$new | Add-Member TotalUsageAt $now
$old | Add-Member TotalUsageAt $now.AddMinutes(-1)
$new.UsageAt=[DateTimeOffset]::MinValue
$summary=Get-RecordedTokenSummary
Assert ($summary.Total -eq 150) 'Compaction selected an older cumulative counter.'
$new.TotalUsage.reasoning_output_tokens=10
$summary=Get-RecordedTokenSummary
Assert ($summary.Uncached -eq 80 -and $summary.Reasoning -eq 10 -and $summary.CacheTasks -eq 1 -and $summary.Rows.Count -eq 1) 'Detailed counters incorrect.'
$new.TotalUsage.Remove('cached_input_tokens'); $new.TotalUsage.Remove('reasoning_output_tokens')
$summary=Get-RecordedTokenSummary
Assert ($summary.CacheTasks -eq 0 -and $summary.ReasoningTasks -eq 0 -and $null -eq $summary.Rows[0].Cached) 'Missing detail falsely presented as known zero.'
$pending=[pscustomobject]@{ThreadId='pending';IsSubagent=$false;Active=$true;ThreadTokens=$null;LastEventAt=$now;Model='fixture'}
$script:rollouts.pending=$pending
$summary=Get-RecordedTokenSummary
Assert ($summary.ActiveRows.Count -eq 1 -and $null -eq $summary.ActiveRows[0].Total) 'Active task without a first count is missing or fabricated.'
$pending.Active=$false
Assert (@((Get-RecordedTokenSummary).ActiveRows).Count -eq 0) 'Finished task remained in active highlights.'
'PASS: quota maps, null/missing windows, weekly-only plan, clamping, resets, cumulative deduplication and cached subset.'
