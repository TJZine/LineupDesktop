import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Tristate;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
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
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/native_video_surface.dart';
import 'package:lineup_desktop/playback/player_coordinator.dart';
import 'package:lineup_desktop/playback/player_view.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/app_ui.dart';

import '../support/golden_test_support.dart';

final _fixtureArtwork = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);
final _fixtureLogoArtwork = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAlgAAAB4AQMAAAAUmx6AAAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAADUExURfPo0u6COk8AAAAHdElNRQfqCQwOHSj8iqZhAAAAJXRFWHRkYXRlOmNyZWF0ZQAyMDI2LTA5LTEyVDE0OjI5OjQwKzAwOjAw3a1YngAAACV0RVh0ZGF0ZTptb2RpZnkAMjAyNi0wOS0xMlQxNDoyOTo0MCswMDowMKzw4CIAAAAodEVYdGRhdGU6dGltZXN0YW1wADIwMjYtMDktMTJUMTQ6Mjk6NDArMDA6MDD75cH9AAAAIElEQVRo3u3BMQEAAADCoPVPbQo/oAAAAAAAAAAAgJcBI6AAAZ0TDkkAAAAASUVORK5CYII=',
);
final _extremeWideArtwork = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAABLAAAAAUCAIAAAASgVNzAAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAAGYktHRAD/AP8A/6C9p5MAAAAHdElNRQfqCQQBEhHq/110AAAAJXRFWHRkYXRlOmNyZWF0ZQAyMDI2LTA5LTA0VDAxOjE4OjE3KzAwOjAwct2ViQAAACV0RVh0ZGF0ZTptb2RpZnkAMjAyNi0wOS0wNFQwMToxODoxNyswMDowMAOALTUAAAAodEVYdGRhdGU6dGltZXN0YW1wADIwMjYtMDktMDRUMDE6MTg6MTcrMDA6MDBUlQzqAAAAjUlEQVR42u3XMQEAIAzAMMC/5yFjRxMFfXtn5gAAANDztgMAAADYYQgBAACiDCEAAECUIQQAAIgyhAAAAFGGEAAAIMoQAgAARBlCAACAKEMIAAAQZQgBAACiDCEAAECUIQQAAIgyhAAAAFGGEAAAIMoQAgAARBlCAACAKEMIAAAQZQgBAACiDCEAAEDUB/B/AyWGhzYyAAAAAElFTkSuQmCC',
);

void main() {
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
          builder: LineupCanvas.builder,
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
            builder: LineupCanvas.builder,
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
        fixture.lineup.settings = fixture.lineup.settings.copyWith(
          overlayTransparency: level,
        );
        fixture.lineup.notifyListeners();
        await tester.pumpWidget(
          MaterialApp(
            theme: LineupTheme.forName(LineupThemeName.slatePine),
            builder: LineupCanvas.builder,
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
            builder: LineupCanvas.builder,
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
          fixture.lineup.settings = fixture.lineup.settings.copyWith(
            overlayTransparency: level,
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
            // A single shader joins the feather to flat material without
            // an uncovered pixel or two separately anti-aliased edges.
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
                child: LineupCanvas(child: child!),
              ),
              home: PlayerView(controller: fixture.player, openGuide: () {}),
            ),
          );
          await tester.pumpAndSettle();
          await _settleNowPlayingArtwork(tester);
          final logo = find.byKey(const Key('player-now-playing-logo'));
          expect(logo, findsOneWidget, reason: '$size text$textScale');
          final image = tester.widget<Image>(logo);
          expect(image.image, MemoryImage(bytes!));
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
              child: LineupCanvas(child: child!),
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
    final fixture = _Fixture(PlayerState.playing);
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    fixture.player.showOsd();
    await tester.pumpWidget(
      MaterialApp(
        theme: LineupTheme.forName(LineupThemeName.emberSteel),
        builder: LineupCanvas.builder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('player-osd-sleep')));
    await tester.pumpAndSettle();
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
    await tester.tap(find.text('30 minutes'));
    await tester.pumpAndSettle();
    expect(find.text('Sleep · 30m'), findsOneWidget);
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
          builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
    expect(fixture.player.overlay, PlayerOverlay.sleepTimer);
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
        builder: LineupCanvas.builder,
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
    await tester.pump();
    expect(fixture.player.overlay, PlayerOverlay.sleepTimer);
    await tester.tap(find.text('30 minutes'));
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
        builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
      MaterialApp(
        builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
          builder: LineupCanvas.builder,
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
          builder: LineupCanvas.builder,
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
          builder: LineupCanvas.builder,
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
          builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
            builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
          builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
          builder: LineupCanvas.builder,
          key: ValueKey(item.logo),
          home: PlayerView(controller: item.fixture.player, openGuide: () {}),
        ),
      );
      if (item.logo) {
        await tester.runAsync(
          () => precacheImage(
            MemoryImage(logoBytes),
            tester.element(find.byType(PlayerView)),
          ),
        );
      }
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
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
          builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
          builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
          child: LineupCanvas(child: child!),
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
      fixture.player.showOsd();
      await tester.pumpWidget(
        MaterialApp(
          builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
            builder: LineupCanvas.builder,
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
          // Enter traversal before activating the preset with the keyboard.
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          // The preset is a ListTile, so focus its nearest Focus descendant.
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
        fixture.lineup.stage = SetupStage.ready;
        await tester.pumpWidget(
          MaterialApp(
            builder: LineupCanvas.builder,
            home: LineupShell(
              player: fixture.native,
              controller: fixture.lineup,
              initialMediaPath: '/synthetic.mp4',
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
        builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();

    // A whitespace-only title falls back to the meaningful language, and the
    // detail drops the duplicated language instead of repeating it.
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Dolby Digital Plus'), findsOneWidget);
    expect(find.text('English • eac3'), findsNothing);
    // Fully blank metadata falls back to distinct readable type/ID labels
    // without inventing a redundant secondary fact.
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
    // A custom title keeps its trimmed text, resolved language, and friendly
    // codec detail.
    expect(find.text('English — Director commentary'), findsOneWidget);
    expect(find.text('AAC'), findsOneWidget);
    expect(find.text('   '), findsNothing);
    // Formatting and metadata display emit no native selection command.
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
        builder: LineupCanvas.builder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();

    expect(find.text('English — Original theatrical mix'), findsOneWidget);
    expect(find.text('Stereo • AAC'), findsOneWidget);
    expect(find.text('español (Latinoamérica)'), findsOneWidget);
    expect(find.text('5.1 surround • Dolby Digital Plus'), findsOneWidget);

    const selectedLabel =
        'Select Audio track: English — Original theatrical mix; Stereo; AAC.';
    const alternateLabel =
        'Select Audio track: español (Latinoamérica); 5.1 surround; '
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
          builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
          builder: LineupCanvas.builder,
          home: PlayerView(controller: fixture.player, openGuide: () {}),
        ),
      );
      await tester.pump();

      expect(find.text('日本語 — 監督コメンタリー 🎬'), findsOneWidget);
      expect(find.text('ASS (styled text)'), findsOneWidget);
      // language_code resolves the Klingon code to its self-name.
      expect(find.text('Klingon'), findsOneWidget);
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const Key('playback-track-subtitle-8')),
            )
            .subtitle,
        isNull,
      );
      // Subtitle Off stays a distinct first action.
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
        builder: LineupCanvas.builder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();

    // Rail and OSD agree the whitespace title is absent: the OSD uses the
    // language without forcing the rail's full type/ID label into the chip.
    expect(find.text('Audio • Deutsch'), findsOneWidget);
    expect(find.text('Subtitles • Off'), findsOneWidget);
    expect(fixture.native.selectedTracks, isEmpty);

    // The same tracks in the rail agree: language title, no repeated detail.
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
        builder: LineupCanvas.builder,
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
          builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
        home: PlayerView(controller: fixture.player, openGuide: () {}),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(fixture.native.selectedTracks, isEmpty);

    // Positive control: tapping a row still reaches the native selection.
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
          builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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

  testWidgets('mini Guide wheel changes selection without scrolling', (
    tester,
  ) async {
    final fixture = _Fixture(PlayerState.playing, channelCount: 7);
    await tester.binding.setSurfaceSize(const Size(800, 240));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    fixture.player.showMiniGuide();
    await tester.pumpWidget(
      MaterialApp(
        builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
          builder: LineupCanvas.builder,
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
          builder: LineupCanvas.builder,
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
            builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
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
          builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
          child: LineupCanvas(child: child!),
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
        builder: LineupCanvas.builder,
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
    fixture.lineup.settings = const LineupSettings(
      theme: LineupThemeName.directv,
    );
    fixture.player.showMiniGuide();
    await tester.pumpWidget(
      MaterialApp(
        builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
    expect(find.byType(Image), findsNWidgets(2));
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
    expect(find.text('H264'), findsOneWidget);
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
          builder: LineupCanvas.builder,
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
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    },
    semanticsEnabled: true,
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
        builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
          builder: LineupCanvas.builder,
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

      // Schedule fallback describes progress; it does not establish an
      // observed native seek duration or enable a native seek command.
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      expect(fixture.native.transportCommands, 0);
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
        builder: LineupCanvas.builder,
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
          builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
          builder: LineupCanvas.builder,
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
          builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
        builder: LineupCanvas.builder,
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
          builder: LineupCanvas.builder,
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
    // A 3:1 image remains usable in the compact shelf's title-artwork slot.
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
            builder: LineupCanvas.builder,
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
          builder: LineupCanvas.builder,
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
            builder: LineupCanvas.builder,
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
            child: LineupCanvas(child: child!),
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
      // Completed artwork under the canvas layout scope needs one build frame,
      // without advancing animation time.
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump();
      }
      expect(tester.hasRunningAnimations, isFalse);
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
          builder: LineupCanvas.builder,
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
          builder: LineupCanvas.builder,
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
    return artworkBytes ??
        (path.path.contains('/logo') ? _fixtureLogoArtwork : _fixtureArtwork);
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

  final bool failLoad;
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
  Future<void> initialize() async {}
  @override
  Future<void> load(Uri media, {String? plexToken, int? generation}) async {
    loadCalls++;
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
  Future<void> dispose() => _events.close();
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

Rect _drawnRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

Size _drawnSize(WidgetTester tester, Finder finder) =>
    _drawnRect(tester, finder).size;
