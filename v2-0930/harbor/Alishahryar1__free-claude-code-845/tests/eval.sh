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
# (no pre-test commands needed)

# Run target tests
set +e
uv run pytest tests/api/test_dependencies.py tests/contracts/test_import_boundaries.py tests/providers/test_anthropic_messages.py tests/providers/test_anthropic_messages_429_retry.py tests/providers/test_cerebras.py tests/providers/test_codestral.py tests/providers/test_deepseek.py tests/providers/test_error_mapping.py tests/providers/test_fireworks.py tests/providers/test_gemini.py tests/providers/test_groq.py tests/providers/test_kimi.py tests/providers/test_llamacpp.py tests/providers/test_lmstudio.py tests/providers/test_mistral.py tests/providers/test_model_validation.py tests/providers/test_nvidia_nim.py tests/providers/test_ollama.py tests/providers/test_open_router.py tests/providers/test_provider_transport_logging.py tests/providers/test_registry.py tests/providers/test_streaming_errors.py tests/providers/test_subagent_interception.py tests/providers/test_wafer.py tests/providers/test_zai.py -v --tb=short
exit_code=$?
set -e

# Mandatory exit protocol
echo "OMNIGRIL_EXIT_CODE=${exit_code}"
exit $exit_code
