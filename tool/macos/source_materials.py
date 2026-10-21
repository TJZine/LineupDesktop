#!/usr/bin/env python3
"""Prepare offline R-03 materials from pinned local inputs; never fetch or sign.

assets regenerates the small in-app source/recipe texts. prepare creates a new
companion directory, binding sources to a candidate and verified engine. It uses
canonical engine verification before archiving Git source snapshots. No app,
runtime or engine output is modified. verify checks all delivered hashes.
"""
import argparse
import hashlib
import importlib.util
import json
import os
import plistlib
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
import zipfile
from urllib.parse import urlsplit

REPOSITORY = Path(__file__).resolve().parents[2]
PRINCIPAL = 'MPV FFMPEG LIBPLACEBO GLSLANG MOLTENVK OPENSSL CURL LCMS2 DAV1D FREETYPE FRIBIDI HARFBUZZ LIBASS'.split()
HELPERS = [
    'tool/macos/build-mpv.sh', 'tool/macos/mpv-runtime.lock',
    'tool/macos/collect-notices.py', 'tool/macos/runtime-smoke.c',
    'tool/macos/runtime-smoke-layer.m', 'tool/macos/source_materials.py',
    'tool/flutter_version.json', 'tool/windows/build-metadata.psd1',
    'tool/flutter_engine/desktop-accessibility.json',
    'tool/flutter_engine/desktop_accessibility.py', 'tool/flutter_engine/README.md',
    'tool/macos/build_app.dart', 'docs/DEVELOPMENT.md', 'LICENSE',
    'tool/flutter_engine/0001-windows-direct-composition.patch',
    'tool/flutter_engine/0002-desktop-accessibility.patch',
    'tool/flutter_engine/0003-macos-apple-linker.patch',
    'tool/flutter_engine/0004-windows-test-fixtures.patch',
    'docs/licenses-and-rebuilding.md',
]
HELPERS += [str(p.relative_to(REPOSITORY)) for directory in ['mpv-patches', 'ffmpeg-patches']
            for p in sorted((REPOSITORY / 'tool/macos' / directory).glob('*.patch'))]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    value = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for data in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(data)
    return value.hexdigest()


def git(path, *args):
    return subprocess.check_output(['git', '-C', str(path), *args], stderr=subprocess.PIPE).decode().rstrip('\n')


def pins():
    text = (REPOSITORY / 'tool/macos/mpv-runtime.lock').read_text()
    values = {}
    for match in re.finditer(r'^([A-Z0-9_]+)=(?:"([^"\n]*)"|([^\s#]+))', text, re.M):
        values[match[1]] = match[2] if match[2] is not None else match[3]
    external = dict(re.findall(r'^  ([\w-]+)=([a-f0-9]{40})$', text, re.M))
    return values, external


def runtime_sources(runtime_root):
    values, external = pins()
    records = []
    for name in PRINCIPAL:
        version = values[name + '_VERSION']
        directory = runtime_root / 'src' / (name.lower() + '-' + version)
        if name + '_URL' in values:
            url = values[name + '_URL']
            archive = runtime_root / 'downloads' / urlsplit(url).path.split('/')[-1]
            expected = values[name + '_SHA256']
            require(archive.is_file() and not archive.is_symlink() and digest(archive) == expected,
                    'Missing or mismatched pinned archive: ' + name)
            records.append(dict(name=name, url=url, sha256=expected, path=archive, kind='archive'))
        else:
            revision = values[name + '_COMMIT']
            require(git(directory, 'rev-parse', 'HEAD') == revision, 'Source revision mismatch: ' + name)
            records.append(dict(name=name, url=values[name + '_GIT'], revision=revision, path=directory, kind='git'))
            if name == 'LIBPLACEBO':
                for line in git(directory, 'submodule', 'status', '--recursive').splitlines():
                    require(line.startswith(' '), 'Unpinned or missing libplacebo submodule')
                    revision, relative = line.split()[:2]
                    child = directory / relative
                    records.append(dict(name='libplacebo/' + relative,
                        url=git(child, 'remote', 'get-url', 'origin'), revision=revision, path=child, kind='git'))
            if name == 'MOLTENVK':
                for relative, revision in external.items():
                    child = directory / 'External' / relative
                    if relative == 'SPIRV-Headers':
                        child = directory / 'External/SPIRV-Tools/external/spirv-headers'
                    require(git(child, 'rev-parse', 'HEAD') == revision,
                            'MoltenVK dependency revision mismatch: ' + relative)
                    records.append(dict(name='moltenvk/' + relative,
                        url=git(child, 'remote', 'get-url', 'origin'), revision=revision, path=child, kind='git'))
    for entry in records:
        url = urlsplit(entry['url'])
        require(url.scheme == 'https' and url.hostname and not url.username and not url.password and
                not url.query and not url.fragment, 'Only public credential-free source URLs may be exported')
    return records


def catalog(runtime_root):
    values, external = pins()
    lines = ['Exact macOS runtime source inventory', '',
        'Source archives and Git snapshots accompany the candidate separately.',
        'Integrity pins below identify source inputs, not signed package hashes.', '']
    for name in PRINCIPAL:
        lines += [name + ' ' + values[name + '_VERSION'],
                  values.get(name + '_URL', values.get(name + '_GIT', '')),
                  'SHA-256: ' + values[name + '_SHA256'] if name + '_SHA256' in values
                  else 'Git commit: ' + values[name + '_COMMIT'], '']
    lines += ['MoltenVK nested dependencies (including build-only inputs):']
    urls = {'Vulkan-Headers': 'KhronosGroup/Vulkan-Headers', 'SPIRV-Cross': 'KhronosGroup/SPIRV-Cross',
            'SPIRV-Headers': 'KhronosGroup/SPIRV-Headers', 'SPIRV-Tools': 'KhronosGroup/SPIRV-Tools',
            'Vulkan-Tools': 'KhronosGroup/Vulkan-Tools', 'Volk': 'zeux/volk', 'cereal': 'USCiLab/cereal'}
    for name, revision in external.items():
        lines += [name + ': https://github.com/' + urls[name] + '/tree/' + revision]
    # Exact nested pin is in the parent Git tree, not an independently selected version.
    lines += ['', 'libplacebo nested sources:',
        'https://code.videolan.org/videolan/libplacebo/-/tree/' + values['LIBPLACEBO_COMMIT'] + '/3rdparty',
        'fast_float and other recursive submodule commits are pinned by this exact parent tree.',
        'The companion manifest records each resolved submodule commit and archive hash.',
        '', 'Flutter source:', 'https://github.com/flutter/flutter/tree/' +
        json.loads((REPOSITORY / 'tool/flutter_version.json').read_text())['frameworkRevision'],
        'Flutter DEPS and the selected engine receipt pin its full evaluated Git dependency graph.',
        'The companion contains baseline source snapshots plus the macOS patches and build recipe.',
        'Its manifest binds these to the selected engine and final candidate; no stock-engine claim is made.']
    return '\n'.join(lines) + '\n'


def asset_files(flutter_sdk, runtime_root):
    files = {'source-inventory.txt': catalog(runtime_root).encode(),
             'rebuilding.txt': (REPOSITORY / 'docs/licenses-and-rebuilding.md').read_bytes(),
             'engine-notices.txt': ('''Lineup macOS Flutter engine notices

The macOS engine uses Flutter's BSD-3-Clause sources with the repository's
accessibility patch and, when selected by its receipt, Apple-linker build patch.
The Windows DirectComposition patch is not applied to the macOS engine.
Flutter and dependency notices are also available under Flutter and packages.
The exact framework pin, patch hashes and build instructions are readable under
Sources and rebuilding. The selected engine receipt accompanies the candidate.

''' + (flutter_sdk / 'LICENSE').read_text()).encode()}
    entries = [('Credits and library replacement notice', 'rebuilding.txt'),
               ('Exact source inventory', 'source-inventory.txt')]
    for relative in HELPERS:
        filename = relative.replace('/', '__') + '.txt'
        files[filename] = (REPOSITORY / relative).read_bytes()
        entries.append((relative, filename))
    files['index.txt'] = ''.join(title + '\t' + name + '\n' for title, name in entries).encode()
    return files


def write_assets(flutter_sdk, output, check=False, runtime_root=REPOSITORY / 'build/macos-runtime'):
    files = asset_files(flutter_sdk, runtime_root)
    if check:
        require(set(p.name for p in output.iterdir()) == set(files), 'Stale generated asset set')
        require(all((output / name).read_bytes() == data for name, data in files.items()), 'Stale generated assets')
    else:
        output.mkdir(parents=True, exist_ok=True)
        require(not any(p.name not in files for p in output.iterdir()), 'Unexpected asset destination content')
        for name, data in files.items():
            (output / name).write_bytes(data)


def path_parts(name, directory=False):
    require(isinstance(name, str) and name and '\\' not in name and
            all(ord(character) >= 32 and ord(character) != 127 for character in name),
            'Malformed delivery path')
    value = name[:-1] if directory and name.endswith('/') else name
    parts = value.split('/')
    require(all(part not in ['', '.', '..'] for part in parts), 'Unsafe delivery path')
    return parts


def companion_files(output):
    require(stat.S_ISDIR(output.lstat().st_mode), 'Companion root must be a real directory')
    files = set()
    def visit(directory):
        with os.scandir(directory) as entries:
            for entry in entries:
                relative = str(Path(entry.path).relative_to(output))
                path_parts(relative)
                mode = entry.stat(follow_symlinks=False).st_mode
                if stat.S_ISDIR(mode):
                    visit(Path(entry.path))
                else:
                    require(stat.S_ISREG(mode), 'Companion contains a symlink or special entry')
                    files.add(relative)
    visit(output)
    return files


def validate_completed_bundle(engine, selected, app, app_receipt, artifacts, version):
    receipt_path = app.parent / (app.name + engine.APP_RECEIPT_SUFFIX)
    final_path = app.parent / (app.name + '.engine-provenance.json')
    require(final_path.is_file() and not final_path.is_symlink(), 'Completed engine comparison is missing')
    final = json.loads(final_path.read_text())
    require(final.get('schemaVersion') == 1 and final.get('kind') == selected['kind'] and
            final.get('engine') == selected, 'Completed engine comparison selects another engine')
    require(final.get('buildReceiptSha256') == digest(receipt_path) and
            final.get('buildRecipe') == app_receipt['recipe'] and
            final.get('bundleArtifacts') == artifacts and
            final.get('appCommit') == app_receipt['recipe']['appCommit'] and
            final.get('appVersion') == version, 'Completed engine comparison is stale')
    built = Path(selected['binary'])
    embedded = app / 'Contents/Frameworks/FlutterMacOS.framework/Versions/A/FlutterMacOS'
    require(embedded.is_file() and embedded.resolve().is_relative_to(app.resolve()),
            'Embedded engine is missing or escapes the app')
    require(final.get('builtEngineSha256') == digest(built) == selected['binarySha256'] and
            final.get('bundledEngineSha256') == digest(embedded), 'Completed engine binary identity differs')
    # bundle() writes this envelope only after normalized executable equality.
    # Bind its raw files/receipt now without repeating codesign normalization.
    require(isinstance(final.get('unsignedExecutableSha256'), str) and
            re.fullmatch(r'[0-9a-f]{64}', final['unsignedExecutableSha256']),
            'Completed engine comparison lacks its normalized executable identity')
    info_path = app / 'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    executable_name = info.get('CFBundleExecutable')
    require(len(path_parts(executable_name)) == 1, 'Invalid app executable name')
    executable = app / 'Contents/MacOS' / executable_name
    require(executable.is_file() and executable.resolve().is_relative_to(app.resolve()) and
            final.get('appExecutableSha256') == digest(executable) and
            final.get('infoPlistSha256') == digest(info_path), 'Completed app identity differs')
    return digest(final_path)


def validate_candidate(engine, receipt, args, runtime):
    app_receipt = json.loads((args.app.parent / (args.app.name + engine.APP_RECEIPT_SUFFIX)).read_text())
    version = engine.validate_recipe(REPOSITORY, receipt, app_receipt['recipe'])
    artifacts = engine.bundle_artifacts(args.app)
    require(app_receipt.get('bundleArtifacts') == artifacts, 'Candidate bundle differs from build receipt')
    final_digest = validate_completed_bundle(engine, receipt, args.app, app_receipt, artifacts, version)
    with zipfile.ZipFile(args.candidate) as candidate:
        seen = set()
        archived_files = set()
        for entry in candidate.infolist():
            require(entry.orig_filename == entry.filename, 'Malformed original ZIP name')
            parts = path_parts(entry.filename, directory=entry.is_dir())
            require(parts[0] == args.app.name, 'Candidate archive root differs')
            canonical = '/'.join(parts)
            require(canonical not in seen, 'Duplicate candidate archive entry')
            seen.add(canonical)
            kind = stat.S_IFMT(entry.external_attr >> 16)
            if entry.is_dir():
                require(kind in [0, stat.S_IFDIR] and entry.file_size == 0,
                        'Candidate directory has an invalid type or payload')
                continue
            require(len(parts) > 1 and kind in [0, stat.S_IFREG, stat.S_IFLNK],
                    'Candidate file has an invalid type')
            relative = '/'.join(parts[1:])
            require(relative in artifacts, 'Candidate archive member differs')
            archived_files.add(relative)
            expected = artifacts[relative]
            if 'symlink' in expected:
                require(stat.S_ISLNK(entry.external_attr >> 16) and
                        entry.file_size == len(expected['symlink'].encode()) and
                        candidate.read(entry) == expected['symlink'].encode(), 'Candidate symlink differs')
            else:
                require(not stat.S_ISLNK(entry.external_attr >> 16) and
                        entry.file_size == (args.app / relative).stat().st_size and
                        (entry.external_attr >> 16) & 0o777 == expected['mode'], 'Candidate file metadata differs')
                value = hashlib.sha256()
                with candidate.open(entry) as stream:
                    for data in iter(lambda: stream.read(1024 * 1024), b''): value.update(data)
                require(value.hexdigest() == expected['sha256'], 'Candidate archive bytes differ')
        require(archived_files == set(artifacts), 'Candidate archive file set differs')
    for tree in ['licenses', 'patches']:
        expected = {str(p.relative_to(runtime)): digest(p) for p in (runtime / tree).rglob('*') if p.is_file()}
        installed = args.app / 'Contents/Resources/LineupNativeRuntime'
        actual = {str(p.relative_to(installed)): digest(p) for p in (installed / tree).rglob('*') if p.is_file()}
        require(actual == expected, 'Candidate native notice/patch tree differs')
    require(digest(args.app / 'Contents/Resources/LineupNativeRuntime/BUILD-INFO.txt') ==
            digest(runtime / 'BUILD-INFO.txt'), 'Candidate runtime identity differs')
    return dict(appBuildReceiptSha256=digest(args.app.parent / (args.app.name + engine.APP_RECEIPT_SUFFIX)),
                appEngineProvenanceSha256=final_digest)


def validate_runtime(runtime):
    info = (runtime / 'BUILD-INFO.txt').read_text()
    require('Pin file SHA-256: ' + digest(REPOSITORY / 'tool/macos/mpv-runtime.lock') in info,
            'Prepared runtime lock identity differs')
    for relative in HELPERS:
        patch = REPOSITORY / relative
        if relative.startswith('tool/macos/') and patch.suffix == '.patch':
            expected = digest(patch)
            require('  ' + patch.parent.name + '/' + patch.name + ' ' + expected in info,
                    'Prepared runtime patch identity differs')
            family = 'mpv' if patch.parent.name == 'mpv-patches' else 'ffmpeg'
            require(digest(runtime / 'patches' / family / patch.name) == expected,
                    'Prepared runtime patch bytes differ')


def prepare(args):
    require(not args.output.exists(), 'Output must be a new owned directory')
    require(args.candidate.is_file() and not args.candidate.is_symlink(), 'Candidate archive is required')
    root = args.runtime_root.resolve()
    runtime = root / 'dist/arm64'
    validate_runtime(runtime)
    records = runtime_sources(root)
    records.append(dict(name='lineup-desktop', path=REPOSITORY, revision=git(REPOSITORY, 'rev-parse', 'HEAD'),
                        url='https://github.com/TJZine/LineupDesktop.git', kind='git'))
    spec = importlib.util.spec_from_file_location('lineup_engine', REPOSITORY / 'tool/flutter_engine/desktop_accessibility.py')
    engine = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(engine)
    # The controller runs this after its final engine verification. This call
    # rechecks source, dependency and artifact identity; it never builds/signs.
    receipt = engine.verify(REPOSITORY, args.flutter_root.resolve(), args.engine_output, 'macos', 'arm64', 'release')
    candidate_identity = validate_candidate(engine, receipt, args, runtime)
    source = json.loads((args.flutter_root / 'engine/src/out' / args.engine_output / engine.PROVENANCE).read_text())['source']
    framework = json.loads((REPOSITORY / 'tool/flutter_version.json').read_text())['frameworkRevision']
    records.append(dict(name='flutter', path=args.flutter_root, revision=framework,
                        url='https://github.com/flutter/flutter.git', kind='git'))
    for name, entry in source['dependencies']['gitDependencies'].items():
        records.append(dict(name='flutter-deps/' + name, path=args.flutter_root / name,
                            revision=entry['revision'], url=entry['url'], kind='git'))
    source_commit = git(REPOSITORY, 'rev-parse', 'HEAD')
    identity = dict(sourceCommit=source_commit,
        candidateSha256=digest(args.candidate), **candidate_identity,
        runtimeBuildInfoSha256=digest(runtime / 'BUILD-INFO.txt'),
        engineBinarySha256=receipt['binarySha256'], engineProvenanceSha256=receipt['provenanceSha256'])
    # Read exact committed helper bytes, not mutable working-tree snapshots.
    helpers = {relative: subprocess.check_output(
        ['git', '-C', str(REPOSITORY), 'show', source_commit + ':' + relative], stderr=subprocess.PIPE)
        for relative in HELPERS}
    assemble(records, helpers, identity, args.output, args.max_gib)


def assemble(records, helpers, identity, output, max_gib):
    require(not output.exists(), 'Output must be a new owned directory')
    # Require a conservative ceiling before creating archives. No large copy is
    # attempted silently; caller chooses its disk budget explicitly.
    require(max_gib > 0, 'A positive explicit capacity budget is required')
    estimate = 0
    for entry in records:
        if entry['kind'] == 'archive': estimate += entry['path'].stat().st_size
        else:
            for line in git(entry['path'], 'ls-tree', '-rl', entry['revision']).splitlines():
                fields = line.split(None, 4)
                if fields[1] == 'blob': estimate += int(fields[3]) + 1024
    estimate += 16 * 1024 * 1024  # recipe and manifest allowance
    for entry in records:
        url = urlsplit(entry['url'])
        require(url.scheme == 'https' and url.hostname and not url.username and not url.password and
                not url.query and not url.fragment, 'Only public credential-free source URLs may be exported')
    budget = max_gib * 1024**3
    require(estimate <= budget, 'Source size estimate exceeds the approved budget')
    require(shutil.disk_usage(output.parent).free > estimate * 2 + 1024**3,
            'Insufficient capacity for source assembly and safety reserve')
    with tempfile.TemporaryDirectory(prefix='.lineup-sources-', dir=output.parent) as temporary:
        stage = Path(temporary)
        deliveries = []
        for number, entry in enumerate(records):
            target = stage / (str(number) + ('.tar' if entry['kind'] == 'git' else '-' + entry['path'].name))
            if entry['kind'] == 'git':
                with target.open('wb') as stream:
                    subprocess.run(['git', '-C', str(entry['path']), 'archive', '--format=tar', entry['revision']],
                                   stdout=stream, stderr=subprocess.PIPE, check=True)
            else:
                shutil.copyfile(entry['path'], target)
                require(digest(target) == entry['sha256'], 'Source archive changed during assembly')
            require(sum(p.stat().st_size for p in stage.iterdir() if p.is_file()) <= budget,
                    'Source assembly exceeded the approved budget')
            deliveries.append({key: value for key, value in entry.items() if key not in ['path', 'kind']} |
                              dict(file=target.name, sha256=digest(target)))
        for relative, data in helpers.items():
            target = stage / 'recipe' / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        manifest = dict(identity, schemaVersion=1, sources=deliveries,
            files={str(p.relative_to(stage)): digest(p) for p in sorted(stage.rglob('*')) if p.is_file()})
        (stage / 'manifest.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
        verify(stage)
        os.rename(stage, output)


def verify(output):
    actual = companion_files(output)
    manifest = json.loads((output / 'manifest.json').read_text())
    require(manifest['schemaVersion'] == 1, 'Unsupported companion manifest')
    require(actual == set(manifest['files']) | {'manifest.json'}, 'Companion file set differs')
    for relative, expected in manifest['files'].items():
        path_parts(relative)
        path = output / relative
        require(not Path(relative).is_absolute() and '..' not in Path(relative).parts and
                not path.is_symlink() and path.resolve().is_relative_to(output.resolve()) and
                digest(path) == expected, 'Companion hash or containment mismatch')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    assets = sub.add_parser('assets')
    assets.add_argument('--flutter-sdk', type=Path, required=True)
    assets.add_argument('--output', type=Path, default=REPOSITORY / 'assets/licenses')
    assets.add_argument('--check', action='store_true')
    assets.add_argument('--runtime-root', type=Path, default=REPOSITORY / 'build/macos-runtime')
    assembly = sub.add_parser('prepare')
    assembly.add_argument('--runtime-root', type=Path, required=True)
    assembly.add_argument('--flutter-root', type=Path, required=True)
    assembly.add_argument('--engine-output', required=True)
    assembly.add_argument('--candidate', type=Path, required=True)
    assembly.add_argument('--app', type=Path, required=True)
    assembly.add_argument('--output', type=Path, required=True)
    assembly.add_argument('--max-gib', type=int, required=True)
    validate = sub.add_parser('verify')
    validate.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == 'assets': write_assets(args.flutter_sdk, args.output, args.check, args.runtime_root)
        elif args.command == 'prepare': prepare(args)
        else: verify(args.output)
    except (ValueError, OSError, subprocess.CalledProcessError, KeyError, zipfile.BadZipFile) as error:
        parser.exit(1, 'Source material preparation failed: ' + type(error).__name__ + '\n')


if __name__ == '__main__': main()
