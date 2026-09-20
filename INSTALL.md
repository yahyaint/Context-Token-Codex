# Install Context-Token Codex

Windows only. The public repository and release must exist before these commands work.

## One prompt for Codex

> Install Context-Token Codex from https://github.com/yahyaint/Context-Token-Codex. Read INSTALL.md and RECOVERY.md first. Download the latest published Windows release and its SHA256 file. Verify the hash, then open Setup.exe. Preserve any existing preferences and back up the old version. Check that the widget opens and reads local task usage. Do not change Codex settings or queued messages. If there is no published release, stop and report that instead of downloading from another source.

## One command with GitHub CLI

Run in PowerShell after signing into `gh`:

```powershell
& { $p=Join-Path $env:TEMP ('ctc-source-'+[guid]::NewGuid().ToString('N')); gh repo clone yahyaint/Context-Token-Codex $p; if ($LASTEXITCODE) { throw 'Clone failed' }; powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $p 'Install-FromGitHub.ps1') }
```

The command clones source and runs the repository's installer helper. The helper downloads the latest release, verifies its SHA256 and opens the setup wizard. You choose the destination and startup option in the wizard. It does not require administrator rights. This is not an unattended install or a digital-signature guarantee; the hash detects a mismatched download.

To pin a release, add `-Version v6.3.0` to the helper command. For a manual install, download the Windows ZIP and checksum from Releases, verify the hash with `Get-FileHash`, extract and open Setup.exe. Source archives require `Build/build.ps1` first.
