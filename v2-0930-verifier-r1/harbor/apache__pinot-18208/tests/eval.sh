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
./mvnw -B -ntp -DskipTests -DskipITs -Dskip.integration.tests=true -Dskip.unit.tests=true -pl pinot-spi,pinot-common,pinot-segment-local,pinot-core,pinot-broker,pinot-udf-test -am test-compile

# Run target tests
set +e
./mvnw -B -ntp test -pl pinot-common,pinot-segment-local,pinot-core,pinot-broker,pinot-udf-test -am -DskipITs -Dskip.integration.tests=true -Dtest=QueryValidationTest,InbuiltFunctionEvaluatorTest,ArithmeticFunctionsTest,ArrayFunctionsTest,BitFunctionsTest,DateTimeFunctionsTest,GroovyFunctionEvaluatorTest,GroovyStaticAnalyzerConfigTest,JsonFunctionsTest,LogicalFunctionsTest,ObjectFunctionsTest,VectorFunctionsTest,FunctionPackageCompatibilityTest,PartialUpsertHandlerTest -Dsurefire.failIfNoSpecifiedTests=false -DfailIfNoTests=false
exit_code=$?
set -e

# Mandatory exit protocol
echo "OMNIGRIL_EXIT_CODE=${exit_code}"
exit $exit_code
