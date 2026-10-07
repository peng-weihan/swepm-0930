#!/usr/bin/env python3
"""Install the held-out schema test's dev dependencies without altering production deps."""
import argparse
import copy
import json
from pathlib import Path
import re
import tomllib


def encode(value):
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list):
        return '[' + ', '.join(encode(x) for x in value) + ']'
    if isinstance(value, dict):
        return '{ ' + ', '.join(json.dumps(k) + ' = ' + encode(v) for k, v in value.items()) + ' }'
    raise TypeError(type(value))


def prepare(text):
    before = tomllib.loads(text)
    dependencies = copy.deepcopy(before.get('dev-dependencies', {}))
    # Exactly the dependencies added by the original reference for the moved test.
    for name in ['anyhow', 'is_ci', 'serde_json']:
        dependencies.setdefault(name, {'workspace': True})
    tokio = dependencies.setdefault('tokio', {'workspace': True})
    if isinstance(tokio, str):
        tokio = dependencies['tokio'] = {'version': tokio}
    tokio['features'] = sorted(set(tokio.get('features', [])) | {'rt-multi-thread', 'macros'})
    kept = []
    inside = False
    for line in text.splitlines(keepends=True):
        if re.match(r'^\s*\[', line):
            inside = bool(re.match(r'^\s*\[dev-dependencies(?:\]|\.)', line))
        if not inside:
            kept.append(line)
    result = ''.join(kept).rstrip() + '\n\n[dev-dependencies]\n'
    result += ''.join(json.dumps(k) + ' = ' + encode(v) + '\n' for k, v in dependencies.items())
    after = tomllib.loads(result)
    assert {k: v for k, v in before.items() if k != 'dev-dependencies'} == \
           {k: v for k, v in after.items() if k != 'dev-dependencies'}
    return result, {'before': before.get('dev-dependencies', {}),
                    'after': after['dev-dependencies'], 'production_fields_unchanged': True}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('manifest', type=Path)
    parser.add_argument('record', type=Path)
    args = parser.parse_args()
    result, record = prepare(args.manifest.read_text())
    args.manifest.write_text(result)
    args.record.write_text(json.dumps(record, indent=2) + '\n')
