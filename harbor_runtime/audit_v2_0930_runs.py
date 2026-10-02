#!/usr/bin/env python3
"""Read-only audit of four v2-0930 runs; writes diagnostic JSON, never reruns tasks."""
import collections
from datetime import datetime, timezone
import json
from pathlib import Path
import re

ROOT = Path('/data/swepmv2-harbor-runtime')
BASE = ROOT / 'campaigns/v2-0930-max300-nomcp'
ANSI = re.compile(r'\x1b\[[0-?]*[ -/]*[@-~]')
PATTERNS = {
    'test_patch_missing': r"(?i)(?:can't open patch.*test\.patch|cannot open.*test\.patch).*no such file",
    'patch_reversal': r'Reversed \(or previously applied\) patch detected!\s+Assuming -R',
    'patch_hunks_rejected': r'(?i)(?:^Hunk #\d+ FAILED|\d+ out of \d+ hunks? (?:FAILED|ignored)|^Skipping patch|^No file to patch|^can.t find file to patch)',
    'patch_fuzz': r'(?i)^Hunk #\d+ succeeded .*with fuzz',
    'git_apply_rejection': r'^error: (?:patch failed:|.*patch does not apply|.*already exists in working directory)',
    'git_apply_missing_source': r'^error: .+: No such file or directory$',
    'no_tests_found': r'(?i)(?:^No tests found|^No tests defined\.|^no tests ran in|\bcollected 0 items\b|^No test files found)',
    'dependency_network_error': r'(?i)(?:Could not resolve host|Temporary failure in name resolution|Could not transfer artifact|failed to download from|Could not resolve hostname|ConnectTimeoutError|Connection timed out.*(?:https?|443)|Failed to establish a new connection)',
    'missing_command': r'(?i)(?:^.*(?:/eval\.sh|/test\.sh|bash|sh):.*command not found|^.*(?:/eval\.sh|/test\.sh):.*No such file or directory)',
    'process_killed': r'(?:^Killed\s*$|fatal error: Killed signal terminated program|\bKilled\s+(?:python|node|pytest|npm|ninja|cmake|mvn|go|cargo)|signal: killed)',
}
PATTERNS = {k: re.compile(v) for k, v in PATTERNS.items()}
PATCH_UNRELIABLE = {'test_patch_missing', 'patch_reversal', 'patch_hunks_rejected', 'patch_apply_failed_without_fallback'}


def events(path):
    if not path.exists():
        return
    with path.open(errors='replace') as handle:
        for line in handle:
            try:
                event = json.loads(line)
            except ValueError:
                continue
            if isinstance(event, dict):
                yield event


def load_job(path):
    result = {}
    for file in path.glob('*/result.json'):
        data = json.loads(file.read_text())
        result[data['task_name']] = (file.parent, data)
    return result


def verifier(directory, reward, task):
    flags = collections.Counter()
    samples = collections.defaultdict(list)
    for name in ['eval-stdout.txt', 'eval-stderr.txt']:
        path = directory / 'verifier' / name
        if not path.exists():
            continue
        with path.open(errors='replace') as handle:
            for number, raw in enumerate(handle, 1):
                line = ANSI.sub('', raw).strip()
                for flag, regex in PATTERNS.items():
                    if regex.search(line):
                        flags[flag] += 1
                        if len(samples[flag]) < 2:
                            samples[flag].append({'file': str(path), 'line': number, 'text': line[:500]})
    eval_path = ROOT / 'datasets/v2-0930/tasks' / task / 'tests/eval.sh'
    if flags['git_apply_missing_source'] and eval_path.exists() and 'patch --batch' not in eval_path.read_text():
        flags['patch_apply_failed_without_fallback'] = 1
        samples['patch_apply_failed_without_fallback'] = samples['git_apply_missing_source']
    def code(name):
        path = directory / 'verifier' / name
        try:
            return int(path.read_text().strip())
        except (OSError, ValueError):
            return None
    raw, effective = code('raw-eval-exit-code.txt'), code('eval-exit-code.txt')
    if raw is not None and effective is not None and raw != effective:
        flags['exit_code_override'] = 1
    if reward is not None and effective is not None and (reward == 1) != (effective == 0):
        flags['reward_exit_inconsistency'] = 1
    return {'flags': dict(flags), 'evidence': dict(samples), 'raw_exit': raw, 'effective_exit': effective,
            'patch_installation_unreliable': bool(PATCH_UNRELIABLE.intersection(flags))}


def agent(directory, kind, expected_model):
    info = {'tools': collections.Counter(), 'tool_errors': collections.Counter(),
            'terminal': None, 'api_errors': [], 'model_mismatches': [], 'mcp_nonempty': False,
            'malformed_event_lines': 0, 'transport_warnings': [], 'native_protocol_errors': [],
            'native_contexts': [], 'native_trajectory_files': 0, 'shell_calls': 0, 'edit_calls': 0}
    path = directory / 'agent' / ('codex.txt' if kind == 'codex' else 'claude-code.txt')
    calls = {}
    if path.exists():
        with path.open(errors='replace') as handle:
            for number, line in enumerate(handle, 1):
                try:
                    event = json.loads(line)
                except ValueError:
                    if line.lstrip().startswith('{'):
                        info['malformed_event_lines'] += 1
                    if re.match(r'^\d{4}-\d\d-\d\dT', line) and re.search(r'(?i)(websocket|stream disconnect|error sending request|reconnect|rate.limit|code.mode.*(?:fail|unavailable))', line):
                        info['transport_warnings'].append({'line': number, 'text': line.strip()[:350]})
                    continue
                if not isinstance(event, dict):
                    continue
                typ = event.get('type')
                if kind == 'claude':
                    if typ == 'system' and event.get('subtype') == 'init':
                        info['mcp_nonempty'] |= bool(event.get('mcp_servers'))
                        if event.get('model') != expected_model:
                            info['model_mismatches'].append(event.get('model'))
                    if typ == 'result':
                        info['terminal'] = {k: event.get(k) for k in ['subtype', 'is_error', 'num_turns', 'terminal_reason', 'errors']}
                        if str(event.get('result', '')).startswith('API Error:'):
                            info['api_errors'].append(event['result'][:500])
                    message = event.get('message') or {}
                    if not isinstance(message, dict):
                        continue
                    content = message.get('content')
                    for block in content if isinstance(content, list) else []:
                        if not isinstance(block, dict):
                            continue
                        if block.get('type') == 'tool_use':
                            name = block.get('name', 'unknown'); calls[block.get('id')] = name
                            info['tools'][name] += 1
                            info['shell_calls'] += name == 'Bash'
                            info['edit_calls'] += name in ['Edit', 'Write', 'MultiEdit', 'NotebookEdit']
                        elif block.get('type') == 'tool_result' and block.get('is_error'):
                            name = calls.get(block.get('tool_use_id'), 'unknown')
                            info['tool_errors'][name] += 1
                else:
                    item = event.get('item') or {}; item = item if isinstance(item, dict) else {}
                    if typ in ['turn.completed', 'turn.failed']:
                        info['terminal'] = {'type': typ, 'error': event.get('error')}
                    if typ in ['error', 'turn.failed'] or item.get('type') == 'error':
                        info['api_errors'].append(str(event)[:650])
                    if typ == 'item.completed':
                        name = item.get('type', 'unknown'); info['tools'][name] += 1
                        info['shell_calls'] += name == 'command_execution'
                        info['edit_calls'] += name == 'file_change'
                        if item.get('status') == 'failed':
                            info['tool_errors'][name] += 1
    native_files = list((directory / 'agent' / 'sessions').rglob('*.jsonl'))
    info['native_trajectory_files'] = len(native_files)
    if kind == 'codex':
        for path in native_files:
            first_context = None
            for event in events(path):
                payload = event.get('payload') or {}
                if not isinstance(payload, dict):
                    continue
                if event.get('type') == 'turn_context' and first_context is None:
                    first_context = {k: payload.get(k) for k in ['model', 'effort']}
                    info['native_contexts'].append(first_context)
                    if first_context != {'model': expected_model, 'effort': 'high'}:
                        info['model_mismatches'].append(first_context)
                if event.get('type') == 'response_item' and payload.get('type') in ['custom_tool_call_output', 'function_call_output']:
                    output = payload.get('output', '')
                    if isinstance(output, str) and re.match(r'(?i)^(Script error:|Error parsing (?:function|JSON)|failed to spawn code.mode|Invalid (?:tool|function)|Unknown tool)', output):
                        info['native_protocol_errors'].append(output[:500])
    info['tools'] = dict(info['tools']); info['tool_errors'] = dict(info['tool_errors'])
    return info


def cause(result, agent_info):
    ex = result.get('exception_info') or {}
    if not ex:
        return None
    msg = ex.get('exception_message', '')
    terminal = agent_info.get('terminal') or {}
    if terminal.get('subtype') == 'error_max_turns':
        return 'max_turns_300'
    if 'cannot execute: required file not found' in msg:
        return 'native_cli_cannot_execute'
    if re.search(r'\bKilled\s+\|\s+claude', msg):
        return 'agent_killed_confirmed_oom_in_prior_kernel_audit'
    if ex.get('exception_type') == 'AgentTimeoutError':
        return 'agent_timeout_7200s'
    return ex.get('exception_type', 'unknown')


def summarize(records):
    counts = collections.Counter(); verifiers = collections.Counter(); agent_flags = collections.Counter(); causes = collections.Counter(); passed_flags = collections.Counter()
    for r in records:
        counts['tasks'] += 1; counts['exceptions'] += bool(r['exception_type'])
        counts['normal'] += not bool(r['exception_type']); counts['reward_present'] += r['reward'] is not None
        counts['raw_pass'] += r['reward'] == 1
        counts['native_trajectory_present'] += bool(r['agent']['native_trajectory_files'])
        if r['cause']: causes[r['cause']] += 1
        for flag in r['verifier']['flags']:
            verifiers[flag] += 1
            if r['reward'] == 1: passed_flags[flag] += 1
        if r['verifier']['patch_installation_unreliable']:
            counts['patch_installation_unreliable'] += 1
            counts['raw_pass_with_patch_problem'] += r['reward'] == 1
        for flag in ['api_errors', 'transport_warnings', 'native_protocol_errors', 'model_mismatches', 'mcp_nonempty', 'malformed_event_lines']:
            agent_flags[flag] += bool(r['agent'][flag])
        agent_flags['no_shell_calls'] += not bool(r['agent']['shell_calls'])
        agent_flags['no_recorded_edit_tool'] += not bool(r['agent']['edit_calls'])
        terminal = r['agent']['terminal'] or {}
        agent_flags['terminal_success'] += terminal.get('type') == 'turn.completed' or (terminal.get('subtype') == 'success' and terminal.get('is_error') is False)
        if not r['exception_type'] and (terminal.get('is_error') or terminal.get('type') == 'turn.failed'):
            agent_flags['terminal_error_without_harbor_exception'] += 1
        counts['raw_pass_with_exception'] += r['reward'] == 1 and bool(r['exception_type'])
    return {'counts': dict(counts), 'causes': dict(causes), 'verifier_flags': dict(verifiers),
            'pass_verifier_flags': dict(passed_flags), 'agent_flags': dict(agent_flags)}


def main():
    report = {'created_at': datetime.now(timezone.utc).isoformat(), 'scope': 'Qwen, GLM, Kimi main plus network recovery; Codex Luna; separate ongoing 32 GiB retries',
              'limitations': ['Verifier flags are log indicators, not a proof of all final test-tree contents.',
                              'No recorded edit tool does not imply an empty patch: shell commands can modify code.',
                              'Existing trials did not export a final repository diff; exact final patch reconstruction is not certified.'],
              'models': {}, 'oom32g': {}}
    manifest = json.loads((BASE / 'manifest.json').read_text())
    sources = []
    for model in manifest['models']:
        if 'deepseek' in model['model']:
            continue
        selected = load_job(Path(model['job_dir']))
        selected.update(load_job(ROOT / 'jobs' / (model['job_name'] + '-network-recovery')))
        sources.append((model['model'], 'claude', selected))
    manifest = json.loads((ROOT / 'campaigns/v2-0930-codex-gpt-6-luna-high/manifest.json').read_text())
    sources.append(('gpt-6-luna', 'codex', load_job(Path(manifest['job_dir']))))
    for model, kind, selected in sources:
        assert len(selected) == 82
        records = []
        for task, (directory, result) in sorted(selected.items()):
            reward = ((result.get('verifier_result') or {}).get('rewards') or {}).get('reward')
            agent_info = agent(directory, kind, model)
            records.append({'task': task, 'trial_dir': str(directory), 'reward': reward,
                            'exception_type': (result.get('exception_info') or {}).get('exception_type'),
                            'cause': cause(result, agent_info), 'agent': agent_info,
                            'verifier': verifier(directory, reward, task)})
        summary = summarize(records)
        report['models'][model] = {'summary': summary, 'records': records}
        print(model, json.dumps(summary), flush=True)
    manifest = json.loads((ROOT / 'campaigns/v2-0930-oom32g-once/manifest.json').read_text())
    for model in manifest['models']:
        path = Path(model['job_dir']); result = json.loads((path / 'result.json').read_text())
        report['oom32g'][model['model']] = {'job_dir': str(path), 'finished_at': result.get('finished_at'),
                                          'stats': {k: v for k, v in result.get('stats', {}).items() if k != 'evals'}}
    directory = ROOT / 'diagnostics' / ('v2-0930-four-model-health-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
    directory.mkdir(parents=True)
    output = directory / 'report.json'
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print('REPORT_PATH', output, flush=True)
    print('OOM32G', json.dumps(report['oom32g']), flush=True)


if __name__ == '__main__':
    main()
