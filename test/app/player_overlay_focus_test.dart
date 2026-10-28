import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_view.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/player_coordinator.dart';
import 'package:lineup_desktop/playback/player_view.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

import '../support/ui_fixture.dart';

void main() {
  for (final pointerCollapse in [true, false]) {
    testWidgets(
      '${pointerCollapse ? "pointer Close" : "Escape then hover"} preserves Player keys after OSD retirement',
      (tester) async {
        for (final key in [
          LogicalKeyboardKey.enter,
          LogicalKeyboardKey.escape,
          LogicalKeyboardKey.f2,
        ]) {
          final h = await _Harness.mount(tester);
          await h.restoreNowPlayingMenu();
          if (pointerCollapse) {
            await h.collapseWithPointer();
          } else {
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(h.player.overlay, PlayerOverlay.osd);
            // Keyboard focus suspends hide until subsequent pointer activity.
            await tester.pump(const Duration(seconds: 8));
            expect(h.player.overlay, PlayerOverlay.osd);
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
            );
            await mouse.addPointer(location: const Offset(100, 100));
            await mouse.moveTo(const Offset(150, 110));
            await tester.pump();
            await mouse.removePointer();
          }
          await h.waitForHide();
          await h.sendKey(key);
          await tester.pumpAndSettle();
          if (key == LogicalKeyboardKey.enter) {
            expect(h.player.overlay, PlayerOverlay.osd);
          } else {
            expect(h.player.overlay, PlayerOverlay.fullGuide);
            expect(find.byType(GuideView), findsOneWidget);
          }
          await h.close();
        }
      },
      semanticsEnabled: true,
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets(
    'OSD retirement keeps an open menu focused',
    (tester) async {
      final h = await _Harness.mount(tester);
      await h.restoreNowPlayingMenu();
      await h.collapseWithPointer();
      await tester.tap(find.byTooltip('Lineup menu'));
      await tester.pumpAndSettle();
      final menu = find.byKey(const Key('immersive-app-menu'));
      expect(menu, findsOneWidget);
      final menuFocus = FocusManager.instance.primaryFocus;
      expect(h.rootFocus.hasFocus, isFalse);
      await h.waitForHide();
      expect(menu, findsOneWidget);
      expect(FocusManager.instance.primaryFocus, same(menuFocus));
      expect(h.rootFocus.hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(menu, findsNothing);
      await h.close();
    },
    semanticsEnabled: true,
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'OSD retirement preserves dialog focus and restores Player keys on return',
    (tester) async {
      final h = await _Harness.mount(tester);
      await h.restoreNowPlayingMenu();
      await h.collapseWithPointer();
      final dialog = showDialog<void>(
        context: tester.element(find.byType(PlayerView)),
        builder: (context) => AlertDialog(
          title: const Text('Keep dialog focus'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Dismiss'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        ModalRoute.of(tester.element(find.byType(PlayerView)))!.isCurrent,
        isFalse,
      );
      final dialogFocus = FocusManager.instance.primaryFocus;
      expect(h.rootFocus.hasFocus, isFalse);
      await h.waitForHide();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(FocusManager.instance.primaryFocus, same(dialogFocus));
      expect(h.rootFocus.hasFocus, isFalse);
      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();
      await dialog;
      await h.sendKey(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(h.player.overlay, PlayerOverlay.osd);
      await h.close();
    },
    semanticsEnabled: true,
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final menuRestored in [true, false]) {
    testWidgets(
      'inactive hide does not steal focus and resume restores Player keys after ${menuRestored ? "menu" : "Tab"} focus',
      (tester) async {
        final h = await _Harness.mount(tester);
        if (menuRestored) {
          await h.restoreNowPlayingMenu();
        } else {
          await h.focusNowPlayingMenuWithTab();
        }
        await h.collapseWithPointer();
        expect(h.rootFocus.hasFocus, isTrue);
        expect(h.rootFocus.hasPrimaryFocus, isFalse);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        addTearDown(
          () => tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          ),
        );
        await tester.pump();
        await h.waitForHide();
        expect(h.rootFocus.hasPrimaryFocus, isFalse);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        await h.sendKey(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(h.player.overlay, PlayerOverlay.osd);
        await h.close();
      },
      semanticsEnabled: true,
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets(
    'channel digits and subsequent commands survive focused OSD retirement',
    (tester) async {
      final h = await _Harness.mount(tester);
      await h.restoreNowPlayingMenu();
      await h.sendKey(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(h.player.overlay, PlayerOverlay.osd);
      await h.sendKey(LogicalKeyboardKey.digit8);
      await tester.pump();
      // Advance one delayed frame across retirement before the next key.
      // This fake-time boundary is separate from native event/frame pacing.
      await tester.pump(const Duration(milliseconds: 500));
      expect(h.player.overlay, PlayerOverlay.channelNumber);
      await h.sendKey(LogicalKeyboardKey.digit9);
      await tester.pump();
      expect(h.player.channelNumber, '89');
      // Neither 8 nor 89 exists in this fixture: expiry closes the buffer.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(h.player.channelNumber, isEmpty);
      expect(h.player.overlay, PlayerOverlay.none);
      await h.sendKey(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      expect(find.byType(GuideView), findsOneWidget);
      await h.close();
    },
    semanticsEnabled: true,
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'keyboard MiniGuide retains Escape and F2 routing after focused OSD retirement',
    (tester) async {
      for (final key in [LogicalKeyboardKey.escape, LogicalKeyboardKey.f2]) {
        final h = await _Harness.mount(tester);
        await h.restoreNowPlayingMenu();
        await h.sendKey(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(h.player.overlay, PlayerOverlay.osd);
        await h.sendKey(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(h.player.overlay, PlayerOverlay.miniGuide);
        await h.sendKey(key);
        await tester.pumpAndSettle();
        expect(
          h.player.overlay,
          key == LogicalKeyboardKey.escape
              ? PlayerOverlay.none
              : PlayerOverlay.fullGuide,
        );
        if (key == LogicalKeyboardKey.f2) {
          expect(find.byType(GuideView), findsOneWidget);
        }
        await h.close();
      }
    },
    semanticsEnabled: true,
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'playback error retires focused controls without losing supported Escape',
    (tester) async {
      final h = await _Harness.mount(tester);
      await h.restoreNowPlayingMenu();
      await h.collapseWithPointer();
      h.native.emit(
        const PlayerStatus(
          state: PlayerState.error,
          message: 'Synthetic failure',
          recoverable: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(h.player.overlay, PlayerOverlay.error);
      await h.sendKey(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(h.player.overlay, PlayerOverlay.none);
      await h.sendKey(LogicalKeyboardKey.escape);
      // The unavailable Guide picture animates continuously.
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(GuideView), findsOneWidget);
      await h.close();
    },
    semanticsEnabled: true,
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'programmatic NowPlaying retirement preserves active Player keyboard ownership',
    (tester) async {
      final h = await _Harness.mount(tester);
      await h.restoreNowPlayingMenu();
      // This controller path is intentionally programmatic, not a claimed key binding.
      h.player.closeOverlay();
      await tester.pumpAndSettle();
      expect(h.player.overlay, PlayerOverlay.none);
      await h.sendKey(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      expect(find.byType(GuideView), findsOneWidget);
      await h.close();
    },
    semanticsEnabled: true,
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}

class _Harness {
  _Harness(this.tester)
    : controller = _ScheduleController(),
      native = FixturePlayer()
        ..emit(
          const PlayerStatus(state: PlayerState.ready, message: 'Ready'),
          position: const Duration(minutes: 10),
          duration: const Duration(hours: 1),
        );
  final WidgetTester tester;
  final _ScheduleController controller;
  final FixturePlayer native;
  late final PlayerCoordinator player;
  FocusNode get rootFocus =>
      tester.widget<PlayerView>(find.byType(PlayerView)).focusNode!;
  bool _closed = false;

  static Future<_Harness> mount(WidgetTester tester) async {
    final h = _Harness(tester);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 632);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(h.close);
    final fixture = UiFixture(
      controller: h.controller,
      player: h.native,
      guideClock: () => _now,
    );
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    final guide = tester.widget<GuideView>(find.byType(GuideView));
    expect(await guide.controller.ensureCurrentProgram('channel'), isNotNull);
    // Exercise the actual Guide -> shell tune path and shell-owned coordinator.
    final tuning = guide.onTune('channel');
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tuning;
    h.player = tester.widget<PlayerView>(find.byType(PlayerView)).controller;
    h.native.emit(
      const PlayerStatus(state: PlayerState.playing, message: 'Playing'),
    );
    await tester.pumpAndSettle();
    expect(h.native.loads, isNotEmpty);
    expect(h.player.currentProgram, isNotNull);
    expect(h.controller.settings.dvrControlsEnabled, isTrue);
    return h;
  }

  Future<void> restoreNowPlayingMenu() async {
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.pumpAndSettle();
    expect(player.overlay, PlayerOverlay.nowPlaying);
    expect(
      find.byKey(const Key('player-now-playing-collapse')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Lineup menu'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('immersive-app-menu')), findsOneWidget);
    tester.view.physicalSize = const Size(1728, 1084);
    await tester.pumpAndSettle();
    expect(player.overlay, PlayerOverlay.nowPlaying);
    expect(find.byKey(const Key('immersive-app-menu')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('immersive-app-menu')), findsNothing);
    expect(player.overlay, PlayerOverlay.nowPlaying);
    tester.view.physicalSize = const Size(800, 632);
    await tester.pumpAndSettle();
    final menuButton = tester.widget<IconButton>(
      find.byKey(const Key('player-app-menu')),
    );
    expect(FocusManager.instance.primaryFocus, same(menuButton.focusNode));
  }

  Future<void> sendKey(LogicalKeyboardKey key) async {
    var delivered = false;
    bool observe(KeyEvent event) {
      if (event is KeyDownEvent && event.logicalKey == key) {
        delivered = true;
      }
      return false;
    }

    HardwareKeyboard.instance.addHandler(observe);
    try {
      await tester.sendKeyEvent(key);
    } finally {
      HardwareKeyboard.instance.removeHandler(observe);
    }
    expect(delivered, isTrue);
  }

  Future<void> focusNowPlayingMenuWithTab() async {
    await sendKey(LogicalKeyboardKey.keyI);
    await tester.pumpAndSettle();
    expect(player.overlay, PlayerOverlay.nowPlaying);
    final target = tester
        .widget<IconButton>(find.byKey(const Key('player-app-menu')))
        .focusNode;
    for (
      var i = 0;
      i < 40 && FocusManager.instance.primaryFocus != target;
      i++
    ) {
      await sendKey(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(FocusManager.instance.primaryFocus, same(target));
  }

  Future<void> collapseWithPointer() async {
    await tester.tap(find.byKey(const Key('player-now-playing-collapse')));
    await tester.pumpAndSettle();
    expect(player.overlay, PlayerOverlay.osd);
  }

  Future<void> waitForHide() async {
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(player.overlay, PlayerOverlay.none);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
    controller.dispose();
  }
}

final _now = DateTime(2026, 10, 19, 12);

class _ScheduleController extends FixtureController {
  _ScheduleController()
    : super(
        scenario: LineupScenario(
          stage: SetupStage.ready,
          currentChannelId: 'channel',
          settings: const LineupSettings(dvrControlsEnabled: true),
          channels: [
            Channel(
              id: 'channel',
              number: 7,
              name: 'Synthetic channel',
              source: ManualSource([
                ChannelItem(
                  id: 'program',
                  title: 'Synthetic program',
                  duration: const Duration(hours: 24),
                ),
              ]),
              playbackMode: PlaybackMode.sequential,
              anchor: _now.subtract(const Duration(hours: 1)),
              shuffleSeed: 1,
            ),
          ],
        ),
      );

  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) async => buildSchedule(
    (channel.source as ManualSource).items,
    mode: channel.playbackMode,
    seed: channel.shuffleSeed,
  );

  @override
  LineupPlaybackRequest playbackFor(String itemId) =>
      LineupPlaybackRequest.parts([
        LineupPlaybackPart(uri: Uri.parse('lineup-test://$itemId')),
      ]);
}
