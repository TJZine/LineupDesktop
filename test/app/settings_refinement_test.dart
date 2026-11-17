import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/settings_view.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/settings/subtitle_style.dart';
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
  testWidgets('TV rail enters first swatch before and after category rebuild', (
    tester,
  ) async {
    final controller = FixtureController();
    addTearDown(controller.dispose);
    await show(tester, controller, tv: true);
    final first = find.byKey(const ValueKey('settings-theme-emberSteel'));
    final appearance = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Appearance').first)
        .focusNode!;
    expect(appearance.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
      tester.widget<OutlinedButton>(first).focusNode!.hasPrimaryFocus,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    final second = find.byKey(const ValueKey('settings-theme-slatePine'));
    expect(
      tester.widget<OutlinedButton>(second).focusNode!.hasPrimaryFocus,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.settings.theme, LineupThemeName.slatePine);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(
      tester.widget<OutlinedButton>(first).focusNode!.hasPrimaryFocus,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(appearance.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(first, findsNothing);
    // Enter Appearance before its dwell timer fires: entry owns the rebuild
    // and must wait for the recreated swatches to attach their focus nodes.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
      tester.widget<OutlinedButton>(first).focusNode!.hasPrimaryFocus,
      isTrue,
    );
    expect(controller.settings.theme, LineupThemeName.slatePine);
    expect(tester.takeException(), isNull);
  });
  for (final config in [
    (size: const Size(1280, 720), tv: false, columns: false),
    (size: const Size(1512, 945), tv: false, columns: true),
    (size: const Size(1920, 1080), tv: true, columns: true),
  ]) {
    testWidgets('subtitle pages fit and restore focus at $config', (
      tester,
    ) async {
      final controller = FixtureController();
      addTearDown(controller.dispose);
      await show(
        tester,
        controller,
        size: config.size,
        tv: config.tv,
        category: SettingsCategory.subtitles,
      );
      final rows = find.byKey(const ValueKey('subtitle-rows'));
      final preview = find.byKey(const ValueKey('subtitle-preview'));
      expect(tester.getSize(preview).aspectRatio, closeTo(16 / 9, .01));
      expect(
        tester.getRect(preview).left >= tester.getRect(rows).right,
        config.columns,
      );
      final customise = find.byKey(
        const ValueKey('subtitle-field-subtitleCustomise'),
      );
      await tester.ensureVisible(customise);
      await tester.pumpAndSettle();
      await tester.tap(customise);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('subtitle-field-subtitlePreset')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('subtitle-field-subtitleTextColor')),
        findsOneWidget,
      );
      expect(preview, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('subtitle-field-subtitlePreset')),
        findsOneWidget,
      );
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'subtitleCustomise',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('TV device subtitle style enters an enabled Customise control', (
    tester,
  ) async {
    final controller = FixtureController(
      scenario: const LineupScenario(
        settings: LineupSettings(
          subtitleStyle: SubtitleStyle(useDeviceStyle: true),
        ),
      ),
    );
    addTearDown(controller.dispose);
    await show(
      tester,
      controller,
      tv: true,
      category: SettingsCategory.subtitles,
    );
    final rail = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Subtitles').first)
        .focusNode!;
    expect(rail.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    final customise = find.byKey(
      const ValueKey('subtitle-field-subtitleCustomise'),
    );
    final invoke = tester.widget<TextButton>(customise).focusNode!;
    for (var i = 0; i < 5 && !invoke.hasPrimaryFocus; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(invoke.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    final bold = tester.widget<Switch>(
      find.byKey(const ValueKey('subtitle-field-subtitleBold')),
    );
    expect(bold.onChanged, isNotNull);
    expect(bold.focusNode!.hasPrimaryFocus, isTrue);
    final color = find.descendant(
      of: find.byKey(const ValueKey('subtitle-field-subtitleTextColor')),
      matching: find.byType(DropdownButton<SubtitleColor>),
    );
    expect(
      tester.widget<DropdownButton<SubtitleColor>>(color).onChanged,
      isNull,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(rail.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(bold.focusNode!.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextButton>(customise).focusNode!.hasPrimaryFocus,
      isTrue,
    );
    expect(
      find.byKey(const ValueKey('subtitle-field-subtitlePreset')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('subtitle-field-subtitleBold')),
      findsNothing,
    );
    expect(
      controller.settings.subtitleStyle,
      const SubtitleStyle(useDeviceStyle: true),
    );
    expect(tester.takeException(), isNull);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));

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
