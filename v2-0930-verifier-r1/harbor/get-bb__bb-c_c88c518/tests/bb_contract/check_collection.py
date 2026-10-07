#!/usr/bin/env python3
"""Confirm the unchanged 29 canonical assertions actually passed in four files."""
from pathlib import Path
import json
import sys

expected = json.loads((Path(__file__).parent / 'expected-nodeids.json').read_text())
result = json.loads(Path(sys.argv[1]).read_text())
assert result['success'] is True
assert result['numTotalTests'] == result['numPassedTests'] == 29
assert result['numFailedTests'] == result['numPendingTests'] == result.get('numTodoTests', 0) == 0
assert result['numFailedTestSuites'] == result['numPendingTestSuites'] == 0
assert len(result['testResults']) == 4
actual = {}
for suite in result['testResults']:
    name = str(Path(suite['name']).relative_to('/testbed'))
    assert name in expected and name not in actual
    assert suite['status'] == 'passed'
    rows = suite['assertionResults']
    assert all(row['status'] == 'passed' and not row.get('failureMessages') for row in rows)
    actual[name] = sorted(row['fullName'] for row in rows)
assert actual == expected
print('SWEPM_BB_CANONICAL_COLLECTION=29_CASES_4_FILES')
