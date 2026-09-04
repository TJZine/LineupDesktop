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
final _extremeWideArtwork = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAABLAAAAAUCAIAAAASgVNzAAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAAGYktHRAD/AP8A/6C9p5MAAAAHdElNRQfqCQQBEhHq/110AAAAJXRFWHRkYXRlOmNyZWF0ZQAyMDI2LTA5LTA0VDAxOjE4OjE3KzAwOjAwct2ViQAAACV0RVh0ZGF0ZTptb2RpZnkAMjAyNi0wOS0wNFQwMToxODoxNyswMDowMAOALTUAAAAodEVYdGRhdGU6dGltZXN0YW1wADIwMjYtMDktMDRUMDE6MTg6MTcrMDA6MDBUlQzqAAAAjUlEQVR42u3XMQEAIAzAMMC/5yFjRxMFfXtn5gAAANDztgMAAADYYQgBAACiDCEAAECUIQQAAIgyhAAAAFGGEAAAIMoQAgAARBlCAACAKEMIAAAQZQgBAACiDCEAAECUIQQAAIgyhAAAAFGGEAAAIMoQAgAARBlCAACAKEMIAAAQZQgBAACiDCEAAEDUB/B/AyWGhzYyAAAAAElFTkSuQmCC',
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
      dvrControlsEnabled: true,
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

  testWidgets('classic TV mode hides and ignores DVR transport controls', (
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

    expect(find.byTooltip('Previous channel'), findsNothing);
    expect(find.byTooltip('Play'), findsNothing);
    expect(find.byTooltip('Next channel'), findsNothing);
    for (final key in [
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.keyJ,
      LogicalKeyboardKey.keyK,
      LogicalKeyboardKey.keyL,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.mediaPlay,
      LogicalKeyboardKey.mediaPause,
      LogicalKeyboardKey.mediaPlayPause,
      LogicalKeyboardKey.mediaStop,
      LogicalKeyboardKey.mediaRewind,
      LogicalKeyboardKey.mediaFastForward,
    ]) {
      await tester.sendKeyEvent(key);
    }
    expect(fixture.native.transportCommands, 0);
    expect(fixture.player.overlay, PlayerOverlay.osd);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('classic TV mode keeps PageUp and PageDown channel surfing', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing, channelCount: 2);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    await tester.pump();
    expect(fixture.lineup.currentChannelId, 'channel-1');
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pump();
    await tester.pump();
    expect(fixture.lineup.currentChannelId, 'channel');
    final afterSurfing = fixture.native.transportCommands;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(fixture.native.transportCommands, afterSurfing);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('media Stop reports failures without an unhandled error', (
    tester,
  ) async {
    final fixture = _Fixture(
      PlayerState.playing,
      dvrControlsEnabled: true,
      failStop: true,
    );
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

  testWidgets('media Play and Pause route through safe coordinator controls', (
    tester,
  ) async {
    final fixture = _Fixture(
      PlayerState.playing,
      dvrControlsEnabled: true,
      failControls: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );

    for (final key in [
      LogicalKeyboardKey.mediaPlay,
      LogicalKeyboardKey.mediaPause,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(
        fixture.player.error,
        'Playback controls are temporarily unavailable. Try again.',
      );
      expect(fixture.player.overlay, PlayerOverlay.error);
      expect(tester.takeException(), isNull);
      fixture.player.closeOverlay();
    }

    expect(fixture.native.transportCommands, 2);
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

  testWidgets('playback errors replace timed overlays and loading states', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.buffering, failLoad: true);
    fixture.player.showMiniGuide();
    await fixture.player.loadInitialMedia(Uri.parse('lineup-test://failure'));

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(fixture.player.overlay, PlayerOverlay.error);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'Playback error',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('mini-guide-shelf')), findsNothing);
    expect(find.byKey(const Key('player-osd-surface')), findsNothing);
    expect(find.bySemanticsLabel('Preparing playback'), findsNothing);
    expect(find.bySemanticsLabel('Buffering playback'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('core player keyboard controls work while the OSD is visible', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing, dvrControlsEnabled: true);
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
    final fixture = _Fixture(PlayerState.playing, channelCount: 5);
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
      final progressLine = tester.getRect(
        find.byKey(const Key('player-osd-progress-line')),
      );
      expect(progressLine.left, 0, reason: '$size');
      expect(progressLine.width, size.width, reason: '$size');
      expect(progressLine.bottom, size.height, reason: '$size');
      expect(tester.takeException(), isNull, reason: '$size');
    }

    for (final size in const [
      Size(480, 900),
      Size(800, 600),
      Size(1280, 720),
      Size(1600, 900),
      Size(1920, 1080),
      Size(3840, 2160),
    ]) {
      await tester.binding.setSurfaceSize(size);
      fixture.player.showMiniGuide();
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(size),
          home: MediaQuery(
            data: MediaQueryData(size: size),
            child: PlayerView(controller: fixture.player, openGuide: () {}),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.bySemanticsLabel(RegExp('Mini Guide')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('mini-guide-shelf'))).width,
        size.width,
      );
      expect(fixture.player.miniGuideChannels, hasLength(5));
      expect(find.textContaining('UP/DOWN Browse'), findsOneWidget);
      final shelf = tester.getRect(find.byKey(const Key('mini-guide-shelf')));
      expect(
        MediaQuery.sizeOf(
          tester.element(find.byKey(const Key('mini-guide-shelf'))),
        ),
        size,
      );
      for (final channel in fixture.player.miniGuideChannels) {
        final row = tester.getRect(
          find.byKey(Key('mini-guide-row-${channel.id}')),
        );
        expect(row.top, greaterThanOrEqualTo(shelf.top), reason: '$size');
        expect(row.bottom, lessThanOrEqualTo(shelf.bottom), reason: '$size');
        if (LineupLayout.isCompactWidth(size.width) || size.height < 720) {
          expect(row.height, greaterThan(48), reason: '$size');
        } else if (size.height >= 900) {
          expect(row.height, 48, reason: '$size');
        }
        for (final fact in ['current', 'next']) {
          final factRect = tester.getRect(
            find.byKey(Key('mini-guide-$fact-${channel.id}')),
          );
          expect(row.contains(factRect.topLeft), isTrue, reason: '$size');
          expect(row.contains(factRect.bottomRight), isTrue, reason: '$size');
        }
      }
      if (size.height >= 900 && !LineupLayout.isCompactWidth(size.width)) {
        expect(shelf.height / size.height, lessThan(0.34), reason: '$size');
      }
      expect(tester.takeException(), isNull, reason: '$size');
      fixture.player.closeOverlay();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('OSD uses a shallow horizontal widescreen hierarchy', (
    tester,
  ) async {
    final fixture = _Fixture(
      PlayerState.playing,
      shortPrograms: true,
      longNextTitle: true,
      guideClock: () => DateTime(2026, 1, 15, 12),
    );
    expect(await fixture.guide.ensureCurrentProgram('channel'), isNotNull);
    expect(fixture.player.nextProgram, isNotNull);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final size in const [
      Size(800, 600),
      Size(1280, 720),
      Size(1600, 900),
      Size(1920, 1080),
      Size(3840, 2160),
    ]) {
      await tester.binding.setSurfaceSize(size);
      fixture.player.showOsd();
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(size),
          home: MediaQuery(
            data: MediaQueryData(size: size),
            child: PlayerView(controller: fixture.player, openGuide: () {}),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(fixture.player.nextProgram, isNotNull, reason: '$size');

      final surface = tester.getRect(
        find.byKey(const Key('player-osd-surface')),
      );
      expect(surface.width, size.width, reason: '$size');
      if (size.width >= 1200 && size.height >= 640) {
        expect(
          find.byKey(const Key('player-osd-horizontal-layout')),
          findsOneWidget,
        );
        expect(
          surface.height / size.height,
          lessThan(size.height < 900 ? 0.30 : 0.26),
          reason: '$size',
        );
        final timeline = tester.getRect(
          find.byKey(const Key('player-osd-progress-block')),
        );
        final controls = tester.getRect(
          find.byKey(const Key('player-osd-horizontal-layout')),
        );
        final identity = tester.getRect(
          find.byKey(const Key('player-osd-identity')),
        );
        final actions = tester.getRect(
          find.byKey(const Key('player-osd-action-groups')),
        );
        expect(identity.left, lessThan(actions.left), reason: '$size');
        expect(
          actions.right,
          lessThanOrEqualTo(surface.right),
          reason: '$size',
        );
        expect(timeline.bottom, closeTo(surface.bottom, 24));
        expect(timeline.top, greaterThan(controls.bottom));
      } else {
        expect(
          find.byKey(const Key('player-osd-stacked-controls')),
          findsOneWidget,
        );
      }
      expect(
        find.byKey(const Key('player-osd-next')),
        findsOneWidget,
        reason: '$size',
      );
      {
        final timing = tester.widget<Text>(
          find.byKey(const Key('player-osd-timing')),
        );
        expect(timing.data, contains('50m left'));
        final next = tester.widget<Text>(
          find.byKey(const Key('player-osd-next')),
        );
        expect(next.data, contains('deliberately long synthetic next program'));
        final localizedStart =
            MaterialLocalizations.of(
              tester.element(find.byKey(const Key('player-osd-surface'))),
            ).formatTimeOfDay(
              TimeOfDay.fromDateTime(
                fixture.player.nextProgram!.scheduled.start.toLocal(),
              ),
              alwaysUse24HourFormat: false,
            );
        expect(next.data, contains('Up next • $localizedStart •'));
        expect(next.maxLines, 1);
        expect(next.overflow, TextOverflow.ellipsis);
        final timeline = tester.getRect(
          find.byKey(const Key('player-osd-progress-block')),
        );
        final nextRect = tester.getRect(
          find.byKey(const Key('player-osd-next')),
        );
        expect(
          timeline.inflate(0.1).contains(nextRect.topLeft),
          isTrue,
          reason: '$size',
        );
        expect(
          timeline.inflate(0.1).contains(nextRect.bottomRight),
          isTrue,
          reason: '$size',
        );
      }
      expect(tester.takeException(), isNull, reason: '$size');
    }

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('OSD keeps status facts and unsupported actions disabled', (
    tester,
  ) async {
    for (final state in [
      PlayerState.loading,
      PlayerState.buffering,
      PlayerState.unsupported,
    ]) {
      final fixture = _Fixture(state, dvrControlsEnabled: true);
      fixture.player.showOsd();
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(state),
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final status = tester.widget<Text>(
        find.byKey(const Key('player-osd-status')),
      );
      expect(status.data, isNot(contains('Channel')));
      expect(status.data, contains(_statusLabelForTest(state)));
      if (state == PlayerState.unsupported) {
        for (final icon in [
          Icons.skip_previous,
          Icons.play_arrow,
          Icons.skip_next,
          Icons.fullscreen,
        ]) {
          expect(
            tester
                .widget<IconButton>(find.widgetWithIcon(IconButton, icon))
                .onPressed,
            isNull,
          );
        }
      }

      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    }
  });

  testWidgets('OSD uses stateful labeled track and sleep actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _Fixture(
      PlayerState.playing,
      tracks: const [
        PlayerTrack(
          id: 1,
          type: PlayerTrackType.audio,
          selected: true,
          title: 'English stereo',
        ),
        PlayerTrack(
          id: 2,
          type: PlayerTrackType.subtitle,
          selected: false,
          language: 'English',
        ),
      ],
    );
    fixture.player.showOsd();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1280, 720)),
          child: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Subtitles • Off'), findsOneWidget);
    expect(find.text('Audio • English stereo'), findsOneWidget);
    expect(find.text('Sleep • Off'), findsOneWidget);
    expect(find.byKey(const Key('player-osd-subtitles')), findsOneWidget);
    expect(find.byKey(const Key('player-osd-audio')), findsOneWidget);
    expect(find.byKey(const Key('player-osd-sleep')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('OSD omits normal-state status and quality telemetry', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _Fixture(
      PlayerState.playing,
      richProgram: true,
      nativeTelemetry: const PlayerTelemetry(
        width: 1920,
        height: 1080,
        videoCodec: 'h264',
      ),
    );
    fixture.player.showOsd();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1280, 720)),
          child: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final status = tester.widget<Text>(
      find.byKey(const Key('player-osd-status')),
    );
    expect(status.data, 'Lineup Stories');
    expect(status.data, isNot(contains('Playing')));
    expect(find.text('1080p'), findsNothing);
    expect(find.text('1920×1080'), findsNothing);
    expect(find.text('h264'), findsNothing);

    fixture.player.showNowPlaying();
    await tester.pumpAndSettle();
    final nowPlayingSemantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byKey(const Key('player-now-playing-shelf')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(
      nowPlayingSemantics.properties.label,
      allOf(contains('H264'), isNot(contains('1920×1080'))),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('OSD rounds positive remaining minutes up', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final (position, duration, expected) in [
      (const Duration(seconds: 1), const Duration(minutes: 1), '1m left'),
      (
        const Duration(milliseconds: 59999),
        const Duration(minutes: 2),
        '2m left',
      ),
      (const Duration(minutes: 1), const Duration(minutes: 1), '0m left'),
      (
        const Duration(minutes: 2),
        const Duration(minutes: 1),
        '01:00 / 01:00 • 0m left',
      ),
      (
        const Duration(seconds: -1),
        const Duration(minutes: 1),
        '00:00 / 01:00 • 1m left',
      ),
      (const Duration(seconds: 10), Duration.zero, '00:10 / 00:00'),
    ]) {
      final fixture = _Fixture(
        PlayerState.playing,
        nativePosition: position,
        nativeDuration: duration,
      );
      fixture.player.showOsd();
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(position),
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pump();

      expect(
        tester.widget<Text>(find.byKey(const Key('player-osd-timing'))).data,
        contains(expected),
      );
      if (duration == Duration.zero) {
        expect(
          tester.widget<Text>(find.byKey(const Key('player-osd-timing'))).data,
          isNot(contains('left')),
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    }
  });

  testWidgets('OSD clamps the seek slider when duration is unknown', (
    tester,
  ) async {
    final fixture = _Fixture(
      PlayerState.playing,
      dvrControlsEnabled: true,
      nativePosition: const Duration(seconds: 10),
      nativeDuration: Duration.zero,
    );
    fixture.player.showOsd();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, inInclusiveRange(slider.min, slider.max));
    expect(slider.value, 1);
    expect(
      tester.widget<Text>(find.byKey(const Key('player-osd-timing'))).data,
      contains('00:10 / 00:00'),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('OSD uses official title artwork with a text fallback', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final cases = [
      (
        fixture: _Fixture(PlayerState.playing, richProgram: true),
        logo: true,
        description: 'loaded logo',
      ),
      (
        fixture: _Fixture(
          PlayerState.playing,
          richProgram: true,
          preferClearLogos: false,
        ),
        logo: false,
        description: 'disabled logos',
      ),
      (
        fixture: _Fixture(
          PlayerState.playing,
          richProgram: true,
          failArtwork: true,
        ),
        logo: false,
        description: 'failed artwork',
      ),
    ];
    for (final item in cases) {
      await item.fixture.guide.ensureCurrentProgram('channel');
      item.fixture.player.showOsd();
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(item.logo),
          home: PlayerView(controller: item.fixture.player, openGuide: () {}),
        ),
      );
      if (item.logo) {
        await tester.runAsync(
          () => precacheImage(
            MemoryImage(_fixtureArtwork),
            tester.element(find.byType(PlayerView)),
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('player-osd-logo')),
        item.logo ? findsOneWidget : findsNothing,
        reason: item.description,
      );
      final titleSemantics = find.bySemanticsLabel('Program');
      expect(titleSemantics, findsOneWidget, reason: item.description);
      final titleData = tester
          .getSemantics(
            find.byKey(Key(item.logo ? 'player-osd-logo' : 'player-osd-title')),
          )
          .getSemanticsData();
      expect(titleData.label, 'Program', reason: item.description);
      expect(
        titleData.flagsCollection.isImage,
        item.logo,
        reason: item.description,
      );
      if (item.logo) {
        expect(find.byKey(const Key('player-osd-title')), findsNothing);
      } else {
        expect(find.byKey(const Key('player-osd-title')), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      item.fixture.dispose();
    }
    semantics.dispose();
  });

  testWidgets('OSD keeps its widescreen hierarchy at DPR2', (tester) async {
    final fixture = _Fixture(PlayerState.playing);
    tester.view
      ..devicePixelRatio = 2
      ..physicalSize = const Size(3840, 2160);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    fixture.player.showOsd();

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pumpAndSettle();

    final surface = tester.getSize(find.byKey(const Key('player-osd-surface')));
    expect(surface.width, 1920);
    expect(surface.height / 1080, lessThan(0.20));
    final progressLine = tester.getRect(
      find.byKey(const Key('player-osd-progress-line')),
    );
    expect(progressLine.left, 0);
    expect(progressLine.width, 1920);
    expect(progressLine.bottom, 1080);
    expect(
      find.byKey(const Key('player-osd-horizontal-layout')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('DVR seek target stays clear of OSD action buttons', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final fixture = _Fixture(PlayerState.playing, dvrControlsEnabled: true);
    for (final size in const [Size(1280, 720), Size(1920, 1080)]) {
      await tester.binding.setSurfaceSize(size);
      fixture.player.showOsd();
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(size),
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pump();
      final seekTarget = tester.getRect(
        find.byKey(const Key('player-osd-progress-line')),
      );
      final actions = tester.getRect(
        find.byKey(const Key('player-osd-action-groups')),
      );
      expect(seekTarget.overlaps(actions), isFalse, reason: '$size');
      expect(
        find.bySemanticsLabel('Playback progress'),
        findsOneWidget,
        reason: '$size',
      );
      expect(tester.takeException(), isNull, reason: '$size');
    }
    await tester.binding.setSurfaceSize(null);
    fixture.player.closeOverlay();
    await tester.pump();
    fixture.dispose();
    semantics.dispose();
  });

  testWidgets('player overlays retain 1280x720 layout at DPR2', (tester) async {
    final fixture = _Fixture(PlayerState.playing);
    tester.view
      ..devicePixelRatio = 2
      ..physicalSize = const Size(2560, 1440);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    fixture.player.showOsd();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      tester.getSize(find.byKey(const Key('player-osd-surface'))).width,
      1280,
    );

    fixture.player.showMiniGuide();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.getSize(find.byKey(const Key('mini-guide-shelf'))).width,
      1280,
    );
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(3840, 2160);
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const Key('mini-guide-shelf'))).width,
      1920,
    );
    expect(
      tester.getSize(find.byKey(const Key('mini-guide-shelf'))).height / 1080,
      lessThan(0.34),
    );
    for (final channel in fixture.player.miniGuideChannels) {
      expect(
        tester.getSize(find.byKey(Key('mini-guide-row-${channel.id}'))).height,
        48,
      );
    }
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('OSD and Mini Guide enter and exit from their attached edges', (
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
    await tester.pump(const Duration(milliseconds: 100));
    final transitions = find.byType(AnimatedSwitcher);
    final switcher = tester.widget<AnimatedSwitcher>(transitions);
    expect(switcher.duration, const Duration(milliseconds: 300));
    expect(switcher.reverseDuration, const Duration(milliseconds: 300));
    expect(
      find.descendant(of: transitions, matching: find.byType(FadeTransition)),
      findsWidgets,
    );
    final miniSlide = tester.widget<SlideTransition>(
      find
          .ancestor(
            of: find.byKey(const Key('mini-guide-shelf')),
            matching: find.byType(SlideTransition),
          )
          .first,
    );
    expect(miniSlide.position.value.dx, 0);
    expect(miniSlide.position.value.dy, lessThan(0));

    await tester.pumpAndSettle();
    fixture.player.closeOverlay();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(miniSlide.position.value.dy, lessThan(0));

    await tester.pumpAndSettle();
    fixture.player.showOsd();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final osdSwitcher = tester.widget<AnimatedSwitcher>(transitions);
    expect(osdSwitcher.duration, const Duration(milliseconds: 350));
    expect(osdSwitcher.reverseDuration, const Duration(milliseconds: 350));
    final osdSlide = tester.widget<SlideTransition>(
      find
          .ancestor(
            of: find.byKey(const Key('player-osd-surface')),
            matching: find.byType(SlideTransition),
          )
          .first,
    );
    expect(osdSlide.position.value.dx, 0);
    expect(osdSlide.position.value.dy, greaterThan(0));

    await tester.pumpAndSettle();
    fixture.player.closeOverlay();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(osdSlide.position.value.dy, greaterThan(0));

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

    fixture.player.closeOverlay();
    await tester.pump();
    fixture.player.showMiniGuide();
    await tester.pump();
    expect(switcher.duration, Duration.zero);
    expect(switcher.reverseDuration, Duration.zero);
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.bySemanticsLabel(RegExp('Mini Guide')), findsOneWidget);

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

  testWidgets('track rows distinguish focused and selected presentation', (
    tester,
  ) async {
    final fixture = _Fixture(
      PlayerState.playing,
      tracks: const [
        PlayerTrack(
          id: 1,
          type: PlayerTrackType.audio,
          selected: false,
          title: 'Stereo',
        ),
        PlayerTrack(
          id: 2,
          type: PlayerTrackType.audio,
          selected: true,
          title: 'Surround',
        ),
      ],
    );
    fixture.player.showTracks(PlayerTrackType.audio);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    final focused = tester.widget<ListTile>(
      find.byKey(const Key('playback-track-audio-1')),
    );
    final selected = tester.widget<ListTile>(
      find.byKey(const Key('playback-track-audio-2')),
    );
    expect(Focus.of(tester.element(find.text('Stereo'))).hasFocus, isTrue);
    expect(focused.selected, isFalse);
    expect(selected.selected, isTrue);
    expect(focused.focusColor, isNot(selected.selectedTileColor));
    expect((selected.trailing! as Icon).semanticLabel, 'Selected');

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
      final rail = tester.getRect(
        find.byKey(const Key('playback-options-rail')),
      );
      expect(rail.right, size.width);
      expect(rail.height, size.height);
      expect(rail.width, size.width == 800 ? 320 : 420);
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      expect(find.text('Audio track 29'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$size');
    }

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('selected subtitle in a long list is focused and visible', (
    tester,
  ) async {
    final fixture = _Fixture(
      PlayerState.playing,
      tracks: [
        for (var index = 0; index < 30; index++)
          PlayerTrack(
            id: index,
            type: PlayerTrackType.subtitle,
            selected: index == 24,
            title: 'Subtitle track $index',
          ),
      ],
    );
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    fixture.player.showTracks(PlayerTrackType.subtitle);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pumpAndSettle();

    final selected = find.text('Subtitle track 24');
    final list = find.byKey(const Key('playback-options-list'));
    expect(Focus.of(tester.element(selected)).hasFocus, isTrue);
    expect(tester.getRect(list).contains(tester.getCenter(selected)), isTrue);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('track rail keeps proportional bounds through 4K', (
    tester,
  ) async {
    final fixture = _Fixture(
      PlayerState.playing,
      tracks: const [
        PlayerTrack(id: 1, type: PlayerTrackType.audio, selected: true),
      ],
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final layout in const [
      (viewport: Size(800, 600), width: 320.0),
      (viewport: Size(1280, 720), width: 420.0),
      (viewport: Size(3840, 2160), width: 420.0),
    ]) {
      await tester.binding.setSurfaceSize(layout.viewport);
      fixture.player.showOsd();
      fixture.player.showTracks(PlayerTrackType.audio);
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pumpAndSettle();

      final rect = tester.getRect(
        find.byKey(const Key('playback-options-rail')),
      );
      expect(
        rect,
        Rect.fromLTWH(
          layout.viewport.width - layout.width,
          0,
          layout.width,
          layout.viewport.height,
        ),
      );
      expect(tester.takeException(), isNull, reason: '${layout.viewport}');
    }

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('track rails enter from the right and exit in 300ms', (
    tester,
  ) async {
    final fixture = _Fixture(
      PlayerState.playing,
      tracks: const [
        PlayerTrack(id: 1, type: PlayerTrackType.audio, selected: true),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );

    fixture.player.showTracks(PlayerTrackType.audio);
    await tester.pump();
    var switcher = tester.widget<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher),
    );
    expect(switcher.duration, const Duration(milliseconds: 300));
    expect(switcher.reverseDuration, const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 150));
    var positions = tester
        .widgetList<SlideTransition>(
          find.ancestor(
            of: find.byKey(const Key('playback-options-rail')),
            matching: find.byType(SlideTransition),
          ),
        )
        .map((slide) => slide.position.value);
    expect(positions.any((position) => position.dx > 0), isTrue);
    expect(positions.every((position) => position.dy == 0), isTrue);

    await tester.pumpAndSettle();
    fixture.player.closeOverlay();
    await tester.pump();
    switcher = tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
    expect(switcher.duration, const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 150));
    positions = tester
        .widgetList<SlideTransition>(
          find.ancestor(
            of: find.byKey(const Key('playback-options-rail')),
            matching: find.byType(SlideTransition),
          ),
        )
        .map((slide) => slide.position.value);
    expect(positions.any((position) => position.dx > 0), isTrue);
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('Reduce Motion settles track rails in one pump', (tester) async {
    final fixture = _Fixture(
      PlayerState.playing,
      tracks: const [
        PlayerTrack(id: 1, type: PlayerTrackType.audio, selected: true),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );

    fixture.player.showTracks(PlayerTrackType.audio);
    await tester.pump();
    final switcher = tester.widget<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher),
    );
    expect(switcher.duration, Duration.zero);
    expect(switcher.reverseDuration, Duration.zero);
    expect(find.byKey(const Key('playback-options-rail')), findsOneWidget);
    final slides = tester.widgetList<SlideTransition>(
      find.ancestor(
        of: find.byKey(const Key('playback-options-rail')),
        matching: find.byType(SlideTransition),
      ),
    );
    expect(slides, isNotEmpty);
    expect(
      slides.every((slide) => slide.position.value == Offset.zero),
      isTrue,
    );

    fixture.player.closeOverlay();
    await tester.pump();
    expect(find.byKey(const Key('playback-options-rail')), findsNothing);

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
      find.byKey(const Key('player-now-playing-channel-bug')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('player-now-playing-channel')), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('player-now-playing-shelf'))),
      const Size(1180, 380),
    );
    expect(
      MediaQuery.sizeOf(
        tester.element(find.byKey(const Key('player-now-playing-surface'))),
      ),
      const Size(1280, 720),
    );
    expect(fixture.lineup.artworkRequests, hasLength(2));
    expect(find.byType(Image), findsNWidgets(2));
    expect(find.byKey(const Key('player-now-playing-logo')), findsOneWidget);
    expect(find.text('Season 2 • Episode 6'), findsOneWidget);
    expect(
      find.text('A synthetic synopsis for deterministic tests.'),
      findsOneWidget,
    );
    expect(find.text('TV-14'), findsOneWidget);
    expect(
      find.byKey(const Key('player-now-playing-channel-bug')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Channel 7, Channel'), findsOneWidget);
    expect(find.bySemanticsLabel('7 • Channel'), findsNothing);
    expect(find.text('Source • H264'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^Now playing\..*Program')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'10:00 / 1:00:00 playback')),
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

  testWidgets(
    'Now Playing renders bounded cast portraits, fallbacks, names, and semantics',
    (tester) async {
      final fixture = _Fixture(
        PlayerState.playing,
        richItemOverride: _fixtureItem(
          0,
          rich: true,
          duration: const Duration(hours: 1),
          cast: _fixtureCast,
        ),
      );
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
      fixture.player.showNowPlaying();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('player-now-playing-cast')), findsOneWidget);
      expect(
        find.byKey(const Key('player-now-playing-cast-portrait-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('player-now-playing-cast-fallback-4')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('player-now-playing-cast-more')),
        findsOneWidget,
      );
      expect(find.text('+2'), findsOneWidget);
      expect(
        find.text(
          'Avery Vale • Mina Park • Solomon Reed • Clara Wynn • Noa Bell • Theo March • Imani Cross',
        ),
        findsOneWidget,
      );
      expect(fixture.lineup.artworkRequests, hasLength(6));
      expect(
        find.bySemanticsLabel(
          RegExp(
            r'Cast: Avery Vale as Detective Rowan.*Mina Park as Dr\. Lena Quill',
          ),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
  );

  testWidgets('failed cast portrait uses the neutral person fallback', (
    tester,
  ) async {
    final fixture = _Fixture(
      PlayerState.playing,
      failArtwork: true,
      richItemOverride: _fixtureItem(
        0,
        rich: true,
        duration: const Duration(hours: 1),
        cast: [
          ChannelCastMember(
            name: 'Avery Vale',
            portrait: Uri.parse('/library/metadata/test/cast-avery'),
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();
    fixture.player.showNowPlaying();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('player-now-playing-cast-fallback-0')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.person), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('Now Playing omits cast without cast facts', (tester) async {
    final fixture = _Fixture(PlayerState.playing, richProgram: true);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();
    fixture.player.showNowPlaying();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('player-now-playing-cast')), findsNothing);
    expect(
      find.byKey(const Key('player-now-playing-cast-names')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets(
    'Now Playing falls back to schedule timing without native duration',
    (tester) async {
      final now = DateTime.utc(2026, 1, 15, 3);
      final fixture = _Fixture(
        PlayerState.playing,
        richProgram: true,
        shortPrograms: true,
        nativeDuration: Duration.zero,
        guideClock: () => now,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pump();
      fixture.player.showNowPlaying();
      await tester.pumpAndSettle();

      expect(find.text('30:00 / 1:00:00'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const Key('player-now-playing-progress')),
            )
            .value,
        0.5,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
  );

  testWidgets('runtime HDR overrides stale catalog SDR', (tester) async {
    final fixture = _Fixture(
      PlayerState.playing,
      richItemOverride: _fixtureItem(
        0,
        rich: true,
        duration: const Duration(hours: 1),
        dynamicRange: 'SDR',
      ),
      nativeTelemetry: const PlayerTelemetry(gamma: 'pq'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();
    fixture.player.showNowPlaying();
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel(RegExp(r'\. HDR\.')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'\. SDR\.')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('Now Playing keeps series identity when logo is unusable', (
    tester,
  ) async {
    for (final (bytes, description, precache) in [
      (Uint8List.fromList(const [1, 2, 3]), 'invalid', false),
      (_extremeWideArtwork, 'extreme-wide', true),
    ]) {
      final fixture = _Fixture(
        PlayerState.playing,
        richProgram: true,
        artworkBytes: bytes,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      fixture.player.showNowPlaying();
      await tester.pump();
      if (precache) {
        await tester.runAsync(
          () => precacheImage(
            MemoryImage(bytes),
            tester.element(find.byType(PlayerView)),
          ),
        );
      }
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('player-now-playing-series')),
        findsOneWidget,
        reason: description,
      );
      expect(
        find.byKey(const Key('player-now-playing-title')),
        findsOneWidget,
        reason: description,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    }
  });

  testWidgets('Now Playing input replaces the surface and still executes', (
    tester,
  ) async {
    final fixture = _Fixture(
      PlayerState.playing,
      dvrControlsEnabled: true,
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
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('player-now-playing-shelf')));
    expect(fixture.player.overlay, PlayerOverlay.nowPlaying);
    await tester.tapAt(const Offset(799, 5));
    expect(fixture.player.overlay, PlayerOverlay.osd);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets(
    'compact layout retains the poster and disabled logos skip fetching',
    (tester) async {
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
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => precacheImage(
          MemoryImage(_fixtureArtwork),
          tester.element(find.byType(PlayerView)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('player-now-playing-title')), findsOneWidget);
      expect(
        find.byKey(const Key('player-now-playing-poster')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('player-now-playing-logo')), findsOneWidget);
      expect(fixture.lineup.artworkRequests, hasLength(2));
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

      expect(disabled.lineup.artworkRequests, hasLength(1));
      expect(
        disabled.lineup.artworkRequests,
        isNot(contains(Uri.parse('test://logo'))),
      );
      expect(find.byKey(const Key('player-now-playing-logo')), findsNothing);
      expect(find.byKey(const Key('player-now-playing-title')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      disabled.dispose();
    },
  );

  testWidgets('compact Now Playing with cast does not overflow', (
    tester,
  ) async {
    final fixture = _Fixture(
      PlayerState.playing,
      richItemOverride: _fixtureItem(
        0,
        rich: true,
        duration: const Duration(hours: 1),
        cast: _fixtureCast.take(5).toList(growable: false),
      ),
    );
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();
    fixture.player.showNowPlaying();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('player-now-playing-cast')), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
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
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    expect(fixture.lineup.artworkRequests, hasLength(2));

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
      containsAll(['test://poster-replacement', 'test://logo-replacement']),
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
    expect(fixture.lineup.artworkRequests, hasLength(2));

    fixture.lineup.bumpContentGeneration();
    await tester.pump();
    expect(fixture.player.overlay, PlayerOverlay.none);
    fixture.guide.requestViewport(0, 1);
    await tester.pump();
    await tester.pump();
    fixture.player.showNowPlaying();
    await tester.pumpAndSettle();

    expect(fixture.lineup.artworkRequests, hasLength(4));
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
      expect(fixture.lineup.artworkRequests, hasLength(2));

      fixture.player.closeOverlay();
      fixture.player.showNowPlaying();
      await tester.pumpAndSettle();
      expect(fixture.lineup.artworkRequests, hasLength(2));

      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
  );

  testWidgets('Now Playing reflows with and without cast through 4K', (
    tester,
  ) async {
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    for (final variant in const [
      (
        castPresent: false,
        shelves: [
          Size(760, 336),
          Size(1180, 380),
          Size(1180, 450),
          Size(1180, 540),
          Size(1500, 560),
        ],
        dpr2Shelf: Size(1180, 540),
      ),
      (
        castPresent: true,
        shelves: [
          Size(760, 378),
          Size(1180, 432),
          Size(1180, 486),
          Size(1180, 580),
          Size(1500, 580),
        ],
        dpr2Shelf: Size(1180, 580),
      ),
    ]) {
      final fixture = variant.castPresent
          ? _Fixture(
              PlayerState.playing,
              richItemOverride: _fixtureItem(
                0,
                rich: true,
                duration: const Duration(hours: 1),
                cast: _fixtureCast.take(5).toList(growable: false),
              ),
            )
          : _Fixture(PlayerState.playing, richProgram: true);
      tester.view.devicePixelRatio = 1;

      for (final (index, viewport) in const [
        Size(800, 600),
        Size(1280, 720),
        Size(1600, 900),
        Size(1920, 1080),
        Size(3840, 2160),
      ].indexed) {
        final expectedShelf = variant.shelves[index];
        tester.view.physicalSize = viewport;
        await tester.pumpWidget(
          MaterialApp(
            home: PlayerView(controller: fixture.player, openGuide: () {}),
          ),
        );
        await tester.pump();
        fixture.player.showNowPlaying();
        await tester.pumpAndSettle();

        final shelfSize = tester.getSize(
          find.byKey(const Key('player-now-playing-shelf')),
        );
        expect(shelfSize.width, closeTo(expectedShelf.width, 0.01));
        expect(shelfSize.height, closeTo(expectedShelf.height, 0.01));
        expect(
          tester
              .getSize(find.byKey(const Key('player-now-playing-poster')))
              .width,
          closeTo((expectedShelf.height * 2 / 3).clamp(190, 374), 0.01),
        );
        expect(
          tester
              .getSize(find.byKey(const Key('player-now-playing-poster')))
              .height,
          closeTo(expectedShelf.height, 1.01),
        );
        expect(
          tester
              .getRect(find.byKey(const Key('player-now-playing-title')).last)
              .top,
          greaterThan(
            tester
                .getRect(find.byKey(const Key('player-now-playing-logo')))
                .top,
          ),
        );
        expect(
          find.byKey(const Key('player-now-playing-cast')),
          variant.castPresent ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull, reason: '$viewport');
      }

      tester.view
        ..devicePixelRatio = 2
        ..physicalSize = const Size(3840, 2160);
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('player-now-playing-shelf'))),
        variant.dpr2Shelf,
      );
      expect(
        find.byKey(const Key('player-now-playing-cast')),
        variant.castPresent ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull, reason: 'DPR2');

      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    }
  });

  testWidgets(
    'Now Playing keeps essential hierarchy with missing, long, and sparse metadata',
    (tester) async {
      final cases = [
        (
          viewport: const Size(1920, 1080),
          item: _fixtureItem(
            0,
            rich: true,
            includeClearLogo: false,
            title: 'Missing Logo Program',
            duration: const Duration(hours: 2),
          ),
          logo: false,
          summary: true,
          badges: true,
        ),
        (
          viewport: const Size(1600, 900),
          item: _fixtureItem(
            0,
            rich: true,
            title: 'A deliberately long synthetic episode title that must stay inside the text column',
            duration: const Duration(hours: 2),
            summary:
                'A deliberately long synthetic synopsis that repeats enough detail to exercise the bounded summary allocation without introducing private media facts. '
                'The remaining text verifies that progress stays reachable below the description.',
          ),
          logo: true,
          summary: true,
          badges: true,
        ),
        (
          viewport: const Size(800, 600),
          item: _fixtureItem(
            0,
            rich: false,
            title: 'Sparse Program',
            duration: const Duration(hours: 2),
          ),
          logo: false,
          summary: false,
          badges: false,
        ),
      ];
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      for (final testCase in cases) {
        final fixture = _Fixture(
          PlayerState.playing,
          richItemOverride: testCase.item,
        );
        tester.view.physicalSize = testCase.viewport;
        await tester.pumpWidget(
          MaterialApp(
            home: PlayerView(controller: fixture.player, openGuide: () {}),
          ),
        );
        fixture.player.showNowPlaying();
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('player-now-playing-title')),
          findsOneWidget,
        );
        expect(find.text(testCase.item.title), findsOneWidget);
        expect(
          MediaQuery.sizeOf(
            tester.element(find.byKey(const Key('player-now-playing-surface'))),
          ),
          testCase.viewport,
        );
        expect(
          find.byKey(const Key('player-now-playing-logo')),
          testCase.logo ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const Key('player-now-playing-progress')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('player-now-playing-summary')),
          testCase.summary ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const Key('player-now-playing-badges')),
          testCase.badges && testCase.viewport.height >= 650
              ? findsOneWidget
              : findsNothing,
          reason: testCase.item.id,
        );
        expect(tester.takeException(), isNull, reason: testCase.item.id);

        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
      }
    },
  );

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
    expect(switcher.reverseDuration, Duration.zero);
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.byKey(const Key('player-now-playing-surface')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('Now Playing enters from the left and exits in 200ms', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing, richProgram: true);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );

    fixture.player.showNowPlaying();
    await tester.pump();
    var switcher = tester.widget<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher),
    );
    expect(switcher.duration, const Duration(milliseconds: 200));
    expect(switcher.reverseDuration, const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 100));
    var slidePositions = tester
        .widgetList<SlideTransition>(
          find.ancestor(
            of: find.byKey(const Key('player-now-playing-surface')),
            matching: find.byType(SlideTransition),
          ),
        )
        .map((slide) => slide.position.value);
    expect(slidePositions.any((position) => position.dx < 0), isTrue);
    expect(slidePositions.every((position) => position.dy == 0), isTrue);

    await tester.pumpAndSettle();
    fixture.player.closeOverlay();
    await tester.pump();
    switcher = tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
    expect(switcher.duration, const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 100));
    slidePositions = tester
        .widgetList<SlideTransition>(
          find.ancestor(
            of: find.byKey(const Key('player-now-playing-surface')),
            matching: find.byType(SlideTransition),
          ),
        )
        .map((slide) => slide.position.value);
    expect(slidePositions.any((position) => position.dx < 0), isTrue);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('player-now-playing-surface')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });
}

class _Fixture {
  _Fixture(
    PlayerState state, {
    bool failLoad = false,
    bool failStop = false,
    bool failControls = false,
    bool blockLoad = false,
    List<PlayerTrack> tracks = const [],
    int channelCount = 1,
    Duration? overlayTimeout,
    bool richProgram = false,
    bool preferClearLogos = true,
    bool dvrControlsEnabled = false,
    bool failArtwork = false,
    Uint8List? artworkBytes,
    bool blockArtwork = false,
    bool shortPrograms = false,
    bool longNextTitle = false,
    ChannelItem? richItemOverride,
    DateTime Function()? guideClock,
    Duration nativePosition = const Duration(minutes: 10),
    Duration nativeDuration = const Duration(hours: 1),
    PlayerTelemetry nativeTelemetry = const PlayerTelemetry(),
  }) {
    lineup = _Lineup(
      channelCount,
      richProgram: richProgram,
      preferClearLogos: preferClearLogos,
      dvrControlsEnabled: dvrControlsEnabled,
      failArtwork: failArtwork,
      artworkBytes: artworkBytes,
      blockArtwork: blockArtwork,
      shortPrograms: shortPrograms,
      longNextTitle: longNextTitle,
      richItemOverride: richItemOverride,
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
      failControls: failControls,
      blockLoad: blockLoad,
      tracks: tracks,
      positionValue: nativePosition,
      durationValue: nativeDuration,
      telemetryValue: nativeTelemetry,
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
    bool dvrControlsEnabled = false,
    this.failArtwork = false,
    this.artworkBytes,
    this.blockArtwork = false,
    bool shortPrograms = false,
    bool longNextTitle = false,
    ChannelItem? richItemOverride,
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
          if (index == 0 && richItemOverride != null)
            richItemOverride
          else
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
              title: longNextTitle
                  ? 'A deliberately long synthetic next program title that must remain ellipsized'
                  : null,
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
    settings = LineupSettings(
      preferClearLogos: preferClearLogos,
      dvrControlsEnabled: dvrControlsEnabled,
    );
    stage = SetupStage.ready;
  }

  final artworkRequests = <Uri>[];
  final bool failArtwork;
  final Uint8List? artworkBytes;
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
    return artworkBytes ?? _fixtureArtwork;
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
  String? title,
  String? summary,
  bool includeClearLogo = true,
  String? dynamicRange,
  required Duration duration,
  List<ChannelCastMember> cast = const [],
}) => ChannelItem(
  id: '${index == 0 ? 'program' : 'program-$index'}$suffix',
  title:
      title ??
      (suffix.isEmpty
          ? (index == 0 ? 'Program' : 'Program $index')
          : 'Replacement Program'),
  duration: duration,
  showTitle: rich ? 'Lineup Stories' : null,
  poster: rich ? Uri.parse('test://poster$artworkTag') : null,
  backdrop: rich ? Uri.parse('test://backdrop$artworkTag') : null,
  clearLogo: rich && includeClearLogo
      ? Uri.parse('test://logo$artworkTag')
      : null,
  summary: rich
      ? summary ?? 'A synthetic synopsis for deterministic tests.'
      : null,
  contentRating: rich ? 'TV-14' : null,
  genres: rich ? const ['Drama', 'Adventure'] : const [],
  year: rich ? 2026 : null,
  seasonNumber: rich ? 2 : null,
  episodeNumber: rich ? 6 : null,
  resolution: rich ? '1080p' : null,
  dynamicRange: dynamicRange,
  videoCodec: rich ? 'h264' : null,
  cast: cast,
);

final _fixtureCast = [
  ChannelCastMember(
    name: 'Avery Vale',
    role: 'Detective Rowan',
    portrait: Uri.parse('/library/metadata/test/cast-avery'),
  ),
  ChannelCastMember(
    name: 'Mina Park',
    role: 'Dr. Lena Quill',
    portrait: Uri.parse('/library/metadata/test/cast-mina'),
  ),
  ChannelCastMember(
    name: 'Solomon Reed',
    role: 'Arthur Bell',
    portrait: Uri.parse('/library/metadata/test/cast-solomon'),
  ),
  ChannelCastMember(
    name: 'Clara Wynn',
    role: 'June Mercer',
    portrait: Uri.parse('/library/metadata/test/cast-clara'),
  ),
  ChannelCastMember(name: 'Noa Bell', role: 'Evelyn Shaw'),
  ChannelCastMember(name: 'Theo March', role: 'Deputy Ames'),
  ChannelCastMember(name: 'Imani Cross', role: 'Nora Venn'),
];

String _statusLabelForTest(PlayerState state) => switch (state) {
  PlayerState.loading => 'Loading',
  PlayerState.buffering => 'Buffering',
  PlayerState.unsupported => 'Unsupported',
  _ => throw ArgumentError.value(state),
};

class _Native implements NativePlayer {
  _Native(
    PlayerState state, {
    this.failLoad = false,
    this.failStop = false,
    this.failControls = false,
    this.blockLoad = false,
    this.tracks = const [],
    this.positionValue = const Duration(minutes: 10),
    this.durationValue = const Duration(hours: 1),
    this.telemetryValue = const PlayerTelemetry(),
  }) : status = PlayerStatus(
         state: state,
         message: state == PlayerState.unsupported
             ? 'Playback is unavailable on macOS.'
             : 'Playing',
       );

  final bool failLoad;
  final bool failStop;
  final bool failControls;
  final bool blockLoad;
  final Duration positionValue;
  final Duration durationValue;
  final PlayerTelemetry telemetryValue;
  final loadStarted = Completer<void>();
  final _loadCompletion = Completer<void>();
  int transportCommands = 0;
  final fullscreenValues = <bool>[];

  @override
  final PlayerStatus status;
  @override
  Duration get position => positionValue;
  @override
  Duration get duration => durationValue;
  @override
  PlayerTelemetry get telemetry => telemetryValue;
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
    if (failControls) {
      throw const PlayerUnavailable(
        'Synthetic play failure.',
        failureCode: 'command_error',
      );
    }
  }

  @override
  Future<void> pause() async {
    transportCommands++;
    if (failControls) {
      throw const PlayerUnavailable(
        'Synthetic pause failure.',
        failureCode: 'command_error',
      );
    }
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
