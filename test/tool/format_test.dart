import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final formatter = File('tool/format.dart').absolute.path;
  final dart = _dartExecutable();
  late Directory repository;

  Future<ProcessResult> git(List<String> arguments) async {
    final result = await Process.run(
      'git',
      arguments,
      workingDirectory: repository.path,
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    return result;
  }

  Future<File> source(String path, String contents) async {
    final nativePath = path.split('/').join(Platform.pathSeparator);
    final file = File('${repository.path}${Platform.pathSeparator}$nativePath');
    await file.parent.create(recursive: true);
    return file.writeAsString(contents);
  }

  Future<ProcessResult> run({bool check = true, String? directory}) {
    return Process.run(dart, [
      formatter,
      if (check) '--check',
    ], workingDirectory: directory ?? repository.path);
  }

  setUp(() async {
    repository = await Directory.systemTemp.createTemp('lineup format ');
    await git(['init', '--quiet']);
  });

  tearDown(() async {
    await repository.delete(recursive: true);
  });

  test(
    'checks tracked and new source without scanning ignored output',
    () async {
      for (final directory in ['lib', 'test', 'tool', 'test_driver']) {
        await source('$directory/clean.dart', 'void main() {}\n');
      }
      await git(['add', '.']);
      await source('.gitignore', 'build/\n');
      await source('build/historical.dart', 'this is not Dart');
      final newSource = await source(
        'lib/new file.dart',
        'void main(){print(1);}\n',
      );

      expect((await run()).exitCode, 1);
      expect(await newSource.readAsString(), 'void main(){print(1);}\n');
      expect((await run(check: false)).exitCode, 0);
      expect(await newSource.readAsString(), contains('  print(1);'));
      expect((await run()).exitCode, 0);
      expect(
        await File('${repository.path}/build/historical.dart').readAsString(),
        'this is not Dart',
      );
    },
  );

  test('tracked files stay covered even when an ignore rule matches', () async {
    final file = await source('lib/tracked.dart', 'void main() {}\n');
    await git(['add', 'lib/tracked.dart']);
    await source('.gitignore', 'lib/\n');
    await file.writeAsString('void main(){print(2);}\n');
    expect((await run()).exitCode, 1);
  });

  test(
    'handles deleted files and resolves inputs from a subdirectory',
    () async {
      final deleted = await source('lib/deleted.dart', 'void main() {}\n');
      await source('tool/clean.dart', 'void main() {}\n');
      await git(['add', '.']);
      await deleted.delete();
      expect((await run(directory: '${repository.path}/lib')).exitCode, 0);
    },
  );

  test('passes unusual paths as literal file arguments', () async {
    final names = [
      'lib/space and \$dollar.dart',
      '-option.dart',
      if (!Platform.isWindows) 'lib/quote" and newline\n.dart',
    ];
    for (final name in names) {
      await source(name, 'void main(){print(3);}\n');
    }
    expect((await run()).exitCode, 1);
    expect((await run(check: false)).exitCode, 0);
    expect((await run()).exitCode, 0);
  });

  for (final literalPath in [
    'lib/a%20b.dart',
    if (!Platform.isWindows) r'lib/a\b.dart',
  ]) {
    test('checks and formats the literal Git path $literalPath', () async {
      await source('lib/clean.dart', 'void main() {}\n');
      await git(['add', 'lib/clean.dart']);
      final file = await source(literalPath, 'void main(){print(5);}\n');
      final listed = await git(['ls-files', '--others', '-z']);
      expect((listed.stdout as String).split('\u0000'), contains(literalPath));

      expect((await run()).exitCode, 1);
      expect(await file.readAsString(), 'void main(){print(5);}\n');
      expect((await run(check: false)).exitCode, 0);
      expect(await file.readAsString(), contains('  print(5);'));
      expect((await run()).exitCode, 0);
    });
  }

  test('propagates the Dart formatter parse failure', () async {
    await source('lib/broken.dart', 'void main( {\n');
    final direct = await Process.run(dart, [
      'format',
      '--output=none',
      '--set-exit-if-changed',
      './lib/broken.dart',
    ], workingDirectory: repository.path);
    expect(direct.exitCode, isNot(0));
    expect((await run()).exitCode, direct.exitCode);
  });

  test(
    'formats later inputs while retaining an earlier parse failure',
    () async {
      await source('a_broken.dart', 'void main( {\n');
      final files = <File>[];
      final suffix = ''.padLeft(80, 'x');
      for (var index = 0; index < 110; index++) {
        final name = 'z_${index.toString().padLeft(3, '0')}_$suffix.dart';
        files.add(await source(name, 'void main(){print(4);}\n'));
      }
      final direct = await Process.run(dart, [
        'format',
        './a_broken.dart',
      ], workingDirectory: repository.path);
      expect(direct.exitCode, isNot(0));
      expect((await run(check: false)).exitCode, direct.exitCode);
      for (final file in files) {
        expect(await file.readAsString(), contains('  print(4);'));
      }
    },
  );

  test('fails when no source inputs can be established', () async {
    expect((await run()).exitCode, isNot(0));
    final file = await source('deleted.dart', 'void main() {}\n');
    await git(['add', 'deleted.dart']);
    await file.delete();
    expect((await run()).exitCode, isNot(0));
  });

  test('propagates Git failure outside a repository', () async {
    await Directory('${repository.path}/.git').delete(recursive: true);
    final direct = await Process.run('git', [
      'rev-parse',
      '--show-toplevel',
    ], workingDirectory: repository.path);
    expect(direct.exitCode, isNot(0));
    expect((await run()).exitCode, direct.exitCode);
  });
}

String _dartExecutable() {
  // Flutter tests run inside flutter_tester; use that Flutter installation's SDK.
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
