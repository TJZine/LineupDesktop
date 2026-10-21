#!/usr/bin/env python3
"""Portable parser/closure controls plus actual Dart hook with fake compiler IO."""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('assets', Path(__file__).with_name('native_assets.py'))
n = importlib.util.module_from_spec(spec)
spec.loader.exec_module(n)
ROOT = Path(__file__).resolve().parents[2]
DART = Path.home() / '.cache/lineup-flutter/3.47.7/flutter/bin/dart'


def thin(target=12, cpu=0x100000c, platform=1, kind=6):
    command = struct.pack('<6I', 0x32, 24, platform, target << 16, 27 << 16, 0)
    return struct.pack('<8I', 0xfeedfacf, cpu, 0 if cpu == 0x100000c else 3, kind, 1, len(command), 0, 0) + command


def dylib_command(name):
    value = name.encode() + b'\0'
    size = (24 + len(value) + 7) // 8 * 8
    return struct.pack('<6I', 0xc, size, 24, 0, 0, 0) + value + bytes(size - 24 - len(value))


def with_commands(data, *commands):
    header = list(struct.unpack_from('<8I', data))
    header[4] += len(commands)
    header[5] += sum(map(len, commands))
    return struct.pack('<8I', *header) + data[32:] + b''.join(commands)


class BundleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / 'Lineup.app'
        self.write('Contents/Info.plist', plistlib.dumps({'CFBundleExecutable': 'Lineup'}))
        self.write('Contents/MacOS/Lineup', thin(kind=2))
        self.asset = self.write('Contents/Frameworks/objective_c.framework/objective_c', thin())
        self.write('Contents/Frameworks/objective_c.framework/Resources/Info.plist', plistlib.dumps({
            'CFBundleIdentifier': 'io.flutter.flutter.native-assets.objective-c', 'CFBundleExecutable': 'objective_c'}))
        self.manifest = self.write('Contents/Frameworks/App.framework/Resources/flutter_assets/NativeAssetsManifest.json',
                                  json.dumps({'native-assets': {'macos_arm64': {n.ASSET: ['absolute', 'objective_c.framework/objective_c']}}}).encode())

    def write(self, name, data):
        path = self.app / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def test_good_then_newer_wrong_platform_architecture_and_missing_asset(self):
        n.bundle_closure(self.app)
        for data, reason in ((thin(13), 'newer macOS'), (thin(platform=2), 'platform'),
                             (thin(cpu=0x1000007), 'architecture'), (b'not Mach-O', 'Missing objective_c')):
            self.asset.write_bytes(data)
            with self.assertRaisesRegex(ValueError, reason): n.bundle_closure(self.app)
            self.asset.write_bytes(thin())
            n.bundle_closure(self.app)
        self.asset.unlink()
        with self.assertRaises((ValueError, OSError)): n.bundle_closure(self.app)

    def test_fat_slices_and_truncated_or_lying_headers(self):
        a, b = thin(), thin(13, cpu=0x1000007)
        fat = struct.pack('>II', 0xcafebabe, 2) + struct.pack('>5I', 0x100000c, 0, 48, len(a), 0) + struct.pack('>5I', 0x1000007, 3, 48 + len(a), len(b), 0) + a + b
        self.assertEqual([v['minimumOS'][0] for v in n.macho(fat)], [12, 13])
        self.asset.write_bytes(fat)
        with self.assertRaisesRegex(ValueError, 'newer macOS'): n.bundle_closure(self.app)
        for value in (fat[:40], fat[:48] + b'invalid', thin()[:40]):
            with self.assertRaises((ValueError, struct.error)): n.macho(value)

    def test_manifest_identity_and_escaping_symlink_fail_closed(self):
        original = self.manifest.read_bytes()
        self.manifest.write_text(original.decode().replace('package:objective_c/', 'package:other/'))
        with self.assertRaises(ValueError): n.bundle_closure(self.app)
        self.manifest.write_bytes(original)
        self.asset.unlink()
        self.asset.symlink_to(Path(self.temp.name) / 'external')
        with self.assertRaises((ValueError, OSError)): n.bundle_closure(self.app)

    def test_dependency_closure_and_unsupported_binary_types(self):
        self.asset.write_bytes(with_commands(thin(), dylib_command('@loader_path/peer.dylib')))
        with self.assertRaisesRegex(ValueError, 'Unresolved'): n.bundle_closure(self.app)
        peer = self.write('Contents/Frameworks/objective_c.framework/peer.dylib', thin())
        n.bundle_closure(self.app)
        peer.write_bytes(thin(13))
        with self.assertRaisesRegex(ValueError, 'newer macOS'): n.bundle_closure(self.app)
        peer.write_bytes(b'\xce\xfa\xed\xfe' + bytes(28))
        with self.assertRaisesRegex(ValueError, '32-bit'): n.bundle_closure(self.app)
        peer.unlink()
        self.asset.write_bytes(thin(kind=2))
        with self.assertRaisesRegex(ValueError, 'not a dylib'): n.bundle_closure(self.app)

    def test_current_hook_proof_matches_final_slice_and_rejects_stale_inputs(self):
        repository = (Path(self.temp.name) / 'repo').resolve()
        receipt_path = repository / '.dart_tool/hooks_runner/shared/objective_c/build/fixture/macos-12/lineup-objective-c-build.json'
        receipt_path.parent.mkdir(parents=True)
        raw = receipt_path.with_name('objective_c.dylib')
        compiler, sdk = repository / 'clang', repository / 'SDK'
        compiler.write_bytes(b'compiler identity')
        sdk.mkdir()
        (sdk / 'SDKSettings.json').write_bytes(b'sdk identity')
        # Match the identity retained through Flutter wrapping/stripping/signing.
        uuid = struct.pack('<II', 0x1b, 24) + bytes(range(16))
        segment = bytearray(152)
        struct.pack_into('<II', segment, 0, 0x19, len(segment))
        struct.pack_into('<I', segment, 64, 1)
        segment[72:78], segment[88:94] = b'__text', b'__TEXT'
        data = with_commands(thin(), uuid, bytes(segment))
        self.asset.write_bytes(data)
        raw.write_bytes(data)
        vendor = repository / n.VENDOR
        (vendor / 'hook').mkdir(parents=True)
        (vendor / 'src').mkdir()
        for name in ('hook/build.dart', 'pubspec.yaml', 'src/foreign.c'):
            (vendor / name).write_text(name)
        source_hashes = {name: n.sha(vendor / name) for name in ('hook/build.dart', 'pubspec.yaml', 'src/foreign.c')}
        workspace = repository / 'pubspec.yaml'
        workspace.write_text('fixture root configuration')
        inputs = {'toolchain': {'compilerSha256': n.sha(compiler), 'sdkSettingsSha256': n.sha(sdk / 'SDKSettings.json')},
                  'inputs': {'pubspec.yaml': n.sha(workspace), **{n.VENDOR + '/' + name: digest for name, digest in source_hashes.items()}}}
        configuration = {'user_defines': {'workspace_pubspec': {'defines': {'macos_target_version': 12}, 'base_path': str(repository)}},
                         'package_root': str(vendor), 'package_name': 'objective_c',
                         'config': {'extensions': {'code_assets': {'target_os': 'macos', 'target_architecture': 'arm64'}}}}

        receipt = {'architecture': 'arm64', 'packageRoot': str(repository / n.VENDOR), 'assetId': n.ASSET,
                   'compileFlags': ['-mmacos-version-min=12'], 'linkFlags': ['-mmacos-version-min=12'],
                   'asset': str(raw), 'compiler': str(compiler), 'sdk': str(sdk),
                   'schemaVersion': 2, 'rawAssetSha256': n.sha(raw),
                   'producingInputs': {**inputs['toolchain'], 'sources': source_hashes, 'configuration': configuration, 'workspacePubspecSha256': n.sha(workspace)}}
        receipt_path.write_text(json.dumps(receipt))
        with patch.object(n, 'project_inputs', return_value=inputs):
            self.assertIn('arm64', n.verify(repository, self.app, inputs)['hookBuilds'])
            with self.assertRaisesRegex(ValueError, 'inputs changed'): n.verify(repository, self.app, {})
            for tool in (compiler, sdk / 'SDKSettings.json'):
                original = tool.read_bytes()
                tool.write_bytes(original + b' replaced at the same path')
                changed = {**inputs, 'toolchain': {'compilerSha256': n.sha(compiler), 'sdkSettingsSha256': n.sha(sdk / 'SDKSettings.json')}}
                with patch.object(n, 'project_inputs', return_value=changed):
                    with self.assertRaisesRegex(ValueError, 'current hook proof'): n.verify(repository, self.app, changed)
                tool.write_bytes(original)
                self.assertIn('arm64', n.verify(repository, self.app, inputs)['hookBuilds'])

            original = workspace.read_bytes()
            workspace.write_bytes(b'changed root configuration')
            changed = {**inputs, 'inputs': {**inputs['inputs'], 'pubspec.yaml': n.sha(workspace)}}
            with patch.object(n, 'project_inputs', return_value=changed):
                with self.assertRaisesRegex(ValueError, 'current hook proof'): n.verify(repository, self.app, changed)
            workspace.write_bytes(original)
            self.assertIn('arm64', n.verify(repository, self.app, inputs)['hookBuilds'])
            source = vendor / 'src/foreign.c'
            original = source.read_bytes()
            source.write_bytes(b'new source at the same path')
            changed = {**inputs, 'inputs': {**inputs['inputs'], n.VENDOR + '/src/foreign.c': n.sha(source)}}
            with patch.object(n, 'project_inputs', return_value=changed):
                with self.assertRaisesRegex(ValueError, 'current hook proof'): n.verify(repository, self.app, changed)
            source.write_bytes(original)
            self.assertIn('arm64', n.verify(repository, self.app, inputs)['hookBuilds'])
            raw.write_bytes(data + b'changed non-text bytes')
            with self.assertRaisesRegex(ValueError, 'current hook proof'): n.verify(repository, self.app, inputs)
            raw.write_bytes(data)
            self.assertIn('arm64', n.verify(repository, self.app, inputs)['hookBuilds'])
            receipt['schemaVersion'] = 1
            receipt_path.write_text(json.dumps(receipt))
            with self.assertRaisesRegex(ValueError, 'current hook proof'): n.verify(repository, self.app, inputs)
            receipt['schemaVersion'] = 2
            receipt['producingInputs']['configuration']['user_defines'] = {}
            receipt_path.write_text(json.dumps(receipt))
            with self.assertRaisesRegex(ValueError, 'current hook proof'): n.verify(repository, self.app, inputs)

    @unittest.skipUnless(os.name == 'posix', 'existing local macOS scratch proof')
    def test_actual_unchanged_source_scratch_helpers_12_and_13(self):
        root = Path.home() / '.cache/lineup-stabilization/2026-10-21/v06-vm/objective-c-macos12-4f2e2429'
        if not (root / 'target12/objective_c.dylib').exists(): self.skipTest('private native compile proof unavailable')
        for target in (12, 13):
            data = (root / f'target{target}/objective_c.dylib').read_bytes()
            self.assertEqual(n.macho(data)[0]['minimumOS'], [target, 0, 0])
            self.asset.write_bytes(data)
            if target == 12: n.bundle_closure(self.app)
            else:
                with self.assertRaisesRegex(ValueError, 'newer macOS'): n.bundle_closure(self.app)
        self.asset.write_bytes((root / 'target12/objective_c.dylib').read_bytes())
        n.bundle_closure(self.app)


class InputTests(unittest.TestCase):
    def test_project_target_and_foreign_source_guard(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            def write(name, contents):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(contents)
                return path
            pubspec = write('pubspec.yaml', 'dependency_overrides:\n  objective_c:\n    path: third_party/objective_c\n\nhooks:\n  user_defines:\n    objective_c:\n      macos_target_version: 12\n')
            original = pubspec.read_text()
            xcode = write('macos/Runner.xcodeproj/project.pbxproj', 'MACOSX_DEPLOYMENT_TARGET = 12.0;')
            for name in ('pubspec.lock', 'analysis_options.yaml', 'tool/macos/build_app.dart', 'tool/macos/native_assets.py'):
                write(name, 'fixture')
            foreign = write(n.VENDOR + '/src/immutable.c', 'native baseline')
            hook = write(n.VENDOR + '/hook/build.dart', 'owned hook')
            write(n.VENDOR + '/UPSTREAM.json', json.dumps({'files': {'src/immutable.c': n.sha(foreign)}}))
            with patch.object(n, 'native_toolchain_identity', return_value={}):
                before = n.project_inputs(root)
                hook.write_text('changed owned hook')
                self.assertNotEqual(before, n.project_inputs(root))
                for value in ('13', '12.0', '"12"'):
                    pubspec.write_text(original.replace('version: 12', 'version: ' + value))
                    with self.assertRaisesRegex(ValueError, 'typed macOS 12'): n.project_inputs(root)
                pubspec.write_text(original)
                xcode.write_text('MACOSX_DEPLOYMENT_TARGET = 13.0;')
                with self.assertRaisesRegex(ValueError, 'target mismatch'): n.project_inputs(root)
                xcode.write_text('MACOSX_DEPLOYMENT_TARGET = 12.0;')
                foreign.write_text('changed runtime')
                with self.assertRaisesRegex(ValueError, 'Foreign baseline changed'): n.project_inputs(root)


@unittest.skipUnless(DART.exists() and os.name == 'posix', 'pinned Dart hook process fixture')
class HookTests(unittest.TestCase):
    def test_default_override_invalid_ios_and_target_specific_cache_outputs(self):
        with tempfile.TemporaryDirectory(prefix='lineup native hook ') as temporary:
            root = Path(temporary)
            (root / 'pubspec.yaml').write_text('fixture workspace configuration')
            package = root / 'package'
            shutil.copytree(ROOT / 'third_party/objective_c', package)
            compiler = root / 'compiler.py'
            compiler.write_text('#!' + str(Path('/usr/bin/python3')) + '\nimport json,pathlib,sys\na=sys.argv[1:]\np=pathlib.Path(a[a.index("-o")+1]);p.parent.mkdir(parents=True,exist_ok=True);p.write_text("fixture artifact")\nwith open(' + repr(str(root / 'commands.jsonl')) + ',"a") as f:f.write(json.dumps(a)+"\\n")\n')
            compiler.chmod(0o755)
            sdk = root / 'SDK'
            sdk.mkdir()
            (sdk / 'SDKSettings.json').write_text('fixture SDK identity')
            xcrun = root / 'xcrun'
            xcrun.write_text('#!/usr/bin/python3\nprint(' + repr(str(sdk)) + ')\n')
            xcrun.chmod(0o755)
            outputs = []
            for index, (os_name, define, valid, flag) in enumerate((
                ('macos', None, True, '-mmacos-version-min=13'), ('macos', 12, True, '-mmacos-version-min=12'),
                ('macos', '12 -bad', False, ''), ('macos', 12.5, False, ''), ('macos', True, False, ''),
                ('ios', 'ignored', True, '-mios-version-min=17'))):
                output = root / f'output-{index}.json'
                code = {'target_os': os_name, 'target_architecture': 'arm64', 'link_mode_preference': 'dynamic',
                        'c_compiler': {'cc': str(compiler), 'ar': str(compiler), 'ld': str(compiler)},
                        'macos': {'target_version': 13}} if os_name == 'macos' else {
                        'target_os': 'ios', 'target_architecture': 'arm64', 'link_mode_preference': 'dynamic',
                        'c_compiler': {'cc': str(compiler), 'ar': str(compiler), 'ld': str(compiler)},
                        'ios': {'target_version': 17, 'target_sdk': 'iphoneos'}}
                data = {'assets': {}, 'config': {'build_asset_types': ['code_assets/code'], 'extensions': {'code_assets': code}, 'linking_enabled': True},
                        'out_dir_shared': str(root / 'shared') + '/', 'out_file': str(output), 'package_name': 'objective_c',
                        'package_root': str(package) + '/', 'user_defines': {} if define is None else {
                            'workspace_pubspec': {'defines': {'macos_target_version': define}, 'base_path': str(root) + '/'}}}
                input_path = root / 'input.json'
                input_path.write_text(json.dumps(data))
                log = root / 'commands.jsonl'
                if log.exists(): log.unlink()
                process = subprocess.run([str(DART), '--disable-dart-dev', '--packages=' + str(ROOT / '.dart_tool/package_config.json'), str(ROOT / 'third_party/objective_c/hook/build.dart'), '--config=' + str(input_path)],
                                         cwd=ROOT, env={**os.environ, 'PATH': str(root) + os.pathsep + os.environ['PATH']}, capture_output=True, text=True)
                self.assertEqual(process.returncode == 0, valid, process.stderr)
                if not valid:
                    self.assertIn('macos_target_version', process.stderr)
                    self.assertFalse(log.exists())
                    continue
                commands = [json.loads(v) for v in log.read_text().splitlines()]
                self.assertEqual(len(commands), 9)
                self.assertTrue(all(flag in command for command in commands))
                record = json.loads(output.read_text())
                asset = record['assets'][0]['encoding']
                self.assertEqual(asset['id'], n.ASSET)
                self.assertEqual(asset['link_mode']['type'], 'dynamic_loading_bundle')
                self.assertIn(str(package / 'hook/build.dart'), record['dependencies'])
                if os_name == 'macos':
                    receipt = json.loads(Path(asset['file']).with_name('lineup-objective-c-build.json').read_text())
                    producing = receipt['producingInputs']
                    self.assertEqual(receipt['schemaVersion'], 2)
                    self.assertEqual(producing['configuration'], data)
                    if define is not None:
                        self.assertEqual(producing['workspacePubspecSha256'], n.sha(root / 'pubspec.yaml'))
                        self.assertIn(str(root / 'pubspec.yaml'), record['dependencies'])
                    self.assertEqual(producing['compilerSha256'], n.sha(compiler))
                    self.assertEqual(producing['sdkSettingsSha256'], n.sha(sdk / 'SDKSettings.json'))
                    expected_sources = {'hook/build.dart', 'pubspec.yaml'} | {
                        p.relative_to(package).as_posix() for p in (package / 'src').rglob('*')
                        if p.is_file() and p.suffix in ('.c', '.m', '.h')}
                    self.assertEqual(producing['sources'], {name: n.sha(package / name) for name in expected_sources})
                    self.assertEqual(receipt['rawAssetSha256'], n.sha(Path(asset['file'])))
                    self.assertIn(str(compiler.resolve()), record['dependencies'])
                    self.assertIn(str(sdk / 'SDKSettings.json'), record['dependencies'])
                outputs.append(asset['file'])
            self.assertNotEqual(outputs[0], outputs[1])
            self.assertIn('macos-12', outputs[1])


if __name__ == '__main__': unittest.main()
