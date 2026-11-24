import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/channel_filter.dart';
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

void main() {
  setUpAll(loadPinnedTestFonts);
  testWidgets('tuned Guide controls fit across the merged header threshold', (
    tester,
  ) async {
    await _mount(tester, size: const Size(1600, 900));
    final top = find.byKey(const Key('lineup-top-bar'));
    Future<bool> resize(int width) async {
      tester.view.physicalSize = Size(width.toDouble(), 900);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'window width $width');
      return tester.getSize(top).height == 72;
    }

    var narrow = 840;
    var wide = 1600;
    expect(await resize(narrow), isFalse);
    expect(await resize(wide), isTrue);
    while (wide - narrow > 1) {
      final width = (narrow + wide) ~/ 2;
      if (await resize(width)) {
        wide = width;
      } else {
        narrow = width;
      }
    }
    for (final width in [narrow - 1, narrow, wide, wide + 1]) {
      final merged = await resize(width);
      expect(merged, width >= wide);
      expect(
        tester
            .getSize(find.byKey(const Key('guide-now-playing-context')))
            .width,
        greaterThan(0),
      );
      final toolbar = tester.getRect(top);
      for (final key in [
        'guide-app-menu',
        'guide-current-date-time',
        'guide-back-to-player',
        if (merged) ...[
          'guide-channel-filter',
          'guide-earlier',
          'guide-now',
          'guide-later',
          'guide-hours',
          'guide-search-button',
        ],
      ]) {
        final rect = tester.getRect(find.byKey(Key(key)));
        expect(
          toolbar.inflate(.01).contains(rect.topLeft),
          isTrue,
          reason: key,
        );
        expect(
          toolbar.inflate(.01).contains(rect.bottomRight),
          isTrue,
          reason: key,
        );
      }
    }
  });

  testWidgets('focused desktop search keeps editing across a live resize', (
    tester,
  ) async {
    final guide = await _mount(tester);
    final button = find.byKey(const Key('guide-search-button'));
    final search = find.byKey(const Key('guide-channel-search'));
    final top = find.byKey(const Key('lineup-top-bar'));
    expect(tester.getSize(top).height, 72);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.enterText(search, 'Signal');
    await tester.pumpAndSettle();
    for (final (size, barHeight, input) in [
      (const Size(840, 720), 80, 'Signal House'),
      (const Size(1920, 1080), 72, 'Signal House 1'),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.getSize(top).height, barHeight);
      expect(
        tester.widget<TextField>(search).focusNode!.hasPrimaryFocus,
        isTrue,
      );
      expect(tester.testTextInput.hasAnyClients, isTrue);
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: input,
          selection: TextSelection.collapsed(offset: input.length),
        ),
      );
      await tester.pumpAndSettle();
      expect(guide.searchQuery, input.toLowerCase());
    }
  });

  for (final escape in [false, true]) {
    testWidgets('merged search collapses with only whitespace escape=$escape', (
      tester,
    ) async {
      final guide = await _mount(tester);
      final button = find.byKey(const Key('guide-search-button'));
      final search = find.byKey(const Key('guide-channel-search'));
      if (escape) {
        guide.setSearchQuery('Signal');
        await tester.pumpAndSettle();
        await tester.tap(search);
      } else {
        await tester.tap(button);
      }
      await tester.pumpAndSettle();
      await tester.enterText(search, '   ');
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(search);
      expect(field.focusNode!.hasPrimaryFocus, isTrue);
      expect(field.controller!.text, '   ');
      expect(guide.searchQuery, isEmpty);
      if (escape) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      } else {
        field.focusNode!.unfocus();
      }
      await tester.pumpAndSettle();
      expect(search, findsNothing);
      expect(button, findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        escape ? 'Guide search channels' : isNot('Guide channel search'),
      );
    });
  }
  for (final tv in [false, true]) {
    testWidgets('merged Guide bar order and search lifecycle TV=$tv', (
      tester,
    ) async {
      final guide = await _mount(tester, tv: tv);
      final top = find.byKey(const ValueKey('lineup-top-bar'));
      expect(tester.getSize(top).height, 72);
      final controls = [
        'guide-channel-filter',
        'guide-earlier',
        'guide-now',
        'guide-later',
        'guide-hours',
        'guide-search-button',
      ];
      double previous = 0;
      for (final key in controls) {
        final rect = tester.getRect(find.byKey(Key(key)));
        expect(rect.top, greaterThanOrEqualTo(tester.getTopLeft(top).dy));
        expect(rect.bottom, lessThanOrEqualTo(tester.getBottomLeft(top).dy));
        expect(rect.left, greaterThan(previous));
        previous = rect.left;
      }
      expect(find.byKey(const Key('guide-channel-search')), findsNothing);
      await tester.tap(find.byKey(const Key('guide-search-button')));
      await tester.pumpAndSettle();
      final search = find.byKey(const Key('guide-channel-search'));
      expect(search, findsOneWidget);
      expect(find.byKey(const Key('guide-hours')), findsNothing);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        tv ? 'Guide channel search' : isNotNull,
      );
      await tester.enterText(search, 'Signal');
      await tester.pumpAndSettle();
      if (!tv) {
        final editor = tester.widget<TextField>(search).controller!;
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(search).focusNode!.hasPrimaryFocus,
          isTrue,
        );
        editor.selection = const TextSelection.collapsed(offset: 3);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(editor.selection, const TextSelection.collapsed(offset: 2));
        expect(
          tester.widget<TextField>(search).focusNode!.hasPrimaryFocus,
          isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(editor.selection, const TextSelection.collapsed(offset: 3));
        expect(
          tester.widget<TextField>(search).focusNode!.hasPrimaryFocus,
          isTrue,
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        expect(
          editor.selection,
          const TextSelection(baseOffset: 3, extentOffset: 4),
        );
        expect(
          tester.widget<TextField>(search).focusNode!.hasPrimaryFocus,
          isTrue,
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        expect(editor.selection, const TextSelection.collapsed(offset: 3));
        expect(
          tester.widget<TextField>(search).focusNode!.hasPrimaryFocus,
          isTrue,
        );
      }
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(search, findsOneWidget);
      expect(guide.searchQuery, 'signal');
      await tester.tap(search);
      await tester.pumpAndSettle();
      if (tv) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(guide.searchQuery, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(search, findsNothing);
      expect(find.byKey(const Key('guide-search-button')), findsOneWidget);
      guide.setChannelFilter((
        group: ChannelFilterGroup.sourceType,
        value: 'custom',
      ));
      await tester.pumpAndSettle();
      final label = find.byKey(const Key('guide-active-channel-filter-label'));
      expect(label, findsOneWidget);
      expect(
        tester.getTopLeft(label).dx,
        lessThan(tester.getTopLeft(find.byKey(const Key('guide-earlier'))).dx),
      );
    });
  }
  for (final tv in [false, true]) {
    testWidgets('merged bar horizontal focus and grid return TV=$tv', (
      tester,
    ) async {
      final guide = await _mount(tester, tv: tv);
      tester
          .widget<TextButton>(find.byKey(const Key('guide-app-menu')))
          .focusNode!
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Guide channel filter',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Guide now');
      final channel = guide.focusedChannelId;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Guide grid');
      expect(guide.focusedChannelId, channel);
      if (tv) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          isNot('Guide grid'),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(guide.focusedChannelId, channel);
      }
    });
  }
  testWidgets('cell lines mask now-line and episode code follows title', (
    tester,
  ) async {
    final guide = await _mount(tester, tv: true);
    expect(find.byKey(const Key('guide-airing-dot')), findsNothing);
    final cell = find.byKey(ValueKey(guide.currentProgram('c0')!.id));
    final title = find.descendant(
      of: cell,
      matching: find.text('Signal House'),
    );
    final code = find.descendant(of: cell, matching: find.text('S02E01'));
    final episode = find.descendant(
      of: cell,
      matching: find.text('The Last Frequency'),
    );
    expect(
      tester.getTopLeft(code).dx - tester.getTopRight(title).dx,
      closeTo(8, .001),
    );
    expect(tester.getTopLeft(title).dx, tester.getTopLeft(episode).dx);
    final backing = find.descendant(
      of: cell,
      matching: find.byKey(const Key('guide-cell-text-backing')),
    );
    expect(backing, findsNWidgets(2));
    final fill =
        (tester
                    .widget<AnimatedContainer>(
                      find
                          .descendant(
                            of: cell,
                            matching: find.byType(AnimatedContainer),
                          )
                          .first,
                    )
                    .decoration!
                as BoxDecoration)
            .color!;
    final roles = LineupTheme.of(tester.element(cell));
    for (final widget in tester.widgetList<AnimatedContainer>(backing)) {
      final color = (widget.decoration! as BoxDecoration).color!;
      expect(color, Color.alphaBlend(fill, roles.deepBackground));
      expect(color.a, 1);
      expect(widget.padding, const EdgeInsets.symmetric(horizontal: 6));
    }
    expect(
      tester.getTopLeft(backing.first).dx,
      tester.getTopLeft(title).dx - 6,
    );
    final secondary = tester.widget<Text>(episode).style!;
    expect(secondary.fontSize, 19);
    final marker = tester.getRect(find.byKey(const Key('guide-now-marker')));
    final line = tester.getRect(find.byKey(const Key('guide-now-line')));
    expect(marker.center.dx, line.center.dx);
    expect(line.top, marker.center.dy);
    expect(find.text('12:18'), findsOneWidget);
  });
  testWidgets('narrow cells hide text while inspection remains available', (
    tester,
  ) async {
    final guide = await _mount(
      tester,
      tv: true,
      items: const [
        ChannelItem(
          id: 'long',
          title: 'Long Program',
          duration: Duration(minutes: 48),
        ),
        ChannelItem(
          id: 'tiny',
          title: 'Wide Narrow Title',
          duration: Duration(minutes: 2),
        ),
        ChannelItem(
          id: 'next',
          title: 'Next Program',
          duration: Duration(minutes: 48),
        ),
      ],
    );
    final tiny = guide
        .row('c0')
        .programs
        .firstWhere((p) => p.scheduled.item.id == 'tiny');
    final cell = find.byKey(ValueKey(tiny.id));
    expect(cell, findsOneWidget);
    expect(
      find.descendant(of: cell, matching: find.byType(Text)),
      findsNothing,
    );
    guide.focusProgram(tiny);
    await tester.pumpAndSettle();
    expect(guide.focusedProgramId, tiny.id);
    expect(
      find.descendant(of: cell, matching: find.byType(Text)),
      findsNothing,
    );
    expect(find.text('Wide Narrow Title'), findsOneWidget);
  });
  testWidgets('now marker hides an overlapping half-hour label', (
    tester,
  ) async {
    await _mount(tester, now: DateTime(2026, 11, 16, 12, 30));
    expect(find.byKey(const ValueKey('guide-time-label-0')), findsNothing);
    expect(find.byKey(const ValueKey('guide-time-label-1')), findsOneWidget);
    expect(find.text('12:30'), findsOneWidget);
  });
  testWidgets('midnight date remains visible beside an overlapping marker', (
    tester,
  ) async {
    var now = DateTime(2026, 5, 19, 22, 48);
    final guide = await _mount(tester, clock: () => now);
    guide.moveWindow(2);
    await tester.pumpAndSettle();
    final date = find.byKey(const Key('guide-midnight-date'));
    final windowDate = find.byKey(const Key('guide-window-date'));
    final midnightTick = find.byKey(const Key('guide-time-label-1'));
    expect(date, findsOneWidget);
    expect(midnightTick, findsOneWidget);
    expect(
      tester.widget<Text>(date).data,
      isNot(tester.widget<Text>(windowDate).data),
    );

    now = DateTime(2026, 5, 20);
    await tester.pump(const Duration(minutes: 1));
    final marker = find.byKey(const Key('guide-now-marker'));
    expect(
      find.descendant(of: marker, matching: find.text('12:00')),
      findsOneWidget,
    );
    expect(midnightTick, findsNothing);
    expect(date, findsOneWidget);
    final dateRect = tester.getRect(date);
    final markerRect = tester.getRect(marker);
    expect(
      dateRect.overlaps(markerRect),
      isFalse,
      reason: '$dateRect / $markerRect',
    );
    now = DateTime(2026, 5, 20, 0, 10);
    await tester.pump(const Duration(seconds: 30));
    expect(
      find.descendant(of: marker, matching: find.text('12:10')),
      findsOneWidget,
    );
    expect(midnightTick, findsOneWidget);
    final laterMarker = tester.getRect(marker);
    final laterDate = tester.getRect(date);
    expect(
      laterMarker.left,
      greaterThanOrEqualTo(tester.getRect(midnightTick).right),
    );
    expect(laterMarker.left, lessThan(laterDate.right));
    expect(
      laterDate.overlaps(laterMarker),
      isFalse,
      reason: '$laterDate / $laterMarker',
    );
    expect(guide.windowStart.toLocal(), DateTime(2026, 5, 19, 23, 30));
  });
  for (final sample in const [
    (name: 'film', title: 'Feature Film', show: null, range: true),
    (
      name: 'episode without distinct subtitle',
      title: 'Signal House',
      show: 'Signal House',
      range: true,
    ),
    (
      name: 'episode with room for range',
      title: 'The Relay',
      show: 'Signal House',
      range: true,
    ),
    (
      name: 'episode title takes priority',
      title: 'A very long episode title that fills the program cell and leaves no room for the time range to follow it',
      show: 'Signal House',
      range: false,
    ),
  ]) {
    testWidgets('second cell line ${sample.name}', (tester) async {
      final guide = await _mount(
        tester,
        tv: true,
        items: [
          ChannelItem(
            id: 'sample',
            title: sample.title,
            showTitle: sample.show,
            duration: const Duration(minutes: 48),
          ),
        ],
      );
      final cell = find.byKey(ValueKey(guide.currentProgram('c0')!.id));
      final range = find.descendant(
        of: cell,
        matching: find.byWidgetPredicate(
          (widget) => widget is Text && (widget.data?.contains('–') ?? false),
        ),
      );
      expect(range, sample.range ? findsOneWidget : findsNothing);
      if (sample.show != null && sample.title != sample.show) {
        expect(
          find.descendant(of: cell, matching: find.text(sample.title)),
          findsOneWidget,
        );
      }
    });
  }
  testWidgets('line masks use opaque effective fills in all cell states', (
    tester,
  ) async {
    final guide = await _mount(
      tester,
      tv: true,
      items: const [
        ChannelItem(
          id: 'past',
          title: 'Past Feature',
          duration: Duration(minutes: 17),
        ),
        ChannelItem(
          id: 'current',
          title: 'Current Feature',
          duration: Duration(minutes: 48),
        ),
        ChannelItem(
          id: 'future',
          title: 'Future Feature',
          duration: Duration(minutes: 48),
        ),
      ],
    );
    final programs = guide.row('c0').programs.take(3).toList();
    void check() {
      for (final program in programs) {
        final cell = find.byKey(ValueKey(program.id));
        final fill =
            (tester
                        .widget<AnimatedContainer>(
                          find
                              .descendant(
                                of: cell,
                                matching: find.byType(AnimatedContainer),
                              )
                              .first,
                        )
                        .decoration!
                    as BoxDecoration)
                .color!;
        final roles = LineupTheme.of(tester.element(cell));
        final masks = find.descendant(
          of: cell,
          matching: find.byKey(const Key('guide-cell-text-backing')),
        );
        expect(masks, findsNWidgets(2), reason: program.scheduled.item.title);
        for (final mask in tester.widgetList<AnimatedContainer>(masks)) {
          final color = (mask.decoration! as BoxDecoration).color!;
          expect(color, Color.alphaBlend(fill, roles.deepBackground));
          expect(color.a, 1);
        }
      }
    }

    check();
    guide.selectProgram(programs.first);
    guide.focusProgram(programs[1]);
    await tester.pumpAndSettle();
    check();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
      location: tester.getCenter(find.byKey(ValueKey(programs.last.id))),
    );
    await tester.pumpAndSettle();
    check();
    await mouse.removePointer();
  });
  for (final size in const [
    Size(1280, 720),
    Size(1920, 1080),
    Size(3840, 2160),
  ]) {
    testWidgets(
      'merged TV recovery wrap reaches actions and restores grid at $size',
      (tester) async {
        var retries = 0;
        var next = 0;
        final guide = await _mount(
          tester,
          tv: true,
          size: size,
          picture: GuidePlaybackPlaceholder(
            unavailable: true,
            reduceMotion: true,
            onRetry: () => retries++,
            onNextChannel: () => next++,
          ),
        );
        guide.moveVertical(2);
        await tester.pumpAndSettle();
        final remembered = guide.focusedProgramId;
        Focus.of(
          tester.element(
            find
                .descendant(
                  of: find.byKey(const Key('guide-channel-filter')),
                  matching: find.text('All channels'),
                )
                .first,
          ),
        ).requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(_focusedButtonText(), 'Retry');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(_focusedButtonText(), 'Next channel');
        expect((retries, next), (0, 0));
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(next, 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(_focusedButtonText(), 'Retry');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'Guide channel filter',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(retries, 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'Guide grid');
        expect(guide.focusedProgramId, remembered);
        expect(guide.focusedChannelId, 'c2');
      },
    );
  }
  for (final retry in [false, true]) {
    testWidgets(
      'TV recovery entry only targets visible enabled actions retry=$retry',
      (tester) async {
        await _mount(
          tester,
          tv: true,
          picture: GuidePlaybackPlaceholder(
            unavailable: true,
            reduceMotion: true,
            onNextChannel: retry ? () {} : null,
          ),
        );
        Focus.of(
          tester.element(
            find
                .descendant(
                  of: find.byKey(const Key('guide-channel-filter')),
                  matching: find.text('All channels'),
                )
                .first,
          ),
        ).requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        if (retry) {
          expect(_focusedButtonText(), 'Next channel');
        } else {
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'Guide channel filter',
          );
        }
      },
    );
  }
  testWidgets('recovery shortcut leaves an open TV filter popup in charge', (
    tester,
  ) async {
    await _mount(
      tester,
      tv: true,
      picture: GuidePlaybackPlaceholder(
        unavailable: true,
        reduceMotion: true,
        onRetry: () {},
      ),
    );
    await tester.tap(find.byKey(const Key('guide-channel-filter')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(_focusedButtonText(), isNot('Retry'));
    expect(find.byType(LineupDropdownMenuRow), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });
  for (final scale in [1.0, 1.3, 1.69]) {
    testWidgets('TV Guide row count follows measured floor scale=$scale', (
      tester,
    ) async {
      await _mount(tester, tv: true, scale: scale);
      final list = find.byKey(const Key('guide-schedule-list'));
      final extent = tester.widget<ListView>(list).itemExtent!;
      final count = tester.getSize(list).height / extent;
      expect(count, closeTo(scale <= 1.3 ? 6 : 5, .00001));
      expect(tester.takeException(), isNull);
    });
  }
  for (final scale in [1.5, 2.0]) {
    testWidgets('narrow enlarged Guide retains wrapping layout scale=$scale', (
      tester,
    ) async {
      await _mount(tester, size: const Size(1280, 720), scale: scale);
      expect(
        tester.getSize(find.byKey(const ValueKey('lineup-top-bar'))).height,
        80,
      );
      expect(find.byKey(const Key('guide-channel-search')), findsOneWidget);
      expect(find.byKey(const Key('guide-search-button')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<GuideController> _mount(
  WidgetTester tester, {
  bool tv = false,
  double scale = 1,
  Size size = const Size(1920, 1080),
  DateTime? now,
  DateTime Function()? clock,
  List<ChannelItem>? items,
  Widget picture = const ColoredBox(color: Color(0xff17292f)),
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  now ??= clock?.call() ?? DateTime(2026, 11, 16, 12, 18);
  final channels = List.generate(
    20,
    (i) => Channel(
      id: 'c$i',
      number: i + 1,
      name: 'Signal House $i',
      source: ManualSource(
        items ??
            List.generate(
              8,
              (j) => ChannelItem(
                id: 'p$i-$j',
                title: 'The Last Frequency',
                showTitle: 'Signal House',
                seasonNumber: 2,
                episodeNumber: j + 1,
                duration: const Duration(minutes: 48),
              ),
            ),
      ),
      playbackMode: PlaybackMode.sequential,
      anchor: now!.subtract(const Duration(minutes: 18)),
      shuffleSeed: i,
    ),
  );
  final lineup = FixtureController(
    scenario: LineupScenario(
      stage: SetupStage.ready,
      channels: channels,
      settings: const LineupSettings(reduceMotion: true),
    ),
  );
  final guide = GuideController(
    lineup: lineup,
    clock: clock ?? () => now!,
    loadSchedule: (c) async =>
        buildChannelSchedule(c, (c.source as ManualSource).items),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    guide.dispose();
    lineup.dispose();
  });
  await tester.pumpWidget(
    DeviceProfileScope(
      profile: profileFor(tv),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: LineupTheme.forName(
          LineupThemeName.emberSteel,
          formFactor: profileFor(tv).formFactor,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: LineupCanvas(child: child!),
        ),
        home: GuideView(
          controller: guide,
          pictureInPicture: picture,
          watchingChannelId: 'c0',
          onOpenMenu: (_, _) {},
          onClose: (_, _) {},
          onTune: (_) async {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return guide;
}

String? _focusedButtonText() {
  final widget = FocusManager.instance.primaryFocus?.context
      ?.findAncestorWidgetOfExactType<TextButton>();
  return widget?.child is Text ? (widget!.child as Text).data : null;
}
