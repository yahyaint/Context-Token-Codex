# Codex Context Monitor - shared reader for Windows overlay 4.0
# SPDX-License-Identifier: MIT
# Reads local Codex session/state files. Config helpers write only selected config.toml files.
param(
    [string]$CodexHome = '',
    [string]$SqliteHome = '',
    [string]$SessionRoot = '',
    [string]$LogDatabase = '',
    [int]$RefreshSeconds = 2,
    [int]$LookbackHours = 24,
    [int]$MaxRecentRollouts = 128,
    [int]$ReconcileSeconds = 10,
    [int]$WarnPercent = 80,
    [int]$CriticalPercent = 95,
    [int]$MaxUpdates = 0,
    [switch]$Once,
    [switch]$NoClear
)

$ErrorActionPreference = 'Stop'
if (-not $CodexHome) {
    $CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME }
        else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex' }
}
if ((Test-Path -LiteralPath $CodexHome) -and -not (Test-Path -LiteralPath $CodexHome -PathType Container)) {
    throw "Codex data path must be a directory: $CodexHome."
}
if (-not $SessionRoot) { $SessionRoot = Join-Path $CodexHome 'sessions' }
function Find-VersionedDatabase([string]$folder, [string]$stem) {
    $candidates = @(Get-ChildItem -LiteralPath $folder -File -Filter "$stem`_*.sqlite" -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -match ('^' + [regex]::Escape($stem) + '_(\d+)$') } |
        Sort-Object @{ Expression = { [int]([regex]::Match($_.BaseName, '(\d+)$').Groups[1].Value) } } -Descending)
    if ($candidates.Count) { return $candidates[0].FullName }
    $plain = Join-Path $folder "$stem.sqlite"
    if (Test-Path -LiteralPath $plain -PathType Leaf) { return $plain }
    return ''
}
function Get-TomlStatements([string]$content) {
    # Lexical boundaries only: never interpret a table marker inside a string/array.
    # Unsupported escaped key names are rejected by the editor, not rewritten.
    $start=0; $depth=0; $quote=''; $multi=$false; $comment=$false; $escaped=$false
    for ($i=0; $i -lt $content.Length; $i++) {
        $ch=$content[$i]
        if ($comment) { if ($ch -ne "`n") { continue }; $comment=$false }
        elseif ($quote) {
            if ($escaped) { $escaped=$false; continue }
            if ($quote -eq '"' -and $ch -eq '\') { $escaped=$true; continue }
            if ($ch -eq $quote) {
                if (-not $multi) { $quote=''; continue }
                if ($i+2 -lt $content.Length -and $content.Substring($i,3) -eq ($quote*3)) {
                    $i+=2
                    # TOML permits one/two literal quotes before the closing delimiter.
                    while ($i+1 -lt $content.Length -and $content[$i+1] -eq $quote) { $i++ }
                    $quote=''; $multi=$false
                }
            } elseif (-not $multi -and $ch -eq "`n") { throw 'The TOML string is not closed. CTC did not change settings.' }
            continue
        }
        elseif ($ch -eq '#') { $comment=$true; continue }
        elseif ($ch -eq '"' -or $ch -eq "'") {
            $quote=[string]$ch
            $multi=$i+2 -lt $content.Length -and $content.Substring($i,3) -eq ($quote*3)
            if ($multi) { $i+=2 }; continue
        }
        elseif ($ch -eq '[' -or $ch -eq '{') { $depth++ }
        elseif ($ch -eq ']' -or $ch -eq '}') { $depth--; if ($depth -lt 0) { throw 'The TOML brackets do not match. CTC did not change settings.' } }
        if ($ch -eq "`n" -and $depth -eq 0) {
            [pscustomobject]@{Start=$start;Length=$i+1-$start;Text=$content.Substring($start,$i+1-$start)}
            $start=$i+1
        }
    }
    if ($quote -or $depth -ne 0) { throw 'The TOML data are incomplete. CTC did not change settings.' }
    if ($start -lt $content.Length) { [pscustomobject]@{Start=$start;Length=$content.Length-$start;Text=$content.Substring($start)} }
}

function Get-TomlRootSettings([string]$content, [switch]$Strict) {
    foreach ($statement in @(Get-TomlStatements $content)) {
        $text=$statement.Text.TrimStart()
        if ($text.StartsWith('[')) { break }
        if (-not $text -or $text.StartsWith('#')) { continue }
        $match=[regex]::Match($text,'^(?:([A-Za-z0-9_-]+)|"([^"\\]+)"|''([^'']+)'')\s*=\s*([\s\S]*)$')
        if (-not $match.Success) { if ($Strict) { throw 'CTC cannot use this TOML key format. Edit the file through Codex. CTC did not change settings.' }; continue }
        $key=if ($match.Groups[1].Success) {$match.Groups[1].Value} elseif ($match.Groups[2].Success) {$match.Groups[2].Value} else {$match.Groups[3].Value}
        [pscustomobject]@{Key=$key;Value=$match.Groups[4].Value;Start=$statement.Start;Length=$statement.Length}
    }
}

function Get-ConfiguredSqliteHome([string]$configFile) {
    if (-not (Test-Path -LiteralPath $configFile -PathType Leaf)) { return '' }
    $content = [System.IO.File]::ReadAllText($configFile)
    $entry=@(Get-TomlRootSettings $content | Where-Object Key -ceq 'sqlite_home' | Select-Object -Last 1)
    if (-not $entry.Count) {return ''}
    $match=[regex]::Match($entry[0].Value,'^(["''])(.*?)\1\s*(?:#.*)?$')
    if (-not $match.Success) {return ''}
    $value=$match.Groups[2].Value
    if ($match.Groups[1].Value -eq '"') {$value=$value.Replace('\\','\')}
    return $value
}

function Get-CachedRootSettings([string]$path) {
    # Read and compare contents on every poll. Timestamp/length alone can miss edits.
    # Keep the writer's strict parsing and stale-save checks independent of this cache.
    $content=[IO.File]::ReadAllText($path)
    if(-not $script:rootSettingsCache){$script:rootSettingsCache=@{}}
    $prior=$script:rootSettingsCache[$path]
    if($prior -and [string]::Equals($prior.Content,$content,[StringComparison]::Ordinal)){return $prior.Entries}
    $entries=@(Get-TomlRootSettings $content)
    if($content.Length -le 262144){
        if($script:rootSettingsCache.Count -ge 32 -and -not $script:rootSettingsCache.ContainsKey($path)){$script:rootSettingsCache.Clear()}
        $script:rootSettingsCache[$path]=@{Content=$content;Entries=$entries}
    }elseif($prior){$script:rootSettingsCache.Remove($path)}
    return $entries
}
if (-not $SqliteHome) {
    $SqliteHome = Get-ConfiguredSqliteHome (Join-Path $CodexHome 'config.toml')
    if (-not $SqliteHome) { $SqliteHome = $env:CODEX_SQLITE_HOME }
    if (-not $SqliteHome) { $SqliteHome = $CodexHome }
}
if (-not [System.IO.Path]::IsPathRooted($SqliteHome)) {
    throw "SQLite state path is relative: $SqliteHome. Pass -SqliteHome with its absolute path."
}
$script:explicitLogDatabase = [bool]$LogDatabase
if (-not $LogDatabase) { $LogDatabase = Find-VersionedDatabase $SqliteHome 'logs' }
if ($RefreshSeconds -lt 1) { throw 'RefreshSeconds must be at least 1.' }
if ($LookbackHours -lt 1 -or $LookbackHours -gt 720) { throw 'LookbackHours must be 1 to 720.' }
if ($MaxRecentRollouts -lt 1 -or $MaxRecentRollouts -gt 256) { throw 'MaxRecentRollouts must be 1 to 256.' }
if ($ReconcileSeconds -lt 5) { throw 'ReconcileSeconds must be at least 5.' }
if ($WarnPercent -lt 1 -or $CriticalPercent -gt 100 -or $WarnPercent -ge $CriticalPercent) {
    throw 'Use WarnPercent below CriticalPercent, both between 1 and 100.'
}
if ($MaxUpdates -lt 0) { throw 'MaxUpdates cannot be negative.' }

$script:rollouts = @{}
$script:version = '3.0 public'
$script:sqlite = $null
$script:lastLogId = 0L
$script:logStatus = 'unavailable'
$script:titleCache = @{}
$script:lastTitleRefresh = [DateTimeOffset]::MinValue
$script:stateDatabase = Find-VersionedDatabase $SqliteHome 'state'
$script:lastDatabaseScan = [DateTimeOffset]::MinValue
$script:sessionIndexPath = Join-Path $CodexHome 'session_index.jsonl'
$script:lastIndexWrite = [DateTime]::MinValue
$script:lastReconcile = [DateTimeOffset]::MinValue
$script:discoveredPaths=$null
$script:discoveryMode = 'initializing'
$script:discoveryWarning = ''
$script:lastFrame = @()
$script:dashboardTop = -1
$script:lastRenderWidth = 0
$script:renderFallback = $false
$script:originalCursorVisible = $true
$script:configPath = Join-Path $CodexHome 'config.toml'
$script:modelCachePath = Join-Path $CodexHome 'models_cache.json'
$script:modelInfoCache = @{}
$script:modelInfoCacheWrite = [DateTime]::MinValue

function Get-TopLevelModel([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    $entry=@(Get-CachedRootSettings $path | Where-Object Key -ceq 'model')
    if($entry.Count){$entry=@($entry[-1])}
    if ($entry.Count -and $entry[0].Value -match '^["'']([^"'']+)["'']\s*(?:#[^\r\n]*)?\s*$') {return $Matches[1]}
    return ''
}

function Get-ModelCatalogInfo([string]$model) {
    if (-not $model -or -not (Test-Path -LiteralPath $script:modelCachePath -PathType Leaf)) { return $null }
    try {
        $write = (Get-Item -LiteralPath $script:modelCachePath).LastWriteTimeUtc
        if ($write -ne $script:modelInfoCacheWrite) {
            $cache = [System.IO.File]::ReadAllText($script:modelCachePath) | ConvertFrom-Json
            $script:modelInfoCache = @{}
            foreach ($entry in $cache.models) {
                if ($entry.slug) { $script:modelInfoCache[[string]$entry.slug] = $entry }
            }
            $script:modelInfoCacheWrite = $write
        }
        $info = $script:modelInfoCache[[string]$model]
        if ($info) {
            $window = if ($info.context_window) { [long]$info.context_window }
                elseif ($info.max_context_window) { [long]$info.max_context_window }
                else { $null }
            return [pscustomobject]@{
                Window = $window
                Maximum = if ($info.max_context_window) { [long]$info.max_context_window } else { $null }
                EffectivePercent = if ($null -ne $info.effective_context_window_percent) {
                    [long]$info.effective_context_window_percent
                } else { $null }
            }
        }
    }
    catch { }
    return $null
}

function Get-ModelWindow([string]$model) {
    $info = Get-ModelCatalogInfo $model
    if ($info) { return $info.Window }
    return $null
}

function Format-Limit($value) {
    if ($null -eq $value) { return 'model default' }
    return ('{0:N0} tokens' -f [long]$value)
}

function ConvertTo-TokenLimit([string]$inputText, $window) {
    $value = $inputText.Trim().ToLowerInvariant()
    if ($value -eq 'default') { return [pscustomobject]@{ IsDefault = $true; Limit = $null } }
    $number = $value -replace '[,_ ]', ''
    if ($number -match '^(\d+(?:\.\d+)?)%$') {
        if ($null -eq $window) { throw 'Enter a number for the context window first. Example: 200k. Or enter Compact at in tokens.' }
        $percent = [decimal]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
        if ($percent -le 0 -or $percent -gt 100) { throw 'Enter a percentage above 0 and at most 100.' }
        $tokens = [long][Math]::Round([decimal]$window * $percent / 100)
    }
    elseif ($number -match '^(\d+(?:\.\d+)?)k$') {
        $tokens = [long][Math]::Round(
            [decimal]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture) * 1000)
    }
    elseif ($number -match '^\d+$') {
        $tokens = 0L
        if (-not [long]::TryParse($number, [ref]$tokens)) { throw 'Number is too large.' }
    }
    else { throw 'Use 180000, 180,000, 180k, 70%, or default.' }
    if ($tokens -lt 1) { throw 'Enter at least 1 token.' }
    return [pscustomobject]@{ IsDefault = $false; Limit = $tokens }
}

# Editor baselines are scoped configuration or observed metadata, never a promise
# that the provider supports the requested capacity. No model-name allowlist.
function Get-ContextConfigPaths([string]$cwd) {
    # Codex loads project layers from a repository root through the chat cwd.
    # Outside a repository, only cwd settings are part of the project scope.
    $paths=New-Object 'Collections.Generic.List[string]'
    if ($cwd -and [IO.Directory]::Exists($cwd)) {
        $directory=[IO.DirectoryInfo]::new([IO.Path]::GetFullPath($cwd))
        $foundRoot=$false
        while ($directory) {
            $paths.Add((Join-Path $directory.FullName '.codex/config.toml'))
            $git=Join-Path $directory.FullName '.git'
            if ([IO.File]::Exists($git) -or [IO.File]::Exists((Join-Path $git 'HEAD'))) { $foundRoot=$true; break }
            $directory=$directory.Parent
        }
        if (-not $foundRoot -and $paths.Count -gt 1) {$paths.RemoveRange(1,$paths.Count-1)}
    }
    if ($script:configPath -and -not $paths.Contains($script:configPath)) {$paths.Add($script:configPath)}
    return $paths.ToArray()
}

function Get-ContextSettingsVersion([string]$path) {
    if (-not [IO.File]::Exists($path)) {return 'missing'}
    $hash=[Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToBase64String($hash.ComputeHash([IO.File]::ReadAllBytes($path))) }
    finally { $hash.Dispose() }
}

function Get-LimitEditorBaseline([string]$path, $card) {
    $saved = Get-TopLevelContextWindow $path
    $compact = Get-TopLevelAutoCompactLimit $path
    $fallbacks=@($script:configPath)
    $folder=Split-Path $path -Parent
    if ((Split-Path $folder -Leaf) -eq '.codex') {
        $fallbacks=@(Get-ContextConfigPaths (Split-Path $folder -Parent) | Where-Object {$_ -ne $path})
    }
    $model = if ($card) { [string]$card.Model } else { Get-TopLevelModel $path }
    if (-not $model) {foreach($fallback in $fallbacks){$model=Get-TopLevelModel $fallback;if($model){break}}}
    $catalog = Get-ModelCatalogInfo $model
    $base = $saved; $source = 'saved window'
    if ($null -eq $base -and $path -ne $script:configPath) {
        foreach($fallback in $fallbacks) {
            $base = Get-TopLevelContextWindow $fallback
            $source = if($fallback -eq $script:configPath){'global fallback'}else{'parent project fallback'}
            if($null -ne $base){break}
        }
    }
    if ($null -eq $base -and $catalog -and $catalog.Window -gt 0) {
        $base = $catalog.Window; $source = 'local model catalog'
    }
    if ($null -eq $base -and $card -and $card.Window -gt 0) {
        $base = $card.Window; $source = 'live usable window'
    }
    return [pscustomobject]@{
        SavedWindow=$saved; SavedCompact=$compact; Base=$base; Source=$source
        Model=$model; Maximum=if ($catalog) { $catalog.Maximum } else { $null }
        Live=if ($card) { $card.Window } else { $null }
    }
}

function ConvertTo-ContextDraft([string]$windowText, [string]$compactText) {
    $w = ConvertTo-TokenLimit $windowText $null
    $c = ConvertTo-TokenLimit $compactText $w.Limit
    if ($null -ne $w.Limit -and $null -ne $c.Limit -and $c.Limit -gt $w.Limit) {
        throw 'Compact at must be at most the entered context window.'
    }
    return [pscustomobject]@{Window=$w.Limit; Compact=$c.Limit}
}

function Get-ScaledContextDraft($base, [int]$multiplier, [string]$windowText, [string]$compactText) {
    if ($null -eq $base -or $base -lt 1) { throw 'No base value is available. Enter a number for the context window first.' }
    if ($multiplier -lt 1 -or $multiplier -gt 3) { throw 'Choose 1x, 2x or 3x.' }
    $scaled = [decimal]$base * $multiplier
    if ($scaled -gt [long]::MaxValue) { throw 'The multiplied window is too large.' }
    $previous = ConvertTo-TokenLimit $windowText $null
    $denominator = if ($null -ne $previous.Limit) { $previous.Limit } else { $base }
    $threshold = ConvertTo-TokenLimit $compactText $denominator
    if ($null -ne $threshold.Limit -and $threshold.Limit -gt $denominator) {
        throw 'Before you multiply the window, Compact at must be at most the current window.'
    }
    $nextCompact = 'default'
    if ($null -ne $threshold.Limit) {
        # Preserve an entered percentage exactly. Numeric thresholds preserve
        # their ratio, so increasing the window does not leave an old threshold.
        $nextCompact = if ($compactText.Trim().EndsWith('%')) { $compactText.Trim() }
            else { [string][long][Math]::Max(1,[Math]::Round([decimal]$threshold.Limit * $scaled / $denominator)) }
    }
    return [pscustomobject]@{Window=[string][long]$scaled; Compact=$nextCompact}
}

function Get-TopLevelNumericSetting([string]$path, [string]$key) {
    if ($key -cnotin @('model_auto_compact_token_limit', 'model_context_window')) { throw 'CTC cannot change this setting.' }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $settings=@(Get-CachedRootSettings $path | Where-Object Key -ceq $key)
    if ($settings.Count -gt 1) { throw "The TOML setting occurs twice: $key." }
    if (-not $settings.Count) { return $null }
    if ($settings[0].Value -notmatch '^\+?(\d(?:_?\d)*)\s*(?:#[^\r\n]*)?\s*$') { throw "The setting must contain a whole number: $key." }
    return [long]($Matches[1].Replace('_',''))
}

function Get-TopLevelAutoCompactScope([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    $entry=@(Get-CachedRootSettings $path | Where-Object Key -ceq 'model_auto_compact_token_limit_scope')
    if($entry.Count){$entry=@($entry[-1])}
    if (-not $entry.Count -or $entry[0].Value -notmatch '^["''](total|body_after_prefix)["'']\s*(?:#.*)?$') {return ''}
    return $Matches[1]
}

function Set-ContextLimits([string]$path, [hashtable]$changes, [string]$ExpectedVersion='') {
    if ($ExpectedVersion -and (Get-ContextSettingsVersion $path) -cne $ExpectedVersion) {
        throw 'The settings file changed. Select Undo to load the new values. Enter your changes again.'
    }
    foreach ($key in $changes.Keys) {
        if ($key -cnotin @('model_auto_compact_token_limit','model_context_window')) { throw 'CTC cannot change this setting.' }
        if ($null -ne $changes[$key]) {
            $tokens=0L
            if ([string]$changes[$key] -notmatch '^\d+$' -or -not [long]::TryParse([string]$changes[$key],[ref]$tokens) -or $tokens -lt 1) {
                throw 'Enter a whole number of at least 1 token.'
            }
        }
    }
    $folder = Split-Path -Path $path -Parent
    if ((Split-Path $folder -Leaf) -eq '.codex' -and -not [IO.Directory]::Exists((Split-Path $folder -Parent))) {throw 'The project folder is unavailable. Restore it before you save limits.'}
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $folder -Force)
    }
    $existed=Test-Path -LiteralPath $path -PathType Leaf
    [byte[]]$originalBytes=@()
    if ($existed) {$originalBytes=[IO.File]::ReadAllBytes($path)}
    if ($ExpectedVersion -and (Get-ContextSettingsVersion $path) -cne $ExpectedVersion) {
        throw 'The settings file changed. Select Undo to load the new values. Enter your changes again.'
    }
    $content = if ($existed) {
        [System.IO.File]::ReadAllText($path)
    } else { '' }
    $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $root=@(Get-TomlRootSettings $content -Strict)
    $updated=$content
    $different=$false
    foreach ($key in $changes.Keys) {
        $entries=@($root|Where-Object Key -ceq $key)
        if ($entries.Count -gt 1) { throw "The TOML setting occurs twice: $key. CTC did not change settings." }
        if ($null -eq $changes[$key]) {if($entries.Count){$different=$true}}
        elseif (-not $entries.Count) {$different=$true}
        else {
            $existing=0L
            if ($entries[0].Value -notmatch '^\+?(\d(?:_?\d)*)\s*(?:#[^\r\n]*)?\s*$' -or
                -not [long]::TryParse($Matches[1].Replace('_',''),[ref]$existing) -or $existing -ne [long]$changes[$key]) {$different=$true}
        }
    }
    if (-not $different) {return $false}
    foreach ($entry in @($root|Where-Object {@($changes.Keys) -ccontains $_.Key}|Sort-Object Start -Descending)) {
        $updated=$updated.Remove($entry.Start,$entry.Length)
    }
    $prefix=''
    foreach ($key in @($changes.Keys|Sort-Object)) { if ($null -ne $changes[$key]) { $prefix+="$key = $($changes[$key])$newline" } }
    $updated=$prefix+$updated
    $null=@(Get-TomlRootSettings $updated -Strict) # Check boundaries again before any write.
    if ($updated -ceq $content) { return $false }
    $temporary="$path.ctc-$([guid]::NewGuid().ToString('N')).tmp"
    $guard=$null
    try {
        [IO.File]::WriteAllText($temporary,$updated,[Text.UTF8Encoding]::new($false))
        if ($existed) {
            # Permit rename, but exclude concurrent writers while checking/replacing.
            $guard=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::Read -bor [IO.FileShare]::Delete))
            [byte[]]$current=[byte[]]::new($guard.Length); $offset=0
            while ($offset -lt $current.Length) { $n=$guard.Read($current,$offset,$current.Length-$offset); if ($n -eq 0) {break}; $offset+=$n }
            if ([Convert]::ToBase64String($current) -cne [Convert]::ToBase64String([byte[]]$originalBytes)) { throw 'The settings file changed. Reload the form. Try again.' }
            $backup="$path.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss-fff')-$([guid]::NewGuid().ToString('N').Substring(0,6))"
            [IO.File]::Replace($temporary,$path,$backup)
        } else { [IO.File]::Move($temporary,$path) }
    } finally {
        if ($guard) {$guard.Dispose()}
        if ([IO.File]::Exists($temporary)) {[IO.File]::Delete($temporary)}
    }
    return $true
}

function Set-TopLevelNumericSetting([string]$path, [string]$key, [Nullable[long]]$limit) {
    return Set-ContextLimits $path @{$key=$limit}
}

function Get-TopLevelAutoCompactLimit([string]$path) {
    return Get-TopLevelNumericSetting $path 'model_auto_compact_token_limit'
}

function Set-TopLevelAutoCompactLimit([string]$path, [Nullable[long]]$limit) {
    return Set-TopLevelNumericSetting $path 'model_auto_compact_token_limit' $limit
}

function Get-TopLevelContextWindow([string]$path) {
    return Get-TopLevelNumericSetting $path 'model_context_window'
}

function Set-TopLevelContextWindow([string]$path, [Nullable[long]]$limit) {
    return Set-TopLevelNumericSetting $path 'model_context_window' $limit
}

function Get-SavedWindowStatus($state) {
    $source = ''
    $requested = $null
    try {
        foreach($candidate in @(Get-ContextConfigPaths $state.Cwd)) {
            $requested = Get-TopLevelContextWindow $candidate
            if ($null -ne $requested) {
                $source=if($candidate -eq $script:configPath){'global'}else{'project'}
                break
            }
        }
    }
    catch { return [pscustomobject]@{ Error = $_.Exception.Message } }
    if ($null -eq $requested) { return $null }
    $catalog = Get-ModelCatalogInfo $state.Model
    $expected = $null
    if ($catalog -and $null -ne $catalog.EffectivePercent) {
        $resolved = [long]$requested
        if ($null -ne $catalog.Maximum) {
            $resolved = [Math]::Min($resolved, [long]$catalog.Maximum)
        }
        $expected = [long][Math]::Floor($resolved * [double]$catalog.EffectivePercent / 100)
    }
    return [pscustomobject]@{ Source = $source; Path = $candidate; Requested = [long]$requested;
        Expected = $expected; Error = ''; Status = $(if ($null -eq $expected) {'Unverified'} elseif ($state.ContextWindow -eq $expected) {'Confirmed'} else {'Pending'});
        Message = $(if ($null -eq $expected) {'CTC cannot verify the usable window for this model.'} elseif ($state.ContextWindow -eq $expected) {'The recorded window matches the saved value.'} else {'Saved settings do not match this chat. After all chats stop, quit Codex. Open Codex again. Resume this chat.'}) }
}



function Get-EventTime($value) {
    if (-not $value) { return [DateTimeOffset]::MinValue }
    try {
        if ($value -is [DateTime]) { return [DateTimeOffset]::new($value) }
        return [DateTimeOffset]::Parse([string]$value)
    }
    catch { return [DateTimeOffset]::MinValue }
}

function New-RolloutState($file) {
    return [pscustomobject]@{
        Path = $file.FullName
        Offset = 0L
        NeedsBackfill = $false
        Partial = ''
        ThreadId = ''
        IsSubagent = $false
        Cwd = ''
        Model = ''
        ServiceTier = ''
        ToolCounts = @{}
        SeenCalls = @{}
        ExecActivity = @{Results=0L;Success=0L;Errors=0L;UnknownStatus=0L;Timed=0L;Seconds=0.0;Spans=0L;SpanSeconds=0.0;Kinds=@{};ScriptKinds=@{};ScriptTools=@{};ReferencesPartial=$false;Shell=@{Results=0L;Success=0L;Errors=0L;Running=0L;Timed=0L;Seconds=0.0;ExitCodes=@{};Partial=$false};SeenShellResults=@{}}
        ActivityPartial = $false
        HasMetadata = $false
        LifecycleKnown = $false
        Originator = ''
        TokenEvents = (New-Object 'Collections.Generic.List[object]')
        Active = $false
        StartedAt = [DateTimeOffset]::MinValue
        LastEventAt = [DateTimeOffset]::MinValue
        LastWriteAt = $file.LastWriteTime
        CreatedAt = $file.CreationTimeUtc
        ContextInput = $null
        ContextWindow = $null
        CachedInput = $null
        OutputTokens = $null
        ThreadTokens = $null
        TotalUsage = $null
        TotalUsageAt = [DateTimeOffset]::MinValue
        UsageAt = [DateTimeOffset]::MinValue
        CompactCount = 0
        LastCompactAt = [DateTimeOffset]::MinValue
        CompactingAt = [DateTimeOffset]::MinValue
        RateLimits = $null
        RateLimitAt = [DateTimeOffset]::MinValue
        ReadError = ''
        ReadErrorAt = [DateTimeOffset]::MinValue
    }
}

function Get-UsageInteger($value) {
    $number=0L
    if ($null -ne $value -and [long]::TryParse([string]$value,[ref]$number) -and $number -ge 0) { return $number }
    return $null
}
function Test-RecordedExecName([string]$Name){return $Name -match '(^|[.])(?:exec|exec_command|write_stdin|wait)$'}
function Get-ScriptToolReferences([string]$Code) {
    # Mask strings and comments. Never execute code. A reference is not proof
    # of execution: loops and conditional branches can change call counts.
    if($Code.Length -gt 65536){return [pscustomobject]@{Tools=@();Partial=$true}}
    if(-not ('CTCActivityScanner' -as [type])){
        try{[void][Reflection.Assembly]::Load([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'ContextWidget.exe')))}catch{}
    }
    $mask=$Code.ToCharArray();$quote='';$comment='';$escaped=$false;$partial=$false
    $native=if('CTCActivityScanner' -as [type]){[CTCActivityScanner]::Mask($Code)}else{$null}
    if($native){$text=$native.Text;$partial=$native.Partial}else{
    for($i=0;$i -lt $mask.Length;$i++){
        $ch=$Code[$i];$next=if($i+1 -lt $mask.Length){$Code[$i+1]}else{[char]0}
        if($comment -eq 'line'){$mask[$i]=' ';if($ch -eq "`n"){$comment=''};continue}
        if($comment -eq 'block'){$mask[$i]=' ';if($ch -eq '*' -and $next -eq '/'){$mask[++$i]=' ';$comment=''};continue}
        if($quote){$mask[$i]=' ';if($escaped){$escaped=$false}elseif($ch -eq '\'){$escaped=$true}elseif($ch -eq $quote){$quote=''};continue}
        if($ch -eq '/' -and $next -in @('/','*')){$comment=if($next -eq '/'){'line'}else{'block'};$mask[$i]=' ';$mask[++$i]=' ';continue}
        if($ch -in @('"',"'",'`')){$quote=[string]$ch;$mask[$i]=' ';if($ch -eq '`'){$partial=$true};continue}
    }
    $text=-join $mask
    }
    $matches=@([regex]::Matches($text,'\btools\.([A-Za-z_][A-Za-z_0-9]{0,99})\s*\('))
    $tools=@($matches|ForEach-Object {$_.Groups[1].Value})
    $commandKinds=@{}
    foreach($call in @($matches|Where-Object {$_.Groups[1].Value -eq 'exec_command'})){
        $tail=$Code.Substring($call.Index,[Math]::Min(8192,$Code.Length-$call.Index))
        $pattern='\bcmd\s*:\s*("(?:[^"\\]|\\.)*")'
        $literal=[regex]::Match($tail,$pattern)
        if($literal.Success -and $text.Substring($call.Index+$literal.Index,3) -eq 'cmd'){
            try{
                $command=$literal.Groups[1].Value|ConvertFrom-Json -ErrorAction Stop
                foreach($kind in @(Get-ExecCommandKinds $command)){$commandKinds[$kind]=1L+[long]$commandKinds[$kind]}
            }catch{$partial=$true}
        }else{$partial=$true}
    }
    if($text -match '\btools\s*\[' -or $quote -or $comment -eq 'block'){$partial=$true}
    return [pscustomobject]@{Tools=$tools;CommandKinds=$commandKinds;Partial=$partial}
}
function Get-ExecCommandKinds([string]$Command) {
    if(-not $Command -or $Command.Length -gt 65536){return @('Other commands')}
    $errors=$null;$tokens=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($Command,[ref]$tokens,[ref]$errors)
    $kinds=@{}
    foreach($node in @($ast.FindAll({param($n)$n -is [Management.Automation.Language.CommandAst]},$true))){
        $name=$node.GetCommandName();if(-not $name){$kinds['Other commands']=$true;continue}
        $leaf=[IO.Path]::GetFileName($name).ToLowerInvariant()
        $kind=switch -Regex ($leaf){
            '^(rg|grep|findstr)(\.exe)?$' {'Search';break}
            '^(get-content|cat|type|get-item|get-childitem|ls|dir|test-path|get-filehash)$' {'Read files';break}
            '^(set-content|add-content|out-file|copy-item|move-item|remove-item|new-item|mkdir|cp|mv|rm)$' {'Change files';break}
            '^git(\.exe)?$' {'Git';break}
            '^(pytest|jest|vitest|test_.+\.ps1)(\.exe)?$' {'Tests';break}
            '^(npm|pnpm|yarn|dotnet|msbuild|cmake|make)(\.exe)?$' {'Build tools';break}
            '^(python[0-9.]*|node|pwsh|powershell)(\.exe)?$|\.(ps1|py|js)$' {'Scripts';break}
            default {'Other commands'}
        }
        $kinds[$kind]=$true
    }
    if(-not $kinds.Count){$kinds['Other commands']=$true}
    return @($kinds.Keys)
}
function Add-ExecRequest($state,$payload,[string]$name,$when,[string]$id) {
    $a=$state.ExecActivity
    $requestArgs=$null;$raw=if($payload.arguments -is [string]){$payload.arguments}elseif($payload.input -is [string]){$payload.input}else{''}
    if($raw.Length -le 65536 -and $raw.TrimStart().StartsWith('{')){try{$requestArgs=$raw|ConvertFrom-Json -ErrorAction Stop}catch{}}
    $kinds=@('Scripts')
    if($name -match '(^|[.])exec_command$'){$kinds=@(Get-ExecCommandKinds ([string]$requestArgs.cmd))}
    elseif($name -match '(^|[.])write_stdin$'){$kinds=@($(if($requestArgs -and [string]$requestArgs.chars){'Process input'}else{'Process checks'}))}
    elseif($name -match '(^|[.])wait$'){$kinds=@('Script checks')}
    else{
        $code=if($requestArgs.code -is [string]){$requestArgs.code}else{$raw}
        $refs=Get-ScriptToolReferences $code
        $a.ReferencesPartial=$a.ReferencesPartial -or $refs.Partial
        foreach($kind in $refs.CommandKinds.Keys){$a.ScriptKinds[$kind]=[long]$a.ScriptKinds[$kind]+[long]$refs.CommandKinds[$kind]}
        foreach($tool in $refs.Tools){
            if($a.ScriptTools.Count -ge 64 -and -not $a.ScriptTools.ContainsKey($tool)){$tool='Other script tools'}
            $a.ScriptTools[$tool]=1L+[long]$a.ScriptTools[$tool]
        }
    }
    foreach($kind in $kinds){$a.Kinds[$kind]=1L+[long]$a.Kinds[$kind]}
    # Only safe derived fields survive. Never retain arguments or command text.
    $state.SeenCalls[$id]=@{Exec=$true;At=$when;Completed=$false}
}
function Add-ExecResult($state,$payload,$when) {
    $id=[string]$payload.call_id
    if(-not $id -or -not $state.SeenCalls.ContainsKey($id)){return}
    $call=$state.SeenCalls[$id]
    if($call -isnot [hashtable] -or -not $call.Exec -or $call.Completed){return}
    $call.Completed=$true;$a=$state.ExecActivity;$a.Results++
    if($call.At -ne [DateTimeOffset]::MinValue -and $when -ge $call.At){$a.Spans++;$a.SpanSeconds+=($when-$call.At).TotalSeconds}
    $exit=$null;$seconds=$null
    $output=$payload.output
    $blocks=@()
    if($output -is [array]){$blocks=@($output)}elseif($output -and $output.PSObject.Properties['content']){$blocks=@($output.content)}
    if($blocks.Count){
        $output=if($blocks[0].type -in @('text','input_text','output_text')){$blocks[0].text}else{$null}
        foreach($block in @($blocks|Select-Object -First 64)){
            if($block.type -notin @('text','input_text','output_text') -or $block.text -isnot [string]){continue}
            if($block.text.Length -gt 65536){$a.Shell.Partial=$true;continue}
            if(-not $block.text.TrimStart().StartsWith('{')){continue}
            try{$nested=$block.text|ConvertFrom-Json -ErrorAction Stop}catch{continue}
            # Shell helper records have stable typed metadata. No stdout is kept.
            if([string]$nested.chunk_id -notmatch '^[a-fA-F0-9]{6,32}$' -or -not $nested.PSObject.Properties['wall_time_seconds']){continue}
            $duration=0.0
            if(-not [double]::TryParse([string]$nested.wall_time_seconds,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$duration) -or $duration -lt 0 -or [double]::IsInfinity($duration) -or [double]::IsNaN($duration)){continue}
            if($a.SeenShellResults.ContainsKey([string]$nested.chunk_id)){continue}
            if($a.SeenShellResults.Count -ge 8192){$a.Shell.Partial=$true;continue}
            $code=0L;$hasCode=$null -ne $nested.exit_code -and [long]::TryParse([string]$nested.exit_code,[ref]$code)
            $hasSession=$null -ne $nested.session_id -and [long]::TryParse([string]$nested.session_id,[ref]$code)
            if(-not $hasCode -and -not $hasSession){continue}
            $a.SeenShellResults[[string]$nested.chunk_id]=$true;$a.Shell.Results++;$a.Shell.Timed++;$a.Shell.Seconds+=$duration
            if($hasCode){
                $code=[long]$nested.exit_code
                if($code -eq 0){$a.Shell.Success++}else{$a.Shell.Errors++}
                $key=[string]$code;if($a.Shell.ExitCodes.Count -ge 64 -and -not $a.Shell.ExitCodes.ContainsKey($key)){$key='Other codes'}
                $a.Shell.ExitCodes[$key]=1L+[long]$a.Shell.ExitCodes[$key]
            }else{$a.Shell.Running++}
        }
        if($blocks.Count -gt 64){$a.Shell.Partial=$true}
    }
    # Only parse a bounded metadata header. Final output and command stdout
    # must not supply status or timing values.
    if($output -is [string]){
        $header=$output.Substring(0,[Math]::Min(1024,$output.Length))
        $cut=[regex]::Match($header,'(?m)^(?:Final output:|Output:)');if($cut.Success){$header=$header.Substring(0,$cut.Index)}
        if($header -match '(?m)^Process exited with code (-?\d+)\s*$'){$exit=[long]$Matches[1]}
        elseif($header -match '^Script completed\s*(?:\r?\n|$)'){$exit=0L}
        elseif($header -match '^Script (?:failed|error)\b'){$exit=1L}
        if($header -match '(?m)^Wall (?:time|time_seconds):\s*([0-9]+(?:\.[0-9]+)?)\s*(?:seconds)?\s*$'){$seconds=[double]::Parse($Matches[1],[Globalization.CultureInfo]::InvariantCulture)}
        if($output.Length -le 65536 -and $output.TrimStart().StartsWith('{')){try{$output=$output|ConvertFrom-Json -ErrorAction Stop}catch{$output=$null}}
        else{$output=$null}
    }
    if($output -and $output -isnot [string]){
        $value=$output.exit_code;$parsed=0L
        if($null -ne $value -and [long]::TryParse([string]$value,[ref]$parsed)){$exit=$parsed}
        $value=$output.wall_time_seconds;$parsedSeconds=0.0
        if($null -ne $value -and [double]::TryParse([string]$value,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$parsedSeconds) -and $parsedSeconds -ge 0 -and -not [double]::IsInfinity($parsedSeconds)){$seconds=$parsedSeconds}
    }
    if($null -eq $exit){$a.UnknownStatus++}elseif($exit -eq 0){$a.Success++}else{$a.Errors++}
    if($null -ne $seconds -and $seconds -ge 0){$a.Timed++;$a.Seconds+=$seconds}
}
function Get-JsonStringPrefix([string]$Line,[string]$Key,[int]$Limit=4096) {
    $match=[regex]::Match($Line,'"'+[regex]::Escape($Key)+'"\s*:\s*"')
    if(-not $match.Success){return $null}
    $start=$match.Index+$match.Length;$end=$start
    while($end -lt $Line.Length -and $end-$start -lt $Limit){
        if($Line[$end] -eq '"'){break}
        if($Line[$end] -eq '\'){
            $step=if($end+1 -lt $Line.Length -and $Line[$end+1] -eq 'u'){6}else{2}
            if($end+$step -gt $Line.Length -or $end+$step-$start -gt $Limit){break}
            $end+=$step
        }else{$end++}
    }
    try{return (('"'+$Line.Substring($start,$end-$start)+'"')|ConvertFrom-Json -ErrorAction Stop)}catch{return $null}
}
function Read-RolloutLine($state, [string]$line) {
    # Borrowed method from Codex Monitor HUD: reject irrelevant records before JSON parsing.
    if ($line -notmatch '"type"\s*:\s*"(session_meta|turn_context|event_msg|token_usage_record|compacted|response_item)"') { return }
    if ($line -match '"type"\s*:\s*"response_item"' -and $line -notmatch '"type"\s*:\s*"(function_call|custom_tool_call|web_search_call|function_call_output|custom_tool_call_output)"') {return}
    if($line -match '"type"\s*:\s*"(?:function_call_output|custom_tool_call_output)"'){
        $id=Get-JsonStringPrefix $line 'call_id' 512
        if(-not $id -or -not $state.SeenCalls.ContainsKey($id) -or $state.SeenCalls[$id] -isnot [hashtable] -or -not $state.SeenCalls[$id].Exec){return}
        if($line.Length -gt 128KB){
            # Large stdout must not delay live monitoring or allocate another
            # full copy. Only a metadata prefix is needed for status and time.
            $prefix=Get-JsonStringPrefix $line 'output'
            if($null -eq $prefix -and $line -match '"output"\s*:\s*\['){$prefix=@([pscustomobject]@{type='text';text=(Get-JsonStringPrefix $line 'text')});$state.ExecActivity.Shell.Partial=$true}
            $payload=[pscustomobject]@{call_id=$id;output=$prefix}
            $when=Get-EventTime (Get-JsonStringPrefix $line 'timestamp' 128)
            Add-ExecResult $state $payload $when
            if($when -gt $state.LastEventAt){$state.LastEventAt=$when}
            return
        }
    }
    # Most event messages are prose/tool progress. Keep their timestamp without
    # allocating a full PowerShell JSON object for each historical message.
    if ($line -match '"type"\s*:\s*"event_msg"' -and
        $line -notmatch '"type"\s*:\s*"(task_started|task_complete|turn_aborted|token_count)"') {
        if ($line -match '^\s*\{\s*"timestamp"\s*:\s*"([^"]+)"') {
            $eventAt=Get-EventTime $Matches[1]
            if ($eventAt -gt $state.LastEventAt) {$state.LastEventAt=$eventAt}
        } else {
            # Preserve reordered JSON compatibility. Normal Codex records put
            # timestamp first; uncommon layouts take the conservative path.
            try {$progress=$line|ConvertFrom-Json -ErrorAction Stop;$eventAt=Get-EventTime $progress.timestamp;if($eventAt -gt $state.LastEventAt){$state.LastEventAt=$eventAt}}catch{}
        }
        return
    }
    try { $record = $line | ConvertFrom-Json -ErrorAction Stop }
    catch { return }
    $payload = $record.payload
    $when = Get-EventTime $record.timestamp
    if ($when -gt $state.LastEventAt) { $state.LastEventAt = $when }

    switch ($record.type) {
        'response_item' {
            if($payload.type -in @('function_call_output','custom_tool_call_output')){Add-ExecResult $state $payload $when;return}
            if ($payload.type -notin @('function_call','custom_tool_call','web_search_call')) {return}
            $id=if ($payload.call_id) {[string]$payload.call_id} elseif ($payload.id) {[string]$payload.id} else {''}
            if (-not $id -or $id.Length -gt 256) {$state.ActivityPartial=$true;return}
            if ($state.SeenCalls.ContainsKey($id)) {return}
            if ($state.SeenCalls.Count -ge 8192) {$state.ActivityPartial=$true;return}
            $state.SeenCalls[$id]=$true
            $name=if ($payload.name) {[string]$payload.name} else {[string]$payload.type}
            $name=($name -replace '[\x00-\x1f]',' ').Trim()
            if ($name.Length -gt 100) {$name=$name.Substring(0,100)}
            if ($state.ToolCounts.Count -ge 64 -and -not $state.ToolCounts.ContainsKey($name)) {$name='Other tools'}
            $state.ToolCounts[$name]=1+[long]$state.ToolCounts[$name]
            if(Test-RecordedExecName $name){Add-ExecRequest $state $payload $name $when $id}
        }
        'session_meta' {
            $state.HasMetadata=$true
            if ($payload.originator -is [string]) {$state.Originator=([string]$payload.originator).Substring(0,[Math]::Min(100,$payload.originator.Length))}
            if ($payload.id) { $state.ThreadId = [string]$payload.id; if (-not $script:titleCache.ContainsKey($state.ThreadId)) {$script:lastIndexWrite=[DateTime]::MinValue} }
            if ($payload.cwd) { $state.Cwd = [string]$payload.cwd }
            if ($payload.source -and $payload.source -isnot [string] -and
                $payload.source.PSObject.Properties['subagent']) { $state.IsSubagent = $true }
        }
        'turn_context' {
            if ($payload.model) { $state.Model = [string]$payload.model }
            $state.ServiceTier=[string]$payload.service_tier
            if ($payload.cwd) { $state.Cwd = [string]$payload.cwd }
        }
        'event_msg' {
            switch ($payload.type) {
                'task_started' {
                    $state.LifecycleKnown = $true
                    $state.Active = $true
                    $state.StartedAt = $when
                    $state.CompactingAt = [DateTimeOffset]::MinValue
                    if ((Get-UsageInteger $payload.model_context_window) -gt 0) {
                        $nextWindow=Get-UsageInteger $payload.model_context_window
                        if ($state.ContextWindow -ne $nextWindow) { $state.ContextInput=$null; $state.CachedInput=$null; $state.OutputTokens=$null; $state.UsageAt=[DateTimeOffset]::MinValue }
                        $state.ContextWindow=$nextWindow
                    }
                }
                'task_complete' { $state.LifecycleKnown = $true; $state.Active = $false; $state.CompactingAt = [DateTimeOffset]::MinValue }
                'turn_aborted' { $state.LifecycleKnown = $true; $state.Active = $false; $state.CompactingAt = [DateTimeOffset]::MinValue }
                'token_count' {
                    $info = $payload.info
                    if ($payload.rate_limits) {
                        $state.RateLimits = $payload.rate_limits
                        $state.RateLimitAt = $when
                    }
                    if ($info) {
                        if ((Get-UsageInteger $info.model_context_window) -gt 0) {
                            $nextWindow=Get-UsageInteger $info.model_context_window
                            if ($state.ContextWindow -ne $nextWindow) {$state.ContextInput=$null;$state.CachedInput=$null;$state.OutputTokens=$null;$state.UsageAt=[DateTimeOffset]::MinValue}
                            $state.ContextWindow=$nextWindow
                        }
                        if ($info.last_token_usage) {
                            $state.ContextInput = Get-UsageInteger $info.last_token_usage.input_tokens
                            $state.CachedInput = Get-UsageInteger $info.last_token_usage.cached_input_tokens
                            $state.OutputTokens = Get-UsageInteger $info.last_token_usage.output_tokens
                            $state.UsageAt = $when
                        }
                        if ($null -ne (Get-UsageInteger $info.total_token_usage.total_tokens)) {
                            $u=$info.total_token_usage; $prior=$state.TotalUsage
                            $deltaInput=$null; $deltaCache=$null; $deltaOutput=$null
                            if ($prior -and $null -ne $u.input_tokens -and $null -ne $u.output_tokens -and $null -ne $u.cached_input_tokens -and $null -ne $prior.cached_input_tokens) {
                                $deltaInput=[long]$u.input_tokens-[long]$prior.input_tokens; $deltaCache=[long]$u.cached_input_tokens-[long]$prior.cached_input_tokens; $deltaOutput=[long]$u.output_tokens-[long]$prior.output_tokens
                            }
                            if ($null -ne $deltaInput -and $deltaInput -ge 0 -and $deltaCache -ge 0 -and $deltaCache -le $deltaInput -and $deltaOutput -ge 0 -and ($deltaInput+$deltaOutput) -gt 0) {
                                $state.TokenEvents.Add([pscustomobject]@{Id=$state.ThreadId;At=$when;Model=$state.Model;Tier=$state.ServiceTier;Input=$deltaInput;Cached=$deltaCache;Output=$deltaOutput;RequestInput=$state.ContextInput;Total=[long]$u.total_tokens})
                            } elseif ($null -eq $state.ThreadTokens -or [long]$u.total_tokens -ne $state.ThreadTokens) {
                                $state.TokenEvents.Add([pscustomobject]@{Id=$state.ThreadId;At=$when;Model='';Tier='';Input=$null;Cached=$null;Output=$null;RequestInput=$null;Total=[long]$u.total_tokens})
                            }
                            if ($state.TokenEvents.Count -gt 4096) { $state.TokenEvents.RemoveRange(0,$state.TokenEvents.Count-4096) }
                            $state.ThreadTokens = Get-UsageInteger $info.total_token_usage.total_tokens
                            $state.TotalUsage = [pscustomobject]@{input_tokens=(Get-UsageInteger $info.total_token_usage.input_tokens);cached_input_tokens=(Get-UsageInteger $info.total_token_usage.cached_input_tokens);output_tokens=(Get-UsageInteger $info.total_token_usage.output_tokens);reasoning_output_tokens=(Get-UsageInteger $info.total_token_usage.reasoning_output_tokens)}
                            $state.TotalUsageAt = $when
                        }
                    }
                }
            }
        }
        'token_usage_record' {
            if ($payload.usage -and $when -ge $state.UsageAt) {
                $state.ContextInput = Get-UsageInteger $payload.usage.input_tokens
                $state.CachedInput = Get-UsageInteger $payload.usage.cached_input_tokens
                $state.OutputTokens = Get-UsageInteger $payload.usage.output_tokens
                $state.UsageAt = $when
            }
            if ($null -ne (Get-UsageInteger $payload.thread_token_usage.total_tokens)) {
                $state.ThreadTokens = Get-UsageInteger $payload.thread_token_usage.total_tokens
                $state.TotalUsage = [pscustomobject]@{input_tokens=(Get-UsageInteger $payload.thread_token_usage.input_tokens);cached_input_tokens=(Get-UsageInteger $payload.thread_token_usage.cached_input_tokens);output_tokens=(Get-UsageInteger $payload.thread_token_usage.output_tokens);reasoning_output_tokens=(Get-UsageInteger $payload.thread_token_usage.reasoning_output_tokens)}
                $state.TotalUsageAt = $when
            }
        }
        'compacted' {
            $state.CompactCount++
            $state.LastCompactAt = $when
            $state.CompactingAt = [DateTimeOffset]::MinValue
            # The next token_count record resets last request usage.
            $state.ContextInput = $null
            $state.CachedInput = $null
            $state.OutputTokens = $null
            $state.UsageAt = [DateTimeOffset]::MinValue
        }
    }
}

function Update-Rollout($file, [switch]$QuickStart) {
    $key = $file.FullName
    if (-not $script:rollouts.ContainsKey($key)) {
        $script:rollouts[$key] = New-RolloutState $file
    }
    $state = $script:rollouts[$key]
    if ($state.NeedsBackfill -and -not $QuickStart) {
        $script:rollouts[$key]=New-RolloutState $file
        $state=$script:rollouts[$key]
    }
    if ($file.Length -lt $state.Offset -or $file.CreationTimeUtc -ne $state.CreatedAt) {
        $script:rollouts[$key] = New-RolloutState $file
        $state = $script:rollouts[$key]
    }
    $state.LastWriteAt = $file.LastWriteTime
    if ($file.Length -eq $state.Offset) { return }
    if ($file.Length -eq 0) { return }

    $stream = $null
    $reader = $null
    try {
        $share = [System.IO.FileShare]([int][System.IO.FileShare]::ReadWrite -bor
            [int][System.IO.FileShare]::Delete)
        $stream = New-Object System.IO.FileStream($file.FullName, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read, $share)
        [void]$stream.Seek(-1, [System.IO.SeekOrigin]::End)
        $hasFinalNewline = $stream.ReadByte() -eq 10
        [void]$stream.Seek($state.Offset, [System.IO.SeekOrigin]::Begin)
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8, $false)
        $quick=$QuickStart -and $state.Offset -eq 0 -and $file.Length -gt 256KB
        $latest=@{}; $sequence=0; $compactCount=0; $lastProgressLine=$null
        $firstLine = $true
        while ($null -ne ($line = $reader.ReadLine())) {
            if ($firstLine) {
                $line = $state.Partial + $line
                $state.Partial = ''
                $firstLine = $false
            }
            if ($reader.EndOfStream -and -not $hasFinalNewline) {
                try { $null = ConvertFrom-Json -InputObject $line -ErrorAction Stop }
                catch { $state.Partial = $line; break }
            }
            if ($quick) {
                # Only deserialize the last record of each state-bearing category.
                # Lifecycle records are scanned across the whole file so a long
                # running turn is not mistaken for an idle chat by a tail read.
                $sequence++
                $head=$line.Substring(0,[Math]::Min(512,$line.Length))
                if($head -notmatch '"type"\s*:\s*"(session_meta|turn_context|event_msg|token_usage_record|compacted)"') {
                    # A producer may move the root type after a large payload.
                    # Search the complete line before rejecting that layout.
                    if($line -notmatch '"type"\s*:\s*"(session_meta|turn_context|event_msg|token_usage_record|compacted)"'){continue}
                    $head=$line
                }
                $categories=@()
                if ($head -match '"type"\s*:\s*"(session_meta|turn_context|compacted)"') {
                    $categories=@($Matches[1])
                    if($categories[0] -eq 'compacted'){$compactCount++}
                } elseif ($head -match '"type"\s*:\s*"(event_msg|token_usage_record)"') {
                    $kind=$Matches[1]
                    $lastProgressLine=$line
                    if ($kind -eq 'token_usage_record') {
                        if($line -match '"usage"\s*:\s*\{'){$categories+='recordUsage'}
                        if($line -match '"thread_token_usage"\s*:\s*\{'){$categories+='recordTotal'}
                    } elseif ($line -match '"type"\s*:\s*"task_started"') {$categories=@('start')}
                    elseif ($line -match '"type"\s*:\s*"(task_complete|turn_aborted)"') {$categories=@('end')}
                    elseif ($line -match '"type"\s*:\s*"token_count"') {
                        if($line -match '"last_token_usage"\s*:\s*\{'){$categories+='tokensUsage'}
                        if($line -match '"total_token_usage"\s*:\s*\{'){$categories+='tokensTotal'}
                        if($line -match '"model_context_window"\s*:'){$categories+='tokensWindow'}
                        if($line -match '"rate_limits"\s*:\s*\{'){$categories+='quota'}
                    }
                }
                foreach($category in $categories){$latest[$category]=[pscustomobject]@{Order=$sequence;Line=$line}}
            } else { Read-RolloutLine $state $line }
        }
        if($quick){
            foreach($record in @($latest.Values|Sort-Object Order -Unique)){Read-RolloutLine $state $record.Line}
            $progressAt=[DateTimeOffset]::MinValue
            if($lastProgressLine){try{$progressAt=Get-EventTime (($lastProgressLine|ConvertFrom-Json -ErrorAction Stop).timestamp)}catch{}}
            if($progressAt -gt $state.LastEventAt){$state.LastEventAt=$progressAt}
            $state.CompactCount=$compactCount
            $state.NeedsBackfill=$true
        }
        $state.Offset = $stream.Position
        $state.ReadError = ''
    }
    catch {
        $state.ReadError = $_.Exception.GetType().Name
        $state.ReadErrorAt = [DateTimeOffset]::Now
    }
    finally {
        if ($reader) { $reader.Dispose() }
        elseif ($stream) { $stream.Dispose() }
    }
}

function Invoke-Sqlite([string]$query, [string]$database = $LogDatabase) {
    $script:sqliteQueryFailed = $false
    if (-not $script:sqlite) { return @() }
    try {
        $output = & $script:sqlite -readonly -json $database $query 2>$null
        if ($LASTEXITCODE -ne 0) { $script:sqliteQueryFailed = $true; return @() }
        if (-not $output) { return @() }
        return @(ConvertFrom-Json -InputObject ($output -join "`n") -ErrorAction Stop)
    }
    catch { $script:sqliteQueryFailed = $true; return @() }
}

function Get-RolloutFiles {
    if (-not (Test-Path -LiteralPath $SessionRoot -PathType Container)) {
        $script:discoveryMode = 'no local chat record'
        $script:discoveryWarning = ''
        return @()
    }
    if ($null -ne $script:discoveredPaths -and ([DateTimeOffset]::Now-$script:lastReconcile).TotalSeconds -lt $ReconcileSeconds) {
        $cached=@($script:discoveredPaths)+@($script:rollouts.Values|Where-Object Active|ForEach-Object Path)
        return @($cached|Select-Object -Unique|ForEach-Object {if([IO.File]::Exists($_)){Get-Item -LiteralPath $_ -ErrorAction SilentlyContinue}}|Sort-Object LastWriteTime)
    }
    $cutoff = (Get-Date).AddHours(-$LookbackHours)
    $paths = @{}
    $indexed = $false
    if ($script:sqlite -and $script:stateDatabase -and
        (Test-Path -LiteralPath $script:stateDatabase -PathType Leaf)) {
        # Adapted from Codex Monitor HUD: ask the local thread index for user-task rollout paths.
        $since = ([DateTimeOffset]$cutoff).ToUnixTimeSeconds()
        $query = "SELECT rollout_path FROM threads WHERE archived = 0 AND (thread_source = 'user' OR (thread_source IS NULL AND has_user_event = 1)) AND updated_at >= $since ORDER BY updated_at DESC LIMIT $MaxRecentRollouts;"
        $rows = Invoke-Sqlite $query $script:stateDatabase
        foreach ($row in $rows) {
            $path = [string]$row.rollout_path
            if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) { $paths[$path] = $path }
        }
        $indexed = $paths.Count -gt 0 -and $paths.Count -eq $rows.Count
    }
    $now = [DateTimeOffset]::Now
    if (-not $indexed -and ($now - $script:lastReconcile).TotalSeconds -ge $ReconcileSeconds) {
        # Fallback when the private SQLite schema is missing or temporarily unavailable.
        $recent = @(Get-ChildItem -LiteralPath $SessionRoot -Recurse -File -Filter '*.jsonl' -ErrorAction Stop |
            Where-Object { $_.LastWriteTime -ge $cutoff } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First $MaxRecentRollouts)
        foreach ($file in $recent) { $paths[$file.FullName] = $file.FullName }
        $script:lastReconcile = $now
        $script:discoveryMode = 'folder fallback'
        $script:discoveryWarning = 'The chat index is unavailable. CTC can show background records.'
    }
    elseif ($indexed) {
        $script:discoveryMode = 'thread index'
        $script:discoveryWarning = ''
    }
    $script:discoveredPaths=@($paths.Keys); $script:lastReconcile=$now
    foreach ($state in $script:rollouts.Values) {
        if ($state.Active -and (Test-Path -LiteralPath $state.Path -PathType Leaf)) {
            $paths[$state.Path] = $state.Path
        }
    }
    $files = New-Object 'System.Collections.Generic.List[object]'
    foreach ($path in $paths.Keys) {
        try { [void]$files.Add((Get-Item -LiteralPath $path -ErrorAction Stop)) }
        catch { }
    }
    return @($files.ToArray() | Sort-Object LastWriteTime)
}

function Update-CompactionLog {
    if (-not $script:sqlite) { return }
    # One indexed query gets new signals and the high-water mark.
    $query = "SELECT id, ts, thread_id FROM logs WHERE id > $($script:lastLogId) AND target = 'codex_api::sse::responses' AND feedback_log_body LIKE '%response.compaction.compacting%' UNION ALL SELECT max(id), 0, NULL FROM logs ORDER BY id;"
    $rows = Invoke-Sqlite $query
    if ($script:sqliteQueryFailed) { $script:logStatus = 'completion only (log schema unavailable)'; return }
    $script:logStatus = 'live'
    foreach ($row in $rows) {
        if (-not $row.ts) {
            if ($row.id) { $script:lastLogId = [long]$row.id }
            continue
        }
        $eventTime = [DateTimeOffset]::FromUnixTimeSeconds([long]$row.ts)
        foreach ($state in $script:rollouts.Values) {
            if ($state.ThreadId -eq [string]$row.thread_id -and
                $state.Active -and $eventTime -gt $state.LastCompactAt -and
                $eventTime -ge $state.StartedAt) {
                $state.CompactingAt = $eventTime
            }
        }
    }
}

function Update-Titles {
    if (-not $script:sqlite -or -not $script:stateDatabase -or
        -not (Test-Path -LiteralPath $script:stateDatabase -PathType Leaf)) { return }
    if (([DateTimeOffset]::Now - $script:lastTitleRefresh).TotalSeconds -lt 10) { return }
    $rows = Invoke-Sqlite 'SELECT id, substr(coalesce(name, ''''), 1, 100) AS ui_name, substr(coalesce(title, ''''), 1, 100) AS initial_title FROM threads ORDER BY updated_at DESC LIMIT 100;' $script:stateDatabase
    foreach ($row in $rows) {
        $uiName = ([string]$row.ui_name -replace '[\x00-\x1F\x7F]', ' ').Trim()
        $initial = ([string]$row.initial_title -replace '[\x00-\x1F\x7F]', ' ').Trim()
        $prior=$script:titleCache[[string]$row.id]
        if (-not $uiName -and $prior.UiName) { continue }
        $script:titleCache[[string]$row.id] = [pscustomobject]@{
            UiName = $uiName
            Initial = $initial
            Source = 'database'
        }
    }
    $script:lastTitleRefresh = [DateTimeOffset]::Now
}

function Update-IndexTitles {
    if (-not (Test-Path -LiteralPath $script:sessionIndexPath -PathType Leaf)) { return }
    try {
        $file = Get-Item -LiteralPath $script:sessionIndexPath
        if ($file.LastWriteTimeUtc -eq $script:lastIndexWrite) { return }
        # HUD also uses session_index.jsonl for names. Desktop state names still take precedence.
        foreach ($line in [System.IO.File]::ReadLines($file.FullName, [System.Text.Encoding]::UTF8)) {
            if ($line -notmatch '"thread_name"') { continue }
            try { $entry = ConvertFrom-Json -InputObject $line -ErrorAction Stop }
            catch { continue }
            if (-not $entry.id -or -not $entry.thread_name) { continue }
            $id = [string]$entry.id
            if ($script:titleCache.ContainsKey($id) -and $script:titleCache[$id].Source -eq 'database' -and $script:titleCache[$id].UiName) { continue }
            $name = ([string]$entry.thread_name -replace '[\x00-\x1F\x7F]', ' ').Trim()
            $script:titleCache[$id] = [pscustomobject]@{ UiName = $name; Initial = ''; Source = 'index' }
        }
        $script:lastIndexWrite = $file.LastWriteTimeUtc
    }
    catch { }
}

function Remove-ExpiredRolloutStates {
    # An old rollout's Active flag is not the lifecycle of a resumed chat.
    $latest=@{}
    foreach ($state in $script:rollouts.Values) {
        if ($state.ThreadId -and (-not $latest.ContainsKey($state.ThreadId) -or $state.LastEventAt -gt $latest[$state.ThreadId].LastEventAt)) {$latest[$state.ThreadId]=$state}
    }
    foreach ($state in $script:rollouts.Values) {
        if ($state.ThreadId -and -not [object]::ReferenceEquals($state,$latest[$state.ThreadId])) {$state.Active=$false}
    }
    $cutoff=[DateTimeOffset]::Now.AddHours(-$LookbackHours)
    $inactive=@($script:rollouts.Values | Where-Object {-not $_.Active} | Sort-Object LastWriteAt -Descending)
    $kept=0
    foreach ($state in $inactive) {
        if ($kept -ge $MaxRecentRollouts -or $state.LastWriteAt -lt $cutoff.LocalDateTime -or -not [IO.File]::Exists($state.Path)) {
            $script:rollouts.Remove($state.Path)
        } else { $kept++ }
    }
    $ids=@{};foreach($state in $script:rollouts.Values){if($state.ThreadId){$ids[$state.ThreadId]=$true}}
    foreach($id in @($script:titleCache.Keys)){if(-not $ids.ContainsKey($id)){$script:titleCache.Remove($id)}}
    # The bounded cache may need to reload an index name after eviction/re-discovery.
    if ($inactive.Count -gt $kept) {$script:lastIndexWrite=[DateTime]::MinValue}
}

function Get-DisplayStates {
    # A resumed chat can have several rollout files. Newest rollout wins.
    $byThread = @{}
    foreach ($state in $script:rollouts.Values) {
        if (-not $state.ThreadId -or $state.IsSubagent) { continue }
        if (-not $byThread.ContainsKey($state.ThreadId) -or
            $state.LastEventAt -gt $byThread[$state.ThreadId].LastEventAt) {
            $byThread[$state.ThreadId] = $state
        }
    }
    # Show whichever chat wrote most recently first.
    return @($byThread.Values | Where-Object { $_.Active } | Sort-Object LastEventAt -Descending)
}

function Format-Count($n) {
    if ($null -eq $n) { return '?' }
    return ('{0:N0}' -f [long]$n)
}

function Format-RateWindow($window) {
    if (-not $window -or $null -eq $window.used_percent) { return '' }
    $minutes = [int]$window.window_minutes
    $label = if ($minutes -eq 300) { '5h' }
        elseif ($minutes -eq 10080) { '7d' }
        elseif ($minutes -gt 0 -and $minutes % 1440 -eq 0) { "$(($minutes / 1440))d" }
        elseif ($minutes -gt 0 -and $minutes % 60 -eq 0) { "$(($minutes / 60))h" }
        else { "${minutes}m" }
    $remaining = [Math]::Max(0, [Math]::Min(100, 100 - [double]$window.used_percent))
    $reset = ''
    if ($window.resets_at) {
        try { $reset = ' reset ' + [DateTimeOffset]::FromUnixTimeSeconds([long]$window.resets_at).ToLocalTime().ToString('MMM d HH:mm') }
        catch { }
    }
    return ('{0} {1:N0}% left{2}' -f $label, $remaining, $reset)
}

function Get-QuotaLine {
    # Select-Object without -Property mutates persistent objects' type names in PS 5.1.
    # Repeated selection creates ever-larger ETS cache keys. Index a sorted array instead.
    $latestRows = @($script:rollouts.Values | Where-Object { $_.RateLimits } | Sort-Object RateLimitAt -Descending)
    if (-not $latestRows.Count) { return '' }
    $latest=$latestRows[0]
    $parts = @()
    foreach ($window in @($latest.RateLimits.primary, $latest.RateLimits.secondary)) {
        $part = Format-RateWindow $window
        if ($part) { $parts += $part }
    }
    if ($parts.Count -eq 0) { return '' }
    return 'Quota observed ' + $latest.RateLimitAt.ToLocalTime().ToString('HH:mm') + ': ' + ($parts -join ' | ')
}







function Refresh-DatabasePaths {
    $now = [DateTimeOffset]::Now
    if (($now - $script:lastDatabaseScan).TotalSeconds -lt 60) { return }
    $script:lastDatabaseScan = $now
    $newState = Find-VersionedDatabase $SqliteHome 'state'
    if ($newState -ne $script:stateDatabase) {
        $script:stateDatabase = $newState
        $script:lastTitleRefresh = [DateTimeOffset]::MinValue
    }
    if (-not $script:explicitLogDatabase) {
        $newLog = Find-VersionedDatabase $SqliteHome 'logs'
        if ($newLog -ne $LogDatabase) {
            $script:LogDatabase = $newLog
            $script:lastLogId = 0L
        }
    }
    $sqliteCommand = Get-Command sqlite3.exe -ErrorAction SilentlyContinue
    $script:sqlite = if ($sqliteCommand) { $sqliteCommand.Source } else { $null }
    $script:logStatus = if (-not $script:sqlite) { 'completion only (sqlite3.exe unavailable)' }
        elseif (-not $LogDatabase -or -not (Test-Path -LiteralPath $LogDatabase -PathType Leaf)) {
            'completion only (log database unavailable)'
        }
        else { 'live' }
}
