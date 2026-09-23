# Context-Token Codex 6.5.0

A Windows widget for local Codex context, token counts and subscription usage.

**Windows 10/11 | MIT | Independent community project**

Created by **Yahya Nabil** — [yahyanabil.com](https://yahyanabil.com).

## Install

Download the Windows release ZIP, verify its SHA256, extract it and open **Setup.exe**. The installer creates CTC shortcuts, preserves settings and backs up the previous runtime. Auto-open with ChatGPT or Codex is enabled by default. Installation needs no administrator access or downloaded runtime.

See [INSTALL.md](INSTALL.md) for the GitHub CLI command and copy-paste Codex installation prompt. These require a published repository/release. Publication is pending the owner's explicit approval.

From source, build first:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build\build.ps1
```

Then open `Setup.exe` or `ContextWidget.exe`. Executables are generated, not committed. The Windows package includes them. Launchers are unsigned.

You can also launch from an extracted folder. **Default auto-open creates a Startup shortcut pointing to that folder.** Disable Auto-open in Widget settings before moving/deleting it; enable it again from the new location. This is portable storage, not a no-persistence mode.

## Views

- **Context:** active chats, measured context percentage, compaction state and side-by-side 5h/7d quota bars. Details holds secondary readings.
- **Tokens:** active-chat cumulative totals, input, output, cache, uncached input and reasoning; loaded-chat totals and subscription readings.
- **Limits:** global and project defaults, including saved idle projects. Applies to all models in the chosen scope.
- **Collapsed:** one selected active chat. Previous/next changes the chat. **Edit context limits** expands that chat's project editor.

Current chat names come from local desktop state or the session index. Initial text is a tooltip fallback. Missing data stays unknown rather than being invented.

Context is the latest recorded request, not a continuous measurement inside Codex. Token counters update when new local records arrive. Changed model windows clear incompatible old context readings. Compaction completion comes from session events; live compaction-start indicators need compatible SQLite logs.

## Context settings

Enter `180000`, `180k`, or `default`. **Compact at also accepts percentages**, e.g. `90%` with a `200k` context window saves `180000` tokens. Decimal percentages are supported, above 0 through 100. Enter a numeric context window first; `default` has no fixed denominator across models. The live hint previews the token result. Percentages are converted on save, not stored as a rule for future window changes.

Window and compact changes are prepared together and atomically replace the selected file, with a backup and an intervening-change check. The editor preserves multiline strings and ordinary quoted keys. Unsupported root-key syntax is rejected before writing; edit such a file through Codex instead. This is a conservative scoped editor, not a general TOML formatter.

These are project/global defaults, **not persistent per-chat or per-model overrides**. Loaded chats may require a reload. There is no apply-on-idle queue. A configured number does not increase the model's supported capacity. Live usable capacity may differ from the raw configured window.

## Window controls

Drag the header to move; drop near a corner to snap. Expand shows all active chats; Collapse shows the mini card. Expanded views have a 520-unit minimum height where the screen permits it.

- **Background:** live background opacity, 40–100%; text and controls stay opaque.
- **Pinned:** always on top.
- **Corner:** move to a screen corner.
- **Tray:** hide; restore with the CTC icon beside the Windows clock, possibly inside the overflow menu.
- **Park:** show a small restore tab at the screen edge.
- **Minus:** minimize to the taskbar. **Close:** exit the widget.

The footer includes the author and website. Opening the launcher again restores an existing hidden widget.

## Startup

Widget settings chooses Codex, ChatGPT or Either. Auto-open adds a per-user Startup shortcut and a watcher. The watcher polls visible app instances every five seconds; identities include the process/window and do not pin a package version. CTC stays open after the watched app closes. Exit stays respected until another app launch or manual launch.

The watched application controls when CTC opens. **ChatGPT conversations are not monitored**; data comes from local Codex files.

## Quotas and token totals

Tokens mode asks the installed, signed-in Codex CLI for subscription readings, roughly once a minute after a refresh finishes. Refresh allows an earlier request. Requests run off the UI thread with a 45-second bound; errors identify initialization versus subscription-response timeout.

The newest observation wins for each quota window. Other available buckets remain visible; older readings are marked with `*`. Hover shows observation/reset times and source. Retry indicates a failed refresh. Missing readings are not treated as zero.

Cumulative totals cover currently retained user chats, not today's usage, billing, account lifetime totals, or plan tokens remaining. Discovery considers recent files (24 hours, up to 128 by default). Active rollouts are retained; inactive rollouts are bounded by age and count. Totals can change when inactive history expires. Cached input is a subset of input; reasoning is a subset of output. Subagent counts are excluded to avoid misleading aggregation. See [USAGE-METHODS.md](USAGE-METHODS.md).

## Data and privacy

The application reads session files, title indexes and optional local SQLite state. Queries use read-only SQLite access. Prompt bodies are not a UI feature; names/initial-title tooltips can contain user text. Do not share private screenshots or diagnostics without reviewing them.

Subscription refresh starts a Codex CLI helper. The CLI owns authentication and provider network access. CTC does not extract credentials or read browser cookies; it requests a separate SQLite state directory for the helper and sends initialization plus account rate-limit reads. No task/queue mutation RPC or telemetry is implemented.

Settings saves write only the selected context configuration. No queued Codex messages are edited. Release packaging explicitly excludes conversation data, credentials and local preferences.

`CODEX_HOME` selects the data profile. SQLite discovery honors `sqlite_home`, then `CODEX_SQLITE_HOME`, then Codex home. `sqlite3.exe` on PATH is optional; without it, session-file fallback remains available. Custom launch:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\Overlay.ps1 -CodexHome 'D:\CodexData'
```

One-off profile arguments are not saved to startup. Preferences live at `%LOCALAPPDATA%\CodexContextMonitor\overlay.json`. Invalid values fall back to defaults; originals are retained as `.invalid-*.bak` before normalization.

## Recovery and removal

See [RECOVERY.md](RECOVERY.md) for a Codex repair prompt, failure checks and rollback. Failed installations restore captured runtime/preferences/shortcuts where possible; a rollback failure reports the paths that need manual recovery. Existing update backups remain available.

To remove: disable Auto-open and save, exit CTC, delete its installed folder, and remove the **Context-Token Codex** desktop/Start-menu shortcuts. Preferences and helper state under `%LOCALAPPDATA%\CodexContextMonitor` can be removed separately. Do not delete Codex's own profile.

## Development and compatibility

Windows PowerShell 5.1/WPF and desktop .NET Framework are the runtime; PowerShell 7 is also tested. Small launchers do not imply a small RAM footprint. See [AUDIT.md](AUDIT.md), [COMPATIBILITY.md](COMPATIBILITY.md), and [CONTRIBUTING.md](CONTRIBUTING.md).

Private Codex schemas can change. Versioned discovery, read-only fallbacks and regression fixtures reduce risk; they cannot guarantee every future update. Hosted Windows CI, a separate Windows machine, mixed-DPI hardware, ARM and long-duration soak checks are not claimed unless documented as completed.

## Credits

MIT. Thanks to ccusage, CodexBar, Codex Monitor HUD and Codex Usage for referenced ideas. [Acknowledgments](ACKNOWLEDGMENTS.md), [third-party notices](THIRD_PARTY_NOTICES.md), [methods](METHODS.md), [branding](BRANDING.md), and [UI writing](UI-WRITING.md) describe provenance. This is not an OpenAI product or an endorsed upstream fork.
## Quota estimates (6.5.0)

Tokens mode shows actual account **5h / 7d percent used**, the reported plan, and an **Est. tracked share** below each chat. Estimates allocate observed quota increases using each chat's model-weighted uncached input, cached input and output. The model is recorded per token event; reasoning is already part of output. They are local-only estimates, not exact subscription charges or lifetime chat percentages. Other devices can contribute to the same account readings.

`--` means not enough reliable data. Monitoring needs two fresh observations and supported local token deltas. Estimates cover matched intervals since the displayed baseline, independently for each reset window. Missing events/models, gaps over ten minutes, explicit non-Standard speed, long-context requests over 272k and subagent intervals stay unattributed. An absent speed field assumes Standard. Account bars remain usable regardless of estimator coverage. No hours estimate is shown.

Expand **Token and quota details** for cached/uncached input, cache hit rate, reasoning/other output, latest request, last model, compactions and estimate coverage. The total covers all recorded models; it is not re-priced using the last model.

`Quota.Rates.json` contains dated relative weights sourced from official rates. Unknown models get no invented price. Weights expire after 90 days until reviewed; rates do not establish an account's subscription ceiling. `Quota.Estimator.ps1` implements the independent allocator. Current-window history checkpoints every 30 seconds under `%LOCALAPPDATA%\CodexContextMonitor\QuotaHistory`; a changed profile/login-file timestamp starts a new baseline. Credential contents are not read. Keychain-only account changes cannot be detected from file metadata: restart with cleared quota history after such an account switch. History contains chat IDs and estimates, not messages or credentials.

See [quota research](QUOTA-RESEARCH.md) for methods, assumptions and references. Removing only the QuotaHistory folder resets estimates; token logs and account quotas are unaffected.
