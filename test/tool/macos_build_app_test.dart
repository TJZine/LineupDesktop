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
      '--local-engine=host_debug',
      '--local-engine-host=host_debug',
      '--local-engine-src-path=/other',
    ]) {
      expect(
        () => arguments(options: ['build', option]),
        throwsFormatException,
      );
    }
    expect(() => arguments(options: []), throwsFormatException);
    expect(() => arguments(options: ['windows']), throwsFormatException);
  });

  test('verified engine selection is explicit, complete and mode specific', () {
    final options = MacosEngineOptions([
      'build',
      '--debug',
      '--accessibility-engine-root=/engine root',
      '--accessibility-engine=lineup_ax_debug_arm64',
    ]);
    expect(options.root, '/engine root');
    expect(options.name, 'lineup_ax_debug_arm64');
    expect(options.mode, 'debug');
    expect(options.flutterArguments, ['build', '--debug']);
    for (final arguments in [
      ['build', '--accessibility-engine=output'],
      ['build', '--accessibility-engine-root=root'],
      [
        'build',
        '--accessibility-engine-root=',
        '--accessibility-engine=output',
      ],
      ['run', '--debug'],
      ['build'],
      ['build', '--debug', '--release'],
      ['build', '--debug', '--config-only'],
      ['build', '--debug', '--flavor=other'],
      ['build', '--debug', '--target=lib/other.dart'],
      ['build', '--debug', '-tlib/other.dart'],
      ['build', '--debug', 'lib/other.dart'],
      ['build', '--debug', '--help'],
      ['build', '--debug', '-h'],
      ['build', '--debug', '--version'],
    ]) {
      expect(
        () => MacosEngineOptions([
          ...arguments,
          if (!arguments.any(
            (v) => v.startsWith('--accessibility-engine'),
          )) ...[
            '--accessibility-engine-root=root',
            '--accessibility-engine=output',
          ],
        ]),
        throwsFormatException,
      );
    }
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
      await File('${repository.path}/tool/macos/native_assets.py')
          .writeAsString('''import json,os,sys
if os.environ.get('LINEUP_NATIVE_ASSET_FAIL') == sys.argv[1]:
    sys.stderr.write('controlled native asset rejection')
    sys.exit(1)
print(json.dumps({'verifiedNativeAsset': sys.argv[1]}))
''');
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

    Future<ProcessResult> run({
      int flutterExit = 0,
      List<String> options = const ['build', '--release'],
      String? nativeFailure,
    }) {
      final environment = Map<String, String>.from(Platform.environment);
      final pathKey = environment.keys.firstWhere(
        (key) => key.toLowerCase() == 'path',
      );
      if (nativeFailure != null) {
        environment['LINEUP_NATIVE_ASSET_FAIL'] = nativeFailure;
      }
      environment[pathKey] =
          '${repository.path}${Platform.isWindows ? ';' : ':'}'
          '${environment[pathKey]}';
      environment['LINEUP_FIXTURE_EXIT'] = '$flutterExit';
      return Process.run(
        dart,
        ['${repository.path}/tool/macos/build_app.dart', ...options],
        // The script uses its owning repository, not the caller's directory.
        workingDirectory: Directory.systemTemp.path,
        environment: environment,
      );
    }

    Future<void> configureEngineFixture({bool reject = false}) async {
      final verifier = File(
        '${repository.path}/tool/flutter_engine/desktop_accessibility.py',
      );
      await verifier.parent.create(recursive: true);
      // This fixture observes wrapper-to-verifier wiring. Exact source and
      // artifact integrity are exercised by desktop_accessibility_test.py.
      await verifier.writeAsString('''
import json, pathlib, sys
root = pathlib.Path(__file__).resolve().parents[2]
arguments = sys.argv[1:]
if ${reject ? 'True' : 'False'}:
    print('Engine provenance is missing', file=sys.stderr)
    sys.exit(1)
path = root / 'engine-requests.json'
requests = json.loads(path.read_text()) if path.exists() else []
requests.append(arguments)
path.write_text(json.dumps(requests))
if arguments[0] == 'record-app-build':
    recipe = pathlib.Path(arguments[arguments.index('--recipe-file') + 1])
    (root / 'recipe-observed.json').write_text(recipe.read_text())
print(json.dumps({'kind': 'verified-local-desktop-accessibility', 'engineSource': str(root / 'engine/src'), 'flutterRoot': str(root / 'engine')}))
''');
      final launcher = File('${repository.path}/engine/bin/flutter');
      await launcher.parent.create(recursive: true);
      await launcher.writeAsString(
        '#!/bin/sh\nexec "$dart" "${repository.path}/flutter_fixture.dart" "\$@"\n',
      );
      await Process.run('chmod', ['+x', launcher.path]);
      await File('${repository.path}/.gitignore').writeAsString(
        'invocation.json\nengine-requests.json\nrecipe-observed.json\nbuild/\n',
      );
      await Process.run('git', ['-C', repository.path, 'add', '.']);
      final result = await Process.run('git', [
        '-C',
        repository.path,
        '-c',
        'user.name=Lineup fixture',
        '-c',
        'user.email=fixture@example.invalid',
        'commit',
        '--quiet',
        '-m',
        'engine fixture',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }

    test(
      'stock builds fail closed on native input or final-bundle rejection',
      () async {
        for (final action in ['inputs', 'verify']) {
          final result = await run(nativeFailure: action);
          expect(result.exitCode, 1);
          expect(result.stderr, contains('controlled native asset rejection'));
        }
      },
      skip: Platform.isWindows,
    );

    test('stock config-only follows the final flag and invalidates stale reports', () async {
      final report = File(
        '${repository.path}/build/macos/Build/Products/Release/Lineup Desktop.app.native-assets.json',
      );
      await report.parent.create(recursive: true);
      expect((await run()).exitCode, 0);
      final record =
          jsonDecode(await report.readAsString()) as Map<String, dynamic>;
      expect(record['nativeAssets'], {'verifiedNativeAsset': 'verify'});
      expect(record['runtimeAcceptance'], 'not observed');
      for (final flags in [
        ['--config-only', '--no-config-only'],
        ['--no-config-only'],
        ['--no-config-only', '--config-only', '--no-config-only'],
        ['--config-only', '--config-only', '--no-config-only'],
      ]) {
        await report.writeAsString('old report');
        final rejected = await run(
          nativeFailure: 'verify',
          options: ['build', '--release', ...flags],
        );
        expect(rejected.exitCode, 1, reason: '$flags');
        expect(await report.exists(), false, reason: '$flags');
      }
      for (final flags in [
        ['--config-only'],
        ['--config-only', '--config-only'],
        ['--no-config-only', '--config-only'],
        ['--config-only', '--no-config-only', '--config-only'],
      ]) {
        await report.writeAsString('previous actual build');
        final informational = await run(
          nativeFailure: 'inputs',
          options: ['build', '--release', ...flags],
        );
        expect(informational.exitCode, 0, reason: '$flags');
        expect(
          await report.readAsString(),
          'previous actual build',
          reason: '$flags',
        );
      }
    }, skip: Platform.isWindows);

    test(
      'repaired native asset rejection prevents successful app receipt',
      () async {
        await configureEngineFixture();
        final result = await run(
          nativeFailure: 'verify',
          options: [
            'build',
            '--debug',
            '--accessibility-engine-root=${repository.path}/engine',
            '--accessibility-engine=lineup_ax_debug_arm64',
          ],
        );
        expect(result.exitCode, 1);
        final requests = jsonDecode(
          File('${repository.path}/engine-requests.json').readAsStringSync(),
        ) as List<dynamic>;
        expect(requests.map((request) => (request as List).first), ['verify']);
        expect(
          File('${repository.path}/recipe-observed.json').existsSync(),
          false,
        );
      },
      skip: Platform.isWindows,
    );

    test(
      'actual invocation uses repository metadata and forwards exit status',
      () async {
        final result = await run(flutterExit: 23);
        expect(result.exitCode, 23, reason: '${result.stderr}');
        expect(result.stdout, contains('Engine: stock Flutter SDK'));
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

    test(
      'actual entry point rejects identity and raw engine overrides',
      () async {
        for (final option in [
          '--dart-define=LINEUP_BUILD=other',
          '--dart-define-from-file=other.json',
          '--build-name=other',
          '--local-engine=unverified',
          '--local-engine-src-path=/unverified',
        ]) {
          final result = await run(options: ['build', '--release', option]);
          expect(result.exitCode, 1, reason: '$option: ${result.stderr}');
          expect(
            File('${repository.path}/invocation.json').existsSync(),
            isFalse,
          );
        }
      },
    );

    test(
      'verified selection gates Flutter and verifies the bundle afterward',
      () async {
        await configureEngineFixture();
        final result = await run(
          options: [
            'build',
            '--debug',
            '--dart-define=EXPERIMENT=fixture',
            '--accessibility-engine-root=${repository.path}/engine',
            '--accessibility-engine=lineup_ax_debug_arm64',
          ],
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(result.stdout, contains('Engine: verified local'));
        expect(
          result.stdout,
          contains('Runtime loaded engine remains unobserved'),
        );
        final invocation = jsonDecode(
          File('${repository.path}/invocation.json').readAsStringSync(),
        ) as List<dynamic>;
        final canonicalRoot = repository.resolveSymbolicLinksSync();
        expect(invocation.take(5), [
          '--local-engine-src-path=$canonicalRoot/engine/src',
          '--local-engine=lineup_ax_debug_arm64',
          '--local-engine-host=lineup_ax_debug_arm64',
          'build',
          'macos',
        ]);
        expect(invocation, contains('--dart-define=LINEUP_VERSION=9.8.7'));
        expect(invocation.last, startsWith('--dart-define=LINEUP_BUILD=65@'));
        final requests = jsonDecode(
          File('${repository.path}/engine-requests.json').readAsStringSync(),
        ) as List<dynamic>;
        expect(requests.map((request) => (request as List).first), [
          'verify',
          'record-app-build',
          'bundle',
        ]);
        expect(requests.last, contains('--app'));
        final recipe = jsonDecode(
          File('${repository.path}/recipe-observed.json').readAsStringSync(),
        ) as Map<String, dynamic>;
        expect(recipe['entrypoint'], 'lib/main.dart');
        expect(recipe['flutterArguments'], invocation);
        expect(
          recipe['flutterArguments'],
          contains('--dart-define=EXPERIMENT=fixture'),
        );
        expect(recipe['flutterExitCode'], 0);
        expect(recipe['mode'], 'debug');
        expect(recipe['nativeAssets'], {'verifiedNativeAsset': 'verify'});
        expect(
          recipe['appCommit'],
          (invocation.last as String).split('@').last,
        );
      },
      skip: Platform.isWindows,
    );

    test('missing engine provenance stops before Flutter', () async {
      await configureEngineFixture(reject: true);
      final result = await run(
        options: [
          'build',
          '--debug',
          '--accessibility-engine-root=${repository.path}/engine',
          '--accessibility-engine=lineup_ax_debug_arm64',
        ],
      );
      expect(result.exitCode, 1);
      expect(result.stderr, contains('Engine provenance is missing'));
      expect(File('${repository.path}/invocation.json').existsSync(), isFalse);
    }, skip: Platform.isWindows);

    test(
      'verified entry point rejects alternate Dart targets before Flutter',
      () async {
        await configureEngineFixture();
        for (final target in [
          '--target=lib/other.dart',
          '-tlib/other.dart',
          'lib/other.dart',
        ]) {
          final result = await run(
            options: [
              'build',
              '--debug',
              target,
              '--accessibility-engine-root=${repository.path}/engine',
              '--accessibility-engine=lineup_ax_debug_arm64',
            ],
          );
          expect(result.exitCode, 1);
          expect(result.stderr, contains('canonical lib/main.dart'));
          expect(
            File('${repository.path}/invocation.json').existsSync(),
            isFalse,
          );
          expect(
            File('${repository.path}/engine-requests.json').existsSync(),
            isFalse,
          );
        }
      },
      skip: Platform.isWindows,
    );

    test('failed verified build removes old receipts and creates none', () async {
      await configureEngineFixture();
      final appPath =
          '${repository.path}/build/macos/Build/Products/Debug/Lineup Desktop.app';
      for (final suffix in ['.build-receipt.json', '.engine-provenance.json']) {
        final file = File('$appPath$suffix');
        await file.parent.create(recursive: true);
        await file.writeAsString('stale');
      }
      final result = await run(
        flutterExit: 23,
        options: [
          'build',
          '--debug',
          '--accessibility-engine-root=${repository.path}/engine',
          '--accessibility-engine=lineup_ax_debug_arm64',
        ],
      );
      expect(result.exitCode, 23);
      expect(File('$appPath.build-receipt.json').existsSync(), isFalse);
      expect(File('$appPath.engine-provenance.json').existsSync(), isFalse);
      final requests = jsonDecode(
        File('${repository.path}/engine-requests.json').readAsStringSync(),
      ) as List;
      expect(requests.map((request) => (request as List).first), ['verify']);
      expect(
        File('${repository.path}/recipe-observed.json').existsSync(),
        isFalse,
      );
    }, skip: Platform.isWindows);

    test('informational flags cannot attribute an old app to a new build', () async {
      await configureEngineFixture();
      final oldApp = File(
        '${repository.path}/build/macos/Build/Products/Release/'
        'Lineup Desktop.app/Contents/Frameworks/App.framework/App',
      );
      await oldApp.parent.create(recursive: true);
      await oldApp.writeAsString('old Dart application bytes');
      for (final option in [
        '--help',
        '-h',
        '--help=true',
        '--version',
        '--version=true',
        '-v',
        '--verbose',
        '--config-only',
        '--enable-analytics',
        '--disable-analytics',
      ]) {
        final result = await run(
          options: [
            'build',
            '--release',
            option,
            '--accessibility-engine-root=${repository.path}/engine',
            '--accessibility-engine=lineup_ax_release_arm64',
          ],
        );
        expect(result.exitCode, 1, reason: option);
        expect(result.stderr, contains('only the selected mode'));
        expect(await oldApp.readAsString(), 'old Dart application bytes');
        expect(
          File('${repository.path}/invocation.json').existsSync(),
          isFalse,
        );
        expect(
          File('${repository.path}/engine-requests.json').existsSync(),
          isFalse,
        );
        expect(
          File('${repository.path}/recipe-observed.json').existsSync(),
          isFalse,
        );
        final appPath =
            '${repository.path}/build/macos/Build/Products/Release/Lineup Desktop.app';
        expect(File('$appPath.build-receipt.json').existsSync(), isFalse);
        expect(File('$appPath.engine-provenance.json').existsSync(), isFalse);
      }
      // The stock wrapper retains its existing forwarding contract.
      final stock = await run(options: ['build', '--release', '--help']);
      expect(stock.exitCode, 0);
      expect(
        jsonDecode(
          File('${repository.path}/invocation.json').readAsStringSync(),
        ),
        contains('--help'),
      );
    }, skip: Platform.isWindows);
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
