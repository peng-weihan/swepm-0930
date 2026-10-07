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

# Verify immutable test-domain helpers before reading candidate sources.
sha256sum -c /tests/bb_contract/checksums.sha256
export COREPACK_HOME=/root/.cache/node/corepack
export COREPACK_ENABLE_NETWORK=0
export NODE_OPTIONS=
export NODE_DISABLE_COMPILE_CACHE=1
export XDG_CACHE_HOME=/logs/verifier/cache/bb-xdg
mkdir -p "$XDG_CACHE_HOME"

# Run every independent obligation, even when another one fails, so the verifier
# retains the actual native test collection and the precise rejection reason.
set +e
/usr/local/bin/node /tests/bb_contract/check_contract.cjs > /logs/verifier/bb-contract.json 2> /logs/verifier/bb-contract.stderr
guard_exit=$?
cat /logs/verifier/bb-contract.json
cat /logs/verifier/bb-contract.stderr >&2
(
    cd /testbed/apps/app || exit 2
    /usr/local/bin/node /testbed/node_modules/.pnpm/typescript@5.9.3/node_modules/typescript/bin/tsc --noEmit
) > /logs/verifier/bb-typecheck.stdout 2> /logs/verifier/bb-typecheck.stderr
typecheck_exit=$?
cat /logs/verifier/bb-typecheck.stdout
cat /logs/verifier/bb-typecheck.stderr >&2
pnpm exec vitest run --config vitest.config.ts apps/app/src/components/sidebar/ProjectRow.test.tsx apps/app/src/components/ui/markdown-local-file-link.test.ts apps/app/src/components/ui/markdown-preview.test.tsx apps/app/src/views/thread-detail/ThreadDetailView.test.tsx --reporter=default --reporter=json --outputFile=/logs/verifier/bb-vitest.json
native_exit=$?
python3 -B /tests/bb_contract/check_collection.py /logs/verifier/bb-vitest.json > /logs/verifier/bb-collection.stdout 2> /logs/verifier/bb-collection.stderr
collection_exit=$?
cat /logs/verifier/bb-collection.stdout
cat /logs/verifier/bb-collection.stderr >&2
set -e
printf 'SWEPM_BB_EXITS guard=%s typecheck=%s native=%s collection=%s\n' "$guard_exit" "$typecheck_exit" "$native_exit" "$collection_exit"
exit_code=1
if [ "$guard_exit" = 0 ] && [ "$typecheck_exit" = 0 ] && [ "$native_exit" = 0 ] && [ "$collection_exit" = 0 ]; then
    exit_code=0
fi
# Mandatory exit protocol
printf 'OMNIGRIL_EXIT_CODE=%s\n' "$exit_code"
exit "$exit_code"
