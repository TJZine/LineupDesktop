import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/app/channel_air_check.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

import '../support/ui_fixture.dart';

void main() {
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
    final first = _channel(items: [_item('one')]);
    final second = _channel(items: [_item('two')]);
    final latest = _channel(items: [_item('three')]);

    await tester.pumpWidget(_airCheck(controller, first));
    expect(controller.requests, 1);
    await tester.pumpWidget(_airCheck(controller, second));
    await tester.pump(
      channelAirCheckDebounce + const Duration(milliseconds: 1),
    );
    await tester.pumpWidget(_airCheck(controller, latest));
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
    expect(find.text('Three'), findsWidgets);
    expect(find.text('One'), findsNothing);
    expect(find.text('Two'), findsNothing);
  });

  testWidgets('same-key source recovery keeps the newest pending request', (
    tester,
  ) async {
    final controller = _AirController(controlled: true);
    addTearDown(controller.dispose);
    final channel = _channel(items: [_item('latest')]);
    await tester.pumpWidget(_airCheck(controller, channel));
    await tester.pumpWidget(
      _airCheck(controller, channel, sourceIssue: 'Incomplete source choice'),
    );
    await tester.pumpWidget(_airCheck(controller, channel));
    await tester.pump(
      channelAirCheckDebounce + const Duration(milliseconds: 1),
    );

    expect(controller.requests, 1);
    controller.completeNext();
    await tester.pump();
    expect(controller.requests, 2);
    controller.completeNext();
    await tester.pump();
    expect(find.text('Latest'), findsWidgets);
    expect(controller.requests, 2);
  });

  testWidgets('content generation, retry, and disposal reject stale results', (
    tester,
  ) async {
    final controller = _AirController(controlled: true);
    addTearDown(controller.dispose);
    final channel = _channel(items: [_item('one')]);
    await tester.pumpWidget(_airCheck(controller, channel));
    controller.generation++;
    await tester.pumpWidget(_airCheck(controller, channel));
    await tester.pump(
      channelAirCheckDebounce + const Duration(milliseconds: 1),
    );
    expect(controller.requests, 1);
    controller.completeNext();
    await tester.pump();
    expect(controller.requests, 2);
    controller.failNext(StateError('synthetic worker failure'));
    await tester.pump();
    expect(find.textContaining('could not verify'), findsOneWidget);

    await tester.tap(find.text('Retry Air Check'));
    await tester.pump(
      channelAirCheckDebounce + const Duration(milliseconds: 1),
    );
    expect(controller.requests, 3);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.completeNext();
    await tester.pump();
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
      // scrollUntilVisible jumps both nested scrollables; lay out before tapping.
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

  testWidgets('failure states gate validity except retained manual off-air', (
    tester,
  ) async {
    final controller = _AirController();
    addTearDown(controller.dispose);
    var validity = ChannelAirCheckValidity.valid;
    await tester.pumpWidget(
      _airCheck(
        controller,
        _channel(items: const []),
        onValidityChanged: (value) => validity = value,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('no playable programs'), findsOneWidget);
    expect(validity, ChannelAirCheckValidity.unknown);

    controller.nextFailure = const ScheduleBuildException(
      ScheduleFailureReason.unsupportedSource,
    );
    await tester.pumpWidget(
      _airCheck(
        controller,
        _channel(items: [_item('unsupported')]),
        onValidityChanged: (value) => validity = value,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('unsupported filter'), findsOneWidget);
    expect(validity, ChannelAirCheckValidity.unknown);

    controller.nextFailure = const ScheduleBuildException(
      ScheduleFailureReason.noContent,
    );
    await tester.pumpWidget(
      _airCheck(
        controller,
        _channel(items: [_item('missing')]),
        onValidityChanged: (value) => validity = value,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('explicitly off air'), findsOneWidget);
    expect(validity, ChannelAirCheckValidity.retainedOffAir);

    controller.nextFailure = StateError('Schedule worker is unavailable');
    await tester.pumpWidget(
      _airCheck(
        controller,
        _channel(items: [_item('retained')]),
        onValidityChanged: (value) => validity = value,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('could not verify'), findsOneWidget);
    expect(validity, ChannelAirCheckValidity.unknown);
  });

  testWidgets(
    'nested retained manual content permits only no-content off-air',
    (tester) async {
      final controller = _AirController();
      addTearDown(controller.dispose);
      var validity = ChannelAirCheckValidity.valid;
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

      controller.nextFailure = const ScheduleBuildException(
        ScheduleFailureReason.noContent,
      );
      await tester.pumpWidget(
        _airCheck(
          controller,
          channel,
          onValidityChanged: (value) => validity = value,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('explicitly off air'), findsOneWidget);
      expect(validity, ChannelAirCheckValidity.retainedOffAir);

      controller.nextFailure = StateError('synthetic worker failure');
      await tester.pumpWidget(
        _airCheck(
          controller,
          channel,
          key: UniqueKey(),
          onValidityChanged: (value) => validity = value,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('could not verify'), findsOneWidget);
      expect(validity, ChannelAirCheckValidity.unknown);
    },
  );

  testWidgets(
    'partially playable mixed source reports every nested retained occurrence',
    (tester) async {
      final controller = _MixedAirController()
        ..availableMedia = [_playableMedia('live')];
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
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: always24),
    child: LineupCanvas(child: child!),
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 520,
          child: ChannelAirCheck(
            key: key,
            controller: controller,
            channel: channel,
            originalChannel: originalChannel,
            clock: clock ?? () => DateTime.utc(2026, 1, 1, 0, 10),
            compact: compact,
            inclusionReason: inclusionReason,
            sourceIssue: sourceIssue,
            onValidityChanged: (status) =>
                onValidityChanged?.call(status.validity),
          ),
        ),
      ),
    ),
  ),
);

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
  _AirController({this.controlled = false});

  final bool controlled;
  final _pending = <(Completer<ScheduleIndex>, ScheduleIndex)>[];
  int requests = 0;
  int generation = 0;
  Object? nextFailure;

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
    final schedule = buildSchedule(
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
