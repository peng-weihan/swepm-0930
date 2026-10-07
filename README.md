# SWEPM v2-0930 修复任务、健康报告与实验记录

## 最新修复版：2026-10-07

已发布 [82 个修复后的 Harbor instance](v2-0930-verifier-r1/README.md) 和 [逐题修改、执行健康报告](verifier_repair/reports/20261007-instance-health/REPORT.md)。其中 **53 题有专项修改；60 题没问题、1 题有问题、21 题待定**。健康判断限于明确的环境与 verifier 执行问题，测试契约、覆盖范围等质量争议仍单独保留。

- [全部任务目录](v2-0930-verifier-r1/harbor/)、[逐题索引和当前指纹](v2-0930-verifier-r1/task-index.json)、[报告 CSV](verifier_repair/reports/20261007-instance-health/instances.csv)。
- [两个修复镜像的 Docker Hub 仓库](https://hub.docker.com/r/raymone23/swepm-0930)、[推送、匿名拉取和引用迁移证明](verifier_repair/image_publish/README.md)。
- [执行前的镜像、Docker network 与 Enola 离线缓存准备](v2-0930-verifier-r1/README.md#运行前准备)。
- [本次发布校验](verifier_repair/github-release-validation.json)、[新增文件清单](verifier_repair/github-release-manifest.json)。

本次上传保持 82 个任务与开发区文件一致；没有重新求解或验证全部 82 题。报告、验证摘要及 Docker Hub 地址迁移均注明各自时间和证据边界。

## 历史实验快照：2026-10-02

本仓库保存 82 道题的运行结果、标准化轨迹、原生 session、verifier 日志、配置与分析。包含 Qwen、GLM、Kimi、GPT-6-Luna 四组主要实验，以及 DeepSeek 失败批次、网络恢复、32 GiB 补跑、smoke 和修正 workdir 后的 Luna 重跑快照。

**这些是原始实验记录，不是经过 verifier 修复并重新认证的模型排名。** 已确认有测试被反向删除、业务代码被反向修改、测试补丁缺失、零测试通过及构建环境问题。正常结束、`turn.completed` 和 `reward=1` 都不能单独证明评分有效。

## 从这里开始

- [运行结果索引](results/README.md)：逐 job 完成情况、原始 reward、异常数和轨迹数。
- [原四模型 328 条结果](results/original-four-models.csv)：每个模型 82 题，按题合并网络恢复结果；提供对应结果、轨迹和 verifier 文件路径。
- [全部 trial 索引](trials.csv)：包含重试、补跑和 smoke，不应直接累加成主批次成绩。
- [分析入口](ANALYSIS.md)：共同零分、环境、verifier、转换审计和历史质量审计。
- [五个 verifier 异常的详细案例](health_audit/v2-0930-four-model-20261002/verifier_examples/README.txt)：过程、日志、因果解释及不能下结论的部分。
- [快照信息](snapshot.json)：准确的导出起止时间、范围、体积和脱敏计数。

## 原四模型主批次

下表来自原审查快照，网络恢复按同题覆盖原 trial；不合入 32 GiB 补跑或 workdir 重跑。异常与 reward 可以同时存在，缺失 reward 不当作零分。GLM/Kimi 各有部分 reward=1 的记录同时带 agent 异常，详见逐题数据。

| 模型 | Harness | 配置 | 题数 | 原始 reward=1 | 无 Harbor 终止异常 | 有终止异常 |
|---|---|---|---:|---:|---:|---:|
| qwen3.8-max-qiniu | Claude Code | max reasoning / 最多 300 turns / 16 并发 / MCP 关闭 | 82 | 17 | 69 | 13 |
| glm-5.3-siflow | Claude Code | max reasoning / 最多 300 turns / 16 并发 / MCP 关闭 | 82 | 15 | 70 | 12 |
| kimi-k3-qiniu | Claude Code | max reasoning / 最多 300 turns / 16 并发 / MCP 关闭 | 82 | 15 | 72 | 10 |
| gpt-6-luna | Codex | high / 8 并发 / MCP 关闭 | 82 | 9 | 82 | 0 |

配置表达的是本地请求设置，不能仅据此认证各供应商内部实际 reasoning 行为。上述原始分数受评测有效性问题影响，不能直接用于公平能力比较。

## 批次如何区分

- 原始 job：`...20261001T173933Z`（Claude Code）与 `...nomcp-c8-20261001T180922Z`（Codex）。
- 网络恢复：job 名以 `-network-recovery` 结尾。主批次分析按题使用恢复结果，原始失败证据也保留。
- 32 GiB 补跑：job 名含 `32g-oom-once`；仅重跑先前 OOM 的 17 条，不是重新跑全部 82 题。
- 新版 Luna：job 名含 `workdir-codex-gpt-6-luna-high-nomcp-c16`；`/testbed`、32 GiB、4 CPU、high、16 并发，agent 7200 秒、verifier 3600 秒，MCP 关闭。该批导出时仍有运行中的任务，详见快照索引。
- DeepSeek：作为额外的运行和故障记录保留，不加入四模型共同零分分析。
- smoke / plugin-check：只用于启动、真实调用或网络验证，不加入 82 题成绩。

此次快照在运行持续期间逐文件生成，**不是原子快照**；每个 job 的 trial 状态以 `trials.csv` 的 `snapshot_at` 为准。运行中日志可能只有前半段，后续完成结果不会自动进入这个 commit。已被 Harbor 内部重试覆盖的旧文件无法从现存目录恢复；保留下来的 job 日志仍可能记录其发生。

## 文件布局

```text
runs/<job>/<trial>/
  result.json                  # 原始 reward、异常、时间、token、估算费用
  config.json                  # 本 trial 的设置，凭据已脱敏
  agent/trajectory.json[.gz]   # Harbor 标准轨迹；启动失败时可能不存在
  agent/sessions/...          # 原生 Claude Code / Codex session
  agent/claude-code.txt[.gz]   # Claude Code 命令输出（如有）
  agent/codex.txt[.gz]         # Codex 命令输出（如有）
  verifier/                  # 测试标准输出、错误、reward 和退出码
campaigns/                   # 远端启动配置与运行状态，不含认证和账号缓存
harbor_runtime/              # 开发区启动脚本、配置镜像和先前健康/用量快照
health_audit/                # 四模型审查、转换审计、workdir 修复验证
quality_audit/               # 单独标记的旧 v2.1 质量审计，已保持模型去敏
v2-0930/                    # 源记录和 workdir 修正后的 82 个 Harbor task
convert_v2_harbor.py          # 转换脚本
runtime/                     # Harbor 版本与依赖锁定记录
scripts/                     # 读取、导出和重建索引脚本
```

较大的日志和轨迹使用 gzip 保存；完整内容可用标准库直接读取，不需要安装依赖：

```bash
python3 scripts/read_artifact.py runs/<job>/<trial>/agent/trajectory.json.gz
python3 scripts/read_artifact.py runs/<job>/<trial>/agent/sessions/<session>.jsonl.gz
python3 scripts/build_index.py
```

大文件在凭据清理后压缩为 `.gz`，内容没有为体积而截断。某些原始运行本来没有轨迹或 verifier 结果，这些缺失在索引中保留。仓库未额外导出每个最终工作树的独立 patch；模型编辑行为需从轨迹和工具输出查看，不能声称每题都已有经过验证的最终 patch。

## 用量和版本

运行结果保留 token 和 Harbor 估算费用；原生 session 保留模型调用事件。已有 [Luna turns/token 汇总](harbor_runtime/v2-0930-codex-gpt-6-luna-high-workdir-c16/usage-turns.json) 是标有时间的较早 53 题快照，并不代表此次导出时的全部完成题。

该汇总的 turns 指 native `token_usage_record` 中去重的 `response_id` 数，不是顶层 `turn.completed` 次数。Claude Code 的 SDK turns 与此口径不能直接混用。`cost_usd` 是 Harbor 估值，不是账号实际账单；缓存输入属于总输入的一部分，reasoning 输出属于总输出的一部分。

历史快照的 Harbor 为 0.23.0；新版 Codex 与 code-mode host 为 0.159.0，具体配置以各批次文件为准。workdir 修复使用 Harbor 现有 `environment.workdir`，没有改 Harbor 核心。**2026-10-02 的原始快照只修复 workdir；后续 verifier 修复请查看上方独立发布的 `v2-0930-verifier-r1/` 和报告。**

## 脱敏与复现边界

不包含 API key、ChatGPT auth 文件、账号缓存、`.env` 或 Docker 镜像。JSON 中的认证/账号字段、原生 session 的账号限额数据和识别到的 token 字符串被替换为占位符，日志结构和评测事件保留。源码测试中符合 token 模式的示例字符串也可能被保守替换：`v2-0930/v2.json` 的两个 instance 的 `test_patch` 共 6 处被替换，因此该源文件不是原始文件的逐字节副本。相应 Harbor task 文件未因这 6 处发生变化。

历史快照文件清单见 [file-manifest.json](file-manifest.json)、[local-file-manifest.json](local-file-manifest.json)；本次新增内容单列发布清单，`checksums.sha256` 覆盖当前发布文件。源路径只用于追溯，在其他机器上并不存在。Docker 镜像仍需按 task.toml 获取。原 `v2-0930/` 中三题镜像缺少 `/tmp/test.patch` 的问题属于历史快照，修复版的处理和未决状态按最新逐题报告判断。

发布校验见 [publish-validation.json](publish-validation.json)：检查了 1,707 个 gzip 文件、3,833 个 JSON、612 个 JSONL，并逐条核对 328 条主批次结果；未发现解析、文件哈希或所检查的凭据模式残留问题。项目测试中的 29 处私钥块也已替换。克隆后可运行 `sha256sum -c checksums.sha256` 校验发布文件。

历史分析中的“正在运行”和时间点均属于其原快照，不代表当前状态。旧 v2.1 审计不是 v2-0930 新版逐题重新审计，不能混用其计数。
