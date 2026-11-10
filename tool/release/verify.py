#!/usr/bin/env python3
"""Installed release checks. Never import or execute candidate-provided code."""

import argparse
import datetime
import hashlib
import json
import re
import stat
import subprocess
import sys
import zipfile
from pathlib import Path, PurePosixPath


WINDOWS_RESERVED_NAMES = {'CON', 'PRN', 'AUX', 'NUL', 'CONIN$', 'CONOUT$'} | {
    f'{prefix}{digit}' for prefix in ('COM', 'LPT') for digit in '0123456789¹²³'
}


def sha256(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def check_digest(path, expected):
    require(re.fullmatch(r'[0-9a-fA-F]{64}', expected) is not None,
            'expected SHA-256 must be 64 hexadecimal characters')
    require(sha256(path) == expected.lower(), 'SHA-256 mismatch')


def run(*args):
    return subprocess.run(args, check=True, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE).stdout


def inspect_zip(path, destination=None, max_bytes=2 * 1024**3, max_entries=20000):
    """Bound decompression, reject special/ambiguous paths, verify every CRC.

    Extraction, when requested, is into a new directory only. No member is run.
    A rejected archive may leave a partial directory: discard it, never reuse it.
    """
    require(Path(path).stat().st_size <= max_bytes, 'archive input size limit exceeded')
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        require(0 < len(entries) <= max_entries, 'archive entry limit exceeded or empty')
        total = 0
        names = set()
        for entry in entries:
            name = entry.filename.rstrip('/')
            parts = name.split('/')
            require(name and not entry.filename.startswith('/') and '\\' not in name
                    and all(p not in ('', '.', '..') for p in parts)
                    and all(not re.search(r'[\x00-\x1f\x7f:<>"|?*]', p)
                            and not p.endswith((' ', '.')) for p in parts),
                    'unsafe archive path')
            require(all(p.split('.')[0].rstrip(' ').upper() not in
                        WINDOWS_RESERVED_NAMES for p in parts),
                    'reserved archive path')
            key = name.casefold()
            require(key not in names, 'duplicate archive path')
            names.add(key)
            kind = stat.S_IFMT(entry.external_attr >> 16)
            require(kind in (0, stat.S_IFREG, stat.S_IFDIR), 'special archive member')
            require(not entry.flag_bits & 1, 'encrypted archive member')
            total += entry.file_size
            require(total <= max_bytes, 'archive expanded size limit exceeded')
        files = {entry.filename.casefold() for entry in entries if not entry.is_dir()}
        for entry in entries:
            parts = entry.filename.rstrip('/').casefold().split('/')
            require(not any('/'.join(parts[:i]) in files for i in range(1, len(parts))),
                    'archive file/directory path collision')
        if destination is not None:
            destination = Path(destination)
            destination.mkdir(exist_ok=False)
        consumed = 0
        for entry in entries:
            if entry.is_dir():
                continue
            target = None
            if destination is not None:
                target_path = destination.joinpath(*PurePosixPath(entry.filename).parts)
                target_path.parent.mkdir(parents=True, exist_ok=True)
                target = target_path.open('xb')
            try:
                with archive.open(entry) as source:
                    while chunk := source.read(1024 * 1024):
                        consumed += len(chunk)
                        require(consumed <= max_bytes, 'archive expanded size limit exceeded')
                        if target:
                            target.write(chunk)
            finally:
                if target:
                    target.close()
    return len(entries), consumed


def check_run(run_info, artifact, commit, run_id, attempt, workflow):
    require(re.fullmatch(r'[0-9a-f]{40}', commit) is not None, 'full source commit required')
    require(run_info.get('id') == run_id and run_info.get('run_attempt') == attempt,
            'wrong CI run or attempt')
    require(run_info.get('head_sha') == commit and run_info.get('path') == workflow,
            'wrong CI source or workflow')
    require(run_info.get('status') == 'completed' and
            run_info.get('conclusion') == 'success', 'CI run did not succeed')
    require(not artifact.get('expired', True) and
            artifact.get('workflow_run', {}).get('id') == run_id and
            artifact.get('workflow_run', {}).get('head_sha') == commit,
            'artifact does not belong to selected source/run or expired')
    # Reruns retain the run ID; artifacts from a previous attempt must not pass.
    started = datetime.datetime.fromisoformat(run_info['run_started_at'].replace('Z', '+00:00'))
    created = datetime.datetime.fromisoformat(artifact['created_at'].replace('Z', '+00:00'))
    require(created >= started, 'artifact predates selected CI attempt')
    digest = artifact.get('digest', '')
    require(isinstance(digest, str) and re.fullmatch(r'sha256:[0-9a-f]{64}', digest) is not None,
            'GitHub artifact SHA-256 unavailable; do not trust candidate checksums instead')
    return digest.removeprefix('sha256:')


def github_ci(repo, commit, run_id, attempt, artifact_id, workflow):
    require(re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo) is not None,
            'expected OWNER/REPO')
    root = f'repos/{repo}/actions'
    run_info = json.loads(run('gh', 'api', f'{root}/runs/{run_id}'))
    artifact = json.loads(run('gh', 'api', f'{root}/artifacts/{artifact_id}'))
    require(artifact.get('id') == artifact_id, 'wrong artifact ID')
    require((run_info.get('repository') or {}).get('full_name', '').lower() == repo.lower()
            and (run_info.get('head_repository') or {}).get('full_name', '').lower() == repo.lower(),
            'CI run repository mismatch')
    digest = check_run(run_info, artifact, commit, run_id, attempt, workflow)
    return run_info, artifact, digest


def verify_ci(args):
    _, _, expected = github_ci(args.repo, args.commit, args.run, args.attempt,
                                args.artifact, args.workflow)
    # Hash the original API artifact ZIP, not gh run download's extracted files.
    # Metadata is independently fetched above, never read from inside the ZIP.
    check_digest(args.archive, expected)
    count, size = inspect_zip(args.archive, args.extract)
    print(f'GitHub run {args.run} attempt {args.attempt}; {args.commit}; '
          f'artifact {args.artifact}; sha256:{expected}; {count} entries; {size} bytes')


def verify_apk(args):
    check_digest(args.apk, args.sha256)
    inspect_zip(args.apk)
    tools = Path(args.build_tools).resolve(strict=True)
    run(str(tools / 'zipalign'), '-c', '-P', '16', '4', str(args.apk.resolve()))
    badging = run(str(tools / 'aapt'), 'dump', 'badging', str(args.apk.resolve()))
    package = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']*)'",
                        badging, re.MULTILINE)
    require(package is not None and package.groups() ==
            (args.package, args.version_code, args.version_name), 'APK application/version mismatch')
    signer = str(tools / 'apksigner')
    if args.certificate:
        require(re.fullmatch(r'[0-9a-fA-F]{64}', args.certificate) is not None,
                'expected certificate SHA-256 must be 64 hexadecimal characters')
        output = run(signer, 'verify', '--verbose', '--print-certs', str(args.apk.resolve()))
        certs = re.findall(r'^Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]+)$',
                           output, re.MULTILINE)
        require([c.lower() for c in certs] == [args.certificate.lower()],
                'APK signer certificate mismatch or unexpected multiple signers')
    else:
        with args.apk.open('rb') as stream:
            previous = b''
            while chunk := stream.read(1024 * 1024):
                require(b'APK Sig Block 42' not in previous + chunk,
                        'unsigned APK contains signing-block marker')
                previous = chunk[-16:]
        with zipfile.ZipFile(args.apk) as archive:
            require(not any(re.match(r'META-INF/.*\.(SF|RSA|DSA|EC)$', n, re.I)
                            for n in archive.namelist()), 'APK has JAR signature material')
        result = subprocess.run([signer, 'verify', '--verbose', str(args.apk.resolve())],
                                capture_output=True, text=True)
        # An arbitrary tool error is not evidence of an unsigned APK.
        require(result.returncode == 1 and 'DOES NOT VERIFY' in result.stderr and
                'Missing META-INF/MANIFEST.MF' in result.stderr,
                'APK is signed, malformed, or unsigned status could not be established')
    print(f'APK identity/alignment verified; sha256:{args.sha256.lower()}; '
          f'{args.package} {args.version_name} ({args.version_code}); '
          f'{"certificate " + args.certificate.lower() if args.certificate else "unsigned"}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    ci = commands.add_parser('ci', help='verify original GitHub artifact ZIP against API identity/digest')
    for name in ('repo', 'commit', 'workflow'):
        ci.add_argument('--' + name, required=True)
    for name in ('run', 'attempt', 'artifact'):
        ci.add_argument('--' + name, required=True, type=int)
    ci.add_argument('archive', type=Path)
    ci.add_argument('--extract', type=Path)
    ci.set_defaults(action=verify_ci)
    archive = commands.add_parser('archive', help='verify digest/ZIP without executing members')
    archive.add_argument('archive', type=Path)
    archive.add_argument('--sha256', required=True)
    archive.add_argument('--extract', type=Path)
    archive.set_defaults(action=lambda a: (check_digest(a.archive, a.sha256),
                                         print(inspect_zip(a.archive, a.extract))))
    apk = commands.add_parser('apk', help='verify expected APK identity; omit certificate for unsigned input')
    apk.add_argument('apk', type=Path)
    for name in ('sha256', 'build-tools', 'package', 'version-code', 'version-name'):
        apk.add_argument('--' + name, required=True)
    apk.add_argument('--certificate', help='expected authorized signer certificate SHA-256')
    apk.set_defaults(action=verify_apk)
    args = parser.parse_args()
    args.action(args)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError, zipfile.BadZipFile,
            RuntimeError, NotImplementedError) as error:
        sys.exit(f'Release verification failed: {error}')
