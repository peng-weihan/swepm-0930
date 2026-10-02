"""Read-only checks of cached input images; no builds, pulls or test execution."""

from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import subprocess


ROOT = Path('/data/swepmv2-harbor-runtime/diagnostics/v2-0930-conversion-audit')
PROBE = r'''
printf 'repository_present\t'
if [ -d "$1/.git" ] || [ -f "$1/.git" ]; then printf 'yes\n'; else printf 'no\n'; fi
cd "$1" || exit 2
printf 'pwd\t'; pwd
printf 'head\t'; git -c safe.directory="$1" rev-parse HEAD
printf 'base_object_present\t'
git -c safe.directory="$1" cat-file -e "$2^{commit}" 2>/dev/null; printf '%s\n' "$?"
printf 'tracked_status_begin\n'
git -c safe.directory="$1" --no-optional-locks status --porcelain --untracked-files=no
printf 'tracked_status_end\n'
printf 'test_patch_present\t'
if [ -f /tmp/test.patch ]; then
  printf 'yes\n'
  printf 'test_patch_hash\t'; sha256sum /tmp/test.patch
  printf 'test_patch_size\t'; wc -c < /tmp/test.patch
  git -c safe.directory="$1" apply --check /tmp/test.patch >/dev/null 2>&1
  printf 'test_patch_forward_check\t%s\n' "$?"
  git -c safe.directory="$1" apply --reverse --check /tmp/test.patch >/dev/null 2>&1
  printf 'test_patch_reverse_check\t%s\n' "$?"
else
  printf 'no\n'
fi
'''


def probe(index, record):
    name = f'swepm-conversion-audit-{index}'
    inspected = json.loads(subprocess.check_output(
        ['docker', 'image', 'inspect', record['image_name']], text=True
    ))[0]
    config = inspected['Config']
    row = dict(record, image_id=inspected['Id'], repo_digests=inspected.get('RepoDigests'),
               image_workdir=config.get('WorkingDir'), image_user=config.get('User'),
               image_entrypoint=config.get('Entrypoint'), image_volumes=config.get('Volumes'),
               image_env_names=[v.split('=', 1)[0] for v in config.get('Env') or []])
    if config.get('Volumes'):
        row['probe_skipped'] = 'Declared image volumes could initialize large copies.'
        return row
    command = ['docker', 'run', '--rm', '--pull=never', '--read-only', '--network=none',
               '--user=0', '--workdir=/', '--memory=256m', '--cpus=1', '--pids-limit=32',
               '--name', name, '--entrypoint=sh', record['image_name'], '-c', PROBE,
               'probe', record['working_dir'], record['base_commit']]
    try:
        result = subprocess.run(command, text=True, capture_output=True, timeout=75)
        row.update(returncode=result.returncode, stderr=result.stderr[:2000])
        lines = result.stdout.splitlines()
        inside = False
        tracked = []
        fields = {}
        for line in lines:
            if line == 'tracked_status_begin':
                inside = True
            elif line == 'tracked_status_end':
                inside = False
            elif inside:
                tracked.append(line)
            elif '\t' in line:
                key, value = line.split('\t', 1)
                fields[key] = value
        row.update(probe=fields, tracked_status_count=len(tracked), tracked_status_sample=tracked[:12])
        patch_hash = fields.get('test_patch_hash', '').split()
        row['test_patch_matches_source'] = bool(patch_hash and patch_hash[0] == record['test_patch_sha256'])
        row['head_matches_base'] = fields.get('head') == record['base_commit']
    except subprocess.TimeoutExpired:
        subprocess.run(['docker', 'rm', '-f', name], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=15)
        row['probe_timeout'] = True
    return row


if __name__ == '__main__':
    records = json.loads((ROOT / 'image-probe-input.json').read_text())
    print('DISK_FREE', shutil.disk_usage('/data').free, flush=True)
    result = []
    with ThreadPoolExecutor(max_workers=3) as executor:
        futures = [executor.submit(probe, i, record) for i, record in enumerate(records)]
        for future in as_completed(futures):
            result.append(future.result())
            if len(result) % 10 == 0 or len(result) == len(records):
                print('CHECKED', len(result), 'OF', len(records), flush=True)
                (ROOT / 'image-probe-results.json').write_text(json.dumps(result, indent=2) + '\n')
    print('DONE', datetime.now(timezone.utc).isoformat(), flush=True)
