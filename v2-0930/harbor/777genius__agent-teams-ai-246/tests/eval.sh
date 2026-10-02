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
pnpm --filter agent-teams-mcp build

# Run target tests
set +e
pnpm exec vitest run --maxWorkers=1 mcp-server/test/tools.test.ts src/main/services/team/__tests__/CrossTeamOutbox.test.ts src/main/services/team/__tests__/CrossTeamService.runtimeDedupe.test.ts src/main/services/team/opencode/delivery/__tests__/RuntimeDeliveryJournal.test.ts src/main/services/team/opencode/delivery/__tests__/RuntimeDeliveryService.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningHasOpenCodeMemberRuntimeEvidenceForControlledRelaunchUseCase.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningLaunchIdentity.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningLiveRuntimeMetadataPortsFactory.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningMemberLifecycleServiceUseCases.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningMemberLifecycleStaleRun.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningPrepareCoordinator.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningPreparePrimaryOwnedMemberRestartRuntimeUseCase.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningRuntimeSnapshot.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningServiceComposition.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningServiceFacadeGuard.test.ts src/main/services/team/provisioning/__tests__/TeamProvisioningServiceMemberLifecycleHostPortGroups.test.ts src/main/services/team/runtime-control/__tests__/OpenCodeRuntimeControlApi.test.ts src/main/services/team/runtime-projection/__tests__/RuntimeProjection.test.ts test/main/http/teamRouteParsers.test.ts test/main/http/teamRuntimeControlValidation.test.ts test/main/http/teams.test.ts test/main/ipc/teams.test.ts test/main/services/team/RuntimeDeliveryService.test.ts test/main/services/team/TeamDataService.test.ts test/main/services/team/TeamProvisioningService.test.ts test/main/services/team/TeamProvisioningServiceRelay.test.ts test/main/services/team/provisioningHarness/TeamProvisioningHarnessBuilder.test.ts test/main/services/team/provisioningHarness/servicePrivateHarness.test.ts test/renderer/store/teamSlice.test.ts
exit_code=$?
set -e

# Mandatory exit protocol
echo "OMNIGRIL_EXIT_CODE=${exit_code}"
exit $exit_code
