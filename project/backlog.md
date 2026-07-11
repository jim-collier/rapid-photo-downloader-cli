<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
# Requirements

This is a product backlog just for pre-v1.0.0 release. After that, bugs, features, and enhancements will be managed in Github Issues.

<!-- TOC ignore:true -->
## Table of contents
<!-- TOC -->

- [Conventions](#conventions)
- [Initial requirements](#initial-requirements)
- [Backlog](#backlog)
	- [Misc to-do](#misc-to-do)
	- [Bugs](#bugs)
	- [Features and enhancements](#features-and-enhancements)
	- [Done](#done)
		- [Done - Initial requirements](#done---initial-requirements)
		- [Done - Bugs](#done---bugs)
		- [Done - Features and enhancements](#done---features-and-enhancements)
	- [Future and/or deferred](#future-andor-deferred)
	- [Canceled](#canceled)

<!-- /TOC -->

## Conventions

In each section, items are listed approximately from newest to oldest.

| Icon | Status
| :--: | :--
| 🔘   | Not started
| 🛠️   | Started, and/or partially complete
| ✋   | Defer
| ✅   | Complete
| 🚫   | Canceled

## Initial requirements

- 🛠️ A CI/CD pipeline kicked off by a bash script (`cicd/cicd.bash`): builds, tests, and can commit and push. Packaging and publishing are opt-in.
	- Scaffolded 2026-07-09: 7-stage fail-fast pipeline (format/build/test/profile/release/dogfood/publish) with `-q`, `-m`, `--quick`, `--no-*`. Build/test/profile stages skip until Go code exists; backup+publish works now. Includes fuzz/security tests and a flamegraph profiler+report. Marked partial until real code exercises the build/test/profile paths.

- 🔘 Dev-environment install script (Linux bash, macOS sh, Windows PowerShell), runnable via a single `curl`/`wget` and documented under "how to develop". Clones main, installs dependencies, and states what it will do with an option to abort.

- 🔘 Release-install script per platform, runnable via a single `curl`/`wget` and documented under "how to install". Downloads, installs, and runs the latest release, with an option to abort.

- 🔘 Default configuration hard-coded
	- 🔘 Overridden by per-user config file, created the first time a default setting is changed.
		- 🔘 Settings live under `~/.config/rpdc/config.SHCL`.
	- 🔘 Overridden by program options at run-time.

## Backlog

### Misc to-do

### Bugs

### Features and enhancements

- 🔘 CI/CD improvements
	- 🔘 Minimal hosted CI
		- Add a bare-bones GitHub Actions workflow: vet, test, build on push and PR.
		- This is the safety net only - the full local pipeline (fuzz, profiling, dogfood, publish) stays local and unchanged.
		- Keep it to one small YAML file. No matrix beyond what's needed to prove it builds off this machine (linux, current Go).
		- Run against both dev and main.
	- 🔘 Dev branch + release on main
		- Adopt a dev branch as the integration target. Feature branches merge to dev; main becomes release-only.
		- Merging dev to main automatically cuts a release: a workflow on main tags the merge and publishes the release with built artifacts.
		- Decide the version source up front (version var in source vs manual tag before merge) and make the workflow and build stamping agree on it.
		- Document the flow in a line or two wherever branch conventions live, so day-to-day work knows the merge-back target changed.
	- 🔘 goreleaser for release packaging
		- Replace the hand-rolled cross-compile and tgz/zip packaging with a goreleaser config: same targets, same archive layout and naming as now, plus checksums.
		- Wire it into the release workflow above so a merge to main produces the GitHub Release with all platform artifacts attached.
		- Keep the local build path (native make target) untouched for day-to-day work; goreleaser is for releases only.
		- Verify artifact names and archive contents match the old scheme before switching over, so existing download links and scripts keep working.
	- 🔘 Pin tool versions
		- Lint and audit tools currently run at whatever version is installed, so results drift across machines and over time. Pin them.
		- Pin golangci-lint, staticcheck, govulncheck (and any others the pipeline probes for) to explicit versions, in one place, used by both the local pipeline and CI.
		- Add a dependabot config so dependency and toolchain bumps arrive as PRs against dev. Group minor/patch bumps to keep the noise down.
	- 🔘 README badges
		- Add badges for the parts that now exist: CI status, latest release, Go version. Keep it to the few that carry signal.
		- Point the CI badge at the new workflow on main, the release badge at the latest tag.
		- Place them at the top of the README in one line, matching the existing README style.

- 🔘 When listing flags (e.g. for `--help`), figure out a way to simplify the many ways of showing `--[i][whole]name-inc[lude]="*glob*"`, for example. In most cases, users will just do something like `--name-inc="*.IMG"`. But they won't do anything, if they are overwhelmed with complex help. The file selection option documentation, in particular are very dense. (And hard to read.)

- 🔘 Make SHCL its own standalone module for config-file reading, with easy reusability.
	- Options:
		- A monorepo with a SHCL reader/writer in multiple languages and a common test harness...
		- My own private (or create a public) Go helper repo. As it grows though a version bump in one bumps all - painful.
		- `go.work`, Go 1.18+. Never used before, seems simple enough. All local. Not managed.

- 🔘 Make Include/exclude flags it's own standalone module: Use the isolated engine already build and debugged in '../repoint-symlink/github/'. Then add in the expanded glob flags defined in design.md::'##### Input selection', plus the ability to mix-and-match globs and regex for selection. Then make that a new, better standalone engine in one file in this project, with easy reusability.

- 🔘 Make design.md::'### Duplicate detection' its own own standalone module, that can be easily reused and consumed, with easy reusability.

### Done

#### Done - Initial requirements

#### Done - Bugs

#### Done - Features and enhancements

### Future and/or deferred

### Canceled
