#!/usr/bin/env python3
"""Fail closed on missing/extra targets, skips, inconsistent counts or runtime errors.

This checks evidence completeness, not semantic correctness of failed test bodies.
The caller must also preserve the real Vitest exit status.
"""
import argparse
import json
from pathlib import Path, PurePosixPath
import sys


def inspect(report, runtime, project_root, targets):
    issues = []
    if project_root not in ('/testbed', '/testbed/mcp-server'):
        raise ValueError('unexpected project root')
    if not targets or len(set(targets)) != len(targets):
        raise ValueError('empty/duplicate targets')
    if any(not isinstance(t, str) or not t or PurePosixPath(t).is_absolute()
           or '..' in PurePosixPath(t).parts or str(PurePosixPath(t)) != t for t in targets):
        raise ValueError('invalid relative target')
    expected = {project_root + '/' + t: t for t in targets}
    if not isinstance(report, dict) or not isinstance(report.get('testResults'), list):
        raise ValueError('missing JSON testResults array')
    results = report['testResults']
    paths = [r.get('name') if isinstance(r, dict) else None for r in results]
    if any(not isinstance(p, str) for p in paths):
        raise ValueError('missing JSON file name')
    if len(set(paths)) != len(paths) or set(paths) != set(expected):
        issues.append('JSON files do not exactly equal all target paths')
    total = passed = failed = 0
    rows = []
    for r in results:
        assertions = r.get('assertionResults')
        if not isinstance(assertions, list) or not assertions:
            issues.append('target has missing/empty assertionResults: ' + r['name'])
            assertions = []
        statuses = [a.get('status') if isinstance(a, dict) else None for a in assertions]
        if any(s not in ('passed', 'failed') for s in statuses):
            issues.append('nonexecuted/unknown assertion status: ' + r['name'])
        p, f = statuses.count('passed'), statuses.count('failed')
        total += len(assertions)
        passed += p
        failed += f
        if r.get('message') or r.get('testExecError'):
            issues.append('file execution error: ' + r['name'])
        if r.get('status') != ('failed' if f else 'passed'):
            issues.append('file status disagrees with executed assertions: ' + r['name'])
        rows.append({'file': r['name'], 'total': len(assertions), 'passed': p, 'failed': f})
    for key, value in [('numTotalTests', total), ('numPassedTests', passed),
                       ('numFailedTests', failed), ('numPendingTests', 0), ('numTodoTests', 0)]:
        if type(report.get(key)) is not int or report[key] != value:
            issues.append(key + ' is missing or inconsistent')
    if total != passed + failed:
        issues.append('total does not equal executed passed plus failed')
    if type(report.get('success')) is not bool or report['success'] != (failed == 0):
        issues.append('JSON success disagrees with executed assertions')
    if report.get('unhandledErrors') or report.get('errors'):
        issues.append('JSON contains top-level errors')
    if not isinstance(runtime, dict):
        issues.append('runtime callback evidence missing')
        runtime = {}
    if type(runtime.get('schema_version')) is not int or runtime['schema_version'] != 2:
        issues.append('runtime schema version missing/unsupported')
    if runtime.get('helper_version') != 'agentteams-formal-runtime-v1':
        issues.append('runtime helper version missing/unsupported')
    runtime_paths = runtime.get('file_paths')
    if (not isinstance(runtime_paths, list) or any(not isinstance(p, str) for p in runtime_paths)
            or len(set(runtime_paths)) != len(runtime_paths) or set(runtime_paths) != set(expected)):
        issues.append('runtime callback file paths do not exactly equal target paths')
    for number, array in [('unhandled_errors_count', 'unhandled_errors'),
                          ('runtime_error_suites', 'suite_errors')]:
        count, errors = runtime.get(number), runtime.get(array)
        if type(count) is not int or count < 0 or not isinstance(errors, list) or count != len(errors):
            issues.append(number + ' missing or inconsistent with array')
        elif count:
            issues.append(number + ' is nonzero')
    for key in ['dangerously_ignore_unhandled_errors', 'pass_with_no_tests']:
        if runtime.get(key) is not False:
            issues.append(key + ' must explicitly be false')
    return {'valid_test_evidence': not issues, 'issues': issues, 'targets': rows,
            'actual_total': total, 'actual_passed': passed, 'actual_failed': failed,
            'runtime_error_suites': runtime.get('runtime_error_suites'),
            'unhandled_errors_count': runtime.get('unhandled_errors_count'),
            'manual_failure_classification_required': failed > 0}


def main():
    p = argparse.ArgumentParser()
    p.add_argument('report')
    p.add_argument('--runtime-report', required=True)
    p.add_argument('--project-root', required=True)
    p.add_argument('targets', nargs='+')
    a = p.parse_args()
    try:
        result = inspect(json.loads(Path(a.report).read_text()),
                         json.loads(Path(a.runtime_report).read_text()), a.project_root, a.targets)
    except (OSError, ValueError, TypeError, KeyError) as error:
        result = {'valid_test_evidence': False, 'error': str(error)}
    print(json.dumps(result, indent=2))
    return 0 if result['valid_test_evidence'] else 97


if __name__ == '__main__':
    sys.exit(main())
