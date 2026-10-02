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
bun test src/backend/local-backend.test.ts src/backend/pi-model-factory.test.ts src/cli/app/command-routing.test.ts src/cli/approval-classification.test.ts src/cli/args.test.ts src/cli/mods/command-runtime.test.ts src/cli/mods/local-mod-loader.test.ts src/cli/reload-command.test.ts src/headless-mod-lifecycle.test.ts src/mods/conversation-handle.test.ts src/mods/disable.test.ts src/mods/disabled-mod-adapter.test.ts src/mods/mod-adapter.test.ts src/mods/mod-diagnostics-file.test.ts src/mods/mod-diagnostics.test.ts src/mods/mod-engine.test.ts src/mods/paths.test.ts src/providers/local-pi-provider-catalog.test.ts src/tools/tool-execution-context.test.ts src/websocket/listen-client-protocol.test.ts src/websocket/listener/mod-adapter.test.ts --timeout 15000
exit_code=$?
set -e

# Mandatory exit protocol
echo "OMNIGRIL_EXIT_CODE=${exit_code}"
exit $exit_code
