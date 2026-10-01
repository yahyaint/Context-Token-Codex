# Contributing

New app changes use C# and WPF.
Keep the PowerShell 6.8.9 source and release.
Use Windows and the .NET 10 SDK for builds.
The release includes the runtime.

## Build

Run:

    .\Build\build-native.ps1

The script runs the native core fixtures and publishes dist/native-win-x64.
Open ContextTokenCodex.exe to run the widget.
Open Setup.exe to run compiled setup.
No PowerShell process runs either app.

## Test

Run:

    dotnet run --project tests/CTC.Tests/CTC.Tests.csproj
    .\Tests\test_native_ui.ps1 -Executable "$PWD/dist/native-win-x64/ContextTokenCodex.exe"

The core tests use temporary profiles.
The UI tests use marked fixture folders and actual WPF windows.
They test percentage saves, draft retention, corner return, tray, scrolling, setup updates, and normal close.
The UI test cannot use a real Codex profile.
Do not add real chat arguments, outputs, or account credentials to fixtures.

The startup watcher test requires an open Codex app:

    .\Tests\test_native_watcher.ps1 -Executable "$PWD/dist/native-win-x64/ContextTokenCodex.exe" -FixtureHome "FIXTURE-HOME" -Output "FIXTURE-OUTPUT"

It opens a fixture widget and checks recovery after a fixture process stops.
It does not close Codex.

## Package

Run:

    .\Build\package-native.ps1

The ZIP contains only the published app folder.
The package includes the runtime, licenses, notices, and guides.
Executables, packages, user data, backups, and caches are not committed.
The executables are unsigned.

## Review

Explain the changed behavior and the checks you ran.
Use STE for app text.
Keep conservative settings writes and schema fallbacks.
Unknown lifecycle data must block automatic restart.
Keep account identity and reset boundaries in quota estimates.
Keep MIT attribution and all bundled runtime notices.
See MIGRATION.md and UPDATE-RECOVERY.md.

The legacy build and tests remain available for PowerShell 6.8.9.
Use its tag for a fixed legacy source tree.
