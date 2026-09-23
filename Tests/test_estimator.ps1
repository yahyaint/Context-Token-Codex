# SPDX-License-Identifier: MIT
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Quota.Estimator.ps1')
$rates=[IO.File]::ReadAllText((Join-Path $root 'Quota.Rates.json'))|ConvertFrom-Json
function Assert($ok,$message){if(-not $ok){throw $message}}
$now=[DateTimeOffset]::Now
$rates.checked=$now.ToString('yyyy-MM-dd')
function Quota($at,$used,$reset=$now.AddHours(3).ToUnixTimeSeconds()) {
    [pscustomobject]@{Observed=$at;Windows=@([pscustomobject]@{Name='codex / 5 hours';Minutes=300;Remaining=100-$used;Reset=$reset})}
}
function Event($id,$model,$cache=0) {
    [pscustomobject]@{Id=$id;Model=$model;Tier='standard';Input=1000;Cached=$cache;Output=0;RequestInput=1000;At=$now.AddSeconds(30);Total=1000}
}
$a=Event 'a' 'gpt-6-astra';$b=Event 'b' 'gpt-6-sol'
Assert ((Get-QuotaEventWeight $a $rates) -eq .25) 'Astra input weight wrong'
Assert ((Get-QuotaEventWeight (Event 'cached' 'gpt-6-astra' 1000) $rates) -eq .025) 'Cache weight wrong'
Assert ($null -eq (Get-QuotaEventWeight (Event 'unknown' 'future-model') $rates)) 'Unknown model received invented weight'
$ledger=New-QuotaLedger
Update-QuotaLedger $ledger (Quota $now 10) @() $rates $now
Update-QuotaLedger $ledger (Quota $now.AddMinutes(1) 16) @($a,$a,$b) $rates $now.AddMinutes(1)
$w=$ledger.Windows['codex / 5 hours']
Assert ([math]::Abs($w.Shares.a-5) -lt .00001 -and [math]::Abs($w.Shares.b-1) -lt .00001) 'Concurrent model weighting or deduplication failed'
Update-QuotaLedger $ledger (Quota $now.AddMinutes(1) 16) @($a,$b) $rates $now.AddMinutes(1)
Assert ($w.Spans -eq 1) 'Repeated sample counted twice'
Assert ((Get-QuotaShareText $ledger 'a' $now.AddMinutes(1)) -match '5h ~5%') 'Share display incorrect'
Assert ((Get-QuotaShareText $ledger 'a' $now.AddMinutes(5)) -match '5h --') 'Stale share must be unavailable'
Update-QuotaLedger $ledger (Quota $now.AddMinutes(2) 20) @() $rates $now.AddMinutes(2)
Assert ($w.Unattributed -eq 4) 'Unobserved activity allocated to local chat'
Update-QuotaLedger $ledger (Quota $now.AddMinutes(3) 2 $now.AddHours(5).ToUnixTimeSeconds()) @($a) $rates $now.AddMinutes(3)
Assert ($ledger.Windows['codex / 5 hours'].Shares.Count -eq 0) 'Reset retained old shares'
$fixture=Join-Path $env:TEMP ('ctc-estimator-'+[guid]::NewGuid().ToString('N'))
$path=Join-Path $fixture 'history.json';$ledger.Scope='profile-a'
Save-QuotaLedger $ledger $path
$loaded=Read-QuotaLedger $path 'profile-a'
Assert ($loaded.Windows.Count -eq 1 -and $loaded.Windows['codex / 5 hours'].LastAt -eq $now.AddMinutes(3)) 'History roundtrip failed'
Assert ((Read-QuotaLedger $path 'profile-b').Windows.Count -eq 0) 'Profile change reused history'
[IO.File]::WriteAllText($path,'broken')
Assert ((Read-QuotaLedger $path 'profile-a').Warning) 'Corrupt history should recover visibly'
$ledger=New-QuotaLedger
Update-QuotaLedger $ledger (Quota $now 10) @() $rates $now
Update-QuotaLedger $ledger (Quota $now.AddMinutes(1) 20) @($a,(Event 'u' 'unknown')) $rates $now.AddMinutes(1)
Assert ($ledger.Windows['codex / 5 hours'].Shares.Count -eq 0 -and $ledger.Windows['codex / 5 hours'].Unattributed -eq 10) 'Unknown model coverage normalized away'
Write-Output 'PASS: weighted concurrent allocation, cache, missing rates, duplicate/stale/reset samples, unobserved usage, durable history and profile isolation.'
# The collector records per-event model changes instead of repricing old totals.
[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'sessions'))
. (Join-Path $root 'Monitor.Core.ps1') -CodexHome $fixture
$log=Join-Path $fixture 'sessions/collector.jsonl';[IO.File]::WriteAllText($log,'')
$state=New-RolloutState (Get-Item $log);$state.ThreadId='collector';$state.Model='gpt-6-sol'
function CountRecord($inputCount,$cacheCount,$outputCount,$at) {
    @{type='event_msg';timestamp=$at.ToString('o');payload=@{type='token_count';info=@{last_token_usage=@{input_tokens=100;cached_input_tokens=20;output_tokens=5};total_token_usage=@{input_tokens=$inputCount;cached_input_tokens=$cacheCount;output_tokens=$outputCount;total_tokens=$inputCount+$outputCount}}}}|ConvertTo-Json -Depth 8 -Compress
}
Read-RolloutLine $state (CountRecord 100 20 10 $now)
Read-RolloutLine $state (CountRecord 200 40 20 $now.AddSeconds(1))
$state.Model='gpt-6-astra'
Read-RolloutLine $state (CountRecord 300 60 30 $now.AddSeconds(2))
Read-RolloutLine $state (CountRecord 300 60 30 $now.AddSeconds(3))
Assert ($state.TokenEvents.Count -eq 3 -and $state.TokenEvents[1].Model -eq 'gpt-6-sol' -and $state.TokenEvents[2].Model -eq 'gpt-6-astra') 'Collector lost model history or repeated a cumulative event'
Assert ($state.TokenEvents[2].Input -eq 100 -and $state.TokenEvents[2].Cached -eq 20 -and $state.TokenEvents[2].Output -eq 10) 'Collector token deltas wrong'
Write-Output 'PASS: cumulative-event collector and model switches.'
