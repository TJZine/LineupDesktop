import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/diagnostics/diagnostics.dart';

void main() {
  test('redacts tokens, URLs, credentials, and paths before storage', () {
    final diagnostics = Diagnostics();
    diagnostics.enabled = true;
    diagnostics.add(
      'plex',
      'Bearer abc https://plex.test/file?X-Plex-Token=secret /Users/person/movie.mkv',
      {'server': 'ok', 'authorization': 'secret'},
    );
    final entry = diagnostics.entries.single;
    expect(entry.message, isNot(contains('abc')));
    expect(entry.message, isNot(contains('secret')));
    expect(entry.message, isNot(contains('/Users/person')));
    expect(entry.context, {'server': 'ok'});
  });

  test('redacts authorization schemes and JSON auth tokens', () {
    for (final input in [
      'Authorization: Bearer bearer-secret',
      'Authorization: Basic basic-secret',
      '{"authToken":"json-secret"}',
    ]) {
      final output = Diagnostics.redact(input);
      expect(output, contains('[REDACTED]'));
      expect(output, isNot(contains('secret')));
    }
  });

  test('disabled diagnostics retain nothing and clear existing entries', () {
    final diagnostics = Diagnostics();
    diagnostics.add('plex', 'not retained');
    expect(diagnostics.entries, isEmpty);

    diagnostics.enabled = true;
    diagnostics.add('plex', 'retained');
    expect(diagnostics.entries, hasLength(1));

    diagnostics.enabled = false;
    expect(diagnostics.entries, isEmpty);
  });
}
