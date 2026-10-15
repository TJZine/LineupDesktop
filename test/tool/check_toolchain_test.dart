import 'dart:convert';

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
}
