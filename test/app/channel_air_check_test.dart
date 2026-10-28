import 'package:lineup_desktop/app/lineup_controller.dart';

import 'dart:async';
import 'dart:ui' show SemanticsAction;

// Clock fixtures intentionally reassign their local time source.
// ignore_for_file: prefer_final_locals

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/app_ui.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/app/channel_air_check.dart';
import 'package:lineup_desktop/app/air_check_verification.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

import '../support/ui_fixture.dart';

void main() {
  for (final tv in [true, false]) {
    testWidgets('schedule row focus ink preserves live identity tv=$tv', (
      tester,
    ) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTouch;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      final controller = _AirController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _airCheck(
          controller,
          _channel(items: [_item('one'), _item('two')]),
          compact: true,
          isTv: tv,
          theme:
              LineupTheme.forName(
                LineupThemeName.emberSteel,
                formFactor: profileFor(tv).formFactor,
              ).copyWith(
                platform: tv ? TargetPlatform.android : TargetPlatform.windows,
              ),
        ),
      );
      await tester.pumpAndSettle();
      final row = find.ancestor(
        of: find.text('ON NOW'),
        matching: find.byType(LineupNavigationRow),
      );
      expect(row, findsOneWidget);
      final live = find.descendant(of: row, matching: find.text('ON NOW'));
      final metadata = find.descendant(
        of: row,
        matching: find.byWidgetPredicate(
          (w) => w is Text && (w.data?.startsWith('Today ·') ?? false),
        ),
      );
      expect(metadata, findsOneWidget);
      Color? ink(Finder text) => tester.widget<Text>(text).style?.color;
      final base = ink(live);
      final baseMeta = ink(metadata);
      final element = tester.element(live);
      // Enter the real shared row's focus owner, then use D-pad to leave it.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      final button = find.descendant(
        of: row,
        matching: find.byType(TextButton),
      );
      Focus.of(
        tester.element(
          find.descendant(of: button, matching: find.byType(Padding)).last,
        ),
      ).requestFocus();
      await tester.pumpAndSettle();
      expect(Focus.of(tester.element(live)).hasFocus, isTrue);
      expect(ink(live), tv ? const Color(0xFF090806) : base);
      expect(
        ink(metadata),
        tv
            ? LineupTheme.of(tester.element(metadata)).focusSecondaryText
            : baseMeta,
      );
      expect(tester.element(live), same(element));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(Focus.of(tester.element(live)).hasFocus, isFalse);
      expect(ink(live), base);
      expect(ink(metadata), baseMeta);
    });
  }
  testWidgets(
    'successful Air Check load with failed projection offers a recovering retry',
    (tester) async {
      final controller = _AirController();
      addTearDown(controller.dispose);
      var validity = ChannelAirCheckValidity.valid;
      controller.scheduleOverride = buildSchedule(
        [
          const ChannelItem(
            id: 'long',
            title: 'Long',
            duration: Duration(microseconds: 8640000000000000000),
          ),
        ],
        mode: PlaybackMode.sequential,
        seed: 1,
      );
      final channel = _channel(items: [_item('one')]);
      await tester.pumpWidget(
        _airCheck(
          controller,
          channel,
          onValidityChanged: (value) => validity = value,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Retry Air Check'), findsOneWidget);
      expect(validity, ChannelAirCheckValidity.unknown);
      controller.scheduleOverride = null;
      await tester.tap(find.text('Retry Air Check'));
      await tester.pumpAndSettle();
      expect(controller.requests, 2);
      expect(find.text('One'), findsWidgets);
      expect(find.text('Retry Air Check'), findsNothing);
      expect(validity, ChannelAirCheckValidity.valid);
    },
  );

  testWidgets(
    'later Air Check transition failure retires the cached preview and retries',
    (tester) async {
      final controller = _AirController();
      addTearDown(controller.dispose);
      var now = DateTime.utc(2026, 1, 1, 0, 10);
      final boundary = now.add(const Duration(days: 1));
      controller.scheduleOverride = buildSchedule(
        [
          const ChannelItem(
            id: 'long',
            title: 'Long',
            duration: Duration(microseconds: 8640000000000000000),
          ),
        ],
        mode: PlaybackMode.sequential,
        seed: 1,
        transition: ScheduleTransition(
          boundary: boundary,
          legacyCycleItems: [_item('one')],
        ),
      );
      await tester.pumpWidget(
        _airCheck(
          controller,
          _channel(items: [_item('one')]),
          clock: () => now,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('One'), findsWidgets);
      now = boundary;
      await tester.pump(const Duration(seconds: 30));
      expect(tester.takeException(), isNull);
      expect(find.text('Retry Air Check'), findsOneWidget);
      expect(find.text('One'), findsNothing);
      controller.scheduleOverride = null;
      await tester.tap(find.text('Retry Air Check'));
      await tester.pumpAndSettle();
      expect(controller.requests, 2);
      expect(find.text('One'), findsWidgets);
      expect(find.text('Retry Air Check'), findsNothing);
    },
  );

  testWidgets(
    'synchronous comparison failure recovers through revision-bound retry',
    (tester) async {
      final controller = _AirController(controlled: true);
      addTearDown(controller.dispose);
      var now = DateTime.utc(2026, 1, 1, 0, 10);
      final boundary = now.add(const Duration(days: 1));
      final original = _channel(items: [_item('one')]);
      final draft = _channel(items: [_item('two')]);
      controller.scheduleOverride = buildSchedule(
        [
          const ChannelItem(
            id: 'long',
            title: 'Long',
            duration: Duration(microseconds: 8640000000000000000),
          ),
        ],
        mode: PlaybackMode.sequential,
        seed: 1,
        transition: ScheduleTransition(
          boundary: boundary,
          legacyCycleItems: [_item('one')],
        ),
      );
      final verification = AirCheckVerification(
        loadSchedule: controller.loadScheduleFor,
        clock: () => now,
      );
      verification.update(draft, original, 0, null);
      controller.scheduleOverride = null;
      controller.completeNext();
      await tester.pump();
      controller.completeNext();
      await tester.pump();
      expect(verification.result.preview, isNotNull);
      now = boundary;
      await tester.pump(const Duration(seconds: 30));
      expect(verification.result.preview, isNull);
      expect(verification.result.validity, ChannelAirCheckValidity.unknown);
      expect(verification.result.error, isA<ScheduleBuildException>());
      now = boundary.subtract(const Duration(days: 1));
      verification.retry();
      await tester.pump(
        channelAirCheckDebounce + const Duration(milliseconds: 1),
      );
      controller.completeNext();
      await tester.pump();
      controller.completeNext();
      await tester.pump();
      expect(
        verification.result.preview!.channel.source.toJson(),
        draft.source.toJson(),
      );
      expect(verification.result.validity, ChannelAirCheckValidity.valid);
      expect(controller.requests, 4);
      expect(tester.takeException(), isNull);
      verification.dispose();
    },
  );

  testWidgets(
    'sequential Air Check exposes authoritative facts, selection, and clock rollover',
    (tester) async {
      var now = DateTime.utc(2026, 1, 1, 0, 29, 59);
      final controller = _AirController();
      addTearDown(controller.dispose);
      final channel = _channel(
        items: const [
          ChannelItem(id: 'one', title: 'One', duration: Duration(minutes: 30)),
          ChannelItem(id: 'two', title: 'Two', duration: Duration(minutes: 30)),
        ],
      );
      final schedule = buildSchedule(
        (channel.source as ManualSource).items,
        mode: channel.playbackMode,
        seed: channel.shuffleSeed,
        blockSize: 3,
      );

      await tester.pumpWidget(_airCheck(controller, channel, clock: () => now));
      await tester.pumpAndSettle();

      expect(controller.requests, 1);
      expect(find.textContaining('2 playable'), findsOneWidget);
      expect(find.textContaining('1h cycle'), findsOneWidget);
      expect(find.textContaining('In order'), findsOneWidget);
      expect(find.text('ON NOW'), findsOneWidget);
      final heading = tester.widget<Semantics>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Schedule preview',
        ),
      );
      expect(heading.properties.header, isTrue);
      expect(
        find.descendant(
          of: find.byKey(const Key('air-check-selection')),
          matching: find.text('One'),
        ),
        findsOneWidget,
      );
      now = DateTime.utc(2026, 1, 1, 0, 29, 59, 500);
      await tester.pump(const Duration(seconds: 30));

      now = DateTime.utc(2026, 1, 1, 0, 30);
      await tester.pump(const Duration(seconds: 30));

      expect(controller.requests, 1);
      expect(find.text('Two'), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(const Key('air-check-selection')),
          matching: find.text('Two'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Channel 4 .*Two.*current')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Channel 4 .*One.*upcoming')),
        findsWidgets,
      );
      final ended = GuideProgram(
        channelId: 'air-check',
        scheduled: programAt(channel.anchor, channel.anchor, schedule),
      );
      expect(
        find.byKey(ValueKey('air-check-program-${ended.id}')),
        findsNothing,
      );
    },
  );

  testWidgets('every rhythm matches programAt and Guide boundary semantics', (
    tester,
  ) async {
    final controller = _AirController();
    addTearDown(controller.dispose);
    final items = [
      for (var index = 0; index < 6; index++)
        ChannelItem(
          id: '$index',
          title: 'Episode $index',
          duration: const Duration(minutes: 20),
          showTitle: index.isEven ? 'Even' : 'Odd',
        ),
    ];
    for (final mode in PlaybackMode.values) {
      var now = DateTime.utc(2025, 12, 31, 23, 59, 59, 999, 999);
      final channel = _channel(
        items: items,
        mode: mode,
        blockSize: mode == PlaybackMode.block ? 2 : null,
      );
      await tester.pumpWidget(_airCheck(controller, channel, clock: () => now));
      await tester.pumpAndSettle();
      final schedule = buildSchedule(
        items,
        mode: mode,
        seed: channel.shuffleSeed,
        blockSize: channel.blockSize ?? 3,
      );
      for (final instant in [
        DateTime.utc(2025, 12, 31, 23, 59, 59, 999, 999),
        channel.anchor,
        channel.anchor.add(const Duration(microseconds: 1)),
      ]) {
        now = instant;
        await tester.pump(const Duration(seconds: 30));
        final expected = programAt(now, channel.anchor, schedule);
        final guideProgram = GuideProgram(
          channelId: 'air-check',
          scheduled: expected,
        );
        expect(guideProgram.isCurrentAt(now), isTrue);
        expect(
          find.byKey(ValueKey('air-check-program-${guideProgram.id}')),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(
            RegExp(
              '${expected.item.title}.*${_formatted(expected.start)} to ${_formatted(expected.end)}.*current',
            ),
          ),
          findsOneWidget,
        );
      }
    }
  });

  testWidgets('rapid changes keep one active and one latest pending request', (
    tester,
  ) async {
    final controller = _AirController(controlled: true);
    addTearDown(controller.dispose);
    final verification = AirCheckVerification(
      loadSchedule: controller.loadScheduleFor,
      clock: () => DateTime.utc(2026, 1, 1, 0, 10),
    );
    void update(String id) =>
        verification.update(_channel(items: [_item(id)]), null, 0, null);
    update('one');
    expect(controller.requests, 1);
    update('two');
    await tester.pump(
      channelAirCheckDebounce + const Duration(milliseconds: 1),
    );
    update('three');
    await tester.pump(
      channelAirCheckDebounce + const Duration(milliseconds: 1),
    );
    expect(controller.requests, 1);
    controller.completeNext();
    await tester.pump();
    expect(controller.requests, 2);
    controller.completeNext();
    await tester.pump();
    expect(controller.requests, 2);
    expect(
      verification.result.preview!.channel.source.toJson(),
      ManualSource([_item('three')]).toJson(),
    );
    expect(verification.result.validity, ChannelAirCheckValidity.valid);
    verification.dispose();
  });

  testWidgets('same-key source recovery keeps the newest pending request', (
    tester,
  ) async {
    final controller = _AirController(controlled: true);
    addTearDown(controller.dispose);
    final verification = AirCheckVerification(
      loadSchedule: controller.loadScheduleFor,
      clock: () => DateTime.utc(2026, 1, 1, 0, 10),
    );
    final channel = _channel(items: [_item('latest')]);
    verification.update(channel, null, 0, null);
    verification.update(channel, null, 0, 'Incomplete source choice');
    verification.update(channel, null, 0, null);
    await tester.pump(
      channelAirCheckDebounce + const Duration(milliseconds: 1),
    );
    expect(controller.requests, 1);
    controller.completeNext();
    await tester.pump();
    expect(controller.requests, 2);
    controller.completeNext();
    await tester.pump();
    expect(
      verification.result.preview!.channel.source.toJson(),
      channel.source.toJson(),
    );
    expect(verification.result.validity, ChannelAirCheckValidity.valid);
    expect(controller.requests, 2);
    verification.dispose();
  });

  testWidgets('content generation, retry, and disposal reject stale results', (
    tester,
  ) async {
    final controller = _AirController(controlled: true);
    addTearDown(controller.dispose);
    final verification = AirCheckVerification(
      loadSchedule: controller.loadScheduleFor,
      clock: () => DateTime.utc(2026, 1, 1, 0, 10),
    );
    final channel = _channel(items: [_item('one')]);
    verification.update(channel, null, 0, null);
    verification.update(channel, null, 1, null);
    await tester.pump(
      channelAirCheckDebounce + const Duration(milliseconds: 1),
    );
    expect(controller.requests, 1);
    controller.completeNext();
    await tester.pump();
    expect(controller.requests, 2);
    controller.failNext(StateError('synthetic worker failure'));
    await tester.pump();
    expect(verification.result.error, isA<StateError>());
    expect(verification.result.validity, ChannelAirCheckValidity.unknown);
    verification.retry();
    await tester.pump(
      channelAirCheckDebounce + const Duration(milliseconds: 1),
    );
    expect(controller.requests, 3);
    var notifications = 0;
    verification.addListener(() => notifications++);
    verification.dispose();
    controller.completeNext();
    await tester.pump();
    expect(notifications, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'empty, missing, unsupported, stale, and truncated states are explicit',
    (tester) async {
      final controller = _AirController();
      addTearDown(controller.dispose);
      final missing = _channel(items: const []);
      await tester.pumpWidget(
        _airCheck(
          controller,
          missing,
          sourceIssue: 'The saved playlist is unavailable. Choose another.',
        ),
      );
      await tester.pump();
      expect(
        find.textContaining('saved playlist is unavailable'),
        findsOneWidget,
      );
      expect(find.text('ON NOW'), findsNothing);

      await tester.pumpWidget(
        _airCheck(
          controller,
          missing,
          sourceIssue: 'This source contains an unsupported filter. Choose a replacement.',
        ),
      );
      await tester.pump();
      expect(find.textContaining('unsupported filter'), findsOneWidget);

      final short = _channel(
        items: [
          const ChannelItem(
            id: 'short',
            title: 'Short',
            duration: Duration(seconds: 1),
          ),
        ],
      );
      await tester.pumpWidget(_airCheck(controller, short));
      await tester.pumpAndSettle();
      expect(find.textContaining('Preview truncated at'), findsOneWidget);
      expect(find.textContaining('last projected program end'), findsOneWidget);
    },
  );

  testWidgets('compact Air Check retains projected semantic entries', (
    tester,
  ) async {
    final controller = _AirController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _airCheck(
        controller,
        _channel(items: [_item('one'), _item('two'), _item('three')]),
        compact: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('One'), findsWidgets);
    expect(find.text('Two'), findsWidgets);
    expect(find.text('Three'), findsWidgets);
    expect(
      find.bySemanticsLabel(RegExp(r'Channel 4 .*One.*current')),
      findsOneWidget,
    );
  });

  testWidgets(
    'Air Check hides ended retained entries and preserves a future inspection',
    (tester) async {
      var now = DateTime.utc(2026, 1, 1, 0, 10);
      final controller = _AirController();
      addTearDown(controller.dispose);
      final channel = _channel(
        items: [_item('one'), _item('two'), _item('three')],
      );
      final schedule = buildSchedule(
        (channel.source as ManualSource).items,
        mode: channel.playbackMode,
        seed: channel.shuffleSeed,
        blockSize: 3,
      );
      final future = GuideProgram(
        channelId: 'air-check',
        scheduled: programAt(
          DateTime.utc(2026, 1, 1, 3),
          channel.anchor,
          schedule,
        ),
      );

      await tester.pumpWidget(_airCheck(controller, channel, clock: () => now));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Show next 6 hours'));
      await tester.pump();
      final extension = find.widgetWithText(TextButton, 'Show next 6 hours');
      final link = tester.widget<TextButton>(extension);
      final roles = LineupTheme.of(tester.element(extension));
      expect(link.style!.foregroundColor!.resolve({}), roles.progressFill);
      expect(
        link.style!.foregroundColor!.resolve({WidgetState.hovered}),
        roles.progressFill,
      );
      await tester.tap(find.text('Show next 6 hours'));
      await tester.pump();
      final futureRow = find.byKey(ValueKey('air-check-program-${future.id}'));
      await tester.scrollUntilVisible(
        futureRow,
        230,
        scrollable: find.descendant(
          of: find.byKey(const Key('air-check-schedule-list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pump();
      await tester.tap(futureRow);
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const Key('air-check-selection')),
          matching: find.text('One'),
        ),
        findsOneWidget,
      );

      now = DateTime.utc(2026, 1, 1, 2, 10);
      await tester.pump(const Duration(seconds: 30));
      expect(
        find.descendant(
          of: find.byKey(const Key('air-check-selection')),
          matching: find.text('One'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Channel 4 .*One.*upcoming')),
        findsWidgets,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Channel 4 .*Two.*upcoming')),
        findsWidgets,
      );
    },
    semanticsEnabled: true,
  );

  testWidgets('Air Check falls back to now when an inspection ends', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 1, 1, 0, 10);
    final controller = _AirController();
    addTearDown(controller.dispose);
    final channel = _channel(items: [_item('one'), _item('two')]);
    final schedule = buildSchedule(
      (channel.source as ManualSource).items,
      mode: channel.playbackMode,
      seed: channel.shuffleSeed,
      blockSize: 3,
    );
    final future = GuideProgram(
      channelId: 'air-check',
      scheduled: programAt(
        DateTime.utc(2026, 1, 1, 1),
        channel.anchor,
        schedule,
      ),
    );

    await tester.pumpWidget(_airCheck(controller, channel, clock: () => now));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('air-check-program-${future.id}')));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('air-check-selection')),
        matching: find.text('One'),
      ),
      findsOneWidget,
    );

    now = DateTime.utc(2026, 1, 1, 1, 40);
    await tester.pump(const Duration(seconds: 30));
    expect(
      find.descendant(
        of: find.byKey(const Key('air-check-selection')),
        matching: find.text('Two'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Air Check preserves inspection after successful recalculation', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 1, 1, 0, 10);
    final controller = _AirController();
    addTearDown(controller.dispose);
    final channel = _channel(items: [_item('one'), _item('two')]);
    final schedule = buildSchedule(
      (channel.source as ManualSource).items,
      mode: channel.playbackMode,
      seed: channel.shuffleSeed,
      blockSize: 3,
    );
    final future = GuideProgram(
      channelId: 'air-check',
      scheduled: programAt(
        DateTime.utc(2026, 1, 1, 1),
        channel.anchor,
        schedule,
      ),
    );

    await tester.pumpWidget(_airCheck(controller, channel, clock: () => now));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('air-check-program-${future.id}')));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('air-check-selection')),
        matching: find.text('One'),
      ),
      findsOneWidget,
    );

    controller.generation++;
    await tester.pumpWidget(_airCheck(controller, channel, clock: () => now));
    await tester.pump(
      channelAirCheckDebounce + const Duration(milliseconds: 1),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('air-check-selection')),
        matching: find.text('One'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('program rows expose selection detail and semantics', (
    tester,
  ) async {
    final controller = _AirController();
    addTearDown(controller.dispose);
    final channel = _channel(
      items: const [
        ChannelItem(id: 'a', title: 'A', duration: Duration(minutes: 1)),
        ChannelItem(id: 'b', title: 'B', duration: Duration(minutes: 1)),
      ],
    );
    await tester.pumpWidget(_airCheck(controller, channel));
    await tester.pumpAndSettle();
    final firstProgram = find.bySemanticsLabel(
      RegExp(r'Channel 4 .*A.*current'),
    );
    final firstSemantics = tester.getSemantics(firstProgram);
    firstSemantics.owner!.performAction(firstSemantics.id, SemanticsAction.tap);
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('air-check-selection')),
        matching: find.text('A'),
      ),
      findsOneWidget,
    );
    final secondProgram = tester.getSemantics(
      find.bySemanticsLabel(RegExp(r'Channel 4 .*B.*upcoming')),
    );
    secondProgram.owner!.performAction(secondProgram.id, SemanticsAction.tap);
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('air-check-selection')),
        matching: find.text('B'),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'Channel 4 .*B.*upcoming')),
      findsWidgets,
    );
  }, semanticsEnabled: true);

  testWidgets('time labels show and announce local twelve-hour wall time', (
    tester,
  ) async {
    final controller = _AirController();
    addTearDown(controller.dispose);
    final start = DateTime.utc(2026, 1, 1, 13);
    final end = start.add(const Duration(minutes: 30));
    final now = start.add(const Duration(minutes: 10));
    final twelveHourStart = _formatted(start);
    final twelveHourEnd = _formatted(end);
    final twentyFourHourStart = _formatted(start, always24: true);
    expect(twelveHourStart, isNot(twentyFourHourStart));
    await tester.pumpWidget(
      _airCheck(
        controller,
        _channel(items: [_item('one'), _item('two')]),
        clock: () => now,
        always24: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining(twelveHourStart), findsWidgets);
    expect(
      find.bySemanticsLabel(
        RegExp(
          'One, ${RegExp.escape(twelveHourStart)} to '
          '${RegExp.escape(twelveHourEnd)}, current',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text(twentyFourHourStart), findsNothing);
  });

  testWidgets('before, at, and after anchor match authoritative boundaries', (
    tester,
  ) async {
    var now = DateTime.utc(2025, 12, 31, 23, 59, 59, 999, 999);
    final controller = _AirController();
    addTearDown(controller.dispose);
    final channel = _channel(items: [_item('one'), _item('two')]);
    final schedule = buildSchedule(
      (channel.source as ManualSource).items,
      mode: channel.playbackMode,
      seed: channel.shuffleSeed,
      blockSize: 3,
    );
    await tester.pumpWidget(_airCheck(controller, channel, clock: () => now));
    await tester.pumpAndSettle();

    for (final instant in [
      DateTime.utc(2025, 12, 31, 23, 59, 59, 999, 999),
      channel.anchor,
      channel.anchor.add(const Duration(microseconds: 1)),
    ]) {
      now = instant;
      await tester.pump(const Duration(seconds: 30));
      final expected = programAt(now, channel.anchor, schedule);
      expect(
        find.bySemanticsLabel(
          RegExp('Channel 4 .*${expected.item.title}.*current'),
        ),
        findsOneWidget,
      );
      if (instant == channel.anchor) {
        final ended = GuideProgram(
          channelId: 'air-check',
          scheduled: programAt(
            channel.anchor.subtract(const Duration(microseconds: 1)),
            channel.anchor,
            schedule,
          ),
        );
        expect(
          find.byKey(ValueKey('air-check-program-${ended.id}')),
          findsNothing,
        );
      }
    }
    expect(controller.requests, 1);
  });

  testWidgets('stale preview stays visible and only latest data publishes', (
    tester,
  ) async {
    final controller = _AirController(controlled: true);
    addTearDown(controller.dispose);
    final first = _channel(items: [_item('one')]);
    final second = _channel(items: [_item('two')]);
    final latest = _channel(items: [_item('three')]);
    await tester.pumpWidget(_airCheck(controller, first));
    controller.completeNext();
    await tester.pump();
    expect(find.text('One'), findsWidgets);

    await tester.pumpWidget(_airCheck(controller, second));
    await tester.pump(
      channelAirCheckDebounce + const Duration(milliseconds: 1),
    );
    expect(find.text('Out of date'), findsOneWidget);
    expect(find.text('One'), findsWidgets);
    await tester.pumpWidget(_airCheck(controller, latest));
    await tester.pump(
      channelAirCheckDebounce + const Duration(milliseconds: 1),
    );
    controller.completeNext();
    await tester.pump();
    expect(find.text('Two'), findsNothing);
    controller.completeNext();
    await tester.pump();
    expect(find.text('Three'), findsWidgets);
    expect(controller.requests, 3);
  });

  testWidgets(
    'source and worker errors visibly mark a retained preview stale',
    (tester) async {
      final controller = _AirController(controlled: true);
      addTearDown(controller.dispose);
      final first = _channel(items: [_item('one')]);
      final changed = _channel(items: [_item('two')]);
      await tester.pumpWidget(_airCheck(controller, first));
      controller.completeNext();
      await tester.pump();

      await tester.pumpWidget(
        _airCheck(
          controller,
          first,
          sourceIssue: 'Choose the missing source value.',
        ),
      );
      await tester.pump();
      expect(find.text('Out of date'), findsOneWidget);
      expect(find.text('One'), findsWidgets);

      await tester.pumpWidget(_airCheck(controller, changed));
      await tester.pump(
        channelAirCheckDebounce + const Duration(milliseconds: 1),
      );
      controller.failNext(StateError('synthetic worker failure'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Out of date'), findsOneWidget);
      expect(find.text('One'), findsWidgets);
      expect(find.textContaining('could not verify'), findsOneWidget);
    },
  );

  testWidgets(
    'retained schedule keeps its source and dims without offering invalid-source retry',
    (tester) async {
      final controller = _AirController(controlled: true);
      addTearDown(controller.dispose);
      final first = _channel(items: [_item('one')]);
      final next = _channel(items: [_item('two')]);
      await tester.pumpWidget(
        _airCheck(controller, first, inclusionReason: 'Original source'),
      );
      controller.completeNext();
      await tester.pump();
      await tester.pumpWidget(
        _airCheck(
          controller,
          next,
          inclusionReason: 'Replacement source',
          sourceIssue: 'Choose available programming.',
        ),
      );
      await tester.pump();
      expect(find.text('Previous schedule · Original source'), findsOneWidget);
      final selectedFacts = find.descendant(
        of: find.byKey(const Key('air-check-selection')),
        matching: find.text('30m · Original source'),
      );
      expect(selectedFacts, findsOneWidget);
      expect(find.textContaining('Replacement source'), findsNothing);
      expect(
        tester
            .widget<Opacity>(
              find.byKey(const Key('air-check-schedule-content')),
            )
            .opacity,
        .5,
      );
      expect(find.text('Retry Air Check'), findsNothing);
      final renamed = Channel(
        id: next.id,
        number: 9,
        name: 'Renamed draft',
        source: next.source,
        playbackMode: next.playbackMode,
        anchor: next.anchor,
        shuffleSeed: next.shuffleSeed,
      );
      await tester.pumpWidget(
        _airCheck(
          controller,
          renamed,
          inclusionReason: 'Replacement source',
          sourceIssue: 'Choose available programming.',
        ),
      );
      await tester.pump();
      expect(find.textContaining('Ch 4 · 1 playable'), findsOneWidget);
      expect(find.text('Previous schedule · Original source'), findsOneWidget);
      expect(selectedFacts, findsOneWidget);
      expect(find.textContaining('Replacement source'), findsNothing);
      expect(controller.requests, 1);
    },
  );

  testWidgets('schedule failures render their typed recovery messages', (
    tester,
  ) async {
    final controller = _AirController();
    addTearDown(controller.dispose);
    final retained = _channel(items: [_item('retained')]);
    final nested = Channel.fromJson({
      ...retained.toJson(),
      'source': MixedSource(
        sources: [
          ManualSource([_item('retained')]),
        ],
      ).toJson(),
    });
    for (final (channel, failure, message) in [
      (
        _channel(items: const []),
        const ScheduleBuildException(ScheduleFailureReason.noContent),
        'no playable programs',
      ),
      (
        retained,
        const ScheduleBuildException(ScheduleFailureReason.unsupportedSource),
        'unsupported filter',
      ),
      (
        retained,
        const ScheduleBuildException(ScheduleFailureReason.noContent),
        'explicitly off air',
      ),
      (retained, StateError('synthetic worker failure'), 'could not verify'),
      (
        nested,
        const ScheduleBuildException(ScheduleFailureReason.noContent),
        'explicitly off air',
      ),
    ]) {
      controller.nextFailure = failure;
      await tester.pumpWidget(_airCheck(controller, channel, key: UniqueKey()));
      await tester.pumpAndSettle();
      expect(find.textContaining(message), findsOneWidget);
    }
  });

  testWidgets('failure states gate validity except retained manual off-air', (
    tester,
  ) async {
    final controller = _AirController();
    addTearDown(controller.dispose);
    final verification = AirCheckVerification(
      loadSchedule: controller.loadScheduleFor,
      clock: () => DateTime.utc(2026, 1, 1, 0, 10),
    );
    verification.update(_channel(items: const []), null, 0, null);
    await tester.pump();
    expect(verification.result.error, isA<ScheduleBuildException>());
    expect(verification.result.validity, ChannelAirCheckValidity.unknown);
    for (final (id, failure, expected) in [
      (
        'unsupported',
        const ScheduleBuildException(ScheduleFailureReason.unsupportedSource),
        ChannelAirCheckValidity.unknown,
      ),
      (
        'missing',
        const ScheduleBuildException(ScheduleFailureReason.noContent),
        ChannelAirCheckValidity.retainedOffAir,
      ),
      (
        'worker',
        StateError('synthetic worker failure'),
        ChannelAirCheckValidity.unknown,
      ),
    ]) {
      controller.nextFailure = failure;
      verification.update(_channel(items: [_item(id)]), null, 0, null);
      expect(verification.result.validity, ChannelAirCheckValidity.unknown);
      await tester.pump(
        channelAirCheckDebounce + const Duration(milliseconds: 1),
      );
      expect(verification.result.error, same(failure));
      expect(verification.result.validity, expected);
    }
    verification.dispose();
  });

  testWidgets(
    'nested retained manual content permits only no-content off-air',
    (tester) async {
      final controller = _AirController();
      addTearDown(controller.dispose);
      final channel = Channel.fromJson({
        ..._channel(items: [_item('retained')]).toJson(),
        'source': MixedSource(
          sources: [
            ManualSource([_item('retained')]),
          ],
        ).toJson(),
      });
      expect(
        hasNonemptyRetainedManualContent(
          const MixedSource(
            sources: [ManualSource([]), PlaylistSource('live')],
          ),
        ),
        isFalse,
      );
      final verification = AirCheckVerification(
        loadSchedule: controller.loadScheduleFor,
        clock: () => DateTime.utc(2026, 1, 1, 0, 10),
      );
      controller.nextFailure = const ScheduleBuildException(
        ScheduleFailureReason.noContent,
      );
      verification.update(channel, null, 0, null);
      await tester.pump();
      expect(
        verification.result.validity,
        ChannelAirCheckValidity.retainedOffAir,
      );
      controller.nextFailure = StateError('synthetic worker failure');
      verification.retry();
      await tester.pump(
        channelAirCheckDebounce + const Duration(milliseconds: 1),
      );
      expect(verification.result.validity, ChannelAirCheckValidity.unknown);
      expect(verification.result.error, isA<StateError>());
      verification.dispose();
    },
  );

  testWidgets(
    'partially playable mixed source reports every nested retained occurrence',
    (tester) async {
      final controller = _MixedAirController(
        scenario: LineupScenario(availableMedia: [_playableMedia('live')]),
      );
      addTearDown(controller.dispose);
      final channel = Channel.fromJson({
        ..._channel(items: [_item('live')]).toJson(),
        'source': MixedSource(
          sources: [
            ManualSource([_item('live'), _item('missing')]),
            MixedSource(
              sources: [
                ManualSource([_item('missing'), _item('other')]),
              ],
            ),
          ],
        ).toJson(),
      });

      await tester.pumpWidget(_airCheck(controller, channel));
      await tester.pumpAndSettle();

      const explanation =
          '3 unavailable hand-picked items are retained but off air until available or removed.';
      expect(find.text(explanation), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('3 unavailable hand-picked items')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'pending Air Check publishes the latest same-key channel identity',
    (tester) async {
      final controller = _AirController(controlled: true);
      addTearDown(controller.dispose);
      final original = _channel(items: [_item('one'), _item('two')]);
      await tester.pumpWidget(_airCheck(controller, original));
      expect(controller.requests, 1);
      final renamed = Channel.fromJson({
        ...original.toJson(),
        'name': 'Renamed while loading',
        'number': 9,
      });
      await tester.pumpWidget(_airCheck(controller, renamed));
      expect(controller.requests, 1);
      controller.completeNext();
      await tester.pumpAndSettle();
      final preview = tester
          .widget<ChannelAirCheck>(find.byType(ChannelAirCheck))
          .verification
          .result
          .preview!;
      expect(preview.channel.anchor, original.anchor);
      expect(preview.channel.shuffleSeed, original.shuffleSeed);
      expect(
        canonicalScheduleIdentity(preview.channel),
        canonicalScheduleIdentity(original),
      );
      expect(
        {
          'latest facts': find.textContaining('Ch 9 ·').evaluate().length,
          'latest program semantics': find
              .bySemanticsLabel(
                RegExp(r'Channel 9 Renamed while loading, .*current'),
              )
              .evaluate()
              .length,
          'old facts': find.textContaining('Ch 4 ·').evaluate().length,
          'schedule loads': controller.requests,
        },
        {
          'latest facts': 1,
          'latest program semantics': 1,
          'old facts': 0,
          'schedule loads': 1,
        },
      );
    },
  );

  testWidgets('on-now warning is exact and ignores identity-only edits', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 1, 1, 0, 10);
    final controller = _AirController();
    addTearDown(controller.dispose);
    final original = _channel(items: [_item('one'), _item('two')]);
    await tester.pumpWidget(
      _airCheck(
        controller,
        original,
        originalChannel: original,
        clock: () => now,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('air-check-on-now-warning')), findsNothing);

    final requestsBeforeRename = controller.requests;
    final renamed = Channel.fromJson({
      ...original.toJson(),
      'name': 'Renamed',
      'number': 9,
    });
    await tester.pumpWidget(
      _airCheck(
        controller,
        renamed,
        originalChannel: original,
        clock: () => now,
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('air-check-on-now-warning')), findsNothing);
    expect(find.textContaining('Ch 9 ·'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'Channel 9 Renamed, .*current')),
      findsOneWidget,
    );
    expect(controller.requests, requestsBeforeRename);

    final changed = Channel.fromJson({
      ...original.toJson(),
      'source': ManualSource([_item('two'), _item('one')]).toJson(),
    });
    await tester.pumpWidget(
      _airCheck(
        controller,
        changed,
        originalChannel: original,
        clock: () => now,
      ),
    );
    await tester.pump(
      channelAirCheckDebounce + const Duration(milliseconds: 1),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Saving these programming changes may change what is on now'),
      findsOneWidget,
    );
    final requests = controller.requests;
    now = DateTime.utc(2026, 1, 1, 0, 40);
    await tester.pump(const Duration(seconds: 30));
    expect(
      find.text('Saving these programming changes may change what is on now'),
      findsOneWidget,
    );
    expect(controller.requests, requests);
  });

  testWidgets('retry establishes the original schedule before warning', (
    tester,
  ) async {
    final controller = _AirController(controlled: true);
    addTearDown(controller.dispose);
    final original = _channel(items: [_item('one'), _item('two')]);
    await tester.pumpWidget(
      _airCheck(controller, original, originalChannel: original),
    );
    controller.failNext(StateError('first load failed'));
    await tester.pump();
    await tester.tap(find.text('Retry Air Check'));
    await tester.pump(
      channelAirCheckDebounce + const Duration(milliseconds: 1),
    );
    controller.completeNext();
    await tester.pump();
    await tester.pump();

    final changed = Channel.fromJson({
      ...original.toJson(),
      'source': ManualSource([_item('two'), _item('one')]).toJson(),
    });
    await tester.pumpWidget(
      _airCheck(controller, changed, originalChannel: original),
    );
    await tester.pump(
      channelAirCheckDebounce + const Duration(milliseconds: 1),
    );
    controller.completeNext();
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('air-check-on-now-warning')), findsOneWidget);
    expect(controller.requests, 3);
  });

  testWidgets(
    'baseline comparison failure keeps the draft visible and invalid until retry',
    (tester) async {
      final controller = _AirController(controlled: true);
      addTearDown(controller.dispose);
      var validity = ChannelAirCheckValidity.valid;
      final original = _channel(items: [_item('one'), _item('two')]);
      final changed = Channel.fromJson({
        ...original.toJson(),
        'source': ManualSource([_item('two'), _item('one')]).toJson(),
      });
      await tester.pumpWidget(
        _airCheck(
          controller,
          changed,
          originalChannel: original,
          onValidityChanged: (value) => validity = value,
        ),
      );
      expect(controller.requests, 1);
      controller.failNext(StateError('baseline worker unavailable'));
      await tester.pump();
      expect(controller.requests, 2);
      controller.completeNext();
      await tester.pump();
      await tester.pump();

      expect(find.text('Two'), findsWidgets);
      expect(
        find.textContaining('could not compare this draft'),
        findsOneWidget,
      );
      expect(find.text('Retry comparison'), findsOneWidget);
      expect(find.text('Out of date'), findsNothing);
      expect(validity, ChannelAirCheckValidity.unknown);
      expect(controller.requests, 2);

      await tester.ensureVisible(find.text('Retry comparison'));
      await tester.tap(find.text('Retry comparison'));
      await tester.pump(
        channelAirCheckDebounce + const Duration(milliseconds: 1),
      );
      expect(controller.requests, 3);
      controller.completeNext();
      await tester.pump();
      expect(controller.requests, 4);
      controller.completeNext();
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('could not compare this draft'), findsNothing);
      expect(find.byKey(const Key('air-check-on-now-warning')), findsOneWidget);
      expect(validity, ChannelAirCheckValidity.valid);
      expect(controller.requests, 4);
    },
  );

  testWidgets('an explicitly off-air original remains repairable', (
    tester,
  ) async {
    final controller = _AirController(controlled: true);
    addTearDown(controller.dispose);
    var validity = ChannelAirCheckValidity.unknown;
    final original = _channel(items: [_item('missing')]);
    final changed = Channel.fromJson({
      ...original.toJson(),
      'source': ManualSource([_item('replacement')]).toJson(),
    });
    await tester.pumpWidget(
      _airCheck(
        controller,
        changed,
        originalChannel: original,
        onValidityChanged: (value) => validity = value,
      ),
    );
    controller.failNext(
      const ScheduleBuildException(ScheduleFailureReason.noContent),
    );
    await tester.pump();
    controller.completeNext();
    await tester.pump();
    await tester.pump();

    expect(find.text('Replacement'), findsWidgets);
    expect(find.byKey(const Key('air-check-on-now-warning')), findsOneWidget);
    expect(find.textContaining('could not compare this draft'), findsNothing);
    expect(validity, ChannelAirCheckValidity.valid);
    expect(controller.requests, 2);
  });

  testWidgets('content generation refreshes original before the draft', (
    tester,
  ) async {
    final controller = _AirController(controlled: true);
    addTearDown(controller.dispose);
    final original = _channel(items: [_item('one'), _item('two')]);
    final changed = Channel.fromJson({
      ...original.toJson(),
      'source': ManualSource([_item('two'), _item('one')]).toJson(),
    });
    await tester.pumpWidget(
      _airCheck(controller, original, originalChannel: original),
    );
    controller.completeNext();
    await tester.pump();
    await tester.pump();
    await tester.pumpWidget(
      _airCheck(controller, changed, originalChannel: original),
    );
    await tester.pump(
      channelAirCheckDebounce + const Duration(milliseconds: 1),
    );
    controller.completeNext();
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('air-check-on-now-warning')), findsOneWidget);

    controller.generation++;
    await tester.pumpWidget(
      _airCheck(controller, changed, originalChannel: original),
    );
    await tester.pump(
      channelAirCheckDebounce + const Duration(milliseconds: 1),
    );
    expect(controller.requests, 3);
    controller.completeNext();
    await tester.pump();
    await tester.pump();
    expect(controller.requests, 4);
    controller.completeNext();
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('air-check-on-now-warning')), findsOneWidget);
    expect(controller.requests, 4);
  });

  testWidgets(
    'long-open rollover uses loaded schedule without live semantics',
    (tester) async {
      var now = DateTime.utc(2026, 1, 1, 0, 10);
      final controller = _AirController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _airCheck(
          controller,
          _channel(items: [_item('one'), _item('two'), _item('three')]),
          clock: () => now,
        ),
      );
      await tester.pumpAndSettle();
      now = DateTime.utc(2026, 1, 1, 8, 40);
      await tester.pump(const Duration(seconds: 30));

      expect(controller.requests, 1);
      expect(
        find.descendant(
          of: find.byKey(const Key('air-check-selection')),
          matching: find.text('Three'),
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
        findsNothing,
      );
    },
  );
}

Widget _airCheck(
  _AirController controller,
  Channel channel, {
  Key? key,
  DateTime Function()? clock,
  bool compact = false,
  String? sourceIssue,
  String inclusionReason = 'Hand-picked programming',
  Channel? originalChannel,
  ValueChanged<ChannelAirCheckValidity>? onValidityChanged,
  bool always24 = false,
  bool isTv = false,
  ThemeData? theme,
}) => MaterialApp(
  theme: theme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: always24),
    child: DeviceProfileScope(
      profile: profileFor(isTv),
      child: LineupCanvas(child: child!),
    ),
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 520,
          child: _VerificationSurface(
            key: key,
            controller: controller,
            channel: channel,
            originalChannel: originalChannel,
            clock: clock ?? () => DateTime.utc(2026, 1, 1, 0, 10),
            compact: compact,
            inclusionReason: inclusionReason,
            sourceIssue: sourceIssue,
            onValidityChanged: onValidityChanged,
          ),
        ),
      ),
    ),
  ),
);

class _VerificationSurface extends StatefulWidget {
  const _VerificationSurface({
    required this.controller,
    required this.channel,
    required this.clock,
    required this.compact,
    required this.inclusionReason,
    this.originalChannel,
    this.sourceIssue,
    this.onValidityChanged,
    super.key,
  });
  final _AirController controller;
  final Channel channel;
  final Channel? originalChannel;
  final DateTime Function() clock;
  final bool compact;
  final String inclusionReason;
  final String? sourceIssue;
  final ValueChanged<ChannelAirCheckValidity>? onValidityChanged;
  @override
  State<_VerificationSurface> createState() => _VerificationSurfaceState();
}

class _VerificationSurfaceState extends State<_VerificationSurface> {
  late final AirCheckVerification verification;
  @override
  void initState() {
    super.initState();
    verification = AirCheckVerification(
      loadSchedule: widget.controller.loadScheduleFor,
      clock: () => widget.clock(),
    );
    verification.addListener(_observed);
    _update();
  }

  void _observed() =>
      widget.onValidityChanged?.call(verification.result.validity);
  void _update() => verification.update(
    widget.channel,
    widget.originalChannel,
    widget.controller.contentGeneration,
    widget.sourceIssue,
    sourceLabel: widget.inclusionReason,
  );
  @override
  void didUpdateWidget(_VerificationSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  @override
  void dispose() {
    verification.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChannelAirCheck(
    controller: widget.controller,
    channel: widget.channel,
    originalChannel: widget.originalChannel,
    clock: widget.clock,
    compact: widget.compact,
    inclusionReason: widget.inclusionReason,
    sourceIssue: widget.sourceIssue,
    verification: verification,
  );
}

Channel _channel({
  required List<ChannelItem> items,
  PlaybackMode mode = PlaybackMode.sequential,
  int? blockSize,
}) => Channel(
  id: 'channel',
  number: 4,
  name: 'Test channel',
  source: ManualSource(items),
  playbackMode: mode,
  anchor: DateTime.utc(2026),
  shuffleSeed: 17,
  blockSize: blockSize,
);

ChannelItem _item(String id) => ChannelItem(
  id: id,
  title: id[0].toUpperCase() + id.substring(1),
  duration: const Duration(minutes: 30),
);

String _formatted(DateTime value, {bool always24 = false}) =>
    const DefaultMaterialLocalizations().formatTimeOfDay(
      TimeOfDay.fromDateTime(value.toLocal()),
      alwaysUse24HourFormat: always24,
    );

class _AirController extends FixtureController {
  _AirController({super.scenario, this.controlled = false});

  final bool controlled;
  final _pending = <(Completer<ScheduleIndex>, ScheduleIndex)>[];
  int requests = 0;
  int generation = 0;
  Object? nextFailure;
  ScheduleIndex? scheduleOverride;

  @override
  int get contentGeneration => generation;

  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) {
    requests++;
    if (nextFailure case final error?) {
      nextFailure = null;
      return Future.error(error);
    }
    final source = channel.source as ManualSource;
    if (source.items.isEmpty) {
      return Future.error(
        const ScheduleBuildException(ScheduleFailureReason.noContent),
      );
    }
    final schedule =
        scheduleOverride ??
        buildSchedule(
          source.items,
          mode: channel.playbackMode,
          seed: channel.shuffleSeed,
          blockSize: channel.blockSize ?? 3,
        );
    if (!controlled) return Future.value(schedule);
    final completer = Completer<ScheduleIndex>();
    _pending.add((completer, schedule));
    return completer.future;
  }

  void completeNext() {
    final request = _pending.removeAt(0);
    request.$1.complete(request.$2);
  }

  void failNext(Object error) {
    _pending.removeAt(0).$1.completeError(error);
  }
}

class _MixedAirController extends _AirController {
  _MixedAirController({super.scenario});
  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) async => buildSchedule(
    [_item('live')],
    mode: channel.playbackMode,
    seed: channel.shuffleSeed,
    blockSize: channel.blockSize ?? 3,
  );
}

PlexMediaItem _playableMedia(String id) => PlexMediaItem(
  id: id,
  title: 'Live',
  type: 'movie',
  duration: const Duration(minutes: 30),
  libraryId: 'movies',
  parts: [PlexMediaPart(path: '/$id')],
);
