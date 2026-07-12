#!/usr/bin/env bash

##	- Purpose: the README shows a version. It must never disagree with the
##	  in-source version (internal/version, the source of truth). The release
##	  badge is the dynamic shields.io "latest release" form, so it tracks the
##	  git tag on its own - the real risk is (a) it points at the wrong repo, or
##	  (b) someone hardcodes a stale vX.Y.Z badge. This catches both.
##	- Modes:
##	    (default)  warn-only: report a mismatch and return 0.
##	    --strict   non-zero on any mismatch. The release path uses this so a
##	               push to the release branch can't ship a lying badge.
##	- Guard: no version source yet -> nothing to compare, return 0 (like
##	  version-check / have_go_code; lights up once the source lands).
##	- Syntax: cicd/utility/badge-check.bash [--strict]

##	History: At bottom of script.

##	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
strict=0; [[ "${1:-}" == "--strict" ]] && strict=1

readme="${root}/README.md"
warn(){ echo "[ badge-check: $* ]" >&2; ((strict)) && exit 1; return 0; }

# In-source version (empty until the source lands -> nothing to enforce yet).
ver="$("${here}/version-check.bash" 2>/dev/null || true)"
[[ -n "$ver" ]] || exit 0
[[ -f "$readme" ]] || { warn "no README.md to check"; exit 0; }

# Repo slug (owner/name) from the origin remote, to confirm the dynamic release
# badge points at THIS repo and not a stale copy from a forked template.
slug="$(git -C "$root" config --get remote.origin.url 2>/dev/null \
	| sed -E 's#\.git$##; s#^.*[:/]([^/]+/[^/]+)$#\1#')"
if [[ -n "$slug" ]]; then
	grep -qiE "shields\.io/github/v/release/${slug}(\?|\")" "$readme" \
		|| warn "release badge does not reference ${slug} - stale or wrong repo"
fi

# Any hardcoded vX.Y.Z sitting in a badge line must equal the in-source version.
# The dynamic badge carries no literal version, so a match here means someone
# pinned one by hand and let it drift.
stale="$(grep -nE 'shields\.io|badge' "$readme" \
	| grep -oiE 'v?[0-9]+\.[0-9]+\.[0-9]+' | sed 's/^[vV]//' | sort -u | grep -vxF "$ver" || true)"
[[ -z "$stale" ]] || warn "README badge version(s) [$(echo "$stale" | paste -sd, -)] != in-source ${ver}"

echo "[ badge-check: README agrees with ${ver} ]" >&2


##	History:
##		- 2026-07-11 JC: Created.
