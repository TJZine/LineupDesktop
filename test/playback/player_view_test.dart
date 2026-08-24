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
    for (final key in [
      LogicalKeyboardKey.keyF,
      LogicalKeyboardKey.f11,
      LogicalKeyboardKey.keyJ,
      LogicalKeyboardKey.keyK,
      LogicalKeyboardKey.keyL,
      LogicalKeyboardKey.mediaPlayPause,
    ]) {
      await tester.sendKeyEvent(key);
    }
    expect(fixture.native.transportCommands, 0);
    expect(fixture.native.fullscreenValues, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('edge-triggered player shortcuts ignore repeat events', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyI);
    expect(fixture.player.overlay, PlayerOverlay.osd);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.f11);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.f11);
    await tester.pump();
    expect(fixture.native.fullscreenValues, [true]);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyS);
    expect(fixture.player.sleepDuration, const Duration(minutes: 30));

    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f11);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('documented player shortcut aliases reach their public actions', (
    tester,
  ) async {
    final fixture = _Fixture(
      PlayerState.playing,
      tracks: const [
        PlayerTrack(id: 1, type: PlayerTrackType.audio, selected: true),
        PlayerTrack(id: 2, type: PlayerTrackType.subtitle, selected: false),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );

    for (final key in [
      LogicalKeyboardKey.keyJ,
      LogicalKeyboardKey.keyK,
      LogicalKeyboardKey.keyL,
      LogicalKeyboardKey.mediaPlayPause,
    ]) {
      await tester.sendKeyEvent(key);
    }
    expect(fixture.native.transportCommands, 4);

    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    expect(fixture.native.fullscreenValues, [true]);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    expect(fixture.player.sleepDuration, const Duration(minutes: 30));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(fixture.player.overlay, PlayerOverlay.audioTracks);
    fixture.player.closeOverlay();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    expect(fixture.player.overlay, PlayerOverlay.subtitleTracks);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('media Stop reports failures without an unhandled error', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing, failStop: true);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.mediaStop);
    await tester.pump();

    expect(fixture.player.overlay, PlayerOverlay.error);
    expect(
      fixture.player.error,
      'Playback could not be stopped. Retry or choose another channel.',
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('numpad Enter commits channel entry', (tester) async {
    final fixture = _Fixture(PlayerState.playing, channelCount: 2);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.digit8);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await tester.pump();

    expect(fixture.lineup.currentChannelId, 'channel-1');
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('non-OSD overlays guard transport shortcuts', (tester) async {
    final fixture = _Fixture(PlayerState.playing);
    var guideOpened = false;
    fixture.player.showMiniGuide();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(
          controller: fixture.player,
          openGuide: () => guideOpened = true,
        ),
      ),
    );

    for (final key in [
      LogicalKeyboardKey.keyJ,
      LogicalKeyboardKey.keyK,
      LogicalKeyboardKey.mediaPlayPause,
    ]) {
      await tester.sendKeyEvent(key);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);

    expect(fixture.native.transportCommands, 0);
    expect(guideOpened, isTrue);
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

  testWidgets('player errors remain named live regions', (tester) async {
    final fixture = _Fixture(PlayerState.playing, failLoad: true);
    await fixture.player.loadInitialMedia(Uri.parse('lineup-test://failure'));
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );

    final errorSemantics = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'Playback error',
      ),
    );
    expect(errorSemantics.properties.liveRegion, isTrue);

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
    final tuning = fixture.player.tune('channel');
    await tester.pump();
    await fixture.native.loadStarted.future;

    await tester.pumpWidget(
      MaterialApp(home: PlayerSurface(controller: fixture.player)),
    );

    expect(find.bySemanticsLabel('Preparing playback'), findsOneWidget);
    expect(find.bySemanticsLabel('Buffering playback'), findsNothing);

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

    guideOpened = false;
    fixture.player.closeOverlay();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    expect(guideOpened, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('core player keyboard controls work while the OSD is visible', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing);
    fixture.player.showOsd();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();

    expect(fixture.native.transportCommands, 2);
    expect(fixture.native.fullscreenValues, [true]);
    expect(fixture.player.overlay, PlayerOverlay.osd);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    expect(fixture.player.overlay, PlayerOverlay.none);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    expect(fixture.player.overlay, PlayerOverlay.osd);

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
      await tester.pump(const Duration(milliseconds: 350));
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
    final transitions = find.byType(AnimatedSwitcher);
    final switcher = tester.widget<AnimatedSwitcher>(transitions);
    expect(switcher.duration, const Duration(milliseconds: 350));
    expect(switcher.reverseDuration, const Duration(milliseconds: 350));
    expect(
      find.descendant(of: transitions, matching: find.byType(FadeTransition)),
      findsWidgets,
    );
    final slides = find.descendant(
      of: transitions,
      matching: find.byType(SlideTransition),
    );
    expect(slides, findsNothing);

    fixture.player.closeOverlay();
    await tester.pumpAndSettle();
    fixture.player.showOsd();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 175));
    expect(slides, findsOneWidget);
    expect(
      find.descendant(of: slides, matching: find.byType(FadeTransition)),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('Reduce Motion settles player overlays in one pump', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );

    fixture.player.showOsd();
    await tester.pump();

    final switcher = tester.widget<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher),
    );
    expect(switcher.duration, Duration.zero);
    expect(switcher.reverseDuration, Duration.zero);
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.bySemanticsLabel(RegExp('Playback controls')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets(
    'reopened OSD rejects outgoing focus loss and keeps focused semantics',
    (tester) async {
      final fixture = _Fixture(
        PlayerState.playing,
        overlayTimeout: const Duration(milliseconds: 100),
      );
      final rootFocus = FocusNode();
      addTearDown(rootFocus.dispose);
      final semantics = tester.ensureSemantics();
      fixture.player.showOsd();
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerView(
            controller: fixture.player,
            focusNode: rootFocus,
            openGuide: () {},
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(rootFocus.hasPrimaryFocus, isFalse);

      fixture.player.closeOverlay();
      await tester.pump();
      fixture.player.showOsd();
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      rootFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(fixture.player.overlay, PlayerOverlay.osd);
      expect(
        find.bySemanticsLabel(RegExp('Playback controls')),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Playback progress',
        ),
        findsOneWidget,
      );

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 99));
      expect(fixture.player.overlay, PlayerOverlay.osd);
      await tester.pump(const Duration(milliseconds: 2));
      expect(fixture.player.overlay, PlayerOverlay.none);

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
  );

  testWidgets('reopened mini Guide rejects outgoing descendant focus loss', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing);
    final rootFocus = FocusNode();
    addTearDown(rootFocus.dispose);
    fixture.player.showMiniGuide();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(
          controller: fixture.player,
          focusNode: rootFocus,
          openGuide: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(rootFocus.hasPrimaryFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(seconds: 9));
    expect(fixture.player.overlay, PlayerOverlay.miniGuide);

    fixture.player.closeOverlay();
    await tester.pump();
    fixture.player.showMiniGuide();
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    rootFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 8));

    expect(fixture.player.overlay, PlayerOverlay.miniGuide);
    expect(find.bySemanticsLabel(RegExp('Mini Guide')), findsOneWidget);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 7999));
    expect(fixture.player.overlay, PlayerOverlay.miniGuide);
    await tester.pump(const Duration(milliseconds: 2));
    expect(fixture.player.overlay, PlayerOverlay.none);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('pointer and root focus do not suspend a timed OSD', (
    tester,
  ) async {
    final fixture = _Fixture(
      PlayerState.playing,
      overlayTimeout: const Duration(milliseconds: 100),
    );
    final rootFocus = FocusNode();
    addTearDown(rootFocus.dispose);
    fixture.player.showOsd();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(
          controller: fixture.player,
          focusNode: rootFocus,
          openGuide: () {},
        ),
      ),
    );
    await tester.pump();
    rootFocus.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 101));

    expect(fixture.player.overlay, PlayerOverlay.none);

    fixture.player.showOsd();
    await tester.pump();
    await tester.tapAt(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 101));
    expect(fixture.player.overlay, PlayerOverlay.none);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('selected track rows receive initial focus', (tester) async {
    final fixture = _Fixture(
      PlayerState.playing,
      tracks: const [
        PlayerTrack(id: 1, type: PlayerTrackType.audio, selected: false),
        PlayerTrack(
          id: 2,
          type: PlayerTrackType.audio,
          selected: true,
          title: 'Selected audio',
        ),
        PlayerTrack(
          id: 3,
          type: PlayerTrackType.subtitle,
          selected: true,
          title: 'Selected subtitles',
        ),
      ],
    );
    fixture.player.showOsd();
    fixture.player.showTracks(PlayerTrackType.audio);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();
    expect(
      Focus.of(tester.element(find.text('Selected audio'))).hasFocus,
      isTrue,
    );
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Selected audio'))
          .selected,
      isTrue,
    );

    fixture.player.closeOverlay();
    fixture.player.showTracks(PlayerTrackType.subtitle);
    await tester.pump();
    expect(
      Focus.of(tester.element(find.text('Selected subtitles'))).hasFocus,
      isTrue,
    );
    expect(
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Selected subtitles'))
          .selected,
      isTrue,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('subtitle Off receives focus only when no track is selected', (
    tester,
  ) async {
    final fixture = _Fixture(
      PlayerState.playing,
      tracks: const [
        PlayerTrack(id: 3, type: PlayerTrackType.subtitle, selected: false),
      ],
    );
    fixture.player.showOsd();
    fixture.player.showTracks(PlayerTrackType.subtitle);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();
    expect(Focus.of(tester.element(find.text('Off'))).hasFocus, isTrue);
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, 'Off')).selected,
      isTrue,
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
      await tester.pumpAndSettle();

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

  testWidgets('A and C do not open unavailable track rails', (tester) async {
    final fixture = _Fixture(PlayerState.playing);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(fixture.player.overlay, PlayerOverlay.none);

    fixture.player.showOsd();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    expect(fixture.player.overlay, PlayerOverlay.osd);
    expect(find.byKey(const Key('playback-options-rail')), findsNothing);

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
    bool failStop = false,
    bool blockLoad = false,
    List<PlayerTrack> tracks = const [],
    int channelCount = 1,
    Duration? overlayTimeout,
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
      failStop: failStop,
      blockLoad: blockLoad,
      tracks: tracks,
    );
    player = PlayerCoordinator(
      player: native,
      lineup: lineup,
      guide: guide,
      overlayTimeout: overlayTimeout,
    );
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
      LineupPlaybackRequest.parts([
        LineupPlaybackPart(uri: Uri.parse('lineup-test://$itemId')),
      ]);
}

class _Native implements NativePlayer {
  _Native(
    PlayerState state, {
    this.failLoad = false,
    this.failStop = false,
    this.blockLoad = false,
    this.tracks = const [],
  }) : status = PlayerStatus(
         state: state,
         message: state == PlayerState.unsupported
             ? 'Playback is unavailable on macOS.'
             : 'Playing',
       );

  final bool failLoad;
  final bool failStop;
  final bool blockLoad;
  final loadStarted = Completer<void>();
  final _loadCompletion = Completer<void>();
  int transportCommands = 0;
  final fullscreenValues = <bool>[];

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
      if (!loadStarted.isCompleted) loadStarted.complete();
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
  Future<void> setFullscreen(bool fullscreen) async {
    fullscreenValues.add(fullscreen);
  }

  @override
  Future<void> selectTrack(PlayerTrackType type, int? id) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> stop() async {
    if (failStop) throw const PlayerUnavailable('Synthetic stop failure.');
  }

  @override
  Future<void> dispose() async {}
}

class _Store implements AppStore {
  @override
  Future<String> clientIdentifier() async => 'test';
  @override
  Future<AppStoreLoadResult> load() async =>
      const AppStoreLoadResult(PersistedState());
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
