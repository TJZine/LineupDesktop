import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/lineup_controls.dart';

import '../support/ui_fixture.dart';

Color? _ink(WidgetTester tester, Finder text) => tester
    .widget<RichText>(
      find.descendant(of: text, matching: find.byType(RichText)),
    )
    .text
    .style
    ?.color;

void main() {
  testWidgets('TV Guide raw dropdowns read focused leaf ink', (tester) async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    final fixture = UiFixture(
      androidTv: true,
      scenario: const LineupScenario(stage: SetupStage.ready),
    );
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    for (final key in ['guide-library-picker', 'guide-hours']) {
      final picker = find.byKey(Key(key));
      final baseSurface = LineupTheme.of(tester.element(picker))
          .elevatedSurface;
      final trigger = tester.widget<InkWell>(
        find.descendant(of: picker, matching: find.byType(InkWell)).first,
      );
      // Position the component test at the real trigger; subsequent open/close
      // uses keys. Native consumer navigation is checked separately.
      trigger.focusNode!.requestFocus();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      trigger.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      final label = find
          .descendant(of: picker, matching: find.byType(Text))
          .hitTestable()
          .first;
      expect(_ink(tester, label), const Color(0xFF090806), reason: key);
      final surface = switch (tester.widget(picker)) {
        DropdownButton<int>(:final dropdownColor) => dropdownColor,
        DropdownButton<String?>(:final dropdownColor) => dropdownColor,
        _ => null,
      };
      expect(surface, baseSurface);
      final icon = find.descendant(
        of: picker,
        matching: find.byIcon(Icons.arrow_drop_down),
      );
      expect(IconTheme.of(tester.element(icon)).color, const Color(0xFF3B3226));
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(LineupDropdownMenuRow), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.controller.dispose();
  });

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.windows,
    TargetPlatform.macOS,
  ]) {
    testWidgets(
      '$platform Channels issue and directory styles resolve inside the row focus scope',
      (tester) async {
        final tv = platform == TargetPlatform.android;
        debugDefaultTargetPlatformOverride = platform;
        try {
          final fixture = UiFixture(
            androidTv: tv,
            controller: _IssueController(
              LineupScenario(
                stage: SetupStage.ready,
                channels: [
                  Channel(
                    id: 'focus-channel',
                    number: 7,
                    name: 'Focus channel',
                    source: const ManualSource([]),
                    playbackMode: PlaybackMode.shuffle,
                    anchor: DateTime.utc(2026),
                    shuffleSeed: 0,
                  ),
                ],
              ),
            ),
          );
          await tester.pumpWidget(fixture.build());
          await tester.pumpAndSettle();
          await openDestination(tester, 'Channels');
          final row = find.byKey(const ValueKey('channel-row-focus-channel'));
          final name = find.descendant(
            of: row,
            matching: find.text('Focus channel'),
          );
          final element = tester.element(name);
          final node = tester
              .widget<InkWell>(
                find.descendant(of: row, matching: find.byType(InkWell)).first,
              )
              .focusNode!;
          node.requestFocus();
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          node.requestFocus();
          await tester.pumpAndSettle();
          expect(node.hasFocus, isTrue);
          expect(
            _ink(tester, name),
            tv ? const Color(0xFF090806) : const Color(0xFFF3E8D2),
          );
          final number = find.descendant(of: row, matching: find.text('7'));
          expect(
            _ink(tester, number),
            LineupTheme.of(tester.element(number)).secondaryText,
          );
          expect(tester.element(name), same(element));
          // The view contract receives a deterministic schedule failure. Native
          // acceptance separately exercises the real worker with invalid content.
          final issue = find.text(
            'Schedule issue — open this channel to recover',
          );
          expect(issue, findsOneWidget);
          final issueElement = tester.element(issue);
          final focusedInk = _ink(tester, issue)!;
          expect(
            focusedInk,
            tv
                ? const Color(0xFF090806)
                : Theme.of(tester.element(issue)).colorScheme.error,
          );
          if (tv) {
            expect(
              (const Color(0xFFE9DCC3).computeLuminance() + .05) /
                  (focusedInk.computeLuminance() + .05),
              greaterThan(4.5),
            );
          }
          node.unfocus();
          await tester.pumpAndSettle();
          expect(
            _ink(tester, issue),
            Theme.of(tester.element(issue)).colorScheme.error,
          );
          expect(tester.element(issue), same(issueElement));
          await tester.pumpWidget(const SizedBox.shrink());
          fixture.controller.dispose();
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
}

class _IssueController extends FixtureController {
  _IssueController(LineupScenario scenario) : super(scenario: scenario);
  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) => Future.error(
    const ScheduleBuildException(ScheduleFailureReason.noContent),
  );
}
