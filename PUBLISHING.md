# Publish a CTC release

Public repository: [yahyaint/Context-Token-Codex](https://github.com/yahyaint/Context-Token-Codex).
The owner approved publication on 1 October 2026.
For a fork, change the installer's Repository parameter.

## Release checks

1. Inspect the source diff. Keep credentials, local Codex data, settings and runtime backups out of Git.
2. Build the launchers. Run Tests/run.ps1 with -Desktop in PowerShell 5.1 and 7. Check a fresh Git export.
3. Push the tested commit to main. Wait for all four [Windows jobs](https://github.com/yahyaint/Context-Token-Codex/actions) to pass.
4. Run Build/package.ps1. Check the ZIP and its SHA256 file with Tests/test_bootstrap.ps1 in both shells.
5. Create a new annotated tag on the tested commit. Do not move a published tag.
6. Attach the Windows ZIP and checksum to the release. Use RELEASE-NOTES.md for the release text.
7. Test Install-FromGitHub.ps1 -VerifyOnly against the public release. Check the latest release and the fixed version.
8. Keep the prior runtime and user settings when the installed widget is updated.

## GitHub CLI

Run these commands from the tested checkout. Use a new version for each release.

```powershell
$version = '6.8.9'
$tag = 'v' + $version
if (git tag --list $tag) { throw 'This tag exists. Check it or use a new version.' }
git tag -a $tag -m ('Context-Token Codex ' + $version)
git push origin main $tag
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build\package.ps1
gh release create $tag ('.\dist\Context-Token-Codex-Windows-' + $tag + '.zip') ('.\dist\Context-Token-Codex-Windows-' + $tag + '.zip.sha256') --verify-tag --title ('Context-Token Codex ' + $version) --notes-file .\RELEASE-NOTES.md
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-FromGitHub.ps1 -Version $tag -VerifyOnly
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-FromGitHub.ps1 -VerifyOnly
```

For a new fork, use gh repo create with its owner/repository name before the first push.
Enable private vulnerability reporting. Use a repository-local Git author identity.

## Evidence and limits

The workflow builds on Windows Server 2022 and 2025 with PowerShell 5.1 and 7.
Desktop UI checks require a local interactive desktop. CI keeps its tested package and report for 14 days.
The two official GitHub actions are pinned to verified commit IDs.
Record the tested commit, CI run, package hash, runtime version and public download result.
Do not report an unperformed check as passed.
See AUDIT.md and COMPATIBILITY.md for measured results and platform limits.

CTC uses the MIT license. Keep LICENSE, ACKNOWLEDGMENTS.md and THIRD_PARTY_NOTICES.md in distributions.
Keep source and design credits in METHODS.md and BRANDING.md. CTC is independent of OpenAI.
A SHA256 checksum detects changed files. It is not a publisher signature.