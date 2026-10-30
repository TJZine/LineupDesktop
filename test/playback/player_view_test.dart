import '../support/device_profile_test_support.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Tristate;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/app/lineup_shell.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/native_video_surface.dart';
import 'package:lineup_desktop/playback/player_coordinator.dart';
import 'package:lineup_desktop/playback/player_view.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/app_ui.dart';

import '../support/golden_test_support.dart';
import '../support/test_doubles.dart';

final _fixtureArtwork = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);
final _fixtureLogoArtwork = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAlgAAAB4AQMAAAAUmx6AAAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAADUExURfPo0u6COk8AAAAHdElNRQfqCQwOHSj8iqZhAAAAJXRFWHRkYXRlOmNyZWF0ZQAyMDI2LTA5LTEyVDE0OjI5OjQwKzAwOjAw3a1YngAAACV0RVh0ZGF0ZTptb2RpZnkAMjAyNi0wOS0xMlQxNDoyOTo0MCswMDowMKzw4CIAAAAodEVYdGRhdGU6dGltZXN0YW1wADIwMjYtMDktMTJUMTQ6Mjk6NDArMDA6MDD75cH9AAAAIElEQVRo3u3BMQEAAADCoPVPbQo/oAAAAAAAAAAAgJcBI6AAAZ0TDkkAAAAASUVORK5CYII=',
);
final _extremeWideArtwork = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAABLAAAAAUCAIAAAASgVNzAAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAAGYktHRAD/AP8A/6C9p5MAAAAHdElNRQfqCQQBEhHq/110AAAAJXRFWHRkYXRlOmNyZWF0ZQAyMDI2LTA5LTA0VDAxOjE4OjE3KzAwOjAwct2ViQAAACV0RVh0ZGF0ZTptb2RpZnkAMjAyNi0wOS0wNFQwMToxODoxNyswMDowMAOALTUAAAAodEVYdGRhdGU6dGltZXN0YW1wADIwMjYtMDktMDRUMDE6MTg6MTcrMDA6MDBUlQzqAAAAjUlEQVR42u3XMQEAIAzAMMC/5yFjRxMFfXtn5gAAANDztgMAAADYYQgBAACiDCEAAECUIQQAAIgyhAAAAFGGEAAAIMoQAgAARBlCAACAKEMIAAAQZQgBAACiDCEAAECUIQQAAIgyhAAAAFGGEAAAIMoQAgAARBlCAACAKEMIAAAQZQgBAACiDCEAAEDUB/B/AyWGhzYyAAAAAElFTkSuQmCC',
);

Widget _playerDesktopCanvasBuilder(BuildContext context, Widget? child) =>
    DeviceProfileScope(
      profile: desktopProfile,
      child: LineupCanvas(child: child ?? const SizedBox.shrink()),
    );

Widget _playerTvCanvasBuilder(BuildContext context, Widget? child) =>
    DeviceProfileScope(
      profile: tvProfile,
      child: LineupCanvas(child: child ?? const SizedBox.shrink()),
    );

TransitionBuilder _playerCanvasBuilderFor(bool tv) =>
    (_, child) => DeviceProfileScope(
      profile: profileFor(tv),
      child: LineupCanvas(child: child ?? const SizedBox.shrink()),
    );

void main() {
  tearDown(debugResetClearLogoCache);

  testWidgets(
    'hidden progress leaves Player subtree idle and visible OSD progress stays live',
    (tester) async {
      final fixture = _Fixture(
        PlayerState.playing,
        overlayTimeout: const Duration(minutes: 1),
        dvrControlsEnabled: true,
      );
      addTearDown(fixture.dispose);
      await fixture.player.tune('channel');
      fixture.native.emitState(PlayerState.playing);
      await tester.pump();
      await tester.pump();
      fixture.player.closeOverlay();
      await tester.pumpWidget(
        MaterialApp(
          builder: LineupCanvas.builder,
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pumpAndSettle();
      final rebuilt = <String>[];
      debugOnRebuildDirtyWidget = (element, _) =>
          rebuilt.add(element.widget.runtimeType.toString());
      addTearDown(() => debugOnRebuildDirtyWidget = null);
      fixture.native.emitState(
        PlayerState.playing,
        at: const Duration(minutes: 11),
      );
      await tester.pump();
      await tester.pump();
      expect(fixture.player.position, const Duration(minutes: 11));
      expect(rebuilt, isEmpty);
      fixture.native.emitState(
        PlayerState.buffering,
        at: const Duration(minutes: 11),
      );
      await tester.pump();
      await tester.pump();
      expect(rebuilt, contains('PlayerView'));
      expect(find.bySemanticsLabel('Buffering playback'), findsOneWidget);
      fixture.native.emitState(
        PlayerState.playing,
        at: const Duration(minutes: 11),
      );
      fixture.player.showOsd();
      await tester.pumpAndSettle();
      final before = tester.widget<Slider>(find.byType(Slider)).value;
      rebuilt.clear();
      fixture.native.emitState(
        PlayerState.playing,
        at: const Duration(minutes: 12),
      );
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<Slider>(find.byType(Slider)).value,
        greaterThan(before),
      );
      expect(rebuilt, isNot(contains('PlayerView')));
      expect(rebuilt, isNot(contains('_Osd')));
      fixture.player.showNowPlaying();
      await tester.pumpAndSettle();
      rebuilt.clear();
      fixture.native.emitState(
        PlayerState.playing,
        at: const Duration(minutes: 13),
      );
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<Slider>(find.byType(Slider)).value,
        greaterThan(before),
      );
      expect(rebuilt, isNot(contains('PlayerView')));
      expect(rebuilt, isNot(contains('_NowPlaying')));
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
    semanticsEnabled: true,
  );

  for (final tv in [false, true]) {
    for (final reduceMotion in [false, true]) {
      testWidgets('channel tag motion tv=$tv reduceMotion=$reduceMotion', (
        tester,
      ) async {
        await tester.runAsync(loadPinnedTestFonts);
        await tester.binding.setSurfaceSize(
          tv ? const Size(960, 540) : const Size(1920, 1080),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final fixture = _Fixture(
          PlayerState.playing,
          overlayTimeout: const Duration(minutes: 1),
        );
        final captureKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: LineupTheme.forName(
                LineupThemeName.emberSteel,
                formFactor: profileFor(tv).formFactor,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(disableAnimations: reduceMotion),
                child: _playerCanvasBuilderFor(tv)(context, child),
              ),
              home: PlayerView(controller: fixture.player, openGuide: () {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final tag = find.byKey(const Key('player-osd-channel-bug'));
        expect(tag, findsNothing);
        fixture.player.showOsd();
        await tester.pump();
        final entryTops = <double>[];
        for (var frame = 0; frame <= 4; frame++) {
          if (frame > 0) await tester.pump(const Duration(microseconds: 87500));
          final opacity = _channelTagOpacity(tester);
          if (frame == 0) expect(opacity, 0);
          if (frame > 0 && frame < 4) {
            expect(opacity, allOf(greaterThan(0), lessThan(1)));
          }
          entryTops.add(_drawnRect(tester, tag).top);
          await _captureChannelTag(
            tester,
            captureKey,
            'tv-$tv-reduce-$reduceMotion-entry-$frame',
            tv: tv,
          );
        }
        expect(_channelTagOpacity(tester), 1);
        final restingTop = entryTops.last;
        expect(
          entryTops.first,
          closeTo(
            restingTop -
                (reduceMotion
                    ? 0
                    : tv
                    ? 6
                    : 12),
            .01,
          ),
        );
        for (final top in entryTops.take(4)) {
          if (reduceMotion) {
            expect(top, restingTop);
          } else {
            expect(top, lessThan(restingTop));
          }
        }
        expect(tester.getSemantics(tag).label, 'Channel 7, Channel');
        fixture.player.closeOverlay();
        await tester.pump();
        for (var frame = 0; frame <= 4; frame++) {
          if (frame > 0) await tester.pump(const Duration(microseconds: 87500));
          if (frame < 4) {
            final opacity = _channelTagOpacity(tester);
            if (frame == 0) expect(opacity, 1);
            if (frame > 0) expect(opacity, allOf(greaterThan(0), lessThan(1)));
            final top = _drawnRect(tester, tag).top;
            expect(
              top,
              reduceMotion ? restingTop : lessThanOrEqualTo(restingTop),
            );
            if (!reduceMotion && frame > 0) expect(top, lessThan(restingTop));
          } else {
            expect(tag, findsNothing);
          }
          await _captureChannelTag(
            tester,
            captureKey,
            'tv-$tv-reduce-$reduceMotion-exit-$frame',
            tv: tv,
          );
        }
        await fixture.player.tune('channel');
        fixture.player.closeOverlay();
        fixture.native.emitState(PlayerState.playing);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.byKey(const Key('player-osd-surface')), findsNothing);
        expect(_channelTagOpacity(tester), 1);
        await _captureChannelTag(
          tester,
          captureKey,
          'tv-$tv-reduce-$reduceMotion-tune-window',
          tv: tv,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
      }, semanticsEnabled: true);
    }
  }

  for (final dismissAfterPlaying in [false, true]) {
    testWidgets(
      'channel tag gets four seconds from playing, dismissAfterPlaying=$dismissAfterPlaying',
      (tester) async {
        final fixture = _Fixture(PlayerState.playing, channelCount: 2);
        final captureKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: MaterialApp(
              builder: LineupCanvas.builder,
              home: PlayerView(controller: fixture.player, openGuide: () {}),
            ),
          ),
        );
        await fixture.player.tune('channel-1');
        fixture.native.emitState(PlayerState.loading);
        if (!dismissAfterPlaying) fixture.player.closeOverlay();
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        expect(fixture.player.channelTagWindowActive, isFalse);
        expect(fixture.player.busyLabel, isNotNull);
        expect(find.byKey(const Key('player-osd-channel-bug')), findsNothing);
        fixture.native.emitState(PlayerState.playing);
        await tester.pump();
        if (dismissAfterPlaying) fixture.player.closeOverlay();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(fixture.player.channelTagWindowActive, isTrue);
        expect(_channelTagOpacity(tester), 1);
        expect(find.byKey(const Key('player-osd-surface')), findsNothing);
        await _captureChannelTag(
          tester,
          captureKey,
          'tune-window-dismiss-$dismissAfterPlaying',
        );
        await tester.pump(const Duration(milliseconds: 3649));
        expect(fixture.player.channelTagWindowActive, isTrue);
        fixture.native.emitState(
          PlayerState.playing,
        ); // Repeated playing never renews it.
        await tester.pump(const Duration(milliseconds: 1));
        expect(fixture.player.channelTagWindowActive, isFalse);
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.byKey(const Key('player-osd-channel-bug')), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
      },
    );
  }

  testWidgets(
    'channel tag follows OSD without restarting during the tune window',
    (tester) async {
      final fixture = _Fixture(
        PlayerState.playing,
        overlayTimeout: const Duration(minutes: 1),
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: LineupCanvas.builder,
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await fixture.player.tune('channel');
      fixture.player.closeOverlay();
      await tester.pumpAndSettle();
      fixture.native.emitState(PlayerState.playing);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 175));
      final halfway = _channelTagOpacity(tester);
      expect(halfway, allOf(greaterThan(0), lessThan(1)));
      final tag = find.byKey(const Key('player-osd-channel-bug'));
      final element = tester.element(tag);
      fixture.player.showOsd();
      await tester.pump();
      expect(_channelTagOpacity(tester), halfway);
      expect(tester.element(tag), same(element));
      await tester.pump(const Duration(milliseconds: 175));
      expect(_channelTagOpacity(tester), 1);
      await tester.pump(const Duration(seconds: 4));
      expect(fixture.player.channelTagWindowActive, isFalse);
      expect(tag, findsOneWidget);
      fixture.player.showNowPlaying();
      await tester.pumpAndSettle();
      expect(_channelTagOpacity(tester), 1);
      fixture.player.closeOverlay();
      await tester.pumpAndSettle();
      expect(tag, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
  );

  testWidgets('channel tag suppression applies during the tune window', (
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
        builder: LineupCanvas.builder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    final suppressors = <VoidCallback>[
      () => fixture.player.appendChannelDigit('9'),
      () {
        fixture.player.showNowPlaying();
        fixture.player.showProgramInfo();
      },
      fixture.player.showMiniGuide,
      fixture.player.showFullGuide,
      () => fixture.player.showTracks(PlayerTrackType.audio),
      () => fixture.player.showTracks(PlayerTrackType.subtitle),
      () => fixture.native.emitState(PlayerState.error),
    ];
    for (final suppress in suppressors) {
      await fixture.player.tune('channel');
      fixture.native.emitState(PlayerState.playing);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('player-osd-channel-bug')), findsOneWidget);
      suppress();
      await tester.pump();
      await tester
          .pump(); // Deliver native events and paint, without advancing time.
      expect(find.byKey(const Key('player-osd-channel-bug')), findsNothing);
    }
    await fixture.player.tune('channel');
    fixture.native.emitState(PlayerState.playing);
    await tester.pumpAndSettle();
    fixture.player.appendChannelDigit('9');
    await fixture.player.commitChannelNumber();
    fixture.player.showOsd();
    await tester.pump();
    expect(fixture.player.notice, isNotNull);
    expect(find.byKey(const Key('player-osd-channel-bug')), findsNothing);
    // Busy suppression, independently of the overlay and notice timeout.
    await fixture.player.tune('channel');
    fixture.native.emitState(PlayerState.playing);
    await tester.pumpAndSettle();
    fixture.native.emitState(PlayerState.buffering);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(fixture.player.busyLabel, isNotNull);
    expect(find.byKey(const Key('player-osd-channel-bug')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets(
    'visible cast surfaces share the hydrated shelf, semantics, and TV More info',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = _Fixture(
        PlayerState.playing,
        richItemOverride: _fixtureItem(
          0,
          rich: true,
          duration: const Duration(hours: 24),
          summary: 'Short synopsis.',
          cast: [
            ChannelCastMember(name: 'Catalog Actor', role: 'Catalog role'),
          ],
        ),
      );
      final pending = Completer<List<PlexCastMember>?>();
      fixture.lineup.castHandler = (_) => pending.future;
      await tester.pumpWidget(
        MaterialApp(
          theme: LineupTheme.forName(
            LineupThemeName.emberSteel,
            formFactor: profileFor(true).formFactor,
          ),
          builder: _playerTvCanvasBuilder,
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pumpAndSettle();
      await fixture.player.tune('channel');
      fixture.player.showOsd();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('player-osd-surface')), findsOneWidget);
      expect(find.byKey(const Key('player-osd-title')), findsOneWidget);
      expect(fixture.lineup.castRequests, isEmpty);
      fixture.player.showNowPlaying();
      await tester.pumpAndSettle();
      expect(fixture.lineup.castRequests, ['program']);
      expect(find.text('Catalog Actor'), findsOneWidget);
      expect(find.byKey(const Key('player-more-info')), findsNothing);
      pending.complete(const [
        PlexCastMember(
          name: 'Detail Lead',
          role: 'Lead',
          thumbPath: '/hydrated/lead',
        ),
        PlexCastMember(name: 'Catalog Actor', role: 'Detail role'),
        PlexCastMember(name: 'Detail Third'),
        PlexCastMember(name: 'Detail Fourth'),
        PlexCastMember(name: 'Detail Fifth', role: 'Guest'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Detail Lead'), findsOneWidget);
      expect(
        find.byKey(const Key('player-now-playing-cast-portrait-0')),
        findsOneWidget,
      );
      expect(
        fixture.lineup.artworkRequests,
        contains(Uri.parse('/hydrated/lead')),
      );
      expect(find.text('Detail Fourth'), findsOneWidget);
      expect(find.text('Detail Fifth'), findsNothing);
      expect(
        find.bySemanticsLabel(
          RegExp('Cast: Detail Lead as Lead, Catalog Actor as Detail role'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('player-more-info')), findsOneWidget);
      await tester.tap(find.byKey(const Key('player-more-info')));
      await tester.pumpAndSettle();
      expect(find.text('Detail Fifth'), findsOneWidget);
      expect(find.text('Guest'), findsOneWidget);
      expect(fixture.lineup.castRequests, ['program']);
      expect(
        fixture.player.currentProgram!.scheduled.item.cast.single.name,
        'Catalog Actor',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
    semanticsEnabled: true,
  );

  for (final size in [
    const Size(1280, 720),
    const Size(1920, 1080),
    const Size(960, 540),
  ]) {
    testWidgets('R2 matched Player size=$size', (tester) async {
      await tester.runAsync(loadPinnedTestFonts);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final tv = size.width == 960;
      debugDefaultTargetPlatformOverride = tv
          ? TargetPlatform.android
          : TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final fixture = _Fixture(
        PlayerState.playing,
        guideClock: () => DateTime(2026, 1, 15, 12),
        richItemOverride: _fixtureItem(
          0,
          rich: true,
          duration: const Duration(hours: 24),
          summary: List.filled(20, 'A synthetic synopsis.').join(' '),
          cast: _fixtureCast,
        ),
        tracks: const [
          PlayerTrack(
            id: 1,
            type: PlayerTrackType.audio,
            selected: true,
            language: 'eng',
          ),
        ],
      );
      await fixture.guide.ensureCurrentProgram('channel');
      fixture.player.showNowPlaying();
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            theme: LineupTheme.forName(
              LineupThemeName.emberSteel,
              formFactor: profileFor(tv).formFactor,
            ),
            builder: _playerCanvasBuilderFor(tv),
            home: PlayerView(controller: fixture.player, openGuide: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _settleNowPlayingArtwork(tester);
      await _r2Capture(
        tester,
        captureKey,
        'matched-$tv-${size.width.toInt()}-NowPlaying',
      );
      fixture.player.showMiniGuide();
      await tester.pumpAndSettle();
      await _r2Capture(
        tester,
        captureKey,
        'matched-$tv-${size.width.toInt()}-MiniGuide',
      );
      fixture.player.showOsd();
      fixture.player.showTracks(PlayerTrackType.audio);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('playback-options-rail')), findsOneWidget);
      await _r2Capture(
        tester,
        captureKey,
        'matched-$tv-${size.width.toInt()}-Audio',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
      debugDefaultTargetPlatformOverride = null;
    }, skip: Platform.environment['R2_CAPTURE'] == null);
  }

  for (final variant in [
    (tv: true, long: false, cast: 4, shown: false),
    (tv: true, long: true, cast: 4, shown: true),
    (tv: true, long: false, cast: 24, shown: true),
    (tv: false, long: true, cast: 24, shown: false),
  ]) {
    testWidgets('O1 More info uses actual synopsis and cast clamp $variant', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final item = _fixtureItem(
        0,
        rich: true,
        duration: const Duration(hours: 24),
        summary: variant.long
            ? List.filled(50, 'A lengthy program synopsis.').join(' ')
            : 'Short synopsis.',
        cast: List.generate(
          variant.cast,
          (i) => ChannelCastMember(name: 'Performer $i', role: 'Role $i'),
        ),
      );
      final fixture = _Fixture(PlayerState.playing, richItemOverride: item);
      await fixture.player.tune('channel');
      fixture.player.showNowPlaying();
      await tester.pumpWidget(
        MaterialApp(
          theme: LineupTheme.forName(
            LineupThemeName.emberSteel,
            formFactor: profileFor(variant.tv).formFactor,
          ),
          builder: _playerCanvasBuilderFor(variant.tv),
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('player-more-info')),
        variant.shown ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    });
  }

  for (final large in [false, true]) {
    for (final textScale in [1.0, 1.3]) {
      testWidgets(
        'O1 remote reads full drawer and returns Large=$large scale=$textScale',
        (tester) async {
          await tester.runAsync(loadPinnedTestFonts);
          await tester.binding.setSurfaceSize(const Size(960, 540));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final item = _fixtureItem(
            0,
            rich: true,
            duration: const Duration(hours: 24),
            summary: List.filled(
              30,
              'A lengthy program synopsis with all its details.',
            ).join(' '),
            cast: List.generate(
              24,
              (i) => ChannelCastMember(name: 'Performer $i', role: 'Role $i'),
            ),
          );
          final fixture = _Fixture(
            PlayerState.playing,
            richItemOverride: item,
            guideClock: () => DateTime(2026, 1, 15, 12),
          );
          await fixture.lineup.updateSettings(
            (s) => s.copyWith(reduceMotion: large, largeFocusIndicators: large),
          );
          await fixture.player.tune('channel');
          fixture.player.showNowPlaying();
          final captureKey = GlobalKey();
          await tester.pumpWidget(
            DeviceProfileScope(
              profile: profileFor(true),
              child: RepaintBoundary(
                key: captureKey,
                child: MaterialApp(
                  theme: LineupTheme.forName(
                    LineupThemeName.emberSteel,
                    formFactor: profileFor(true).formFactor,
                    largeFocusIndicators: large,
                  ),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(textScale)),
                    child: LineupCanvas(reduceMotion: large, child: child!),
                  ),
                  home: PlayerView(
                    controller: fixture.player,
                    openGuide: () {},
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          Future<void> key(LogicalKeyboardKey key) async {
            await tester.sendKeyEvent(key);
            await tester.pumpAndSettle();
          }

          final shelf = tester.getRect(
            find.byKey(const Key('player-now-playing-details')),
          );
          final fourthRole = tester.getRect(
            find.byKey(const ValueKey('player-now-playing-cast-role-3')),
          );
          expect(fourthRole.bottom, lessThanOrEqualTo(shelf.bottom + .1));
          expect(
            tester
                .getRect(find.byKey(const Key('player-now-playing-collapse')))
                .top,
            greaterThanOrEqualTo(27),
          );
          await _r2Capture(
            tester,
            captureKey,
            'now-playing-entry-large$large-scale$textScale',
          );
          final more = find.byKey(const Key('player-more-info'));
          await key(LogicalKeyboardKey.arrowUp);
          expect(Focus.of(tester.element(more)).hasFocus, isTrue);
          await _r2Capture(
            tester,
            captureKey,
            'now-playing-large$large-scale$textScale',
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
          await tester.pump();
          expect(
            tester
                .widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher).first)
                .duration,
            large ? Duration.zero : const Duration(milliseconds: 300),
          );
          expect(find.byKey(const Key('player-osd-surface')), findsNothing);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('player-more-info-close')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('player-more-info-cast-23')),
            findsOneWidget,
          );
          expect(
            tester
                .widget<Text>(find.byKey(const Key('player-more-info-summary')))
                .maxLines,
            isNull,
          );
          await _r2Capture(
            tester,
            captureKey,
            'info-entry-large$large-scale$textScale',
          );
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'More info reading',
          );
          expect(fixture.player.overlay.name, 'programInfo');
          expect(find.byKey(const Key('player-osd-surface')), findsNothing);
          expect(find.byKey(const Key('player-osd-channel-bug')), findsNothing);
          expect(find.text('Up/Down Scroll · Back Close'), findsOneWidget);
          final reader = find.byKey(const Key('player-more-info-reading'));
          expect(Focus.of(tester.element(reader)).hasPrimaryFocus, isTrue);
          final decoration =
              tester.widget<DecoratedBox>(reader).decoration as BoxDecoration;
          expect(decoration.color, isNull);
          expect(
            (decoration.border! as Border).left,
            const BorderSide(color: Color(0xFFE9DCC3), width: 4),
          );
          expect(
            tester
                .widget<RawScrollbar>(
                  find.byKey(const Key('player-more-info-scrollbar')),
                )
                .thickness,
            4,
          );
          expect(
            tester
                .widget<RawScrollbar>(
                  find.byKey(const Key('player-more-info-scrollbar')),
                )
                .thumbColor,
            const Color(0xFFE9DCC3),
          );
          final summaryInk = tester
              .widget<RichText>(
                find.descendant(
                  of: find.byKey(const Key('player-more-info-summary')),
                  matching: find.byType(RichText),
                ),
              )
              .text
              .style!
              .color;
          expect(summaryInk, const Color(0xFFF3E8D2));
          await _expectInfoPaint(
            tester,
            captureKey,
            reader,
            focused: true,
            name: 'paint-large$large-scale$textScale-reader',
          );
          await _r2Capture(
            tester,
            captureKey,
            'info-top-large$large-scale$textScale',
          );
          final scroll = tester
              .widget<SingleChildScrollView>(
                find.byKey(const Key('player-more-info-scroll')),
              )
              .controller!;
          for (
            var n = 0;
            n < 160 && scroll.offset < scroll.position.maxScrollExtent;
            n++
          ) {
            await key(LogicalKeyboardKey.arrowDown);
          }
          expect(scroll.offset, scroll.position.maxScrollExtent);
          final last = tester.getRect(
            find.byKey(const Key('player-more-info-cast-23')),
          );
          final viewport = tester.getRect(reader);
          expect(last.top, greaterThanOrEqualTo(viewport.top));
          expect(last.bottom, lessThanOrEqualTo(viewport.bottom));
          await _r2Capture(
            tester,
            captureKey,
            'info-end-large$large-scale$textScale',
          );
          for (var n = 0; n < 160 && scroll.offset > 0; n++) {
            await key(LogicalKeyboardKey.arrowUp);
          }
          expect(scroll.offset, 0);
          await key(LogicalKeyboardKey.arrowUp);
          expect(
            tester
                .widget<TextButton>(
                  find.byKey(const Key('player-more-info-close')),
                )
                .focusNode!
                .hasPrimaryFocus,
            isTrue,
          );
          await _expectInfoPaint(
            tester,
            captureKey,
            reader,
            focused: false,
            name: 'paint-large$large-scale$textScale-close',
          );
          await _r2Capture(
            tester,
            captureKey,
            'info-close-large$large-scale$textScale',
          );
          await key(LogicalKeyboardKey.select);
          expect(Focus.of(tester.element(more)).hasFocus, isTrue);
          await _r2Capture(
            tester,
            captureKey,
            'info-return-large$large-scale$textScale',
          );
          await key(LogicalKeyboardKey.arrowUp);
          await key(LogicalKeyboardKey.arrowDown);
          expect(Focus.of(tester.element(more)).hasFocus, isTrue);
          await key(LogicalKeyboardKey.select);
          await key(LogicalKeyboardKey.escape);
          expect(Focus.of(tester.element(more)).hasFocus, isTrue);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          fixture.dispose();
        },
      );
    }
  }

  testWidgets('O1 amendment reader owns initial focus', (tester) async {
    final fixture = _amendmentFixture();
    await _openInfoForAmendment(tester, fixture);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'More info reading');
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('O1 amendment reader paint stays dark instead of inverting', (
    tester,
  ) async {
    final fixture = _amendmentFixture();
    await _openInfoForAmendment(tester, fixture);
    // On d155 entry is Close; establish its old reading state to isolate paint.
    if (FocusManager.instance.primaryFocus?.debugLabel != 'More info reading') {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    final text = tester.widget<RichText>(
      find.descendant(
        of: find.byKey(const Key('player-more-info-summary')),
        matching: find.byType(RichText),
      ),
    );
    expect(text.text.style?.color, const Color(0xFFF3E8D2));
    expect(find.byKey(const Key('player-more-info-scrollbar')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });
  testWidgets('O1 amendment replaces chrome without a Navigator route', (
    tester,
  ) async {
    final fixture = _amendmentFixture();
    await _openInfoForAmendment(tester, fixture);
    expect(find.byKey(const Key('player-osd-surface')), findsNothing);
    expect(find.byKey(const Key('player-osd-channel-bug')), findsNothing);
    expect(find.byKey(const Key('player-status-bug')), findsNothing);
    expect(find.text('Up/Down Scroll · Back Close'), findsOneWidget);
    expect(
      Navigator.of(
        tester.element(find.byKey(const Key('player-more-info-close'))),
      ).canPop(),
      isFalse,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  for (final dvr in [false, true]) {
    for (final key in [
      LogicalKeyboardKey.mediaPlayPause,
      LogicalKeyboardKey.mediaPause,
      LogicalKeyboardKey.mediaPlay,
    ]) {
      testWidgets('O1 amendment media action $key DVR=$dvr', (tester) async {
        final fixture = _amendmentFixture(dvr: dvr);
        fixture.native.emitControlEvents = true;
        await _openInfoForAmendment(tester, fixture);
        final count = fixture.native.pausedValues.length;
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        if (dvr) {
          final pause = key != LogicalKeyboardKey.mediaPlay;
          expect(fixture.native.pausedValues.skip(count), [pause]);
          expect(
            fixture.player.status.state,
            pause ? PlayerState.paused : PlayerState.playing,
          );
        } else {
          expect(fixture.native.pausedValues.length, count);
        }
        expect(fixture.player.overlay.name, 'programInfo');
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'More info reading',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
      });
    }
  }
  for (final key in [
    LogicalKeyboardKey.channelUp,
    LogicalKeyboardKey.channelDown,
  ]) {
    testWidgets('O1 amendment actual channel action $key', (tester) async {
      final fixture = _amendmentFixture(channels: 3);
      await _openInfoForAmendment(tester, fixture);
      final before = fixture.native.loadCalls;
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(
        fixture.lineup.currentChannelId,
        key == LogicalKeyboardKey.channelUp ? 'channel-2' : 'channel-1',
      );
      expect(fixture.native.loadCalls, greaterThan(before));
      expect(find.byKey(const Key('player-more-info-reading')), findsNothing);
      expect(FocusManager.instance.primaryFocus?.context, isNotNull);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot('More info reading'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    });
  }
  testWidgets('O1 amendment Close keeps media PlayPause in Player policy', (
    tester,
  ) async {
    final fixture = _amendmentFixture(dvr: true);
    fixture.native.emitControlEvents = true;
    await _openInfoForAmendment(tester, fixture);
    if (FocusManager.instance.primaryFocus?.debugLabel == 'More info reading') {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pumpAndSettle();
    expect(fixture.native.pausedValues, [true]);
    expect(fixture.player.status.state, PlayerState.paused);
    expect(fixture.player.overlay.name, 'programInfo');
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'More info Close');
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets(
    'O1 amendment reads a real scheduled boundary live and safely returns without invoker',
    (tester) async {
      var now = DateTime(2026, 1, 15, 12);
      final fixture = _amendmentFixture(now: () => now, short: true);
      await _openInfoForAmendment(tester, fixture);
      final old = fixture.player.currentProgram!.id;
      final scroll = tester
          .widget<SingleChildScrollView>(
            find.byKey(const Key('player-more-info-scroll')),
          )
          .controller!;
      if (FocusManager.instance.primaryFocus?.debugLabel !=
          'More info reading') {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      now = now.add(const Duration(hours: 1));
      fixture.guide.playToNow();
      fixture.native.emitState(PlayerState.ended, at: const Duration(hours: 1));
      await tester.pumpAndSettle();
      expect(fixture.native.loadCalls, 2);
      expect(fixture.player.currentProgram!.id, isNot(old));
      expect(
        fixture.player.currentProgram!.scheduled.item.title,
        'Replacement Program',
      );
      expect(find.text('Replacement Program'), findsOneWidget);
      expect(find.text('Program'), findsNothing);
      expect(scroll.offset, 0);
      expect(fixture.player.overlay.name, 'programInfo');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(fixture.player.overlay, PlayerOverlay.nowPlaying);
      expect(find.byKey(const Key('player-more-info')), findsNothing);
      final sleep = tester
          .widget<TextButton>(find.byKey(const Key('player-osd-sleep')))
          .focusNode!;
      final close = tester
          .widget<TextButton>(
            find.byKey(const Key('player-now-playing-collapse')),
          )
          .focusNode!;
      // A retired FocusNode keeps its last context. Prove an attached action
      // receives focus and that the absent More info action is skipped both ways.
      expect(sleep.hasPrimaryFocus, isTrue);
      expect(sleep.parent, isNotNull);
      final transportCommands = fixture.native.transportCommands;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(close.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(sleep.hasPrimaryFocus, isTrue);
      expect(fixture.native.transportCommands, transportCommands);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
  );
  for (final failure in ['stop', 'error']) {
    testWidgets('O1 amendment $failure retires reader to live recovery focus', (
      tester,
    ) async {
      final fixture = _amendmentFixture(dvr: true);
      await _openInfoForAmendment(tester, fixture);
      if (failure == 'stop') {
        await tester.sendKeyEvent(LogicalKeyboardKey.mediaStop);
      } else {
        fixture.native.emitState(PlayerState.error);
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('player-more-info-reading')), findsNothing);
      expect(FocusManager.instance.primaryFocus?.context, isNotNull);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot('More info reading'),
      );
      expect(
        Focus.of(
          tester.element(
            find.text(failure == 'error' ? 'Retry' : 'Browse channels'),
          ),
        ).hasFocus,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    });
  }

  testWidgets('C5 TV Mini Guide virtual cursor paints cream and leaf ink', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing, channelCount: 12);
    await fixture.player.tune('channel');
    fixture.player.showMiniGuide();
    await tester.pumpWidget(
      MaterialApp(
        theme: LineupTheme.forName(
          LineupThemeName.emberSteel,
          formFactor: profileFor(true).formFactor,
        ),
        builder: _playerTvCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pumpAndSettle();
    // Establish remote modality first so this negative isolates virtual-cursor
    // paint from the separate cold-focus correction.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final owner = FocusManager.instance.primaryFocus;
    for (var i = 0; i < 13; i++) {
      final id = fixture.player.miniGuideChannelId!;
      final text = find.byKey(Key('mini-guide-channel-$id'));
      final rich = find
          .descendant(of: text, matching: find.byType(RichText))
          .first;
      expect(
        tester.widget<RichText>(rich).text.style?.color,
        const Color(0xFF090806),
      );
      expect(tester.widget<RichText>(rich).text.style?.shadows, isEmpty);
      final row = find
          .ancestor(of: text, matching: find.byType(LineupRowSurface))
          .first;
      for (final text in tester.widgetList<RichText>(
        find.descendant(of: row, matching: find.byType(RichText)),
      )) {
        if (text.text.style?.fontFamily == 'MaterialIcons') continue;
        expect(
          text.text.style?.shadows ?? const [],
          isEmpty,
          reason: text.text.toPlainText(),
        );
      }
      final paints = find.descendant(
        of: row,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).color == const Color(0xFFE9DCC3),
        ),
      );
      expect(paints, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(owner));
    }
    // Pointer modality hides the fill; restore the ordinary overlay shadow.
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(5, 5));
    await mouse.moveTo(const Offset(10, 10));
    await tester.pumpAndSettle();
    final cursor = find.byKey(
      Key('mini-guide-channel-${fixture.player.miniGuideChannelId}'),
    );
    final pointerText = tester.widget<RichText>(
      find.descendant(of: cursor, matching: find.byType(RichText)).first,
    );
    expect(pointerText.text.style?.shadows, isNotEmpty);
    expect(pointerText.text.style?.color, const Color(0xFFF3E8D2));
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets(
    'TV Sleep presets keep focus ink separate from selected preset in touch mode',
    (tester) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      final fixture = _Fixture(PlayerState.playing);
      fixture.player.showOsd();
      fixture.player.showSleepTimer();
      await tester.pumpWidget(
        MaterialApp(
          theme: LineupTheme.forName(
            LineupThemeName.emberSteel,
            formFactor: profileFor(true).formFactor,
          ),
          builder: _playerTvCanvasBuilder,
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pumpAndSettle();
      Color? ink(String text) => tester
          .widget<RichText>(
            find.descendant(
              of: find.text(text),
              matching: find.byType(RichText),
            ),
          )
          .text
          .style
          ?.color;
      final off = tester.element(find.byKey(const Key('sleep-timer-off')));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.highlightMode, FocusHighlightMode.touch);
      expect(ink('30 minutes'), const Color(0xFF090806));
      expect(ink('Off'), const Color(0xFFF3E8D2));
      expect(fixture.player.sleepDuration, isNull);
      expect(
        tester.element(find.byKey(const Key('sleep-timer-off'))),
        same(off),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(fixture.player.sleepDuration, const Duration(minutes: 30));
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
  );
  for (final state in [
    PlayerState.error,
    PlayerState.stopped,
    PlayerState.unsupported,
  ]) {
    testWidgets(
      'TV recovery slate owns remote focus and retires controls: $state',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        tester.view
          ..physicalSize = const Size(1920, 1080)
          ..devicePixelRatio = 2;
        final fixture = _Fixture(
          state == PlayerState.error ? PlayerState.playing : state,
          failLoad: state == PlayerState.error,
        );
        final root = FocusNode();
        var closed = false;
        Future<void> key(LogicalKeyboardKey key) async {
          await tester.sendKeyEvent(
            key,
            physicalKey: key == LogicalKeyboardKey.goBack
                ? PhysicalKeyboardKey.escape
                : null,
          );
          await tester.pumpAndSettle();
        }

        bool focused(String label) =>
            Focus.of(tester.element(find.text(label))).hasFocus;
        try {
          if (state == PlayerState.error) {
            await fixture.player.tune('channel');
            expect(fixture.player.canRetry, isTrue);
          }
          await tester.pumpWidget(
            MaterialApp(
              theme: LineupTheme.forName(
                LineupThemeName.emberSteel,
                formFactor: profileFor(true).formFactor,
              ),
              builder: _playerTvCanvasBuilder,
              home: PlayerView(
                controller: fixture.player,
                focusNode: root,
                openGuide: () => closed = true,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            focused(state == PlayerState.error ? 'Retry' : 'Browse channels'),
            isTrue,
          );
          if (state == PlayerState.error) {
            await key(LogicalKeyboardKey.arrowRight);
          }
          expect(focused('Browse channels'), isTrue);
          for (var i = 0; i < 3; i++) {
            fixture.lineup.notifyListeners();
            await tester.pumpAndSettle();
            expect(
              focused('Browse channels'),
              isTrue,
              reason: 'Rebuilds must not restart autofocus',
            );
          }
          await key(LogicalKeyboardKey.arrowRight);
          expect(focused('Close'), isTrue);
          await key(LogicalKeyboardKey.arrowLeft);
          expect(focused('Browse channels'), isTrue);
          await key(LogicalKeyboardKey.select);
          expect(fixture.player.overlay, PlayerOverlay.miniGuide);
          expect(
            tester.semantics.simulatedAccessibilityTraversal().any(
              (node) =>
                  node.getSemanticsData().label == 'Browse channels' &&
                  node.getSemanticsData().hasAction(SemanticsAction.tap),
            ),
            isFalse,
          );
          await key(LogicalKeyboardKey.goBack);
          expect(
            focused(state == PlayerState.error ? 'Retry' : 'Browse channels'),
            isTrue,
          );
          if (state == PlayerState.error) {
            final loads = fixture.native.loadCalls;
            fixture.native.failLoad = false;
            await key(LogicalKeyboardKey.select);
            expect(fixture.native.loadCalls, greaterThan(loads));
            expect(fixture.player.error, isNull);
            expect(find.widgetWithText(FilledButton, 'Retry'), findsNothing);
            expect(root.hasPrimaryFocus, isTrue);
          } else {
            await key(LogicalKeyboardKey.arrowRight);
            await key(LogicalKeyboardKey.select);
            expect(closed, isTrue);
            expect(find.bySemanticsLabel('Browse channels'), findsNothing);
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          fixture.dispose();
          root.dispose();
          tester.view.reset();
          debugDefaultTargetPlatformOverride = null;
        }
      },
      semanticsEnabled: true,
    );
  }
  for (final dvr in [false, true]) {
    testWidgets('TV Player remote action and return model DVR=$dvr', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view
        ..physicalSize = const Size(1920, 1080)
        ..devicePixelRatio = 2;
      final root = FocusNode();
      final fixture = _Fixture(
        PlayerState.playing,
        richProgram: true,
        dvrControlsEnabled: dvr,
        overlayTimeout: const Duration(seconds: 3),
        tracks: const [
          PlayerTrack(
            id: 1,
            type: PlayerTrackType.audio,
            title: 'English',
            selected: true,
          ),
          PlayerTrack(
            id: 2,
            type: PlayerTrackType.subtitle,
            title: 'English',
            selected: false,
          ),
        ],
      );
      Future<void> key(LogicalKeyboardKey key) async {
        // Flutter has no inferred physical key for normalized Android Back.
        await tester.sendKeyEvent(
          key,
          physicalKey: key == LogicalKeyboardKey.goBack
              ? PhysicalKeyboardKey.escape
              : null,
        );
        await tester.pumpAndSettle();
      }

      void focused(String label) {
        expect(FocusManager.instance.primaryFocus!.debugLabel, switch (label) {
          'menu' => 'Player Lineup menu',
          'sleep' => 'Player sleep timer',
          _ => 'Player $label',
        });
      }

      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: LineupTheme.forName(
              LineupThemeName.emberSteel,
              formFactor: profileFor(true).formFactor,
            ),
            builder: _playerTvCanvasBuilder,
            home: PlayerView(
              controller: fixture.player,
              focusNode: root,
              openGuide: () {},
              openMenu: (_, _) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        await key(LogicalKeyboardKey.select);
        focused('subtitles');
        final initialCommands = fixture.native.transportCommands;
        await key(LogicalKeyboardKey.arrowRight);
        focused('audio');
        await key(LogicalKeyboardKey.select);
        expect(fixture.player.overlay, PlayerOverlay.audioTracks);
        await key(LogicalKeyboardKey.goBack);
        expect(fixture.player.overlay, PlayerOverlay.osd);
        focused('audio');
        await key(LogicalKeyboardKey.arrowLeft);
        focused('subtitles');
        await key(LogicalKeyboardKey.select);
        expect(fixture.player.overlay, PlayerOverlay.subtitleTracks);
        await key(LogicalKeyboardKey.goBack);
        focused('subtitles');
        await key(LogicalKeyboardKey.arrowRight);
        await key(LogicalKeyboardKey.arrowRight);
        focused('sleep');
        await key(LogicalKeyboardKey.select);
        expect(fixture.player.sleepPickerOpen, isTrue);
        await key(LogicalKeyboardKey.arrowDown);
        expect(fixture.player.sleepPickerOpen, isTrue);
        await key(LogicalKeyboardKey.goBack);
        expect(fixture.player.sleepPickerOpen, isFalse);
        focused('sleep');
        await key(LogicalKeyboardKey.arrowRight);
        focused('menu');
        await key(LogicalKeyboardKey.arrowLeft);
        focused('sleep');
        expect(fixture.native.transportCommands, initialCommands);
        await key(LogicalKeyboardKey.arrowUp);
        expect(fixture.player.overlay, PlayerOverlay.miniGuide);
        await key(LogicalKeyboardKey.goBack);
        expect(root.hasPrimaryFocus, isTrue);
        await key(LogicalKeyboardKey.arrowDown);
        expect(fixture.player.overlay, PlayerOverlay.osd);
        focused('subtitles');
        await key(LogicalKeyboardKey.arrowDown);
        expect(fixture.player.overlay, PlayerOverlay.nowPlaying);
        focused('subtitles');
        await key(LogicalKeyboardKey.arrowUp);
        focused('close');
        await key(LogicalKeyboardKey.arrowDown);
        focused('subtitles');
        await key(LogicalKeyboardKey.arrowRight);
        focused('audio');
        await key(LogicalKeyboardKey.select);
        expect(fixture.player.overlay, PlayerOverlay.audioTracks);
        await key(LogicalKeyboardKey.goBack);
        expect(fixture.player.overlay, PlayerOverlay.nowPlaying);
        focused('audio');
        await key(LogicalKeyboardKey.arrowUp);
        focused('close');
        await key(LogicalKeyboardKey.select);
        expect(fixture.player.overlay, PlayerOverlay.osd);
        focused('audio');
        await key(LogicalKeyboardKey.arrowDown);
        focused('subtitles');
        await key(LogicalKeyboardKey.arrowRight);
        focused('audio');
        await key(LogicalKeyboardKey.mediaRewind);
        await key(LogicalKeyboardKey.mediaFastForward);
        expect(
          fixture.player.overlay,
          dvr ? PlayerOverlay.osd : PlayerOverlay.nowPlaying,
        );
        expect(
          fixture.native.transportCommands,
          initialCommands + (dvr ? 2 : 0),
        );
        if (dvr) {
          await key(LogicalKeyboardKey.arrowDown);
          focused('subtitles');
          await key(LogicalKeyboardKey.arrowRight);
          focused('audio');
        }
        await key(LogicalKeyboardKey.goBack);
        expect(fixture.player.overlay, PlayerOverlay.osd);
        focused('audio');
        await tester.pump(const Duration(seconds: 2));
        await key(LogicalKeyboardKey.arrowRight);
        focused('sleep');
        await tester.pump(const Duration(seconds: 2));
        expect(fixture.player.overlay, PlayerOverlay.osd);
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(fixture.player.overlay, PlayerOverlay.none);
        expect(root.hasPrimaryFocus, isTrue);
        await key(LogicalKeyboardKey.arrowLeft);
        await key(LogicalKeyboardKey.arrowRight);
        expect(
          fixture.native.transportCommands,
          initialCommands + (dvr ? 4 : 0),
        );
        if (dvr) await key(LogicalKeyboardKey.goBack);
        await key(LogicalKeyboardKey.select);
        focused('sleep');
        await key(LogicalKeyboardKey.goBack);
        expect(fixture.player.overlay, PlayerOverlay.none);
        expect(root.hasPrimaryFocus, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
        root.dispose();
        tester.view.reset();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('M1 TV Menu stays on the shell callback and Down expands once', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view
      ..physicalSize = const Size(1920, 1080)
      ..devicePixelRatio = 2;
    final root = FocusNode();
    addTearDown(root.dispose);
    final fixture = _Fixture(PlayerState.playing, richProgram: true);
    final invokerContexts = <BuildContext>[];
    final invokerFocus = <FocusNode>[];
    final menuCalls = <int>[];
    await fixture.player.tune('channel');
    fixture.player.closeOverlay();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: LineupTheme.forName(
            LineupThemeName.emberSteel,
            formFactor: profileFor(true).formFactor,
          ),
          builder: _playerTvCanvasBuilder,
          home: PlayerView(
            controller: fixture.player,
            focusNode: root,
            openGuide: () {},
            openMenu: (context, focus) {
              invokerContexts.add(context);
              invokerFocus.add(focus);
              menuCalls.add(menuCalls.length);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final initialCommands = fixture.native.transportCommands;

      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      expect(fixture.player.overlay, PlayerOverlay.none);
      expect(menuCalls, [0]);
      expect(invokerContexts.single.findRenderObject(), isA<RenderBox>());
      expect(invokerFocus.single, same(root));

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(fixture.player.overlay, PlayerOverlay.osd);
      expect(FocusManager.instance.primaryFocus?.debugLabel, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      expect(menuCalls, [0, 1]);
      expect(invokerContexts.last.findRenderObject(), isA<RenderBox>());

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(fixture.player.overlay, PlayerOverlay.nowPlaying);
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      expect(menuCalls, [0, 1, 2]);
      expect(fixture.native.transportCommands, initialCommands);

      // Minimize and hide the Player, then verify ordinary Select reveals only
      // compact OSD. The next Down is the deliberate details transition.
      fixture.player.showOsd();
      await tester.pumpAndSettle();
      fixture.player.closeOverlay();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(fixture.player.overlay, PlayerOverlay.osd);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(fixture.player.overlay, PlayerOverlay.nowPlaying);
      expect(fixture.native.transportCommands, initialCommands);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
      tester.view.reset();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  for (final hasProgram in [true, false]) {
    testWidgets(
      'M1 mounted menu survives TV OSD retirement program=$hasProgram',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        tester.view
          ..physicalSize = const Size(1920, 1080)
          ..devicePixelRatio = 2;
        final fixture = _Fixture(
          PlayerState.playing,
          richProgram: true,
          tracks: const [
            PlayerTrack(id: 1, type: PlayerTrackType.audio, selected: true),
          ],
        );
        fixture.lineup.fixtureActor.present(
          const LineupPresentation(stage: SetupStage.ready),
        );
        Future<void> key(LogicalKeyboardKey value) async {
          await tester.sendKeyEvent(
            value,
            physicalKey: value == LogicalKeyboardKey.goBack
                ? PhysicalKeyboardKey.escape
                : null,
          );
          await tester.pumpAndSettle();
        }

        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: LineupTheme.forName(
                LineupThemeName.emberSteel,
                formFactor: profileFor(true).formFactor,
              ),
              builder: _playerTvCanvasBuilder,
              home: LineupShell(
                player: fixture.native,
                controller: fixture.lineup,
                initialMediaPath: '/synthetic.mp4',
                profile: profileFor(true),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final player = tester
              .widget<PlayerView>(find.byType(PlayerView))
              .controller;
          if (hasProgram) {
            final tuning = player.tune('channel');
            await tester.pumpAndSettle();
            expect(await tuning, isTrue);
            expect(player.currentProgram, isNotNull);
          } else {
            expect(player.currentProgram, isNull);
          }
          fixture.native.emitState(PlayerState.playing);
          await tester.pumpAndSettle();
          // Establish hidden playback through actual Back, then exercise both
          // ordinary compact reveals and fully retire their animated OSD subtree.
          await key(LogicalKeyboardKey.goBack);
          final initialCommands = fixture.native.transportCommands;
          final initialLoads = fixture.native.loadCalls;
          final store = fixture.lineup.store as MemoryAppStore;
          final initialSaves = store.savedStates.length;
          for (final reveal in [
            LogicalKeyboardKey.arrowDown,
            LogicalKeyboardKey.select,
            if (!hasProgram) ...[
              LogicalKeyboardKey.info,
              LogicalKeyboardKey.keyI,
            ],
          ]) {
            await key(reveal);
            expect(player.overlay, PlayerOverlay.osd);
            expect(find.byKey(const Key('player-osd-surface')), findsOneWidget);
            await key(LogicalKeyboardKey.goBack);
            expect(player.overlay, PlayerOverlay.none);
            expect(find.byKey(const Key('player-osd-surface')), findsNothing);
            expect(FocusManager.instance.primaryFocus?.debugLabel, 'Player');

            await key(LogicalKeyboardKey.contextMenu);
            expect(find.byKey(const Key('immersive-app-menu')), findsOneWidget);
            expect(find.text('Plex account'), findsOneWidget);
            expect(player.overlay, PlayerOverlay.none);
            await key(LogicalKeyboardKey.goBack);
            expect(find.byKey(const Key('immersive-app-menu')), findsNothing);
            expect(FocusManager.instance.primaryFocus?.debugLabel, 'Player');
          }

          // A live OSD menu button remains the keyboard invoker when visible.
          await key(LogicalKeyboardKey.select);
          await key(LogicalKeyboardKey.contextMenu);
          expect(find.byKey(const Key('immersive-app-menu')), findsOneWidget);
          await key(LogicalKeyboardKey.goBack);
          expect(player.overlay, PlayerOverlay.osd);
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'Player Lineup menu',
          );
          await key(LogicalKeyboardKey.arrowDown);
          expect(
            player.overlay,
            hasProgram ? PlayerOverlay.nowPlaying : PlayerOverlay.osd,
          );
          await key(LogicalKeyboardKey.contextMenu);
          expect(find.byKey(const Key('immersive-app-menu')), findsOneWidget);
          await key(LogicalKeyboardKey.goBack);
          expect(
            player.overlay,
            hasProgram ? PlayerOverlay.nowPlaying : PlayerOverlay.osd,
          );
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'Player Lineup menu',
          );
          // Track readers have no OSD invoker, even while its retiring button
          // context is still retained by the shared FocusNode.
          await key(LogicalKeyboardKey.arrowLeft);
          await key(LogicalKeyboardKey.arrowLeft);
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'Player audio',
          );
          await key(LogicalKeyboardKey.select);
          expect(player.overlay, PlayerOverlay.audioTracks);
          await key(LogicalKeyboardKey.contextMenu);
          expect(find.byKey(const Key('immersive-app-menu')), findsOneWidget);
          await key(LogicalKeyboardKey.goBack);
          expect(player.overlay, PlayerOverlay.audioTracks);
          expect(
            tester
                .widget<PlayerView>(find.byType(PlayerView))
                .focusNode!
                .hasFocus,
            isTrue,
          );
          expect(fixture.native.transportCommands, initialCommands);
          expect(fixture.native.loadCalls, initialLoads);
          expect(store.savedStates.length, initialSaves);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          fixture.dispose();
          tester.view.reset();
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }

  for (final reader in [
    PlayerOverlay.audioTracks,
    PlayerOverlay.subtitleTracks,
    PlayerOverlay.programInfo,
  ]) {
    testWidgets('M1 mounted reader remains usable after menu: $reader', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view
        ..physicalSize = const Size(1920, 1080)
        ..devicePixelRatio = 2;
      final fixture = _Fixture(
        PlayerState.playing,
        richItemOverride: _fixtureItem(
          0,
          rich: true,
          duration: const Duration(hours: 24),
          summary: List.filled(100, 'A synthetic long synopsis.').join(' '),
        ),
        tracks: const [
          PlayerTrack(id: 1, type: PlayerTrackType.audio, selected: true),
          PlayerTrack(id: 2, type: PlayerTrackType.audio, selected: false),
          PlayerTrack(id: 11, type: PlayerTrackType.subtitle, selected: true),
          PlayerTrack(id: 12, type: PlayerTrackType.subtitle, selected: false),
        ],
      );
      Future<void> key(LogicalKeyboardKey value) async {
        await tester.sendKeyEvent(
          value,
          physicalKey: value == LogicalKeyboardKey.goBack
              ? PhysicalKeyboardKey.escape
              : null,
        );
        await tester.pumpAndSettle();
      }

      bool rowFocused(String key) {
        final element = tester.element(find.byKey(Key(key)));
        return Focus.of(element).hasFocus;
      }

      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: LineupTheme.forName(
              LineupThemeName.emberSteel,
              formFactor: profileFor(true).formFactor,
            ),
            builder: _playerTvCanvasBuilder,
            home: LineupShell(
              player: fixture.native,
              controller: fixture.lineup,
              initialMediaPath: '/synthetic.mp4',
              profile: profileFor(true),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final player = tester
            .widget<PlayerView>(find.byType(PlayerView))
            .controller;
        final tuning = player.tune('channel');
        await tester.pumpAndSettle();
        expect(await tuning, isTrue);
        fixture.native.emitState(PlayerState.playing);
        await tester.pumpAndSettle();
        final commands = fixture.native.transportCommands;
        final loads = fixture.native.loadCalls;
        final store = fixture.lineup.store as MemoryAppStore;
        final saves = store.savedStates.length;
        await key(LogicalKeyboardKey.info);
        expect(player.overlay, PlayerOverlay.nowPlaying);
        if (reader == PlayerOverlay.programInfo) {
          await key(LogicalKeyboardKey.arrowUp);
          await key(LogicalKeyboardKey.select);
        } else {
          if (reader == PlayerOverlay.audioTracks) {
            await key(LogicalKeyboardKey.arrowRight);
          }
          await key(LogicalKeyboardKey.select);
        }
        expect(player.overlay, reader);
        final primary = FocusManager.instance.primaryFocus;
        await key(LogicalKeyboardKey.contextMenu);
        expect(find.byKey(const Key('immersive-app-menu')), findsOneWidget);
        await key(LogicalKeyboardKey.goBack);
        expect(player.overlay, reader);
        if (reader == PlayerOverlay.programInfo) {
          expect(FocusManager.instance.primaryFocus, same(primary));
          final scroll = tester
              .widget<SingleChildScrollView>(
                find.byKey(const Key('player-more-info-scroll')),
              )
              .controller!;
          await key(LogicalKeyboardKey.arrowDown);
          expect(scroll.offset, greaterThan(0));
          await key(LogicalKeyboardKey.arrowUp);
          expect(scroll.offset, 0);
          await key(LogicalKeyboardKey.arrowUp);
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'More info Close',
          );
          await key(LogicalKeyboardKey.select);
          expect(player.overlay, PlayerOverlay.nowPlaying);
          expect(fixture.native.selectedTracks, isEmpty);
        } else {
          final type = reader == PlayerOverlay.audioTracks
              ? PlayerTrackType.audio
              : PlayerTrackType.subtitle;
          final secondId = type == PlayerTrackType.audio ? 2 : 12;
          expect(
            rowFocused('playback-track-${type.name}-${secondId - 1}'),
            isTrue,
          );
          await key(LogicalKeyboardKey.arrowDown);
          expect(rowFocused('playback-track-${type.name}-$secondId'), isTrue);
          await key(LogicalKeyboardKey.select);
          expect(fixture.native.selectedTracks, [(type, secondId)]);
          // Refresh real native track data while the menu hides its invoker.
          // All rows of this type retire; Close/Off remains a live fallback.
          await key(LogicalKeyboardKey.contextMenu);
          fixture.native.emitTracks(const []);
          await tester.pumpAndSettle();
          await key(LogicalKeyboardKey.goBack);
          expect(player.overlay, reader);
          expect(player.tracks, isEmpty);
          if (type == PlayerTrackType.audio) {
            await key(LogicalKeyboardKey.select);
            expect(player.overlay, PlayerOverlay.nowPlaying);
          } else {
            // The retired row falls back to Close; Down reaches Off.
            await key(LogicalKeyboardKey.arrowDown);
            expect(rowFocused('playback-track-off'), isTrue);
            await key(LogicalKeyboardKey.select);
            expect(fixture.native.selectedTracks, [
              (type, secondId),
              (type, null),
            ]);
          }
        }
        expect(fixture.native.transportCommands, commands);
        expect(fixture.native.loadCalls, loads);
        expect(store.savedStates.length, saves);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
        tester.view.reset();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  for (final window in const [Size(960, 540), Size(1920, 1080)]) {
    for (final dvr in [false, true]) {
      for (final padding in const [
        EdgeInsets.zero,
        EdgeInsets.fromLTRB(70, 35, 65, 40),
      ]) {
        testWidgets(
          'TV Player keeps video full-frame and overlay content safe: $window DVR=$dvr padding=$padding',
          (tester) async {
            debugDefaultTargetPlatformOverride = TargetPlatform.android;
            tester.view
              ..physicalSize = window * 2
              ..devicePixelRatio = 2;
            final fixture = _Fixture(
              PlayerState.playing,
              richProgram: true,
              channelCount: 5,
              dvrControlsEnabled: dvr,
              tracks: const [
                PlayerTrack(
                  id: 1,
                  type: PlayerTrackType.audio,
                  selected: true,
                  title: 'English',
                ),
              ],
            );
            final safe = padding.deflateRect(Offset.zero & window);
            void inside(Finder finder) {
              final rect = _drawnRect(tester, finder);
              expect(rect.left, greaterThanOrEqualTo(safe.left - .01));
              expect(rect.top, greaterThanOrEqualTo(safe.top - .01));
              expect(rect.right, lessThanOrEqualTo(safe.right + .01));
              expect(rect.bottom, lessThanOrEqualTo(safe.bottom + .01));
            }

            try {
              fixture.player.showOsd();
              await tester.pumpWidget(
                MaterialApp(
                  theme: LineupTheme.forName(
                    LineupThemeName.emberSteel,
                    formFactor: profileFor(true).formFactor,
                  ),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(padding: padding),
                    child: _playerTvCanvasBuilder(context, child),
                  ),
                  home: PlayerView(
                    controller: fixture.player,
                    openGuide: () {},
                  ),
                ),
              );
              await tester.pumpAndSettle();
              expect(
                _drawnRect(tester, find.byType(NativeVideoSurface)),
                Offset.zero & window,
              );
              final nativeRect = fixture.native.videoRects.last;
              expect(nativeRect.left, 0);
              expect(nativeRect.top, 0);
              expect(nativeRect.width, closeTo(window.width, .001));
              expect(nativeRect.height, closeTo(window.height, .001));
              expect(nativeRect.scale, 2);
              for (final key in [
                'player-osd-title',
                'player-osd-subtitles',
                'player-osd-audio',
                'player-osd-sleep',
                'player-osd-channel-bug',
              ]) {
                inside(find.byKey(Key(key)));
              }
              final scale = LineupCanvas.scaleFor(
                window,
                formFactor: profileFor(true).formFactor,
              );
              final bug = _drawnRect(
                tester,
                find.byKey(const Key('player-osd-channel-bug')),
              );
              expect(bug.top, closeTo(math.max(padding.top, 24 * scale), .001));
              expect(
                window.width - bug.right,
                closeTo(math.max(padding.right, 96 * scale), .001),
              );
              expect(
                _drawnRect(
                  tester,
                  find.byKey(const Key('player-osd-progress-line')),
                ).bottom,
                closeTo(window.height, .001),
              );
              if (dvr) {
                final target = find.byKey(const Key('player-safe-dvr-target'));
                inside(target);
                final sliderNode = tester.semantics
                    .simulatedAccessibilityTraversal()
                    .where(
                      (node) =>
                          node.getSemanticsData().flagsCollection.isSlider,
                    )
                    .single;
                final range = sliderNode.getSemanticsData();
                expect(range.label, 'Playback progress');
                expect(range.value, '10:00 of 1:00:00');
                expect(range.hasAction(SemanticsAction.increase), isTrue);
                expect(range.hasAction(SemanticsAction.decrease), isTrue);
                final box = tester.renderObject<RenderBox>(target);
                final accessibleBounds = Rect.fromPoints(
                  box.localToGlobal(sliderNode.rect.topLeft),
                  box.localToGlobal(sliderNode.rect.bottomRight),
                );
                expect(accessibleBounds.top, greaterThanOrEqualTo(safe.top));
                expect(
                  accessibleBounds.bottom,
                  lessThanOrEqualTo(safe.bottom + .001),
                );
                fixture.player.closeOverlay();
                await tester.pump();
                expect(
                  tester.semantics.simulatedAccessibilityTraversal().where(
                    (node) => node.getSemanticsData().flagsCollection.isSlider,
                  ),
                  isEmpty,
                );
                fixture.player.showOsd();
                await tester.pumpAndSettle();
              }
              fixture.player.showSleepTimer();
              await tester.pumpAndSettle();
              inside(find.byKey(const Key('sleep-timer-picker')));
              fixture.player.closeSleepPicker();
              fixture.player.showNowPlaying();
              await tester.pumpAndSettle();
              inside(find.byKey(const Key('player-now-playing-surface')));
              fixture.player.closeOverlay();
              fixture.player.showTracks(PlayerTrackType.audio);
              await tester.pumpAndSettle();
              inside(find.byKey(const Key('playback-options-footer')));
              inside(find.text('English').last);
              fixture.player.closeOverlay();
              fixture.player.showMiniGuide();
              await tester.pumpAndSettle();
              inside(find.text('Up/Down Browse · Select Tune · Back Close'));
              expect(tester.takeException(), isNull);
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              fixture.dispose();
              tester.view.reset();
              debugDefaultTargetPlatformOverride = null;
            }
          },
        );
      }
    }
  }
  testWidgets('deferred tune transport name and icon agree with K', (
    tester,
  ) async {
    final fixture = _Fixture(
      PlayerState.playing,
      channelCount: 3,
      dvrControlsEnabled: true,
    );
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => LineupCanvas.builder(
          context,
          MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await fixture.player.tune('channel');
    unawaited(fixture.player.nextChannel());
    final step = fixture.player.nextChannel();
    fixture.native._events.add(
      PlayerEvent(
        status: const PlayerStatus(
          state: PlayerState.stopped,
          message: 'Stopped',
        ),
        position: Duration.zero,
        duration: Duration.zero,
        telemetry: const PlayerTelemetry(),
        tracks: const [],
      ),
    );
    await tester.pump();
    fixture.player.showOsd();
    await tester.pump();
    void expectToggle(String name, IconData icon) {
      final button = find.byTooltip(name);
      expect(button, findsOneWidget);
      final semantics = tester.getSemantics(button);
      expect(semantics.label, name);
      expect(semantics.getSemanticsData().flagsCollection.isButton, isTrue);
      expect(
        tester
            .widget<Icon>(
              find.descendant(of: button, matching: find.byType(Icon)),
            )
            .icon,
        icon,
      );
    }

    expectToggle('Pause', Icons.pause);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    expectToggle('Play', Icons.play_arrow);
    expect(fixture.native.transportCommands, 0);
    // The visible button reverses K's pending intent without a native command.
    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    expectToggle('Pause', Icons.pause);
    expect(fixture.native.transportCommands, 0);
    await tester.pump(const Duration(milliseconds: 250));
    await step;
    fixture.player.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  }, semanticsEnabled: true);

  for (final tooltipsVisible in [true, false]) {
    testWidgets(
      'retiring OSD removes tooltips and preserves inherited visibility $tooltipsVisible',
      (tester) async {
        final fixture = _Fixture(PlayerState.playing, dvrControlsEnabled: true);
        await tester.pumpWidget(
          MaterialApp(
            builder: _playerDesktopCanvasBuilder,
            home: TooltipVisibility(
              visible: tooltipsVisible,
              child: PlayerView(controller: fixture.player, openGuide: () {}),
            ),
          ),
        );
        await tester.pumpAndSettle();

        fixture.player.showOsd();
        await tester.pumpAndSettle();
        final pauseTooltip = find.byWidgetPredicate(
          (widget) => widget is Tooltip && widget.message == 'Pause',
        );
        expect(
          tester.state<TooltipState>(pauseTooltip).ensureTooltipVisible(),
          tooltipsVisible,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          find.text('Pause'),
          tooltipsVisible ? findsOneWidget : findsNothing,
        );

        fixture.player.closeOverlay();
        await tester.pump();
        expect(pauseTooltip, findsOneWidget);
        expect(find.text('Pause'), findsNothing);
        expect(
          tester.state<TooltipState>(pauseTooltip).ensureTooltipVisible(),
          isFalse,
        );

        fixture.player.showOsd();
        await tester.pumpAndSettle();
        expect(pauseTooltip, findsOneWidget);
        expect(
          tester.state<TooltipState>(pauseTooltip).ensureTooltipVisible(),
          tooltipsVisible,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          find.text('Pause'),
          tooltipsVisible ? findsOneWidget : findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
      },
    );
  }

  testWidgets(
    'Player icon actions have accessible names in OSD and Now Playing',
    (tester) async {
      final fixture = _Fixture(PlayerState.playing, dvrControlsEnabled: true);
      await tester.pumpWidget(
        MaterialApp(
          builder: _playerDesktopCanvasBuilder,
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      for (final overlay in [PlayerOverlay.osd, PlayerOverlay.nowPlaying]) {
        if (overlay == PlayerOverlay.osd) {
          fixture.player.showOsd();
        } else {
          fixture.player.showNowPlaying();
        }
        await tester.pumpAndSettle();
        for (final label in [
          'Previous channel',
          'Pause',
          'Next channel',
          'Full screen',
        ]) {
          final node = tester.getSemantics(find.byTooltip(label));
          expect(node.label, label, reason: '$overlay');
          expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
    semanticsEnabled: true,
  );

  testWidgets('Android TV omits the ineffective fullscreen action', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final fixture = _Fixture(PlayerState.playing, dvrControlsEnabled: true);
    try {
      fixture.player.showOsd();
      await tester.pumpWidget(
        MaterialApp(
          theme: LineupTheme.forName(
            LineupThemeName.emberSteel,
            formFactor: profileFor(true).formFactor,
          ),
          builder: _playerTvCanvasBuilder,
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Full screen'), findsNothing);
      expect(find.byTooltip('Exit full screen'), findsNothing);
    } finally {
      fixture.dispose();
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets(
    'presentation getters distinguish watching from selected and held state',
    (tester) async {
      for (final state in PlayerState.values) {
        final fixture = _Fixture(state);
        expect(fixture.player.presentedState, state);
        expect(fixture.player.watchingChannelId, isNull);
        expect(await fixture.player.tune('channel'), isTrue);
        expect(
          fixture.player.watchingChannelId,
          const {
                PlayerState.playing,
                PlayerState.paused,
                PlayerState.buffering,
                PlayerState.seeking,
              }.contains(state)
              ? 'channel'
              : null,
          reason: '$state',
        );
        fixture.dispose();
      }
      final empty = _Fixture(PlayerState.playing, channelCount: 0);
      expect(empty.player.watchingChannelId, isNull);
      empty.dispose();
    },
  );

  for (final overlay in [PlayerOverlay.osd, PlayerOverlay.nowPlaying]) {
    testWidgets('display hold projects preparing and loading in $overlay', (
      tester,
    ) async {
      final f = _Fixture(
        PlayerState.paused,
        dvrControlsEnabled: true,
        richProgram: true,
        nativeTelemetry: const PlayerTelemetry(gamma: 'pq'),
        tracks: const [
          PlayerTrack(id: 1, type: PlayerTrackType.video, selected: true),
        ],
      );
      await f.guide.ensureCurrentProgram('channel');
      await f.player.toggleFullscreen();
      await f.player.loadInitialMedia(
        Uri.parse('https://synthetic.test/local'),
      );
      expect(f.player.displayHoldActive, isTrue);
      expect(f.player.presentedState, PlayerState.loading);
      expect(f.player.status.state, PlayerState.paused);
      if (overlay == PlayerOverlay.nowPlaying) f.player.showNowPlaying();
      await tester.pumpWidget(
        MaterialApp(
          builder: _playerDesktopCanvasBuilder,
          theme: LineupTheme.forName(
            LineupThemeName.emberSteel,
            largeFocusIndicators: false,
          ),
          home: PlayerView(controller: f.player, openGuide: () {}),
        ),
      );
      await tester.pump();
      expect(f.player.displayHoldActive, isTrue);
      expect(f.player.presentedState, PlayerState.loading);
      expect(f.player.status.state, PlayerState.paused);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Preparing playback',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Loading'), findsWidgets);
      expect(find.text('Paused'), findsNothing);
      expect(find.byTooltip('Play'), findsNothing);
      expect(find.byTooltip('Pause'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(f.player.status.state, PlayerState.paused);
      expect(f.player.overlay, overlay);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Starting playback…'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      f.dispose();
    });
  }

  testWidgets(
    'shell Diagnostics reacts to display reports without media events',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = _Fixture(PlayerState.playing);
      await tester.pumpWidget(
        MaterialApp(
          builder: _playerDesktopCanvasBuilder,
          theme: LineupTheme.forName(
            LineupThemeName.emberSteel,
            largeFocusIndicators: false,
          ),
          home: LineupShell(
            player: f.native,
            controller: f.lineup,
            initialMediaPath: 'https://synthetic.test/local',
            profile: desktopProfile,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Lineup menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Support'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Open Diagnostics'));
      await tester.tap(find.text('Open Diagnostics'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Technical details'));
      await tester.tap(find.text('Technical details'));
      await tester.pumpAndSettle();
      f.native.emitDisplay(
        const DisplayMatchingReport(
          revision: 1,
          session: DisplayMatchingSessionState.active,
          observed: DisplayMatchingState.hdr,
          outcome: DisplayMatchingOutcome.matched,
          wrote: true,
          owned: true,
          reason: null,
          route: DisplayMatchingRoute.advancedColor,
          activeColorMode: null,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('hdr · advancedColor'), findsOneWidget);
      expect(find.textContaining('revision=1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      f.dispose();
      await f.native.dispose();
    },
  );

  testWidgets(
    'paused Mini Guide clock refreshes without player events and stops in background',
    (tester) async {
      var now = DateTime(2026, 1, 15, 12);
      final fixture = _Fixture(
        PlayerState.paused,
        guideClock: () => now,
        shortPrograms: true,
      );
      await fixture.guide.ensureCurrentProgram('channel');
      fixture.player.showMiniGuide();
      await tester.pumpWidget(
        MaterialApp(
          builder: _playerDesktopCanvasBuilder,
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('12:00 PM'), findsOneWidget);
      final beforeProgress = tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value!;
      now = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('12:01 PM'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value!,
        greaterThan(beforeProgress),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      now = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('12:01 PM'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('12:02 PM'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
  );

  for (final overlay in [PlayerOverlay.osd, PlayerOverlay.nowPlaying]) {
    testWidgets(
      'paused ${overlay.name} schedule changes without player events',
      (tester) async {
        var now = DateTime(2026, 1, 15, 12);
        final fixture = _Fixture(
          PlayerState.paused,
          guideClock: () => now,
          shortPrograms: true,
          overlayTimeout: const Duration(hours: 1),
        );
        await fixture.guide.ensureCurrentProgram('channel');
        if (overlay == PlayerOverlay.osd) {
          fixture.player.showOsd();
        } else {
          fixture.player.showNowPlaying();
        }
        await tester.pumpWidget(
          MaterialApp(
            builder: _playerDesktopCanvasBuilder,
            home: PlayerView(controller: fixture.player, openGuide: () {}),
          ),
        );
        await tester.pumpAndSettle();
        final title = find.byKey(
          Key(
            overlay == PlayerOverlay.osd
                ? 'player-osd-title'
                : 'player-now-playing-title',
          ),
        );
        expect(tester.widget<Text>(title).data, 'Program');
        now = now.add(const Duration(minutes: 31));
        await tester.pump(const Duration(seconds: 30));
        expect(tester.widget<Text>(title).data, 'Replacement Program');
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
      },
    );
  }

  testWidgets(
    'stopped slate stays opaque at every level with working Browse and Close',
    (tester) async {
      final fixture = _Fixture(PlayerState.stopped);
      var closed = false;
      for (final level in OverlayTransparency.values) {
        fixture.lineup.fixtureActor.publishSettings(
          fixture.lineup.settings.copyWith(overlayTransparency: level),
        );
        fixture.lineup.notifyListeners();
        await tester.pumpWidget(
          MaterialApp(
            theme: LineupTheme.forName(LineupThemeName.slatePine),
            builder: _playerDesktopCanvasBuilder,
            home: PlayerView(
              controller: fixture.player,
              openGuide: () => closed = true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Playback stopped'), findsOneWidget);
        expect(find.text('Retry'), findsNothing);
        expect(find.byType(NativeVideoSurface), findsNothing);
        final roles = LineupTheme.of(
          tester.element(find.text('Playback stopped')),
        );
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is ColoredBox &&
                w.color == roles.deepBackground &&
                w.color.a == 1,
          ),
          findsWidgets,
        );
      }
      await tester.tap(find.text('Browse channels'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mini-guide-shelf')), findsOneWidget);
      fixture.player.closeOverlay();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
  );

  testWidgets(
    'overlay settings update the mounted Player with each theme tint',
    (tester) async {
      final fixture = _Fixture(PlayerState.playing);
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      fixture.player.showOsd();
      for (final theme in LineupThemeName.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: LineupTheme.forName(theme),
            builder: _playerDesktopCanvasBuilder,
            home: PlayerView(controller: fixture.player, openGuide: () {}),
          ),
        );
        await tester.pumpAndSettle();
        final surface = find.byKey(const Key('player-osd-surface'));
        final roles = LineupTheme.of(tester.element(surface));
        final before = _drawnRect(
          tester,
          find.byKey(const Key('player-osd-title')),
        );
        for (final level in OverlayTransparency.values) {
          fixture.lineup.fixtureActor.publishSettings(
            fixture.lineup.settings.copyWith(overlayTransparency: level),
          );
          fixture.lineup.notifyListeners();
          await tester.pumpAndSettle();
          final painter = tester
              .widget<CustomPaint>(
                find
                    .ancestor(of: surface, matching: find.byType(CustomPaint))
                    .first,
              )
              .painter!;
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder)..translate(0, 55);
          painter.paint(canvas, const Size(8, 256));
          final picture = recorder.endRecording();
          final image = await tester.runAsync(() => picture.toImage(8, 311));
          final pixels = await tester.runAsync(
            () => image!.toByteData(format: ui.ImageByteFormat.rawStraightRgba),
          );
          final offset = (310 * 8 + 4) * 4;
          final tint = roles.overlaySurface;
          expect(pixels!.getUint8(offset), closeTo(tint.r * 255, 2));
          expect(pixels.getUint8(offset + 1), closeTo(tint.g * 255, 2));
          expect(pixels.getUint8(offset + 2), closeTo(tint.b * 255, 2));
          expect(
            pixels.getUint8(offset + 3) / 255,
            closeTo(switch (level) {
              OverlayTransparency.moreTransparent => .45,
              OverlayTransparency.standard => .78,
              OverlayTransparency.reduced => .94,
            }, .006),
          );
          if (level != OverlayTransparency.moreTransparent) {
            final above = pixels.getUint8((54 * 8 + 4) * 4 + 3);
            final below = pixels.getUint8((55 * 8 + 4) * 4 + 3);
            expect(above, closeTo(below, 3));
          }
          image!.dispose();
          picture.dispose();
          expect(
            _drawnRect(tester, find.byKey(const Key('player-osd-title'))),
            before,
          );
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
  );

  testWidgets(
    'expanded proposal displays approved title artwork within its cap',
    (tester) async {
      final bytes = await tester.runAsync(
        () =>
            File('test/support/now_playing/signal-after-midnight-title.png')
                .readAsBytes(),
      );
      final inkFraction = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(bytes!);
        final image = (await codec.getNextFrame()).image;
        final pixels = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        var top = image.height, bottom = -1;
        for (var y = 0; y < image.height; y++) {
          for (var x = 0; x < image.width; x++) {
            if (pixels!.getUint8((y * image.width + x) * 4 + 3) >= 32) {
              top = math.min(top, y);
              bottom = math.max(bottom, y);
            }
          }
        }
        final fraction = (bottom - top + 1) / image.height;
        image.dispose();
        codec.dispose();
        return fraction;
      });
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final size in [const Size(1280, 720), const Size(1920, 1080)]) {
        for (final textScale in [1.0, 1.5]) {
          await tester.binding.setSurfaceSize(size);
          final fixture = _Fixture(
            PlayerState.playing,
            richProgram: true,
            artworkBytes: bytes,
          );
          await fixture.guide.ensureCurrentProgram('channel');
          fixture.player.showNowPlaying();
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(textScale)),
                child: _playerDesktopCanvasBuilder(context, child),
              ),
              home: PlayerView(controller: fixture.player, openGuide: () {}),
            ),
          );
          await tester.pumpAndSettle();
          await _settleNowPlayingArtwork(tester);
          final logo = find.byKey(const Key('player-now-playing-logo'));
          expect(logo, findsOneWidget, reason: '$size text$textScale');
          final image = tester.widget<RawImage>(logo);
          expect(image.image, isNotNull);
          final visibleLogo = find
              .ancestor(of: logo, matching: find.byType(ClearLogoImage))
              .first;
          final drawn = _drawnSize(tester, visibleLogo);
          expect(
            drawn.height,
            lessThanOrEqualTo(56 * LineupCanvas.scaleFor(size) + .01),
          );
          expect(
            drawn.height,
            greaterThanOrEqualTo(48 * LineupCanvas.scaleFor(size)),
          );
          expect(drawn.width, greaterThan(0));
          final paintedInkHeight =
              _drawnSize(tester, logo).height * inkFraction!;
          final canvasScale = LineupCanvas.scaleFor(size);
          expect(
            paintedInkHeight,
            inInclusiveRange(48 * canvasScale, 56 * canvasScale),
          );

          expect(
            find.byKey(const Key('player-now-playing-series')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          fixture.dispose();
        }
      }
    },
  );

  testWidgets('expanded proposal keeps metadata, cast and controls reachable', (
    tester,
  ) async {
    await tester.runAsync(loadPinnedTestFonts);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in [const Size(1280, 720), const Size(1920, 1080)]) {
      for (final textScale in [1.0, 1.5]) {
        await tester.binding.setSurfaceSize(size);
        final fixture = _Fixture(
          PlayerState.playing,
          richItemOverride: _fixtureItem(
            0,
            rich: true,
            duration: const Duration(hours: 1),
            cast: _fixtureCast,
          ),
          shortPrograms: true,
          dvrControlsEnabled: textScale > 1,
          guideClock: () => DateTime(2026, 1, 15, 12),
          tracks: const [
            PlayerTrack(
              id: 1,
              type: PlayerTrackType.audio,
              language: 'eng',
              selected: true,
            ),
            PlayerTrack(
              id: 2,
              type: PlayerTrackType.subtitle,
              language: 'eng',
              selected: true,
            ),
          ],
        );
        await fixture.guide.ensureCurrentProgram('channel');
        fixture.player.showNowPlaying();
        await tester.pumpWidget(
          MaterialApp(
            theme: LineupTheme.forName(LineupThemeName.emberSteel),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: _playerDesktopCanvasBuilder(context, child),
            ),
            home: PlayerView(
              controller: fixture.player,
              openGuide: () {},
              openMenu: (_, _) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _settleNowPlayingArtwork(tester);
        expect(
          find.text('S2 E6 · 60 min · 2026 · Drama · Adventure'),
          findsOneWidget,
        );
        expect(find.textContaining('Season 2'), findsNothing);
        final logo = find.byKey(const Key('player-now-playing-logo'));
        final canvasScale = LineupCanvas.scaleFor(size);
        expect(
          _drawnSize(
            tester,
            find
                .ancestor(of: logo, matching: find.byType(ClearLogoImage))
                .first,
          ).height,
          lessThanOrEqualTo(56 * canvasScale + .01),
        );
        final summaryFinder = find.byKey(
          const Key('player-now-playing-summary'),
        );
        final summary = tester.widget<Text>(summaryFinder);
        expect(summary.maxLines, 3);
        expect(summary.overflow, TextOverflow.ellipsis);
        expect(
          _drawnSize(tester, summaryFinder).width,
          lessThanOrEqualTo(900 * canvasScale + .01),
        );
        final castFinder = find.byKey(const Key('player-now-playing-cast'));
        final castLeft = _drawnRect(tester, castFinder).left;
        final roleStyle = tester
            .widget<Text>(
              find.byKey(const ValueKey('player-now-playing-cast-role-0')),
            )
            .style!;
        final roles = LineupTheme.of(tester.element(castFinder));
        expect(roleStyle.color, roles.secondaryText);
        for (var i = 0; i < 4; i++) {
          final nameFinder = find.byKey(
            ValueKey('player-now-playing-cast-name-$i'),
          );
          final roleFinder = find.byKey(
            ValueKey('player-now-playing-cast-role-$i'),
          );
          final name = tester.widget<Text>(nameFinder);
          expect(name.style!.color, roles.primaryText);
          expect(name.maxLines, 2);
          final nameRect = _drawnRect(tester, nameFinder);
          final roleRect = _drawnRect(tester, roleFinder);
          expect(roleRect.left, closeTo(nameRect.left, .01));
          expect(roleRect.top - nameRect.bottom, closeTo(3 * canvasScale, .01));
          if (i == 0) expect(nameRect.left, closeTo(castLeft, .01));
          final roleParagraph = tester.renderObject<RenderParagraph>(
            roleFinder,
          );
          expect(roleParagraph.didExceedMaxLines, isFalse);
        }
        expect(
          find.byKey(const ValueKey('player-now-playing-cast-name-4')),
          findsNothing,
        );
        for (final key in [
          'player-osd-subtitles',
          'player-osd-audio',
          'player-osd-sleep',
        ]) {
          final labelFinder = find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(Text),
          );
          final text = tester.widget<Text>(labelFinder);
          expect(text.overflow, isNot(TextOverflow.ellipsis));
          expect(
            tester.renderObject<RenderParagraph>(labelFinder).didExceedMaxLines,
            isFalse,
          );
        }
        final standardActions = [
          find.byKey(const Key('player-osd-subtitles')),
          find.byKey(const Key('player-osd-audio')),
          find.byKey(const Key('player-osd-sleep')),
          find.byKey(const Key('player-app-menu')),
          find.byTooltip('Full screen'),
        ].map((finder) => _drawnRect(tester, finder)).toList();
        final availableWidth =
            size.width -
            2 *
                (size.width / LineupCanvas.scaleFor(size) * .05).clamp(
                  24.0,
                  96.0,
                ) *
                LineupCanvas.scaleFor(size);
        final naturalStandardWidth = standardActions.fold<double>(
          16 * LineupCanvas.scaleFor(size),
          (sum, rect) => sum + rect.width,
        );
        if (naturalStandardWidth <= availableWidth) {
          for (final rect in standardActions.skip(1)) {
            expect(
              rect.center.dy,
              closeTo(standardActions.first.center.dy, .01),
              reason: 'All five actions fit at $size text$textScale',
            );
          }
        }
        final actions = _drawnRect(
          tester,
          find.byKey(const Key('player-osd-action-groups')),
        );
        final close = _drawnRect(
          tester,
          find.byKey(const Key('player-now-playing-collapse')),
        );
        expect(close.right, closeTo(actions.right, .01));
        final closeGlyph = find.descendant(
          of: find.byKey(const Key('player-now-playing-collapse')),
          matching: find.byIcon(Icons.close),
        );
        final fullscreenGlyph = find.byIcon(Icons.fullscreen);
        expect(
          await _paintedIconRight(tester, closeGlyph),
          closeTo(await _paintedIconRight(tester, fullscreenGlyph), .5),
        );

        final next = _drawnRect(
          tester,
          find.byKey(const Key('player-osd-next')),
        );
        expect(next.right, closeTo(actions.right, .01));
        expect(next.top, greaterThanOrEqualTo(actions.bottom));
        expect(tester.takeException(), isNull, reason: '$size text$textScale');
        fixture.player.showOsd();
        await tester.pumpAndSettle();
        for (final key in [
          'player-osd-subtitles',
          'player-osd-audio',
          'player-osd-sleep',
        ]) {
          final labelFinder = find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(Text),
          );
          expect(
            tester.renderObject<RenderParagraph>(labelFinder).didExceedMaxLines,
            isFalse,
          );
        }
        final collapsedActions = _drawnRect(
          tester,
          find.byKey(const Key('player-osd-action-groups')),
        );
        final collapsedNext = _drawnRect(
          tester,
          find.byKey(const Key('player-osd-next')),
        );
        expect(collapsedNext.right, closeTo(collapsedActions.right, .01));
        expect(
          collapsedNext.top,
          greaterThanOrEqualTo(collapsedActions.bottom),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
      }
    }
  });

  testWidgets('sleep popover is above its real button and remains clickable', (
    tester,
  ) async {
    final fixture = _Fixture(
      PlayerState.playing,
      tracks: const [
        PlayerTrack(id: 1, type: PlayerTrackType.subtitle, selected: false),
      ],
    );
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    fixture.player.showOsd();
    await tester.pumpWidget(
      MaterialApp(
        theme: LineupTheme.forName(LineupThemeName.emberSteel),
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pumpAndSettle();
    final generation = fixture.player.overlayPresentationGeneration;
    await tester.tap(find.byKey(const Key('player-osd-sleep')));
    await tester.pumpAndSettle();
    expect(fixture.player.overlay, PlayerOverlay.osd);
    expect(fixture.player.sleepPickerOpen, isTrue);
    expect(fixture.player.overlayPresentationGeneration, generation);
    final popup = _drawnRect(
      tester,
      find.byKey(const Key('sleep-timer-picker')),
    );
    final button = _drawnRect(
      tester,
      find.byKey(const Key('player-osd-sleep')),
    );
    expect(popup.bottom, lessThan(button.top));
    expect(popup.right, closeTo(button.right, .1));
    expect(popup.left, greaterThanOrEqualTo(0));
    expect(popup.top, greaterThanOrEqualTo(0));
    await tester.tap(find.byKey(const Key('player-osd-subtitles')));
    await tester.pumpAndSettle();
    expect(fixture.player.overlay, PlayerOverlay.subtitleTracks);
    expect(fixture.player.sleepPickerOpen, isFalse);
    fixture.player.closeOverlay();
    await tester.pumpAndSettle();
    fixture.player.showSleepTimer();
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 minutes'));
    await tester.pumpAndSettle();
    expect(find.text('Sleep · 30m'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets(
    'video click closes the sleep picker and restarts the OSD timer',
    (tester) async {
      final fixture = _Fixture(
        PlayerState.playing,
        overlayTimeout: const Duration(seconds: 1),
      );
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      fixture.player.showOsd();
      await tester.pumpWidget(
        MaterialApp(
          builder: _playerDesktopCanvasBuilder,
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('player-osd-sleep')));
      await tester.pumpAndSettle();
      expect(fixture.player.sleepPickerOpen, isTrue);

      await tester.tapAt(const Offset(8, 8), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(fixture.player.overlay, PlayerOverlay.osd);
      expect(fixture.player.sleepPickerOpen, isFalse);
      await tester.pump(const Duration(milliseconds: 999));
      expect(fixture.player.overlay, PlayerOverlay.osd);
      await tester.pump(const Duration(milliseconds: 1));
      expect(fixture.player.overlay, PlayerOverlay.none);

      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
  );

  testWidgets(
    'pointer activity and timeout changes do not dismiss an open picker',
    (tester) async {
      final fixture = _Fixture(PlayerState.playing);
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      fixture.player.showOsd();
      await tester.pumpWidget(
        MaterialApp(
          builder: _playerDesktopCanvasBuilder,
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('player-osd-sleep')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      await tester.sendEventToBinding(
        PointerHoverEvent(position: const Offset(8, 8)),
      );
      fixture.lineup.fixtureActor.publishSettings(
        fixture.lineup.settings.copyWith(osdAutoHideSeconds: 2),
      );
      fixture.lineup.notifyListeners();
      await tester.pump(const Duration(seconds: 3));
      expect(fixture.player.overlay, PlayerOverlay.osd);
      expect(fixture.player.sleepPickerOpen, isTrue);

      fixture.player.closeOverlay();
      await tester.pump(const Duration(milliseconds: 1999));
      expect(fixture.player.overlay, PlayerOverlay.osd);
      await tester.pump(const Duration(milliseconds: 1));
      expect(fixture.player.overlay, PlayerOverlay.none);

      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
  );

  testWidgets(
    'native fullscreen changes update OSD icon without another command',
    (tester) async {
      final fixture = _Fixture(PlayerState.playing);
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      fixture.player.showOsd();
      await tester.pumpWidget(
        MaterialApp(
          builder: _playerDesktopCanvasBuilder,
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Full screen'), findsOneWidget);
      fixture.native.emitFullscreen(true);
      await tester.pump();
      expect(find.byTooltip('Exit full screen'), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);
      fixture.native.emitFullscreen(false);
      await tester.pump();
      expect(find.byTooltip('Full screen'), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen), findsOneWidget);
      expect(fixture.native.fullscreenValues, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
  );

  testWidgets('OSD menu and fullscreen actions close the picker first', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing);
    var menuOpened = false;
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    fixture.player.showOsd();
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(
          controller: fixture.player,
          openGuide: () {},
          openMenu: (_, _) => menuOpened = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final generation = fixture.player.overlayPresentationGeneration;

    await tester.tap(find.byKey(const Key('player-osd-sleep')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('player-app-menu')));
    await tester.pump();
    expect(menuOpened, isTrue);
    expect(fixture.player.overlay, PlayerOverlay.osd);
    expect(fixture.player.sleepPickerOpen, isFalse);
    expect(fixture.player.overlayPresentationGeneration, generation);

    fixture.player.showSleepTimer();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Full screen'));
    await tester.pumpAndSettle();
    expect(fixture.native.fullscreenValues, [true]);
    expect(fixture.player.overlay, PlayerOverlay.osd);
    expect(fixture.player.sleepPickerOpen, isFalse);
    expect(fixture.player.overlayPresentationGeneration, generation);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('sleep picker keeps arrow navigation within its focused rows', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing);
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    fixture.player.showOsd();
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pumpAndSettle();

    final thirtyMinutes = find.text('30 minutes');
    final oneHour = find.text('1 hour');
    expect(thirtyMinutes, findsOneWidget);
    expect(oneHour, findsOneWidget);
    Focus.of(tester.element(thirtyMinutes)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(fixture.player.overlay, PlayerOverlay.osd);
    expect(fixture.player.sleepPickerOpen, isTrue);
    expect(Focus.of(tester.element(oneHour)).hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(Focus.of(tester.element(thirtyMinutes)).hasFocus, isTrue);
    expect(fixture.player.overlay, PlayerOverlay.osd);
    expect(fixture.player.sleepPickerOpen, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  for (final dvrControlsEnabled in [false, true]) {
    testWidgets(
      'sleep picker Space activates a preset without playback commands '
      '(DVR ${dvrControlsEnabled ? 'on' : 'off'})',
      (tester) async {
        final fixture = _Fixture(
          PlayerState.playing,
          dvrControlsEnabled: dvrControlsEnabled,
        );
        await tester.binding.setSurfaceSize(const Size(1280, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        fixture.player.showOsd();
        await tester.pumpWidget(
          MaterialApp(
            builder: _playerDesktopCanvasBuilder,
            home: PlayerView(controller: fixture.player, openGuide: () {}),
          ),
        );
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        await tester.pumpAndSettle();
        Focus.of(tester.element(find.text('30 minutes'))).requestFocus();
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(fixture.player.sleepDuration, const Duration(minutes: 30));
        expect(fixture.native.transportCommands, 0);
        expect(fixture.player.overlay, PlayerOverlay.osd);
        expect(fixture.player.sleepPickerOpen, isFalse);

        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
      },
    );
  }

  testWidgets('OSD Up still opens Mini Guide outside the sleep picker', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing);
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    fixture.player.showOsd();
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pumpAndSettle();
    final sleepButton = tester.widget<TextButton>(
      find.byKey(const Key('player-osd-sleep')),
    );
    sleepButton.focusNode!.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(fixture.player.overlay, PlayerOverlay.miniGuide);
    expect(fixture.player.sleepPickerOpen, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets(
    'keyboard track traversal reveals each focused row below its header',
    (tester) async {
      final fixture = _Fixture(
        PlayerState.playing,
        tracks: [
          for (var index = 0; index < 30; index++)
            PlayerTrack(
              id: index + 1,
              type: PlayerTrackType.audio,
              selected: index == 0,
              title: 'Audio choice ${index + 1}',
            ),
        ],
      );
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      fixture.player.showOsd();
      await tester.pumpWidget(
        MaterialApp(
          theme: LineupTheme.forName(LineupThemeName.emberSteel),
          builder: _playerDesktopCanvasBuilder,
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('player-osd-audio')));
      await tester.pumpAndSettle();
      final selected = find.byKey(const Key('playback-track-audio-1'));
      final selectedSurface = find.ancestor(
        of: selected,
        matching: find.byType(LineupRowSurface),
      );
      final ring =
          tester
                  .widget<Container>(
                    find
                        .descendant(
                          of: selectedSurface,
                          matching: find.byWidgetPredicate(
                            (w) =>
                                w is Container &&
                                w.foregroundDecoration != null,
                          ),
                        )
                        .first,
                  )
                  .foregroundDecoration!
              as BoxDecoration;
      expect((ring.border! as Border).top.color.a, 0);
      for (var index = 2; index <= 12; index++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        final row = find.byKey(Key('playback-track-audio-$index'));
        expect(Focus.of(tester.element(row)).hasFocus, isTrue);
        final rowSurface = find.ancestor(
          of: row,
          matching: find.byType(LineupRowSurface),
        );
        final keyboardRing =
            tester
                    .widget<Container>(
                      find
                          .descendant(
                            of: rowSurface,
                            matching: find.byWidgetPredicate(
                              (w) =>
                                  w is Container &&
                                  w.foregroundDecoration != null,
                            ),
                          )
                          .first,
                    )
                    .foregroundDecoration!
                as BoxDecoration;
        final roles = LineupTheme.of(tester.element(row));
        final keyboardBorder = keyboardRing.border! as Border;
        expect(keyboardBorder.top.color, roles.focusBorder);
        expect(keyboardBorder.top.width, roles.focusBorderWidth);
        final rect = _drawnRect(tester, row);
        final list = _drawnRect(
          tester,
          find.byKey(const Key('playback-options-list')),
        );
        expect(rect.top, greaterThanOrEqualTo(list.top));
        expect(rect.bottom, lessThanOrEqualTo(list.bottom));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
  );

  testWidgets('unsupported macOS backend keeps the Flutter player accessible', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.unsupported);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
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

  testWidgets('macOS Command leaves Player keys for the app menu', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
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

    Future<int> fullscreenAfter({required bool command}) async {
      final before = fixture.native.fullscreenValues.length;
      if (command) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      if (command) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      return fixture.native.fullscreenValues.length - before;
    }

    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(await fullscreenAfter(command: true), 0);
      expect(await fullscreenAfter(command: false), 1);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(await fullscreenAfter(command: true), 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('Player propagates Ctrl route repeats and keeps local keys', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing);
    final propagated = <KeyEvent>[];
    var guideOpens = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
        home: Focus(
          onKeyEvent: (_, event) {
            if (event.logicalKey == LogicalKeyboardKey.digit1 &&
                (event is KeyDownEvent || event is KeyRepeatEvent)) {
              propagated.add(event);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: PlayerView(
            controller: fixture.player,
            openGuide: () => guideOpens++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final modifier in [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.metaLeft,
    ]) {
      await tester.sendKeyDownEvent(modifier);
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.digit1);
    expect(propagated, hasLength(2));
    expect(propagated.first, isA<KeyDownEvent>());
    expect(propagated.last, isA<KeyRepeatEvent>());
    expect(fixture.player.overlay, PlayerOverlay.none);
    for (final modifier in [
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.controlLeft,
    ]) {
      await tester.sendKeyUpEvent(modifier);
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    expect(fixture.player.overlay, PlayerOverlay.channelNumber);
    expect(fixture.player.channelNumberLabel, startsWith('1'));
    expect(propagated, hasLength(2));
    fixture.player.closeOverlay();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    expect(fixture.player.overlay, PlayerOverlay.none);
    expect(guideOpens, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    expect(fixture.player.overlay, PlayerOverlay.fullGuide);
    expect(guideOpens, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('edge-triggered player shortcuts ignore repeat events', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing);
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
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
    await tester.pump();
    expect(fixture.player.overlay, PlayerOverlay.osd);
    expect(fixture.player.sleepPickerOpen, isTrue);
    expect(find.byKey(const Key('sleep-timer-picker')), findsOneWidget);

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
        builder: _playerDesktopCanvasBuilder,
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
    await tester.pumpAndSettle();
    expect(fixture.player.overlay, PlayerOverlay.osd);
    expect(fixture.player.sleepPickerOpen, isTrue);
    final sleepChoice = find.text('30 minutes');
    await tester.tap(sleepChoice);
    await tester.pump();
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
        builder: _playerDesktopCanvasBuilder,
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
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    expect(fixture.player.currentChannel?.id, 'channel-1');
    await tester.pump(const Duration(milliseconds: 250));
    expect(fixture.lineup.currentChannelId, 'channel-1');
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    expect(fixture.player.currentChannel?.id, 'channel');
    await tester.pump(const Duration(milliseconds: 250));
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
        builder: _playerDesktopCanvasBuilder,
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
        builder: _playerDesktopCanvasBuilder,
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
        fixture.player.notice,
        'Playback controls are temporarily unavailable. Try again.',
      );
      expect(fixture.player.error, isNull);
      expect(fixture.player.overlay, isNot(PlayerOverlay.error));
      expect(find.byType(NativeVideoSurface), findsOneWidget);
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
        builder: _playerDesktopCanvasBuilder,
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
        builder: _playerDesktopCanvasBuilder,
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

  testWidgets('Mini Guide activates with its supported keyboard selectors', (
    tester,
  ) async {
    for (final key in [
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.select,
    ]) {
      final fixture = _Fixture(PlayerState.playing, channelCount: 2);
      fixture.player.showMiniGuide();
      fixture.player.moveMiniGuide(1);
      await tester.pumpWidget(
        MaterialApp(
          builder: _playerDesktopCanvasBuilder,
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(
        fixture.native.loadCalls,
        1,
        reason: '$key tunes the selected Mini Guide channel',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    }
  });

  testWidgets(
    'track drawers keep Guide shortcuts and errors keep channel recovery',
    (tester) async {
      final errorFixture = _Fixture(
        PlayerState.playing,
        failLoad: true,
        channelCount: 2,
      );
      await errorFixture.player.loadInitialMedia(
        Uri.parse('lineup-test://failure'),
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: _playerDesktopCanvasBuilder,
          home: PlayerView(controller: errorFixture.player, openGuide: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(errorFixture.player.overlay, PlayerOverlay.error);
      final loadsBeforeRecovery = errorFixture.native.loadCalls;

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(errorFixture.native.loadCalls, loadsBeforeRecovery + 1);
      expect(errorFixture.player.overlay, PlayerOverlay.error);

      await tester.pumpWidget(const SizedBox.shrink());
      errorFixture.dispose();

      for (final type in [PlayerTrackType.audio, PlayerTrackType.subtitle]) {
        for (final key in [LogicalKeyboardKey.keyG, LogicalKeyboardKey.f2]) {
          var guideOpened = false;
          final fixture = _Fixture(
            PlayerState.playing,
            tracks: const [
              PlayerTrack(id: 1, type: PlayerTrackType.audio, selected: true),
              PlayerTrack(
                id: 2,
                type: PlayerTrackType.subtitle,
                selected: true,
              ),
            ],
          );
          await tester.pumpWidget(
            MaterialApp(
              builder: _playerTvCanvasBuilder,
              home: PlayerView(
                controller: fixture.player,
                openGuide: () => guideOpened = true,
              ),
            ),
          );
          await tester.pumpAndSettle();
          fixture.player.showTracks(type);
          await tester.pumpAndSettle();

          await tester.sendKeyEvent(key);
          await tester.pump();
          expect(
            guideOpened,
            isTrue,
            reason: '$key opens Guide from ${type.name} drawer',
          );

          await tester.pumpWidget(const SizedBox.shrink());
          fixture.dispose();
        }
      }
    },
  );

  testWidgets('Guide-sized player surface keeps load failures reachable', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing, failLoad: true);
    await fixture.player.loadInitialMedia(Uri.parse('lineup-test://failure'));

    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
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
    expect(fixture.player.error, isNotNull);
    expect(fixture.player.watchingChannelId, isNull);
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
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
    expect(fixture.player.tuning, isTrue);
    expect(fixture.player.watchingChannelId, isNull);

    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
        home: PlayerSurface(controller: fixture.player),
      ),
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
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(
          controller: fixture.player,
          openGuide: () => guideOpened = true,
        ),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel(RegExp('Playback controls')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(fixture.player.overlay, PlayerOverlay.miniGuide);
    expect(find.byKey(const Key('mini-guide-shelf')), findsOneWidget);

    fixture.player.closeOverlay();
    fixture.player.showOsd();
    await tester.pumpAndSettle();
    final sleepButton = tester.widget<TextButton>(
      find.byKey(const Key('player-osd-sleep')),
    );
    sleepButton.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(fixture.player.overlay, PlayerOverlay.miniGuide);

    fixture.player.closeOverlay();
    fixture.player.showOsd();
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
        builder: _playerDesktopCanvasBuilder,
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
        builder: _playerDesktopCanvasBuilder,
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
    expect(fixture.player.overlay, PlayerOverlay.osd);
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
          builder: _playerDesktopCanvasBuilder,
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
        _drawnSize(tester, find.byKey(const Key('player-osd-surface'))).width,
        closeTo(size.width, .001),
      );
      final progressLine = _drawnRect(
        tester,
        find.byKey(const Key('player-osd-progress-line')),
      );
      expect(progressLine.left, 0, reason: '$size');
      expect(progressLine.width, closeTo(size.width, .001), reason: '$size');
      expect(progressLine.bottom, closeTo(size.height, .001), reason: '$size');
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
          builder: _playerDesktopCanvasBuilder,
          key: ValueKey(size),
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.bySemanticsLabel(RegExp('Mini Guide')), findsOneWidget);
      expect(
        _drawnSize(tester, find.byKey(const Key('mini-guide-shelf'))).width,
        closeTo(size.width, .001),
      );
      expect(fixture.player.miniGuideChannels, hasLength(5));
      expect(
        find.textContaining('Browse · Enter Tune · Esc Close'),
        findsOneWidget,
      );
      final shelf = _drawnRect(
        tester,
        find.byKey(const Key('mini-guide-shelf')),
      );
      expect(
        MediaQuery.sizeOf(
          tester.element(find.byKey(const Key('mini-guide-shelf'))),
        ),
        size / LineupCanvas.scaleFor(size),
      );
      for (final channel in fixture.player.miniGuideChannels) {
        final row = _drawnRect(
          tester,
          find.byKey(Key('mini-guide-row-${channel.id}')),
        );
        expect(row.top, greaterThanOrEqualTo(shelf.top), reason: '$size');
        final miniScroll = tester
            .state<ScrollableState>(
              find.descendant(
                of: find.byKey(const Key('mini-guide-scroll')),
                matching: find.byType(Scrollable),
              ),
            )
            .position;
        if (miniScroll.maxScrollExtent == 0) {
          expect(row.bottom, lessThanOrEqualTo(shelf.bottom), reason: '$size');
        }
        if (LineupLayout.isCompactWidth(
              (size / LineupCanvas.scaleFor(size)).width,
            ) ||
            (size / LineupCanvas.scaleFor(size)).height < 720) {
          expect(
            row.height,
            greaterThan(48 * LineupCanvas.scaleFor(size)),
            reason: '$size',
          );
        } else {
          expect(
            row.height,
            closeTo(
              ((size / LineupCanvas.scaleFor(size)).width >= 1920 &&
                          (size / LineupCanvas.scaleFor(size)).height >= 1080
                      ? 66
                      : 56) *
                  LineupCanvas.scaleFor(size),
              0.01,
            ),
            reason: '$size',
          );
        }
        for (final fact in ['current', 'next']) {
          final factRect = _drawnRect(
            tester,
            find.byKey(Key('mini-guide-$fact-${channel.id}')),
          );
          expect(row.contains(factRect.topLeft), isTrue, reason: '$size');
          expect(row.contains(factRect.bottomRight), isTrue, reason: '$size');
        }
      }
      if (size.height >= 900 && !LineupLayout.isCompactWidth(size.width)) {
        expect(shelf.height / size.height, lessThan(0.55), reason: '$size');
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
          builder: _playerDesktopCanvasBuilder,
          key: ValueKey(size),
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(fixture.player.nextProgram, isNotNull, reason: '$size');

      final surface = _drawnRect(
        tester,
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
        final timeline = _drawnRect(
          tester,
          find.byKey(const Key('player-osd-progress-block')),
        );
        final controls = _drawnRect(
          tester,
          find.byKey(const Key('player-osd-horizontal-layout')),
        );
        final identity = _drawnRect(
          tester,
          find.byKey(const Key('player-osd-identity')),
        );
        final actions = _drawnRect(
          tester,
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
        final timeline = _drawnRect(
          tester,
          find.byKey(const Key('player-osd-progress-block')),
        );
        final nextRect = _drawnRect(
          tester,
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
          builder: _playerDesktopCanvasBuilder,
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
      for (final label in [
        'Audio tracks unavailable',
        'Subtitles unavailable',
      ]) {
        expect(find.byTooltip(label), findsOneWidget);
        final semantics = tester
            .getSemantics(find.bySemanticsLabel(label))
            .getSemanticsData();
        expect(semantics.flagsCollection.isEnabled, Tristate.isFalse);
        expect(semantics.hasAction(SemanticsAction.tap), isFalse);
      }

      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    }
  }, semanticsEnabled: true);

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
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();

    expect(find.text('Subtitles • Off'), findsOneWidget);
    expect(find.text('Audio • English stereo'), findsOneWidget);
    expect(find.text('Sleep'), findsOneWidget);
    expect(find.byKey(const Key('player-osd-subtitles')), findsOneWidget);
    expect(find.byKey(const Key('player-osd-audio')), findsOneWidget);
    expect(find.byKey(const Key('player-osd-sleep')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('Player menu supplies its exact button context and focus owner', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing);
    BuildContext? invokerContext;
    FocusNode? invokerFocus;
    fixture.player.showOsd();
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(
          controller: fixture.player,
          openGuide: () {},
          openMenu: (context, focus) {
            invokerContext = context;
            invokerFocus = focus;
          },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('player-app-menu')));

    expect(invokerContext, isNotNull);
    expect(invokerFocus?.debugLabel, 'Player Lineup menu');
    expect(
      find.descendant(
        of: find.byWidget(invokerContext!.widget),
        matching: find.byKey(const Key('player-app-menu')),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('Player panels remain unclipped at text scale two', (
    tester,
  ) async {
    final fixture = _Fixture(
      PlayerState.playing,
      channelCount: 5,
      tracks: const [
        PlayerTrack(
          id: 1,
          type: PlayerTrackType.audio,
          selected: true,
          title: 'A long descriptive English surround audio track label',
          language: 'English',
          codec: 'eac3',
        ),
      ],
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in const [
      Size(800, 600),
      Size(1280, 720),
      Size(1920, 1080),
      Size(3840, 2160),
    ]) {
      await tester.binding.setSurfaceSize(size);
      for (final (show, overlay) in <(VoidCallback, Finder)>[
        (
          fixture.player.showMiniGuide,
          find.byKey(const Key('mini-guide-shelf')),
        ),
        (
          () => fixture.player.showTracks(PlayerTrackType.audio),
          find.byKey(const Key('playback-options-fade')),
        ),
        (
          fixture.player.showSleepTimer,
          find.byKey(const Key('sleep-timer-picker')),
        ),
      ]) {
        fixture.player.closeOverlay();
        show();
        await tester.pumpWidget(
          MaterialApp(
            builder: _playerDesktopCanvasBuilder,
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: PlayerView(controller: fixture.player, openGuide: () {}),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 350));
        expect(overlay, findsOneWidget, reason: '$size');
        expect(tester.takeException(), isNull, reason: '$size');
      }
    }
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
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pumpAndSettle();

    final status = tester.widget<Text>(
      find.byKey(const Key('player-osd-status')),
    );
    expect(status.data, 'S2 · E6 — Program');
    expect(status.data, isNot(contains('Playing')));
    expect(find.text('1080p'), findsNothing);
    expect(find.text('1920×1080'), findsNothing);
    expect(find.text('h264'), findsNothing);

    fixture.player.showNowPlaying();
    await tester.pumpAndSettle();
    final nowPlayingSemantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byKey(const Key('player-now-playing-details')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(
      nowPlayingSemantics.properties.label,
      allOf(contains('H.264'), isNot(contains('1920×1080'))),
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
          builder: _playerDesktopCanvasBuilder,
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
        builder: _playerDesktopCanvasBuilder,
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

  testWidgets(
    'chosen OSD logo height preserves width and small-window bounds',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final config in [
        (
          window: const Size(1920, 1080),
          maximum: const Size(520, 104),
          minimum: const Size(96, 28),
        ),
        (
          window: const Size(1280, 720),
          maximum: const Size(360, 104),
          minimum: const Size(96, 28),
        ),
        (
          window: const Size(800, 600),
          maximum: const Size(360, 72),
          minimum: const Size(96, 24),
        ),
      ]) {
        await tester.binding.setSurfaceSize(config.window);
        final fixture = _Fixture(PlayerState.playing, richProgram: true);
        await fixture.guide.ensureCurrentProgram('channel');
        fixture.player.showOsd();
        await tester.pumpWidget(
          MaterialApp(
            builder: _playerDesktopCanvasBuilder,
            home: PlayerView(controller: fixture.player, openGuide: () {}),
          ),
        );
        await tester.pumpAndSettle();
        final logo = tester.widget<ClearLogoImage>(
          find.descendant(
            of: find.byKey(const Key('player-osd-identity')),
            matching: find.byType(ClearLogoImage),
          ),
        );
        expect(logo.maximumSize, config.maximum);
        expect(logo.minimumVisibleSize, config.minimum);
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
      }
    },
  );

  testWidgets('OSD uses official title artwork with a text fallback', (
    tester,
  ) async {
    final logoBytes = File(
      'test/support/now_playing/signal-after-midnight-title.png',
    ).readAsBytesSync();
    final cases = [
      (
        fixture: _Fixture(
          PlayerState.playing,
          richProgram: true,
          artworkBytes: logoBytes,
        ),
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
          builder: _playerDesktopCanvasBuilder,
          key: ValueKey(item.logo),
          home: PlayerView(controller: item.fixture.player, openGuide: () {}),
        ),
      );
      await tester.pumpAndSettle();
      if (item.logo) {
        // ClearLogoImage decodes its own raster outside the fake test clock;
        // precaching MemoryImage does not wait for that work to finish.
        final elapsed = Stopwatch()..start();
        while (find.byKey(const Key('player-osd-logo')).evaluate().isEmpty &&
            elapsed.elapsed < const Duration(seconds: 5)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
      }
      expect(
        find.byKey(const Key('player-osd-logo')),
        item.logo ? findsOneWidget : findsNothing,
        reason: item.description,
      );
      final titleSemantics = find.bySemanticsLabel('Lineup Stories');
      expect(titleSemantics, findsOneWidget, reason: item.description);
      final titleData = tester
          .getSemantics(
            find.byKey(Key(item.logo ? 'player-osd-logo' : 'player-osd-title')),
          )
          .getSemanticsData();
      expect(titleData.label, 'Lineup Stories', reason: item.description);
      expect(
        titleData.flagsCollection.isImage,
        item.logo,
        reason: item.description,
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('player-osd-status'))).data,
        'S2 · E6 — Program',
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
  }, semanticsEnabled: true);

  testWidgets('OSD keeps show identity and compact episode facts', (
    tester,
  ) async {
    final cases = [
      (
        item: _fixtureItem(
          0,
          rich: true,
          title: 'Episode title',
          duration: const Duration(hours: 1),
        ),
        primary: 'Lineup Stories',
        facts: 'S2 · E6 — Episode title',
      ),
      (
        item: const ChannelItem(
          id: 'un-numbered-episode',
          title: 'Episode title',
          duration: Duration(hours: 1),
          showTitle: 'Un-numbered Show',
        ),
        primary: 'Un-numbered Show',
        facts: 'Episode title',
      ),
      (
        item: const ChannelItem(
          id: 'season-zero',
          title: 'Special',
          duration: Duration(hours: 1),
          showTitle: 'Zero Show',
          seasonNumber: 0,
        ),
        primary: 'Zero Show',
        facts: 'S0 — Special',
      ),
      (
        item: const ChannelItem(
          id: 'episode-zero',
          title: 'Pilot',
          duration: Duration(hours: 1),
          showTitle: 'Episode Zero Show',
          episodeNumber: 0,
        ),
        primary: 'Episode Zero Show',
        facts: 'E0 — Pilot',
      ),
      (
        item: const ChannelItem(
          id: 'duplicate-title',
          title: 'Same Show',
          duration: Duration(hours: 1),
          showTitle: 'Same Show',
          seasonNumber: 0,
          episodeNumber: 0,
        ),
        primary: 'Same Show',
        facts: 'S0 · E0',
      ),
      (
        item: const ChannelItem(
          id: 'movie-with-numbers',
          title: 'Movie',
          duration: Duration(hours: 1),
          seasonNumber: 0,
          episodeNumber: 0,
        ),
        primary: 'Movie',
        facts: 'S0 · E0',
      ),
      (
        item: const ChannelItem(
          id: 'movie',
          title: 'Movie',
          duration: Duration(hours: 1),
        ),
        primary: 'Movie',
        facts: null,
      ),
    ];

    for (final itemCase in cases) {
      final fixture = _Fixture(
        PlayerState.playing,
        preferClearLogos: false,
        richItemOverride: itemCase.item,
      );
      await fixture.guide.ensureCurrentProgram('channel');
      fixture.player.showOsd();
      await tester.pumpWidget(
        MaterialApp(
          builder: _playerDesktopCanvasBuilder,
          key: ValueKey(itemCase.item.id),
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('player-osd-title'))).data,
        itemCase.primary,
        reason: itemCase.item.id,
      );
      final status = find.byKey(const Key('player-osd-status'));
      if (itemCase.facts == null) {
        expect(status, findsNothing, reason: itemCase.item.id);
      } else {
        expect(tester.widget<Text>(status).data, itemCase.facts);
      }

      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    }
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
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pumpAndSettle();

    final surface = _drawnSize(
      tester,
      find.byKey(const Key('player-osd-surface')),
    );
    expect(surface.width, 1920);
    expect(surface.height / 1080, lessThan(0.20));
    final progressLine = _drawnRect(
      tester,
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
    final fixture = _Fixture(PlayerState.playing, dvrControlsEnabled: true);
    for (final size in const [Size(1280, 720), Size(1920, 1080)]) {
      await tester.binding.setSurfaceSize(size);
      fixture.player.showOsd();
      await tester.pumpWidget(
        MaterialApp(
          builder: _playerDesktopCanvasBuilder,
          key: ValueKey(size),
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pump();
      final seekTarget = _drawnRect(
        tester,
        find.byKey(const Key('player-osd-progress-line')),
      );
      final actions = _drawnRect(
        tester,
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
  }, semanticsEnabled: true);

  testWidgets('player overlays retain 1280x720 layout at DPR2', (tester) async {
    final fixture = _Fixture(PlayerState.playing);
    tester.view
      ..devicePixelRatio = 2
      ..physicalSize = const Size(2560, 1440);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    fixture.player.showOsd();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      _drawnSize(tester, find.byKey(const Key('player-osd-surface'))).width,
      1280,
    );

    fixture.player.showMiniGuide();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      _drawnSize(tester, find.byKey(const Key('mini-guide-shelf'))).width,
      1280,
    );
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(3840, 2160);
    await tester.pump();
    expect(
      _drawnSize(tester, find.byKey(const Key('mini-guide-shelf'))).width,
      1920,
    );
    expect(
      _drawnSize(tester, find.byKey(const Key('mini-guide-shelf'))).height /
          1080,
      lessThan(0.34),
    );
    for (final channel in fixture.player.miniGuideChannels) {
      expect(
        _drawnSize(
          tester,
          find.byKey(Key('mini-guide-row-${channel.id}')),
        ).height,
        66,
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
        builder: _playerDesktopCanvasBuilder,
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

  testWidgets(
    'Reduce Motion settles panels in one pump while the channel tag fades',
    (tester) async {
      final fixture = _Fixture(PlayerState.playing);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: _playerTvCanvasBuilder(context, child),
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
      expect(
        find.bySemanticsLabel(RegExp('Playback controls')),
        findsOneWidget,
      );

      final panel = find.byKey(const Key('player-osd-surface'));
      final fade = tester.widget<FadeTransition>(
        find.ancestor(of: panel, matching: find.byType(FadeTransition)).first,
      );
      final slide = tester.widget<SlideTransition>(
        find.ancestor(of: panel, matching: find.byType(SlideTransition)).first,
      );
      expect(fade.opacity.value, 1);
      expect(slide.position.value, Offset.zero);

      fixture.player.closeOverlay();
      await tester.pump();
      fixture.player.showMiniGuide();
      await tester.pump();
      expect(switcher.duration, Duration.zero);
      expect(switcher.reverseDuration, Duration.zero);
      expect(find.bySemanticsLabel(RegExp('Mini Guide')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
  );

  testWidgets(
    'reopened OSD rejects outgoing focus loss and keeps focused semantics',
    (tester) async {
      final fixture = _Fixture(
        PlayerState.playing,
        overlayTimeout: const Duration(milliseconds: 100),
      );
      final rootFocus = FocusNode();
      addTearDown(rootFocus.dispose);
      fixture.player.showOsd();
      await tester.pumpWidget(
        MaterialApp(
          builder: _playerDesktopCanvasBuilder,
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

      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
    semanticsEnabled: true,
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
        builder: _playerDesktopCanvasBuilder,
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
    expect(fixture.player.overlay, PlayerOverlay.miniGuide);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  for (final keyboard in [false, true]) {
    testWidgets(
      '${keyboard ? 'keyboard' : 'mouse'} Sleep choice restores appropriate focus and timeout',
      (tester) async {
        final fixture = _Fixture(
          PlayerState.playing,
          overlayTimeout: const Duration(seconds: 1),
        );
        fixture.player.showOsd();
        await tester.pumpWidget(
          MaterialApp(
            builder: _playerDesktopCanvasBuilder,
            home: PlayerView(controller: fixture.player, openGuide: () {}),
          ),
        );
        await tester.pumpAndSettle();
        if (keyboard) {
          await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        } else {
          await tester.tap(
            find.byKey(const Key('player-osd-sleep')),
            kind: PointerDeviceKind.mouse,
          );
        }
        await tester.pump();
        if (keyboard) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          final choiceContext = tester.element(find.text('30 minutes'));
          Focus.of(choiceContext).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        } else {
          await tester.tap(
            find.text('30 minutes'),
            kind: PointerDeviceKind.mouse,
          );
        }
        await tester.pump();
        expect(fixture.player.sleepDuration, const Duration(minutes: 30));
        await tester.pump(const Duration(seconds: 2));
        expect(
          fixture.player.overlay,
          keyboard ? PlayerOverlay.osd : PlayerOverlay.none,
        );
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          keyboard ? 'Player sleep timer' : 'Player root',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
      },
    );

    testWidgets(
      '${keyboard ? 'keyboard' : 'mouse'} app menu dismissal restores appropriate Player focus and timeout',
      (tester) async {
        final fixture = _Fixture(
          PlayerState.playing,
          overlayTimeout: const Duration(seconds: 1),
        );
        fixture.lineup.fixtureActor.present(
          LineupPresentation(stage: SetupStage.ready),
        );
        await tester.pumpWidget(
          MaterialApp(
            builder: _playerDesktopCanvasBuilder,
            home: LineupShell(
              player: fixture.native,
              controller: fixture.lineup,
              initialMediaPath: '/synthetic.mp4',
              profile: desktopProfile,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final player = tester
            .widget<PlayerView>(find.byType(PlayerView))
            .controller;
        player.showOsd();
        await tester.pump(const Duration(milliseconds: 400));
        if (keyboard) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          final menu = tester.widget<IconButton>(
            find.byKey(const Key('player-app-menu')),
          );
          menu.focusNode!.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        } else {
          await tester.tap(
            find.byKey(const Key('player-app-menu')),
            kind: PointerDeviceKind.mouse,
          );
        }
        await tester.pump();
        expect(find.text('Plex account'), findsOneWidget);
        if (keyboard) {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        } else {
          await tester.tapAt(const Offset(5, 5), kind: PointerDeviceKind.mouse);
        }
        await tester.pump();
        expect(find.text('Plex account'), findsNothing);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          keyboard ? 'Player Lineup menu' : 'Player',
        );
        await tester.pump(const Duration(seconds: 5));
        expect(
          player.overlay,
          keyboard ? PlayerOverlay.osd : PlayerOverlay.none,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
      },
    );
  }

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
        builder: _playerDesktopCanvasBuilder,
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
        builder: _playerDesktopCanvasBuilder,
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
        builder: _playerDesktopCanvasBuilder,
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
    expect(focused.shape, isNull);
    expect(selected.shape, isNull);
    final focusSurface = tester.widget<Container>(
      find
          .ancestor(
            of: find.byKey(const Key('playback-track-audio-1')),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container && widget.foregroundDecoration != null,
            ),
          )
          .first,
    );
    final focusBorder =
        (focusSurface.foregroundDecoration! as BoxDecoration).border! as Border;
    expect(
      focusBorder.top.color,
      LineupTheme.of(tester.element(find.text('Stereo'))).focusBorder,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('playback-track-audio-2')),
        matching: find.byWidgetPredicate(
          (widget) => widget is Icon && widget.icon == Icons.check,
        ),
      ),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(fixture.native.selectedTracks, [(PlayerTrackType.audio, 1)]);

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
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();
    expect(Focus.of(tester.element(find.text('Off'))).hasFocus, isTrue);
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, 'Off')).selected,
      isTrue,
    );
    expect(
      tester.getTopLeft(find.text('Off')).dy,
      lessThan(tester.getTopLeft(find.text('Subtitle track 3')).dy),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('track rail normalizes blank titles to language and ID labels', (
    tester,
  ) async {
    final fixture = _Fixture(
      PlayerState.playing,
      tracks: const [
        PlayerTrack(
          id: 1,
          type: PlayerTrackType.audio,
          selected: true,
          title: '   ',
          language: 'English',
          codec: 'eac3',
        ),
        PlayerTrack(
          id: 2,
          type: PlayerTrackType.audio,
          selected: false,
          title: '',
          language: '  ',
          codec: '',
        ),
        PlayerTrack(id: 3, type: PlayerTrackType.audio, selected: false),
        PlayerTrack(
          id: 4,
          type: PlayerTrackType.audio,
          selected: false,
          title: '  Director commentary  ',
          language: 'en',
          codec: 'aac',
        ),
      ],
    );
    fixture.player.showTracks(PlayerTrackType.audio);
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();

    expect(find.text('English'), findsOneWidget);
    expect(find.text('Dolby Digital Plus'), findsOneWidget);
    expect(find.text('English • eac3'), findsNothing);
    expect(find.text('Audio track 2'), findsOneWidget);
    expect(find.text('Audio track 3'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Select Audio track: Audio track 2.'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Select Audio track: Audio track 3.'),
      findsOneWidget,
    );
    for (final id in [2, 3]) {
      expect(
        tester
            .widget<ListTile>(find.byKey(Key('playback-track-audio-$id')))
            .subtitle,
        isNull,
        reason: 'track $id has no meaningful detail',
      );
    }
    expect(find.text('English — Director commentary'), findsOneWidget);
    expect(find.text('AAC'), findsOneWidget);
    expect(find.text('   '), findsNothing);
    expect(fixture.native.selectedTracks, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  }, semanticsEnabled: true);

  testWidgets('track rows expose one complete actionable semantics identity', (
    tester,
  ) async {
    final fixture = _Fixture(
      PlayerState.playing,
      tracks: const [
        PlayerTrack(
          id: 1,
          type: PlayerTrackType.audio,
          selected: true,
          title: 'Original theatrical mix',
          language: 'en',
          codec: 'aac',
          channelLayout: 'stereo',
        ),
        PlayerTrack(
          id: 2,
          type: PlayerTrackType.audio,
          selected: false,
          language: 'es-419',
          codec: 'eac3',
          channelLayout: '5.1',
        ),
      ],
    );
    fixture.player.showTracks(PlayerTrackType.audio);
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();

    expect(find.text('English — Original theatrical mix'), findsOneWidget);
    expect(find.text('Stereo • AAC'), findsOneWidget);
    expect(find.text('Español'), findsOneWidget);
    expect(
      find.text('Latinoamérica • 5.1 surround • Dolby Digital Plus'),
      findsOneWidget,
    );

    const selectedLabel =
        'Select Audio track: English — Original theatrical mix; Stereo; AAC.';
    const alternateLabel =
        'Select Audio track: Español; Latinoamérica; 5.1 surround; '
        'Dolby Digital Plus.';
    final selectedFinder = find.bySemanticsLabel(selectedLabel);
    final alternateFinder = find.bySemanticsLabel(alternateLabel);
    expect(selectedFinder, findsOneWidget);
    expect(alternateFinder, findsOneWidget);
    final selectedSemantics = tester
        .getSemantics(selectedFinder)
        .getSemanticsData();
    expect(selectedSemantics.flagsCollection.isButton, isTrue);
    expect(selectedSemantics.flagsCollection.isSelected, Tristate.isTrue);
    expect(selectedSemantics.hasAction(SemanticsAction.tap), isTrue);
    final alternateSemantics = tester
        .getSemantics(alternateFinder)
        .getSemanticsData();
    expect(alternateSemantics.flagsCollection.isButton, isTrue);
    expect(alternateSemantics.flagsCollection.isSelected, Tristate.isFalse);
    expect(alternateSemantics.hasAction(SemanticsAction.tap), isTrue);
    expect(
      find.bySemanticsLabel('English — Original theatrical mix'),
      findsNothing,
    );
    expect(find.bySemanticsLabel('Selected'), findsNothing);
    expect(find.bySemanticsLabel('Changing track'), findsNothing);
    expect(
      find.bySemanticsLabel(
        'Audio track: English — Original theatrical mix; Stereo; AAC',
      ),
      findsNothing,
    );
    for (final tooltip in [
      'Audio track: English — Original theatrical mix; Stereo; AAC',
      'Audio track: Español; Latinoamérica; 5.1 surround; Dolby Digital Plus',
    ]) {
      await _showReachableTooltip(tester, tooltip);
      final reachable = tester.semantics.simulatedAccessibilityTraversal();
      expect(
        reachable.where((node) => node.label == selectedLabel),
        hasLength(1),
      );
      expect(
        reachable.where((node) => node.label == alternateLabel),
        hasLength(1),
      );
      Tooltip.dismissAllToolTips();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  }, semanticsEnabled: true);

  testWidgets(
    'pending track semantics retain confirmed selection until native update',
    (tester) async {
      const confirmed = PlayerTrack(
        id: 1,
        type: PlayerTrackType.subtitle,
        selected: true,
        title: 'Festival edition',
        language: 'en',
        codec: 'subrip',
        hearingImpaired: true,
      );
      const requested = PlayerTrack(
        id: 2,
        type: PlayerTrackType.subtitle,
        selected: false,
        language: 'en',
        codec: 'hdmv_pgs_subtitle',
        forced: true,
      );
      final fixture = _Fixture(
        PlayerState.playing,
        tracks: const [confirmed, requested],
      );
      fixture.player.showTracks(PlayerTrackType.subtitle);
      await tester.pumpWidget(
        MaterialApp(
          builder: _playerDesktopCanvasBuilder,
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pump();

      const confirmedLabel =
          'Select Subtitle track: English — Festival edition; subtitles for '
          'deaf and hard-of-hearing viewers; SRT (text).';
      const requestedLabel =
          'Select Subtitle track: English — marked as forced; PGS (image).';
      final requestedNode = tester.getSemantics(
        find.bySemanticsLabel(requestedLabel),
      );
      requestedNode.owner!.performAction(requestedNode.id, SemanticsAction.tap);
      await tester.pump();

      expect(fixture.native.selectedTracks, [(PlayerTrackType.subtitle, 2)]);
      final pendingFinder = find.bySemanticsLabel('$requestedLabel Pending.');
      expect(pendingFinder, findsOneWidget);
      final pendingSemantics = tester
          .getSemantics(pendingFinder)
          .getSemanticsData();
      expect(pendingSemantics.flagsCollection.isSelected, Tristate.isFalse);
      expect(pendingSemantics.flagsCollection.isLiveRegion, isFalse);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(confirmedLabel))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );

      for (final tooltip in [
        'Subtitle track: English — Festival edition; SDH; SRT (text)',
        'Subtitle track: English — Forced; PGS (image)',
      ]) {
        await _showReachableTooltip(tester, tooltip);
        final reachable = tester.semantics.simulatedAccessibilityTraversal();
        final confirmed = reachable.singleWhere(
          (node) => node.label == confirmedLabel,
        );
        final pending = reachable.singleWhere(
          (node) => node.label == '$requestedLabel Pending.',
        );
        expect(
          confirmed.getSemanticsData().flagsCollection.isSelected,
          Tristate.isTrue,
        );
        expect(
          pending.getSemanticsData().flagsCollection.isSelected,
          Tristate.isFalse,
        );
        expect(
          pending.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        Tooltip.dismissAllToolTips();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }

      final pendingNodeId = tester.getSemantics(pendingFinder).id;
      fixture.lineup.notifyListeners();
      await tester.pump();
      expect(tester.getSemantics(pendingFinder).id, pendingNodeId);
      expect(fixture.native.selectedTracks, [(PlayerTrackType.subtitle, 2)]);

      fixture.native.emitTracks(const [
        PlayerTrack(
          id: 1,
          type: PlayerTrackType.subtitle,
          selected: false,
          title: 'Festival edition',
          language: 'en',
          codec: 'subrip',
          hearingImpaired: true,
        ),
        PlayerTrack(
          id: 2,
          type: PlayerTrackType.subtitle,
          selected: true,
          language: 'en',
          codec: 'hdmv_pgs_subtitle',
          forced: true,
        ),
      ]);
      await tester.pump();
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(requestedLabel))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      expect(find.bySemanticsLabel('$requestedLabel Pending.'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
    semanticsEnabled: true,
  );

  testWidgets('subtitle Off is one actionable confirmed choice', (
    tester,
  ) async {
    final fixture = _Fixture(
      PlayerState.playing,
      tracks: const [
        PlayerTrack(id: 3, type: PlayerTrackType.subtitle, selected: false),
      ],
    );
    fixture.player.showTracks(PlayerTrackType.subtitle);
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();

    final offFinder = find.bySemanticsLabel('Select subtitle track: Off.');
    expect(offFinder, findsOneWidget);
    final off = tester.getSemantics(offFinder);
    final data = off.getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isSelected, Tristate.isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    await _showReachableTooltip(tester, 'Off');
    final reachableOff = tester.semantics
        .simulatedAccessibilityTraversal()
        .singleWhere((node) => node.label == 'Select subtitle track: Off.');
    expect(
      reachableOff.getSemanticsData().flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(
      reachableOff.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    off.owner!.performAction(off.id, SemanticsAction.tap);
    await tester.pump();
    expect(fixture.native.selectedTracks, [(PlayerTrackType.subtitle, null)]);
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  }, semanticsEnabled: true);

  testWidgets(
    'subtitle rail preserves Unicode titles, unknown codes, and Off',
    (tester) async {
      final fixture = _Fixture(
        PlayerState.playing,
        tracks: const [
          PlayerTrack(
            id: 7,
            type: PlayerTrackType.subtitle,
            selected: true,
            title: '監督コメンタリー 🎬',
            language: 'ja',
            codec: 'ass',
          ),
          PlayerTrack(
            id: 8,
            type: PlayerTrackType.subtitle,
            selected: false,
            title: '  ',
            language: 'tlh',
            codec: '   ',
          ),
        ],
      );
      fixture.player.showTracks(PlayerTrackType.subtitle);
      await tester.pumpWidget(
        MaterialApp(
          builder: _playerDesktopCanvasBuilder,
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pump();

      expect(find.text('日本語 — 監督コメンタリー 🎬'), findsOneWidget);
      expect(find.text('ASS (styled text)'), findsOneWidget);
      expect(find.text('Klingon'), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const Key('playback-track-subtitle-8')),
            )
            .subtitle,
        isNull,
      );
      expect(find.text('Off'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Off')).dy,
        lessThan(tester.getTopLeft(find.text('日本語 — 監督コメンタリー 🎬')).dy),
      );
      expect(fixture.native.selectedTracks, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
  );

  testWidgets('OSD shares the blank-title fallback with compact labels', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _Fixture(
      PlayerState.playing,
      tracks: const [
        PlayerTrack(
          id: 5,
          type: PlayerTrackType.audio,
          selected: true,
          title: '  ',
          language: 'Deutsch',
        ),
        PlayerTrack(id: 6, type: PlayerTrackType.subtitle, selected: false),
      ],
    );
    fixture.player.showOsd();
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();

    expect(find.text('Audio • Deutsch'), findsOneWidget);
    expect(find.text('Subtitles • Off'), findsOneWidget);
    expect(fixture.native.selectedTracks, isEmpty);

    fixture.player.showTracks(PlayerTrackType.audio);
    await tester.pump();
    expect(find.text('Deutsch'), findsOneWidget);
    expect(
      tester
          .widget<ListTile>(find.byKey(const Key('playback-track-audio-5')))
          .subtitle,
      isNull,
    );
    expect(fixture.native.selectedTracks, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('OSD reads fresh selection from a display-equivalent snapshot', (
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
          language: 'en',
          title: 'Original',
        ),
        PlayerTrack(
          id: 2,
          type: PlayerTrackType.audio,
          selected: false,
          language: 'en',
          title: 'Restored',
        ),
      ],
    );
    fixture.player.showOsd();
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();
    expect(find.text('Audio • English — Original'), findsOneWidget);
    fixture.native.emitTracks(const [
      PlayerTrack(
        id: 1,
        type: PlayerTrackType.audio,
        selected: false,
        language: 'en',
        title: 'Original',
      ),
      PlayerTrack(
        id: 2,
        type: PlayerTrackType.audio,
        selected: true,
        language: 'en',
        title: 'Restored',
      ),
    ]);
    await tester.pump();
    expect(fixture.player.tracks.singleWhere((track) => track.selected).id, 2);
    await tester.pump();
    expect(find.text('Audio • English — Restored'), findsOneWidget);
    expect(find.byTooltip('Audio track: English — Restored'), findsOneWidget);
    expect(fixture.native.selectedTracks, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('OSD keeps the bare category when no track field is meaningful', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _Fixture(
      PlayerState.playing,
      tracks: const [
        PlayerTrack(
          id: 9,
          type: PlayerTrackType.audio,
          selected: true,
          title: ' ',
          language: '',
          codec: '  ',
        ),
      ],
    );
    fixture.player.showOsd();
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();
    expect(find.text('Audio'), findsOneWidget);
    expect(find.textContaining('Audio •'), findsNothing);

    fixture.player.showTracks(PlayerTrackType.audio);
    await tester.pump();
    expect(find.text('Audio track 9'), findsOneWidget);
    expect(
      tester
          .widget<ListTile>(find.byKey(const Key('playback-track-audio-9')))
          .subtitle,
      isNull,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets(
    'OSD keeps compact text and exposes the complete track identity',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = _Fixture(
        PlayerState.playing,
        tracks: const [
          PlayerTrack(
            id: 4,
            type: PlayerTrackType.audio,
            selected: true,
            title: 'Original theatrical mix',
            language: 'en',
            codec: 'truehd',
            channelLayout: '5.1',
          ),
          PlayerTrack(id: 8, type: PlayerTrackType.subtitle, selected: false),
        ],
      );
      fixture.player.showOsd();
      await tester.pumpWidget(
        MaterialApp(
          builder: _playerDesktopCanvasBuilder,
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pump();

      expect(find.text('Audio • English'), findsOneWidget);
      expect(find.textContaining('Dolby TrueHD'), findsNothing);
      const audioDescription =
          'Audio track: English — Original theatrical mix; 5.1 surround; '
          'Dolby TrueHD';
      expect(find.byTooltip(audioDescription), findsOneWidget);
      final audioFinder = find.bySemanticsLabel(audioDescription);
      expect(audioFinder, findsOneWidget);
      final audioSemantics = tester
          .getSemantics(audioFinder)
          .getSemanticsData();
      expect(audioSemantics.flagsCollection.isButton, isTrue);
      expect(audioSemantics.flagsCollection.isEnabled, Tristate.isTrue);
      expect(audioSemantics.hasAction(SemanticsAction.tap), isTrue);

      expect(find.text('Subtitles • Off'), findsOneWidget);
      expect(find.byTooltip('Subtitle tracks: Off'), findsOneWidget);
      final subtitlesSemantics = tester
          .getSemantics(find.bySemanticsLabel('Subtitle tracks: Off'))
          .getSemanticsData();
      expect(subtitlesSemantics.flagsCollection.isEnabled, Tristate.isTrue);
      expect(subtitlesSemantics.hasAction(SemanticsAction.tap), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
    semanticsEnabled: true,
  );

  testWidgets('long track labels stay bounded with untruncated semantics', (
    tester,
  ) async {
    const longTitle =
        'A deliberately long synthetic commentary track title that must remain '
        'ellipsized inside the on-screen display and the options rail';
    final fixture = _Fixture(
      PlayerState.playing,
      tracks: const [
        PlayerTrack(
          id: 11,
          type: PlayerTrackType.audio,
          selected: true,
          title: longTitle,
          language: 'English',
          codec: 'truehd',
        ),
        PlayerTrack(
          id: 12,
          type: PlayerTrackType.audio,
          selected: false,
          title: 'Alternate mix',
          language: 'English',
          codec: 'aac',
        ),
      ],
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 600));
    fixture.player.showOsd();
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();
    final osdLabel = find.text('Audio • English — $longTitle');
    expect(osdLabel, findsOneWidget);
    final osdText = tester.widget<Text>(osdLabel);
    expect(osdText.maxLines, isNull);
    expect(osdText.overflow, isNot(TextOverflow.ellipsis));
    expect(
      tester.renderObject<RenderParagraph>(osdLabel).didExceedMaxLines,
      isFalse,
    );

    await tester.binding.setSurfaceSize(const Size(3840, 2160));
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: PlayerView(controller: fixture.player, openGuide: () {}),
          ),
        ),
      ),
    );
    await tester.pump();
    fixture.player.showTracks(PlayerTrackType.audio);
    await tester.pumpAndSettle();
    expect(find.text('English — $longTitle'), findsOneWidget);
    expect(find.text('Dolby TrueHD'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Select Audio track: English — $longTitle; Dolby TrueHD.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  }, semanticsEnabled: true);

  testWidgets('displaying track metadata emits no native selection command', (
    tester,
  ) async {
    final fixture = _Fixture(
      PlayerState.playing,
      tracks: const [
        PlayerTrack(
          id: 1,
          type: PlayerTrackType.audio,
          selected: true,
          title: 'Stereo',
        ),
        PlayerTrack(
          id: 2,
          type: PlayerTrackType.audio,
          selected: false,
          title: 'Surround',
        ),
      ],
    );
    fixture.player.showOsd();
    fixture.player.showTracks(PlayerTrackType.audio);
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(fixture.native.selectedTracks, isEmpty);

    await tester.tap(find.text('Surround'));
    await tester.pump();
    await tester.pump();
    expect(fixture.native.selectedTracks, [(PlayerTrackType.audio, 2)]);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets(
    'display-only track updates preserve keyed focus and selection identity',
    (tester) async {
      final fixture = _Fixture(
        PlayerState.playing,
        tracks: const [
          PlayerTrack(
            id: 1,
            type: PlayerTrackType.audio,
            selected: true,
            title: 'Original mix',
            language: 'en',
          ),
          PlayerTrack(
            id: 2,
            type: PlayerTrackType.audio,
            selected: false,
            title: 'Alternate mix',
            language: 'en',
          ),
        ],
      );
      fixture.player.showTracks(PlayerTrackType.audio);
      await tester.pumpWidget(
        MaterialApp(
          builder: _playerDesktopCanvasBuilder,
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(
        Focus.of(tester.element(find.text('English — Alternate mix'))).hasFocus,
        isTrue,
      );

      fixture.native.emitTracks(const [
        PlayerTrack(
          id: 1,
          type: PlayerTrackType.audio,
          selected: true,
          title: 'Original mix remastered',
          language: 'en',
          codec: 'flac',
        ),
        PlayerTrack(
          id: 2,
          type: PlayerTrackType.audio,
          selected: false,
          title: 'Alternate mix restored',
          language: 'en',
          codec: 'aac',
        ),
        PlayerTrack(
          id: 3,
          type: PlayerTrackType.audio,
          selected: false,
          title: 'New peer',
          language: 'fr',
        ),
      ]);
      await tester.pump();

      expect(
        Focus.of(tester.element(find.text('English — Alternate mix restored')))
            .hasFocus,
        isTrue,
      );
      expect(
        tester
            .widget<ListTile>(find.byKey(const Key('playback-track-audio-1')))
            .selected,
        isTrue,
      );
      expect(fixture.native.selectedTracks, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
  );

  testWidgets('failed track switch keeps the rail and reports recovery', (
    tester,
  ) async {
    final fixture = _Fixture(
      PlayerState.playing,
      failTrackSelect: true,
      tracks: const [
        PlayerTrack(
          id: 1,
          type: PlayerTrackType.audio,
          selected: true,
          title: 'Stereo',
        ),
        PlayerTrack(
          id: 2,
          type: PlayerTrackType.audio,
          selected: false,
          title: 'Surround',
        ),
      ],
    );
    fixture.player.showTracks(PlayerTrackType.audio);
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Surround'));
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Could not change this track. Try again.'),
      findsOneWidget,
    );
    expect(fixture.player.overlay, PlayerOverlay.audioTracks);
    expect(find.byKey(const Key('playback-options-list')), findsOneWidget);
    expect(find.text('Stereo'), findsOneWidget);
    expect(find.text('Surround'), findsOneWidget);
    expect(
      tester
          .widget<ListTile>(find.byKey(const Key('playback-track-audio-1')))
          .selected,
      isTrue,
    );
    final error = find.text('Could not change this track. Try again.');
    final errorNode = tester.getSemantics(error);
    expect(errorNode.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    final errorNodeId = errorNode.id;
    fixture.lineup.notifyListeners();
    await tester.pump();
    expect(tester.getSemantics(error).id, errorNodeId);
    expect(fixture.native.selectedTracks, [(PlayerTrackType.audio, 2)]);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  }, semanticsEnabled: true);

  testWidgets('mini Guide scrolls in short windows', (tester) async {
    final fixture = _Fixture(PlayerState.playing, channelCount: 5);
    await tester.binding.setSurfaceSize(const Size(800, 240));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    fixture.player.showMiniGuide();
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
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

    final hint = find.textContaining('Browse · Enter Tune · Esc Close');
    expect(_drawnRect(tester, hint).bottom, lessThanOrEqualTo(240));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  for (final isTv in [false, true]) {
    testWidgets(
      'playback drawer hints use the ${isTv ? 'TV' : 'desktop'} vocabulary',
      (tester) async {
        final previousPlatform = debugDefaultTargetPlatformOverride;
        if (isTv) {
          debugDefaultTargetPlatformOverride = TargetPlatform.android;
        }
        final fixture = _Fixture(
          PlayerState.playing,
          tracks: const [
            PlayerTrack(
              id: 1,
              type: PlayerTrackType.audio,
              selected: true,
              title: 'Original mix',
            ),
          ],
        );
        try {
          fixture.player.showMiniGuide();
          await tester.pumpWidget(
            MaterialApp(
              theme: LineupTheme.forName(
                LineupThemeName.emberSteel,
                formFactor: profileFor(isTv).formFactor,
              ),
              builder: _playerCanvasBuilderFor(isTv),
              home: PlayerView(controller: fixture.player, openGuide: () {}),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(
              isTv
                  ? 'Up/Down Browse · Select Tune · Back Close'
                  : 'Up / Down · Browse · Enter Tune · Esc Close',
            ),
            findsOneWidget,
          );

          fixture.player.closeOverlay();
          fixture.player.showOsd();
          fixture.player.showTracks(PlayerTrackType.audio);
          await tester.pumpAndSettle();
          expect(
            find.descendant(
              of: find.byKey(const Key('playback-options-footer')),
              matching: find.text(
                isTv
                    ? 'Up/Down Browse · Select Choose · Back Close'
                    : 'Up/Down Browse · Enter Select · Esc Close',
              ),
            ),
            findsOneWidget,
          );
        } finally {
          fixture.dispose();
          debugDefaultTargetPlatformOverride = previousPlatform;
        }
      },
    );
  }

  testWidgets('mini Guide wheel changes selection without scrolling', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing, channelCount: 7);
    await tester.binding.setSurfaceSize(const Size(800, 240));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    fixture.player.showMiniGuide();
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();

    final scrollable = find.descendant(
      of: find.byKey(const Key('mini-guide-scroll')),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    position.jumpTo(position.maxScrollExtent / 2);
    await tester.pump();
    final pixels = position.pixels;
    final selectedIndex = fixture.player.miniGuideChannelIndex;
    final scroll = find.byKey(const Key('mini-guide-scroll'));

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(scroll),
        scrollDelta: const Offset(0, 40),
      ),
    );
    await tester.pump();
    expect(fixture.player.miniGuideChannelIndex, (selectedIndex + 1) % 7);
    expect(position.pixels, pixels);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(scroll),
        scrollDelta: const Offset(0, -40),
      ),
    );
    await tester.pump();
    expect(fixture.player.miniGuideChannelIndex, selectedIndex);
    expect(position.pixels, pixels);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('mini Guide announces unavailable schedules as shown', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing, failSchedule: true);
    addTearDown(fixture.dispose);
    fixture.player.showMiniGuide();

    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Schedule unavailable'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'Now Schedule unavailable\.')),
      findsOneWidget,
    );
  }, semanticsEnabled: true);

  testWidgets('Now Playing preserves nullable episode facts including zero', (
    tester,
  ) async {
    final fixture = _Fixture(
      PlayerState.playing,
      preferClearLogos: false,
      richItemOverride: const ChannelItem(
        id: 'zero-episode',
        title: 'Zero Episode',
        duration: Duration(hours: 1),
        showTitle: 'Zero Stories',
        episodeNumber: 0,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();
    fixture.player.showNowPlaying();
    await tester.pumpAndSettle();

    expect(find.text('E0 · 60 min'), findsOneWidget);
    expect(find.textContaining('Season'), findsNothing);
    expect(find.text('Zero Episode'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets(
    'Mini Guide single selects, double tunes, and outside dismisses',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = _Fixture(PlayerState.playing, channelCount: 7);
      fixture.player.showMiniGuide();
      await tester.pumpWidget(
        MaterialApp(
          builder: _playerDesktopCanvasBuilder,
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pump();
      final visibleBefore = fixture.player.miniGuideChannels
          .map((channel) => channel.id)
          .toList();
      final target = fixture.player.miniGuideChannels.last;
      final row = find.byKey(Key('mini-guide-row-${target.id}'));

      await tester.tap(row);
      await tester.pump(const Duration(milliseconds: 350));
      expect(fixture.player.miniGuideChannelId, target.id);
      expect(fixture.native.loadCalls, 0);
      expect(
        fixture.player.miniGuideChannels.map((channel) => channel.id),
        visibleBefore,
      );

      await tester.tap(row);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(row);
      await tester.pump();
      await tester.pump();
      expect(fixture.native.loadCalls, greaterThan(0));

      fixture.player.showMiniGuide();
      await tester.pump();
      final commands = fixture.native.transportCommands;
      await tester.tapAt(const Offset(640, 700));
      await tester.pump();
      expect(fixture.player.overlay, PlayerOverlay.none);
      expect(fixture.native.transportCommands, commands);
      await tester.pump(const Duration(milliseconds: 50));

      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
  );

  testWidgets('playback options keep all 256 native track rows reachable', (
    tester,
  ) async {
    final tracks = List.generate(
      256,
      (index) => PlayerTrack(
        id: index + 1,
        type: PlayerTrackType.audio,
        selected: index == 0,
        title: 'Audio choice ${index + 1}',
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
          builder: _playerDesktopCanvasBuilder,
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
      final rail = _drawnRect(
        tester,
        find.byKey(const Key('playback-options-rail')),
      );
      expect(rail.right, size.width);
      expect(rail.height, size.height);
      expect(
        rail.width,
        math.min(size.width * 0.4, 600 * LineupCanvas.scaleFor(size)),
      );
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('Audio choice 256'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$size');
    }

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets(
    '1280 track drawers keep wrapped rows clear of the fixed footer',
    (tester) async {
      const audioTracks = [
        PlayerTrack(
          id: 1,
          type: PlayerTrackType.audio,
          selected: true,
          title: 'Original theatrical mix',
          language: 'en',
          codec: 'truehd',
          channelLayout: '5.1',
        ),
        PlayerTrack(
          id: 2,
          type: PlayerTrackType.audio,
          selected: false,
          title: 'Director commentary',
          language: 'en',
          codec: 'aac',
          channelLayout: 'stereo',
          commentary: true,
        ),
        PlayerTrack(
          id: 3,
          type: PlayerTrackType.audio,
          selected: false,
          language: 'es-419',
          codec: 'eac3',
          channelLayout: '5.1(side)',
        ),
        PlayerTrack(
          id: 4,
          type: PlayerTrackType.audio,
          selected: false,
          title: 'Descriptive restoration',
          language: 'fr',
          codec: 'ac3',
          channelCount: 6,
          channelLayout: 'unknown-layout',
          visualImpaired: true,
        ),
        PlayerTrack(
          id: 5,
          type: PlayerTrackType.audio,
          selected: false,
          title: 'Long shared archival presentation title ending in theatrical',
          language: 'en',
          codec: 'flac',
          channelLayout: 'stereo',
        ),
        PlayerTrack(
          id: 6,
          type: PlayerTrackType.audio,
          selected: false,
          title: 'Long shared archival presentation title ending in commentary',
          language: 'en',
          codec: 'flac',
          channelLayout: 'stereo',
        ),
      ];
      const subtitleTracks = [
        PlayerTrack(
          id: 11,
          type: PlayerTrackType.subtitle,
          selected: true,
          language: 'en',
          codec: 'subrip',
          hearingImpaired: true,
        ),
        PlayerTrack(
          id: 12,
          type: PlayerTrackType.subtitle,
          selected: false,
          language: 'en',
          codec: 'hdmv_pgs_subtitle',
          forced: true,
        ),
        PlayerTrack(
          id: 13,
          type: PlayerTrackType.subtitle,
          selected: false,
          title: 'Festival edition',
          language: 'fr',
          codec: 'ass',
        ),
        PlayerTrack(
          id: 14,
          type: PlayerTrackType.subtitle,
          selected: false,
          language: 'es-419',
          codec: 'subrip',
          external: true,
        ),
        PlayerTrack(
          id: 15,
          type: PlayerTrackType.subtitle,
          selected: false,
          title:
              'Long shared restored subtitle presentation ending in theatrical',
          language: 'en',
          codec: 'subrip',
        ),
        PlayerTrack(
          id: 16,
          type: PlayerTrackType.subtitle,
          selected: false,
          title:
              'Long shared restored subtitle presentation ending in commentary',
          language: 'en',
          codec: 'subrip',
        ),
      ];
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final scenario in [
        (type: PlayerTrackType.audio, tracks: audioTracks),
        (type: PlayerTrackType.subtitle, tracks: subtitleTracks),
      ]) {
        final fixture = _Fixture(PlayerState.playing, tracks: scenario.tracks);
        fixture.player.showTracks(scenario.type);
        await tester.pumpWidget(
          MaterialApp(
            builder: _playerDesktopCanvasBuilder,
            home: PlayerView(controller: fixture.player, openGuide: () {}),
          ),
        );
        await tester.pumpAndSettle();

        final rail = _drawnRect(
          tester,
          find.byKey(const Key('playback-options-rail')),
        );
        final list = _drawnRect(
          tester,
          find.byKey(const Key('playback-options-list')),
        );
        final footer = _drawnRect(
          tester,
          find.byKey(const Key('playback-options-footer')),
        );
        expect(rail.contains(footer.topLeft), isTrue);
        expect(
          rail.contains(footer.bottomRight - const Offset(0.1, 0.1)),
          isTrue,
        );
        expect(list.bottom, lessThan(footer.top));

        for (final track in scenario.tracks) {
          final row = _drawnRect(
            tester,
            find.byKey(Key('playback-track-${scenario.type.name}-${track.id}')),
          );
          final visible = row.intersect(list);
          if (!visible.isEmpty) {
            expect(visible.overlaps(footer), isFalse);
          }
        }

        for (var index = 0; index < 5; index++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pump();
        }
        final prefix = scenario.type == PlayerTrackType.audio
            ? 'English — Long shared archival presentation title ending in '
            : 'English — Long shared restored subtitle presentation ending in ';
        final theatrical = find.text('${prefix}theatrical');
        final commentary = find.text('${prefix}commentary');
        expect(theatrical, findsOneWidget);
        expect(commentary, findsOneWidget);
        expect(list.contains(_drawnRect(tester, theatrical).center), isTrue);
        expect(list.contains(_drawnRect(tester, commentary).center), isTrue);
        expect(Focus.of(tester.element(commentary)).hasFocus, isTrue);
        expect(tester.takeException(), isNull, reason: '${scenario.type}');

        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
      }
    },
  );

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
            title: index == 24
                ? 'Subtitle track $index'
                : 'Subtitle track $index — Closed captions for deaf and hard '
                      'of hearing viewers with additional descriptions in the '
                      'extended restoration',
            language: 'English',
            codec: 'hdmv_pgs_subtitle',
          ),
      ],
    );
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    fixture.player.showTracks(PlayerTrackType.subtitle);
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pumpAndSettle();

    final selected = find.text('English — Subtitle track 24');
    final list = find.byKey(const Key('playback-options-list'));
    expect(Focus.of(tester.element(selected)).hasFocus, isTrue);
    expect(
      _drawnRect(tester, list).contains(tester.getCenter(selected)),
      isTrue,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('track panel scales its reading rail and soft fade through 4K', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final fixture = _Fixture(
      PlayerState.playing,
      tracks: const [
        PlayerTrack(
          id: 1,
          type: PlayerTrackType.audio,
          selected: true,
          title: 'A long descriptive English surround audio track label',
          language: 'English',
          codec: 'eac3',
        ),
      ],
    );
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      tester.view.resetDevicePixelRatio();
    });
    for (final layout in const [
      (
        viewport: Size(800, 600),
        dpr: 1.0,
        width: 320.0,
        fade: 44.0,
        scale: 1.0,
      ),
      (
        viewport: Size(1280, 720),
        dpr: 1.0,
        width: 480.0,
        fade: 44.0,
        scale: 1.0,
      ),
      (
        viewport: Size(1920, 1080),
        dpr: 1.25,
        width: 600.0,
        fade: 55.0,
        scale: 1.0,
      ),
      (
        viewport: Size(1360, 840),
        dpr: 1.0,
        width: 480.0,
        fade: 44.0,
        scale: 1.0,
      ),
      (
        viewport: Size(1600, 900),
        dpr: 1.0,
        width: 500.0,
        fade: 55 * 5 / 6,
        scale: 1.0,
      ),
      (
        viewport: Size(2560, 1440),
        dpr: 1.5,
        width: 800.0,
        fade: 55 * 4 / 3,
        scale: 4 / 3,
      ),
      (
        viewport: Size(3840, 2160),
        dpr: 2.0,
        width: 1200.0,
        fade: 110.0,
        scale: 2.0,
      ),
    ]) {
      await tester.binding.setSurfaceSize(layout.viewport);
      tester.view.devicePixelRatio = layout.dpr;
      fixture.player.showOsd();
      fixture.player.showTracks(PlayerTrackType.audio);
      await tester.pumpWidget(
        MaterialApp(
          builder: _playerDesktopCanvasBuilder,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                devicePixelRatio: layout.dpr,
                textScaler: const TextScaler.linear(2),
              ),
              child: PlayerView(controller: fixture.player, openGuide: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rail = _drawnRect(
        tester,
        find.byKey(const Key('playback-options-rail')),
      );
      final expectedRail = Rect.fromLTWH(
        layout.viewport.width - layout.width,
        0,
        layout.width,
        layout.viewport.height,
      );
      expect(rail.left, closeTo(expectedRail.left, .001));
      expect(rail.top, closeTo(expectedRail.top, .001));
      expect(rail.width, closeTo(expectedRail.width, .001));
      expect(rail.height, closeTo(expectedRail.height, .001));
      final fade = _drawnRect(
        tester,
        find.byKey(const Key('playback-options-fade')),
      );
      expect(fade.right, layout.viewport.width);
      expect(fade.left, closeTo(rail.left - layout.fade, 0.01));
      final decoration =
          tester
                  .widget<Container>(
                    find.byKey(const Key('playback-options-fade')),
                  )
                  .decoration!
              as BoxDecoration;
      final gradient = decoration.gradient! as LinearGradient;
      expect(gradient.stops![1], closeTo(layout.fade / fade.width, .001));
      expect(gradient.stops![2], gradient.stops![1]);
      expect(gradient.colors.first.a, 0);
      expect(gradient.colors.last.a, closeTo(0.78, 0.01));
      expect(find.text('Audio'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('PLAYBACK OPTIONS'), findsNothing);
      expect(
        find.byTooltip(
          'Audio track: English — '
          'A long descriptive English surround audio track label; '
          'Dolby Digital Plus',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .getSemantics(
              find.text(
                'English — A long descriptive English surround audio track label',
              ),
            )
            .label,
        contains('A long descriptive English surround audio track label'),
      );
      expect(
        tester
            .widget<Text>(
              find.text(
                'English — A long descriptive English surround audio track label',
              ),
            )
            .style
            ?.fontSize,
        closeTo(16, 0.01),
      );
      final label = _drawnRect(
        tester,
        find.text(
          'English — A long descriptive English surround audio track label',
        ),
      );
      expect(rail.overlaps(label), isTrue);
      expect(
        _drawnRect(
          tester,
          find.byKey(const Key('playback-options-list')),
        ).contains(label.center),
        isTrue,
      );
      expect(
        Focus.of(
          tester.element(
            find.text(
              'English — A long descriptive English surround audio track label',
            ),
          ),
        ).hasFocus,
        isTrue,
      );
      expect(tester.takeException(), isNull, reason: '${layout.viewport}');
    }

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
    semantics.dispose();
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
        builder: _playerDesktopCanvasBuilder,
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
          child: _playerDesktopCanvasBuilder(context, child),
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

  testWidgets('audio requires a track and empty subtitles explains Off', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing);
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(fixture.player.overlay, PlayerOverlay.none);

    fixture.player.showOsd();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pump();
    expect(fixture.player.overlay, PlayerOverlay.subtitleTracks);
    expect(find.byKey(const Key('playback-options-rail')), findsOneWidget);
    expect(find.text('No subtitle tracks available'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });

  testWidgets('Mini Guide selection keeps its primary foreground', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing);
    fixture.lineup.fixtureActor.publishSettings(
      const LineupSettings(theme: LineupThemeName.directv),
    );
    fixture.player.showMiniGuide();
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
        theme: LineupTheme.forName(LineupThemeName.directv),
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();

    expect(
      tester
          .widget<Text>(
            find
                .descendant(
                  of: find.byKey(const Key('mini-guide-channel-channel')),
                  matching: find.byType(Text),
                )
                .first,
          )
          .style
          ?.color,
      LineupTheme.of(tester.element(find.text('Channel').first)).primaryText,
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
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();

    expect(fixture.lineup.settings.preferClearLogos, isTrue);
    fixture.player.showNowPlaying();
    await tester.pump();
    await tester.pumpAndSettle();
    await _settleNowPlayingArtwork(tester);

    expect(find.byKey(const Key('player-now-playing-surface')), findsOneWidget);
    expect(find.byKey(const Key('player-osd-channel-bug')), findsOneWidget);
    expect(find.byKey(const Key('player-now-playing-channel')), findsNothing);
    expect(
      _drawnSize(tester, find.byKey(const Key('player-osd-surface'))).width,
      1280,
    );
    expect(
      _drawnSize(tester, find.byKey(const Key('player-osd-surface'))).height,
      lessThan(720),
    );
    expect(
      MediaQuery.sizeOf(
        tester.element(find.byKey(const Key('player-now-playing-surface'))),
      ),
      const Size(1600, 900),
    );
    expect(fixture.lineup.artworkRequests, hasLength(2));
    expect(find.byKey(const Key('player-now-playing-logo')), findsOneWidget);
    expect(
      find.byType(Image),
      findsOneWidget,
    ); // Poster; the logo owns a RawImage.
    expect(
      find.text('S2 E6 · 60 min · 2026 · Drama · Adventure'),
      findsOneWidget,
    );
    final title = tester.widget<Text>(
      find.byKey(const Key('player-now-playing-title')),
    );
    expect(title.style?.fontSize, 54);
    expect(title.style?.fontWeight, FontWeight.w600);
    expect(
      find.text('A synthetic synopsis for deterministic tests.'),
      findsOneWidget,
    );
    expect(find.text('TV-14'), findsOneWidget);
    expect(find.byKey(const Key('player-osd-channel-bug')), findsOneWidget);
    expect(find.bySemanticsLabel('Channel 7, Channel'), findsOneWidget);
    expect(find.bySemanticsLabel('7 • Channel'), findsNothing);
    expect(find.text('H.264'), findsOneWidget);
    expect(
      find.byKey(const Key('player-now-playing-runtime-facts')),
      findsNothing,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Now playing\..*Program')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Playback progress'), findsOneWidget);

    final progressSemantics = tester.widget<Semantics>(
      find.descendant(
        of: find.byKey(const Key('player-osd-progress-line')),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Playback progress',
        ),
      ),
    );
    expect(progressSemantics.properties.value, '10:00 of 1:00:00');
    fixture.player.showOsd();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.bySemanticsLabel(RegExp(r'^Now playing\.')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Playback controls')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  }, semanticsEnabled: true);

  testWidgets(
    'Now Playing renders bounded cast portraits, fallbacks, names, and semantics',
    (tester) async {
      final cast = [
        ..._fixtureCast.take(3),
        ChannelCastMember(name: 'Alexander Maximilian Montgomery'),
        ..._fixtureCast.skip(5),
      ];
      final fixture = _Fixture(
        PlayerState.playing,
        richItemOverride: _fixtureItem(
          0,
          rich: true,
          duration: const Duration(hours: 1),
          cast: cast,
        ),
      );
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          builder: _playerDesktopCanvasBuilder,
          home: PlayerView(controller: fixture.player, openGuide: () {}),
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
        find.byKey(const Key('player-now-playing-cast-fallback-3')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('player-now-playing-cast-more')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('player-now-playing-cast-name-4')),
        findsNothing,
      );
      for (final member in cast.take(4)) {
        expect(find.text(member.name), findsOneWidget);
      }
      expect(
        find.byKey(const Key('player-now-playing-cast-names')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('player-now-playing-cast-name-3')),
        findsOneWidget,
      );
      expect(find.byTooltip('Alexander Maximilian Montgomery'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Cast:.*Alexander Maximilian Montgomery')),
        findsOneWidget,
      );
      expect(fixture.lineup.artworkRequests, hasLength(5));
      expect(
        find.bySemanticsLabel(
          RegExp(
            r'Cast: Avery Vale as Detective Rowan.*Mina Park as Dr\. Lena Quill',
          ),
        ),
        findsOneWidget,
      );
      final canonical = tester.semantics
          .simulatedAccessibilityTraversal()
          .singleWhere((node) => node.label.startsWith('Now playing.'))
          .label;
      final visualLabels = [
        for (final member in cast.take(4)) ...[
          member.name,
          if (member.role != null) member.role!,
        ],
        tester
            .widget<Text>(find.byKey(const Key('player-now-playing-title')))
            .data!,
        tester
            .widget<Text>(find.byKey(const Key('player-now-playing-editorial')))
            .data!,
        tester
            .widget<Text>(find.byKey(const Key('player-now-playing-summary')))
            .data!,
      ];
      expect(
        tester.semantics.simulatedAccessibilityTraversal().map(
          (node) => node.label,
        ),
        isNot(anyElement(isIn(visualLabels))),
      );
      for (final message in [
        'Alexander Maximilian Montgomery',
        cast.first.role!,
      ]) {
        await _showReachableTooltip(tester, message);
        expect(
          tester.semantics.simulatedAccessibilityTraversal().where(
            (node) => node.label == canonical,
          ),
          hasLength(1),
        );
        Tooltip.dismissAllToolTips();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
    semanticsEnabled: true,
  );

  for (final config in [
    (size: const Size(1920, 1080), dpr: 1.0),
    (size: const Size(3840, 2160), dpr: 1.0),
    (size: const Size(1536, 864), dpr: 1.25),
  ]) {
    testWidgets(
      'portrait requests match painted pixels ${config.size}/${config.dpr}',
      (tester) async {
        tester.view
          ..devicePixelRatio = config.dpr
          ..physicalSize = config.size * config.dpr;
        addTearDown(tester.view.reset);
        final fixture = _Fixture(
          PlayerState.playing,
          richItemOverride: _fixtureItem(
            0,
            rich: true,
            duration: const Duration(hours: 1),
            cast: _fixtureCast,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            builder: _playerDesktopCanvasBuilder,
            home: PlayerView(controller: fixture.player, openGuide: () {}),
          ),
        );
        fixture.player.showNowPlaying();
        await tester.pumpAndSettle();
        final size = _drawnSize(
          tester,
          find.byKey(const Key('player-now-playing-cast-portrait-0')),
        );
        final request =
            fixture.lineup.portraitSizes[_fixtureCast.first.portrait]!;
        expect(request.width, (size.width * config.dpr).ceil());
        expect(request.height, (size.height * config.dpr).ceil());
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
      },
    );
  }

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
        builder: _playerDesktopCanvasBuilder,
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
        builder: _playerDesktopCanvasBuilder,
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
        dvrControlsEnabled: true,
        guideClock: () => now,
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: _playerDesktopCanvasBuilder,
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pump();
      fixture.player.showNowPlaying();
      await tester.pumpAndSettle();

      expect(find.text('30:00 / 1:00:00 • 30m left'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.descendant(
                of: find.byKey(const Key('player-osd-progress-line')),
                matching: find.byType(LinearProgressIndicator),
              ),
            )
            .value,
        0.5,
      );

      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      expect(fixture.native.transportCommands, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
  );

  testWidgets('Now Playing omits unknown dynamic range', (tester) async {
    final fixture = _Fixture(
      PlayerState.playing,
      richItemOverride: _fixtureItem(
        0,
        rich: true,
        duration: const Duration(hours: 1),
        dynamicRange: 'unknown',
      ),
    );
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();
    fixture.player.showNowPlaying();
    await tester.pumpAndSettle();

    // This assertion must fail on the unchanged production baseline if NF-23
    // is confirmed. The surface assertion prevents an absent-panel false pass.
    expect(find.byKey(const Key('player-now-playing-surface')), findsOneWidget);
    expect(find.text('TV-14'), findsOneWidget);
    expect(find.text('UNKNOWN'), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'\. UNKNOWN\.')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final (videoFormat, catalogCodec, runtimeCodec, expected) in [
    ('hevc', 'h264', 'vp9', 'HEVC'),
    ('', 'h264', 'vp9', 'H.264'),
    ('', null, 'vp9', 'VP9'),
  ]) {
    testWidgets(
      'Now Playing codec precedence $videoFormat/$catalogCodec/$runtimeCodec',
      (tester) async {
        final fixture = _Fixture(
          PlayerState.playing,
          richItemOverride: ChannelItem(
            id: 'program',
            title: 'Program',
            duration: const Duration(hours: 1),
            contentRating: 'TV-14',
            videoCodec: catalogCodec,
          ),
          nativeTelemetry: PlayerTelemetry(
            videoFormat: videoFormat,
            videoCodec: runtimeCodec,
          ),
        );
        addTearDown(fixture.dispose);
        await tester.pumpWidget(
          MaterialApp(
            builder: _playerDesktopCanvasBuilder,
            home: PlayerView(controller: fixture.player, openGuide: () {}),
          ),
        );
        await tester.pump();
        fixture.player.showNowPlaying();
        await tester.pumpAndSettle();

        final badges = find.byKey(const Key('player-now-playing-badges'));
        expect(badges, findsOneWidget);
        expect(
          find.descendant(of: badges, matching: find.text(expected)),
          findsOneWidget,
        );
        final displayedCodecs = tester
            .widgetList<Text>(
              find.descendant(of: badges, matching: find.byType(Text)),
            )
            .map((text) => text.data)
            .where((text) => const {'HEVC', 'H.264', 'VP9'}.contains(text));
        expect(displayedCodecs, [expected]);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('runtime HDR overrides stale catalog SDR', (tester) async {
    final fixture = _Fixture(
      PlayerState.playing,
      richItemOverride: _fixtureItem(
        0,
        rich: true,
        duration: const Duration(hours: 1),
        dynamicRange: 'sdr',
      ),
      nativeTelemetry: const PlayerTelemetry(gamma: 'pq'),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
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
          builder: _playerDesktopCanvasBuilder,
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
        builder: _playerDesktopCanvasBuilder,
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
    await tester.tap(find.byKey(const Key('player-now-playing-details')));
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
          builder: _playerDesktopCanvasBuilder,
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pump();

      fixture.player.showNowPlaying();
      await tester.pumpAndSettle();
      await _settleNowPlayingArtwork(tester);
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
          builder: _playerDesktopCanvasBuilder,
          home: PlayerView(controller: disabled.player, openGuide: () {}),
        ),
      );
      await tester.pump();
      disabled.player.showNowPlaying();
      await tester.pumpAndSettle();

      expect(disabled.lineup.artworkRequests, hasLength(1));
      expect(
        disabled.lineup.artworkRequests,
        isNot(contains(Uri.parse('/library/metadata/test/logo'))),
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
    await tester.binding.setSurfaceSize(const Size(640, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();
    fixture.player.showNowPlaying();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('player-now-playing-cast')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('player-now-playing-cast-name-3')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('player-now-playing-cast-name-4')),
      findsNothing,
    );
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
        builder: _playerDesktopCanvasBuilder,
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
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
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
      containsAll([
        '/library/metadata/test/poster-replacement',
        '/library/metadata/test/logo-replacement',
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
        builder: _playerDesktopCanvasBuilder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
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
    await _settleNowPlayingArtwork(tester);

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
          builder: _playerDesktopCanvasBuilder,
          home: PlayerView(controller: fixture.player, openGuide: () {}),
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
    final wideArtwork = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAMAAAABCAAAAAA+i0toAAAADElEQVR4nGP4//8/AAX+Av4N70a4AAAAAElFTkSuQmCC',
    );

    for (final variant in const [
      (
        castPresent: false,
        maxShelves: [
          Size(760, 336),
          Size(1180, 380),
          Size(1180, 450),
          Size(1180, 540),
          Size(2360, 1080),
        ],
        dpr2MaxShelf: Size(1180, 540),
      ),
      (
        castPresent: true,
        maxShelves: [
          Size(760, 378),
          Size(1180, 432),
          Size(1180, 486),
          Size(1180, 580),
          Size(2360, 1160),
        ],
        dpr2MaxShelf: Size(1180, 580),
      ),
    ]) {
      final fixture = variant.castPresent
          ? _Fixture(
              PlayerState.playing,
              artworkBytes: wideArtwork,
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
        final scale = LineupCanvas.scaleFor(viewport);
        final canvas = viewport / scale;
        tester.view.physicalSize = viewport;
        await tester.pumpWidget(
          MaterialApp(
            builder: _playerDesktopCanvasBuilder,
            theme: LineupTheme.forName(LineupThemeName.emberSteel),
            home: PlayerView(controller: fixture.player, openGuide: () {}),
          ),
        );
        await tester.pump();
        fixture.player.showNowPlaying();
        await tester.pumpAndSettle();
        await _settleNowPlayingArtwork(tester);

        if (index == 0) {
          await tester.runAsync(
            () => precacheImage(
              MemoryImage(variant.castPresent ? wideArtwork : _fixtureArtwork),
              tester.element(find.byType(PlayerView)),
            ),
          );
          await tester.pumpAndSettle();
        }

        final shelfSize = _drawnSize(
          tester,
          find.byKey(const Key('player-osd-surface')),
        );
        final posterSize = _drawnSize(
          tester,
          find.byKey(const Key('player-now-playing-poster')),
        );
        expect(shelfSize.width, closeTo(viewport.width, .01));
        expect(shelfSize.height, lessThan(viewport.height));
        expect(
          posterSize.width,
          closeTo((canvas.height < 900 ? 160 : 240) * scale, .01),
        );
        expect(
          posterSize.height,
          lessThanOrEqualTo(posterSize.width * 1.5 + .01),
        );
        expect(
          _drawnRect(
            tester,
            find.byKey(const Key('player-osd-surface')),
          ).bottom,
          closeTo(viewport.height, .01),
        );
        expect(
          _drawnRect(
            tester,
            find.byKey(const Key('player-now-playing-title')).last,
          ).top,
          greaterThan(
            _drawnRect(
              tester,
              find.byKey(const Key('player-now-playing-logo')),
            ).top,
          ),
        );
        if (viewport == const Size(1920, 1080)) {
          final title = tester.widget<Text>(
            find.byKey(const Key('player-now-playing-title')).last,
          );
          expect(title.style?.fontSize, 54);
          expect(title.style?.fontWeight, FontWeight.w600);
        }
        expect(
          find.byKey(const Key('player-now-playing-cast')),
          variant.castPresent ? findsOneWidget : findsNothing,
        );
        if (variant.castPresent) {
          final name = find.byKey(const Key('player-now-playing-cast-name-0'));
          final text = tester.widget<Text>(name);
          final context = tester.element(name);
          final measure = TextPainter(
            text: TextSpan(text: text.data, style: text.style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 2,
          )..layout(maxWidth: tester.getSize(name).width);
          expect(
            tester.getSize(name).height,
            greaterThanOrEqualTo(measure.height),
            reason: 'Cast name must fit at $viewport',
          );
          measure.dispose();
        }
        expect(tester.takeException(), isNull, reason: '$viewport');
      }

      tester.view
        ..devicePixelRatio = 2
        ..physicalSize = const Size(3840, 2160);
      await tester.pumpWidget(
        MaterialApp(
          builder: _playerDesktopCanvasBuilder,
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pumpAndSettle();
      await _settleNowPlayingArtwork(tester);
      expect(
        _drawnSize(tester, find.byKey(const Key('player-osd-surface'))).width,
        1920,
      );
      expect(
        _drawnSize(tester, find.byKey(const Key('player-osd-surface'))).height,
        lessThan(1080),
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
            builder: _playerDesktopCanvasBuilder,
            home: PlayerView(controller: fixture.player, openGuide: () {}),
          ),
        );
        fixture.player.showNowPlaying();
        await tester.pumpAndSettle();
        await _settleNowPlayingArtwork(tester);

        expect(
          find.byKey(const Key('player-now-playing-title')),
          findsOneWidget,
        );
        expect(find.text(testCase.item.title), findsOneWidget);
        expect(
          MediaQuery.sizeOf(
            tester.element(find.byKey(const Key('player-now-playing-surface'))),
          ),
          testCase.viewport / LineupCanvas.scaleFor(testCase.viewport),
        );
        expect(
          find.byKey(const Key('player-now-playing-logo')),
          testCase.logo ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const Key('player-osd-progress-line')),
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

  testWidgets(
    'Reduce Motion skips Now Playing animation while artwork resolves',
    (tester) async {
      final fixture = _Fixture(PlayerState.playing, richProgram: true);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: _playerDesktopCanvasBuilder(context, child),
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
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump();
      }
      final panel = find.byKey(const Key('player-now-playing-surface'));
      final fade = tester.widget<FadeTransition>(
        find.ancestor(of: panel, matching: find.byType(FadeTransition)).first,
      );
      expect(fade.opacity.value, 1);
      expect(
        find.byKey(const Key('player-now-playing-surface')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
  );

  testWidgets(
    'retained OSD action focus suspends hide across expansion and collapse',
    (tester) async {
      final fixture = _Fixture(
        PlayerState.playing,
        richProgram: true,
        overlayTimeout: const Duration(seconds: 1),
      );
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: _playerDesktopCanvasBuilder,
          home: PlayerView(
            controller: fixture.player,
            openGuide: () {},
            openMenu: (_, _) {},
          ),
        ),
      );
      await tester.pump();
      fixture.player.showOsd();
      await tester.pumpAndSettle();
      final menu = tester.widget<IconButton>(
        find.byKey(const Key('player-app-menu')),
      );
      menu.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.pumpAndSettle();
      expect(menu.focusNode!.hasFocus, isTrue);
      expect(fixture.player.overlay, PlayerOverlay.nowPlaying);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.pumpAndSettle();
      expect(menu.focusNode!.hasFocus, isTrue);
      await tester.pump(const Duration(seconds: 2));
      expect(fixture.player.overlay, PlayerOverlay.osd);
      menu.focusNode!.unfocus();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(fixture.player.overlay, PlayerOverlay.none);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
  );

  testWidgets(
    'Now Playing expands the same bottom panel and collapses in 200ms',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = _Fixture(PlayerState.playing, richProgram: true);
      await tester.pumpWidget(
        MaterialApp(
          builder: _playerDesktopCanvasBuilder,
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pump();
      fixture.player.showOsd();
      await tester.pumpAndSettle();
      final collapsed = _drawnRect(
        tester,
        find.byKey(const Key('player-osd-surface')),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(fixture.player.overlay, PlayerOverlay.nowPlaying);
      expect(find.byKey(const Key('player-osd-surface')), findsOneWidget);
      expect(find.byKey(const Key('player-osd-progress-line')), findsOneWidget);
      await tester.pumpAndSettle();
      final expanded = _drawnRect(
        tester,
        find.byKey(const Key('player-osd-surface')),
      );
      expect(expanded.top, lessThan(collapsed.top));
      expect(expanded.bottom, collapsed.bottom);
      expect(expanded.left, collapsed.left);
      expect(
        tester.widget<AnimatedSize>(find.byType(AnimatedSize)).duration,
        const Duration(milliseconds: 200),
      );
      await tester.tap(find.byKey(const Key('player-now-playing-collapse')));
      await tester.pumpAndSettle();
      expect(fixture.player.overlay, PlayerOverlay.osd);
      expect(
        _drawnRect(tester, find.byKey(const Key('player-osd-surface'))),
        collapsed,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.pumpAndSettle();
      expect(fixture.player.overlay, PlayerOverlay.nowPlaying);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(fixture.player.overlay, PlayerOverlay.osd);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
  );
}

class _Fixture {
  _Fixture(
    PlayerState state, {
    bool failLoad = false,
    bool failStop = false,
    bool failControls = false,
    bool failTrackSelect = false,
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
    bool failSchedule = false,
    ChannelItem? richItemOverride,
    DateTime Function()? guideClock,
    DateTime Function()? playerClock,
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
      loadSchedule: (channel) async {
        if (failSchedule) throw StateError('Synthetic schedule failure');
        return buildSchedule(
          (channel.source as ManualSource).items,
          mode: channel.playbackMode,
          seed: channel.shuffleSeed,
        );
      },
    )..requestViewport(0, 1);
    native = _Native(
      state,
      failLoad: failLoad,
      failStop: failStop,
      failControls: failControls,
      failTrackSelect: failTrackSelect,
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
      clock: playerClock,
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
  Future<List<PlexCastMember>?> Function(String)? castHandler;
  final castRequests = <String>[];
  @override
  Future<List<PlexCastMember>?> castForItem(
    String itemId, {
    Future<void>? cancelled,
  }) async {
    castRequests.add(itemId);
    return castHandler?.call(itemId);
  }

  _Lineup(
    int channelCount, {
    LineupScenario? scenario,
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
         store: MemoryAppStore(clientId: 'test'),
         credentials: MemoryCredentialStore(),
         plex: PlexClient(
           clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
         ),
       ) {
    final initialChannels = List.generate(
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

    installScenario(
      (scenario ?? const LineupScenario()).withDefaults(
        LineupScenario(
          channels: initialChannels,
          currentChannelId: initialChannels.firstOrNull?.id,
          settings: LineupSettings(
            preferClearLogos: preferClearLogos,
            dvrControlsEnabled: dvrControlsEnabled,
          ),
          stage: SetupStage.ready,
        ),
      ),
    );
  }

  final artworkRequests = <Uri>[];
  final portraitSizes = <Uri, ({int? width, int? height})>{};
  final bool failArtwork;
  final Uint8List? artworkBytes;
  final bool blockArtwork;
  final artworkCompletions = <Uri, Completer<Uint8List?>>{};
  int _contentGeneration = 0;

  @override
  int get contentGeneration => _contentGeneration;

  @override
  Future<Uint8List?> artworkForPath(Uri path, {int? width, int? height}) async {
    artworkRequests.add(path);
    if (width != null || height != null) {
      portraitSizes[path] = (width: width, height: height);
    }
    if (failArtwork) return null;
    if (blockArtwork) {
      return (artworkCompletions[path] ??= Completer<Uint8List?>()).future;
    }
    return artworkBytes ??
        (path.path.contains('/logo') ? _fixtureLogoArtwork : _fixtureArtwork);
  }

  void replaceArtwork(String tag, {bool bumpGeneration = false}) {
    final channel = channels.first;
    fixtureActor.replaceChannels([
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
    ]);
    if (bumpGeneration) _contentGeneration++;
    notifyListeners();
  }

  void bumpContentGeneration() {
    _contentGeneration++;
    notifyListeners();
  }

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
  poster: rich ? Uri.parse('/library/metadata/test/poster$artworkTag') : null,
  backdrop: rich
      ? Uri.parse('/library/metadata/test/backdrop$artworkTag')
      : null,
  clearLogo: rich && includeClearLogo
      ? Uri.parse('/library/metadata/test/logo$artworkTag')
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

Future<void> _settleNowPlayingArtwork(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
  }
}

Future<double> _paintedIconRight(WidgetTester tester, Finder icon) async {
  final text = find.descendant(of: icon, matching: find.byType(RichText));
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
  )..layout(maxWidth: paragraph.size.width);
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), Offset.zero);
  final picture = recorder.endRecording();
  final image = await tester.runAsync(
    () => picture.toImage(
      paragraph.size.width.ceil(),
      paragraph.size.height.ceil(),
    ),
  );
  final pixels = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  var right = -1;
  for (var y = 0; y < image!.height; y++) {
    for (var x = 0; x < image.width; x++) {
      if (pixels!.getUint8((y * image.width + x) * 4 + 3) >= 32) {
        right = math.max(right, x);
      }
    }
  }
  expect(right, greaterThanOrEqualTo(0));
  final drawn = _drawnRect(tester, text);
  final scale = drawn.width / paragraph.size.width;
  image.dispose();
  picture.dispose();
  painter.dispose();
  return drawn.left + (right + 1) * scale;
}

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
    this.failTrackSelect = false,
    this.blockLoad = false,
    List<PlayerTrack> tracks = const [],
    this.positionValue = const Duration(minutes: 10),
    this.durationValue = const Duration(hours: 1),
    this.telemetryValue = const PlayerTelemetry(),
  }) : status = PlayerStatus(
         state: state,
         message: state == PlayerState.unsupported
             ? 'Playback is unavailable on macOS.'
             : 'Playing',
       ) {
    _tracks = tracks;
  }

  bool failLoad;
  final bool failStop;
  final bool failControls;
  final bool failTrackSelect;
  final bool blockLoad;
  final Duration positionValue;
  final Duration durationValue;
  final PlayerTelemetry telemetryValue;
  final loadStarted = Completer<void>();
  final _loadCompletion = Completer<void>();
  final _events = StreamController<PlayerEvent>.broadcast();
  int transportCommands = 0;
  final pausedValues = <bool>[];
  bool emitControlEvents = false;
  int? lastLoadGeneration;

  void emitState(PlayerState state, {Duration? at}) {
    _events.add(
      PlayerEvent(
        status: PlayerStatus(
          state: state,
          message: state.name,
          recoverable: true,
          failureCode: state == PlayerState.error ? 'synthetic' : null,
        ),
        position: at ?? position,
        duration: duration,
        telemetry: telemetry,
        tracks: tracks,
        generation: lastLoadGeneration,
      ),
    );
  }

  int loadCalls = 0;
  final fullscreenValues = <bool>[];
  final selectedTracks = <(PlayerTrackType, int?)>[];

  @override
  final PlayerStatus status;
  @override
  Duration get position => positionValue;
  @override
  Duration get duration => durationValue;
  @override
  PlayerTelemetry get telemetry => telemetryValue;
  @override
  List<PlayerTrack> get tracks => _tracks;
  late List<PlayerTrack> _tracks;
  @override
  Stream<PlayerEvent> get events => _events.stream;
  @override
  DisplayMatchingReport get displayReport =>
      const DisplayMatchingReport.initial();
  final _displayReports = StreamController<DisplayMatchingReport>.broadcast();
  @override
  Stream<DisplayMatchingReport> get displayReports => _displayReports.stream;
  void emitDisplay(DisplayMatchingReport report) => _displayReports.add(report);
  @override
  bool fullscreen = false;
  @override
  PlayerCapabilities capabilities = const PlayerCapabilities.unavailable();
  final _fullscreenChanges = StreamController<bool>.broadcast(sync: true);
  @override
  Stream<bool> get fullscreenChanges => _fullscreenChanges.stream;
  void emitFullscreen(bool observed) {
    fullscreen = observed;
    if (!_fullscreenChanges.isClosed) _fullscreenChanges.add(observed);
  }

  @override
  Future<void> initialize() async {}
  @override
  Future<void> load(
    Uri media, {
    String? plexToken,
    int? generation,
    bool startPaused = false,
    Duration? startPosition,
  }) async {
    loadCalls++;
    lastLoadGeneration = generation;
    if (failLoad) throw const PlayerUnavailable('synthetic load failure');
    if (blockLoad) {
      if (!loadStarted.isCompleted) loadStarted.complete();
      await _loadCompletion.future;
    }
    if (startPaused) {
      _events.add(
        PlayerEvent(
          status: const PlayerStatus(
            state: PlayerState.paused,
            message: 'Paused',
          ),
          position: position,
          duration: duration,
          telemetry: telemetry,
          tracks: tracks,
          generation: generation,
        ),
      );
    }
  }

  @override
  Future<void> setDisplayMatching(DisplayMatchingRequest request) async {}

  void completeLoad() {
    if (!_loadCompletion.isCompleted) _loadCompletion.complete();
  }

  @override
  Future<void> play() async {
    transportCommands++;
    pausedValues.add(false);
    if (emitControlEvents) emitState(PlayerState.playing);
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
    pausedValues.add(true);
    if (emitControlEvents) emitState(PlayerState.paused);
    if (failControls) {
      throw const PlayerUnavailable(
        'Synthetic pause failure.',
        failureCode: 'command_error',
      );
    }
  }

  @override
  Future<void> seek(Duration position, {SeekMode mode = SeekMode.exact}) async {
    transportCommands++;
  }

  final videoRects = <PlayerVideoRect>[];
  @override
  Future<void> setVideoRect(PlayerVideoRect rect) async {
    videoRects.add(rect);
  }

  @override
  Future<void> setFullscreen(bool fullscreen) async {
    fullscreenValues.add(fullscreen);
    emitFullscreen(fullscreen);
  }

  @override
  Future<void> selectTrack(PlayerTrackType type, int? id) async {
    selectedTracks.add((type, id));
    if (failTrackSelect) throw StateError('synthetic track failure');
  }

  void emitTracks(List<PlayerTrack> tracks) {
    _tracks = List.unmodifiable(tracks);
    _events.add(
      PlayerEvent(
        status: status,
        position: position,
        duration: duration,
        telemetry: telemetry,
        tracks: _tracks,
        generation: lastLoadGeneration,
      ),
    );
  }

  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> stop() async {
    if (failStop) throw const PlayerUnavailable('Synthetic stop failure.');
  }

  @override
  Future<void> dispose() async {
    await _events.close();
    await _displayReports.close();
    await _fullscreenChanges.close();
  }
}

Rect _drawnRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

Size _drawnSize(WidgetTester tester, Finder finder) =>
    _drawnRect(tester, finder).size;

/// An excluded origin can still have a local node. Walk from the view's root
/// through Flutter's accessibility traversal to prove the overlay is reachable.
Future<void> _showReachableTooltip(WidgetTester tester, String message) async {
  expect(
    tester.semantics.simulatedAccessibilityTraversal().where(
      (node) => node.label == message,
    ),
    isEmpty,
  );
  final tooltip = find.byWidgetPredicate(
    (widget) => widget is Tooltip && widget.message == message,
  );
  expect(tooltip, findsOneWidget);
  expect(tester.state<TooltipState>(tooltip).ensureTooltipVisible(), isTrue);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  final overlay = tester.semantics.simulatedAccessibilityTraversal().where(
    (node) => node.label == message,
  );
  expect(overlay, hasLength(1));
  expect(
    overlay.single.getSemanticsData().hasAction(SemanticsAction.tap),
    isFalse,
  );
}

Future<void> _r2Capture(WidgetTester tester, GlobalKey key, String name) async {
  final directory = Platform.environment['R2_CAPTURE'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

_Fixture _amendmentFixture({
  bool dvr = false,
  int channels = 1,
  DateTime Function()? now,
  bool short = false,
}) {
  final clock = now ?? () => DateTime(2026, 1, 15, 12);
  return _Fixture(
    PlayerState.playing,
    dvrControlsEnabled: dvr,
    channelCount: channels,
    guideClock: clock,
    playerClock: clock,
    shortPrograms: short,
    richItemOverride: _fixtureItem(
      0,
      rich: true,
      duration: Duration(hours: short ? 1 : 24),
      summary: List.filled(
        30,
        'Complete program details for reading.',
      ).join(' '),
      cast: List.generate(
        24,
        (i) => ChannelCastMember(name: 'Performer $i', role: 'Role $i'),
      ),
    ),
  );
}

Future<void> _openInfoForAmendment(
  WidgetTester tester,
  _Fixture fixture,
) async {
  await fixture.player.tune('channel');
  fixture.player.showNowPlaying();
  await tester.pumpWidget(
    MaterialApp(
      theme: LineupTheme.forName(
        LineupThemeName.emberSteel,
        formFactor: profileFor(true).formFactor,
      ),
      builder: _playerTvCanvasBuilder,
      home: PlayerView(controller: fixture.player, openGuide: () {}),
    ),
  );
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.select);
  await tester.pumpAndSettle();
}

Future<void> _expectInfoPaint(
  WidgetTester tester,
  GlobalKey captureKey,
  Finder reader, {
  required bool focused,
  required String name,
}) async {
  final rect = tester.getRect(reader);
  final box = tester.renderObject<RenderBox>(reader);
  final scale = rect.width / box.size.width;
  final sampleY = (rect.top + 20).floor();
  final pixels = (await tester.runAsync(() async {
    final image =
        await (captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
    List<int> sample(double x) {
      final offset = (sampleY * image.width + x.floor()) * 4;
      return data.sublist(offset, offset + 4);
    }

    final values = {
      'bar': sample(rect.left + 2 * scale),
      'body': sample(rect.left + 12 * scale),
      'thumb': sample(rect.right - 2 * scale),
    };
    image.dispose();
    final directory = Platform.environment['R2_CAPTURE'];
    if (directory != null) {
      await File('$directory/$name.json').writeAsString(
        jsonEncode({
          'focused': focused,
          'scale': scale,
          'reader': [rect.left, rect.top, rect.right, rect.bottom],
          'sample_y': sampleY,
          'rgba': values,
        }),
      );
    }
    return values;
  }))!;
  expect(pixels['bar'], focused ? [233, 220, 195, 255] : [43, 38, 30, 255]);
  expect(pixels['body']!.take(3).reduce((a, b) => a + b), lessThan(100));
  if (focused) {
    expect(pixels['thumb'], [233, 220, 195, 255]);
  } else {
    expect(pixels['thumb'], isNot([233, 220, 195, 255]));
    expect(
      pixels['thumb']!.take(3).reduce((a, b) => a + b),
      greaterThan(pixels['body']!.take(3).reduce((a, b) => a + b)),
    );
  }
}

double _channelTagOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find
          .ancestor(
            of: find.byKey(const Key('player-osd-channel-bug')),
            matching: find.byType(Opacity),
          )
          .first,
    )
    .opacity;

Future<void> _captureChannelTag(
  WidgetTester tester,
  GlobalKey key,
  String name, {
  bool tv = false,
}) async {
  final directory = Platform.environment['CHANNEL_TAG_CAPTURE'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: tv ? 2 : 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
