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

## Pending real-session check

Two live chats still record 258400 after saving 544000.
The native fixture confirms that a fresh engine and resumed chat can use 516800 with the current 95% catalog value.
The real desktop chats still need a safe restart and a new usage record.
Do not force-close running chats. Keep this item pending until a real record confirms it.

## Resume packet

Working source: `work/context-widget`.
The canonical publication checkout and installed runtime are recorded in the private workspace resume file.
Version 6.8.3 is installed. The latest widget is restored after tested UI changes.
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
