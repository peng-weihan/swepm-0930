#!/usr/bin/env python3
"""Export sanitized benchmark evidence; never copy credential/cache directories."""
import argparse
import base64
import csv
import gzip
import hashlib
import io
import json
import re
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

SECRET_KEY = re.compile(r'^(?:api[_-]?key|.*_api_key|access_token|refresh_token|id_token|auth_token|password|authorization|client_secret|account_id|chatgpt_account_id|email)$', re.I)
TOKEN_PATTERNS = [
    re.compile(r'-----BEGIN (?P<kind>(?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY)-----.*?-----END (?P=kind)-----', re.S),
    re.compile(r'\bsk-[A-Za-z0-9_-]{16,}'),
    re.compile(r'\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})'),
    re.compile(r'\beyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}'),
    re.compile(r'(?i)(?<=Bearer )[A-Za-z0-9_.+/=-]{24,}'),
]


class Sanitizer:
    def __init__(self, secrets=()):
        self.secrets = sorted(set(s for s in secrets if isinstance(s, str) and len(s) >= 8), key=len, reverse=True)
        self.counts = Counter()

    def text(self, value):
        for secret in self.secrets:
            count = value.count(secret)
            if count:
                value = value.replace(secret, '[REDACTED]')
                self.counts['known_secret'] += count
        for pattern in TOKEN_PATTERNS:
            value, n = pattern.subn('[REDACTED_TOKEN]', value)
            self.counts['credential_pattern'] += n
        return value

    def object(self, obj):
        if isinstance(obj, dict):
            result = {}
            for key, value in obj.items():
                if (SECRET_KEY.match(key) or key in ('rate_limits', 'rate_limit_snapshot')) and value is not None and value != '':
                    result[key] = '[REDACTED]'
                    self.counts['credential_or_account_field'] += 1
                else:
                    result[key] = self.object(value)
            return result
        if isinstance(obj, list):
            return [self.object(v) for v in obj]
        if isinstance(obj, str):
            return self.text(obj)
        return obj

    def content(self, raw, suffix):
        text = raw.decode('utf-8')
        if suffix == '.json':
            try:
                return (json.dumps(self.object(json.loads(text)), ensure_ascii=False, indent=2) + '\n').encode()
            except json.JSONDecodeError:
                pass
        if suffix == '.jsonl':
            lines = []
            for line in text.splitlines():
                try:
                    lines.append(json.dumps(self.object(json.loads(line)), ensure_ascii=False, separators=(',', ':')))
                except json.JSONDecodeError:
                    lines.append(self.text(line))
            return ('\n'.join(lines) + '\n').encode()
        return self.text(text).encode()


def gather_secrets(root):
    values = set()

    def walk(obj):
        if isinstance(obj, dict):
            for k, v in obj.items():
                if isinstance(v, str) and (SECRET_KEY.match(k) or k == 'sub') and len(v) >= 8:
                    values.add(v)
                walk(v)
        elif isinstance(obj, list):
            for v in obj:
                walk(v)
        elif isinstance(obj, str) and obj.startswith('eyJ'):
            values.add(obj)
            try:
                part = obj.split('.')[1]
                walk(json.loads(base64.urlsafe_b64decode(part + '=' * (-len(part) % 4))))
            except (ValueError, IndexError):
                pass

    for p in root.glob('.env*'):
        if not p.is_file():
            continue
        for line in p.read_text().splitlines():
            if '=' in line:
                key, value = line.split('=', 1)
                if re.search('TOKEN|KEY|PASSWORD|SECRET', key, re.I):
                    values.add(value.strip().strip('\"\''))
    for p in (root / 'campaigns').glob('*0930*/credentials/*.json'):
        walk(json.loads(p.read_text()))
    return values


def export(root, out):
    out.mkdir(parents=True, exist_ok=False)
    sanitizer = Sanitizer(gather_secrets(root))
    manifest = []
    trials = []
    start = datetime.now(timezone.utc).isoformat()

    def copy(src, rel):
        if src.is_symlink():
            return
        raw = src.read_bytes()
        data = sanitizer.content(raw, src.suffix)
        dst = out / rel
        if len(data) >= 128 * 1024 and src.name not in ('result.json', 'config.json'):
            dst = dst.with_name(dst.name + '.gz')
            stored = gzip.compress(data, compresslevel=6, mtime=0)
        else:
            stored = data
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(stored)
        dst.chmod(src.stat().st_mode & 0o777)
        manifest.append({'source': str(src.relative_to(root)), 'path': str(dst.relative_to(out)),
                         'source_bytes': len(raw), 'exported_bytes': len(stored),
                         'sha256': hashlib.sha256(stored).hexdigest()})

    for job in sorted((root / 'jobs').glob('*0930*')):
        if not job.is_dir():
            continue
        job_start = datetime.now(timezone.utc).isoformat()
        for trial in sorted(p for p in job.iterdir() if p.is_dir()):
            result_path = trial / 'result.json'
            config_path = trial / 'config.json'
            result = json.loads(result_path.read_text()) if result_path.exists() else {}
            cfg = result.get('config') or (json.loads(config_path.read_text()) if config_path.exists() else {})
            task = result.get('task_name') or Path(cfg.get('task', {}).get('path', '')).name
            agent = cfg.get('agent') or {}
            rewards = (result.get('verifier_result') or {}).get('rewards') or {}
            exception = result.get('exception_info') or {}
            usage = result.get('agent_result') or {}
            native = list((trial / 'agent' / 'sessions').rglob('*.jsonl')) if (trial / 'agent' / 'sessions').exists() else []
            trials.append({'job': job.name, 'trial': trial.name, 'task': task,
                           'model': agent.get('model_name'), 'finished': bool(result.get('finished_at')),
                           'reward': rewards.get('reward'), 'exception': exception.get('exception_type'),
                           'started_at': result.get('started_at'), 'finished_at': result.get('finished_at'),
                           'n_input_tokens': usage.get('n_input_tokens'), 'n_cache_tokens': usage.get('n_cache_tokens'),
                           'n_output_tokens': usage.get('n_output_tokens'), 'cost_usd_estimated': usage.get('cost_usd'),
                           'trajectory_present': (trial / 'agent' / 'trajectory.json').exists(),
                           'native_session_files': len(native), 'snapshot_at': job_start})
        for src in sorted(job.rglob('*')):
            if src.is_file():
                copy(src, Path('runs') / job.name / src.relative_to(job))
        print('exported', job.name, flush=True)
    for campaign in sorted((root / 'campaigns').glob('*0930*')):
        for src in sorted(campaign.iterdir()):
            if src.is_file() and src.suffix not in ('.lock', '.pid'):
                copy(src, Path('campaigns') / campaign.name / src.name)
    for name in ('VERSION', 'requirements.lock', 'INSTALL.txt'):
        if (root / name).is_file():
            copy(root / name, Path('runtime') / name)
    metadata = {'started_at': start, 'finished_at': datetime.now(timezone.utc).isoformat(),
                'scope': 'All v2-0930 jobs including original, network recovery, 32GiB retries, smoke, DeepSeek, and workdir rerun snapshot.',
                'live_snapshot': True, 'atomic_across_files': False,
                'excluded': ['credentials/', 'runtime account homes and caches', '.env files', 'Docker images'],
                'redaction_counts': dict(sanitizer.counts),
                'source_bytes': sum(x['source_bytes'] for x in manifest),
                'stored_bytes': sum(x['exported_bytes'] for x in manifest),
                'files': len(manifest), 'trials': len(trials)}
    (out / 'snapshot.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
    (out / 'file-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    (out / 'trials.json').write_text(json.dumps(trials, ensure_ascii=False, indent=2) + '\n')
    with (out / 'trials.csv').open('w') as f:
        writer = csv.DictWriter(f, fieldnames=list(trials[0]))
        writer.writeheader()
        writer.writerows(trials)
    print(json.dumps(metadata), flush=True)


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('root', type=Path)
    p.add_argument('out', type=Path)
    a = p.parse_args()
    export(a.root, a.out)
