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

files=(api/queries_pr_test.go internal/safeurl/safeurl_test.go internal/skills/discovery/discovery_test.go pkg/cmd/attestation/api/client_test.go pkg/cmd/codespace/create_test.go pkg/cmd/codespace/list_test.go pkg/cmd/copilot/copilot_test.go pkg/cmd/gist/shared/shared_test.go pkg/cmd/pr/close/close_test.go pkg/cmd/pr/merge/merge_test.go pkg/cmd/release/delete/delete_test.go pkg/cmd/release/shared/fetch_test.go pkg/cmd/release/shared/upload_test.go pkg/cmd/repo/read-file/read_file_test.go pkg/cmd/repo/sync/sync_test.go pkg/cmd/run/download/download_test.go pkg/cmd/run/download/http_test.go pkg/cmd/secret/list/list_test.go pkg/cmd/skills/install/install_test.go pkg/cmd/skills/preview/preview_test.go pkg/cmd/skills/update/update_test.go pkg/cmd/variable/list/list_test.go pkg/cmd/workflow/run/run_test.go pkg/cmd/workflow/view/view_test.go)
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
