# Context-Token Codex 6.3.7

## Install and recover

See [INSTALL.md](INSTALL.md) for the one-command GitHub CLI installer and a copy-paste Codex installation prompt. See [RECOVERY.md](RECOVERY.md) for update diagnosis and repair instructions. These GitHub instructions require a published repository and release.

Active chats show token details first. Edit project context defaults directly in a chat card. Limits also lists idle saved projects. These are project-wide defaults for all models, not persistent per-model or per-chat overrides. Existing loaded chats may require a reload; changing a number does not increase supported model capacity.

A portable Windows overlay for local Codex tasks. Native WPF interface, live context bars, compaction status, editable project/global context settings, and a system-tray icon. No browser, service, account, administrator rights, or downloaded runtime required.

**Windows only · MIT licensed · independent community project**

By **Yahya Nabil** · [yahyanabil.com](https://yahyanabil.com)

## Context / Tokens modes

Use Context and Tokens below the header to switch modes. Limits opens the context editor inside the widget. **Context** keeps the task context cards and embedded context controls. **Tokens** shows cumulative recorded token counts plus account subscription quota windows, reset times and plan information. Mode selection is remembered.

Live quota reads use your installed, signed-in Codex CLI once per minute while Tokens mode is selected. Click Refresh for an earlier read. The CLI handles authentication and provider network access; the widget does not extract credentials or read browser cookies. If unavailable, recorded local quota data is labeled with its source and age. Missing windows stay missing. Available reset-credit counts are read-only.

Token totals cover loaded user tasks (24-hour discovery lookback, up to 128 files by default), and each task counter can include older work. They are **not today's usage, account lifetime usage, a bill, or tokens remaining in a plan**. Cached input is already part of input. See [USAGE-METHODS.md](USAGE-METHODS.md) for the tool comparison, CodexBar attribution and accounting limits.

Downloading the source repository? Build the launchers first:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build\build.ps1
```

Then run `Setup.exe` or `ContextWidget.exe`. Generated executables are provided in the release package, not in Git. See [CONTRIBUTING.md](CONTRIBUTING.md) for build/tests, [AUDIT.md](AUDIT.md) for resource costs and [METHODS.md](METHODS.md) for credited design ideas.

## Open it

1. Extract the complete ZIP, then double-click **Setup.exe**.
2. Choose your installation folder and shortcuts. **Auto-open is enabled by default**; uncheck it if unwanted.
3. Click **Install**, then **Finish**. No administrator access required.

For portable use, run **ContextWidget.exe**. The VBS/CMD launchers remain as fallbacks. The installer creates branded desktop and Start-menu shortcuts. It preserves the previous runtime files when updating an existing installation.

Windows 10/11 with Windows PowerShell 5.1 and desktop .NET Framework required. This release is Windows-only. Optional `sqlite3.exe` on PATH enables current desktop task names, indexed discovery, and live compaction-start events. Without it, the overlay uses session files and the session index; completed compactions remain visible. SQLite is not bundled.

The overlay has no Windows title bar. It starts as a small **mini card** in the bottom-right corner, showing the most recently active task, status, context bar and token usage. Click the task name or **Expand** for all tasks; **Collapse** returns to the mini card. The selected view is remembered.

Drag the **CONTEXT** header to move it. Release within 48 display units of a corner to snap with a small margin. Or choose a corner in the widget's **Corner** menu. Expanding and collapsing retain that corner. Drag the bottom-right grip to resize the expanded view; its dimensions are remembered separately from the mini card.

The **Opacity** slider is directly on the widget and changes the entire widget immediately (40-100%). The percentage updates as you drag; preference writes are debounced. **Pinned** toggles always-on-top. **Corner** chooses a screen corner without opening settings. The mini card now shows remaining tokens, observed compactions, cached-input percentage, last event time, and previous/next task controls.

**Tray** hides the widget but leaves a Frost **context-ring** icon in the Windows notification area beside the clock (possibly inside **^**). Single-click that icon to restore; right-click for settings or exit. **Park** leaves a small visible Context restore tab at the screen edge instead. The minus button minimizes to the taskbar. Close exits the monitor and removes its tray icon. The launcher also restores an existing hidden instance.

Version 4.2 fixes a lifecycle bug: WPF's modal `ShowDialog()` returned when the main window was hidden, which disposed the tray icon. The main window now uses a persistent application dispatcher, with explicit shutdown on exit. Tests hide it across multiple dispatcher ticks to verify continued operation.

## Open automatically with the app

In **Settings**, enable **Auto-open with app**, select **Codex**, **ChatGPT**, or **Either**, then click **Save window preferences**.

This creates a shortcut in your Windows account's Startup folder and starts a small watcher immediately. The watcher checks app processes every five seconds. It opens the overlay when the selected app starts, including if that app is already open when the watcher starts. It distinguishes Codex's `ChatGPT.exe` using its installation path. No admin privileges or scheduled task needed.

The overlay stays open when the app closes. Hiding/minimizing it stays respected until the next app launch or manual restore. Closing it exits that instance; the watcher can reopen it on the next app launch. Turn off Auto-open and save to remove the Startup shortcut and stop the watcher within five seconds. Move the folder only after disabling Auto-open; enable again from the new location.

**The selected app controls when the overlay opens. Its data source remains local Codex sessions. ChatGPT conversation context is not exposed by this monitor.**

## Read the cards

- Current task name, model, project, status and last event time.
- Context percentage: input tokens in the latest recorded request divided by that request's reported usable context window. It is not an exact counter of tokens currently streaming. After compaction, usage waits for the next recorded request.
- Exactly three brand colors. HIGH at 80%, CRITICAL at 95%, and COMPACTING are explicit text states.
- Cached input, last output and observed compaction count. Counts cover loaded recent rollouts, not guaranteed lifetime totals.
- Saved raw context size, expected usable size when model metadata allows calculation, and whether that matches the live task. A mismatch does not identify the exact reason by itself.
- Most recently active tasks move upward. Task controls update in place; the full window is not cleared each refresh.
- Read failures and unavailable data appear explicitly. An old running record may be stale after a crash; absence of events does not prove a task is still executing.

## Change context settings

Click the compact header's **context controls icon**. It expands directly to the Context panel inside the overlay. The gear opens the Widget panel; Tasks returns to live cards. Select global scope or a project represented by an active task. The form shows the target file, current overrides, live usable window, global fallback values for a project, and compaction accounting scope.

Enter token counts such as `500000`, `500,000`, or `500k`. Enter `default` to remove that scope's override. This form intentionally requires explicit counts instead of percentages. Both fields are validated before writing. Each changed existing file gets a timestamped backup beside it.

Settings write only top-level `model_context_window` and `model_auto_compact_token_limit` in the selected `config.toml`. Other settings remain intact. The monitor does not modify model capacity or bypass model limits. Project trust, ancestor configs, profiles and runtime overrides can affect effective configuration beyond the global/project view shown here.

Already-loaded desktop tasks can keep their previous runtime settings even after becoming idle. Saving a file does **not** reload a task. Reload the app/task through Codex as appropriate, then verify the live card. This edition does not promise queued runtime overrides or automatically archive/reload tasks. The configured compaction threshold can be constrained by model/runtime policy; `body_after_prefix` accounting cannot be compared directly with the card's total input size.

## Data and privacy

Context and token-counter processing stays local. The overlay reads `.codex/sessions`, `session_index.jsonl`, model metadata, config files, and optional state/log SQLite databases in read-only mode. Tokens mode additionally asks the Codex CLI to fetch subscription limits from its provider. The CLI owns authentication. The widget sends no telemetry and does not read authentication files itself. Full prompt contents are not displayed. No conversation files are copied into the release. The author link opens only when clicked.

`CODEX_HOME` selects a different Codex data directory. SQLite lookup honors top-level `sqlite_home`, then `CODEX_SQLITE_HOME`, then Codex home. Use absolute SQLite paths. A custom data path can also be supplied:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\Overlay.ps1 -CodexHome 'D:\CodexData'
```

Overlay preferences and window position are stored at `%LOCALAPPDATA%\CodexContextMonitor\overlay.json`. Startup uses the current Windows environment. For persistent custom paths, configure the environment before starting the watcher; one-off command-line paths are not saved as startup defaults.

If the data folder is absent, the overlay reports the error. Create/use your Codex installation, set the path, then reopen the overlay. The monitor depends on local file formats and may need updates when Codex changes them.

## Architecture and tests

`Monitor.Core.ps1` contains the existing incremental reader and config helpers. `Monitor.Data.ps1` produces plain snapshot objects. `Overlay.ps1` runs scanning in a background PowerShell runspace and updates WPF controls on the dispatcher. A 500ms UI timer consumes completed snapshots; data scans occur approximately every second, with indexed/fallback discovery reconciliation. There is no embedded web server. `Watch-App.ps1` handles optional app lifecycle detection independently.

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\test_settings.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\test_repository.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\test_overlay.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\test_install.ps1
```

The second test opens a temporary WPF test window, checks synthetic task lifecycle and actual settings buttons, borderless expand/collapse, corner snapping, opacity/corner persistence and minimize/hide/restore. It leaves a disposable fixture/report and expanded/mini screenshots in your temporary folder. It never changes your Codex settings. Startup shortcuts were separately tested using an isolated temporary shortcut, and live session reading was smoke-tested. Windows sign-in and physical dragging across mixed-DPI displays have not been tested.

## Credits and license

MIT. Built from Codex Context Monitor's console reader; the existing console release is preserved separately. See `METHODS.md` for borrowed design ideas and method comparisons with [LH-03/codex-monitor-hud](https://github.com/LH-03/codex-monitor-hud). This is an independent community utility, not an OpenAI product.

## Release 6.0

See BRANDING.md for palette sources and logo provenance. See AUDIT.md for disk, memory, CPU and verification results. ContextWidget.exe and Setup.exe are small launchers; the runtime is still Windows PowerShell/WPF, not a bundled browser or .NET runtime. SetCurrentProcessExplicitAppUserModelID and the custom window icon separate taskbar identity from PowerShell.

To remove: disable Auto-open in Widget settings and save, exit via the tray menu, remove your installed folder and the Context Widget desktop/Start-menu shortcuts. Preferences in LOCALAPPDATA\\CodexContextMonitor are retained unless you remove them separately. No Codex task data is deleted.

## Credits

Created by [Yahya Nabil](https://yahyanabil.com). Thanks to ccusage, CodexBar, Codex Monitor HUD and Codex Usage. See [Acknowledgments](ACKNOWLEDGMENTS.md) for authors and contributions, [third-party notices](THIRD_PARTY_NOTICES.md) for licenses, and [UI writing](UI-WRITING.md) for wording rules.
