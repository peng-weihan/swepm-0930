#!/bin/bash
set -euo pipefail
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
# Authoritative test assets installed by test.sh.

# Pre-test commands
# (no pre-test commands needed)

# Run target tests
set +e
pnpm exec vitest run --project main --project renderer --project shared packages/shared/data/api/schemas/__tests__/prompts.test.ts packages/shared/data/types/__tests__/prompt.test.ts src/main/data/api/handlers/__tests__/prompts.test.ts src/main/data/migration/v2/core/__tests__/MigrationEngine.test.ts src/main/data/migration/v2/migrators/__tests__/MigratorResetContract.test.ts src/main/data/migration/v2/migrators/__tests__/PromptMigrator.test.ts src/main/data/services/__tests__/PromptService.test.ts src/renderer/src/pages/home/Inputbar/components/__tests__/promptVariableNavigation.test.ts src/renderer/src/pages/home/Inputbar/tools/components/__tests__/quickPhraseInsert.test.ts src/renderer/src/pages/settings/__tests__/PromptSettings.test.tsx
exit_code=$?
set -e

# Mandatory exit protocol
echo "OMNIGRIL_EXIT_CODE=${exit_code}"
exit $exit_code
