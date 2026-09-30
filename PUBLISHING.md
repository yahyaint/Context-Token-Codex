# Publishing this repository

The default installer target is `yahyaint/Context-Token-Codex`.
For a fork, change the Repository parameter.
Do not create the repository, push, or publish until the owner gives an explicit mark.

1. Set a repository-local author name and email if Git is not already configured. A GitHub-provided noreply address can keep a personal email out of commits.
2. Run the build, fixture tests and desktop UI tests listed in CONTRIBUTING.md.
3. Inspect `git diff --cached` and commit the initial source. Do not add generated executables, local Codex data, preferences, installation backups or secret values.
4. Create an empty repository on your chosen host and add its actual URL as `origin`.
5. Push `main`. The Windows build workflow will run on GitHub; it has not been run on hosted infrastructure during local preparation.
6. Run Build/package.ps1. Attach the generated ZIP and checksum to a release named `v6.8.7`. The source-only ZIP from a Git hosting service does not contain the generated launchers; users need the release package or a local build.

The MIT license permits use, modification and redistribution subject to retaining its notice. Keep the third-party design attribution in METHODS.md and the palette credit in BRANDING.md. The application is independent of OpenAI.

## GitHub CLI steps after the owner's mark

Run these commands from the prepared repository. Check RELEASE-NOTES.md before publication.
The repository must not already exist for the create command.

```powershell
gh repo create yahyaint/Context-Token-Codex --public --source . --remote origin
git push -u origin main
git tag -a v6.8.7 -m "Context-Token Codex 6.8.7"
git push origin v6.8.7
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build\package.ps1
gh release create v6.8.7 ".\dist\Context-Token-Codex-Windows-v6.8.7.zip" ".\dist\Context-Token-Codex-Windows-v6.8.7.zip.sha256" --verify-tag --title "Context-Token Codex 6.8.7" --notes-file .\RELEASE-NOTES.md
```

Then check the hosted build result. Test the public installation command from INSTALL.md.
The public audit records measured resource use and unverified environments.
Do not describe an unperformed check as passed.
