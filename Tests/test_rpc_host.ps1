# SPDX-License-Identifier: MIT
$ErrorActionPreference='Stop'
$folder=Join-Path $env:TEMP ('ctc-rpc-host-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($folder)
$fixture=Join-Path $folder 'host.ps1'
[IO.File]::WriteAllText($fixture,@'
[IO.File]::WriteAllText($PSCommandPath+'.trace','started')
while($line=[Console]::ReadLine()){
 [IO.File]::AppendAllText($PSCommandPath+'.trace',' received')
 $message=$line|ConvertFrom-Json
 [IO.File]::AppendAllText($PSCommandPath+'.trace',' parsed')
 [Console]::WriteLine('probe-ok')
}
'@)
$info=[Diagnostics.ProcessStartInfo]::new()
$info.FileName=(Get-Process -Id $PID).Path
$info.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$fixture+'"'
$info.UseShellExecute=$false;$info.CreateNoWindow=$true
$info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
$process=[Diagnostics.Process]::new();$process.StartInfo=$info
try{
 [void]$process.Start()
 $err=$process.StandardError.ReadToEndAsync();$out=$process.StandardOutput.ReadLineAsync()
 $process.StandardInput.WriteLine('{"id":1}');$process.StandardInput.Flush()
 $responded=$out.Wait(8000)
 $process.StandardInput.Close()
 if(-not $process.WaitForExit(8000)){$process.Kill();[void]$process.WaitForExit(2000)}
 $trace=if(Test-Path -LiteralPath ($fixture+'.trace')){[IO.File]::ReadAllText($fixture+'.trace')}else{'not started'}
 Write-Output ('Fixture trace: '+$trace)
 Write-Output ('Fixture stderr: '+$err.Result)
 if(-not $responded -or $out.Result -notmatch 'probe-ok'){throw 'The redirected PowerShell RPC fixture did not echo its input while the pipe was open.'}
 'PASS: redirected PowerShell RPC host.'
}finally{$process.Dispose()}
