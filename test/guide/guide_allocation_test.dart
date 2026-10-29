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
            state: 'idle',
          ),
    for (final scale in [1.0, 1.15, 1.3])
      (
        name: 'desktop-$scale',
        tv: false,
        scale: scale,
        large: false,
        dpr: 1.0,
        theme: LineupThemeName.emberSteel,
        state: 'idle',
      ),
    for (final theme in LineupThemeName.values.skip(1))
      (
        name: 'tv-theme-${theme.name}',
        tv: true,
        scale: 1.3,
        large: true,
        dpr: 2.0,
        theme: theme,
        state: 'idle',
      ),
    for (final scale in [1.0, 1.15, 1.3])
      for (final large in [false, true])
        for (final variant in ['normal', 'logo-wide', 'wide-no-synopsis'])
          (
            name: 'tv-$variant-$scale-large$large-unavailable',
            tv: true,
            scale: scale,
            large: large,
            dpr: 2.0,
            theme: LineupThemeName.emberSteel,
            state: 'unavailable',
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
        var retryCalls = 0;
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
                    pictureInPicture: _pictureForState(
                      configuration.state,
                      () => retryCalls++,
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
            await _awaitLogoArtwork(
              tester,
              fallback: configuration.name.contains('fallback'),
            );
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
          final placeholderFields = <Map<String, Object?>>[];
          final required = configuration.state == 'playing'
              ? [find.byKey(const Key('playing-proxy'))]
              : [
                  find.text(
                    configuration.state == 'unavailable'
                        ? 'Playback unavailable'
                        : 'Choose a channel to watch',
                  ),
                  if (configuration.state == 'unavailable') ...[
                    find.text(_playbackError),
                    find.widgetWithText(TextButton, 'Retry'),
                  ],
                ];
          final placeholder = tester.getRect(required.first);
          for (final field in required) {
            final rect = tester.getRect(field);
            var frame = rect;
            if (tester.widget(field) is TextButton && large) {
              frame = rect.inflate(6 * canvasScale);
            }
            if (frame.top < pip.top - .1 ||
                frame.bottom > pip.bottom + .1 ||
                (configuration.tv &&
                    (frame.left < pip.left - .1 ||
                        frame.right > pip.right + .1))) {
              violations.add(
                'Complete placeholder/control/frame clipped: $frame outside $pip',
              );
            }
            if (tester.widget(field) is Text) {
              final paragraph = tester.renderObject<RenderParagraph>(field);
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
                violations.add('Placeholder glyph line clipped');
              }
              if (configuration.state == 'unavailable' &&
                  tester.widget<Text>(field).data == _playbackError) {
                expect(painter.computeLineMetrics(), hasLength(3));
              }
              placeholderFields.add({
                'text': paragraph.text.toPlainText(),
                'rect': _rect(rect),
                'fontSizeCu': paragraph.text.style?.fontSize,
                'lines': painter.computeLineMetrics().length,
                'glyphHeightCu': painter.height,
                'paintedHeightCu': paragraph.size.height,
              });
              painter.dispose();
            } else {
              placeholderFields.add({
                'control': 'Retry',
                'rect': _rect(rect),
                'frame': _rect(frame),
              });
            }
          }
          final placeholderScrolls = <double>[];
          for (final element
              in find
                  .descendant(
                    of: find.byType(GuidePlaybackPlaceholder),
                    matching: find.byType(Scrollable),
                  )
                  .evaluate()) {
            final state = tester.state<ScrollableState>(
              find.byElementPredicate((e) => e == element),
            );
            placeholderScrolls.add(state.position.maxScrollExtent);
            if (configuration.tv && state.position.maxScrollExtent > .1) {
              violations.add(
                'Placeholder has hidden scroll extent ${state.position.maxScrollExtent}',
              );
            }
          }
          expect(pip.width / pip.height, closeTo(16 / 9, .000001));
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
            'pictureState': configuration.state,
            'placeholderFields': placeholderFields,
            'placeholderScrollExtents': placeholderScrolls,
            'synopsisWidthCu':
                find
                    .byKey(const Key('guide-program-synopsis'))
                    .evaluate()
                    .isEmpty
                ? null
                : tester
                      .getSize(find.byKey(const Key('guide-program-synopsis')))
                      .width,
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
          if (configuration.state == 'unavailable') {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
            await tester.pumpAndSettle();
            final picker = tester.widget<DropdownButton<String?>>(
              find.byKey(const Key('guide-library-picker')),
            );
            for (
              var step = 0;
              step < 8 && !picker.focusNode!.hasFocus;
              step++
            ) {
              await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
              await tester.pumpAndSettle();
            }
            expect(picker.focusNode!.hasFocus, isTrue);
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
            await tester.pumpAndSettle();
            final retry = find.widgetWithText(TextButton, 'Retry');
            final owner = FocusManager.instance.primaryFocus!;
            expect(
              owner.context!.findAncestorWidgetOfExactType<TextButton>(),
              same(tester.widget<TextButton>(retry)),
            );
            // The entire unchanged placeholder remains visible while its actual
            // Retry button owns focus, with no scroll/reveal hiding earlier text.
            final focusedFields = <Map<String, Object?>>[];
            for (final field in required) {
              final rect = tester.getRect(field);
              final frame = tester.widget(field) is TextButton && large
                  ? rect.inflate(6 * canvasScale)
                  : rect;
              if (frame.top < pip.top - .1 ||
                  frame.bottom > pip.bottom + .1 ||
                  frame.left < pip.left - .1 ||
                  frame.right > pip.right + .1) {
                violations.add(
                  'Retry focus hides required placeholder/frame: $frame outside $pip',
                );
              }
              focusedFields.add({'rect': _rect(rect), 'frame': _rect(frame)});
            }
            final focusedScrolls = <Map<String, double>>[];
            for (final element
                in find
                    .descendant(
                      of: find.byType(GuidePlaybackPlaceholder),
                      matching: find.byType(Scrollable),
                    )
                    .evaluate()) {
              final state = tester.state<ScrollableState>(
                find.byElementPredicate((e) => e == element),
              );
              focusedScrolls.add({
                'extent': state.position.maxScrollExtent,
                'offset': state.position.pixels,
              });
              if (state.position.maxScrollExtent > .1 ||
                  state.position.pixels.abs() > .1) {
                violations.add(
                  'Focused Retry needs placeholder scroll: ${state.position.pixels}/${state.position.maxScrollExtent}',
                );
              }
            }
            expect(tester.getRect(list), listRect);
            expect(tester.widget<ListView>(list).itemExtent, rowHeight);
            expect(
              tester.getRect(find.byKey(const Key('guide-picture-in-picture'))),
              pip,
            );
            final dir = Platform.environment['GUIDE_ALLOCATION_CAPTURE'];
            if (dir != null) {
              await tester.runAsync(() async {
                final image =
                    await (capture.currentContext!.findRenderObject()!
                            as RenderRepaintBoundary)
                        .toImage(pixelRatio: configuration.dpr);
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File(
                  '$dir/${configuration.name}-rich$rich-retry-focused.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            await tester.sendKeyEvent(LogicalKeyboardKey.select);
            await tester.pumpAndSettle();
            expect(retryCalls, 1);
            if (dir != null) {
              await tester.runAsync(
                () =>
                    File(
                      '$dir/${configuration.name}-rich$rich-retry-focus.json',
                    ).writeAsString(
                      jsonEncode({
                        'keyRoute': [
                          'Up',
                          'Left to library picker',
                          'Up',
                          'Select',
                        ],
                        'actualRetryOwner': true,
                        'callbackCount': retryCalls,
                        'fields': focusedFields,
                        'scrolls': focusedScrolls,
                        'rowHeightCu': rowHeight,
                        'list': _rect(listRect),
                        'pip': _rect(pip),
                        'violations': violations,
                      }),
                    ),
              );
            }
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
          final pictureState = ValueNotifier('idle');
          final baseTheme = LineupTheme.forName(
            LineupThemeName.emberSteel,
            androidTv: true,
            largeFocusIndicators: large,
          );
          final theme = ValueNotifier(baseTheme);
          final transitions = <Map<String, Object?>>[];
          final semantics = tester.ensureSemantics();
          try {
            await tester.pumpWidget(
              ValueListenableBuilder<ThemeData>(
                valueListenable: theme,
                builder: (context, value, child) => MaterialApp(
                  theme: value,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: LineupCanvas(
                      child: Theme(data: value, child: child!),
                    ),
                  ),
                  home: SafeArea(
                    child: ValueListenableBuilder<String>(
                      valueListenable: pictureState,
                      builder: (context, state, child) => GuideView(
                        controller: guide,
                        pictureInPicture: _pictureForState(state, () {}),
                        onClose: (_, _) {},
                        onTune: (_) async {},
                        onOpenMenu: (_, _) {},
                      ),
                    ),
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
            final element = tester.element(find.byType(GuideView));
            final owner = FocusManager.instance.primaryFocus;
            final stableFields = {
              for (final key in [
                'guide-information-area',
                'guide-program-identity',
                'guide-program-synopsis',
              ])
                key: tester.getRect(find.byKey(Key(key))),
            };
            for (final state in ['playing', 'unavailable', 'idle']) {
              pictureState.value = state;
              await tester.pumpAndSettle();
              expect(
                state == 'playing'
                    ? find.byKey(const Key('playing-proxy'))
                    : find.text(
                        state == 'unavailable'
                            ? 'Playback unavailable'
                            : 'Choose a channel to watch',
                      ),
                findsOneWidget,
              );
              expect(tester.element(find.byType(GuideView)), same(element));
              expect(FocusManager.instance.primaryFocus, same(owner));
              expect(tester.widget<ListView>(list).itemExtent, row);
              expect(tester.getRect(list), listRect);
              expect(
                tester.getRect(
                  find.byKey(const Key('guide-picture-in-picture')),
                ),
                pipRect,
              );
              for (final field in stableFields.entries) {
                expect(tester.getRect(find.byKey(Key(field.key))), field.value);
              }
              transitions.add({
                'state': state,
                'contentObserved': true,
                'fields': {
                  for (final f in stableFields.entries) f.key: _rect(f.value),
                },
                'rowHeightCu': row,
                'list': _rect(listRect),
                'pip': _rect(pipRect),
              });
            }
            // Retry geometry is a theme input, unlike playback or program state.
            // Change each dependency while retaining the same Guide and TextTheme.
            pictureState.value = 'unavailable';
            await tester.pumpAndSettle();
            final retryStyle = baseTheme.textButtonTheme.style!;
            for (final geometry in {
              'text': retryStyle.copyWith(
                textStyle: WidgetStatePropertyAll(
                  retryStyle.textStyle!.resolve({})!.copyWith(fontSize: 60),
                ),
              ),
              'minimum': retryStyle.copyWith(
                minimumSize: const WidgetStatePropertyAll(Size(48, 100)),
              ),
              'padding': retryStyle.copyWith(
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 20, vertical: 28),
                ),
              ),
            }.entries) {
              theme.value = baseTheme.copyWith(
                textButtonTheme: TextButtonThemeData(style: geometry.value),
              );
              await tester.pumpAndSettle();
              expect(tester.element(find.byType(GuideView)), same(element));
              final changedPiP = tester.getRect(
                find.byKey(const Key('guide-picture-in-picture')),
              );
              // The full-height canvas may already use the PiP width budget.
              // Its complete error/Retry task must fit for each theme input.
              expect(changedPiP.width, greaterThan(0));
              _expectCompletePlaybackTask(tester, changedPiP, large: large);
              theme.value = baseTheme;
              await tester.pumpAndSettle();
              expect(
                tester.getRect(
                  find.byKey(const Key('guide-picture-in-picture')),
                ),
                pipRect,
              );
            }
            pictureState.value = 'idle';
            await tester.pumpAndSettle();
            final directory = Platform.environment['GUIDE_ALLOCATION_CAPTURE'];
            if (directory != null) {
              await tester.runAsync(() async {
                await Directory(directory).create(recursive: true);
                await File('$directory/state-stability-$scale-large$large.json')
                    .writeAsString(jsonEncode(transitions));
              });
            }
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
                await _awaitLogoArtwork(tester);
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
            pictureState.dispose();
            theme.dispose();
          }
        },
      );
    }
  }
}

const _playbackError =
    'A synthetic playback request failed while connecting to the media source. Check the connection and try playback again. The original three-line message contract is retained for this deliberate long synthetic error.';
Widget _pictureForState(String state, VoidCallback retry) => state == 'playing'
    ? const ColoredBox(
        color: Color(0xFF203747),
        child: Center(
          child: Text('Synthetic playing PiP proxy', key: Key('playing-proxy')),
        ),
      )
    : GuidePlaybackPlaceholder(
        unavailable: state == 'unavailable',
        reduceMotion: true,
        message: state == 'unavailable' ? _playbackError : null,
        onRetry: state == 'unavailable' ? retry : null,
      );

void _expectCompletePlaybackTask(
  WidgetTester tester,
  Rect pip, {
  required bool large,
}) {
  final box = tester.renderObject<RenderBox>(
    find.byKey(const Key('guide-picture-in-picture')),
  );
  final scale =
      (box.localToGlobal(const Offset(1, 0)) - box.localToGlobal(Offset.zero))
          .distance;
  for (final field in [
    find.text('Playback unavailable'),
    find.text(_playbackError),
    find.descendant(
      of: find.byType(GuidePlaybackPlaceholder),
      matching: find.widgetWithText(TextButton, 'Retry'),
    ),
  ]) {
    final rect = tester.getRect(field);
    final frame = tester.widget(field) is TextButton && large
        ? rect.inflate(6 * scale)
        : rect;
    expect(frame.left, greaterThanOrEqualTo(pip.left - .1));
    expect(frame.right, lessThanOrEqualTo(pip.right + .1));
    expect(frame.top, greaterThanOrEqualTo(pip.top - .1));
    expect(frame.bottom, lessThanOrEqualTo(pip.bottom + .1));
  }
  for (final element
      in find
          .descendant(
            of: find.byType(GuidePlaybackPlaceholder),
            matching: find.byType(RichText),
          )
          .evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final painter = TextPainter(
      text: paragraph.text,
      textScaler: paragraph.textScaler,
      textDirection: paragraph.textDirection,
      maxLines: paragraph.maxLines,
      ellipsis: paragraph.overflow == TextOverflow.ellipsis ? '…' : null,
    )..layout(maxWidth: paragraph.size.width);
    expect(paragraph.size.height + .1, greaterThanOrEqualTo(painter.height));
    if (paragraph.text.toPlainText() == _playbackError) {
      expect(painter.computeLineMetrics(), hasLength(3));
    }
    painter.dispose();
  }
  for (final element
      in find
          .descendant(
            of: find.byType(GuidePlaybackPlaceholder),
            matching: find.byType(Scrollable),
          )
          .evaluate()) {
    final state = tester.state<ScrollableState>(
      find.byElementPredicate((e) => e == element),
    );
    expect(state.position.maxScrollExtent, closeTo(0, .1));
    expect(state.position.pixels, closeTo(0, .1));
  }
}

Future<void> _awaitLogoArtwork(
  WidgetTester tester, {
  bool fallback = false,
}) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pumpAndSettle();
    if (!fallback &&
        find.byKey(const Key('guide-clear-logo')).evaluate().isNotEmpty) {
      return;
    }
    // Rejected tall artwork has the same geometry during loading and after
    // rejection. Give the engine its complete real-time settling window.
  }
  expect(
    find.byKey(
      Key(fallback ? 'guide-clear-logo-fallback' : 'guide-clear-logo'),
    ),
    findsOneWidget,
  );
}
