#!/usr/bin/env python3
"""Require fresh, successful JUnit reports for each configured target class."""
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

folder = Path(sys.argv[1])
required = sys.argv[2:]
cutoff = Path('/logs/verifier/test-start.marker').stat().st_mtime
executed = failures = errors = 0
seen = set()
reports = []
for path in sorted(folder.glob('TEST-*.xml')):
    if path.stat().st_mtime < cutoff:
        continue
    root = ET.parse(path).getroot()
    cases = list(root.iter('testcase'))
    for case in cases:
        name = case.get('classname', '')
        if case.find('skipped') is not None:
            continue
        executed += 1
        failures += case.find('failure') is not None
        errors += case.find('error') is not None
        seen.update(target for target in required if name == target or name.startswith(target + '$'))
    reports.append(str(path))
result = dict(executed=executed, failures=failures, errors=errors,
              missing_classes=sorted(set(required) - seen), reports=reports)
Path('/logs/verifier/junit-evidence.json').write_text(json.dumps(result, indent=2) + '\n')
if not executed or failures or errors or result['missing_classes']:
    print('SWEPM_JUNIT_INVALID=' + json.dumps(result))
    sys.exit(2)
print('SWEPM_JUNIT_EXECUTED=' + str(executed))
