import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/player_coordinator.dart';
import 'package:lineup_desktop/playback/player_view.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/ui/channel_identity.dart';

import '../support/ui_fixture.dart';

final _now = DateTime.utc(2026, 9, 14, 12);
const _program = ChannelItem(
  id: 'audit-program',
  title: 'Audit program',
  duration: Duration(hours: 1),
);
final _channel = Channel(
  id: 'audit-channel',
  number: 7,
  name: 'Audit channel',
  source: const ManualSource([_program]),
  playbackMode: PlaybackMode.sequential,
  anchor: _now,
  shuffleSeed: 7,
  scheduleVersion: currentScheduleVersion,
);

void main() {
  for (final route in ['Guide', 'Player', 'Settings']) {
    testWidgets('Tuned menu row from $route returns to Player without retuning', (
      tester,
    ) async {
      _setViewport(tester, const Size(1280, 720));
      final controller = _AuditController(
        scenario: LineupScenario(
          stage: SetupStage.ready,
          channels: [_channel],
          currentChannelId: _channel.id,
        ),
      );
      final player = _CountingPlayer()
        ..emit(
          const PlayerStatus(state: PlayerState.playing, message: 'Playing'),
          duration: _program.duration,
        );
      await tester.pumpWidget(
        UiFixture(
          controller: controller,
          player: player,
          guideClock: () => _now,
        ).build(),
      );
      await tester.pumpAndSettle();

      if (route != 'Guide') {
        await openDestination(tester, 'Player');
        await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
        await tester.pumpAndSettle();
        final playback = tester
            .widget<PlayerView>(find.byType(PlayerView))
            .controller;
        expect(playback.overlay, PlayerOverlay.nowPlaying);
        if (route == 'Settings') {
          await tester.sendKeyEvent(LogicalKeyboardKey.f3);
          await tester.pumpAndSettle();
          expect(playback.overlay, PlayerOverlay.nowPlaying);
        }
      }
      final before = List<String>.of(player.commands);
      final generation = player.generation;
      await tester.tap(
        route == 'Settings'
            ? find.byKey(const Key('settings-app-menu'))
            : find.byTooltip(
                route == 'Player' ? 'Lineup menu' : 'Open Lineup menu',
              ),
      );
      await tester.pumpAndSettle();
      final action = find.byKey(const Key('app-menu-now-playing'));
      expect(action, findsOneWidget);
      final semantics = find.bySemanticsLabel(
        'Now Playing, Channel ${_channel.number}, ${_channel.name}, ${_program.title}',
      );
      expect(semantics, findsOneWidget);
      expect(
        tester
            .getSemantics(semantics)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(
        find.descendant(of: action, matching: find.text(_program.title)),
        findsOneWidget,
      );
      final identity = find.descendant(
        of: action,
        matching: find.byType(ChannelIdentity),
      );
      expect(
        tester.getBottomLeft(identity).dy,
        lessThanOrEqualTo(
          tester
              .getTopLeft(
                find.descendant(
                  of: action,
                  matching: find.text(_program.title),
                ),
              )
              .dy,
        ),
      );
      expect(
        tester.getTopLeft(action).dy,
        lessThan(tester.getTopLeft(find.text('Guide').last).dy),
      );
      await tester.tap(action);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('immersive-app-menu')), findsNothing);
      final view = tester.widget<PlayerView>(find.byType(PlayerView));
      expect(view.controller.overlay, PlayerOverlay.none);
      expect(view.focusNode!.hasFocus, isTrue);
      expect(controller.currentChannelId, _channel.id);
      expect(player.commands, before);
      expect(player.generation, generation);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.pumpAndSettle();
      expect(view.controller.overlay, PlayerOverlay.nowPlaying);
      expect(find.byType(PlayerView), findsOneWidget);
      expect(player.commands, before);
      await tester.pumpWidget(const SizedBox.shrink());
    }, semanticsEnabled: true);
  }

  for (final overlay in [
    PlayerOverlay.subtitleTracks,
    PlayerOverlay.programInfo,
  ]) {
    testWidgets('TV tuned row exits $overlay and Menu dismissal preserves it', (
      tester,
    ) async {
      _setViewport(tester, const Size(1920, 1080));
      final controller = _AuditController(
        scenario: LineupScenario(
          stage: SetupStage.ready,
          channels: [_channel],
          currentChannelId: _channel.id,
        ),
      );
      final player = _CountingPlayer()
        ..emit(
          const PlayerStatus(state: PlayerState.playing, message: 'Playing'),
          duration: _program.duration,
        );
      await tester.pumpWidget(
        UiFixture(
          controller: controller,
          player: player,
          profile: tvProfile,
          guideClock: () => _now,
        ).build(),
      );
      await tester.pumpAndSettle();
      await openDestination(tester, 'Player');
      final view = tester.widget<PlayerView>(find.byType(PlayerView));
      final playback = view.controller;
      await tester.sendKeyEvent(LogicalKeyboardKey.info);
      await tester.pumpAndSettle();
      expect(playback.overlay, PlayerOverlay.nowPlaying);
      if (overlay == PlayerOverlay.subtitleTracks) {
        playback.showTracks(PlayerTrackType.subtitle);
      } else {
        playback.showProgramInfo();
      }
      await tester.pumpAndSettle();
      expect(playback.overlay, overlay);

      final before = List<String>.of(player.commands);
      final generation = player.generation;
      final menu = find.byKey(const Key('immersive-app-menu'));
      Future<void> key(LogicalKeyboardKey key) async {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }

      await key(LogicalKeyboardKey.contextMenu);
      expect(menu, findsOneWidget);
      await key(LogicalKeyboardKey.contextMenu);
      expect(menu, findsNothing);
      expect(playback.overlay, overlay);

      await key(LogicalKeyboardKey.contextMenu);
      await key(LogicalKeyboardKey.arrowUp);
      await key(LogicalKeyboardKey.select);
      expect(menu, findsNothing);
      expect(playback.overlay, PlayerOverlay.none);
      expect(view.focusNode!.hasPrimaryFocus, isTrue);
      expect(player.commands, before);
      expect(player.generation, generation);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('classic-guide')), findsOneWidget);
      expect(player.commands, before);
      await tester.pumpWidget(const SizedBox.shrink());
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets('Tuned row honors cancellation and stale Studio leave', (
    tester,
  ) async {
    _setViewport(tester, const Size(1280, 720));
    final controller = _AuditController(
      scenario: LineupScenario(
        stage: SetupStage.ready,
        channels: [_channel],
        currentChannelId: _channel.id,
      ),
    );
    final player = _CountingPlayer()
      ..emit(
        const PlayerStatus(state: PlayerState.playing, message: 'Playing'),
      );
    await tester.pumpWidget(
      UiFixture(
        controller: controller,
        player: player,
        guideClock: () => _now,
      ).build(),
    );
    await tester.pumpAndSettle();
    await openDestination(tester, 'Player');
    final playback = tester
        .widget<PlayerView>(find.byType(PlayerView))
        .controller;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.pumpAndSettle();
    expect(playback.overlay, PlayerOverlay.nowPlaying);
    await tester.tap(find.byTooltip('Lineup menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage channels'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open Audit channel'));
    await tester.pumpAndSettle();
    final name = find.byKey(const Key('studio-name'));
    await tester.enterText(name, 'Synthetic unsaved name');
    final commands = List<String>.of(player.commands);
    await tester.tap(find.byTooltip('Open Lineup menu'));
    await tester.pumpAndSettle();
    final tunedRow = find.byKey(const Key('app-menu-now-playing'));
    await tester.tap(tunedRow);
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    expect(playback.overlay, PlayerOverlay.nowPlaying);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(name, findsOneWidget);
    expect(playback.overlay, PlayerOverlay.nowPlaying);
    expect(player.commands, commands);

    await tester.tap(tunedRow);
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    controller.fixtureActor.publishInventory();
    await tester.pump();
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerView), findsNothing);
    expect(find.byKey(const Key('channels-app-menu')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final hasPlayback in [false, true]) {
    testWidgets(
      'Now Playing is absent without program metadata (playback: $hasPlayback)',
      (tester) async {
        _setViewport(tester, const Size(1280, 720));
        final controller = _AuditController(
          scenario: LineupScenario(stage: SetupStage.ready),
        );
        final player = _CountingPlayer();
        if (hasPlayback) {
          player.emit(
            const PlayerStatus(state: PlayerState.playing, message: 'Playing'),
          );
        }
        await tester.pumpWidget(
          UiFixture(
            controller: controller,
            player: player,
            guideClock: () => _now,
          ).build(),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Open Lineup menu'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('app-menu-now-playing')), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final size in const [
    Size(1280, 720),
    Size(1920, 1080),
    Size(2560, 1440),
    Size(3840, 2160),
  ]) {
    testWidgets('review footer actions align at $size and preserve choices', (
      tester,
    ) async {
      _setViewport(tester, size);
      final controller = _AuditController(
        scenario: LineupScenario(
          stage: SetupStage.channelSetup,
          libraries: const [
            PlexLibrary(
              id: 'movies',
              title: 'Movies',
              type: PlexLibraryType.movie,
            ),
          ],
        ),
      );
      await tester.pumpWidget(UiFixture(controller: controller).build());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('scan-selected-libraries')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('review-channels')));
      await tester.pumpAndSettle();

      final back = find.byKey(const ValueKey('back-to-configure'));
      final create = find.byKey(const ValueKey('apply-reviewed-lineup'));
      expect(back, findsOneWidget);
      expect(create, findsOneWidget);
      expect(find.text('Create lineup'), findsOneWidget);
      expect(
        tester.getRect(back).center.dy,
        closeTo(tester.getRect(create).center.dy, 0.1),
      );
      expect(
        tester.getSize(back).height,
        closeTo(tester.getSize(create).height, 0.1),
      );
      expect(tester.takeException(), isNull);

      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('review-channels')), findsOneWidget);
      expect(controller.selectedLibraryIds, {'movies'});
      expect(controller.channels, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _AuditController extends FixtureController {
  _AuditController({super.scenario});

  Set<String> _readyIds = const {};
  Map<String, LibraryScanFact> _facts = const {};

  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) async =>
      buildChannelSchedule(channel, (channel.source as ManualSource).items);

  @override
  Set<String> get libraryScanReadyIds => _readyIds;
  @override
  Set<String> get libraryScanRetryIds => const {};
  @override
  Map<String, LibraryScanFact> get libraryScanFacts => _facts;

  @override
  Future<bool> scanLibraries(
    Set<String> ids, {
    bool retryFailedOnly = false,
  }) async {
    fixtureActor.publishInventory(
      media: [
        for (var index = 0; index < 12; index++)
          PlexMediaItem(
            id: 'movie-$index',
            title: 'Movie $index',
            type: 'movie',
            duration: const Duration(minutes: 90),
            libraryId: 'movies',
            parts: [PlexMediaPart(path: '/parts/movie-$index')],
            genres: const ['Drama'],
          ),
      ],
    );
    _readyIds = Set.unmodifiable(ids);
    _facts = {
      for (final id in ids)
        id: const LibraryScanFact(
          status: LibraryScanStatus.complete,
          completedPages: 1,
          completedItems: 12,
          totalItems: 12,
        ),
    };
    fixtureActor.reportScan(status: LibraryScanStatus.complete);
    notifyListeners();
    return true;
  }

  @override
  Future<bool> commitLibraryScan(Set<String> readyIds) async {
    fixtureActor.publishInventory(
      selectedLibraryIds: Set.unmodifiable(readyIds),
    );
    return true;
  }
}

class _CountingPlayer extends FixturePlayer {
  final List<String> commands = [];

  @override
  Future<void> load(
    Uri media, {
    String? plexToken,
    int? generation,
    bool startPaused = false,
    Duration? startPosition,
    LoadKind kind = LoadKind.direct,
    NativeSessionPlaylist? sessionPlaylist,
  }) async {
    commands.add('load');
    await super.load(media, plexToken: plexToken, generation: generation);
  }

  @override
  Future<void> play() async => commands.add('play');
  @override
  Future<void> pause() async => commands.add('pause');
  @override
  Future<void> seek(
    Duration position, {
    SeekMode mode = SeekMode.exact,
  }) async => commands.add('seek');
  @override
  Future<void> stop() async => commands.add('stop');
  @override
  Future<void> setFullscreen(bool fullscreen) async =>
      commands.add('fullscreen');
  @override
  Future<void> selectTrack(PlayerTrackType type, int? id) async =>
      commands.add('track');
}
