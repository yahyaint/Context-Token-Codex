# Context-Token Codex instructions

## App platform

Use C#, .NET 10, and WPF for all new app work.
Keep the PowerShell 6.8.9 source and release as the earlier version.
The compiled app is the default release and prompt installation.
Use tests/CTC.Tests and Tests/test_native_ui.ps1 for native checks.
Keep root PowerShell modules unchanged except for download and build helpers.

## App writing rules

Use ASD-STE100 Simplified Technical English (STE) for all new or changed app text.
Apply this rule to labels, tooltips, help, status, errors, setup, and user guides.
Read UI-WRITING.md before you change text. It contains the project terms and review steps.

Use complete sentences for help and messages. Use short noun phrases for labels.
Use commands for instructions. Give one instruction in each sentence.
Use at most 20 words in an instruction and 25 words in a description.
Use active voice and one term for one concept. Use "chat" for a conversation.
Keep technical names and input formats exact. Define new software terms in UI-WRITING.md.

Keep user content, product names, source error details, license notices, and historical evidence exact.
Use STE for the text around those items. Do not claim full dictionary compliance without an audit.

## Verification and release

Check changed text in compact and expanded views. Check the setup window when its text changes.
Use the existing fixture tests. Do not change real Codex limits or queues to test text.
Keep earlier versions and preferences when you install an update.
Do not create a public repository, push, or publish without the owner's explicit mark.
