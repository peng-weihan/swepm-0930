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
uv run $PYTHON -m pytest tests/test_backends.py tests/test_channel_comprehensive.py tests/test_channel_debug.py tests/test_channel_sends.py tests/test_cli_async_runtime.py tests/test_cli_interrupts.py tests/test_cli_serve.py tests/test_code_interpreter_middleware.py tests/test_event_loop.py tests/test_mcp_client.py tests/test_model_fallback.py tests/test_onboard_async_runtime.py tests/test_runtime.py tests/test_serve_agent_holder.py tests/test_stream_cancel.py tests/test_tool_selector_middleware.py tests/test_tui_banner_position.py tests/test_ui_runtime.py -x -v --tb=short --timeout=30
exit_code=$?
set -e

# Mandatory exit protocol
echo "OMNIGRIL_EXIT_CODE=${exit_code}"
exit $exit_code
