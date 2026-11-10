"""Exercise the hosted workflow's helper with fixture GitHub API and real SDK tools."""

import base64
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

import verify


@unittest.skipUnless(os.environ.get('LINEUP_RELEASE_TEST_SDK'),
                     'set LINEUP_RELEASE_TEST_SDK and JAVA_HOME for disposable SDK signing rehearsal')
class HostedSigningRehearsal(unittest.TestCase):
    def test_approval_binding_and_disposable_signing(self):
        sdk = Path(os.environ['LINEUP_RELEASE_TEST_SDK'])
        tools = sdk / 'build-tools' / os.environ.get('LINEUP_RELEASE_TEST_BUILD_TOOLS', '36.0.0')
        platform = sdk / 'platforms' / os.environ.get('LINEUP_RELEASE_TEST_PLATFORM', 'android-36')
        keytool = str(Path(os.environ['JAVA_HOME']) / 'bin/keytool')
        helper = Path(__file__).with_name('sign_android.py').resolve()

        with tempfile.TemporaryDirectory(prefix='lineup-hosted-signing-test-') as temporary:
            root = Path(temporary)
            xml = root / 'AndroidManifest.xml'
            xml.write_text('''<manifest xmlns:android="http://schemas.android.com/apk/res/android"
                package="com.tjzine.lineup" android:versionCode="4" android:versionName="1.2.3">
                <uses-sdk android:minSdkVersion="28" android:targetSdkVersion="35"/>
                <application android:label="Disposable signing rehearsal"/>
                </manifest>''')
            verify.run(str(tools / 'aapt'), 'package', '-f', '-M', str(xml),
                       '-I', str(platform / 'android.jar'), '-F', str(root / 'unaligned.apk'))
            unsigned = root / 'lineup-unsigned-aligned.apk'
            verify.run(str(tools / 'zipalign'), '-P', '16', '4', str(root / 'unaligned.apk'), str(unsigned))
            archive = root / 'candidate.zip'
            with zipfile.ZipFile(archive, 'w') as z:
                z.write(unsigned, unsigned.name)
                z.writestr('build-evidence.txt', 'disposable test data')

            key = root / 'disposable.p12'
            # These credentials are generated and used only inside this fixture.
            verify.run(keytool, '-genkeypair', '-keystore', str(key),
                       '-storepass', 'disposable-only', '-keypass', 'disposable-only',
                       '-alias', 'rehearsal', '-dname', 'CN=Disposable hosted rehearsal',
                       '-keyalg', 'RSA', '-keysize', '2048', '-validity', '1', '-noprompt')
            cert = subprocess.check_output([keytool, '-exportcert', '-keystore', str(key),
                                            '-storepass', 'disposable-only', '-alias', 'rehearsal'])
            cert_digest = hashlib.sha256(cert).hexdigest()
            secrets = dict(ANDROID_KEYSTORE_BASE64=base64.b64encode(key.read_bytes()).decode(),
                           ANDROID_KEY_ALIAS='rehearsal', ANDROID_KEYSTORE_PASSWORD='disposable-only',
                           ANDROID_KEY_PASSWORD='disposable-only')

            repo = 'TJZine/LineupDesktop'
            source = 'a' * 40
            workflow_sha = 'b' * 40
            endpoint = f'repos/{repo}'
            run_info = dict(id=123, run_attempt=2, head_sha=source, status='completed',
                            conclusion='success', path='.github/workflows/ci.yml',
                            head_branch='main', event='push', repository=dict(full_name=repo),
                            head_repository=dict(full_name=repo), run_started_at='2026-11-09T10:00:00Z')
            artifact = dict(id=456, name=f'android-unsigned-{source}', expired=False,
                            digest=f'sha256:{verify.sha256(archive)}', size_in_bytes=archive.stat().st_size,
                            workflow_run=dict(id=123, head_sha=source), created_at='2026-11-09T10:01:00Z')
            fixture = root / 'github.json'
            pubspec = 'version: 1.2.3+4\n'
            comparison = {'merge_base_commit': {'sha': source}}

            def github_fixture():
                fixture.write_text(json.dumps({
                    f'{endpoint}/actions/runs/123': json.dumps(run_info),
                    f'{endpoint}/actions/artifacts/456': json.dumps(artifact),
                    f'{endpoint}/actions/artifacts/456/zip': {'file': str(archive)},
                    f'{endpoint}/compare/{source}...{workflow_sha}': json.dumps(comparison),
                    f'{endpoint}/contents/pubspec.yaml?ref={source}': pubspec,
                }))

            # Only the transport is simulated. The helper parses the same API
            # responses and downloads, and invokes the real Android tools.
            gh = root / 'gh'
            gh.write_text(f'''#!{sys.executable}
import json, os, sys
from pathlib import Path
assert sys.argv[1] == 'api'
assert not any(name in os.environ for name in {tuple(secrets)!r})
response = json.loads(Path({str(fixture)!r}).read_text())[sys.argv[-1]]
sys.stdout.buffer.write(Path(response['file']).read_bytes() if isinstance(response, dict) else response.encode())
''')
            gh.chmod(0o700)
            env = {key: value for key, value in os.environ.items() if key not in secrets}
            env['PATH'] = f'{root}{os.pathsep}{env["PATH"]}'

            def run(action, work, *options, error=None, credentials=None):
                completed = subprocess.run([
                    sys.executable, '-I', '-B', str(helper), action, '--work-dir', str(work),
                    '--build-tools', str(tools), *options,
                ], env=dict(env, **(credentials or {})), capture_output=True, text=True)
                if error:
                    self.assertNotEqual(completed.returncode, 0)
                    self.assertIn(error, completed.stderr)
                else:
                    self.assertEqual(completed.returncode, 0, completed.stderr)

            def prepare(work, *options, certificate=cert_digest, error=None):
                github_fixture()
                run('prepare', work, '--repo', repo, '--source-sha', source,
                    '--workflow-sha', workflow_sha, '--ci-run', '123', '--ci-attempt', '2',
                    '--artifact', '456', '--signing-run', '789', '--signing-attempt', '1',
                    '--certificate', certificate, *options, error=error)

            for data, field, value, error in (
                (run_info, 'head_branch', 'dev/test', 'CI must run on a main branch push'),
                (run_info, 'event', 'workflow_dispatch', 'CI must run on a main branch push'),
                (run_info, 'head_repository', {'full_name': 'fork/LineupDesktop'}, 'repository mismatch'),
                (run_info, 'head_sha', 'c' * 40, 'wrong CI source'),
                (run_info, 'run_attempt', 3, 'wrong CI run or attempt'),
                (artifact, 'id', 457, 'wrong artifact ID'),
                (artifact, 'name', 'other-artifact', 'not the Android unsigned candidate'),
                (artifact, 'digest', 'sha256:' + '0' * 64, 'SHA-256 mismatch'),
                (comparison, 'merge_base_commit', {'sha': 'c' * 40}, 'not in the protected'),
            ):
                with self.subTest(field=field):
                    previous = data[field]
                    data[field] = value
                    prepare(root / f'invalid-{field}', error=error)
                    data[field] = previous
            pubspec = 'version: 1.2.4+4\n'
            prepare(root / 'wrong-version', error='APK application/version mismatch')
            pubspec = 'version: 1.2.3+4\n'

            preflight = root / 'preflight'
            prepare(preflight)
            manifest = preflight / 'input-manifest.txt'
            self.assertIn(f'unsigned_apk_sha256={verify.sha256(unsigned)}', manifest.read_text())
            approval = ('--manifest-sha256', verify.sha256(manifest))
            prepare(root / 'wrong-approval', '--manifest-sha256', '0' * 64, error='SHA-256 mismatch')
            # A different but valid re-fetched ZIP and matching API digest cannot
            # inherit approval from the original manifest.
            original_zip = archive.read_bytes()
            with zipfile.ZipFile(archive, 'a') as z:
                z.writestr('different-evidence.txt', 'changed')
            artifact.update(digest=f'sha256:{verify.sha256(archive)}', size_in_bytes=archive.stat().st_size)
            prepare(root / 'changed-zip', *approval, error='SHA-256 mismatch')
            archive.write_bytes(original_zip)
            artifact.update(digest=f'sha256:{verify.sha256(archive)}', size_in_bytes=archive.stat().st_size)

            approved = root / 'approved'
            prepare(approved, *approval)
            local_apk = approved / 'input' / unsigned.name
            local_apk.write_bytes(b'changed after approval')
            run('sign', approved, *approval, credentials=secrets, error='SHA-256 mismatch')
            self.assertFalse((approved / 'lineup-final.apk').exists())
            local_apk.write_bytes(unsigned.read_bytes())
            wrong_password = dict(secrets, ANDROID_KEYSTORE_PASSWORD='wrong-disposable-password')
            run('sign', approved, *approval, credentials=wrong_password, error='apksigner signing failed')
            self.assertFalse(list(approved.glob('keystore-*')))
            run('sign', approved, *approval, credentials=secrets)
            self.assertFalse(list(approved.glob('keystore-*')))
            run('finalize', approved, *approval)
            candidate = approved / 'candidate'
            self.assertEqual({item.name for item in candidate.iterdir()}, {
                'lineup-final.apk', 'lineup-final.apk.sha256', 'input-manifest.txt', 'signing-evidence.txt',
            })
            final_digest = verify.sha256(candidate / 'lineup-final.apk')
            self.assertEqual((candidate / 'lineup-final.apk.sha256').read_text(),
                             f'{final_digest}  lineup-final.apk\n')
            self.assertEqual(verify.sha256(candidate / manifest.name), approval[1])

            wrong_pin = root / 'wrong-pin'
            prepare(wrong_pin, certificate='0' * 64)
            wrong_pin_approval = ('--manifest-sha256', verify.sha256(wrong_pin / manifest.name))
            run('sign', wrong_pin, *wrong_pin_approval, credentials=secrets)
            run('finalize', wrong_pin, *wrong_pin_approval, error='APK signer certificate mismatch')
            self.assertFalse((wrong_pin / 'candidate').exists())
            print(f'\nHosted helper disposable rehearsal: manifest SHA-256 {approval[1]}, '
                  f'unsigned APK SHA-256 {verify.sha256(unsigned)}, signed APK SHA-256 {final_digest}, '
                  f'certificate SHA-256 {cert_digest}')
