import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/diagnostics_view.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/app/settings_view.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/channel_filter.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/guide/guide_view.dart';
import 'package:lineup_desktop/guide/guide_playback_placeholder.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/player_view.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

import '../support/ui_fixture.dart';

final _now = DateTime.utc(2026, 11, 15, 16, 7);

void main() {
  for (final tv in [false, true]) {
    testWidgets(
      'Diagnostics Details and Support keep their origins (TV: $tv)',
      (tester) async {
        final fixture = await _pumpShell(tester, tv: tv);
        await _tune(tester, 'three');
        _fail(fixture, known: true);
        await tester.pumpAndSettle();

        Future<void> back() async {
          if (tv) {
            await tester.binding.handlePopRoute();
          } else {
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          }
          await tester.pumpAndSettle();
        }

        if (tv) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
        } else {
          await tester.tap(find.text('Details'));
        }
        await tester.pumpAndSettle();
        expect(find.byType(DiagnosticsView), findsOneWidget);
        final playerLink = find.text('‹ Back to Player');
        expect(playerLink, findsOneWidget);
        await back();
        expect(find.byType(PlayerView), findsOneWidget);
        // Reopen the error presentation to exercise its link as well as Back.
        await tester
            .widget<PlayerView>(find.byType(PlayerView))
            .controller
            .retry();
        await tester.pump();
        _fail(fixture, known: true);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Details'));
        await tester.pumpAndSettle();
        await tester.tap(playerLink);
        await tester.pumpAndSettle();
        expect(find.byType(PlayerView), findsOneWidget);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(find.byType(SettingsView), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Support'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Open Diagnostics'));
        await tester.tap(find.text('Open Diagnostics'));
        await tester.pumpAndSettle();
        expect(find.text('‹ Settings · Support'), findsOneWidget);
        await back();
        expect(
          tester.widget<SettingsView>(find.byType(SettingsView)).category,
          SettingsCategory.support,
        );
      },
    );
  }

  for (final tv in [false, true]) {
    testWidgets(
      'Player Diagnostics returns to Guide when playback is gone (TV: $tv)',
      (tester) async {
        final fixture = await _pumpShell(tester, tv: tv);
        await _tune(tester, 'three');
        _fail(fixture, known: true);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Details'));
        await tester.pumpAndSettle();
        expect(find.text('‹ Back to Player'), findsOneWidget);

        fixture.controller.fixtureActor.replaceChannels([
          for (final channel in fixture.controller.channels)
            if (channel.id != 'three') channel,
        ]);
        await tester.pumpAndSettle();
        final guideLink = find.text('‹ Back to Guide');
        expect(guideLink, findsOneWidget);
        expect(find.text('‹ Back to Player'), findsNothing);
        if (tv) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(guideLink);
        }
        await tester.pumpAndSettle();
        final guide = tester.widget<GuideView>(find.byType(GuideView));
        expect(find.byType(PlayerView), findsNothing);
        if (tv) {
          // TV Home has no in-app parent.
          expect(guide.onBack!(), isFalse);
        }
      },
    );
  }

  testWidgets('A single visible failed channel has no Next focus target', (
    tester,
  ) async {
    final fixture = await _pumpShell(tester, tv: true);
    final guide = _guide(tester);
    await _tune(tester, 'one');
    _fail(fixture, known: true, recoverable: false);
    await tester.pumpAndSettle();
    await _returnToGuide(tester);
    final next = find.widgetWithText(TextButton, 'Next channel');
    expect(next, findsOneWidget);
    guide.setSearchQuery('Synthetic one');
    await tester.pumpAndSettle();
    expect(guide.channels.single.id, 'one');
    expect(next, findsNothing);
    expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
    final filter = tester
        .widget<InkWell>(find.byKey(const Key('guide-channel-filter')))
        .focusNode!;
    filter.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<GuidePlaybackPlaceholder>(),
      isNull,
    );
    expect(fixture.player.loads, hasLength(1));
    guide.setSearchQuery('Synthetic three');
    await tester.pumpAndSettle();
    expect(next, findsOneWidget);
  });

  testWidgets('Guide failure Next tunes the filtered successor and wraps', (
    tester,
  ) async {
    final fixture = await _pumpShell(tester, tv: true);
    final guide = _guide(tester);
    guide.setChannelFilter(ChannelFilter.favourites);
    await tester.pumpAndSettle();
    await _tune(tester, 'three');
    expect(fixture.player.loads.single.path, startsWith('/three-'));
    _fail(fixture, known: true);
    await tester.pumpAndSettle();
    await _returnToGuide(tester);
    expect(find.text("Lineup can't reach your Plex server."), findsOneWidget);
    final next = find.text('Next channel');
    expect(next, findsOneWidget);

    final pendingNext = tester
        .widget<GuidePlaybackPlaceholder>(find.byType(GuidePlaybackPlaceholder))
        .onNextChannel!;
    guide.setSearchQuery('no matching channel');
    pendingNext();
    await tester.pumpAndSettle();
    expect(guide.channels, isEmpty);
    expect(fixture.player.loads, hasLength(1));
    guide.setSearchQuery('');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    final filter = tester
        .widget<InkWell>(find.byKey(const Key('guide-channel-filter')))
        .focusNode!;
    for (var step = 0; step < 8 && !filter.hasFocus; step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
    }
    expect(filter.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    final nextButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Next channel'),
    );
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<TextButton>(),
      same(nextButton),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    fixture.player.emit(
      const PlayerStatus(state: PlayerState.playing, message: 'Playing'),
    );
    await tester.pumpAndSettle();
    expect(fixture.player.loads, hasLength(2));
    expect(fixture.player.loads.last.path, startsWith('/one-'));
    expect(find.byType(PlayerView), findsOneWidget);

    _fail(fixture, known: false);
    await tester.pumpAndSettle();
    await _returnToGuide(tester);
    expect(find.text('Playback unavailable'), findsOneWidget);
    expect(
      find.text('Playback failed. Retry or choose another channel.'),
      findsNothing,
    );
    guide.setSearchQuery('Synthetic three');
    await tester.pumpAndSettle();
    await tester.tap(next);
    await tester.pump();
    fixture.player.emit(
      const PlayerStatus(state: PlayerState.playing, message: 'Playing'),
    );
    await tester.pumpAndSettle();
    expect(fixture.player.loads.last.path, startsWith('/three-'));
  });

  testWidgets('Guide retains the unsupported player message', (tester) async {
    final player = FixturePlayer()
      ..emit(
        const PlayerStatus(
          state: PlayerState.unsupported,
          message: 'Playback is unavailable on this platform.',
        ),
      );
    await _pumpShell(tester, tv: true, player: player);
    expect(find.text('Playback unavailable'), findsOneWidget);
    expect(
      find.text('Playback is unavailable on this platform.'),
      findsOneWidget,
    );
    expect(find.text('Next channel'), findsNothing);
  });

  testWidgets('Guide retains the authorization stop message and Retry', (
    tester,
  ) async {
    final player = _StopFailingFixturePlayer();
    final fixture = await _pumpShell(tester, tv: true, player: player);
    await _tune(tester, 'one');
    player.emit(
      const PlayerStatus(state: PlayerState.playing, message: 'Playing'),
    );
    await tester.pumpAndSettle();
    final coordinator = tester
        .widget<PlayerView>(find.byType(PlayerView))
        .controller;
    player.rejectStop = true;
    expect(await coordinator.logout(), isFalse);
    await tester.pumpAndSettle();
    expect(coordinator.failureCause, isNull);
    await _returnToGuide(tester);
    expect(fixture.controller.stage, SetupStage.ready);
    expect(
      find.text(
        'Playback could not be stopped. Retry or exit Lineup before continuing.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Next channel'), findsNothing);
  });

  testWidgets('TV idle preview survives background cleanup and resume', (
    tester,
  ) async {
    var now = _now;
    final fixture = await _pumpShell(tester, tv: true, clock: () => now);
    final guide = _guide(tester);
    final focused = guide.focusedProgramId;
    expect(focused, isNotNull);
    final artwork = find.byKey(const Key('guide-idle-backdrop'));
    expect(artwork, findsOneWidget);

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    now = now.add(const Duration(minutes: 4));
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(guide.focusedProgramId, focused);
    expect(fixture.player.loads, isEmpty);
    expect(fixture.player.stops, 0);
    expect(artwork, findsOneWidget);
  });

  for (final moveFocus in [false, true]) {
    testWidgets(
      'TV failed inspection survives an early return when focus stays (moved: $moveFocus)',
      (tester) async {
        var now = _now;
        final fixture = await _pumpShell(tester, tv: true, clock: () => now);
        final guide = _guide(tester);
        final attempted = guide.focusedProgram!;
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pump();
        _fail(fixture, known: true);
        await tester.pumpAndSettle();
        await _returnToGuide(tester);
        expect(guide.focusedProgramId, attempted.id);
        if (moveFocus) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          expect(guide.focusedChannelId, isNot(attempted.channelId));
          guide.focusProgram(attempted);
        }

        await openDestination(tester, 'Player');
        expect(find.byType(PlayerView), findsOneWidget);
        now = attempted.scheduled.end.add(const Duration(minutes: 1));
        final current = guide.currentProgram(attempted.channelId)!;
        expect(current.id, isNot(attempted.id));
        await _returnToGuide(tester);
        expect(guide.focusedChannelId, attempted.channelId);
        expect(guide.focusedProgramId, moveFocus ? attempted.id : current.id);
        expect(fixture.player.loads, hasLength(1));
      },
    );
  }

  for (final failed in [true, false]) {
    testWidgets(
      'TV Guide repairs only failed ended inspection (failed: $failed)',
      (tester) async {
        var now = _now;
        final fixture = await _pumpShell(tester, tv: true, clock: () => now);
        final guide = _guide(tester);
        final attempted = guide.focusedProgram!;
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pump();
        expect(fixture.player.loads, hasLength(1));
        if (failed) {
          _fail(fixture, known: false);
        } else {
          fixture.player.emit(
            const PlayerStatus(state: PlayerState.playing, message: 'Playing'),
          );
        }
        await tester.pumpAndSettle();
        now = attempted.scheduled.end.add(const Duration(minutes: 1));
        final current = guide.currentProgram(attempted.channelId)!;
        expect(current.id, isNot(attempted.id));
        await _returnToGuide(tester);
        expect(guide.focusedChannelId, attempted.channelId);
        expect(guide.focusedProgramId, failed ? current.id : attempted.id);
      },
    );
  }
}

GuideController _guide(WidgetTester tester) =>
    tester.widget<GuideView>(find.byType(GuideView)).controller;

Future<void> _tune(WidgetTester tester, String id) async {
  await tester.widget<GuideView>(find.byType(GuideView)).onTune(id);
  await tester.pump();
}

void _fail(UiFixture fixture, {required bool known, bool recoverable = true}) {
  fixture.player.emit(
    PlayerStatus(
      state: PlayerState.error,
      message: 'Synthetic playback error',
      recoverable: recoverable,
      failureCode: known ? 'network_error' : null,
    ),
    eventGeneration: fixture.player.generation,
  );
}

Future<void> _returnToGuide(WidgetTester tester) async {
  for (var i = 0; i < 2 && find.byType(GuideView).evaluate().isEmpty; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }
  expect(find.byType(GuideView), findsOneWidget);
}

Future<UiFixture> _pumpShell(
  WidgetTester tester, {
  required bool tv,
  DateTime Function()? clock,
  FixturePlayer? player,
}) async {
  tester.view
    ..physicalSize = const Size(1920, 1080)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final lineup = _ShellController();
  final fixture = UiFixture(
    controller: lineup,
    player: player,
    profile: profileFor(tv),
    guideClock: clock ?? () => _now,
  );
  addTearDown(lineup.dispose);
  await tester.pumpWidget(fixture.build());
  await tester.pumpAndSettle();
  return fixture;
}

class _ShellController extends FixtureController {
  _ShellController()
    : super(
        scenario: LineupScenario(
          stage: SetupStage.ready,
          settings: const LineupSettings(reduceMotion: true),
          channels: [
            for (final (index, id) in ['one', 'two', 'three', 'four'].indexed)
              Channel(
                id: id,
                name: 'Synthetic $id',
                number: index + 1,
                favorite: index.isEven,
                source: ManualSource([
                  for (var i = 0; i < 3; i++)
                    ChannelItem(
                      id: '$id-$i',
                      title: 'Synthetic program $i',
                      duration: const Duration(minutes: 24),
                      backdrop: Uri.parse('https://synthetic.invalid/backdrop'),
                    ),
                ]),
                playbackMode: PlaybackMode.sequential,
                anchor: _now.subtract(const Duration(minutes: 6)),
                shuffleSeed: index,
              ),
          ],
        ),
      );

  static final _artwork = File('assets/branding/lineup-logo-mark.png')
      .readAsBytesSync();

  @override
  Future<Uint8List?> artworkForPath(
    Uri path, {
    int? width,
    int? height,
  }) async => _artwork;

  @override
  Future<Uint8List?> programArtworkForPath(
    Uri path, {
    required int width,
    required int height,
  }) async => _artwork;

  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) async =>
      buildChannelSchedule(channel, (channel.source as ManualSource).items);

  @override
  LineupPlaybackRequest playbackFor(String itemId) =>
      LineupPlaybackRequest.parts([
        LineupPlaybackPart(
          uri: Uri.https('synthetic.invalid', '/$itemId'),
          duration: const Duration(minutes: 24),
        ),
      ]);
}

class _StopFailingFixturePlayer extends FixturePlayer {
  bool rejectStop = false;

  @override
  Future<void> stop() async {
    if (rejectStop) throw const PlayerUnavailable('Synthetic stop error');
    await super.stop();
  }
}
