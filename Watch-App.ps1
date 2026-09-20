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
$wasRunning=$false
try {
    while ($true) {
        $path=Join-Path $env:LOCALAPPDATA 'CodexContextMonitor\overlay.json'
        if (-not (Test-Path -LiteralPath $path)) { break }
        try { $prefs=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { Start-Sleep -Seconds 5; continue }
        if (-not $prefs.AutoOpen) { break }
        $running=Test-TargetApp $prefs.Target
        if ($running -and -not $wasRunning) {
            Start-Process -FilePath wscript.exe -WindowStyle Hidden -ArgumentList ('"'+(Join-Path $PSScriptRoot 'Open-Overlay.vbs')+'"')
        }
        $wasRunning=$running
        if ($stop.WaitOne(5000)) { break }
    }
} finally { $stop.Dispose(); if ($owned) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
