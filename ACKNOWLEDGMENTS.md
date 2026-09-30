# Acknowledgments

Created by **Yahya Nabil** — [yahyanabil.com](https://yahyanabil.com).

Thanks to these projects and their contributors. They informed the methods below. This application is an independent implementation, not a fork or an official integration endorsed by those authors.

| Project and author | License | Contribution to this design |
|---|---|---|
| [ccusage](https://github.com/ccusage/ccusage), ryoppippi and contributors | [MIT](https://github.com/ccusage/ccusage/blob/main/apps/ccusage/LICENSE) | Detailed input, cache, output and reasoning views; session reports; cache and reasoning subset accounting. |
| [CodexBar](https://github.com/steipete/CodexBar), Peter Steinberger and contributors | [MIT](https://github.com/steipete/CodexBar/blob/main/LICENSE) | Subscription windows, freshness, reset times and a Codex CLI RPC provider. |
| [Codex Monitor HUD](https://github.com/LH-03/codex-monitor-hud), Codex Monitor HUD Contributors | [MIT](https://github.com/LH-03/codex-monitor-hud/blob/main/LICENSE) | Bounded task discovery, session-index names and visible fallback states. |
| [Codex Usage](https://github.com/upstream-ray/codex-usage-monitor), Craig Constable and contributors | [MIT](https://github.com/upstream-ray/codex-usage-monitor/blob/main/LICENSE) | Windows subscription-monitor comparison; no implementation incorporated. |

No source code or binaries from these projects are copied or bundled. Credit describes ideas and research, not code ownership. Reference copyright and license notices are included in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

The previous palette was inspired by [Nord](https://www.nordtheme.com/docs/colors-and-palettes/). The current Ink Black/Prussian Blue/Dusk Blue/Dusty Denim/Alabaster Grey palette was selected by Yahya Nabil. The CTC logo is original. See [BRANDING.md](BRANDING.md).

UI wording follows principles from [ASD-STE100](https://www.asd-ste100.org/about_STE.html) and [Microsoft Windows writing guidance](https://learn.microsoft.com/en-us/windows/apps/design/style/writing-style). See [UI-WRITING.md](UI-WRITING.md). These references do not imply certification or endorsement.

License links checked on 18 September 2026. Keep this file and the notices in source and binary distributions. If a future change copies upstream code, record its path and revision, retain its copyright and license, and identify modifications.

### Quota attribution research (24 September 2026)

- [Codexometer](https://github.com/merefield/codexometer), merefield and contributors, [MIT](https://github.com/merefield/codexometer/blob/main/LICENSE): local-only estimate wording, baseline/reset checks and honest precision.
- [CPA Quota Estimator](https://github.com/Autsunset/cpa-quota-estimator), Autsunset and contributors, [MIT](https://github.com/Autsunset/cpa-quota-estimator/blob/main/LICENSE): separate model/cache weights and window research.
- [How Much I Get From Codex](https://github.com/bigbobro/how-much-i-get-from-codex), bigbobro and contributors, [MIT](https://github.com/bigbobro/how-much-i-get-from-codex/blob/main/LICENSE): allowance-calibration comparison; its website endpoints are not used.
- [AI Usage Tracker](https://github.com/Danielw412/AI-usage-tracker), Danielw412: interval-allocation comparison. License not confirmed; no source incorporated.

CTC's implementation is independently written. These are method/research acknowledgments, not copied-code notices or endorsements. See QUOTA-RESEARCH.md.

## Context editor design review - 30 September 2026

The following sources informed this review. Their source and license were checked at the revisions below. These are design references, not copied code. CTC's multiplier, percentage, validation and TOML save code is original. No listed monitor documents this exact context-writing feature; CTC does not attribute its editor implementation to them.

| Upstream (MIT) | Reviewed revision | Useful pattern / application |
|---|---|---|
| [Codex Token Overlay](https://github.com/soleillevant0125/codex-token-overlay), soleillevant0125 | `b3a38d727fb2e0cf8e8c92ffff3f65da9a592dc5` | Compact controls, expanded details, explicit reset/commit interaction. CTC adopts compact editing and hides secondary readings behind disclosure. Focus-following IPC remains a possible later enhancement. |
| [Codex Monitor HUD](https://github.com/LH-03/codex-monitor-hud), contributors | `d9ac8537e1763fac470ffb55d6abdf7aa83a0f44` | Compact projections, bounded discovery and model-agnostic fallbacks. CTC labels unknown/catalog/live baselines and avoids model-name assumptions in editor controls. |
| [CodexBar Windows](https://github.com/dontcallmejames/CodexBar-Windows), Peter Steinberger and contributors | `1bdf1ffe2453997539bbcf13aaa184769d2e0ad0` | Compact usage surfaces and per-provider backoff. Structured settings and quota retry improvements are later candidates, not added by this editor change. |
| [ccusage](https://github.com/ccusage/ccusage), ryoppippi and contributors | `5304e3548c6e1ead42860a975b0d1900928ce53c` | Explicit token subset accounting and grouped detail remain useful. MIT applies to `apps/ccusage/LICENSE`; the root license is not labeled MIT by GitHub. No package incorporated. |
| [Codex Overlay and Tracker](https://github.com/Glergini/codex-overlay-and-tracker), Glergini | `aaaec763531b4a5d0ef3e47c2887506613de1774` | Local per-chat/project accounting is a future comparison target; no code incorporated. |
| [Codexometer](https://github.com/merefield/codexometer), merefield | `5c0fd8446f8c95ea6f9c4ed3c7bc7e6a05f0b379` | Honest quota estimates and reset/baseline checks remain useful for token mode; no quota changes in this editor release. |

Code reuse policy: if code is copied later, record upstream URL, full commit, source and destination paths, local changes, copyright, and complete license in THIRD_PARTY_NOTICES.md. Preserve required notices in distributed source and binaries. Git commit trailers may add `Inspired-by:` / `Source:` links; do not name upstream authors as co-authors when they did not author the CTC commit.
