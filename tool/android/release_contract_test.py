"""Portable negative controls for Android manifest and immutable notice checks."""
import importlib.util
from pathlib import Path
import tempfile
import os
import shutil
import subprocess
import unittest


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


generator = module('licenses', 'generate-licenses.py')
manifest = module('manifest', 'check-manifest.py')


class ReleaseContractTest(unittest.TestCase):
    def test_back_opt_in_is_required(self):
        root = Path(__file__).resolve().parents[2]
        xml = (root / 'android/app/src/main/AndroidManifest.xml').read_text()
        manifest.check(xml)
        for invalid in (xml.replace('android:enableOnBackInvokedCallback="true"', ''),
                        xml.replace('android:enableOnBackInvokedCallback="true"',
                                    'android:enableOnBackInvokedCallback="false"')):
            with self.assertRaisesRegex(ValueError, 'OnBackInvokedCallback'):
                manifest.check(invalid)

    def test_release_refuses_notice_drift_before_packaging(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tools = root / 'tool/android'
            tools.mkdir(parents=True)
            for name in ('build-release.sh', 'generate-licenses.py', 'check-manifest.py'):
                shutil.copy(Path(__file__).with_name(name), tools / name)
            android = root / 'android'
            android.mkdir()
            wrapper = android / 'gradlew'
            wrapper.write_text('#!/bin/sh\necho io.flutter:flutter_embedding_release:1.0.0\n')
            wrapper.chmod(0o755)
            source = android / 'app/src/main'
            source.mkdir(parents=True)
            (source / 'AndroidManifest.xml').write_text(
                '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
                '<application android:enableOnBackInvokedCallback="true"/></manifest>')
            (root / 'pubspec.yaml').write_text('version: 1.0.0+1\n')
            sdk = root / 'flutter'
            (sdk / 'bin').mkdir(parents=True)
            (sdk / 'LICENSE').write_text('SDK terms\n')
            flutter = sdk / 'bin/flutter'
            flutter.write_text("#!/bin/sh\necho '{\"frameworkVersion\":\"fixture\"}'\n")
            flutter.chmod(0o755)
            assets = source / 'assets'
            generator.generate('io.flutter:flutter_embedding_release:1.0.0', assets, [], sdk, None, 'fixture')
            notice = assets / 'licenses/flutter/Flutter-SDK-LICENSE.txt'
            notice.write_text('stale SDK terms\n')
            result = subprocess.run(['bash', str(tools / 'build-release.sh')],
                env={**os.environ, 'PATH': str(sdk / 'bin') + os.pathsep + os.environ['PATH']},
                capture_output=True, text=True)
            self.assertNotEqual(0, result.returncode)
            self.assertEqual('stale SDK terms\n', notice.read_text())
            self.assertIn('notices differ', result.stderr)

    def test_notice_check_detects_all_drift_without_writing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sdk = root / 'flutter'
            sdk.mkdir()
            (sdk / 'LICENSE').write_text('Exact SDK terms\n')
            output = root / 'assets'
            args = ('io.flutter:flutter_embedding_release:1.0.0', output, [], sdk, None, 'fixture')
            generator.generate(*args)
            def snapshot():
                return {p.relative_to(output): p.read_bytes() for p in output.rglob('*') if p.is_file()}
            original = snapshot()
            generator.generate(*args, check=True)
            self.assertEqual(original, snapshot())
            for kind in ('changed', 'missing', 'extra'):
                if output.exists():
                    shutil.rmtree(output)
                generator.generate(*args)
                target = output / 'licenses/flutter/Flutter-SDK-LICENSE.txt'
                if kind == 'changed':
                    target.write_text('stale terms\n')
                elif kind == 'missing':
                    target.unlink()
                else:
                    (output / 'unexpected.txt').write_text('stale document\n')
                before = snapshot()
                with self.assertRaisesRegex(generator.GenerationError, 'notices differ'):
                    generator.generate(*args, check=True)
                self.assertEqual(before, snapshot(), kind)
            self.assertEqual([], list(root.glob('lineup-android-licenses-*')))


if __name__ == '__main__':
    unittest.main()
