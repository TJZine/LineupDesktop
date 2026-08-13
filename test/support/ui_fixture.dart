import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:lineup_desktop/app/lineup_app.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/plex/plex_client.dart';

/// Deterministic UI states for widget tests. This file is not imported by the
/// production composition root.
class UiFixture {
  UiFixture({FixtureController? controller, FixturePlayer? player})
    : controller = controller ?? FixtureController(),
      player = player ?? FixturePlayer();

  final FixtureController controller;
  final FixturePlayer player;

  Widget build() => LineupBootstrap(player: player, controller: controller);
}

class FixtureController extends LineupController {
  FixtureController()
    : super(
        store: _MemoryStore(),
        credentials: _MemoryCredentials(),
        plex: PlexClient(
          clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        ),
      );

  @override
  Future<void> initialize() async {}
}

class FixturePlayer implements NativePlayer {
  @override
  PlayerStatus get status => const PlayerStatus(
    state: PlayerState.idle,
    message: 'Test player is idle',
  );

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
  Future<void> load(Uri media) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> selectTrack(PlayerTrackType type, int? id) async {}
  @override
  Future<void> setFullscreen(bool fullscreen) async {}
  @override
  Future<void> setVideoRect(PlayerVideoRect rect) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class _MemoryStore implements AppStore {
  @override
  Future<String> clientIdentifier() async =>
      'lineup-desktop-test-abcdefghijklmnopqrst';
  @override
  Future<PersistedState> load() async => const PersistedState();
  @override
  Future<void> save(PersistedState state) async {}
}

class _MemoryCredentials implements CredentialStore {
  @override
  Future<void> clear() async {}
  @override
  Future<String?> readAccountToken() async => null;
  @override
  Future<String?> readProfileToken(String profileId) async => null;
  @override
  Future<void> writeAccountToken(String token) async {}
  @override
  Future<void> writeProfileToken(String profileId, String token) async {}
}
