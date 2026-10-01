# Publishing this repository

The default installer target is `yahyaint/Context-Token-Codex`.
For a fork, change the Repository parameter.
Do not create the repository, push, or publish until the owner gives an explicit mark.

1. Set a repository-local author name and email if Git is not already configured. A GitHub-provided noreply address can keep a personal email out of commits.
2. Build the launchers. Run Tests/run.ps1 with -Desktop in PowerShell 5.1 and 7. Check a fresh Git export.
3. Inspect `git diff --cached` and commit the source. Do not add generated executables, local Codex data, preferences, installation backups or secret values.
4. Create an empty repository on your chosen host and add its actual URL as `origin`.
5. Push `main`. The Windows build workflow will run on GitHub; it has not been run on hosted infrastructure during local preparation.
6. Run Build/package.ps1. Attach the generated ZIP and checksum to a release named `v6.8.9`. The source-only ZIP from a Git hosting service does not contain the generated launchers; users need the release package or a local build.

The MIT license permits use, modification and redistribution subject to retaining its notice. Keep the third-party design attribution in METHODS.md and the palette credit in BRANDING.md. The application is independent of OpenAI.

## GitHub CLI steps after the owner's mark

Run these commands from the prepared repository. Check RELEASE-NOTES.md before publication.
The repository must not already exist for the create command.

```powershell
gh repo create yahyaint/Context-Token-Codex --public --source . --remote origin
git push -u origin main
# Use the prepared local tag. If absent, create it on the tested commit.
if (-not (git tag --list v6.8.9)) { git tag -a v6.8.9 -m "Context-Token Codex 6.8.9" }
if ((git rev-parse 'v6.8.9^{commit}') -ne (git rev-parse HEAD)) { throw 'The release tag does not match the tested commit.' }
git push origin v6.8.9
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build\package.ps1
gh release create v6.8.9 ".\dist\Context-Token-Codex-Windows-v6.8.9.zip" ".\dist\Context-Token-Codex-Windows-v6.8.9.zip.sha256" --verify-tag --title "Context-Token Codex 6.8.9" --notes-file .\RELEASE-NOTES.md
```

Then check the hosted build result. Test the public installation command from INSTALL.md.
The public audit records measured resource use and unverified environments.
Do not describe an unperformed check as passed.

## Publication gates

Before the owner's mark:

- Check Git integrity, source paths, ignored files, and credentials.
- Retain MIT and upstream notices. Do not add upstream authors as co-authors for design ideas.
- Build from a fresh Git export. Run Tests/run.ps1 in both shells.
- Keep previous runtime files and preferences. Do not restart Codex to check a release.
- Prepare the Windows ZIP, SHA256 file, source archive, and local release tag.
- Keep the public repository, pushes, and release creation pending.

After the owner's mark:

1. Create the public repository through GitHub CLI. Push the tested commit and tag.
2. Enable private vulnerability reporting in the repository settings.
3. Check all four hosted Windows build jobs. Download their verification reports if a job fails.
4. Publish the Windows ZIP and its matching checksum with RELEASE-NOTES.md.
5. Test the public installation command from INSTALL.md.

Hosted builds and public downloads cannot be marked passed before publication.
The workflow keeps its tested package and report as artifacts for 14 days.
The two official GitHub actions are pinned to verified commit IDs.
A SHA256 checksum detects changed files. It is not a publisher signature.

## Local readiness - 1 October 2026

- GitHub CLI is installed and authenticated as the intended repository owner.
- The intended public repository is yahyaint/Context-Token-Codex. It does not exist at preparation time.
- Git integrity passes. Tracked history has no forbidden private-data paths or common secret patterns in the local scan.
- A fresh Git export passes all 22 checks in each supported PowerShell version on this host.
- The Windows package includes build source, tests, MIT notices, repair guides, and the README's sample screenshot.
- Previous runtime versions and user preferences are kept.
- Repository creation, remote configuration, push, hosted CI, release publication, and public installation remain pending.
