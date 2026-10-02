# 分析索引与结论边界

## 四模型主批次：82 题与共同零分 55 题

- [完整审查说明](health_audit/v2-0930-four-model-20261002/summary.txt)
- [82 题横向结果](health_audit/v2-0930-four-model-20261002/all_82.csv)
- [共同零分逐题归因](health_audit/v2-0930-four-model-20261002/common_zero_attribution.txt) / [CSV](health_audit/v2-0930-four-model-20261002/common_zero_attribution.csv)
- [完整结构化审查](health_audit/v2-0930-four-model-20261002/report.json)
- [运行时长对照](health_audit/v2-0930-four-model-20261002/execution_timing.json)
- [参考提交读取/cherry-pick 线索](health_audit/v2-0930-four-model-20261002/cherry_pick_indicators.json)
- [OOM 内核记录](health_audit/v2-0930-four-model-20261002/oom32g_kernel_events.json)

四组共同 reward=0 为 55 题，其中 43 题四组都没有 Harbor 终止异常。55 题中 52 题至少一组出现测试补丁风险标记；这不是“52 个镜像已证实坏了”，也不是“52 题全部零分都由 verifier 导致”。保守复核中直接 verifier 破坏证据涉及 13 题，环境/运行器异常涉及 6 题；类别可以重叠。详细记录区分实现失败、评测失败、终止异常和未实施修复。

## 五个具体 verifier 案例

[详细说明与逐步解释](health_audit/v2-0930-four-model-20261002/verifier_examples/README.txt) 配套文件位于同目录：

| Instance | 观察到的问题 | 不能由此推断的结论 |
|---|---|---|
| DeepLabCut__DeepLabCut-3303 | Qwen/GLM 的目标测试被反向补丁删除，pytest 找不到文件 | 不能把 Luna 实际 33 过 1 败也归为同因 |
| apache__kafka-22505 | test.patch 包含业务代码；反向移除 final 后无法编译 | 不能证明修复 verifier 后整题一定通过 |
| babarot__afx-69 | 恢复旧测试、重命名补丁失败、继续测试，遗留旧包导入 | 不能简单视为缺外部 Go 依赖 |
| lucianodato__libspecbleach-86 | agent 自测 24 过；verifier 无法读取 Meson 构建数据 | 不足以证明原始镜像天生损坏，也不证明目标测试全部通过 |
| 0xMiden__miden-vm-c_5a9834d | test.patch 缺失仍跑旧测试并 reward=1 | reward=1 不证明预定测试正确安装，也不证明代码错误 |

## Harbor 转换与 workdir

- [转换审计全文](health_audit/v2-0930-conversion-audit/report.txt)
- [字段映射](health_audit/v2-0930-conversion-audit/field-mapping.csv)
- [82 题逐项检查](health_audit/v2-0930-conversion-audit/all-82-checks.csv)
- [82 个缓存镜像只读探查](health_audit/v2-0930-conversion-audit/image-probe-results.json)
- [reward 协议受控复现](health_audit/v2-0930-conversion-audit/reward-wrapper-reproduction.json)
- [workdir 修复验证](health_audit/v2-0930-workdir-fix/local-validation.json)

已修复原始 `working_dir=/testbed` 未映射到 Harbor 配置的问题。验证 82 个任务的身份、镜像、base commit、问题、gold patch 和评测脚本的映射，没有发现额外的这些字段丢失。

另外三题原始镜像缺 `/tmp/test.patch`：Miden 5a9834d、forgecode 2716、xremap 892。原始 JSON 的 test_patch 非空；转换脚本没有交付或验证这些文件。缺失在原镜像中已存在，不能说是转换删除了文件，但接入层没有把缺口拦住。

原始脚本的不安全补丁回退被沿用；Harbor shared verifier 还会继承 agent 工作树与缓存状态，与当前本地 v1 评测器导出 diff 后在新容器复验的方式不同。workdir 修复没有消除这些差异。

reward wrapper 的潜在协议问题在受控复现中成立，但对旧四模型 328 条日志检查的实际命中为 0，不能把潜在缺陷直接当作已发生的分数错误。详细报告保留了未完成复现和不能确定的因果边界。

## 早期 v2.1 质量审计

[审计入口](quality_audit/swepm-v2.1-quality-audit/README.md) 和 [逐题表格](quality_audit/swepm-v2.1-quality-audit/quality_summary.csv) 保留先前已经去除审计模型身份的版本。共 82 题，76 份有效报告、6 个环境异常；它属于旧 v2.1 输入，不能视为 v2-0930 已完成同样的质量认证。

## 未做的工作

本次是资料归档和日志核对，没有重新运行所有 oracle/no-op，没有修复全部 verifier，没有认证每条最终 patch，也没有把缺测试或零测试通过的原始 reward 自动改写为其他分数。可复核证据与未解决问题均保留。
