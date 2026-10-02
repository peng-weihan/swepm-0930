# Claude Code evaluation for SWEPM v2.1

The launcher uses the independent Harbor 0.23.0 runtime on `10.161.41.9` and
runs as `ray`. Claude Code is pinned to `2.1.140`. Jobs, caches, and temporary
files stay under `/data/swepmv2-harbor-runtime`; Docker uses `/data/docker`.

The default run contains all 82 tasks. Two tasks have known Oracle caveats:

- `xremap__xremap-892`: the base passes, but the gold patch and bundled tests
  disagree about the `EventHandler` API.
- `DeepLabCut__DeepLabCut-3303`: Oracle needs external GitHub test data and
  failed because DNS was unavailable in the verifier.

Validate without model calls:

```bash
./harbor_runtime/claude-v2.1.sh dry-run
```

Check installation in one image, without running the model or verifier:

```bash
./harbor_runtime/claude-v2.1.sh install-check
```

Start the 82-task experiment (concurrency 4, pass@1, 100 turns, high effort):

```bash
./harbor_runtime/claude-v2.1.sh start
```

Override settings through environment variables:

```bash
N_CONCURRENT=8 MAX_TURNS=200 EFFORT=high MODEL=claude-opus-4-8-ppio \
  ./harbor_runtime/claude-v2.1.sh start
```

Set `EXCLUDE_BLOCKED=1` to omit the two caveat tasks and run 80. Resume an interrupted job with:

```bash
./harbor_runtime/claude-v2.1.sh resume /data/swepmv2-harbor-runtime/jobs/JOB_NAME
```

The independent credential copy is at `/data/swepmv2-harbor-runtime/.env`,
mode `0600`, owned by `ray`. The launcher uses `CLAUDE_CODE_MODEL` from it
unless `MODEL` is supplied.
