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

- ✅ Cross-platform build matrix + packaging (full run, not `--quick`)
	- Done 2026-07-11 (branch `pkg` -> dev). Verified end-to-end against a throwaway module: 8 cross binaries + 4 Linux packages + 2 Windows installers all build.
	- Matrix: Linux / FreeBSD / Windows / macOS x x86_64 + arm64, pure-Go cross-compiles. No `--include-arm` - cross-builds aren't emulated, so arm64 is as fast as amd64 and there is nothing slow to gate.
	- Debug (native, unstripped) build drives test + profile; optimized `-s -w -trimpath` build drives packaging + dogfood.
	- Packages built here now: `.deb` + `.rpm` per Linux arch (nfpm), plus a single self-contained Windows setup `.exe` per arch (NSIS - static binary, adds `rpdc` to PATH, upgrades in place). New `--no-package` flag; `--quick` skips packaging.
	- Deferred to hosted OS runners / signing (slots + docs wired): macOS `.dmg`, FreeBSD pkg, Linux AppImage + Flatpak, Windows `.msi`. See Future.

- 🛠️ CI/CD improvements
	- Scaffolded 2026-07-11 (branch `ci` -> dev): all five below written + validated, guarded to stay green until `go.mod` + the version source land - same pattern as the local pipeline. End-to-end verification (green CI on real code, real release artifacts) waits for the module.
	- ✅ Minimal hosted CI
		- `.github/workflows/ci.yml`: vet/build/test on push + PR to dev and main; guarded no-op until code lands. Adds a pinned govulncheck run.
	- ✅ Dev branch + release on main
		- `dev` adopted as the integration target; main is release-only. Feature branches now merge to dev.
		- `.github/workflows/release.yml`: a merge to main tags `vX.Y.Z` from the in-source version and publishes via goreleaser.
		- Version source = a `Version` const in `internal/version` (see design.md "Versioning"); local cicd warns and the release workflow fails if it wasn't bumped.
	- ✅ goreleaser for release packaging
		- `.goreleaser.yaml` (validated with `goreleaser check`): same targets/flags as `config.bash`, adds archives + checksums. Local build path untouched. (No prior archive scheme existed - local pipeline emits raw binaries.)
	- ✅ Pin tool versions
		- `cicd/tool-versions.env` is the single pinned source (Go + govulncheck/gosec/golangci-lint/staticcheck/goreleaser), used by both local (`test.bash`) and CI. `.github/dependabot.yml` bumps deps + actions against dev, minor/patch grouped.
	- ✅ README badges
		- CI status + latest release added to the existing badge block.

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

- 🔘 Native installer formats that need their own OS or a signing cert - wire each as a hosted-runner step: macOS `.dmg` (Mac + Apple cert), FreeBSD pkg (FreeBSD builder), Linux AppImage + Flatpak, Windows `.msi`. Config/goreleaser slots + docs already in place; those targets ship as binaries/archives meanwhile.

### Canceled
