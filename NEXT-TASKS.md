# CTC ordered task list - 30 September 2026

Use this list to continue work after an interruption. Complete one item before the next item.
Use STE for app text. Preserve earlier versions and settings. Keep GitHub publication on hold.

## Completed verification

- [x] Test chat and project limits in PowerShell 5.1 and 7: 85 cases per runtime.
- [x] Test the installed Codex engine with local Sol and Astra fixtures: 24 checks.
- [x] Verify three previously saved project windows through Codex `config/read`.
- [x] Repair stale saves, parent project reads, empty-file writes, stale usage, and percentage arithmetic.

## Current implementation queue

1. [x] Finish the weekly-only sign-in repair and install it.
   - Fix PowerShell 5.1 handling of one quota window.
   - Keep current account windows separate from unknown historical readings.
   - Refresh after sign-in changes. Reject responses from an earlier sign-in.
   - Separate estimate histories by account. Fix repeated history saves.
   - Verify the actual installed weekly quota and its displayed label.
2. [x] Finish startup preferences.
   - Open in the parked bar at the saved corner.
   - Set the fresh-install background slider to 85%.
   - Apply 85% and parked startup to the owner's current installation.
   - Keep text fully visible. Apply the same background opacity to the bar.
   - Keep automatic app launches parked. Keep manual restore available.
3. [x] Add a Queue page beside Limits.
   - Show saved limit changes and the restart state.
   - Show the chat or project, saved window, recorded window, and pending status.
   - Keep Restart now safely, Restart after all chats stop, and Cancel visible.
   - Remove restart controls from hidden limit-editor sections.
   - Block unsafe restarts. Keep waiting requests and saved changes after CTC closes.
4. [x] Separate token sections.
   - Add a divider after Breakdown.
   - Put Data status and How counts work in one small row with a separator.
   - Keep Recorded chats and Other chat details separate from the main breakdown.
5. [x] Improve tool-call details.
   - Put Tool calls in its own expandable row inside the Breakdown grid.
   - Group exec calls below Tool calls.
   - Include results, status, time, command types, nested script references and reported shell metadata.
   - Use recorded tool names and counts. Do not infer exact token costs.
   - Keep unknown or incomplete data clear. Do not show command arguments or private tool output.
6. [x] Combine Minimize and Park.
   - Make Minimize show the parked bar.
   - Remove the separate Park button.
   - Put Corner in the available control position.
   - Keep tray hide and restore separate from the parked bar.
7. [x] Run final checks and install the complete version.
   - Test both runtimes, the actual WPF controls, startup, queue, quotas, and installation.
   - Inspect rendered compact, expanded, parked, and Queue views.
   - Keep the previous runtime and the owner's settings, except for the requested new defaults.
8. [x] Prepare local Git and release files.
   - Update the README, changelog, audit, and recovery guide.
   - Keep the MIT license and existing attribution.
   - Check staged files for private data. Commit locally. Keep the GitHub push on hold.

## Final queue - complete

9. [x] Finish the longer actual-widget memory test.
   - A parked Tokens run showed continued RAM growth.
   - Stop updates to hidden token panels. Keep the parked bar and data collector live.
   - Run a new bounded soak after the repair. Record errors, stale data, memory and CPU.
   - Fix growing Selected type names in persistent PowerShell objects. Add repeated-read regression checks.
   - Final 30-minute run: 120 samples, no errors or stale readings, one process, and two source type names.
   - Peak working set: 377.6 MiB. See AUDIT.md for scope and CPU.
10. [x] Finish update-safe desktop restart identity.
   - Select the OpenAI.Codex desktop path even when its file name is ChatGPT.exe.
   - Exclude ordinary ChatGPT, CLI binaries and bundled helpers.
   - Keep the idle gate and normal close. Test the fixture close/reopen in both shells.
   - Package-version, renamed-file and helper exclusion fixtures pass in both shells.
   - The real primary OpenAI.Codex path is recognized. Real Codex was not closed.
11. [x] Install the repairs and prepare the final local release.
   - Refresh the open CTC. Keep earlier versions and current settings.
   - Update test evidence, docs, source archive and local Git. Keep publication held.

## Verification follow-up - 1 October 2026

12. [x] Verify all queue items and repair missed cases.
    - Check implementation, actual WPF controls, runtime hashes, startup, and local Git.
    - Fix scope confirmation, external queue changes, and malformed queue entries.
    - Refresh the old waiting helper. Preserve the request and original expiry.
    - Keep local checks separate from publication and environment checks that remain unverified.
    - See QUEUE-VERIFICATION.md for the item-by-item result.

## Real-session result

- [x] The original Sol chat records 516800. Its saved 544000 value and the 95% catalog value match.
- [x] The original Astra chat also records 516800 in its checked usage record.
Its project and global overrides are now absent. That external settings change is preserved.
The Astra record confirms the earlier 544000 setting, not a later reset to default.
Do not restore or change those settings without a user request.
A full app restart is no longer needed to prove that the earlier window update was adopted.
Do not force-close running chats.

## Resume packet

Working source: `work/context-widget`.
The canonical publication checkout and installed runtime are recorded in the private workspace resume file.
Version 6.8.6 is the current repair. The latest widget is restored after tested UI changes.
Weekly-only WPF fixtures pass in PowerShell 5.1 and 7 after the array repair.
Weekly-only quota, parked startup, Queue, token layout, tool tile, Exec results, command types and script references are implemented.
Final package, runtime alignment, local commit and source archive are prepared. Publication remains held.
See AUDIT.md for full scan time, memory samples and unverified environments.
Do not repeat a completed item. Update each checkbox with test evidence.

## Chat continuation

The user requested a continuation in this chat.
A follow-up with the ordered list was sent through the supported Codex chat tool.
Device Use identified the desktop surface as ChatGPT. Its skill blocks submission there.
Do not send the same continuation again. Continue from this checklist.

## Live preview

The user requested that the latest CTC stay open after tested UI changes.
Refresh only the CTC runtime. Preserve current preferences.
Restore the widget after startup is ready. Do not restart Codex to preview CTC.
