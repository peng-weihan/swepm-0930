# v2-0930 Harbor tasks

`harbor/` contains the 82 converted tasks. `../convert_v2_harbor.py` maps the
source record's `working_dir` into `[environment].workdir` in `task.toml`.
All 82 source records specify `/testbed`. Harbor uses this directory when
launching commands, including Claude Code and Codex, even when the cached
image defaults to `/` or `/go`.

The correction uses the existing Harbor runtime's native configuration support;
it requires no Harbor source changes or image rebuild. Memory remains 32 GiB.
The verifier scripts and test patches were not changed by this correction.

The corrected dataset on `root@10.161.41.9` is:

```
/data/swepmv2-harbor-runtime/datasets/v2-0930-workdir/tasks
```

Use this dataset path in new experiment configurations. Existing campaign
configurations still point to their original datasets, preserving their inputs
and results. No model campaign was started or restarted for this correction.

Validation evidence is in `../health_audit/v2-0930-workdir-fix/` and, on the run
host, `/data/swepmv2-harbor-runtime/diagnostics/v2-0930-workdir-fix/`.
