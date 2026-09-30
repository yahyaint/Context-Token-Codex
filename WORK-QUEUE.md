# CTC work queue - 30 September 2026

Complete these requests in order. Use STE for app text.
Keep previous versions and user settings. Do not push to GitHub without the owner's mark.

| Order | Request | Result needed | State |
|---|---|---|---|
| 0 | Fix quotas after a new sign-in, including weekly-only accounts | Reload quotas for the signed-in account. Show the weekly limit without a 5-hour limit. Prevent stale account data. | Reproduced and repaired. Actual weekly-only reading verified in the installed PowerShell 5.1 widget. |
| 1 | Fix the saved context change | Verify saved versus recorded values. Show pending reload until a record confirms the window. | Saved 544k verified through config/read; running record is 258400. Restart controls and pending status implemented. Restart confirmation awaits a fresh chat record. |
| 1a | Test chat and project limit editing extensively | Start with saved projects. Test both runtimes, actual controls, and isolated native sessions. Fix confirmed failures. | Three saved projects verified. 85 cases pass per runtime. Native and WPF checks recorded in LIMITS-VERIFICATION.md. Actual live reload remains pending. |
| 2 | Use STE everywhere in the app | Update authored text and save rules for future changes. Keep names and source evidence exact. | Passed in PowerShell 5.1 and 7 |
| 3 | Arrange context controls | Put multipliers below Context window. Put percentages below Compact at. Put Undo and Default on a separate shared row. | Passed widget tests and visual check |
| 4 | Reduce text in token details | Use small metric cards and grouped details. Put explanations in help. | Passed in PowerShell 5.1 and 7 |
| 5 | Research tool and automation usage | Show recorded call counts by tool when available. Show exact tokens only where records supply them. | Passed in PowerShell 5.1 and 7 |
| 6 | Replace the parked tab | Show a small bar at the same corner. Include chat navigation, context, tokens, and account quotas. | Passed in PowerShell 5.1 and 7 |
| 7 | Review the technology choice | Run an independent read-only review. Compare native options and record a migration plan. | Complete. C# / .NET 10 / WPF recommended. Two confirmed P2 issues fixed. |
| 8 | Verify and install | Check both PowerShell versions and window layouts. Preserve the current runtime. Commit locally. | Version 6.8.3 is installed with 26 matching files. Both runtimes pass. Preferences and previous versions are retained. Local release prepared; push held. |

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

## Weekly-only quota repair

The failure was reproduced in Windows PowerShell 5.1.
An if expression unwrapped one quota window. The missing scalar Count property made CTC display unknown values.
The repair keeps an array outside the expression. Both WPF runtimes now show one weekly bar.
The actual installed PowerShell 5.1 widget shows the current native weekly reading.
Account-change tests reject earlier responses and keep estimate histories separate.

See NEXT-TASKS.md for the remaining release checks and the pending real-session reload.
