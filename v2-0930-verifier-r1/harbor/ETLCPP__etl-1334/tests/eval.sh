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
cmake -S . -B build -DBUILD_TESTS=ON -DNO_STL=OFF -DETL_USE_TYPE_TRAITS_BUILTINS=OFF -DETL_USER_DEFINED_TYPE_TRAITS=OFF -DETL_FORCE_TEST_CPP03_IMPLEMENTATION=OFF -DETL_CXX_STANDARD=17
cmake --build build -j 2

# Run target tests
set +e
./build/test/etl_tests -v
exit_code=$?
set -e

cpp17_exit=$exit_code
set +e
bash test/run_swepm_cpp11_constexpr.sh /testbed /logs/verifier/cpp11-contract
cpp11_exit=$?
set -e
echo "SWEPM_ETL_CPP17_EXIT_CODE=$cpp17_exit"
echo "SWEPM_ETL_CPP11_EXIT_CODE=$cpp11_exit"
if [ "$cpp17_exit" != 0 ] || [ "$cpp11_exit" != 0 ]; then
    exit_code=1
else
    exit_code=0
fi
# Mandatory exit protocol: joint result, after both suites.
echo "OMNIGRIL_EXIT_CODE=${exit_code}"
exit "$exit_code"
