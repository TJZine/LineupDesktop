import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/diagnostics/diagnostics.dart';
import 'package:lineup_desktop/playback/native_player.dart';

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
    var notifications = 0;
    diagnostics.addListener(() => notifications++);
    diagnostics.add('plex', 'not retained');
    expect(diagnostics.entries, isEmpty);
    expect(notifications, 0);

    diagnostics.enabled = true;
    diagnostics.add('plex', 'retained');
    expect(diagnostics.entries, hasLength(1));
    expect(notifications, 2);

    diagnostics.enabled = false;
    expect(diagnostics.entries, isEmpty);
    expect(notifications, 3);
    diagnostics.enabled = false;
    expect(notifications, 3);
    diagnostics.dispose();

    diagnostics.enabled = true;
    expect(diagnostics.enabled, isFalse);
    expect(notifications, 3);

    diagnostics.add('plex', 'ignored after disposal');
    expect(diagnostics.entries, isEmpty);
    expect(notifications, 3);
  });

  test('retention remains bounded', () {
    final diagnostics = Diagnostics()..enabled = true;
    for (var index = 0; index < 251; index++) {
      diagnostics.add('plex', 'entry $index');
    }

    expect(diagnostics.entries, hasLength(250));
    expect(diagnostics.entries.first.message, 'entry 1');
  });

  test('support report exports only typed facts and known producer events', () {
    final diagnostics = Diagnostics()..enabled = true;
    diagnostics.add('playback', 'Playback request failed', {
      'operation': 'seek',
      'code': 'http_error',
    });
    diagnostics.add('safe-looking-area', 'safe-looking-secret-sentinel', {
      'videoCodec': 'safe-looking-secret-sentinel',
    });
    final snapshot = diagnostics.snapshot(
      reportTime: DateTime.utc(2026, 9, 8, 12),
      timeZone: 'Pacific Standard Time',
      appVersion: '1.2.3',
      appBuild: '42',
      platform: 'windows',
      plexServerSelected: true,
      plexConnectionVerified: false,
      playback: const PlaybackDiagnosticSnapshot(
        state: PlayerState.playing,
        receivedTelemetry: PlayerTelemetry(
          width: 1920,
          height: 1080,
          videoCodec: 'h264',
          videoOutput: 'safe-looking-secret-sentinel',
        ),
      ),
    );

    final report = diagnostics.buildSupportReport(snapshot);
    expect(report, contains('Time zone: Pacific Standard Time'));
    expect(report, contains('Playback method: Unknown'));
    expect(report, contains('Plex server selected: Yes'));
    expect(report, contains('Plex connection verified: No'));
    expect(report, contains('Received video: 1920x1080'));
    expect(report, contains('Received video codec: h264'));
    expect(report, contains('playback: Playback request failed'));
    expect(report, contains('operation=seek'));
    expect(report, contains('code=http_error'));
    expect(report, isNot(contains('safe-looking-secret-sentinel')));
    expect(
      () => snapshot.events.add(
        DiagnosticEntry(DateTime.now(), 'x', 'y', const {}),
      ),
      throwsUnsupportedError,
    );
  });

  test('support report rejects unsafe metadata independently', () {
    final diagnostics = Diagnostics();
    final snapshot = diagnostics.snapshot(
      reportTime: DateTime.utc(2026, 9, 8, 12),
      timeZone: 'Pacific\nsecret',
      appVersion: '1.2.3 private',
      appBuild: '42',
      platform: 'windows',
      plexServerSelected: false,
      plexConnectionVerified: false,
      playback: const PlaybackDiagnosticSnapshot(state: PlayerState.idle),
    );

    final report = diagnostics.buildSupportReport(snapshot);
    expect(report, contains('Time zone: Unavailable'));
    expect(report, contains('App: Unavailable (42)'));
    expect(report, isNot(contains('secret')));
    expect(report, isNot(contains('private')));
  });
}
