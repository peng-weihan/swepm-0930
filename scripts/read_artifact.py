#!/usr/bin/env python3
"""Print a text artifact, transparently handling .gz files."""
import gzip
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists() and path.with_name(path.name + '.gz').exists():
    path = path.with_name(path.name + '.gz')
opener = gzip.open if path.suffix == '.gz' else open
with opener(path, 'rt', encoding='utf-8') as stream:
    for line in stream:
        sys.stdout.write(line)
