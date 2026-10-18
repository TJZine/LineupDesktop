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
    if (argument == '--dart-define' ||
        argument.startsWith('--dart-define=LINEUP_VERSION=') ||
        argument.startsWith('--dart-define=LINEUP_BUILD=') ||
        argument.startsWith('--dart-define-from-file') ||
        argument.startsWith('--build-name') ||
        argument.startsWith('--build-number')) {
      throw const FormatException(
        'App version/build identity is owned by pubspec.yaml and Git HEAD. '
        'Use --dart-define=NAME=VALUE for other defines.',
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
    final flutterArguments = macosAppArguments(
      pubspec: File('${repository.path}/pubspec.yaml').readAsStringSync(),
      commit: (revision.stdout as String).trim(),
      arguments: arguments,
    );
    final flutter = await Process.start(
      Platform.isWindows ? 'flutter.bat' : 'flutter',
      flutterArguments,
      workingDirectory: repository.path,
      mode: ProcessStartMode.inheritStdio,
      runInShell: Platform.isWindows,
    );
    exitCode = await flutter.exitCode;
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
