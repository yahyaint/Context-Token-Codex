# SPDX-License-Identifier: MIT
# One lightweight watcher per Windows user; never reads task contents.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Monitor.Data.ps1')
$mutex=New-Object Threading.Mutex($false, ('Local\CodexContextWatcher-'+[Environment]::UserName))
$owned=$false
try { $owned=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned=$true }
if (-not $owned) { $mutex.Dispose(); exit }
$stop=New-Object Threading.EventWaitHandle($false,[Threading.EventResetMode]::ManualReset,('Local\CodexContextWatcherStop-'+[Environment]::UserName))
$stop.Reset() | Out-Null
$previous=@()
try {
    while ($true) {
        $path=Join-Path $env:LOCALAPPDATA 'CodexContextMonitor\overlay.json'
        if (-not (Test-Path -LiteralPath $path)) { break }
        try { $prefs=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { Start-Sleep -Seconds 5; continue }
        if (-not $prefs.AutoOpen) { break }
        try {
            $current=@(Get-TargetAppInstances $prefs.Target)
            if (@(Get-NewAppInstances $current $previous).Count -gt 0) {
                Start-Process -FilePath (Join-Path $PSScriptRoot 'ContextWidget.exe') -WindowStyle Hidden -ErrorAction Stop
            }
            $previous=$current
        } catch {
            # Retry transient launch/detection failures. Do not lose the startup watcher.
            $folder=Join-Path $env:LOCALAPPDATA 'CodexContextMonitor'
            try { [IO.File]::WriteAllText((Join-Path $folder 'watcher-error.txt'),([DateTimeOffset]::Now.ToString('o')+" Launch/detection failed; retrying.")) } catch {}
        }
        if ($stop.WaitOne(5000)) { break }
    }
} finally { $stop.Dispose(); if ($owned) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
