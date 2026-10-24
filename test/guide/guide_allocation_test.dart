import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/guide/guide_playback_placeholder.dart';
import 'package:lineup_desktop/guide/guide_view.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';

import '../support/golden_test_support.dart';
import '../support/ui_fixture.dart';

void main() {
  _stabilityTests();
  for (final configuration in [
    for (final scale in [1.0, 1.15, 1.3])
      for (final large in [false, true])
        for (final variant in [
          'normal',
          'library',
          'logo',
          'logo-fallback',
          'facts',
          'message',
          'no-synopsis',
          'wide',
          'logo-wide',
          'wide-no-synopsis',
        ])
          (
            name: 'tv-$variant-$scale-large$large',
            tv: true,
            scale: scale,
            large: large,
            dpr: 2.0,
            theme: LineupThemeName.emberSteel,
          ),
    for (final scale in [1.0, 1.15, 1.3])
      (
        name: 'desktop-$scale',
        tv: false,
        scale: scale,
        large: false,
        dpr: 1.0,
        theme: LineupThemeName.emberSteel,
      ),
    for (final theme in LineupThemeName.values.skip(1))
      (
        name: 'tv-theme-${theme.name}',
        tv: true,
        scale: 1.3,
        large: true,
        dpr: 2.0,
        theme: theme,
      ),
  ]) {
    final scale = configuration.scale;
    final large = configuration.large;
    for (final rich in [false, true]) {
      testWidgets('Guide allocation ${configuration.name} rich=$rich', (
        tester,
      ) async {
        await tester.runAsync(loadPinnedTestFonts);
        tester.view
          ..physicalSize = const Size(1920, 1080)
          ..devicePixelRatio = configuration.dpr;
        final now = DateTime(2026, 10, 24, 6, 40);
        final library = configuration.name.contains('library');
        final logo = configuration.name.contains('logo');
        final longFacts = configuration.name.contains('facts');
        final wide = configuration.name.contains('wide');
        final message = configuration.name.contains('message')
            ? 'Playback unavailable — choose another channel or try again.'
            : null;
        ChannelItem item(int i) => ChannelItem(
          id: 'program-$i',
          title: rich ? 'The Last Frequency' : 'Synthetic program ${i + 1}',
          showTitle: rich ? 'Signal House' : null,
          seasonNumber: rich ? 12 : null,
          episodeNumber: rich ? 5 : null,
          duration: const Duration(hours: 2),
          summary: rich && !configuration.name.contains('no-synopsis')
              ? 'A signal reaches the crew. They follow its source across the city.'
              : null,
          year: rich ? 2026 : null,
          genres: rich
              ? (longFacts
                    ? const [
                        'Science Fiction',
                        'Historical Documentary',
                        'International Drama',
                      ]
                    : const ['Drama', 'Science Fiction'])
              : const [],
          contentRating: rich ? (wide ? 'TV-Y7-FV' : 'TV-14') : null,
          resolution: rich ? (wide ? '1080p' : '4k') : null,
          audioCodec: rich ? (wide ? 'dts-hd' : 'eac3') : null,
          audioChannels: rich && (longFacts || wide) ? (wide ? 2 : 8) : null,
          dynamicRange: rich && (longFacts || wide) ? 'dolbyVision' : null,
          clearLogo: logo ? Uri.parse('/clear-logo') : null,
        );
        final channels = List.generate(
          40,
          (i) => Channel(
            id: 'channel-$i',
            number: i + 1,
            name: 'Synthetic channel ${i + 1}',
            source: library
                ? const LibrarySource(
                    libraryId: 'library',
                    libraryType: PlexLibraryType.movie,
                  )
                : ManualSource([item(i)]),
            playbackMode: PlaybackMode.sequential,
            anchor: DateTime(2026, 10, 24, 6),
            shuffleSeed: i,
          ),
        );
        final lineup = _GuideArtworkController(
          logo: !logo
              ? null
              : base64Decode(
                  configuration.name.contains('fallback')
                      ? 'iVBORw0KGgoAAAANSUhEUgAAABQAAASwCAAAAADeIDU6AAAAWElEQVR4nO3IMQEAAAwCIPuX1gILsANO0kOklFJKKaWUUkoppZRSSimllFJKKaWUUkoppZRSSimllFJKKaWUUkoppZRSSimllFJKKaWUUkoppZRSSinl1xx/t2e0Ivf9MAAAAABJRU5ErkJggg=='
                      : 'iVBORw0KGgoAAAANSUhEUgAAAAMAAAABCAAAAAA+i0toAAAADElEQVR4nGP4//8/AAX+Av4N70a4AAAAAElFTkSuQmCC',
                ),
          scenario: LineupScenario(
            stage: SetupStage.ready,
            channels: channels,
            libraries: library
                ? const [
                    PlexLibrary(
                      id: 'library',
                      title: 'Synthetic documentary and historical television collections',
                      type: PlexLibraryType.movie,
                    ),
                  ]
                : const [],
            settings: LineupSettings(
              largeFocusIndicators: large,
              preferClearLogos: logo,
            ),
          ),
        );
        final guide = GuideController(
          lineup: lineup,
          clock: () => now,
          loadSchedule: (c) async => buildSchedule(
            [item(int.parse(c.id.split('-').last))],
            mode: c.playbackMode,
            seed: c.shuffleSeed,
          ),
        );
        final capture = GlobalKey();
        try {
          await tester.pumpWidget(
            RepaintBoundary(
              key: capture,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: LineupTheme.forName(
                  configuration.theme,
                  androidTv: configuration.tv,
                  largeFocusIndicators: large,
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: LineupCanvas(child: child!),
                ),
                home: SafeArea(
                  child: GuideView(
                    controller: guide,
                    playbackMessage: message,
                    pictureInPicture: const GuidePlaybackPlaceholder(
                      unavailable: false,
                      reduceMotion: true,
                    ),
                    onOpenMenu: (_, _) {},
                    onClose: (_, _) {},
                    onTune: (_) async {},
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.runAsync(
            () => precacheImage(
              const AssetImage('assets/branding/lineup-logo-mark.png'),
              tester.element(find.byType(GuideView)),
            ),
          );
          await tester.pumpAndSettle();
          if (library) {
            guide.setLibraryFilter('library');
            await tester.pumpAndSettle();
            final label = find.byKey(const Key('guide-active-library-label'));
            expect(label, findsOneWidget);
            expect(
              tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
              isFalse,
            );
          }
          if (logo) {
            await tester.runAsync(
              () => precacheImage(
                MemoryImage(lineup.logo!),
                tester.element(find.byType(GuideView)),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              find.byKey(
                Key(
                  configuration.name.contains('fallback')
                      ? 'guide-clear-logo-fallback'
                      : 'guide-clear-logo',
                ),
              ),
              findsOneWidget,
            );
          }
          final info = tester.getRect(
            find.byKey(const Key('guide-information-area')),
          );
          final list = find.byKey(const Key('guide-schedule-list'));
          final listRect = tester.getRect(list);
          final rowHeight = tester.widget<ListView>(list).itemExtent!;
          final infoBox = tester.renderObject<RenderBox>(
            find.byKey(const Key('guide-information-area')),
          );
          final canvasScale =
              (infoBox.localToGlobal(const Offset(1, 0)) -
                      infoBox.localToGlobal(Offset.zero))
                  .distance;
          final violations = <String>[];
          final fields = <String, Object?>{};
          for (final name in [
            'guide-info-channel',
            'guide-clear-logo-fallback',
            'guide-info-episode',
            'guide-program-meta',
            'guide-info-genres',
            'guide-program-badges',
            'guide-program-synopsis',
            'guide-playback-message',
          ]) {
            final finder = find.byKey(Key(name));
            if (finder.evaluate().isEmpty) continue;
            final rect = tester.getRect(finder);
            if (tester.widget(finder) is Text) {
              final paragraph = tester.renderObject<RenderParagraph>(finder);
              final painter = TextPainter(
                text: paragraph.text,
                textScaler: paragraph.textScaler,
                textDirection: paragraph.textDirection,
                maxLines: paragraph.maxLines,
                ellipsis: paragraph.overflow == TextOverflow.ellipsis
                    ? '…'
                    : null,
              )..layout(maxWidth: paragraph.size.width);
              if (paragraph.size.height + .1 < painter.height) {
                violations.add(
                  '$name glyph line clipped: ${paragraph.size.height} < ${painter.height}',
                );
              }
              painter.dispose();
            }
            var aperture = info;
            for (final scroll
                in find
                    .ancestor(
                      of: finder,
                      matching: find.byType(SingleChildScrollView),
                    )
                    .evaluate()) {
              aperture = aperture.intersect(
                tester.getRect(find.byElementPredicate((e) => e == scroll)),
              );
            }
            fields[name] = {
              'rect': _rect(rect),
              'aperture': _rect(aperture),
              if (tester.widget(finder) is Text)
                'fontSizeCu': (tester
                    .renderObject<RenderParagraph>(finder)
                    .text
                    .style
                    ?.fontSize),
              if (tester.widget(finder) is Text)
                'fontSizePhysicalPx':
                    (tester
                            .renderObject<RenderParagraph>(finder)
                            .text
                            .style
                            ?.fontSize ??
                        0) *
                    scale *
                    canvasScale *
                    configuration.dpr,
            };
            if (rect.top < aperture.top - .1 ||
                rect.bottom > aperture.bottom + .1) {
              violations.add('$name clipped: $rect outside $aperture');
            }
          }
          final badgeMeasurements = <Map<String, Object?>>[];
          var requiredBadgeWidth = 0.0;
          for (final badge
              in find
                  .descendant(
                    of: find.byKey(const Key('guide-program-badges')),
                    matching: find.byType(RichText),
                  )
                  .evaluate()) {
            final paragraph = badge.renderObject! as RenderParagraph;
            final natural = TextPainter(
              text: paragraph.text,
              textScaler: paragraph.textScaler,
              textDirection: paragraph.textDirection,
              maxLines: 1,
            )..layout();
            final painted = TextPainter(
              text: paragraph.text,
              textScaler: paragraph.textScaler,
              textDirection: paragraph.textDirection,
              maxLines: paragraph.maxLines,
              ellipsis: paragraph.overflow == TextOverflow.ellipsis
                  ? '…'
                  : null,
            )..layout(maxWidth: paragraph.size.width);
            final lineCount = painted.computeLineMetrics().length;
            if (configuration.tv && lineCount != 1) {
              violations.add(
                'Badge label wraps to $lineCount lines: ${paragraph.text.toPlainText()}',
              );
            }
            if (paragraph.didExceedMaxLines ||
                natural.width > paragraph.size.width + .1) {
              violations.add(
                'Badge label clipped: ${paragraph.text.toPlainText()} (${natural.width} > ${paragraph.size.width})',
              );
            }
            if (paragraph.size.height + .1 < painted.height) {
              violations.add(
                'Badge glyph height clipped: ${paragraph.text.toPlainText()}',
              );
            }
            requiredBadgeWidth += natural.width + 20;
            badgeMeasurements.add({
              'label': paragraph.text.toPlainText(),
              'lineCount': lineCount,
              'naturalWidthCu': natural.width,
              'paintedWidthCu': paragraph.size.width,
              'glyphHeightCu': painted.height,
              'paintedHeightCu': paragraph.size.height,
            });
            natural.dispose();
            painted.dispose();
          }
          if (badgeMeasurements.isNotEmpty) {
            requiredBadgeWidth += (badgeMeasurements.length - 1) * 6;
          }
          final identityWidth = tester
              .getSize(find.byKey(const Key('guide-program-identity')))
              .width;
          if (configuration.tv && requiredBadgeWidth > identityWidth + .1) {
            violations.add(
              'Badge schema requires $requiredBadgeWidth cu but identity has $identityWidth cu',
            );
          }
          final pip = tester.getRect(
            find.byKey(const Key('guide-picture-in-picture')),
          );
          final placeholder = tester.getRect(
            find.text('Choose a channel to watch'),
          );
          if (placeholder.top < pip.top - .1 ||
              placeholder.bottom > pip.bottom + .1) {
            violations.add('PiP text clipped: $placeholder outside $pip');
          }
          final completeRows =
              ((listRect.height + .1) / (rowHeight * canvasScale)).floor();
          if (completeRows < 5) {
            violations.add(
              'Fewer than five complete rows: list $listRect rowHeightCu $rowHeight',
            );
          }
          final controls = tester.getRect(
            find.byKey(const Key('guide-control-content')),
          );
          final controlRects = <String, Object?>{};
          for (final name in [
            'guide-library-picker',
            'guide-channel-search',
            'guide-earlier',
            'guide-now',
            'guide-later',
            'guide-hours',
          ]) {
            final rect = tester.getRect(find.byKey(Key(name)));
            controlRects[name] = _rect(rect);
            if (rect.left < controls.left - .1 ||
                rect.right > controls.right + .1 ||
                rect.top < controls.top - .1 ||
                rect.bottom > controls.bottom + .1) {
              violations.add('$name outside control row: $rect');
            }
          }
          final rowPaint = <Object?>[];
          for (var i = 0; i < 5; i++) {
            final top = listRect.top + i * rowHeight * canvasScale;
            final rect = Rect.fromLTWH(
              listRect.left,
              top,
              listRect.width,
              rowHeight * canvasScale,
            );
            rowPaint.add(_rect(rect));
          }
          final paragraphBounds = <String, Object?>{};
          for (final entry in {
            'controlParagraphs': find.byKey(const Key('guide-control-content')),
            'firstGridRowParagraphs': find.byKey(
              const ValueKey('guide-timeline-channel-0'),
            ),
          }.entries) {
            paragraphBounds[entry.key] = [
              for (final element
                  in find
                      .descendant(
                        of: entry.value,
                        matching: find.byType(RichText),
                      )
                      .evaluate())
                if (element.renderObject is RenderParagraph)
                  {
                    'text': (element.renderObject! as RenderParagraph).text
                        .toPlainText(),
                    'rect': _rect(
                      tester.getRect(
                        find.byElementPredicate((e) => e == element),
                      ),
                    ),
                    'fontSizeCu': (element.renderObject! as RenderParagraph)
                        .text
                        .style
                        ?.fontSize,
                    'lineHeight': (element.renderObject! as RenderParagraph)
                        .text
                        .style
                        ?.height,
                  },
            ];
          }
          for (var i = 0; i < 5; i++) {
            final timeline = find.byKey(ValueKey('guide-timeline-channel-$i'));
            final paragraphs = find.descendant(
              of: timeline,
              matching: find.byType(RichText),
            );
            if (!paragraphs.evaluate().any(
              (e) =>
                  (e.renderObject! as RenderParagraph).text.toPlainText() ==
                  '6:00 AM–8:00 AM',
            )) {
              violations.add(
                'Grid row ${i + 1} dropped its existing time line',
              );
            }
          }
          final observation = {
            'configuration': configuration.name,
            'physicalSize': [1920, 1080],
            'dpr': configuration.dpr,
            'windowSize': [1920 / configuration.dpr, 1080 / configuration.dpr],
            'canvasScale': canvasScale,
            'canvasSize': [
              1920 / configuration.dpr / canvasScale,
              1080 / configuration.dpr / canvasScale,
            ],
            'scale': scale,
            'large': large,
            'rich': rich,
            'information': _rect(info),
            'controls': _rect(controls),
            'controlRects': controlRects,
            'rowRects': rowPaint,
            'list': _rect(listRect),
            'rowHeightCu': rowHeight,
            'completeRows': completeRows,
            'fields': fields,
            'badgeMeasurements': badgeMeasurements,
            'identityWidthCu': identityWidth,
            'requiredBadgeWidthCu': requiredBadgeWidth,
            ...paragraphBounds,
            'pip': _rect(pip),
            'placeholder': _rect(placeholder),
            'violations': violations,
          };
          final dir = Platform.environment['GUIDE_ALLOCATION_CAPTURE'];
          if (dir != null) {
            await tester.runAsync(() async {
              await Directory(dir).create(recursive: true);
              final name = '${configuration.name}-rich$rich';
              await File('$dir/$name.json')
                  .writeAsString(jsonEncode(observation));
              final image =
                  await (capture.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: configuration.dpr);
              expect(image.width, 1920);
              expect(image.height, 1080);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File('$dir/$name.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          expect(
            violations,
            isEmpty,
            reason: 'Every field and five complete rows must fit at every supported scale',
          );
          if (configuration.scale == 1 &&
              rich &&
              !configuration.name.contains('no-synopsis')) {
            expect(
              tester
                  .widget<Text>(find.byKey(const Key('guide-program-synopsis')))
                  .maxLines,
              greaterThan(1),
            );
          }
          if (configuration.name == 'tv-normal-1.0-largefalse' && rich) {
            guide.focusProgram(guide.row('channel-1').programs.first);
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<Text>(find.byKey(const Key('guide-info-channel')))
                  .data,
              contains('2 • Synthetic channel 2'),
            );
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          guide.dispose();
          lineup.dispose();
          tester.view.reset();
        }
      });
    }
  }
}

List<double> _rect(Rect r) => [r.left, r.top, r.right, r.bottom];

class _GuideArtworkController extends FixtureController {
  _GuideArtworkController({required super.scenario, this.logo});
  final Uint8List? logo;
  @override
  Future<Uint8List?> artworkForPath(
    Uri path, {
    int? width,
    int? height,
  }) async => path.path == '/clear-logo' ? logo : null;
}

void _stabilityTests() {
  for (final scale in [1.0, 1.15, 1.3]) {
    for (final large in [false, true]) {
      testWidgets(
        'TV allocation stable through remote rich minimal empty logo oversized scale=$scale large=$large',
        (tester) async {
          await tester.runAsync(loadPinnedTestFonts);
          tester.view
            ..physicalSize = const Size(1920, 1080)
            ..devicePixelRatio = 2;
          addTearDown(tester.view.reset);
          final oversized = List.filled(160, 'X').join();
          final now = DateTime(2026, 10, 24, 6, 40);
          final logo = base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAMAAAABCAAAAAA+i0toAAAADElEQVR4nGP4//8/AAX+Av4N70a4AAAAAElFTkSuQmCC',
          );
          final channels = List.generate(
            10,
            (i) => Channel(
              id: 'c$i',
              number: i + 1,
              name: 'Synthetic channel $i',
              source: ManualSource(
                i == 2
                    ? []
                    : [
                        ChannelItem(
                          id: 'p$i',
                          title: 'Program $i',
                          duration: const Duration(hours: 2),
                          showTitle: i == 0 ? 'Signal House' : null,
                          summary: i == 0
                              ? 'A complete rich synthetic program description.'
                              : null,
                          year: i == 0 ? 2026 : null,
                          genres: i == 0 ? ['Drama', 'Science Fiction'] : [],
                          contentRating: i == 0
                              ? 'TV-Y7-FV'
                              : i == 4
                              ? oversized
                              : null,
                          resolution: i == 0 || i == 4 ? '1080p' : null,
                          dynamicRange: i == 0 || i == 4 ? 'dolbyVision' : null,
                          audioCodec: i == 0 || i == 4 ? 'dts-hd' : null,
                          audioChannels: i == 0 || i == 4 ? 2 : null,
                          clearLogo: i == 3 ? Uri.parse('/clear-logo') : null,
                        ),
                      ],
              ),
              playbackMode: PlaybackMode.sequential,
              anchor: DateTime(2026, 10, 24, 6),
              shuffleSeed: i,
            ),
          );
          final lineup = _GuideArtworkController(
            logo: logo,
            scenario: LineupScenario(
              stage: SetupStage.ready,
              channels: channels,
              settings: LineupSettings(
                preferClearLogos: true,
                largeFocusIndicators: large,
                reduceMotion: large,
              ),
            ),
          );
          final guide = GuideController(
            lineup: lineup,
            clock: () => now,
            loadSchedule: (channel) async => buildSchedule(
              (channel.source as ManualSource).items,
              mode: channel.playbackMode,
              seed: channel.shuffleSeed,
            ),
          );
          final semantics = tester.ensureSemantics();
          try {
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
                  child: LineupCanvas(child: child!),
                ),
                home: SafeArea(
                  child: GuideView(
                    controller: guide,
                    pictureInPicture: const GuidePlaybackPlaceholder(
                      unavailable: false,
                      reduceMotion: true,
                    ),
                    onClose: (_, _) {},
                    onTune: (_) async {},
                    onOpenMenu: (_, _) {},
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final list = find.byKey(const Key('guide-schedule-list'));
            final row = tester.widget<ListView>(list).itemExtent;
            final listRect = tester.getRect(list);
            final pipRect = tester.getRect(
              find.byKey(const Key('guide-picture-in-picture')),
            );
            for (var i = 1; i < 5; i++) {
              await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
              await tester.pumpAndSettle();
              expect(guide.focusedChannel?.id, 'c$i');
              expect(tester.widget<ListView>(list).itemExtent, row);
              expect(tester.getRect(list), listRect);
              expect(
                tester.getRect(
                  find.byKey(const Key('guide-picture-in-picture')),
                ),
                pipRect,
              );
              if (i == 2) {
                expect(find.text('Schedule unavailable'), findsWidgets);
              }
              if (i == 4) {
                expect(
                  find.bySemanticsLabel(RegExp(oversized)),
                  findsOneWidget,
                );
                var ellipsized = false;
                for (final element
                    in find
                        .descendant(
                          of: find.byKey(const Key('guide-program-badges')),
                          matching: find.byType(RichText),
                        )
                        .evaluate()) {
                  final paragraph = element.renderObject! as RenderParagraph;
                  final painter = TextPainter(
                    text: paragraph.text,
                    textScaler: paragraph.textScaler,
                    textDirection: paragraph.textDirection,
                    maxLines: paragraph.maxLines,
                    ellipsis: '…',
                  )..layout(maxWidth: paragraph.size.width);
                  expect(painter.computeLineMetrics(), hasLength(1));
                  expect(
                    paragraph.size.height,
                    greaterThanOrEqualTo(painter.height),
                  );
                  ellipsized |= paragraph.didExceedMaxLines;
                  painter.dispose();
                }
                expect(
                  ellipsized,
                  isTrue,
                  reason: 'Unbounded raw text stays in the bounded row while its full semantics remain',
                );
              }

              if (i == 3) {
                await tester.runAsync(
                  () => precacheImage(
                    MemoryImage(logo),
                    tester.element(find.byType(GuideView)),
                  ),
                );
                await tester.pumpAndSettle();
                expect(
                  find.byKey(const Key('guide-clear-logo')),
                  findsOneWidget,
                );
                expect(tester.getRect(list), listRect);
                expect(
                  tester.getRect(
                    find.byKey(const Key('guide-picture-in-picture')),
                  ),
                  pipRect,
                );
              }
            }
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            guide.dispose();
            lineup.dispose();
            semantics.dispose();
          }
        },
      );
    }
  }
}
