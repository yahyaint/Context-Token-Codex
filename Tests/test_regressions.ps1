# SPDX-License-Identifier: MIT
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $env:TEMP ('ctc-regressions-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'sessions'))
. (Join-Path $root 'Monitor.Core.ps1') -CodexHome $fixture -MaxRecentRollouts 1
. (Join-Path $root 'Monitor.Data.ps1')
. (Join-Path $root 'Usage.Provider.ps1')
. (Join-Path $root 'Install.Core.ps1')
function Assert($value,$message){if(-not $value){throw $message}}
$path=Join-Path $fixture 'config.toml'
$original='developer_instructions = """'+"`n[example]`nunchanged instructions`n"+'"""'+"`n"+'"model_context_window" = 100_000'+"`n[projects.x]`ntrust_level = 'trusted'`n"
[IO.File]::WriteAllText($path,$original)
[void](Set-ContextLimits $path @{model_context_window=200000;model_auto_compact_token_limit=180000})
$result=[IO.File]::ReadAllText($path)
Assert ($result.Contains('developer_instructions = """'+"`n[example]`nunchanged instructions`n"+'"""')) 'Multiline TOML changed.'
Assert ((Get-TopLevelContextWindow $path) -eq 200000 -and (Get-TopLevelAutoCompactLimit $path) -eq 180000) 'Combined TOML save failed.'
Assert (@(Get-ChildItem $fixture -Filter 'config.toml.bak-*').Count -eq 1) 'Two fields must use one transaction/backup.'
Assert ($result.Contains("trust_level = 'trusted'")) 'Table changed.'
$lock=[IO.File]::Open($path,'Open','Read','Read');$failed=$false
try{try{[void](Set-ContextLimits $path @{model_context_window=300000})}catch{$failed=$true}}finally{$lock.Dispose()}
Assert ($failed -and [IO.File]::ReadAllText($path) -ceq $result) 'Locked write altered configuration.'
[IO.File]::WriteAllText($path,'"\u006dodel_context_window" = 100000')
$failed=$false;try{[void](Set-ContextLimits $path @{model_context_window=200000})}catch{$failed=$true}
Assert ($failed -and [IO.File]::ReadAllText($path) -eq '"\u006dodel_context_window" = 100000') 'Unsupported escaped key was not rejected safely.'
[IO.File]::Delete($path)
$expected=Join-Path $fixture ('Pr'+[char]0xFC+'fung')
[IO.File]::WriteAllText((Join-Path $fixture '.codex-global-state.json'),(@{'local-projects'=@{one=@{rootPaths=@($expected)}}}|ConvertTo-Json -Depth 5))
$script:sqlite=$null
Assert (@(Get-KnownProjectPaths) -contains $expected) 'Unicode idle project path corrupted.'
$f=Join-Path $fixture 'sessions/a.jsonl';[IO.File]::WriteAllText($f,'')
$state=New-RolloutState (Get-Item $f)
Read-RolloutLine $state '{"type":"event_msg","payload":{"type":"token_count","info":{"model_context_window":100000,"last_token_usage":{"input_tokens":90000}}}}'
Read-RolloutLine $state '{"type":"event_msg","payload":{"type":"task_started","model_context_window":1000000}}'
Assert ($null -eq $state.ContextInput) 'Old usage combined with new window.'
$originalSqlite=(Get-Command Invoke-Sqlite).Definition
function Invoke-Sqlite {return @([pscustomobject]@{id='one';ui_name='';initial_title='Old first prompt';rollout_path='Z:\missing\rollout.jsonl'})}
$script:sqlite='fixture';$script:stateDatabase=$f
$script:titleCache['one']=[pscustomobject]@{UiName='Current name';Initial='';Source='index'}
Update-Titles
Assert ($script:titleCache['one'].UiName -eq 'Current name') 'Blank database name replaced current index name.'
$script:lastReconcile=[DateTimeOffset]::MinValue
Assert (@(Get-RolloutFiles).Count -gt 0 -and $script:discoveryMode -eq 'folder fallback') 'Stale database paths prevented fallback.'
Set-Item Function:Invoke-Sqlite ([scriptblock]::Create($originalSqlite));$script:sqlite=$null
foreach($n in 1..3){$f=Join-Path $fixture ('sessions/'+$n+'.jsonl');[IO.File]::WriteAllText($f,'');$script:rollouts[$f]=New-RolloutState (Get-Item $f)}
Remove-ExpiredRolloutStates
Assert ($script:rollouts.Count -eq 1) 'Inactive cache exceeded retention cap.'
$live=[pscustomobject]@{Observed=[DateTimeOffset]::Now.AddHours(-1);Windows=@([pscustomobject]@{Name='Codex / 5 hours';Remaining=90},[pscustomobject]@{Name='Extra / 5 hours';Remaining=50})}
$local=[pscustomobject]@{Observed=[DateTimeOffset]::Now;Windows=@([pscustomobject]@{Name='Codex / 5 hours';Remaining=10})}
$merged=Select-FreshQuota $live $local
Assert ($merged.Windows.Count -eq 2 -and @($merged.Windows|Where-Object {$_.Name -eq 'Codex / 5 hours'})[0].Remaining -eq 10) 'Stale live quota beat a newer reading.'
$prefs=Join-Path $fixture 'prefs.json';[IO.File]::WriteAllText($prefs,'{"Opacity":"broken","Width":-100,"Topmost":"no","Mode":"unknown"}')
$defaults=@{Opacity=.92;Width=460;Height=620;Topmost=$true;Mode='Context'}
$clean=Read-WidgetPreferences $prefs $defaults
Assert ($clean.Opacity -eq .92 -and $clean.Width -eq 460 -and $clean.Topmost -eq $true -and $clean.Mode -eq 'Context') 'Invalid preferences were not normalized.'
$install=Join-Path $fixture 'install';$destination=Join-Path $install 'installed'
[void][IO.Directory]::CreateDirectory($destination);[void][IO.Directory]::CreateDirectory((Join-Path $install 'preferences'))
[IO.File]::WriteAllText((Join-Path $install 'preferences/overlay.json'),'{broken')
$installed=Install-ContextWidget -Source $root -Destination $destination -TestRoot $install
Assert ($installed.Files -eq 34 -and @(Get-ChildItem (Join-Path $install 'preferences') -Filter '*.bak').Count -eq 1) 'Malformed preference recovery failed.'
$exe=Join-Path $destination 'ContextWidget.exe';$scriptFile=Join-Path $destination 'Overlay.ps1'
[IO.File]::WriteAllText($exe,'old launcher');[IO.File]::WriteAllText($scriptFile,'old script')
$lock=[IO.File]::Open($scriptFile,'Open','Read','Read');$failed=$false
try{try{$null=Install-ContextWidget -Source $root -Destination $destination -TestRoot $install}catch{$failed=$true}}finally{$lock.Dispose()}
Assert ($failed -and [IO.File]::ReadAllText($exe) -eq 'old launcher' -and [IO.File]::ReadAllText($scriptFile) -eq 'old script') 'Failed installation did not roll back.'
$script:discoveredPaths=@();$script:lastReconcile=[DateTimeOffset]::Now.AddSeconds(-9)
$before=$script:lastReconcile;$null=Get-RolloutFiles
Assert ($script:lastReconcile -eq $before) 'Empty cache polling moved the discovery deadline.'
$script:lastReconcile=[DateTimeOffset]::Now.AddSeconds(-11)
Assert (@(Get-RolloutFiles).Count -gt 0) 'First task after empty discovery was never found.'
$script:lastIndexWrite=[DateTime]::Now
Read-RolloutLine $state '{"type":"session_meta","payload":{"id":"newly-resumed-chat"}}'
Assert ($script:lastIndexWrite -eq [DateTime]::MinValue) 'Newly discovered chat did not refresh its index name.'
$script:rollouts=@{}
foreach($n in 1..2){$f=Join-Path $fixture ('sessions/lifecycle'+$n+'.jsonl');[IO.File]::WriteAllText($f,'');$r=New-RolloutState (Get-Item $f);$r.ThreadId='same-chat';$r.Active=$n -eq 1;$r.LastEventAt=[DateTimeOffset]::Now.AddMinutes($n);$r.LastWriteAt=(Get-Date).AddDays(-3);$script:rollouts[$f]=$r}
Remove-ExpiredRolloutStates
Assert (@(Get-DisplayStates).Count -eq 0) 'Eviction resurrected an older active rollout.'
'PASS: safe TOML, atomic settings, Unicode paths, naming, context reset, index fallback, bounded state, quota freshness, preference recovery and installer rollback.'