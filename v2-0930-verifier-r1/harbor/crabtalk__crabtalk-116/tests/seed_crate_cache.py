#!/usr/bin/env python3
"""Seed two reviewed, checksum-pinned registry archives; never change Cargo manifests."""
import hashlib
import json
import os
from pathlib import Path
import shutil

source = Path('/tests/dependency-cache')
expected = json.loads((source / 'manifest.json').read_text())
cargo = Path(os.environ.get('CARGO_HOME', str(Path.home() / '.cargo')))
caches = list((cargo / 'registry/cache').glob('*'))
assert len(caches) == 1, ('Review nonstandard registry cache layout', caches)
for name, sha in expected.items():
    assert Path(name).name == name and name.endswith('.crate')
    data = (source / name).read_bytes()
    assert len(data) <= 1024 * 1024 and hashlib.sha256(data).hexdigest() == sha
    target = caches[0] / name
    if target.exists():
        assert hashlib.sha256(target.read_bytes()).hexdigest() == sha
    else:
        shutil.copyfile(source / name, target)
    print('SWEPM_VERIFIED_CRATE_CACHE', name, len(data), sha)
