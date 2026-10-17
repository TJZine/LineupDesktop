import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app_version.dart';

void main() {
  test(
    'the default application version matches pubspec without build metadata',
    () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final version = RegExp(
        r'^version:\s*([^\s+]+)(?:\+[^\s]+)?\s*$',
        multiLine: true,
      ).firstMatch(pubspec)?.group(1);

      expect(version, isNotNull);
      expect(lineupVersion, version);
    },
  );
}
