# SPDX-License-Identifier: MIT
param([string]$CodexHome='', [string]$StatusPath='', [switch]$Now,[string]$TestRoot='',[string]$TestExecutable='',[string]$RequestExpiresAt='',[string]$DiagnosticReport='')
$ErrorActionPreference='Stop'
if(-not $CodexHome){$CodexHome=if($env:CODEX_HOME){$env:CODEX_HOME}else{Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex'}}
if(-not $StatusPath){$StatusPath=Join-Path $env:LOCALAPPDATA 'CodexContextMonitor/restart.json'}
. (Join-Path $PSScriptRoot 'Restart.Core.ps1')
$testMode=[bool]$TestRoot
if($testMode){
    $prefix=[IO.Path]::GetFullPath($TestRoot).TrimEnd('\')+'\'
    if(-not [IO.File]::Exists((Join-Path $TestRoot '.restart-test-fixture'))){throw 'Restart test needs a marked fixture.'}
    foreach($testPath in @($CodexHome,$StatusPath,$TestExecutable)){
        if(-not [IO.Path]::GetFullPath($testPath).StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Restart test paths must stay in the fixture.'}
    }
    if([IO.Path]::GetFileName($TestExecutable) -ne 'CTCTestCodex.exe'){throw 'Restart test needs the fixture executable.'}
}
function Get-RestartDesktopProcesses {
    if($testMode){return @(Get-Process -Name CTCTestCodex -ErrorAction SilentlyContinue|Where-Object {$_.Path -eq $TestExecutable})}
    return @(Select-CodexDesktopProcesses @(Get-Process -ErrorAction SilentlyContinue))
}
$mutex=New-Object Threading.Mutex($false,('Local\CTC-Restart-'+$(if($testMode){'Test-'+$PID}else{[Environment]::UserName})))
$owned=$false
try {
    try{$owned=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
    if(-not $owned){exit}
    . (Join-Path $PSScriptRoot 'Monitor.Core.ps1') -CodexHome $CodexHome -LookbackHours 168 -MaxRecentRollouts 256 -ReconcileSeconds 5
    . (Join-Path $PSScriptRoot 'Monitor.Data.ps1')
    # Scan user and agent records through the folder path for restart checks.
    $script:sqlite=$null; $script:stateDatabase=$null
    $deadline=if($RequestExpiresAt){([DateTimeOffset]::Parse($RequestExpiresAt)).UtcDateTime}else{[DateTime]::UtcNow.AddHours(24)};$idleSince=$null
    Write-RestartStatus $StatusPath 'Waiting' 'CTC waits for running chats to stop.' ([DateTimeOffset]$deadline).ToString('o')
    while([DateTime]::UtcNow -lt $deadline){
        try{$request=[IO.File]::ReadAllText($StatusPath)|ConvertFrom-Json;if($request.Status -eq 'Cancelled'){exit}}catch{}
        $snapshot=Get-MonitorSnapshot
        $gate=Get-RestartReadiness @($script:rollouts.Values) 256
        if($DiagnosticReport){
            [void][IO.Directory]::CreateDirectory((Split-Path ([IO.Path]::GetFullPath($DiagnosticReport)) -Parent))
            $metrics=@{At=[DateTimeOffset]::UtcNow.ToString('o');PID=$PID;Ready=$gate.Ready;States=$script:rollouts.Count;TypeNamesMax=($script:rollouts.Values|ForEach-Object {$_.PSTypeNames.Count}|Measure-Object -Maximum).Maximum;ManagedMiB=[GC]::GetTotalMemory($false)/1MB;WorkingMiB=[Diagnostics.Process]::GetCurrentProcess().WorkingSet64/1MB;ExpiresAt=([DateTimeOffset]$deadline).ToString('o')}
            [IO.File]::WriteAllText($DiagnosticReport,($metrics|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
        }
        if(-not $gate.Ready){
            $idleSince=$null
            if($Now){Write-RestartStatus $StatusPath 'Blocked' $gate.Reason;exit}
            Start-Sleep -Seconds 2;continue
        }
        if(-not $idleSince){$idleSince=[DateTime]::UtcNow}
        if(([DateTime]::UtcNow-$idleSince).TotalSeconds -lt 10){Start-Sleep -Seconds 2;continue}
        # Identify visible Codex windows. Ordinary ChatGPT and CLI helpers are excluded.
        $roots=@(Get-RestartDesktopProcesses|Where-Object {$_.MainWindowHandle -ne 0})
        if(-not $roots.Count){Write-RestartStatus $StatusPath 'Blocked' 'No Codex desktop window is available. Open Codex manually.';exit}
        $path=$roots[0].Path
        if(-not [IO.File]::Exists($path)){Write-RestartStatus $StatusPath 'Blocked' 'The app path changed. Open Codex manually.';exit}
        $snapshot=Get-MonitorSnapshot
        if(-not (Get-RestartReadiness @($script:rollouts.Values) 256).Ready){$idleSince=$null;continue}
        try{$request=[IO.File]::ReadAllText($StatusPath)|ConvertFrom-Json;if($request.Status -eq 'Cancelled'){exit}}catch{}
        Write-RestartStatus $StatusPath 'Closing' 'CTC requested a normal app close.'
        $closeAccepted=$true
        foreach($root in $roots){if(-not $root.CloseMainWindow()){$closeAccepted=$false}}
        $left=[DateTime]::UtcNow.AddSeconds(20)
        do {
            $remaining=@(Get-RestartDesktopProcesses|Where-Object {try{$_.Path -eq $path}catch{$false}})
            if(-not $remaining.Count){break}
            Start-Sleep -Milliseconds 500
        }while([DateTime]::UtcNow -lt $left)
        if($remaining.Count -or -not $closeAccepted){Write-RestartStatus $StatusPath 'Blocked' ('Codex did not quit. Quit Codex manually. Open Codex again. Close accepted: '+$closeAccepted+'. Remaining processes: '+$remaining.Count+'.');exit}
        Start-Process -FilePath $path -WindowStyle Normal
        Write-RestartStatus $StatusPath 'Reopened' 'CTC reopened Codex. Resume the chat. Check its next context record.'
        exit
    }
    Write-RestartStatus $StatusPath 'Expired' 'The restart request expired after 24 h. Select the restart button again.'
}catch{Write-RestartStatus $StatusPath 'Blocked' ('CTC could not restart Codex. '+$_.Exception.Message)}
finally{if($owned){$mutex.ReleaseMutex()};$mutex.Dispose()}
