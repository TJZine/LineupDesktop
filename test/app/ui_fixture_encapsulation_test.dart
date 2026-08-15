import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production source has no visual fixture entry point', () {
    final production = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
    expect(production, isNotEmpty);

    for (final file in production) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('ui_fixture.dart')), reason: file.path);
      expect(source, isNot(contains('UiFixture')), reason: file.path);
    }
  });
}
