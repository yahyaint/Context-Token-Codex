# UI writing

Use short, consistent English. References: [ASD-STE100 Simplified Technical English](https://www.asd-ste100.org/about_STE.html), used in aviation technical documentation, and [Microsoft Windows UI writing guidance](https://learn.microsoft.com/en-us/windows/apps/design/style/writing-style). This is STE-inspired writing, not a claim of full ASD-STE100 compliance. The full controlled vocabulary has not been audited.

## Rules

- Use one term for one thing: task, input, output, cache, reasoning.
- Use direct action labels: Refresh, Save, Close.
- Put values first. Put explanations in tooltips or expandable help.
- Give status in words. Do not rely on color or an unexplained icon.
- Keep a short visible label for every metric.
- Show `--` for unavailable data. Use `*` for a partial sum and explain it in help.
- Use the Windows number format. Token counts remain exact integers.
- State the observation time. “Watching files” describes the reader; it does not mean the provider emits each generated token.

## Token labels

| Label | Meaning |
|---|---|
| Total | Recorded input plus output. |
| Input | Includes cached input. |
| Output | Includes reasoning output. |
| Cache | Input read from cache. |
| Uncached | Input minus cache, when both are available. |
| Reasoning | Reasoning tokens within output. |
| Cache hit | Cache divided by input for tasks with both fields. |
| Last record | Time in the newest usage record. |

Task totals can contain earlier models. A task's last model is not used to classify its entire history. Local totals do not measure a subscription balance or a bill.
