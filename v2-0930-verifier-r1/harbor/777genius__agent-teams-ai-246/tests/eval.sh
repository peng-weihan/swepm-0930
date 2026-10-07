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
pnpm --filter agent-teams-mcp build

# Run target tests
# Four private-helper cases are retained in the installed archive for provenance.
# Their unpromised internal module is excluded from scoring; see the reviewed contract adjudication.
# Helpers are installed only after agent patch capture, inside the separate verifier.
# Fresh trial logs are required; never accept reports left by an earlier invocation.
for report in root-vitest.json root-runtime-errors.json mcp-vitest.json mcp-runtime-errors.json; do
    if [ -e "/logs/verifier/$report" ]; then
        echo "Existing verifier report must not be reused: $report" >&2
        exit 97
    fi
done
root_helper="$(mktemp -d /testbed/.swepm-verifier-agentteams246.XXXXXXXX)"
mcp_helper="$(mktemp -d /testbed/mcp-server/.swepm-verifier-agentteams246.XXXXXXXX)"
cp /tests/agentteams_runtime_reporter.mjs "$root_helper/runtime_reporter.mjs"
cp /tests/agentteams_runtime_reporter.mjs "$mcp_helper/runtime_reporter.mjs"
root_reporter="./${root_helper##*/}/runtime_reporter.mjs"
mcp_reporter="./${mcp_helper##*/}/runtime_reporter.mjs"
set +e
SWEPM_RUNTIME_REPORT_PATH=/logs/verifier/root-runtime-errors.json pnpm exec vitest run --maxWorkers=1 src/main/services/team/__tests__/CrossTeamOutbox.test.ts src/main/services/team/__tests__/CrossTeamService.runtimeDedupe.test.ts src/main/services/team/opencode/delivery/__tests__/RuntimeDeliveryJournal.test.ts src/main/services/team/opencode/delivery/__tests__/RuntimeDeliveryService.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningLaunchIdentity.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningLiveRuntimeMetadataPortsFactory.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningMemberLifecycleServiceUseCases.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningMemberLifecycleStaleRun.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningPrepareCoordinator.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningPreparePrimaryOwnedMemberRestartRuntimeUseCase.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningRuntimeSnapshot.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningServiceComposition.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningServiceFacadeGuard.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningServiceMemberLifecycleHostPortGroups.test.ts src/main/services/team/runtime-control/__tests__/OpenCodeRuntimeControlApi.test.ts src/main/services/team/runtime-projection/__tests__/RuntimeProjection.test.ts test/main/http/teamRouteParsers.test.ts test/main/http/teamRuntimeControlValidation.test.ts test/main/http/teams.test.ts test/main/ipc/teams.test.ts test/main/services/team/RuntimeDeliveryService.test.ts test/main/services/team/TeamDataService.test.ts test/main/services/team/TeamProvisioningService.test.ts test/main/services/team/TeamProvisioningServiceRelay.test.ts test/main/services/team/provisioningHarness/TeamProvisioningHarnessBuilder.test.ts test/main/services/team/provisioningHarness/servicePrivateHarness.test.ts test/renderer/store/teamSlice.test.ts --passWithNoTests=false --dangerouslyIgnoreUnhandledErrors=false --reporter=default --reporter=json --reporter="$root_reporter" --outputFile=/logs/verifier/root-vitest.json
root_exit=$?
"$PYTHON" /tests/check_agentteams_collection.py /logs/verifier/root-vitest.json --runtime-report /logs/verifier/root-runtime-errors.json --project-root /testbed src/main/services/team/__tests__/CrossTeamOutbox.test.ts src/main/services/team/__tests__/CrossTeamService.runtimeDedupe.test.ts src/main/services/team/opencode/delivery/__tests__/RuntimeDeliveryJournal.test.ts src/main/services/team/opencode/delivery/__tests__/RuntimeDeliveryService.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningLaunchIdentity.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningLiveRuntimeMetadataPortsFactory.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningMemberLifecycleServiceUseCases.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningMemberLifecycleStaleRun.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningPrepareCoordinator.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningPreparePrimaryOwnedMemberRestartRuntimeUseCase.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningRuntimeSnapshot.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningServiceComposition.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningServiceFacadeGuard.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningServiceMemberLifecycleHostPortGroups.test.ts src/main/services/team/runtime-control/__tests__/OpenCodeRuntimeControlApi.test.ts src/main/services/team/runtime-projection/__tests__/RuntimeProjection.test.ts test/main/http/teamRouteParsers.test.ts test/main/http/teamRuntimeControlValidation.test.ts test/main/http/teams.test.ts test/main/ipc/teams.test.ts test/main/services/team/RuntimeDeliveryService.test.ts test/main/services/team/TeamDataService.test.ts test/main/services/team/TeamProvisioningService.test.ts test/main/services/team/TeamProvisioningServiceRelay.test.ts test/main/services/team/provisioningHarness/TeamProvisioningHarnessBuilder.test.ts test/main/services/team/provisioningHarness/servicePrivateHarness.test.ts test/renderer/store/teamSlice.test.ts > /logs/verifier/root-collection.json
root_collection_exit=$?
(
    cd /testbed/mcp-server || exit 98
    # Use the existing package binary: no install or package resolution.
    test -x ./node_modules/.bin/vitest || exit 98
    SWEPM_RUNTIME_REPORT_PATH=/logs/verifier/mcp-runtime-errors.json ./node_modules/.bin/vitest run --config vitest.config.ts --maxWorkers=1 --passWithNoTests=false --dangerouslyIgnoreUnhandledErrors=false --reporter=default --reporter=json --reporter="$mcp_reporter" --outputFile=/logs/verifier/mcp-vitest.json test/tools.test.ts
)
mcp_exit=$?
"$PYTHON" /tests/check_agentteams_collection.py /logs/verifier/mcp-vitest.json --runtime-report /logs/verifier/mcp-runtime-errors.json --project-root /testbed/mcp-server test/tools.test.ts > /logs/verifier/mcp-collection.json
mcp_collection_exit=$?
set -e
printf 'ROOT_VITEST_EXIT_CODE=%s\nROOT_COLLECTION_EXIT_CODE=%s\nMCP_VITEST_EXIT_CODE=%s\nMCP_COLLECTION_EXIT_CODE=%s\n' "$root_exit" "$root_collection_exit" "$mcp_exit" "$mcp_collection_exit"
exit_code=0
if [ "$root_exit" -ne 0 ] || [ "$root_collection_exit" -ne 0 ] || [ "$mcp_exit" -ne 0 ] || [ "$mcp_collection_exit" -ne 0 ]; then
    exit_code=1
fi

# Mandatory exit protocol
echo "OMNIGRIL_EXIT_CODE=${exit_code}"
exit $exit_code
