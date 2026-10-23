import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_view.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/lineup_text_field_activation.dart';

import '../support/ui_fixture.dart';

const _up = LogicalKeyboardKey.arrowUp;
const _down = LogicalKeyboardKey.arrowDown;
const _left = LogicalKeyboardKey.arrowLeft;
const _right = LogicalKeyboardKey.arrowRight;

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

bool _hasFocus(FocusNode node) => node.hasPrimaryFocus;

FocusNode _toolbarNode(WidgetTester tester, String name) => switch (name) {
  'library' =>
    tester
        .widget<DropdownButton<String?>>(
          find.byKey(const Key('guide-library-picker')),
        )
        .focusNode!,
  'search' =>
    tester
        .widget<LineupTextFieldActivation>(
          find.byType(LineupTextFieldActivation),
        )
        .focusNode!,
  'earlier' =>
    tester
        .widget<IconButton>(find.byKey(const Key('guide-earlier')))
        .focusNode!,
  'now' =>
    tester.widget<TextButton>(find.byKey(const Key('guide-now'))).focusNode!,
  'later' =>
    tester.widget<IconButton>(find.byKey(const Key('guide-later'))).focusNode!,
  'hours' =>
    tester
        .widget<DropdownButton<int>>(find.byKey(const Key('guide-hours')))
        .focusNode!,
  'menu' =>
    tester
        .widget<TextButton>(find.byKey(const Key('guide-app-menu')))
        .focusNode!,
  'close' =>
    tester
        .widget<IconButton>(
          find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == 'Close Guide',
          ),
        )
        .focusNode!,
  _ => throw StateError('Unknown Guide toolbar control: $name'),
};

Finder _toolbarFinder(String name) => switch (name) {
  'library' => find.byKey(const Key('guide-library-picker')),
  'search' => find.byKey(const Key('guide-channel-search')),
  'earlier' => find.byKey(const Key('guide-earlier')),
  'now' => find.byKey(const Key('guide-now')),
  'later' => find.byKey(const Key('guide-later')),
  'hours' => find.byKey(const Key('guide-hours')),
  'menu' => find.byKey(const Key('guide-app-menu')),
  'close' => find.byTooltip('Close Guide'),
  _ => throw StateError('Unknown Guide toolbar control: $name'),
};

String _expectedToolbarControl(WidgetTester tester) {
  final cell = tester.getRect(find.byKey(const Key('guide-focused-program')));
  final timeline = tester.getRect(
    find.byKey(const Key('guide-focused-timeline')),
  );
  final visibleCell = cell.intersect(timeline);
  final targetX = (visibleCell.isEmpty ? cell : visibleCell).center.dx;
  const controls = [
    'library',
    'search',
    'earlier',
    'now',
    'later',
    'hours',
    'menu',
    'close',
  ];
  final candidates = controls.where(
    (name) => _toolbarNode(tester, name).canRequestFocus,
  );
  return candidates.reduce((nearest, candidate) {
    final nearestDistance =
        (tester.getRect(_toolbarFinder(nearest)).center.dx - targetX).abs();
    final candidateDistance =
        (tester.getRect(_toolbarFinder(candidate)).center.dx - targetX).abs();
    return candidateDistance < nearestDistance ? candidate : nearest;
  });
}

void _expectToolbarFocus(WidgetTester tester, String name) {
  expect(
    _hasFocus(_toolbarNode(tester, name)),
    isTrue,
    reason: '$name should own TV focus',
  );
}

class _GuideFixtureController extends FixtureController {
  _GuideFixtureController({super.scenario});

  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) async =>
      buildChannelSchedule(channel, (channel.source as ManualSource).items);
}

void main() {
  testWidgets('TV Guide walks the toolbar and returns to the same grid cell', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view
      ..physicalSize = const Size(1920, 1080)
      ..devicePixelRatio = 2;
    final fixture = UiFixture(
      controller: _GuideFixtureController(
        scenario: LineupScenario(
          stage: SetupStage.ready,
          channels: [
            Channel(
              id: 'fixture',
              number: 1,
              name: 'Fixture channel',
              source: const ManualSource([
                ChannelItem(
                  id: 'program-1',
                  title: 'Fixture program one',
                  duration: Duration(minutes: 30),
                ),
                ChannelItem(
                  id: 'program-2',
                  title: 'Fixture program two',
                  duration: Duration(minutes: 30),
                ),
                ChannelItem(
                  id: 'program-3',
                  title: 'Fixture program three',
                  duration: Duration(minutes: 30),
                ),
                ChannelItem(
                  id: 'program-4',
                  title: 'Fixture program four',
                  duration: Duration(minutes: 30),
                ),
              ]),
              playbackMode: PlaybackMode.sequential,
              anchor: DateTime.utc(2026),
              shuffleSeed: 1,
            ),
          ],
          settings: const LineupSettings(guideHours: 4),
        ),
      ),
      androidTv: true,
    );
    try {
      await tester.pumpWidget(fixture.build());
      await _settle(tester);
      final guide = tester.widget<GuideView>(find.byType(GuideView));
      final before = (
        channel: guide.controller.focusedChannelId,
        program: guide.controller.focusedProgramId,
        time: guide.controller.focusTime,
      );
      guide.controller.moveWindow(1);
      await _settle(tester);
      guide.focusNode!.requestFocus();
      await tester.pumpAndSettle();

      final programs = guide.controller.row('fixture').programs;
      expect(programs.length, greaterThanOrEqualTo(3));
      final firstProgram = programs.first;
      final secondProgram = programs[programs.length ~/ 2];
      for (final program in [firstProgram, secondProgram]) {
        guide.controller.focusProgram(program);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('guide-focused-program')),
          findsOneWidget,
          reason:
              'row=${guide.controller.row('fixture').state} '
              'rowPrograms=${guide.controller.row('fixture').programs.length} '
              'focusedChannel=${guide.controller.focusedChannelId} '
              'focusedProgram=${guide.controller.focusedProgramId}',
        );
        final expected = _expectedToolbarControl(tester);
        guide.focusNode!.requestFocus();
        await tester.pumpAndSettle();
        await _key(tester, _up);
        _expectToolbarFocus(tester, expected);
        await _key(tester, _down);
        expect(guide.focusNode!.hasPrimaryFocus, isTrue);
      }

      final controls = [
        'library',
        'search',
        'earlier',
        'now',
        'later',
        'hours',
        'menu',
        'close',
      ];
      guide.controller.focusProgram(firstProgram);
      await tester.pumpAndSettle();
      guide.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      await _key(tester, _up);
      _expectToolbarFocus(tester, _expectedToolbarControl(tester));

      var current = controls.indexWhere((name) {
        try {
          _expectToolbarFocus(tester, name);
          return true;
        } on TestFailure {
          return false;
        }
      });
      expect(current, greaterThanOrEqualTo(0));
      while (current > 0) {
        await _key(tester, _left);
        current--;
        _expectToolbarFocus(tester, controls[current]);
      }
      for (var i = 1; i < controls.length; i++) {
        await _key(tester, _right);
        _expectToolbarFocus(tester, controls[i]);
      }

      await _key(tester, _down);
      expect(guide.focusNode!.hasPrimaryFocus, isTrue);
      expect(guide.controller.focusedChannelId, before.channel);
      expect(guide.controller.focusedProgramId, firstProgram.id);

      final search = _toolbarNode(tester, 'search');
      search.requestFocus();
      await tester.pumpAndSettle();
      await _key(tester, LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await _key(tester, LogicalKeyboardKey.keyI);
      expect(find.byKey(const Key('immersive-app-menu')), findsNothing);

      guide.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      await _key(tester, LogicalKeyboardKey.contextMenu);
      expect(find.byKey(const Key('immersive-app-menu')), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.reset();
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets('desktop Guide keeps its existing Tab order', (tester) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final fixture = UiFixture(
      controller: _GuideFixtureController(
        scenario: LineupScenario(
          stage: SetupStage.ready,
          channels: [
            Channel(
              id: 'fixture',
              number: 1,
              name: 'Fixture channel',
              source: const ManualSource([
                ChannelItem(
                  id: 'program',
                  title: 'Fixture program',
                  duration: Duration(minutes: 30),
                ),
              ]),
              playbackMode: PlaybackMode.sequential,
              anchor: DateTime.utc(2026),
              shuffleSeed: 1,
            ),
          ],
        ),
      ),
      androidTv: false,
    );
    try {
      await tester.pumpWidget(fixture.build());
      await _settle(tester);
      final guide = tester.widget<GuideView>(find.byType(GuideView));
      final before = (
        channel: guide.controller.focusedChannelId,
        program: guide.controller.focusedProgramId,
      );
      guide.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      await _key(tester, _up);
      expect(guide.focusNode!.hasPrimaryFocus, isTrue);
      expect(guide.controller.focusedChannelId, before.channel);
      expect(guide.controller.focusedProgramId, before.program);

      final now = _toolbarNode(tester, 'now');
      now.requestFocus();
      await tester.pumpAndSettle();
      await _key(tester, _left);
      expect(
        now.hasPrimaryFocus,
        isFalse,
        reason: 'desktop ArrowLeft should retain the existing baseline',
      );
      expect(guide.focusNode!.hasPrimaryFocus, isTrue);
      await _key(tester, _right);
      expect(now.hasPrimaryFocus, isFalse);
      expect(guide.focusNode!.hasPrimaryFocus, isTrue);

      final activation = tester.widget<LineupTextFieldActivation>(
        find.byType(LineupTextFieldActivation),
      );
      activation.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      await _key(tester, LogicalKeyboardKey.tab);
      _expectToolbarFocus(tester, 'now');
      await _key(tester, LogicalKeyboardKey.tab);
      _expectToolbarFocus(tester, 'later');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });
}
