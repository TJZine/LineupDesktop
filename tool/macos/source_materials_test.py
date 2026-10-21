#!/usr/bin/env python3
"""Controlled source-delivery fixtures; no builds, signing, fetches or Git writes."""
import importlib.util
import json
import os
import plistlib
import stat
import shutil
from pathlib import Path
import tempfile
import zipfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('materials', Path(__file__).with_name('source_materials.py'))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class SourceMaterialsTests(unittest.TestCase):
    def test_generated_assets_match_recipe_and_pins(self):
        # Assets are content-addressable source snapshots, including the recipe
        # helper closure and Mac patches; no Windows DC patch is selected.
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            sdk = root / 'sdk'
            sdk.mkdir()
            (sdk / 'LICENSE').write_text('Fixture BSD terms')
            output = root / 'assets'
            with patch.object(m, 'runtime_sources', return_value=[]):
                m.write_assets(sdk, output)
                m.write_assets(sdk, output, check=True)
            self.assertIn('fast_float', (output / 'source-inventory.txt').read_text())
            self.assertIn('SPIRV-Headers', (output / 'source-inventory.txt').read_text())
            for helper in m.HELPERS:
                self.assertEqual((output / (helper.replace('/', '__') + '.txt')).read_bytes(),
                                 (m.REPOSITORY / helper).read_bytes())
            (output / 'source-inventory.txt').write_text('stale')
            with patch.object(m, 'runtime_sources', return_value=[]):
                with self.assertRaises(ValueError): m.write_assets(sdk, output, check=True)

    def test_manifest_rejects_extra_missing_changed_and_escaping_material(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / 'delivery'
            output.mkdir()
            source = output / 'source.tar'
            source.write_bytes(b'original source archive')
            manifest = dict(schemaVersion=1, files={'source.tar': m.digest(source)})
            (output / 'manifest.json').write_text(json.dumps(manifest))
            m.verify(output)
            (output / 'empty-directory').mkdir()
            m.verify(output)
            external_directory = Path(temporary) / 'external-directory'
            external_directory.mkdir()
            redirect = output / 'directory-symlink'
            redirect.symlink_to(external_directory, target_is_directory=True)
            with self.assertRaises(ValueError): m.verify(output)
            redirect.unlink()
            fifo = output / 'unexpected-fifo'
            os.mkfifo(fifo)
            with self.assertRaises(ValueError): m.verify(output)
            fifo.unlink()
            m.verify(output)
            source.write_bytes(b'changed')
            with self.assertRaises(ValueError): m.verify(output)
            source.write_bytes(b'original source archive')
            extra = output / 'unexpected'
            extra.write_text('extra')
            with self.assertRaises(ValueError): m.verify(output)
            extra.unlink()
            source.unlink()
            with self.assertRaises(ValueError): m.verify(output)
            external = Path(temporary) / 'private-source'
            external.write_bytes(b'original source archive')
            source.symlink_to(external)
            with self.assertRaises(ValueError): m.verify(output)

    def test_runtime_recipe_patch_binding(self):
        with tempfile.TemporaryDirectory() as temporary:
            runtime = Path(temporary)
            lines = ['Pin file SHA-256: ' + m.digest(m.REPOSITORY / 'tool/macos/mpv-runtime.lock')]
            for relative in m.HELPERS:
                patch_file = m.REPOSITORY / relative
                if relative.startswith('tool/macos/') and patch_file.suffix == '.patch':
                    family = 'mpv' if patch_file.parent.name == 'mpv-patches' else 'ffmpeg'
                    target = runtime / 'patches' / family / patch_file.name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(patch_file, target)
                    lines.append('  ' + patch_file.parent.name + '/' + patch_file.name + ' ' + m.digest(patch_file))
            (runtime / 'BUILD-INFO.txt').write_text('\n'.join(lines))
            m.validate_runtime(runtime)
            target.write_text('wrong patch')
            with self.assertRaises(ValueError): m.validate_runtime(runtime)
            (runtime / 'BUILD-INFO.txt').write_text('wrong pin file hash')
            with self.assertRaises(ValueError): m.validate_runtime(runtime)

    def test_bounded_companion_assembly_preserves_archives_and_refuses_partial_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / 'original.tar.xz'
            archive.write_bytes(b'small exact source archive fixture')
            record = dict(name='component', url='https://example.invalid/source.tar.xz',
                          sha256=m.digest(archive), path=archive, kind='archive')
            output = root / 'companion'
            identity = dict(sourceCommit='a' * 40, candidateSha256='b' * 64)
            m.assemble([record], {'build.sh': b'build recipe'}, identity, output, 1)
            m.verify(output)
            manifest = json.loads((output / 'manifest.json').read_text())
            self.assertEqual(manifest['candidateSha256'], 'b' * 64)
            self.assertEqual((output / manifest['sources'][0]['file']).read_bytes(), archive.read_bytes())
            self.assertNotIn(str(root), json.dumps(manifest))
            with self.assertRaises(ValueError): m.assemble([record], {}, identity, output, 1)
            other = root / 'not-published'
            with self.assertRaises(ValueError): m.assemble([record], {}, identity, other, 0)
            self.assertFalse(other.exists())
            archive.write_bytes(b'tampered after inventory')
            with self.assertRaises(ValueError): m.assemble([record], {}, identity, other, 1)
            self.assertFalse(other.exists())
            self.assertFalse(list(root.glob('.lineup-sources-*')))

    def candidate_fixture(self, root):
        app = root / 'Fixture.app'
        runtime = root / 'runtime'
        for relative in ['licenses/mpv/LICENSE.LGPL', 'patches/mpv/fix.patch', 'BUILD-INFO.txt']:
            for base in [runtime, app / 'Contents/Resources/LineupNativeRuntime']:
                path = base / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('Fixture immutable content')
        raw = root / 'raw-engine'
        raw.write_bytes(b'raw engine bytes')
        embedded = app / 'Contents/Frameworks/FlutterMacOS.framework/Versions/A/FlutterMacOS'
        embedded.parent.mkdir(parents=True)
        embedded.write_bytes(b'engine bytes with app signing')
        executable = app / 'Contents/MacOS/Fixture'
        executable.parent.mkdir(parents=True)
        executable.write_bytes(b'app executable')
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable': 'Fixture'}))
        (app / 'Contents/ExecutableLink').symlink_to('MacOS/Fixture')
        def artifact_map(app):
            return {str(p.relative_to(app)): dict(symlink=os.readlink(p)) if p.is_symlink()
                    else dict(sha256=m.digest(p), mode=p.stat().st_mode & 0o777)
                    for p in app.rglob('*') if p.is_file() or p.is_symlink()}
        artifacts = artifact_map(app)
        selected = dict(kind='verified-local-desktop-accessibility', binary=str(raw), binarySha256=m.digest(raw))
        recipe = dict(engine=selected, appCommit='a' * 40)
        receipt = dict(recipe=recipe, bundleArtifacts=artifacts)
        sidecar = root / 'Fixture.app.build-receipt.json'
        sidecar.write_text(json.dumps(receipt))
        final = dict(schemaVersion=1, kind=selected['kind'], engine=selected,
            buildReceiptSha256=m.digest(sidecar), buildRecipe=recipe, bundleArtifacts=artifacts,
            appCommit=recipe['appCommit'], appVersion='0.1.0+1', builtEngineSha256=m.digest(raw),
            bundledEngineSha256=m.digest(embedded), unsignedExecutableSha256='c' * 64,
            appExecutableSha256=m.digest(executable), infoPlistSha256=m.digest(app / 'Contents/Info.plist'))
        final_path = root / 'Fixture.app.engine-provenance.json'
        final_path.write_text(json.dumps(final))
        candidate = root / 'candidate.zip'
        def package():
            with zipfile.ZipFile(candidate, 'w') as archive:
                archive.writestr('Fixture.app/', b'')
                archive.writestr('Fixture.app/safe-empty-directory/', b'')
                for path in app.rglob('*'):
                    name = 'Fixture.app/' + str(path.relative_to(app))
                    if path.is_symlink():
                        entry = zipfile.ZipInfo(name)
                        entry.create_system = 3
                        entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                        archive.writestr(entry, os.readlink(path))
                    elif path.is_file():
                        archive.write(path, name)
        package()
        def validate(repository, expected, recipe):
            m.require(expected == recipe['engine'], 'engine mismatch')
            return '0.1.0+1'
        engine = SimpleNamespace(APP_RECEIPT_SUFFIX='.build-receipt.json',
            validate_recipe=validate, bundle_artifacts=artifact_map)
        args = SimpleNamespace(app=app, candidate=candidate)
        return SimpleNamespace(engine=engine, selected=selected, args=args, runtime=runtime,
            receipt_path=sidecar, final_path=final_path, final=final, package=package, raw=raw)

    def test_candidate_binding_checks_receipt_zip_and_native_resources(self):
        with tempfile.TemporaryDirectory() as temporary:
            f = self.candidate_fixture(Path(temporary))
            result = m.validate_candidate(f.engine, f.selected, f.args, f.runtime)
            self.assertEqual(result, dict(appBuildReceiptSha256=m.digest(f.receipt_path),
                appEngineProvenanceSha256=m.digest(f.final_path)))
            with self.assertRaises(ValueError): m.validate_candidate(f.engine, {}, f.args, f.runtime)
            with zipfile.ZipFile(f.args.candidate, 'a') as archive: archive.writestr('outside', b'extra')
            with self.assertRaises(ValueError): m.validate_candidate(f.engine, f.selected, f.args, f.runtime)
            f.package()
            (f.runtime / 'BUILD-INFO.txt').write_text('other runtime identity')
            with self.assertRaises(ValueError): m.validate_candidate(f.engine, f.selected, f.args, f.runtime)
            (f.runtime / 'BUILD-INFO.txt').write_text('Fixture immutable content')
            m.validate_candidate(f.engine, f.selected, f.args, f.runtime)

    def test_zip_directory_path_and_type_bypasses_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            f = self.candidate_fixture(Path(temporary))
            bad_names = ['unrelated/', '../escape/', '/Fixture.app/absolute/',
                'Fixture.app/../../escape/', 'Fixture.app//empty/', 'Fixture.app/./empty/',
                'Fixture.app/back\\slash/', 'Fixture.app/null\x00suffix/']
            for name in bad_names:
                f.package()
                with zipfile.ZipFile(f.args.candidate, 'a') as archive: archive.writestr(name, b'')
                with self.subTest(name=name):
                    with self.assertRaises(ValueError): m.validate_candidate(f.engine, f.selected, f.args, f.runtime)
            for mode, name in [(stat.S_IFIFO, 'Fixture.app/extra/'),
                               (stat.S_IFLNK, 'Fixture.app/link/'),
                               (stat.S_IFDIR, 'Fixture.app/missing-directory-slash')]:
                f.package()
                entry = zipfile.ZipInfo(name)
                entry.create_system = 3
                entry.external_attr = (mode | 0o755) << 16
                with zipfile.ZipFile(f.args.candidate, 'a') as archive: archive.writestr(entry, b'')
                with self.assertRaises(ValueError): m.validate_candidate(f.engine, f.selected, f.args, f.runtime)
            f.package()
            m.validate_candidate(f.engine, f.selected, f.args, f.runtime)

    def test_completed_engine_sidecar_is_required_and_binds_actual_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            f = self.candidate_fixture(Path(temporary))
            f.final_path.unlink()
            with self.assertRaises(ValueError): m.validate_candidate(f.engine, f.selected, f.args, f.runtime)
            for key, value in [('schemaVersion', 2), ('engine', {}), ('kind', 'other'),
                ('buildReceiptSha256', '0' * 64), ('bundleArtifacts', {}), ('buildRecipe', {}),
                ('appCommit', 'b' * 40), ('appVersion', '0.0.0'), ('builtEngineSha256', '0' * 64),
                ('bundledEngineSha256', '0' * 64), ('unsignedExecutableSha256', None),
                ('appExecutableSha256', '0' * 64), ('infoPlistSha256', '0' * 64)]:
                f.final_path.write_text(json.dumps(dict(f.final, **{key: value})))
                with self.subTest(field=key):
                    with self.assertRaises(ValueError): m.validate_candidate(f.engine, f.selected, f.args, f.runtime)
            f.final_path.write_text(json.dumps(f.final))
            m.validate_candidate(f.engine, f.selected, f.args, f.runtime)
            original = f.raw.read_bytes()
            f.raw.write_bytes(b'different raw engine')
            with self.assertRaises(ValueError): m.validate_candidate(f.engine, f.selected, f.args, f.runtime)
            f.raw.write_bytes(original)
            # A refreshed pre-comparison receipt does not refresh the completed envelope.
            embedded = f.args.app / 'Contents/Frameworks/FlutterMacOS.framework/Versions/A/FlutterMacOS'
            embedded.write_bytes(b'different embedded engine')
            receipt = json.loads(f.receipt_path.read_text())
            receipt['bundleArtifacts'] = f.engine.bundle_artifacts(f.args.app)
            f.receipt_path.write_text(json.dumps(receipt))
            f.package()
            with self.assertRaises(ValueError): m.validate_candidate(f.engine, f.selected, f.args, f.runtime)

    def test_runtime_archive_integrity_and_nested_git_pins(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'downloads').mkdir()
            archive = root / 'downloads/example.tar.xz'
            archive.write_bytes(b'archive fixture')
            values = {'ONE_VERSION': '1', 'ONE_URL': 'https://example.invalid/example.tar.xz',
                      'ONE_SHA256': m.digest(archive)}
            with patch.object(m, 'PRINCIPAL', ['ONE']), patch.object(m, 'pins', return_value=(values, {})):
                self.assertEqual(len(m.runtime_sources(root)), 1)
                archive.write_bytes(b'tampered')
                with self.assertRaises(ValueError): m.runtime_sources(root)
            values = {'LIBPLACEBO_VERSION': '1', 'LIBPLACEBO_GIT': 'https://example.invalid/repo.git',
                      'LIBPLACEBO_COMMIT': 'a' * 40}
            def git(path, *args):
                if args[0] == 'rev-parse': return 'a' * 40
                if args[0] == 'submodule': return ' ' + 'b' * 40 + ' 3rdparty/fast_float (fixture)'
                return 'https://example.invalid/fast_float.git'
            with patch.object(m, 'PRINCIPAL', ['LIBPLACEBO']), patch.object(m, 'pins', return_value=(values, {})), patch.object(m, 'git', side_effect=git):
                records = m.runtime_sources(root)
                self.assertEqual(records[1]['revision'], 'b' * 40)
                self.assertEqual(records[1]['name'], 'libplacebo/3rdparty/fast_float')
                with patch.object(m, 'git', return_value='wrong revision'):
                    with self.assertRaises(ValueError): m.runtime_sources(root)


if __name__ == '__main__': unittest.main()
