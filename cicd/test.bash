#!/usr/bin/env bash

#  shellcheck disable=2086  ## 'Double quote to prevent word splitting.' OK for integer flags.
#  shellcheck disable=2155  ## 'Declare and assign separately.' Cumbersome and unnecessary here.

##	- Purpose: Test harness for the Go module. Runs regression, race, fuzz, and
##	  security suites. Called by cicd.bash stage 3 (from the repo root), but also
##	  runnable by hand. Slow suites (race, fuzz) skip when CICD_QUICK=1; any tool
##	  that isn't installed skips with a warning instead of aborting. A genuine test
##	  failure exits non-zero (which aborts the pipeline).
##	- Suites:
##	   vet          go vet ./...                     (always)
##	   test         go test ./...                    (always)
##	   race         go test -race ./...              (skipped under --quick)
##	   fuzz         go test -fuzz per target, short  (skipped under --quick)
##	   govulncheck  known-vuln scan of our + dependency (library) code  (if installed)
##	   gosec        static security scan of first-party code            (if installed)
##	- Syntax: cicd/test.bash        (env: CICD_QUICK=1 to skip the slow suites)

##	History: At bottom of script.

##	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"
export PATH="${HOME}/.go/bin:${HOME}/.local/bin:${HOME}/go/bin:${PATH}"
source "${here}/tool-versions.env"   ## pinned tool versions (same set CI uses)
cd "${root}"

## Hold go test / race / vet to <=50% of cores when run standalone; honour cicd.bash's
## exported GOMAXPROCS when called from the pipeline (see config.bash).
: "${GOMAXPROCS:=$(( "$(nproc 2>/dev/null || echo 2)" / 2 ))}"; (( GOMAXPROCS < 1 )) && GOMAXPROCS=1; export GOMAXPROCS

quick="${CICD_QUICK:-0}"
fuzztime="${CICD_FUZZTIME:-10s}"   # per fuzz target; short by default

## Output helpers (same family as cicd.bash).
declare -i _wasLastEchoBlank=0
fEcho_Clean(){ if [[ -n "${1:-}" ]]; then echo -e "$*"; _wasLastEchoBlank=0; elif [[ $_wasLastEchoBlank -eq 0 ]] && echo; then _wasLastEchoBlank=1; fi; }
fEcho(){ if [[ -n "$*" ]]; then fEcho_Clean "[ $* ]"; else fEcho_Clean ""; fi; }
have(){ command -v "$1" >/dev/null 2>&1; }

## Bail early if there is no Go source yet (cicd.bash already guards this, but keep
## the harness safe to run standalone).
if [[ ! -f go.mod ]] || [[ -z "$(go list ./... 2>/dev/null)" ]]; then
	fEcho_Clean "no Go code yet - nothing to test"; exit 0
fi

## Regression: vet then the unit/integration tests.
fEcho "vet ..."
go vet ./...

fEcho "go test ..."
go test ./...

## Race detector (slow). Skipped under --quick.
if [[ "$quick" == "1" ]]; then
	fEcho_Clean "race skipped (--quick)"
else
	fEcho "go test -race ..."
	go test -race ./...
fi

## Fuzz: run each fuzz target briefly. `go test -list` finds Fuzz funcs per package.
## Skipped under --quick (a real fuzz campaign is long).
if [[ "$quick" == "1" ]]; then
	fEcho_Clean "fuzz skipped (--quick)"
else
	fEcho "fuzz (${fuzztime} per target) ..."
	fuzz_any=0
	while read -r pkg; do
		[[ -n "$pkg" ]] || continue
		while read -r fn; do
			[[ -n "$fn" ]] || continue
			fuzz_any=1
			fEcho_Clean "  ${pkg}  ${fn}"
			go test -run='^$' -fuzz="^${fn}\$" -fuzztime="${fuzztime}" "${pkg}"
		done < <(go test -list '^Fuzz' "${pkg}" 2>/dev/null | grep -E '^Fuzz' || true)
	done < <(go list ./... 2>/dev/null)
	((fuzz_any)) || fEcho_Clean "  (no fuzz targets yet)"
fi

## Optionally install the pinned security tools first (CI does this). Off by
## default so a plain local run stays fast and offline; missing tools just skip.
[[ "${CICD_INSTALL_TOOLS:-0}" == "1" ]] && "${here}/utility/install-tools.bash" govulncheck gosec || true

## Security: govulncheck covers our code AND the dependency (library) code it pulls
## in - the "library code too" requirement. gosec statically scans first-party code.
## Versions are pinned in tool-versions.env; the install hints echo the exact pin.
if have govulncheck; then
	fEcho "govulncheck (our code + dependencies) ..."
	govulncheck ./...
else
	fEcho "WARNING: govulncheck not installed - skipping vuln scan (go install golang.org/x/vuln/cmd/govulncheck@${GOVULNCHECK_VERSION})"
fi

if have gosec; then
	fEcho "gosec (first-party static security) ..."
	gosec ./...
else
	fEcho "WARNING: gosec not installed - skipping static security scan (go install github.com/securego/gosec/v2/cmd/gosec@${GOSEC_VERSION})"
fi

fEcho "OK: all test suites passed"


##	History:
##		- 2026-07-09 JC: Created.
