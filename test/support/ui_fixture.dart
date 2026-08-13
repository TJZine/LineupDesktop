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
  FixtureController({FixtureStore? store, bool restoreOnInitialize = false})
    : this._(store ?? FixtureStore(), restoreOnInitialize);

  FixtureController._(FixtureStore store, this.restoreOnInitialize)
    : fixtureStore = store,
      super(
        store: store,
        credentials: _MemoryCredentials(),
        plex: PlexClient(
          clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        ),
      );

  final FixtureStore fixtureStore;
  final bool restoreOnInitialize;

  @override
  Future<void> initialize() =>
      restoreOnInitialize ? super.initialize() : Future.value();
}

class FixturePlayer implements NativePlayer {
  final _events = StreamController<PlayerEvent>();
  int generation = 0;
  PlayerStatus _status = const PlayerStatus(
    state: PlayerState.idle,
    message: 'Test player is idle',
  );
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  PlayerTelemetry _telemetry = const PlayerTelemetry();
  List<PlayerTrack> _tracks = const [];

  @override
  PlayerStatus get status => _status;

  @override
  Duration get position => _position;
  @override
  Duration get duration => _duration;
  @override
  PlayerTelemetry get telemetry => _telemetry;
  @override
  List<PlayerTrack> get tracks => _tracks;
  @override
  Stream<PlayerEvent> get events => _events.stream;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> load(Uri media) async {
    generation++;
    emit(const PlayerStatus(state: PlayerState.loading, message: 'Loading'));
  }

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
  Future<void> dispose() => _events.close();

  void emit(
    PlayerStatus status, {
    Duration? position,
    Duration? duration,
    PlayerTelemetry? telemetry,
    List<PlayerTrack>? tracks,
    int? eventGeneration,
  }) {
    _status = status;
    _position = position ?? _position;
    _duration = duration ?? _duration;
    _telemetry = telemetry ?? _telemetry;
    _tracks = List.unmodifiable(tracks ?? _tracks);
    _events.add(
      PlayerEvent(
        status: _status,
        position: _position,
        duration: _duration,
        telemetry: _telemetry,
        tracks: _tracks,
        generation: eventGeneration ?? generation,
      ),
    );
  }
}

class FixtureStore implements AppStore {
  PersistedState state = const PersistedState();

  @override
  Future<String> clientIdentifier() async =>
      'lineup-desktop-test-abcdefghijklmnopqrst';
  @override
  Future<PersistedState> load() async => state;
  @override
  Future<void> save(PersistedState value) async => state = value;
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
