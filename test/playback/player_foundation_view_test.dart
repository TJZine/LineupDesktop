import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/native_video_surface.dart';
import 'package:lineup_desktop/playback/player_foundation_view.dart';

void main() {
  testWidgets('unsupported backend does not mount native presentation', (
    tester,
  ) async {
    final player = _RecordingPlayer(
      status: const PlayerStatus(
        state: PlayerState.unsupported,
        message: 'Playback is not implemented on macOS.',
      ),
    );

    await tester.pumpWidget(_host(PlayerFoundationView(player: player)));
    await tester.pump();

    expect(find.byType(NativeVideoSurface), findsNothing);
    expect(player.videoRects, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'recreation resends bounds and resets the fullscreen projection',
    (tester) async {
      final player = _RecordingPlayer();

      await tester.pumpWidget(_host(PlayerFoundationView(player: player)));
      await tester.pump();

      final initialBounds = player.videoRects.where(_hasArea).length;
      expect(initialBounds, 1);

      final fullscreen = find.text('Fullscreen');
      await tester.ensureVisible(fullscreen);
      await tester.tap(fullscreen);
      await tester.pumpAndSettle();

      expect(player.fullscreenCalls, [true]);
      expect(find.text('Exit fullscreen'), findsOneWidget);

      final recreate = find.text('Dispose + recreate');
      await tester.ensureVisible(recreate);
      await tester.tap(recreate);
      await tester.pumpAndSettle();

      expect(player.disposeCalls, 1);
      expect(player.initializeCalls, 1);
      expect(player.videoRects.where(_hasArea), hasLength(initialBounds + 1));
      expect(find.text('Fullscreen'), findsOneWidget);
      expect(find.text('Exit fullscreen'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _host(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

bool _hasArea(PlayerVideoRect rect) => rect.width > 0 && rect.height > 0;

class _RecordingPlayer implements NativePlayer {
  _RecordingPlayer({
    this.status = const PlayerStatus(
      state: PlayerState.idle,
      message: 'Test player ready',
    ),
  });

  final List<PlayerVideoRect> videoRects = [];
  final List<bool> fullscreenCalls = [];
  @override
  PlayerStatus status;
  int initializeCalls = 0;
  int disposeCalls = 0;

  @override
  Duration get position => Duration.zero;

  @override
  Duration get duration => Duration.zero;

  @override
  PlayerTelemetry get telemetry => const PlayerTelemetry();

  @override
  List<PlayerTrack> get tracks => const [];

  @override
  Stream<PlayerEvent> get events => const Stream<PlayerEvent>.empty();

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
    status = const PlayerStatus(
      state: PlayerState.idle,
      message: 'Test player ready',
    );
  }

  @override
  Future<void> load(Uri media) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVideoRect(PlayerVideoRect rect) async {
    videoRects.add(rect);
  }

  @override
  Future<void> setFullscreen(bool fullscreen) async {
    fullscreenCalls.add(fullscreen);
  }

  @override
  Future<void> selectTrack(PlayerTrackType type, int? id) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    status = const PlayerStatus(
      state: PlayerState.stopped,
      message: 'Test player disposed',
    );
  }
}
