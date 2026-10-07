#!/usr/bin/env python3
"""Build an evidence-linked 82-instance report; performs no benchmark execution."""
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
import csv
import hashlib
import json
import re

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
REPAIR = ROOT / 'verifier_repair'
SCOPE = REPAIR / 'full82_review/operational-repair-scope'
TASKS = ROOT / 'v2-0930-verifier-r1/harbor'
BASELINE = ROOT / 'v2-0930/harbor'
REFERENCE_REASONS_ZH = {
    'providers/transports/openai_chat/transport.py': '合并重复的 stream 关键字，修复实际流式文本/工具恢复被重复参数阻断的问题，保留输入请求和流式语义。',
    'src/main/data/migration/v2/migrators/PromptMigrator.ts': '跳过非法/缺失 UUID 和无效标题并记录警告；保留合法 UUID，保存裁剪后长度为1至256的标题。',
    'crates/core/src/config/provider.rs': '为当前改写后的题目要求补 custom preset；属于当前题意对齐，原上游描述只有五种 preset。',
    'crates/daemon/src/daemon/protocol.rs': '按实际 provider key 返回完整配置且不重复；由活动 model/provider 映射判断 active；显式保存 auto_restart=false，防止省略后按 true 重新加载。',
    'src/visualize-client-lib.ts': '补题面明确要求的公开模块路径，以 re-export 暴露原参考解嵌套路径中的同一实现。',
}


def read(path):
    return json.loads(path.read_text())


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def files(root):
    return {str(p.relative_to(root)): digest(p) for p in sorted(root.rglob('*')) if p.is_file()}


def fingerprint(root):
    h = hashlib.sha256()
    for p in sorted(root.rglob('*')):
        if p.is_file():
            h.update(str(p.relative_to(root)).encode() + b'\0')
            h.update(p.read_bytes())
    return h.hexdigest()


def latest(items):
    return max(items, key=lambda x: x.get('finished_at') or '') if items else None


def frozen_validation(row):
    return '/validation/' + row['job_name'] + '/tasks/' in row['snapshot_path']


def reward(row):
    if not row:
        return '无记录'
    return str(int(row['reward'])) if row.get('reward') is not None else '无有效分数'


def table(text):
    return str(text).replace('|', '\\|').replace('\n', ' ')


def main():
    evidence = read(HERE / 'remote-evidence.json')
    old_status = {x['instance_id']: x for x in read(SCOPE / 'status.json')['instances']}
    changes = read(HERE / 'dedicated_changes.json')
    details = {x['instance_id']: x for x in read(SCOPE / 'modification-details.json')['instances']}
    inventory = {x['instance_id']: x for x in read(REPAIR / 'inventory.json')}
    assert len(inventory) == 82 and len(changes) == 53
    assert set(changes) == set(read(SCOPE / 'modified-count-readback.json')['modified_instance_ids'])
    current = evidence['current_remote_fingerprints']
    rows = []
    for ident in sorted(inventory):
        task = TASKS / ident
        fp = fingerprint(task)
        assert fp == current[ident] == old_status[ident]['current_fingerprint'], ident
        vf = [x for x in evidence['validation_trials'] if x['instance_id'] == ident]
        valid_current = [x for x in vf if frozen_validation(x) and x['snapshot_fingerprint'] == fp
                         and x['finished_at'] and x['exception_type'] is None]
        groups = defaultdict(dict)
        for x in valid_current:
            groups[x['job_name']][x['agent']] = x
        pairs = [g for g in groups.values() if g.get('oracle', {}).get('reward') == 1
                 and g.get('nop', {}).get('reward') == 0]
        pair = max(pairs, key=lambda g: g['oracle']['finished_at']) if pairs else None
        if pair:
            health = '没问题'
            reason = '当前任务文件版本有完整 Oracle=1、no-op=0 对照；未发现阻止正确实现通过的环境/verifier 执行问题。'
            next_action = '保留当前执行配置；对后续模型失败按轨迹判断，不因 reward=0 自动修改测试。'
        elif ident == 'Mrmayman__quantumlauncher-c_fb3452c':
            health = '有问题'
            reason = 'cargo test 没有执行真正的自定义 main 测试，Oracle 被执行证据检查拒绝；main 的失败列表还缺可靠非零退出协议。'
            next_action = '修正自定义测试入口与失败协议；核实图形/Java/游戏数据需求，完成预算审查后再实际验证。'
        else:
            health = '待定'
            reason = '尚无当前任务文件版本的完整成功对照。旧版本的通过记录不能直接证明当前版本健康。'
            next_action = '优先补当前版本 Oracle/no-op；只修复实际复现的环境、测试安装、执行入口或判分错误。'
        if ident == 'dexidp__dex-4929':
            reason = '当前同版本 Oracle=0；sessions 开启时 HTTP 与 gRPC Discovery 文档字段不一致。测试可以执行，尚未裁定参考实现、题面与新增断言之间的契约问题。'
            next_action = '保留待定；契约/标准争议属于目前暂停的质量范围，不通过删断言制造通过。'
        elif ident == 'iced-rs__iced-3278':
            reason = '没有找到修复版当前快照的 Oracle/no-op 对照，无法据旧模型分数确认执行健康。'
        elif ident == 'get-bb__bb-c_c88c518':
            reason = '已落地新的删除/import/typecheck 检查，但该版本验证在存储限制处停止；旧版通过不覆盖新检查。'
            next_action = '完成受限资源方案后验证当前版本；资源停止不计作模型或题目逻辑失败。'
        expected = {'未发现执行阻断': '没问题', '有问题': '有问题', '待定': '待定'}[old_status[ident]['operational_status']]
        assert health == expected, (ident, health, expected)
        luna = [x for x in evidence['luna_trials'] if x['instance_id'] == ident and x['finished_at']]
        current_luna = [x for x in luna if '/campaigns/' in x['snapshot_path']
                        and '/tasks/' in x['snapshot_path'] and x['snapshot_fingerprint'] == fp]
        original_files = files(BASELINE / ident)
        current_files = files(task)
        file_changes = [{'path': name, 'kind': 'added' if name not in original_files else
                         'removed' if name not in current_files else 'changed',
                         'before_sha256': original_files.get(name), 'after_sha256': current_files.get(name)}
                        for name in sorted(set(original_files) | set(current_files))
                        if original_files.get(name) != current_files.get(name)]
        config = (task / 'task.toml').read_text()
        workdir = re.search(r'^workdir\s*=\s*"([^"]+)"', config, re.M).group(1)
        memory = int(re.search(r'^memory_mb\s*=\s*(\d+)', config, re.M).group(1))
        separate = re.search(r'^environment_mode\s*=\s*"([^"]+)"', config, re.M).group(1)
        assert workdir == '/testbed' and memory == 32768 and separate == 'separate'
        d = details.get(ident, {})
        row = {'instance_id': ident, 'language': inventory[ident]['language'],
               'health': health, 'health_scope': '明显环境/verifier执行阻断', 'health_reason': reason,
               'dedicated_modified': ident in changes,
               'dedicated_changes': changes.get(ident, ['没有记录额外的逐题专项修改；已应用本报告列出的共用 verifier 修复流程。']),
               'test_overlay': d.get('active_test_overlay'),
               'production_files_excluded_from_test_install': inventory[ident].get('production_files_excluded', []),
               'fixtures_moved_to_test_assets': inventory[ident].get('fixtures_moved_from_reference', []),
               'oracle_only_reference_correction': d.get('oracle_only_reference_correction'),
               'current_fingerprint': fp, 'local_remote_identical': True,
               'workdir': workdir, 'memory_mb': memory, 'verifier_environment_mode': separate,
               'current_pair': pair, 'latest_current_oracle': latest([x for x in valid_current if x['agent'] == 'oracle']),
               'latest_historical_oracle': latest([x for x in vf if frozen_validation(x) and x['agent'] == 'oracle' and x['finished_at']]),
               'latest_current_luna': latest(current_luna), 'latest_historical_luna': latest(luna),
               'all_luna_trial_count': len(luna), 'next_action': next_action,
               'deferred_quality_findings': old_status[ident].get('deferred_quality_findings', []),
               'historical_whole_quality_label': old_status[ident].get('whole_quality_status_separate'),
               'task_dir': str(task), 'baseline_task_dir': str(BASELINE / ident),
               'file_changes_from_baseline_including_shared': file_changes}
        rows.append(row)
    counts = dict(Counter(x['health'] for x in rows))
    assert counts == {'没问题': 60, '待定': 21, '有问题': 1}
    cross = {kind: dict(Counter(x['health'] for x in rows if x['dedicated_modified'] == flag))
             for kind, flag in [('专项修改过', True), ('没有额外专项修改', False)]}
    current_luna = [x['latest_current_luna'] for x in rows if x['latest_current_luna']]
    summary = {'generated_at_utc': datetime.now(timezone.utc).isoformat(),
               'evidence_readback_at_utc': evidence['collected_at_utc'],
               'total': 82, 'dedicated_modified': 53, 'without_dedicated_modification': 29,
               'health_counts': counts, 'cross_counts': cross,
               'current_luna_unique_tasks': len(current_luna),
               'current_luna_rewards': dict(Counter(str(x['reward']) for x in current_luna)),
               'all_remote_validation_trial_records_read': len(evidence['validation_trials']),
               'all_remote_luna_trial_records_read': len(evidence['luna_trials']),
               'excluded_unfrozen_validation_records': sum(not frozen_validation(x) for x in evidence['validation_trials']),
               'latest_two_luna': evidence['latest_two_luna'],
               'method': '只读回查已有运行及逐文件指纹；此次没有重新运行82题。健康仅指明显执行阻断；不认证测试覆盖/公平性/答案隔离。',
               'inputs_sha256': {str(p.relative_to(ROOT)): digest(p) for p in [HERE / 'remote-evidence.json',
                                 HERE / 'dedicated_changes.json', SCOPE / 'status.json',
                                 SCOPE / 'modification-details.json', REPAIR / 'build_tasks.py']}}
    save(HERE / 'instances.json', {'summary': summary, 'instances': rows})
    save(HERE / 'summary.json', summary)
    with (HERE / 'instances.csv').open('w', encoding='utf-8-sig', newline='') as f:
        w = csv.writer(f)
        w.writerow(['instance_id', '健康状态_执行层面', '是否专项修改', '具体修改', '健康依据',
                    '当前Oracle', '当前no-op', '当前Luna', '最近已存Oracle_含旧版', '最近已存Luna_含旧版',
                    '剩余处理', '当前指纹', '当前任务目录', '当前Oracle日志目录', '当前Luna日志目录'])
        for x in rows:
            pair = x['current_pair'] or {}
            w.writerow([x['instance_id'], x['health'], '是' if x['dedicated_modified'] else '否',
                        '；'.join(x['dedicated_changes']), x['health_reason'],
                        reward(pair.get('oracle') or x['latest_current_oracle']), reward(pair.get('nop')),
                        reward(x['latest_current_luna']), reward(x['latest_historical_oracle']),
                        reward(x['latest_historical_luna']), x['next_action'], x['current_fingerprint'],
                        x['task_dir'], (pair.get('oracle') or {}).get('trial_path', ''),
                        (x['latest_current_luna'] or {}).get('trial_path', '')])

    md = ['# SWEPM v2-0930：82题修改说明与执行健康报告', '',
          f"生成时间：{summary['generated_at_utc']}。物理机只读回查时间：{summary['evidence_readback_at_utc']}。", '',
          '当前修复版：`v2-0930-verifier-r1/harbor`；对比基线：`v2-0930/harbor`。运行证据来自 `10.161.41.9` 的 `/data/swepmv2-harbor-runtime`。', '',
          '## 结论与统计口径', '',
          '**82题中，53题有逐题专项修改，29题没有额外专项修改；全部82题均使用共用修复版 verifier 流程。当前执行健康为：60题没问题、1题有问题、21题待定。**', '',
          '| 当前状态 | 数量 | 本报告的含义 |', '|---|---:|---|',
          '| 没问题 | 60 | 当前任务文件版本存在完整 Oracle=1、no-op=0 对照，未发现明确执行阻断。 |',
          '| 有问题 | 1 | 有明确的执行入口/失败协议问题，正确实现也无法按当前流程得到可靠评测。 |',
          '| 待定 | 21 | 缺当前版本完整成功证明，或有尚未裁定的契约问题；不能一律算有缺陷。 |', '',
          '“没问题”限于用户当前要求的环境与 verifier 执行层面。测试过宽/过窄、覆盖缺口、标准不清和历史答案暴露另行保留，不因此改动本表状态。Oracle=1也不证明所有合理实现均可通过。', '',
          '这是一份截至回查时间的证据报告：重新读取了343条 Oracle/no-op 验证记录和207条 Luna运行记录，核对了本地/远端全部82题的文件指纹；此次没有新跑一轮82题。历史早期 smoke 使用可变任务目录的12条记录不作为当前版本证明。', '',
          '| 修改范围 | 没问题 | 有问题 | 待定 | 合计 |', '|---|---:|---:|---:|---:|']
    for kind, n in cross.items():
        md.append(f"| {kind} | {n.get('没问题', 0)} | {n.get('有问题', 0)} | {n.get('待定', 0)} | {sum(n.values())} |")
    md += ['', '53题的去重口径：旧专项台账49题，加上此前漏记但已落地的 Brimstone-454、Dex-4929、Wavesurfer-4340，以及新增 Dax-Pay-f88f383。Aimee-1c60c9c 已在原49题中。修改过不等于所有验证或质量修复已经完成。', '',
           '## 所有82题共用的修改', '',
           '- 使用 `/testbed` 工作目录、32 GiB 内存配置；solver 与 verifier 使用独立环境。',
           '- 收集候选代码补丁，在独立 verifier 中重放；避免直接依赖 agent 留下的测试/构建环境。',
           '- 使用随任务携带的测试资产、路径清单和 SHA-256 校验；测试安装失败即失败，避免宽松反向 patch 恢复旧测试。',
           '- 检查原生测试退出码、显式退出协议和实际执行证据；识别零测试、测试安装失败等情况。',
           '- 将 verifier 缓存/临时产物放入持久日志目录，并限制构建并发。', '',
           '逐题的文件级差异含上述共用变化，见 `instances.json` 的 `file_changes_from_baseline_including_shared`。这些共用差异不重复计入53题专项修改。', '',
           '## 修改边界和参考解说明', '',
           '累计修改包含：环境依赖、测试安装/补丁重放、运行目标与判分、资源/缓存控制，以及早期做过的测试契约和覆盖调整。19题启用了新增/替换测试文件。用户收窄范围后，纯测试质量优化已经暂停。', '',
           '以下4题还存在单独的 Oracle 参考更正补丁：Free-Claude-Code-845、Cherry-Studio-13430、Crabtalk-116、OpenWiki-60f7877。它们在原参考补丁之后由 Oracle 应用，verifier 不给候选应用这些更正。逐题详情列出更正内容；不能将这4题的 Oracle 通过称为“原始参考解未经更正通过”。', '',
           '另外，部分原始 test.patch 混入生产源码，已从 verifier 安装资产分离；必需测试夹具有从参考补丁移到测试资产的情况。这些资产分类变更也在逐题记录中列明。', '',
           '## 最新 Luna 复测', '',
           'Aimee-1c60c9c 与 Dax-Pay-f88f383 已完成 Codex + gpt-6-luna high 复测，均有 turn.completed、无 Harbor 异常、reward=0；捕获补丁与 verifier 重放补丁一致，测试资产校验成功。', '',
           '| 题目 | Oracle / no-op | Luna | 回查到的失败点 |', '|---|---|---|---|',
           '| Aimee-1c60c9c | 1 / 0 | 0 | 两个C测试程序通过；Go测试引用的 AgentTier、BuildEconomicsReport 等缺失，包构建失败。 |',
           '| Dax-Pay-f88f383 | 1 / 0 | 0 | 测试要求的 AlipayAuthProvider、DouyinH5AuthProvider、WechatMpAuthProvider 等类找不到。 |', '',
           '这说明最近补齐的依赖/头文件/下载源阻断已解决，但 Luna 本次实现没有满足当前测试要求。仅凭缺符号日志，不能进一步断言是实现遗漏还是过度绑定私有接口；后者属于已暂停的质量审查范围。', '',
           f"与当前任务文件指纹精确匹配的 Luna 复测共有{len(current_luna)}题，其中4题reward=1、5题reward=0；另外73题没有当前版本匹配的Luna记录，不能当作0分。旧版本Luna结果在逐题详情单独标注。", '',
           '两题环境修复及复测均在已批准3 GiB新增存储范围内完成：实际卷可用空间差值峰值约1.73 GiB，保守归属计量峰值约2.32 GiB，监控未触发停止。', '',
           '## 明确问题与待定项', '',
           '**QuantumLauncher-fb3452c：** `cargo test` 并未调用实际下载/启动 Minecraft 并观察窗口的自定义 main；main 中普通测试失败也没有可靠非零退出协议。当前 Oracle 因缺实际执行证据得0分。修复需要明确入口、失败协议和运行依赖，不能通过删除执行证据检查使其通过。', '',
           '**21题待定的主要原因：** 多数是任务后来修改过，而成功对照来自旧快照；Dex-4929 有同版 Oracle 的 sessions 文档字段不一致；BB-c88c518 新检查的验证曾因资源限制停止；Iced-3278 缺修复版对照。早期 EvoScientist-307/Libspecbleach-83 smoke 失败引用的是可变目录，仅作历史诊断，不能据今天目录的指纹追认当时版本。', '',
           '| 待定题目 | 原因 / 下一步 |', '|---|---|']
    for x in rows:
        if x['health'] == '待定':
            md.append(f"| {x['instance_id']} | {table(x['health_reason'])} |")
    md += ['', '后续顺序：先处理 QuantumLauncher 的明确执行阻断；再补待定题当前版本对照，发现真实环境/verifier错误再修。纯契约与覆盖争议保留记录。新的大规模安装/构建仍遵循既有存储授权边界。', '',
           '## 82题总表', '',
           '| # | instance | 专项修改 | 执行健康 | 当前Oracle / no-op | 当前Luna |',
           '|---:|---|---|---|---|---|']
    for index, x in enumerate(rows, 1):
        pair = x['current_pair']
        controls = '1 / 0' if pair else (reward(x['latest_current_oracle']) + ' / 未验收' if x['latest_current_oracle'] else '无完整同版对照')
        md.append(f"| {index} | [{x['instance_id']}](#task-{index:02d}) | {'是' if x['dedicated_modified'] else '否'} | {x['health']} | {controls} | {reward(x['latest_current_luna'])} |")
    md += ['', '## 逐题修改与证据', '']
    for index, x in enumerate(rows, 1):
        ident = x['instance_id']
        md += [f'<a id="task-{index:02d}"></a>', '', f'### {index:02d}. {ident}', '',
               f"**执行健康：{x['health']}；专项修改：{'是' if x['dedicated_modified'] else '否'}。** {x['health_reason']}", '', '实际修改：', '']
        md.extend('- ' + c for c in x['dedicated_changes'])
        ov = x['test_overlay']
        if ov:
            md += ['', '已启用新增/替换测试文件：' + '、'.join('`' + p + '`' for p in ov['files']) + '。']
        for key, label in [('production_files_excluded_from_test_install', '从测试安装资产剥离的生产文件'),
                           ('fixtures_moved_to_test_assets', '转为测试资产的必需夹具')]:
            if x[key]:
                md += ['', label + '：' + '、'.join('`' + p + '`' for p in x[key]) + '。']
        correction = x['oracle_only_reference_correction']
        if correction:
            md += ['', '**Oracle附加参考更正：**']
            md += ['', *['- `' + c['path'] + '`：' + REFERENCE_REASONS_ZH[c['path']] for c in correction['corrections']]]
        pair = x['current_pair']
        if pair:
            md += ['', f"验证：当前同版 Oracle=1、no-op=0；任务快照 `{pair['oracle']['snapshot_path']}`。",
                   f"Oracle日志：`{pair['oracle']['trial_path']}`；no-op日志：`{pair['nop']['trial_path']}`。"]
        else:
            cur = x['latest_current_oracle']
            if cur:
                md += ['', f"当前版本Oracle：reward={reward(cur)}，状态 `{(cur['status'] or '').strip()}`；日志 `{cur['trial_path']}`。"]
            hist = x['latest_historical_oracle']
            if hist and (not cur or hist['trial_path'] != cur['trial_path']):
                md += ['', f"旧版Oracle：reward={reward(hist)}，日志 `{hist['trial_path']}`。其文件版本与当前不同，不计作当前验收。"]
            if not cur and not hist:
                md += ['', '尚未找到可采用的修复版 Oracle 记录。']
        luna = x['latest_current_luna']
        hist_luna = x['latest_historical_luna']
        if luna:
            md += ['', f"当前版本Luna：reward={reward(luna)}；Harbor异常 `{luna['exception_type'] or '无'}`；日志 `{luna['trial_path']}`。"]
        elif hist_luna:
            md += ['', f"当前版本Luna：无匹配记录。最近历史版本reward={reward(hist_luna)}，Harbor异常 `{hist_luna['exception_type'] or '无'}`；日志 `{hist_luna['trial_path']}`。旧分数不代表当前版本。"]
        else:
            md += ['', 'Luna：本次回查范围内未找到运行记录。']
        md += ['', '剩余处理：' + x['next_action']]
        if x['deferred_quality_findings']:
            md += ['', '另有测试契约/覆盖/历史答案等质量记录，按用户当前范围暂缓；详见 `instances.json` 的 `deferred_quality_findings`。']
        md += ['', f"当前文件指纹：`{x['current_fingerprint']}`。开发区与物理机一致。",
               f"任务文件：[本地目录]({x['task_dir']})；具体文件差异与SHA在 `instances.json` 对应条目。", '']
    md += ['## 附件与复核方式', '',
           '- `instances.csv`：82题表格，可直接导入表格软件筛选。',
           '- `instances.json`：逐题完整修改、测试资产、参考更正、证据路径、文件差异及SHA。',
           '- `summary.json`：机器可读统计与来源文件校验和。',
           '- `remote-evidence.json`：本次只读回查的343条验证、207条Luna元数据及最近两题的日志摘录。',
           '- `historical-failure-excerpts.json`：补充失败摘录；其中早期smoke引用可变任务目录，仅作历史诊断，不计当前版本失败证明。',
           '- `build_report.py` / `collect_remote.py` / `dedicated_changes.json`：报告构建规则、只读采集代码与53题人工核对的修改说明。', '',
           '所有结果按 instance_id 去重；修改统计不累加迭代轮次。完整任务文件指纹一致才将固定快照运行归于当前版本。模型是否解题成功与评测环境是否能正确执行分别记录。', '']
    (HERE / 'REPORT.md').write_text('\n'.join(md))
    print(json.dumps({'counts': counts, 'cross_counts': cross, 'current_luna': len(current_luna),
                      'report_bytes': (HERE / 'REPORT.md').stat().st_size}, ensure_ascii=False))


if __name__ == '__main__':
    main()
