#!/bin/bash
set -euo pipefail
mkdir -p /logs/verifier
echo 0 > /logs/verifier/reward.txt
echo verifier_setup > /logs/verifier/status.txt
trap 'code=$?; printf "%s\n" "$code" > /logs/verifier/wrapper-exit-code.txt' EXIT
cd /testbed
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
:
test -f /logs/agent/solution.patch
cp /logs/agent/solution.patch /logs/verifier/agent.patch
if [ -s /logs/agent/solution.patch ]; then
    export GIT_INDEX_FILE=/logs/verifier/replay.index
    git read-tree 12cdbc0da02e84a94a66ead292f34093356d92ea
    git apply --cached --check /logs/agent/solution.patch
    git apply --cached --whitespace=nowarn /logs/agent/solution.patch
    git diff --cached --no-renames --name-only --diff-filter=D -z 12cdbc0da02e84a94a66ead292f34093356d92ea | while IFS= read -r -d '' f; do rm -f -- "$f"; done
    git diff --cached --no-renames --name-only --diff-filter=ACMRT -z 12cdbc0da02e84a94a66ead292f34093356d92ea | git checkout-index --force -z --stdin
    unset GIT_INDEX_FILE
fi
echo patch_replayed > /logs/verifier/status.txt
# Remove only reviewed test files, never production directories or source.
while IFS= read -r f; do
    [ -n "$f" ] || continue
    d=$(dirname "$f")
    while [ "$d" != . ]; do
        [ ! -L "$d" ] || { echo "UNSAFE_TEST_PARENT=$d"; exit 2; }
        d=$(dirname "$d")
    done
    [ ! -d "$f" ] || { echo "TEST_PATH_IS_DIRECTORY=$f"; exit 2; }
    rm -f -- "$f"
done < /tests/install-paths.txt
tar -xf /tests/tests.tar -C /testbed
sha256sum -c /tests/checksums.sha256 > /logs/verifier/test-installation.txt
while IFS= read -r f; do
    [ -z "$f" ] || { [ ! -e "$f" ] && [ ! -L "$f" ]; }
done < /tests/deleted-tests.txt
echo tests_installed > /logs/verifier/status.txt
touch /logs/verifier/test-start.marker
set +e
bash /tests/eval.sh > /logs/verifier/eval-stdout.txt 2> /logs/verifier/eval-stderr.txt
raw=$?
set -e
cat /logs/verifier/eval-stdout.txt
cat /logs/verifier/eval-stderr.txt >&2
printf '%s
' "$raw" > /logs/verifier/raw-eval-exit-code.txt
cat /logs/verifier/eval-stdout.txt /logs/verifier/eval-stderr.txt > /logs/verifier/eval-combined.txt
log=/logs/verifier/eval-combined.txt
# Require the canonical suite and both real C++11 profile runs.
if grep -qE '^Success: [1-9][0-9]* tests passed\.$' "$log" && \
   grep -qE '^CPP11_CONSTEXPR_PROFILE checked=1 runtime_checks=[1-9][0-9]* failures=0$' "$log" && \
   grep -qE '^CPP11_CONSTEXPR_PROFILE checked=0 runtime_checks=[1-9][0-9]* failures=0$' "$log" && \
   grep -qx 'CPP11_CONSTEXPR_CONTRACT_PASSED checked_and_unchecked' "$log"; then
    echo 'SWEPM_ETL_EXECUTION_EVIDENCE: All tests passed' >> "$log"
fi

reported=$( (grep -hE '^OMNIGRIL_EXIT_CODE=[0-9]+$' "$log" || true) | tail -1 | cut -d= -f2)
code=$raw
if [ "$raw" != 0 ] || [ "${reported:-missing}" != 0 ]; then
    echo test_or_build_failure > /logs/verifier/status.txt
    code=1
elif grep -qiE '(^|[^a-z])(No tests (found|defined|were found)|collected 0 items|OMNIGRIL_TEST_PATCH_APPLY_FAILED=1)' "$log"; then
    echo no_tests_or_patch_failure > /logs/verifier/status.txt
    code=2
elif ! grep -qE '(SWEPM_DUCKDB_TESTS_EXECUTED=1|SWEPM_JUNIT_EXECUTED=[1-9]|SWEPM_C_TEST_PASS=|[1-9][0-9]* passed|[1-9][0-9]* pass$|Tests run: [1-9]|out of [1-9][0-9]*|Ok:[[:space:]]+[1-9]|# pass [1-9]|"Action":"pass".*"Test":|All tests passed)' "$log"; then
    echo missing_execution_evidence > /logs/verifier/status.txt
    code=2
else
    echo passed > /logs/verifier/status.txt
    echo 1 > /logs/verifier/reward.txt
fi
printf '%s
' "$code" > /logs/verifier/eval-exit-code.txt
exit "$code"
