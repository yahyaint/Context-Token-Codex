# Per-chat quota attribution research

Research date: 24 September 2026. Version 6.5.0 implements independent measured-interval model-weighted allocation with durable current-window checkpoints. Exact attribution and empirical allowance calibration remain unavailable. Implementation scope and conservative exclusions are in README.md and USAGE-METHODS.md.

## Findings

The documented account/rateLimits/read response supplies account quota usedPercent, windowDurationMins, resetsAt and sometimes planType. account/usage/read supplies lifetime/daily token activity, not per-chat quota attribution. A plan label does not supply a numeric token allowance. OpenAI explicitly states that credit prices alone do not determine included subscription usage.

Sources:
- https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt
- https://learn.chatgpt.com/docs/pricing

## Methods compared

1. Chat-local first/last quota subtraction (initial CTC draft): calculates observed account movement during the recorded span. Concurrent chats can each display the same movement. Useful diagnostic, unsuitable as the main attributed-chat figure.
2. Local token-share allocation: Codexometer (MIT) multiplies account quota change by each local session's token share. It suppresses invalid baselines and reset-crossing figures, avoids false decimal precision and labels local-only estimates. Raw token weighting does not distinguish cache or models.
3. Model-weighted allocation: AI Usage Tracker's attribution source splits positive quota increases among token events weighted by estimated cost; absent events remain unattributed. More useful for concurrent chats. No standalone license was visible in the inspected repository listing; do not copy its code into CTC.
4. Account allowance calibration: How Much I Get From Codex (MIT) combines website daily credit totals and percentage history. Useful independent check for weekly capacity; daily buckets cannot establish accurate five-hour attribution. Undocumented website endpoints, delayed statistics, and stale denominators reduce robustness. Its documented model rate table differs from current official rates, illustrating rate drift.
5. CPA Quota Estimator (MIT): proxy-traffic observation and separate model/cache/speed valuation. Useful method reference; adopting its proxy architecture would change CTC's passive desktop-monitor design. Its example rate values also differ from the official page checked today.

Primary project references:
- https://github.com/merefield/codexometer (MIT: https://github.com/merefield/codexometer/blob/main/LICENSE)
- https://github.com/Danielw412/AI-usage-tracker
- https://raw.githubusercontent.com/Danielw412/AI-usage-tracker/main/server/threadUsage.ts
- https://github.com/bigbobro/how-much-i-get-from-codex (MIT: https://github.com/bigbobro/how-much-i-get-from-codex/blob/main/LICENSE)
- https://github.com/Autsunset/cpa-quota-estimator (MIT: https://github.com/Autsunset/cpa-quota-estimator/blob/main/LICENSE)

These projects are research references. No third-party source code has been copied. Credit any adopted methods in ACKNOWLEDGMENTS.md and USAGE-METHODS.md when implementation is finalized.

## Recommended CTC design

Use measured account quota as the authority, separately for each account, bucket, duration and reset boundary. Collect model-tagged token deltas between successive observations, not lifetime chat totals. Weight uncached input, cached input and output separately using a dated, updateable rate table. Output already includes reasoning; never add it twice. Apply speed/context modifiers only when known, and retain unknown coverage explicitly.

For a sufficiently covered interval:

estimated chat percentage points = measured account increase * chat weighted usage / sum of covered local weighted usage

This is a local-only allocation assumption, not proof of causal charge. External activity concurrent with local activity cannot be detected perfectly. Do not claim the unexplained remainder is fully identified. Reserve usage before baseline and intervals without usable events as unattributed; disclose mixed or incomplete coverage. A per-account empirical model can later calibrate credits per percentage point against sufficiently isolated intervals, with independent validation intervals and errors; it must not train on its own apportioned results as if they were truth.

Read account plan from the service. Do not hardcode Plus/Pro token ceilings. A model switch changes the weight of subsequent events, never re-prices an entire chat using its final model. Track descendants without counting parent and child counters twice. Separate current five-hour and weekly estimates from lifetime token totals.

Reject/suspend estimates after resets, account changes, stale observations, missing baselines, negative counters and unknown-rate intervals. Match display precision to source resolution. Show a coverage label rather than invented statistical confidence.

## UI

- Compact headline per chat: token total; estimated 5h and 7d quota share with an approximation marker.
- Separate account bars: actual 5h and 7d percent used, plan, freshness/reset tooltip.
- Collapsed Details: input/cached/uncached, cache hit rate, output/reasoning/other output, latest request, per-model history, compactions, coverage and estimator assumptions.
- No hours counter: user clarified they mean quota percentage.

## Further work

Implemented: interval allocation, bounded history, per-event model weights, profile/login-file metadata invalidation and tests. Future work: service-confirmed account identity, validated Fast/long-context weights, descendant ownership reconciliation, longer historical coverage and empirically validated allowance calibration. Public GitHub push remains held.
