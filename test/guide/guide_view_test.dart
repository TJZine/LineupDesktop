import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart'
    show RenderParagraph, RenderRepaintBoundary;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/guide/guide_view.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/native_video_surface.dart';

import '../support/ui_fixture.dart' show FixturePlayer;

import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/app_ui.dart';

final _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
  'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);
// Synthetic 3:1 title artwork and a 20x1200 image that fits too narrowly.
final _wideLogoPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAMAAAABCAAAAAA+i0toAAAADElEQVR4nGP4//8/AAX+Av4N70a4AAAAAElFTkSuQmCC',
);
final _narrowLogoPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAABQAAASwCAAAAADeIDU6AAAAWElEQVR4nO3IMQEAAAwCIPuX1gILsANO0kOklFJKKaWUUkoppZRSSimllFJKKaWUUkoppZRSSimllFJKKaWUUkoppZRSSimllFJKKaWUUkoppZRSSinl1xx/t2e0Ivf9MAAAAABJRU5ErkJggg==',
);

void main() {
  test('full-bleed layout and row snapping use the whole viewport', () {
    for (final size in const [
      Size(1280, 720),
      Size(1920, 1080),
      Size(1920, 1200),
      Size(2560, 1440),
      Size(3440, 1440),
    ]) {
      final canvas = size / LineupCanvas.scaleFor(size);
      final policy = GuideLayoutPolicy.forSize(canvas, hasPicture: true);
      expect(policy.padding, 0);
      expect(GuideLayoutPolicy.availableWidth(canvas), canvas.width);
      final row = policy.rowHeight;
      expect(
        GuideLayoutPolicy.snapRowOffset(row * 2.4, row, row * 10),
        closeTo(row * 2, .000001),
      );
      expect(
        GuideLayoutPolicy.snapRowOffset(row * 2.6, row, row * 10),
        closeTo(row * 3, .000001),
      );
      expect(GuideLayoutPolicy.snapRowOffset(-row, row, row * 10), 0);
      expect(
        GuideLayoutPolicy.snapRowOffset(row * 20, row, row * 10),
        closeTo(row * 10, .000001),
      );
    }
  });

  testWidgets(
    'Guide rows fill the bottom and snap wheel, scrollbar, focus and page movement',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final (size, textScale) in [
        (const Size(1280, 720), 1.0),
        (const Size(1920, 1080), 1.0),
        (const Size(1920, 1200), 1.0),
        (const Size(2560, 1440), 1.0),
        (const Size(3440, 1440), 1.0),
        (const Size(1920, 1080), 1.5),
      ]) {
        tester.view.physicalSize = size;
        final lineup = _Lineup(40);
        final guide = GuideController(
          lineup: lineup,
          loadSchedule: (c) async => _schedule(c),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: LineupTheme.forName(LineupThemeName.emberSteel)
                .copyWith(platform: TargetPlatform.windows),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: LineupCanvas(child: child!),
            ),
            home: GuideView(
              controller: guide,
              pictureInPicture: const SizedBox.expand(),
              onClose: () {},
              onTune: (_) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final finder = find.byKey(const Key('guide-schedule-list'));
        final list = tester.widget<ListView>(finder);
        final row = list.itemExtent!;
        ScrollPosition position() => list.controller!.position;
        void expectSnapped() => expect(
          position().pixels / row,
          closeTo((position().pixels / row).round(), .000001),
          reason: '$size text=$textScale',
        );
        final bounds = _drawnRect(tester, finder);
        expect(bounds.left, closeTo(0, .001));
        expect(bounds.right, closeTo(size.width, .001));
        expect(bounds.bottom, closeTo(size.height, .001));
        expect(tester.getSize(finder).height / row, closeTo(5, .000001));
        final controls = _drawnRect(
          tester,
          find.byKey(const Key('guide-control-content')),
        );
        final inset = 12 * LineupCanvas.scaleFor(size);
        expect(controls.left, closeTo(inset, .001));
        expect(controls.right, closeTo(size.width - inset, .001));
        expect(
          _drawnRect(tester, find.text('1')).left,
          closeTo(controls.left, .001),
        );
        // Scrollbar updates use ScrollPosition.jumpTo, not ScrollController.jumpTo.
        position().jumpTo(row * 2.4);
        await tester.pumpAndSettle();
        expect(position().pixels, closeTo(row * 2, .000001));
        expectSnapped();
        tester.binding.handlePointerEvent(
          PointerScrollEvent(
            position: bounds.center,
            scrollDelta: const Offset(0, 25),
          ),
        );
        await tester.pumpAndSettle();
        expect(position().pixels, closeTo(row * 3, .000001));
        expectSnapped();
        // Drag the actual desktop thumb from the first row.
        position().jumpTo(0);
        await tester.pumpAndSettle();
        await tester.dragFrom(
          Offset(bounds.right - 4, bounds.top + 12),
          const Offset(0, 100),
        );
        await tester.pumpAndSettle();
        expect(position().pixels, greaterThan(0));
        expectSnapped();
        for (var i = 0; i < 15; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          expectSnapped();
        }
        final beforePage = guide.focusedChannelIndex;
        await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
        await tester.pumpAndSettle();
        expect(guide.focusedChannelIndex, beforePage + 5);
        expectSnapped();
        await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
        await tester.pumpAndSettle();
        expectSnapped();
        position().jumpTo(position().maxScrollExtent);
        await tester.pumpAndSettle();
        expectSnapped();
        expect(position().pixels, closeTo(position().maxScrollExtent, .000001));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        guide.dispose();
        lineup.dispose();
      }
    },
  );

  testWidgets(
    'hours trigger is plain text and search hint and input share the field center',
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1920, 1080);
      addTearDown(tester.view.reset);
      for (final scale in [1.0, 1.5]) {
        final lineup = _Lineup(10);
        final guide = GuideController(
          lineup: lineup,
          loadSchedule: (c) async => _schedule(c),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: LineupTheme.forName(LineupThemeName.emberSteel),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: LineupCanvas(child: child!),
            ),
            home: GuideView(
              controller: guide,
              onClose: () {},
              onTune: (_) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final hours = find.byKey(const Key('guide-hours'));
        expect(
          find.descendant(
            of: hours,
            matching: find.byType(LineupDropdownMenuRow),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: hours,
            matching: find.text('${guide.guideHours} hours'),
          ),
          findsOneWidget,
        );
        final search = find.byKey(const Key('guide-channel-search'));
        final center = _drawnRect(tester, search).center.dy;
        final hint = find.descendant(
          of: search,
          matching: find.text('Search channels'),
        );
        final hintCenter = _drawnRect(tester, hint).center.dy;
        expect(
          hintCenter,
          closeTo(center, 1),
          reason: 'hint at text scale $scale',
        );
        await tester.enterText(search, 'Channel');
        await tester.pumpAndSettle();
        final editable = tester
            .state<EditableTextState>(
              find.descendant(of: search, matching: find.byType(EditableText)),
            )
            .renderEditable;
        final caret = editable.getLocalRectForCaret(
          const TextPosition(offset: 0),
        );
        final inputCenter = editable.localToGlobal(caret.center).dy;
        expect(
          inputCenter,
          closeTo(center, 1),
          reason: 'input at text scale $scale',
        );
        expect(inputCenter, closeTo(hintCenter, 1));
        await tester.tap(hours);
        await tester.pumpAndSettle();
        expect(find.byType(LineupDropdownMenuRow), findsWidgets);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        guide.dispose();
        lineup.dispose();
      }
    },
  );

  testWidgets(
    'Guide PiP preserves pre-full-bleed dimensions and native alignment across the matrix',
    (tester) async {
      addTearDown(tester.view.reset);
      // Frozen drawn dimensions measured from the retained pre-B production
      // Guide widget with the same canvas, theme and text scale. This protects
      // the approved aperture size independently of the current layout policy.
      for (final (size, textScale, expectedPicture, expectedInformationHeight)
          in const [
            (Size(1280.0, 720.0), 1.0, Size(296.967111, 167.044), 167.036),
            (Size(1920.0, 1080.0), 1.0, Size(576.0, 324.0), 323.995),
            (Size(1920.0, 1200.0), 1.0, Size(576.0, 324.0), 443.995),
            (Size(2560.0, 1440.0), 1.0, Size(768.0, 432.0), 431.993333),
            (Size(3440.0, 1440.0), 1.0, Size(768.0, 432.0), 431.993333),
            (Size(3840.0, 2160.0), 1.0, Size(1152.0, 648.0), 647.99),
            (Size(1920.0, 1080.0), 1.5, Size(576.0, 324.0), 323.995),
          ]) {
        for (final dpr in [1.0, 1.5]) {
          tester.view
            ..devicePixelRatio = dpr
            ..physicalSize = size * dpr;
          final lineup = _Lineup(20);
          final guide = GuideController(
            lineup: lineup,
            // Match the non-midnight reference clock used for the frozen measurements.
            clock: () => DateTime.utc(2026, 1, 15, 3, 17),
            loadSchedule: (c) async => _schedule(c),
          );
          final player = _GuideBoundsPlayer();
          await tester.pumpWidget(
            MaterialApp(
              theme: LineupTheme.forName(LineupThemeName.emberSteel),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(textScale)),
                child: LineupCanvas(child: child!),
              ),
              home: GuideView(
                controller: guide,
                pictureInPicture: NativeVideoSurface(player: player),
                onClose: () {},
                onTune: (_) async {},
              ),
            ),
          );
          await tester.pumpAndSettle();
          final aperture = _drawnRect(
            tester,
            find.byKey(const Key('guide-picture-in-picture')),
          );
          final clip = tester.widget<ClipRRect>(
            find.descendant(
              of: find.byKey(const Key('guide-picture-in-picture')),
              matching: find.byType(ClipRRect),
            ),
          );
          final radius = clip.borderRadius.resolve(TextDirection.ltr);
          expect(radius.topLeft, Radius.zero);
          expect(radius.bottomLeft, Radius.zero);
          expect(radius.topRight, const Radius.circular(12));
          expect(radius.bottomRight, const Radius.circular(12));
          final rect = player.rects.last;
          expect(
            _drawnRect(
              tester,
              find.byKey(const Key('guide-information-area')),
            ).height,
            closeTo(expectedInformationHeight, .001),
            reason: '$size text=$textScale information height',
          );

          expect(
            aperture.width,
            closeTo(expectedPicture.width, .001),
            reason: '$size text=$textScale DPR=$dpr',
          );
          expect(
            aperture.height,
            closeTo(expectedPicture.height, .001),
            reason: '$size text=$textScale DPR=$dpr',
          );
          expect(aperture.left, closeTo(0, .001));
          expect(rect.left, closeTo(aperture.left, .001));
          expect(rect.top, closeTo(aperture.top, .001));
          expect(rect.width, closeTo(aperture.width, .001));
          expect(rect.height, closeTo(aperture.height, .001));
          expect(rect.scale, dpr);
          await tester.pumpWidget(const SizedBox.shrink());
          guide.dispose();
          lineup.dispose();
          await player.dispose();
        }
      }
    },
  );

  testWidgets(
    'short and long synopsis retain media facts in bounded small and enlarged Guide details',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final (size, textScale) in [
        (const Size(1280, 720), 1.0),
        (const Size(1920, 1080), 1.0),
        (const Size(1920, 1080), 1.5),
      ]) {
        tester.view.physicalSize = size;
        double? infoHeight;
        double? rowHeight;
        double? shortHeight;
        for (final summary in [
          'A signal arrives.',
          List.filled(80, 'A signal reaches the crew.').join(' '),
        ]) {
          final lineup = _Lineup(1)
            ..settings = const LineupSettings(preferClearLogos: false);
          final channel = lineup.channels.single;
          lineup.channels = [
            Channel(
              id: channel.id,
              number: 1,
              name: 'Drama',
              source: ManualSource([
                ChannelItem(
                  id: 'episode',
                  title: 'The Last Frequency',
                  showTitle: 'Signal House',
                  duration: const Duration(hours: 24),
                  summary: summary,
                  year: 2026,
                  genres: const ['Drama', 'Science Fiction'],
                  contentRating: 'TV-14',
                  resolution: '4k',
                  audioCodec: 'eac3',
                ),
              ]),
              playbackMode: PlaybackMode.sequential,
              anchor: channel.anchor,
              shuffleSeed: 1,
            ),
          ];
          final guide = GuideController(
            lineup: lineup,
            loadSchedule: (c) async => _schedule(c),
          );
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(textScale)),
                child: LineupCanvas(child: child!),
              ),
              theme: LineupTheme.forName(
                LineupThemeName.emberSteel,
                largeFocusIndicators: false,
              ),
              home: GuideView(
                controller: guide,
                pictureInPicture: const ColoredBox(color: Colors.black),
                onClose: () {},
                onTune: (_) async {},
              ),
            ),
          );
          await tester.pumpAndSettle();
          final synopsis = find.byKey(const Key('guide-program-synopsis'));
          expect(synopsis, findsOneWidget, reason: '$size, text $textScale');
          final text = tester.widget<Text>(synopsis);
          expect(text.maxLines, greaterThan(0));
          if (size == const Size(1920, 1080) && textScale == 1) {
            expect(text.maxLines, greaterThan(3));
          }
          expect(text.overflow, TextOverflow.ellipsis);
          final paragraph = tester.renderObject<RenderParagraph>(synopsis);
          final element = tester.element(synopsis);
          final natural = TextPainter(
            text: TextSpan(
              text: summary,
              style: DefaultTextStyle.of(element).style.merge(text.style),
            ),
            textScaler: MediaQuery.textScalerOf(element),
            textDirection: Directionality.of(element),
            maxLines: text.maxLines,
            ellipsis: '…',
          )..layout(maxWidth: tester.getSize(synopsis).width);
          expect(tester.getSize(synopsis).height, closeTo(natural.height, .1));
          natural.dispose();
          if (shortHeight == null) {
            shortHeight = tester.getSize(synopsis).height;
            expect(paragraph.didExceedMaxLines, isFalse);
          } else {
            expect(paragraph.didExceedMaxLines, isTrue);
            expect(tester.getSize(synopsis).height, greaterThan(shortHeight));
          }
          final area = find.byKey(const Key('guide-information-area'));
          final currentHeight = tester.getSize(area).height;
          final list = tester.widget<ListView>(
            find.byKey(const Key('guide-schedule-list')),
          );
          if (infoHeight == null) {
            infoHeight = currentHeight;
            rowHeight = list.itemExtent;
          } else {
            expect(currentHeight, infoHeight);
            expect(list.itemExtent, rowHeight);
          }
          expect(
            _detailsMetadata(tester),
            contains('2026 · Drama · Science Fiction'),
          );
          for (final badge in ['TV-14', '4K', 'EAC3']) {
            expect(find.text(badge), findsOneWidget);
          }
          final progressRect = tester.getRect(
            find.byKey(const Key('guide-program-progress')),
          );
          expect(
            tester.getRect(synopsis).bottom,
            lessThanOrEqualTo(progressRect.top),
          );
          await tester.ensureVisible(
            find.byKey(const Key('guide-program-badges')),
          );
          await tester.pumpAndSettle();
          expect(
            tester
                .getRect(find.byKey(const Key('guide-program-badges')))
                .bottom,
            lessThan(progressRect.top),
          );
          await tester.ensureVisible(synopsis);
          await tester.pumpAndSettle();
          expect(synopsis.hitTestable(), findsOneWidget);
          expect(tester.getSize(area).height, infoHeight);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          guide.dispose();
          lineup.dispose();
        }
      }
    },
  );

  testWidgets(
    'enlarged Guide metadata wraps with content at the start of each rendered line',
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1920, 1080);
      addTearDown(tester.view.reset);
      final start = DateTime.utc(2026, 1, 15, 3, 12);
      final lineup = _Lineup(1, anchor: start)
        ..settings = const LineupSettings(preferClearLogos: false);
      final channel = lineup.channels.single;
      lineup.channels = [
        Channel(
          id: channel.id,
          number: 2,
          name: 'Midnight Mysteries',
          source: const ManualSource([
            ChannelItem(
              id: 'signal',
              title: 'The Last Frequency',
              showTitle: 'Signal After Midnight',
              duration: Duration(minutes: 48),
              year: 2026,
              genres: ['Mystery', 'Drama', 'Thriller'],
              summary: 'A broadcast returns.',
            ),
          ]),
          playbackMode: channel.playbackMode,
          anchor: start,
          shuffleSeed: 1,
        ),
      ];
      final guide = GuideController(
        lineup: lineup,
        clock: () => start.add(const Duration(minutes: 5)),
        loadSchedule: (c) async => _schedule(c),
      );
      addTearDown(guide.dispose);
      addTearDown(lineup.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: LineupCanvas(child: child!),
          ),
          home: GuideView(
            controller: guide,
            pictureInPicture: const ColoredBox(color: Colors.black),
            onClose: () {},
            onTune: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final time = find.byKey(const Key('guide-program-meta'));
      final facts = find.byKey(const Key('guide-info-genres'));
      expect(
        tester.getRect(facts).top,
        greaterThan(tester.getRect(time).bottom),
      );
      expect(
        tester.widget<Text>(time).data!.replaceAll('\u00a0', ' '),
        '${_testTime(start.toLocal())}–${_testTime(start.add(const Duration(minutes: 48)).toLocal())} · 43m left',
      );
      expect(
        _detailsMetadata(tester),
        contains('2026 · Mystery · Drama · Thriller'),
      );
      for (final finder in [time, facts]) {
        final paragraph = tester.renderObject<RenderParagraph>(finder);
        final text = paragraph.text.toPlainText();
        final lines = <double, String>{};
        // Inspect actual glyph positions, including soft line breaks. The test
        // font forces wrapping inside both paragraphs at this allocation.
        for (var offset = 0; offset < text.length; offset++) {
          final character = text.substring(offset, offset + 1);
          if (character.trim().isEmpty) continue;
          final boxes = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: offset, extentOffset: offset + 1),
          );
          expect(boxes, isNotEmpty);
          final top = boxes.first.top;
          lines[top] = '${lines[top] ?? ''}$character';
        }
        expect(lines.length, greaterThan(1), reason: text);
        for (final line in lines.values) {
          expect(line.startsWith('·'), isFalse, reason: '$text: $line');
        }
        expect(paragraph.didExceedMaxLines, isFalse);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Guide detail time line follows start-inclusive and end-exclusive airing boundaries',
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1920, 1080);
      addTearDown(tester.view.reset);
      final start = DateTime.utc(2026, 1, 15, 3, 12);
      var now = start.add(const Duration(minutes: 5));
      final lineup = _Lineup(1, anchor: start)
        ..settings = const LineupSettings(
          preferClearLogos: false,
          reduceMotion: true,
        );
      final old = lineup.channels.single;
      lineup.channels = [
        Channel(
          id: old.id,
          number: 2,
          name: 'Midnight Mysteries',
          source: const ManualSource([
            ChannelItem(
              id: 'signal',
              title: 'The Last Frequency',
              showTitle: 'Signal After Midnight',
              duration: Duration(minutes: 48),
              year: 2026,
              genres: ['Mystery', 'Drama', 'Thriller'],
              summary: 'A broadcast returns.',
            ),
          ]),
          playbackMode: old.playbackMode,
          anchor: start,
          shuffleSeed: 1,
        ),
      ];
      final guide = GuideController(
        lineup: lineup,
        clock: () => now,
        loadSchedule: (c) async => _schedule(c),
      );
      addTearDown(guide.dispose);
      addTearDown(lineup.dispose);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            builder: LineupCanvas.builder,
            home: GuideView(
              controller: guide,
              pictureInPicture: const ColoredBox(color: Colors.black),
              onClose: () {},
              onTune: (_) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final program = guide.focusedProgram!;
        final end = start.add(const Duration(minutes: 48));
        expect(program.scheduled.start, start);
        expect(program.scheduled.end, end);
        final range =
            '${_testTime(start.toLocal())}–${_testTime(end.toLocal())}';
        for (final (at, suffix, progressLabel) in [
          (start.subtract(const Duration(seconds: 1)), ' · 48m', null),
          (start, ' · 48m left', '0m elapsed, 48m remaining'),
          (
            start.add(const Duration(minutes: 5)),
            ' · 43m left',
            '5m elapsed, 43m remaining',
          ),
          (
            end.subtract(const Duration(seconds: 1)),
            ' · 0m left',
            '47m elapsed, 0m remaining',
          ),
          (end, '', null),
          (end.add(const Duration(seconds: 1)), '', null),
        ]) {
          now = at;
          guide.focusProgram(program);
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<Text>(find.byKey(const Key('guide-program-meta')))
                .data,
            '$range$suffix',
            reason: '$at',
          );
          expect(
            tester
                .widget<Text>(find.byKey(const Key('guide-info-genres')))
                .data,
            '2026 · Mystery · Drama · Thriller',
          );
          expect(
            find.byKey(const Key('guide-program-progress')),
            progressLabel == null ? findsNothing : findsOneWidget,
          );
          if (progressLabel != null) {
            expect(
              find.bySemanticsLabel(RegExp(RegExp.escape(progressLabel))),
              findsWidgets,
            );
          }
          expect(tester.takeException(), isNull);
        }
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'Guide identity uses the full companion width when synopsis is missing',
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1920, 1080);
      addTearDown(tester.view.reset);
      final lineup = _Lineup(1)
        ..settings = const LineupSettings(reduceMotion: true);
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (c) async => _schedule(c),
      );
      addTearDown(guide.dispose);
      addTearDown(lineup.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: LineupCanvas.builder,
          home: GuideView(
            controller: guide,
            pictureInPicture: const ColoredBox(color: Colors.black),
            onClose: () {},
            onTune: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guide-program-synopsis')), findsNothing);
      final identity = tester.getRect(
        find.byKey(const Key('guide-program-identity')),
      );
      final progress = tester.getRect(
        find.byKey(const Key('guide-program-progress')),
      );
      expect(identity.left, progress.left);
      expect(identity.width, progress.width);
      expect(
        find.byKey(const Key('guide-clear-logo-fallback')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Guide details use companion columns and fitted cell times follow the episode',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final lineup = _Lineup(1)
        ..settings = const LineupSettings(
          preferClearLogos: false,
          largeFocusIndicators: true,
        );
      final channel = lineup.channels.single;
      lineup.channels = [
        Channel(
          id: channel.id,
          number: 1,
          name: 'Drama',
          source: const ManualSource([
            ChannelItem(
              id: 'episode',
              title: 'The Last Frequency',
              showTitle: 'Signal House',
              duration: Duration(hours: 24),
              year: 2026,
              genres: ['Drama', 'Science Fiction'],
              contentRating: 'TV-14',
              resolution: '4k',
              audioCodec: 'eac3',
              summary: 'A signal reaches the crew. A signal reaches the crew. A signal reaches the crew. A signal reaches the crew. A signal reaches the crew. A signal reaches the crew. A signal reaches the crew. A signal reaches the crew. A signal reaches the crew. A signal reaches the crew.',
            ),
          ]),
          playbackMode: PlaybackMode.sequential,
          anchor: channel.anchor,
          shuffleSeed: 1,
        ),
      ];
      addTearDown(lineup.dispose);
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (c) async => _schedule(c),
      );
      addTearDown(guide.dispose);
      for (final theme in LineupThemeName.values) {
        await tester.pumpWidget(
          MaterialApp(
            builder: LineupCanvas.builder,
            theme: LineupTheme.forName(theme, largeFocusIndicators: true),
            home: GuideView(
              controller: guide,
              pictureInPicture: const ColoredBox(color: Colors.black),
              onClose: () {},
              onTune: (_) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final meta = find.byKey(const Key('guide-program-meta'));
        final progress = find.byKey(const Key('guide-program-progress'));
        final synopsis = find.byKey(const Key('guide-program-synopsis'));
        final identity = find.byKey(const Key('guide-program-identity'));
        expect(tester.getSize(progress).width, greaterThan(920));
        expect(
          tester.getSize(identity).width,
          closeTo((tester.getSize(progress).width - 32) * .4, .1),
        );
        expect(
          tester.getTopLeft(synopsis).dx,
          greaterThan(tester.getTopRight(identity).dx),
        );
        expect(
          tester.getTopLeft(synopsis).dy,
          closeTo(
            tester
                .getTopLeft(find.byKey(const Key('guide-clear-logo-fallback')))
                .dy,
            .1,
          ),
        );
        expect(tester.getTopLeft(meta).dx, tester.getTopLeft(progress).dx);
        final summary = tester.widget<Text>(synopsis);
        expect(summary.maxLines, greaterThan(3));
        expect(summary.overflow, TextOverflow.ellipsis);
        final metadata = tester.widget<Text>(meta);
        expect(metadata.data, contains('left'));
        expect(
          _detailsMetadata(tester),
          contains('2026 · Drama · Science Fiction'),
        );
        final cell = find.byKey(ValueKey(guide.focusedProgram!.id));
        final episode = find.descendant(
          of: cell,
          matching: find.text('The Last Frequency'),
        );
        final time = find.descendant(
          of: cell,
          matching: find.byWidgetPredicate(
            (w) => w is Text && (w.data?.contains('–') ?? false),
          ),
        );
        final dot = find.descendant(
          of: cell,
          matching: find.byKey(const Key('guide-airing-dot')),
        );
        final title = find.descendant(
          of: cell,
          matching: find.text('Signal House'),
        );
        expect(
          tester.getTopLeft(time).dx - tester.getTopRight(episode).dx,
          closeTo(12, .1),
        );
        expect(
          tester.getTopLeft(dot).dx,
          lessThan(tester.getTopLeft(title).dx),
        );
        final container = tester.widget<AnimatedContainer>(
          find.descendant(of: cell, matching: find.byType(AnimatedContainer)),
        );
        final decoration = container.decoration! as BoxDecoration;
        expect((decoration.border! as Border).top.color, Colors.transparent);
        final roles = LineupTheme.of(tester.element(cell));
        expect(
          decoration.color!.computeLuminance(),
          greaterThan(roles.primarySurface.computeLuminance()),
        );
        if (theme == LineupThemeName.directv) {
          expect(decoration.color, roles.focusedSurface);
          expect(tester.widget<Text>(title).style!.color, roles.onFocus);
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final activation in [
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.select,
  ]) {
    testWidgets(
      'single timeline retry is reachable with $activation and returns to row failures',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final lineup = _Lineup(12)
          ..settings = const LineupSettings(reduceMotion: true);
        addTearDown(lineup.dispose);
        final attempts = <String, int>{};
        final guide = GuideController(
          lineup: lineup,
          loadSchedule: (channel) async {
            final attempt = attempts.update(
              channel.id,
              (n) => n + 1,
              ifAbsent: () => 1,
            );
            if (attempt == 2 && channel.id == 'channel-0') {
              return _schedule(channel);
            }
            throw StateError('offline');
          },
        );
        addTearDown(guide.dispose);
        guide.requestChannels(lineup.channels);
        await tester.pumpWidget(
          MaterialApp(
            builder: LineupCanvas.builder,
            home: GuideView(
              controller: guide,
              onClose: () {},
              onTune: (_) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text("Schedules couldn't load"), findsOneWidget);
        final failureHeading = find.text("Schedules couldn't load");
        expect(
          tester.widget<Text>(failureHeading).style,
          Theme.of(tester.element(failureHeading)).textTheme.titleLarge,
        );
        expect(
          tester
              .getSemantics(failureHeading)
              .getSemanticsData()
              .flagsCollection
              .isHeader,
          isTrue,
        );
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Schedule unavailable ·'), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(guide.focusedChannelId, 'channel-1');
        expect(find.text('2 • Channel 1'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Guide retry all schedules',
        );
        await tester.sendKeyEvent(activation);
        await tester.pumpAndSettle();
        expect(attempts.length, 12);
        expect(attempts.values, everyElement(2));
        expect(find.text("Schedules couldn't load"), findsNothing);
        expect(find.text('Schedule unavailable ·'), findsWidgets);
        expect(guide.row('channel-0').state, GuideLoadState.ready);
        expect(guide.row('channel-1').state, GuideLoadState.error);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'empty Guide setup action and filtered empty state remain distinct',
    (tester) async {
      final lineup = _Lineup(0);
      addTearDown(lineup.dispose);
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (c) async => _schedule(c),
      );
      addTearDown(guide.dispose);
      var setups = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: LineupCanvas.builder,
          home: GuideView(
            controller: guide,
            onClose: () {},
            onTune: (_) async {},
            onSetUpChannels: () => setups++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No channels yet'), findsOneWidget);
      final emptyHeading = find.text('No channels yet');
      expect(
        tester.widget<Text>(emptyHeading).style,
        Theme.of(tester.element(emptyHeading)).textTheme.titleLarge,
      );
      expect(
        tester
            .getSemantics(emptyHeading)
            .getSemanticsData()
            .flagsCollection
            .isHeader,
        isTrue,
      );
      expect(find.text('Move to a program for details.'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Guide set up channels',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      expect(setups, 1);
      await tester.tap(find.text('Set up channels'));
      expect(setups, 2);
    },
  );

  testWidgets('sources default hidden and Watching remains independent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final lineup = _Lineup(2);
    addTearDown(lineup.dispose);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (c) async => _schedule(c),
    );
    addTearDown(guide.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: LineupCanvas.builder,
        home: GuideView(
          controller: guide,
          onClose: () {},
          onTune: (_) async {},
          watchingChannelId: 'channel-0',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Manual lineup'), findsNothing);
    expect(find.text('Watching'), findsOneWidget);
    await lineup.updateSettings(
      (s) => s.copyWith(guideShowChannelSources: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('Manual lineup'), findsOneWidget);
    expect(find.text('Watching'), findsOneWidget);
  });

  testWidgets(
    'shared idle backdrop rejects stale focus artwork and honors Reduce Motion',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = <String, Completer<Uint8List?>>{};
      final lineup =
          _Lineup(
              2,
              artworkLoader: (path) =>
                  (pending[path.path] = Completer<Uint8List?>()).future,
            )
            ..settings = const LineupSettings(
              guideInfoBackgroundMode: GuideInfoBackgroundMode.artwork,
              preferClearLogos: false,
              reduceMotion: true,
            );
      lineup.channels = [
        for (var i = 0; i < 2; i++)
          Channel(
            id: 'channel-$i',
            number: i + 1,
            name: 'Channel $i',
            source: ManualSource([
              ChannelItem(
                id: 'item-$i',
                title: 'Program $i',
                duration: const Duration(hours: 24),
                backdrop: Uri.parse('/backdrop-$i'),
              ),
            ]),
            playbackMode: PlaybackMode.sequential,
            anchor: DateTime.now().subtract(const Duration(hours: 1)),
            shuffleSeed: i,
          ),
      ];
      addTearDown(lineup.dispose);
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (c) async => _schedule(c),
      );
      addTearDown(guide.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: LineupCanvas.builder,
          home: GuideView(
            controller: guide,
            onClose: () {},
            onTune: (_) async {},
            showIdleArtwork: true,
            pictureInPicture: const Text('Choose a channel to watch'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Choose a channel to watch'), findsOneWidget);
      guide.moveVertical(1);
      await tester.pump();
      expect(lineup.artworkLoads, 2);
      pending['/backdrop-1']!.complete(_wideLogoPng);
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => precacheImage(
          MemoryImage(_wideLogoPng),
          tester.element(find.byType(GuideView)),
        ),
      );
      await tester.pumpAndSettle();
      pending['/backdrop-0']!.complete(_tinyPng);
      await tester.pumpAndSettle();
      final idle = tester.widget<Image>(
        find.byKey(const Key('guide-idle-backdrop')),
      );
      final info = tester.widget<Image>(
        find.byKey(const Key('guide-info-backdrop')),
      );
      expect((idle.image as MemoryImage).bytes, same(_wideLogoPng));
      expect(
        (info.image as MemoryImage).bytes,
        same((idle.image as MemoryImage).bytes),
      );
      expect(find.text('Select to watch · Channel 1'), findsOneWidget);
      final switcher = find.descendant(
        of: find.byKey(const Key('guide-picture-in-picture')),
        matching: find.byType(AnimatedSwitcher),
      );
      expect(tester.widget<AnimatedSwitcher>(switcher).duration, Duration.zero);
      await lineup.updateSettings((s) => s.copyWith(reduceMotion: false));
      await tester.pumpAndSettle();
      expect(
        tester.widget<AnimatedSwitcher>(switcher).duration,
        const Duration(milliseconds: 400),
      );
      expect(lineup.artworkLoads, 2);
      expect(tester.takeException(), isNull);
    },
  );

  test('16:10 height extends information without enlarging five rows', () {
    final reference = GuideLayoutPolicy.forSize(
      const Size(1920, 1080),
      hasPicture: true,
    );
    final tall = GuideLayoutPolicy.forSize(
      const Size(1920, 1200),
      hasPicture: true,
    );
    expect(tall.minimumRows, 5);
    expect(tall.rowHeight, reference.rowHeight);
    expect(tall.pictureWidth, reference.pictureWidth);
    expect(tall.showcaseHeight - reference.showcaseHeight, closeTo(120, .001));
  });

  test('clear logo usability follows decoded size and actual constraints', () {
    const ordinary = Size(1200, 400);
    const extremeWide = Size(1200, 20);
    const extremeNarrow = Size(20, 1200);
    const guideConstraint = BoxConstraints(maxWidth: 360, maxHeight: 52);
    const osdConstraint = BoxConstraints(maxWidth: 320, maxHeight: 68);
    const nowPlayingConstraint = BoxConstraints(maxWidth: 600, maxHeight: 132);

    for (final constraint in [
      guideConstraint,
      const BoxConstraints(maxWidth: 240, maxHeight: 36),
      osdConstraint,
      nowPlayingConstraint,
      const BoxConstraints(maxWidth: 360, maxHeight: 84),
      const BoxConstraints(maxWidth: 360, maxHeight: 58),
    ]) {
      expect(clearLogoIsUsable(ordinary, constraint), isTrue);
      expect(clearLogoIsUsable(extremeWide, constraint), isFalse);
      expect(clearLogoIsUsable(extremeNarrow, constraint), isFalse);
    }
    expect(
      clearLogoIsUsable(
        const Size(1200, 400),
        const BoxConstraints(maxWidth: 120, maxHeight: 20),
      ),
      isTrue,
    );
  });

  test('layout policy stays bounded and keeps one five-row composition', () {
    for (final size in const [
      Size.zero,
      Size(320, 240),
      Size(double.infinity, 720),
      Size(1280, double.infinity),
    ]) {
      final policy = GuideLayoutPolicy.forSize(
        size / LineupCanvas.scaleFor(size),
        hasPicture: true,
      );
      expect(policy.showcaseHeight, isNonNegative, reason: '$size');
      expect(policy.showcaseHeight.isFinite, isTrue, reason: '$size');
      expect(policy.pictureWidth, isNonNegative, reason: '$size');
      expect(policy.pictureWidth.isFinite, isTrue, reason: '$size');
    }

    final comfortable = GuideLayoutPolicy.forSize(
      const Size(1920, 1080),
      hasPicture: true,
    );
    final enlarged = GuideLayoutPolicy.forSize(
      const Size(1920, 1080),
      hasPicture: true,
      textScale: 2,
    );
    expect(comfortable.rowHeight, closeTo(114.4, 0.1));
    expect(enlarged.rowHeight, greaterThanOrEqualTo(116));
    expect(comfortable.minimumRows, 5);
    expect(enlarged.minimumRows, 5);
  });

  testWidgets('non-positive timeline slots render safely', (tester) async {
    final lineup = _Lineup(1)..settings = const LineupSettings(guideHours: 0);
    addTearDown(lineup.dispose);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    addTearDown(guide.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: LineupCanvas.builder,
        home: GuideView(
          controller: guide,
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
    lineup.dispose();
  });

  testWidgets('Guide Media Play jumps to now with DVR controls disabled', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 1, 1, 12, 17);
    final lineup = _Lineup(1)
      ..settings = const LineupSettings(dvrControlsEnabled: false);
    addTearDown(lineup.dispose);
    final guide = GuideController(
      lineup: lineup,
      clock: () => now,
      loadSchedule: (channel) async => _schedule(channel),
    );
    addTearDown(guide.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: LineupCanvas.builder,
        home: GuideView(
          controller: guide,
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    guide.moveHorizontal(1);
    expect(guide.windowStart, isNot(DateTime.utc(2026, 1, 1, 11, 30)));
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlay);
    await tester.pumpAndSettle();

    expect(guide.windowStart, DateTime.utc(2026, 1, 1, 12));
    expect(guide.focusTime, now);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('established viewport work is independent of lineup cardinality', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final count in [200, 500, 1000]) {
      final lineup = _Lineup(count);
      addTearDown(lineup.dispose);
      var loads = 0;
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async {
          loads++;
          return _schedule(channel);
        },
      );
      addTearDown(guide.dispose);
      final elapsed = Stopwatch()..start();
      await tester.pumpWidget(
        MaterialApp(
          builder: LineupCanvas.builder,
          home: GuideView(
            controller: guide,
            onClose: () {},
            onTune: (_) async {},
          ),
        ),
      );
      await tester.pump();
      elapsed.stop();
      debugPrint(
        'GUIDE_CARDINALITY channels=$count firstViewportUs=${elapsed.elapsedMicroseconds} '
        'widgets=${tester.allWidgets.length} loadedRows=$loads',
      );
      expect(loads, lessThan(30));
      expect(find.text('Channel ${count - 1}'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      guide.dispose();
      lineup.dispose();
    }
  });

  testWidgets('1000-channel Guide builds a bounded accessible viewport', (
    tester,
  ) async {
    final lineup = _Lineup(1000);
    addTearDown(lineup.dispose);
    var loads = 0;
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async {
        loads++;
        return _schedule(channel);
      },
    );
    addTearDown(guide.dispose);
    final rssBefore = ProcessInfo.currentRss;
    final firstViewport = Stopwatch()..start();
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: LineupCanvas.builder,
        home: GuideView(
          controller: guide,
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pump();
    firstViewport.stop();

    expect(
      find.bySemanticsLabel(RegExp(r'^Channel 1, Channel 0')),
      findsOneWidget,
    );
    expect(find.text('Channel 999'), findsNothing);
    expect(loads, lessThan(30));

    final navigation = Stopwatch()..start();
    for (var index = 0; index < 500; index++) {
      guide.moveVertical(1);
    }
    navigation.stop();
    await tester.pump();

    debugPrint(
      'GUIDE_PROFILE channels=1000 firstViewportUs=${firstViewport.elapsedMicroseconds} '
      'navigation500Us=${navigation.elapsedMicroseconds} widgets=${tester.allWidgets.length} '
      'cachedRows=${guide.cachedRowCount} rssDeltaBytes=${ProcessInfo.currentRss - rssBefore}',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    expect(guide.focusedChannelId, isNot('channel-0'));
    expect(loads, lessThan(40));

    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
    lineup.dispose();
  });

  testWidgets('1000-channel four-hour Guide stays lazy and focusable', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 1, 1, 12, 15);
    final lineup = _Lineup(1000)
      ..settings = const LineupSettings(guideHours: 4, reduceMotion: true);
    lineup.channels = [
      for (var index = 0; index < 1000; index++)
        Channel(
          id: 'channel-$index',
          number: index + 1,
          name: 'Channel $index',
          source: ManualSource([
            for (var slot = 0; slot < 4; slot++)
              ChannelItem(
                id: 'program-$index-$slot',
                title: 'Program $index-$slot',
                duration: const Duration(minutes: 30),
              ),
          ]),
          playbackMode: PlaybackMode.sequential,
          anchor: now.subtract(const Duration(minutes: 15)),
          shuffleSeed: index,
        ),
    ];
    addTearDown(lineup.dispose);
    final loadedChannelIds = <String>[];
    final guide = GuideController(
      lineup: lineup,
      clock: () => now,
      loadSchedule: (channel) async {
        loadedChannelIds.add(channel.id);
        return _schedule(channel);
      },
    );
    addTearDown(guide.dispose);
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1600, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final firstViewport = Stopwatch()..start();
    await tester.pumpWidget(
      MaterialApp(
        builder: LineupCanvas.builder,
        home: GuideView(
          controller: guide,
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    firstViewport.stop();

    final list = tester.widget<ListView>(
      find.byKey(const Key('guide-schedule-list')),
    );
    final scheduleHeight = tester
        .getSize(find.byKey(const Key('guide-schedule-list')))
        .height;
    final fullyVisibleRows = (scheduleHeight / list.itemExtent!).floor();
    final programCells = find
        .byWidgetPredicate((widget) {
          final key = widget.key;
          return key is ValueKey<String> &&
              key.value.startsWith('channel-') &&
              key.value.contains(':');
        })
        .evaluate()
        .length;

    expect(fullyVisibleRows, 5);
    expect(programCells, inInclusiveRange(40, 160));
    expect(loadedChannelIds.length, lessThan(20));
    expect(loadedChannelIds.toSet().length, loadedChannelIds.length);
    expect(loadedChannelIds, isNot(contains('channel-999')));
    expect(guide.cachedRowCount, loadedChannelIds.length);
    expect(guide.cachedRowCount, lessThanOrEqualTo(64));
    expect(guide.activeLoadCount, 0);
    expect(lineup.artworkLoads, 0);
    for (final channelId in loadedChannelIds) {
      expect(guide.row(channelId).programs.length, inInclusiveRange(8, 10));
    }

    final initialProgram = guide.focusedProgramId;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(guide.focusedProgramId, isNot(initialProgram));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(guide.focusedChannelId, 'channel-1');
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(guide.focusedChannelId, 'channel-6');
    expect(loadedChannelIds.length, lessThan(30));
    expect(guide.cachedRowCount, lessThanOrEqualTo(64));
    expect(find.text('Channel 999'), findsNothing);

    debugPrint(
      'GUIDE_PROFILE channels=1000 hours=4 rows=$fullyVisibleRows '
      'firstViewportUs=${firstViewport.elapsedMicroseconds} '
      'widgets=${tester.allWidgets.length} programCells=$programCells '
      'scheduleLoads=${loadedChannelIds.length} cachedRows=${guide.cachedRowCount}',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('loading, error, retry, and program semantics stay visible', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 1, 1, 12, 45);
    final lineup = _Lineup(1);
    addTearDown(lineup.dispose);
    lineup.channels = [
      Channel(
        id: 'semantic-channel',
        number: 1,
        name: 'Semantic Channel',
        source: const ManualSource([
          ChannelItem(
            id: 'ended-program',
            title: 'Ended Program',
            duration: Duration(minutes: 10),
          ),
          ChannelItem(
            id: 'current-program',
            title: 'Current Program',
            duration: Duration(minutes: 30),
          ),
          ChannelItem(
            id: 'upcoming-program',
            title: 'Upcoming Program',
            duration: Duration(hours: 4),
          ),
        ]),
        playbackMode: PlaybackMode.sequential,
        anchor: DateTime.utc(2026, 1, 1, 12, 30),
        shuffleSeed: 1,
      ),
    ];
    lineup.currentChannelId = 'semantic-channel';
    var fail = true;
    var tunes = 0;
    final guide = GuideController(
      lineup: lineup,
      clock: () => now,
      loadSchedule: (channel) async {
        if (fail) throw StateError('offline');
        return _schedule(channel);
      },
    );
    addTearDown(guide.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: LineupCanvas.builder,
        home: GuideView(
          controller: guide,
          onClose: () {},
          watchingChannelId: lineup.currentChannelId,
          onTune: (_) async => tunes++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Schedules couldn't load"), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    final current = guide.currentProgram('semantic-channel')!;
    final startLabel = _testTime(current.scheduled.start.toLocal());
    final endLabel = _testTime(current.scheduled.end.toLocal());
    expect(find.textContaining('$startLabel–$endLabel'), findsWidgets);
    expect(
      find.bySemanticsLabel(
        'Current Program, $startLabel to $endLabel, currently airing',
      ),
      findsOneWidget,
    );
    final currentCell = find.bySemanticsLabel(
      'Current Program, $startLabel to $endLabel, currently airing',
    );
    expect(
      find.descendant(
        of: currentCell,
        matching: find.byType(FractionallySizedBox),
      ),
      findsNothing,
    );
    expect(find.bySemanticsLabel('Current time'), findsOneWidget);
    final rawStartLabel = _testTime(current.scheduled.start);
    if (rawStartLabel != startLabel) {
      expect(find.textContaining(rawStartLabel), findsNothing);
    }

    final channelRail = find.bySemanticsLabel(
      RegExp(r'^Channel 1, Semantic Channel, now watching'),
    );
    expect(channelRail, findsOneWidget);
    final channelSemantics = tester
        .getSemantics(channelRail)
        .getSemanticsData();
    expect(channelSemantics.flagsCollection.isButton, isTrue);
    expect(channelSemantics.hasAction(SemanticsAction.tap), isTrue);
    expect(find.bySemanticsLabel(RegExp(r'^Now watching$')), findsNothing);

    final upcomingCell = find.bySemanticsLabel(
      RegExp(r'^Upcoming Program, .+, upcoming$'),
    );
    expect(upcomingCell, findsOneWidget);
    await tester.tap(upcomingCell);
    await tester.pump(const Duration(milliseconds: 400));
    expect(guide.focusedProgramId, isNot(current.id));
    for (final key in [
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.select,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }
    await tester.tap(upcomingCell);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(upcomingCell);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tunes, 0);
    await tester.tap(channelRail);
    await tester.pump();
    expect(guide.focusedProgramId, current.id);

    for (final status in ['currently airing', 'ended', 'upcoming']) {
      final programs = find.bySemanticsLabel(RegExp(status));
      expect(programs, findsOneWidget);
      final program = programs.first;
      final semantics = tester.getSemantics(program).getSemanticsData();
      expect(semantics.flagsCollection.isButton, isTrue);
      expect(semantics.hasAction(SemanticsAction.tap), isTrue);
    }

    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
    lineup.dispose();
  });

  testWidgets('responsive PiP geometry and Guide focus remain coherent', (
    tester,
  ) async {
    final lineup = _Lineup(20);
    addTearDown(lineup.dispose);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    addTearDown(guide.dispose);
    final tallGeometry = <double, (double, double, double)>{};
    var tunes = 0;
    var closes = 0;

    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in const [
      Size(800, 600),
      Size(1920, 719),
      Size(1280, 720),
      Size(800, 720),
      Size(600, 720),
      Size(1360, 840),
      Size(1920, 899),
      Size(1600, 900),
      Size(1920, 1079),
      Size(1920, 1080),
      Size(1920, 1200),
      Size(2560, 1440),
      Size(3840, 2160),
    ]) {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          builder: LineupCanvas.builder,
          home: GuideView(
            controller: guide,
            pictureInPicture: const ColoredBox(color: Colors.black),
            onOpenPlayer: () {},
            onClose: () => closes++,
            onTune: (_) async => tunes++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final picture = find.byKey(const Key('guide-picture-in-picture'));
      expect(picture, findsOneWidget);
      expect(
        find.byKey(const Key('guide-picture-corner-mask')),
        findsOneWidget,
      );
      final pictureSize = _drawnSize(tester, picture);
      expect(
        pictureSize.width / pictureSize.height,
        closeTo(16 / 9, 0.001),
        reason: '$size',
      );
      final policy = GuideLayoutPolicy.forSize(
        size / LineupCanvas.scaleFor(size),
        hasPicture: true,
      );
      expect(
        pictureSize.width,
        closeTo(policy.pictureWidth * LineupCanvas.scaleFor(size), 1),
        reason: '$size',
      );
      final list = tester.widget<ListView>(
        find.byKey(const Key('guide-schedule-list')),
      );
      if (size.width == 1920 && (size.height == 1080 || size.height == 1200)) {
        tallGeometry[size.height] = (
          list.itemExtent!,
          pictureSize.width,
          _drawnSize(
            tester,
            find.byKey(const Key('guide-information-area')),
          ).height,
        );
      }
      final scheduleHeight = tester
          .getSize(find.byKey(const Key('guide-schedule-list')))
          .height;
      final standardFiveRowSize =
          size == const Size(1280, 720) ||
          size == const Size(1920, 1080) ||
          size == const Size(2560, 1440) ||
          size == const Size(3840, 2160);
      expect(
        ((scheduleHeight + 0.000001) / list.itemExtent!).floor(),
        greaterThanOrEqualTo(standardFiveRowSize ? 5 : 3),
        reason: '$size',
      );
      expect(
        tester.widget<Material>(find.byKey(const Key('classic-guide'))).color,
        Colors.transparent,
      );
      expect(tester.takeException(), isNull, reason: '$size');
    }

    expect(tallGeometry[1200]!.$1, tallGeometry[1080]!.$1);
    expect(tallGeometry[1200]!.$2, tallGeometry[1080]!.$2);
    expect(tallGeometry[1200]!.$3 - tallGeometry[1080]!.$3, closeTo(120, .001));
    final pictureSemantics = find.bySemanticsLabel(
      'Now playing picture in picture. Open full player.',
    );
    expect(pictureSemantics, findsOneWidget);
    final semantics = tester.getSemantics(pictureSemantics).getSemanticsData();
    expect(semantics.flagsCollection.isButton, isTrue);
    expect(semantics.hasAction(SemanticsAction.tap), isTrue);

    expect(guide.focusedProgram, isNotNull);
    expect(guide.selectedProgram, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(guide.selectedProgramId, guide.focusedProgramId);
    expect(tunes, 1);

    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 720);
    await tester.pumpWidget(
      MaterialApp(
        builder: LineupCanvas.builder,
        home: GuideView(
          controller: guide,
          onClose: () => closes++,
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final classicList = tester.widget<ListView>(
      find.byKey(const Key('guide-schedule-list')),
    );
    expect(
      (_drawnSize(tester, find.byKey(const Key('guide-schedule-list'))).height /
                  (classicList.itemExtent! * .8) +
              0.000001)
          .floor(),
      greaterThanOrEqualTo(5),
      reason:
          'height=${_drawnSize(tester, find.byKey(const Key('guide-schedule-list'))).height} row=${classicList.itemExtent}',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    expect(closes, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
    lineup.dispose();
  });

  testWidgets('Guide details project Plex metadata and artwork color', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1600, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final lineup = _Lineup(1, artworkBytes: _tinyPng);
    addTearDown(lineup.dispose);
    lineup.channels = [
      Channel(
        id: 'channel',
        number: 7,
        name: 'Drama Seven',
        source: ManualSource([
          ChannelItem(
            id: 'episode',
            title: 'The Arrival',
            duration: const Duration(hours: 24),
            showTitle: 'Signal House',
            poster: Uri(path: '/poster'),
            summary: 'A mysterious signal changes the course of the mission.',
            contentRating: 'TV-14',
            genres: const ['Drama', 'Science Fiction'],
            year: 2026,
            seasonNumber: 1,
            episodeNumber: 2,
            resolution: '4k',
            videoCodec: 'hevc',
            audioCodec: 'eac3',
            audioChannels: 6,
            dynamicRange: 'hdr10',
          ),
        ]),
        playbackMode: PlaybackMode.sequential,
        anchor: DateTime.now().subtract(const Duration(hours: 1)),
        shuffleSeed: 7,
      ),
    ];
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    addTearDown(guide.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.25)),
          child: LineupCanvas(child: child!),
        ),
        home: GuideView(
          controller: guide,
          pictureInPicture: const ColoredBox(color: Colors.black),
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Signal House'), findsWidgets);
    expect(find.text('S01E02'), findsWidgets);
    expect(_detailsMetadata(tester), contains('2026'));
    expect(_detailsMetadata(tester), contains('Drama · Science Fiction'));
    for (final badge in ['TV-14', '4K', 'HDR10', 'EAC3', '5.1']) {
      expect(find.textContaining(badge), findsOneWidget);
    }
    expect(
      find.text('A mysterious signal changes the course of the mission.'),
      findsOneWidget,
    );
    expect(lineup.artworkLoads, 1);
    expect(tester.takeException(), isNull);
    final background = tester.widget<AnimatedContainer>(
      find.byKey(const Key('guide-info-dynamic-background')),
    );
    final gradient = (background.decoration! as BoxDecoration).gradient!;
    final roles = LineupTheme.of(
      tester.element(find.byKey(const Key('guide-info-dynamic-background'))),
    );
    expect(
      (gradient as RadialGradient).colors.first,
      isNot(
        Color.alphaBlend(
          roles.progressFill.withValues(alpha: 0.48),
          roles.primarySurface,
        ),
      ),
    );
  });

  testWidgets(
    'Guide details keep loading, retry, and error scoped to focused channel',
    (tester) async {
      final now = DateTime.utc(2026, 1, 1, 12, 30);
      final lineup = _Lineup(2, artworkBytes: _tinyPng)
        ..settings = const LineupSettings(
          guideHours: 4,
          reduceMotion: true,
          guideInfoBackgroundMode: GuideInfoBackgroundMode.artwork,
        );
      lineup.channels = [
        Channel(
          id: 'channel-a',
          number: 1,
          name: 'Channel A',
          source: ManualSource([
            ChannelItem(
              id: 'program-a',
              title: 'Program A',
              duration: const Duration(hours: 24),
              poster: Uri.parse('/poster-a'),
              backdrop: Uri.parse('/backdrop-a'),
            ),
          ]),
          playbackMode: PlaybackMode.sequential,
          anchor: now,
          shuffleSeed: 1,
        ),
        Channel(
          id: 'channel-b',
          number: 2,
          name: 'Channel B',
          source: const ManualSource([
            ChannelItem(
              id: 'program-b',
              title: 'Program B',
              duration: Duration(hours: 24),
            ),
          ]),
          playbackMode: PlaybackMode.sequential,
          anchor: now,
          shuffleSeed: 2,
        ),
      ];
      lineup.currentChannelId = 'channel-a';
      addTearDown(lineup.dispose);
      final firstLoad = Completer<ScheduleIndex>();
      final retryLoad = Completer<ScheduleIndex>();
      var channelBAttempts = 0;
      final guide = GuideController(
        lineup: lineup,
        clock: () => now,
        loadSchedule: (channel) {
          if (channel.id == 'channel-a') {
            return Future.value(_schedule(channel));
          }
          channelBAttempts++;
          return channelBAttempts == 1 ? firstLoad.future : retryLoad.future;
        },
      );
      addTearDown(guide.dispose);

      await tester.pumpWidget(
        MaterialApp(
          builder: LineupCanvas.builder,
          home: GuideView(
            controller: guide,
            onClose: () {},
            onTune: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      guide.selectProgram(guide.row('channel-a').programs.first);
      await tester.pumpAndSettle();
      final details = find.byKey(const Key('guide-info-dynamic-background'));
      Finder detailText(String value) =>
          find.descendant(of: details, matching: find.text(value));
      expect(detailText('Program A'), findsOneWidget);
      expect(
        find.descendant(
          of: details,
          matching: find.byKey(const Key('guide-info-backdrop')),
        ),
        findsOneWidget,
      );

      guide.moveVertical(1);
      await tester.pump();
      expect(find.text('2 • Channel B'), findsOneWidget);
      expect(find.text('Loading schedule…'), findsWidgets);
      expect(
        find.descendant(
          of: details,
          matching: find.byKey(const Key('guide-info-backdrop')),
        ),
        findsNothing,
      );

      firstLoad.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('2 • Channel B'), findsOneWidget);
      expect(find.text('Schedule unavailable'), findsWidgets);
      expect(detailText('Program A'), findsNothing);
      expect(lineup.currentChannelId, 'channel-a');

      await guide.retry('channel-b');
      await tester.pump();
      expect(find.text('2 • Channel B'), findsOneWidget);
      expect(find.text('Retrying…'), findsWidgets);
      expect(detailText('Program A'), findsNothing);

      retryLoad.completeError(StateError('still offline'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Guide details identify a focused ready row with no programs', (
    tester,
  ) async {
    final lineup = _Lineup(2)
      ..settings = const LineupSettings(guideHours: 0, reduceMotion: true);
    addTearDown(lineup.dispose);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    addTearDown(guide.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: LineupCanvas.builder,
        home: GuideView(
          controller: guide,
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    guide.moveVertical(1);
    await tester.pump();

    expect(guide.row('channel-1').state, GuideLoadState.ready);
    expect(find.text('2 • Channel 1'), findsOneWidget);
    expect(find.text('No programs scheduled in this time range'), findsWidgets);
  });

  testWidgets('PiP information color loads artwork only from source metadata', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final lineup = _Lineup(2);
    addTearDown(lineup.dispose);
    lineup.channels = [
      Channel(
        id: 'without-artwork',
        number: 1,
        name: 'Home Video',
        source: const ManualSource([
          ChannelItem(
            id: 'without-artwork-item',
            title: 'Family Movie',
            duration: Duration(hours: 24),
          ),
        ]),
        playbackMode: PlaybackMode.sequential,
        anchor: DateTime.now().subtract(const Duration(hours: 1)),
        shuffleSeed: 1,
      ),
      Channel(
        id: 'with-artwork',
        number: 2,
        name: 'Plex Movie',
        source: ManualSource([
          ChannelItem(
            id: 'with-artwork-item',
            title: 'Catalog Movie',
            duration: const Duration(hours: 24),
            poster: Uri.parse('/poster-that-fails'),
          ),
        ]),
        playbackMode: PlaybackMode.sequential,
        anchor: DateTime.now().subtract(const Duration(hours: 1)),
        shuffleSeed: 2,
      ),
    ];
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    addTearDown(guide.dispose);

    for (final size in const [
      Size(800, 600),
      Size(1280, 720),
      Size(1920, 1080),
    ]) {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          builder: LineupCanvas.builder,
          home: GuideView(
            controller: guide,
            pictureInPicture: const SizedBox.expand(),
            onClose: () {},
            onTune: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(guide.focusedChannelId, 'without-artwork');
      expect(tester.takeException(), isNull, reason: '$size');
    }
    expect(lineup.artworkLoads, 0);

    guide.moveVertical(1);
    await tester.pump();

    expect(guide.focusedChannelId, 'with-artwork');
    await tester.pumpAndSettle();
    expect(lineup.artworkLoads, 1);
  });

  testWidgets('Guide omits incomplete episode coordinates', (tester) async {
    final lineup = _Lineup(1);
    addTearDown(lineup.dispose);
    lineup.channels = [
      for (final (index, item) in [
        const ChannelItem(
          id: 'season-only',
          title: 'Season only',
          showTitle: 'Incomplete Show',
          duration: Duration(hours: 24),
          seasonNumber: 1,
        ),
        const ChannelItem(
          id: 'episode-only',
          title: 'Episode only',
          showTitle: 'Incomplete Show',
          duration: Duration(hours: 24),
          episodeNumber: 2,
        ),
      ].indexed)
        Channel(
          id: 'channel-$index',
          number: index + 1,
          name: 'Channel $index',
          source: ManualSource([item]),
          playbackMode: PlaybackMode.sequential,
          anchor: DateTime.now().subtract(const Duration(hours: 1)),
          shuffleSeed: index + 1,
        ),
    ];
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    addTearDown(guide.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: LineupCanvas.builder,
        home: GuideView(
          controller: guide,
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('S01E00'), findsNothing);
    guide.moveVertical(1);
    await tester.pumpAndSettle();
    expect(find.text('S00E02'), findsNothing);
  });

  testWidgets('Guide artwork mode renders backdrop and preferred clear logo', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1600, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final lineup = _Lineup(1, artworkBytes: _wideLogoPng)
      ..settings = const LineupSettings(
        guideInfoBackgroundMode: GuideInfoBackgroundMode.artwork,
      );
    addTearDown(lineup.dispose);
    lineup.channels = [
      Channel(
        id: 'channel',
        number: 7,
        name: 'Drama Seven',
        source: ManualSource([
          ChannelItem(
            id: 'episode',
            title: 'The Arrival',
            showTitle: 'Signal House',
            duration: const Duration(hours: 24),
            showThumb: '/poster',
            backdrop: Uri.parse('/backdrop'),
            clearLogo: Uri.parse('/clear-logo'),
          ),
        ]),
        playbackMode: PlaybackMode.sequential,
        anchor: DateTime.now().subtract(const Duration(hours: 1)),
        shuffleSeed: 7,
      ),
    ];
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    addTearDown(guide.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: LineupCanvas.builder,
        home: GuideView(
          controller: guide,
          pictureInPicture: const ColoredBox(color: Colors.black),
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.runAsync(
      () => precacheImage(
        MemoryImage(_wideLogoPng),
        tester.element(find.byType(GuideView)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('guide-info-backdrop')), findsOneWidget);
    expect(find.byKey(const Key('guide-clear-logo')), findsOneWidget);
    expect(find.bySemanticsLabel('Signal House logo'), findsOneWidget);
    expect(lineup.artworkLoads, 3);
    final background = tester.widget<AnimatedContainer>(
      find.byKey(const Key('guide-info-dynamic-background')),
    );
    expect(
      (background.decoration! as BoxDecoration).gradient,
      isA<LinearGradient>(),
    );
  });

  for (final (description, bytes) in [
    ('invalid clear-logo bytes', Uint8List.fromList(const [1, 2, 3])),
    ('decoded narrow clear-logo', _narrowLogoPng),
  ]) {
    testWidgets('$description retains the textual title', (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1600, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final lineup = _Lineup(1, artworkBytes: bytes);
      addTearDown(lineup.dispose);
      lineup.channels = [
        Channel(
          id: 'channel',
          number: 7,
          name: 'Drama Seven',
          source: ManualSource([
            ChannelItem(
              id: 'episode',
              title: 'The Arrival',
              showTitle: 'Signal House',
              duration: const Duration(hours: 24),
              poster: Uri.parse('/poster'),
              clearLogo: Uri.parse('/clear-logo'),
            ),
          ]),
          playbackMode: PlaybackMode.sequential,
          anchor: DateTime.now().subtract(const Duration(hours: 1)),
          shuffleSeed: 7,
        ),
      ];
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      addTearDown(guide.dispose);

      await tester.pumpWidget(
        MaterialApp(
          builder: LineupCanvas.builder,
          home: GuideView(
            controller: guide,
            pictureInPicture: const ColoredBox(color: Colors.black),
            onClose: () {},
            onTune: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      if (bytes == _narrowLogoPng) {
        await tester.runAsync(
          () => precacheImage(
            MemoryImage(bytes),
            tester.element(find.byType(GuideView)),
          ),
        );
        await tester.pumpAndSettle();
      }

      expect(find.byKey(const Key('guide-clear-logo')), findsNothing);
      expect(
        find.byKey(const Key('guide-clear-logo-fallback')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('guide-clear-logo-fallback')))
            .data,
        'Signal House',
      );
    });
  }

  testWidgets('physical 4K at DPR 2 uses the 1080p Guide row budget', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 2
      ..physicalSize = const Size(3840, 2160);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final lineup = _Lineup(20);
    addTearDown(lineup.dispose);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    addTearDown(guide.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: LineupCanvas.builder,
        home: GuideView(
          controller: guide,
          pictureInPicture: const ColoredBox(color: Colors.black),
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      MediaQuery.sizeOf(tester.element(find.byType(GuideView))),
      const Size(1920, 1080),
    );
    expect(
      _drawnSize(
        tester,
        find.byKey(const Key('guide-picture-in-picture')),
      ).width,
      closeTo(576, 0.01),
    );
    final list = tester.widget<ListView>(
      find.byKey(const Key('guide-schedule-list')),
    );
    expect(
      (_drawnSize(tester, find.byKey(const Key('guide-schedule-list'))).height /
              list.itemExtent!)
          .floor(),
      greaterThanOrEqualTo(5),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
    lineup.dispose();
  });

  testWidgets('schedule loading labels are not repeated as live regions', (
    tester,
  ) async {
    final lineup = _Lineup(1);
    addTearDown(lineup.dispose);
    final pending = Completer<ScheduleIndex>();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (_) => pending.future,
    );
    addTearDown(guide.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: LineupCanvas.builder,
        home: GuideView(
          controller: guide,
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pump();

    final status = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.label == 'Loading schedule…',
    );
    expect(status, findsOneWidget);
    expect(tester.widget<Semantics>(status).properties.liveRegion, isNot(true));

    pending.complete(_schedule(lineup.channels.single));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ultrawide long programs cover and tune from the timeline edge', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(3440, 1440);
    addTearDown(tester.view.reset);
    final now = DateTime(2026, 8, 13, 12, 47);
    final lineup = _Lineup(2, anchor: now.subtract(const Duration(hours: 1)));
    final guide = GuideController(
      lineup: lineup,
      clock: () => now,
      loadSchedule: (channel) async => _schedule(channel),
    );
    addTearDown(guide.dispose);
    addTearDown(lineup.dispose);
    final tunes = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        builder: LineupCanvas.builder,
        home: GuideView(
          controller: guide,
          onClose: () {},
          onTune: (id) async => tunes.add(id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final program = guide.row('channel-0').programs.single;
    final cell = find.byKey(ValueKey(program.id));
    final cellRect = _drawnRect(tester, cell);
    final listRect = _drawnRect(
      tester,
      find.byKey(const Key('guide-schedule-list')),
    );
    expect(tester.getSize(cell).width, greaterThan(2000));
    expect(cellRect.right, closeTo(listRect.right, .01));
    guide.moveVertical(1);
    await tester.pumpAndSettle();
    final edge = Offset(listRect.right - 20, cellRect.center.dy);
    await tester.tapAt(edge);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(guide.focusedProgramId, program.id);
    await tester.tapAt(edge);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(edge);
    await tester.pumpAndSettle();
    expect(tunes, ['channel-0']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final (restoredHours, message) in [
    (1, "Couldn't change visible hours. Still showing 1 hour."),
    (2, "Couldn't change visible hours. Still showing 2 hours."),
    (3, "Couldn't change visible hours. Still showing 3 hours."),
  ]) {
    testWidgets(
      'Guide hours failure retains $restoredHours hours and Retry saves the choice',
      (tester) async {
        final store = _RetryStore();
        final lineup = _Lineup(1, store: store)
          ..settings = LineupSettings(guideHours: restoredHours);
        store.saved = PersistedState(settings: lineup.settings);
        final guide = GuideController(
          lineup: lineup,
          loadSchedule: (channel) async => _schedule(channel),
        );
        addTearDown(guide.dispose);
        addTearDown(lineup.dispose);
        await tester.pumpWidget(
          MaterialApp(
            builder: LineupCanvas.builder,
            theme: LineupTheme.forName(LineupThemeName.emberSteel),
            home: Scaffold(
              body: GuideView(
                controller: guide,
                onClose: () {},
                onTune: (_) async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('guide-hours')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('4 hours').last);
        await tester.pumpAndSettle();
        expect(find.text(message), findsOneWidget);
        final feedback = tester.widget<SnackBar>(find.byType(SnackBar));
        final roles = LineupTheme.of(tester.element(find.byType(SnackBar)));
        expect(feedback.backgroundColor, roles.elevatedSurface);
        expect(feedback.elevation, 0);
        expect(feedback.action!.textColor, roles.primaryText);
        expect(guide.guideHours, restoredHours);
        expect(lineup.settings.guideHours, restoredHours);
        expect(store.saved.settings.guideHours, restoredHours);
        expect(store.attempts, 1);
        store.fail = false;
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(guide.guideHours, 4);
        expect(lineup.settings.guideHours, 4);
        expect(store.saved.settings.guideHours, 4);
        expect(store.attempts, 2);
        expect(find.text(message), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final size in [const Size(1920, 1080), const Size(960, 720)]) {
    testWidgets('hours feedback paints above the grid and Now line at $size', (
      tester,
    ) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = size;
      addTearDown(tester.view.reset);
      final now = DateTime(2026, 8, 13, 12, 47);
      final lineup = _Lineup(
        20,
        store: _RetryStore(),
        anchor: now.subtract(const Duration(hours: 1)),
      );
      final guide = GuideController(
        lineup: lineup,
        clock: () => now,
        loadSchedule: (channel) async => _schedule(channel),
      );
      addTearDown(guide.dispose);
      addTearDown(lineup.dispose);
      const boundaryKey = Key('feedback-paint-boundary');
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            theme: LineupTheme.forName(LineupThemeName.emberSteel),
            builder: LineupCanvas.builder,
            home: GuideView(
              controller: guide,
              onClose: () {},
              onTune: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('guide-hours')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4 hours').last);
      await tester.pumpAndSettle();
      final feedback = find.byType(SnackBar);
      final roles = LineupTheme.of(tester.element(feedback));
      final material = find.descendant(
        of: feedback,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Material && widget.color == roles.elevatedSurface,
        ),
      );
      final bannerRect = _drawnRect(tester, material);
      final lineRect = _drawnRect(
        tester,
        find.byKey(const Key('guide-now-line')),
      );
      final gridRect = _drawnRect(
        tester,
        find.byKey(const Key('guide-schedule-list')),
      );
      final crossing = Offset(lineRect.center.dx, bannerRect.top + 4);
      final gridCovered = Offset(bannerRect.right - 100, bannerRect.top + 4);
      expect(bannerRect.contains(crossing), isTrue);
      expect(lineRect.contains(crossing), isTrue);
      expect(gridRect.contains(gridCovered), isTrue);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final argb = roles.elevatedSurface.toARGB32();
        final expected = [
          (argb >> 16) & 255,
          (argb >> 8) & 255,
          argb & 255,
          255,
        ];
        for (final point in [crossing, gridCovered]) {
          final index = (point.dy.floor() * image.width + point.dx.floor()) * 4;
          expect(
            List.generate(4, (i) => bytes.getUint8(index + i)),
            expected,
            reason: 'The opaque banner must paint over the grid and Now line',
          );
        }
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final pending in [false, true]) {
    testWidgets(
      'Guide hours feedback leaves with its route (pending=$pending)',
      (tester) async {
        final store = _RetryStore();
        if (pending) store.saveGate = Completer<void>();
        final lineup = _Lineup(1, store: store);
        final guide = GuideController(
          lineup: lineup,
          loadSchedule: (channel) async => _schedule(channel),
        );
        addTearDown(guide.dispose);
        addTearDown(lineup.dispose);
        final showGuide = ValueNotifier(true);
        addTearDown(showGuide.dispose);
        final shellMessenger = GlobalKey<ScaffoldMessengerState>();
        await tester.pumpWidget(
          MaterialApp(
            scaffoldMessengerKey: shellMessenger,
            builder: LineupCanvas.builder,
            theme: LineupTheme.forName(LineupThemeName.emberSteel),
            home: Scaffold(
              body: ValueListenableBuilder<bool>(
                valueListenable: showGuide,
                builder: (_, visible, _) => visible
                    ? GuideView(
                        controller: guide,
                        onClose: () {},
                        onTune: (_) async {},
                      )
                    : const Center(child: Text('Other route')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('guide-hours')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('4 hours').last);
        await tester.pumpAndSettle();
        expect(
          find.text("Couldn't change visible hours. Still showing 2 hours."),
          pending ? findsNothing : findsOneWidget,
        );
        showGuide.value = false;
        await tester.pumpAndSettle();
        store.saveGate?.complete();
        await tester.pumpAndSettle();
        expect(find.text('Other route'), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
        expect(guide.guideHours, 2);
        expect(tester.takeException(), isNull);
        // The persistent shell messenger still works after the Guide scope leaves.
        shellMessenger.currentState!.showSnackBar(
          const SnackBar(content: Text('Shell feedback')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Shell feedback'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('search owns Escape and Enter focus without tuning', (
    tester,
  ) async {
    final lineup = _Lineup(3);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    var closes = 0;
    var tunes = 0;
    var appChords = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: LineupCanvas.builder,
        home: Focus(
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                HardwareKeyboard.instance.isControlPressed &&
                [
                  LogicalKeyboardKey.keyG,
                  LogicalKeyboardKey.keyP,
                ].contains(event.logicalKey)) {
              appChords++;
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: GuideView(
            controller: guide,
            onClose: () => closes++,
            onTune: (_) async => tunes++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final search = find.byKey(const Key('guide-channel-search'));
    expect(find.byTooltip('Clear search'), findsNothing);
    await tester.tap(search);
    guide.moveWindow(2);
    final browsedStart = guide.windowStart;
    final inspected = guide.focusedProgramId;
    for (final key in [LogicalKeyboardKey.keyG, LogicalKeyboardKey.keyP]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(closes, 0);
      expect(guide.windowStart, browsedStart);
      expect(guide.focusedProgramId, inspected);
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    }
    expect(appChords, 2);

    await tester.enterText(search, '   ');
    await tester.pump();
    expect(guide.searchQuery, isEmpty);
    expect(find.byTooltip('Clear search'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(find.byTooltip('Clear search'), findsNothing);

    guide.setSearchQuery('CHANNEL 1');
    await tester.pump();
    final searchValue = tester.widget<TextField>(search).controller!.value;
    expect(searchValue.text, 'channel 1');
    expect(searchValue.selection, const TextSelection.collapsed(offset: 9));

    await tester.enterText(search, 'Channel 2');
    await tester.pump();
    expect(guide.channels.single.id, 'channel-2');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tester.widget<TextField>(search).focusNode!.hasFocus, isFalse);
    expect(tunes, 0);
    await tester.tap(search);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(guide.searchQuery, isEmpty);
    expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
    expect(closes, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(tester.widget<TextField>(search).focusNode!.hasFocus, isFalse);
    expect(tunes, 0);
    expect(closes, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    expect(guide.windowStart, isNot(browsedStart));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    expect(closes, 1);
    guide.dispose();
    lineup.dispose();
  });

  testWidgets(
    'timeline controls expose one aligned marker and 30-minute steps',
    (tester) async {
      final localMidnight = DateTime(2026, 1, 2);
      var now = localMidnight.toUtc().subtract(const Duration(minutes: 30));
      final lineup = _Lineup(2, anchor: now.subtract(const Duration(hours: 1)));
      final guide = GuideController(
        lineup: lineup,
        clock: () => now,
        loadSchedule: (channel) async => _schedule(channel),
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: LineupCanvas.builder,
          theme: LineupTheme.forName(LineupThemeName.emberSteel),
          home: GuideView(
            controller: guide,
            onClose: () {},
            onTune: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      Finder marker() => find.byKey(const Key('guide-now-line'));
      Finder focusedCell() => find.byKey(ValueKey(guide.focusedProgram!.id));

      expect(tester.takeException(), isNull);
      expect(marker(), findsOneWidget);
      expect(find.byKey(const Key('guide-midnight-date')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('guide-midnight-date'))).data,
        MaterialLocalizations.of(
          tester.element(find.byKey(const Key('guide-midnight-date'))),
        ).formatMediumDate(localMidnight),
      );
      expect(find.bySemanticsLabel('Current time'), findsOneWidget);
      expect(
        find.ancestor(
          of: marker(),
          matching: find.byWidgetPredicate(
            (widget) => widget is IgnorePointer && widget.ignoring,
          ),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(marker()).dx,
        closeTo(tester.getTopLeft(focusedCell()).dx, 0.01),
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('guide-earlier')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('guide-later')));
      await tester.pump();
      expect(guide.windowStart, localMidnight.toUtc());
      expect(find.byKey(const Key('guide-midnight-date')), findsOneWidget);
      await tester.tap(find.byKey(const Key('guide-earlier')));
      await tester.pump();
      expect(
        guide.windowStart,
        localMidnight.toUtc().subtract(const Duration(minutes: 30)),
      );

      guide.moveWindow(2);
      now = guide.windowStart.add(const Duration(hours: 1));
      await tester.pumpWidget(
        MaterialApp(
          builder: LineupCanvas.builder,
          theme: LineupTheme.forName(LineupThemeName.emberSteel),
          home: GuideView(
            controller: guide,
            onClose: () {},
            onTune: (_) async {},
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getTopLeft(marker()).dx,
        closeTo(
          tester.getTopLeft(focusedCell()).dx +
              _drawnSize(tester, focusedCell()).width / 2,
          0.01,
        ),
      );

      guide.moveWindow(4);
      await tester.pump();
      expect(marker(), findsNothing);

      guide.dispose();
      lineup.dispose();
    },
  );

  testWidgets('removing a wrapping library label preserves channel search', (
    tester,
  ) async {
    const libraryId =
        'International television documentaries and limited series archive';
    final lineup = _Lineup(2);
    lineup.channels = [
      Channel(
        id: 'library-channel',
        number: 17,
        name: 'Library Channel',
        source: const LibrarySource(
          libraryId: libraryId,
          libraryType: PlexLibraryType.show,
        ),
        playbackMode: PlaybackMode.sequential,
        anchor: DateTime.now(),
        shuffleSeed: 1,
      ),
      lineup.channels.last,
    ];
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: LineupCanvas.builder,
        home: GuideView(
          controller: guide,
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('guide-channel-search')),
      'Library',
    );
    guide.setLibraryFilter(libraryId);
    await tester.pump();

    final label = find.byKey(const Key('guide-active-library-label'));
    expect(label, findsOneWidget);
    expect(find.text('Libraries'), findsOneWidget);
    expect(tester.widget<Text>(label).data, libraryId);
    expect(_drawnSize(tester, label).height, greaterThan(16));
    await tester.tap(find.byTooltip('Remove library filter'));
    await tester.pump();
    expect(guide.libraryFilterId, isNull);
    expect(guide.searchQuery, 'library');

    guide.dispose();
    lineup.dispose();
  });

  testWidgets(
    'standard resolutions and enlarged text do not clip Guide controls',
    (tester) async {
      final lineup = _Lineup(20)
        ..settings = const LineupSettings(reduceMotion: true);
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
      );
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1280, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final size in const [
        Size(1280, 720),
        Size(1920, 1080),
        Size(2560, 1440),
        Size(3840, 2160),
      ]) {
        tester.view
          ..devicePixelRatio = 1
          ..physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: LineupCanvas(child: child!),
            ),
            home: GuideView(
              controller: guide,
              pictureInPicture: const ColoredBox(color: Colors.black),
              onClose: () {},
              onTune: (_) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('guide-channel-search')), findsOneWidget);
        expect(find.byKey(const Key('guide-hours')), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '$size');
      }
      guide.dispose();
      lineup.dispose();
    },
  );

  testWidgets('Now Playing context remains stable while Guide focus moves', (
    tester,
  ) async {
    final lineup = _Lineup(2)..currentChannelId = 'channel-0';
    addTearDown(lineup.dispose);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    )..requestViewport(0, 2);
    addTearDown(guide.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: LineupCanvas.builder,
        home: GuideView(
          controller: guide,
          watchingChannelId: lineup.currentChannelId,
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final context = find.byKey(const Key('guide-now-playing-context'));
    expect(context, findsOneWidget);
    expect(tester.widget<Text>(context).data, contains('Channel 0'));

    guide.moveVertical(1);
    await tester.pump();
    expect(guide.focusedChannelId, 'channel-1');
    expect(tester.widget<Text>(context).data, contains('Channel 0'));

    // Remembering a channel is not evidence of current playback.
    await tester.pumpWidget(
      MaterialApp(
        builder: LineupCanvas.builder,
        home: GuideView(
          controller: guide,
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('guide-now-playing-context')), findsNothing);
    expect(find.text('Watching'), findsNothing);
    expect(lineup.currentChannelId, 'channel-0');

    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
    lineup.dispose();
  });

  testWidgets('Now Playing context setting updates its Guide consumer', (
    tester,
  ) async {
    final lineup = _Lineup(2)..currentChannelId = 'channel-0';
    addTearDown(lineup.dispose);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    addTearDown(guide.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: LineupCanvas.builder,
        home: GuideView(
          controller: guide,
          watchingChannelId: lineup.currentChannelId,
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide-now-playing-context')), findsOneWidget);

    lineup.settings = lineup.settings.copyWith(nowWatchingBanner: false);
    lineup.notifyListeners();
    await tester.pump();
    expect(find.byKey(const Key('guide-now-playing-context')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
    lineup.dispose();
  });

  testWidgets('vertical Guide position survives route disposal and return', (
    tester,
  ) async {
    final lineup = _Lineup(100);
    addTearDown(lineup.dispose);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    addTearDown(guide.dispose);
    Widget buildGuide() => MaterialApp(
      builder: LineupCanvas.builder,
      home: GuideView(controller: guide, onClose: () {}, onTune: (_) async {}),
    );

    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(buildGuide());
    await tester.pumpAndSettle();
    const scheduleList = Key('guide-schedule-list');
    final initialScrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(scheduleList),
        matching: find.byType(Scrollable),
      ),
    );
    initialScrollable.position.jumpTo(1200);
    await tester.pump();
    final rowHeight = tester
        .widget<ListView>(find.byKey(scheduleList))
        .itemExtent!;
    final remembered = guide.verticalOffsetFor(rowHeight);
    expect(remembered, greaterThan(500));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(buildGuide());
    await tester.pump();
    await tester.pump();
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(scheduleList),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.pixels, closeTo(remembered, 1));

    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
    lineup.dispose();
  });

  testWidgets('focused row survives row-height resize and route recreation', (
    tester,
  ) async {
    final lineup = _Lineup(100)
      ..settings = const LineupSettings(reduceMotion: true);
    addTearDown(lineup.dispose);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    addTearDown(guide.dispose);
    Widget buildGuide() => MaterialApp(
      builder: LineupCanvas.builder,
      home: GuideView(controller: guide, onClose: () {}, onTune: (_) async {}),
    );
    void expectFocusedRowVisible() {
      final list = tester.widget<ListView>(
        find.byKey(const Key('guide-schedule-list')),
      );
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('guide-schedule-list')),
          matching: find.byType(Scrollable),
        ),
      );
      final first = (scrollable.position.pixels / list.itemExtent!).floor();
      final visible = (scrollable.position.viewportDimension / list.itemExtent!)
          .ceil();
      expect(first, lessThanOrEqualTo(guide.focusedChannelIndex));
      expect(guide.focusedChannelIndex, lessThan(first + visible));
    }

    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(buildGuide());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();
    for (var index = 0; index < 20; index++) {
      guide.moveVertical(1);
    }
    await tester.pump();
    await tester.pump();
    expect(guide.focusedChannelIndex, 20);

    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 899);
    await tester.pump();
    await tester.pump();
    expectFocusedRowVisible();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 900);
    await tester.pumpWidget(buildGuide());
    await tester.pump();
    await tester.pump();
    expectFocusedRowVisible();

    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
    lineup.dispose();
  });

  testWidgets('focus fully reveals a trailing partial row', (tester) async {
    final lineup = _Lineup(100)
      ..settings = const LineupSettings(reduceMotion: true);
    addTearDown(lineup.dispose);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
    );
    addTearDown(guide.dispose);
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: LineupCanvas.builder,
        home: GuideView(
          controller: guide,
          onClose: () {},
          onTune: (_) async {},
        ),
      ),
    );
    await tester.pump();

    final list = tester.widget<ListView>(
      find.byKey(const Key('guide-schedule-list')),
    );
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('guide-schedule-list')),
        matching: find.byType(Scrollable),
      ),
    );
    final rowHeight = list.itemExtent!;
    scrollable.position.jumpTo(rowHeight * 3 + 5);
    await tester.pump();

    final trailingPartialRow =
        (scrollable.position.pixels / rowHeight).floor() +
        (scrollable.position.viewportDimension / rowHeight).floor();
    guide.moveVertical(trailingPartialRow);
    await tester.pump();
    await tester.pump();

    expect(guide.focusedChannelIndex, trailingPartialRow);
    final viewportTop = scrollable.position.pixels;
    final viewportBottom = viewportTop + scrollable.position.viewportDimension;
    final rowTop = rowHeight * trailingPartialRow;
    final rowBottom = rowTop + rowHeight;
    expect(rowTop, greaterThanOrEqualTo(viewportTop));
    expect(rowBottom, lessThanOrEqualTo(viewportBottom));

    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
    lineup.dispose();
  });
}

String _detailsMetadata(WidgetTester tester) => [
  tester.widget<Text>(find.byKey(const Key('guide-program-meta'))).data!,
  if (find.byKey(const Key('guide-info-genres')).evaluate().isNotEmpty)
    tester.widget<Text>(find.byKey(const Key('guide-info-genres'))).data!,
].join(' · ').replaceAll('\u00a0', ' ');

ScheduleIndex _schedule(Channel channel) => buildSchedule(
  (channel.source as ManualSource).items,
  mode: channel.playbackMode,
  seed: channel.shuffleSeed,
);

String _testTime(DateTime value) =>
    const DefaultMaterialLocalizations().formatTimeOfDay(
      TimeOfDay.fromDateTime(value),
      alwaysUse24HourFormat: false,
    );

class _Lineup extends LineupController {
  _Lineup(
    int count, {
    this.artworkBytes,
    this.artworkLoader,
    DateTime? anchor,
    AppStore? store,
  }) : super(
         store: store ?? _Store(),
         credentials: _Credentials(),
         plex: PlexClient(
           clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
         ),
       ) {
    channels = List.generate(
      count,
      (index) => Channel(
        id: 'channel-$index',
        number: index + 1,
        name: 'Channel $index',
        source: ManualSource([
          ChannelItem(
            id: 'program-$index',
            title: 'Program $index',
            duration: const Duration(hours: 24),
          ),
        ]),
        playbackMode: PlaybackMode.sequential,
        anchor: anchor ?? DateTime.now().subtract(const Duration(hours: 1)),
        shuffleSeed: index,
      ),
    );
    stage = SetupStage.ready;
  }

  final Uint8List? artworkBytes;
  final Future<Uint8List?> Function(Uri)? artworkLoader;
  int artworkLoads = 0;

  @override
  Future<Uint8List?> artworkForPath(Uri path, {int? width, int? height}) async {
    artworkLoads++;
    return artworkLoader == null ? artworkBytes : await artworkLoader!(path);
  }
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

class _RetryStore extends _Store {
  Completer<void>? saveGate;
  bool fail = true;
  int attempts = 0;
  PersistedState saved = const PersistedState();

  @override
  Future<void> save(PersistedState state) async {
    attempts++;
    await saveGate?.future;
    if (fail) throw StateError('Synthetic save failure');
    saved = state;
  }
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

class _GuideBoundsPlayer extends FixturePlayer {
  final rects = <PlayerVideoRect>[];
  @override
  Future<void> setVideoRect(PlayerVideoRect rect) async => rects.add(rect);
}
