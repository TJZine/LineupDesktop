// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';

const objCFlags = ['-x', 'objective-c', '-fobjc-arc'];

const assetName = 'objective_c.dylib';

final logger = Logger('')
  ..level = Level.INFO
  ..onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      // Don't build any other asset types.
      return;
    }

    final supportedOSs = {OS.iOS, OS.macOS};
    final codeConfig = input.config.code;
    final os = codeConfig.targetOS;
    if (!supportedOSs.contains(os)) {
      // Nothing to do.
      return;
    }

    if (codeConfig.linkModePreference == LinkModePreference.static) {
      throw UnsupportedError('LinkModePreference.static is not supported.');
    }

    final packageName = input.packageName;
    final minVersion = minOSVersion(
      codeConfig,
      macosTargetVersion: input.userDefines['macos_target_version'],
    );
    final outputDirectory = os == OS.macOS
        ? input.outputDirectory.resolve('macos-${minVersion.split('=').last}/')
        : input.outputDirectory;
    final assetPath = outputDirectory.resolve(assetName);
    final srcDir = Directory.fromUri(input.packageRoot.resolve('src/'));
    final target = toTargetTriple(codeConfig);

    final cFiles = <String>[];
    final mFiles = <String>[];
    final hFiles = <String>[];
    for (final file in srcDir.listSync(recursive: true)) {
      if (file is File) {
        final path = file.path;
        if (path.endsWith('.c')) cFiles.add(path);
        if (path.endsWith('.m')) mFiles.add(path);
        if (path.endsWith('.h')) hFiles.add(path);
      }
    }

    final testMode = input.userDefines['include_test_utils'] == true;
    if (testMode) {
      mFiles.add(input.packageRoot.resolve('test/gc_inject.m').toFilePath());
      mFiles.add(
        input.packageRoot.resolve('test/reference_tracker.m').toFilePath(),
      );
    }

    final sysroot = sdkPath(codeConfig);

    final cFlags = <String>[
      '-isysroot',
      sysroot,
      '-target',
      target,
      minVersion,
    ];
    final mFlags = [...cFlags, ...objCFlags];
    final linkFlags = cFlags;

    final builder = await Builder.create(
      input,
      input.packageRoot.toFilePath(),
      outputDirectory,
    );

    // Hash selected inputs before compiling, and require them to stay unchanged.
    // The receipt retains these producing-time identities across hook cache hits.
    final sources = <Uri>[
      input.packageRoot.resolve('hook/build.dart'),
      input.packageRoot.resolve('pubspec.yaml'),
      ...[...cFiles, ...mFiles, ...hFiles].map(Uri.file),
    ]..sort((a, b) => a.toString().compareTo(b.toString()));
    final compiler = os == OS.macOS
        ? await resolvedCompiler(builder._compiler)
        : builder._compiler;
    final workspacePubspec = os == OS.macOS
        ? input.userDefines
              .baseUri(['macos_target_version'])
              ?.resolve('pubspec.yaml')
        : null;
    Future<Map<String, Object>> snapshot() => producingInputs(
      sources,
      input.packageRoot,
      compiler,
      sysroot,
      input.json,
      workspacePubspec,
    );
    final producing = os == OS.macOS ? await snapshot() : null;

    final objectFiles = await Future.wait(<Future<String>>[
      for (final src in cFiles) builder.buildObject(src, cFlags),
      for (final src in mFiles) builder.buildObject(src, mFlags),
    ]);
    await builder.linkLib(objectFiles, assetPath.toFilePath(), linkFlags);

    if (os == OS.macOS) {
      if (jsonEncode(producing) != jsonEncode(await snapshot())) {
        throw StateError('objective_c inputs changed during compilation.');
      }
      if (workspacePubspec != null) output.dependencies.add(workspacePubspec);
      output.dependencies.add(Uri.file(compiler));
      output.dependencies.add(Uri.file('$sysroot/SDKSettings.json'));
      await File.fromUri(
        outputDirectory.resolve('lineup-objective-c-build.json'),
      ).writeAsString(
        jsonEncode({
          'schemaVersion': 2,
          'assetId': 'package:objective_c/objective_c.dylib',
          'packageRoot': input.packageRoot.toFilePath(),
          'architecture': codeConfig.targetArchitecture.toString(),
          'compileFlags': cFlags,
          'linkFlags': linkFlags,
          'compiler': compiler,
          'sdk': sysroot,
          'producingInputs': producing,
          'asset': assetPath.toFilePath(),
          'rawAssetSha256': await sha256File(assetPath),
        }),
      );
    }
    output.dependencies.add(input.packageRoot.resolve('hook/build.dart'));
    output.dependencies.add(input.packageRoot.resolve('pubspec.yaml'));
    output.dependencies.addAll(cFiles.map(Uri.file));
    output.dependencies.addAll(mFiles.map(Uri.file));
    output.dependencies.addAll(hFiles.map(Uri.file));

    output.assets.code.add(
      CodeAsset(
        package: packageName,
        name: assetName,
        file: assetPath,
        linkMode: DynamicLoadingBundled(),
      ),
    );
  });
}

Future<String> resolvedCompiler(String compiler) async {
  if (compiler.startsWith('/')) return File(compiler).resolveSymbolicLinks();
  final result = await Process.run('/usr/bin/which', [compiler]);
  if (result.exitCode != 0) {
    throw StateError('Cannot resolve compiler $compiler');
  }
  return File((result.stdout as String).trim()).resolveSymbolicLinks();
}

Future<String> sha256File(Uri file) async {
  final result = await Process.run('/usr/bin/shasum', [
    '-a',
    '256',
    '--',
    file.toFilePath(),
  ]);
  final digest = (result.stdout as String).split(' ').first;
  if (result.exitCode != 0 || !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
    throw StateError('Cannot hash build input ${file.toFilePath()}');
  }
  return digest;
}

Future<Map<String, Object>> producingInputs(
  List<Uri> sources,
  Uri packageRoot,
  String compiler,
  String sdk,
  Map<String, Object?> configuration,
  Uri? workspacePubspec,
) async => {
  'configuration': configuration,
  if (workspacePubspec != null)
    'workspacePubspecSha256': await sha256File(workspacePubspec),
  'sources': {
    for (final file in sources)
      file.toFilePath().substring(packageRoot.toFilePath().length):
          await sha256File(file),
  },
  'compilerSha256': await sha256File(Uri.file(compiler)),
  'sdkSettingsSha256': await sha256File(Uri.file('$sdk/SDKSettings.json')),
};

class Builder {
  final String _compiler;
  final String _rootDir;
  final Uri _tempOutDir;
  Builder._(this._compiler, this._rootDir, this._tempOutDir);

  static Future<Builder> create(
    BuildInput input,
    String rootDir,
    Uri outputDirectory,
  ) async {
    return Builder._(
      await _findCompiler(input.config.code),
      rootDir,
      outputDirectory.resolve('obj/'),
    );
  }

  static Future<String> _findCompiler(CodeConfig codeConfig) async {
    final compiler = codeConfig.cCompiler?.compiler.toFilePath();
    if (compiler != null) {
      assert(await File(compiler).exists());
      logger.info('Using compiler $compiler from BuildInput.cCompiler.cc.');
      return compiler;
    }
    logger.info(
      'No compiler set in BuildInput.cCompiler.cc. Falling back to '
      'assuming clang is in the PATH.',
    );
    return 'clang';
  }

  Future<String> buildObject(String input, List<String> flags) async {
    assert(input.startsWith(_rootDir));
    final relativeInput = input.substring(_rootDir.length);
    final output = '${_tempOutDir.resolve(relativeInput).toFilePath()}.o';
    File(output).parent.createSync(recursive: true);
    await _compile([
      ...flags,
      '-c',
      input,
      '-fpic',
      '-gline-tables-only',
      '-I',
      'src',
    ], output);
    return output;
  }

  Future<void> linkLib(
    List<String> objects,
    String output,
    List<String> flags,
  ) => _compile([
    '-shared',
    '-Wl,-encryptable',
    '-undefined',
    'dynamic_lookup',
    ...flags,
    ...objects,
  ], output);

  Future<void> _compile(List<String> flags, String output) async {
    final args = [...flags, '-o', output];
    logger.info('Running: $_compiler ${args.join(" ")}');
    final proc = await Process.run(_compiler, args);
    logger.info(proc.stdout);
    logger.info(proc.stderr);
    if (proc.exitCode != 0) {
      exitCode = proc.exitCode;
      throw Exception('Command failed: $_compiler ${args.join(" ")}');
    }
    logger.info('Generated $output');
  }
}

String sdkPath(CodeConfig codeConfig) {
  final String target;
  if (codeConfig.targetOS == OS.iOS) {
    if (codeConfig.iOS.targetSdk == IOSSdk.iPhoneOS) {
      target = 'iphoneos';
    } else {
      target = 'iphonesimulator';
    }
  } else {
    assert(codeConfig.targetOS == OS.macOS);
    target = 'macosx';
  }
  return firstLineOfStdout('xcrun', ['--show-sdk-path', '--sdk', target]);
}

String firstLineOfStdout(String cmd, List<String> args) {
  final result = Process.runSync(cmd, args);
  assert(result.exitCode == 0);
  return (result.stdout as String)
      .split('\n')
      .where((line) => line.isNotEmpty)
      .first;
}

String minOSVersion(CodeConfig codeConfig, {Object? macosTargetVersion}) {
  if (codeConfig.targetOS == OS.iOS) {
    final targetVersion = codeConfig.iOS.targetVersion;
    return '-mios-version-min=$targetVersion';
  }
  assert(codeConfig.targetOS == OS.macOS);
  if (macosTargetVersion != null &&
      (macosTargetVersion is! int ||
          macosTargetVersion < 10 ||
          macosTargetVersion > 99)) {
    throw const FormatException(
      'macos_target_version must be an integer from 10 to 99.',
    );
  }
  final targetVersion = macosTargetVersion ?? codeConfig.macOS.targetVersion;
  return '-mmacos-version-min=$targetVersion';
}

String toTargetTriple(CodeConfig codeConfig) {
  final architecture = codeConfig.targetArchitecture;
  if (codeConfig.targetOS == OS.iOS) {
    return appleClangIosTargetFlags[architecture]![codeConfig.iOS.targetSdk]!;
  }
  assert(codeConfig.targetOS == OS.macOS);
  return appleClangMacosTargetFlags[architecture]!;
}

final appleClangMacosTargetFlags = {
  Architecture.arm64: 'arm64-apple-darwin',
  Architecture.arm64e: 'arm64e-apple-darwin',
  Architecture.x64: 'x86_64-apple-darwin',
};

final appleClangIosTargetFlags = {
  Architecture.arm64: {
    IOSSdk.iPhoneOS: 'arm64-apple-ios',
    IOSSdk.iPhoneSimulator: 'arm64-apple-ios-simulator',
  },
  Architecture.arm64e: {
    IOSSdk.iPhoneOS: 'arm64e-apple-ios',
    IOSSdk.iPhoneSimulator: 'arm64e-apple-ios-simulator',
  },
  Architecture.x64: {IOSSdk.iPhoneSimulator: 'x86_64-apple-ios-simulator'},
};
