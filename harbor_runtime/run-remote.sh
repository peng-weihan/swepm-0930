#!/bin/bash
set -euo pipefail

HARBOR_HOST="${SWEPMV2_HARBOR_HOST:-10.161.41.9}"
SSH_KEY="${SWEPMV2_SSH_KEY:-/volume/pt-coder/users/mlei/.ssh/id_ed25519}"
REMOTE_HARBOR="${SWEPMV2_REMOTE_HARBOR:-/data/swepmv2-harbor-runtime/bin/harbor}"

printf -v remote_command '%q ' sudo -u ray -H "$REMOTE_HARBOR" "$@"
exec ssh -t -i "$SSH_KEY" -o BatchMode=yes "$HARBOR_HOST" "$remote_command"
