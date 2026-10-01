# Install Context-Token Codex

Use Windows 10 or Windows 11 on an x64 PC.
The Windows release includes .NET.

## Install with a prompt

Paste this prompt into Codex:

> Install Context-Token Codex from https://github.com/yahyaint/Context-Token-Codex. Read INSTALL.md and UPDATE-RECOVERY.md. Download the latest Windows release and its SHA256 file. Check the hash. Extract the ZIP and open Setup.exe. Keep preferences, queues, and earlier versions. Verify local chat data after installation. Do not change Codex limits or submit chat messages. If the compiled release is unavailable, report the cause.

## Install with GitHub CLI

Install GitHub CLI.
Run this command in PowerShell:

```powershell
& { $p=Join-Path $env:TEMP ('ctc-source-'+[guid]::NewGuid().ToString('N')); gh repo clone yahyaint/Context-Token-Codex $p; if ($LASTEXITCODE) { throw 'Clone failed' }; powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $p 'Install-FromGitHub.ps1') }
```

The helper downloads the latest release, checks the ZIP hash, and opens setup.
The helper downloads public release files without a GitHub sign-in.
GitHub CLI can require a sign-in before it runs the clone command.

## Install manually

1. Open the [latest release](https://github.com/yahyaint/Context-Token-Codex/releases/latest).
2. Download the Windows ZIP and its `.sha256` file.
3. Run `Get-FileHash "PATH-TO-ZIP" -Algorithm SHA256` in PowerShell.
4. Compare the result with the hash in the `.sha256` file.
5. Extract the ZIP.
6. Open `ContextWidget\Setup.exe`.
7. Select **Next**.
8. Select the installation folder and options.
9. Select **Install**, then **Finish**.

CTC installs for your Windows account. Administrator access is not required.
Auto-open and the desktop shortcut are on by default.
The executables are unsigned. The hash detects file changes; it is not a publisher signature.

## After installation

Open the desktop shortcut.
CTC starts in the small bar with 85% background opacity.
Select the restore arrow to open the widget.

The watcher follows Codex or ChatGPT after Windows sign-in.
Change this option in **Widget settings**.
The watcher reads Codex data even when ChatGPT triggers the launch.

## Update or restore

Install the latest release in the same app folder.
Setup keeps earlier compiled files in `Versions`.
It keeps preferences and the saved limits queue.

See [Troubleshooting](UPDATE-RECOVERY.md) for rollback and removal.
The [PowerShell 6.8.9 release](https://github.com/yahyaint/Context-Token-Codex/releases/tag/v6.8.9) remains available.
Use its release files to install that version.

## Unattended installation

After extraction and the hash check, run:

```powershell
.\ContextWidget\ContextTokenCodex.exe --install "$env:LOCALAPPDATA\Programs\Context-Token-Codex"
```

Add `--no-startup` to disable Auto-open.
Open the new desktop shortcut after installation.

Source archives do not contain built executables.
See [Build and test](https://github.com/yahyaint/Context-Token-Codex/blob/main/CONTRIBUTING.md) to build from source.
