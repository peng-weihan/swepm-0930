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

# Use the verified public tokenizer data already supplied with this verifier.
export TIKTOKEN_CACHE_DIR=/tests/runtime-fixtures/tiktoken
test -f "$TIKTOKEN_CACHE_DIR/9b5ad71b2ce5302211f9c61530b329a4922fc6a4"
printf '%s  %s\n' 223921b76ee99bde995b7ff738513eef100fb51d18c93597a113bcffe865b2a7 "$TIKTOKEN_CACHE_DIR/9b5ad71b2ce5302211f9c61530b329a4922fc6a4" | sha256sum -c -
# Run target tests
set +e
"$PYTHON" -m pytest tests/api/test_dependencies.py tests/contracts/test_import_boundaries.py tests/providers/test_anthropic_messages.py tests/providers/test_anthropic_messages_429_retry.py tests/providers/test_cerebras.py tests/providers/test_codestral.py tests/providers/test_deepseek.py tests/providers/test_error_mapping.py tests/providers/test_fireworks.py tests/providers/test_gemini.py tests/providers/test_groq.py tests/providers/test_kimi.py tests/providers/test_llamacpp.py tests/providers/test_lmstudio.py tests/providers/test_mistral.py tests/providers/test_model_validation.py tests/providers/test_nvidia_nim.py tests/providers/test_ollama.py tests/providers/test_open_router.py tests/providers/test_provider_transport_logging.py tests/providers/test_registry.py tests/providers/test_streaming_errors.py tests/providers/test_subagent_interception.py tests/providers/test_wafer.py tests/providers/test_zai.py -v --tb=short
exit_code=$?
set -e

# Mandatory exit protocol
echo "OMNIGRIL_EXIT_CODE=${exit_code}"
exit $exit_code
