#!/usr/bin/env python3
"""Exact-source, fresh-build provenance for the opt-in desktop AX engine.

The framework and engine pins remain owned by flutter_version.json and Windows
build-metadata.psd1. This tool never writes the stock SDK cache. Generated JSON
contains local paths and belongs with private build evidence, not in Git.
"""

import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time

MANIFEST = 'tool/flutter_engine/desktop-accessibility.json'
AX_PATCH = 'tool/flutter_engine/0002-desktop-accessibility.patch'
MAC_BUILD_PATCH = 'tool/flutter_engine/0003-macos-apple-linker.patch'
PIN_FILES = ('tool/flutter_version.json', 'tool/windows/build-metadata.psd1')
PROVENANCE = 'lineup-desktop-accessibility.json'


class VerificationError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise VerificationError(message)


def run(arguments, cwd=None, capture=True, env=None):
    result = subprocess.run([str(a) for a in arguments], cwd=cwd, env=env, check=False,
                            stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.PIPE if capture else None)
    require(result.returncode == 0,
            f'Command failed ({result.returncode}): {arguments[0]}' +
            (f'\n{result.stderr.decode(errors="replace")}' if capture else ''))
    return result.stdout if capture else b''


def git(root, *arguments):
    return run(['git', '-C', root, *arguments])


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_hash(path):
    return digest(Path(path).read_bytes())


def source_hash(path):
    # Git and the existing Windows verifier own LF-normalized text sources.
    return digest(Path(path).read_bytes().replace(b'\r\n', b'\n'))


def relative_file(root, name):
    require(isinstance(name, str) and re.fullmatch(r'[A-Za-z0-9_.\-/]+', name)
            and not name.startswith('/') and '..' not in name.split('/'),
            'Unsafe repository-relative input path.')
    result = root / name
    require(result.resolve().is_relative_to(root.resolve()), 'Input escapes its repository.')
    require(result.is_file() and not result.is_symlink(), f'Required regular input is missing: {name}')
    return result


def committed(root, name):
    path = relative_file(root, name)
    require(git(root, 'rev-parse', f'HEAD:{name}').strip() == git(root, 'hash-object', '--', name).strip(),
            f'Build input must match its committed revision: {name}')
    return path


def pins(repository, exact=True):
    read = committed if exact else relative_file
    framework = json.loads(read(repository, PIN_FILES[0]).read_text())
    windows = dict(re.findall(r"^\s*(\w+)\s*=\s*'([^']*)'", read(repository, PIN_FILES[1]).read_text(), re.M))
    require(framework['frameworkRevision'] == windows['FlutterFrameworkRevision'],
            'Framework pin authorities disagree.')
    return framework, windows


def verify_checkout(root, framework, windows):
    require(git(root, 'rev-parse', 'HEAD').decode().strip() == framework['frameworkRevision'],
            'Flutter framework revision does not match the repository pin.')
    require((root / 'bin/internal/engine.version').read_text().strip() == windows['FlutterEngineRevision'],
            'Flutter engine.version does not match the repository pin.')
    require(not git(root, 'diff', '--cached', '--name-only').strip(),
            'Flutter checkout must have no staged changes.')


def patch_files(patch):
    # No rename, mode-only, deletion, creation, or arbitrary binary patch support.
    # This intentionally accepts the reviewed text-source patch shape only.
    text = patch.read_text()
    require(not any(x in text for x in ('new file mode ', 'deleted file mode ', 'rename from ', 'GIT binary patch', 'old mode ')),
            'Only modifications to existing text source files are supported.')
    pairs = re.findall(r'^--- a/(.+)\n\+\+\+ b/(.+)$', text, re.M)
    require(pairs and all(a == b for a, b in pairs), 'Patch contains unsupported paths.')
    names = [a for a, _ in pairs]
    require(len(names) == len(set(names)), 'Duplicate patched source path.')
    require(all(n.startswith(('engine/src/flutter/', 'engine/src/build/')) for n in names), 'Patch escapes engine source.')
    return names


def derive_patch(root, patch):
    """Apply against actual HEAD blobs in a temporary index, never the checkout."""
    names = patch_files(patch)
    with tempfile.TemporaryDirectory(prefix='lineup-ax-patch-') as temporary:
        scratch = Path(temporary)
        git(scratch, 'init', '--quiet')
        for name in names:
            path = scratch / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(git(root, 'show', f'HEAD:{name}'))
        git(scratch, 'add', '.')
        git(scratch, 'apply', '--check', str(patch.resolve()))
        git(scratch, 'apply', str(patch.resolve()))
        return {name: {'baselineBlob': git(root, 'rev-parse', f'HEAD:{name}').decode().strip(),
                       'patchedSha256': source_hash(scratch / name)} for name in names}


def finalize(repository, root):
    framework, windows = pins(repository, exact=False)
    verify_checkout(root, framework, windows)
    patches = []
    for name in [AX_PATCH] + ([MAC_BUILD_PATCH] if (repository / MAC_BUILD_PATCH).exists() else []):
        patch = relative_file(repository, name)
        files = derive_patch(root, patch)
        require(windows['FlutterManagerPath'] not in files,
                'Accessibility patches must not replace the DirectComposition owner.')
        patches.append({'path': name, 'sha256': file_hash(patch), 'files': files,
                        'platforms': ['macos', 'windows'] if name == AX_PATCH else ['macos']})
    result = {'schemaVersion': 1, 'patches': patches}
    destination = repository / MANIFEST
    destination.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    return {'manifest': MANIFEST, 'patches': [p['path'] for p in patches], 'status': 'finalized; commit canonical inputs before verification'}


def source_identity(repository, root, target, require_applied=True):
    framework, windows = pins(repository)
    verify_checkout(root, framework, windows)
    manifest_path = committed(repository, MANIFEST)
    manifest = json.loads(manifest_path.read_text())
    require(manifest.get('schemaVersion') == 1, 'Unsupported desktop accessibility manifest.')
    entries = manifest.get('patches', [])
    require([e['path'] for e in entries] in ([AX_PATCH], [AX_PATCH, MAC_BUILD_PATCH]),
            'Require AX patch followed by the optional macOS build patch.')
    expected, patches = {}, []
    for entry in entries:
        name = entry['path']
        require(entry['platforms'] == (['macos', 'windows'] if name == AX_PATCH else ['macos']),
                'Incorrect patch platform selection.')
        patch = committed(repository, name)
        require(file_hash(patch) == entry.get('sha256'), 'Accessibility patch SHA-256 mismatch.')
        files = derive_patch(root, patch)
        require(files == entry.get('files') and files, 'Accessibility baseline/patched file metadata mismatch.')
        require(windows['FlutterManagerPath'] not in files, 'Accessibility patch overlaps DirectComposition.')
        if target not in entry['platforms']:
            continue
        require(not set(expected).intersection(files), 'Platform patches overlap.')
        expected.update(files)
        patches.append({'path': name, 'sha256': file_hash(patch)})
    if target == 'windows':
        direct = committed(repository, windows['FlutterEnginePatchPath'])
        require(file_hash(direct).upper() == windows['FlutterEnginePatchSha256'].upper(),
                'DirectComposition patch SHA-256 mismatch.')
        direct_files = derive_patch(root, direct)
        require(list(direct_files) == [windows['FlutterManagerPath']] and
                direct_files[windows['FlutterManagerPath']]['baselineBlob'] == windows['FlutterManagerBlob'] and
                direct_files[windows['FlutterManagerPath']]['patchedSha256'].upper() == windows['FlutterPatchedManagerSha256'].upper(),
                'DirectComposition exact-source metadata mismatch.')
        require(not set(expected).intersection(direct_files), 'Platform patches overlap.')
        expected.update(direct_files)
        patches.insert(0, {'path': windows['FlutterEnginePatchPath'], 'sha256': file_hash(direct)})
    identity = {'frameworkRevision': framework['frameworkRevision'], 'engineVersion': windows['FlutterEngineRevision'],
                'patches': patches, 'files': expected, 'manifestSha256': file_hash(manifest_path),
                'pinSha256': {name: file_hash(repository / name) for name in PIN_FILES}}
    if not require_applied:
        return identity
    actual = set(git(root, 'diff', '--name-only', '-z', 'HEAD').decode().rstrip('\0').split('\0')) - {''}
    require(actual == set(expected), 'Flutter checkout must contain exactly the selected repository-owned patches.')
    for name, record in expected.items():
        require(source_hash(relative_file(root, name)) == record['patchedSha256'],
                f'Patched source SHA-256 mismatch: {name}')
    # Untracked dependency repositories/output are normal. Untracked source code
    # in Flutter itself is not: a new .cc could participate via a glob/build rule.
    untracked = git(root, 'ls-files', '--others', '--exclude-standard', '-z', '--', 'engine/src/flutter', 'engine/src/build').decode().split('\0')
    require(not any(untracked), 'Untracked Flutter engine source is not a verified candidate.')
    return identity


def gclient_solutions(data):
    module = ast.parse(data)
    require(len(module.body) == 1 and isinstance(module.body[0], ast.Assign) and
            len(module.body[0].targets) == 1 and isinstance(module.body[0].targets[0], ast.Name) and
            module.body[0].targets[0].id == 'solutions', 'Unsupported .gclient configuration.')
    return ast.literal_eval(module.body[0].value)


def dependency_identity(repository, root, gclient=None):
    _, windows = pins(repository)
    executable = Path(gclient or shutil.which('gclient') or '')
    require(executable.is_file(), 'Pinned depot_tools gclient is required for provisioned source verification.')
    executable = executable.resolve()
    depot = executable.parent
    require(git(depot, 'rev-parse', '--show-toplevel').decode().strip() == str(depot),
            'gclient must belong to the pinned depot_tools Git root.')
    require(git(depot, 'rev-parse', 'HEAD').decode().strip() == windows['DepotToolsRevision'],
            'depot_tools revision does not match build metadata.')
    require(not git(depot, 'status', '--porcelain', '--untracked-files=no').strip(), 'depot_tools has tracked source changes.')
    config = root / '.gclient'
    require(config.is_file(), 'Provisioned Flutter checkout is missing .gclient.')
    actual = gclient_solutions(config.read_text())
    standard = gclient_solutions(git(root, 'show', 'HEAD:engine/scripts/standard.gclient').decode())
    require(isinstance(actual, list) and len(actual) == 1, 'Require the standard single Flutter solution.')
    actual_solution = dict(actual[0])
    variables = actual_solution.pop('custom_vars', {})
    require(isinstance(variables, dict) and all(isinstance(value, bool) and
            (name.startswith('download_') or name == 'use_rbe') for name, value in variables.items()),
            'Only download/use_rbe boolean .gclient custom variables are allowed.')
    require(actual_solution == standard[0], '.gclient must preserve the pinned standard solution without source overrides.')
    environment = dict(os.environ, DEPOT_TOOLS_UPDATE='0')
    with tempfile.TemporaryDirectory(prefix='lineup-ax-dependencies-') as temporary:
        expected_path = Path(temporary) / 'expected.json'
        run([executable, 'revinfo', '--ignore-dep-type', 'cipd', '--ignore-dep-type', 'gcs',
             '--output-json', expected_path], cwd=root, env=environment)
        expected = json.loads(expected_path.read_text())
    require(isinstance(expected, dict) and '.' in expected and len(expected) > 1,
            'Gclient did not evaluate the complete provisioned Git source graph.')
    dependencies = {}
    for name, entry in sorted(expected.items()):
        if name == '.':
            continue  # The outer framework HEAD/source is checked separately.
        require(re.fullmatch(r'[0-9a-f]{40}', entry.get('rev') or ''), 'Git dependency lacks an exact DEPS revision.')
        require(re.fullmatch(r'[A-Za-z0-9_.\-/]+', name) and not name.startswith('/') and '..' not in name.split('/'),
                'Unsafe gclient source dependency path.')
        directory = root / name
        require(directory.is_dir() and directory.resolve().is_relative_to(root), 'Missing provisioned Git dependency.')
        require(Path(git(directory, 'rev-parse', '--show-toplevel').decode().strip()).resolve() == directory.resolve(),
                f'Dependency is not its own Git checkout: {name}')
        resolved_revision = git(directory, 'rev-parse', '--verify', entry['rev'] + '^{commit}').decode().strip()
        require(git(directory, 'rev-parse', 'HEAD').decode().strip() == resolved_revision,
                f'Git dependency revision differs from evaluated DEPS: {name}')
        require(not git(directory, 'status', '--porcelain').strip(), f'Git dependency has source changes: {name}')
        dependencies[name] = {'declaredRevision': entry['rev'], 'revision': resolved_revision, 'url': entry['url']}
    return {'gclient': str(executable), 'depotToolsRevision': windows['DepotToolsRevision'],
            'gclientConfigSha256': file_hash(config), 'gitDependencies': dependencies}


def verified_sources(repository, root, target, gclient=None):
    result = source_identity(repository, root, target)
    result['dependencies'] = dependency_identity(repository, root, gclient)
    return result


def configuration(output, target, architecture, mode):
    args = output / 'args.gn'
    require(args.is_file() and (output / 'build.ninja').is_file(), 'Engine configuration is missing.')
    values = dict(re.findall(r'^\s*(\w+)\s*=\s*"([^"\n]*)"\s*$', args.read_text(), re.M))
    require(values.get('target_os') == {'macos': 'mac', 'windows': 'win'}[target], 'Wrong engine platform.')
    require(values.get('target_cpu') == architecture and values.get('host_cpu') == architecture,
            'Wrong engine architecture (cross-host builds are not supported).')
    require(values.get('flutter_runtime_mode') == mode, 'Wrong engine runtime mode.')
    return {'platform': target, 'architecture': architecture, 'mode': mode,
            'gnArgs': args.read_text(), 'argsSha256': file_hash(args),
            'ninjaGraphSha256': {str(p.relative_to(output)).replace(os.sep, '/'): file_hash(p)
                                 for p in sorted(output.rglob('*.ninja'))}}


def engine_binary(output, target):
    if target == 'windows':
        result = output / 'flutter_windows.dll'
    else:
        choices = list((output / 'FlutterMacOS.xcframework').glob('macos-*'))
        require(len(choices) == 1, 'Require one unambiguous local macOS xcframework slice.')
        result = choices[0] / 'FlutterMacOS.framework/Versions/A/FlutterMacOS'
    require(result.is_file() and result.resolve().is_relative_to(output.resolve()),
            'Built engine binary is missing or escapes its output.')
    return result


def binary_architecture(binary, target):
    with binary.open('rb') as stream:
        header = stream.read(64)
        if target == 'macos':
            require(len(header) >= 8 and header[:4] == b'\xcf\xfa\xed\xfe', 'Require a native thin 64-bit Mach-O engine.')
            cpu = struct.unpack_from('<I', header, 4)[0]
            architecture = {0x100000c: 'arm64', 0x1000007: 'x64'}.get(cpu)
        else:
            require(header[:2] == b'MZ' and len(header) >= 64, 'Require a Windows PE engine.')
            stream.seek(struct.unpack_from('<I', header, 60)[0])
            pe = stream.read(6)
            require(len(pe) >= 6 and pe[:4] == b'PE\0\0', 'Invalid Windows engine PE header.')
            architecture = {0x8664: 'x64', 0xaa64: 'arm64'}.get(struct.unpack_from('<H', pe, 4)[0])
    require(architecture, 'Unsupported engine executable architecture.')
    return architecture


def artifact_hashes(output, target):
    binary = engine_binary(output, target)
    suffix = '.exe' if target == 'windows' else ''
    for name in [f'dart-sdk/bin/dart{suffix}', 'dart-sdk/bin/snapshots/frontend_server_aot.dart.snapshot',
                 'flutter_patched_sdk/platform_strong.dill', 'flutter_patched_sdk/vm_outline_strong.dill',
                 'gen/dart-pkg/sky_engine/lib/_embedder.yaml', 'gen/frontend_server_aot.dart.snapshot',
                 'gen/const_finder.dart.snapshot', f'font-subset{suffix}', f'impellerc{suffix}', 'shader_lib/flutter/runtime_effect.glsl']:
        require((output / name).is_file(), f'Required local engine host artifact is missing: {name}')
    snapshot_directories = ('.', 'universal', 'clang_x64', 'clang_x86', 'clang_i386', 'clang_arm64', 'clang_riscv64')
    require(any((output / directory / name).is_file() for directory in snapshot_directories
                for name in ('gen_snapshot', 'gen_snapshot.exe', 'gen_snapshot_arm64', 'gen_snapshot_x64')),
            'Required local engine snapshot tool is missing.')
    # Bind all xcframework contents (headers/resources as well as the engine),
    # and the SDK/snapshot tools consumed by Flutter from this local output.
    roots = [output / 'FlutterMacOS.xcframework'] if target == 'macos' else [binary]
    relative_roots = ['shader_lib', 'dart-sdk', 'flutter_patched_sdk', 'flutter_patched_sdk_product',
                      'gen/dart-pkg', 'gen/flutter/lib/snapshot', 'gen/frontend_server_aot.dart.snapshot',
                      'gen/const_finder.dart.snapshot', 'font-subset', 'font-subset.exe', 'impellerc',
                      'impellerc.exe', 'icudtl.dat', 'flutter_windows.dll.lib', 'flutter_windows.dll.exp',
                      'flutter_windows.h', 'flutter_export.h', 'flutter_messenger.h', 'flutter_plugin_registrar.h',
                      'flutter_texture_registrar.h', 'cpp_client_wrapper']
    # Flutter searches these directories in order for the host snapshot tool.
    for directory in snapshot_directories:
        relative_roots += [f'{directory}/{name}' for name in ('gen_snapshot', 'gen_snapshot.exe', 'gen_snapshot_arm64', 'gen_snapshot_x64')]
    roots += [output / name for name in relative_roots if (output / name).exists()]
    files = set()
    for root in roots:
        for path in ([root] if root.is_file() else root.rglob('*')):
            if path.is_file():
                require(path.resolve().is_relative_to(output.resolve()), 'Artifact symlink escapes output.')
                files.add(path)
    require(files, 'No engine artifacts found.')
    return {str(p.relative_to(output)).replace(os.sep, '/'): file_hash(p) for p in sorted(files)}


def host_matches(target, architecture):
    actual_os = {'Darwin': 'macos', 'Windows': 'windows'}.get(platform.system())
    actual_arch = {'aarch64': 'arm64', 'arm64': 'arm64', 'AMD64': 'x64', 'x86_64': 'x64'}.get(platform.machine())
    require((actual_os, actual_arch) == (target, architecture), 'Build must run on the selected native host/architecture.')


def toolchain_identity(root, output, target, architecture):
    args = dict(re.findall(r'^\s*(\w+)\s*=\s*"([^"\n]*)"\s*$', (output / 'args.gn').read_text(), re.M))
    tools = {}
    if target == 'macos':
        compiler = root / f'engine/src/flutter/buildtools/mac-{architecture}/clang/bin/clang++'
        tools['compiler'] = compiler.resolve()
        if 'mac_use_apple_linker = true' in (output / 'args.gn').read_text():
            tools['linker'] = Path(args['mac_host_toolchain_path']) / 'usr/bin/ld'
        else:
            tools['linker'] = compiler.parent / 'ld64.lld'
        tools['sdkSettings'] = Path(args['mac_sdk_path']) / 'SDKSettings.json'
        # The pinned Metal build action invokes xcrun's selected native SDK,
        # independently of the C++ SDK path from GN. Bind that actual selection.
        tools['metal'] = Path(run(['xcrun', '-sdk', 'macosx', '-find', 'metal']).decode().strip()).resolve()
        metal_sdk = Path(run(['xcrun', '-sdk', 'macosx', '--show-sdk-path']).decode().strip())
        tools['metalSdkSettings'] = metal_sdk / 'SDKSettings.json'
        metal_version = run(['xcrun', '-sdk', 'macosx', 'metal', '--version']).decode().strip()
    else:
        directory = root / 'engine/src/flutter/buildtools/windows-x64/clang/bin'
        tools.update(compiler=directory / 'clang-cl.exe', linker=directory / 'lld-link.exe')
    require(all(p.is_file() for p in tools.values()), 'Required compiler/linker/SDK identity is missing.')
    result = {key: {'path': str(path), 'sha256': file_hash(path)} for key, path in tools.items()}
    if target == 'macos':
        result['metalVersion'] = metal_version
    return result


def build_environment():
    # Clang's hidden driver override changes both compilation and linking.
    require(not os.environ.get('CCC_OVERRIDE_OPTIONS'), 'CCC_OVERRIDE_OPTIONS is forbidden for verified engine builds.')
    return {name: os.environ[name] for name in ('DEVELOPER_DIR', 'SDKROOT', 'CC', 'CXX', 'CFLAGS', 'CXXFLAGS', 'LDFLAGS',
                                               'GYP_MSVS_OVERRIDE_PATH', 'WINDOWSSDKDIR') if name in os.environ}


def resolve_ninja(ninja):
    ninja_path = shutil.which(ninja)
    require(ninja_path, 'Ninja executable is missing.')
    ninja_path = str(Path(ninja_path).resolve())
    with open(ninja_path, 'rb') as ninja_file:
        magic = ninja_file.read(4)
    require(magic[:2] == b'MZ' or magic in (b'\x7fELF', b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'),
            'Ninja must be a real executable, not a context-dependent script/shim.')
    return ninja_path


def build(repository, root, target, architecture, mode, ninja, apple_linker=False, jobs=2, gclient=None):
    require(isinstance(jobs, int) and 1 <= jobs <= 64, 'Ninja jobs must be between 1 and 64.')
    host_matches(target, architecture)
    environment = build_environment()
    before = verified_sources(repository, root, target, gclient)
    source = root / 'engine/src'
    name = f'lineup_ax_{mode}_{architecture}'
    output = source / 'out' / name
    # A fresh GN/Ninja graph cannot reuse a stock or previous-patch object tree.
    # The caller removes an old candidate explicitly before rebuilding it.
    require(not output.exists(), f'Fresh build requires absent output: {output}')
    gn = [sys.executable, source / 'flutter/tools/gn', '--runtime-mode', mode,
          '--target-dir', name, '--no-goma', '--no-rbe', '--enable-unittests',
          '--no-build-glfw-shell', '--no-build-embedder-examples']
    gn += ['--mac-cpu', architecture] if target == 'macos' else ['--windows-cpu', architecture]
    if apple_linker:
        require(target == 'macos' and any(p['path'] == MAC_BUILD_PATCH for p in before['patches']),
                'Apple linker requires the reviewed macOS build patch.')
        # Pinned LLVM bitcode is incompatible with this Xcode linker's LTO
        # codegen. Keep normal optimization while avoiding that plugin boundary.
        gn += ['--no-lto', '--gn-args', 'mac_use_apple_linker=true']
    started = time.time_ns()
    run(gn, cwd=source, capture=False)
    config = configuration(output, target, architecture, mode)
    toolchain = toolchain_identity(root, output, target, architecture)
    ninja_path = resolve_ninja(ninja)
    ninja_identity = {'path': str(Path(ninja_path).resolve()), 'sha256': file_hash(ninja_path)}
    targets = ['flutter_framework' if target == 'macos' else 'windows', 'dart_sdk',
               'generate_snapshot_bins', 'sky_engine', 'font_subset', 'const_finder', 'impellerc',
               'phony/flutter/flutter_frontend_server/frontend_server']
    command = [ninja_path, '-C', output, '-j', str(jobs), *targets]
    run(command, cwd=source, capture=False)
    require(environment == build_environment(), 'Engine build environment changed.')
    require(toolchain == toolchain_identity(root, output, target, architecture), 'Engine toolchain changed during build.')
    require(before == verified_sources(repository, root, target, before['dependencies']['gclient']), 'Engine sources changed during build.')
    require(config == configuration(output, target, architecture, mode), 'Engine configuration changed during build.')
    binary = engine_binary(output, target)
    require(binary.stat().st_mtime_ns >= started, 'Engine artifact predates this build.')
    require(binary_architecture(binary, target) == architecture, 'Built engine executable has wrong architecture.')
    record = {'schemaVersion': 1, 'kind': 'verified-local-desktop-accessibility',
              'flutterRoot': str(root), 'outputName': name, 'source': before, 'configuration': config,
              'build': {'startedNs': started, 'finishedNs': time.time_ns(), 'gnCommand': [str(x) for x in gn],
                        'ninjaCommand': [str(x) for x in command], 'freshOutput': True},
              'toolchain': toolchain, 'environment': environment, 'ninja': ninja_identity,
              'artifacts': artifact_hashes(output, target),
              'engineBinary': str(binary.relative_to(output)).replace(os.sep, '/')}
    (output / PROVENANCE).write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
    return verify(repository, root, name, target, architecture, mode)


def verify(repository, root, name, target, architecture, mode):
    require(re.fullmatch(r'[A-Za-z0-9_-]+', name), 'Unsafe local engine output name.')
    output = root / 'engine/src/out' / name
    path = output / PROVENANCE
    require(path.is_file(), 'Engine provenance is missing; build a fresh candidate with desktop_accessibility.py build.')
    record = json.loads(path.read_text())
    require(record.get('schemaVersion') == 1 and record.get('kind') == 'verified-local-desktop-accessibility', 'Unsupported engine provenance.')
    require(record.get('flutterRoot') == str(root) and record.get('outputName') == name, 'Engine provenance belongs to another checkout/output.')
    require(record.get('source') == verified_sources(repository, root, target,
            record.get('source', {}).get('dependencies', {}).get('gclient')), 'Stale engine source/patch provenance.')
    build_environment()
    require(record.get('toolchain') == toolchain_identity(root, output, target, architecture), 'Engine toolchain provenance mismatch.')
    ninja_identity = record.get('ninja', {})
    require(ninja_identity.get('sha256') == file_hash(ninja_identity.get('path', '')), 'Ninja executable changed.')
    require(record.get('configuration') == configuration(output, target, architecture, mode), 'Engine configuration provenance mismatch.')
    build_record = record.get('build', {})
    require(build_record.get('freshOutput') is True and isinstance(build_record.get('startedNs'), int)
            and build_record.get('finishedNs', 0) >= build_record['startedNs'], 'Missing completed fresh-build provenance.')
    binary = engine_binary(output, target)
    require(binary_architecture(binary, target) == architecture, 'Engine executable has wrong architecture.')
    require(record.get('engineBinary') == str(binary.relative_to(output)).replace(os.sep, '/'), 'Engine binary selection changed.')
    require(binary.stat().st_mtime_ns >= build_record['startedNs'], 'Stale engine artifact.')
    require(record.get('artifacts') == artifact_hashes(output, target), 'Engine artifact hashes changed.')
    return {'kind': record['kind'], 'flutterRoot': str(root), 'engineSource': str(root / 'engine/src'),
            'outputName': name, 'platform': target, 'architecture': architecture, 'mode': mode,
            'binary': str(binary), 'binarySha256': file_hash(binary), 'provenanceSha256': file_hash(path)}


def executable_hash(binary):
    # Removing a signature leaves __LINKEDIT's VM allocation sized for the old
    # signature. Different signing layouts can change that size. A fixed ad-hoc
    # sign/remove cycle lets codesign normalize that allocation on disposable
    # copies; compare every resulting byte, never just sections or UUIDs.
    with tempfile.TemporaryDirectory(prefix='lineup-ax-signature-') as temporary:
        copy = Path(temporary) / binary.name
        shutil.copy2(binary, copy)
        display = subprocess.run(['codesign', '-d', str(copy)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if display.returncode == 0:
            run(['codesign', '--remove-signature', copy])
        else:
            require(b'not signed at all' in display.stderr, 'Cannot inspect engine code signature.')
        run(['codesign', '--force', '--sign', '-', '--identifier',
             'lineup.engine-comparison', '--pagesize', '16384', '--timestamp=none', copy])
        run(['codesign', '--remove-signature', copy])
        return file_hash(copy)


APP_RECEIPT_SUFFIX = '.build-receipt.json'


def app_source(repository):
    require(not git(repository, 'status', '--porcelain').strip(),
            'Verified app provenance requires clean committed Lineup source.')
    return git(repository, 'rev-parse', 'HEAD').decode().strip()


def bundle_artifacts(app):
    require(app.is_dir(), 'App bundle is missing.')
    artifacts = {}
    for path in sorted(app.rglob('*')):
        relative = path.relative_to(app).as_posix()
        require(path.resolve().is_relative_to(app.resolve()), 'App bundle path escapes the bundle.')
        if path.is_symlink():
            artifacts[relative] = {'symlink': os.readlink(path)}
        elif path.is_file():
            artifacts[relative] = {'sha256': file_hash(path), 'mode': path.stat().st_mode & 0o777}
    require(artifacts, 'App bundle has no artifacts.')
    # Includes Runner, App.framework Dart executable, Flutter assets and code
    # signatures. Sidecars live beside the bundle and do not invalidate signing.
    require(any((app / name).is_file() for name in ('Contents/Frameworks/App.framework/App',
                'Contents/Frameworks/App.framework/Versions/A/App')), 'Built Dart App.framework executable is missing.')
    require(any('/flutter_assets/' in name for name in artifacts), 'Built Flutter assets are missing.')
    return artifacts


def validate_recipe(repository, selected, recipe):
    require(recipe.get('schemaVersion') == 1 and recipe.get('flutterExitCode') == 0,
            'Require a successful wrapper Flutter build recipe.')
    require(recipe.get('appCommit') == app_source(repository), 'App build receipt belongs to another source commit.')
    require(recipe.get('engine') == selected, 'App build receipt belongs to another engine candidate.')
    require(recipe.get('entrypoint') == 'lib/main.dart' and recipe.get('mode') == selected['mode'],
            'App build recipe entrypoint/mode mismatch.')
    arguments = recipe.get('flutterArguments', [])
    prefix = [f"--local-engine-src-path={selected['engineSource']}",
              f"--local-engine={selected['outputName']}", f"--local-engine-host={selected['outputName']}",
              'build', 'macos']
    require(isinstance(arguments, list) and arguments[:5] == prefix and
            f"--{selected['mode']}" in arguments, 'App build recipe does not select the canonical engine build.')
    build_options = arguments[5:-2]
    selected_mode = f"--{selected['mode']}"
    require(build_options.count(selected_mode) == 1 and all(isinstance(option, str) and
            (option == selected_mode or (re.fullmatch(r'--dart-define=[^=]+=[\s\S]*', option) and
             not option.startswith(('--dart-define=LINEUP_VERSION=', '--dart-define=LINEUP_BUILD='))))
            for option in build_options),
            'App build recipe only supports the selected mode and inline Dart defines.')
    version_lines = re.findall(r'^version:\s*([^\s]+)\s*$', (repository / 'pubspec.yaml').read_text(), re.M)
    require(len(version_lines) == 1 and len(version_lines[0].split('+')) == 2, 'Cannot establish app version.')
    version, number = version_lines[0].split('+')
    require(arguments[-2:] == [f'--dart-define=LINEUP_VERSION={version}',
                               f"--dart-define=LINEUP_BUILD={number}@{recipe['appCommit']}"],
            'App build recipe has incorrect application identity.')
    return version_lines[0]


def record_app_build(repository, root, name, target, architecture, mode, app, recipe):
    """Record the wrapper's successful build; this is local evidence, not attestation.

    Only the build owner calls this after Flutter exits successfully. A caller
    able to fabricate local receipts is outside this provenance trust boundary.
    Standalone bundle verification never creates or updates this receipt.
    """
    selected = verify(repository, root, name, target, architecture, mode)
    version = validate_recipe(repository, selected, recipe)
    record = {'schemaVersion': 1, 'kind': selected['kind'], 'recipe': recipe,
              'appVersion': version, 'bundleArtifacts': bundle_artifacts(app)}
    require(recipe['appCommit'] == app_source(repository), 'App source changed while recording the build receipt.')
    destination = app.parent / (app.name + APP_RECEIPT_SUFFIX)
    destination.write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
    return {'kind': selected['kind'], 'receiptSha256': file_hash(destination)}


def bundle(repository, root, name, target, architecture, mode, app):
    selected = verify(repository, root, name, target, architecture, mode)
    receipt_path = app.parent / (app.name + APP_RECEIPT_SUFFIX)
    require(receipt_path.is_file(), 'App successful-build receipt is missing; build with the macOS wrapper.')
    receipt = json.loads(receipt_path.read_text())
    require(receipt.get('schemaVersion') == 1 and receipt.get('kind') == selected['kind'], 'Unsupported app build receipt.')
    recipe = receipt['recipe']
    version_from_receipt = validate_recipe(repository, selected, recipe)
    require(receipt.get('bundleArtifacts') == bundle_artifacts(app), 'App bundle Dart code/assets or other artifacts changed after build receipt.')
    require(target == 'macos' and platform.system() == 'Darwin', 'Bundle verification currently supports native macOS only.')
    embedded = app / 'Contents/Frameworks/FlutterMacOS.framework/Versions/A/FlutterMacOS'
    require(embedded.is_file() and embedded.resolve().is_relative_to(app.resolve()), 'Bundled engine is missing or escapes the app.')
    built = Path(selected['binary'])
    built_contents = executable_hash(built)
    require(built_contents == executable_hash(embedded), 'App contains a different engine executable.')
    revision = recipe['appCommit']
    version = re.findall(r'^version:\s*([^\s]+)\s*$', (repository / 'pubspec.yaml').read_text(), re.M)
    require(len(version) == 1 and version[0] == version_from_receipt, 'App build receipt version mismatch.')
    info_path = app / 'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    version_parts = version[0].split('+')
    require(len(version_parts) == 2 and info.get('CFBundleShortVersionString') == version_parts[0]
            and str(info.get('CFBundleVersion')) == version_parts[1], 'Built app version disagrees with pubspec.')
    executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
    require(executable.is_file() and executable.resolve().is_relative_to(app.resolve()), 'App executable is missing or escapes the bundle.')
    record = {'schemaVersion': 1, 'kind': selected['kind'], 'appCommit': revision, 'appVersion': version[0],
              'appExecutableSha256': file_hash(executable), 'infoPlistSha256': file_hash(info_path),
              'buildReceiptSha256': file_hash(receipt_path), 'buildRecipe': recipe,
              'bundleArtifacts': receipt['bundleArtifacts'],
              'engine': selected, 'builtEngineSha256': file_hash(built),
              'bundledEngineSha256': file_hash(embedded), 'unsignedExecutableSha256': built_contents,
              'runtimeLoadedEngine': 'not observed; requires native runtime evidence'}
    require(recipe['appCommit'] == app_source(repository), 'App source changed during bundle verification.')
    destination = app.parent / (app.name + '.engine-provenance.json')
    destination.write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['finalize', 'verify-source', 'apply', 'build', 'verify', 'record-app-build', 'bundle'])
    parser.add_argument('--repository', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--flutter-root', type=Path, required=True)
    parser.add_argument('--platform', choices=['macos', 'windows'], default='macos')
    parser.add_argument('--architecture', choices=['arm64', 'x64'], default='arm64')
    parser.add_argument('--mode', choices=['debug', 'profile', 'release'], default='debug')
    parser.add_argument('--output-name')
    parser.add_argument('--ninja', default='ninja')
    parser.add_argument('--apple-linker', action='store_true')
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--gclient', type=Path)
    parser.add_argument('--app', type=Path)
    parser.add_argument('--recipe-file', type=Path)
    args = parser.parse_args()
    repository, root = args.repository.resolve(), args.flutter_root.resolve()
    if args.action == 'finalize':
        result = finalize(repository, root)
    elif args.action == 'apply':
        framework, windows = pins(repository)
        verify_checkout(root, framework, windows)
        require(not git(root, 'status', '--porcelain', '--untracked-files=no').strip(), 'Applying patches requires a clean tracked Flutter checkout.')
        identity = source_identity(repository, root, args.platform, require_applied=False)
        # Validate the complete manifest and every patch before atomic git apply.
        paths = [committed(repository, entry['path']) for entry in identity['patches']]
        git(root, 'apply', '--check', *paths)
        git(root, 'apply', *paths)
        result = source_identity(repository, root, args.platform)
    elif args.action == 'verify-source':
        result = verified_sources(repository, root, args.platform, args.gclient)
    elif args.action == 'build':
        result = build(repository, root, args.platform, args.architecture, args.mode, args.ninja, args.apple_linker, args.jobs, args.gclient)
    else:
        require(args.output_name, '--output-name is required.')
        if args.action in ('bundle', 'record-app-build'):
            require(args.app, '--app is required.')
            if args.action == 'record-app-build':
                require(args.recipe_file, '--recipe-file is required.')
                result = record_app_build(repository, root, args.output_name, args.platform, args.architecture, args.mode,
                                          args.app.resolve(), json.loads(args.recipe_file.read_text()))
            else:
                result = bundle(repository, root, args.output_name, args.platform, args.architecture, args.mode, args.app.resolve())
        else:
            result = verify(repository, root, args.output_name, args.platform, args.architecture, args.mode)
    if args.action == 'bundle':
        print(json.dumps({'kind': result['kind'], 'status': 'bundle and successful-build receipt verified'}, sort_keys=True))
    else:
        print(json.dumps(result, sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except (VerificationError, OSError, ValueError, KeyError, TypeError) as error:
        print(f'Desktop accessibility engine: {error}', file=sys.stderr)
        sys.exit(1)
