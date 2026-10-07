#!/usr/bin/env python3
"""Check the bundled Go cache; --install explicitly copies it to the host path."""
import argparse
import hashlib
import importlib.util
from pathlib import Path, PurePosixPath
import shutil
import stat
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = ROOT / 'v2-0930-verifier-r1/support/enola-regexp2'
DEFAULT_TARGET = Path('/data/swepmv2-harbor-runtime/repairs/v2-0930-verifier-r1/full82_review/enola-payload-draft/full-controls')
PREFIX = 'github.com/dlclark/regexp2@v1.12.0/'
ZIP_SHA256 = 'dac93d7598b95a6a2c8b334f98078c77d22e29a85b4f73573591bcda65406636'
DOWNLOAD_FILES = ('v1.12.0.info', 'v1.12.0.mod', 'v1.12.0.zip', 'v1.12.0.ziphash', 'v1.12.0.lock')


def installed_check(target):
    path = ROOT / 'v2-0930-verifier-r1/harbor/TheYahya__enola-50/tests/check_enola_go_cache.py'
    spec = importlib.util.spec_from_file_location('enola_cache_check', path)
    checker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checker)
    checker.MODULE = target / 'regexp2-module'
    checker.DOWNLOAD = target / 'regexp2-download'
    checker.main()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--install', action='store_true', help='Copy 1.24 MB of bundled files; no network or package manager.')
    parser.add_argument('--check-installed', action='store_true')
    parser.add_argument('--target-root', type=Path, default=DEFAULT_TARGET, help='The task compose file expects the default path.')
    args = parser.parse_args()
    archive = BUNDLE / 'v1.12.0.zip'
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == ZIP_SHA256
    payloads = []
    with zipfile.ZipFile(archive) as source:
        for item in source.infolist():
            path = PurePosixPath(item.filename)
            assert not path.is_absolute() and '..' not in path.parts
            assert item.filename.startswith(PREFIX)
            assert not stat.S_ISLNK(item.external_attr >> 16)
            if item.is_dir():
                continue
            relative = item.filename[len(PREFIX):]
            payloads.append((args.target_root / 'regexp2-module' / relative, source.read(item)))
    for name in DOWNLOAD_FILES:
        payloads.append((args.target_root / 'regexp2-download' / name, (BUNDLE / name).read_bytes()))
    total = sum(len(data) for _, data in payloads)
    assert total < 2 * 1024 * 1024
    print('Bundled cache verified: %d files, %d bytes; target %s' % (len(payloads), total, args.target_root))
    if args.install:
        existing_parent = args.target_root
        while not existing_parent.exists():
            existing_parent = existing_parent.parent
        assert shutil.disk_usage(existing_parent).free > total + 16 * 1024 * 1024
        for destination, data in payloads:
            assert not destination.is_symlink(), str(destination)
            if destination.exists():
                assert destination.is_file() and destination.read_bytes() == data, 'Existing cache differs: ' + str(destination)
        for destination, data in payloads:
            if not destination.exists():
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(data)
        installed_check(args.target_root)
    elif args.check_installed:
        installed_check(args.target_root)


if __name__ == '__main__':
    main()
