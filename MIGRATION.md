# CTC 7.0: C# and WPF

The owner approved this migration on 1 October 2026.
Keep the PowerShell 6.8.9 source and release. New features use C# only.
The compiled version becomes the default download and prompt installation after the checks pass.

## Queue

- [x] Create .NET 10 core, WPF application, and fixture projects.
- [x] Port incremental session discovery, names, lifecycle, context and compaction signals.
- [x] Port token totals, subsets, tool calls, Exec details, command types and shell results.
- [x] Port account quota RPC, account isolation, freshness and quota estimates.
- [x] Port context parsing, percentages, anchored multipliers and conservative TOML writes.
- [x] Port idle project discovery, model catalog, settings inheritance and queued confirmation.
- [x] Port safe restart: idle gate, normal window close, expiry, cancellation and one reopen.
- [x] Build all WPF views: parked, compact, expanded, Context, Tokens, Limits and Queue.
- [x] Port tray, corner return, DPI logo, live opacity, startup watcher and preference migration.
- [x] Build compiled setup, update backups, rollback, startup shortcuts and uninstall.
- [x] Test core parity, corrupt/future records, locales, paths, accounts, errors and limits.
- [x] Test actual windows, installer, tray, startup, restart fixture and resource use.
- [x] Add compiled CI, package, MIT notices, attribution, recovery and installation guides.
- [ ] Install and open compiled CTC. Keep legacy files and settings.
- [ ] Publish compiled release as latest. Verify public downloads and prompt installation.

## Invariants

No PowerShell process runs the compiled application.
Monitor Codex records without changing them.
Write context settings only after Save. Do not replace recorded values with saved values.
Unknown values remain unknown. Tool call counts are not exact token charges.
Keep account identity, baseline and reset boundaries in quota estimates.
Preserve earlier versions and preferences. Use isolated fixtures for settings and restart tests.
A larger saved context value cannot increase model capacity.
Use STE for app text. Keep the existing palette and ctc artwork.
