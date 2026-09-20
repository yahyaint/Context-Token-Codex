# Publishing this repository

The repository is prepared for a public Git host, but no hosting account or remote URL is baked into the source.

1. Set a repository-local author name and email if Git is not already configured. A GitHub-provided noreply address can keep a personal email out of commits.
2. Run the build, fixture tests and desktop UI tests listed in CONTRIBUTING.md.
3. Inspect `git diff --cached` and commit the initial source. Do not add generated executables, local Codex data, preferences, installation backups or secret values.
4. Create an empty repository on your chosen host and add its actual URL as `origin`.
5. Push `main`. The Windows build workflow will run on GitHub; it has not been run on hosted infrastructure during local preparation.
6. Run Build/package.ps1. Attach the generated ZIP and checksum to a release named `v6.3.2`. The source-only ZIP from a Git hosting service does not contain the generated launchers; users need the release package or a local build.

The MIT license permits use, modification and redistribution subject to retaining its notice. Keep the third-party design attribution in METHODS.md and the palette credit in BRANDING.md. The application is independent of OpenAI.

The public audit documents the current memory cost and unverified environments. Avoid claiming clean-machine, sign-in, ARM or long-duration stability testing until those checks have actually been performed.
