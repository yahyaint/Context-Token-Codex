# SPDX-License-Identifier: MIT
# Independent CodexBar-style RPC provider and ccusage-inspired detail view.
# No upstream source copied. See ACKNOWLEDGMENTS.md and THIRD_PARTY_NOTICES.md.
function Find-CodexExecutable {
    $command=Get-Command codex.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $root=Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
    $found=Get-ChildItem -LiteralPath $root -Filter codex.exe -Recurse -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($found) { return $found.FullName }
    throw 'Codex CLI not found. Install/sign in to Codex; recorded local quotas remain available.'
}
function Get-CodexRateLimits([string]$HomePath,[string]$Executable='', [string]$Arguments='app-server',[int]$TimeoutSeconds=12) {
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
        $process.StandardInput.WriteLine('{"id":1,"method":"initialize","params":{"clientInfo":{"name":"context-widget","version":"6.3.4"}}}')
        $process.StandardInput.Flush()
        $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        while ([DateTime]::UtcNow -lt $deadline) {
            $pending=$process.StandardOutput.ReadLineAsync()
            $left=[Math]::Max(1,[int]($deadline-[DateTime]::UtcNow).TotalMilliseconds)
            if (-not $pending.Wait($left)) { throw 'Usage refresh timed out. Showing the last available reading.' }
            if ($null -eq $pending.Result) { throw 'Codex CLI closed before returning subscription usage.' }
            try { $message=$pending.Result|ConvertFrom-Json } catch { continue }
            if ($message.id -eq 1) {
                if ($message.error) { throw 'Codex CLI initialization failed. Update or sign in to Codex.' }
                $process.StandardInput.WriteLine('{"method":"initialized","params":{}}')
                $process.StandardInput.WriteLine('{"id":2,"method":"account/rateLimits/read","params":{"excludeResetCreditDetails":true}}')
                $process.StandardInput.Flush()
            }
            if ($message.id -eq 2 -and $message.error.code -eq -32602) {
                $process.StandardInput.WriteLine('{"id":3,"method":"account/rateLimits/read","params":{}}')
                $process.StandardInput.Flush(); continue
            }
            if ($message.id -in @(2,3)) {
                if ($message.error) { throw 'Subscription usage unavailable. Check Codex sign-in and network access.' }
                return ConvertTo-QuotaSnapshot $message.result 'Live Codex CLI' ([DateTimeOffset]::Now)
            }
        }
        throw 'Subscription usage refresh timed out.'
    } finally {
        if ($startedProcess) { try { if (-not $process.HasExited) { $process.StandardInput.Close(); if (-not $process.WaitForExit(1000)) { $process.Kill(); [void]$process.WaitForExit(1500) } } } catch {} }
        $process.Dispose()
    }
}
function ConvertTo-QuotaSnapshot($response,[string]$source,$observed) {
    $buckets=@()
    if ($response.rateLimitsByLimitId) { $buckets=@($response.rateLimitsByLimitId.PSObject.Properties | ForEach-Object { $_.Value }) }
    if (-not $buckets.Count -and $response.rateLimits) { $buckets=@($response.rateLimits) }
    $windows=@(); $plan=''; $credits=$null
    foreach ($bucket in $buckets) {
        if ($bucket.planType) { $plan=[string]$bucket.planType }
        if ($bucket.credits) { $credits=$bucket.credits }
        foreach ($entry in @($bucket.primary,$bucket.secondary)) {
            if ($null -eq $entry -or $null -eq $entry.usedPercent) { continue }
            $used=0.0
            if (-not [double]::TryParse([string]$entry.usedPercent,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$used) -or [double]::IsNaN($used) -or [double]::IsInfinity($used)) { continue }
            $minutes=$entry.windowDurationMins
            $label=if ($minutes -eq 300) {'5 hours'} elseif ($minutes -eq 10080) {'7 days'} elseif ($minutes) {"$minutes minutes"} else {'Window'}
            $bucketName=if ($bucket.limitName) {$bucket.limitName} elseif ($bucket.limitId) {$bucket.limitId} else {'Codex'}
            $windows+=[pscustomobject]@{Name="$bucketName / $label";Remaining=[Math]::Max(0.0,[Math]::Min(100.0,100.0-$used));Reset=$entry.resetsAt;Minutes=$minutes}
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
        $rows+=[pscustomobject]@{Id=$state.ThreadId;Title=$title;Cwd=$state.Cwd;Model=$state.Model;Active=$lifecycle[$state.ThreadId].Active;Total=$state.ThreadTokens;Input=$usage.input_tokens;Cached=$usage.cached_input_tokens;Uncached=$plain;Output=$usage.output_tokens;Reasoning=$usage.reasoning_output_tokens;Observed=$when}
    }
    foreach ($state in $lifecycle.Values) {
        if (-not $state.Active -or $byThread.ContainsKey($state.ThreadId)) { continue }
        $identity=if ($script:titleCache) {$script:titleCache[$state.ThreadId]} else {$null}
        $title=if ($identity.UiName) {$identity.UiName} else {$state.ThreadId}
        $rows+=[pscustomobject]@{Id=$state.ThreadId;Title=$title;Cwd=$state.Cwd;Model=$state.Model;Active=$true;Total=$null;Input=$null;Cached=$null;Uncached=$null;Output=$null;Reasoning=$null;Observed=$null}
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
        Coverage="Cumulative counters for $($byThread.Count) loaded user chats; discovery: last $LookbackHours h, up to $MaxRecentRollouts files. Not account lifetime or today's total."}
}
function Format-TokenValue($value) {
    if ($null -eq $value) { return '--' }
    return ('{0:N0}' -f $value)
}
function Format-QuotaReset($timestamp) {
    if (-not $timestamp) { return 'Reset unknown' }
    try {
        $reset=[DateTimeOffset]::FromUnixTimeSeconds([long]$timestamp)
        $left=$reset-[DateTimeOffset]::Now
        if ($left.TotalSeconds -le 0) { return 'Reset time passed; awaiting refreshed usage' }
        return ('Resets {0} ({1}h {2}m)' -f $reset.ToLocalTime().ToString('MMM d HH:mm'),[Math]::Floor($left.TotalHours),$left.Minutes)
    } catch { return 'Reset unknown' }
}
