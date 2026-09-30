# Repair CTC

## Prompt for Codex

> Diagnose and repair Context-Token Codex with RECOVERY.md and UI-WRITING.md. Use STE for all new app text. Keep the installed version, preferences, and Codex chats. Read local errors first. Run the related fixture tests before you change installed files. Do not change or replay queued Codex messages. Do not send a chat message to test monitoring. Report the cause, repair, and test results. Ask before you restart Codex. Do not publish or push without my mark.

## First checks

1. Record the CTC, Codex, Windows, and PowerShell versions.
2. Keep the error text and its time.
3. Keep preferences and the previous runtime files.
4. Check the related row below.
5. Use fixture tests before you install the repair.

| Problem | Check and action |
|---|---|
| Save is disabled | Check the error message. Percent needs an entered numeric window. Compact at must be at most that window. |
| Save is disabled with no error | The entered values match the saved values. |
| Multiplier buttons are disabled | No base value is available. Enter a numeric context window first. |
| Multiplier result is unexpected | Check the base label. Saved and recorded window sizes can differ. Select Undo to read saved values again. |
| Model catalog warning | Check current provider data. The local catalog can be old. A larger setting cannot increase model capacity. |
| Project folder is unavailable | Restore the project folder before you save. CTC does not recreate a deleted project. |
| CTC rejects TOML syntax | Edit the file through Codex. Keep multiline strings. Run test_regressions.ps1 before you install a reader change. |
| Quota refresh is slow | Allow up to 45 seconds. Check CLI initialization, account response, sign-in, and network access. |
| Quota data are old | Read the record time. Select Refresh. Keep the last reading marked as old. |
| Widget is hidden | Select the ctc tray icon or edge tab. Or open ContextWidget.exe again. |
| Auto-open fails | Check Auto-open, Target, Windows Startup apps, shortcut path, and watcher process. Run test_watcher.ps1. |
| Local startup is slow | Check session sizes and data status. Run test_startup.ps1. Keep the complete lifecycle scan. |
| Preferences are incorrect | Compare overlay.json with overlay.json.invalid-*.bak. Keep the backup until recovery is complete. |
| Installation fails | Check the rollback message and Versions backup. Restore the listed files if automatic recovery fails. |

## Auto-open

The Startup shortcut must point to the installed ContextWidget.exe with `/watch`.
It must not point to an old folder.
The watcher reads process and window identity, not a fixed package version.
It tries a failed first launch again until CTC is ready.
After a normal Close, another app launch can start CTC again.

## Message queue error

Codex can show this source error:

> App-server queued follow-up no longer exists

Keep the draft text.
When the chat is idle, reopen or refresh it.
Send a new message only if the user requests it.
Do not change queue database rows.
See ERROR-AUDIT.md for recorded checks.

## Tests and data limits

Run test_context_editor.ps1 for limit parsing and base selection.
Run test_overlay.ps1 for the compact and expanded controls.
Run test_install.ps1 for the setup window.
Use disposable fixtures. Do not change real project limits to test a repair.

Keep atomic writes, configuration backups, and checks for file changes.
Keep unknown readings unknown. Do not replace an unknown value with zero.
CTC sends only initialization and `account/rateLimits/read` to its own helper.
The helper uses a separate database folder.
Do not attach to the Codex desktop RPC connection or change thread and queue records.
Do not stop processes by name. Identify only the CTC helper that needs to stop.

## Release checks

Check `git diff --check` and the staged files.
Keep license notices and source credits exact.
Exclude private paths, authentication data, session logs, and preferences.
Build the Windows ZIP and SHA256 file.
Check the ZIP with `Install-FromGitHub.ps1 -VerifyOnly`.
Keep test results and screenshots.
Do not claim sign-in, separate-machine, ARM, or long-duration checks unless those checks passed.
Do not push without the owner's mark.

## A saved context window does not change a running chat

Check the root `model_context_window` key in the selected settings file.
A key under `[shell_environment_policy.set]` is an environment variable, not a context setting.
Check project overrides and trust before changing global defaults.
Saving changes the file. It does not replace the loaded session configuration.
After all chats stop, quit Codex fully. Open Codex again. Resume the chat.
Check the next `token_count.info.model_context_window` value.
Do not edit rollout counters or the live state database to simulate a larger window.
CTC must show the recorded window until Codex supplies a new value.

## Queued restart is blocked

Open **Limits updates in queue**. Read its status tooltip.
CTC requires known idle lifecycle records. Incomplete data block the restart.
Select **Cancel restart** to remove a waiting request.
After all chats stop, quit Codex fully. Open it again. Check the next context record.
Do not force-stop a running chat to apply a limit.
