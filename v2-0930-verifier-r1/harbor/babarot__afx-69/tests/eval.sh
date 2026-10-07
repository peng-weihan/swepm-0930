#!/bin/bash
set -euo pipefail
cd /testbed
for p in /usr/local/go/bin /go/bin "$HOME/go/bin"; do
    [ ! -d "$p" ] || export PATH="$p:$PATH"
done
export CMAKE_BUILD_PARALLEL_LEVEL=2
ulimit -c 0
export CARGO_BUILD_JOBS=2
export MAKEFLAGS=-j2
export GOMAXPROCS=4
export PYTEST_XDIST_AUTO_NUM_WORKERS=4
export UV_CACHE_DIR=/logs/verifier/cache/uv
export PIP_CACHE_DIR=/logs/verifier/cache/pip
export TMPDIR=/logs/verifier/tmp
mkdir -p "$TMPDIR" "$UV_CACHE_DIR" "$PIP_CACHE_DIR"
export NO_PROXY="localhost,127.0.0.1,::1${NO_PROXY:+,$NO_PROXY}"
export no_proxy="$NO_PROXY"

files=(cmd/meta_test.go internal/data/data_test.go internal/dependency/dependency_test.go internal/env/config_test.go internal/errors/errors_test.go internal/github/client_test.go internal/github/github_test.go internal/helpers/path/path_test.go internal/helpers/shell/shell_test.go internal/helpers/spin/spin_test.go internal/helpers/templates/normalizer_test.go internal/logging/logging_additional_test.go internal/logging/logging_test.go internal/pkg/command_test.go internal/pkg/config_test.go internal/pkg/installed_test.go internal/pkg/read_test.go internal/pkg/resource_test.go internal/pkg/util_test.go internal/printers/printers_test.go internal/state/state_additional_test.go internal/state/state_test.go internal/templates/templates_test.go internal/update/update_test.go)
declare -A packages=()
for f in "${files[@]}"; do
    test -f "$f"
    d=$(dirname "$f")
    m="$d"
    while [ ! -f "$m/go.mod" ] && [ "$m" != . ]; do m=$(dirname "$m"); done
    test -f "$m/go.mod" || { echo "MISSING_GO_MODULE=$f"; exit 2; }
    if [ "$m" = . ]; then p="./$d"; else p="./${d#"$m"/}"; fi
    [ "$d" != "$m" ] || p=.
    packages["$m|$p"]=1
done
rc=0
for key in "${!packages[@]}"; do
    m=${key%%|*}; p=${key#*|}
    echo "SWEPM_TARGET_PACKAGE=$m/$p"
    set +e
    (cd "$m" && go test -p 1 -count=1 -json "$p")
    code=$?
    set -e
    [ "$code" = 0 ] || rc=1
done
echo "OMNIGRIL_EXIT_CODE=$rc"
exit "$rc"
