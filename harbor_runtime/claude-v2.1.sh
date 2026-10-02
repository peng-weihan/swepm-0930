#!/bin/bash
set -euo pipefail

ACTION="${1:-dry-run}"
if [[ $# -gt 0 ]]; then shift; fi

HARBOR_HOST="${SWEPMV2_HARBOR_HOST:-10.161.41.9}"
SSH_KEY="${SWEPMV2_SSH_KEY:-/volume/pt-coder/users/mlei/.ssh/id_ed25519}"
RUNTIME_ROOT="${SWEPMV2_HARBOR_ROOT:-/data/swepmv2-harbor-runtime}"
N_CONCURRENT="${N_CONCURRENT:-4}"
MAX_TURNS="${MAX_TURNS:-100}"
EFFORT="${EFFORT:-high}"
CLAUDE_CODE_VERSION="${CLAUDE_CODE_VERSION:-2.1.140}"
EXCLUDE_BLOCKED="${EXCLUDE_BLOCKED:-0}"
MODEL="${MODEL:-}"
MODEL_ARG="${MODEL:-__FROM_ENV__}"

case "$ACTION" in
  dry-run|install-check|start) ;;
  resume)
    if [[ $# -ne 1 ]]; then
      echo "usage: $0 resume /data/swepmv2-harbor-runtime/jobs/JOB_NAME" >&2
      exit 2
    fi
    printf -v resume_command '%q ' sudo -u ray -H \
      "$RUNTIME_ROOT/bin/harbor" job resume --job-path "$1"
    exec ssh -T -i "$SSH_KEY" -o BatchMode=yes "root@$HARBOR_HOST" "$resume_command"
    ;;
  *) echo "usage: $0 {dry-run|install-check|start|resume JOB_PATH}" >&2; exit 2 ;;
esac

ssh -T -i "$SSH_KEY" -o BatchMode=yes "root@$HARBOR_HOST" bash -s -- \
  "$ACTION" "$RUNTIME_ROOT" "$N_CONCURRENT" "$MAX_TURNS" "$EFFORT" \
  "$CLAUDE_CODE_VERSION" "$EXCLUDE_BLOCKED" "$MODEL_ARG" <<'REMOTE'
set -euo pipefail
action="$1"; runtime_root="$2"; n_concurrent="$3"; max_turns="$4"
effort="$5"; claude_version="$6"; exclude_blocked="$7"; model_override="$8"
if [[ "$model_override" == "__FROM_ENV__" ]]; then model_override=""; fi
credential_file="$runtime_root/.env"
tasks="$runtime_root/datasets/v2.1/tasks"
jobs="$runtime_root/jobs"

if [[ ! -r "$credential_file" ]]; then
  echo "missing credential file: $credential_file" >&2
  exit 1
fi
set -a
# shellcheck disable=SC1090
source "$credential_file"
set +a
model="${model_override:-${CLAUDE_CODE_MODEL:-}}"
if [[ -z "$model" ]]; then
  echo "MODEL or CLAUDE_CODE_MODEL must be set" >&2
  exit 1
fi

args=(run --path "$tasks" --agent claude-code --model "$model"
  --agent-kwarg "version=$claude_version"
  --agent-kwarg "max_turns=$max_turns"
  --agent-kwarg "reasoning_effort=$effort"
  --env-file "$credential_file" --jobs-dir "$jobs" --n-attempts 1
  --n-concurrent "$n_concurrent" --max-retries 1 --yes)

if [[ "$exclude_blocked" == "1" ]]; then
  args+=(--exclude-task-name xremap__xremap-892
    --exclude-task-name DeepLabCut__DeepLabCut-3303)
fi

case "$action" in
  dry-run) args+=(--dry-run --job-name swepm-v2.1-claude-code-dry-run) ;;
  install-check)
    args=(run --path "$tasks/GizClaw__flowcraft-84" --agent claude-code
      --model "$model" --agent-kwarg "version=$claude_version"
      --env-file "$credential_file" --jobs-dir "$jobs" --install-only
      --job-name swepm-v2.1-claude-code-install-check --yes)
    ;;
  start)
    job_name="swepm-v2.1-claude-code-$(date -u +%Y%m%dT%H%M%SZ)"
    args+=(--job-name "$job_name")
    echo "job_name=$job_name"
    echo "model=$model tasks=$([[ "$exclude_blocked" == "1" ]] && echo 80 || echo 82) concurrency=$n_concurrent"
    ;;
esac
exec sudo -u ray -H "$runtime_root/bin/harbor" "${args[@]}"
REMOTE
