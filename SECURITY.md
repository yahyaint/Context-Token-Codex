# Security

## Report a vulnerability

Use GitHub's private vulnerability reporting control when available.
Otherwise, open an issue that requests a private reporting channel.
Do not post vulnerability details in that issue.

Include the CTC version, Windows version, affected component, and reproduction steps in the private report.
Use sample data.
Do not upload credentials, `auth.json`, private chat records, or account tokens.

## Installation

The release executables are unsigned.
The SHA256 file detects changed files; it does not prove publisher identity.
Use the repository and release linked in [INSTALL.md](INSTALL.md).

The download helper checks the archive hash and paths.
Compiled setup checks its file manifest before installation.

## Data and settings

CTC reads local Codex records and opens SQLite databases read-only.
Save can change selected context settings.
Restart controls request a normal restart after recorded idle checks.

See [Data](docs/DATA.md) and [Troubleshooting](UPDATE-RECOVERY.md) for operating limits.

## Updates

Use the latest CTC release for fixes.
Earlier installed versions support rollback.
No fixed response time or support period is promised.
