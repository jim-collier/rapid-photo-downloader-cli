#!/usr/bin/env bash

#  shellcheck disable=2086  ## 'Double quote to prevent word splitting.' OK for integer flags.
#  shellcheck disable=2155  ## 'Declare and assign separately.' Cumbersome and unnecessary here.

##	- Purpose: Produce a CPU flamegraph for the profiler stage. Runs the module's
##	  benchmarks under the Go CPU profiler, then renders the pprof profile to an
##	  inferno flamegraph SVG (the fg:w/fg:x format flame-report.py reads).
##	- Contract (called by cicd.bash): profile-workload.bash <out_svg> <secs>
##	    exit 0  wrote <out_svg>
##	    exit 3  nothing to profile yet, or a required tool is missing (engine skips)
##	    else    genuine failure (engine aborts, unless PROFILE_STRICT is off)
##	- Rendering needs inferno (cargo install inferno) for the collapse+flamegraph
##	  step; go tool pprof ships with go. Missing inferno -> exit 3 (skip), so this
##	  is a soft dependency.
##	- Bench selection: BENCH_PKG (default ./...) and BENCH_PAT (default .) pick which
##	  benchmarks feed the profile; point them at a representative hot path once one exists.

##	History: At bottom of script.

##	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

out="${1:?usage: profile-workload.bash <out_svg> <secs>}"
secs="${2:-8}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
export PATH="${HOME}/.go/bin:${HOME}/.local/bin:${HOME}/go/bin:${HOME}/.cargo/bin:${PATH}"
cd "${root}"

benchPkg="${BENCH_PKG:-./...}"
benchPat="${BENCH_PAT:-.}"
have(){ command -v "$1" >/dev/null 2>&1; }

## Nothing to profile without Go source.
[[ -f go.mod ]] && [[ -n "$(go list ./... 2>/dev/null)" ]] || { echo "profile: no Go code yet" >&2; exit 3; }

## Need at least one benchmark to drive the profiler.
if ! go test -list '^Benchmark' ${benchPkg} 2>/dev/null | grep -qE '^Benchmark'; then
	echo "profile: no benchmarks to profile (set BENCH_PKG/BENCH_PAT, or add a Benchmark func)" >&2
	exit 3
fi

## Need inferno to render the pprof profile into the flame-report SVG format.
if ! have inferno-collapse-go || ! have inferno-flamegraph; then
	echo "profile: inferno not installed - skipping (cargo install inferno)" >&2
	exit 3
fi

tmp="$(mktemp -d)"; trap 'rm -rf "${tmp}"' EXIT
prof="${tmp}/cpu.pprof"

## Sample the benchmarks. -benchtime as a duration keeps the run near <secs>.
go test -run='^$' -bench="${benchPat}" -benchtime="${secs}s" -cpuprofile="${prof}" ${benchPkg} >/dev/null \
	|| { echo "profile: benchmark run failed" >&2; exit 1; }
[[ -s "${prof}" ]] || { echo "profile: no cpu profile produced" >&2; exit 1; }

## pprof text traces -> folded stacks -> inferno SVG (carries total_samples + fg:w).
go tool pprof -traces "${prof}" 2>/dev/null \
	| inferno-collapse-go \
	| inferno-flamegraph --title "${APP_NAME:-CPU} profile" \
	> "${out}" \
	|| { echo "profile: flamegraph render failed" >&2; exit 1; }
[[ -s "${out}" ]] || { echo "profile: empty SVG" >&2; exit 1; }

exit 0


##	History:
##		- 2026-07-09 JC: Created.
