# Queue verification - 1 October 2026

The verification checks code, fixtures, installed files, and release evidence.
Checkboxes alone do not prove completion. Historical checks retain their original version and scope.

## Results

| Queue item | Evidence | Result |
|---|---|---|
| 1. Weekly-only sign-in | Account-change tests reject old responses. The installed widget shows one weekly bar. | Verified |
| 2. Startup defaults | Owner preferences and installer fixtures use parked startup, 85% background, and Auto-open. Startup shortcut is valid. | Verified locally |
| 3. Queue page | Actual WPF controls show saved changes, safe restart, waiting, cancellation, and external file changes. | Verified; repaired scope and stale-value gaps |
| 4. Token sections | Rendered token cards, divider, and separate Data status / How counts work controls. | Verified |
| 5. Tool details | Full-width expandable Tool calls row. Exec, command types, and shell metrics use recorded metadata. | Verified |
| 6. Minimize and tray | Minimize shows the corner bar. Tray hide and restore remain separate. | Verified |
| 7. Tests and installation | Fifteen backend suites, 85 limit cases, actual widget, and actual installer pass in both shells. | Verified on this Windows host |
| 8. Git and release | MIT notices, source credits, recovery guide, release notes, archives, and local commit. | Prepared; public publication remains held |
| 9. Memory | Version 6.8.5 passed a 30-minute single-process test. Repeated-read tests preserve type metadata. | Verified within the recorded test scope |
| 10. Desktop identity | Version and primary-file-name fixtures pass. Normal close/reopen uses a marked fixture. | Verified locally; actual update unavailable |
| 11. Runtime alignment | Installed manifest files match tested source. Previous runtime and preferences remain available. | Verified |
| Earlier context-editing requests | Compact editor, percentages, multipliers, reset row, stale saves, scope precedence, and idle projects have fixture checks. | Verified |
| Original saved context changes | Sol and Astra recorded 516800 for the original 544000 setting at 95%. | Confirmed from earlier real records |
| Technology review and credit | ARCHITECTURE-REVIEW.md and ACKNOWLEDGMENTS.md retain the review and source references. | Complete; no native rewrite claimed |

## Missed items repaired in 6.8.6

1. Global queue rows could use a project's confirmation status. The row now identifies a project override.
2. External configuration edits could leave old queue values labeled Saved. The view now shows queued and current file values.
3. Malformed version-1 queue entries could pass the reader. The reader now rejects invalid paths and limits without overwriting the file.
4. A corrupt queue could leave old rows visible. The view now clears those rows and shows the error.
5. A waiting restart helper still used code loaded before the memory repair. The old process used 3623.5 MiB working memory.
6. Helper maintenance could reset the request's 24-hour expiry. The helper now accepts and preserves the original expiry.
7. The release receipt claimed exact runtime bytes but did not include that field. The receipt now records the byte count.

The existing waiting request was preserved. Its repaired helper retains the idle gate and original expiry.
Real Codex was not closed for this verification. The helper's live resource result is recorded in AUDIT.md.

## Checks that remain outside local completion

- GitHub repository creation, push, release publication, public download, and hosted CI wait for the owner's explicit mark.
- The configured Codex updater reported up_to_date. No eligible update was available for an actual update-cycle test.
- Another Windows machine, ARM, and actual Windows sign-in remain unverified.
- Thirty minutes does not prove indefinite memory stability.
- STE writing rules and software terms are applied. A complete controlled-dictionary audit or certification is not claimed.
- Project/global settings apply to all models in the selected scope. Separate desktop settings for each chat or model are not implemented.
- Exact tool token charges and exact per-chat account charges are not supplied by the records. Estimates remain labeled.
- Models without confirmed credit weights retain unknown quota estimates. CTC does not invent or alias weights.

See AUDIT.md, COMPATIBILITY.md, LIMITS-VERIFICATION.md, and RECOVERY.md for test scope and repair steps.
