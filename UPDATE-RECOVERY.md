# Repair CTC after a Codex update

Use this guide for the compiled C# and WPF version.
Keep the PowerShell 6.8.9 release as an earlier version.
See RECOVERY.md for that version.

## Prompt for Codex

> Repair Context-Token Codex from https://github.com/yahyaint/Context-Token-Codex. Read UPDATE-RECOVERY.md and UI-WRITING.md. Check the installed version, native-errors.log, session schema, app paths, account quota RPC, and context settings. Use isolated fixtures. Do not change real chat records or message queues. Keep settings and backups. Run the native core and UI checks. Explain each remaining limitation.

## First checks

1. Open the newest Context-Token Codex shortcut.
2. Check the executable path in Task Manager.
3. Check native-errors.log in %LOCALAPPDATA%\CodexContextMonitor.
4. Check the next Codex model request for a new context record.
5. Select Refresh to read account quotas.

The compiled app does not require PowerShell or an installed .NET runtime.
The release includes its .NET runtime.
The quota reader requires the Codex CLI supplied with Codex.
CTC uses a separate SQLite folder for its quota helper.
It does not submit chat messages.

## Startup failure

Check the Startup shortcut named Context-Token Codex.
Its target must be the installed ContextTokenCodex.exe.
Its arguments must include --watch.
Check the Auto-open with app setting.
Check the Codex package path in DesktopIdentity.IsCodex.
Codex updates can change the executable name from Codex.exe to ChatGPT.exe.
The package path identifies the app.

## Missing quota data

Check Codex sign-in and network connection.
A plan can supply only a weekly quota.
CTC must not create a missing 5-hour quota.
Check account/rateLimits/read through an isolated CLI helper.
Check rateLimitsByLimitId before the older rateLimits property.
Check usedPercent, windowDurationMins, and resetsAt.
Null values must remain unknown.
After sign-in changes, discard earlier live quotas and estimate baselines.

## Missing chat data

Check CODEX_HOME and sqlite_home.
Find the newest numeric state_*.sqlite and logs_*.sqlite versions.
Check threads.rollout_path, session_index.jsonl, and sessions JSONL records.
CTC opens SQLite databases for reading only.
If a table changes, keep the JSONL fallback.
Unknown event types must not stop the reader.
An incomplete JSONL line must wait for its newline.
Keep unknown lifecycle data out of automatic restart decisions.

## Saved limits do not appear live

Check model_context_window and model_auto_compact_token_limit in the selected config.toml.
Check project overrides before global settings.
Check model catalog capacity and effective_context_window_percent.
Do not replace recorded context values with saved values.
Select Queue to inspect saved changes.
Select Restart after all chats stop for one normal restart.
Unknown or busy records block the restart.
Open Codex windows close during a restart.
A larger saved window cannot increase provider model capacity.

## Build and test

Install the .NET 10 SDK on Windows.
Run Build/build-native.ps1.
Run Tests/test_native_ui.ps1 with the published ContextTokenCodex.exe.
The core checks use temporary profiles.
The UI checks use fixture accounts and projects.
Do not use real context settings for tests.

## Restore an earlier version

Keep the installation Versions folder and installation.json backups.
Compiled updates retain the earlier compiled version.
The PowerShell release remains available at tag v6.8.9.
To switch to the previous compiled version, run ContextTokenCodex.exe --rollback with the installation folder.
To remove CTC shortcuts, run the installed ContextTokenCodex.exe --uninstall.
Uninstall keeps version files and user settings.
Do not delete preferences, limits-queue.json, or restart.json to repair startup.
Keep a waiting restart request and its original expiry.
