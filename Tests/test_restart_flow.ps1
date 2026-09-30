# SPDX-License-Identifier: MIT
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $env:TEMP ('ctc-restart-flow-'+[guid]::NewGuid().ToString('N'))
$profile=Join-Path $fixture 'profile'
[void][IO.Directory]::CreateDirectory((Join-Path $profile 'sessions'))
[IO.File]::WriteAllText((Join-Path $fixture '.restart-test-fixture'),'fixture')
$source=Join-Path $fixture 'Fixture.cs';$exe=Join-Path $fixture 'CTCTestCodex.exe'
[IO.File]::WriteAllText($source,@'
using System; using System.Windows.Forms;
class Fixture { [STAThread] static void Main() {
 var main=new Form { Text="CTC restart fixture", Width=180, Height=80, ShowInTaskbar=true };
 var auxiliary=new Form { Text="", Width=80, Height=60, ShowInTaskbar=false, FormBorderStyle=FormBorderStyle.FixedToolWindow };
 main.Shown+=(s,e)=>auxiliary.Show();
 Application.Run(main);auxiliary.Dispose();
} }
'@)
$compiler=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
& $compiler /nologo /target:winexe /reference:System.Windows.Forms.dll /reference:System.Drawing.dll "/out:$exe" $source
if($LASTEXITCODE){throw 'Fixture build failed.'}
$path=Join-Path $profile 'sessions/chat.jsonl'
$now=[DateTimeOffset]::Now.ToString('o')
[IO.File]::WriteAllText($path,(@{timestamp=$now;type='session_meta';payload=@{id='fixture'}}|ConvertTo-Json -Compress)+"`n"+(@{timestamp=$now;type='event_msg';payload=@{type='task_complete'}}|ConvertTo-Json -Compress)+"`n")
$status=Join-Path $fixture 'status.json'
$desktop=Start-Process -FilePath $exe -WindowStyle Normal -PassThru
try {
    [void]$desktop.WaitForInputIdle(10000)
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'Restart-Codex.ps1') -CodexHome $profile -StatusPath $status -Now -TestRoot $fixture -TestExecutable $exe
    $result=Get-Content $status -Raw|ConvertFrom-Json
    if($result.Status -ne 'Reopened'){throw ('Isolated restart failed: '+$result.Message)}
    $desktop.Refresh()
    if(-not $desktop.HasExited){throw 'Old fixture window did not close.'}
    Start-Sleep -Milliseconds 500
    $new=@(Get-Process -Name CTCTestCodex -ErrorAction SilentlyContinue|Where-Object Path -eq $exe)
    if($new.Count -ne 1 -or $new[0].Id -eq $desktop.Id){throw 'Fixture did not reopen exactly once.'}
    $reopenedPID=$new[0].Id
    . (Join-Path $root 'Restart.Core.ps1')
    Write-RestartStatus $status 'Waiting' 'Fixture maintenance request.'
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'Restart-Codex.ps1') -CodexHome $profile -StatusPath $status -Now -TestRoot $fixture -TestExecutable $exe -RequestExpiresAt ([DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('o'))
    $expired=Get-Content $status -Raw|ConvertFrom-Json
    if($expired.Status -ne 'Expired' -or -not (Get-Process -Id $reopenedPID -ErrorAction SilentlyContinue)){throw 'Expired resumed request closed the fixture or extended its deadline.'}
    Write-RestartStatus $status 'Cancelled' 'Fixture cancellation.'
    $cancelledBefore=[IO.File]::ReadAllText($status)
    & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'Restart-Codex.ps1') -CodexHome $profile -StatusPath $status -TestRoot $fixture -TestExecutable $exe -RequestExpiresAt ([DateTimeOffset]::UtcNow.AddHours(1).ToString('o'))
    if([IO.File]::ReadAllText($status) -cne $cancelledBefore -or -not (Get-Process -Id $reopenedPID -ErrorAction SilentlyContinue)){throw 'Helper maintenance revived a cancelled request.'}
    'PASS: main and untitled auxiliary windows, normal close, process exit, one reopen, expiry and cancellation. Real Codex was not touched.'
}finally{
    foreach($process in @(Get-Process -Name CTCTestCodex -ErrorAction SilentlyContinue|Where-Object Path -eq $exe)){
        [void]$process.CloseMainWindow();if(-not $process.WaitForExit(5000)){$process.Kill()}
    }
    $desktop.Dispose()
}
