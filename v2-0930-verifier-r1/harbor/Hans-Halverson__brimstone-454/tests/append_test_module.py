#!/usr/bin/env python3
"""Append one reviewed test module declaration, preserving candidate bytes."""
import hashlib
import json
from pathlib import Path


def main():
    root = Path('/testbed')
    target = root / 'src/js/runtime/mod.rs'
    test = root / 'src/js/runtime/swepm_common_shapes_internal_tests.rs'
    declaration = b'\n#[cfg(test)]\nmod swepm_common_shapes_internal_tests;\n'
    for path in (target, test):
        assert path.is_file() and not path.is_symlink(), path
        assert path.resolve().is_relative_to(root), path
    before = target.read_bytes()
    marker = b'mod swepm_common_shapes_internal_tests;'
    if marker in before:
        assert before.count(marker) == 1 and declaration in before
        after = before
    else:
        after = before + declaration
        target.write_bytes(after)
    assert target.read_bytes() == after and after.startswith(before)
    Path('/logs/verifier/test-module-hook.json').write_text(json.dumps({
        'path': str(target.relative_to(root)), 'operation': 'append_cfg_test_module',
        'original_bytes_preserved': True, 'appended_bytes': len(after) - len(before),
        'before_sha256': hashlib.sha256(before).hexdigest(),
        'after_sha256': hashlib.sha256(after).hexdigest(),
    }, indent=2) + '\n')


if __name__ == '__main__':
    main()
