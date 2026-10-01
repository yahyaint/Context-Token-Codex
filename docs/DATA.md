# Data and measurement limits

## Context

CTC reads local Codex usage records.
The context percentage uses the last recorded input and recorded window.
It is not a continuous measurement of the model.
New values appear when Codex writes records.

Compaction completion comes from session events.
A live compaction indicator also needs compatible local logs.
Unknown values remain `--`.
The marker `*` means that data are incomplete or old.

## Token counts

| Value | Rule |
|---|---|
| Total | Input plus output. |
| Input | Includes cached input. |
| Uncached input | Input minus cached input. |
| Output | Includes reasoning. |
| Other output | Output minus reasoning. |
| Cache hit | Cached input divided by input. |
| Reasoning share | Reasoning divided by output. |

Chat totals can include earlier requests and earlier models.
Local totals do not represent the whole account.
CTC does not add guessed tokens between records.

## Tool calls and Exec

Tool calls count recorded requests with unique call IDs.
Resumed records can cover different periods.
CTC combines available records and marks incomplete scans.

A script reference does not prove execution.
Loops, branches, and dynamic code can change execution counts.
Command types describe recorded requests.
One request can have more than one type.

A missing result does not prove that a call is running.
Nonzero exit codes can have normal meanings.
For example, search can return 1 when there is no match.

Shell results are separate from wrapper results.
CTC does not add those results to the tool-call count.
Recorded times can overlap and include waiting.
They are not active work hours.

CTC does not show exact token costs for tools or automations.
Those costs are not present in the available records.
Raw tool arguments and output are not retained in the activity view.

## Account quota

The Codex CLI supplies account quota readings.
CTC uses initialization and account quota requests through a separate helper database.
It does not send chat messages.

Bars show remaining allowance.
Tooltips show used quota and reset time.
The provider can supply one weekly window or several windows.
CTC does not create a missing quota window.

The first account request can take up to 45 seconds.
Local chat data can appear before it completes.
An old reading is marked.
An account change discards the earlier live reading and estimate baseline.

## Per-chat quota estimates

CTC allocates observed quota changes across local chat activity.
Weights include the model and available cached input, uncached input, and output.
Unsupported model, tier, or context combinations remain unattributed.

An estimate needs a baseline and a later observation.
Earlier chat history cannot be assigned to an unobserved quota interval.
Other devices can affect the account change.

A share is a percentage-point estimate of account allowance.
It is not an exact charge for one chat.
Quota percentages cannot reliably convert to model work hours.

## Files and access

CTC reads Codex session files, model data, and local SQLite databases.
SQLite access is read-only.
New schemas can require a CTC update.

CTC stores its preferences and saved-change queue in `%LOCALAPPDATA%\CodexContextMonitor`.
Selecting Save changes only the selected context settings.
CTC preserves settings backups.
Restart controls use recorded idle checks before requesting a normal close.
