import 'dart:async';
import 'dart:convert';

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

final _fixtureArtwork = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

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
    expect(fixture.player.overlay, PlayerOverlay.nowPlaying);

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
    expect(fixture.player.overlay, PlayerOverlay.nowPlaying);
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
    await tester.pump(const Duration(milliseconds: 1));
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

  testWidgets('rich Now Playing renders metadata, artwork, and one surface', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing, richProgram: true);
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1280, 720)),
          child: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      ),
    );
    await tester.pump();

    expect(fixture.lineup.settings.preferClearLogos, isTrue);
    fixture.player.showNowPlaying();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('player-now-playing-surface')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('player-now-playing-surface'))),
      const Size(1280, 720),
    );
    expect(
      MediaQuery.sizeOf(
        tester.element(find.byKey(const Key('player-now-playing-surface'))),
      ),
      const Size(1280, 720),
    );
    expect(fixture.lineup.artworkRequests, hasLength(3));
    expect(find.byType(Image), findsNWidgets(3));
    expect(find.byKey(const Key('player-now-playing-logo')), findsOneWidget);
    expect(find.text('Season 2 • Episode 6'), findsOneWidget);
    expect(
      find.text('A synthetic synopsis for deterministic tests.'),
      findsOneWidget,
    );
    expect(find.text('TV-14'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        RegExp(r'^Now playing\. Channel 7, Channel\..*Program'),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'\b\d+ percent complete\b')),
      findsOneWidget,
    );

    fixture.player.showOsd();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.bySemanticsLabel(RegExp(r'^Now playing\.')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Playback controls')), findsOneWidget);

    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('Now Playing input replaces the surface and still executes', (
    tester,
  ) async {
    final fixture = _Fixture(
      PlayerState.playing,
      richProgram: true,
      tracks: const [
        PlayerTrack(id: 1, type: PlayerTrackType.audio, selected: true),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    expect(fixture.player.overlay, PlayerOverlay.nowPlaying);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(fixture.native.transportCommands, 1);
    expect(fixture.player.overlay, PlayerOverlay.osd);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(fixture.player.overlay, PlayerOverlay.audioTracks);

    fixture.player.closeOverlay();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.tapAt(const Offset(5, 5));
    expect(fixture.player.overlay, PlayerOverlay.osd);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('compact layout drops artwork and disabled logos skip fetching', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing, richProgram: true);
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();

    fixture.player.showNowPlaying();
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('player-now-playing-title')), findsOneWidget);
    expect(find.byKey(const Key('player-now-playing-logo')), findsNothing);
    expect(fixture.lineup.artworkRequests, isEmpty);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();

    final disabled = _Fixture(
      PlayerState.playing,
      richProgram: true,
      preferClearLogos: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1280, 720)),
          child: PlayerView(controller: disabled.player, openGuide: () {}),
        ),
      ),
    );
    await tester.pump();
    disabled.player.showNowPlaying();
    await tester.pumpAndSettle();

    expect(disabled.lineup.artworkRequests, hasLength(2));
    expect(
      disabled.lineup.artworkRequests,
      isNot(contains(Uri.parse('test://logo'))),
    );
    expect(find.byKey(const Key('player-now-playing-logo')), findsNothing);
    expect(find.byKey(const Key('player-now-playing-title')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    disabled.dispose();
  });

  testWidgets('Guide clock replacement updates the visible current program', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 1, 1, 12);
    final fixture = _Fixture(
      PlayerState.playing,
      shortPrograms: true,
      guideClock: () => now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();
    fixture.player.showNowPlaying();
    await tester.pump();
    expect(find.text('Program'), findsOneWidget);

    now = now.add(const Duration(hours: 1));
    fixture.guide.playToNow();
    await tester.pump();

    expect(fixture.player.overlay, PlayerOverlay.nowPlaying);
    expect(find.text('Replacement Program'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('same program ID with a new path rejects stale artwork', (
    tester,
  ) async {
    final fixture = _Fixture(
      PlayerState.playing,
      richProgram: true,
      blockArtwork: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1280, 720)),
          child: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      ),
    );
    await tester.pump();
    fixture.player.showNowPlaying();
    await tester.pump();
    expect(fixture.lineup.artworkRequests, hasLength(3));

    fixture.lineup.replaceArtwork('-replacement');
    expect(fixture.player.overlay, PlayerOverlay.none);
    fixture.guide.requestViewport(0, 1);
    await tester.pump();
    await tester.pump();
    fixture.player.showNowPlaying();
    await tester.pump();

    for (final entry in fixture.lineup.artworkCompletions.entries.where(
      (entry) => !entry.key.toString().contains('replacement'),
    )) {
      entry.value.complete(_fixtureArtwork);
    }
    await tester.pump();

    expect(find.byKey(const Key('player-now-playing-logo')), findsNothing);
    expect(find.byKey(const Key('player-now-playing-title')), findsOneWidget);

    expect(
      fixture.lineup.artworkRequests.map((path) => path.toString()),
      containsAll([
        'test://poster-replacement',
        'test://backdrop-replacement',
        'test://logo-replacement',
      ]),
    );
    for (final entry in fixture.lineup.artworkCompletions.entries.where(
      (entry) => entry.key.toString().contains('replacement'),
    )) {
      entry.value.complete(_fixtureArtwork);
    }
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('content generation retires and refetches Now Playing artwork', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing, richProgram: true);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1280, 720)),
          child: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      ),
    );
    await tester.pump();
    fixture.player.showNowPlaying();
    await tester.pumpAndSettle();
    expect(fixture.lineup.artworkRequests, hasLength(3));

    fixture.lineup.bumpContentGeneration();
    await tester.pump();
    expect(fixture.player.overlay, PlayerOverlay.none);
    fixture.guide.requestViewport(0, 1);
    await tester.pump();
    await tester.pump();
    fixture.player.showNowPlaying();
    await tester.pumpAndSettle();

    expect(fixture.lineup.artworkRequests, hasLength(6));
    expect(find.byKey(const Key('player-now-playing-logo')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets(
    'artwork failure falls back and cached failure is not refetched',
    (tester) async {
      final fixture = _Fixture(
        PlayerState.playing,
        richProgram: true,
        failArtwork: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(1280, 720)),
            child: PlayerView(controller: fixture.player, openGuide: () {}),
          ),
        ),
      );
      await tester.pump();
      fixture.player.showNowPlaying();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('player-now-playing-logo')), findsNothing);
      expect(find.byKey(const Key('player-now-playing-title')), findsOneWidget);
      expect(fixture.lineup.artworkRequests, hasLength(3));

      fixture.player.closeOverlay();
      fixture.player.showNowPlaying();
      await tester.pumpAndSettle();
      expect(fixture.lineup.artworkRequests, hasLength(3));

      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
  );

  testWidgets('Now Playing reflows from 800x600 through 4K', (tester) async {
    final fixture = _Fixture(PlayerState.playing, richProgram: true);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    for (final size in const [
      Size(800, 600),
      Size(LineupLayout.compact - 1, 700),
      Size(LineupLayout.compact, 700),
      Size(1280, 720),
      Size(1920, 1080),
      Size(3840, 2160),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pump();
      fixture.player.showNowPlaying();
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byKey(const Key('player-now-playing-surface'))),
        size,
      );
      expect(tester.takeException(), isNull, reason: '$size');
    }

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('Reduce Motion settles Now Playing in one pump', (tester) async {
    final fixture = _Fixture(PlayerState.playing, richProgram: true);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();

    fixture.player.showNowPlaying();
    await tester.pump();

    final switcher = tester.widget<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher),
    );
    expect(switcher.duration, Duration.zero);
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.byKey(const Key('player-now-playing-surface')), findsOneWidget);

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
    bool richProgram = false,
    bool preferClearLogos = true,
    bool failArtwork = false,
    bool blockArtwork = false,
    bool shortPrograms = false,
    DateTime Function()? guideClock,
  }) {
    lineup = _Lineup(
      channelCount,
      richProgram: richProgram,
      preferClearLogos: preferClearLogos,
      failArtwork: failArtwork,
      blockArtwork: blockArtwork,
      shortPrograms: shortPrograms,
      anchorNow: guideClock?.call(),
    );
    guide = GuideController(
      lineup: lineup,
      clock: guideClock,
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
  _Lineup(
    int channelCount, {
    bool richProgram = false,
    bool preferClearLogos = true,
    this.failArtwork = false,
    this.blockArtwork = false,
    bool shortPrograms = false,
    DateTime? anchorNow,
  }) : super(
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
          _fixtureItem(
            index,
            rich: richProgram,
            duration: shortPrograms
                ? const Duration(hours: 1)
                : const Duration(hours: 24),
          ),
          if (shortPrograms)
            _fixtureItem(
              index,
              rich: richProgram,
              suffix: '-next',
              duration: const Duration(hours: 1),
            ),
        ]),
        playbackMode: PlaybackMode.sequential,
        anchor: (anchorNow ?? DateTime.now()).subtract(
          shortPrograms
              ? const Duration(minutes: 30)
              : const Duration(hours: 1),
        ),
        shuffleSeed: index + 1,
      ),
      growable: false,
    );
    currentChannelId = 'channel';
    settings = LineupSettings(preferClearLogos: preferClearLogos);
    stage = SetupStage.ready;
  }

  final artworkRequests = <Uri>[];
  final bool failArtwork;
  final bool blockArtwork;
  final artworkCompletions = <Uri, Completer<Uint8List?>>{};
  int _contentGeneration = 0;

  @override
  int get contentGeneration => _contentGeneration;

  @override
  Future<Uint8List?> artworkForPath(Uri path) async {
    artworkRequests.add(path);
    if (failArtwork) return null;
    if (blockArtwork) {
      return (artworkCompletions[path] ??= Completer<Uint8List?>()).future;
    }
    return _fixtureArtwork;
  }

  void replaceArtwork(String tag, {bool bumpGeneration = false}) {
    final channel = channels.first;
    channels = [
      Channel(
        id: channel.id,
        number: channel.number,
        name: channel.name,
        source: ManualSource([
          _fixtureItem(
            0,
            rich: true,
            artworkTag: tag,
            duration: const Duration(hours: 24),
          ),
        ]),
        playbackMode: channel.playbackMode,
        anchor: channel.anchor,
        shuffleSeed: channel.shuffleSeed,
      ),
    ];
    if (bumpGeneration) _contentGeneration++;
    notifyListeners();
  }

  void bumpContentGeneration() {
    _contentGeneration++;
    notifyListeners();
  }

  @override
  LineupPlaybackRequest playbackFor(String itemId) =>
      LineupPlaybackRequest.parts([
        LineupPlaybackPart(uri: Uri.parse('lineup-test://$itemId')),
      ]);
}

ChannelItem _fixtureItem(
  int index, {
  required bool rich,
  String suffix = '',
  String artworkTag = '',
  required Duration duration,
}) => ChannelItem(
  id: '${index == 0 ? 'program' : 'program-$index'}$suffix',
  title: suffix.isEmpty
      ? (index == 0 ? 'Program' : 'Program $index')
      : 'Replacement Program',
  duration: duration,
  showTitle: rich ? 'Lineup Stories' : null,
  poster: rich ? Uri.parse('test://poster$artworkTag') : null,
  backdrop: rich ? Uri.parse('test://backdrop$artworkTag') : null,
  clearLogo: rich ? Uri.parse('test://logo$artworkTag') : null,
  summary: rich ? 'A synthetic synopsis for deterministic tests.' : null,
  contentRating: rich ? 'TV-14' : null,
  genres: rich ? const ['Drama', 'Adventure'] : const [],
  year: rich ? 2026 : null,
  seasonNumber: rich ? 2 : null,
  episodeNumber: rich ? 6 : null,
  resolution: rich ? '1080p' : null,
  videoCodec: rich ? 'h264' : null,
);

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
