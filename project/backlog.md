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

- 🔘 A CI/CD pipeline kicked off by a bash script (`cicd/cicd.bash`): builds, tests, and can commit and push. Packaging and publishing are opt-in.

- 🔘 Dev-environment install script (Linux bash, macOS sh, Windows PowerShell), runnable via a single `curl`/`wget` and documented under "how to develop". Clones main, installs dependencies, and states what it will do with an option to abort.

- 🔘 Release-install script per platform, runnable via a single `curl`/`wget` and documented under "how to install". Downloads, installs, and runs the latest release, with an option to abort.

- 🔘 Default configuration hard-coded
	- 🔘 Overridden by per-user config file, created the first time a default setting is changed.
		- 🔘 Settings live under `~/.config/rpdc/config.ashl`.
	- 🔘 Overridden by program options at run-time.

## Backlog

### Misc to-do

### Bugs

### Features and enhancements

- 🔘 When listing flags (e.g. for `--help`), figure out a way to simplify the many ways of showing `--[i][whole]name-inc[lude]="*glob*"`, for example. In most cases, users will just do something like `--name-inc="*.IMG"`. But they won't do anything, if they are overwhelmed with complex help. The file selection option documentation, in particular are very dense. (And hard to read.)

- 🔘 Make ASHL its own standalone module for config-file reading, with easy reusability.
	- Options:
		- A monorepo with a ASHL reader/writer in multiple languages and a common test harness...
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
