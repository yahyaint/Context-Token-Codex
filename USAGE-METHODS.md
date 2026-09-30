# Usage-monitor comparison and v6 integration

Researched 18 September 2026. The best fit here means a mature subscription-usage method that can be integrated into this existing Windows overlay without replacing the UI or bundling a second application.

| Project | License | Strength | Fit for this widget |
|---|---|---|---|
| [CodexBar](https://github.com/steipete/CodexBar) | [MIT](https://github.com/steipete/CodexBar/blob/main/LICENSE), Peter Steinberger | Provider quota windows, reset times, CLI RPC fallback, separate local token/cost scanning | Selected reference for subscription monitoring. Its distributed app/CLI target macOS/Linux, so we implement the documented CLI RPC method in PowerShell. |
| [Codex Usage](https://github.com/upstream-ray/codex-usage-monitor) | [MIT](https://github.com/upstream-ray/codex-usage-monitor/blob/main/LICENSE), upstream notices retained | Native Windows taskbar quota monitor, reset countdowns, Rust implementation | Useful Windows comparison. Its direct credential/HTTP integration and separate widget are less suitable than reusing Codex's read-only app-server interface here. |

CodexBar's [Codex provider documentation](https://github.com/steipete/CodexBar/blob/main/docs/codex.md) describes its CLI RPC data source. This release adopts that architectural method with attribution. No CodexBar or Codex Usage source code or executable is copied or bundled. Our independent implementation remains MIT licensed.

## What is integrated

`Usage.Provider.ps1` starts the installed `codex.exe app-server`, initializes it, requests `account/rateLimits/read`, and closes that helper. The [official app-server documentation](https://learn.chatgpt.com/docs/app-server) describes that read-only method. It never starts a model turn, redeems credits or buys anything.

The Codex CLI handles its existing authentication and provider network connection. The widget does not open auth.json, extract bearer tokens, scrape browser cookies or log CLI diagnostics. Polls run in a separate background runspace in every view, once per minute after the previous request finishes; Refresh requests an earlier poll. Timeout: 45 seconds; failures identify initialization or subscription-response phase. Shared quota bars show remaining allowance in all views; tooltips show used percentage, plan, freshness and reset time.

The quota panel supports named limit buckets, arbitrary window lengths, plan names, remaining percentages, reset times and available reset-credit counts. Missing windows remain missing; unknown is not zero. Expired reset times do not imply quota recovery. Read failures preserve a clearly labeled last reading. The newest live or local observation wins for each window; additional older windows remain available with their own observation time. Freshness is displayed and observations older than two minutes are marked stale.

## Token accounting and limits

The local token side uses the existing incremental rollout reader. It takes the newest cumulative snapshot for each loaded user task and sums those counters, avoiding repeated token_count events and duplicate files for the same task. It does not add last-request usage repeatedly. Cached input is a subset of input. Available detail counts are stated explicitly.

Coverage is deliberately labeled: loaded user tasks discovered within the configured lookback (24 hours by default, cap 128 files). A task's cumulative counter can include work before that lookback. These are **not today's totals, all-device/account lifetime totals, API billing, or tokens remaining in the subscription**. Child-agent logs and archived tasks are not exhaustively scanned. No API-equivalent dollar estimate is shown because it would not be a subscription bill.

Live subscription limits describe the account signed into the selected local Codex profile; they can include use from other devices. They cannot be derived from the local token counts.


## Detailed live view (6.1.0)

Reference: [ccusage Codex reports](https://github.com/ccusage/ccusage/blob/main/docs/guide/codex/index.md), MIT, ryoppippi and contributors. Its reports informed the input/cache/output/reasoning fields and task breakdown. No ccusage code is copied or bundled. Its day/model accounting is broader than this widget's loaded-task snapshot; this widget does not claim day totals or per-model historical totals.

The background reader checks known active files each second and processes new complete records. Discovery can take up to the folder reconciliation interval (10 seconds) without SQLite. The panel updates existing controls. Usage is live when Codex writes records; no token-stream estimates are invented. Subscription polls remain separate at 60 seconds, with manual Refresh. The newest token record and quota observation each have a visible time. Missing fields show --; partial sums show *. Cached input and reasoning output are subsets, never added twice.

See [Acknowledgments](ACKNOWLEDGMENTS.md), [third-party notices](THIRD_PARTY_NOTICES.md) and [UI writing](UI-WRITING.md).

## Model-weighted attribution (6.5.0)

An independent measured-interval allocator replaces simple chat-local before/after subtraction. It distributes a positive account change among local cumulative-token deltas, weighting uncached input, cached input and output using the recorded model and the dated Quota.Rates.json table. No fixed plan allowance or dollar charge is inferred. Two concurrent chats share one delta, rather than each claiming the full account movement.

Research references: [Codexometer](https://github.com/merefield/codexometer) (MIT), for local-only labeling, source precision and reset/baseline guards; [CPA Quota Estimator](https://github.com/Autsunset/cpa-quota-estimator) (MIT), for model/cache valuation; [How Much I Get From Codex](https://github.com/bigbobro/how-much-i-get-from-codex) (MIT), for separate-window calibration research. [AI Usage Tracker](https://github.com/Danielw412/AI-usage-tracker) is a comparison for interval allocation; no license was confirmed and no code was copied. No external project code is bundled.

Current-window history is bounded and checkpointed locally. Unsupported or missing inputs, subagent intervals and observation gaps remain unattributed. Values are explicitly estimates and rounded to whole percentages; a positive estimate below one point is shown as <1%. An unknown value is --, never zero. External activity concurrent with visible local events remains inseparable. A reset, percent decrease or login-file metadata change starts a new baseline. These conservative guards can underreport local usage. Empirical allowance-capacity calibration and retrospective full-week reconstruction are not implemented.

## Token cards and tool activity - 30 September 2026

CTC uses token cards with exact values in tooltips. Secondary data use expandable sections.
Input and output remain totals. Cache and reasoning remain subsets.

The activity reader counts `response_item` function, custom-tool, and web-search calls with unique IDs.
It excludes output records and repeated call IDs.
It retains names and counts, not arguments or result text.
The scan bounds names, tool groups, and IDs. Incomplete scans show unknown counts.
Missing IDs and capped histories mark counts as partial.
Counts cover the selected rollout record, not all resumed records in a chat.
Client metadata are shown as recorded. They do not prove that a call came from an automation.

Codex's aggregate usage counters do not assign billed tokens to each tool call.
Tool output size is not the model's total input charge.
Therefore, CTC shows call counts and leaves tool and automation token costs unknown.
Source: [Codex protocol](https://github.com/openai/codex/blob/main/codex-rs/protocol/src/protocol.rs).

Design references:

- [ccusage Codex reports](https://ccusage.com/guide/codex/): input, cache, and output separation with coverage.
- [ClaudeCodeUsage](https://github.com/ClaudeCodeUsage/ClaudeCodeUsage/tree/a871da2b970433cc42a56185f32428c21d0c4e36): compact primary values, grouped details, and labelled content estimates.
- [Codex Monitor HUD](https://github.com/LH-03/codex-monitor-hud): record filtering and bounded discovery.

CTC uses the display patterns. It does not copy a tokenizer or claim exact content attribution.
See ACKNOWLEDGMENTS.md for licenses and fixed revisions.

## Exec details

CTC reads tool arguments in memory to classify command requests and direct script tool references.
It reads result metadata for status and timing. It keeps only categories, counters and numeric metadata.
It does not retain commands, arguments or stdout in activity summaries.

Script references are not execution counts. Dynamic calls and conditional branches can change the number of calls.
Reported shell results come from printed helper metadata. They are separate from the outer script result.
Duplicate output IDs and shell chunk IDs count once.
Large records, code and collections have scan limits. Missing data stay marked.
Call-to-result spans include waiting. Concurrent calls can overlap.
Neither call counts nor time totals supply exact tool token costs.
