#!/usr/bin/env bash

#  shellcheck disable=1091  ## 'source is valid here, but shellcheck doesn't know the path to it.'
#  shellcheck disable=2001  ## 'See if you can use ${variable//search/replace} instead.' Complains about good uses of sed.
#  shellcheck disable=2016  ## 'Expressions don't expand in single quotes, use double quotes for that.' I know, and I often want an explicit '$'.
#  shellcheck disable=2034  ## 'variable appears unused.' Complains about valid use of variable indirection.
#  shellcheck disable=2046  ## 'Quote to prevent word-splitting.' (OK for integers.)
#  shellcheck disable=2086  ## 'Double quote to prevent globbing and word splitting.' (OK for integers.)
#  shellcheck disable=2154  ## 'referenced but not assigned.' False hit on 'rc=$?' assigned inside the ERR trap string.
#  shellcheck disable=2155  ## 'Declare and assign separately to avoid masking return values.' Cumbersome and unnecessary.
#  shellcheck disable=2181  ## 'Check exit code directly, not indirectly with $?.'
#  shellcheck disable=2317  ## 'Can't reach.' (I.e. an 'exit' is used for debugging - and makes an unusable visual mess.)

##	- Purpose: Local CI/CD pipeline. Generic engine; per-project settings live in
##	  config.bash. Stages that need Go source skip cleanly until there is code to
##	  build, so this runs (and can publish) from day one.
##	- Stages (fail-fast, any error aborts before the next stage):
##	   1. format    (gofmt)
##	   2. debug build (go build ./...)
##	   3. test harness (vet, go test, race, fuzz, govulncheck, gosec)
##	   4. profiler   (flamegraph SVG; non-gating artifact - see failure policy)
##	   5. release    (native + cross targets, then packages: deb/rpm + win installer)
##	   6. dogfood    (install native release locally)
##	   7. backup + publish to git (runs from repo root)
##	- Syntax:
##	  cicd/cicd.bash [options]
##	  Options:
##	   -y, --yes           run unattended (no message prompt)
##	   -q, --quiet         quiet + unattended (implies -y); publish runs quiet too
##	   -m, --message MSG   publish hands-off with this commit message (no editor)
##	       --msg MSG       alias for --message
##	   --quick             skip the slow stages (cross-builds, packaging, profiling, race+fuzz)
##	   --no-fmt            skip the formatter stage
##	   --no-test           skip the test harness stage
##	   --no-cross          skip cross-target release builds
##	   --no-package        skip building distributable packages (deb/rpm, win installer)
##	   --no-profile        skip the profiler stage
##	   --no-dogfood        skip installing the native release locally
##	   --no-publish        skip the git backup + publish stage
##	   -h, --help
##	- Reuse: copy the cicd/ directory into another project and edit config.bash.

##	History: At bottom of script.

##	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

## Find the repo root and load project config.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"                                  # the git repo root (cicd/..)
export PATH="${HOME}/.go/bin:${HOME}/.local/bin:${HOME}/go/bin:${HOME}/.cargo/bin:${PATH}"  ## go toolchain, go-installed tools, inferno
source "${here}/config.bash"
source "${here}/utility/include/gfs-rotate.bash"                  ## gfs_rotate() for the artifacts
declare -p FMT_CMD &>/dev/null || FMT_CMD=()                      ## tolerate a config without the fmt stage
: "${BUILD_PACKAGES:=0}"                                          ## tolerate a config without the packaging block
cd "${root}"
stamp="$(date +%Y%m%d-%H%M%S)"

## Parse options.
assume_yes=0; quiet=0; quick=0; cli_message=""
while (($#)); do case "$1" in
	-y|--yes)                 assume_yes=1; shift ;;
	-q|--quiet)               quiet=1; assume_yes=1; shift ;;   ## quiet + unattended; publish runs quiet too
	--no-fmt)                 FMT_CMD=(); shift ;;
	--no-test)                TEST_HARNESS=(); shift ;;
	--no-cross)               BUILD_CROSS=0; shift ;;
	--no-package)             BUILD_PACKAGES=0; shift ;;
	--no-profile)             PROFILE_ENABLE=0; shift ;;
	--no-dogfood)             DOGFOOD_FIXED_DESTS=(); DOGFOOD_ROTATING_DESTS=(); shift ;;
	--no-publish)             GIT_PUBLISH=(); shift ;;
	--quick)                  quick=1; BUILD_CROSS=0; BUILD_PACKAGES=0; PROFILE_ENABLE=0; shift ;;   ## skip the slow stages
	--message=*|--msg=*|-m=*) cli_message="${1#*=}"; shift ;;
	-m|--message|--msg)       cli_message="${2-}"; shift; (($#)) && shift ;;
	-h|--help)                sed -n '/^##	- Purpose:/,/^##	History:/p' "${BASH_SOURCE[0]}" | sed '$d; s/^##	\{0,1\}//'; exit 0 ;;
	*) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
esac; done

## Publish commit message: -m wins, then config, then a default when unattended.
## Empty -> publish interactively (git commit opens an editor); when interactive
## we offer to capture a message at the preflight prompt below.
publish_msg=""
if   [[ -n "$cli_message" ]];              then publish_msg="$cli_message"
elif [[ -n "${PUBLISH_AUTO_MESSAGE:-}" ]]; then publish_msg="$PUBLISH_AUTO_MESSAGE"
elif ((assume_yes));                       then publish_msg="${EXE_NAME} cicd ${stamp}"
fi

## Output helpers: fEcho / fEcho_Clean, blank-collapsing. fEcho "msg" -> "[ msg ]"
## status line; fEcho_Clean "msg" -> plain line, a bare call collapses repeated
## blanks. fSection draws the leading-blank + rule letterbox before a stage
## header; fDie prints a fatal line and exits.
declare -i _wasLastEchoBlank=0
fEcho_ResetBlankCounter(){ _wasLastEchoBlank=0; }
fEcho_Clean(){ if [[ -n "${1:-}" ]]; then echo -e "$*"; _wasLastEchoBlank=0; elif [[ $_wasLastEchoBlank -eq 0 ]] && echo; then _wasLastEchoBlank=1; fi; }
fEcho(){       if [[ -n "$*"     ]]; then fEcho_Clean "[ $* ]"; else fEcho_Clean ""; fi; }
fEcho_Force(){ fEcho_ResetBlankCounter; fEcho "$*"; }
_letterbox="••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••"
fSection(){ fEcho_Clean; fEcho_Clean "${_letterbox}"; fEcho "$*"; }
fDie(){ { fEcho_Force "FAILED: $*"; } >&2; exit 1; }

## True once there is buildable Go source - go.mod plus at least one package go
## can list. Every Go stage guards on this so an empty pre-code repo still runs
## (and can back up + publish) without a wall of build errors.
declare -i _goChecked=0 _goHave=0
have_go_code(){
	((_goChecked)) && return $((! _goHave))
	_goChecked=1; _goHave=0
	[[ -f "${root}/go.mod" ]] || return 1
	[[ -n "$(go list ./... 2>/dev/null)" ]] && _goHave=1
	return $((! _goHave))
}

## True if a running process is executing the given binary (its own exe, not a
## substring match), so an in-use dogfood copy isn't pruned. Checks /proc/*/exe.
in_use(){
	local -r bin="$(realpath -e "$1" 2>/dev/null || true)"
	[[ -n "$bin" ]] || return 1
	local exe
	for e in /proc/[0-9]*/exe; do
		exe="$(realpath -e "$e" 2>/dev/null || true)"
		[[ "$exe" == "$bin" ]] && return 0
	done
	return 1
}

## Stage 5b: build distributable packages from the release binaries. Fail-soft per
## builder - a missing tool skips that format with a warning (nfpm is auto-installed
## at its pinned version when absent; NSIS/makensis is a system pkg). Guarded on go
## code + a resolved in-source version. Output -> PACKAGE_OUT_DIR (dist/, gitignored).
run_packaging(){
	((BUILD_PACKAGES)) || { fEcho_Clean "packaging disabled$( ((quick)) && echo ' (--quick)')"; return 0; }
	have_go_code       || { fEcho_Clean "packaging skipped (no Go code yet)"; return 0; }

	local ver; ver="$("${here}/utility/version-check.bash" 2>/dev/null || true)"
	[[ -n "$ver" ]] || { fEcho "WARNING: packaging skipped (no version in internal/version yet)"; return 0; }
	mkdir -p "${root}/${PACKAGE_OUT_DIR}"

	## Linux .deb + .rpm via nfpm. nfpm.yaml is a template - render the ${PKG_*}
	## placeholders per arch (nfpm's globber would otherwise choke on the ${...}),
	## then build each format from the rendered file.
	if ((${#PKG_LINUX_BINS[@]})) && [[ -n "${NFPM_CONFIG:-}" ]]; then
		command -v nfpm >/dev/null 2>&1 || { fEcho_Clean "nfpm absent - installing (pinned)"; "${here}/utility/install-tools.bash" nfpm >/dev/null 2>&1 || true; }
		if command -v nfpm >/dev/null 2>&1; then
			local entry arch bin fmt out rendered
			for entry in "${PKG_LINUX_BINS[@]}"; do
				arch="${entry%%|*}"; bin="${entry#*|}"
				[[ -f "${root}/${bin}" ]] || { fEcho "WARNING: linux ${arch} binary missing (${bin}) - skip its packages"; continue; }
				rendered="${PACKAGE_OUT_DIR}/.nfpm-${arch}.yaml"
				sed -e "s|\${PKG_ARCH}|${arch}|g" -e "s|\${PKG_VERSION}|${ver}|g" -e "s|\${PKG_BIN}|${bin}|g" "${NFPM_CONFIG}" > "${rendered}"
				for fmt in "${NFPM_FORMATS[@]}"; do
					out="${PACKAGE_OUT_DIR}/${EXE_NAME}_${ver}_${arch}.${fmt}"
					if nfpm package -f "${rendered}" -p "$fmt" -t "${out}" >/dev/null 2>&1
					then fEcho "OK: ${fmt} (${arch}): ${out}"
					else fEcho "WARNING: nfpm ${fmt} (${arch}) failed - skipping"; fi
				done
				rm -f "${rendered}"
			done
		else
			fEcho "WARNING: nfpm unavailable - skipping deb/rpm"
		fi
	fi

	## Windows single-file installer .exe via NSIS (self-contained, upgrade-in-place).
	if ((${#PKG_WINDOWS_BINS[@]})) && [[ -n "${NSIS_SCRIPT:-}" ]]; then
		if command -v makensis >/dev/null 2>&1; then
			local wentry warch wbin wout
			for wentry in "${PKG_WINDOWS_BINS[@]}"; do
				warch="${wentry%%|*}"; wbin="${wentry#*|}"
				[[ -f "${root}/${wbin}" ]] || { fEcho "WARNING: windows ${warch} binary missing (${wbin}) - skip its installer"; continue; }
				wout="${PACKAGE_OUT_DIR}/${EXE_NAME}-${ver}-windows-${warch}-setup.exe"
				if makensis -V2 -DVERSION="$ver" -DARCH="$warch" -DSRCEXE="${root}/${wbin}" -DOUTFILE="${root}/${wout}" "${NSIS_SCRIPT}" >/dev/null 2>&1
				then fEcho "OK: windows installer (${warch}): ${wout}"
				else fEcho "WARNING: NSIS installer (${warch}) failed - skipping"; fi
			done
		else
			fEcho "WARNING: makensis (NSIS) not installed - skipping windows installer (apt install nsis)"
		fi
	fi
	## macOS .dmg + FreeBSD pkg are deferred (need a Mac/Apple cert and a FreeBSD
	## builder); those targets still ship as archives via goreleaser on release.
}
trap 'rc=$?; printf "\n[ CICD ABORTED (exit %s) at line %s: %s ]\n" "$rc" "$LINENO" "$BASH_COMMAND" >&2; exit $rc' ERR

## Preflight: show the plan with resolved paths.
profile_dir="$(cd "${root}" && mkdir -p "${PROFILE_OUT_DIR}" 2>/dev/null; cd "${PROFILE_OUT_DIR}" 2>/dev/null && pwd || echo "${root}/${PROFILE_OUT_DIR}")"
fixed_dest=""; for d in "${DOGFOOD_FIXED_DESTS[@]:-}"; do [[ -d "$d" && -w "$d" ]] && { fixed_dest="$d"; break; }; done
rot_dest="";   for d in "${DOGFOOD_ROTATING_DESTS[@]:-}"; do [[ -d "$d" && -w "$d" ]] && { rot_dest="$d"; break; }; done
rot_target="${rot_dest:-${DOGFOOD_ROTATING_DESTS[0]:-}}"  # created in stage 6 if it doesn't exist yet
code_note=""; have_go_code || code_note="  (no Go code yet - build/test/profile skip)"

fEcho_Clean
fEcho_Clean "${APP_NAME} local CI/CD${code_note}"
fEcho_Clean
fEcho_Clean "Repo root ...........: ${root}"
fEcho_Clean "Format ..............: ${FMT_CMD[*]:-(skipped)}"
fEcho_Clean "Debug build .........: ${DEBUG_BUILD_CMD[*]}"
fEcho_Clean "Test harness ........: ${TEST_HARNESS[*]:-(skipped)}$( ((quick)) && echo '  (--quick: no race/fuzz)')"
if ((PROFILE_ENABLE)); then
	fEcho_Clean "Profiler ............: ${PROFILE_SECS}s workload -> inferno flamegraph SVG"
	fEcho_Clean "  output dir ........: ${profile_dir}"
else
	fEcho_Clean "Profiler ............: (disabled$( ((quick)) && echo ' - --quick'))"
fi
fEcho_Clean "Release (native) ....: ${RELEASE_NATIVE_CMD[*]} -> ${RELEASE_NATIVE_BIN}"
if ((BUILD_CROSS)) && ((${#CROSS_TARGETS[@]})); then
	fEcho_Clean "Release (cross) .....:"
	for t in "${CROSS_TARGETS[@]}"; do fEcho_Clean "    - ${t%%|*}"; done
else
	fEcho_Clean "Release (cross) .....: (skipped)"
fi
if ((BUILD_PACKAGES)); then
	fEcho_Clean "Packages ............: deb/rpm (linux) + installer .exe (windows)$(have_go_code || echo '  (skips - no code yet)')"
else
	fEcho_Clean "Packages ............: (skipped$( ((quick)) && echo ' - --quick'))"
fi
if ((${#DOGFOOD_FIXED_DESTS[@]})); then
	if [[ -n "$fixed_dest" ]]; then fEcho_Clean "Dogfood, fixed name .: overwrite ${fixed_dest}/${EXE_NAME}"
	else fEcho_Clean "Dogfood, fixed name .: <none of: ${DOGFOOD_FIXED_DESTS[*]} exists - will skip>"; fi
else
	fEcho_Clean "Dogfood, fixed name .: (disabled)"
fi
if ((${#DOGFOOD_ROTATING_DESTS[@]})) && [[ -n "${DOGFOOD_PREFIX:-}" ]]; then
	fEcho_Clean "Dogfood, rotating ...: ${rot_target}/${DOGFOOD_PREFIX}_${stamp}  (dated copy; prunes idle ones)"
else
	fEcho_Clean "Dogfood, rotating ...: (disabled)"
fi
if ((${#GIT_PUBLISH[@]} == 0)); then
	fEcho_Clean "Publish (last) ......: (disabled)"
elif [[ -n "$publish_msg" ]]; then
	fEcho_Clean "Publish (last) ......: ${GIT_PUBLISH[*]} (hands-off: \"${publish_msg}\")"
else
	fEcho_Clean "Publish (last) ......: ${GIT_PUBLISH[*]} (will prompt for message; blank = editor)"
fi
fEcho_Clean
fEcho_Clean "Fail-fast: any error aborts before the next stage."
fEcho_Clean

if ((! assume_yes)); then
	## Capture the commit message up front so the run can finish unattended. This
	## is the natural place to bail on the common (publish) path - Ctrl+C here
	## aborts; there is no separate "Proceed? [y/N]" (removed to cut friction).
	if ((${#GIT_PUBLISH[@]})) && [[ -z "$publish_msg" ]]; then
		read -r -p "Publish commit message (blank = editor; Ctrl+C aborts): " m
		fEcho_ResetBlankCounter
		[[ -n "$m" ]] && publish_msg="$m"
	fi
fi

## Tee the rest of the run (all stages) to a gitignored log so warnings from any
## stage can be reviewed after the fact (lint-report.bash distils them). Rotate
## the prior (closed) logs first.
if [[ -n "${LINT_LOG_DIR:-}" ]] && mkdir -p "${root}/${LINT_LOG_DIR}" 2>/dev/null; then
	gfs_rotate "${root}/${LINT_LOG_DIR}" run log >/dev/null 2>&1 || true
	exec > >(tee "${root}/${LINT_LOG_DIR}/run_${stamp}.log") 2>&1
fi

## Stage 1: format.
fSection "1/7  Format"
if ((${#FMT_CMD[@]} == 0)); then
	fEcho_Clean "format skipped"
elif ! have_go_code; then
	fEcho_Clean "format skipped (no Go code yet)"
else
	"${FMT_CMD[@]}"
	fEcho "OK: formatted (${FMT_CMD[*]})"
fi

## Stage 2: debug build.
fSection "2/7  Debug build"
if ! have_go_code; then
	fEcho_Clean "debug build skipped (no Go code yet)"
else
	"${DEBUG_BUILD_CMD[@]}"
	fEcho "OK: debug build"
fi

## Stage 3: test harness (regression + race + fuzz + security). The harness
## probes its own tools and honours CICD_QUICK; a real failure aborts here.
fSection "3/7  Test harness"
if ((${#TEST_HARNESS[@]} == 0)); then
	fEcho_Clean "tests skipped (--no-test)"
elif ! have_go_code; then
	fEcho_Clean "tests skipped (no Go code yet)"
else
	CICD_QUICK=${quick} "${root}/${TEST_HARNESS[0]}" "${TEST_HARNESS[@]:1}"
	fEcho_ResetBlankCounter
	fEcho "OK: tests passed"
fi

## Stage 4: profiler (non-gating artifact; failures classified below). The
## workload script owns the Go specifics and reports its outcome by exit code:
##   0 = wrote an SVG, 3 = nothing to profile / tools missing (skip), else = fault.
run_profiler(){
	((PROFILE_ENABLE)) || { fEcho_Clean "profiler disabled$( ((quick)) && echo ' (--quick)')"; return 0; }
	have_go_code       || { fEcho_Clean "profiler skipped (no Go code yet)"; return 0; }
	[[ -f "${root}/${PROFILE_WORKLOAD[0]}" ]] || { fEcho "WARNING: profiler skipped: workload missing: ${PROFILE_WORKLOAD[0]}"; return 0; }

	mkdir -p "${profile_dir}"
	## Born canonical (role "frequent"); rotation retags the newest as "latest".
	local out="${profile_dir}/flame_${stamp}_frequent.svg"
	fEcho_Clean "running ${PROFILE_SECS}s profile workload -> flamegraph ..."
	local prc=0
	"${root}/${PROFILE_WORKLOAD[0]}" "${PROFILE_WORKLOAD[@]:1}" "$out" "${PROFILE_SECS}" || prc=$?
	if ((prc == 3)); then
		((PROFILE_STRICT)) && fDie "profiler: workload reported nothing to profile (or tools missing)"
		fEcho "WARNING: profiler skipped (nothing to profile yet, or profiling tools missing)"; return 0
	fi
	((prc == 0)) || fDie "profiler workload failed (exit ${prc} - app problem)"
	[[ -s "$out" ]] || fDie "profiler produced no SVG (app problem): ${out}"
	gfs_rotate "${profile_dir}" flame svg
	local latest="${profile_dir}/flame_${stamp}_latest.svg"
	[[ -e "$latest" ]] || latest="$out"
	fEcho "OK: flamegraph: ${latest}"
	fEcho_Clean "open: ${latest}  (in a browser)"

	## Hot-spot summary into the log (non-fatal, no marker - the marker is for the
	## per-session --check gate, not the pipeline).
	local report="${here}/utility/flame-report.py"
	if [[ -f "$report" ]] && command -v python3 >/dev/null 2>&1; then
		fEcho_Clean ""
		python3 "$report" --dir "${profile_dir}" 2>/dev/null || fEcho_Clean "hot spots: (report unavailable)"
	fi
}
fSection "4/7  Profiler"
run_profiler

## Stage 5: release builds.
fSection "5/7  Release build (native)"
if ! have_go_code; then
	fEcho_Clean "release skipped (no Go code yet)"
else
	"${RELEASE_NATIVE_CMD[@]}"
	[[ -f "${RELEASE_NATIVE_BIN}" ]] || fDie "native release binary missing: ${RELEASE_NATIVE_BIN}"
	fEcho "OK: native release: ${RELEASE_NATIVE_BIN} ($(du -h "${RELEASE_NATIVE_BIN}" | cut -f1))"
	if ((BUILD_CROSS)) && ((${#CROSS_TARGETS[@]})); then
		for t in "${CROSS_TARGETS[@]}"; do
			local_label="${t%%|*}"; rest="${t#*|}"; art="${rest%%|*}"; cmd="${rest#*|}"
			fSection "5/7  Release build: ${local_label}"
			eval "${cmd}"
			[[ -f "${art}" ]] || fDie "missing artifact for ${local_label}: ${art}"
			fEcho "OK: ${local_label}: ${art} ($(du -h "${art}" | cut -f1))"
		done
	fi
fi

## Stage 5b: distributable packages (deb/rpm + windows installer) from the binaries.
fSection "5/7  Package (deb/rpm + windows installer)"
run_packaging

## Stage 6: dogfood. Two independent installs (fixed overwrite + rotating dated copy).
fSection "6/7  Dogfood (install native release locally)"
df_did=0
if ! have_go_code || [[ ! -f "${RELEASE_NATIVE_BIN}" ]]; then
	fEcho_Clean "dogfood skipped (no native binary)"
else
	## 6a. Fixed name: overwrite EXE_NAME (the stable path you launch by hand).
	if ((${#DOGFOOD_FIXED_DESTS[@]})); then
		if [[ -n "$fixed_dest" ]]; then
			cp -f "${RELEASE_NATIVE_BIN}" "${fixed_dest}/${EXE_NAME}"
			fEcho "OK: installed (fixed) -> ${fixed_dest}/${EXE_NAME}"
			df_did=1
		else
			fEcho "WARNING: no fixed dogfood dest exists (${DOGFOOD_FIXED_DESTS[*]}); skipping"
		fi
	fi

	## 6b. Rotating name: dated copy so builds coexist; prune older ones not running.
	if ((${#DOGFOOD_ROTATING_DESTS[@]})) && [[ -n "${DOGFOOD_PREFIX:-}" ]]; then
		[[ -z "$rot_dest" && -n "$rot_target" ]] && mkdir -p "$rot_target" 2>/dev/null && rot_dest="$rot_target"
		if [[ -n "$rot_dest" && -w "$rot_dest" ]]; then
			df_name="${DOGFOOD_PREFIX}_${stamp}"
			cp -f "${RELEASE_NATIVE_BIN}" "${rot_dest}/${df_name}"
			chmod +x "${rot_dest}/${df_name}"
			fEcho "OK: installed (rotating) -> ${rot_dest}/${df_name}"
			pruned=0
			for old in "${rot_dest}/${DOGFOOD_PREFIX}_"*; do
				[[ -e "$old" ]] || continue                  # no-match glob (nullglob is off)
				[[ "$(basename "$old")" == "$df_name" ]] && continue
				if in_use "$old"; then
					fEcho_Clean "kept (running): $(basename "$old")"
				else
					rm -f "$old" && pruned=$((pruned + 1))
				fi
			done
			if ((pruned)); then fEcho_Clean "pruned ${pruned} old copy(ies) not in use"; fi
			df_did=1
		else
			fEcho "WARNING: no rotating dogfood dest writable (${DOGFOOD_ROTATING_DESTS[*]}); skipping"
		fi
	fi
	if ((! df_did)); then fEcho_Clean "dogfood disabled"; fi
fi

## Stage 7: backup + publish.
fSection "7/7  Backup + publish"
## Pre-publish gate. On the release branch (a push there cuts a release) it is
## strict: version must be bumped past the last tag and the README badge must
## agree, or we abort before publishing. On any other branch the same checks run
## warn-only. All skip silently until the version source lands. The AI-tell scrub
## lives outside the tree (../private/hooks); absent -> skipped, never an error.
cur_branch="$(git -C "${root}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
gate_strict=0; [[ -n "$cur_branch" && "$cur_branch" == "${RELEASE_BRANCH:-main}" ]] && gate_strict=1
gate_flag=(); ((gate_strict)) && gate_flag=(--strict)

scrub="${root}/${PRIVATE_HOOKS_DIR:-../private/hooks}/ai-tell-scrub.bash"
if [[ -x "$scrub" ]]; then
	if ! "$scrub" "${root}" >&2; then
		((gate_strict)) && fDie "AI-tell scrub found giveaways (release branch '${cur_branch}')"
		fEcho "WARNING: AI-tell scrub found giveaways - scrub before releasing"
	fi
fi
if [[ -x "${here}/utility/version-check.bash" ]]; then
	"${here}/utility/version-check.bash" "${gate_flag[@]}" >/dev/null \
		|| fDie "version not bumped for release branch '${cur_branch}' - bump internal/version"
fi
if [[ -x "${here}/utility/badge-check.bash" ]]; then
	"${here}/utility/badge-check.bash" "${gate_flag[@]}" \
		|| fDie "README badge disagrees with in-source version (release branch '${cur_branch}')"
fi
## Always run the publisher quiet: cicd already gave the initial prompt, so skip
## its redundant continue-prompt. With no message it still lets git open the editor.
pub_flags=(--quiet)
[[ -n "$publish_msg" ]] && pub_flags+=(--message "$publish_msg")
if ((${#GIT_PUBLISH[@]} == 0)); then
	fEcho_Clean "publish disabled"
elif [[ -n "$publish_msg" ]]; then
	fEcho_Clean "hands-off publish (commit message: \"${publish_msg}\")"
	"${GIT_PUBLISH[@]}" "${pub_flags[@]}"
	fEcho "OK: published"
else
	"${GIT_PUBLISH[@]}" "${pub_flags[@]}"
	fEcho "OK: published"
fi

fSection "${APP_NAME} CI/CD: done."
fEcho_Clean


##	History:
##		- 2026-07-09 JC: Created (Go adaptation of the silkterm cicd template).
