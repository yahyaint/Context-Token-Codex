# CTC work queue - 30 September 2026

Complete these requests in order. Use STE for app text.
Keep previous versions and user settings. Do not push to GitHub without the owner's mark.

| Order | Request | Result needed | State |
|---|---|---|---|
| 0 | Fix the saved context change | Verify saved versus recorded values. Show pending reload until a record confirms the window. | Saved 544k verified through config/read; running record is 258400. Restart controls and pending status implemented. Restart confirmation awaits a fresh chat record. |
| 1 | Use STE everywhere in the app | Update authored text and save rules for future changes. Keep names and source evidence exact. | Passed in PowerShell 5.1 and 7 |
| 2 | Arrange context controls | Put multipliers below Context window. Put percentages below Compact at. Put Undo and Default on a separate shared row. | Passed widget tests and visual check |
| 3 | Reduce text in token details | Use small metric cards and grouped details. Put explanations in help. | Passed in PowerShell 5.1 and 7 |
| 4 | Research tool and automation usage | Show recorded call counts by tool when available. Show exact tokens only where records supply them. | Passed in PowerShell 5.1 and 7 |
| 5 | Replace the parked tab | Show a small bar at the same corner. Include chat navigation, context, tokens, and account quotas. | Passed in PowerShell 5.1 and 7 |
| 6 | Review the technology choice | Run an independent read-only review. Compare native options and record a migration plan. | Complete. C# / .NET 10 / WPF recommended. Two confirmed P2 issues fixed. |
| 7 | Verify and install | Check both PowerShell versions and window layouts. Preserve the current runtime. Commit locally. | Installed 6.8.0 with 26 matching files. Preferences and previous version retained. Local commit prepared; push held. |

## Data rules

Token totals include input and output. Cached input and reasoning are subsets.
Call counts do not measure token cost.
Do not invent exact tokens for tools, automations, or account quota use.
Codex can omit data. Unknown values must stay unknown.
Project and global limits apply to all models in the selected scope.
A larger setting cannot increase provider model capacity.

## Test record

The earlier STE changes passed the WPF widget and setup tests in PowerShell 5.1 and PowerShell 7.
The usage test needed an update because the reset message changed. Its behavior check now passes.
Source at the start: local commit `34e72de`, installed version 6.7.0.
No public repository or push exists.

## Final checks

The Windows ZIP passed local installation-helper verification in both runtimes.
Its corrupted-checksum test passed. Public download remains unverified until publication.
The installed widget and watcher run once each. The ready event is set.
The runtime contains 290133 bytes. The current release ZIP is about 174 KiB.
Real-profile first snapshot: 2.3 s. Background scan: 4.2 s. These times cover three discovered files on this host.
Normal close and reopen passed with a separate fixture app in both runtimes outside the sandbox.
The running Codex chat was not restarted. Its next session must confirm the saved limit.
