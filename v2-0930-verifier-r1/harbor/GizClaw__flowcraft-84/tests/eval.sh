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

files=(sdk/engine/board_test.go sdk/errdefs/http_test.go sdk/graph/compile_test.go sdk/graph/node/knowledgenode/knowledgenode_test.go sdk/graph/node/llmnode/config_test.go sdk/graph/node/llmnode/exec_test.go sdk/graph/node/llmnode/host_test.go sdk/graph/runner/internal/executor/checkpoint_test.go sdk/graph/runner/internal/executor/executor_test.go sdk/graph/runner/internal/executor/retry_test.go sdk/graph/runner/runner_test.go sdk/history/archive_test.go sdk/history/compact_test.go sdk/history/compactor_factory_test.go sdk/history/compactor_test.go sdk/history/coordinator_test.go sdk/history/store_test.go sdk/llm/factory_test.go sdk/llm/resolver_test.go sdk/model/message_test.go sdk/retrieval/pipeline/pipeline_test.go sdkx/tool/history/tools_test.go sdkx/tool/kanban/tools_test.go)
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
