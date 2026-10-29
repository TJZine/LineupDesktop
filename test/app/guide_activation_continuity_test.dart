import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_app.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_view.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/playback/player_coordinator.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/player_view.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

import '../support/test_doubles.dart';

void main() {
  testWidgets('TV Guide Select preserves the owned playing session', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _RequestSpyController();
    await controller.prepare();
    final native = FakeNativePlayer();
    await tester.pumpWidget(
      LineupBootstrap(
        player: native,
        controller: controller,
        androidTv: true,
        guideClock: () => _now,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(GuideView), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Guide');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    final coordinator = tester
        .widget<PlayerView>(find.byType(PlayerView))
        .controller;
    expect(coordinator.error, isNull);
    expect(controller.requests, hasLength(1));
    native.emit(
      const PlayerStatus(state: PlayerState.playing, message: 'Playing'),
      position: const Duration(seconds: 37),
      duration: const Duration(hours: 24),
      tracks: const [
        PlayerTrack(id: 7, type: PlayerTrackType.audio, selected: true),
      ],
      tracksUpdated: true,
    );
    await tester.pump();
    final program = coordinator.currentProgram;
    final request = controller.requests.single;
    final generation = native.generation;
    for (final state in [
      PlayerState.playing,
      PlayerState.buffering,
      PlayerState.seeking,
      PlayerState.paused,
    ]) {
      if (state == PlayerState.paused) await coordinator.pause();
      native.emit(PlayerStatus(state: state, message: state.name));
      await tester.pump();
      final counts = _commands(native);
      final toggleWillPause = coordinator.playbackToggleWillPause;
      for (var visit = 0; visit < 3; visit++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump();
        expect(
          find.byKey(const Key('guide-picture-in-picture')),
          findsOneWidget,
        );
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'Guide');
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump();
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'Player');
        expect((_commands(native), controller.requests.length), (counts, 1));
        expect(controller.requests.single, same(request));
        expect(native.generation, generation);
        expect(coordinator.currentProgram, same(program));
        expect(coordinator.position, const Duration(seconds: 37));
        expect(coordinator.tracks.single.id, 7);
        expect(coordinator.tracks.single.selected, isTrue);
        expect(coordinator.status.state, state);
        expect(coordinator.playbackToggleWillPause, toggleWillPause);
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    controller.dispose();
  });
  testWidgets('desktop Guide Select retains explicit retune behavior', (
    tester,
  ) async {
    final controller = _RequestSpyController();
    await controller.prepare();
    final native = FakeNativePlayer();
    await tester.pumpWidget(
      LineupBootstrap(
        player: native,
        controller: controller,
        androidTv: false,
        guideClock: () => _now,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    native.emit(
      const PlayerStatus(state: PlayerState.playing, message: 'Playing'),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.requests, hasLength(2));
    expect(native.loads, hasLength(2));
    expect(native.stops, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    controller.dispose();
  });

  for (final scope in ['profile', 'server', 'connection', 'inventory']) {
    test(
      'Guide activation respects real controller $scope retirement',
      () async {
        final controller = _RequestSpyController();
        await controller.prepare();
        final native = FakeNativePlayer();
        final guide = GuideController(lineup: controller, clock: () => _now);
        final coordinator = PlayerCoordinator(
          player: native,
          lineup: controller,
          guide: guide,
          clock: () => _now,
          androidTv: true,
        );
        addTearDown(controller.dispose);
        addTearDown(guide.dispose);
        addTearDown(coordinator.dispose);
        addTearDown(native.dispose);
        expect(await coordinator.tune('channel'), isTrue);
        native.emit(
          const PlayerStatus(state: PlayerState.playing, message: 'Playing'),
        );
        await Future<void>.delayed(Duration.zero);
        expect(coordinator.watchingChannelId, 'channel');
        switch (scope) {
          case 'profile':
            controller.fixtureActor.profileSelected(
              const PlexHomeUser(
                id: 'other-profile',
                name: 'Synthetic Other',
                protected: false,
              ),
            );
          case 'server':
            controller.fixtureActor.serverSelected(
              PlexServer(
                id: 'other-server',
                name: 'Synthetic Other',
                connections: [controller.connection!],
              ),
            );
          case 'connection':
            controller.fixtureActor.replaceConnection(
              PlexConnection(
                uri: Uri.parse('https://other-synthetic.invalid'),
                local: true,
                relay: false,
              ),
            );
          case 'inventory':
            controller.fixtureActor.publishInventory(
              media: controller.availableMedia,
            );
        }
        expect(
          await coordinator.activateFromGuide('channel'),
          scope == 'connection' || scope == 'inventory',
        );
        expect(native.stops, 1);
        if (scope == 'profile' || scope == 'server') {
          expect(native.loads, hasLength(1));
          expect(coordinator.watchingChannelId, isNull);
        } else {
          expect(native.loads, hasLength(2));
          expect(controller.requests, hasLength(2));
          expect(native.loadGenerations[1], isNot(native.loadGenerations[0]));
        }
      },
    );
  }
}

(int, int, int, int, int, int) _commands(FakeNativePlayer native) => (
  native.stops,
  native.loads.length,
  native.seeks.length,
  native.plays,
  native.pauseCalls,
  native.selectedTracks.length,
);

final _now = DateTime(2026, 10, 25, 12);

class _RequestSpyController extends LineupController {
  _RequestSpyController()
    : super(
        store: MemoryAppStore(),
        credentials: MemoryCredentialStore(accountToken: 'synthetic-account'),
        plex: _SyntheticPlex(),
      );
  final requests = <LineupPlaybackRequest>[];
  @override
  Future<void> initialize() async {}

  Future<void> prepare() async {
    await super.initialize();
    await selectProfile(profiles.single);
    await selectServer(servers.single);
    fixtureActor.publishInventory(
      media: [
        PlexMediaItem(
          id: 'program',
          title: 'Synthetic Program',
          type: 'movie',
          duration: Duration(hours: 24),
          parts: [PlexMediaPart(path: '/library/parts/synthetic/file.mkv')],
        ),
      ],
    );
    fixtureActor.replaceChannels([
      Channel(
        id: 'channel',
        number: 7,
        name: 'Synthetic Seven',
        source: const ManualSource([
          ChannelItem(
            id: 'program',
            title: 'Synthetic Program',
            duration: Duration(hours: 24),
          ),
        ]),
        playbackMode: PlaybackMode.sequential,
        anchor: _now.subtract(const Duration(hours: 1)),
        shuffleSeed: 7,
      ),
    ]);
    completeChannelSetup();
    expect(stage, SetupStage.ready);
  }

  @override
  LineupPlaybackRequest playbackFor(String itemId) {
    final request = super.playbackFor(itemId);
    requests.add(request);
    return request;
  }

  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) async => buildSchedule(
    (channel.source as ManualSource).items,
    mode: channel.playbackMode,
    seed: channel.shuffleSeed,
  );
}

class _SyntheticPlex extends PlexClient {
  _SyntheticPlex()
    : super(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: testPlexHttpClient(),
      );
  final syntheticServer = PlexServer(
    id: 'server',
    name: 'Synthetic Server',
    owned: true,
    connections: [
      PlexConnection(
        uri: Uri.parse('https://synthetic.invalid'),
        local: true,
        relay: false,
      ),
    ],
  );
  @override
  Future<PlexAccount> account(String token) async =>
      const PlexAccount(id: 'owner', name: 'Synthetic Owner', email: '');
  @override
  Future<List<PlexHomeUser>> homeUsers(String accountToken) async => const [
    PlexHomeUser(id: 'owner', name: 'Synthetic Owner', protected: false),
  ];
  @override
  Future<List<PlexServerAccess>> discoverServers(String token) async => [
    PlexServerAccess(server: syntheticServer, token: 'synthetic-pms'),
  ];
  @override
  Future<PlexConnection> selectConnection(
    PlexServer server,
    String token,
  ) async => server.connections.single;
  @override
  Future<List<PlexLibrary>> libraries(Uri server, String token) async =>
      const [];
}
