import 'dart:convert';
import 'dart:io';

const _versionPattern = r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$';
final _revisionPattern = RegExp(r'^[0-9a-f]{40}$', caseSensitive: false);

/// The Flutter SDK identity recorded by the repository.
class FlutterPin {
  FlutterPin({required this.version, required this.frameworkRevision});

  factory FlutterPin.fromJson(Object? value) {
    final map = _asJsonMap(value, 'tool/flutter_version.json');
    return FlutterPin(
      version: _requiredString(
        map,
        'version',
        'tool/flutter_version.json',
        pattern: RegExp(_versionPattern),
      ),
      frameworkRevision: _requiredString(
        map,
        'frameworkRevision',
        'tool/flutter_version.json',
        pattern: _revisionPattern,
      ),
    );
  }

  final String version;
  final String frameworkRevision;
}

/// The identity reported by `flutter --version --machine`.
class FlutterToolchain {
  FlutterToolchain({
    required this.version,
    required this.frameworkRevision,
    this.flutterRoot,
  });

  factory FlutterToolchain.fromMachineJson(String output) {
    final Object? decoded;
    try {
      decoded = jsonDecode(output);
    } on FormatException catch (error) {
      throw FormatException(
        'flutter --version --machine did not return JSON: ${error.message}',
      );
    }
    final map = _asJsonMap(decoded, 'flutter --version --machine output');
    return FlutterToolchain(
      version: _requiredString(
        map,
        'frameworkVersion',
        'flutter --version --machine output',
        pattern: RegExp(_versionPattern),
      ),
      frameworkRevision: _requiredString(
        map,
        'frameworkRevision',
        'flutter --version --machine output',
        pattern: _revisionPattern,
      ),
      flutterRoot: _optionalString(map['flutterRoot']),
    );
  }

  final String version;
  final String frameworkRevision;
  final String? flutterRoot;
}

/// The result of comparing a reported SDK identity with the repository pin.
class ToolchainComparison {
  ToolchainComparison({
    required this.expected,
    required this.actual,
    required this.versionMatches,
    required this.frameworkRevisionMatches,
  });

  final FlutterPin expected;
  final FlutterToolchain actual;
  final bool versionMatches;
  final bool frameworkRevisionMatches;

  bool get matches => versionMatches && frameworkRevisionMatches;

  String mismatchMessage({required String expectedSdkLocation}) {
    final differences = <String>[
      if (!versionMatches)
        'version ${actual.version} (expected ${expected.version})',
      if (!frameworkRevisionMatches)
        'framework revision ${actual.frameworkRevision} '
            '(expected ${expected.frameworkRevision})',
    ];
    return 'Flutter toolchain mismatch: expected Flutter ${expected.version} '
        '(framework ${expected.frameworkRevision}) at '
        '$expectedSdkLocation, but found ${differences.join(' and ')} at '
        '${actual.flutterRoot ?? 'the Flutter SDK selected on PATH'}. '
        'Put the expected SDK first on PATH.';
  }
}

/// Compares two already-parsed SDK identities without consulting the host.
ToolchainComparison compareToolchain({
  required FlutterPin expected,
  required FlutterToolchain actual,
}) {
  return ToolchainComparison(
    expected: expected,
    actual: actual,
    versionMatches: expected.version == actual.version,
    frameworkRevisionMatches:
        expected.frameworkRevision == actual.frameworkRevision,
  );
}

/// Runs the repository's checked Flutter SDK guard.
Future<int> runToolchainCheck({String? repositoryRoot}) async {
  final root = repositoryRoot ?? await _repositoryRoot();
  if (root == null) {
    stderr.writeln(
      'Unable to locate the repository root. Run this command inside a Git '
      'checkout.',
    );
    return 1;
  }

  final pinPath = _join(root, 'tool', 'flutter_version.json');
  final FlutterPin expected;
  try {
    final contents = await File(pinPath).readAsString();
    final Object? decoded = jsonDecode(contents);
    expected = FlutterPin.fromJson(decoded);
  } on FileSystemException catch (error) {
    stderr.writeln(
      'Unable to read required Flutter SDK pin at $pinPath: ${error.message}. '
      'Restore tool/flutter_version.json; the toolchain check cannot be '
      'disabled for the real repository.',
    );
    return 1;
  } on FormatException catch (error) {
    stderr.writeln(
      'Invalid Flutter SDK pin at $pinPath: ${error.message}. '
      'Restore tool/flutter_version.json with version and frameworkRevision.',
    );
    return 1;
  }

  // Windows Flutter bootstrap can write package progress to stdout. Finish
  // that initialization before requesting a strictly JSON machine report.
  late ProcessResult result;
  for (final arguments in const [
    ['--version'],
    ['--version', '--machine'],
  ]) {
    result = await Process.run(
      'flutter',
      arguments,
      workingDirectory: root,
      runInShell: Platform.isWindows,
    );
    if (result.exitCode != 0) {
      stderr.writeln(
        'Unable to query Flutter SDK with `flutter ${arguments.join(' ')}`.',
      );
      stderr.write(result.stdout);
      stderr.write(result.stderr);
      return result.exitCode;
    }
  }

  final FlutterToolchain actual;
  try {
    actual = FlutterToolchain.fromMachineJson(result.stdout as String);
  } on FormatException catch (error) {
    stderr.writeln('Invalid Flutter SDK report: ${error.message}');
    return 1;
  }

  final comparison = compareToolchain(expected: expected, actual: actual);
  if (!comparison.matches) {
    stderr.writeln(
      comparison.mismatchMessage(
        expectedSdkLocation: _expectedSdkLocation(actual, expected.version),
      ),
    );
    return 1;
  }

  stdout.writeln(
    'Flutter ${actual.version} (${actual.frameworkRevision}) matches '
    'tool/flutter_version.json.',
  );
  return 0;
}

Future<void> main() async {
  exitCode = await runToolchainCheck();
}

Map<String, Object?> _asJsonMap(Object? value, String description) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$description must be a JSON object.');
  }
  return value.map<String, Object?>(MapEntry<String, Object?>.new);
}

String _requiredString(
  Map<String, Object?> map,
  String key,
  String description, {
  required RegExp pattern,
}) {
  final value = map[key];
  if (value is! String || !pattern.hasMatch(value)) {
    throw FormatException('$description must contain a valid $key.');
  }
  return value;
}

String? _optionalString(Object? value) {
  return value is String && value.isNotEmpty ? value : null;
}

Future<String?> _repositoryRoot() async {
  final result = await Process.run('git', ['rev-parse', '--show-toplevel']);
  if (result.exitCode != 0) {
    return null;
  }
  final root = (result.stdout as String).trim();
  return root.isEmpty ? null : root;
}

String _expectedSdkLocation(FlutterToolchain actual, String expectedVersion) {
  final actualRoot = actual.flutterRoot;
  if (actualRoot == null) {
    return 'the Flutter $expectedVersion SDK selected on PATH';
  }
  final versionMatch = RegExp(r'(?<!\d)\d+\.\d+\.\d+(?!\d)')
      .firstMatch(actualRoot);
  if (versionMatch == null) {
    return 'the Flutter $expectedVersion SDK (next to $actualRoot)';
  }
  return actualRoot.replaceRange(
    versionMatch.start,
    versionMatch.end,
    expectedVersion,
  );
}

String _join(String first, String second, [String? third]) {
  final parts = <String>[first, second, ?third];
  return parts.join(Platform.pathSeparator);
}
