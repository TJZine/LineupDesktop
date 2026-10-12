import 'dart:convert';
import 'dart:io';

/// Formats Git-owned Dart inputs, including new source but excluding ignored output.
Future<void> main(List<String> arguments) async {
  if (arguments.length > 1 ||
      (arguments.isNotEmpty && arguments.single != '--check')) {
    stderr.writeln('Usage: dart tool/format.dart [--check]');
    exitCode = 64;
    return;
  }

  try {
    exitCode = await _format(check: arguments.isNotEmpty);
  } on ProcessException catch (error) {
    stderr.writeln('Unable to execute ${error.executable}: ${error.message}');
    exitCode = 1;
  } on FileSystemException catch (error) {
    stderr.writeln('Unable to inspect formatter inputs: ${error.message}');
    exitCode = 1;
  } on FormatException catch (error) {
    stderr.writeln('Unable to decode Git paths: ${error.message}');
    exitCode = 1;
  }
}

Future<int> _format({required bool check}) async {
  final rootResult = await Process.run('git', ['rev-parse', '--show-toplevel']);
  if (rootResult.exitCode != 0) {
    stderr.write(rootResult.stderr);
    return rootResult.exitCode;
  }
  final root = (rootResult.stdout as String).replaceFirst(
    RegExp(r'\r?\n$'),
    '',
  );
  final inputsResult = await Process.run(
    'git',
    [
      'ls-files',
      '--cached',
      '--others',
      '--exclude-standard',
      '-z',
      '--',
      '*.dart',
    ],
    workingDirectory: root,
    stdoutEncoding: null,
  );
  if (inputsResult.exitCode != 0) {
    stderr.write(inputsResult.stderr);
    return inputsResult.exitCode;
  }

  final paths =
      utf8
          .decode(inputsResult.stdout as List<int>)
          .split('\u0000')
          .where((path) => path.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  final files = <String>[];
  for (final path in paths) {
    // Tracked files may have been removed from the working tree.
    final nativePath = path.split('/').join(Platform.pathSeparator);
    final file = File('$root${Platform.pathSeparator}$nativePath');
    if (await file.exists()) {
      // Prefixing prevents a filename beginning with '-' being treated as an option.
      files.add('./$path');
    }
  }
  if (files.isEmpty) {
    stderr.writeln('No existing Git-owned Dart inputs were found.');
    return 1;
  }

  final options = [
    'format',
    if (check) ...['--output=none', '--set-exit-if-changed'],
  ];
  var resultCode = 0;
  var batch = <String>[];
  var argumentLength = Platform.resolvedExecutable.length;

  Future<void> runBatch() async {
    final result = await Process.run(Platform.resolvedExecutable, [
      ...options,
      ...batch,
    ], workingDirectory: root);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (resultCode == 0 && result.exitCode != 0) {
      resultCode = result.exitCode;
    }
    batch = <String>[];
    argumentLength = Platform.resolvedExecutable.length;
  }

  // Keep invocations below Windows' command-line limit, allowing for quoting.
  for (final file in files) {
    if (batch.isNotEmpty && argumentLength + file.length + 3 > 8000) {
      await runBatch();
    }
    batch.add(file);
    argumentLength += file.length + 3;
  }
  await runBatch();
  return resultCode;
}
