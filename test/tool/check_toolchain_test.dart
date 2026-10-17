import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_toolchain.dart';

void main() {
  const expectedVersion = '3.47.7';
  const expectedRevision = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const actualVersion = '3.47.7';
  const actualRevision = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  FlutterPin pin() {
    return FlutterPin(
      version: expectedVersion,
      frameworkRevision: expectedRevision,
    );
  }

  FlutterToolchain toolchain({
    String version = actualVersion,
    String frameworkRevision = expectedRevision,
  }) {
    return FlutterToolchain(
      version: version,
      frameworkRevision: frameworkRevision,
      flutterRoot: '/opt/flutter/3.47.7/flutter',
    );
  }

  String machineOutput({
    Object version = actualVersion,
    Object frameworkRevision = expectedRevision,
  }) {
    return jsonEncode({
      'frameworkVersion': version,
      'frameworkRevision': frameworkRevision,
      'flutterRoot': '/opt/flutter/3.47.7/flutter',
    });
  }

  test('compares a matching toolchain', () {
    final result = compareToolchain(expected: pin(), actual: toolchain());

    expect(result.matches, isTrue);
    expect(result.versionMatches, isTrue);
    expect(result.frameworkRevisionMatches, isTrue);
  });

  test('detects a Flutter version mismatch', () {
    final result = compareToolchain(
      expected: pin(),
      actual: toolchain(version: '3.47.6'),
    );

    expect(result.matches, isFalse);
    expect(result.versionMatches, isFalse);
    expect(result.frameworkRevisionMatches, isTrue);
  });

  test('detects a framework revision mismatch', () {
    final result = compareToolchain(
      expected: pin(),
      actual: toolchain(frameworkRevision: actualRevision),
    );

    expect(result.matches, isFalse);
    expect(result.versionMatches, isTrue);
    expect(result.frameworkRevisionMatches, isFalse);
  });

  test('rejects malformed Flutter version output', () {
    expect(
      () => FlutterToolchain.fromMachineJson(machineOutput(version: 3.47)),
      throwsFormatException,
    );
    expect(
      () => FlutterToolchain.fromMachineJson('{not json'),
      throwsFormatException,
    );
  });

  test('rejects missing or malformed pin configuration', () {
    expect(() => FlutterPin.fromJson(null), throwsFormatException);
    expect(
      () => FlutterPin.fromJson({'version': expectedVersion}),
      throwsFormatException,
    );
    expect(
      () => FlutterPin.fromJson({
        'version': expectedVersion,
        'frameworkRevision': 'short',
      }),
      throwsFormatException,
    );
  });

  group('checker process boundary', () {
    final checker = File('tool/check_toolchain.dart').absolute.path;
    final dart = _dartExecutable();
    late Directory repository;

    setUp(() async {
      repository = await Directory.systemTemp.createTemp('lineup toolchain ');
      final initialized = await Process.run('git', [
        'init',
        '--quiet',
        repository.path,
      ]);
      expect(initialized.exitCode, 0, reason: '${initialized.stderr}');
      final pinFile = File('${repository.path}/tool/flutter_version.json');
      await pinFile.parent.create();
      await pinFile.writeAsString(
        jsonEncode({
          'version': expectedVersion,
          'frameworkRevision': expectedRevision,
        }),
      );
    });

    tearDown(() async {
      await repository.delete(recursive: true);
    });

    Future<ProcessResult> run({
      int bootstrapExit = 0,
      String? machineReport,
    }) async {
      final fixture = File('${repository.path}/flutter_fixture.dart');
      await fixture.writeAsString('''
import 'dart:io';

void main(List<String> arguments) {
  File('calls.txt').writeAsStringSync(
    '\${arguments.join(' ')}\\n', mode: FileMode.append);
  final ready = File('ready');
  if (!ready.existsSync()) {
    stdout.writeln('Resolving dependencies...');
    stdout.writeln('Downloading packages...');
  }
  if (arguments.length == 1 && arguments.single == '--version') {
    if ($bootstrapExit != 0) {
      stderr.writeln('Fixture bootstrap failed.');
      exit($bootstrapExit);
    }
    ready.writeAsStringSync('ready');
    stdout.writeln('Flutter $actualVersion');
  } else {
    stdout.writeln(${jsonEncode(machineReport ?? machineOutput())});
  }
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
        final permission = await Process.run('chmod', ['+x', launcher.path]);
        expect(permission.exitCode, 0, reason: '${permission.stderr}');
      }
      final environment = Map<String, String>.from(Platform.environment);
      final pathKey = environment.keys.firstWhere(
        (key) => key.toLowerCase() == 'path',
      );
      environment[pathKey] =
          '${repository.path}${Platform.isWindows ? ';' : ':'}'
          '${environment[pathKey]}';
      final process = await Process.start(
        dart,
        [checker],
        workingDirectory: repository.path,
        environment: environment,
      );
      final output = process.stdout.transform(utf8.decoder).join();
      final errors = process.stderr.transform(utf8.decoder).join();
      final code = await process.exitCode.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          process.kill();
          throw TimeoutException('Toolchain checker did not finish.');
        },
      );
      return ProcessResult(process.pid, code, await output, await errors);
    }

    Future<List<String>> calls() =>
        File('${repository.path}/calls.txt').readAsLines();

    test('initializes a cold SDK before reading its machine report', () async {
      final result = await run();
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('matches tool/flutter_version.json'));
      expect(await calls(), ['--version', '--version --machine']);
    });

    test('stops and preserves a failed bootstrap exit code', () async {
      final result = await run(bootstrapExit: 23);
      expect(result.exitCode, 23);
      expect(result.stderr, contains('Fixture bootstrap failed.'));
      expect(await calls(), ['--version']);
    });

    test('still rejects a malformed machine report after bootstrap', () async {
      final result = await run(machineReport: '{not json');
      expect(result.exitCode, 1);
      expect(result.stderr, contains('Invalid Flutter SDK report'));
      expect(await calls(), ['--version', '--version --machine']);
    });

    test('still rejects a different revision after bootstrap', () async {
      final result = await run(
        machineReport: machineOutput(frameworkRevision: actualRevision),
      );
      expect(result.exitCode, 1);
      expect(result.stderr, contains('Flutter toolchain mismatch'));
      expect(result.stderr, contains(actualRevision));
      expect(await calls(), ['--version', '--version --machine']);
    });
  });
}

String _dartExecutable() {
  // Flutter tests use flutter_tester; locate that installation's bundled Dart.
  var directory = File(Platform.resolvedExecutable).parent;
  while (true) {
    final executable = File(
      '${directory.path}/bin/cache/dart-sdk/bin/${Platform.isWindows ? 'dart.exe' : 'dart'}',
    );
    if (executable.existsSync()) {
      return executable.path;
    }
    if (directory.parent.path == directory.path) {
      throw StateError('Cannot locate the test runner Flutter Dart SDK.');
    }
    directory = directory.parent;
  }
}
