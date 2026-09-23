# SPDX-License-Identifier: MIT
# Independent measured-interval attribution. Research references in QUOTA-RESEARCH.md.
function Get-QuotaEventWeight($event,$rates) {
    if (([DateTimeOffset]::Now-[DateTimeOffset]::Parse($rates.checked)).TotalDays -gt 90) {return $null}
    $r=$rates.models.($event.Model)
    # Unknown tiers and long-context pricing must not silently receive base weights.
    if (-not $r -or $event.Tier -notin @('','default','auto','standard') -or $null -eq $event.Input -or $null -eq $event.Cached -or $null -eq $event.Output -or $event.RequestInput -gt 272000) { return $null }
    if ($event.Input -lt 0 -or $event.Cached -lt 0 -or $event.Cached -gt $event.Input -or $event.Output -lt 0) { return $null }
    return (($event.Input-$event.Cached)*[double]$r[0]+$event.Cached*[double]$r[1]+$event.Output*[double]$r[2])/1000000.0
}
function New-QuotaLedger { @{Schema=1;Windows=@{};Scope='';SavedAt=[DateTimeOffset]::MinValue;Warning=''} }
function Update-QuotaLedger($ledger,$quota,$events,$rates,$now=[DateTimeOffset]::Now) {
    if (-not $quota) { return }
    foreach ($q in @($quota.Windows)) {
        if (-not $q.Reset -or -not $q.Minutes) { continue }
        $reset=[DateTimeOffset]::FromUnixTimeSeconds([long]$q.Reset)
        if ($reset -le $now) { continue }
        $at=if ($q.Observed) {[DateTimeOffset]$q.Observed} else {[DateTimeOffset]$quota.Observed}
        if (($now-$at).TotalMinutes -gt 2 -or $at -gt $now.AddMinutes(1)) { continue }
        $used=100.0-[double]$q.Remaining
        $key=[string]$q.Name; $w=$ledger.Windows[$key]
        if (-not $w -or [long]$w.Reset -ne [long]$q.Reset -or ($at -gt $w.LastAt -and $used -lt $w.LastUsed)) {
            $ledger.Windows[$key]=[pscustomobject]@{Reset=[long]$q.Reset;Minutes=$q.Minutes;Start=$at;LastAt=$at;HighAt=$at;HighUsed=$used;LastUsed=$used;Shares=@{};Unattributed=0.0;Spans=0;Mixed=0;Reason='Collecting baseline'}
            continue
        }
        if ($at -le $w.LastAt) { continue }
        $w.LastAt=$at; $w.LastUsed=$used
        $delta=$used-$w.HighUsed
        if ($delta -le 0) { continue }
        $weights=@{}; $seen=@{}; $unknown=$false
        foreach ($e in @($events)) {
            if ($e.At -le $w.HighAt -or $e.At -gt $at) { continue }
            $eventKey="$($e.Id)|$($e.At)|$($e.Total)"
            if ($seen.ContainsKey($eventKey)) { continue }; $seen[$eventKey]=$true
            $weight=Get-QuotaEventWeight $e $rates
            if ($null -eq $weight) { $unknown=$true; continue }
            if ($weight -gt 0) { $weights[$e.Id]+=$weight }
        }
        $total=($weights.Values|Measure-Object -Sum).Sum
        # Gaps and unsupported events stay unattributed. Do not normalize away missing coverage.
        if ($unknown -or -not $total -or ($at-$w.HighAt).TotalMinutes -gt 10 -or $w.Shares.Count -gt 512) {
            $w.Unattributed+=$delta; $w.Reason='Some intervals unattributed'
        } else {
            foreach ($id in $weights.Keys) { $w.Shares[$id]+=$delta*$weights[$id]/$total }
            $w.Spans++; if ($weights.Count -gt 1) {$w.Mixed++}; $w.Reason='Local-only estimate'
        }
        $w.HighUsed=$used; $w.HighAt=$at
    }
    foreach ($key in @($ledger.Windows.Keys)) { if ([DateTimeOffset]::FromUnixTimeSeconds([long]$ledger.Windows[$key].Reset) -le $now) { $ledger.Windows.Remove($key) } }
}
function Read-QuotaLedger([string]$path,[string]$scope) {
    $ledger=New-QuotaLedger; $ledger.Scope=$scope
    if (-not (Test-Path -LiteralPath $path)) {return $ledger}
    try {
        if ((Get-Item -LiteralPath $path).Length -gt 2MB) {throw 'History too large'}
        $saved=[IO.File]::ReadAllText($path)|ConvertFrom-Json
        if ($saved.Schema -ne 1 -or $saved.Scope -ne $scope) {return $ledger}
        foreach ($p in $saved.Windows.PSObject.Properties) {
            $w=$p.Value
            foreach ($field in @('Start','LastAt','HighAt')) {$w.$field=[DateTimeOffset]$w.$field}
            $shares=@{}; foreach ($v in $w.Shares.PSObject.Properties) {$shares[$v.Name]=[double]$v.Value}; $w.Shares=$shares
            $ledger.Windows[$p.Name]=$w
        }
    } catch { $ledger=New-QuotaLedger; $ledger.Scope=$scope; $ledger.Warning='History unavailable; new baseline' }
    return $ledger
}
function Save-QuotaLedger($ledger,[string]$path) {
    $temp=$path+'.tmp-'+[guid]::NewGuid().ToString('N')
    try {
        [void][IO.Directory]::CreateDirectory((Split-Path $path -Parent))
        $windows=@{}
        foreach($key in $ledger.Windows.Keys) {
            $copy=@{}; foreach($property in $ledger.Windows[$key].PSObject.Properties){$copy[$property.Name]=$property.Value}
            foreach($field in @('Start','LastAt','HighAt')){$copy[$field]=([DateTimeOffset]$copy[$field]).ToString('o')}
            $windows[$key]=$copy
        }
        $saved=@{Schema=1;Scope=$ledger.Scope;Windows=$windows}
        [IO.File]::WriteAllText($temp,($saved|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $path) {[IO.File]::Replace($temp,$path,$null)} else {[IO.File]::Move($temp,$path)}
        $ledger.SavedAt=[DateTimeOffset]::Now
    } finally {if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp}}
}
function Get-QuotaShareText($ledger,[string]$id,$now=[DateTimeOffset]::Now) {
    $parts=@()
    foreach ($minutes in @(300,10080)) {
        $label=if($minutes -eq 300){'5h'}else{'7d'}
        $windows=@($ledger.Windows.Values|Where-Object {$_.Minutes -eq $minutes -and [DateTimeOffset]::FromUnixTimeSeconds([long]$_.Reset) -gt $now})
        # Multiple buckets cannot safely be added into one percentage.
        if ($windows.Count -ne 1) {$parts+="$label --";continue}
        $w=$windows[0]
        if (($now-$w.LastAt).TotalMinutes -gt 2 -or -not $w.Shares.ContainsKey($id)) {$parts+="$label --";continue}
        $n=$w.Shares[$id]; $value=if($n -lt 1){'<1%'}else{'~{0:N0}%' -f $n}
        $parts+="$label $value"
    }
    'Est. tracked share: '+($parts -join ' | ')
}
function Update-SnapshotQuota($snapshot,$live,[string]$homePath) {
    if (-not $homePath) {$homePath=if($env:CODEX_HOME){$env:CODEX_HOME}else{Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex'}}
    # Metadata only: never read credentials. A changed login file invalidates estimates.
    $auth=Get-Item -LiteralPath (Join-Path $homePath 'auth.json') -ErrorAction SilentlyContinue
    $scope=[IO.Path]::GetFullPath($homePath)+'|'+[string]$auth.LastWriteTimeUtc.Ticks+'|'+[string]$auth.Length
    if (-not $script:quotaLedger -or $script:quotaLedger.Scope -ne $scope) {
        $sha=[Security.Cryptography.SHA256]::Create()
        try {$key=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($homePath))))).Replace('-','').Substring(0,16)}finally{$sha.Dispose()}
        $base=if(Test-Path -LiteralPath (Join-Path $homePath '.overlay-test-fixture')){$homePath}else{Join-Path $env:LOCALAPPDATA 'CodexContextMonitor/QuotaHistory'}
        $script:quotaLedgerPath=Join-Path $base ($key+'.json')
        $script:quotaLedger=Read-QuotaLedger $script:quotaLedgerPath $scope
        $script:quotaLedgerStamp=''
        $script:quotaRates=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Quota.Rates.json'))|ConvertFrom-Json
    }
    $quota=Select-FreshQuota $live $snapshot.Tokens.Quota
    $stamp=($quota.Windows|ForEach-Object {"$($_.Name)|$($_.Reset)|$($_.Remaining)|$($_.Observed)"}) -join ';'
    $stamp+='|'+[string]$quota.Observed
    if ($stamp -ne $script:quotaLedgerStamp) {
        $events=@(foreach($state in $script:rollouts.Values){foreach($event in $state.TokenEvents){
            if($state.IsSubagent){$unknown=$event|Select-Object *; $unknown.Model=''; $unknown}else{$event}
        }})
        Update-QuotaLedger $script:quotaLedger $quota $events $script:quotaRates
        $script:quotaLedgerStamp=$stamp
    }
    foreach($row in @($snapshot.Tokens.Rows)) {
        $text=Get-QuotaShareText $script:quotaLedger $row.Id
        $notes=@('Local-only allocation; other devices can contaminate it.','Only observed intervals since baseline; not full chat history.','Weights: model + uncached/cached input + output.','Missing speed assumes Standard; unsupported speed/context stays unattributed.')
        foreach($w in $script:quotaLedger.Windows.Values) {
            $label=if($w.Minutes -eq 300){'5h'}elseif($w.Minutes -eq 10080){'7d'}else{"$($w.Minutes)m"}
            $notes+=('{0}: since {1}; {2} matched intervals; {3:N0} pp unattributed.' -f $label,$w.Start.ToLocalTime().ToString('MMM d HH:mm'),$w.Spans,$w.Unattributed)
        }
        if($script:quotaLedger.Warning){$notes+=$script:quotaLedger.Warning}
        $row|Add-Member QuotaShare $text -Force
        $row|Add-Member QuotaNotes ($notes -join "`n") -Force
    }
    if (([DateTimeOffset]::Now-$script:quotaLedger.SavedAt).TotalSeconds -ge 30) {
        try {Save-QuotaLedger $script:quotaLedger $script:quotaLedgerPath} catch {$script:quotaLedger.Warning='History could not be saved; estimates last until restart'}
    }
}
