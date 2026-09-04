import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/diagnostics/diagnostics.dart';

void main() {
  test('redacts tokens, URLs, credentials, and paths before storage', () {
    final diagnostics = Diagnostics();
    diagnostics.enabled = true;
    diagnostics.add(
      'plex',
      'Bearer abc https://plex.test/file?X-Plex-Token=secret /Users/person/movie.mkv',
      {'container': 'mpeg-ts', 'authorization': 'secret'},
    );
    final entry = diagnostics.entries.single;
    expect(entry.message, isNot(contains('abc')));
    expect(entry.message, isNot(contains('secret')));
    expect(entry.message, isNot(contains('/Users/person')));
    expect(entry.context, {'container': 'mpeg-ts'});
  });

  test('stores only bounded structured context', () {
    final diagnostics = Diagnostics()..enabled = true;
    diagnostics.add('playback', 'Playback facts', {
      'code': 'offline',
      'failureCode': 'http_error',
      'operation': 'seek',
      'httpStatus': 401,
      'count': 12,
      'container': 'mpeg-ts',
      'videoCodec': 'h264',
      'audioCodec': 'eac3',
      'dynamicRange': 'hdr10',
      'videoOutput': 'gpu-next',
      'hardwareDecoder': 'd3d11va',
      'unknown': 'opaque-secret-sentinel',
    });

    expect(diagnostics.entries.single.context, {
      'code': 'offline',
      'failureCode': 'http_error',
      'operation': 'seek',
      'httpStatus': 401,
      'count': 12,
      'container': 'mpeg-ts',
      'videoCodec': 'h264',
      'audioCodec': 'eac3',
      'dynamicRange': 'hdr10',
      'videoOutput': 'gpu-next',
      'hardwareDecoder': 'd3d11va',
    });
    expect(
      () => diagnostics.entries.single.context['code'] = 'mutated',
      throwsUnsupportedError,
    );
  });

  test(
    'replaces invalid or oversized strings and drops invalid primitives',
    () {
      final diagnostics = Diagnostics()..enabled = true;
      diagnostics.add('playback', 'Playback facts', {
        'code': 'opaque secret sentinel',
        'failureCode': 'x' * 65,
        'container': true,
        'httpStatus': 99,
        'count': -1,
      });

      expect(diagnostics.entries.single.context, {
        'code': 'unexpected',
        'failureCode': 'unexpected',
      });
    },
  );

  test('redacts authorization schemes and JSON auth tokens', () {
    for (final value in {
      'Authorization: Bearer bearer-secret': 'Authorization: Bearer [REDACTED]',
      'Authorization: Basic basic-secret': 'Authorization: Basic [REDACTED]',
      'Authorization: opaque-secret': 'Authorization: [REDACTED]',
      'Bearer bearer-secret': 'Bearer [REDACTED]',
      'Basic basic-secret': 'Basic [REDACTED]',
      '{"authToken":"json-secret"}': '{"authToken":[REDACTED]}',
      'X-Plex-Token=plex-secret': 'X-Plex-Token=[REDACTED]',
    }.entries) {
      final output = Diagnostics.redact(value.key);
      expect(output, value.value);
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

  test('retention remains bounded', () {
    final diagnostics = Diagnostics()..enabled = true;
    for (var index = 0; index < 251; index++) {
      diagnostics.add('plex', 'entry $index');
    }

    expect(diagnostics.entries, hasLength(250));
    expect(diagnostics.entries.first.message, 'entry 1');
  });
}
