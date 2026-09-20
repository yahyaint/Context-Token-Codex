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
