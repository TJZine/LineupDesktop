import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/channel_builder.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/player_coordinator.dart';
import 'package:lineup_desktop/playback/stream_policy.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

void main() {
  test(
    'deterministic public seams exercise the portable product spine',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lineup-product-spine-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final store = FileAppStore(directory);
      final credentials = _Credentials();
      final events = <String>[];
      final plex = _ProductPlex(events);
      var controller = LineupController(
        store: store,
        credentials: credentials,
        plex: plex,
        pinPollInterval: const Duration(milliseconds: 1),
      );

      await controller.initialize();
      expect(controller.stage, SetupStage.welcome);

      await controller.startLinking();
      expect(controller.stage, SetupStage.linking);
      plex.authorized = true;
      await _until(() => controller.stage == SetupStage.profiles);

      final child = controller.profiles.last;
      await controller.selectProfile(child, pin: '2468');
      expect(controller.stage, SetupStage.servers);

      await controller.selectServer(plex.server);
      expect(controller.stage, SetupStage.audio);
      expect(controller.connection?.relay, isFalse);
      expect(controller.connection?.latency, const Duration(milliseconds: 18));

      await controller.completeAudioSetup();
      expect(controller.stage, SetupStage.channelSetup);
      expect(await controller.setLibraries({'movies'}), isTrue);

      final channel = _channel(1, anchor: _ProductPlex.now);
      await controller.applyChannelPlan([
        channel,
      ], mode: ChannelBuildMode.replace);
      expect(controller.stage, SetupStage.ready);

      final guide = GuideController(
        lineup: controller,
        clock: () => _ProductPlex.now,
      )..requestViewport(0, 1);
      await _until(() => guide.currentProgram(channel.id) != null);
      final nativePlayer = _ProductPlayer(events);
      final player = PlayerCoordinator(
        player: nativePlayer,
        lineup: controller,
        guide: guide,
      );

      await player.tune(channel.id);
      expect(player.error, isNull);
      expect(controller.currentChannelId, channel.id);
      nativePlayer.emit(
        PlayerState.playing,
        generation: nativePlayer.generation,
        tracks: const [
          PlayerTrack(
            id: 1,
            type: PlayerTrackType.audio,
            selected: true,
            language: 'eng',
          ),
          PlayerTrack(
            id: 2,
            type: PlayerTrackType.subtitle,
            selected: false,
            language: 'spa',
          ),
        ],
      );
      await Future<void>.delayed(Duration.zero);
      player
        ..showFullGuide()
        ..showOsd()
        ..showMiniGuide()
        ..moveMiniGuide(1)
        ..showOsd()
        ..showTracks(PlayerTrackType.subtitle);
      await player.selectTrack(PlayerTrackType.subtitle, 2);
      expect(nativePlayer.selectedTracks, [(PlayerTrackType.subtitle, 2)]);

      nativePlayer.emit(
        PlayerState.error,
        generation: nativePlayer.generation,
        message: 'failed https://plex.example/video?X-Plex-Token=secret',
      );
      await Future<void>.delayed(Duration.zero);
      expect(player.canRetry, isTrue);
      expect(player.error, isNot(contains('secret')));
      await player.retry();

      await controller.updateSettings(
        controller.settings.copyWith(
          nowWatchingBanner: false,
          osdAutoHideSeconds: 8,
        ),
      );
      expect(controller.settings.nowWatchingBanner, isFalse);

      plex.offline = true;
      await controller.refreshServers();
      expect(controller.stage, SetupStage.servers);
      expect(controller.error, contains('network'));
      plex.offline = false;
      await controller.refreshServers();
      expect(controller.stage, SetupStage.ready);

      final largeLineup = List.generate(
        1000,
        (index) => _channel(index + 1, anchor: _ProductPlex.now),
        growable: false,
      );
      final rebuild = Stopwatch()..start();
      await controller.applyChannelPlan(
        largeLineup,
        mode: ChannelBuildMode.replace,
      );
      rebuild.stop();
      expect(controller.channels, hasLength(1000));
      expect(
        (await store.load()).channelsByProfileServer['child']!['server']!,
        hasLength(1000),
      );
      // ignore: avoid_print
      print('PRODUCT_SPINE rebuild1000Us=${rebuild.elapsedMicroseconds}');

      player.dispose();
      await nativePlayer.dispose();
      guide.dispose();
      controller.dispose();

      final restoredPlex = _ProductPlex(events)..authorized = true;
      controller = LineupController(
        store: store,
        credentials: credentials,
        plex: restoredPlex,
      );
      await controller.initialize();
      expect(controller.stage, SetupStage.ready);
      expect(controller.profile?.id, 'child');
      expect(controller.server?.id, 'server');
      expect(controller.channels, hasLength(1000));
      expect(controller.settings.osdAutoHideSeconds, 8);

      final restoredGuide = GuideController(
        lineup: controller,
        clock: () => _ProductPlex.now,
      )..requestViewport(0, 1);
      await _until(
        () =>
            restoredGuide.currentProgram(controller.channels.first.id) != null,
      );
      final restoredNativePlayer = _ProductPlayer(events);
      final restoredPlayer = PlayerCoordinator(
        player: restoredNativePlayer,
        lineup: controller,
        guide: restoredGuide,
      );
      await restoredPlayer.tune(controller.channels.first.id);
      expect(await restoredPlayer.logout(), isTrue);
      expect(controller.stage, SetupStage.welcome);
      expect(credentials.accountToken, isNull);
      expect(credentials.profileTokens, isEmpty);
      expect(events, contains('playback:release'));
      restoredPlayer.dispose();
      await restoredNativePlayer.dispose();
      restoredGuide.dispose();
      controller.dispose();

      expect(
        events,
        containsAllInOrder([
          'pin:create',
          'pin:poll',
          'account',
          'profile:child',
          'servers',
          'connection:server',
          'libraries',
          'library:movies',
          'player:load',
          'player:track:subtitle:2',
          'servers:offline',
          'servers',
        ]),
      );
    },
  );
}

Future<void> _until(bool Function() condition) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Timed out waiting for deterministic product state.');
}

Channel _channel(int number, {required DateTime anchor}) => Channel(
  id: 'channel-$number',
  number: number,
  name: 'Channel $number',
  source: const LibrarySource(
    libraryId: 'movies',
    libraryType: PlexLibraryType.movie,
  ),
  playbackMode: PlaybackMode.sequential,
  anchor: anchor.subtract(const Duration(minutes: 5)),
  shuffleSeed: number,
);

class _ProductPlex extends PlexClient {
  _ProductPlex(this.events)
    : super(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient(
          (_) async => throw StateError('unexpected HTTP'),
        ),
      );

  static final now = DateTime.utc(2026, 8, 13, 12);
  final List<String> events;
  bool authorized = false;
  bool offline = false;
  final server = PlexServer(
    id: 'server',
    name: 'Test Server',
    owned: true,
    connections: [
      PlexConnection(
        uri: Uri.parse('https://plex.example:32400'),
        local: true,
        relay: false,
      ),
    ],
  );

  @override
  Future<PlexPin> createPin() async {
    events.add('pin:create');
    return PlexPin(
      id: 1,
      code: 'ABCD',
      expiresAt: DateTime.now().add(const Duration(minutes: 1)),
    );
  }

  @override
  Future<String?> pollPin(PlexPin pin) async {
    events.add('pin:poll');
    return authorized ? 'account-token' : null;
  }

  @override
  Future<void> cancelPin(PlexPin pin) async {}

  @override
  Future<PlexAccount> account(String token) async {
    events.add('account');
    return const PlexAccount(id: 'owner', name: 'Owner', email: '');
  }

  @override
  Future<List<PlexHomeUser>> homeUsers(String accountToken) async => const [
    PlexHomeUser(id: 'owner', name: 'Owner', protected: false),
    PlexHomeUser(id: 'child', name: 'Child', protected: true),
  ];

  @override
  Future<String> switchHomeUser(
    String accountToken,
    String userId,
    String? pin,
  ) async {
    expect(pin, '2468');
    events.add('profile:$userId');
    return 'child-token';
  }

  @override
  Future<List<PlexServer>> discoverServers(String token) async {
    if (offline) {
      events.add('servers:offline');
      throw const PlexException('offline', 'The network is unavailable.');
    }
    events.add('servers');
    return [server];
  }

  @override
  Future<PlexConnection> selectConnection(
    PlexServer server,
    String token,
  ) async {
    events.add('connection:${server.id}');
    return PlexConnection(
      uri: server.connections.single.uri,
      local: true,
      relay: false,
      latency: const Duration(milliseconds: 18),
    );
  }

  @override
  Future<List<PlexLibrary>> libraries(Uri server, String token) async {
    events.add('libraries');
    return const [
      PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
    ];
  }

  @override
  Future<List<PlexMediaItem>> libraryItems(
    Uri server,
    String token,
    String libraryId,
    PlexLibraryType libraryType,
  ) async {
    events.add('library:$libraryId');
    return List.generate(
      12,
      (index) => PlexMediaItem(
        id: 'movie-$index',
        key: '/library/metadata/$index',
        title: 'Movie $index',
        type: 'movie',
        duration: const Duration(minutes: 30),
        libraryId: libraryId,
        partPath: '/library/parts/$index/file.mp4',
        container: 'mp4',
        videoCodec: 'h264',
        audioCodec: 'aac',
        dynamicRange: DynamicRange.sdr,
      ),
      growable: false,
    );
  }

  @override
  Future<PlexPlaylistCatalog> playlists(Uri server, String token) async =>
      const PlexPlaylistCatalog(playlists: [], failedIds: {});

  @override
  Future<void> releasePlaybackSession({
    required Uri server,
    required String token,
    required String sessionId,
  }) async {
    events.add('playback:release');
  }

  @override
  void close() {}
}

class _ProductPlayer implements NativePlayer {
  _ProductPlayer(this.eventLog);

  final List<String> eventLog;
  final _events = StreamController<PlayerEvent>();
  final selectedTracks = <(PlayerTrackType, int?)>[];
  int generation = 0;
  PlayerStatus _status = const PlayerStatus(
    state: PlayerState.idle,
    message: 'Idle',
  );
  List<PlayerTrack> _tracks = const [];

  @override
  PlayerStatus get status => _status;
  @override
  Duration get position => Duration.zero;
  @override
  Duration get duration => const Duration(minutes: 30);
  @override
  PlayerTelemetry get telemetry => const PlayerTelemetry();
  @override
  List<PlayerTrack> get tracks => _tracks;
  @override
  Stream<PlayerEvent> get events => _events.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> load(Uri media, {int? generation}) async {
    this.generation = generation ?? this.generation + 1;
    eventLog.add('player:load');
  }

  void emit(
    PlayerState state, {
    required int generation,
    String? message,
    List<PlayerTrack> tracks = const [],
  }) {
    _status = PlayerStatus(
      state: state,
      message: message ?? state.name,
      recoverable: state == PlayerState.error,
    );
    _tracks = tracks;
    _events.add(
      PlayerEvent(
        status: _status,
        position: Duration.zero,
        duration: const Duration(minutes: 30),
        telemetry: const PlayerTelemetry(),
        tracks: tracks,
        generation: generation,
      ),
    );
  }

  @override
  Future<void> selectTrack(PlayerTrackType type, int? id) async {
    selectedTracks.add((type, id));
    eventLog.add('player:track:${type.name}:$id');
  }

  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVideoRect(PlayerVideoRect rect) async {}
  @override
  Future<void> setFullscreen(bool fullscreen) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() => _events.close();
}

class _Credentials implements CredentialStore {
  String? accountToken;
  final profileTokens = <String, String>{};

  @override
  Future<String?> readAccountToken() async => accountToken;
  @override
  Future<String?> readProfileToken(String profileId) async =>
      profileTokens[profileId];
  @override
  Future<void> writeAccountToken(String token) async => accountToken = token;
  @override
  Future<void> writeProfileToken(String profileId, String token) async =>
      profileTokens[profileId] = token;
  @override
  Future<void> clear() async {
    accountToken = null;
    profileTokens.clear();
  }
}
