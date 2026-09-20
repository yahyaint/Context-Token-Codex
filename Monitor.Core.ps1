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
function Get-ConfiguredSqliteHome([string]$configFile) {
    if (-not (Test-Path -LiteralPath $configFile -PathType Leaf)) { return '' }
    $content = [System.IO.File]::ReadAllText($configFile)
    $section = [regex]::Match($content, '(?m)^\s*\[')
    if ($section.Success) { $content = $content.Substring(0, $section.Index) }
    $matches = [regex]::Matches($content,
        '(?m)^\s*sqlite_home\s*=\s*(["''])(.*?)\1\s*(?:#.*)?$')
    if ($matches.Count -eq 0) { return '' }
    $match = $matches[$matches.Count - 1]
    $value = $match.Groups[2].Value
    if ($match.Groups[1].Value -eq '"') { $value = $value.Replace('\\', '\') }
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
        if ($null -eq $window) { throw 'Percent needs a known model window. Enter a token count instead.' }
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
    $section = [regex]::Match($content, '(?m)^\s*\[')
    if ($section.Success) { $content = $content.Substring(0, $section.Index) }
    $matches = [regex]::Matches($content, '(?m)^\s*' + $key + '\s*=\s*(\d+)\s*(?:#.*)?$')
    if ($matches.Count -eq 0) { return $null }
    return [long]$matches[$matches.Count - 1].Groups[1].Value
}

function Get-TopLevelAutoCompactScope([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    $content = [System.IO.File]::ReadAllText($path)
    $section = [regex]::Match($content, '(?m)^\s*\[')
    if ($section.Success) { $content = $content.Substring(0, $section.Index) }
    $matches = [regex]::Matches($content,
        '(?m)^\s*model_auto_compact_token_limit_scope\s*=\s*["''](total|body_after_prefix)["'']\s*(?:#.*)?$')
    if ($matches.Count -eq 0) { return '' }
    return $matches[$matches.Count - 1].Groups[1].Value
}

function Set-TopLevelNumericSetting([string]$path, [string]$key, [Nullable[long]]$limit) {
    if ($key -notin @('model_auto_compact_token_limit', 'model_context_window')) { throw 'Unsupported setting.' }
    $folder = Split-Path -Path $path -Parent
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $folder -Force)
    }
    $content = if (Test-Path -LiteralPath $path -PathType Leaf) {
        [System.IO.File]::ReadAllText($path)
    } else { '' }
    $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $section = [regex]::Match($content, '(?m)^\s*\[')
    $head = if ($section.Success) { $content.Substring(0, $section.Index) } else { $content }
    $tail = if ($section.Success) { $content.Substring($section.Index) } else { '' }
    $head = [regex]::Replace($head, '(?m)^\s*' + $key + '\s*=.*(?:\r?\n|$)', '')
    if ($null -ne $limit) {
        if ($head.Length -gt 0 -and -not $head.EndsWith("`n")) { $head += $newline }
        $head += "$key = $limit$newline"
    }
    $updated = $head + $tail
    if ($updated -ceq $content) { return $false }
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $backup = "$path.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss-fff')-$([guid]::NewGuid().ToString('N').Substring(0, 6))"
        Copy-Item -LiteralPath $path -Destination $backup -ErrorAction Stop
    }
    [System.IO.File]::WriteAllText($path, $updated, [System.Text.UTF8Encoding]::new($false))
    return $true
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
        Partial = ''
        ThreadId = ''
        IsSubagent = $false
        Cwd = ''
        Model = ''
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
    try { $record = $line | ConvertFrom-Json -ErrorAction Stop }
    catch { return }
    $payload = $record.payload
    $when = Get-EventTime $record.timestamp
    if ($when -gt $state.LastEventAt) { $state.LastEventAt = $when }

    switch ($record.type) {
        'session_meta' {
            if ($payload.id) { $state.ThreadId = [string]$payload.id }
            if ($payload.cwd) { $state.Cwd = [string]$payload.cwd }
            if ($payload.source -and $payload.source -isnot [string] -and
                $payload.source.PSObject.Properties['subagent']) { $state.IsSubagent = $true }
        }
        'turn_context' {
            if ($payload.model) { $state.Model = [string]$payload.model }
            if ($payload.cwd) { $state.Cwd = [string]$payload.cwd }
        }
        'event_msg' {
            switch ($payload.type) {
                'task_started' {
                    $state.Active = $true
                    $state.StartedAt = $when
                    $state.CompactingAt = [DateTimeOffset]::MinValue
                    if ((Get-UsageInteger $payload.model_context_window) -gt 0) {
                        $state.ContextWindow = Get-UsageInteger $payload.model_context_window
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

function Update-Rollout($file) {
    $key = $file.FullName
    if (-not $script:rollouts.ContainsKey($key)) {
        $script:rollouts[$key] = New-RolloutState $file
    }
    $state = $script:rollouts[$key]
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
            Read-RolloutLine $state $line
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
        $indexed = $rows.Count -gt 0
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
