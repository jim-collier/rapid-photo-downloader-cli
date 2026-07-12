#!/usr/bin/env bash

##	- Purpose: the version lives in Go source and is the source of truth (see
##	  design.md "Versioning"). This checks that it was actually bumped before a
##	  release - i.e. the in-source version is strictly greater than the latest
##	  git release tag. Prints the resolved version on stdout.
##	- Modes:
##	    (default)  warn-only: report and return 0 even if not bumped. cicd.bash
##	               calls it this way - a normal publish is not a release.
##	    --strict   non-zero if the version is missing, malformed, or not ahead of
##	               the latest tag. The release workflow uses this to block a
##	               release that forgot the bump.
##	- Guard: no version file yet -> print nothing, return 0 (like have_go_code;
##	  the whole thing lights up once the source lands).
##	- Syntax: cicd/utility/version-check.bash [--strict]

##	History: At bottom of script.

##	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
strict=0; [[ "${1:-}" == "--strict" ]] && strict=1

# Canonical location + format, kept dead simple so a plain grep is stable.
verfile="${root}/internal/version/version.go"
fail(){ echo "[ version-check: $* ]" >&2; ((strict)) && exit 1; exit 0; }

[[ -f "$verfile" ]] || { ((strict)) && fail "no version source yet (${verfile#"$root"/})"; exit 0; }

ver="$(grep -oE 'const[[:space:]]+Version[[:space:]]*=[[:space:]]*"[^"]+"' "$verfile" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
[[ -n "$ver" ]] || fail "could not parse Version from ${verfile#"$root"/}"
echo "$ver"

# Latest release tag (vX.Y.Z). None yet -> first release, nothing to compare.
last="$(git -C "$root" tag --list 'v[0-9]*' --sort=-v:refname | head -1)"
[[ -n "$last" ]] || { echo "[ version-check: v${ver} would be the first release ]" >&2; exit 0; }

lastnum="${last#v}"
top="$(printf '%s\n%s\n' "$ver" "$lastnum" | sort -V | tail -1)"
if [[ "$ver" == "$lastnum" ]] || [[ "$top" != "$ver" ]]; then
	fail "in-source version ${ver} is not ahead of latest tag ${last} - bump internal/version"
fi
echo "[ version-check: ${ver} is ahead of ${last} - OK ]" >&2


##	History:
##		- 2026-07-11 JC: Created.
