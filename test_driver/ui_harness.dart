import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lineup_desktop/app/lineup_app.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/plex/plex_client.dart';

void main() {
  runApp(
    LineupBootstrap(player: HarnessPlayer(), controller: HarnessController()),
  );
}

/// Synthetic, credential-free visual/profile harness. Production main.dart
/// cannot reach this composition root.
class HarnessController extends LineupController {
  HarnessController()
    : super(
        store: _HarnessStore(),
        credentials: _HarnessCredentials(),
        plex: PlexClient(
          clientIdentifier: 'lineup-desktop-harness-abcdefghijklmnopqr',
        ),
      ) {
    channels = List.generate(1000, _channel, growable: false);
    currentChannelId = channels[40].id;
    stage = SetupStage.ready;
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) async => buildSchedule(
    (channel.source as ManualSource).items,
    mode: channel.playbackMode,
    seed: channel.shuffleSeed,
  );

  @override
  LineupPlaybackRequest playbackFor(String itemId) =>
      LineupPlaybackRequest.parts([
        LineupPlaybackPart(uri: Uri.parse('lineup-test://synthetic/$itemId')),
      ]);

  @override
  Future<void> setCurrentChannel(String? id) async {
    currentChannelId = id;
    notifyListeners();
  }

  static Channel _channel(int index) => Channel(
    id: 'synthetic-channel-$index',
    number: index + 1,
    name: [
      'Action Cinema',
      'Comedy Club',
      'Documentary',
      'Evening Drama',
      'Family Favorites',
    ][index % 5],
    source: ManualSource([
      for (var program = 0; program < 12; program++)
        ChannelItem(
          id: 'synthetic-$index-$program',
          title: [
            'The Long Way Home',
            'City Stories',
            'After Midnight',
            'World in Focus',
            'The Weekend Edit',
          ][(index + program) % 5],
          showTitle: program.isEven ? 'Lineup Originals' : null,
          duration: Duration(minutes: 24 + program * 3),
        ),
    ]),
    playbackMode: PlaybackMode.sequential,
    anchor: DateTime.utc(2026, 8, 13),
    shuffleSeed: index,
  );
}

class HarnessPlayer implements NativePlayer {
  final _events = StreamController<PlayerEvent>.broadcast();
  bool _disposed = false;
  int _loadEpoch = 0;
  int? _generation;
  PlayerStatus _status = const PlayerStatus(
    state: PlayerState.playing,
    message: 'Synthetic player surface',
  );

  @override
  PlayerStatus get status => _status;
  @override
  Duration get position => const Duration(minutes: 18);
  @override
  Duration get duration => const Duration(minutes: 48);
  @override
  PlayerTelemetry get telemetry =>
      const PlayerTelemetry(width: 1920, height: 1080, videoCodec: 'h264');
  @override
  List<PlayerTrack> get tracks => const [
    PlayerTrack(
      id: 1,
      type: PlayerTrackType.audio,
      selected: true,
      title: 'Synthetic English',
    ),
    PlayerTrack(
      id: 2,
      type: PlayerTrackType.subtitle,
      selected: false,
      title: 'Synthetic captions',
    ),
  ];
  @override
  Stream<PlayerEvent> get events => _events.stream;

  @override
  Future<void> initialize() async {}
  @override
  Future<void> load(Uri media, {String? plexToken, int? generation}) async {
    if (_disposed) return;
    final operation = ++_loadEpoch;
    _generation = generation;
    _status = const PlayerStatus(
      state: PlayerState.loading,
      message: 'Loading synthetic program',
    );
    _emit();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (_disposed || operation != _loadEpoch) return;
    _status = const PlayerStatus(
      state: PlayerState.playing,
      message: 'Playing synthetic program',
    );
    _emit();
  }

  @override
  Future<void> pause() async {
    _status = const PlayerStatus(state: PlayerState.paused, message: 'Paused');
    _emit();
  }

  @override
  Future<void> play() async {
    _status = const PlayerStatus(
      state: PlayerState.playing,
      message: 'Playing',
    );
    _emit();
  }

  void _emit() {
    if (_disposed || _events.isClosed) return;
    _events.add(
      PlayerEvent(
        status: status,
        position: position,
        duration: duration,
        telemetry: telemetry,
        tracks: tracks,
        generation: _generation,
      ),
    );
  }

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
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _events.close();
  }
}

class _HarnessStore implements AppStore {
  @override
  Future<String> clientIdentifier() async => 'harness';
  @override
  Future<AppStoreLoadResult> load() async =>
      const AppStoreLoadResult(PersistedState());
  @override
  Future<void> save(PersistedState state) async {}
}

class _HarnessCredentials implements CredentialStore {
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
