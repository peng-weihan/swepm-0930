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

files=(agent/agent_test.go agent/hosting/a2ahosting/a2a_test.go agent/hosting/aguihosting/agui_test.go agent/internal/middleware/autocall/autocall_approval_test.go agent/internal/middleware/autocall/autocall_log_test.go agent/internal/middleware/autocall/autocall_test.go agent/internal/middleware/contextprovider/contextprovider_test.go agent/internal/middleware/middleware_test.go agent/internal/middleware/structuredoutput/structuredoutput_test.go agent/middleware/logger/logger_test.go agent/middleware/otel/otel_test.go agent/provider/a2aagent/a2a_test.go agent/provider/aguiagent/agui_test.go agent/provider/anthropicagent/agent_test.go agent/provider/geminiagent/agent_test.go agent/provider/openaichatagent/chat_test.go agent/provider/openairesponsesagent/responses_test.go)
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
