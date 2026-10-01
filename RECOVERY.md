# PowerShell version recovery

This guide applies to [CTC 6.8.9](https://github.com/yahyaint/Context-Token-Codex/releases/tag/v6.8.9).

Use the current [C# release](https://github.com/yahyaint/Context-Token-Codex/releases/latest) for new fixes.
It keeps the earlier layout and shared preferences.

## Basic checks

1. Open the installed `ContextWidget.exe`.
2. Check that Windows PowerShell can start.
3. Check the Startup shortcut's target and `/watch` argument.
4. Check **Auto-open with app** in Widget settings.
5. Select Refresh for account quota data.

A weekly-only plan has one quota window.
An unknown value remains `--`.

## Update

Keep `%LOCALAPPDATA%\CodexContextMonitor` and the installation's `Versions` folder.
Install the current compiled release in a separate app folder.
Run one widget at a time.

Do not delete preferences or saved queues to repair startup.
Do not edit or replay Codex message queues.

For source checks, use the `v6.8.9` tag and [Contributing](CONTRIBUTING.md).
