#!/usr/bin/env python3
"""Build navigable result tables from the exported snapshot, without dependencies."""
import csv
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'results'
OUT.mkdir(exist_ok=True)


def write_csv(name, rows):
    with (OUT / name).open('w') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def artifact(base, name):
    p = ROOT / base / name
    if not p.is_file():
        p = p.with_name(p.name + '.gz')
    return str(p.relative_to(ROOT)) if p.is_file() else ''


audit = json.loads((ROOT / 'health_audit/v2-0930-four-model-20261002/report.json').read_text())
main = []
for model, group in audit['models'].items():
    for record in group['records']:
        remote = Path(record['trial_dir'])
        base = Path('runs') / remote.parent.name / remote.name
        main.append({'model': model, 'task': record['task'], 'reward': record['reward'],
                     'exception': record.get('exception'), 'job': remote.parent.name,
                     'trial': remote.name, 'result': artifact(base, 'result.json'),
                     'trajectory': artifact(base, 'agent/trajectory.json'),
                     'verifier_stdout': artifact(base, 'verifier/eval-stdout.txt'),
                     'verifier_stderr': artifact(base, 'verifier/eval-stderr.txt')})
write_csv('original-four-models.csv', main)
(OUT / 'original-four-models.json').write_text(json.dumps(main, ensure_ascii=False, indent=2) + '\n')

trials = json.loads((ROOT / 'trials.json').read_text())
jobs = []
for job in sorted({r['job'] for r in trials}):
    rows = [r for r in trials if r['job'] == job]
    if 'workdir' in job:
        phase = 'workdir-fixed-rerun'
    elif '32g-oom-once' in job:
        phase = '32GiB-retry'
    elif 'network-recovery' in job:
        phase = 'network-recovery'
    else:
        phase = 'original'
    if 'smoke' in job or 'plugin-check' in job:
        phase = 'smoke'
    counts = Counter(str(r['reward']) for r in rows)
    jobs.append({'job': job, 'phase': phase, 'trial_count': len(rows),
                 'finished': sum(r['finished'] for r in rows),
                 'unfinished': sum(not r['finished'] for r in rows),
                 'reward_1': sum(r['reward'] == 1 for r in rows),
                 'reward_0': sum(r['reward'] == 0 for r in rows),
                 'reward_missing': sum(r['reward'] is None for r in rows),
                 'exceptions': sum(bool(r['exception']) for r in rows),
                 'trajectories': sum(r['trajectory_present'] for r in rows),
                 'native_session_files': sum(r['native_session_files'] for r in rows),
                 'snapshot_at': rows[0]['snapshot_at']})
write_csv('job-summary.csv', jobs)
(OUT / 'job-summary.json').write_text(json.dumps(jobs, ensure_ascii=False, indent=2) + '\n')
lines = ['# 实验结果索引', '', '所有 reward 均为原始评分；缺失 reward 不计为 0。网络恢复、32 GiB 补跑和 workdir 重跑分别保留，不能直接把全部 trial 相加作为 82 题分数。', '',
         '原四模型按题合并网络恢复后的 328 条记录：[original-four-models.csv](original-four-models.csv)。', '',
         '所有 job 的明细见 [job-summary.csv](job-summary.csv)，所有 trial 见 [../trials.csv](../trials.csv)。', '',
         '| Job | 阶段 | Trial | 已结束 | Reward 1 | Reward 0 | 缺分 | 异常 | 标准轨迹 |',
         '|---|---|---:|---:|---:|---:|---:|---:|---:|']
for j in jobs:
    lines.append(f"| [{j['job']}](../runs/{j['job']}/) | {j['phase']} | {j['trial_count']} | {j['finished']} | {j['reward_1']} | {j['reward_0']} | {j['reward_missing']} | {j['exceptions']} | {j['trajectories']} |")
(OUT / 'README.md').write_text('\n'.join(lines) + '\n')
print(json.dumps({'indexed_jobs': len(jobs), 'indexed_trials': len(trials), 'merged_original_records': len(main)}))
