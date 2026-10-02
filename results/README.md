# 实验结果索引

所有 reward 均为原始评分；缺失 reward 不计为 0。网络恢复、32 GiB 补跑和 workdir 重跑分别保留，不能直接把全部 trial 相加作为 82 题分数。

原四模型按题合并网络恢复后的 328 条记录：[original-four-models.csv](original-four-models.csv)。

所有 job 的明细见 [job-summary.csv](job-summary.csv)，所有 trial 见 [../trials.csv](../trials.csv)。

| Job | 阶段 | Trial | 已结束 | Reward 1 | Reward 0 | 缺分 | 异常 | 标准轨迹 |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| [swepm-v2-0930-claude-code-deepseek-v4-flash-siflow-max300-nomcp-c16-20261001T173933Z](../runs/swepm-v2-0930-claude-code-deepseek-v4-flash-siflow-max300-nomcp-c16-20261001T173933Z/) | original | 82 | 82 | 4 | 40 | 38 | 75 | 44 |
| [swepm-v2-0930-claude-code-deepseek-v4-flash-siflow-max300-nomcp-c16-20261001T173933Z-network-recovery](../runs/swepm-v2-0930-claude-code-deepseek-v4-flash-siflow-max300-nomcp-c16-20261001T173933Z-network-recovery/) | network-recovery | 38 | 38 | 3 | 34 | 1 | 28 | 37 |
| [swepm-v2-0930-claude-code-glm-5.3-siflow-max300-nomcp-32g-oom-once-20261002T050646Z](../runs/swepm-v2-0930-claude-code-glm-5.3-siflow-max300-nomcp-32g-oom-once-20261002T050646Z/) | 32GiB-retry | 6 | 6 | 0 | 6 | 0 | 3 | 6 |
| [swepm-v2-0930-claude-code-glm-5.3-siflow-max300-nomcp-c16-20261001T173933Z](../runs/swepm-v2-0930-claude-code-glm-5.3-siflow-max300-nomcp-c16-20261001T173933Z/) | original | 82 | 82 | 10 | 37 | 35 | 40 | 46 |
| [swepm-v2-0930-claude-code-glm-5.3-siflow-max300-nomcp-c16-20261001T173933Z-network-recovery](../runs/swepm-v2-0930-claude-code-glm-5.3-siflow-max300-nomcp-c16-20261001T173933Z-network-recovery/) | network-recovery | 35 | 35 | 5 | 29 | 1 | 7 | 34 |
| [swepm-v2-0930-claude-code-kimi-k3-qiniu-max300-nomcp-32g-oom-once-20261002T050646Z](../runs/swepm-v2-0930-claude-code-kimi-k3-qiniu-max300-nomcp-32g-oom-once-20261002T050646Z/) | 32GiB-retry | 5 | 5 | 1 | 4 | 0 | 2 | 5 |
| [swepm-v2-0930-claude-code-kimi-k3-qiniu-max300-nomcp-c16-20261001T173933Z](../runs/swepm-v2-0930-claude-code-kimi-k3-qiniu-max300-nomcp-c16-20261001T173933Z/) | original | 82 | 82 | 13 | 39 | 30 | 36 | 51 |
| [swepm-v2-0930-claude-code-kimi-k3-qiniu-max300-nomcp-c16-20261001T173933Z-network-recovery](../runs/swepm-v2-0930-claude-code-kimi-k3-qiniu-max300-nomcp-c16-20261001T173933Z-network-recovery/) | network-recovery | 30 | 30 | 2 | 26 | 2 | 4 | 29 |
| [swepm-v2-0930-claude-code-qwen3.8-max-qiniu-max300-nomcp-32g-oom-once-20261002T050646Z](../runs/swepm-v2-0930-claude-code-qwen3.8-max-qiniu-max300-nomcp-32g-oom-once-20261002T050646Z/) | 32GiB-retry | 6 | 6 | 1 | 5 | 0 | 1 | 6 |
| [swepm-v2-0930-claude-code-qwen3.8-max-qiniu-max300-nomcp-c16-20261001T173933Z](../runs/swepm-v2-0930-claude-code-qwen3.8-max-qiniu-max300-nomcp-c16-20261001T173933Z/) | original | 82 | 82 | 9 | 38 | 35 | 41 | 47 |
| [swepm-v2-0930-claude-code-qwen3.8-max-qiniu-max300-nomcp-c16-20261001T173933Z-network-recovery](../runs/swepm-v2-0930-claude-code-qwen3.8-max-qiniu-max300-nomcp-c16-20261001T173933Z-network-recovery/) | network-recovery | 35 | 35 | 8 | 26 | 1 | 7 | 33 |
| [swepm-v2-0930-codex-gpt-6-luna-high-account-smoke-20261001T180922Z](../runs/swepm-v2-0930-codex-gpt-6-luna-high-account-smoke-20261001T180922Z/) | smoke | 1 | 1 | 0 | 0 | 1 | 0 | 1 |
| [swepm-v2-0930-codex-gpt-6-luna-high-account-smoke-20261001T180922Z-complete-cli](../runs/swepm-v2-0930-codex-gpt-6-luna-high-account-smoke-20261001T180922Z-complete-cli/) | smoke | 1 | 1 | 0 | 0 | 1 | 0 | 1 |
| [swepm-v2-0930-codex-gpt-6-luna-high-nomcp-c8-20261001T180922Z](../runs/swepm-v2-0930-codex-gpt-6-luna-high-nomcp-c8-20261001T180922Z/) | original | 82 | 82 | 9 | 73 | 0 | 0 | 82 |
| [swepm-v2-0930-network-plugin-check](../runs/swepm-v2-0930-network-plugin-check/) | smoke | 1 | 1 | 0 | 0 | 1 | 0 | 1 |
| [swepm-v2-0930-smoke-deepseek-v4-flash-siflow-max300-nomcp-20261001T173933Z](../runs/swepm-v2-0930-smoke-deepseek-v4-flash-siflow-max300-nomcp-20261001T173933Z/) | smoke | 1 | 1 | 0 | 0 | 1 | 0 | 1 |
| [swepm-v2-0930-smoke-glm-5.3-siflow-max300-nomcp-20261001T173933Z](../runs/swepm-v2-0930-smoke-glm-5.3-siflow-max300-nomcp-20261001T173933Z/) | smoke | 1 | 1 | 0 | 0 | 1 | 0 | 1 |
| [swepm-v2-0930-smoke-kimi-k3-qiniu-max300-nomcp-20261001T173933Z](../runs/swepm-v2-0930-smoke-kimi-k3-qiniu-max300-nomcp-20261001T173933Z/) | smoke | 1 | 1 | 0 | 0 | 1 | 0 | 1 |
| [swepm-v2-0930-smoke-qwen3.8-max-qiniu-max300-nomcp-20261001T173933Z](../runs/swepm-v2-0930-smoke-qwen3.8-max-qiniu-max300-nomcp-20261001T173933Z/) | smoke | 1 | 1 | 0 | 0 | 1 | 0 | 1 |
| [swepm-v2-0930-workdir-codex-gpt-6-luna-high-nomcp-c16-20261002T065111Z](../runs/swepm-v2-0930-workdir-codex-gpt-6-luna-high-nomcp-c16-20261002T065111Z/) | workdir-fixed-rerun | 82 | 75 | 10 | 65 | 7 | 0 | 76 |
| [swepm-v2-0930-workdir-codex-gpt-6-luna-high-nomcp-c16-20261002T065111Z-smoke](../runs/swepm-v2-0930-workdir-codex-gpt-6-luna-high-nomcp-c16-20261002T065111Z-smoke/) | smoke | 1 | 1 | 0 | 0 | 1 | 0 | 1 |
