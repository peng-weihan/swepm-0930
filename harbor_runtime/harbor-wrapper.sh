#!/bin/bash
set -euo pipefail

RUNTIME_ROOT="${SWEPMV2_HARBOR_ROOT:-/data/swepmv2-harbor-runtime}"
export XDG_CACHE_HOME="$RUNTIME_ROOT/cache"
export PIP_CACHE_DIR="$RUNTIME_ROOT/cache/pip"
export TMPDIR="$RUNTIME_ROOT/tmp"

exec "$RUNTIME_ROOT/venv/bin/harbor" "$@"
