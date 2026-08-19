import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/native_video_surface.dart';
import 'package:lineup_desktop/playback/player_coordinator.dart';
import 'package:lineup_desktop/playback/player_view.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/app_ui.dart';

void main() {
  testWidgets('unsupported macOS backend keeps the Flutter player accessible', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.unsupported);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(
          controller: fixture.player,
          focusNode: focus,
          openGuide: () {},
        ),
      ),
    );
    await tester.pump();
    focus.requestFocus();
    await tester.pump();

    expect(find.byType(NativeVideoSurface), findsNothing);
    expect(find.text('Playback unavailable'), findsOneWidget);
    expect(find.text('Playback is unavailable on macOS.'), findsOneWidget);
    expect(focus.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlay);
    expect(fixture.native.transportCommands, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('Guide-sized player surface keeps load failures reachable', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing, failLoad: true);
    await fixture.player.loadInitialMedia(Uri.parse('lineup-test://failure'));

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 180,
          child: PlayerSurface(controller: fixture.player, showErrors: true),
        ),
      ),
    );

    expect(
      find.text('Playback could not start. Retry or choose another channel.'),
      findsOneWidget,
    );
    expect(find.textContaining('synthetic load failure'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('preparing takes precedence over buffering while tuning', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.buffering, blockLoad: true);
    var disposed = false;
    void disposeFixture() {
      if (disposed) return;
      disposed = true;
      fixture.native.completeLoad();
      fixture.dispose();
    }

    addTearDown(disposeFixture);
    await Future<void>.delayed(Duration.zero);
    final tuning = fixture.player.tune('channel');
    await fixture.native.loadStarted.future;

    await tester.pumpWidget(
      MaterialApp(home: PlayerSurface(controller: fixture.player)),
    );

    expect(find.text('Preparing playback'), findsOneWidget);
    expect(find.text('Buffering playback'), findsNothing);

    fixture.native.completeLoad();
    await tuning;
    await tester.pumpWidget(const SizedBox.shrink());
    disposeFixture();
  });

  testWidgets('keyboard routes OSD, mini Guide, and full Guide consistently', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing);
    var guideOpened = false;
    fixture.player.showOsd();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(
          controller: fixture.player,
          openGuide: () => guideOpened = true,
        ),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel(RegExp('Playback controls')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.bySemanticsLabel(RegExp('Mini Guide')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    expect(guideOpened, isTrue);

    guideOpened = false;
    fixture.player.closeOverlay();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(guideOpened, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('player OSD and mini Guide reflow at desktop sizes', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing);
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in const [
      Size(800, 600),
      Size(LineupLayout.compact - 1, 700),
      Size(LineupLayout.compact, 700),
      Size(1280, 720),
      Size(1600, 900),
      Size(1920, 1080),
      Size(3840, 2160),
      Size(1360, 840),
    ]) {
      await tester.binding.setSurfaceSize(size);
      fixture.player.showOsd();
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pump();
      expect(
        find.bySemanticsLabel(RegExp('Playback controls')),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byKey(const Key('player-osd-surface'))).width,
        size.width,
      );
      expect(tester.takeException(), isNull, reason: '$size');
    }

    await tester.binding.setSurfaceSize(const Size(1360, 840));
    fixture.player.showMiniGuide();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.bySemanticsLabel(RegExp('Mini Guide')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('mini-guide-shelf'))).width,
      1360,
    );
    expect(find.textContaining('UP/DOWN Browse'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('all player overlays fade and only the OSD slides', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );

    fixture.player.showMiniGuide();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 175));
    expect(find.byType(FadeTransition), findsWidgets);
    expect(find.byType(SlideTransition), findsNothing);

    fixture.player.closeOverlay();
    await tester.pumpAndSettle();
    fixture.player.showOsd();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 175));
    final slide = find.byType(SlideTransition);
    expect(slide, findsOneWidget);
    expect(
      find.descendant(of: slide, matching: find.byType(FadeTransition)),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('mini Guide scrolls in short windows', (tester) async {
    final fixture = _Fixture(PlayerState.playing, channelCount: 5);
    await tester.binding.setSurfaceSize(const Size(800, 240));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    fixture.player.showMiniGuide();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();

    final scrollable = find.descendant(
      of: find.byKey(const Key('mini-guide-shelf')),
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsOneWidget);
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();

    final hint = find.textContaining('UP/DOWN Browse');
    expect(tester.getRect(hint).bottom, lessThanOrEqualTo(240));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('playback options scroll through long native track lists', (
    tester,
  ) async {
    final tracks = List.generate(
      30,
      (index) => PlayerTrack(
        id: index,
        type: PlayerTrackType.audio,
        selected: index == 0,
        title: 'Audio track $index',
      ),
    );
    final fixture = _Fixture(PlayerState.playing, tracks: tracks);
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in const [Size(800, 600), Size(1280, 720)]) {
      await tester.binding.setSurfaceSize(size);
      fixture.player.showOsd();
      fixture.player.showTracks(PlayerTrackType.audio);
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pump();

      final scrollable = find.descendant(
        of: find.byKey(const Key('playback-options-list')),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.maxScrollExtent, greaterThan(0));
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      expect(find.text('Audio track 29'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$size');
    }

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('empty track menus assign one intentional autofocus target', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );

    fixture.player.showOsd();
    fixture.player.showTracks(PlayerTrackType.subtitle);
    await tester.pump();
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, 'Off')).autofocus,
      isTrue,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Back'))
          .autofocus,
      isFalse,
    );

    fixture.player.closeOverlay();
    fixture.player.showTracks(PlayerTrackType.audio);
    await tester.pump();
    expect(find.text('Off'), findsNothing);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Back'))
          .autofocus,
      isTrue,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('focused Mini Guide uses the theme focused foreground', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing);
    fixture.lineup.settings = const LineupSettings(
      theme: LineupThemeName.directv,
    );
    fixture.player.showMiniGuide();
    await tester.pumpWidget(
      MaterialApp(
        theme: LineupTheme.forName(LineupThemeName.directv),
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();

    expect(
      tester.widget<Text>(find.text('Channel')).style?.color,
      LineupTheme.of(tester.element(find.text('Channel'))).focusedText,
    );
    expect(find.bySemanticsLabel(RegExp(r'^Now watching$')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });
}

class _Fixture {
  _Fixture(
    PlayerState state, {
    bool failLoad = false,
    bool blockLoad = false,
    List<PlayerTrack> tracks = const [],
    int channelCount = 1,
  }) {
    lineup = _Lineup(channelCount);
    guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => buildSchedule(
        (channel.source as ManualSource).items,
        mode: channel.playbackMode,
        seed: channel.shuffleSeed,
      ),
    )..requestViewport(0, 1);
    native = _Native(
      state,
      failLoad: failLoad,
      blockLoad: blockLoad,
      tracks: tracks,
    );
    player = PlayerCoordinator(player: native, lineup: lineup, guide: guide);
  }

  late final _Lineup lineup;
  late final GuideController guide;
  late final _Native native;
  late final PlayerCoordinator player;

  void dispose() {
    player.dispose();
    guide.dispose();
    lineup.dispose();
  }
}

class _Lineup extends LineupController {
  _Lineup(int channelCount)
    : super(
        store: _Store(),
        credentials: _Credentials(),
        plex: PlexClient(
          clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        ),
      ) {
    channels = List.generate(
      channelCount,
      (index) => Channel(
        id: index == 0 ? 'channel' : 'channel-$index',
        number: 7 + index,
        name: index == 0 ? 'Channel' : 'Channel $index',
        source: ManualSource([
          ChannelItem(
            id: index == 0 ? 'program' : 'program-$index',
            title: index == 0 ? 'Program' : 'Program $index',
            duration: const Duration(hours: 24),
          ),
        ]),
        playbackMode: PlaybackMode.sequential,
        anchor: DateTime.now().subtract(const Duration(hours: 1)),
        shuffleSeed: index + 1,
      ),
      growable: false,
    );
    currentChannelId = 'channel';
    stage = SetupStage.ready;
  }

  @override
  LineupPlaybackRequest playbackFor(String itemId) =>
      LineupPlaybackRequest(Uri.parse('lineup-test://$itemId'), () async {});
}

class _Native implements NativePlayer {
  _Native(
    PlayerState state, {
    this.failLoad = false,
    this.blockLoad = false,
    this.tracks = const [],
  })
    : status = PlayerStatus(
        state: state,
        message: state == PlayerState.unsupported
            ? 'Playback is unavailable on macOS.'
            : 'Playing',
      );

  final bool failLoad;
  final bool blockLoad;
  final loadStarted = Completer<void>();
  final _loadCompletion = Completer<void>();
  int transportCommands = 0;

  @override
  final PlayerStatus status;
  @override
  Duration get position => const Duration(minutes: 10);
  @override
  Duration get duration => const Duration(hours: 1);
  @override
  PlayerTelemetry get telemetry => const PlayerTelemetry();
  @override
  final List<PlayerTrack> tracks;
  @override
  Stream<PlayerEvent> get events => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<void> load(Uri media, {String? plexToken, int? generation}) async {
    if (failLoad) throw StateError('synthetic load failure');
    if (blockLoad) {
      loadStarted.complete();
      await _loadCompletion.future;
    }
  }

  void completeLoad() {
    if (!_loadCompletion.isCompleted) _loadCompletion.complete();
  }

  @override
  Future<void> play() async {
    transportCommands++;
  }

  @override
  Future<void> pause() async {
    transportCommands++;
  }

  @override
  Future<void> seek(Duration position) async {
    transportCommands++;
  }

  @override
  Future<void> setVideoRect(PlayerVideoRect rect) async {}
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

class _Store implements AppStore {
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
