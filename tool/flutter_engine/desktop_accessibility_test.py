#!/usr/bin/env python3
"""Tooling fixtures only: these do not build or validate a Flutter engine."""
import importlib.util
import json
import os
import plistlib
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('desktop_accessibility', Path(__file__).with_name('desktop_accessibility.py'))
ax = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ax)


class EngineFixture(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='lineup ax integration ')
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.repository = self.base / 'lineup'
        self.root = self.base / 'flutter'
        for root in (self.repository, self.root):
            root.mkdir()
            ax.git(root, 'init', '--quiet')
            ax.git(root, 'config', 'user.name', 'Tool fixture')
            ax.git(root, 'config', 'user.email', 'fixture@example.invalid')
        self.name = 'engine/src/flutter/shell/platform/common/bridge.cc'
        self.manager = 'engine/src/flutter/shell/platform/windows/egl/manager.cc'
        self.write(self.root, self.name, 'old AX\n')
        self.write(self.root, self.manager, 'old DC\n')
        self.write(self.root, 'bin/internal/engine.version', 'fixture-engine\n')
        self.commit(self.root)
        revision = ax.git(self.root, 'rev-parse', 'HEAD').decode().strip()
        self.write(self.repository, 'tool/flutter_version.json', json.dumps({'frameworkRevision': revision}))
        patched_manager_hash = ax.digest(b'new DC\n')
        self.write(self.repository, 'tool/windows/build-metadata.psd1', f"""@{{
FlutterFrameworkRevision = '{revision}'
FlutterEngineRevision = 'fixture-engine'
FlutterManagerPath = '{self.manager}'
FlutterManagerBlob = '{ax.git(self.root, 'rev-parse', f'HEAD:{self.manager}').decode().strip()}'
FlutterPatchedManagerSha256 = '{patched_manager_hash}'
FlutterEnginePatchPath = 'tool/flutter_engine/0001-windows-direct-composition.patch'
FlutterEnginePatchSha256 = 'REPLACE'
}}
""")
        self.write(self.root, self.name, 'new AX\n')
        self.write(self.repository, ax.AX_PATCH, ax.git(self.root, 'diff', '--', self.name).decode())
        self.write(self.root, self.name, 'old AX\n')
        self.write(self.root, self.manager, 'new DC\n')
        patch = ax.git(self.root, 'diff', '--', self.manager)
        self.write(self.repository, 'tool/flutter_engine/0001-windows-direct-composition.patch', patch.decode())
        metadata = self.repository / 'tool/windows/build-metadata.psd1'
        metadata.write_text(metadata.read_text().replace('REPLACE', ax.digest(patch)))
        self.write(self.root, self.manager, 'old DC\n')
        ax.finalize(self.repository, self.root)
        self.commit(self.repository)
        self.write(self.root, self.name, 'new AX\n')

    @staticmethod
    def write(root, name, data):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data)
        return path

    @staticmethod
    def commit(root):
        ax.git(root, 'add', '.')
        ax.git(root, 'commit', '--quiet', '-m', 'fixture')

    def identity(self, target='macos'):
        return ax.source_identity(self.repository, self.root, target)

    def output(self):
        output = self.root / 'engine/src/out/lineup_ax_debug_arm64'
        output.mkdir(parents=True)
        self.write(output, 'args.gn', 'target_os = "mac"\ntarget_cpu = "arm64"\nhost_cpu = "arm64"\nflutter_runtime_mode = "debug"\n')
        self.write(output, 'build.ninja', '# configured fixture\n')
        binary = self.write(output, 'FlutterMacOS.xcframework/macos-arm64/FlutterMacOS.framework/Versions/A/FlutterMacOS', '')
        binary.write_bytes(struct.pack('<IIII', 0xfeedfacf, 0x100000c, 0, 6) + b'fixture engine')
        for name in ['dart-sdk/bin/dart', 'dart-sdk/bin/snapshots/frontend_server_aot.dart.snapshot',
                     'flutter_patched_sdk/platform_strong.dill', 'flutter_patched_sdk/vm_outline_strong.dill',
                     'gen/dart-pkg/sky_engine/lib/_embedder.yaml', 'gen/frontend_server_aot.dart.snapshot',
                     'gen/const_finder.dart.snapshot', 'font-subset', 'impellerc', 'gen_snapshot',
                     'shader_lib/flutter/runtime_effect.glsl']:
            self.write(output, name, 'fixture host artifact\n')
        return output

    def provenance(self):
        output = self.output()
        ninja = self.write(self.base, 'ninja-fixture', 'fixture executable')
        record = {'schemaVersion': 1, 'kind': 'verified-local-desktop-accessibility',
                  'flutterRoot': str(self.root), 'outputName': output.name,
                  'source': {**self.identity(), 'dependencies': {'gclient': 'fixture'}}, 'configuration': ax.configuration(output, 'macos', 'arm64', 'debug'),
                  'toolchain': {}, 'ninja': {'path': str(ninja), 'sha256': ax.file_hash(ninja)},
                  'build': {'freshOutput': True, 'startedNs': 1, 'finishedNs': 2},
                  'artifacts': ax.artifact_hashes(output, 'macos'),
                  'engineBinary': str(ax.engine_binary(output, 'macos').relative_to(output))}
        (output / ax.PROVENANCE).write_text(json.dumps(record))
        return output

    def verify(self, output, **overrides):
        options = dict(target='macos', architecture='arm64', mode='debug')
        options.update(overrides)
        with mock.patch.object(ax, 'toolchain_identity', return_value={}), mock.patch.object(ax, 'dependency_identity', return_value={'gclient': 'fixture'}):
            return ax.verify(self.repository, self.root, output.name, **options)

    def test_exact_source_and_windows_composition(self):
        identity = self.identity()
        self.assertEqual([p['path'] for p in identity['patches']], [ax.AX_PATCH])
        with self.assertRaisesRegex(ax.VerificationError, 'exactly'):
            self.identity('windows')
        self.write(self.root, self.manager, 'new DC\n')
        windows = self.identity('windows')
        self.assertEqual([p['path'] for p in windows['patches']], ['tool/flutter_engine/0001-windows-direct-composition.patch', ax.AX_PATCH])
        with self.assertRaisesRegex(ax.VerificationError, 'exactly'):
            self.identity()

    def test_wrong_revision_engine_pin_staging_and_untracked_source(self):
        self.write(self.root, 'bin/internal/engine.version', 'wrong-engine\n')
        with self.assertRaisesRegex(ax.VerificationError, 'engine.version'):
            self.identity()
        self.write(self.root, 'bin/internal/engine.version', 'fixture-engine\n')
        ax.git(self.root, 'add', self.name)
        with self.assertRaisesRegex(ax.VerificationError, 'staged'):
            self.identity()
        ax.git(self.root, 'reset', '--quiet')
        extra = self.write(self.root, 'engine/src/flutter/injected.cc', 'unexpected\n')
        with self.assertRaisesRegex(ax.VerificationError, 'Untracked'):
            self.identity()
        extra.unlink()
        self.identity()

    def test_uncommitted_and_tampered_canonical_inputs(self):
        patch = self.repository / ax.AX_PATCH
        original = patch.read_text()
        patch.write_text(original + '\n')
        with self.assertRaisesRegex(ax.VerificationError, 'committed'):
            self.identity()
        patch.write_text(original)
        manifest = self.repository / ax.MANIFEST
        metadata = json.loads(manifest.read_text())
        metadata['patches'][0]['files'][self.name]['patchedSha256'] = '0' * 64
        manifest.write_text(json.dumps(metadata))
        self.commit(self.repository)
        with self.assertRaisesRegex(ax.VerificationError, 'metadata mismatch'):
            self.identity()

    def test_extra_or_modified_source_is_rejected_and_restoration_passes(self):
        self.write(self.root, self.name, 'new AX plus injected code\n')
        with self.assertRaisesRegex(ax.VerificationError, 'SHA-256 mismatch'):
            self.identity()
        self.write(self.root, self.name, 'new AX\n')
        self.identity()
        self.write(self.root, self.manager, 'unrelated change\n')
        with self.assertRaisesRegex(ax.VerificationError, 'exactly'):
            self.identity()

    def test_verified_artifact_then_missing_stale_and_tampered_controls(self):
        output = self.provenance()
        self.assertEqual(self.verify(output)['kind'], 'verified-local-desktop-accessibility')
        binary = ax.engine_binary(output, 'macos')
        original = binary.read_bytes()
        binary.write_bytes(original + b'tampered')
        with self.assertRaisesRegex(ax.VerificationError, 'artifact hashes'):
            self.verify(output)
        binary.write_bytes(original)
        self.verify(output)
        record_path = output / ax.PROVENANCE
        record = json.loads(record_path.read_text())
        record['build']['startedNs'] = binary.stat().st_mtime_ns + 1000000000
        record['build']['finishedNs'] = record['build']['startedNs'] + 1
        record_path.write_text(json.dumps(record))
        with self.assertRaisesRegex(ax.VerificationError, 'Stale engine artifact'):
            self.verify(output)
        record_path.unlink()
        with self.assertRaisesRegex(ax.VerificationError, 'provenance is missing'):
            self.verify(output)

    def test_wrong_platform_architecture_and_mode_are_rejected(self):
        output = self.provenance()
        for override, message in [({'architecture': 'x64'}, 'architecture'), ({'mode': 'release'}, 'runtime mode')]:
            with self.assertRaisesRegex(ax.VerificationError, message):
                self.verify(output, **override)
        self.write(output, 'args.gn', (output / 'args.gn').read_text().replace('"mac"', '"win"'))
        with self.assertRaisesRegex(ax.VerificationError, 'platform'):
            self.verify(output)

    def test_configuration_and_source_provenance_are_bound(self):
        output = self.provenance()
        self.write(output, 'build.ninja', '# changed graph\n')
        with self.assertRaisesRegex(ax.VerificationError, 'configuration provenance'):
            self.verify(output)
        self.write(output, 'build.ninja', '# configured fixture\n')
        self.verify(output)
        manifest = self.repository / ax.MANIFEST
        record = json.loads(manifest.read_text())
        record['note'] = 'new reviewed manifest'
        manifest.write_text(json.dumps(record))
        self.commit(self.repository)
        with self.assertRaisesRegex(ax.VerificationError, 'Stale engine source'):
            self.verify(output)

    def test_actual_binary_architecture_and_required_host_artifacts(self):
        output = self.provenance()
        binary = ax.engine_binary(output, 'macos')
        original = binary.read_bytes()
        binary.write_bytes(struct.pack('<IIII', 0xfeedfacf, 0x1000007, 0, 6) + b'other architecture')
        with self.assertRaisesRegex(ax.VerificationError, 'wrong architecture'):
            self.verify(output)
        binary.write_bytes(original)
        (output / 'gen_snapshot').unlink()
        with self.assertRaisesRegex(ax.VerificationError, 'snapshot tool is missing'):
            self.verify(output)

    def test_shader_header_missing_and_tampered_controls(self):
        output = self.provenance()
        header = output / 'shader_lib/flutter/runtime_effect.glsl'
        header.write_text('tampered shader source')
        with self.assertRaisesRegex(ax.VerificationError, 'artifact hashes changed'):
            self.verify(output)
        header.unlink()
        with self.assertRaisesRegex(ax.VerificationError, 'host artifact is missing'):
            self.verify(output)

    def test_build_does_not_bless_existing_output(self):
        self.output()
        with mock.patch.object(ax, 'host_matches'), mock.patch.object(ax, 'dependency_identity', return_value={'gclient': 'fixture'}):
            with self.assertRaisesRegex(ax.VerificationError, 'Fresh build requires absent output'):
                ax.build(self.repository, self.root, 'macos', 'arm64', 'debug', 'ninja')

    def test_build_owns_fresh_output_and_records_bounded_explicit_targets(self):
        commands = []
        def fake_command(arguments, cwd=None, capture=True):
            commands.append([str(a) for a in arguments])
            if len(arguments) > 1 and str(arguments[1]).endswith('/tools/gn'):
                self.output()
            return b''
        with mock.patch.object(ax, 'host_matches'), mock.patch.object(ax, 'run', side_effect=fake_command), \
             mock.patch.object(ax, 'source_identity', return_value={}), mock.patch.object(ax, 'toolchain_identity', return_value={}), mock.patch.object(ax, 'dependency_identity', return_value={'gclient': 'fixture'}), \
             mock.patch('shutil.which', return_value=sys.executable):
            result = ax.build(self.repository, self.root, 'macos', 'arm64', 'debug', 'ninja')
        self.assertEqual(result['kind'], 'verified-local-desktop-accessibility')
        self.assertIn('--no-build-glfw-shell', commands[0])
        self.assertIn('--no-build-embedder-examples', commands[0])
        self.assertEqual(commands[1][3:5], ['-j', '2'])
        self.assertIn('flutter_framework', commands[1])
        self.assertIn('dart_sdk', commands[1])
        self.assertNotIn('all', commands[1])

    def test_build_owns_refresh_and_does_not_emit_provenance_on_failed_refresh(self):
        def fake_command(arguments, cwd=None, capture=True):
            if len(arguments) > 1 and str(arguments[1]).endswith('/tools/gn'):
                self.output()
            else:
                binary = ax.engine_binary(self.root / 'engine/src/out/lineup_ax_debug_arm64', 'macos')
                binary.unlink()
            return b''
        with mock.patch.object(ax, 'host_matches'), mock.patch.object(ax, 'run', side_effect=fake_command), \
             mock.patch.object(ax, 'source_identity', return_value={}), mock.patch.object(ax, 'toolchain_identity', return_value={}), mock.patch.object(ax, 'dependency_identity', return_value={'gclient': 'fixture'}), \
             mock.patch('shutil.which', return_value=sys.executable):
            with self.assertRaisesRegex(ax.VerificationError, 'binary is missing'):
                ax.build(self.repository, self.root, 'macos', 'arm64', 'debug', 'ninja')
        self.assertFalse((self.root / 'engine/src/out/lineup_ax_debug_arm64' / ax.PROVENANCE).exists())

    def test_cli_rejects_bad_inputs_before_any_build(self):
        result = subprocess.run([sys.executable, ax.__file__, 'verify', '--repository', str(self.repository),
                                 '--flutter-root', str(self.root), '--output-name', '../escape'], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unsafe local engine output', result.stderr)

    def app_recipe_fixture(self):
        output = self.provenance()
        self.write(self.repository, 'pubspec.yaml', 'version: 1.2.3+4\n')
        self.commit(self.repository)
        with mock.patch.object(ax, 'toolchain_identity', return_value={}), mock.patch.object(ax, 'dependency_identity', return_value={'gclient': 'fixture'}):
            selected = ax.verify(self.repository, self.root, output.name, 'macos', 'arm64', 'debug')
        commit = ax.git(self.repository, 'rev-parse', 'HEAD').decode().strip()
        recipe = {'schemaVersion': 1, 'flutterExitCode': 0, 'appCommit': commit,
                  'engine': selected, 'entrypoint': 'lib/main.dart', 'mode': 'debug',
                  'flutterArguments': [f"--local-engine-src-path={selected['engineSource']}",
                      f'--local-engine={output.name}', f'--local-engine-host={output.name}',
                      'build', 'macos', '--debug', '--dart-define=EXPERIMENT=fixture',
                      '--dart-define=LINEUP_VERSION=1.2.3', f'--dart-define=LINEUP_BUILD=4@{commit}']}
        app = self.base / 'Lineup Desktop.app'
        self.write(app, 'Contents/MacOS/Lineup Desktop', 'fixture Runner')
        self.write(app, 'Contents/Frameworks/App.framework/Versions/A/App', 'compiled Dart bytes')
        self.write(app, 'Contents/Frameworks/App.framework/Resources/flutter_assets/AssetManifest.bin', 'asset bytes')
        engine = app / 'Contents/Frameworks/FlutterMacOS.framework/Versions/A/FlutterMacOS'
        engine.parent.mkdir(parents=True)
        shutil.copy2(ax.engine_binary(output, 'macos'), engine)
        info = {'CFBundleShortVersionString': '1.2.3', 'CFBundleVersion': '4', 'CFBundleExecutable': 'Lineup Desktop'}
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        return selected, recipe, app

    def test_bundle_requires_receipt_and_binds_dart_assets_recipe_and_source(self):
        selected, recipe, app = self.app_recipe_fixture()
        arguments = (self.repository, self.root, selected['outputName'], 'macos', 'arm64', 'debug', app)
        with mock.patch.object(ax, 'verify', return_value=selected), mock.patch('platform.system', return_value='Darwin'), \
             mock.patch.object(ax, 'executable_hash', side_effect=ax.file_hash):
            # Same engine, version and Runner are insufficient without a receipt.
            with self.assertRaisesRegex(ax.VerificationError, 'receipt is missing'):
                ax.bundle(*arguments)
            ax.record_app_build(*arguments, recipe)
            record = ax.bundle(*arguments)
            self.assertEqual(record['appCommit'], recipe['appCommit'])
            self.assertIn('--dart-define=EXPERIMENT=fixture', record['buildRecipe']['flutterArguments'])
            for relative in ('Contents/Frameworks/App.framework/Versions/A/App',
                             'Contents/Frameworks/App.framework/Resources/flutter_assets/AssetManifest.bin'):
                artifact = app / relative
                original = artifact.read_bytes()
                artifact.write_bytes(original + b'tampered')
                with self.assertRaisesRegex(ax.VerificationError, 'Dart code/assets'):
                    ax.bundle(*arguments)
                artifact.write_bytes(original)
                ax.bundle(*arguments)
            receipt_path = app.parent / (app.name + ax.APP_RECEIPT_SUFFIX)
            receipt = json.loads(receipt_path.read_text())
            receipt['recipe']['appCommit'] = '0' * 40
            receipt_path.write_text(json.dumps(receipt))
            with self.assertRaisesRegex(ax.VerificationError, 'another source commit'):
                ax.bundle(*arguments)
            for option in ('--help', '-h', '--version', '--version=true', '--verbose', '--config-only', '--enable-analytics', '--disable-analytics'):
                bad_recipe = {**recipe, 'flutterArguments': [*recipe['flutterArguments'][:-2], option, *recipe['flutterArguments'][-2:]]}
                with self.assertRaisesRegex(ax.VerificationError, 'only supports'):
                    ax.record_app_build(*arguments, bad_recipe)
            recipe['entrypoint'] = 'lib/other.dart'
            with self.assertRaisesRegex(ax.VerificationError, 'entrypoint/mode'):
                ax.record_app_build(*arguments, recipe)

    def test_nested_git_graph_checks_expected_head_dirty_and_configuration(self):
        dependency_name = 'engine/src/flutter/third_party/nested'
        nested = self.root / dependency_name
        nested.mkdir(parents=True)
        ax.git(nested, 'init', '--quiet')
        ax.git(nested, 'config', 'user.name', 'Tool fixture')
        ax.git(nested, 'config', 'user.email', 'fixture@example.invalid')
        self.write(nested, 'source.cc', 'source')
        self.write(nested, '.gitignore', 'output/\n')
        self.commit(nested)
        expected = ax.git(nested, 'rev-parse', 'HEAD').decode().strip()
        ax.git(nested, 'tag', '-a', 'pinned', '-m', 'annotated DEPS object')
        declared_object = ax.git(nested, 'rev-parse', 'pinned').decode().strip()
        standard = {'custom_deps': {}, 'deps_file': 'DEPS', 'managed': False, 'name': '.', 'safesync_url': '', 'url': 'https://example.invalid/flutter.git'}
        self.write(self.root, 'engine/scripts/standard.gclient', 'solutions = ' + repr([standard]))
        ax.git(self.root, 'add', 'engine/scripts/standard.gclient')
        ax.git(self.root, 'commit', '--quiet', '-m', 'standard gclient')
        config = self.write(self.root, '.gclient', 'solutions = ' + repr([{**standard, 'custom_vars': {'download_android_deps': False}}]))
        depot = self.base / 'depot_tools'
        depot.mkdir()
        ax.git(depot, 'init', '--quiet')
        ax.git(depot, 'config', 'user.name', 'Tool fixture')
        ax.git(depot, 'config', 'user.email', 'fixture@example.invalid')
        launcher = self.write(depot, 'gclient', '#!' + sys.executable + '\nimport json,pathlib,sys\npathlib.Path(sys.argv[sys.argv.index("--output-json")+1]).write_text((pathlib.Path(__file__).parent/"graph.json").read_text())\n')
        launcher.chmod(0o755)
        graph = {'.': {'url': standard['url'], 'rev': None}, dependency_name: {'url': 'https://example.invalid/nested.git', 'rev': declared_object}}
        self.write(depot, 'graph.json', json.dumps(graph))
        self.commit(depot)
        metadata = self.repository / 'tool/windows/build-metadata.psd1'
        depot_revision = ax.git(depot, 'rev-parse', 'HEAD').decode().strip()
        metadata.write_text(metadata.read_text().replace('}\n', f"DepotToolsRevision = '{depot_revision}'\n}}\n"))
        self.commit(self.repository)
        identity = lambda: ax.dependency_identity(self.repository, self.root.resolve(), launcher)
        self.assertNotEqual(declared_object, expected)
        self.assertEqual(identity()['gitDependencies'][dependency_name]['revision'], expected)
        self.assertEqual(identity()['gitDependencies'][dependency_name]['declaredRevision'], declared_object)
        self.write(nested, 'output/generated', 'ignored build output')
        identity()
        self.write(nested, 'source.cc', 'dirty source')
        with self.assertRaisesRegex(ax.VerificationError, 'source changes'):
            identity()
        self.commit(nested)
        with self.assertRaisesRegex(ax.VerificationError, 'revision differs'):
            identity()
        ax.git(nested, 'checkout', '--quiet', expected)
        identity()
        config.write_text('solutions = ' + repr([{**standard, 'custom_deps': {dependency_name: None}}]))
        with self.assertRaisesRegex(ax.VerificationError, 'without source overrides'):
            identity()

    def test_ninja_resolves_real_executable_and_rejects_context_dependent_shim(self):
        shim = self.write(self.base, 'ninja-shim', '#!/bin/sh\nexec other-ninja "$@"\n')
        shim.chmod(0o755)
        with self.assertRaisesRegex(ax.VerificationError, 'script/shim'):
            ax.resolve_ninja(str(shim))
        self.assertEqual(ax.resolve_ninja(sys.executable), str(Path(sys.executable).resolve()))

    def test_hidden_clang_override_is_rejected(self):
        with mock.patch.dict(os.environ, {'CCC_OVERRIDE_OPTIONS': '+--ld-path=other'}):
            with self.assertRaisesRegex(ax.VerificationError, 'forbidden'):
                ax.build_environment()


@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('codesign') and shutil.which('clang'), 'native macOS signature fixture')
class SignedExecutable(unittest.TestCase):
    def test_signature_comparison_preserves_canonical_binaries_and_detects_other_code(self):
        with tempfile.TemporaryDirectory(prefix='lineup ax codesign ') as temporary:
            root = Path(temporary)
            source = root / 'fixture.c'
            source.write_text('int main(void) { return 0; }\n')
            binary = root / 'built'
            subprocess.run(['clang', str(source), '-o', str(binary)], check=True, capture_output=True)
            signed = root / 'signed'
            shutil.copy2(binary, signed)
            subprocess.run(['codesign', '--force', '--sign', '-', '--identifier', 'lineup.fixture', str(signed)], check=True, capture_output=True)
            originals = [ax.file_hash(binary), ax.file_hash(signed)]
            self.assertNotEqual(*originals)
            self.assertEqual(ax.executable_hash(binary), ax.executable_hash(signed))
            self.assertEqual(originals, [ax.file_hash(binary), ax.file_hash(signed)])
            source.write_text('int main(void) { return 42; }\n')
            other = root / 'other'
            subprocess.run(['clang', str(source), '-o', str(other)], check=True, capture_output=True)
            self.assertNotEqual(ax.executable_hash(binary), ax.executable_hash(other))


if __name__ == '__main__':
    unittest.main()
