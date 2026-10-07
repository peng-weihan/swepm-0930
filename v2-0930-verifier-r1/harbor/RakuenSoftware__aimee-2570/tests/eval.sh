#!/bin/bash
set -euo pipefail
cd /testbed
export PATH="/usr/local/go/bin:/go/bin:$PATH"
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
mkdir -p /logs/verifier/aimee-obj /logs/verifier/aimee-bin
# Tests switch users; the image's checkout ownership must remain trusted.
git config --system --add safe.directory /testbed
mkdir -p /logs/verifier/native-libs
if [ -f /lib/x86_64-linux-gnu/libzstd.so.1 ]; then
    ln -sf /lib/x86_64-linux-gnu/libzstd.so.1 /logs/verifier/native-libs/libzstd.so
    export LIBRARY_PATH="/logs/verifier/native-libs${LIBRARY_PATH:+:$LIBRARY_PATH}"
fi
targets=(unit-test-server-compute)
bins=()
for t in "${targets[@]}"; do bins+=("/logs/verifier/aimee-bin/$t"); done
make -C src -j2 OBJDIR=/logs/verifier/aimee-obj TESTPREFIX=/logs/verifier/aimee-bin "${bins[@]}"
rc=0
set +e
for binary in "${bins[@]}"; do
    echo "SWEPM_C_TEST_START=$binary"
    "$binary"
    code=$?
    if [ "$code" = 0 ]; then echo "SWEPM_C_TEST_PASS=$binary"; else rc=1; fi
done
(cd server-go && CGO_ENABLED=0 go test -p 1 -count=1 -json ./cmd/aimee-module ./modules/delegates)
[ "$?" = 0 ] || rc=1
echo "OMNIGRIL_EXIT_CODE=$rc"
exit "$rc"
