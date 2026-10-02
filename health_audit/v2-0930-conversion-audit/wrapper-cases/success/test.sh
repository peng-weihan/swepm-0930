#!/bin/bash
set -euo pipefail
mkdir -p /volume/pt-coder/users/mlei/SWE-Cascade/swepmv2/health_audit/v2-0930-conversion-audit/wrapper-cases/success/logs

set +e
bash /volume/pt-coder/users/mlei/SWE-Cascade/swepmv2/health_audit/v2-0930-conversion-audit/wrapper-cases/success/eval.sh \
  > >(tee /volume/pt-coder/users/mlei/SWE-Cascade/swepmv2/health_audit/v2-0930-conversion-audit/wrapper-cases/success/logs/eval-stdout.txt) \
  2> >(tee /volume/pt-coder/users/mlei/SWE-Cascade/swepmv2/health_audit/v2-0930-conversion-audit/wrapper-cases/success/logs/eval-stderr.txt >&2)
raw_exit_code=$?
set -e

reported_exit_code="$(
  (grep -hoE 'OMNIGRIL_EXIT_CODE=[0-9]+' \
    /volume/pt-coder/users/mlei/SWE-Cascade/swepmv2/health_audit/v2-0930-conversion-audit/wrapper-cases/success/logs/eval-stdout.txt \
    /volume/pt-coder/users/mlei/SWE-Cascade/swepmv2/health_audit/v2-0930-conversion-audit/wrapper-cases/success/logs/eval-stderr.txt || true) | tail -n 1 | cut -d '=' -f 2
)"
effective_exit_code="${reported_exit_code:-${raw_exit_code}}"
printf '%s
' "${raw_exit_code}" > /volume/pt-coder/users/mlei/SWE-Cascade/swepmv2/health_audit/v2-0930-conversion-audit/wrapper-cases/success/logs/raw-eval-exit-code.txt
printf '%s
' "${effective_exit_code}" > /volume/pt-coder/users/mlei/SWE-Cascade/swepmv2/health_audit/v2-0930-conversion-audit/wrapper-cases/success/logs/eval-exit-code.txt
printf '%s
' "success" > /volume/pt-coder/users/mlei/SWE-Cascade/swepmv2/health_audit/v2-0930-conversion-audit/wrapper-cases/success/logs/instance-id.txt

if [ "${effective_exit_code}" -eq 0 ]; then
  echo 1 > /volume/pt-coder/users/mlei/SWE-Cascade/swepmv2/health_audit/v2-0930-conversion-audit/wrapper-cases/success/logs/reward.txt
else
  echo 0 > /volume/pt-coder/users/mlei/SWE-Cascade/swepmv2/health_audit/v2-0930-conversion-audit/wrapper-cases/success/logs/reward.txt
fi
exit "${effective_exit_code}"
