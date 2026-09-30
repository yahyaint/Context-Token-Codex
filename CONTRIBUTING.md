# Contributing

Use Windows 10/11 and Windows PowerShell 5.1. The .NET Framework compiler is supplied by Windows; the build does not download a runtime. `sqlite3.exe` is optional for development and improves live Codex data discovery.

## Build from a clone

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build\build.ps1
```

This generates ContextWidget.exe, Setup.exe and the multi-resolution Context.ico. Executables and distribution ZIPs are not committed. The icon is tracked as a previewable application asset and can be regenerated from the original drawing code.

## Verify

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\run.ps1 -Desktop
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\run.ps1 -Desktop
```

Without `-Desktop`, the runner checks the noninteractive tests.
Each test runs in a separate STA process. A failed check makes the runner fail.
Add `-Report <path>` to save the results as JSON.
Build a package first to check the installation helper. Then add `-Archive <ZIP path>`.
Tests need built launchers. Run Build/build.ps1 first.
The native-engine limits check is optional. See LIMITS-VERIFICATION.md.


The overlay, installer and theme tests open temporary Windows UI and need a desktop session. Repeat with pwsh.exe to test PowerShell 7, including its own WPF child processes. Tests use disposable fixtures and leave diagnostic results in the temporary directory. Do not use real conversation transcripts as test fixtures. CI runs all noninteractive tests on Windows 2022/2025 with both shells; desktop UI tests remain a local release check. See COMPATIBILITY.md for actual coverage and limitations.

## Make a release package

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build\package.ps1
```

The script rebuilds, packages an explicit list of public files, and writes the ZIP and SHA256 checksum in `dist`. It never packages `.git`, local preferences, Codex data, backups or arbitrary working-directory files. Release binaries are unsigned.

Use pull requests for changes. Explain the behavior change and the tests you ran. Keep compatibility fallbacks for Codex file formats, preserve existing user settings, and keep the MIT notice and attribution documents. Contributions are licensed under the repository's MIT license.

Run Tests/test_theme.ps1 in an STA PowerShell process to verify the CTC scope dropdown. It opens a temporary window and tests scope selection.

## Context editor checks

Run `Tests/test_context_editor.ps1` in Windows PowerShell 5.1 and PowerShell 7. Run `Tests/test_overlay.ps1` on an interactive Windows desktop for compact/expanded editing, draft retention, scope changes, presets, reset controls, and warnings. The UI test writes only to a marked disposable fixture. Do not use real project settings as test data.

## Activity and queue checks

Run test_limits_matrix.ps1, test_limits_queue.ps1, test_account_quota.ps1 and test_exec_activity.ps1 in both shells.
Run test_overlay.ps1 for the full-width tool tile, nested Exec details and Queue controls.
See LIMITS-VERIFICATION.md for the optional local native-engine tests.
Use synthetic input_text blocks for new parser tests. Keep real tool arguments and output out of fixtures.
