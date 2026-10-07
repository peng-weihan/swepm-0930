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

files=(internal/app/help_search_filter_test.go internal/app/portable_dirs_test.go internal/app/select_range_key_test.go internal/app/test_helpers_test.go internal/app/update_keys_test.go internal/app/view_status_test.go internal/app/whichkey_diff_memo_test.go internal/app/whichkey_fixes_test.go internal/app/whichkey_grouping_test.go internal/app/whichkey_help_alignment_test.go internal/app/whichkey_help_literal_test.go internal/app/whichkey_leader_test.go internal/app/whichkey_leaderkey_test.go internal/app/whichkey_legend_test.go internal/app/whichkey_pairs_test.go internal/app/whichkey_polish_test.go internal/app/whichkey_prefs_test.go internal/app/whichkey_rebind_test.go internal/app/whichkey_registry_extra_test.go internal/app/whichkey_registry_test.go internal/app/whichkey_render_test.go internal/app/whichkey_sort_test.go internal/app/whichkey_strip_test.go internal/app/whichkey_test.go internal/app/whichkey_viewers_phase2_test.go internal/app/whichkey_viewers_test.go internal/ui/config_goto_targets_test.go internal/ui/config_keybindings_modifiers_test.go internal/ui/config_keybindings_test.go internal/ui/config_whichkey_test.go internal/ui/config_wiring_test.go internal/ui/diff_cache_test.go internal/ui/diff_fold_test.go internal/ui/help_test.go internal/ui/keysymbols_test.go internal/ui/theme_test.go)
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
