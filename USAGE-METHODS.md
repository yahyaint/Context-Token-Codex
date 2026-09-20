# Usage-monitor comparison and v6 integration

Researched 18 September 2026. The best fit here means a mature subscription-usage method that can be integrated into this existing Windows overlay without replacing the UI or bundling a second application.

| Project | License | Strength | Fit for this widget |
|---|---|---|---|
| [CodexBar](https://github.com/steipete/CodexBar) | [MIT](https://github.com/steipete/CodexBar/blob/main/LICENSE), Peter Steinberger | Provider quota windows, reset times, CLI RPC fallback, separate local token/cost scanning | Selected reference for subscription monitoring. Its distributed app/CLI target macOS/Linux, so we implement the documented CLI RPC method in PowerShell. |
| [Codex Usage](https://github.com/upstream-ray/codex-usage-monitor) | [MIT](https://github.com/upstream-ray/codex-usage-monitor/blob/main/LICENSE), upstream notices retained | Native Windows taskbar quota monitor, reset countdowns, Rust implementation | Useful Windows comparison. Its direct credential/HTTP integration and separate widget are less suitable than reusing Codex's read-only app-server interface here. |

CodexBar's [Codex provider documentation](https://github.com/steipete/CodexBar/blob/main/docs/codex.md) describes its CLI RPC data source. This release adopts that architectural method with attribution. No CodexBar or Codex Usage source code or executable is copied or bundled. Our independent implementation remains MIT licensed.

## What is integrated

`Usage.Provider.ps1` starts the installed `codex.exe app-server`, initializes it, requests `account/rateLimits/read`, and closes that helper. The [official app-server documentation](https://learn.chatgpt.com/docs/app-server) describes that read-only method. It never starts a model turn, redeems credits or buys anything.

The Codex CLI handles its existing authentication and provider network connection. The widget does not open auth.json, extract bearer tokens, scrape browser cookies or log CLI diagnostics. Polls run in a separate background runspace, at most once per minute while Tokens mode is selected; Refresh requests an earlier poll. Timeout: 12 seconds. Context mode stops further automatic quota polls after any in-flight request finishes.

The quota panel supports named limit buckets, arbitrary window lengths, plan names, remaining percentages, reset times and available reset-credit counts. Missing windows remain missing; unknown is not zero. Expired reset times do not imply quota recovery. Read failures preserve a clearly labeled last reading; local rollout quota records are a fallback. Freshness is displayed and observations older than two minutes are marked stale.

## Token accounting and limits

The local token side uses the existing incremental rollout reader. It takes the newest cumulative snapshot for each loaded user task and sums those counters, avoiding repeated token_count events and duplicate files for the same task. It does not add last-request usage repeatedly. Cached input is a subset of input. Available detail counts are stated explicitly.

Coverage is deliberately labeled: loaded user tasks discovered within the configured lookback (24 hours by default, cap 128 files). A task's cumulative counter can include work before that lookback. These are **not today's totals, all-device/account lifetime totals, API billing, or tokens remaining in the subscription**. Child-agent logs and archived tasks are not exhaustively scanned. No API-equivalent dollar estimate is shown because it would not be a subscription bill.

Live subscription limits describe the account signed into the selected local Codex profile; they can include use from other devices. They cannot be derived from the local token counts.


## Detailed live view (6.1.0)

Reference: [ccusage Codex reports](https://github.com/ccusage/ccusage/blob/main/docs/guide/codex/index.md), MIT, ryoppippi and contributors. Its reports informed the input/cache/output/reasoning fields and task breakdown. No ccusage code is copied or bundled. Its day/model accounting is broader than this widget's loaded-task snapshot; this widget does not claim day totals or per-model historical totals.

The background reader checks known active files each second and processes new complete records. Discovery can take up to the folder reconciliation interval (10 seconds) without SQLite. The panel updates existing controls. Usage is live when Codex writes records; no token-stream estimates are invented. Subscription polls remain separate at 60 seconds, with manual Refresh. The newest token record and quota observation each have a visible time. Missing fields show --; partial sums show *. Cached input and reasoning output are subsets, never added twice.

See [Acknowledgments](ACKNOWLEDGMENTS.md), [third-party notices](THIRD_PARTY_NOTICES.md) and [UI writing](UI-WRITING.md).
