"""Check task hashes/schema and real Harbor exec cwd without running an agent."""

import asyncio
import hashlib
import importlib.metadata
import json
from pathlib import Path
import subprocess
import tomllib

from harbor.environments.docker.docker import DockerEnvironment
from harbor.models.task.config import TaskConfig
from harbor.models.trial.paths import TrialPaths


ROOT = Path('/data/swepmv2-harbor-runtime')
DATASET = ROOT / 'datasets/v2-0930-workdir/tasks'
OUTPUT = ROOT / 'diagnostics/v2-0930-workdir-fix'


async def main():
    expected = json.loads((OUTPUT / 'local-validation.json').read_text())
    for relative, digest in expected['files_sha256'].items():
        assert hashlib.sha256((DATASET / relative).read_bytes()).hexdigest() == digest, relative
    configs = {}
    for path in sorted(DATASET.glob('*/task.toml')):
        config = TaskConfig.model_validate(tomllib.loads(path.read_text()))
        assert config.environment.workdir == '/testbed', path
        assert config.environment.memory_mb == 32768, path
        configs[path.parent.name] = config
    assert len(configs) == 82
    # The previous 32 GiB dataset remains an immutable experiment input.
    previous = ROOT / 'datasets/v2-0930-32g/tasks'
    compared = 0
    for relative in expected['files_sha256']:
        before = (previous / relative).read_bytes()
        after = (DATASET / relative).read_bytes()
        if relative.endswith('/task.toml'):
            after = after.replace(b'workdir = "/testbed"\n', b'', 1)
        assert before == after, relative
        compared += 1

    overlay = OUTPUT / 'smoke-compose.json'
    overlay.write_text(json.dumps({'services': {'main': {
        'pull_policy': 'never', 'network_mode': 'none',
    }}}) + '\n')
    results = []
    for number, name in enumerate([
        'lucianodato__libspecbleach-81',
        'RakuenSoftware__aimee-2570',
        'lerd-env__lerd-471',
    ]):
        config = configs[name]
        inspected = json.loads(subprocess.check_output(
            ['docker', 'image', 'inspect', config.environment.docker_image], text=True
        ))[0]
        assert not inspected['Config'].get('Entrypoint')
        paths = TrialPaths(trial_dir=OUTPUT / name)
        paths.mkdir()
        environment = DockerEnvironment(
            environment_dir=DATASET / name / 'environment',
            environment_name=f'swepm-workdir-smoke-{number}',
            session_id=f'swepm-workdir-fix-{number}',
            trial_paths=paths,
            task_env_config=config.environment,
            extra_docker_compose=[overlay],
            override_memory_mb=256,
            override_cpus=1,
        )
        try:
            await environment.start(force_build=False)
            # This uses the same environment.exec entrypoint as installed agents.
            actual = await environment.exec('pwd; git rev-parse --show-toplevel', timeout_sec=15)
            assert actual.return_code == 0, actual
            assert actual.stdout.strip().splitlines() == ['/testbed', '/testbed'], actual
            explicit = await environment.exec('pwd', cwd='/', timeout_sec=15)
            assert explicit.return_code == 0 and explicit.stdout.strip() == '/', explicit
            results.append({
                'task': name,
                'image_default_workdir': inspected['Config'].get('WorkingDir') or '/',
                'harbor_default_pwd': actual.stdout.strip().splitlines()[0],
                'repository_root': actual.stdout.strip().splitlines()[1],
                'explicit_cwd_override': explicit.stdout.strip(),
            })
            print(json.dumps(results[-1]), flush=True)
        finally:
            # Remove only this probe's containers; retain cached images.
            await environment.stop(delete=False)
    report = {
        'harbor_version': importlib.metadata.version('harbor'),
        'schema_valid_tasks': len(configs),
        'unchanged_except_workdir_files': compared,
        'smokes': results,
        'model_calls': 0,
        'image_pulls_or_builds': 0,
    }
    (OUTPUT / 'remote-validation.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report), flush=True)


if __name__ == '__main__':
    asyncio.run(main())
