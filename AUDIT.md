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
