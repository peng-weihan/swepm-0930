"""Run on 10.161.41.9 after preparing this campaign and completing its smokes."""

import json
from pathlib import Path
import subprocess

ROOT = Path('/data/swepmv2-harbor-runtime')
CAMPAIGN = ROOT / 'campaigns/v2-0930-max300-nomcp'


def command(config):
    return ['sudo', '-u', 'ray', '-H', 'env', 'PYTHONDONTWRITEBYTECODE=1',
            'PYTHONPATH=' + str(CAMPAIGN), str(ROOT / 'bin/harbor'),
            'run', '--config', config, '--env-file',
            str(ROOT / '.env.deepseek-v4-flash-siflow'), '--plugin',
            'trial_networks:TrialNetworks', '--yes']


def main():
    manifest = json.loads((CAMPAIGN / 'manifest.json').read_text())
    for row in manifest['models']:
        result = json.loads((ROOT / 'jobs' / row['smoke_job_name'] / 'result.json').read_text())
        assert result['finished_at'], row['model']
        assert result['stats']['n_errored_trials'] == 0, row['model']
        assert not Path(row['job_dir']).exists(), 'Job already exists: ' + row['job_dir']
        dry = subprocess.run(command(row['config']) + ['--dry-run'], cwd=CAMPAIGN,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        (CAMPAIGN / (row['model'] + '.full.dry-run.txt')).write_text(dry.stdout)
        if dry.returncode:
            raise RuntimeError(dry.stdout)
        print('Validated:', row['model'], flush=True)

    for row in manifest['models']:
        with (CAMPAIGN / (row['model'] + '.launch.log')).open('a') as log:
            proc = subprocess.Popen(command(row['config']), cwd=CAMPAIGN,
                                    stdin=subprocess.DEVNULL, stdout=log,
                                    stderr=subprocess.STDOUT, start_new_session=True)
        row['launcher_pid'] = proc.pid
        # Persist each receipt immediately so a partial launch remains inspectable.
        (CAMPAIGN / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        print('Started:', row['model'], proc.pid, row['job_name'], flush=True)


if __name__ == '__main__':
    main()
