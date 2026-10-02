# SWEPM v2.1 Harbor runtime

This directory records the independently maintained Harbor runtime used for
SWEPM v2.1. The runtime is pinned to Harbor 0.23.0 and deployed on
`10.161.41.9` under `/data/swepmv2-harbor-runtime`.

The 82 converted tasks live locally in `../v2.1/harbor` and on the run host in
`/data/swepmv2-harbor-runtime/datasets/v2.1/tasks`.

Install or repair the pinned remote runtime:

```bash
./harbor_runtime/install-remote.sh
```

Check the remote version:

```bash
./harbor_runtime/run-remote.sh --version
```

Run one task:

```bash
./harbor_runtime/run-remote.sh run \
  -p /data/swepmv2-harbor-runtime/datasets/v2.1/tasks/GizClaw__flowcraft-84 \
  -a oracle \
  -o /data/swepmv2-harbor-runtime/jobs \
  -y
```

The wrapper keeps Harbor cache and temporary files under the runtime root.
Docker image layers are managed by the host Docker daemon under `/data/docker`.

For the prepared Claude Code workflow, see `CLAUDE_CODE.md`.
