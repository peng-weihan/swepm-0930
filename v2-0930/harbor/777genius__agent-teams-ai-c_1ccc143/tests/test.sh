#!/bin/bash
set -euo pipefail
mkdir -p /logs/verifier

set +e
bash /tests/eval.sh \
  > >(tee /logs/verifier/eval-stdout.txt) \
  2> >(tee /logs/verifier/eval-stderr.txt >&2)
raw_exit_code=$?
set -e

reported_exit_code="$(
  (grep -hoE 'OMNIGRIL_EXIT_CODE=[0-9]+' \
    /logs/verifier/eval-stdout.txt \
    /logs/verifier/eval-stderr.txt || true) | tail -n 1 | cut -d '=' -f 2
)"
effective_exit_code="${reported_exit_code:-${raw_exit_code}}"
printf '%s
' "${raw_exit_code}" > /logs/verifier/raw-eval-exit-code.txt
printf '%s
' "${effective_exit_code}" > /logs/verifier/eval-exit-code.txt
printf '%s
' "777genius__agent-teams-ai-c_1ccc143" > /logs/verifier/instance-id.txt

if [ "${effective_exit_code}" -eq 0 ]; then
  echo 1 > /logs/verifier/reward.txt
else
  echo 0 > /logs/verifier/reward.txt
fi
exit "${effective_exit_code}"
