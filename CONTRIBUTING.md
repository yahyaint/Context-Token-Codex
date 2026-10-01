# Contributing

New app changes use C#, .NET 10, and WPF.
Keep the PowerShell 6.8.9 runtime as the earlier version.
Use Windows for builds and WPF tests.

## Build

Install the SDK specified in `global.json`.
Run:

```powershell
.\Build\build-native.ps1
```

The script checks the preserved layouts, runs core fixtures, and publishes `dist/native-win-x64`.
Open `ContextTokenCodex.exe` for the widget or `Setup.exe` for setup.

## Test

```powershell
dotnet run --project Tests/CTC.Tests/CTC.Tests.csproj --configuration Release
.\Tests\test_native_visual_parity.ps1
.\Tests\test_public_distribution.ps1
.\Tests\test_native_ui.ps1 -Executable "$PWD/dist/native-win-x64/ContextTokenCodex.exe"
```

Use isolated profiles for settings, accounts, and restart checks.
Do not change real Codex limits or restart real Codex to test a change.
Keep private chat arguments and output out of fixtures.

The startup watcher check needs an open Codex app:

```powershell
.\Tests\test_native_watcher.ps1 -Executable "$PWD/dist/native-win-x64/ContextTokenCodex.exe" -FixtureHome "FIXTURE-HOME" -Output "FIXTURE-OUTPUT"
```

It uses a fixture widget. It does not close Codex.

## Package

```powershell
.\Build\package-native.ps1
```

The package contains the published app, runtime, licenses, credits, and user guides.
It must not contain work queues, chat notes, local diagnostics, credentials, or machine settings.
Executables, archives, caches, and user data are not committed.

CI builds on Windows Server 2022 and Windows Server 2025.
Publish an artifact from a passing job.
Keep the ZIP checksum and all runtime notices.

## Review

Use [STE](UI-WRITING.md) for app text and user guides.
Keep the original layout resources, theme, and icon.
Explain changed behavior and the checks you ran.

Keep conservative settings writes and schema fallbacks.
Unknown lifecycle data must block automatic restart.
Keep account and reset boundaries in quota estimates.

Keep the [MIT license](LICENSE), [credits](ACKNOWLEDGMENTS.md), and [third-party notices](THIRD_PARTY_NOTICES.md).
If you copy upstream code, record its URL, revision, paths, changes, copyright, and complete license.
Do not name upstream authors as co-authors unless they wrote the change.

For the fixed PowerShell source, use tag `v6.8.9`.
Its retained build is `Build/build.ps1`.
