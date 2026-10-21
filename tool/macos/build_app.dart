import 'dart:convert';
import 'dart:io';

/// macOS uses the same pubspec + exact Git identity as the Windows release.
List<String> macosAppArguments({
  required String pubspec,
  required String commit,
  required List<String> arguments,
}) {
  if (arguments.isEmpty || !const ['build', 'run'].contains(arguments.first)) {
    throw const FormatException(
      'Usage: dart tool/macos/build_app.dart <build|run> [Flutter options]',
    );
  }
  final versionLines = pubspec
      .split('\n')
      .where((line) => RegExp(r'^version\s*:').hasMatch(line));
  if (versionLines.length != 1) {
    throw const FormatException(
      'pubspec.yaml must contain exactly one top-level version entry.',
    );
  }
  final version = RegExp(r'^version\s*:\s*([^+\s]+)\+([0-9]+)\s*(?:#.*)?$')
      .firstMatch(versionLines.single);
  if (version == null) {
    throw const FormatException(
      'pubspec.yaml version must have a name and numeric build number (name+build).',
    );
  }
  if (!RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(commit)) {
    throw const FormatException('Build identity requires an exact Git commit.');
  }
  // The wrapper owns identity. An option file could silently replace defines,
  // and Flutter build-name/build-number overrides would disagree with pubspec.
  for (final argument in arguments.skip(1)) {
    if (argument.startsWith('--local-engine') ||
        argument == '--dart-define' ||
        argument.startsWith('--dart-define=LINEUP_VERSION=') ||
        argument.startsWith('--dart-define=LINEUP_BUILD=') ||
        argument.startsWith('--dart-define-from-file') ||
        argument.startsWith('--build-name') ||
        argument.startsWith('--build-number')) {
      throw const FormatException(
        'App version/build identity is owned by pubspec.yaml and Git HEAD. '
        'Use --dart-define=NAME=VALUE for other defines. '
        'Raw local-engine flags are not supported; use the verified '
        '--accessibility-engine-root and --accessibility-engine options.',
      );
    }
  }
  return [
    if (arguments.first == 'build') ...[
      'build',
      'macos',
    ] else ...[
      'run',
      '-d',
      'macos',
    ],
    ...arguments.skip(1),
    '--dart-define=LINEUP_VERSION=${version.group(1)}',
    '--dart-define=LINEUP_BUILD=${version.group(2)}@$commit',
  ];
}

/// Engine selection belongs to this wrapper, before Flutter sees its arguments.
class MacosEngineOptions {
  MacosEngineOptions(List<String> arguments) {
    for (final argument in arguments) {
      if (argument.startsWith('--accessibility-engine-root=')) {
        if (root != null) {
          throw const FormatException('Duplicate engine root.');
        }
        root = argument.substring('--accessibility-engine-root='.length);
      } else if (argument.startsWith('--accessibility-engine=')) {
        if (name != null) {
          throw const FormatException('Duplicate engine output.');
        }
        name = argument.substring('--accessibility-engine='.length);
      } else {
        flutterArguments.add(argument);
      }
    }
    if ((root == null) != (name == null) || root == '' || name == '') {
      throw const FormatException(
        'Supply both --accessibility-engine-root=PATH '
        'and --accessibility-engine=OUTPUT.',
      );
    }
    if (root != null) {
      if (flutterArguments.isEmpty || flutterArguments.first != 'build') {
        throw const FormatException(
          'Verified local engines require build. '
          'Launch the verified app bundle after build verification.',
        );
      }
      const modes = ['--debug', '--profile', '--release'];
      final selected = flutterArguments.where(modes.contains).toList();
      if (selected.length != 1) {
        throw const FormatException(
          'Select exactly one engine build mode: '
          '--debug, --profile or --release.',
        );
      }
      mode = selected.single.substring(2);
      for (final argument in flutterArguments.skip(1)) {
        final inlineDefine =
            argument.startsWith('--dart-define=') &&
            argument.indexOf('=', '--dart-define='.length) >
                '--dart-define='.length;
        if (!modes.contains(argument) && !inlineDefine) {
          throw const FormatException(
            'Verified engine builds require the '
            'canonical lib/main.dart app build: only the selected mode and '
            'inline --dart-define=NAME=VALUE options are supported.',
          );
        }
      }
    }
  }

  String? root;
  String? name;
  String? mode;
  final List<String> flutterArguments = [];
}

Future<Map<String, dynamic>> _engineTool(
  Directory repository,
  MacosEngineOptions options,
  String action, {
  String? app,
  String? recipeFile,
}) async {
  final result = await Process.run('python3', [
    '${repository.path}/tool/flutter_engine/desktop_accessibility.py',
    action,
    '--flutter-root',
    options.root!,
    '--platform',
    'macos',
    '--architecture',
    'arm64',
    '--mode',
    options.mode!,
    '--output-name',
    options.name!,
    if (app != null) ...['--app', app],
    if (recipeFile != null) ...['--recipe-file', recipeFile],
  ], workingDirectory: repository.path);
  if (result.exitCode != 0) {
    throw FormatException((result.stderr as String).trim());
  }
  final resultMap = jsonDecode(result.stdout as String) as Map<String, dynamic>;
  if (resultMap['kind'] != 'verified-local-desktop-accessibility') {
    throw const FormatException(
      'Engine verifier did not select a verified candidate.',
    );
  }
  return resultMap;
}

Future<Map<String, dynamic>> _nativeAssets(
  Directory repository,
  String action, {
  String? app,
  String? inputs,
}) async {
  final result = await Process.run('python3', [
    '${repository.path}/tool/macos/native_assets.py',
    action,
    '--repository',
    repository.path,
    if (app != null) ...['--app', app],
    if (inputs != null) ...['--inputs', inputs],
  ], workingDirectory: repository.path);
  if (result.exitCode != 0) {
    throw FormatException((result.stderr as String).trim());
  }
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

Future<void> main(List<String> arguments) async {
  try {
    final repository = File.fromUri(Platform.script).parent.parent.parent;
    final prefix = await Process.run('git', [
      '-C',
      repository.path,
      'rev-parse',
      '--show-prefix',
    ]);
    if (prefix.exitCode != 0 || (prefix.stdout as String).trim().isNotEmpty) {
      throw const FormatException('Build inputs must belong to the Git root.');
    }
    final revision = await Process.run('git', [
      '-C',
      repository.path,
      'rev-parse',
      '--verify',
      'HEAD',
    ]);
    if (revision.exitCode != 0) {
      throw const FormatException(
        'Build identity requires an exact Git commit.',
      );
    }
    final options = MacosEngineOptions(arguments);
    final flutterArguments = macosAppArguments(
      pubspec: File('${repository.path}/pubspec.yaml').readAsStringSync(),
      commit: (revision.stdout as String).trim(),
      arguments: options.flutterArguments,
    );
    Map<String, dynamic>? selectedEngine;
    String? appPath;
    if (options.root != null) {
      final dirty = await Process.run('git', [
        '-C',
        repository.path,
        'status',
        '--porcelain',
      ]);
      if (dirty.exitCode != 0 || (dirty.stdout as String).trim().isNotEmpty) {
        throw const FormatException(
          'Verified engine app builds require clean committed Lineup source.',
        );
      }
      selectedEngine = await _engineTool(repository, options, 'verify');
      final mode = options.mode!;
      final configuration = '${mode[0].toUpperCase()}${mode.substring(1)}';
      appPath =
          '${repository.path}/build/macos/Build/Products/'
          '$configuration/Lineup Desktop.app';
      for (final suffix in ['.engine-provenance.json', '.build-receipt.json']) {
        final previous = File('$appPath$suffix');
        if (previous.existsSync()) {
          previous.deleteSync();
        }
      }
      flutterArguments.insertAll(0, [
        '--local-engine-src-path=${selectedEngine['engineSource']}',
        '--local-engine=${options.name}',
        '--local-engine-host=${options.name}',
      ]);
      stdout.writeln(
        'Engine: verified local desktop accessibility '
        '(${options.name}, arm64, ${options.mode}).',
      );
    } else {
      stdout.writeln(
        'Engine: stock Flutter SDK; desktop accessibility repair '
        'is not selected. App source may include local development edits.',
      );
    }
    // Flutter's negatable flags use the last occurrence (package:args).
    var configOnly = false;
    for (final argument in options.flutterArguments.skip(1)) {
      if (argument == '--') break;
      if (argument == '--config-only') configOnly = true;
      if (argument.split('=').first == '--no-config-only') configOnly = false;
    }
    final verifyNativeAssets =
        options.flutterArguments.first == 'build' &&
        !configOnly &&
        !options.flutterArguments.any(
          (value) => value == '--help' || value == '-h' || value == '--version',
        );
    if (verifyNativeAssets) {
      final mode =
          options.mode ??
          (options.flutterArguments.contains('--debug')
              ? 'debug'
              : options.flutterArguments.contains('--profile')
              ? 'profile'
              : 'release');
      final configuration = '${mode[0].toUpperCase()}${mode.substring(1)}';
      appPath ??=
          '${repository.path}/build/macos/Build/Products/'
          '$configuration/Lineup Desktop.app';
      if (selectedEngine == null) {
        final report = File('$appPath.native-assets.json');
        if (await report.exists()) await report.delete();
      }
    }
    final nativeInputs = verifyNativeAssets
        ? await _nativeAssets(repository, 'inputs')
        : null;
    final flutter = await Process.start(
      selectedEngine == null
          ? (Platform.isWindows ? 'flutter.bat' : 'flutter')
          : '${selectedEngine['flutterRoot']}/bin/flutter',
      flutterArguments,
      workingDirectory: repository.path,
      mode: ProcessStartMode.inheritStdio,
      runInShell: Platform.isWindows,
    );
    exitCode = await flutter.exitCode;
    Map<String, dynamic>? nativeVerification;
    if (exitCode == 0 && nativeInputs != null) {
      final temporary = await Directory.systemTemp.createTemp(
        'lineup-native-inputs-',
      );
      try {
        final inputs = File('${temporary.path}/inputs.json');
        await inputs.writeAsString(jsonEncode(nativeInputs));
        nativeVerification = await _nativeAssets(
          repository,
          'verify',
          app: appPath,
          inputs: inputs.path,
        );
      } finally {
        await temporary.delete(recursive: true);
      }
      if (selectedEngine == null) {
        await File('$appPath.native-assets.json').writeAsString(
          jsonEncode({
            'sourceCommit': (revision.stdout as String).trim(),
            'nativeAssets': nativeVerification,
            'runtimeAcceptance': 'not observed',
          }),
        );
      }
    }
    if (exitCode == 0 && selectedEngine != null) {
      final current = await Process.run('git', [
        '-C',
        repository.path,
        'rev-parse',
        '--verify',
        'HEAD',
      ]);
      if (current.exitCode != 0 || current.stdout != revision.stdout) {
        throw const FormatException(
          'App source revision changed during build.',
        );
      }
      final temporary = await Directory.systemTemp.createTemp(
        'lineup-app-recipe-',
      );
      try {
        final recipe = File('${temporary.path}/recipe.json');
        await recipe.writeAsString(
          jsonEncode({
            'schemaVersion': 1,
            'flutterExitCode': 0,
            'appCommit': (revision.stdout as String).trim(),
            'engine': selectedEngine,
            'nativeAssets': nativeVerification,
            'entrypoint': 'lib/main.dart',
            'mode': options.mode,
            'flutterArguments': flutterArguments,
          }),
        );
        await _engineTool(
          repository,
          options,
          'record-app-build',
          app: appPath!,
          recipeFile: recipe.path,
        );
      } finally {
        await temporary.delete(recursive: true);
      }
      await _engineTool(repository, options, 'bundle', app: appPath);
      stdout.writeln(
        'Verified bundled engine contents. Provenance: '
        '$appPath.engine-provenance.json. Runtime loaded engine remains unobserved.',
      );
    }
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  } on ProcessException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  }
}
