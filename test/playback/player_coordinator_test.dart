import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/player_coordinator.dart';
import 'package:lineup_desktop/plex/plex_client.dart';

void main() {
  test(
    'tune dispatches load, wall-clock seek, and stable current identity',
    () async {
      final lineup = _TestLineup();
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      guide.requestViewport(0, 2);
      await Future<void>.delayed(Duration.zero);
      final player = _Player();
      final coordinator = PlayerCoordinator(
        player: player,
        lineup: lineup,
        guide: guide,
      );

      await coordinator.tune('channel-b');

      expect(player.loads.single, Uri.parse('https://media.test/program'));
      expect(player.seeks.single, greaterThanOrEqualTo(Duration.zero));
      expect(lineup.currentChannelId, 'channel-b');
      expect(coordinator.overlay, PlayerOverlay.osd);
      expect(lineup.releases, 0);
      await coordinator.stop();
      await coordinator.stop();
      expect(lineup.releases, 1);

      coordinator.dispose();
      guide.dispose();
      lineup.dispose();
    },
  );

  test(
    'one overlay owner enforces track back-stack and direct number tune',
    () async {
      final lineup = _TestLineup();
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      guide.requestViewport(0, 2);
      await Future<void>.delayed(Duration.zero);
      final coordinator = PlayerCoordinator(
        player: _Player(),
        lineup: lineup,
        guide: guide,
      );

      coordinator.showOsd();
      coordinator.showTracks(PlayerTrackType.subtitle);
      expect(coordinator.overlay, PlayerOverlay.subtitleTracks);
      coordinator.closeOverlay();
      expect(coordinator.overlay, PlayerOverlay.osd);

      coordinator.appendChannelDigit('9');
      expect(coordinator.overlay, PlayerOverlay.channelNumber);
      await coordinator.commitChannelNumber();
      expect(lineup.currentChannelId, 'channel-b');

      coordinator.dispose();
      guide.dispose();
      lineup.dispose();
    },
  );

  test(
    'mini Guide pages by logical identity without mounting all channels',
    () {
      final lineup = _TestLineup(count: 1000);
      final guide = GuideController(lineup: lineup);
      final coordinator = PlayerCoordinator(
        player: _Player(),
        lineup: lineup,
        guide: guide,
      );

      coordinator.showMiniGuide();
      coordinator.moveMiniGuide(500);

      expect(coordinator.miniGuideChannelId, 'channel-500');
      expect(guide.cachedRowCount, lessThanOrEqualTo(14));

      coordinator.dispose();
      guide.dispose();
      lineup.dispose();
    },
  );
}

ScheduleIndex _schedule(Channel channel) => buildSchedule(
  (channel.source as ManualSource).items,
  mode: channel.playbackMode,
  seed: channel.shuffleSeed,
);

class _TestLineup extends LineupController {
  _TestLineup({int count = 2})
    : super(
        store: _MemoryStore(),
        credentials: _Credentials(),
        plex: PlexClient(
          clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        ),
      ) {
    channels = List.generate(count, (index) {
      final id = index == 1 ? 'channel-b' : 'channel-$index';
      return Channel(
        id: id,
        number: index == 1 ? 9 : index + 1,
        name: 'Channel $index',
        source: ManualSource([
          ChannelItem(
            id: 'program-$index',
            title: 'Program $index',
            duration: const Duration(hours: 24),
          ),
        ]),
        playbackMode: PlaybackMode.sequential,
        anchor: DateTime.now().subtract(const Duration(hours: 1)),
        shuffleSeed: index,
      );
    });
    currentChannelId = channels.first.id;
    stage = SetupStage.ready;
  }

  int releases = 0;

  @override
  LineupPlaybackRequest playbackFor(String itemId) =>
      LineupPlaybackRequest(Uri.parse('https://media.test/program'), () async {
        releases++;
      });

  @override
  Future<void> setCurrentChannel(String id) async {
    currentChannelId = id;
    notifyListeners();
  }
}

class _Player implements NativePlayer {
  final loads = <Uri>[];
  final seeks = <Duration>[];
  final selectedTracks = <(PlayerTrackType, int?)>[];

  @override
  PlayerStatus status = const PlayerStatus(
    state: PlayerState.playing,
    message: 'Playing',
  );
  @override
  Duration position = const Duration(minutes: 10);
  @override
  Duration duration = const Duration(hours: 1);
  @override
  PlayerTelemetry telemetry = const PlayerTelemetry();
  @override
  List<PlayerTrack> tracks = const [];
  @override
  Stream<PlayerEvent> get events => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<void> load(Uri media) async => loads.add(media);
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration value) async => seeks.add(value);
  @override
  Future<void> setVideoRect(PlayerVideoRect rect) async {}
  @override
  Future<void> setFullscreen(bool fullscreen) async {}
  @override
  Future<void> selectTrack(PlayerTrackType type, int? id) async =>
      selectedTracks.add((type, id));
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class _MemoryStore implements AppStore {
  @override
  Future<String> clientIdentifier() async => 'test';
  @override
  Future<PersistedState> load() async => const PersistedState();
  @override
  Future<void> save(PersistedState state) async {}
}

class _Credentials implements CredentialStore {
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
