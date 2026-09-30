. (Join-Path $PSScriptRoot 'Quota.Estimator.ps1')
# SPDX-License-Identifier: MIT
# Independent CodexBar-style RPC provider and ccusage-inspired detail view.
# No upstream source copied. See ACKNOWLEDGMENTS.md and THIRD_PARTY_NOTICES.md.
function Find-CodexExecutable {
    $command=Get-Command codex.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $root=Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
    $found=Get-ChildItem -LiteralPath $root -Filter codex.exe -Recurse -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($found) { return $found.FullName }
    throw 'CTC cannot find the Codex CLI. Install Codex. Sign in to Codex. CTC keeps the last recorded quota.'
}
function Get-CodexRateLimits([string]$HomePath,[string]$Executable='', [string]$Arguments='app-server',[int]$TimeoutSeconds=45) {
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=if ($Executable) {$Executable} else {Find-CodexExecutable}; $info.Arguments=$Arguments
    if (-not $Executable -and $Arguments -eq 'app-server') {
        # Keep authentication in Codex's own profile, but never share its queue/state DB.
        $profile=if ($HomePath) {$HomePath} elseif ($env:CODEX_HOME) {$env:CODEX_HOME} else {Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex'}
        $sha=[Security.Cryptography.SHA256]::Create()
        try { $hash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($profile))))).Replace('-','').Substring(0,16) } finally {$sha.Dispose()}
        $statePath=Join-Path $env:LOCALAPPDATA ('CodexContextMonitor/UsageState/'+$hash)
        [void][IO.Directory]::CreateDirectory($statePath)
        $setting='sqlite_home='+($statePath.Replace('\','/') | ConvertTo-Json -Compress)
        $quoted='"'+[regex]::Replace($setting,'(\\*)"','$1$1\"')+'"'
        $info.Arguments='-c '+$quoted+' app-server'
        $info.EnvironmentVariables['CODEX_SQLITE_HOME']=$statePath
        $info.WorkingDirectory=$statePath
    }
    $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $info.RedirectStandardInput=$true; $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
    if ($HomePath) { $info.EnvironmentVariables['CODEX_HOME']=$HomePath }
    $process=New-Object Diagnostics.Process; $process.StartInfo=$info
    $startedProcess=$false
    try {
        [void]$process.Start()
        $startedProcess=$true
        # Drain diagnostics but never display them: CLI output can contain local paths.
        $stderr=$process.StandardError.ReadToEndAsync()
        $process.StandardInput.WriteLine('{"id":1,"method":"initialize","params":{"clientInfo":{"name":"context-widget","version":"6.8.0"}}}')
        $process.StandardInput.Flush()
        $phase='CLI initialization'; $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        while ([DateTime]::UtcNow -lt $deadline) {
            $pending=$process.StandardOutput.ReadLineAsync()
            $left=[Math]::Max(1,[int]($deadline-[DateTime]::UtcNow).TotalMilliseconds)
            if (-not $pending.Wait($left)) { throw "$phase timed out. CTC shows the last available reading." }
            if ($null -eq $pending.Result) { throw 'The Codex CLI closed before it sent account quota data.' }
            try { $message=$pending.Result|ConvertFrom-Json } catch { continue }
            if ($message.id -eq 1) {
                $phase='Subscription response'
                if ($message.error) { throw 'Codex CLI initialization failed. Update Codex or sign in to Codex.' }
                $process.StandardInput.WriteLine('{"method":"initialized","params":{}}')
                $process.StandardInput.WriteLine('{"id":2,"method":"account/rateLimits/read","params":{"excludeResetCreditDetails":true}}')
                $process.StandardInput.Flush()
            }
            if ($message.id -eq 2 -and $message.error.code -eq -32602) {
                $process.StandardInput.WriteLine('{"id":3,"method":"account/rateLimits/read","params":{}}')
                $process.StandardInput.Flush(); continue
            }
            if ($message.id -in @(2,3)) {
                if ($message.error) { throw 'Account quota data are unavailable. Check your Codex sign-in and network connection.' }
                return ConvertTo-QuotaSnapshot $message.result 'Codex CLI' ([DateTimeOffset]::Now)
            }
        }
        throw 'The account quota request timed out.'
    } finally {
        if ($startedProcess) { try { if (-not $process.HasExited) { $process.StandardInput.Close(); if (-not $process.WaitForExit(1000)) { $process.Kill(); [void]$process.WaitForExit(1500) } } } catch {} }
        $process.Dispose()
    }
}
function ConvertTo-QuotaSnapshot($response,[string]$source,$observed) {
    $buckets=@()
    if ($response.rateLimitsByLimitId) { $buckets=@($response.rateLimitsByLimitId.PSObject.Properties | ForEach-Object { [pscustomobject]@{Data=$_.Value;Id=$_.Name} }) }
    if (-not $buckets.Count -and $response.rateLimits) { $buckets=@([pscustomobject]@{Data=$response.rateLimits;Id=$response.rateLimits.limitId}) }
    $windows=@(); $plan=''; $credits=$null
    foreach ($wrapper in $buckets) {
        $bucket=$wrapper.Data
        $bucketId=if ($bucket.limitId) {[string]$bucket.limitId} elseif ($wrapper.Id) {[string]$wrapper.Id} elseif ($bucket.limitName) {[string]$bucket.limitName} else {'codex'}
        if ($bucket.planType) { $plan=[string]$bucket.planType }
        if ($bucket.credits) { $credits=$bucket.credits }
        foreach ($role in @('primary','secondary')) {
            $entry=$bucket.$role
            if ($null -eq $entry -or $null -eq $entry.usedPercent) { continue }
            $used=0.0
            if (-not [double]::TryParse([string]$entry.usedPercent,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$used) -or [double]::IsNaN($used) -or [double]::IsInfinity($used)) { continue }
            $minutes=$entry.windowDurationMins
            $label=if ($minutes -eq 300) {'5 hours'} elseif ($minutes -eq 10080) {'7 days'} elseif ($minutes) {"$minutes minutes"} else {'Window'}
            $bucketName=if ($bucket.limitName) {$bucket.limitName} elseif ($bucket.limitId) {$bucket.limitId} else {'Codex'}
            $windows+=[pscustomobject]@{Name="$bucketName / $label";WindowId="$bucketId/$role/$minutes";Remaining=[Math]::Max(0.0,[Math]::Min(100.0,100.0-$used));Reset=$entry.resetsAt;Minutes=$minutes}
        }
    }
    [pscustomobject]@{Source=$source;Observed=$observed;Plan=$plan;Windows=$windows;Credits=$credits;ResetCredits=$response.rateLimitResetCredits.availableCount}
}
function Get-RecordedTokenSummary {
    $byThread=@{}; $lifecycle=@{}
    foreach ($state in $script:rollouts.Values) {
        if (-not $state.ThreadId -or $state.IsSubagent) { continue }
        $prior=$lifecycle[$state.ThreadId]
        if (-not $prior -or $state.LastEventAt -gt $prior.LastEventAt) { $lifecycle[$state.ThreadId]=$state }
    }
    foreach ($state in $script:rollouts.Values) {
        if (-not $state.ThreadId -or $state.IsSubagent -or $null -eq $state.ThreadTokens) { continue }
        $when=if ($state.TotalUsageAt) {$state.TotalUsageAt} else {$state.UsageAt}
        $other=$byThread[$state.ThreadId]
        $otherWhen=if ($other.TotalUsageAt) {$other.TotalUsageAt} else {$other.UsageAt}
        if (-not $other -or $when -gt $otherWhen) { $byThread[$state.ThreadId]=$state }
    }
    $total=0L; $input=0L; $cached=0L; $output=0L; $detailed=0
    $reasoning=0L; $uncached=0L; $cacheTasks=0; $reasoningTasks=0; $rows=@(); $observed=[DateTimeOffset]::MinValue
    foreach ($state in $byThread.Values) {
        $total+=[long]$state.ThreadTokens
        $when=if ($state.TotalUsageAt) {$state.TotalUsageAt} else {$state.UsageAt}
        if ($when -gt $observed) { $observed=$when }
        $usage=$state.TotalUsage; $plain=$null
        if ($state.TotalUsage -and $null -ne $state.TotalUsage.input_tokens -and $null -ne $state.TotalUsage.output_tokens) {
            $input+=[long]$usage.input_tokens; $output+=[long]$usage.output_tokens; $detailed++
        }
        if ($null -ne $usage.cached_input_tokens -and $null -ne $usage.input_tokens -and $usage.cached_input_tokens -le $usage.input_tokens) {
            $cached+=[long]$usage.cached_input_tokens; $plain=[long]$usage.input_tokens-[long]$usage.cached_input_tokens; $uncached+=$plain; $cacheTasks++
        }
        if ($null -ne $usage.reasoning_output_tokens -and $null -ne $usage.output_tokens -and $usage.reasoning_output_tokens -le $usage.output_tokens) {
            $reasoning+=[long]$usage.reasoning_output_tokens; $reasoningTasks++
        }
        $identity=if ($script:titleCache) {$script:titleCache[$state.ThreadId]} else {$null}
        $title=if ($identity.UiName) {$identity.UiName} elseif ($identity.Initial) {$identity.Initial} else {$state.ThreadId}
        $rows+=[pscustomobject]@{Id=$state.ThreadId;Title=$title;Cwd=$state.Cwd;Model=$state.Model;Active=$lifecycle[$state.ThreadId].Active;Total=$state.ThreadTokens;Input=$usage.input_tokens;Cached=$usage.cached_input_tokens;Uncached=$plain;Output=$usage.output_tokens;Reasoning=$usage.reasoning_output_tokens;Observed=$when;LastInput=$state.ContextInput;LastCached=$state.CachedInput;LastOutput=$state.OutputTokens;Compactions=$state.CompactCount;QuotaObserved=$state.RateLimitAt;Activity=(Get-RecordedToolActivity $state)}
    }
    foreach ($state in $lifecycle.Values) {
        if (-not $state.Active -or $byThread.ContainsKey($state.ThreadId)) { continue }
        $identity=if ($script:titleCache) {$script:titleCache[$state.ThreadId]} else {$null}
        $title=if ($identity.UiName) {$identity.UiName} else {$state.ThreadId}
        $rows+=[pscustomobject]@{Id=$state.ThreadId;Title=$title;Cwd=$state.Cwd;Model=$state.Model;Active=$true;Total=$null;Input=$null;Cached=$null;Uncached=$null;Output=$null;Reasoning=$null;Observed=$null;LastInput=$null;LastCached=$null;LastOutput=$null;Compactions=$state.CompactCount;QuotaObserved=$state.RateLimitAt;Activity=(Get-RecordedToolActivity $state)}
    }
    $latest=$script:rollouts.Values | Where-Object {$_.RateLimits} | Sort-Object RateLimitAt -Descending | Select-Object -First 1
    $quota=$null
    if ($latest) {
        $r=$latest.RateLimits
        $bucket=@{limitId=$r.limit_id;planType=$r.plan_type}
        foreach ($key in @('primary','secondary')) {
            if ($r.$key) { $bucket[$key]=@{usedPercent=$r.$key.used_percent;windowDurationMins=$r.$key.window_minutes;resetsAt=$r.$key.resets_at} }
        }
        $quota=ConvertTo-QuotaSnapshot ([pscustomobject]@{rateLimits=[pscustomobject]$bucket}) 'Recorded local quota' $latest.RateLimitAt
    }
    [pscustomobject]@{Total=$total;Input=$input;Cached=$cached;Output=$output;Reasoning=$reasoning;Uncached=$uncached;CacheTasks=$cacheTasks;ReasoningTasks=$reasoningTasks;Rows=@($rows|Sort-Object Observed -Descending);ActiveRows=@($rows|Where-Object Active);Observed=$observed;Tasks=$byThread.Count;DetailedTasks=$detailed;Quota=$quota;
        Coverage="These counts cover $($byThread.Count) chats. CTC reads up to $MaxRecentRollouts files from the last $LookbackHours h. These are not account totals."}
}
function Get-RecordedToolActivity($state) {
    $ready=[bool]$state.HasMetadata -and -not $state.NeedsBackfill -and -not $state.ReadError
    $items=@();$count=0L
    if ($ready -and $state.ToolCounts) {
        $items=@($state.ToolCounts.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { [pscustomobject]@{Name=$_.Key;Count=[long]$_.Value} })
        foreach($item in $items){$count+=$item.Count}
    }
    [pscustomobject]@{Ready=$ready;Partial=[bool]$state.ActivityPartial;Calls=$(if($ready){$count}else{$null});Tools=$items;Originator=$state.Originator}
}
function Format-ShortTokenValue($value) {
    if($null -eq $value){return '--'}
    if($value -ge 1000000000){return ('{0:0.#}B' -f ($value/1000000000.0))}
    if($value -ge 1000000){return ('{0:0.#}M' -f ($value/1000000.0))}
    if($value -ge 1000){return ('{0:0.#}k' -f ($value/1000.0))}
    return ('{0:N0}' -f $value)
}
function Format-TokenValue($value) {
    if ($null -eq $value) { return '--' }
    return ('{0:N0}' -f $value)
}
function Get-ChatTokenDetails($chat) {
    $hit=if ($chat.Input -gt 0 -and $null -ne $chat.Cached -and $chat.Cached -le $chat.Input) { '{0:N1}%' -f (100.0*$chat.Cached/$chat.Input) } else {'--'}
    $nonReasoning=if ($null -ne $chat.Output -and $null -ne $chat.Reasoning -and $chat.Reasoning -le $chat.Output) {$chat.Output-$chat.Reasoning} else {$null}
    $share=if ($chat.Output -gt 0 -and $null -ne $chat.Reasoning -and $chat.Reasoning -le $chat.Output) {'{0:N1}%' -f (100.0*$chat.Reasoning/$chat.Output)} else {'--'}
    @("CHAT TOTALS", "Input: $(Format-TokenValue $chat.Input)", "  Cached input: $(Format-TokenValue $chat.Cached) | Hit rate: $hit", "  Uncached: $(Format-TokenValue $chat.Uncached)", "Output: $(Format-TokenValue $chat.Output)", "  Reasoning: $(Format-TokenValue $chat.Reasoning) | Share: $share", "  Other output: $(Format-TokenValue $nonReasoning)", '', 'LATEST REQUEST', "Input: $(Format-TokenValue $chat.LastInput) | Cached input: $(Format-TokenValue $chat.LastCached)", "Output: $(Format-TokenValue $chat.LastOutput)", '', "Last model: $($chat.Model)", "Compactions in this record: $(Format-TokenValue $chat.Compactions)", "Last token record: $(if($chat.Observed){$chat.Observed.ToLocalTime().ToString('MMM d HH:mm:ss')}else{'--'})", '', 'QUOTA ESTIMATE', $chat.QuotaShare, $chat.QuotaNotes, "Last local quota record: $(if($chat.QuotaObserved -gt [DateTimeOffset]::MinValue){$chat.QuotaObserved.ToLocalTime().ToString('MMM d HH:mm:ss')}else{'--'})", 'pp = percentage points of account allowance.', 'Other chats/devices may contribute; first reading is the baseline.', 'No exact per-chat quota or model-weighted charge is supplied.', '', 'Totals include earlier models. Cache is part of input;', 'reasoning is part of output. Missing data shows --.') -join "`n"
}
function Format-QuotaReset($timestamp) {
    if (-not $timestamp) { return 'Reset time unknown' }
    try {
        $reset=[DateTimeOffset]::FromUnixTimeSeconds([long]$timestamp)
        $left=$reset-[DateTimeOffset]::Now
        if ($left.TotalSeconds -le 0) { return 'The reset time passed. Refresh the quota reading.' }
        return ('Resets {0} ({1}h {2}m)' -f $reset.ToLocalTime().ToString('MMM d HH:mm'),[Math]::Floor($left.TotalHours),$left.Minutes)
    } catch { return 'Reset time unknown' }
}

function Select-FreshQuota($live,$recorded) {
    if (-not $live) {return $recorded}
    if (-not $recorded -or -not @($recorded.Windows).Count) {return $live}
    $byName=@{}
    foreach($snapshot in @($live,$recorded)) {
        foreach($entry in @($snapshot.Windows)) {
            $key=if ($entry.WindowId) {$entry.WindowId} else {$entry.Name}
            if(-not $key){continue}
            if(-not $byName.ContainsKey($key) -or $snapshot.Observed -gt $byName[$key].Observed) {
                $byName[$key]=[pscustomobject]@{Name=$entry.Name;WindowId=$entry.WindowId;Remaining=$entry.Remaining;Reset=$entry.Reset;Minutes=$entry.Minutes;Observed=$snapshot.Observed;Source=$snapshot.Source}
            }
        }
    }
    $windows=@($byName.Values|Sort-Object Name)
    $newest=if($recorded.Observed -gt $live.Observed){$recorded}else{$live}
    [pscustomobject]@{Windows=$windows;Observed=($windows|Sort-Object Observed|Select-Object -First 1).Observed;Source=(@($windows|ForEach-Object Source|Select-Object -Unique)-join ' + ');Plan=$(if($newest.Plan){$newest.Plan}elseif($live.Plan){$live.Plan}else{$recorded.Plan});ResetCredits=$live.ResetCredits;Credits=$newest.Credits}
}
