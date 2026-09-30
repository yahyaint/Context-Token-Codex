# App text: Simplified Technical English

Use ASD-STE100 Simplified Technical English (STE) for all text that CTC authors.
This rule applies to labels, tooltips, help, status, errors, setup, and user guides.
Use this rule for each future change.

Reference: [ASD-STE100, Issue 9](https://www.asd-ste100.org/assets/files/ASD-STE100_ISSUE9.pdf).
The standard has writing rules and a controlled dictionary.
Use its technical noun and technical verb rules for software terms.
CTC does not claim certification or a complete dictionary audit.

## Writing rules

- Write instructions as commands. Example: "Select Save."
- Give one instruction in each sentence.
- Use a maximum of 20 words in an instruction sentence.
- Use a maximum of 25 words in a description sentence.
- Use active voice. Identify the person or program that does the action.
- Use complete sentences in help and messages. Short labels can be noun phrases.
- Give a condition before the instruction. Example: "If the value is incorrect, select Undo."
- Use one term for one concept. Use "chat" for a user conversation.
- Use the same word with the same meaning and part of speech.
- Define technical terms in this guide. Do not use an unknown term to make text shorter.
- Put secondary information in tooltips or expandable help.
- Explain the cause of an error. Give the next action when the cause is known.
- State whether a value is recorded, saved, or estimated.
- Use text to identify a status. Color alone is insufficient.
- Keep numbers, formulas, and input formats exact.

Keep product names, model names, chat names, paths, keys, and source error details exact.
Keep license text and required copyright notices exact.
Keep historical evidence exact. Use STE for new text around that evidence.

## Technical nouns

| Term | Meaning |
|---|---|
| Chat | A user conversation in Codex. |
| Widget | The CTC window. |
| Context window | The number of tokens available for one model request. |
| Model capacity | The context size that the provider supports. |
| Compaction | The process that replaces earlier context with a shorter record. |
| Compact at | The saved threshold that controls when compaction starts. |
| Scope | The selected project settings or global settings. |
| Override | A setting that replaces a value from another scope. |
| Base value | The recorded or saved number that the multiplier buttons use. |
| Global fallback | A global value used when a project has no override. |
| Model catalog | Local model data supplied by Codex. These data can be old. |
| Quota | The account allowance for a time window. |
| Quota estimate | A calculated share of a recorded quota change. It is not an account measurement. |
| Token | A unit that the model uses to process text or other input. |
| Input | All input tokens. Includes cached input. |
| Output | All output tokens. Includes reasoning tokens. |
| Cached input | Input tokens read from cache. |
| Uncached input | Input tokens minus cached input. |
| Reasoning | Reasoning tokens in the output. |
| Cache hit | Cached input divided by input for chats with both values. |
| Last record | The time in the newest usage record. |
| Tray | The Windows notification area beside the clock. |
| Parked bar | The small view with chat data and a restore button. |
| CLI | The Codex command-line program. |
| TOML | The format of a Codex settings file. |
| SHA256 | The method used to check the release file. |


| Tool call | One recorded request to a tool. A call count is not a token cost. |
| Rollout record | A local file with events for one recording of a chat. |
| Lifecycle | The recorded start and stop state of a chat turn. |

## Technical verbs

| Verb | App action |
|---|---|
| Select | Choose a button, menu item, or option. |
| Drag | Move a control while you hold the mouse button. |
| Expand / Collapse | Change the widget or details size. |
| Minimize | Show the parked bar at the same corner. |
| Refresh | Read the newest account quota values. |
| Reload | Load the chat settings again in Codex. |
| Reset | Return a setting or quota window to its specified start state. |
| Sign in | Connect Codex to the user's account. |
| Compact | Reduce earlier context to a shorter record. |

## Values and symbols

Use the Windows number format for output. Keep exact integer token counts.
Accept the formats documented beside each input field.
The value `default` removes an override after Save.
The symbol `--` means that no value is available.
The symbol `*` means that data are incomplete or old. Explain the meaning beside the value.
The symbol `~` means an estimate. The label must also identify the estimate.
The units `h` and `d` mean hours and days.
The unit `pp` means percentage points. Define it in the related help.

## Review each change

Read the changed text in the actual window.
Check each term against this guide and the STE dictionary when available.
Check sentence length, active voice, conditions, and the input examples.
Check the compact layout for text that does not fit.
Do not describe an estimated or old reading as an exact live value.
Do not claim that a larger setting increases model capacity.

## Activity terms

- Script reference: A direct tool call written in recorded script code. Execution is not confirmed.
- Result record: The recorded reply to a tool call.
- Shell result: Numeric helper metadata printed by an exec script.
- Recorded time: Available wall time, or the time between a call and its result.
- No result: No matching output is in the scanned record. This does not mean the call is running.
- Status unknown: A result has no recognized exit status.
