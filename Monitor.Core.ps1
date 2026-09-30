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
            } elseif (-not $multi -and $ch -eq "`n") { throw 'Unclosed TOML string. No settings were changed.' }
            continue
        }
        elseif ($ch -eq '#') { $comment=$true; continue }
        elseif ($ch -eq '"' -or $ch -eq "'") {
            $quote=[string]$ch
            $multi=$i+2 -lt $content.Length -and $content.Substring($i,3) -eq ($quote*3)
            if ($multi) { $i+=2 }; continue
        }
        elseif ($ch -eq '[' -or $ch -eq '{') { $depth++ }
        elseif ($ch -eq ']' -or $ch -eq '}') { $depth--; if ($depth -lt 0) { throw 'Unbalanced TOML. No settings were changed.' } }
        if ($ch -eq "`n" -and $depth -eq 0) {
            [pscustomobject]@{Start=$start;Length=$i+1-$start;Text=$content.Substring($start,$i+1-$start)}
            $start=$i+1
        }
    }
    if ($quote -or $depth -ne 0) { throw 'Incomplete TOML. No settings were changed.' }
    if ($start -lt $content.Length) { [pscustomobject]@{Start=$start;Length=$content.Length-$start;Text=$content.Substring($start)} }
}

function Get-TomlRootSettings([string]$content, [switch]$Strict) {
    foreach ($statement in @(Get-TomlStatements $content)) {
        $text=$statement.Text.TrimStart()
        if ($text.StartsWith('[')) { break }
        if (-not $text -or $text.StartsWith('#')) { continue }
        $match=[regex]::Match($text,'^(?:([A-Za-z0-9_-]+)|"([^"\\]+)"|''([^'']+)'')\s*=\s*([\s\S]*)$')
        if (-not $match.Success) { if ($Strict) { throw 'Unsupported TOML root key syntax. Edit this file in Codex; no settings were changed.' }; continue }
        $key=if ($match.Groups[1].Success) {$match.Groups[1].Value} elseif ($match.Groups[2].Success) {$match.Groups[2].Value} else {$match.Groups[3].Value}
        [pscustomobject]@{Key=$key;Value=$match.Groups[4].Value;Start=$statement.Start;Length=$statement.Length}
    }
}

function Get-ConfiguredSqliteHome([string]$configFile) {
    if (-not (Test-Path -LiteralPath $configFile -PathType Leaf)) { return '' }
    $content = [System.IO.File]::ReadAllText($configFile)
    $entry=@(Get-TomlRootSettings $content | Where-Object Key -eq 'sqlite_home' | Select-Object -Last 1)
    if (-not $entry.Count) {return ''}
    $match=[regex]::Match($entry[0].Value,'^(["''])(.*?)\1\s*(?:#.*)?$')
    if (-not $match.Success) {return ''}
    $value=$match.Groups[2].Value
    if ($match.Groups[1].Value -eq '"') {$value=$value.Replace('\\','\')}
    return $value
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
    $content = [System.IO.File]::ReadAllText($path)
    $section = [regex]::Match($content, '(?m)^\s*\[')
    if ($section.Success) { $content = $content.Substring(0, $section.Index) }
    $match = [regex]::Match($content, '(?m)^\s*model\s*=\s*["'']([^"'']+)["'']')
    if ($match.Success) { return $match.Groups[1].Value }
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
        if ($null -eq $window) { throw 'Enter a numeric context window first (e.g. 200k), or enter Compact at in tokens.' }
        $percent = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
        if ($percent -le 0 -or $percent -gt 100) { throw 'Percent must be above 0 and at most 100.' }
        $tokens = [long][Math]::Round([double]$window * $percent / 100)
    }
    elseif ($number -match '^(\d+(?:\.\d+)?)k$') {
        $tokens = [long][Math]::Round(
            [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture) * 1000)
    }
    elseif ($number -match '^\d+$') {
        $tokens = 0L
        if (-not [long]::TryParse($number, [ref]$tokens)) { throw 'Number is too large.' }
    }
    else { throw 'Use 180000, 180,000, 180k, 70%, or default.' }
    if ($tokens -lt 1) { throw 'Limit must be at least 1 token.' }
    return [pscustomobject]@{ IsDefault = $false; Limit = $tokens }
}

function Get-TopLevelNumericSetting([string]$path, [string]$key) {
    if ($key -notin @('model_auto_compact_token_limit', 'model_context_window')) { throw 'Unsupported setting.' }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $content = [System.IO.File]::ReadAllText($path)
    $settings=@(Get-TomlRootSettings $content | Where-Object Key -eq $key)
    if ($settings.Count -gt 1) { throw "Duplicate TOML setting: $key" }
    if (-not $settings.Count) { return $null }
    if ($settings[0].Value -notmatch '^\+?(\d(?:_?\d)*)\s*(?:#[^\r\n]*)?\s*$') { throw "Invalid numeric setting: $key" }
    return [long]($Matches[1].Replace('_',''))
}

function Get-TopLevelAutoCompactScope([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    $content = [System.IO.File]::ReadAllText($path)
    $entry=@(Get-TomlRootSettings $content | Where-Object Key -eq 'model_auto_compact_token_limit_scope' | Select-Object -Last 1)
    if (-not $entry.Count -or $entry[0].Value -notmatch '^["''](total|body_after_prefix)["'']\s*(?:#.*)?$') {return ''}
    return $Matches[1]
}

function Set-ContextLimits([string]$path, [hashtable]$changes) {
    foreach ($key in $changes.Keys) {
        if ($key -notin @('model_auto_compact_token_limit','model_context_window')) { throw 'Unsupported setting.' }
        if ($null -ne $changes[$key] -and [long]$changes[$key] -lt 1) { throw 'Limit must be at least 1 token.' }
    }
    $folder = Split-Path -Path $path -Parent
    if ((Split-Path $folder -Leaf) -eq '.codex' -and -not [IO.Directory]::Exists((Split-Path $folder -Parent))) {throw 'Project folder is unavailable. Restore it before saving limits.'}
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $folder -Force)
    }
    $existed=Test-Path -LiteralPath $path -PathType Leaf
    $originalBytes=if ($existed) {[IO.File]::ReadAllBytes($path)} else {@()}
    $content = if ($existed) {
        [System.IO.File]::ReadAllText($path)
    } else { '' }
    $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $root=@(Get-TomlRootSettings $content -Strict)
    $updated=$content
    foreach ($key in $changes.Keys) {
        if (@($root|Where-Object Key -eq $key).Count -gt 1) { throw "Duplicate TOML setting: $key. No settings were changed." }
    }
    foreach ($entry in @($root|Where-Object {$changes.ContainsKey($_.Key)}|Sort-Object Start -Descending)) {
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
            $current=New-Object byte[] $guard.Length; $offset=0
            while ($offset -lt $current.Length) { $n=$guard.Read($current,$offset,$current.Length-$offset); if ($n -eq 0) {break}; $offset+=$n }
            if ([Convert]::ToBase64String($current) -cne [Convert]::ToBase64String([byte[]]$originalBytes)) { throw 'Configuration changed during editing. Reload the form and retry.' }
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
        if ($state.Cwd) {
            $projectConfig = Join-Path (Join-Path $state.Cwd '.codex') 'config.toml'
            $requested = Get-TopLevelContextWindow $projectConfig
            if ($null -ne $requested) { $source = 'project' }
        }
        if ($null -eq $requested) {
            $requested = Get-TopLevelContextWindow $script:configPath
            if ($null -ne $requested) { $source = 'global' }
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
    return [pscustomobject]@{ Source = $source; Requested = [long]$requested;
        Expected = $expected; Error = '' }
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
function Read-RolloutLine($state, [string]$line) {
    # Borrowed method from Codex Monitor HUD: reject irrelevant records before JSON parsing.
    if ($line -notmatch '"type"\s*:\s*"(session_meta|turn_context|event_msg|token_usage_record|compacted)"') { return }
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
        'session_meta' {
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
                    $state.Active = $true
                    $state.StartedAt = $when
                    $state.CompactingAt = [DateTimeOffset]::MinValue
                    if ((Get-UsageInteger $payload.model_context_window) -gt 0) {
                        $nextWindow=Get-UsageInteger $payload.model_context_window
                        if ($state.ContextWindow -ne $nextWindow) { $state.ContextInput=$null; $state.CachedInput=$null; $state.OutputTokens=$null; $state.UsageAt=[DateTimeOffset]::MinValue }
                        $state.ContextWindow=$nextWindow
                    }
                }
                'task_complete' { $state.Active = $false; $state.CompactingAt = [DateTimeOffset]::MinValue }
                'turn_aborted' { $state.Active = $false; $state.CompactingAt = [DateTimeOffset]::MinValue }
                'token_count' {
                    $info = $payload.info
                    if ($payload.rate_limits) {
                        $state.RateLimits = $payload.rate_limits
                        $state.RateLimitAt = $when
                    }
                    if ($info) {
                        if ((Get-UsageInteger $info.model_context_window) -gt 0) { $state.ContextWindow = Get-UsageInteger $info.model_context_window }
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
        $script:discoveryMode = 'waiting for first local task'
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
        $script:discoveryWarning = 'thread index unavailable; background files may appear'
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
    $latest = $script:rollouts.Values | Where-Object { $_.RateLimits } |
        Sort-Object RateLimitAt -Descending | Select-Object -First 1
    if (-not $latest) { return '' }
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
