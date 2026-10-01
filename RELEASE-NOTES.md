# Context-Token Codex 6.8.9

Created by Yahya Nabil | [yahyanabil.com](https://yahyanabil.com)

## Clean Windows verification

- Normalize Windows short-path aliases before test fixtures are created.
- Allow normal fake CLI startup time on clean runners. Keep bounded hang checks.

## Publication checks

- Build and test a fresh Git export with one runner in both PowerShell versions.
- Fix normal-close selection when an app has an untitled auxiliary window.
- Request a normal close only on visible windows of the selected app process.
- Keep idle checks, expiry, cancellation, and complete process-exit checks.
- Include contributor templates, security reporting, a sample screenshot, and installation instructions.

## Icon and corner repair

- Use the current launcher icon for shortcuts. Refresh each changed shortcut in Explorer.
- Select the logo resolution for the display scale in the widget and setup window.
- Return Collapse to its original corner after expanded movement or resize.
- Keep previous versions and current preferences.

## Verification repairs

- Fix queue confirmation across scopes and external configuration edits.
- Reject malformed queue files. Preserve restart expiry during helper maintenance.
- Verify every item in QUEUE-VERIFICATION.md.

## Changes

- Monitor recorded context, compaction, tokens, and account quotas.
- Edit project and global context limits in compact and expanded views.
- Use multipliers and compaction percentages. Check saved changes on the Queue page.
- Show detailed token metrics, tool calls, Exec results, command types, and shell metadata.
- Start in a parked bar at 85% background opacity. Use the tray to hide and restore CTC.
- Keep weekly-only quotas correct after a new sign-in.
- Find Codex by its primary package path, including packages that use ChatGPT.exe.
- Fix retained type-cache growth during PowerShell polling. Keep cached settings reads bounded.

## Install

Download the Windows ZIP and its SHA256 file. Check the hash. Extract the ZIP. Open Setup.exe.
See INSTALL.md for the GitHub CLI command and one-prompt installation.
Source archives need a local build. The Windows ZIP contains the launchers.
Updates keep previous runtime files and user settings.

## Verification

Backend, context editor, widget, and installer checks pass in Windows PowerShell 5.1 and PowerShell 7.
The context matrix passes 85 cases per shell. Native Sol and Astra fixtures passed 24 checks.
The actual-window stability result is recorded in AUDIT.md.
See the repository Actions page for hosted Windows results. Another physical Windows machine, ARM, and real Windows sign-in remain unverified.
No eligible Codex update was available for an actual update-cycle test.

## License and credit

CTC uses the MIT license. It is an independent community project.
Keep LICENSE, ACKNOWLEDGMENTS.md, and THIRD_PARTY_NOTICES.md in distributions.
Source and design references include fixed upstream revisions. No upstream code or diagnostic library is bundled.
