#!/bin/bash
set -uo pipefail
cd /testbed

# Preserve runtime paths captured by EnvironmentExecutionAgent, and add common
# tool locations that docker commit may not expose through shell startup files.
for extra in /usr/local/go/bin /go/bin "$HOME/go/bin" "$HOME/.cargo/bin" /usr/local/cargo/bin /opt/conda/bin "$HOME/.local/bin" /opt/poetry/bin /opt/venv/bin /testbed/.venv/bin; do
    if [ -d "$extra" ]; then
        export PATH="$extra:$PATH"
    fi
done

resolve_python() {
    if [ -n "${SPECBUILD_PYTHON:-}" ] && [ -x "${SPECBUILD_PYTHON}" ]; then
        echo "${SPECBUILD_PYTHON}"
        return
    fi
    for candidate in /testbed/.venv/bin/python /opt/venv/bin/python /opt/conda/bin/python python3 python /usr/local/bin/python /usr/bin/python3; do
        if command -v "$candidate" >/dev/null 2>&1 || [ -x "$candidate" ]; then
            if "$candidate" -c "import pytest" >/dev/null 2>&1; then
                echo "$candidate"
                return
            fi
        fi
    done
    for candidate in /testbed/.venv/bin/python /opt/venv/bin/python /opt/conda/bin/python python3 python /usr/local/bin/python /usr/bin/python3; do
        if command -v "$candidate" >/dev/null 2>&1 || [ -x "$candidate" ]; then
            echo "$candidate"
            return
        fi
    done
    echo python3
}

PYTHON="$(resolve_python)"
PIP="${SPECBUILD_PIP:-$PYTHON -m pip}"
POETRY="${SPECBUILD_POETRY:-poetry}"
echo "SPECBUILD_RESOLVED_PYTHON=${PYTHON}"

# Apply test patch
git apply -p1 -v /tmp/test.patch || patch --batch --fuzz=5 -p1 -i /tmp/test.patch

# Pre-test commands
cmake -S . -B build -G Ninja -DWITH_UI=OFF -DAIMEE_THIN_CLIENT=OFF
cmake --build build -j$(nproc)

# Run target tests
set +e
ctest --test-dir build --output-on-failure -R '(unit-test-agent|unit-test-agent-http|unit-test-agent-ir-parse|unit-test-aimee-ir-rescue|unit-test-attention-guard|unit-test-cmd-delegate|unit-test-config|unit-test-context-reduce|unit-test-coord-closet|unit-test-coord-jobs|unit-test-delegate-driver|unit-test-delegate-economics|unit-test-delegate-handoff|unit-test-delegate-patch-coordinator|unit-test-delegate-role|unit-test-fold-recall|unit-test-git-pr-ci-grade|unit-test-git-pr-stage|unit-test-log|unit-test-server-compute|unit-test-session-compact)' && (cd server-go && CGO_ENABLED=0 go test ./modules/delegates ./modules/git ./modules/workspace ./cmd/aimee-module)
exit_code=$?
set -e

# Mandatory exit protocol
echo "OMNIGRIL_EXIT_CODE=${exit_code}"
exit $exit_code
