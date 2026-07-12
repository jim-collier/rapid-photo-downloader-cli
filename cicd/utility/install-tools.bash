#!/usr/bin/env bash

#  shellcheck disable=1091  ## sourced env path is known at runtime, not to shellcheck.

##	- Purpose: install the pinned audit/lint tools at the exact versions in
##	  cicd/tool-versions.env, so local runs and CI agree. Idempotent: a tool
##	  already on PATH at any version is left alone unless FORCE=1. Fail-soft -
##	  a single tool that won't install warns and moves on (govulncheck/gosec
##	  are optional; the harness already skips a missing one).
##	- Syntax: cicd/utility/install-tools.bash [tool ...]
##	    no args -> the security suites the harness runs (govulncheck, gosec)
##	    names   -> any of: govulncheck gosec golangci-lint staticcheck goreleaser
##	  Env: FORCE=1 reinstall even if present.

##	History: At bottom of script.

##	Copyright © 2026 Jim Collier (ID: 1cv◂‡Vᛦ)
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${here}/../tool-versions.env"
export PATH="${HOME}/.go/bin:${HOME}/.local/bin:${HOME}/go/bin:${PATH}"

fEcho(){ echo -e "[ $* ]"; }
have(){ command -v "$1" >/dev/null 2>&1; }
force="${FORCE:-0}"

## go install a pinned module, tolerating failure (offline, yanked tag, etc.).
go_get(){ local bin="$1" path="$2"; if ((! force)) && have "$bin"; then fEcho "$bin present ($(command -v "$bin")) - skip"; return 0; fi
	fEcho "installing ${path}"; go install "${path}" 2>&1 || { fEcho "WARNING: could not install ${path} - skipping"; return 0; }; }

install_one(){ case "$1" in
	govulncheck)    go_get govulncheck    "golang.org/x/vuln/cmd/govulncheck@${GOVULNCHECK_VERSION}" ;;
	gosec)          go_get gosec          "github.com/securego/gosec/v2/cmd/gosec@${GOSEC_VERSION}" ;;
	staticcheck)    go_get staticcheck    "honnef.co/go/tools/cmd/staticcheck@${STATICCHECK_VERSION}" ;;
	golangci-lint)  go_get golangci-lint  "github.com/golangci/golangci-lint/v2/cmd/golangci-lint@${GOLANGCI_LINT_VERSION}" ;;
	goreleaser)     go_get goreleaser     "github.com/goreleaser/goreleaser/v2@${GORELEASER_VERSION}" ;;
	*) fEcho "WARNING: unknown tool '$1'"; return 0 ;;
esac; }

targets=("$@"); ((${#targets[@]})) || targets=(govulncheck gosec)
for t in "${targets[@]}"; do install_one "$t"; done


##	History:
##		- 2026-07-11 JC: Created (pins tool versions for local + CI).
