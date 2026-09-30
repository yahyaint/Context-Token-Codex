# Version 6.8.3 verification - 30 September 2026

- Fifteen backend suites pass in Windows PowerShell 5.1 and PowerShell 7.
- The limit matrix passes 85 cases per runtime. The native Sol and Astra fixtures passed 24 checks.
- Actual WPF controls pass in both runtimes: queue controls, cancellation, idle gates, grid layout, startup, opacity and saves.
- Native text-block outputs were checked against local records. Exec outcomes and reported shell results are available.
- Activity summaries keep categories, counters and timing. They exclude commands, arguments, stdout and internal correlation IDs.
- A single weekly account reading displays one 7d bar in the actual installed PowerShell 5.1 widget.
- The actual /auto launcher parks the widget at 85%. The manual launcher restores it.
- Installation checks preserve the previous runtime and current preferences.

The first real-profile context scan took about 3 seconds on this host.
The full activity backfill took about 32 seconds. Context appears before that backfill finishes.
This is not a clean-machine or long-duration benchmark. New records use the existing file offsets.
The full backfill delay remains a performance limit on large histories.
A PowerShell 5.1 collector comparison after garbage collection measured about 18 MiB managed memory before activity details and 26 MiB after them.
The next scans took about 0.2 seconds in both versions.
A live Tokens working-set sample reached about 900 MiB. This did not prove a retained-data leak.
CTC now skips unchanged detail formatting and does not reset each metric before an update.
A 45-second synthetic Tokens run measured about 67 MiB managed memory and 242 MiB working set.
A fresh real Tokens run after the data-change gate measured 98 MiB managed memory and 319 MiB working set with three chat panels.
Those samples are not directly comparable. Real long-duration Tokens memory remains unverified.
Hosted CI, ARM, a separate Windows machine and a real Windows sign-in are unverified.
No running Codex chat was closed. Real saved context values still need a safe reload and a new usage record.
Public download remains unverified until publication. GitHub publication is held.

---

# Version 6.8.1 context limit audit - 30 September 2026

The limit matrix passes all 85 cases in PowerShell 5.1 and PowerShell 7.
The updated WPF test checks both window sizes and real save handlers.
The audit found stale-save overwrites, missing parent settings, stale usage after capacity changes, and empty-file save failures.
Those failures have regression tests and repairs.
Percentage calculations now use decimal arithmetic. Invalid writer values cannot change settings.
Unchanged saves preserve comments and do not create restart requests.
See [LIMITS-VERIFICATION.md](LIMITS-VERIFICATION.md) for the native checks and repeat commands.

The real saved project values are 544000, 544000, and 500000.
The two active chats still record 258400. Their actual desktop reload is pending.
No real Codex chat was closed or changed during the audit.

---

# Version 6.8.0 verification - 30 September 2026

Eleven backend checks passed in PowerShell 5.1 and PowerShell 7.
The checks cover settings, context editing, quotas, activity, estimates, schema fallback, startup, watcher logic, restart gates, regression fixes, and installation.
The WPF overlay and setup wizard passed in both runtimes.
The widget test checks live counter updates, scroll preservation, both sizes, corner placement, tray restore, opacity, and settings writes.
The parked bar passed data and all four corner checks. Its image was inspected.
The token cards and context controls were inspected in rendered fixture images.

The restart flow passed with a separate fixture app outside the sandbox in both runtimes.
It requests a normal close, waits for exit, and reopens once. Real Codex was not closed.
Sandbox window messaging did not close the fixture; this limitation was tested outside the sandbox.

The real project configuration resolves to 544000 through Codex config/read.
The current loaded chat reports 258400. Its saved change awaits a fresh session and usage record.
CTC shows pending status and restart controls. It does not replace measured counters with saved values.

The independent architecture review found two P2 issues. Tests confirm both repairs.
The installer retains Mode. Quota merging uses stable identities rather than display names.

Only the current Windows host was tested locally. Windows 10 and other machines remain unverified.
The CI matrix is prepared for Windows Server 2022/2025 and both PowerShell runtimes.
CI, public GitHub download, and the pending Codex desktop update remain untested until publication or a separate approved app restart.
No restart can guarantee idle state on other devices. CTC checks local recorded lifecycle data.

Installed version: 6.8.0. All 26 runtime files match the working source.
Preferences and the previous version are retained. One widget and one watcher are running.
The ready event is set. Runtime size: 290133 bytes. ZIP size before final documentation: 177871 bytes.
Real-profile quick snapshot: 2.3 s. Background scan: 4.2 s. Three files were discovered on this host.

## Earlier audit evidence

# STE text - 6.7.1

The app uses short instructions and defined software terms.
The writing rules apply to future changes.
User content, source error details, license notices, and historical evidence stay exact.
The context editor behavior does not change.
See UI-WRITING.md and AGENTS.md for the rules.

# Context editor - 6.7.0

Compact project editing, anchored multipliers, percentage presets, scoped saved/live values, preview-only reset controls and catalog warnings share the same helpers as the expanded editor. The release checks cover these controls in disposable fixtures; they do not alter real Codex limits. Source credits are in ACKNOWLEDGMENTS.md. Older verification below remains historical.

Windows PowerShell 5.1 and PowerShell 7: context editor helpers, settings, regression, repository/isolated-install, local bootstrap checksum and WPF overlay suites passed. UI fixtures check anchored scaling, ratio retention, exact percentages, mini controls, expand/collapse draft retention, idle project writes, Undo/Default previews, invalid drafts and catalog warnings. Both layouts were rendered and inspected. Hosted CI, a separate clean machine and actual sign-in/reboot remain untested.

# Release 6.6.1 logo validation - 30 September 2026

- New lowercase ctc wordmark uses Segoe UI Semibold and the existing ivory/ink palette. One icon source supplies seven resolutions and both executable resources, widget header, tray, taskbar, setup, restore tab and shortcuts. README includes the generated preview; no font file is bundled.
- Visual inspection of 16/24/32/48/64/128-pixel icons and the compact widget: lettering is readable, redundant header text removed, controls and context edit button fit.
- WPF overlay and actual installation wizard passed under Windows PowerShell 5.1 and PowerShell 7. Repository payload/syntax and release checksum checks passed. Prior runtime and user preferences are retained during deployment.
- Startup/reader behavior is unchanged from 6.6.0. See the preceding validation below for performance and platform limits.

---
# Release 6.6.0 validation - 30 September 2026

- Eighteen relevant suite executions passed on Windows 10.0.26200: startup, watcher, compatibility, usage, estimator, regressions, repository/install and bootstrap, each under Windows PowerShell 5.1 and PowerShell 7; plus the WPF overlay under both shells. Startup parity was rerun after the reordered-record fallback was added; WPF checks were rerun after replacing runtime C# compilation with the precompiled launcher bridge.
- Startup fixtures compare quick and full state across a large history, long running chat, completed chat, changed context window, totals-only/quotas-only records, compactions, reordered large payloads, detailed-history reconstruction and partial appends. Watcher fixtures exercise changed app package versions, process/window replacement, launch readiness, delayed retry and intentional close.
- WPF checks cover embedded limits, live token appends, small quota bars, mini edit shortcut, mode switching, opacity, 40-chat scrolling, tray/park restore and the actual content viewport. Visual inspection confirmed the compact edit button is fully visible at 370 by 480; the earlier 440 layout clipped it despite a StackPanel height check.
- A fresh-process local scan comparison on this busy desktop read about 27 MiB: preserved 6.5 full scan 5,339 ms, 6.6 quick scan 1,871 ms. Source-loading time was separate (913/686 ms). These are single observed runs on changing live data, not a controlled cold-disk benchmark or an end-to-end boot guarantee. Detailed history is rebuilt on the following background pass; network quota latency is separate.
- Installed startup integration with the updated OpenAI.Codex 26.928.2636.0 package: starting only the watcher opened a ready CTC window; one watcher and one overlay, real local state and live account quota bars were verified. App version detection and the Startup shortcut worked during diagnosis; an existing watcher had no overlay. The original missed-launch cause could not be proven without earlier readiness/error logs. Failed initial launches now retry until readiness is acknowledged.
- Windows PowerShell 5.1 packaging exposed backslash ZIP entries rejected by the strict installer. Packaging now emits canonical forward-slash entries; local checksum verification and rejection of a bad checksum passed in both shells.
- Runtime manifest remains 24 files, about 245 KiB without preferences/backups. Previous runtime retained under Versions. MIT and upstream credit remain present. Local Git and Windows release are prepared; no public push is implied.
- Actual Windows sign-out/sign-in/reboot, another physical machine, ARM, mixed-DPI hardware, hosted CI and long soak were not tested. Package identity fixtures and verification against the installed updated app reduce update risk; complete private schema changes can still need repairs. See RECOVERY.md.

---
# Release 6.5.0 validation - 24 September 2026

- Twelve suites exercised under Windows PowerShell 5.1 and PowerShell 7: settings, regressions, usage, estimator, compatibility, transport, watcher, repository, bootstrap, overlay, theme and install. The first PS5 estimator run caught a DateTimeOffset serialization issue; explicit ISO timestamps fixed it. Estimator/persistence, repository, regression and usage checks were rerun successfully after the fix and payload changes.
- Estimator checks: relative Astra/Sol weights, cached input, unknown models, concurrent allocation, duplicate samples, stale readings, reset isolation, missing usage, history persistence/corruption, profile changes and per-event model switches. These verify calculation mechanics, not exact agreement with private subscription charging.
- WPF visual inspection: mini navigation at 2 / 2, compact token summary, account percent-used bars and expanded token details. Layout assertions verify at least seven device-independent pixels between counter and arrows for 2 / 2 and 128 / 128.
- Expected runtime payload: 24 files. Rates and estimator are independent local components; no third-party executable or source copied. New history contains current-window estimates and chat IDs, no credential contents or messages.
- Attribution remains a local-only estimate. A known model's standard credit weights are a relative proxy; missing speed assumes Standard. Unknown models, explicit non-Standard tiers, requests above 272k input, child-agent events and observation gaps stay unattributed. Other-device use during local activity cannot be identified exactly. History invalidates on profile/login-file metadata changes; keychain-only account changes require clearing estimator history.
- No account-limit changes, model requests, public push, unrelated-machine test, long soak or backend-accuracy guarantee is implied. Historical performance measurements below are not new 6.5 benchmarks.

---
# Release 6.4.0 audit repairs

Verified 22 September 2026 on the development Windows 10.0.26200 desktop. All twelve findings from the 6.3.7 audit have implemented fixes and targeted checks. The live quota timeout has also been addressed with a longer startup budget, phase-specific errors and a delayed-initialization fixture. Its earlier intermittent environmental cause remains unproven.

## Verification

- **22/22 suite executions passed:** settings, regressions, usage, compatibility, transport, watcher, repository, bootstrap, overlay, theme and install, each under Windows PowerShell 5.1 and PowerShell 7.6.5.
- Regression fixtures cover multiline/quoted TOML, combined settings replacement, locked writes, Unicode roots, blank titles, changed context windows, stale indexed paths, inactive retention, empty discovery, resumed names and lifecycle ordering, quota bucket freshness, invalid preferences and failed-install rollback.
- Visual inspection of rendered limits and token views: controls remain aligned, context inputs and examples visible, quota bars side by side, author/footer and opacity controls visible.
- Real read-only subscription query with Codex CLI 0.155.0-alpha.9.2 returned two windows. A follow-up completed in 1.06 seconds. No model turn or queued-message mutation was requested.
- Installed 6.4.0 and restarted CTC; all **21 installed runtime files** match the tested source hashes. One responding overlay and one responding watcher were present. The preceding installation was retained in Versions.
- Settings tests use disposable fixtures; real Codex context limits were not changed.

## Size and resource sample

Runtime payload: **216,646 bytes**, 21 files, excluding preferences, backups and existing Codex data. No bundled browser or language runtime.

A 15-second post-install sample on this busy development desktop:

| Process | Working set | Private bytes | CPU, one-core basis |
|---|---:|---:|---:|
| Overlay | 210.7 MiB | 190.2 MiB | 6.43% |
| Watcher | 92.0 MiB | 70.3 MiB | 0.42% |

CPU is processor-time delta divided by elapsed wall time; this is not whole-machine utilization. Working sets can share pages. These short samples do not establish a memory-leak result or a controlled performance improvement over older long-running instances.

## Limits of verification

Both shell versions ran on the same Windows machine. No clean unrelated PC, Windows ARM, physical mixed-DPI setup, actual sign-out/sign-in, hosted CI or long-duration soak was tested. The executables remain unsigned. Future Codex schema changes can require adaptation; see RECOVERY.md. Context writes use a conservative TOML-aware boundary scanner, not a complete TOML formatter; unsupported syntax is rejected. Installation rollback can report recovery failure if the filesystem also prevents restoration.

## Reproduce

Run all eleven Tests/test_*.ps1 suites listed in CONTRIBUTING.md under each supported PowerShell version. Build/package.ps1 builds the release ZIP and SHA256 receipt. Preserve the printed fixture paths for diagnostic reports and rendered screenshots.

---
# Release 5.0 audit

**Historical baseline:** these resource measurements are for v5.0. Version 6.0 adds a background quota runspace and a short-lived Codex CLI helper while reading subscription limits; its resource use has not been re-benchmarked. V6 validation additionally covers quota maps, missing/weekly-only windows, reset handling, cumulative-token deduplication, mode switching, author-link controls, and a successful live read-only CLI quota query. The installer and existing overlay regression suites also passed.

Tested on the development Windows desktop, 18 September 2026. Measurements are local observations, not universal system requirements.

## Disk footprint

- Installer-selected runtime payload: 13 files, 136,917 bytes (133.7 KiB) before the final README wording update. No bundled .NET/PowerShell runtime or browser engine.
- ContextWidget.exe: 20,480 bytes. Setup.exe: 20,480 bytes. These launchers start Windows PowerShell; they do not replace the runtime.
- Seven-resolution logo ICO: 15,176 bytes.
- Full source distribution, including wizard, tests and reproducible launcher build source: approximately 180 KiB before compression. See the accompanying release size report for final package totals.
- Backups, user preferences and existing Codex session databases are excluded. Updates preserve old versions, so installed-folder totals grow with retained backups.

## Live runtime sample

The installed widget was monitored over approximately 15 seconds after startup while reading this machine's real Codex state:

| Measure | Observed |
|---|---:|
| Widget peak working set | 195.1 MiB |
| Separate auto-open watcher working set | 91.4 MiB |
| Combined working set (sum, may include shared pages) | 286.5 MiB |
| Widget CPU, normalized to one logical core | 3.5% |
| Startup watchers running | 1 |

CPU percentage is processor-time delta divided by wall time for the widget process only. It is not whole-machine CPU utilization. Watcher CPU was not measured. Working-set totals can double-count shared pages. Cold startup consumed more CPU than steady polling. A separate 22-second live smoke test passed ten scans and hide/restore checks.

Conclusion: disk distribution is small; RAM is the principal cost. PowerShell/WPF and the separate PowerShell watcher dominate overhead. A future native watcher could reduce it. This audit is not a long-duration leak test or a promise of identical performance on other machines.

## Verification performed

- Actual installer UI: Next, Install, completion; startup checked by default.
- Isolated install: payload copied, custom-icon startup shortcut targets ContextWidget.exe /watch.
- Upgrade: previous files backed up, opacity preference retained; disabling startup removes the shortcut.
- Invalid drive-root destination rejected; three-color theme checked.
- Settings helpers: numeric parsing, defaults, TOML preservation, backups, model metadata handling.
- Synthetic task lifecycle: title, Astra model, input usage, compaction count and completion removal.
- Borderless WPF: mini/expanded rendering, opacity changes, saved opacity/corner, snapping, minimize and restore.
- Regression: hiding across separate dispatcher ticks keeps the UI loop and tray icon alive.
- Embedded settings: save buttons work after the panel-opening function returns; no modal settings window is needed.
- Visual inspection: mini card, redesigned slider and embedded context form.
- Installed launch: branded executable opens a responding widget; real startup shortcut points to that executable and custom icon.

Not verified: an actual Windows sign-out/sign-in, a clean unrelated PC, ARM Windows, mixed-DPI physical dragging, SmartScreen reputation, or long-duration memory stability. Executables are unsigned. Windows determines taskbar/notification-area placement. No tests edited real Codex context limits; fixture-only settings tests were used.

## Reproduce

Run Tests/test_settings.ps1, Tests/test_overlay.ps1 and Tests/test_install.ps1 with Windows PowerShell 5.1. Build/build.ps1 regenerates the ICO and both launchers using the Windows .NET Framework compiler. Tests leave disposable reports under the temporary folder and do not enable startup for the real user.
