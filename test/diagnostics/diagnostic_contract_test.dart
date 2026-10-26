import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/diagnostics_view.dart';
import 'package:lineup_desktop/diagnostics/diagnostics.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';

import '../support/ui_fixture.dart';

// These are literal public report expectations, established before the typed
// event/policy migration. Keep the text unchanged through that migration.
const _expectedReport = '''Lineup Desktop support report
Report time: 2026-10-15T12:00:00.000Z
Time zone: America/New_York
App: 1.2.3 (42)
Platform: windows
Diagnostic recording: On
Playback state: playing
Playback method: Direct Stream
Windows display: unknown · none
HDR matching: inactive · idle · revision=0 · wrote=false · owned=false
Renderer output: gamma2.2 · bt.709 · rgb10a2
Display state is reported by Windows; it does not verify the TV's picture.
Plex server selected: Yes
Plex connection verified: No
Received video: 1920x1080
Received video codec: hevc
Reported media transfer: pq
Reported pixel format: yuv420p10le
Reported color primaries: bt.2020
Reported color matrix: bt.2020-ncl
Reported signal peak: 10.0
Video output: gpu-next
Hardware decoder: d3d11va

Recent events:
2026-10-15T11:59:00.000Z application: Credential cleanup failed (code=http_error, failureCode=timeout, operation=seek, container=mpeg-ts, videoCodec=hevc, audioCodec=eac3, dynamicRange=hdr10, videoOutput=gpu-next, hardwareDecoder=d3d11va, scanPath=launch, libraryType=show, httpStatus=401, count=2, itemsMs=86400000, collectionsMs=0, showGenresMs=560, items=1000000, collections=300, members=4200, shows=80)
2026-10-15T11:59:00.000Z application: State save failed
2026-10-15T11:59:00.000Z application: Operation failed
2026-10-15T11:59:00.000Z plex-auth: PIN cancellation failed
2026-10-15T11:59:00.000Z plex-auth: Credential write failed
2026-10-15T11:59:00.000Z plex-auth: PIN poll failed
2026-10-15T11:59:00.000Z plex-library: Playlist discovery unavailable
2026-10-15T11:59:00.000Z plex-library: Some playlists could not be loaded
2026-10-15T11:59:00.000Z plex-library: Some collections could not be loaded
2026-10-15T11:59:00.000Z plex-library: Collection discovery unavailable
2026-10-15T11:59:00.000Z plex-library: Library scan timing
2026-10-15T11:59:00.000Z plex: Cast enrichment
2026-10-15T11:59:00.000Z plex: Cast portrait unavailable
2026-10-15T11:59:00.000Z guide: Guide current program wait timed out
2026-10-15T11:59:00.000Z guide: Guide schedule load timed out
2026-10-15T11:59:00.000Z playback: Native playback failed
2026-10-15T11:59:00.000Z playback: Playback request failed
2026-10-15T11:59:00.000Z playback: Plex playback selected
2026-10-15T11:59:00.000Z playback: Playback request failed
2026-10-15T11:59:00.000Z playback: Playback request failed
2026-10-15T11:59:00.000Z playback: Playback request failed
''';

const _eventPairs = <(String, String)>[
  ('application', 'Credential cleanup failed'),
  ('application', 'State save failed'),
  ('application', 'Operation failed'),
  ('plex-auth', 'PIN cancellation failed'),
  ('plex-auth', 'Credential write failed'),
  ('plex-auth', 'PIN poll failed'),
  ('plex-library', 'Playlist discovery unavailable'),
  ('plex-library', 'Some playlists could not be loaded'),
  ('plex-library', 'Some collections could not be loaded'),
  ('plex-library', 'Collection discovery unavailable'),
  ('plex-library', 'Library scan timing'),
  ('plex', 'Cast enrichment'),
  ('plex', 'Cast portrait unavailable'),
  ('guide', 'Guide current program wait timed out'),
  ('guide', 'Guide schedule load timed out'),
  ('playback', 'Native playback failed'),
  ('playback', 'Playback request failed'),
  ('playback', 'Plex playback selected'),
];

const _mixedCaseContext = <String, Object>{
  'code': 'HTTP_ERROR',
  'failureCode': 'TimeOut',
  'operation': 'SEEK',
  'container': 'MPEG-TS',
  'videoCodec': 'HEVC',
  'audioCodec': 'EAC3',
  'dynamicRange': 'HDR10',
  'videoOutput': 'GPU-NEXT',
  'hardwareDecoder': 'D3D11VA',
  'scanPath': 'Launch',
  'libraryType': 'Show',
  'httpStatus': 401,
  'count': 2,
  'itemsMs': 86400000,
  'collectionsMs': 0,
  'showGenresMs': 560,
  'items': 1000000,
  'collections': 300,
  'members': 4200,
  'shows': 80,
};

DiagnosticSupportSnapshot _snapshot(List<DiagnosticEntry> events) =>
    DiagnosticSupportSnapshot(
      reportTime: DateTime.utc(2026, 10, 15, 12),
      timeZone: 'America/New_York',
      appVersion: '1.2.3',
      appBuild: '42',
      platform: 'windows',
      recordingEnabled: true,
      plexServerSelected: true,
      plexConnectionVerified: false,
      playback: const PlaybackDiagnosticSnapshot(
        state: PlayerState.playing,
        method: DiagnosticPlaybackMethod.directStream,
        receivedTelemetry: PlayerTelemetry(
          width: 1920,
          height: 1080,
          videoCodec: 'HEVC',
          gamma: 'PQ',
          pixelFormat: 'YUV420P10LE',
          primaries: 'BT.2020',
          colorMatrix: 'BT.2020-NCL',
          signalPeak: 10,
          videoOutput: 'GPU-NEXT',
          hardwareDecoder: 'D3D11VA',
          targetGamma: 'GAMMA2.2',
          targetPrimaries: 'BT.709',
          targetPixelFormat: 'RGB10A2',
        ),
      ),
      events: events,
    );

void main() {
  test('cast diagnostics admit only fixed enums in storage and export', () {
    final diagnostics = Diagnostics()..enabled = true;
    addTearDown(diagnostics.dispose);
    for (final outcome in ['requested', 'enriched', 'noRicherData', 'failed']) {
      diagnostics.add(DiagnosticEvent.castEnrichment, {'castOutcome': outcome});
      expect(diagnostics.entries.last.context, {'castOutcome': outcome});
    }
    for (final failure in ['auth', 'timeout', 'transport', 'shape']) {
      diagnostics.add(DiagnosticEvent.castEnrichment, {
        'castOutcome': 'failed',
        'castFailure': failure,
      });
      expect(diagnostics.entries.last.context['castFailure'], failure);
    }
    diagnostics.add(DiagnosticEvent.castEnrichment, {
      'castOutcome': 'private-name',
      'castFailure': 'https://private.invalid',
      'itemId': 'private',
    });
    expect(diagnostics.entries.last.context, isEmpty);
    final report = diagnostics.buildSupportReport(
      _snapshot(diagnostics.entries),
    );
    expect(report, contains('castOutcome=noRicherData'));
    expect(report, isNot(contains('private')));
    final forged = diagnostics.buildSupportReport(
      _snapshot([
        DiagnosticEntry(DateTime.utc(2026), 'plex', 'Cast enrichment', {
          'castOutcome': 'private-name',
          'castFailure': 'private',
        }),
      ]),
    );
    expect(forged, isNot(contains('private')));
  });

  test(
    'fixed support report bytes validate every event and forged context',
    () {
      final diagnostics = Diagnostics();
      addTearDown(diagnostics.dispose);
      expect(
        DiagnosticEvent.values.map((event) => (event.area, event.message)),
        _eventPairs,
      );
      final time = DateTime.utc(2026, 10, 15, 11, 59);
      final stringKeys = _mixedCaseContext.keys.take(11);
      final snapshot = _snapshot([
        for (var index = 0; index < _eventPairs.length; index++)
          DiagnosticEntry(
            time,
            _eventPairs[index].$1,
            _eventPairs[index].$2,
            index == 0 ? _mixedCaseContext : const {},
          ),
        // Syntactically safe unknowns still cannot cross the export boundary.
        DiagnosticEntry(time, 'playback', 'Playback request failed', {
          for (final key in stringKeys) key: 'opaque-safe',
          'unknown': 'seek',
        }),
        // Directly constructed entries bypass ingest sanitation entirely.
        DiagnosticEntry(time, 'playback', 'Playback request failed', {
          for (final key in stringKeys) key: 'unsafe synthetic value',
          'httpStatus': 99,
          'count': 1000001,
          'itemsMs': 86400001,
          'collectionsMs': -1,
          'showGenresMs': 1.5,
          'items': true,
          'collections': '300',
          'members': double.infinity,
          'shows': <int>[],
        }),
        DiagnosticEntry(time, 'playback', 'Playback request failed', {
          for (final key in stringKeys) key: true,
          'httpStatus': '401',
          'count': 2.0,
        }),
        DiagnosticEntry(time, 'synthetic', 'Playback request failed', const {}),
        DiagnosticEntry(
          time,
          'playback',
          'Unrecognized synthetic event',
          const {},
        ),
        DiagnosticEntry(time, 'guide', 'Native playback failed', const {}),
      ]);

      final report = diagnostics.buildSupportReport(snapshot);
      expect(report, _expectedReport);
      expect(utf8.encode(report), utf8.encode(_expectedReport));
    },
  );

  test(
    'storage retains token spelling and sanitizes independently of export',
    () {
      final diagnostics = Diagnostics()..enabled = true;
      addTearDown(diagnostics.dispose);
      diagnostics.add(
        DiagnosticEvent.credentialCleanupFailed,
        _mixedCaseContext,
      );
      expect(diagnostics.entries.single.context, _mixedCaseContext);
      expect(
        () => diagnostics.entries.single.context['code'] = 'mutated',
        throwsUnsupportedError,
      );
      for (final key in _mixedCaseContext.keys.take(11)) {
        diagnostics.add(DiagnosticEvent.playbackRequestFailed, {
          key: 'opaque-safe',
        });
        expect(diagnostics.entries.last.context, {key: 'opaque-safe'});
        for (final value in ['', 'unsafe synthetic value', 'x' * 65]) {
          diagnostics.add(DiagnosticEvent.playbackRequestFailed, {key: value});
          expect(diagnostics.entries.last.context, {key: 'unexpected'});
        }
        for (final value in <Object?>[null, true, 1, 1.5, <String>[]]) {
          diagnostics.add(DiagnosticEvent.playbackRequestFailed, {key: value});
          expect(diagnostics.entries.last.context, isEmpty);
        }
      }
      diagnostics.add(DiagnosticEvent.playbackRequestFailed, {
        'code': 'unsafe synthetic value',
        'container': 'unsafe synthetic value',
        'videoCodec': 'opaque-safe',
        'operation': 'SEEK',
        'httpStatus': true,
        'count': -1,
        'unknown': 'seek',
      });
      final stored = diagnostics.entries.last;
      expect(stored.context, {
        'code': 'unexpected',
        'container': 'unexpected',
        'videoCodec': 'opaque-safe',
        'operation': 'SEEK',
      });
      final report = diagnostics.buildSupportReport(
        _snapshot([
          DiagnosticEntry(
            DateTime.utc(2026, 10, 15, 11, 59),
            stored.area,
            stored.message,
            stored.context,
          ),
        ]),
      );
      expect(
        report.substring(report.indexOf('Recent events:')),
        'Recent events:\n'
        '2026-10-15T11:59:00.000Z playback: Playback request failed '
        '(code=unexpected, operation=seek)\n',
      );
    },
  );

  testWidgets('expanded diagnostics displays stored context spelling', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1280, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = FixtureController();
    addTearDown(controller.dispose);
    controller.diagnostics.enabled = true;
    controller.diagnostics.add(DiagnosticEvent.playbackRequestFailed, {
      'code': 'HTTP_ERROR',
      'operation': 'SEEK',
      'videoCodec': 'opaque-safe',
      'audioCodec': 'unsafe synthetic value',
      'httpStatus': true,
    });
    expect(controller.diagnostics.entries.single.context, {
      'code': 'HTTP_ERROR',
      'operation': 'SEEK',
      'videoCodec': 'opaque-safe',
      'audioCodec': 'unexpected',
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: LineupCanvas.builder,
        theme: LineupTheme.forName(
          LineupThemeName.emberSteel,
          largeFocusIndicators: false,
        ),
        home: Scaffold(
          body: DiagnosticsView(
            controller: controller,
            playback: const PlaybackDiagnosticSnapshot(state: PlayerState.idle),
            onRecordingSettings: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Playback request failed'));
    await tester.tap(find.text('Playback request failed'));
    await tester.pumpAndSettle();
    for (final value in [
      'Code: HTTP_ERROR',
      'Operation: SEEK',
      'Video codec: opaque-safe',
      'Audio codec: unexpected',
    ]) {
      expect(find.text(value, findRichText: true), findsOneWidget);
    }
    expect(find.text('Code: http_error', findRichText: true), findsNothing);
    expect(find.textContaining('unsafe synthetic value'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
