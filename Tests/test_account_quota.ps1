# SPDX-License-Identifier: MIT
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Usage.Provider.ps1')
function Assert($condition,$message){if(-not $condition){throw $message}}
$now=[DateTimeOffset]::Now
function Reading([string]$account,[int]$minutes,[double]$used,[string]$source='Codex CLI') {
    $response=[pscustomobject]@{accountId=$account;rateLimits=[pscustomobject]@{limitId='codex';planType='plus';primary=[pscustomobject]@{usedPercent=$used;windowDurationMins=$minutes;resetsAt=$now.AddDays(2).ToUnixTimeSeconds()}}}
    ConvertTo-QuotaSnapshot $response $source $now
}
$old=Reading 'old-account' 300 12 'Recorded local quota'
$current=Reading 'new-account' 10080 82
$merged=Select-FreshQuota $current $old
Assert ($merged.Windows.Count -eq 1 -and $merged.Windows[0].Minutes -eq 10080 -and $merged.Windows[0].Remaining -eq 18) 'Another account supplied a 5-hour quota to a weekly-only account.'
Assert ($current.AccountKey -and $current.AccountKey -ne $old.AccountKey -and $current.AccountKey -notmatch 'new-account') 'Account keys must be distinct digests.'
$legacy=[pscustomobject]@{Source='Recorded local quota';Observed=$now.AddSeconds(1);Windows=@([pscustomobject]@{Name='codex / 5 hours';Minutes=300;Remaining=88});Plan='plus'}
Assert ((Select-FreshQuota $current $legacy).Windows.Count -eq 1) 'Unidentified history restored an absent account window.'
$empty=ConvertTo-QuotaSnapshot ([pscustomobject]@{accountId='new-account';rateLimits=$null}) 'Codex CLI' $now
Assert ((Select-FreshQuota $empty $old).Windows.Count -eq 0) 'An empty current account reading reused another account.'
$fixture=Join-Path $env:TEMP ('ctc-account-quota-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$before=Get-QuotaProfileStamp $fixture
[IO.File]::WriteAllText((Join-Path $fixture 'auth.json'),'fixture login metadata only')
$after=Get-QuotaProfileStamp $fixture
Assert ($before -ne $after) 'New sign-in metadata did not invalidate the profile stamp.'
[IO.File]::WriteAllText((Join-Path $fixture 'auth.json'),'replacement login metadata only')
Assert ((Get-QuotaProfileStamp $fixture) -ne $after) 'Changed sign-in metadata did not invalidate the profile stamp.'
$live=Reading 'new-account' 10080 82
$live|Add-Member ProfileStamp (Get-QuotaProfileStamp $fixture)
Assert ((Get-CurrentAccountQuota $live $legacy $live.ProfileStamp $false).Windows.Count -eq 1) 'Verified weekly quota missing.'
Assert ($null -eq (Get-CurrentAccountQuota $live $legacy 'different-stamp' $false)) 'Reading from a previous sign-in was shown.'
Assert ($null -eq (Get-CurrentAccountQuota $live $legacy $live.ProfileStamp $true)) 'Historical readings were shown while account identity was pending.'
$loginTest=Join-Path $fixture 'rpc.ps1'
[IO.File]::WriteAllText($loginTest,@'
while($line=[Console]::ReadLine()){
 $m=$line|ConvertFrom-Json
 if($m.id -eq 1){[Console]::WriteLine('{"id":1,"result":{}}')}
 if($m.id -eq 2){
  [IO.File]::WriteAllText((Join-Path $env:CODEX_HOME 'auth.json'),'changed while the request ran')
  [Console]::WriteLine('{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":82,"windowDurationMins":10080}}}}')
 }
}
'@)
$blocked=$false
try{$null=Get-CodexRateLimits -HomePath $fixture -Executable (Get-Process -Id $PID).Path -Arguments ('-NoProfile -File "'+$loginTest+'"') -TimeoutSeconds 8}catch{$blocked=$_.Exception.Message -match 'sign-in changed'}
Assert $blocked 'An in-flight quota response survived a sign-in change.'
$script:rollouts=@{};$ledgerFixture=Join-Path $fixture 'ledger';[void][IO.Directory]::CreateDirectory($ledgerFixture)
[IO.File]::WriteAllText((Join-Path $ledgerFixture '.overlay-test-fixture'),'test')
$snapshot=[pscustomobject]@{Tokens=[pscustomobject]@{Quota=$null;Rows=@()}}
$a=Reading 'account-a' 10080 82
Update-SnapshotQuota $snapshot $a $ledgerFixture
$firstHistory=$script:quotaLedgerPath;$firstScope=$script:quotaLedger.Scope
$b=Reading 'account-b' 10080 30
Update-SnapshotQuota $snapshot $b $ledgerFixture
Assert ($script:quotaLedgerPath -ne $firstHistory -and $script:quotaLedger.Scope -ne $firstScope) 'Different accounts shared the estimate ledger.'
Assert ([IO.File]::Exists($firstHistory)) 'The first account history was overwritten.'
Assert ((Get-QuotaShareText $script:quotaLedger 'unknown') -notmatch '5h') 'A weekly-only estimate fabricated a 5-hour window.'
[IO.File]::WriteAllText((Join-Path $ledgerFixture 'auth.json'),'refreshed metadata for the same account')
$sameScope=$script:quotaLedger.Scope;Update-SnapshotQuota $snapshot $b $ledgerFixture
Assert ($script:quotaLedger.Scope -eq $sameScope) 'Token refresh reset the same account identity.'
Save-QuotaLedger $script:quotaLedger $script:quotaLedgerPath
Save-QuotaLedger $script:quotaLedger $script:quotaLedgerPath
Assert ([IO.File]::Exists($script:quotaLedgerPath)) 'Repeated quota history save failed.'
'PASS: account-separated histories, retained previous history, weekly estimate and same-account token refresh.'
'PASS: in-flight login changes reject the earlier account response.'
'PASS: weekly-only account changes, current account authority, unknown history, digest identity, login metadata and pending refresh.'
