import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/guide/guide_view.dart';
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

bool _hasFocus(FocusNode node) => node.hasPrimaryFocus;

void _expectToolbarFocus(WidgetTester tester, String name) {
  final node = switch (name) {
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
      tester
          .widget<IconButton>(find.byKey(const Key('guide-later')))
          .focusNode!,
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
              (widget) =>
                  widget is IconButton && widget.tooltip == 'Close Guide',
            ),
          )
          .focusNode!,
    _ => throw StateError('Unknown Guide toolbar control: $name'),
  };
  expect(_hasFocus(node), isTrue, reason: '$name should own TV focus');
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
      androidTv: true,
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
    );
    try {
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      final guide = tester.widget<GuideView>(find.byType(GuideView));
      final before = (
        channel: guide.controller.focusedChannelId,
        program: guide.controller.focusedProgramId,
        time: guide.controller.focusTime,
      );
      guide.controller.moveWindow(1);
      await tester.pumpAndSettle();
      guide.focusNode!.requestFocus();
      await tester.pumpAndSettle();

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
      await _key(tester, _up);
      expect(
        controls.any((name) {
          try {
            _expectToolbarFocus(tester, name);
            return true;
          } on TestFailure {
            return false;
          }
        }),
        isTrue,
        reason: 'Up from the first Guide row enters the toolbar',
      );

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
      expect(guide.controller.focusedProgramId, before.program);
      expect(guide.controller.focusTime, before.time);

      await _key(tester, LogicalKeyboardKey.contextMenu);
      expect(find.byKey(const Key('immersive-app-menu')), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.reset();
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets('desktop Guide keeps its existing Tab order', (tester) async {
    final fixture = UiFixture(
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
    );
    try {
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
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
    }
  });
}
