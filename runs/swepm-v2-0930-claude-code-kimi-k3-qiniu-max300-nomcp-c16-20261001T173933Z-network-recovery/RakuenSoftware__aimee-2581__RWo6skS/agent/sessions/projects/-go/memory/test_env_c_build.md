---
name: test-env-c-build
description: "How to build/run the aimee C unit tests in this sandbox (zstd symlink, git safe.directory)"
metadata: 
  node_type: memory
  type: project
  originSessionId: 142ce41f-e0dc-4b7a-8313-7214e2749b56
---

The aimee repo lives at `/testbed` (working dir is `/go`, an empty GOPATH). Go server is `/testbed/server-go` (`go test ./...`); C sources are `/testbed/src` (build via `make build/obj/tests/unit-test-<name>`; `TESTPREFIX = build/obj/tests`, no phony per-test targets).

C test links need two environment workarounds in this sandbox:
- `libzstd-dev` is absent, so `-lzstd` and `<zstd.h>` fail. For link-only failures, create `ln -sf /usr/lib/x86_64-linux-gnu/libzstd.so.1 /tmp/zstdlib/libzstd.so` and run make with `LIBRARY_PATH=/tmp/zstdlib`. Tests that compile `kb/kb_mdl.c` (e.g. `unit-test-agent`) still cannot build — that is a pre-existing env gap, not a code error.
- `unit-test-server-compute` spawns `git ls-files` with `HOME` repointed to a tmpdir, so a root-run binary hits "dubious ownership in repository at '/testbed'". Inject trust via `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*'` (works regardless of HOME).

**Why:** these blocked otherwise-passing tests and looked like code failures.
**How to apply:** use the env vars when building/running the affected C unit tests here.
