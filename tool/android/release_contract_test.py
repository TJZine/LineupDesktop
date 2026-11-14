"""Portable negative controls for Android manifest and immutable notice checks."""
import importlib.util
import hashlib
import io
from pathlib import Path
import tempfile
import os
import re
import shutil
import subprocess
import unittest
import zipfile
import xml.etree.ElementTree as ET
from unittest.mock import patch


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


generator = module('licenses', 'generate-licenses.py')
manifest = module('manifest', 'check-manifest.py')


def commit_lockfile(root):
    (root / 'pubspec.lock').write_text('packages: pinned\n')
    git = ['git', '-C', str(root), '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid',
           '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null']
    subprocess.run([*git, 'init', '-q'], check=True)
    subprocess.run([*git, 'add', 'pubspec.lock'], check=True)
    subprocess.run([*git, 'commit', '-q', '-m', 'fixture'], check=True)


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

    def test_gradle_verifies_runtime_dependency_artifacts(self):
        root = Path(__file__).resolve().parents[2]
        gradle = (root / 'android/app/build.gradle.kts').read_text()
        metadata = root / 'android/gradle/verification-metadata.xml'
        self.assertTrue(metadata.is_file())
        verification = ET.parse(metadata).getroot()
        namespace = {'v': verification.tag.split('}')[0].removeprefix('{')}
        self.assertEqual('true', verification.findtext(
            'v:configuration/v:verify-metadata', namespaces=namespace))
        modules = (
            ('androidx.media3', 'media3-exoplayer'),
            ('androidx.media3', 'media3-exoplayer-hls'),
            ('androidx.media3', 'media3-datasource-okhttp'),
            ('androidx.media3', 'media3-ui'),
            ('com.squareup.okhttp3', 'okhttp'),
        )
        for group, module_name in modules:
            with self.subTest(module=module_name):
                coordinate = re.escape(f'{group}:{module_name}')
                dependency = re.search(rf'implementation\("{coordinate}:([^"]+)"\)', gradle)
                self.assertIsNotNone(dependency)
                version = dependency.group(1)
                component = verification.find(
                    f'v:components/v:component[@group="{group}"]'
                    f'[@name="{module_name}"][@version="{version}"]', namespace)
                self.assertIsNotNone(component)
                binary_names = {f'{module_name}-{version}.{ext}' for ext in ('jar', 'aar')}
                self.assertTrue(any(
                    artifact.get('name') in binary_names
                    and artifact.find('v:sha256', namespace) is not None
                    for artifact in component.findall('v:artifact', namespace)
                ), f'missing binary SHA-256 for {group}:{module_name}:{version}')

    def test_back_opt_in_is_required(self):
        root = Path(__file__).resolve().parents[2]
        xml = (root / 'android/app/src/main/AndroidManifest.xml').read_text()
        manifest.check(xml)
        for attribute in ('debuggable="true"', 'networkSecurityConfig="@xml/fixture"'):
            with self.subTest(attribute=attribute), self.assertRaises(ValueError):
                manifest.check_release(xml.replace('<application', f'<application android:{attribute}'))
        manifest.check_release(xml)
        for invalid in (xml.replace('android:enableOnBackInvokedCallback="true"', ''),
                        xml.replace('android:enableOnBackInvokedCallback="true"',
                                    'android:enableOnBackInvokedCallback="false"')):
            with self.assertRaisesRegex(ValueError, 'OnBackInvokedCallback'):
                manifest.check(invalid)

    def test_packaged_rules_bind_manifest_id_to_renamed_resource(self):
        root = Path(__file__).resolve().parents[2]
        source = (root / 'android/app/src/main/AndroidManifest.xml').read_text()
        xml = source.replace('@xml/data_extraction_rules', '@ref/0x7f110000')
        rules = (root / 'android/app/src/main/res/xml/data_extraction_rules.xml').read_text()
        table = ('    resource 0x7f110000 xml/data_extraction_rules\n'
                 '      () (file) res/4j.xml type=XML\n')
        with patch.object(manifest.subprocess, 'check_output',
                          side_effect=[xml, table, 'res/4j.xml\n', rules]) as run:
            manifest.check_packaged(Path('app.apk'), Path('analyzer'), Path('aapt2'))
            self.assertEqual('res/4j.xml', run.call_args.args[0][-2])
        for invalid_xml, invalid_table, invalid_rules in (
            (xml.replace('@ref/0x7f110000', '@ref/0x7f110001'), table, rules),
            (xml, table.replace('data_extraction_rules', 'other'), rules),
            (xml, table + table, rules),
            (xml, table + '      (v31) (file) res/other.xml type=XML\n', rules),
            (xml, table, rules.replace('path="."', 'path="partial"', 1)),
        ):
            with patch.object(manifest.subprocess, 'check_output',
                              side_effect=[invalid_xml, invalid_table, 'res/4j.xml', invalid_rules]):
                with self.assertRaises(ValueError):
                    manifest.check_packaged(Path('app.apk'), Path('analyzer'), Path('aapt2'))

    def test_rejects_fixture_bytes_at_any_apk_path(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = root / 'fixture.crt'
            fixture.write_bytes(b'test certificate')
            apk = root / 'app.apk'
            with zipfile.ZipFile(apk, 'w') as archive:
                archive.writestr('res/a', b'other bytes')
            manifest.reject_entry_bytes(fixture, apk)
            with zipfile.ZipFile(apk, 'a') as archive:
                archive.writestr('res/b', fixture.read_bytes())
            with self.assertRaises(ValueError):
                manifest.reject_entry_bytes(fixture, apk)

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

    def test_release_requires_reviewed_clean_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tools = root / 'tool/android'
            tools.mkdir(parents=True)
            shutil.copy(Path(__file__).with_name('build-release.sh'), tools)
            commit_lockfile(root)
            commit = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
            command = ['bash', str(tools / 'build-release.sh'), commit,
                       'https://github.com/example/lineup/actions/runs/1']
            # The script itself is an untracked build input.
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(0, result.returncode)
            self.assertIn('completely clean checkout', result.stderr)
            (root / 'pubspec.lock').write_text('packages: floated\n')
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(0, result.returncode)
            self.assertIn('completely clean checkout', result.stderr)
            command[-2] = '0' * 40
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(0, result.returncode)
            self.assertIn('full reviewed commit', result.stderr)

    def test_clean_release_reaches_toolchain_and_rejects_prior_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            scratch = Path(directory)
            root = scratch / 'source'
            tools = root / 'tool/android'
            tools.mkdir(parents=True)
            for name in ('build-release.sh', 'check-wrapper.py'):
                shutil.copy(Path(__file__).with_name(name), tools)
            source = Path(__file__).resolve().parents[2] / 'android'
            wrapper = module('positive_wrapper', 'check-wrapper.py')
            for name in wrapper.HASHES:
                target = root / 'android' / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy(source / name, target)
            (root / '.gitignore').write_text('build/\n')
            commit_lockfile(root)
            git = ['git', '-C', str(root), '-c', 'user.name=fixture',
                   '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false',
                   '-c', 'core.hooksPath=/dev/null']
            subprocess.run([*git, 'add', '.'], check=True)
            subprocess.run([*git, 'commit', '-q', '-m', 'clean release fixture'], check=True)
            commit = subprocess.check_output([*git, 'rev-parse', 'HEAD'], text=True).strip()
            bin_dir = scratch / 'bin'
            bin_dir.mkdir()
            dart = bin_dir / 'dart'
            dart.write_text('#!/bin/sh\necho TOOLCHAIN_REACHED\nexit 42\n')
            dart.chmod(0o755)
            command = ['bash', str(tools / 'build-release.sh'), commit,
                       'https://github.com/example/lineup/actions/runs/1']
            environment = {**os.environ, 'PATH': str(bin_dir) + os.pathsep + os.environ['PATH']}
            result = subprocess.run(command, env=environment, capture_output=True, text=True)
            self.assertEqual(42, result.returncode, result.stderr)
            self.assertIn('Official Gradle', result.stdout)
            self.assertIn('TOOLCHAIN_REACHED', result.stdout)
            (root / 'build').mkdir()
            result = subprocess.run(command, env=environment, capture_output=True, text=True)
            self.assertEqual(1, result.returncode)
            self.assertIn('prior Android build outputs', result.stderr)

    def test_official_wrapper_rejects_changed_bytes_and_distribution(self):
        wrapper = module('wrapper', 'check-wrapper.py')
        source = Path(__file__).resolve().parents[2] / 'android'
        wrapper.check(source)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in wrapper.HASHES:
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy(source / name, target)
            for name in wrapper.HASHES:
                target = root / name
                original = target.read_bytes()
                target.write_bytes(original.replace(b'17f277', b'000000') if name.endswith('.properties')
                                   else original + b'changed')
                with self.subTest(name=name), self.assertRaises(ValueError):
                    wrapper.check(root)
                target.write_bytes(original)
            wrapper.check(root)
            properties = root / 'gradle/wrapper/gradle-wrapper.properties'
            properties.write_text(properties.read_text() + '\ndistributionUrl=https://invalid.example/gradle.zip\n')
            with self.assertRaises(ValueError):
                wrapper.check(root)

    def test_resolved_dependency_reports_reject_affected_missing_and_multiple(self):
        dependencies = module('resolved', 'check-resolved-dependencies.py')
        report = ('+--- org.jetbrains.kotlin:kotlin-gradle-plugin:2.4.21\n'
                  '+--- com.android.tools.build:gradle:9.1.0\n'
                  '+--- com.google.guava:guava:31.1-android -> 33.7.2-android\n')
        dependencies.check(report)
        for invalid in (report.replace('2.4.21', '2.4.0'),
                        report.replace('33.7.2-android', '31.1-android'),
                        report.replace('com.android.tools.build:gradle', 'missing:gradle'),
                        report + '+--- org.jetbrains.kotlin:kotlin-gradle-plugin:2.4.0\n',
                        report + '+--- missing:artifact:1 FAILED\n'):
            with self.assertRaises(ValueError):
                dependencies.check(invalid)

    def test_unsigned_apk_rejects_both_signature_formats(self):
        unsigned = module('unsigned', 'check-unsigned-apk.py')
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / 'app.apk'
            with zipfile.ZipFile(apk, 'w') as archive:
                archive.writestr('classes.dex', b'fixture')
            unsigned.check(apk)
            with zipfile.ZipFile(apk, 'a') as archive:
                archive.writestr('META-INF/CERT.RSA', b'certificate')
            with self.assertRaisesRegex(ValueError, 'JAR signing'):
                unsigned.check(apk)
            with zipfile.ZipFile(apk, 'w') as archive:
                archive.writestr('classes.dex', b'fixture')
            data = apk.read_bytes()
            with zipfile.ZipFile(apk) as archive:
                offset = archive.start_dir
            # Insert an APK signing block and update the central directory offset.
            block = b'\x18' + b'\0' * 7 + b'\x18' + b'\0' * 7 + b'APK Sig Block 42'
            data = bytearray(data[:offset] + block + data[offset:])
            import struct
            eocd = data.rfind(b'PK\x05\x06')
            struct.pack_into('<I', data, eocd + 16, offset + len(block))
            apk.write_bytes(data)
            with self.assertRaisesRegex(ValueError, 'Signing Block'):
                unsigned.check(apk)

    def test_release_manifest_and_extraction_policy_negative_controls(self):
        root = Path(__file__).resolve().parents[2]
        xml = (root / 'android/app/src/main/AndroidManifest.xml').read_text()
        for name, value in (('allowBackup', 'false'), ('fullBackupContent', 'false'),
                            ('usesCleartextTraffic', 'false'),
                            ('dataExtractionRules', '@xml/data_extraction_rules')):
            for replacement in ('', f'android:{name}="invalid"'):
                invalid = xml.replace(f'android:{name}="{value}"', replacement)
                with self.subTest(name=name, replacement=replacement), self.assertRaises(ValueError):
                    manifest.check_release(invalid)
        rules = (root / 'android/app/src/main/res/xml/data_extraction_rules.xml').read_text()
        manifest.check_extraction_rules(rules)
        for mode in ('cloud-backup', 'device-transfer'):
            parsed = ET.fromstring(rules)
            for entry in parsed.find(mode):
                original = entry.get('path')
                entry.set('path', 'only-part')
                with self.assertRaises(ValueError):
                    manifest.check_extraction_rules(ET.tostring(parsed, encoding='unicode'))
                entry.set('path', original)
            parsed.remove(parsed.find(mode))
            with self.assertRaises(ValueError):
                manifest.check_extraction_rules(ET.tostring(parsed, encoding='unicode'))

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
