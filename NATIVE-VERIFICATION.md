# Compiled version checks

Version: 7.0.0.
Runtime: .NET 10.0.12.
SDK: .NET 10.0.401.
The Windows release targets x64.

## Local checks

73 core fixture checks pass.
26 actual WPF window checks pass.
The core checks include percentages, scalers, TOML preservation, stale saves, backups, and token subsets.
They also include corrupt records, future records, resumed call deduplication, weekly quotas, account changes, and RPC timeouts.
The window checks include compact limit saves, draft retention, corner return, scrolling, tray, setup updates, rollback, and normal close.
The startup watcher opens a fixture widget with the updated Codex package.
It also restores a fixture widget after that process fails.
An installed update takes over the watcher without a Windows sign-in.

These checks use temporary profiles and marked desktop fixtures.
They do not change real Codex limits or restart real Codex.
The PowerShell 6.8.9 release remains available.

## Live read-only check

The compiled reader found the running chat and saved projects.
It read the signed-in account's weekly-only quota through the Codex CLI.
It reported no session read errors.
The first optimized snapshot took 0.66 seconds on this host.
The earlier build took 6.87 seconds.
These are local samples. They are not a hardware benchmark.

The optimized reader starts with recent records.
It reads earlier records in bounded background steps.
Tool details have an incomplete marker during this work.
Unknown or incomplete lifecycle data block automatic restart.

The local UI fixture used approximately 167 MiB working memory.
The short read-only reader sample used approximately 96 MiB working memory.
These samples do not measure a long session or compare frameworks.

## Release checks

The Windows release includes the .NET runtime and its MIT license and third-party notices.
Setup checks a file manifest before it installs.
The download helper checks the ZIP SHA256, paths, size, and required files.
It supports both the compiled release and the earlier PowerShell release.
Native CI runs on Windows Server 2022 and Windows Server 2025.
Check the GitHub Actions result for the exact published commit.

## Remaining environment limits

A physical second PC and physical Windows sign-in remain unverified.
Windows ARM and physical mixed-DPI monitor moves remain unverified.
The release supports Windows x64.
Codex data formats can change. Some changes require a CTC update.
A framework change does not supply exact tool token costs or exact per-chat subscription charges.
See UPDATE-RECOVERY.md for repair steps.
