# Compatibility and release checks — 6.0.1

## 6.3.0 / 20 September 2026

Windows PowerShell 5.1 and PowerShell 7: settings, usage, compatibility, transport, repository, WPF overlay, dropdown and installer tests passed. Overlay checks include live counters, a 40-chat list, 24-pixel wheel steps, stable offset, inline project setting saves and idle saved-project discovery.

Codex Desktop was already updated to 26.915.4065.0; CLI reports 0.155.0-alpha.9.2. Read-only local monitoring found active chats and saved/idle projects successfully. The real subscription request timed out at both 12 and 30 seconds. This remains an unresolved live provider check, not a passed integration test. Recorded fallback, timeout handling and private helper database isolation are retained. No queued messages were changed.

## 6.1.0 additions

The token UI now watches active session records every second and displays six metrics plus per-task detail. The WPF fixture appends a new record during execution and checks that the UI receives its total, reasoning count and task row. Unknown cache/reasoning fields are tested separately from known zero. Earlier platform coverage below describes the 6.0.1 baseline; see release verification for reruns.

Codex session files and SQLite tables are private implementation details. This widget tolerates the changes listed below; it cannot guarantee compatibility with every future Codex release. Unknown data stays unavailable rather than being presented as zero usage.

## Tested locally

On Windows build 26200, using Windows PowerShell 5.1 and PowerShell 7.6.5:

- Settings, usage accounting, syntax and isolated runtime installation.
- Actual WPF overlay: expand/collapse, corner snap, opacity persistence, minimize, tray hide/restore, embedded settings and mode switching.
- Actual installation wizard: first installation, upgrade backup, preference retention and startup shortcuts in isolated test directories.
- Missing profile, later session creation, missing SQLite, reordered JSON properties, malformed/unknown records, partial appends and truncated files.
- Task rename through the session index; Unicode/spaced paths; en-US and de-DE quota parsing.
- Real SQLite with incompatible tables: session-folder fallback, completion-only log status and discovery of a future numbered database.
- Mock CLI transport: old request parameters, noisy output, account errors, early exit and bounded timeout.

The installed Codex CLI also returned a real subscription reading through the read-only provider. Authentication data is not copied into this repository.

## Automated hosted coverage prepared

GitHub Actions matrix: Windows Server 2022 and 2025, each with Windows PowerShell and PowerShell 7. Hosted checks cover build, configuration, usage, compatibility, RPC failure handling, isolated installation and packaging. These hosted jobs have not run yet; desktop UI checks require a local interactive desktop.

## Remaining limits

- No separate physical machine, Windows ARM, Windows 10 VM or long-duration soak test performed.
- Locales and format changes are fixtures, not additional operating systems or actual old Codex installations.
- Private log schema changes disable the live compaction-start signal; completed compactions can still be read from session events.
- A complete session-format replacement needs a reader update. Subscription endpoint removal needs a provider update; the last available reading remains labeled with its observation time.
- The Android SDK SQLite executable on the test machine could not open Unicode paths. The file reader supports those paths and remains the fallback. SQLite schema tests therefore used a separate ASCII path.
- Launchers are unsigned. Source ZIP requires building; the Windows release ZIP includes launchers.

Publication requires a final source review, author email, repository URL and the owner's explicit push mark. No push is part of local preparation.

6.1.0 rerun: usage, compatibility, repository/install manifest, live WPF append and installation wizard passed on Windows PowerShell 5.1 and PowerShell 7.6.5 on 18 September 2026. The live UI fixture advanced the total from 85,800 to 90,000 and verified reasoning and task detail. Hosted CI remains pending.
