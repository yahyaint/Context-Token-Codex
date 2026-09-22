# Methods and borrowed ideas

This PowerShell monitor borrows **design ideas** from [Codex Monitor HUD](https://github.com/LH-03/codex-monitor-hud) by LH-03 and contributors ([MIT license](https://github.com/LH-03/codex-monitor-hud/blob/main/LICENSE)). The relevant sources are its [core session reader](https://github.com/LH-03/codex-monitor-hud/blob/main/src/MonitorHud.Core.psm1) and [privacy description](https://github.com/LH-03/codex-monitor-hud/blob/main/PRIVACY.md). The monitor remains an independent implementation; its existing compaction detection and settings menu were developed before this comparison.

| Method | Codex Monitor HUD | This monitor | Reason for our choice |
| --- | --- | --- | --- |
| Find current tasks | Reads recent user-task rollout paths from Codex's local SQLite state index; caps candidates. | **Borrowed idea:** query that index through `sqlite3.exe`, cap at 128 by default, and scan folders when the index is unavailable. | Avoid walking every session folder on every refresh. Keep a fallback for private schema changes. |
| Read JSONL | Reads a bounded tail (up to 8 MiB), then maintains current state. | Streams the full first read line by line, then parses appended bytes only. Rejects unrelated event types before JSON parsing. | Keeps historical compaction counts while bounding memory to roughly one record; initial load can take longer than HUD. |
| Task identity | Uses `session_index.jsonl` for local conversation titles. | **Borrowed fallback:** reads that index when changed; Codex Desktop's `threads.name` remains authoritative for the current UI name. | Preserves renamed Desktop titles and still has a name if SQLite is unavailable. |
| Status and errors | Separates active, idle, completed, aborted, and read-error states. | Keeps lifecycle and live compaction states; **borrowed idea:** show a read error while retaining the last good snapshot. | Avoid silently appearing frozen after a failed file read. |
| Context alerts | Configurable percentage alert levels. | **Borrowed idea:** configurable high and critical markers, default 80% and 95%. | Make approaching limits visible without changing Codex settings. |
| Allowance | Shows recent 5-hour and weekly allowance observations. | **Borrowed idea:** show only locally recorded `token_count.rate_limits`, with observation time and reset time. | Recorded fallback needs no network. Tokens mode also uses an authenticated Codex CLI read-only provider. The CLI handles credentials; CTC does not extract them. Newest observations win per window. |

The first read favors complete compaction history over HUD's faster bounded tail. Our display refreshes on a timer; HUD uses its own desktop overlay and multiple source profiles. This application stays focused on Codex's normal local profile. It does not add DeepSeek support. Its native floating widget is described below.

The monitor reads private Codex storage formats, which may change. The task index and quota rows have a visible fallback or unavailable state. The settings editor uses [official OpenAI configuration keys](https://learn.chatgpt.com/docs/config-file/config-reference) for context window and automatic compaction, but a saved value is not proof that an already-loaded Desktop task adopted it.
# Overlay 4.0 interface

This edition preserves the console monitor's incremental session reader. Native WPF controls replace console rows. The reader runs in a separate runspace and passes completed snapshots to the UI; controls are retained between updates. A separate, optional Windows sign-in watcher detects application launches every five seconds. No HUD rendering code was copied.

| Method | Console edition | Overlay edition |
|---|---|---|
| Refresh | Replace changed console rows | Update existing WPF controls |
| Background reading | Main console loop | Dedicated PowerShell runspace |
| Minimize/restore | Terminal window | Taskbar and notification-area icon |
| App launch | Manual launcher | Manual launcher or optional Startup watcher |
| Configuration | Terminal prompts | Form with current values, examples, validation and feedback |
| Runtime reload | Saved/live mismatch shown | Same limitation shown directly in cards and settings |
