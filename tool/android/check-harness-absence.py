#!/usr/bin/env python3
"""Check source, unshrunk classes, and APK contents for excluded E6 harness code.

This checks the source graph before shrinking as well as packaged bytes: an R8
optimization removing a currently unused observer is not a release boundary.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import zipfile

SOURCE_MARKERS = re.compile(r'\bE6[A-Za-z_]\w*|\bDebugSessionLogging\b|lineup/e6|--e6-|session-live')
BINARY_MARKERS = (
    b'com/tjzine/lineup/player/E6',
    b'com.tjzine.lineup.player.E6',
    b'com/tjzine/lineup/DebugSessionLogging',
    b'lineup/e6',
    b'--e6-observe',
    b'--e6-public-baseline',
    b'--e6-transport',
    b'session-live',
)


def raise_walk_error(error):
    raise error


def inspect(path, *, source=False):
    path = Path(path)
    if not path.exists():
        raise ValueError('input_missing')
    findings = []
    members = 0

    def check(name, data):
        nonlocal members
        members += 1
        if source:
            match = SOURCE_MARKERS.search(data.decode('utf-8'))
            if match:
                findings.append({'member': name, 'marker': match.group()})
        else:
            for marker in BINARY_MARKERS:
                if marker in data or marker.decode() in name:
                    findings.append({'member': name, 'marker': marker.decode()})

    if path.is_dir():
        tree_members = []
        for directory, dirnames, filenames in os.walk(
            path, onerror=raise_walk_error, followlinks=False
        ):
            for name in dirnames + filenames:
                member = Path(directory) / name
                mode = os.lstat(member).st_mode
                if stat.S_ISLNK(mode):
                    raise ValueError('invalid_input')
                if stat.S_ISREG(mode):
                    tree_members.append(member)
        for member in sorted(tree_members):
            if (
                member.suffix in ('.kt', '.java', '.xml', '.dart', '.py') if source
                else member.suffix in ('.class', '.dex', '.jar')
            ):
                if source and member.resolve() == Path(__file__).resolve():
                    continue
                if member.suffix == '.jar' and not source:
                    with zipfile.ZipFile(member) as archive:
                        for entry in archive.infolist():
                            if not entry.is_dir():
                                check(str(member.relative_to(path)) + ':' + entry.filename, archive.read(entry))
                else:
                    check(str(member.relative_to(path)), member.read_bytes())
    elif (not source and path.suffix.lower() in ('.apk', '.aab', '.jar')
          and not zipfile.is_zipfile(path)):
        raise ValueError('invalid_input')
    elif zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as archive:
            for member in archive.infolist():
                if not member.is_dir():
                    check(member.filename, archive.read(member))
    else:
        check(path.name, path.read_bytes())
    if members == 0:
        raise ValueError('no_checkable_inputs')
    return {'input': str(path), 'kind': 'source' if source else 'artifact',
            'membersChecked': members, 'findings': findings,
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, action='append', default=[])
    parser.add_argument('--artifact', type=Path, action='append', default=[])
    args = parser.parse_args()
    if not args.source and not args.artifact:
        parser.error('at least one source or artifact input is required')
    try:
        results = [inspect(p, source=True) for p in args.source] + [inspect(p) for p in args.artifact]
        clean = all(not item['findings'] for item in results)
        print(json.dumps({'harnessAbsent': clean, 'inputs': results}, indent=2))
        return 0 if clean else 1
    except (OSError, ValueError, zipfile.BadZipFile, UnicodeError):
        print(json.dumps({'harnessAbsent': False, 'fixedError': 'invalid_input'}))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
