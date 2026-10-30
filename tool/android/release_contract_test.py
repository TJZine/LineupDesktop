"""Portable negative controls for Android manifest and immutable notice checks."""
import importlib.util
import hashlib
import io
from pathlib import Path
import tempfile
import os
import shutil
import subprocess
import unittest
from unittest.mock import patch


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


generator = module('licenses', 'generate-licenses.py')
manifest = module('manifest', 'check-manifest.py')


class ReleaseContractTest(unittest.TestCase):
    def test_notice_check_fetches_current_terms_without_trusting_disk_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            url = 'https://example.invalid/terms.txt'
            terms = b'Current terms\n'
            cache = root / 'license-cache'
            cache.mkdir()
            cached = cache / (hashlib.sha256(url.encode()).hexdigest() + '.txt')
            cached.write_bytes(terms)
            modules = root / 'modules'
            report = []
            for artifact in ('first', 'second'):
                pom = modules / 'example' / artifact / '1' / f'{artifact}-1.pom'
                pom.parent.mkdir(parents=True)
                pom.write_text(
                    '<project xmlns="http://maven.apache.org/POM/4.0.0">'
                    '<licenses><license><name>Example terms</name>'
                    f'<url>{url}</url></license></licenses></project>')
                report.append(f'+--- example:{artifact}:1')
            output = root / 'assets'
            args = ('\n'.join(report), output, [modules], None, cache, 'fixture')
            with patch.object(generator.urllib.request, 'urlopen') as fetch:
                generator.generate(*args)
                fetch.assert_not_called()
            original = {p.relative_to(output): p.read_bytes()
                        for p in output.rglob('*') if p.is_file()}

            cases = (
                ('stale cache', b'Old terms\n', terms, None),
                ('invalid cache', b'\xff', terms, None),
                ('matching cache, changed upstream', terms, b'New upstream terms\n', 'notices differ'),
                ('empty upstream', terms, b'', 'invalid size'),
                ('oversized upstream', terms, b'x' * (generator.MAX_DOCUMENT_BYTES + 1), 'invalid size'),
                ('non-UTF-8 upstream', terms, b'\xff', 'not UTF-8'),
            )
            for name, cached_terms, upstream_terms, error in cases:
                with self.subTest(name=name):
                    cached.write_bytes(cached_terms)
                    with patch.object(generator.urllib.request, 'urlopen',
                                      return_value=io.BytesIO(upstream_terms)) as fetch:
                        if error:
                            with self.assertRaisesRegex(generator.GenerationError, error):
                                generator.generate(*args, check=True)
                        else:
                            generator.generate(*args, check=True)
                        fetch.assert_called_once()
                    self.assertEqual(cached_terms, cached.read_bytes())
                    self.assertEqual(original, {p.relative_to(output): p.read_bytes()
                                                for p in output.rglob('*') if p.is_file()})
            with patch.object(generator.urllib.request, 'urlopen', side_effect=OSError('offline')):
                with self.assertRaisesRegex(generator.GenerationError, 'Cannot fetch'):
                    generator.generate(*args, check=True)
            self.assertEqual([], list(root.glob('lineup-android-licenses-*')))

    def test_back_opt_in_is_required(self):
        root = Path(__file__).resolve().parents[2]
        xml = (root / 'android/app/src/main/AndroidManifest.xml').read_text()
        manifest.check(xml)
        for invalid in (xml.replace('android:enableOnBackInvokedCallback="true"', ''),
                        xml.replace('android:enableOnBackInvokedCallback="true"',
                                    'android:enableOnBackInvokedCallback="false"')):
            with self.assertRaisesRegex(ValueError, 'OnBackInvokedCallback'):
                manifest.check(invalid)

    def test_report_parsing_ignores_build_warnings(self):
        report = '\n'.join((
            'w: file:///opt/flutter/packages/flutter_tools/gradle/src/main/kotlin/Deeplink.kt:13:5 Deprecated',
            'releaseRuntimeClasspath - Runtime classpath of /release.',
            '+--- androidx.media3:media3-exoplayer:1.8.0',
            '|    \\--- androidx.annotation:annotation:1.3.0 -> 1.9.1',
            '\\--- project :flutter_secure_storage',
        ))
        self.assertEqual(generator.parse_report(report), [
            ('androidx.annotation', 'annotation', '1.9.1'),
            ('androidx.media3', 'media3-exoplayer', '1.8.0'),
        ])

    def test_gradle_report_preserves_caller_options_and_disables_daemon(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            wrapper = project / 'gradlew'
            wrapper.write_text('#!/bin/sh\nprintf "%s\\n" "$GRADLE_OPTS"\n')
            wrapper.chmod(0o755)
            configured = ('-Dorg.gradle.project.android.builder.sdkDownload=false '
                          '-Dorg.gradle.daemon=true')
            for inherited in (None, '', configured):
                with self.subTest(inherited=inherited), patch.dict(os.environ):
                    if inherited is None:
                        os.environ.pop('GRADLE_OPTS', None)
                    else:
                        os.environ['GRADLE_OPTS'] = inherited
                    report = generator.run_gradle_report(project, 'releaseRuntimeClasspath')
                    expected = (inherited or '').split() + ['-Dorg.gradle.daemon=false']
                    self.assertEqual(expected, report.split())
                    self.assertEqual(inherited, os.environ.get('GRADLE_OPTS'))

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
            wrapper.write_text('#!/bin/sh\necho "+--- io.flutter:flutter_embedding_release:1.0.0"\n')
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
            generator.generate('+--- io.flutter:flutter_embedding_release:1.0.0', assets, [], sdk, None, 'fixture')
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
            args = ('+--- io.flutter:flutter_embedding_release:1.0.0', output, [], sdk, None, 'fixture')
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
