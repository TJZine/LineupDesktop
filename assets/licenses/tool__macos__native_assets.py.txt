#!/usr/bin/env python3
"""Read-only macOS native-asset input and final-bundle verification."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import struct
import subprocess

ASSET = 'package:objective_c/objective_c.dylib'
VENDOR = 'third_party/objective_c'
THIN32 = (b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xce')
CPU = {0x100000c: 'arm64', 0x1000007: 'x64'}
MAGIC = (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def version(value):
    require(isinstance(value, str) and re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', value), 'Invalid OS version')
    parts = tuple(map(int, value.split('.')))
    return parts + (0,) * (3 - len(parts))


def packed(value):
    return (value >> 16, (value >> 8) & 255, value & 255)


def macho(data):
    """Parse bounded thin/fat 64-bit Mach-O load commands, independently of host."""
    require(len(data) >= 8 and data[:4] in MAGIC, 'Missing or invalid Mach-O')
    if data[:4] not in MAGIC[:2]:
        endian = '>' if data[:4] in (MAGIC[2], MAGIC[4]) else '<'
        wide = data[:4] in MAGIC[4:]
        count = struct.unpack_from(endian + 'I', data, 4)[0]
        stride = 32 if wide else 20
        require(0 < count <= 32 and 8 + count * stride <= len(data), 'Invalid fat header')
        records, spans = [], []
        for index in range(count):
            values = struct.unpack_from(endian + ('IIQQII' if wide else 'IIIII'), data, 8 + index * stride)
            cpu, subtype, offset, size = values[:4]
            require(offset >= 8 + count * stride and size >= 32 and offset + size <= len(data), 'Invalid fat slice range')
            require(not any(offset < stop and offset + size > start for start, stop in spans), 'Overlapping fat slices')
            spans.append((offset, offset + size))
            require(data[offset:offset + 4] in MAGIC[:2], 'Fat slice must be thin 64-bit Mach-O')
            slices = macho(data[offset:offset + size])
            require(len(slices) == 1 and slices[0]['cpu'] == cpu and slices[0]['subtype'] == subtype, 'Fat slice/header disagreement')
            records += slices
        require(len({r['architecture'] for r in records}) == len(records), 'Duplicate fat architecture')
        return records
    endian = '<' if data[:4] == MAGIC[0] else '>'
    require(len(data) >= 32, 'Truncated Mach-O header')
    _, cpu, subtype, kind, count, command_bytes, _, _ = struct.unpack_from(endian + '8I', data)
    require(cpu in CPU and (subtype & 0xffffff) in ((0,) if CPU[cpu] == 'arm64' else (3,)), 'Unsupported Mach-O architecture')
    require(kind in (2, 6, 8) and count <= 4096 and 32 + command_bytes <= len(data), 'Invalid Mach-O commands')
    record = dict(cpu=cpu, subtype=subtype, fileType=kind, architecture=CPU[cpu], dependencies=[], rpaths=[])
    offset, minimum = 32, []
    for _ in range(count):
        require(offset + 8 <= 32 + command_bytes, 'Truncated load command')
        command, size = struct.unpack_from(endian + 'II', data, offset)
        require(size >= 8 and size % 4 == 0 and offset + size <= 32 + command_bytes, 'Invalid load command size')
        block = data[offset:offset + size]
        def string_at(start):
            require(0 <= start < size and b'\0' in block[start:], 'Invalid load-command string')
            return block[start:].split(b'\0', 1)[0].decode('utf-8')
        if command == 0x32:
            require(size >= 24, 'Truncated build version')
            platform, target, sdk, tools = struct.unpack_from(endian + '4I', block, 8)
            require(platform == 1 and 24 + 8 * tools <= size, 'Wrong Mach-O platform')
            minimum.append(packed(target))
        elif command in (0x24, 0x25, 0x2f, 0x30):
            require(command == 0x24 and size >= 16, 'Wrong Mach-O platform')
            minimum.append(packed(struct.unpack_from(endian + 'I', block, 8)[0]))
        elif command in (0xc, 0x80000018, 0x8000001f, 0x80000023, 0x20, 0xd):
            require(size >= 24, 'Truncated dylib command')
            name = string_at(struct.unpack_from(endian + 'I', block, 8)[0])
            if command != 0xd:
                record['dependencies'].append(name)
        elif command == 0x8000001c:
            require(size >= 12, 'Truncated rpath')
            record['rpaths'].append(string_at(struct.unpack_from(endian + 'I', block, 8)[0]))
        elif command == 0x1b:
            require(size == 24, 'Invalid UUID')
            record['uuid'] = block[8:24].hex()
        elif command == 0x19:
            require(size >= 72, 'Truncated segment')
            sections = struct.unpack_from(endian + 'I', block, 64)[0]
            require(72 + sections * 80 <= size, 'Truncated sections')
            for index in range(sections):
                start = 72 + index * 80
                section, segment = block[start:start + 16].rstrip(b'\0'), block[start + 16:start + 32].rstrip(b'\0')
                if (segment, section) == (b'__TEXT', b'__text'):
                    length = struct.unpack_from(endian + 'Q', block, start + 40)[0]
                    position = struct.unpack_from(endian + 'I', block, start + 48)[0]
                    require(position + length <= len(data), 'Text section escapes slice')
                    record['textSha256'] = hashlib.sha256(data[position:position + length]).hexdigest()
        offset += size
    require(offset == 32 + command_bytes and len(minimum) == 1, 'Missing or ambiguous macOS minimum')
    record['minimumOS'] = list(minimum[0])
    return [record]


def native_toolchain_identity():
    def xcrun(*args):
        return Path(subprocess.check_output(['/usr/bin/xcrun', *args], text=True).strip()).resolve(strict=True)
    return {'compilerSha256': sha(xcrun('--find', 'clang')),
            'sdkSettingsSha256': sha(xcrun('--sdk', 'macosx', '--show-sdk-path') / 'SDKSettings.json')}


def project_inputs(repository):
    pubspec = (repository / 'pubspec.yaml').read_text()
    require(re.search(r'(?m)^dependency_overrides:\n  objective_c:\n    path: third_party/objective_c\s*$', pubspec), 'Missing exact local objective_c override')
    require(re.search(r'(?m)^hooks:\n  user_defines:\n    objective_c:\n      macos_target_version: 12\s*$', pubspec), 'Missing typed macOS 12 hook define')
    targets = re.findall(r'MACOSX_DEPLOYMENT_TARGET\s*=\s*([0-9.]+);', (repository / 'macos/Runner.xcodeproj/project.pbxproj').read_text())
    require(targets and all(version(target) == (12, 0, 0) for target in targets), 'Xcode/hook target mismatch')
    vendor = repository / VENDOR
    baseline = json.loads((vendor / 'UPSTREAM.json').read_text())
    for name, digest in baseline['files'].items():
        if name not in ('hook/build.dart', 'analysis_options.yaml'):
            require(sha(vendor / name) == digest, 'Foreign baseline changed: ' + name)
    names = [str(p.relative_to(repository)) for p in vendor.rglob('*') if p.is_file()]
    names += ['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'macos/Runner.xcodeproj/project.pbxproj',
              'tool/macos/build_app.dart', 'tool/macos/native_assets.py']
    return {'target': [12, 0, 0], 'architecture': 'arm64', 'toolchain': native_toolchain_identity(), 'inputs': {name: sha(repository / name) for name in sorted(names)}}


def bundle_closure(app, target=(12, 0, 0), architecture='arm64'):
    app = app.resolve(strict=True)
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    executable = (app / 'Contents/MacOS' / info['CFBundleExecutable']).resolve(strict=True)
    require(executable.is_relative_to(app), 'Executable escapes app')
    binaries = {}
    for path in app.rglob('*'):
        if path.is_symlink():
            require(path.resolve(strict=True).is_relative_to(app), 'Bundle symlink escapes app')
        if not path.is_file():
            continue
        physical = path.resolve(strict=True)
        if physical in binaries:
            continue
        with path.open('rb') as stream:
            magic = stream.read(4)
        require(magic not in THIN32, 'Unsupported 32-bit Mach-O')
        if magic not in MAGIC:
            continue
        slices = macho(path.read_bytes())
        require(architecture in {r['architecture'] for r in slices}, 'Mach-O lacks required architecture')
        require(all(tuple(r['minimumOS']) <= target for r in slices), 'Mach-O requires newer macOS: ' + str(path.relative_to(app)))
        binaries[physical] = slices
    require(executable in binaries, 'Main executable is not Mach-O')
    require(all(r['fileType'] == 2 for r in binaries[executable]), 'Main Mach-O is not executable')
    frameworks = app / 'Contents/Frameworks'
    def expand(value, loader):
        if value == '@loader_path':
            return loader.parent
        if value == '@executable_path':
            return executable.parent
        if value.startswith('@loader_path/'):
            return loader.parent / value[len('@loader_path/'):]
        if value.startswith('@executable_path/'):
            return executable.parent / value[len('@executable_path/'):]
        return Path(value)
    closure = {}
    for binary, slices in binaries.items():
        for record in slices:
            main = next((r for r in binaries[executable] if r['architecture'] == record['architecture']), None)
            require(main is not None, 'Main executable lacks bundled architecture')
            roots = [expand(r, binary) for r in record['rpaths']] + [expand(r, executable) for r in main['rpaths']]
            for dependency in record['dependencies']:
                if dependency.startswith(('/usr/lib/', '/System/Library/')):
                    continue
                candidates = ([root / dependency[len('@rpath/'):] for root in roots] if dependency.startswith('@rpath/')
                              else [expand(dependency, binary)])
                matches = {p.resolve() for p in candidates if p.is_file()}
                require(matches and all(p.is_relative_to(app) and p in binaries for p in matches), 'Unresolved or external bundled dependency: ' + dependency)
                require(len(matches) == 1, 'Ambiguous bundled dependency')
                require(all(any(r['architecture'] == record['architecture'] for r in binaries[p]) for p in matches), 'Dependency lacks loader architecture')
        closure[binary.relative_to(app).as_posix()] = {'sha256': sha(binary), 'slices': slices}
    manifest = app / 'Contents/Frameworks/App.framework/Resources/flutter_assets/NativeAssetsManifest.json'
    require(manifest.resolve().is_relative_to(app), 'Native manifest escapes app')
    assets = json.loads(manifest.read_text())
    mappings = assets.get('native-assets', {})
    require('macos_arm64' in mappings, 'Required native asset architecture missing')
    asset_paths = set()
    for key, values in mappings.items():
        require(key in ('macos_arm64', 'macos_x64') and ASSET in values, 'Unexpected native asset platform/identity')
        mapping = values[ASSET]
        require(mapping == ['absolute', 'objective_c.framework/objective_c'], 'Incorrect objective_c asset mapping')
        asset_paths.add((frameworks / mapping[1]).resolve(strict=True))
    require(len(asset_paths) == 1 and next(iter(asset_paths)) in binaries, 'Missing objective_c native asset')
    asset = next(iter(asset_paths))
    require(all(r['fileType'] == 6 for r in binaries[asset]), 'Native asset is not a dylib')
    asset_info = plistlib.loads((asset.parent / 'Resources/Info.plist').read_bytes())
    require(asset_info.get('CFBundleIdentifier') == 'io.flutter.flutter.native-assets.objective-c' and
            asset_info.get('CFBundleExecutable') == 'objective_c', 'Incorrect native asset framework identity')
    require({r['architecture'] for r in binaries[asset]} == {key.split('_', 1)[1] for key in mappings}, 'Native asset slice/manifest mismatch')
    return closure, asset, binaries[asset]


def verify(repository, app, before):
    current = project_inputs(repository)
    require(current == before, 'Native asset inputs changed during build')
    closure, asset, slices = bundle_closure(app)
    source_records = {}
    for record in slices:
        architecture = record['architecture']
        candidates = []
        for path in (repository / '.dart_tool/hooks_runner/shared/objective_c/build').rglob('lineup-objective-c-build.json'):
            try:
                receipt = json.loads(path.read_text())
                if receipt['architecture'] != architecture or receipt['packageRoot'].rstrip('/') != str((repository / VENDOR).resolve()):
                    continue
                require(receipt['assetId'] == ASSET and receipt['compileFlags'] == receipt['linkFlags'] and
                        '-mmacos-version-min=12' in receipt['compileFlags'], 'Incorrect hook target flags')
                raw = Path(receipt['asset'])
                require(raw.resolve().is_relative_to((repository / '.dart_tool/hooks_runner').resolve()) and raw.is_file(), 'Invalid hook asset path')
                raw_slices = macho(raw.read_bytes())
                require(len(raw_slices) == 1 and raw_slices[0]['architecture'] == architecture and raw_slices[0]['minimumOS'] == [12, 0, 0], 'Incorrect raw asset slice')
                require(record.get('uuid') and record.get('textSha256') and all(record[key] == raw_slices[0][key] for key in ('uuid', 'textSha256')), 'Wrapped asset differs from selected hook output')
                require(receipt['schemaVersion'] == 2, 'Hook proof predates producing-time identities')
                producing = receipt['producingInputs']
                configuration = producing['configuration']
                require(configuration['user_defines']['workspace_pubspec']['defines']['macos_target_version'] == 12, 'Hook input lost target override')
                require(Path(configuration['user_defines']['workspace_pubspec']['base_path']).resolve() == repository.resolve() and
                        producing['workspacePubspecSha256'] == before['inputs']['pubspec.yaml'], 'Cached hook workspace configuration changed')
                require(configuration['package_name'] == 'objective_c' and
                        Path(configuration['package_root']).resolve() == (repository / VENDOR).resolve(), 'Incorrect producing package')
                code = configuration['config']['extensions']['code_assets']
                require(code['target_os'] == 'macos' and code['target_architecture'] == architecture, 'Incorrect producing code configuration')
                expected = {'hook/build.dart', 'pubspec.yaml'} | {
                    p.relative_to(repository / VENDOR).as_posix() for p in (repository / VENDOR / 'src').rglob('*')
                    if p.is_file() and p.suffix in ('.c', '.m', '.h')}
                sources = producing['sources']
                require(expected <= sources.keys() and all(
                    before['inputs'][VENDOR + '/' + name] == digest for name, digest in sources.items()), 'Cached hook source identities changed')
                compiler = Path(receipt['compiler']).resolve(strict=True)
                sdk = Path(receipt['sdk']).resolve(strict=True) / 'SDKSettings.json'
                toolchain = {key: producing[key] for key in ('compilerSha256', 'sdkSettingsSha256')}
                require(toolchain == before['toolchain'] == {
                    'compilerSha256': sha(compiler), 'sdkSettingsSha256': sha(sdk)}, 'Cached hook toolchain identities changed')
                require(receipt['rawAssetSha256'] == sha(raw), 'Raw asset changed since production')
                candidates.append({'hookReceiptSha256': sha(path), 'rawAssetSha256': receipt['rawAssetSha256'],
                                   **toolchain, 'producingSources': sources,
                                   'hookInputSha256': hashlib.sha256(json.dumps(configuration, sort_keys=True).encode()).hexdigest()})
            except (KeyError, OSError, ValueError):
                continue
        require(candidates and len({json.dumps(c, sort_keys=True) for c in candidates}) == 1, 'Missing or ambiguous current hook proof; cached source/toolchain identities must match: ' + architecture)
        source_records[architecture] = candidates[0]
    return {**current, 'package': 'objective_c', 'version': '9.6.2', 'assetId': ASSET,
            'finalAssetSha256': sha(asset), 'hookBuilds': source_records, 'closure': closure}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['inputs', 'verify'])
    parser.add_argument('--repository', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--app', type=Path)
    parser.add_argument('--inputs', type=Path)
    args = parser.parse_args()
    try:
        repository = args.repository.resolve()
        result = (project_inputs(repository) if args.action == 'inputs' else
                  verify(repository, args.app.resolve(), json.loads(args.inputs.read_text())))
        print(json.dumps(result, sort_keys=True))
    except (ValueError, OSError, KeyError, struct.error) as error:
        parser.exit(1, 'Native asset verification failed: ' + str(error) + '\n')


if __name__ == '__main__':
    main()
