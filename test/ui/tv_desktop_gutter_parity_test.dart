import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/ui/app_ui.dart';

import '../support/golden_test_support.dart';
import '../support/ui_fixture.dart';

void main() {
  for (final stage in [SetupStage.channelSetup, SetupStage.ready]) {
    testWidgets('TV uses desktop gutters for equal content at $stage', (
      tester,
    ) async {
      await tester.runAsync(loadPinnedTestFonts);
      tester.view
        ..physicalSize = const Size(1920, 1080)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final geometry = <bool, Map<String, Rect>>{};
      for (final tv in [false, true]) {
        final fixture = UiFixture(
          profile: profileFor(tv),
          scenario: LineupScenario(stage: stage),
          guideClock: () => DateTime(2026, 1, 15, 12),
        );
        await tester.pumpWidget(fixture.build());
        await tester.pumpAndSettle();
        final rects = <String, Rect>{};
        if (stage == SetupStage.channelSetup) {
          rects['top bar'] = tester.getRect(
            find.byKey(const ValueKey('lineup-top-bar')),
          );
          rects['setup content'] = tester.getRect(
            find
                .descendant(
                  of: find.byType(LineupContentWidth).first,
                  matching: find.byType(Align),
                )
                .first,
          );
          rects['top bar logo'] = tester.getRect(
            find
                .descendant(
                  of: find.byType(LineupTopBar),
                  matching: find.byType(Image),
                )
                .first,
          );
          expect(rects['top bar logo']!.left, 48);
          expect(rects['top bar'], const Rect.fromLTWH(0, 0, 1920, 80));
          expect(rects['setup content']!.left, 48);
          expect(rects['setup content']!.right, 1872);
        } else {
          rects['guide edges'] = tester.getRect(
            find.byKey(const Key('classic-guide')),
          );
          expect(rects['guide edges'], const Rect.fromLTWH(0, 0, 1920, 1080));
          await openDestination(tester, 'Settings');
          rects['settings rail'] = tester.getRect(
            find.byKey(const Key('settings-category-rail')),
          );
          rects['settings detail'] = tester.getRect(
            find.byKey(const Key('settings-detail-pane')),
          );
        }
        geometry[tv] = rects;
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.controller.dispose();
      }
      expect(geometry[true], geometry[false]);
    });
  }
}
