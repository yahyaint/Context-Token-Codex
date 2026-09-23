# Contributing

Use Windows 10/11 and Windows PowerShell 5.1. The .NET Framework compiler is supplied by Windows; the build does not download a runtime. `sqlite3.exe` is optional for development and improves live Codex data discovery.

## Build from a clone

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build\build.ps1
```

This generates ContextWidget.exe, Setup.exe and the multi-resolution Context.ico. Executables and distribution ZIPs are not committed. The icon is tracked as a previewable application asset and can be regenerated from the original drawing code.

## Verify

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\test_settings.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\test_regressions.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\test_repository.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\test_usage.ps1
.\Tests\test_estimator.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\test_compatibility.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\test_transport.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\test_overlay.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\test_install.ps1
```

The overlay, installer and theme tests open temporary Windows UI and need a desktop session. Repeat with pwsh.exe to test PowerShell 7, including its own WPF child processes. Tests use disposable fixtures and leave diagnostic results in the temporary directory. Do not use real conversation transcripts as test fixtures. CI runs all noninteractive tests on Windows 2022/2025 with both shells; desktop UI tests remain a local release check. See COMPATIBILITY.md for actual coverage and limitations.

## Make a release package

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build\package.ps1
```

The script rebuilds, packages an explicit list of public files, and writes the ZIP and SHA256 checksum in `dist`. It never packages `.git`, local preferences, Codex data, backups or arbitrary working-directory files. Release binaries are unsigned.

Use pull requests for changes. Explain the behavior change and the tests you ran. Keep compatibility fallbacks for Codex file formats, preserve existing user settings, and keep the MIT notice and attribution documents. Contributions are licensed under the repository's MIT license.

Run Tests/test_theme.ps1 in an STA PowerShell process to verify the CTC scope dropdown. It opens a temporary window and tests scope selection.
