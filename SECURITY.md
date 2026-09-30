# Security reports

Use GitHub's private vulnerability reporting control when it is available.
If it is unavailable, open an issue that requests a private reporting channel.
Do not post the vulnerability details in that issue.
Do not post credentials, auth.json, private chat records, or account tokens.

Include the CTC version, Windows version, affected component, and reproduction steps in the private report.
Use sample data for reproduction when possible.

## Installation checks

Release launchers are unsigned. The SHA256 file detects changed files; it does not prove the publisher's identity.
Use the repository and release named in INSTALL.md.
The installer checks the release hash before it opens setup.
CTC reads local Codex records. Save can change selected context settings.
The restart controls request a normal Codex restart after recorded idle checks.
See README.md and RECOVERY.md for their operating limits.

## Updates

Use the latest CTC release for fixes. Older runtime backups support recovery.
This project does not promise a response time or a fixed support period.
