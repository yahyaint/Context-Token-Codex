# Context limit verification - 6.8.1

## Test scope

Start with previously saved settings. Compare the saved value with the recorded value.
Keep the two values separate. A successful save does not change a running chat.

The chat editor saves project settings. All chats and models in that project share those settings after reload.
The desktop widget does not save a separate permanent override for each chat.
The isolated native test checks a temporary per-chat override through the Codex API.

## Previously saved projects

Codex `config/read` confirmed three existing project overrides: 544000, 544000, and 500000 tokens.
The two live chats with 544000 overrides still recorded 258400 tokens during this audit.
Both chats therefore needed a fresh session.
The idle project's saved 500000 value was verified through configuration only.
No real project setting or chat record changed during these checks.

## Native engine test

The test uses the installed Codex engine, a temporary data folder, and a local provider fixture.
It does not copy credentials, contact the model provider, or use account quota.
Its model data come from the local Codex catalog.
These results verify configuration and session behavior. They do not prove that the remote provider accepts larger requests.

| Case | Result for a catalog with 95% usable capacity |
|---|---|
| Save 544000 in project settings | A new chat records 516800. |
| Change the file to 800000 during a turn | The existing chat retains 516800. |
| Start another chat | The new chat records 760000. |
| Start a fresh engine and resume the original chat | The resumed chat records 760000. |
| Supply a temporary per-chat override of 400000 | The chat records 380000. |
| Save 1200000 above the catalog maximum of 872000 | The chat records 828400. |
| Remove the project override | The chat uses the global setting. |
| Remove the global override | The chat uses the model default. |
| Open a child directory inside the project repository | Codex reads the parent project setting. |
| Save a compaction threshold | Codex reads the saved integer threshold. |

The larger requested window cannot increase provider capacity.
The compaction percentage uses the entered window. CTC stores the result as an integer token threshold.

## Repeat the tests

Run these commands from the repository folder:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\test_limits_matrix.ps1
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\test_limits_matrix.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\test_overlay.ps1
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\Tests\test_overlay.ps1
```

The limit matrix has 85 cases in each runtime.
It checks percentages, integer boundaries, formatting, defaults, scope precedence, all model names, locked files, and stale saves.
It also checks inherited project settings, empty files, case-sensitive keys, and changed live windows.
Input checks use English, German, and Arabic number cultures.
The widget test checks the actual WPF controls in compact and expanded views.
It checks stale-save rejection, invalid-file recovery, and unchanged saves.

For native integration, install Python and Git. Supply the full path to the installed `codex.exe`:

```powershell
python .\Tests\test_native_limits.py --exe 'C:\path\to\codex.exe' --report native-limits.json
```

The default model is `gpt-6.1-sol`. Add `--model gpt-6-astra` to test Astra.
The selected model must exist in the local `models_cache.json` file.
For another Codex data folder, add `--cache 'C:\path\to\models_cache.json'`.
The script retains its temporary fixture and writes its path in the report.
Keep generated reports outside the public repository. Do not commit account files or rollout records.

## Confirm a real saved change

1. Read the selected project's root `model_context_window` setting.
2. Check project trust and higher-priority overrides through Codex `config/read`.
3. Wait until all chats stop.
4. Select **Restart now safely**, or select **Restart after all chats stop** in advance.
5. Resume the chat after Codex opens.
6. Check the next recorded context window.

For a 544000 window and 95% usable capacity, the expected record is 516800.
If the record differs, keep the change unconfirmed. Check the catalog, selected profile, and session overrides.
Do not edit recorded usage to make the values match.

## Limits of these tests

Real records checked on 30 September 2026 now show 516800 for the original Sol and Astra chats.
This matches the earlier 544000 setting at 95% usable capacity.
The Astra project and global overrides were later removed outside this audit.
Those changes are preserved. Its last record confirms the earlier setting, not the later reset to default.
No full desktop restart is needed to repeat the original confirmation.

The checks ran on this Windows device with PowerShell 5.1 and PowerShell 7.
The real active desktop chats were not restarted during the audit.
Other devices, remote provider capacity, and automatic compaction at a large threshold need separate checks.
Parent project detection currently follows Git repository markers. Custom `project_root_markers` need a separate resolution check.
Profiles, managed settings, and temporary session overrides can replace file settings.
Use Codex `config/read` when those layers are present.
