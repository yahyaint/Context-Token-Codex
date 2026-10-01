# Troubleshooting

Use this guide for the current C# and WPF version.
For PowerShell 6.8.9, use the [legacy guide](RECOVERY.md).

## First checks

1. Open the newest CTC desktop shortcut.
2. Check its executable path in Task Manager.
3. Check `%LOCALAPPDATA%\CodexContextMonitor\native-errors.log` if that file exists.
4. Check for a new Codex usage record after a model request.
5. Select the quota refresh button.

Keep preferences, queues, and backups while you diagnose a fault.
Do not delete Codex chat records.

## CTC does not open with the app

Open Widget settings.
Check **Auto-open with app** and **App to follow**.
Check the Windows Startup shortcut named **Context-Token Codex**.
Its target must be the installed `ContextTokenCodex.exe`.
Its arguments must include `--watch`.

If a shortcut points to an earlier version, install the latest CTC release in the same folder.
If CTC was closed manually, launch the selected app again.
An updated Codex executable can be named `Codex.exe` or `ChatGPT.exe`.
The package path identifies Codex.

## Quotas are missing

Check Codex sign-in and the network connection.
Select Refresh and allow up to 45 seconds.
A weekly-only account shows one bar.
CTC does not add a missing 5-hour window.

If you changed accounts, wait for a new account reading.
Per-chat estimates require a baseline and a later observation.

## Chat data are missing

Check `CODEX_HOME` if you use a custom Codex folder.
Check the local `sessions` files and configured `sqlite_home` folder.
Current readers use the newest numeric `state_*.sqlite` and `logs_*.sqlite` files.

An incomplete JSONL line waits for its newline.
An unsupported data schema can require a CTC update.
Use the repair prompt below if the newest release still cannot read records.

## Saved limits do not appear live

Open **Queue** and check the selected scope.
A project override takes priority over global settings.
A loaded chat needs a fresh Codex session.

Select **Restart after all chats stop** to request one normal restart.
Unknown or busy records block it.
A restart closes open Codex windows.

After Codex reopens, resume the chat.
Check the next usage record.
The recorded usable window can be smaller than the saved number.
A larger saved value cannot increase model capacity.

## Restore the previous compiled version

Close CTC.
Open PowerShell and run:

```powershell
& "PATH-TO-INSTALLED\ContextTokenCodex.exe" --rollback "PATH-TO-APP-FOLDER"
```

Use the installation folder that contains `installation.json` and `Versions`.
Rollback updates the version pointer and shortcuts.
Open the desktop shortcut again.
Earlier version files and preferences remain available.

## Remove shortcuts and Auto-open

Close CTC.
Run:

```powershell
& "PATH-TO-INSTALLED\ContextTokenCodex.exe" --uninstall
```

This removes CTC-owned shortcuts and stops Auto-open.
Version files and user settings remain available.

## Repair with Codex

Paste this prompt into Codex:

> Repair Context-Token Codex from https://github.com/yahyaint/Context-Token-Codex. Read UPDATE-RECOVERY.md and CONTRIBUTING.md. Check the installed version, native-errors.log, app identity, session schema, account quota RPC, and context settings. Keep preferences, queues, backups, and earlier versions. Use isolated fixtures for settings and restart tests. Do not change real chat records or submit chat messages. Run the relevant checks. Explain the cause, fix, and remaining limits.

## Report a fault

Open a [GitHub issue](https://github.com/yahyaint/Context-Token-Codex/issues/new/choose).
Include CTC and Windows versions, steps, and a cropped screenshot.
Remove chat names, file paths, and account details that you do not want to share.
Do not upload `auth.json`, raw chat records, or account tokens.
