# SPDX-License-Identifier: MIT
param([string]$Report='')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $env:TEMP ('ctc-limits-matrix-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'sessions'))
. (Join-Path $root 'Monitor.Core.ps1') -CodexHome $fixture
$results=New-Object 'Collections.Generic.List[object]'
function Check([string]$name,[scriptblock]$test) {
    try { & $test; $results.Add([pscustomobject]@{Case=$name;Passed=$true}) }
    catch {$results.Add([pscustomobject]@{Case=$name;Passed=$false;Error=$_.Exception.Message})}
}
function Assert($condition,[string]$message='Unexpected result.') {if(-not $condition){throw $message}}
function Reject([scriptblock]$operation) {$caught=$false;try{& $operation|Out-Null}catch{$caught=$true};Assert $caught 'Invalid operation was accepted.'}
foreach($pair in @(@('544k',544000),@('1.5k',1500),@('180,000',180000),@('180_000',180000),@(' 200K ',200000),@('1',1),@('9223372036854775807',[long]::MaxValue))) {
    $inputValue=$pair[0];$expected=$pair[1]
    Check "Token format $inputValue" {Assert ((ConvertTo-TokenLimit $inputValue $null).Limit -eq $expected)}
}
foreach($pair in @(@('90%',489600),@('95%',516800),@('100%',544000),@('0.5%',2720),@('90.25%',490960))) {
    $inputValue=$pair[0];$expected=$pair[1]
    Check "Percentage $inputValue of 544k" {Assert ((ConvertTo-ContextDraft '544k' $inputValue).Compact -eq $expected)}
}
foreach($value in @('','0','-1','1e6','NaN','1m','10%%','101%','0%','9223372036854775808','999999999999999999999k','0.00001k')) {
    Check "Reject invalid value [$value]" {Reject {ConvertTo-TokenLimit $value 544000}}
}
Check 'Default removes both draft overrides' {$d=ConvertTo-ContextDraft 'default' 'DEFAULT';Assert ($null -eq $d.Window -and $null -eq $d.Compact)}
Check 'Percentage cannot replace context window' {Reject {ConvertTo-ContextDraft '90%' 'default'}}
Check 'Unknown default denominator rejects percentage' {Reject {ConvertTo-ContextDraft 'default' '90%'}}
Check 'Compaction cannot exceed entered window' {Reject {ConvertTo-ContextDraft '544k' '544001'}}
Check 'One-token percentage cannot produce zero' {Reject {ConvertTo-ContextDraft '1' '0.1%'}}
Check 'Percentages use decimal arithmetic at integer limit' {Assert ((ConvertTo-TokenLimit '100%' ([long]::MaxValue)).Limit -eq [long]::MaxValue)}
foreach($newline in @("`n","`r`n")) {
    foreach($quotedKey in @('model_context_window','"model_context_window"',"'model_context_window'")) {
        $path=Join-Path $fixture ('format-'+[guid]::NewGuid().ToString('N')+'.toml')
        $body="$quotedKey = 272_000 # old window${newline}developer_instructions = " + '"""' + "${newline}[example]${newline}" + 'model_context_window = 5' + "${newline}" + '"""' + "${newline}[profiles.sample]${newline}model_context_window = 123${newline}"
        Check "Atomic paired save: key=$quotedKey newline=$($newline.Length)" {
            [IO.File]::WriteAllText($path,$body,[Text.UTF8Encoding]::new($true))
            [void](Set-ContextLimits $path @{model_context_window=544000;model_auto_compact_token_limit=489600})
            Assert ((Get-TopLevelContextWindow $path) -eq 544000 -and (Get-TopLevelAutoCompactLimit $path) -eq 489600)
            $text=[IO.File]::ReadAllText($path)
            Assert ($text.Contains('[example]') -and $text.Contains('model_context_window = 5') -and $text.Contains('model_context_window = 123')) 'Nested values or instructions changed.'
            Assert (@(Get-ChildItem -LiteralPath $fixture -Filter ((Split-Path $path -Leaf)+'.bak-*')).Count -eq 1) 'Paired save did not use one backup.'
        }
        Check "No-op paired save: key=$quotedKey newline=$($newline.Length)" {Assert (-not (Set-ContextLimits $path @{model_context_window=544000;model_auto_compact_token_limit=489600}))}
        Check "Remove overrides preserves tables: key=$quotedKey newline=$($newline.Length)" {
            [void](Set-ContextLimits $path @{model_context_window=$null;model_auto_compact_token_limit=$null})
            Assert ($null -eq (Get-TopLevelContextWindow $path) -and [IO.File]::ReadAllText($path).Contains('model_context_window = 123'))
        }
    }
}
foreach($body in @("model_context_window = 1`nmodel_context_window = 2`n",'developer_instructions = "unterminated',"items = [`n1,2",'"\u006dodel_context_window" = 100')) {
    Check 'Malformed or unsupported TOML never changes' {
        $path=Join-Path $fixture 'malformed.toml';[IO.File]::WriteAllText($path,$body)
        Reject {Set-ContextLimits $path @{model_context_window=544000;model_auto_compact_token_limit=489600}}
        Assert ([IO.File]::ReadAllText($path) -ceq $body)
    }
}
Check 'Project missing from disk cannot be recreated silently' {Reject {Set-ContextLimits (Join-Path $fixture 'missing/.codex/config.toml') @{model_context_window=544000}}}
foreach($bad in @(0,-1,1.25,$true,'invalid','9223372036854775808')) {
    Check "Invalid writer value [$bad] changes no file" {
        $path=Join-Path $fixture 'bad-value.toml';[IO.File]::WriteAllText($path,'model_context_window = 544000')
        Reject {Set-ContextLimits $path @{model_context_window=$bad;model_auto_compact_token_limit=489600}}
        Assert ([IO.File]::ReadAllText($path) -eq 'model_context_window = 544000')
    }
}
Check 'Project save creates only its config directory' {
    $project=Join-Path $fixture ('Pr'+[char]0xFC+'fung space');[void][IO.Directory]::CreateDirectory($project)
    $path=Join-Path $project '.codex/config.toml';[void](Set-ContextLimits $path @{model_context_window=544000;model_auto_compact_token_limit=489600})
    Assert ((Get-TopLevelContextWindow $path) -eq 544000)
}
Check 'Locked save preserves original settings and removes temp file' {
    $path=Join-Path $fixture 'locked.toml';[IO.File]::WriteAllText($path,'model_context_window = 100000')
    $lock=[IO.File]::Open($path,'Open','Read','Read')
    try{Reject {Set-ContextLimits $path @{model_context_window=544000}}}finally{$lock.Dispose()}
    Assert ([IO.File]::ReadAllText($path) -eq 'model_context_window = 100000')
    Assert (@(Get-ChildItem -LiteralPath $fixture -Filter '*.tmp').Count -eq 0)
}
Check 'Save works after Default leaves an empty settings file' {
    $path=Join-Path $fixture 'empty.toml';[IO.File]::WriteAllText($path,'')
    [void](Set-ContextLimits $path @{model_context_window=544000;model_auto_compact_token_limit=489600})
    Assert ((Get-TopLevelContextWindow $path) -eq 544000)
}
Check 'Unchanged numeric save preserves formatting and comments' {
    $path=Join-Path $fixture 'same-value.toml';$body='"model_context_window" = +544_000 # keep this comment'
    [IO.File]::WriteAllText($path,$body)
    Assert (-not (Set-ContextLimits $path @{model_context_window=544000;model_auto_compact_token_limit=$null}))
    Assert ([IO.File]::ReadAllText($path) -ceq $body)
}
Check 'TOML setting names are case sensitive' {
    $path=Join-Path $fixture 'case.toml';[IO.File]::WriteAllText($path,'MODEL_CONTEXT_WINDOW = 123456')
    Assert ($null -eq (Get-TopLevelContextWindow $path))
    [void](Set-ContextLimits $path @{model_context_window=544000})
    Assert ((Get-TopLevelContextWindow $path) -eq 544000 -and [IO.File]::ReadAllText($path).Contains('MODEL_CONTEXT_WINDOW = 123456'))
}
Check 'Writer rejects an upper-case setting name' {Reject {Set-ContextLimits (Join-Path $fixture 'unsupported.toml') @{MODEL_CONTEXT_WINDOW=544000}}}
Check 'Quoted model key after multiline instructions resolves correctly' {
    $path=Join-Path $fixture 'model.toml'
    [IO.File]::WriteAllText($path,('developer_instructions = """'+"`n[example]`nmodel = 'wrong'`n"+'"""'+"`n"+'"model" = "gpt-6-astra" # chosen model'+"`n"))
    Assert ((Get-TopLevelModel $path) -eq 'gpt-6-astra')
}
Check 'Stale editor cannot overwrite another save' {
    $path=Join-Path $fixture 'conflict.toml';[IO.File]::WriteAllText($path,'model_context_window = 272000')
    $version=Get-ContextSettingsVersion $path
    [void](Set-ContextLimits $path @{model_context_window=800000})
    Reject {Set-ContextLimits $path @{model_context_window=544000} -ExpectedVersion $version}
    Assert ((Get-TopLevelContextWindow $path) -eq 800000)
}
Check 'New file conflict blocks stale editor' {
    $path=Join-Path $fixture 'created-later.toml';$version=Get-ContextSettingsVersion $path
    [IO.File]::WriteAllText($path,'model_context_window = 800000')
    Reject {Set-ContextLimits $path @{model_context_window=544000} -ExpectedVersion $version}
    Assert ((Get-TopLevelContextWindow $path) -eq 800000)
}
[IO.File]::WriteAllText($script:modelCachePath,'{"models":[{"slug":"gpt-6.1-sol","context_window":272000,"max_context_window":872000,"effective_context_window_percent":95},{"slug":"gpt-6-astra","context_window":272000,"max_context_window":872000,"effective_context_window_percent":95},{"slug":"future-model","context_window":200000}]}')
$project=Join-Path $fixture 'active-project';[void][IO.Directory]::CreateDirectory((Join-Path $project '.codex'))
$path=Join-Path $project '.codex/config.toml'
[IO.File]::WriteAllText($script:configPath,"model = 'gpt-6.1-sol'`nmodel_context_window = 300000`n")
foreach($model in @('gpt-6.1-sol','gpt-6-astra','future-model','unknown-model')) {
    Check "Project limits apply to model $model" {
        [void](Set-ContextLimits $path @{model_context_window=544000;model_auto_compact_token_limit=489600})
        $card=[pscustomobject]@{Model=$model;Window=258400}
        $base=Get-LimitEditorBaseline $path $card;Assert ($base.Base -eq 544000 -and $base.SavedCompact -eq 489600)
        $state=[pscustomobject]@{Cwd=$project;Model=$model;ContextWindow=258400}
        $status=Get-SavedWindowStatus $state
        Assert ($status.Requested -eq 544000)
        if($model -like 'gpt-6*'){Assert ($status.Status -eq 'Pending' -and $status.Expected -eq 516800);$state.ContextWindow=516800;Assert ((Get-SavedWindowStatus $state).Status -eq 'Confirmed')}
        else {Assert ($status.Status -eq 'Unverified' -and $null -eq $status.Expected)}
    }
}
Check 'Defaults restore global baseline and do not change another project' {
    $other=Join-Path $fixture 'other.toml';[IO.File]::WriteAllText($other,'model_context_window = 123456')
    [void](Set-ContextLimits $path @{model_context_window=$null;model_auto_compact_token_limit=$null})
    Assert ((Get-LimitEditorBaseline $path $null).Base -eq 300000 -and (Get-TopLevelContextWindow $other) -eq 123456)
}
Check 'Nested chat reads the parent project window' {
    [void][IO.Directory]::CreateDirectory((Join-Path $project '.git'))
    [IO.File]::WriteAllText((Join-Path $project '.git/HEAD'),'ref: refs/heads/main')
    [void](Set-ContextLimits $path @{model_context_window=544000})
    $child=Join-Path $project 'src';[void][IO.Directory]::CreateDirectory($child)
    $state=[pscustomobject]@{Cwd=$child;Model='gpt-6.1-sol';ContextWindow=258400}
    Assert ((Get-SavedWindowStatus $state).Requested -eq 544000)
    $base=Get-LimitEditorBaseline (Join-Path $child '.codex/config.toml') $null
    Assert ($base.Base -eq 544000 -and $base.Source -eq 'parent project fallback' -and $null -eq $base.SavedWindow)
}
Check 'Child override wins; child default restores parent' {
    $childPath=Join-Path $project 'src/.codex/config.toml'
    [void](Set-ContextLimits $childPath @{model_context_window=800000})
    $state=[pscustomobject]@{Cwd=(Join-Path $project 'src');Model='gpt-6.1-sol';ContextWindow=258400}
    Assert ((Get-SavedWindowStatus $state).Requested -eq 800000)
    [void](Set-ContextLimits $childPath @{model_context_window=$null})
    Assert ((Get-SavedWindowStatus $state).Requested -eq 544000)
}
Check 'Nested repository cannot inherit outside its root' {
    $nested=Join-Path $project 'nested';[void][IO.Directory]::CreateDirectory((Join-Path $nested '.git'))
    [IO.File]::WriteAllText((Join-Path $nested '.git/HEAD'),'ref: refs/heads/main')
    $state=[pscustomobject]@{Cwd=$nested;Model='gpt-6.1-sol';ContextWindow=285000}
    Assert ((Get-SavedWindowStatus $state).Requested -eq 300000)
}
Check 'Deleted configuration blocks an old editor' {
    $path=Join-Path $fixture 'deleted.toml';[IO.File]::WriteAllText($path,'model_context_window = 544000')
    $version=Get-ContextSettingsVersion $path;[IO.File]::Delete($path)
    Reject {Set-ContextLimits $path @{model_context_window=800000} -ExpectedVersion $version}
    Assert (-not [IO.File]::Exists($path))
}
foreach($culture in @('en-US','de-DE','ar-EG')) {
    Check "Input uses the same formats under $culture" {
        $previous=[Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [Threading.Thread]::CurrentThread.CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo($culture)
            Assert ((ConvertTo-ContextDraft '544k' '90.25%').Compact -eq 490960)
            Assert ((ConvertTo-TokenLimit '1.5k' $null).Limit -eq 1500)
        }finally{[Threading.Thread]::CurrentThread.CurrentCulture=$previous}
    }
}
foreach($factor in 1..3) {Check "Multiplier $factor retains numeric compaction ratio" {$d=Get-ScaledContextDraft 544000 $factor '544k' '489600';Assert ($d.Window -eq [string](544000*$factor) -and $d.Compact -eq [string](489600*$factor))}}
Check 'Multiplier does not compound after repeated selections' {$d=Get-ScaledContextDraft 544000 2 '544k' '90%';$d=Get-ScaledContextDraft 544000 3 $d.Window $d.Compact;Assert ($d.Window -eq '1632000' -and $d.Compact -eq '90%')}
Check 'Changed window with no new usage clears old context reading' {
    $f=Join-Path $fixture 'sessions/live.jsonl';[IO.File]::WriteAllText($f,'');$state=New-RolloutState (Get-Item $f)
    Read-RolloutLine $state '{"type":"event_msg","payload":{"type":"token_count","info":{"model_context_window":258400,"last_token_usage":{"input_tokens":200000,"cached_input_tokens":100000,"output_tokens":100}}}}'
    Read-RolloutLine $state '{"type":"event_msg","payload":{"type":"token_count","info":{"model_context_window":516800}}}'
    Assert ($state.ContextWindow -eq 516800 -and $null -eq $state.ContextInput -and $null -eq $state.CachedInput -and $null -eq $state.OutputTokens) 'Old usage was combined with the new capacity.'
}
$summary=[pscustomobject]@{Runtime=$PSVersionTable.PSVersion.ToString();Fixture=$fixture;Cases=$results.Count;Passed=@($results|Where-Object Passed).Count;Results=$results}
if($Report){[IO.File]::WriteAllText($Report,($summary|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))}
$results|Where-Object {-not $_.Passed}|ForEach-Object {Write-Output "FAIL: $($_.Case): $($_.Error)"}
Write-Output "$($summary.Passed)/$($summary.Cases) limit cases passed in PowerShell $($summary.Runtime)."
if($summary.Passed -ne $summary.Cases){throw 'Limit matrix failed.'}
