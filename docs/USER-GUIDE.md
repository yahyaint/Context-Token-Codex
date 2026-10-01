# User guide

[Install](../INSTALL.md) · [Troubleshooting](../UPDATE-RECOVERY.md)

## Views

| View | Use |
|---|---|
| Context | Check recorded context use, compactions, and cached input. |
| Tokens | Check chat totals and open a Breakdown. |
| Limits | Edit global settings or a saved project. |
| Queue | Check saved changes and request a normal Codex restart. |

In the compact view, use the arrows to select an active chat.
Select the chat name or **Expand** to show the active chat cards.
Select **Collapse** to return to the compact view at its previous corner.

## Window controls

| Control | Action |
|---|---|
| Settings icon | Open window and startup preferences. |
| Background | Set background opacity. Text stays visible. |
| Pinned | Keep CTC above other windows. |
| Corner | Select a screen corner. |
| Tray | Hide CTC beside the Windows clock. |
| Minus | Show the small bar at the same corner. |
| Close | Stop CTC. |

Drag the header to move CTC.
Drag the lower right control to resize the expanded view.
Select the arrow in the small bar to restore the widget.

If CTC is hidden, select its tray icon.
The icon can be in the hidden-icons menu beside the clock.
You can also open the desktop shortcut again.

## Context limits

Select **Edit context limits** for the displayed chat.
In the expanded view, each active card has an inline project editor.
The **Limits** page includes global settings and saved idle projects.

Settings apply to all models in the selected project.
CTC does not store a separate override for one chat.

| Input | Meaning |
|---|---|
| `200000` or `200k` | A context window of 200,000 tokens. |
| `180000` or `180k` | A compaction threshold of 180,000 tokens. |
| `90%` | A compaction threshold at 90% of the entered window. |
| `default` | Remove the selected override after Save. |

A percentage requires a numeric context window.
CTC saves the percentage as a token count.
A later window change does not change that saved count automatically.

**×1 / ×2 / ×3** use the displayed base value.
Selecting ×2 and then ×3 gives twice and then three times the same base.
Numeric compaction thresholds keep their percentage.
Percentage input and `default` keep their form.

**Undo** reads the saved values again.
**Default** sets both fields to `default`.
**Save limits** writes both fields and keeps a backup.
No file changes occur before Save.

If a settings file changes outside CTC, select Undo before saving again.
If CTC cannot use its syntax, the save stops.

### Capacity and reload

A larger window does not increase provider model capacity.
Codex can reject or reduce the saved value.
Local model catalog data can be old.

A loaded chat needs a fresh Codex session to load saved settings.
Open **Queue** to check the saved change.
Resume the chat after a full Codex restart.
Check the next usage record for the recorded window.
A matching window does not confirm the compaction threshold.

## Restart controls

**Restart now safely** is disabled while recorded chats are busy.
**Restart after all chats stop** requests one normal restart.
**Cancel restart** cancels a waiting request.

The helper waits for ten seconds of recorded idle state.
Unknown records, read errors, and incomplete scans block automatic restart.
It requests a normal close and waits for Codex to quit.
It does not force-stop Codex.
The request expires after 24 hours.

**A restart closes the open Codex windows.**
If Codex stays open, quit it manually and open it again.

## Tokens and quotas

Open **Breakdown** to see input, output, cached input, reasoning, and tool calls.
Move the pointer over a token count to see its exact value.
Open **Exec**, **Command types**, **Script tools**, or **Shell results** for recorded activity details.

Quota bars show the remaining account allowance.
Move the pointer over a bar to see used quota, plan, reset time, and observation time.
Select the refresh button for a new account reading.
A weekly-only plan shows one weekly bar.

Per-chat quota shares are estimates.
Call counts are not token costs.
See [Data and measurement limits](DATA.md).

## Startup

New installations start in the small bar at 85% background opacity.
Change **Open in the small bar** in Widget settings.
Select Codex, ChatGPT, or Either under **App to follow**.

Auto-open creates a Windows Startup shortcut.
The watcher checks app identity every two seconds.
An updated Codex package can have a different executable name.

CTC stays open after the selected app closes.
After a manual CTC close, it waits for the next selected app launch.
