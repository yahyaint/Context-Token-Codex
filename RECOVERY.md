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
| Widget is hidden | Select the ctc tray icon or Restore on the parked bar. Or open ContextWidget.exe again. |
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

## A limit save fails or overwrites an earlier change

Select **Undo** to load the newest file values. Enter the changes again.
CTC rejects a save if another editor changed the file after the form opened.
If the file contains invalid settings, correct the file through Codex. Select **Undo** again.
Check file permissions and open file locks when a valid save fails.
Run the tests in [LIMITS-VERIFICATION.md](LIMITS-VERIFICATION.md).
Keep real chat records intact. Use fixture folders for save tests.

## Weekly quota after sign-in

CTC must show the windows from the current account response.
A weekly-only response must show one 7d bar. Do not add a 5h bar with a zero value.
Run Tests/test_account_quota.ps1 and Tests/test_overlay.ps1 in PowerShell 5.1 and 7.
PowerShell 5.1 does not give a single PSCustomObject a Count property.
Keep quota windows in an array outside an if expression.

CTC checks auth-file metadata to detect a sign-in change. It does not read credentials.
The helper must reject a response if the metadata changed during its request.
Keep the account identifier hashed. Keep quota estimate files separate by account.
Unknown historical readings must not replace an empty current account response.

## Limits queue and restart

Open Queue beside Limits. Restart controls stay above the scrollable change list.
The local limits-queue.json file stores the latest saved change for each settings file.
It is separate from the Codex message queue. Keep it outside the repository.
Run Tests/test_limits_queue.ps1 and Tests/test_restart.ps1 before a queue repair.
Cancel restart cancels the waiting request. It does not undo saved settings.

If a saved entry and the settings file differ, open Limits. Select Undo to read the file.
Save the required values again. The latest save replaces that scope's queue entry.
An unknown queue format is preserved. Keep a copy before you repair it.
After a safe restart, resume the chat. Check its next context record.
A matching window does not confirm the compaction threshold.

For a live display check, start Overlay.ps1 with -DiagnosticReport and a local output path.
The report includes displayed quota labels, startup visibility, background opacity and provider errors.
It contains no account ID, credentials, chat text or tool arguments.
Keep diagnostic reports outside Git. Allow one provider request to complete.

## Exec details

Run Tests/test_exec_activity.ps1 in both PowerShell runtimes.
Check response_item function_call, custom_tool_call and their output records.
Output can be a string, a metadata object, or text blocks.
Accept text, input_text and output_text blocks. Keep unknown block types unknown.
Correlate results by call ID. Exclude duplicate outputs and unrelated tool output.

Script tools come from direct tools.name(...) references.
Do not convert reference counts to execution counts.
Keep strings and comments outside the reference scan.
Mark dynamic calls, template expressions, oversized code and incomplete records.

Keep command categories and numeric result metadata only.
Do not store commands, arguments or stdout in activity summaries.
Keep large-output reads bounded. Keep the quick context scan ahead of the full activity backfill.
If results stay unknown, check the native block type before changing counter logic.
Do not copy real rollout records into a public test fixture.

## Desktop executable names

Some Codex packages use app/ChatGPT.exe. The file name alone does not identify the app.
Check the OpenAI.Codex package path. Exclude app/resources helpers and Codex/bin CLI files.
Run test_restart.ps1 and test_watcher.ps1 after a process identity repair.
Run test_restart_flow.ps1 only with its marked fixture. It must not close real Codex windows.
Do not use a process-name kill to repair the desktop restart.

## RAM grows during polling

Run test_usage.ps1 and test_context_editor.ps1 in both shells.
Repeated reads must keep source object type names unchanged.
Check Select-Object without -Property on objects that remain in a cache.
In PowerShell 5.1, each selection can add a Selected type name to the same object.
Use an array index to read a selected item. Keep the source object's metadata unchanged.
Keep the parsed-settings cache bounded. Compare file contents before you reuse parsed data.

For a live check, exit CTC from its tray menu. Start Overlay.ps1 with -DiagnosticReport and a private file path.
Check ManagedMB, WorkingMB, Scans, ProcessId, CPUSeconds, and TypeNamesMax over at least 30 minutes.
Keep the same process during the test. Check visible Tokens and the parked bar.
Do not clear the working set to hide growth.

The optional diagnostic request is a file named `<report-path>.collect`.
CTC consumes this file and records BeforeGCMB and AfterGCMB after garbage collection.
Use this request outside the stability test. It changes memory measurements.
Diagnostic reports and heap data must stay outside the public repository.

## Queue values differ from the file

Queue keeps the values from the last CTC save. A file edit outside CTC can replace those values.
Check the File changed line. Open Limits to read the current settings.
A Project override row does not confirm a global queued limit.
An Inherited window row does not confirm a project override or a compaction threshold.
If the queue file is corrupt, keep it for repair. CTC clears old display rows and rejects a save.

## A waiting helper runs old code

An existing PowerShell helper keeps its loaded code after files change on disk.
Check Restart-Codex.ps1 processes when RAM still grows after an update.
For a manual update, cancel the waiting restart before you replace runtime files.
After the update, queue the restart again if you still need it.
For controlled maintenance, keep the existing request and its original expiry.
Start the replacement helper with -RequestExpiresAt. Preserve CodexHome and StatusPath.
Do not stop Codex to replace a CTC helper. Do not start a new request without authorization.
Use -DiagnosticReport to record helper PID, type-name count, memory, idle gate, and expiry.
