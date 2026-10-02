Verifier 异常的五个具体例子
核对日期：2026-10-02。以下使用原始四模型主批次的日志，不是 workdir 修正后的 Luna 重跑结果。
本目录的同名 .txt 文件保留原始日志行号；完整轨迹在仓库 runs/ 对应 job/trial/agent/ 下。

1. DeepLabCut__DeepLabCut-3303：把已经存在的测试反向删除

观察批次：Qwen + Claude Code；最终 reward=0。
题目测试补丁原本要新增 tests/utils/test_collect_video_paths.py 等文件。
Qwen 轨迹 step 43 已成功 cherry-pick 仓库中可见的上游提交，其中包含这些测试。
verifier 再安装同一测试补丁时，git apply 因“文件已存在”失败，随后进入 GNU patch 回退：

  The next patch would create the file tests/utils/test_collect_video_paths.py,
  which already exists!  Assuming -R.
  patching file tests/utils/test_collect_video_paths.py

-R 是反向应用：原来“新增文件”的补丁会变成“删除文件”。随后 pytest 报：

  ERROR: file or directory not found: tests/utils/test_collect_video_paths.py
  OMNIGRIL_EXIT_CODE=4

这里的 0 分来自目标测试被删后无法执行，不能按“修复没通过这些测试”解释。
但同一道题的 Luna 日志是测试补丁正常应用，实际 33 passed、1 failed，失败涉及空字符串扩展名的弃用警告。
因此不能把同题四个模型的零分一概归为 verifier，也不能从此例推出 Qwen 的最终实现一定正确。
上游参考提交可读并被 cherry-pick 是另一项独立的评测有效性问题。

2. apache__kafka-22505：测试补丁包含业务代码，反向应用后破坏编译

观察批次：Qwen + Claude Code；最终 reward=0。
原始 v2.json 的 test_patch 并非只修改测试。它还修改：
  raft/src/main/java/org/apache/kafka/raft/CandidateState.java
其中一个变更是：
  - public class CandidateState implements NomineeState {
  + public final class CandidateState implements NomineeState {

verifier 日志先记录对 CandidateState.java 的反向应用：
  Reversed (or previously applied) patch detected!  Assuming -R.
随后 Java 编译器报：
  CandidateState.java:29: error: sealed, non-sealed or final modifiers expected
  public class CandidateState implements NomineeState {

反向补丁移除了 final，与当前接口的 sealed 约束冲突，导致在运行目标测试前编译失败。
这就是“verifier 破坏代码”的具体含义：评分阶段改变了待评实现，随后失败的已不是 agent 交付的原状态。
证据能够解释这次编译失败，不证明消除该问题后全部测试一定通过。

3. babarot__afx-69：恢复旧测试后，迁移补丁失败，却继续执行

观察批次：Luna + Codex；最终 reward=0。四个主模型均观察到此类 setup failed。
题目要求把 pkg 下的实现迁移到 internal。verifier 先执行：
  git checkout 95c6bcd73203fa37b5cd3292b22632d21d1dfeb6 -- cmd/meta_test.go
这把该测试恢复为基线版本，其中仍引用 github.com/babarot/afx/pkg/config。
然后安装测试补丁；补丁还试图从旧 pkg 路径重命名测试，但 agent 已经完成移动，源文件不存在：
  error: pkg/config/config_test.go: No such file or directory

这次 git apply 失败后脚本仍继续 go test，导致：
  cmd/meta_test.go:9:2: no required module provides package github.com/babarot/afx/pkg/config
  FAIL github.com/babarot/afx/cmd [setup failed]

报错看起来像缺 Go 依赖，实际这个路径是本项目被迁移的旧包路径。
直接因果是“恢复旧测试 + 更新测试失败 + 继续评分”，不能简单通过 go get 解释为缺少第三方依赖。
部分 internal 包仍测试通过，也不能抵消 cmd 包未能正确加载的问题。

4. lucianodato__libspecbleach-86：agent 能运行测试，verifier 读不了构建缓存

观察批次：Luna + Codex；最终 reward=0。
轨迹 step 45 的真实工具调用是：
  meson compile -C build && meson test -C build --print-errorlogs && git diff --check
该调用输出 24/24 integration OK，汇总 Ok: 24、Fail: 0。
进入 verifier 后，测试补丁正常安装，但 Meson 报：
  Build data file '/testbed/build/meson-private/build.dat' references functions or classes that don't exist.
  This probably means that it was generated with an old version of meson.
  Consider reconfiguring the directory with "meson setup --reconfigure".
  OMNIGRIL_EXIT_CODE=1

这次评分失败发生在读取构建环境/缓存的阶段，不是业务断言失败。
原始 eval.sh 会调整 PATH，且 verifier 复用 agent 容器及 build 目录；具体 Meson 版本差异仍需进一步复现确认。
不能据此断言原始镜像天生坏了，也不能把 agent 自测的 24 项通过当作新增目标测试已经全部通过。

5. 0xMiden__miden-vm-c_5a9834d：目标补丁缺失，仍得到通过分数

观察批次：Luna + Codex；最终 reward=1。此例不是共同零分的 55 题之一。
verifier 一开始就报：
  error: can't open patch '/tmp/test.patch': No such file or directory
  patch: **** Can't open patch file /tmp/test.patch : No such file or directory
脚本没有在这里终止，继续运行已有测试，最终输出：
  test result: ok. 115 passed; 0 failed
  OMNIGRIL_EXIT_CODE=0

Harbor 根据最终退出标记给出 reward=1，但此次运行没有成功安装预定的 test.patch。
因此这个 1 分不能证明题目要求的目标回归测试已经覆盖。也不能反向断言这份代码一定错误。
转换审计已在缓存中的原始镜像确认该文件本来就缺失；原始 JSON 的 test_patch 非空。
归因是输入镜像封装缺口，转换过程未补齐/拒绝该缺口，加上原始评测脚本允许补丁失败后继续。
不是转换脚本把镜像里已有的 test.patch 删除了。

共性与结论边界

原始评测脚本中常见 git apply ... || patch --batch --fuzz=5 ... 回退；在 agent 已经修改的工作树上，
patch 的自动反向判断可能撤销已存在的改动。转换沿用了这些脚本；Harbor 只是负责调用及读取 reward。
当前 workdir 修复解决的是 agent 启动目录，不会自动修复上述测试安装、构建缓存或 reward 协议问题。

“终止正常”和“评分可靠”必须分开。前者只能说明执行链到达结束，后者还要求待评代码没有被错误改写、
目标测试确实安装且实际执行。原始 reward 应保留为实验记录，不能直接当作干净的模型能力排名。
这些案例是日志与补丁交叉核对，不是对 82 道题逐一完成修复后重新评分。
