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
            ax.git(root, 'config', 'core.autocrlf', 'false')
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
        metadata.write_text(metadata.read_text().replace('REPLACE', ax.digest(patch)), newline='\n')
        self.write(self.root, self.manager, 'old DC\n')
        ax.finalize(self.repository, self.root)
        self.commit(self.repository)
        self.write(self.root, self.name, 'new AX\n')

    @staticmethod
    def write(root, name, data):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data, newline='\n')
        return path

    @staticmethod
    def commit(root):
        ax.git(root, 'add', '.')
        ax.git(root, 'commit', '--quiet', '-m', 'fixture')

    @staticmethod
    def is_gn_command(arguments):
        return (len(arguments) > 1 and
                str(arguments[1]).replace('\\', '/').endswith('/tools/gn'))

    def test_gn_fixture_recognizes_native_and_git_windows_path_spellings(self):
        for path in ('/fixture/flutter/tools/gn', r'C:\fixture\flutter\tools\gn',
                     'C:/fixture/flutter/tools/gn'):
            self.assertTrue(self.is_gn_command(['python', path]), path)
        self.assertFalse(self.is_gn_command(['ninja', '-C', 'output']))
        self.assertFalse(self.is_gn_command(['ninja']))

    def identity(self, target='macos'):
        return ax.source_identity(self.repository, self.root, target)

    def output(self, target='macos', architecture='arm64', mode='debug'):
        if target == 'windows':
            return self.windows_output(mode)
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

    def provenance(self, target='macos', architecture='arm64', mode='debug'):
        output = self.output(target, architecture, mode)
        ninja = self.write(self.base, 'ninja-fixture', 'fixture executable')
        record = {'schemaVersion': 1, 'kind': 'verified-local-desktop-accessibility',
                  'flutterRoot': str(self.root), 'outputName': output.name,
                  'source': {**self.identity(target), 'dependencies': {'gclient': 'fixture'}}, 'configuration': ax.configuration(output, target, architecture, mode),
                  'toolchain': {}, **({'environment': ax.build_environment()} if target == 'windows' else {}), 'ninja': {'path': str(ninja), 'sha256': ax.file_hash(ninja)},
                  'build': {'freshOutput': True, 'startedNs': 1, 'finishedNs': 2},
                  'artifacts': ax.artifact_hashes(output, target),
                  'engineBinary': str(ax.engine_binary(output, target).relative_to(output)).replace(os.sep, '/')}
        (output / ax.PROVENANCE).write_text(json.dumps(record), newline='\n')
        return output

    def verify(self, output, **overrides):
        options = dict(target='macos', architecture='arm64', mode='debug')
        options.update(overrides)
        with mock.patch.object(ax, 'toolchain_identity', return_value={}), mock.patch.object(ax, 'dependency_identity', return_value={'gclient': 'fixture'}):
            return ax.verify(self.repository, self.root, output.name, **options)

    def windows_output(self, mode='debug'):
        output = self.root / f'engine/src/out/lineup_ax_{mode}_x64'
        output.mkdir(parents=True)
        self.write(output, 'args.gn', f'target_os = "win"\ntarget_cpu = "x64"\nhost_cpu = "x64"\nflutter_runtime_mode = "{mode}"\n')
        self.write(output, 'build.ninja', '# configured fixture\n')
        binary = self.write(output, 'flutter_windows.dll', '')
        header = bytearray(64)
        header[:2] = b'MZ'
        struct.pack_into('<I', header, 60, 64)
        binary.write_bytes(header + b'PE\0\0' + struct.pack('<H', 0x8664) + b'fixture')
        for name in ('dart-sdk/bin/dart.exe', 'dart-sdk/bin/snapshots/frontend_server_aot.dart.snapshot',
                     'flutter_patched_sdk/platform_strong.dill', 'flutter_patched_sdk/vm_outline_strong.dill',
                     'gen/dart-pkg/sky_engine/lib/_embedder.yaml', 'gen/frontend_server_aot.dart.snapshot',
                     'gen/const_finder.dart.snapshot', 'font-subset.exe', 'impellerc.exe', 'gen_snapshot.exe',
                     'shader_lib/flutter/runtime_effect.glsl', 'icudtl.dat', 'flutter_windows.dll.lib',
                     'flutter_windows.h', 'flutter_export.h', 'flutter_messenger.h',
                     'flutter_plugin_registrar.h', 'flutter_texture_registrar.h',
                     'cpp_client_wrapper/include/flutter/flutter_engine.h'):
            self.write(output, name, 'Windows fixture artifact\n')
        return output

    def test_windows_combined_apply_cli_excludes_apple_patch_and_rejects_changed_inputs(self):
        # Put the optional Mac patch in the manifest, but leave Windows source
        # exactly DC+AX after the real CLI applies the combined patch set.
        mac = 'engine/src/build/mac_fixture.gni'
        self.write(self.root, mac, 'old Mac\n')
        ax.git(self.root, 'add', mac)
        ax.git(self.root, 'commit', '--quiet', '-m', 'Mac baseline')
        revision = ax.git(self.root, 'rev-parse', 'HEAD').decode().strip()
        pin = self.repository / 'tool/flutter_version.json'
        old_revision = json.loads(pin.read_text())['frameworkRevision']
        for name in ax.PIN_FILES:
            path = self.repository / name
            path.write_text(path.read_text().replace(old_revision, revision), newline='\n')
        self.write(self.root, mac, 'new Mac\n')
        self.write(self.repository, ax.MAC_BUILD_PATCH, ax.git(self.root, 'diff', '--', mac).decode())
        self.write(self.root, mac, 'old Mac\n')
        ax.finalize(self.repository, self.root)
        self.commit(self.repository)
        self.write(self.root, self.name, 'old AX\n')
        result = subprocess.run([sys.executable, ax.__file__, 'apply', '--repository', str(self.repository),
                                 '--flutter-root', str(self.root), '--platform', 'windows'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / mac).read_text(), 'old Mac\n')
        self.identity('windows')
        for name in (*ax.PIN_FILES, ax.MANIFEST, ax.AX_PATCH, 'tool/flutter_engine/0001-windows-direct-composition.patch'):
            path = self.repository / name
            original = path.read_bytes()
            path.write_bytes(original + b'\n')
            with self.assertRaisesRegex(ax.VerificationError, 'committed'):
                self.identity('windows')
            path.write_bytes(original)
            self.identity('windows')

    def test_windows_pe_provenance_and_artifact_controls(self):
        self.write(self.root, self.manager, 'new DC\n')
        for mode in ('debug', 'release'):
            output = self.provenance('windows', 'x64', mode)
            verify = lambda: self.verify(output, target='windows', architecture='x64', mode=mode)
            selected = verify()
            self.assertEqual(selected['outputName'], f'lineup_ax_{mode}_x64')
            self.assertEqual([p['path'] for p in selected['recipe']['patches']],
                             ['tool/flutter_engine/0001-windows-direct-composition.patch', ax.AX_PATCH])
            self.assertNotIn(ax.MAC_BUILD_PATCH, str(selected['recipe']))
            binary = output / 'flutter_windows.dll'
            original = binary.read_bytes()
            for contents, message in [(b'not a PE', 'Windows PE'),
                                      (original[:68] + struct.pack('<H', 0xaa64), 'wrong architecture'),
                                      (original + b'tamper', 'artifact hashes')]:
                binary.write_bytes(contents)
                with self.assertRaisesRegex(ax.VerificationError, message):
                    verify()
                binary.write_bytes(original)
                verify()
            for name in ('flutter_windows.h', 'cpp_client_wrapper/include/flutter/flutter_engine.h',
                         'dart-sdk/bin/dart.exe', 'shader_lib/flutter/runtime_effect.glsl'):
                artifact = output / name
                data = artifact.read_bytes()
                artifact.unlink()
                with self.assertRaisesRegex(ax.VerificationError, 'artifact is missing'):
                    verify()
                artifact.write_bytes(data)
                verify()
            path = output / ax.PROVENANCE
            data = path.read_bytes()
            record = json.loads(data)
            record['source']['dependencies']['changed'] = True
            path.write_text(json.dumps(record), newline='\n')
            with self.assertRaisesRegex(ax.VerificationError, 'source/patch provenance'):
                verify()
            path.write_bytes(data)
            verify()
            ninja = self.base / 'ninja-fixture'
            ninja.write_text('changed executable', newline='\n')
            with self.assertRaisesRegex(ax.VerificationError, 'Ninja executable changed'):
                verify()
            ninja.write_text('fixture executable', newline='\n')
            verify()

    def test_windows_stock_dc_only_ax_only_and_wrong_base_fail(self):
        self.write(self.root, self.name, 'old AX\n')
        with self.assertRaisesRegex(ax.VerificationError, 'exactly'):
            self.identity('windows')
        self.write(self.root, self.manager, 'new DC\n')
        with self.assertRaisesRegex(ax.VerificationError, 'exactly'):
            self.identity('windows')
        self.write(self.root, self.name, 'new AX\n')
        self.identity('windows')
        ax.git(self.root, 'add', self.name)
        with self.assertRaisesRegex(ax.VerificationError, 'staged'):
            self.identity('windows')
        ax.git(self.root, 'reset', '--quiet')
        self.write(self.root, 'unexpected.txt', 'new tracked source')
        self.commit(self.root)
        with self.assertRaisesRegex(ax.VerificationError, 'framework revision'):
            self.identity('windows')

    def test_windows_build_failure_never_emits_receipt(self):
        self.write(self.root, self.manager, 'new DC\n')
        def command(arguments, **kwargs):
            if self.is_gn_command(arguments):
                self.windows_output()
            else:
                raise ax.VerificationError('deliberate Ninja process failure')
            return b''
        with mock.patch.object(ax, 'host_matches'), mock.patch.object(ax, 'run', side_effect=command), \
             mock.patch.object(ax, 'verified_sources', return_value={}), \
             mock.patch.object(ax, 'toolchain_identity', return_value={}), \
             mock.patch.object(ax, 'resolve_ninja', return_value=sys.executable):
            with self.assertRaisesRegex(ax.VerificationError, 'Ninja process failure'):
                ax.build(self.repository, self.root, 'windows', 'x64', 'debug', sys.executable)
        output = self.root / 'engine/src/out/lineup_ax_debug_x64'
        self.assertFalse((output / ax.PROVENANCE).exists())
        with mock.patch.object(ax, 'host_matches'), mock.patch.object(ax, 'dependency_identity', return_value={}):
            with self.assertRaisesRegex(ax.VerificationError, 'absent output'):
                ax.build(self.repository, self.root, 'windows', 'x64', 'debug', sys.executable)

    def test_gtest_xml_requires_cases_and_exposes_skips_and_failures(self):
        path = self.base / 'results.xml'
        for data in ('<testsuites/>', '<broken'):
            path.write_text(data, newline='\n')
            with self.assertRaises(ax.VerificationError):
                ax.gtest_results(path)
        path.write_text('<testsuites><testsuite><testcase classname="Bridge" name="Pass"/>'
                        '<testcase classname="Bridge" name="Fail"><failure/></testcase>'
                        '<testcase classname="Bridge" name="Skip" result="suppressed"/>'
                        '</testsuite></testsuites>', newline='\n')
        self.assertEqual(ax.gtest_results(path), {'Bridge.Pass': 'passed', 'Bridge.Fail': 'failed', 'Bridge.Skip': 'skipped'})
        with mock.patch.object(ax.subprocess, 'run', return_value=mock.Mock(returncode=1)):
            # A filtered baseline must actually include every named failure.
            with self.assertRaisesRegex(ax.VerificationError, 'every requested'):
                ax.run_windows_suite(self.base, 'results', self.base, {'Bridge.Missing'})

    def test_suite_process_ignores_inherited_selection_and_preserves_baseline_filter(self):
        hostile = {
            'GTEST_FILTER': '*Recovery*', 'gtest_filter': '*Recovery*',
            'GTEST_TOTAL_SHARDS': '2', 'GTEST_SHARD_INDEX': '1',
            'GTEST_SHARD_STATUS_FILE': str(self.base / 'unexpected-shard-file'),
            'GTEST_REPEAT': '0', 'GTEST_FAIL_FAST': '1', 'GTEST_LIST_TESTS': '1',
            'GTEST_BREAK_ON_FAILURE': '1', 'GTEST_THROW_ON_FAILURE': '1',
            'TESTBRIDGE_TEST_ONLY': '*Recovery*', 'TESTBRIDGE_TEST_RUNNER_FAIL_FAST': '1',
            'LINEUP_RUNTIME_FIXTURE': 'preserved',
        }
        calls = []
        available = {'Bridge.Recovery', 'Bridge.Ordinary'}
        def process(command, *, cwd, env, stdout, stderr, check):
            calls.append(command)
            self.assertEqual(cwd, self.base)
            self.assertFalse(any(key.upper().startswith('GTEST_') for key in env))
            self.assertNotIn('TESTBRIDGE_TEST_ONLY', env)
            self.assertNotIn('TESTBRIDGE_TEST_RUNNER_FAIL_FAST', env)
            self.assertEqual(env['LINEUP_RUNTIME_FIXTURE'], 'preserved')
            self.assertEqual(env.get('PATH'), os.environ.get('PATH'))
            self.assertIn('--gtest_repeat=1', command)
            self.assertIn('--gtest_fail_fast=0', command)
            self.assertIn('--gtest_list_tests=0', command)
            self.assertFalse(check)
            self.assertEqual(stderr, subprocess.STDOUT)
            selection = next(arg.split('=', 1)[1] for arg in command if arg.startswith('--gtest_filter='))
            selected = available if selection == '*' else set(selection.split(':'))
            self.assertTrue(selected <= available)
            result_path = Path(next(arg.split('xml:', 1)[1] for arg in command if arg.startswith('--gtest_output=')))
            cases = ''.join(f'<testcase classname="Bridge" name="{name.split(".")[1]}"/>' for name in sorted(selected))
            result_path.write_text('<testsuites><testsuite>' + cases + '</testsuite></testsuites>', newline='\n')
            return mock.Mock(returncode=0)
        with mock.patch.dict(os.environ, hostile), mock.patch.object(ax.subprocess, 'run', side_effect=process):
            caller = dict(os.environ)
            self.assertEqual(ax.run_windows_suite(self.base, 'fixture', self.base),
                             {name: 'passed' for name in available})
            self.assertEqual(ax.run_windows_suite(self.base, 'fixture', self.base, {'Bridge.Ordinary'}),
                             {'Bridge.Ordinary': 'passed'})
            self.assertEqual(dict(os.environ), caller)
        self.assertIn('--gtest_filter=*', calls[0])
        self.assertIn('--gtest_filter=Bridge.Ordinary', calls[1])
        self.assertFalse((self.base / 'unexpected-shard-file').exists())

    def test_windows_full_suites_and_baseline_attribution_restore_source(self):
        self.write(self.root, self.manager, 'new DC\n')
        output = self.provenance('windows', 'x64', 'debug')
        record_path = output / ax.PROVENANCE
        record = json.loads(record_path.read_text())
        record['ninja'] = {'path': str(Path(sys.executable).resolve()), 'sha256': ax.file_hash(sys.executable)}
        record['environment'] = ax.build_environment()
        record['build']['gnCommand'] = ['python', 'flutter/tools/gn', '--target-dir', output.name]
        record_path.write_text(json.dumps(record), newline='\n')
        actual_run = ax.run
        def command(arguments, **kwargs):
            if arguments[0] == 'git':
                return actual_run(arguments, **kwargs)
            if '--target-dir' in arguments:
                baseline = output.parent / arguments[arguments.index('--target-dir') + 1]
                baseline.mkdir()
                shutil.copy2(output / 'args.gn', baseline / 'args.gn')
                shutil.copy2(output / 'build.ninja', baseline / 'build.ninja')
            return b''
        for scenario in ('excluded', 'regression', 'missing-recovery'):
            calls = []
            def suite(directory, name, destination, names=None):
                calls.append((name, names))
                if names is not None:
                    self.assertEqual(names, {'Other.EnvironmentFailure'})
                    return {'Other.EnvironmentFailure': 'failed' if scenario == 'excluded' else 'passed'}
                result = {case: 'passed' for case in ax.WINDOWS_RECOVERY[name]}
                if name == 'common_cpp_unittests':
                    result['Other.EnvironmentFailure'] = 'failed'
                    if scenario == 'missing-recovery':
                        result.pop(next(iter(ax.WINDOWS_RECOVERY[name])))
                return result
            baseline = output.parent / 'lineup_dc_baseline_debug_x64'
            if baseline.exists():
                shutil.rmtree(baseline)
            with mock.patch.object(ax, 'host_matches'), mock.patch.object(ax, 'run', side_effect=command), \
                 mock.patch.object(ax, 'run_windows_suite', side_effect=suite), \
                 mock.patch.object(ax, 'toolchain_identity', return_value={}), \
                 mock.patch.object(ax, 'dependency_identity', return_value={'gclient': 'fixture'}):
                action = lambda: ax.windows_tests(self.repository, self.root, 'debug', sys.executable, 2, self.base / scenario)
                if scenario == 'excluded':
                    summary = action()
                    self.assertEqual(summary['dcBaselineExclusions'], {'common_cpp_unittests': ['Other.EnvironmentFailure']})
                else:
                    with self.assertRaisesRegex(ax.VerificationError, 'regression' if scenario == 'regression' else 'recovery cases'):
                        action()
            self.assertEqual([name for name, names in calls[:2]], list(ax.WINDOWS_RECOVERY))
            self.assertEqual((self.root / self.name).read_text(), 'new AX\n')
            self.verify(output, target='windows', architecture='x64')

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
        patch.write_text(original + '\n', newline='\n')
        with self.assertRaisesRegex(ax.VerificationError, 'committed'):
            self.identity()
        patch.write_text(original, newline='\n')
        manifest = self.repository / ax.MANIFEST
        metadata = json.loads(manifest.read_text())
        metadata['patches'][0]['files'][self.name]['patchedSha256'] = '0' * 64
        manifest.write_text(json.dumps(metadata), newline='\n')
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
        record_path.write_text(json.dumps(record), newline='\n')
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
        manifest.write_text(json.dumps(record), newline='\n')
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
        header.write_text('tampered shader source', newline='\n')
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
            if self.is_gn_command(arguments):
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
            if self.is_gn_command(arguments):
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

    def test_only_explicit_apple_linker_disables_lto_and_keeps_optimization(self):
        for target, apple_linker in [('macos', True), ('macos', False), ('windows', False)]:
            with self.subTest(target=target, apple_linker=apple_linker), \
                 mock.patch.object(ax, 'host_matches'), \
                 mock.patch.object(ax, 'verified_sources', return_value={'patches': [{'path': ax.MAC_BUILD_PATCH}]}), \
                 mock.patch.object(ax, 'run', side_effect=ax.VerificationError('fixture stops before GN execution')) as command:
                with self.assertRaisesRegex(ax.VerificationError, 'fixture stops'):
                    ax.build(self.repository, self.root, target, 'arm64', 'release', 'ninja', apple_linker=apple_linker)
            arguments = command.call_args.args[0]
            self.assertEqual('--no-lto' in arguments, apple_linker)
            self.assertEqual('mac_use_apple_linker=true' in arguments, apple_linker)
            self.assertNotIn('--unoptimized', arguments)

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
            receipt_path.write_text(json.dumps(receipt), newline='\n')
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
        if os.name == 'nt':
            generator = self.write(depot, 'generator.py', launcher.read_text().split('\n', 1)[1])
            launcher.unlink()
            launcher = self.write(depot, 'gclient.bat', '@echo off\n"' + sys.executable + '" "%~dp0generator.py" %*\n')
        launcher.chmod(0o755)
        graph = {'.': {'url': standard['url'], 'rev': None}, dependency_name: {'url': 'https://example.invalid/nested.git', 'rev': declared_object}}
        self.write(depot, 'graph.json', json.dumps(graph))
        self.commit(depot)
        metadata = self.repository / 'tool/windows/build-metadata.psd1'
        depot_revision = ax.git(depot, 'rev-parse', 'HEAD').decode().strip()
        metadata.write_text(metadata.read_text().replace('}\n', f"DepotToolsRevision = '{depot_revision}'\n}}\n"), newline='\n')
        self.commit(self.repository)
        identity = lambda: ax.dependency_identity(self.repository, self.root.resolve(), launcher)
        original_git = ax.git
        def alternate_spelling(directory, *arguments):
            result = original_git(directory, *arguments)
            if Path(directory) == depot and arguments == ('rev-parse', '--show-toplevel'):
                return (depot.as_posix() + '/.\n').encode()
            return result
        with mock.patch.object(ax, 'git', side_effect=alternate_spelling):
            self.assertEqual(identity()['gclient'], str(launcher.resolve()))
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
        config.write_text('solutions = ' + repr([{**standard, 'custom_deps': {dependency_name: None}}]), newline='\n')
        with self.assertRaisesRegex(ax.VerificationError, 'without source overrides'):
            identity()

    @unittest.skipUnless(os.name == 'nt', 'physical Windows path normalization fixture')
    def test_windows_git_root_slashes_preserve_physical_identity(self):
        # Git returns forward slashes while native Windows Path spells backslashes.
        depot = self.base.resolve()
        forward = depot.as_posix()
        self.assertIn('\\', str(depot))
        self.assertEqual(Path(forward).resolve(), depot)
        self.assertEqual(Path(forward + '/.').resolve(), depot)
        self.assertNotEqual(Path(forward + '/other').resolve(), depot)

    def test_ninja_resolves_real_executable_and_rejects_context_dependent_shim(self):
        shim = self.write(self.base, 'ninja-shim.cmd' if os.name == 'nt' else 'ninja-shim', '#!/bin/sh\nexec other-ninja "$@"\n')
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
    def test_signing_page_size_normalizes_vm_allocation_and_rejects_changed_or_malformed_code(self):
        with tempfile.TemporaryDirectory(prefix='lineup ax signing pages ') as temporary:
            root = Path(temporary)
            source = root / 'fixture.c'
            source.write_text('unsigned char blob[2097152] = {1};\n'
                              'int main(int argc, char** argv) { return blob[(unsigned)argc % sizeof(blob)]; }\n')
            binary = root / 'built'
            subprocess.run(['clang', str(source), '-o', str(binary)], check=True, capture_output=True)
            copies = []
            removed_hashes = []
            for page_size in ('4096', '16384'):
                signed = root / ('signed-' + page_size)
                shutil.copy2(binary, signed)
                subprocess.run(['codesign', '--force', '--sign', '-', '--identifier', 'lineup.fixture',
                                '--pagesize', page_size, '--timestamp=none', str(signed)], check=True, capture_output=True)
                copies.append(signed)
                removed = root / ('removed-' + page_size)
                shutil.copy2(signed, removed)
                subprocess.run(['codesign', '--remove-signature', str(removed)], check=True, capture_output=True)
                removed_hashes.append(ax.file_hash(removed))
            originals = [ax.file_hash(path) for path in copies]
            # The old remove-signature-only comparison rejects identical code.
            self.assertNotEqual(*removed_hashes)
            self.assertEqual(ax.executable_hash(copies[0]), ax.executable_hash(copies[1]))
            self.assertEqual(originals, [ax.file_hash(path) for path in copies])
            data = bytearray(copies[0].read_bytes())
            commands = struct.unpack_from('<I', data, 16)[0]
            offset = 32
            signature_offset = None
            text_offset = None
            for _ in range(commands):
                command, size = struct.unpack_from('<II', data, offset)
                if command == 0x1d:  # LC_CODE_SIGNATURE
                    signature_offset = offset
                if command == 0x19 and data[offset + 8:offset + 24].rstrip(b'\0') == b'__TEXT':
                    section_count = struct.unpack_from('<I', data, offset + 64)[0]
                    for section in range(section_count):
                        section_offset = offset + 72 + section * 80
                        if data[section_offset:section_offset + 16].rstrip(b'\0') == b'__text':
                            text_offset = struct.unpack_from('<I', data, section_offset + 48)[0]
                offset += size
            self.assertIsNotNone(text_offset)
            self.assertIsNotNone(signature_offset)
            changed = root / 'changed-code'
            changed_bytes = bytearray(data)
            changed_bytes[text_offset] ^= 1
            changed.write_bytes(changed_bytes)
            self.assertNotEqual(ax.executable_hash(copies[0]), ax.executable_hash(changed))
            malformed = {
                'truncated': data[:40],
                'invalid-command-size': bytearray(data),
                'signature-outside-file': bytearray(data),
            }
            struct.pack_into('<I', malformed['invalid-command-size'], 36, 4)
            struct.pack_into('<I', malformed['signature-outside-file'], signature_offset + 8, len(data) + 4096)
            for name, contents in malformed.items():
                path = root / name
                path.write_bytes(contents)
                with self.subTest(name=name), self.assertRaises(ax.VerificationError):
                    ax.executable_hash(path)

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
