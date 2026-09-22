@TestOn('mac-os')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/player_coordinator.dart';
import 'package:lineup_desktop/playback/player_view.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';

import '../../test/support/golden_test_support.dart';
import '../../test/support/ui_fixture.dart';

const _variant = String.fromEnvironment(
  'TRACK_LABEL_VARIANT',
  defaultValue: 'after',
);
const _output = String.fromEnvironment(
  'TRACK_LABEL_OUTPUT',
  defaultValue: 'docs/design/desktop-ui/evidence/2026-09-22-track-labels',
);
const _boundaryKey = Key('player-track-label-visual-boundary');

void main() {
  setUpAll(loadPinnedTestFonts);

  testWidgets('matched audio and subtitle track drawer candidates', (
    tester,
  ) async {
    for (final viewport in const [Size(1280, 720), Size(1920, 1080)]) {
      for (final bright in [true, false]) {
        for (final type in [PlayerTrackType.audio, PlayerTrackType.subtitle]) {
          final fixture = _VisualFixture();
          tester.view
            ..devicePixelRatio = 1
            ..physicalSize = viewport;
          fixture.coordinator.showTracks(type);
          await tester.pumpWidget(
            RepaintBoundary(
              key: _boundaryKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: LineupTheme.forName(LineupThemeName.emberSteel),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: viewport,
                    devicePixelRatio: 1,
                    textScaler: TextScaler.noScaling,
                    disableAnimations: true,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(painter: _VideoScenePainter(bright: bright)),
                      PlayerView(
                        controller: fixture.coordinator,
                        openGuide: () {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));

          final name =
              '${type == PlayerTrackType.audio ? 'audio' : 'subtitles'}-'
              '${bright ? 'bright' : 'dark'}-'
              '${viewport.width.toInt()}x${viewport.height.toInt()}.png';
          final golden = File('$_output/$_variant/$name').absolute.path;
          final boundary = find.byKey(_boundaryKey);
          markSubtreeNeedsPaint(tester.renderObject(boundary));
          await tester.pump();
          await expectLater(boundary, matchesGoldenFile(golden));

          await tester.pumpWidget(const SizedBox.shrink());
          await fixture.dispose();
        }
      }
    }
    tester.view
      ..resetDevicePixelRatio()
      ..resetPhysicalSize();
  });
}

class _VisualFixture {
  _VisualFixture() {
    final item = const ChannelItem(
      id: 'synthetic-program',
      title: 'Synthetic feature',
      duration: Duration(hours: 2),
    );
    final channel = Channel(
      id: 'synthetic-channel',
      number: 7,
      name: 'Synthetic Cinema',
      source: ManualSource([item]),
      playbackMode: PlaybackMode.sequential,
      anchor: DateTime.utc(2026, 9, 22),
      shuffleSeed: 7,
    );
    lineup = FixtureController()
      ..stage = SetupStage.ready
      ..channels = [channel]
      ..currentChannelId = channel.id
      ..settings = const LineupSettings(reduceMotion: true);
    player = FixturePlayer()
      ..emit(
        const PlayerStatus(state: PlayerState.paused, message: 'Paused'),
        position: const Duration(minutes: 32),
        duration: const Duration(hours: 2),
        tracks: _tracks,
      );
    guide = GuideController(
      lineup: lineup,
      clock: () => DateTime.utc(2026, 9, 22, 20),
      loadSchedule: (value) async =>
          buildChannelSchedule(value, (value.source as ManualSource).items),
    );
    coordinator = PlayerCoordinator(
      player: player,
      lineup: lineup,
      guide: guide,
    );
  }

  late final FixtureController lineup;
  late final FixturePlayer player;
  late final GuideController guide;
  late final PlayerCoordinator coordinator;

  Future<void> dispose() async {
    coordinator.dispose();
    guide.dispose();
    lineup.dispose();
    await player.dispose();
  }
}

const _tracks = [
  PlayerTrack(
    id: 1,
    type: PlayerTrackType.audio,
    selected: true,
    title: 'Original theatrical mix',
    language: 'en',
    codec: 'truehd',
    channelCount: 6,
    channelLayout: '5.1',
  ),
  PlayerTrack(
    id: 2,
    type: PlayerTrackType.audio,
    selected: false,
    title: 'Director commentary',
    language: 'en',
    codec: 'aac',
    channelCount: 2,
    channelLayout: 'stereo',
    commentary: true,
  ),
  PlayerTrack(
    id: 3,
    type: PlayerTrackType.audio,
    selected: false,
    language: 'es-419',
    codec: 'eac3',
    channelCount: 6,
    channelLayout: '5.1(side)',
  ),
  PlayerTrack(
    id: 4,
    type: PlayerTrackType.audio,
    selected: false,
    title: 'Descriptive restoration',
    language: 'fr',
    codec: 'ac3',
    channelCount: 6,
    channelLayout: 'unknown-layout',
    visualImpaired: true,
  ),
  PlayerTrack(
    id: 5,
    type: PlayerTrackType.audio,
    selected: false,
    title: 'Long shared archival presentation title ending in theatrical',
    language: 'en',
    codec: 'flac',
    channelCount: 2,
    channelLayout: 'stereo',
  ),
  PlayerTrack(
    id: 6,
    type: PlayerTrackType.audio,
    selected: false,
    title: 'Long shared archival presentation title ending in commentary',
    language: 'en',
    codec: 'flac',
    channelCount: 2,
    channelLayout: 'stereo',
  ),
  PlayerTrack(
    id: 11,
    type: PlayerTrackType.subtitle,
    selected: true,
    language: 'en',
    codec: 'subrip',
    hearingImpaired: true,
  ),
  PlayerTrack(
    id: 12,
    type: PlayerTrackType.subtitle,
    selected: false,
    language: 'en',
    codec: 'hdmv_pgs_subtitle',
    forced: true,
  ),
  PlayerTrack(
    id: 13,
    type: PlayerTrackType.subtitle,
    selected: false,
    title: 'Festival edition',
    language: 'fr',
    codec: 'ass',
  ),
  PlayerTrack(
    id: 14,
    type: PlayerTrackType.subtitle,
    selected: false,
    language: 'es-419',
    codec: 'subrip',
    external: true,
  ),
  PlayerTrack(
    id: 15,
    type: PlayerTrackType.subtitle,
    selected: false,
    title: 'Long shared restored subtitle presentation ending in theatrical',
    language: 'en',
    codec: 'subrip',
  ),
  PlayerTrack(
    id: 16,
    type: PlayerTrackType.subtitle,
    selected: false,
    title: 'Long shared restored subtitle presentation ending in commentary',
    language: 'en',
    codec: 'subrip',
  ),
];

class _VideoScenePainter extends CustomPainter {
  const _VideoScenePainter({required this.bright});

  final bool bright;

  @override
  void paint(Canvas canvas, Size size) {
    final sky = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: bright
            ? const [Color(0xFFF4C980), Color(0xFF85BFD0), Color(0xFF54717B)]
            : const [Color(0xFF080B13), Color(0xFF18203A), Color(0xFF301D28)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sky);
    canvas.drawCircle(
      Offset(size.width * 0.23, size.height * 0.27),
      size.shortestSide * 0.12,
      Paint()
        ..color = bright ? const Color(0xFFFFF3C4) : const Color(0xFFBD7859),
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height * 0.72)
        ..lineTo(size.width * 0.28, size.height * 0.43)
        ..lineTo(size.width * 0.48, size.height * 0.68)
        ..lineTo(size.width * 0.7, size.height * 0.36)
        ..lineTo(size.width, size.height * 0.7)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close(),
      Paint()
        ..color = bright ? const Color(0xFF31474B) : const Color(0xFF090A10),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.84, size.width, size.height * 0.16),
      Paint()
        ..color = bright ? const Color(0xFF18282B) : const Color(0xFF030305),
    );
  }

  @override
  bool shouldRepaint(_VideoScenePainter oldDelegate) =>
      oldDelegate.bright != bright;
}
