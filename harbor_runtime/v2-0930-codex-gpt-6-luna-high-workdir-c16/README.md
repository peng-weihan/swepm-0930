# v2-0930 workdir-corrected Codex rerun

- Host: `root@10.161.41.9`.
- Dataset: `/data/swepmv2-harbor-runtime/datasets/v2-0930-workdir/tasks` (82 tasks).
- Model: `gpt-6-luna`; reasoning effort: `high`; concurrency: 16.
- Authentication: the same current ChatGPT account as the previous Luna campaign.
- MCP disabled; native Codex and code-mode host 0.159.0; Harbor 0.23.0.
- Each task: `/testbed` default workdir, 32 GiB memory, 4 CPUs, 7200-second agent
  timeout and 3600-second verifier timeout. Error retry limit remains 1.
- Verifier scripts are unchanged; previously identified test-patch defects remain.

The remote campaign lives at
`/data/swepmv2-harbor-runtime/campaigns/v2-0930-codex-gpt-6-luna-high-workdir-c16`.
The launcher is `../launch_luna_workdir_c16.py`; it refuses duplicate launches,
checks cached images and isolated networking, and verifies a real account/model
call with successful shell execution in `/testbed` before starting all 82 tasks.

`manifest.json` records the job path and launch receipt. Native sessions and
command output are preserved under each trial's `agent/` directory in that job.
This development-area mirror excludes the remote `credentials/` and `runtime/`
directories. Do not include credentials or runtime account caches in exports.
