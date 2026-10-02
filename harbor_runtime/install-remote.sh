#!/bin/bash
set -euo pipefail

HARBOR_HOST="${SWEPMV2_HARBOR_HOST:-10.161.41.9}"
SSH_KEY="${SWEPMV2_SSH_KEY:-/volume/pt-coder/users/mlei/.ssh/id_ed25519}"
RUNTIME_ROOT="${SWEPMV2_HARBOR_ROOT:-/data/swepmv2-harbor-runtime}"
PYTHON_BIN="${SWEPMV2_PYTHON_BIN:-/home/mlei/.local/share/uv/python/cpython-3.13.8-linux-x86_64-gnu/bin/python3.13}"
HARBOR_VERSION="0.23.0"

ssh -i "$SSH_KEY" -o BatchMode=yes "root@$HARBOR_HOST" bash -s -- \
  "$RUNTIME_ROOT" "$PYTHON_BIN" "$HARBOR_VERSION" <<'REMOTE'
set -euo pipefail
runtime_root="$1"
python_bin="$2"
harbor_version="$3"

mkdir -p \
  "$runtime_root/cache/pip" \
  "$runtime_root/tmp" \
  "$runtime_root/jobs" \
  "$runtime_root/datasets/v2.1"
chown -R ray "$runtime_root"

if sudo -u ray -H "$runtime_root/venv/bin/harbor" --version 2>/dev/null \
  | grep -qx "$harbor_version"; then
  exit 0
fi

sudo -u ray -H env TMPDIR="$runtime_root/tmp" \
  "$python_bin" -m venv "$runtime_root/venv"
sudo -u ray -H env \
  TMPDIR="$runtime_root/tmp" \
  PIP_CACHE_DIR="$runtime_root/cache/pip" \
  XDG_CACHE_HOME="$runtime_root/cache" \
  "$runtime_root/venv/bin/python" -m pip install "harbor==$harbor_version"
REMOTE

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scp -i "$SSH_KEY" -o BatchMode=yes \
  "$script_dir/harbor-wrapper.sh" \
  "root@$HARBOR_HOST:$RUNTIME_ROOT/bin/harbor"
ssh -i "$SSH_KEY" -o BatchMode=yes "root@$HARBOR_HOST" \
  "chmod 755 '$RUNTIME_ROOT/bin/harbor' && chown ray '$RUNTIME_ROOT/bin/harbor'"
