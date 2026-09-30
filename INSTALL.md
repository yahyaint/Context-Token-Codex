# Install CTC

The GitHub method needs a public repository and Windows release.
Publication waits for the owner's approval.

## Prompt for Codex

> Install Context-Token Codex from https://github.com/yahyaint/Context-Token-Codex. Read INSTALL.md, RECOVERY.md, and UI-WRITING.md first. Download the latest Windows release and SHA256 file. Check the hash. Open Setup.exe. Keep existing preferences and a backup. Check local chat data after installation. Do not change Codex limits or message queues. If no release is available, stop and report the cause.

## GitHub command

Install GitHub CLI first.
Sign in with `gh auth login` if required.
Run this command in PowerShell:

```powershell
& { $p=Join-Path $env:TEMP ('ctc-source-'+[guid]::NewGuid().ToString('N')); gh repo clone yahyaint/Context-Token-Codex $p; if ($LASTEXITCODE) { throw 'Clone failed' }; powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $p 'Install-FromGitHub.ps1') }
```

To select a fixed release, add `-Version v6.8.0` to the helper command.
The helper checks the ZIP hash before it opens Setup.
The hash detects changed files. It is not a publisher signature.

## Manual installation

1. Download the Windows release ZIP and SHA256 file.
2. Use `Get-FileHash` to check the ZIP hash.
3. Extract the ZIP.
4. Open Setup.exe.
5. Select the installation folder.
6. Select Install.

Auto-open is on by default.
CTC keeps previous files and settings when you install an update.
Installation does not need administrator access.

## Source files

Source ZIPs do not contain the executables.
Run `Build/build.ps1` before you open Setup.exe.
The Windows release ZIP contains the executables.
