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
yarn test:unit --runTestsByPath src/__tests__/base-plugin.test.ts src/__tests__/envelope-leaks.test.ts src/__tests__/hover.test.ts src/__tests__/memory-leaks.test.ts src/__tests__/minimap.test.ts src/__tests__/record.test.ts src/__tests__/regions.test.ts src/__tests__/renderer.test.ts src/__tests__/scope.test.ts src/__tests__/spectrogram-destroy.test.ts src/__tests__/spectrogram-windowed-destroy.test.ts src/__tests__/timeline.test.ts src/__tests__/wavesurfer.test.ts src/__tests__/webaudio.test.ts src/reactive/__tests__/event-streams.test.ts src/reactive/__tests__/scroll-stream.test.ts src/reactive/__tests__/store.test.ts src/state/__tests__/wavesurfer-state.test.ts
exit_code=$?
set -e

# Mandatory exit protocol
echo "OMNIGRIL_EXIT_CODE=${exit_code}"
exit $exit_code
