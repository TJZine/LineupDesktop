import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/settings_view.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';

import '../support/ui_fixture.dart';

Future<void> show(
  WidgetTester tester,
  FixtureController controller, {
  Size size = const Size(1920, 1080),
  bool tv = false,
  SettingsCategory category = SettingsCategory.appearance,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: LineupTheme.forName(
        controller.settings.theme,
        formFactor: profileFor(tv).formFactor,
      ),
      builder: (context, child) => DeviceProfileScope(
        profile: profileFor(tv),
        child: LineupCanvas(child: child!),
      ),
      home: Scaffold(
        body: SettingsView(controller: controller, category: category),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [const Size(1920, 1080), const Size(960, 720)]) {
    testWidgets('swatches select and wrap at $size', (tester) async {
      final controller = FixtureController();
      addTearDown(controller.dispose);
      await show(tester, controller, size: size);
      final first = find.byKey(const ValueKey('settings-theme-emberSteel'));
      final last = find.byKey(const ValueKey('settings-theme-swiss'));
      expect(
        find.byKey(const ValueKey('settings-field-Theme')),
        findsOneWidget,
      );
      final buttons = find.byWidgetPredicate(
        (w) =>
            w is OutlinedButton && w.key.toString().contains('settings-theme-'),
      );
      expect(buttons, findsNWidgets(4));
      final rects = buttons
          .evaluate()
          .map((e) => tester.getRect(find.byWidget(e.widget)))
          .toList();
      expect(rects[0].top == rects[3].top, size.width == 1920);
      await tester.ensureVisible(last);
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(controller.settings.theme, LineupThemeName.swiss);
      final preview = tester.widget<Container>(
        find.byKey(const ValueKey('settings-theme-preview-swiss')),
      );
      expect((preview.decoration as BoxDecoration).border!.top.width, 3);
      expect(first, findsOneWidget);
    });
  }
  testWidgets('TV swatches traverse with left and right and select', (
    tester,
  ) async {
    final controller = FixtureController();
    addTearDown(controller.dispose);
    await show(tester, controller, tv: true);
    final first = find.byKey(const ValueKey('settings-theme-emberSteel'));
    tester.widget<OutlinedButton>(first).focusNode!.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.settings.theme, isNot(LineupThemeName.emberSteel));
  });
  for (final category in SettingsCategory.values.where(
    (c) => c != SettingsCategory.subtitles,
  )) {
    testWidgets('content width capped in ${category.name}', (tester) async {
      final controller = FixtureController();
      addTearDown(controller.dispose);
      await show(tester, controller, category: category);
      expect(
        tester.getSize(find.byKey(const Key('settings-content-column'))).width,
        lessThanOrEqualTo(1040),
      );
    });
  }
}
