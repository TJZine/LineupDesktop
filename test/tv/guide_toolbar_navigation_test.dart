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
import 'package:lineup_desktop/ui/lineup_canvas.dart';
import 'package:lineup_desktop/ui/lineup_focus.dart';

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

Rect _drawnRect(WidgetTester tester, Finder finder) =>
    Rect.fromPoints(tester.getTopLeft(finder), tester.getBottomRight(finder));

String _expectedToolbarControl(WidgetTester tester, {double? target}) {
  final guide = tester.widget<GuideView>(find.byType(GuideView)).controller;
  final cell = _drawnRect(
    tester,
    find.byKey(ValueKey(guide.focusedProgramId!)),
  );
  final timeline = _drawnRect(
    tester,
    find.byKey(ValueKey('guide-timeline-${guide.focusedChannelId}')),
  );
  final visibleCell = cell.intersect(timeline);
  final targetX =
      target ?? (visibleCell.isEmpty ? cell : visibleCell).center.dx;
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
        (_drawnRect(tester, _toolbarFinder(nearest)).center.dx - targetX).abs();
    final candidateDistance =
        (_drawnRect(tester, _toolbarFinder(candidate)).center.dx - targetX)
            .abs();
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

UiFixture _geometryFixture({required bool isTv, int channelCount = 2}) =>
    UiFixture(
      profile: profileFor(isTv),
      guideClock: () => DateTime.utc(2026, 1, 15, 3, 17),
      controller: _GuideFixtureController(
        scenario: LineupScenario(
          stage: SetupStage.ready,
          settings: const LineupSettings(reduceMotion: true),
          channels: [
            for (var row = 0; row < channelCount; row++)
              Channel(
                id: 'geometry-$row',
                number: row + 1,
                name: 'Geometry $row',
                source: const ManualSource([
                  ChannelItem(
                    id: 'long',
                    title: 'Long program',
                    duration: Duration(minutes: 67),
                  ),
                  ChannelItem(
                    id: 'short',
                    title: 'Short program',
                    duration: Duration(minutes: 37),
                  ),
                ]),
                playbackMode: PlaybackMode.sequential,
                anchor: DateTime.utc(2026, 1, 15, 3),
                shuffleSeed: 1,
              ),
          ],
        ),
      ),
    );

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    for (final tv in [false, true]) {
      testWidgets(
        'L2 Guide aliases and modality follow capability $platform TV=$tv',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          final fixture = _geometryFixture(isTv: tv, channelCount: 12);
          try {
            await tester.pumpWidget(fixture.build());
            await _settle(tester);
            final guide = tester.widget<GuideView>(find.byType(GuideView));
            guide.focusNode!.requestFocus();
            await tester.pumpAndSettle();
            await tester.tapAt(const Offset(5, 5));
            await tester.pumpAndSettle();
            expect(
              LineupFocusScope.visible(tester.element(find.byType(GuideView))),
              isFalse,
            );
            final before = guide.controller.focusedChannelId;
            await tester.sendKeyEvent(
              LogicalKeyboardKey.channelDown,
              // Deliver the remote logical event without pretending Windows
              // has a native ChannelDown scan-code mapping.
              platform: 'android',
              physicalKey: PhysicalKeyboardKey.pageDown,
            );
            await tester.pumpAndSettle();
            expect(guide.controller.focusedChannelId == before, !tv);
            expect(
              LineupFocusScope.visible(tester.element(find.byType(GuideView))),
              tv,
            );
            await tester.sendKeyEvent(
              LogicalKeyboardKey.contextMenu,
              platform: 'android',
              physicalKey: PhysicalKeyboardKey.contextMenu,
            );
            await tester.pumpAndSettle();
            expect(
              find.byKey(const Key('immersive-app-menu')),
              tv ? findsOneWidget : findsNothing,
            );
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            fixture.controller.dispose();
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );
    }
  }

  for (final window in const [Size(960, 540), Size(1920, 1080)]) {
    testWidgets(
      'TV Guide fills the screen and displays five full rows: $window',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        tester.view
          ..physicalSize = window * 2
          ..devicePixelRatio = 2;
        try {
          await tester.pumpWidget(
            _geometryFixture(isTv: true, channelCount: 6).build(),
          );
          await _settle(tester);
          final guide = find.byKey(const Key('classic-guide'));
          final rect = _drawnRect(tester, guide);
          expect(rect, Offset.zero & window);
          expect(tester.getSize(guide), const Size(1920, 1080));
          expect(MediaQuery.paddingOf(tester.element(guide)), EdgeInsets.zero);
          for (var i = 0; i < 5; i++) {
            final channel = find.bySemanticsLabel(
              RegExp('^Channel ${i + 1}, Geometry $i'),
            );
            final bounds = _drawnRect(tester, channel);
            expect(bounds.left, greaterThanOrEqualTo(rect.left - .001));
            expect(bounds.top, greaterThanOrEqualTo(rect.top));
            expect(bounds.bottom, lessThanOrEqualTo(rect.bottom + .001));
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          tester.view.reset();
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
  for (final scale in [0.8, 2 / 3, 0.5]) {
    testWidgets('TV toolbar uses full rendered bounds at scale $scale', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view
        ..physicalSize = const Size(1920, 1080)
        ..devicePixelRatio = 2;
      try {
        final fixture = _geometryFixture(isTv: true);
        await tester.pumpWidget(
          Transform.scale(
            scale:
                scale /
                LineupCanvas.scaleFor(
                  const Size(960, 540),
                  formFactor: profileFor(true).formFactor,
                ),
            alignment: Alignment.topLeft,
            child: fixture.build(),
          ),
        );
        await _settle(tester);
        final guide = tester.widget<GuideView>(find.byType(GuideView));
        var crossingCases = 0;
        var positions = 0;
        for (var window = 0; window < 2; window++) {
          for (final program in guide.controller.row('geometry-0').programs) {
            guide.controller.focusProgram(program);
            await tester.pump();
            final cellFinder = find.byKey(ValueKey(program.id));
            final timelineFinder = find.byKey(
              const ValueKey('guide-timeline-geometry-0'),
            );
            final cellRect = _drawnRect(tester, cellFinder);
            final timelineRect = _drawnRect(tester, timelineFinder);
            expect(
              cellRect.width / tester.getSize(cellFinder).width,
              closeTo(scale, 0.0001),
            );
            final expected = _expectedToolbarControl(tester);
            // Deliberate previous defect: transformed origins with canvas sizes.
            final mixedCell = cellRect.topLeft & tester.getSize(cellFinder);
            final mixedTimeline =
                timelineRect.topLeft & tester.getSize(timelineFinder);
            final wrongTarget = mixedCell.intersect(mixedTimeline).center.dx;
            if (_expectedToolbarControl(tester, target: wrongTarget) !=
                expected) {
              crossingCases++;
            }
            guide.focusNode!.requestFocus();
            await tester.pump();
            await _key(tester, _up);
            _expectToolbarFocus(tester, expected);
            await _key(tester, _down);
            positions++;
          }
          guide.controller.moveWindow(1);
          await tester.pump();
        }
        expect(positions, greaterThanOrEqualTo(2));
        expect(
          crossingCases,
          greaterThan(0),
          reason: 'the fixture must distinguish the mixed-coordinate defect',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.view.reset();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  for (final isTv in [false, true]) {
    testWidgets('Guide keeps mounted cell and timeline identity (TV: $isTv)', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = isTv
          ? TargetPlatform.android
          : TargetPlatform.macOS;
      try {
        final fixture = _geometryFixture(isTv: isTv);
        await tester.pumpWidget(fixture.build());
        await _settle(tester);
        final guide = tester.widget<GuideView>(find.byType(GuideView));
        final programs = [
          ...guide.controller.row('geometry-0').programs,
          ...guide.controller.row('geometry-1').programs,
        ];
        expect(programs.length, greaterThanOrEqualTo(4));
        final elements = {
          for (final program in programs)
            program.id: tester.element(find.byKey(ValueKey(program.id))),
        };
        final states = {
          for (final program in programs)
            program.id: tester.state(find.byKey(ValueKey(program.id))),
        };
        final timelines = {
          for (var row = 0; row < 2; row++)
            row: tester.element(
              find.byKey(ValueKey('guide-timeline-geometry-$row')),
            ),
        };
        for (final selected in programs.reversed) {
          guide.controller.focusProgram(selected);
          await tester.pump();
          for (final program in programs) {
            final finder = find.byKey(ValueKey(program.id));
            expect(tester.element(finder), same(elements[program.id]));
            expect(tester.state(finder), same(states[program.id]));
          }
          for (var row = 0; row < 2; row++) {
            expect(
              tester.element(
                find.byKey(ValueKey('guide-timeline-geometry-$row')),
              ),
              same(timelines[row]),
            );
          }
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

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
      profile: profileFor(true),
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
          find.byKey(ValueKey(program.id)),
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
      await _key(tester, LogicalKeyboardKey.info);
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
      profile: profileFor(false),
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
