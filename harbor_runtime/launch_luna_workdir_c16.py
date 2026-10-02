#!/usr/bin/env python3
"""Launch the authorized workdir-corrected Luna rerun on 10.161.41.9."""

import argparse
from datetime import datetime, timezone
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import shutil
import subprocess
import tomllib


ROOT = Path('/data/swepmv2-harbor-runtime')
SOURCE = ROOT / 'campaigns/v2-0930-codex-gpt-6-luna-high'
CAMPAIGN = ROOT / 'campaigns/v2-0930-codex-gpt-6-luna-high-workdir-c16'
DATASET = ROOT / 'datasets/v2-0930-workdir/tasks'
POOL = ipaddress.ip_network('10.252.0.0/18')
MARKER = 'LUNA_WORKDIR_HIGH_OK'


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def prepare():
    manifest_path = CAMPAIGN / 'manifest.json'
    if manifest_path.exists():
        return json.loads(manifest_path.read_text())
    assert not CAMPAIGN.exists(), 'Unfinished preparation requires inspection'
    assert shutil.disk_usage(ROOT).free > 100 * 1024**3
    paths = sorted(DATASET.glob('*/task.toml'))
    assert len(paths) == 82
    images = set()
    checksums = {}
    for path in paths:
        config = tomllib.loads(path.read_text())
        assert config['environment']['workdir'] == '/testbed', path
        assert config['environment']['memory_mb'] == 32768, path
        assert config['agent']['timeout_sec'] == 7200, path
        images.add(config['environment']['docker_image'])
        for file in sorted(path.parent.rglob('*')):
            if file.is_file():
                checksums[str(file.relative_to(DATASET))] = hashlib.sha256(file.read_bytes()).hexdigest()
    # No image pull/build or dependency installation is needed for this campaign.
    subprocess.run(['docker', 'image', 'inspect', *sorted(images)], check=True,
                   stdout=subprocess.DEVNULL)
    networks = subprocess.check_output(['docker', 'network', 'ls', '-q'], text=True).split()
    if networks:
        for network in json.loads(subprocess.check_output(['docker', 'network', 'inspect', *networks], text=True)):
            for entry in (network.get('IPAM') or {}).get('Config') or []:
                if entry.get('Subnet'):
                    existing = ipaddress.ip_network(entry['Subnet'])
                    assert existing.version != 4 or not POOL.overlaps(existing), entry['Subnet']

    CAMPAIGN.mkdir()
    (CAMPAIGN / 'runtime').mkdir()
    (CAMPAIGN / 'credentials').mkdir(mode=0o700)
    shutil.copyfile(SOURCE / 'credentials/auth.json', CAMPAIGN / 'credentials/auth.json')
    os.chmod(CAMPAIGN / 'credentials/auth.json', 0o600)
    shutil.copyfile(SOURCE / 'codex_account.py', CAMPAIGN / 'codex_account.py')
    plugin = (SOURCE / 'trial_networks.py').read_text()
    plugin = plugin.replace(str(SOURCE), str(CAMPAIGN))
    plugin = plugin.replace('10.253.64.0', str(POOL.network_address))
    plugin = plugin.replace('swepm.campaign=v2-0930-codex-gpt-6-luna-high',
                            'swepm.campaign=v2-0930-codex-gpt-6-luna-high-workdir-c16')
    (CAMPAIGN / 'trial_networks.py').write_text(plugin)
    compose = json.loads((SOURCE / 'compose.json').read_text().replace(str(SOURCE), str(CAMPAIGN)))
    compose['services']['main']['pull_policy'] = 'never'
    save(CAMPAIGN / 'compose.json', compose)

    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    job_name = f'swepm-v2-0930-workdir-codex-gpt-6-luna-high-nomcp-c16-{stamp}'
    config = json.loads((SOURCE / 'full.json').read_text().replace(str(SOURCE), str(CAMPAIGN)))
    config.update(job_name=job_name, n_concurrent_trials=16,
                  datasets=[{'path': str(DATASET)}])
    save(CAMPAIGN / 'full.json', config)
    smoke_task = CAMPAIGN / 'smoke-task'
    shutil.copytree(SOURCE / 'smoke-task', smoke_task)
    toml = (smoke_task / 'task.toml').read_text()
    assert 'workdir =' not in toml
    (smoke_task / 'task.toml').write_text(toml.replace('[environment]\n', '[environment]\nworkdir = "/testbed"\n'))
    (smoke_task / 'instruction.md').write_text(
        'Use the shell tool to execute this exact command, without changing directory: '
        f'pwd; git rev-parse --show-toplevel; printf {MARKER}\n'
        f'Then reply exactly {MARKER}. Do not modify repository files.\n'
    )
    smoke = json.loads((SOURCE / 'smoke.json').read_text().replace(str(SOURCE), str(CAMPAIGN)))
    smoke['job_name'] = job_name + '-smoke'
    save(CAMPAIGN / 'smoke.json', smoke)
    save(CAMPAIGN / 'task-checksums.json', checksums)
    manifest = {
        'dataset': str(DATASET), 'instances': 82, 'model': 'gpt-6-luna',
        'reasoning_effort': 'high', 'concurrency': 16, 'mcp': False,
        'auth': 'current_chatgpt_account', 'codex_version': '0.159.0',
        'harbor_version': '0.23.0', 'memory_mb': 32768, 'workdir': '/testbed',
        'agent_timeout_sec': 7200, 'verifier_timeout_sec': 3600,
        'retry': config['retry'], 'job_name': job_name,
        'job_dir': str(ROOT / 'jobs' / job_name), 'smoke_job_name': smoke['job_name'],
        'full_started': False, 'network_pool': str(POOL),
        'created_at': datetime.now(timezone.utc).isoformat(),
        'scope': 'New rerun; original verifier scripts retained, including known patch defects.',
    }
    save(manifest_path, manifest)
    return manifest


def environment():
    env = os.environ.copy()
    env.update(PYTHONPATH=str(CAMPAIGN), PYTHONDONTWRITEBYTECODE='1')
    for key in ['OPENAI_API_KEY', 'OPENAI_BASE_URL', 'CODEX_API_KEY',
                'ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_BASE_URL']:
        env.pop(key, None)
    return env


def command(name):
    return [str(ROOT / 'bin/harbor'), 'run', '-c', str(CAMPAIGN / name),
            '--plugin', 'trial_networks:TrialNetworks']


def check_smoke(manifest):
    job = ROOT / 'jobs' / manifest['smoke_job_name']
    assert json.loads((job / 'result.json').read_text()).get('finished_at'), 'Smoke unfinished'
    paths = list(job.glob('*/result.json'))
    assert len(paths) == 1
    assert not json.loads(paths[0].read_text()).get('exception_info'), 'Smoke trial failed'
    events = []
    for path in job.glob('*/agent/codex.txt'):
        for line in path.read_text().splitlines():
            try:
                events.append(json.loads(line))
            except ValueError:
                pass
    assert any(e.get('type') == 'turn.completed' for e in events), 'No completed real call'
    assert not any(e.get('type') in ['error', 'turn.failed'] or e.get('item', {}).get('type') == 'error'
                   for e in events), 'Smoke API/tool error'
    assert any(e.get('item', {}).get('type') == 'command_execution'
               and e['item'].get('exit_code') == 0
               and e['item'].get('aggregated_output', '').strip() == f'/testbed\n/testbed\n{MARKER}'
               for e in events), 'No successful shell/workdir proof'
    contexts = []
    for path in job.glob('*/agent/sessions/*/*/*/*.jsonl'):
        for line in path.read_text().splitlines():
            event = json.loads(line)
            if event.get('type') == 'turn_context':
                contexts.append(event['payload'])
    assert contexts and all(c.get('model') == 'gpt-6-luna' and c.get('effort') == 'high'
                            for c in contexts), 'Wrong model or reasoning effort'
    return {'turn_completed': True, 'shell_success': True, 'pwd': '/testbed',
            'model': 'gpt-6-luna', 'reasoning_effort': 'high'}


def launch(manifest):
    assert not manifest.get('full_started'), 'Campaign already started'
    env = environment()
    for name in ['smoke.json', 'full.json']:
        with (CAMPAIGN / (name + '.dry-run.txt')).open('w') as log:
            subprocess.run(command(name) + ['--dry-run'], env=env, cwd=CAMPAIGN,
                           stdout=log, stderr=subprocess.STDOUT, check=True)
    smoke_job = ROOT / 'jobs' / manifest['smoke_job_name']
    if not smoke_job.exists():
        with (CAMPAIGN / 'smoke.launch.log').open('w') as log:
            process = subprocess.Popen(command('smoke.json'), env=env, cwd=CAMPAIGN,
                                       stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT)
        manifest['smoke_pid'] = process.pid
        save(CAMPAIGN / 'manifest.json', manifest)
        print('SMOKE_STARTED', process.pid, manifest['smoke_job_name'], flush=True)
        code = process.wait(timeout=420)
        assert code == 0, f'Smoke process exited {code}'
    manifest['smoke_evidence'] = check_smoke(manifest)
    save(CAMPAIGN / 'manifest.json', manifest)
    assert not Path(manifest['job_dir']).exists(), 'Refusing duplicate full job'
    with (CAMPAIGN / 'full.launch.log').open('w') as log:
        process = subprocess.Popen(command('full.json'), env=env, cwd=CAMPAIGN,
                                   stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=True)
    manifest.update(full_started=True, launcher_pid=process.pid,
                    launched_at=datetime.now(timezone.utc).isoformat())
    save(CAMPAIGN / 'manifest.json', manifest)
    print('FULL_STARTED', json.dumps(manifest), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--launch', action='store_true')
    args = parser.parse_args()
    prepared = prepare()
    if args.launch:
        launch(prepared)
    else:
        print(json.dumps(prepared, indent=2))
