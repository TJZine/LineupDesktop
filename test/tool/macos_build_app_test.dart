import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/macos/build_app.dart';

void main() {
  const commit = '1234567890abcdef1234567890abcdef12345678';

  List<String> arguments({
    String pubspec = 'version: 1.2.3+45 # app version\n',
    String revision = commit,
    List<String> options = const ['build', '--release'],
  }) =>
      macosAppArguments(pubspec: pubspec, commit: revision, arguments: options);

  test('macOS builds pass Windows release identity defines', () {
    expect(arguments(), [
      'build',
      'macos',
      '--release',
      '--dart-define=LINEUP_VERSION=1.2.3',
      '--dart-define=LINEUP_BUILD=45@$commit',
    ]);
    expect(arguments(pubspec: 'version: 9.8.7+65'), [
      'build',
      'macos',
      '--release',
      '--dart-define=LINEUP_VERSION=9.8.7',
      '--dart-define=LINEUP_BUILD=65@$commit',
    ]);
  });

  test('development runs and harnesses use the same identity mechanism', () {
    expect(
      arguments(
        options: [
          'run',
          '--debug',
          '--dart-define=LINEUP_HARNESS_EXERCISE=true',
        ],
      ),
      [
        'run',
        '-d',
        'macos',
        '--debug',
        '--dart-define=LINEUP_HARNESS_EXERCISE=true',
        '--dart-define=LINEUP_VERSION=1.2.3',
        '--dart-define=LINEUP_BUILD=45@$commit',
      ],
    );
  });

  test('missing or ambiguous metadata fails instead of falling back', () {
    for (final pubspec in [
      'name: missing',
      'version: 1.2.3',
      'version: 1.2.3+beta',
      'version: 1.2.3+45\nversion: 2.0.0+46',
    ]) {
      expect(() => arguments(pubspec: pubspec), throwsFormatException);
    }
    for (final revision in ['', 'HEAD', '1234567']) {
      expect(() => arguments(revision: revision), throwsFormatException);
    }
  });

  test('identity cannot be replaced by Flutter overrides or option files', () {
    for (final option in [
      '--dart-define=LINEUP_VERSION=other',
      '--dart-define=LINEUP_BUILD=other',
      '--dart-define',
      '--dart-define-from-file=other.json',
      '--build-name=other',
      '--build-number=999',
    ]) {
      expect(
        () => arguments(options: ['build', option]),
        throwsFormatException,
      );
    }
    expect(() => arguments(options: []), throwsFormatException);
    expect(() => arguments(options: ['windows']), throwsFormatException);
  });

  group('macOS build entry point', () {
    final source = File('tool/macos/build_app.dart').absolute;
    final dart = _dartExecutable();
    late Directory repository;

    setUp(() async {
      repository = await Directory.systemTemp.createTemp(
        'lineup build inputs ',
      );
      final script = File('${repository.path}/tool/macos/build_app.dart');
      await script.parent.create(recursive: true);
      await source.copy(script.path);
      await File('${repository.path}/pubspec.yaml')
          .writeAsString('version: 9.8.7+65\n');
      for (final arguments in [
        ['init', '--quiet'],
        ['add', '.'],
        [
          '-c',
          'user.name=Lineup fixture',
          '-c',
          'user.email=fixture@example.invalid',
          'commit',
          '--quiet',
          '-m',
          'fixture',
        ],
      ]) {
        final result = await Process.run('git', [
          '-C',
          repository.path,
          ...arguments,
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
      }
      final fixture = File('${repository.path}/flutter_fixture.dart');
      await fixture.writeAsString('''
import 'dart:convert';
import 'dart:io';
void main(List<String> arguments) {
  File('invocation.json').writeAsStringSync(jsonEncode(arguments));
  exitCode = int.parse(Platform.environment['LINEUP_FIXTURE_EXIT']!);
}
''');
      final launcher = File(
        '${repository.path}/${Platform.isWindows ? 'flutter.bat' : 'flutter'}',
      );
      await launcher.writeAsString(
        Platform.isWindows
            ? '@echo off\r\n"$dart" "${fixture.path}" %*\r\n'
            : '#!/bin/sh\nexec "$dart" "${fixture.path}" "\$@"\n',
      );
      if (!Platform.isWindows) {
        final result = await Process.run('chmod', ['+x', launcher.path]);
        expect(result.exitCode, 0);
      }
    });

    tearDown(() => repository.delete(recursive: true));

    Future<ProcessResult> run({int flutterExit = 0}) {
      final environment = Map<String, String>.from(Platform.environment);
      final pathKey = environment.keys.firstWhere(
        (key) => key.toLowerCase() == 'path',
      );
      environment[pathKey] =
          '${repository.path}${Platform.isWindows ? ';' : ':'}'
          '${environment[pathKey]}';
      environment['LINEUP_FIXTURE_EXIT'] = '$flutterExit';
      return Process.run(
        dart,
        ['${repository.path}/tool/macos/build_app.dart', 'build', '--release'],
        // The script uses its owning repository, not the caller's directory.
        workingDirectory: Directory.systemTemp.path,
        environment: environment,
      );
    }

    test(
      'actual invocation uses repository metadata and forwards exit status',
      () async {
        final result = await run(flutterExit: 23);
        expect(result.exitCode, 23, reason: '${result.stderr}');
        final revision = await Process.run('git', [
          '-C',
          repository.path,
          'rev-parse',
          '--verify',
          'HEAD',
        ]);
        final delivered = jsonDecode(
          File('${repository.path}/invocation.json').readAsStringSync(),
        );
        expect(delivered, [
          'build',
          'macos',
          '--release',
          '--dart-define=LINEUP_VERSION=9.8.7',
          '--dart-define=LINEUP_BUILD=65@${(revision.stdout as String).trim()}',
        ]);
      },
    );

    test('invalid metadata stops before invoking Flutter', () async {
      await File('${repository.path}/pubspec.yaml')
          .writeAsString('name: missing');
      final result = await run();
      expect(result.exitCode, 1);
      expect(result.stderr, contains('exactly one top-level version'));
      expect(File('${repository.path}/invocation.json').existsSync(), isFalse);
    });
  });
}

String _dartExecutable() {
  var directory = File(Platform.resolvedExecutable).parent;
  while (true) {
    final executable = File(
      '${directory.path}/bin/cache/dart-sdk/bin/'
      '${Platform.isWindows ? 'dart.exe' : 'dart'}',
    );
    if (executable.existsSync()) return executable.path;
    if (directory.parent.path == directory.path) {
      throw StateError('Cannot locate the test runner Flutter Dart SDK.');
    }
    directory = directory.parent;
  }
}
