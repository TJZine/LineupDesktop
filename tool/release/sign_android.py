#!/usr/bin/env python3
"""Prepare, sign and verify an Android candidate using protected workflow source."""

import argparse
import base64
import binascii
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

# Isolated Python ignores the script directory. Import only from this reviewed checkout.
sys.path.insert(0, str(Path(__file__).resolve().parent))
import verify


APPLICATION = 'com.tjzine.lineup'
UNSIGNED = 'lineup-unsigned-aligned.apk'
FINAL = 'lineup-final.apk'
MANIFEST = 'input-manifest.txt'
CI_WORKFLOW = '.github/workflows/ci.yml'


def positive_id(value):
    if not re.fullmatch(r'[1-9][0-9]{0,19}', value):
        raise argparse.ArgumentTypeError('expected a positive numeric ID')
    return int(value)


def check_hex(value, length):
    verify.require(re.fullmatch(rf'[0-9a-f]{{{length}}}', value) is not None,
                   f'expected {length} lowercase hexadecimal characters')


def verify_apk(args, manifest, apk, digest, certificate=None):
    verify.verify_apk(argparse.Namespace(
        apk=apk, sha256=digest, build_tools=args.build_tools,
        package=manifest['application'], version_code=manifest['version_code'],
        version_name=manifest['version_name'], certificate=certificate,
    ))


def prepare(args):
    check_hex(args.source_sha, 40)
    check_hex(args.workflow_sha, 40)
    check_hex(args.certificate, 64)
    run, artifact, zip_digest = verify.github_ci(
        args.repo, args.source_sha, args.ci_run, args.ci_attempt, args.artifact, CI_WORKFLOW,
    )
    # CI's push trigger selects branches only. A manually dispatched run with
    # head_branch=main could instead have used a tag named main.
    verify.require(run.get('head_branch') == 'main' and run.get('event') == 'push',
                   'CI must run on a main branch push')
    verify.require(artifact.get('name') == f'android-unsigned-{args.source_sha}',
                   'CI artifact is not the Android unsigned candidate')
    verify.require(type(artifact.get('size_in_bytes')) is int and
                   0 < artifact['size_in_bytes'] <= 2 * 1024**3, 'invalid CI artifact size')

    root = f'repos/{args.repo}'
    comparison = json.loads(verify.run(
        'gh', 'api', f'{root}/compare/{args.source_sha}...{args.workflow_sha}',
    ))
    verify.require(comparison.get('merge_base_commit', {}).get('sha') == args.source_sha,
                   'CI source is not in the protected workflow revision history')
    # Read the version as data at the selected source SHA. Application ID is the
    # fixed Android update identity. Never fetch or run source build logic.
    pubspec = verify.run('gh', 'api', '-H', 'Accept: application/vnd.github.raw+json',
                         f'{root}/contents/pubspec.yaml?ref={args.source_sha}')
    versions = re.findall(r'^version: ([0-9]+\.[0-9]+\.[0-9]+)\+([1-9][0-9]*)$',
                          pubspec, re.MULTILINE)
    verify.require(len(versions) == 1 and len(re.findall(r'^version\s*:', pubspec, re.M)) == 1,
                   'reviewed pubspec must declare one Android release version and build number')
    version_name, version_code = versions[0]

    args.work_dir.mkdir(mode=0o700)
    archive = args.work_dir / 'ci-artifact.zip'
    with archive.open('xb') as stream:
        subprocess.run(['gh', 'api', f'{root}/actions/artifacts/{args.artifact}/zip'],
                       stdout=stream, stderr=subprocess.PIPE, check=True)
    verify.check_digest(archive, zip_digest)
    inputs = args.work_dir / 'input'
    verify.inspect_zip(archive, inputs)
    apk = inputs / UNSIGNED
    manifest = {
        'repository': args.repo,
        'workflow_sha': args.workflow_sha,
        'signing_run': args.signing_run,
        'signing_attempt': args.signing_attempt,
        'source_sha': args.source_sha,
        'ci_workflow': CI_WORKFLOW,
        'ci_run': args.ci_run,
        'ci_attempt': args.ci_attempt,
        'artifact_id': args.artifact,
        'ci_zip_sha256': zip_digest,
        'unsigned_apk_sha256': verify.sha256(apk),
        'application': APPLICATION,
        'version_name': version_name,
        'version_code': version_code,
        'certificate_sha256': args.certificate,
    }
    verify_apk(args, manifest, apk, manifest['unsigned_apk_sha256'])
    path = args.work_dir / MANIFEST
    path.write_text(''.join(f'{key}={value}\n' for key, value in manifest.items()), encoding='ascii')
    if args.manifest_sha256 is not None:
        verify.check_digest(path, args.manifest_sha256)


def approved_manifest(args):
    path = args.work_dir / MANIFEST
    verify.check_digest(path, args.manifest_sha256)
    return dict(line.split('=', 1) for line in path.read_text(encoding='ascii').splitlines())


def sign(args):
    manifest = approved_manifest(args)
    apk = args.work_dir / 'input' / UNSIGNED
    verify.check_digest(apk, manifest['unsigned_apk_sha256'])
    output = args.work_dir / FINAL
    verify.require(not output.exists(), 'signed candidate already exists')

    encoded = os.environ.pop('ANDROID_KEYSTORE_BASE64', '')
    alias = os.environ.pop('ANDROID_KEY_ALIAS', '')
    password_names = ('ANDROID_KEYSTORE_PASSWORD', 'ANDROID_KEY_PASSWORD')
    passwords = {name: os.environ.pop(name, '') for name in password_names}
    verify.require(encoded and alias and all(passwords.values()), 'missing Android signing secrets')
    try:
        key_bytes = base64.b64decode(encoded, validate=True)
    except (binascii.Error, ValueError):
        raise ValueError('Android keystore secret is not valid base64') from None
    verify.require(key_bytes, 'Android keystore secret is empty')

    signer = Path(args.build_tools).resolve(strict=True) / 'apksigner'
    with tempfile.TemporaryDirectory(prefix='keystore-', dir=args.work_dir) as temporary:
        key = Path(temporary) / 'release.keystore'
        with os.fdopen(os.open(key, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600), 'wb') as stream:
            stream.write(key_bytes)
        # Keep passwords in the apksigner environment, and suppress diagnostics
        # from the key-handling command in case a provider includes secret data.
        result = subprocess.run([
            str(signer), 'sign', '--ks', str(key), '--ks-key-alias', alias,
            '--ks-pass', f'env:{password_names[0]}', '--key-pass', f'env:{password_names[1]}',
            '--v4-signing-enabled', 'false', '--out', str(output), str(apk),
        ], env=dict(os.environ, **passwords), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        verify.require(result.returncode == 0, 'apksigner signing failed')


def finalize(args):
    manifest = approved_manifest(args)
    apk = args.work_dir / FINAL
    digest = verify.sha256(apk)
    verify_apk(args, manifest, apk, digest, manifest['certificate_sha256'])

    candidate = args.work_dir / 'candidate'
    candidate.mkdir(mode=0o700)
    apk.rename(candidate / FINAL)
    shutil.copyfile(args.work_dir / MANIFEST, candidate / MANIFEST)
    (candidate / f'{FINAL}.sha256').write_text(f'{digest}  {FINAL}\n', encoding='ascii')
    (candidate / 'signing-evidence.txt').write_text(
        f'approved_manifest_sha256={args.manifest_sha256}\n'
        f'final_apk_sha256={digest}\n', encoding='ascii',
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    for action in (prepare, sign, finalize):
        command = commands.add_parser(action.__name__)
        command.set_defaults(action=action)
        command.add_argument('--work-dir', required=True, type=Path)
        command.add_argument('--build-tools', required=True, type=Path)
        command.add_argument('--manifest-sha256', required=action is not prepare)
        if action is prepare:
            for name in ('repo', 'source-sha', 'workflow-sha', 'certificate'):
                command.add_argument(f'--{name}', required=True)
            for name in ('ci-run', 'ci-attempt', 'artifact', 'signing-run', 'signing-attempt'):
                command.add_argument(f'--{name}', required=True, type=positive_id)
    args = parser.parse_args()
    args.action(args)


if __name__ == '__main__':
    # The workflow passes only fixed paths under runner-owned scratch storage.
    os.umask(0o077)
    try:
        main()
    except (KeyError, OSError, RuntimeError, ValueError, subprocess.CalledProcessError,
            zipfile.BadZipFile) as error:
        sys.exit(f'Android signing workflow failed: {error}')
