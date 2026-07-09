#!/bin/bash

#  shellcheck disable=1091  ## 'source is valid here, but shellcheck doesn't know the path to it.'
#  shellcheck disable=2034  ## 'variable appears unused.' Config is a bag of settings the engine reads.
#  shellcheck disable=2155  ## 'Declare and assign separately.' Cumbersome and unnecessary here.

##	Purpose:
##		- Project-specific CI/CD settings for the Go CLI.
##		- To reuse this pipeline in another project, copy the whole cicd/ directory
##		  and edit THIS file; cicd.bash stays generic. All command arrays run from
##		  the repo root.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


## Check if sourced
declare -i isSourced_t6wqf=0; [[ "${BASH_SOURCE[0]}" == "${0}" ]] || isSourced_t6wqf=1
((isSourced_t6wqf)) || { echo -e "\nError in $(basename "${BASH_SOURCE[0]}"): This script is meant to be 'sourced' from within another script.\n"; exit "${ERRNUM_MSG_ALREADY_SHOWN:-3}"; }


## Identity. EXE_NAME is provisional (design.md still lists rpdc vs dpdc as open).
APP_NAME="Rapid Photo Downloader CLI"
EXE_NAME="rpdc"

## Go build knobs. Static (CGO off) keeps cross-compiles trivial and the binary
## dependency-free; -s -w -trimpath strip symbols/paths for a smaller exe.
GO_LDFLAGS="-s -w"
GO_BUILD_FLAGS=(-trimpath -ldflags "${GO_LDFLAGS}")
export CGO_ENABLED=0

## Stage 1: format the source in place before anything is compiled or tested.
## Go only - never reformat bash (owner rule). Empty () to disable.
FMT_CMD=(gofmt -w .)

## Stage 2: debug build (fast compile sanity across all packages).
DEBUG_BUILD_CMD=(go build ./...)

## Stage 3: test harness (vet, go test, race, fuzz, govulncheck, gosec). Slow
## pieces skip under --quick; missing tools skip with a warning (see test.bash).
TEST_HARNESS=(cicd/test.bash)

## Stage 5: native release build + its artifact (this is what gets dogfooded).
RELEASE_NATIVE_BIN="bin/${EXE_NAME}"
RELEASE_NATIVE_CMD=(go build "${GO_BUILD_FLAGS[@]}" -o "${RELEASE_NATIVE_BIN}" .)

## Stage 5: cross-release targets. One per line: "label|artifact|command...".
## Pure-Go static builds cross-compile with just GOOS/GOARCH - no zig/SDK needed
## (macOS included, as long as we stay CGO-free). Set BUILD_CROSS=0 to skip.
BUILD_CROSS=1
## The command is eval'd (see cicd.bash), so ldflags is quoted literally here -
## expanding the array would split "-s -w" into two broken args.
CROSS_TARGETS=(
	"Linux ARM64|bin/${EXE_NAME}-linux-arm64|GOOS=linux GOARCH=arm64 go build -trimpath -ldflags '${GO_LDFLAGS}' -o bin/${EXE_NAME}-linux-arm64 ."
	"Windows x86_64|bin/${EXE_NAME}-windows-amd64.exe|GOOS=windows GOARCH=amd64 go build -trimpath -ldflags '${GO_LDFLAGS}' -o bin/${EXE_NAME}-windows-amd64.exe ."
	"Windows ARM64|bin/${EXE_NAME}-windows-arm64.exe|GOOS=windows GOARCH=arm64 go build -trimpath -ldflags '${GO_LDFLAGS}' -o bin/${EXE_NAME}-windows-arm64.exe ."
	"macOS ARM64|bin/${EXE_NAME}-darwin-arm64|GOOS=darwin GOARCH=arm64 go build -trimpath -ldflags '${GO_LDFLAGS}' -o bin/${EXE_NAME}-darwin-arm64 ."
	"macOS x86_64|bin/${EXE_NAME}-darwin-amd64|GOOS=darwin GOARCH=amd64 go build -trimpath -ldflags '${GO_LDFLAGS}' -o bin/${EXE_NAME}-darwin-amd64 ."
)

## Stage 4: profiler (non-gating artifact, not a pass/fail test). Runs the CPU
## profile workload, turns the pprof profile into an inferno flamegraph SVG, and
## drops it in PROFILE_OUT_DIR (rotated like the backups). Needs the Go pprof
## toolchain (bundled with go) plus inferno (cargo install inferno) to render the
## SVG in the fg:w/fg:x format flame-report.py reads; a missing piece skips the
## stage with a warning unless PROFILE_STRICT. See cicd.bash for the failure policy.
PROFILE_ENABLE=1
PROFILE_SECS=8                                   # sampled wall-time for the workload
PROFILE_WORKLOAD=(cicd/utility/profile-workload.bash)
PROFILE_OUT_DIR="cicd/artifacts/profiling"       # relative to repo root; created if missing (gitignored)
PROFILE_STRICT=0                                 # 1 = any profiler failure aborts the pipeline

## Full run output is tee'd here (gitignored) so warnings from any stage can be
## reviewed after the fact (lint-report.bash distils them). Rotated like the flamegraphs.
LINT_LOG_DIR="cicd/artifacts/lint"               # relative to repo root; created if missing (gitignored)

## Old artifacts are pruned by gfs_rotate (utility/include/gfs-rotate.bash): keeps
## ~30 - first + newest-per-hour/day/week/month/year + last 10. Tune with the
## GFS_KEEP_* env vars if needed.

## Stage 6: dogfood the native release. Fixed: overwrite EXE_NAME in the first
## existing dir here (the stable path you run). Rotating: also drop a dated copy
## so builds coexist, pruning idle ones. Empty either list to skip that half.
DOGFOOD_FIXED_DESTS=(
	"${HOME}/synced/0-0/common/exec/util/linux/bin"
	"/usr/local/sbin"
)
DOGFOOD_ROTATING_DESTS=(
	"${HOME}/.local/bin"
)
DOGFOOD_PREFIX="rpdcdf"

## Stage 7: backup + publish to git (runs from repo root).
GIT_PUBLISH=(cicd/utility/n8git_backup-and-publish)

## Set non-empty to publish hands-off (supplies the commit message so `git commit`
## won't open an editor). Left empty, publish is interactive unless -m/-q is given.
PUBLISH_AUTO_MESSAGE=""


##	History:
##		- 2026-07-09 JC: Created (Go adaptation of the silkterm cicd template).
