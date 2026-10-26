import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/guide/guide_view.dart';
import 'package:lineup_desktop/guide/guide_playback_placeholder.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/app_ui.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';

import '../support/golden_test_support.dart';
import '../support/ui_fixture.dart';

// Optional matched real-Flutter artifacts; no golden is written or approved.
void main() {
  for (final width in [900.0, 1200.0, 1920.0]) {
    for (final scale in [1.0, 1.15, 1.3]) {
      test('rail preserves name budget at width=$width scale=$scale', () {
        final before = GuideLayoutPolicy.forSize(
          Size(width, 1080),
          hasPicture: true,
          textScale: scale,
        );
        final after = GuideLayoutPolicy.forSize(
          Size(width, 1080),
          hasPicture: true,
          textScale: scale,
          numberColumnWidth: 74 * scale,
        );
        final previousNumber = before.channelRailWidth < 180 ? 40 : 48;
        expect(
          after.channelRailWidth - 74 * scale - 14 * scale,
          closeTo(before.channelRailWidth - previousNumber, .0001),
        );
      });
    }
  }
  for (final scale in [1.0, 1.15, 1.3]) {
    for (final large in [false, true]) {
      testWidgets(
        'TV constrained picture preserves placeholder minimum scale=$scale large=$large',
        (tester) async {
          await tester.runAsync(loadPinnedTestFonts);
          late Size minimum;
          await tester.pumpWidget(
            MaterialApp(
              theme: LineupTheme.forName(
                LineupThemeName.emberSteel,
                androidTv: true,
                largeFocusIndicators: large,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Builder(
                builder: (context) {
                  minimum = GuidePlaybackPlaceholder.minimumSize(context);
                  return const SizedBox();
                },
              ),
            ),
          );
          // At this width the identity/synopsis budget is smaller than Retry's
          // state-independent aperture; a zero floor allowed it to shrink below that minimum.
          final policy = GuideLayoutPolicy.forSize(
            const Size(1200, 1080),
            hasPicture: true,
            textScale: scale,
            tvControlsHeight: 56,
            tvIdentityWidth: 600,
            tvPictureMinimum: minimum,
          );
          expect(minimum.width, greaterThan(0));
          expect(policy.pictureWidth, minimum.width);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  final output = Platform.environment['GUIDE_CAPTURE'];
  final baseline = Platform.environment['GUIDE_BASELINE'] == '1';
  for (final tv in [true, false]) {
    for (final scale in [1.0, 1.15, 1.3]) {
      for (final large in [false, true]) {
        testWidgets('approved Guide tv=$tv scale=$scale large=$large', (
          tester,
        ) async {
          await tester.runAsync(loadPinnedTestFonts);
          final dpr = tv ? 2.0 : 1.0;
          tester.view
            ..physicalSize = const Size(1920, 1080)
            ..devicePixelRatio = dpr;
          addTearDown(tester.view.reset);
          const numbers = [1, 12, 123, 999, 1000];
          const names = [
            'Northern Lights Documentary Collection',
            'Supercalifragilisticexpialidocious Classics',
            'Space Exploration and Discovery',
            'Weekend Adventure Classics',
            'The Extraordinarily Long Saturday Morning Animation Marathon Channel',
          ];
          final channels = [
            for (var i = 0; i < numbers.length; i++)
              Channel(
                id: 'c$i',
                number: numbers[i],
                name: names[i],
                source: ManualSource([
                  ChannelItem(
                    id: 'p$i',
                    title: 'The Last Frequency',
                    showTitle: 'Signal House',
                    seasonNumber: 12,
                    episodeNumber: 5,
                    duration: const Duration(hours: 2),
                    summary: 'A signal reaches the crew. They follow its source across the city, uncovering a connection to a distant station.',
                    year: 2026,
                    genres: const ['Drama', 'Science Fiction'],
                    contentRating: 'TV-14',
                    resolution: '4k',
                    audioCodec: 'eac3',
                    audioChannels: 8,
                    dynamicRange: 'dolbyVision',
                  ),
                ]),
                playbackMode: PlaybackMode.sequential,
                anchor: DateTime(2026, 10, 25, 6),
                shuffleSeed: i,
              ),
          ];
          final lineup = FixtureController(
            scenario: LineupScenario(
              stage: SetupStage.ready,
              channels: channels,
              settings: LineupSettings(
                guideShowChannelSources: true,
                largeFocusIndicators: large,
                reduceMotion: true,
              ),
            ),
          );
          final guide = GuideController(
            lineup: lineup,
            clock: () => DateTime(2026, 10, 25, 6, 40),
            loadSchedule: (c) async => buildSchedule(
              (channels.firstWhere((channel) => channel.id == c.id).source
                      as ManualSource)
                  .items,
              mode: c.playbackMode,
              seed: c.shuffleSeed,
            ),
          );
          final theme = ValueNotifier(LineupThemeName.emberSteel);
          final textScaler = ValueNotifier<TextScaler>(
            TextScaler.linear(scale),
          );
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: ValueListenableBuilder<LineupThemeName>(
                valueListenable: theme,
                builder: (context, value, _) => MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: LineupTheme.forName(
                    value,
                    androidTv: tv,
                    largeFocusIndicators: large,
                  ),
                  builder: (context, child) =>
                      ValueListenableBuilder<TextScaler>(
                        valueListenable: textScaler,
                        builder: (context, value, _) => MediaQuery(
                          data: MediaQuery.of(context)
                              .copyWith(textScaler: value),
                          child: LineupCanvas(
                            reduceMotion: true,
                            child: child!,
                          ),
                        ),
                      ),
                  home: GuideView(
                    controller: guide,
                    watchingChannelId: 'c3',
                    pictureInPicture: const ColoredBox(
                      color: Color(0xff203747),
                      child: Center(child: Text('Synthetic picture proxy')),
                    ),
                    onOpenPlayer: () {},
                    onClose: (_, _) {},
                    onOpenMenu: (_, _) {},
                    onTune: (_) async {},
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          guide.selectProgram(guide.currentProgram('c0')!);
          guide.focusProgram(guide.currentProgram('c2')!);
          await tester.pumpAndSettle();
          List<double> rect(String key) {
            final r = tester.getRect(find.byKey(Key(key)));
            final box = tester.renderObject<RenderBox>(find.byKey(Key(key)));
            final factor =
                (box.localToGlobal(const Offset(1, 0)) -
                        box.localToGlobal(Offset.zero))
                    .distance;
            return [
              r.left / factor,
              r.top / factor,
              r.width / factor,
              r.height / factor,
            ];
          }

          int lines(String text) {
            final p = tester.renderObject<RenderParagraph>(
              find.text(text).first,
            );
            final painter = TextPainter(
              text: p.text,
              textDirection: p.textDirection,
              textScaler: p.textScaler,
              maxLines: p.maxLines,
              ellipsis: p.overflow == TextOverflow.ellipsis ? '…' : null,
            )..layout(maxWidth: p.size.width);
            final result = painter.computeLineMetrics().length;
            painter.dispose();
            return result;
          }

          final list = find.byKey(const Key('guide-schedule-list'));
          final metrics = <String, Object?>{
            'phase': baseline ? 'staged-baseline' : 'unit-candidate',
            'picture': rect('guide-picture-in-picture'),
            'information': rect('guide-information-area'),
            'identity': rect('guide-program-identity'),
            'synopsis': rect('guide-program-synopsis'),
            'numberColumnWidth': tester.getSize(find.text('1').first).width,
            'nameWidth': tester.getSize(find.text(names.first)).width,
            'railWidth': tester
                .getSize(
                  find
                      .ancestor(
                        of: find.text('1').first,
                        matching: find.byType(AnimatedContainer),
                      )
                      .first,
                )
                .width,
            'libraryPicker': rect('guide-library-picker'),
            'rows': tester.widget<ListView>(list).itemExtent,
            'list': rect('guide-schedule-list'),
            'numberLines': {for (final n in numbers) '$n': lines('$n')},
            'nameLines': {for (final n in names) n: lines(n)},
          };
          if (baseline) {
            if (scale == 1 && !large) {
              expect(lines('123'), greaterThan(1));
              expect(lines('1000'), greaterThan(1));
              if (tv) {
                expect(
                  (metrics['picture'] as List<double>)[2],
                  closeTo(416, 1),
                );
              }
            }
          } else {
            for (final n in numbers) {
              expect(lines('$n'), 1);
            }
            for (final n in names) {
              expect(lines(n), lessThanOrEqualTo(2));
            }
            expect(find.text('Watching'), findsOneWidget);
            expect(
              tester.getSize(list).height /
                  tester.widget<ListView>(list).itemExtent!,
              closeTo(5, .001),
            );
            if (tv) {
              expect(
                (metrics['picture'] as List<double>)[2],
                closeTo(576, .01),
              );
              expect(
                (metrics['picture'] as List<double>)[3],
                closeTo(324, .01),
              );
            }
          }
          final mountedGuide = tester.element(find.byType(GuideView));
          final focus = FocusManager.instance.primaryFocus;
          for (final name in LineupThemeName.values) {
            theme.value = name;
            await tester.pumpAndSettle();
            expect(tester.element(find.byType(GuideView)), same(mountedGuide));
            expect(FocusManager.instance.primaryFocus, same(focus));
            expect(rect('guide-picture-in-picture'), metrics['picture']);
            for (final railFocus in [false, if (tv && !baseline) true]) {
              if (railFocus) {
                guide.moveHorizontal(-1);
                await tester.pumpAndSettle();
                expect(guide.focusedProgram, isNull);
                expect(rect('guide-picture-in-picture'), metrics['picture']);
                final support = tester.renderObject<RenderParagraph>(
                  find.text('Manual lineup').at(2),
                );
                final roles = LineupTheme.forName(
                  name,
                  androidTv: true,
                ).extension<LineupThemeRoles>()!;
                expect(support.text.style!.color, roles.focusMutedText);
              }
              if (output != null) {
                final stem =
                    '$output/${tv ? 'tv' : 'desktop'}-$scale-large$large-${name.name}${railFocus ? '-rail' : ''}';
                File('$stem.json')
                  ..createSync(recursive: true)
                  ..writeAsStringSync(
                    const JsonEncoder.withIndent('  ').convert(metrics),
                  );
                await tester.runAsync(() async {
                  final image =
                      await (boundary.currentContext!.findRenderObject()!
                              as RenderRepaintBoundary)
                          .toImage(pixelRatio: dpr);
                  final data = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  File('$stem.png')
                      .writeAsBytesSync(data!.buffer.asUint8List());
                  image.dispose();
                });
              }
              if (railFocus) {
                guide.focusProgram(guide.currentProgram('c2')!);
                await tester.pumpAndSettle();
              }
            }
          }
          if (!baseline) {
            final numberWidth = tester.getSize(find.text('1').first).width;
            final nameWidth = tester.getSize(find.text(names.first)).width;
            if (tv) {
              guide.focusProgram(guide.currentProgram('c3')!);
              guide.moveHorizontal(-1);
              await tester.pumpAndSettle();
              final owner = FocusManager.instance.primaryFocus;
              for (final name in LineupThemeName.values) {
                theme.value = name;
                await tester.pumpAndSettle();
                expect(
                  tester.element(find.byType(GuideView)),
                  same(mountedGuide),
                );
                expect(FocusManager.instance.primaryFocus, same(owner));
                final watching = find.text('Watching');
                final roles = LineupTheme.of(tester.element(watching));
                expect(
                  tester.widget<Text>(watching).style!.color,
                  roles.focusSecondaryText,
                );
                expect(
                  tester
                      .widget<Icon>(find.byIcon(Icons.play_arrow_rounded))
                      .color,
                  roles.focusSecondaryText,
                );
                final rail = tester.widget<AnimatedContainer>(
                  find
                      .ancestor(
                        of: watching,
                        matching: find.byType(AnimatedContainer),
                      )
                      .first,
                );
                expect(
                  (rail.decoration! as BoxDecoration).color,
                  roles.focusedSurface,
                );
                expect(tester.getSize(find.text('1').first).width, numberWidth);
                expect(rect('guide-picture-in-picture'), metrics['picture']);
              }
              final header = tester.widget<LineupTopBar>(
                find.byType(LineupTopBar),
              );
              header.menuFocusNode!.requestFocus();
              await tester.pumpAndSettle();
              final headerOwner = FocusManager.instance.primaryFocus;
              final lockup = tester.element(find.text('LINEUP'));
              for (final name in LineupThemeName.values) {
                theme.value = name;
                await tester.pumpAndSettle();
                expect(FocusManager.instance.primaryFocus, same(headerOwner));
                expect(tester.element(find.text('LINEUP')), same(lockup));
                final roles = LineupTheme.forName(
                  name,
                  androidTv: true,
                  largeFocusIndicators: large,
                ).extension<LineupThemeRoles>()!;
                final scoped = LineupTheme.of(lockup);
                expect(scoped.primarySurface, roles.focusedInsetSurface);
                expect(scoped.primaryText, roles.onFocus);
                expect(scoped.secondaryText, roles.focusSecondaryText);
                expect(scoped.mutedText, roles.focusMutedText);
                final buttonFinder = find
                    .ancestor(
                      of: find.text('LINEUP'),
                      matching: find.byType(TextButton),
                    )
                    .first;
                final material = tester.widget<Material>(
                  find
                      .descendant(
                        of: buttonFinder,
                        matching: find.byType(Material),
                      )
                      .first,
                );
                expect(material.color, roles.focusedSurface);
                expect(
                  tester.widget<Text>(find.text('LINEUP')).style!.color,
                  roles.onFocus,
                );
                expect(
                  (material.shape! as OutlinedBorder).side,
                  large
                      ? BorderSide(color: roles.focusBorder, width: 3)
                      : BorderSide.none,
                );
              }
            }
            guide.setSearchQuery('Northern');
            await tester.pumpAndSettle();
            expect(
              tester.getSize(find.text('1').first).width,
              numberWidth,
              reason: 'Searching must keep the full-lineup column',
            );
            guide.setSearchQuery('');
            await tester.pumpAndSettle();
            await lineup.updateSettings(
              (settings) => settings.copyWith(guideShowChannelSources: false),
            );
            await tester.pumpAndSettle();
            expect(
              tester.getSize(find.text('1').first).width,
              numberWidth,
              reason: 'Hiding provenance must not change the column',
            );
            final original = channels.first;
            lineup.fixtureActor.replaceChannels([
              Channel(
                id: original.id,
                number: original.number,
                name: original.name,
                source: const LibrarySource(
                  libraryId: 'library',
                  libraryType: PlexLibraryType.show,
                ),
                playbackMode: original.playbackMode,
                anchor: original.anchor,
                shuffleSeed: original.shuffleSeed,
              ),
              ...channels.skip(1),
            ]);
            await tester.pumpAndSettle();
            guide.setLibraryFilter('library');
            await tester.pumpAndSettle();
            expect(guide.channels, hasLength(1));
            expect(
              tester.getSize(find.text('1').first).width,
              numberWidth,
              reason: 'Library filtering must retain the whole-lineup column',
            );
            guide.setLibraryFilter(null);
            await tester.pumpAndSettle();
            for (final maximum in [999, 1]) {
              await lineup.deleteChannels(
                expectedChannels: lineup.channels
                    .where((c) => c.number > maximum)
                    .toList(),
              );
              await tester.pumpAndSettle();
              final paragraph = tester.renderObject<RenderParagraph>(
                find.text('1').first,
              );
              final measure = TextPainter(
                text: TextSpan(
                  text: maximum < 100 ? '99' : '$maximum',
                  style: paragraph.text.style!.copyWith(fontSize: 28),
                ),
                textScaler: paragraph.textScaler,
                textDirection: paragraph.textDirection,
              )..layout();
              expect(
                paragraph.size.width,
                closeTo(measure.width.ceilToDouble(), .01),
                reason: 'Column follows lineup numbers with a two-digit floor',
              );
              measure.dispose();
              expect(
                tester.getSize(find.text(names.first)).width,
                closeTo(nameWidth, .01),
                reason: 'The name budget stays constant for lineups up to 99, 999 and 1000',
              );
            }
          }
          if (!baseline) {
            textScaler.value = const _NonlinearScaler();
            await tester.pumpAndSettle();
            final paragraph = tester.renderObject<RenderParagraph>(
              find.text('1').first,
            );
            final measure = TextPainter(
              text: TextSpan(
                text: '99',
                style: paragraph.text.style!.copyWith(fontSize: 28),
              ),
              textScaler: const _NonlinearScaler(),
              textDirection: paragraph.textDirection,
            )..layout();
            expect(
              paragraph.size.width,
              closeTo(measure.width.ceilToDouble(), .01),
              reason: 'Measure at 28 through the active nonlinear scaler, not scale(1)',
            );
            measure.dispose();
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          guide.dispose();
          lineup.dispose();
          theme.dispose();
          textScaler.dispose();
        });
      }
    }
  }
}

// A portable dependency check, separate from Android's real nonlinear font policy.
class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();

  @override
  double scale(double fontSize) =>
      fontSize * (1 + .3 * fontSize.clamp(0, 28) / 28);

  @override
  double get textScaleFactor => 1.3;
}
