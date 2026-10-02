# Codex account benchmark: v2-0930

- Dataset: 82 tasks from `/data/swepmv2-harbor-runtime/datasets/v2-0930/tasks`.
- Model: `gpt-6-luna`; reasoning effort: `high`; concurrency: 8; MCP: disabled.
- Authentication: the current ChatGPT account, using Harbor `CODEX_AUTH_JSON_PATH`; no sidecar route.
- Harbor: 0.23.0; native Codex CLI and code-mode host: 0.159.0.
- Task agent timeout: 7200 seconds; verifier timeout: 3600 seconds. This Codex adapter does not implement the Claude Code `max_turns` flag.
- Codex's native binaries are mounted read-only; no Node/npm or package install is needed.
- Each trial has its own explicit Docker subnet and runtime directory under this campaign's `/data` directory.
- Native sessions and tool execution logs are saved in the job directory listed in `manifest.json`.
- Source task verifier scripts are unchanged. Known test-patch installation defects remain a separate scoring concern.

`launch.py` checks a completed smoke with successful real shell execution and model/effort evidence before launching all 82 tasks. It refuses a duplicate launch.

Credentials are not included in this development-area mirror. The restricted remote `credentials` directory and local preflight account cache must not be committed or included in report archives. Harbor's reported USD cost is an estimate, not evidence of ChatGPT account billing.
