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
class Fixture { [STAThread] static void Main() { Application.Run(new Form { Text="CTC restart fixture", Width=180, Height=80, ShowInTaskbar=true }); } }
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
    'PASS: isolated normal close, process exit, and one reopen. Real Codex was not touched.'
}finally{
    foreach($process in @(Get-Process -Name CTCTestCodex -ErrorAction SilentlyContinue|Where-Object Path -eq $exe)){
        [void]$process.CloseMainWindow();if(-not $process.WaitForExit(5000)){$process.Kill()}
    }
    $desktop.Dispose()
}
