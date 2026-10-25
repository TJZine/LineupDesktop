import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/app_ui.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';

import 'package:lineup_desktop/settings/lineup_settings.dart';

import '../support/ui_fixture.dart';
import '../support/golden_test_support.dart';

Color? ink(WidgetTester tester, Finder text) => tester
    .widget<RichText>(
      find.descendant(of: text, matching: find.byType(RichText)),
    )
    .text
    .style
    ?.color;

void main() {
  for (final tv in [false, true]) {
    for (final size
        in tv
            ? [const Size(960, 540)]
            : [const Size(1280, 720), const Size(1920, 1080)]) {
      testWidgets('R2 matched production surfaces TV=$tv size=$size', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = tv
            ? TargetPlatform.android
            : TargetPlatform.macOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await tester.runAsync(loadPinnedTestFonts);
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final fixture = UiFixture(
          androidTv: tv,
          guideClock: () => DateTime(2026, 1, 15, 12),
          scenario: const LineupScenario(stage: SetupStage.ready),
        );
        final captureKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(key: captureKey, child: fixture.build()),
        );
        await tester.pumpAndSettle();
        for (final route in ['Guide', 'Settings', 'Channels']) {
          if (route != 'Guide') await openDestination(tester, route);
          await captureR2(
            tester,
            captureKey,
            'matched-$tv-${size.width.toInt()}-$route',
          );
          if (tv && route == 'Settings') {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            await tester.pumpAndSettle();
            for (final large in [false, true]) {
              await fixture.controller.updateSettings(
                (s) => s.copyWith(largeFocusIndicators: large),
              );
              await tester.pumpAndSettle();
              await captureR2(
                tester,
                captureKey,
                'settings-focused-large$large',
              );
            }
            await fixture.controller.updateSettings(
              (s) => s.copyWith(largeFocusIndicators: false),
            );
            await tester.pumpAndSettle();
          }
        }
        await openDestination(tester, 'Settings');
        await tester.tap(find.text('Support').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Open Licenses'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open Licenses'));
        await tester.pumpAndSettle();
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 40)),
          );
          await tester.pumpAndSettle();
        }
        expect(
          find.byKey(const Key('licenses-reading-surface')),
          findsOneWidget,
        );
        await captureR2(
          tester,
          captureKey,
          'matched-$tv-${size.width.toInt()}-Licenses',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.controller.dispose();
        for (final stage in [SetupStage.profiles, SetupStage.channelSetup]) {
          final onboarding = UiFixture(
            androidTv: tv,
            scenario: LineupScenario(
              stage: stage,
              profile: const PlexHomeUser(
                id: 'viewer-0',
                name: 'Viewer 0',
                protected: false,
              ),
              profiles: List.generate(
                12,
                (i) => PlexHomeUser(
                  id: 'viewer-$i',
                  name: 'Viewer $i',
                  protected: i > 0,
                ),
              ),
              libraries: const [
                PlexLibrary(
                  id: 'movies',
                  title: 'Movies',
                  type: PlexLibraryType.movie,
                ),
              ],
              selectedLibraryIds: const {'movies'},
              channelSetupCanCancel: true,
            ),
          );
          await tester.pumpWidget(
            RepaintBoundary(key: captureKey, child: onboarding.build()),
          );
          await tester.pumpAndSettle();
          await captureR2(
            tester,
            captureKey,
            'matched-$tv-${size.width.toInt()}-${stage.name}',
          );
          await tester.pumpWidget(const SizedBox.shrink());
          onboarding.controller.dispose();
        }
        debugDefaultTargetPlatformOverride = null;
      }, skip: Platform.environment['R2_CAPTURE'] == null);
    }
  }

  for (final accountOrigin in [false, true]) {
    for (final back in [false, true]) {
      testWidgets(
        'L1 TV PIN ${back ? 'Back' : 'Cancel'} restores and reveals invoking profile account=$accountOrigin',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(960, 540));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final profiles = List.generate(
            12,
            (i) => PlexHomeUser(
              id: 'viewer-$i',
              name: 'Viewer $i',
              protected: true,
            ),
          );
          final fixture = UiFixture(
            androidTv: true,
            scenario: LineupScenario(
              stage: SetupStage.profiles,
              profiles: profiles,
              profile: profiles.first,
              profileSelectionOrigin: accountOrigin ? SetupStage.ready : null,
            ),
          );
          await tester.pumpWidget(fixture.build());
          await tester.pumpAndSettle();
          final card = find.byKey(const ValueKey('profile-card-viewer-10'));
          final button = find.descendant(
            of: card,
            matching: find.byType(TextButton),
          );
          final node = tester.widget<TextButton>(button).focusNode!;
          node.requestFocus();
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('profile-pin-sheet')), findsOneWidget);
          if (back) {
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          } else {
            final cancel = find.widgetWithText(TextButton, 'Cancel');
            Focus.of(
              tester.element(
                find.descendant(of: cancel, matching: find.text('Cancel')),
              ),
            ).requestFocus();
            await tester.pumpAndSettle();
            await tester.sendKeyEvent(LogicalKeyboardKey.select);
          }
          await tester.pumpAndSettle();
          expect(
            Focus.of(tester.element(find.text('Viewer 10'))).hasFocus,
            isTrue,
          );
          final rect = tester.getRect(card);
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(540));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          fixture.controller.dispose();
        },
      );
    }
  }
  for (final theme in LineupThemeName.values) {
    testWidgets('C1 full bleed route paint $theme', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.runAsync(loadPinnedTestFonts);
      await tester.binding.setSurfaceSize(const Size(960, 540));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = UiFixture(
        guideClock: () => DateTime(2026, 1, 15, 12),
        androidTv: true,
        scenario: LineupScenario(
          stage: SetupStage.ready,
          settings: LineupSettings(theme: theme),
        ),
      );
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: captureKey, child: fixture.build()),
      );
      await tester.pumpAndSettle();
      for (final route in [
        'Guide',
        'Settings',
        'Channels',
        'Diagnostics',
        'Licenses',
      ]) {
        if (route == 'Diagnostics' || route == 'Licenses') {
          await openDestination(tester, 'Settings');
          await tester.tap(find.text('Support').last);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Open $route'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Open $route'));
        } else if (route != 'Guide') {
          await openDestination(tester, route);
        }
        await tester.pumpAndSettle();
        if (route == 'Guide') {
          expect(
            tester
                .getRect(find.byKey(const Key('guide-info-dynamic-background')))
                .right,
            closeTo(960, .1),
          );
          final picture = find.byKey(const Key('guide-picture-in-picture'));
          if (picture.evaluate().isNotEmpty) {
            expect(
              tester
                  .getRect(
                    find.byKey(const Key('guide-info-dynamic-background')),
                  )
                  .left,
              greaterThanOrEqualTo(tester.getRect(picture).right),
            );
          }
        }
        if (route == 'Licenses') {
          expect(
            find.byKey(const Key('licenses-reading-surface')),
            findsOneWidget,
          );
        }
        final data = await captureR2(
          tester,
          captureKey,
          '${theme.name}-$route',
        );
        final rgba = data.buffer.asUint8List();
        for (final point in [
          const Offset(4, 4),
          const Offset(955, 4),
          const Offset(4, 535),
          const Offset(955, 535),
        ]) {
          final at = (point.dy.toInt() * 960 + point.dx.toInt()) * 4;
          expect(
            rgba[at] + rgba[at + 1] + rgba[at + 2],
            greaterThan(0),
            reason: '$route $point',
          );
          expect(rgba[at + 3], greaterThan(230), reason: '$route $point alpha');
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.controller.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('C4 header button has compact TV padding', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: LineupTheme.forName(LineupThemeName.emberSteel, androidTv: true),
        builder: LineupCanvas.builder,
        home: Scaffold(
          body: LineupTopBar(onOpenMenu: (_, _) {}, menuFocusNode: node),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.byType(TextButton);
    final logo = find.byType(Image);
    final scale = LineupCanvas.scaleFor(
      tester.view.physicalSize / tester.view.devicePixelRatio,
      androidTv: true,
    );
    expect(
      tester.getTopLeft(logo).dx - tester.getTopLeft(button).dx,
      closeTo(20 * scale, .1),
    );
  });

  testWidgets('C2 cold profile focus paints scoped badge ink and scale', (
    tester,
  ) async {
    const user = PlexHomeUser(id: 'owner', name: 'Owner', protected: false);
    final fixture = UiFixture(
      androidTv: true,
      scenario: const LineupScenario(
        stage: SetupStage.profiles,
        profile: user,
        profiles: [user],
      ),
    );
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    expect(ink(tester, find.text('Current')), const Color(0xFF090806));
    final card = find.byKey(const ValueKey('profile-card-owner'));
    expect(
      tester
          .widget<AnimatedScale>(
            find.descendant(of: card, matching: find.byType(AnimatedScale)),
          )
          .scale,
      1.06,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.controller.dispose();
  });

  for (final reduceMotion in [false, true]) {
    testWidgets(
      'C3 whole row and Large frame reveal keeps owner ReduceMotion=$reduceMotion',
      (tester) async {
        final nodes = List.generate(12, (_) => FocusNode());
        addTearDown(() {
          for (final node in nodes) {
            node.dispose();
          }
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: LineupTheme.forName(
              LineupThemeName.emberSteel,
              androidTv: true,
              largeFocusIndicators: true,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: reduceMotion),
              child: LineupCanvas(child: child!),
            ),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 500,
                  height: 300,
                  child: SingleChildScrollView(
                    key: const Key('viewport'),
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      children: [
                        for (var i = 0; i < nodes.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: LineupRowSurface(
                              key: ValueKey('row-$i'),
                              selected: false,
                              scaleOnFocus: true,
                              child: SizedBox(
                                height: 180,
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: TextButton(
                                    focusNode: nodes[i],
                                    onPressed: () {},
                                    child: Text('Row $i'),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        for (final i in [8, 3, 11, 0]) {
          nodes[i].requestFocus();
          if (reduceMotion) {
            await tester.pump();
            await tester.pump();
          } else {
            await tester.pumpAndSettle();
          }
          expect(FocusManager.instance.primaryFocus, same(nodes[i]));
          final row = tester.getRect(find.byKey(ValueKey('row-$i')));
          final viewport = tester.getRect(find.byKey(const Key('viewport')));
          final overflow = (reduceMotion ? 0 : 180 * .03) + 6;
          final scale = LineupCanvas.scaleFor(
            tester.view.physicalSize / tester.view.devicePixelRatio,
            androidTv: true,
          );
          expect(
            row.top - overflow * scale,
            greaterThanOrEqualTo(viewport.top - .1),
          );
          expect(
            row.bottom + overflow * scale,
            lessThanOrEqualTo(viewport.bottom + .1),
          );
        }
      },
    );
  }
  testWidgets(
    'O3 Settings labels have 16cu padding in normal and Large modes',
    (tester) async {
      final fixture = UiFixture(
        androidTv: true,
        scenario: const LineupScenario(stage: SetupStage.ready),
      );
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      await openDestination(tester, 'Settings');
      for (final large in [false, true]) {
        await fixture.controller.updateSettings(
          (s) => s.copyWith(largeFocusIndicators: large),
        );
        await tester.pumpAndSettle();
        for (final label in ['Use title artwork', 'Theme']) {
          final title = find.text(label).last;
          final surface = find
              .ancestor(of: title, matching: find.byType(LineupRowSurface))
              .first;
          final scale = LineupCanvas.scaleFor(
            tester.view.physicalSize / tester.view.devicePixelRatio,
            androidTv: true,
          );
          expect(
            tester.getTopLeft(title).dx - tester.getTopLeft(surface).dx,
            closeTo(19 * scale, .1),
          ); // 3cu selection rail + 16cu padding
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.controller.dispose();
    },
  );
}

Future<ByteData> captureR2(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  return (await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final directory = Platform.environment['R2_CAPTURE'];
    if (directory != null) {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File('$directory/$name.png')
          .writeAsBytes(png!.buffer.asUint8List());
    }
    image.dispose();
    return raw!;
  }))!;
}
