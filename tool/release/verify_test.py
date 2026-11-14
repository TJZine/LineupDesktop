"""Release boundary tests; optional SDK rehearsal uses only OS temporary files."""

import argparse
import contextlib
import copy
import hashlib
import io
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
import zipfile

import verify


class ReleaseChecks(unittest.TestCase):
    def test_run_source_attempt_and_digest_rejections(self):
        commit = 'a' * 40
        run = dict(id=123, run_attempt=2, head_sha=commit, status='completed',
                   conclusion='success', path='.github/workflows/ci.yml',
                   head_branch='main', event='push',
                   run_started_at='2026-11-09T10:00:00Z')
        artifact = dict(expired=False, digest='sha256:' + 'b' * 64,
                        workflow_run=dict(id=123, head_sha=commit),
                        created_at='2026-11-09T10:01:00Z')
        def check(r, a):
            return verify.check_run(r, a, commit, 123, 2, '.github/workflows/ci.yml')
        self.assertEqual(check(run, artifact), 'b' * 64)
        self.assertEqual(check(dict(run, event='workflow_dispatch'), artifact), 'b' * 64)
        for field, value in [('id', 456), ('head_sha', 'c' * 40), ('run_attempt', 1),
                             ('path', 'other.yml'), ('event', 'pull_request'),
                             ('head_branch', 'release'), ('conclusion', 'failure'),
                             ('status', 'in_progress')]:
            with self.subTest(run_field=field), self.assertRaises(ValueError):
                check(dict(run, **{field: value}), artifact)
        for field, value in [('expired', True), ('digest', None),
                             ('created_at', '2026-11-09T09:59:00Z'),
                             ('workflow_run', dict(id=456, head_sha=commit))]:
            with self.subTest(artifact_field=field), self.assertRaises(ValueError):
                check(run, dict(artifact, **{field: value}))

    def test_archive_paths_limits_corruption_and_no_execution(self):
        with tempfile.TemporaryDirectory(prefix='lineup-release-test-') as temporary:
            root = Path(temporary)
            archive = root / 'candidate.zip'
            sentinel = root / 'executed'
            with zipfile.ZipFile(archive, 'w') as z:
                z.writestr('app/candidate.sh', f'touch {sentinel}')
                z.writestr('app/data.txt', 'unchanged')
            digest = verify.sha256(archive)
            verify.check_digest(archive, digest)
            self.assertEqual(verify.inspect_zip(archive, root / 'extract')[0], 2)
            self.assertFalse(sentinel.exists())
            with self.assertRaises(FileExistsError):
                verify.inspect_zip(archive, root / 'extract')
            for limit in [dict(max_bytes=1), dict(max_entries=1)]:
                with self.assertRaises(ValueError):
                    verify.inspect_zip(archive, **limit)
            for member in ('app/program.exe', 'app/data.txt'):
                with zipfile.ZipFile(archive, 'w') as z:
                    z.writestr(member, 'changed PE or non-PE')
                with self.assertRaises(ValueError):
                    verify.check_digest(archive, digest)
            for name in ('../escape', '/absolute', 'C:/escape', 'app\\escape',
                         'app/./escape', 'app//escape', 'app/CON.txt', 'app/file.',
                         'app/COM¹.log', 'app/LPT²', 'app/CONOUT$', 'app/CON .txt'):
                with self.subTest(name=name):
                    with zipfile.ZipFile(archive, 'w') as z:
                        z.writestr(name, 'bad')
                    with self.assertRaises(ValueError):
                        verify.inspect_zip(archive)
            with zipfile.ZipFile(archive, 'w') as z:
                z.writestr('A', 'one')
                z.writestr('a', 'two')
            with self.assertRaises(ValueError):
                verify.inspect_zip(archive)
            entry = zipfile.ZipInfo('symlink')
            with zipfile.ZipFile(archive, 'w') as z:
                z.writestr('APP', 'file')
                z.writestr('app/child', 'collision')
            with self.assertRaises(ValueError):
                verify.inspect_zip(archive)
            entry.create_system = 3
            entry.external_attr = (stat.S_IFLNK | 0o777) << 16
            with zipfile.ZipFile(archive, 'w') as z:
                z.writestr(entry, '../outside')
            with self.assertRaises(ValueError):
                verify.inspect_zip(archive)
            archive.write_bytes(b'not a ZIP')
            with self.assertRaises(zipfile.BadZipFile):
                verify.inspect_zip(archive)
            with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_STORED) as z:
                z.writestr('data', b'original-content')
            archive.write_bytes(archive.read_bytes().replace(b'original-content', b'corrupt!-content'))
            with self.assertRaises(zipfile.BadZipFile):
                verify.inspect_zip(archive)


def _sdk_rehearsal_enabled():
    return bool(os.environ.get('LINEUP_RELEASE_TEST_SDK') or
                os.environ.get('LINEUP_RELEASE_TEST_REQUIRE_SDK'))


@unittest.skipUnless(_sdk_rehearsal_enabled(),
                     'set LINEUP_RELEASE_TEST_SDK and JAVA_HOME for disposable SDK signing rehearsal')
class AndroidRehearsal(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.environ.get('LINEUP_RELEASE_TEST_REQUIRE_SDK'):
            missing = [name for name in ('LINEUP_RELEASE_TEST_SDK', 'JAVA_HOME')
                       if not os.environ.get(name)]
            if missing:
                raise AssertionError('required SDK rehearsal environment is missing: ' +
                                     ', '.join(missing))
        super().setUpClass()

    def test_real_disposable_signing_and_identity_rejection(self):
        sdk = Path(os.environ['LINEUP_RELEASE_TEST_SDK'])
        tools = sdk / 'build-tools' / os.environ.get('LINEUP_RELEASE_TEST_BUILD_TOOLS', '36.0.0')
        platform = sdk / 'platforms' / os.environ.get('LINEUP_RELEASE_TEST_PLATFORM', 'android-36')
        java = Path(os.environ['JAVA_HOME']) / 'bin'
        with tempfile.TemporaryDirectory(prefix='lineup-signing-rehearsal-') as temporary:
            root = Path(temporary)
            manifest = root / 'AndroidManifest.xml'
            manifest.write_text('''<manifest xmlns:android="http://schemas.android.com/apk/res/android"
                package="com.example.lineup.rehearsal" android:versionCode="1" android:versionName="1.0">
                <uses-sdk android:minSdkVersion="24" android:targetSdkVersion="35"/>
                <application android:label="Disposable signing rehearsal"/>
                </manifest>''')
            unsigned = root / 'unsigned.apk'
            verify.run(str(tools / 'aapt'), 'package', '-f', '-M', str(manifest),
                       '-I', str(platform / 'android.jar'), '-F', str(root / 'unaligned.apk'))
            verify.run(str(tools / 'zipalign'), '-P', '16', '4',
                       str(root / 'unaligned.apk'), str(unsigned))
            args = argparse.Namespace(apk=unsigned, sha256=verify.sha256(unsigned),
                                      build_tools=str(tools), package='com.example.lineup.rehearsal',
                                      version_code='1', version_name='1.0', certificate=None)
            with contextlib.redirect_stdout(io.StringIO()):
                verify.verify_apk(args)
            # Public test-only password and disposable key; no production store is consulted.
            key = root / 'disposable.p12'
            verify.run(str(java / 'keytool'), '-genkeypair', '-keystore', str(key),
                       '-storepass', 'disposable-only', '-keypass', 'disposable-only',
                       '-alias', 'rehearsal', '-dname', 'CN=Disposable rehearsal',
                       '-keyalg', 'RSA', '-keysize', '2048', '-validity', '1', '-noprompt')
            cert = subprocess.run([str(java / 'keytool'), '-exportcert', '-keystore', str(key),
                                   '-storepass', 'disposable-only', '-alias', 'rehearsal'],
                                  check=True, capture_output=True).stdout
            signed = root / 'signed.apk'
            verify.run(str(tools / 'apksigner'), 'sign', '--ks', str(key), '--ks-key-alias',
                       'rehearsal', '--ks-pass', 'pass:disposable-only', '--out', str(signed), str(unsigned))
            args.apk = signed
            args.sha256 = verify.sha256(signed)
            args.certificate = hashlib.sha256(cert).hexdigest()
            with contextlib.redirect_stdout(io.StringIO()):
                verify.verify_apk(args)
            print(f'\nDisposable synthetic APK: unsigned sha256={verify.sha256(unsigned)}; '
                  f'final sha256={args.sha256}; certificate sha256={args.certificate}; '
                  'com.example.lineup.rehearsal 1.0 (1); temporary files auto-removed')
            for field, value in [('sha256', '0' * 64), ('certificate', '0' * 64),
                                 ('package', 'wrong.package'), ('version_code', '2'),
                                 ('version_name', '2.0'), ('certificate', None)]:
                changed = copy.copy(args)
                setattr(changed, field, value)
                with self.subTest(field=field), self.assertRaises(ValueError):
                    verify.verify_apk(changed)
            with zipfile.ZipFile(signed, 'a') as archive:
                archive.writestr('assets/tampered.txt', 'changed after signing')
            args.sha256 = verify.sha256(signed)  # Signature must fail even with a new digest.
            with self.assertRaises(subprocess.CalledProcessError):
                verify.verify_apk(args)


if __name__ == '__main__':
    unittest.main()
