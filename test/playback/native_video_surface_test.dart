import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/native_video_surface.dart';

void main() {
  testWidgets(
    'projects global logical bounds, DPR, deduplication, and teardown',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final player = _RecordingPlayer();

      Widget surface() => MaterialApp(
        home: Stack(
          children: [
            Positioned(
              left: 40,
              top: 50,
              width: 200,
              height: 100,
              child: NativeVideoSurface(player: player),
            ),
          ],
        ),
      );

      await tester.pumpWidget(surface());
      await tester.pump();

      expect(player.rects, [
        const PlayerVideoRect(
          left: 40,
          top: 50,
          width: 200,
          height: 100,
          scale: 2,
        ),
      ]);

      await tester.pumpWidget(surface());
      await tester.pump();
      expect(player.rects, hasLength(1));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(
        player.rects.last,
        const PlayerVideoRect(left: 0, top: 0, width: 0, height: 0, scale: 1),
      );
    },
  );
}

class _RecordingPlayer implements NativePlayer {
  final rects = <PlayerVideoRect>[];

  @override
  PlayerStatus get status =>
      const PlayerStatus(state: PlayerState.idle, message: 'Idle');

  @override
  Duration get position => Duration.zero;

  @override
  Duration get duration => Duration.zero;

  @override
  PlayerTelemetry get telemetry => const PlayerTelemetry();

  @override
  List<PlayerTrack> get tracks => const [];

  @override
  Stream<PlayerEvent> get events => const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> load(Uri media, {String? plexToken, int? generation}) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVideoRect(PlayerVideoRect rect) async => rects.add(rect);

  @override
  Future<void> setFullscreen(bool fullscreen) async {}

  @override
  Future<void> selectTrack(PlayerTrackType type, int? id) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
