# Changelog

## 6.8.5 - 30 September 2026

- Fix growing PowerShell type metadata during repeated quota reads. Use array indexes for persistent objects.
- Keep type names unchanged in quota, cached settings, parked chat, and token detail reads.
- Add repeated-read regression checks in both shells.
- Do not update hidden token panels. Keep parked context, tokens and quotas live.
- Cache parsed root settings. Compare file contents on each read. Keep at most 32 entries.
- Test same-size and same-time edits, duplicate keys, deletion, and cache limits.
- Correct unreadable symbols in the README. Add Queue and Parked bar to its view table.
- Find Codex desktop by its primary app path. Support ChatGPT.exe inside OpenAI.Codex.
- Exclude ordinary ChatGPT, CLI binaries and bundled helpers from restart targets.
- Detect visible desktop apps without a fixed executable-name list.
- Test package versions, renamed desktop files, excluded helpers and normal fixture close/reopen.

## 6.8.4 - 30 September 2026

- Match the Tool calls label and value to the token metric tiles.
- Keep the full-width tile. Put its expand arrow on the right.
- Use the Exec metric layout for Command types, Shell results and exit codes.
- Keep request categories and script references separate.
- Preserve detail controls when their values change.
- Check the compact and expanded WPF views in PowerShell 5.1 and 7.

## 6.8.3 - 30 September 2026

- Use a full-width tile for Tool calls in the token grid.
- Add expandable Exec results, command types, script tools and reported shell results.
- Read native input_text blocks. Count unique outputs and shell result IDs.
- Show missing status and missing results. Keep wall time separate from call-to-result spans.
- Mark script references as references. Do not claim that every nested call ran.
- Keep command text and tool output out of stored activity data.
- Bound large output scans. Use a compiled in-memory script scanner with a PowerShell fallback.
- Copy activity totals before the UI reads them. Keep collector IDs private.
- Add native-format, privacy, live append, output deduplication and large-record tests.
- Skip unchanged token details. Avoid resetting metrics before updates. Skip JSON parsing for raw JavaScript.

## 6.8.2 - 30 September 2026

- Display a single weekly quota in Windows PowerShell 5.1. Do not add a missing 5-hour window.
- Refresh after sign-in metadata changes. Reject older account responses. Separate quota estimate histories by account.
- Repair repeated estimate history saves.
- Open new installations in the small bar. Set background opacity to 85%. Apply startup preferences to automatic launches.
- Add Queue beside Limits. Keep restart controls visible while saved changes scroll. Keep changes after CTC closes.
- Keep Queue open during Expand and Collapse. Block restart when chat state is active or unknown.
- Put Tool calls in a full grid row. Add an Exec section with recorded counts.
- Add token section dividers. Put Data status and How counts work beside each other.
- Make Minimize show the small bar. Remove Park. Put Corner in its place.
- Test queue persistence, cancellation, weekly-only accounts, login changes and both WPF layouts.

## 6.8.1 - 30 September 2026

- Reject saves from a form that has older settings than the file.
- Let Undo recover after the user corrects an invalid settings file.
- Read parent project limits for chats inside a Git repository.
- Remove old usage when a new context window has no usage record.
- Save limits after Default leaves an empty settings file.
- Preserve comments and formatting when limit values do not change.
- Reject invalid writer values before changing a settings file.
- Use decimal arithmetic for percentage input.
- Read quoted model names after multiline instructions. Keep setting names case sensitive.
- Add 85 limit cases and an isolated Codex engine test.

## 6.8.0 - 30 September 2026

- Show saved limits as pending until recorded context confirms them.
- Add a queued restart with idle checks, cancellation, and normal app close.
- Arrange multipliers and percentages below their fields. Keep Undo and Default on a shared row.
- Replace token paragraphs with metric cards and expandable details.
- Count recorded tool calls. Keep unavailable tool and automation token costs unknown.
- Replace Park with a small information bar at the same corner.
- Keep the selected Tokens view during installation. Merge quotas with stable IDs.
- Add an independent architecture review and a staged C# / WPF migration plan.


## 6.7.1 - STE app text

- Use STE wording in labels, help, status, errors, setup, and current user guides.
- Add a project term list and writing rules for future changes.
- Keep source error details, user content, names, license notices, and historical evidence exact.
- Keep the context editor behavior and previous release files.

## 6.7.0 - context editor

- Edit project/global limits inside the compact widget. Select the displayed chat's project directly; keep Save visible while details scroll.
- Add anchored 1x/2x/3x window previews, preserving numeric compaction ratios and exact entered percentages. Unknown baselines require explicit numeric input.
- Add 80%/90%/95% compaction presets, Undo, and Default previews. Only Save writes settings.
- Share validation and controls across chat cards and the scope editor. Reject compaction above an entered window, disable invalid/no-change saves, and show known local catalog warnings without claiming model capacity increases.
- Keep saved/live metadata and detailed guidance behind disclosure. Preserve older releases and configuration backups.
- Record MIT design references with exact source revisions; no upstream code or binaries copied.

## 6.6.1 - simple wordmark

- Replace the interlocking logo with lowercase ctc in Segoe UI Semibold, using the existing blue-grey palette.
- Update the widget, restore tab, tray, taskbar, installer, executables and shortcuts from the same icon source. Remove the redundant uppercase header label.
- Preserve previous releases and user preferences.

## 6.6.0 - startup recovery and shared quotas

- Retry failed initial launches until the overlay acknowledges a ready window. Detect visible app instances every 1.5 seconds without caching an app package version.
- Publish current context and cumulative tokens from a lightweight whole-file scan, then rebuild detailed history in the background.
- Load the precompiled taskbar identity bridge from the launcher instead of compiling C# during every widget launch.
- Create ZIP entries with canonical forward-slash paths under both PowerShell versions, preserving strict installer path checks.
- Show account quota bars and Refresh below the tabs in every view. Keep network reads separate from local startup.
- Move Tray beside Expand, label the edge-tab action Park tab, and remove the duplicate context settings icon.
- Use a consistent 370 by 480 compact layout. Check the actual content viewport for clipping.
- Add quick/full parity tests and startup checks to Windows CI. Previous versions remain in update backups.

## 6.5.0 - quota share and compact details

- Fix arrow/counter spacing, including large chat counts.
- Show account quota used and model-weighted local chat estimates.
- Add bounded history, conservative missing-data handling and separate reset windows.
- Expand token detail without adding rows to the collapsed view.
- Credit research methods and add estimator tests.


## 6.4.1 - percentage compaction input

- Accept percentages in Compact at in both context editors; preview the converted token count.
- Require an explicit numeric context window; save the calculated token threshold.
- Exercise percentage input through the inline editor save test.

## 6.4.0 — audit repairs

- Preserve TOML strings and quoted keys; reject unsupported edits before writing.
- Save both context limits in one atomic replacement with conflict checks and backup.
- Read Unicode project roots as UTF-8; retain valid fallback names.
- Clear usage when its context window changes; recover from missing indexed paths.
- Prefer the newest quota observation; allow up to 45 seconds for CLI startup/response and report the timed-out phase.
- Validate preferences, preserve invalid originals, and roll back failed installations.
- Bound inactive rollout history and reuse discovery results between reconciliations.
- Enforce a useful expanded minimum height; refresh setup icon and documentation.
- Add regression fixtures covering audit failures and slow CLI initialization.

## 6.3.7 — text encoding fix

- Use plain separators in runtime labels so Windows PowerShell 5.1 reads them correctly.
- Reject BOM-less non-ASCII runtime scripts in repository checks.
- Preserve Unicode chat names and project paths from data sources.

## 6.3.6 — quieter layout

- Shorten headings and status summaries; preserve diagnostic detail in tooltips.
- Group secondary context and subscription details behind expanders.
- Keep active token details visible; align subscription bars side by side.
- Reduce repeated input guidance and improve footer button spacing.

## 6.3.5 — compact quota bars

- Replace Context quota text with small side-by-side remaining-usage bars.
- Show reset times and observation timestamps in tooltips; mark older readings.

## 6.3.4 — compact context shortcut

- Edit context from the collapsed card opens that displayed chat's inline project editor.
- Show a percentage example and live compact/window ratio in both editors.
- Keep numeric input explicit: enter tokens; percentages are guidance.

## 6.3.3 — visual audit fixes

- Separate CTC letter shapes and use the high-resolution icon frame in the header.
- Remove the duplicate expanded toolbar from view; retain header and footer controls.
- Apply opacity only to the background; retain saved slider values.
- Theme scrollbars, expanders and progress bars; add keyboard-focus outlines.
- Use selected fills instead of dimmed navigation labels.

## 6.3.2 — interlocking identity

- Bold interlocking CTC icon in the widget, tray, launchers and setup.
- Keep active-chat context editors in Context; remove them from Tokens.

## 6.3.1 — app launch detection

- Track separate visible app instances instead of one combined running flag.
- Detect process/window replacement and package updates without version-pinned paths.
- Ignore background renderer and CLI processes; retry transient launch failures.
- Launch the branded executable directly; default new installs to ChatGPT or Codex.
- Add PowerShell 5.1/7 regression tests for independent launches and update transitions.

## 6.3.0 — active chats and update resilience

- Five-color user palette; chat terminology in the widget.
- Active-chat token details lead the view; missing first counters stay unknown.
- Fixed 24-pixel wheel steps and retained scroll position on live refresh.
- Inline project context editors on active chat cards; numeric examples and defaults apply to all models.
- Limits discovers idle projects through saved projects and the local project/thread indexes.
- Isolated quota-helper SQLite state, graceful helper shutdown and queued-follow-up audit.
- GitHub installation helper, one-prompt instructions and repair guide.

## 6.2.0 — Context-Token Codex

- Rename the public product and shortcuts; original CTC logo in every application surface.
- User-selected charcoal, ivory and amber palette.
- Integrated Limits tab with aligned fields, saved/live summary and expandable help.
- Centered button content, matched header controls and more room in compact mode.
- Styled dropdowns and safe migration of shortcuts owned by the same installation.

## 6.1.0 — detailed live token view

- Input, output, cache, uncached input, reasoning and cache-hit metrics.
- Expandable task details, exact localized counts and partial-data indicators.
- Read active session changes every second; show record time and read status.
- Test a live append through the running WPF background reader and visible metrics.
- Replace explanatory paragraphs with short labels, tooltips and expandable help.
- Add STE-inspired and Windows UI writing rules, acknowledgments and upstream MIT notices in both source and installed distributions.

## 6.0.1 — compatibility hardening

- Tolerate missing profiles, reordered JSON fields and invalid token counters.
- Refresh renamed tasks in session-index fallback; retain cumulative counter timestamps across compaction.
- Retry older subscription RPC parameters, bound helper lifetimes and preserve fractional quota percentages.
- Report incompatible compaction log schemas as completion-only monitoring.
- Add compatibility and CLI failure fixtures; run native UI and installer tests under both PowerShell versions.
- Prepare a four-combination Windows CI matrix and document actual test coverage.

## 6.0 — Context and Tokens modes

- Persistent Context/Tokens switch in compact and expanded views.
- Live read-only subscription usage via the Codex CLI, with local-record fallback, freshness labels, dynamic windows and reset times.
- Recorded cumulative token totals with explicit coverage and cache semantics.
- CodexBar method attribution and MIT project comparison in USAGE-METHODS.md.
- Yahya Nabil author line and clickable yahyanabil.com link.

## 5.0 — initial public source release

- Native borderless Windows widget, compact/expanded views and live opacity.
- Context limits and widget settings embedded in the overlay.
- Current task titles, token usage, compaction status and active-task navigation.
- Context-ring logo, three-color Nord-derived identity and branded Windows launchers.
- Per-user setup wizard; optional auto-open defaults to enabled.
- Persistent notification-area icon and optional visible edge restore tab.
- MIT license, original-source build, fixture tests, documentation and resource audit.

Earlier console and overlay iterations remain preserved locally by the original developer. They are not part of this repository's source history.
