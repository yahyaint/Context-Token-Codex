# Technology review - 30 September 2026

## Decision

Use **C# with .NET 10 LTS and WPF** for the next compiled version.
Keep this PowerShell version during migration.
This decision does not claim a measured CPU or memory reduction.

CTC already uses WPF. Its PowerShell script creates Windows controls directly.
C# can reuse adapted XAML, window behavior, styles, and Windows integration.
Typed services and view models can separate reading, settings, and presentation.
See the [WPF overview](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/overview/) and [.NET support policy](https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core).

## Alternatives

| Technology | Use when |
|---|---|
| C# / WPF | Windows remains the product scope. This option needs the smallest UI migration. |
| WinUI 3 | Windows Fluent controls become a requirement. The UI and deployment need changes. |
| Avalonia | macOS and Linux become supported targets. WPF controls need adaptation. |
| Tauri | The team chooses HTML/CSS and Rust. Windows needs WebView2 and a web/native interface. |
| Electron | The team already uses JavaScript. Measure all Chromium and Node processes before choosing it. |

Sources: [WinUI windowing](https://learn.microsoft.com/en-us/windows/apps/develop/ui/windowing-overview),
[Avalonia on Windows](https://docs.avaloniaui.net/docs/platform-specific-guides/windows),
[Tauri requirements](https://v2.tauri.app/start/prerequisites/),
and [Electron processes](https://www.electronjs.org/docs/latest/tutorial/process-model).

## Independent review

One fresh reviewer inspected the runtime, installer, watcher, and settings code without changing files.
The reviewer found two P2 issues. The main agent reproduced or checked both issues.

| Issue | Repair | Evidence |
|---|---|---|
| Installation removed the saved Tokens view. | Add Mode to the installer preference schema. | `Tests/test_install.ps1` checks retention. |
| Quota display names acted as identities. | Preserve bucket ID, window role, and duration. | `Tests/test_usage.ps1` merges renamed readings into one window. |

The review did not benchmark different frameworks or test a compiled replacement.

## Migration steps

1. Keep the current installation and fixtures. Create a separate source folder and install path.
2. Port parsing, settings validation, token accounting, and quota normalization into a C# core.
3. Compare snapshots from both implementations with the same fixtures.
4. Port WPF controls into view models. Share state between the widget and parked bar.
5. Add a read-only SQLite adapter. Keep schema checks and folder fallback.
6. Check tray restore, DPI changes, screen removal, startup, sleep, and app updates.
7. Enable settings writes after parsing and display checks pass.
8. Import preferences through a versioned schema. Switch the installer last. Keep rollback.

Use cancellation for background work. Send complete snapshots to the UI dispatcher.
Bound lists and preserve scroll positions.
File notifications need periodic reconciliation because events can be lost or duplicated.

Sources: [SQLite connection modes](https://learn.microsoft.com/en-us/dotnet/standard/data/sqlite/connection-strings),
[WPF virtualization](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/advanced/optimizing-performance-controls),
and [FileSystemWatcher limits](https://learn.microsoft.com/en-us/dotnet/api/system.io.filesystemwatcher).

## Limits that remain

A framework change cannot supply missing tool token counters or exact per-chat account charges.
A larger saved context value cannot increase model capacity.
A loaded Codex chat must use fresh settings before its recorded window can change.
