# Compatibility

## Requirements

| Component | Requirement |
|---|---|
| Operating system | Windows 10 or Windows 11. |
| Architecture | x64. |
| App runtime | Included in the Windows release. |
| Codex records | A local Codex installation and readable chat records. |
| Account quotas | Codex sign-in and a compatible Codex CLI. |

ChatGPT can trigger Auto-open.
CTC reads Codex records; it does not measure ordinary ChatGPT conversations.

## Verified behavior

Tests cover context percentages, input formats, settings backups, stale saves, token subsets, and queue rules.
They cover unknown events, incomplete records, weekly-only quotas, account changes, and bounded RPC failures.

Actual WPF window tests cover compact limits, drafts, corner return, tray restore, setup, update, rollback, and removal.
Visual checks compare the original PowerShell layouts, theme, and icon.
The CI matrix runs on Windows Server 2022 and Windows Server 2025.

See [GitHub Actions](https://github.com/yahyaint/Context-Token-Codex/actions) for the results for each commit.
See [Releases](https://github.com/yahyaint/Context-Token-Codex/releases) for tested packages and SHA256 files.

## Limits

Physical Windows sign-in, a separate physical PC, and physical mixed-DPI monitor moves remain unverified.
Windows ARM is not supported by the published x64 package.
CTC does not promise compatibility with future private Codex data schemas.

Busy, unknown, or incomplete records block automatic restart.
Saved settings cannot increase model capacity.
Exact per-tool token costs and exact per-chat subscription charges are unavailable.

Use [Troubleshooting](UPDATE-RECOVERY.md) if a Codex update changes data or app identity.

## Earlier version

[PowerShell 6.8.9](https://github.com/yahyaint/Context-Token-Codex/releases/tag/v6.8.9) remains available.
The current C# version keeps its layout.
Future feature work uses C# and WPF.
