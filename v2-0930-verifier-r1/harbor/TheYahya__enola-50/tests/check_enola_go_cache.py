#!/usr/bin/env python3
"""Read-only integrity check of Enola's sole added offline Go dependency."""
import base64
import hashlib
import json
from pathlib import Path, PurePosixPath
import zipfile

MODULE = Path('/go/pkg/mod/github.com/dlclark/regexp2@v1.12.0')
DOWNLOAD = Path('/go/pkg/mod/cache/download/github.com/dlclark/regexp2/@v')
PREFIX = 'github.com/dlclark/regexp2@v1.12.0/'
SOURCE_H1 = 'h1:0j4c5qQmnC6XOWNjP3PIXURXN2gWx76rd3KvgdPkCz8='
MOD_H1 = 'h1:DHkYz0B9wPfa6wondMfaivmHpzrQ3v9q8cnmRbL6yW8='
ZIP_SHA256 = 'dac93d7598b95a6a2c8b334f98078c77d22e29a85b4f73573591bcda65406636'


def hash1(entries):
    digest = hashlib.sha256()
    for name, data in sorted(entries):
        assert '\n' not in name
        digest.update((hashlib.sha256(data).hexdigest() + '  ' + name + '\n').encode())
    return 'h1:' + base64.b64encode(digest.digest()).decode()


def main():
    archive_bytes = (DOWNLOAD / 'v1.12.0.zip').read_bytes()
    assert hashlib.sha256(archive_bytes).hexdigest() == ZIP_SHA256
    mod_bytes = (DOWNLOAD / 'v1.12.0.mod').read_bytes()
    assert hash1([('go.mod', mod_bytes)]) == MOD_H1
    assert (DOWNLOAD / 'v1.12.0.ziphash').read_text().strip() == SOURCE_H1
    assert (DOWNLOAD / 'v1.12.0.lock').is_file()
    assert json.loads((DOWNLOAD / 'v1.12.0.info').read_text())['Version'] == 'v1.12.0'
    entries = []
    with zipfile.ZipFile(DOWNLOAD / 'v1.12.0.zip') as archive:
        for item in archive.infolist():
            path = PurePosixPath(item.filename)
            assert not path.is_absolute() and '..' not in path.parts
            assert item.filename.startswith(PREFIX)
            if item.is_dir():
                continue
            installed = MODULE / item.filename[len(PREFIX):]
            assert installed.is_file() and not installed.is_symlink()
            contents = installed.read_bytes()
            assert contents == archive.read(item), item.filename
            entries.append((item.filename, contents))
    assert hash1(entries) == SOURCE_H1
    print('SWEPM_ENOLA_OFFLINE_CACHE=' + json.dumps({
        'module': 'github.com/dlclark/regexp2@v1.12.0',
        'files_checked': len(entries), 'module_h1': SOURCE_H1,
        'read_only_check': True, 'network_requests': 0,
    }, sort_keys=True))


if __name__ == '__main__':
    main()
