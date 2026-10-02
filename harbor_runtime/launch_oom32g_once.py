#!/usr/bin/env python3
"""Prepare a 32 GiB dataset and rerun each previously OOM-killed trial once.

Run on the authorized physical machine using its existing Python environment.
The existing dataset/results are retained. No dependencies or images are installed.
"""

import hashlib
import ipaddress
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone


ROOT = Path('/data/swepmv2-harbor-runtime')
BASE = ROOT / 'campaigns/v2-0930-max300-nomcp'
CAMPAIGN = ROOT / 'campaigns/v2-0930-oom32g-once'
DATASET = ROOT / 'datasets/v2-0930-32g/tasks'
MEMORY_MB = 32768


def save_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def run_command(config):
    return [
        'sudo', '-u', 'ray', '-H', 'env', 'PYTHONDONTWRITEBYTECODE=1',
        'PYTHONPATH=' + str(CAMPAIGN), str(ROOT / 'bin/harbor'), 'run',
        '--config', str(config), '--env-file', str(ROOT / '.env.deepseek-v4-flash-siflow'),
        '--plugin', 'trial_networks:TrialNetworks', '--yes',
    ]


def prepare():
    manifest_path = CAMPAIGN / 'manifest.json'
    if manifest_path.exists():
        return json.loads(manifest_path.read_text())
    assert not DATASET.exists(), 'Refusing to overwrite an existing dataset'
    original = json.loads((BASE / 'manifest.json').read_text())
    models = []
    for model in original['models']:
        final = {}
        for job in [Path(model['job_dir']), ROOT / 'jobs' / (model['job_name'] + '-network-recovery')]:
            assert json.loads((job / 'result.json').read_text()).get('finished_at')
            for result_path in job.glob('*/result.json'):
                result = json.loads(result_path.read_text())
                final[result['task_name']] = (result, result_path)
        selected = []
        for task, (result, path) in sorted(final.items()):
            message = (result.get('exception_info') or {}).get('exception_message', '')
            if re.search(r'\bKilled\s+\|\s+claude', message):
                selected.append({'task': task, 'previous_result': str(path)})
        if selected:
            models.append({'model': model['model'], 'source_config': model['config'], 'tasks': selected})
    expected = {'qwen3.8-max-qiniu': 6, 'glm-5.3-siflow': 6, 'kimi-k3-qiniu': 5}
    assert {x['model']: len(x['tasks']) for x in models} == expected

    source = ROOT / 'datasets/v2-0930/tasks'
    assert len(list(source.glob('*/task.toml'))) == 82
    assert shutil.disk_usage(ROOT).free > 2 * 1024**3
    # Each trial gets an explicit, isolated subnet, avoiding Docker's exhausted default pool.
    subnet_pool = ipaddress.ip_network('10.253.192.0/18')
    network_ids = subprocess.check_output(['docker', 'network', 'ls', '-q'], text=True).split()
    if network_ids:
        networks = json.loads(subprocess.check_output(['docker', 'network', 'inspect', *network_ids], text=True))
        for network in networks:
            for allocation in (network.get('IPAM') or {}).get('Config') or []:
                subnet = allocation.get('Subnet')
                if subnet:
                    other = ipaddress.ip_network(subnet)
                    assert other.version != 4 or not subnet_pool.overlaps(other), subnet

    CAMPAIGN.mkdir(parents=True, exist_ok=True)
    shutil.copytree(source, DATASET)
    old_limits = {}
    for path in sorted(DATASET.glob('*/task.toml')):
        before = path.read_text()
        old_limits[path.parent.name] = int(re.search(r'(?m)^memory_mb\s*=\s*(\d+)', before).group(1))
        after, count = re.subn(r'(?m)^memory_mb\s*=\s*\d+\s*$', 'memory_mb = 32768', before)
        assert count == 1
        path.write_text(after)
    # Verify the full dataset, including verifier and solution files: only memory may change.
    for path in source.rglob('*'):
        if not path.is_file():
            continue
        relative = path.relative_to(source)
        before = path.read_bytes()
        after = (DATASET / relative).read_bytes()
        if path.name == 'task.toml':
            expected_bytes = re.sub(rb'(?m)^memory_mb\s*=\s*\d+\s*$', b'memory_mb = 32768', before)
            assert after == expected_bytes, relative
        else:
            assert hashlib.sha256(before).digest() == hashlib.sha256(after).digest(), relative
    save_json(CAMPAIGN / 'original-memory-mb.json', old_limits)

    shutil.copyfile(BASE / 'claude_no_mcp.py', CAMPAIGN / 'claude_no_mcp.py')
    shutil.copyfile(BASE / 'compose.json', CAMPAIGN / 'compose.json')
    plugin = (BASE / 'trial_networks.py').read_text()
    plugin = plugin.replace(str(BASE), str(CAMPAIGN)).replace('10.253.128.0', '10.253.192.0')
    plugin = plugin.replace('swepm.campaign=v2-0930-max300-nomcp', 'swepm.campaign=v2-0930-oom32g-once')
    (CAMPAIGN / 'trial_networks.py').write_text(plugin)
    timestamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    for model in models:
        config = json.loads(Path(model['source_config']).read_text())
        config.pop('datasets', None)
        config['tasks'] = [{'path': str(DATASET / task['task'])} for task in model['tasks']]
        config['retry'] = {'max_retries': 0}
        config['job_name'] = f"swepm-v2-0930-claude-code-{model['model']}-max300-nomcp-32g-oom-once-{timestamp}"
        config['environment']['extra_docker_compose'] = [str(CAMPAIGN / 'compose.json')]
        path = CAMPAIGN / (model['model'] + '.json')
        save_json(path, config)
        model.update(config=str(path), job_name=config['job_name'], job_dir=str(ROOT / 'jobs' / config['job_name']))
    # Confirm the required images are cached; preparation must not trigger image pulls.
    images = set()
    for model in models:
        for task in model['tasks']:
            text = (DATASET / task['task'] / 'task.toml').read_text()
            images.add(json.loads(re.search(r'(?m)^docker_image\s*=\s*(.*)$', text).group(1)))
    subprocess.run(['docker', 'image', 'inspect', *sorted(images)], check=True, stdout=subprocess.DEVNULL)
    user = pwd.getpwnam('ray')
    os.chown(CAMPAIGN, user.pw_uid, user.pw_gid)
    manifest = {
        'dataset': str(DATASET), 'dataset_instances': 82, 'memory_mb': MEMORY_MB,
        'rerun_count': 17, 'max_retries': 0, 'attempts_per_selected_task': 1,
        'reasoning_effort': 'max', 'max_turns': 300, 'mcp': False,
        'models': models, 'prepared_at': datetime.now(timezone.utc).isoformat(),
    }
    save_json(manifest_path, manifest)
    return manifest


def launch(manifest):
    for model in manifest['models']:
        if model.get('launcher_pid'):
            continue
        assert not Path(model['job_dir']).exists(), 'Existing job: refusing to launch again'
        subprocess.run(run_command(model['config']) + ['--dry-run'], cwd=CAMPAIGN, check=True)
    for model in manifest['models']:
        if model.get('launcher_pid'):
            continue
        with (CAMPAIGN / (model['model'] + '.launch.log')).open('a') as log:
            process = subprocess.Popen(run_command(model['config']), cwd=CAMPAIGN,
                                       stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                                       start_new_session=True)
        model['launcher_pid'] = process.pid
        model['launched_at'] = datetime.now(timezone.utc).isoformat()
        save_json(CAMPAIGN / 'manifest.json', manifest)
        print('STARTED', model['model'], len(model['tasks']), process.pid, flush=True)


if __name__ == '__main__':
    manifest = prepare()
    if '--launch' in sys.argv:
        launch(manifest)
    print(json.dumps({'memory_mb': manifest['memory_mb'], 'dataset_instances': 82,
                      'rerun_count': manifest['rerun_count'], 'max_retries': 0,
                      'models': [{'model': x['model'], 'tasks': len(x['tasks']),
                                  'job_name': x['job_name'], 'pid': x.get('launcher_pid')}
                                 for x in manifest['models']]}, indent=2))
