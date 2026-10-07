"""Read-only remote evidence collection. No credentials, caches or dependency writes."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json

ROOT = Path('/data/swepmv2-harbor-runtime')
REPAIR = ROOT / 'repairs/v2-0930-verifier-r1'
DATASET = ROOT / 'datasets/v2-0930-verifier-r1/tasks'
fingerprints = {}


def fingerprint(path):
    key = str(path)
    if key not in fingerprints:
        if not (path / 'task.toml').exists():
            return None
        digest = hashlib.sha256()
        for f in sorted(path.rglob('*')):
            if f.is_file():
                digest.update(str(f.relative_to(path)).encode() + b'\0')
                digest.update(f.read_bytes())
        fingerprints[key] = digest.hexdigest()
    return fingerprints[key]


def small_text(path, limit=1000):
    return path.read_text(errors='replace')[:limit] if path.exists() else None


def trial(path):
    result = json.loads((path / 'result.json').read_text())
    cfg = json.loads((path / 'config.json').read_text())
    task = Path(cfg['task']['path'])
    if task.name not in current:
        return None
    info = result.get('agent_info') or {}
    return {'instance_id': task.name, 'trial_path': str(path), 'job_name': path.parent.name,
            'snapshot_path': str(task), 'snapshot_fingerprint': fingerprint(task),
            'agent': info.get('name'), 'model': info.get('model_info'),
            'finished_at': result.get('finished_at'),
            'reward': ((result.get('verifier_result') or {}).get('rewards') or {}).get('reward'),
            'exception_type': (result.get('exception_info') or {}).get('exception_type'),
            'status': small_text(path / 'verifier/status.txt'),
            'eval_exit': small_text(path / 'verifier/eval-exit-code.txt'),
            'result_sha256': hashlib.sha256((path / 'result.json').read_bytes()).hexdigest()}


current = {p.name: fingerprint(p) for p in sorted(DATASET.iterdir()) if (p / 'task.toml').exists()}
assert len(current) == 82
validations = []
for f in sorted((REPAIR / 'validation-jobs').glob('*/*/result.json')):
    if (f.parent / 'config.json').exists():
        row = trial(f.parent)
        if row:
            validations.append(row)
solvers = []
campaigns = []
for c in sorted((ROOT / 'campaigns').glob('v2-0930-codex-gpt-6-luna-high*')):
    p = c / 'manifest.json'
    if not p.exists():
        continue
    manifest = json.loads(p.read_text())
    if not manifest.get('job_dir'):
        continue
    job = Path(manifest['job_dir'])
    campaigns.append({'campaign': str(c), 'job': str(job)})
    for f in sorted(job.glob('*/result.json')):
        if (f.parent / 'config.json').exists():
            row = trial(f.parent)
            if row:
                solvers.append(row)

environment = REPAIR / 'full82_review/operational-repair-scope/environment-r1'
plan = json.loads((environment / 'luna-full-launch-plan.json').read_text())
latest_two = []
for f in sorted(Path(plan['job_dir']).glob('*/result.json')):
    p = f.parent
    row = trial(p)
    v = p / 'verifier'
    row['test_installation'] = small_text(v / 'test-installation.txt', 6000)
    a = p / 'agent/solution.patch'
    b = v / 'agent.patch'
    row['captured_patch_bytes'] = a.stat().st_size if a.exists() else None
    row['replayed_patch_bytes'] = b.stat().st_size if b.exists() else None
    row['capture_replay_identical'] = a.exists() and b.exists() and a.read_bytes() == b.read_bytes()
    output = small_text(v / 'eval-stdout.txt', 4 * 1024 * 1024) or ''
    row['relevant_eval_lines'] = [line for line in output.splitlines()
        if any(w in line for w in ['undefined:', 'cannot find symbol', 'SWEPM_C_TEST_',
                                   'Tests run:', 'BUILD FAILURE', 'OMNIGRIL_EXIT_CODE='])][-35:]
    events = []
    errors = []
    for line in (p / 'agent/codex.txt').open():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if not isinstance(event, dict):
            continue
        item = event.get('item') or {}
        if not isinstance(item, dict):
            item = {}
        if event.get('type') == 'turn.completed':
            events.append(event)
        if event.get('type') in ['error', 'turn.failed'] or item.get('type') == 'error':
            errors.append({'type': event.get('type'), 'item_type': item.get('type')})
    row['completed_turn_events'] = events
    row['api_error_event_types'] = errors
    latest_two.append(row)

budget = {name: json.loads((environment / name).read_text())
          for name in ['luna-full-r1/result.json', 'owned-budget-watch-luna-full-r1/result.json']}
print(json.dumps({'collected_at_utc': datetime.now(timezone.utc).isoformat(),
                  'current_remote_fingerprints': current, 'validation_trials': validations,
                  'luna_trials': solvers, 'luna_campaigns': campaigns,
                  'latest_two_luna': latest_two, 'environment_budget': budget}, ensure_ascii=False))
