# Repair CTC after an update

Paste this into Codex with this repository open:

> Diagnose and repair Context-Token Codex using RECOVERY.md. Preserve the installed version, preferences and all Codex tasks. Inspect the current release and local errors. Run the relevant fixture tests before changing live files. Never delete, edit or replay Codex queued messages. Do not send a task to test monitoring. Show the cause, fix and test evidence. Ask before restarting Codex. Do not publish or push without my mark.

## First checks

1. Record Windows, PowerShell, CTC and Codex versions. Keep screenshots and timestamps.
2. Read `installation.json`, `CHANGELOG.md` and `COMPATIBILITY.md`. Keep the previous install's `Versions` folder.
3. Confirm the selected Codex home. Do not copy `auth.json`, session contents or databases into issues or Git.
4. Check Context, Tokens and Limits. A missing value must show `--`, not zero.
5. Run `Build/build.ps1`, then the relevant scripts in `Tests`. UI tests need an interactive Windows desktop and STA PowerShell. Test with Windows PowerShell 5.1 and PowerShell 7 when available.

## Symptoms and fixes

| Symptom | Check | Fix |
|---|---|---|
| No tasks | Selected profile; recent session files; task state | Wait for a local task record. Check discovery/fallback status. Do not fabricate active tasks. |
| Token counts stop | Last-record time versus reader status | A running reader cannot invent usage between Codex records. Test a synthetic append with `test_overlay.ps1`. |
| Missing live compaction | SQLite availability and log schema | Use completed-compaction events from session files. Adapt the private log query only after inspecting the new schema. |
| Subscription refresh fails | CLI location/version, sign-in and timeout | Keep the last reading with its time. Test `test_transport.ps1`. Preserve private state isolation in `Usage.Provider.ps1`. |
| Long lists jump | Wheel handler, nested scroll viewers, retained controls | Use fixed pixel scrolling. Do not recreate or reorder every card on each tick. |
| Saved limit differs from live | Raw versus usable size; selected scope | Check inherited values. Reload the task only with approval. Never claim a larger configured number expands model capacity. |
| Widget is hidden | Tray icon or edge restore tab | Click CTC beside the Windows clock or launch ContextWidget.exe again. |
| New release fails | Backup, checksum, test report | Close CTC, restore the previous runtime files from Versions, retain current preferences, then reopen. Do not remove Codex files. |
| “App-server queued follow-up no longer exists” | Codex Desktop composer and queue state | Preserve draft text. Refresh/reopen the task when idle; submit as a new message only if the user requests it. Do not alter queue SQLite rows. See ERROR-AUDIT.md. |

## Provider boundary

CTC sends only initialization and `account/rateLimits/read`. Its helper uses a separate `sqlite_home` under the CTC data directory. It closes its own stdin before terminating its own helper if needed. Never replace this with killing processes by name, attaching to Desktop's RPC connection, thread/queue calls, or direct credential extraction.

## Before publishing a repair

- Check `git diff --check`, license notices and staged files for private paths/data.
- Build the Windows ZIP and SHA256 file. Test the extracted package and `Install-FromGitHub.ps1 -VerifyOnly` against that local ZIP.
- Record actual tested environments and remaining limits. Hosted CI must pass after publication; local tests are not hosted CI.
- Keep the old release. Use a new version and explain the behavior change.

For a Codex Desktop update, finish and save work first. Restart only after approval. Afterward, verify actual installed versions, a local task's read-only monitoring, subscription refresh, tray restore and Limits. Do not use a live queued message as a destructive test fixture.
