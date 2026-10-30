import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/settings_view.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/playback/device_captions.dart';
import 'package:lineup_desktop/playback/subtitle_appearance_source.dart';
import 'package:lineup_desktop/playback/subtitle_layer.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/settings/subtitle_style.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';

import '../support/golden_test_support.dart';
import '../support/ui_fixture.dart';

Finder field(String name) =>
    find.byKey(ValueKey('subtitle-field-subtitle$name'));

Future<void> showSettings(
  WidgetTester tester,
  FixtureController controller, {
  Size size = const Size(1920, 1080),
  bool tv = false,
  double text = 1,
  SubtitleAppearanceSource? source,
}) async {
  debugDefaultTargetPlatformOverride ??= TargetPlatform.macOS;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: LineupTheme.forName(
        LineupThemeName.emberSteel,
        largeFocusIndicators: controller.settings.largeFocusIndicators,
        formFactor: profileFor(tv).formFactor,
      ),
      builder: (context, child) => DeviceProfileScope(
        profile: profileFor(tv),
        child: LineupCanvas(child: child!),
      ),
      home: Scaffold(
        body: SettingsView(
          controller: controller,
          category: SettingsCategory.subtitles,
          subtitleAppearance: source,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  final scroll = find
      .descendant(
        of: find.byKey(const ValueKey('subtitle-rows')),
        matching: find.byType(Scrollable),
      )
      .first;
  final state = tester.state<ScrollableState>(scroll);
  if (target.evaluate().isEmpty) {
    state.position.jumpTo(0);
    await tester.pumpAndSettle();
    for (var i = 0; i < 100 && target.evaluate().isEmpty; i++) {
      state.position.jumpTo(
        (state.position.pixels + 180).clamp(0, state.position.maxScrollExtent),
      );
      await tester.pumpAndSettle();
    }
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

DropdownButton<T> dropdown<T>(WidgetTester tester, String name) =>
    tester.widget<DropdownButton<T>>(
      find.descendant(
        of: field(name),
        matching: find.byType(DropdownButton<T>),
      ),
    );

SubtitleAppearance preview(WidgetTester tester) =>
    tester.widget<SubtitleLayer>(find.byType(SubtitleLayer)).appearance.value;

void subtitleTest(
  String description,
  WidgetTesterCallback body, {
  bool semanticsEnabled = false,
}) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }, semanticsEnabled: semanticsEnabled);
}

void main() {
  setUpAll(loadPinnedTestFonts);

  subtitleTest(
    'repeated choices keep focus, deduplicate, and compose with reset in action order',
    (tester) async {
      final store = _QueuedStore();
      final controller = FixtureController(store: store);
      addTearDown(controller.dispose);
      await showSettings(tester, controller);
      final size = dropdown<SubtitleSize>(tester, 'Size');
      size.focusNode!.requestFocus();
      await tester.pump();
      size.onChanged!(SubtitleSize.p150);
      size.onChanged!(SubtitleSize.p150);
      await tester.pump();
      expect(dropdown<SubtitleSize>(tester, 'Size').onChanged, isNotNull);
      expect(size.focusNode!.hasFocus, isTrue);
      expect(preview(tester).scale, 1.5);
      dropdown<SubtitleSize>(tester, 'Size').onChanged!(SubtitleSize.p200);
      dropdown<SubtitlePosition>(tester, 'Position').onChanged!(
        SubtitlePosition.higher,
      );
      await reveal(tester, field('Reset'));
      tester.widget<OutlinedButton>(field('Reset')).onPressed!();
      await reveal(tester, field('Position'));
      dropdown<SubtitlePosition>(tester, 'Position').onChanged!(
        SubtitlePosition.highest,
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Saving…'), findsWidgets);
      expect(preview(tester).scale, 1);
      expect(preview(tester).raise, .15);
      for (var i = 0; i < 5; i++) {
        expect(store.calls, i + 1);
        store.finish();
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(store.calls, 5);
      expect(
        controller.settings.subtitleStyle,
        const SubtitleStyle(position: SubtitlePosition.highest),
      );
    },
  );

  subtitleTest(
    'failed earlier save restores committed field and retains later pending preview',
    (tester) async {
      final store = _QueuedStore();
      final controller = FixtureController(store: store);
      addTearDown(controller.dispose);
      await showSettings(tester, controller);
      dropdown<SubtitleSize>(tester, 'Size').onChanged!(SubtitleSize.p150);
      dropdown<SubtitlePosition>(tester, 'Position').onChanged!(
        SubtitlePosition.higher,
      );
      await tester.pump();
      store.finish(fail: true);
      await tester.pumpAndSettle();
      expect(preview(tester).scale, 1);
      expect(preview(tester).raise, .1);
      expect(
        find.text('Could not save. The previous value was restored.'),
        findsOneWidget,
      );
      store.finish();
      await tester.pumpAndSettle();
      expect(
        controller.settings.subtitleStyle.position,
        SubtitlePosition.higher,
      );
    },
  );

  subtitleTest(
    'device mode disables look fields, composes pending raw snapshot and Reset preserves it',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final store = _QueuedStore();
      final controller = FixtureController(
        store: store,
        scenario: const LineupScenario(
          settings: LineupSettings(
            subtitleStyle: SubtitleStyle(useDeviceStyle: true, bold: true),
          ),
        ),
      );
      addTearDown(controller.dispose);
      final client = DeviceCaptionsClient(platform: TargetPlatform.android);
      client.value = const DeviceCaptions(
        enabled: false,
        fontScale: 1.5,
        foreground: 0xffffff00,
        typeface: SubtitleFont.serif,
      );
      final source = SubtitleAppearanceSource(
        lineup: controller,
        deviceCaptions: client,
        platform: TargetPlatform.android,
      );
      addTearDown(source.dispose);
      await showSettings(tester, controller, source: source);
      expect(find.textContaining('Captions are off there'), findsOneWidget);
      expect(preview(tester).scale, 1.5);
      for (final name in [
        'Preset',
        'Size',
        'TextColor',
        'TextOpacity',
        'Font',
        'Edge',
        'EdgeColor',
        'BackgroundOpacity',
        'BackgroundColor',
        'WindowOpacity',
        'WindowColor',
      ]) {
        await reveal(tester, field(name));
        final button = find.descendant(
          of: field(name),
          matching: find.byWidgetPredicate((w) => w is DropdownButton),
        );
        expect(
          (tester.widget(button) as dynamic).onChanged,
          isNull,
          reason: name,
        );
      }
      await reveal(tester, field('Position'));
      dropdown<SubtitlePosition>(tester, 'Position').onChanged!(
        SubtitlePosition.highest,
      );
      await tester.pump();
      expect(preview(tester).raise, .15);
      expect(preview(tester).bold, isTrue);
      await reveal(tester, field('Reset'));
      tester.widget<OutlinedButton>(field('Reset')).onPressed!();
      await tester.pump();
      expect(preview(tester).bold, isFalse);
      store.finish();
      await tester.pump();
      store.finish();
      await tester.pumpAndSettle();
      expect(
        controller.settings.subtitleStyle,
        const SubtitleStyle(useDeviceStyle: true),
      );
      expect(tester.widget<OutlinedButton>(field('Reset')).onPressed, isNull);
    },
  );

  subtitleTest(
    'box and edge dependencies expose disabled semantics with group names',
    (tester) async {
      final controller = FixtureController();
      addTearDown(controller.dispose);

      await showSettings(tester, controller);
      for (final name in ['BackgroundColor', 'WindowColor']) {
        await reveal(tester, field(name));
        final data = tester.getSemantics(field(name)).getSemanticsData();
        expect(
          data.label,
          contains(
            name == 'BackgroundColor' ? 'Background Color' : 'Window Color',
          ),
        );
        expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      }
      await reveal(tester, field('Edge'));
      dropdown<SubtitleEdge>(tester, 'Edge').onChanged!(SubtitleEdge.none);
      await tester.pumpAndSettle();
      expect(dropdown<SubtitleColor>(tester, 'EdgeColor').onChanged, isNull);
      expect(
        tester.getSemantics(field('Edge')).getSemanticsData().label,
        contains('Edge Style'),
      );
      await reveal(tester, field('BackgroundOpacity'));
      dropdown<SubtitleBoxOpacity>(tester, 'BackgroundOpacity').onChanged!(
        SubtitleBoxOpacity.full,
      );
      await tester.pumpAndSettle();
      expect(
        dropdown<SubtitleColor>(tester, 'BackgroundColor').onChanged,
        isNotNull,
      );
    },
    semanticsEnabled: true,
  );

  subtitleTest(
    'TV Custom opens at Standard; Back cancels and Left returns to rail',
    (tester) async {
      final controller = FixtureController(
        scenario: const LineupScenario(
          settings: LineupSettings(
            subtitleStyle: SubtitleStyle(textColor: SubtitleColor.cyan),
          ),
        ),
      );
      addTearDown(controller.dispose);
      await showSettings(
        tester,
        controller,
        tv: true,
        size: const Size(960, 540),
      );
      expect(find.text('Use device subtitle settings'), findsNothing);
      final trigger = dropdown<SubtitlePreset>(tester, 'Preset');
      trigger.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus!.context!
            .findAncestorWidgetOfExactType<InkWell>(),
        isNotNull,
      );
      expect(controller.settings.subtitleStyle.textColor, SubtitleColor.cyan);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(trigger.focusNode!.hasFocus, isTrue);
      expect(controller.settings.subtitleStyle.textColor, SubtitleColor.cyan);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controller.settings.subtitleStyle.preset, SubtitlePreset.standard);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(trigger.focusNode!.hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(trigger.focusNode!.hasFocus, isTrue);
    },
  );

  subtitleTest(
    'device fallback and failed refresh retain displayed composition',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final controller = FixtureController(
        scenario: const LineupScenario(
          settings: LineupSettings(
            subtitleStyle: SubtitleStyle(
              useDeviceStyle: true,
              size: SubtitleSize.p200,
            ),
          ),
        ),
      );
      addTearDown(controller.dispose);
      final client = DeviceCaptionsClient(platform: TargetPlatform.android);
      final source = SubtitleAppearanceSource(
        lineup: controller,
        deviceCaptions: client,
        platform: TargetPlatform.android,
      );
      addTearDown(source.dispose);
      await showSettings(tester, controller, source: source);
      expect(preview(tester).scale, 2);
      expect(find.textContaining('Captions are off there'), findsNothing);
      client.value = const DeviceCaptions(enabled: false, fontScale: 1.5);
      await tester.pumpAndSettle();
      expect(preview(tester).scale, 1.5);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('lineup/device_captions'),
            (call) async => throw PlatformException(code: 'synthetic'),
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('lineup/device_captions'),
              null,
            ),
      );
      await client.read();
      await tester.pumpAndSettle();
      expect(preview(tester).scale, 1.5);
      expect(find.textContaining('Captions are off there'), findsOneWidget);
    },
  );

  subtitleTest(
    'later same-field choice survives failure and clears stale feedback',
    (tester) async {
      final store = _QueuedStore();
      final controller = FixtureController(store: store);
      addTearDown(controller.dispose);
      await showSettings(tester, controller);
      dropdown<SubtitleSize>(tester, 'Size').onChanged!(SubtitleSize.p150);
      dropdown<SubtitleSize>(tester, 'Size').onChanged!(SubtitleSize.p200);
      await tester.pump();
      store.finish(fail: true);
      await tester.pumpAndSettle();
      expect(preview(tester).scale, 2);
      store.finish();
      await tester.pumpAndSettle();
      expect(controller.settings.subtitleStyle.size, SubtitleSize.p200);
      expect(find.textContaining('Could not save.'), findsNothing);
    },
  );

  subtitleTest('TV traversal skips disabled controls and follows one column', (
    tester,
  ) async {
    final controller = FixtureController();
    addTearDown(controller.dispose);
    await showSettings(
      tester,
      controller,
      tv: true,
      size: const Size(960, 540),
    );
    dropdown<SubtitlePreset>(tester, 'Preset').focusNode!.requestFocus();
    await tester.pumpAndSettle();
    final expected = [
      'subtitleSize',
      'subtitlePosition',
      'subtitleTextColor',
      'subtitleTextOpacity',
      'subtitleFont',
      'subtitleBold',
      'subtitleEdge',
      'subtitleEdgeColor',
      'subtitleBackgroundOpacity',
      'subtitleWindowOpacity',
      'subtitleStyled',
    ];
    for (final name in expected) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus!.debugLabel, name);
    }
  });

  subtitleTest(
    'largest handheld focus context includes growing saving and error feedback',
    (tester) async {
      final store = _QueuedStore();
      final controller = FixtureController(
        store: store,
        scenario: const LineupScenario(
          settings: LineupSettings(largeFocusIndicators: true),
        ),
      );
      addTearDown(controller.dispose);
      await showSettings(
        tester,
        controller,
        size: const Size(412, 915),
        text: 2,
      );
      await reveal(tester, field('Styled'));
      final toggle = tester.widget<Switch>(field('Styled'));
      toggle.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      toggle.onChanged!(true);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('subtitle-row-subtitleStyled'));
      final viewport = find.byKey(const ValueKey('subtitle-rows'));
      expect(
        tester.getRect(row).top,
        greaterThanOrEqualTo(tester.getRect(viewport).top - .1),
        reason:
            'saving row=${tester.getRect(row)} viewport=${tester.getRect(viewport)}',
      );
      store.finish(fail: true);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(row).top,
        greaterThanOrEqualTo(tester.getRect(viewport).top - .1),
        reason:
            'error row=${tester.getRect(row)} viewport=${tester.getRect(viewport)}',
      );
      expect(
        tester.getRect(row).bottom,
        lessThanOrEqualTo(tester.getRect(viewport).bottom + .1),
      );
    },
  );

  subtitleTest(
    'heading scroll retains focus and stays latched through same-row feedback',
    (tester) async {
      final store = _QueuedStore();
      final controller = FixtureController(
        store: store,
        scenario: const LineupScenario(
          settings: LineupSettings(largeFocusIndicators: true),
        ),
      );
      addTearDown(controller.dispose);
      await showSettings(
        tester,
        controller,
        size: const Size(412, 915),
        text: 2,
      );
      await reveal(tester, field('Styled'));
      final styled = tester.widget<Switch>(field('Styled'));
      styled.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      final mode = find.byKey(const ValueKey('subtitle-scrolling-heading'));
      expect(mode, findsNothing);
      final referenceHeight = tester.getSize(find.byType(SubtitleLayer)).height;

      Future<void> frames(
        String name,
        FocusNode node,
        String rowName,
        bool scrolling, {
        bool transition = false,
      }) async {
        Rect? settledViewport = transition
            ? null
            : tester.getRect(find.byKey(const ValueKey('subtitle-rows')));
        for (var frame = 0; frame < 24; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(node.hasFocus, isTrue, reason: '$name focus frame$frame');
          final control = tester.getRect(field(rowName));
          final viewportNow = tester.getRect(
            find.byKey(const ValueKey('subtitle-rows')),
          );
          expect(
            control.top,
            greaterThanOrEqualTo(viewportNow.top - .1),
            reason: '$name visible control frame$frame',
          );
          expect(
            control.bottom,
            lessThanOrEqualTo(viewportNow.bottom + .1),
            reason: '$name visible control frame$frame',
          );
          if (!transition || frame >= 3) {
            expect(
              mode,
              scrolling ? findsOneWidget : findsNothing,
              reason: '$name mode frame$frame',
            );
            if (settledViewport != null) {
              expect(
                viewportNow,
                settledViewport,
                reason: '$name immediate stable viewport frame$frame',
              );
            }
          }
          if (frame < 3) continue;
          final viewport = tester.getRect(
            find.byKey(const ValueKey('subtitle-rows')),
          );
          final row = tester.getRect(
            find.byKey(ValueKey('subtitle-row-subtitle$rowName')),
          );
          // Six canvas units per side include the full large focus treatment.
          final clearance =
              6 * LineupCanvas.scaleOf(tester.element(field(rowName)));
          expect(
            row.top - clearance,
            greaterThanOrEqualTo(viewport.top - .1),
            reason: '$name top frame$frame',
          );
          expect(
            row.bottom + clearance,
            lessThanOrEqualTo(viewport.bottom + .1),
            reason: '$name bottom frame$frame',
          );
          expect(
            tester.getSize(find.byType(SubtitleLayer)).height,
            referenceHeight,
          );
          if (settledViewport != null) {
            expect(
              viewport,
              settledViewport,
              reason: '$name stable viewport frame$frame',
            );
          }
          settledViewport = viewport;
        }
      }

      styled.onChanged!(true);
      await tester.pump(const Duration(milliseconds: 350));
      await frames(
        'enter Saving',
        styled.focusNode!,
        'Styled',
        true,
        transition: true,
      );
      expect(find.text('Saving…'), findsOneWidget);
      store.finish();
      await frames('success removes Saving', styled.focusNode!, 'Styled', true);
      expect(find.text('Saving…'), findsNothing);

      tester.widget<Switch>(field('Styled')).onChanged!(false);
      await tester.pump(const Duration(milliseconds: 350));
      await frames('second Saving', styled.focusNode!, 'Styled', true);
      store.finish(fail: true);
      await frames('error replaces Saving', styled.focusNode!, 'Styled', true);
      expect(find.textContaining('Could not save.'), findsOneWidget);
      tester.widget<Switch>(field('Styled')).onChanged!(false);
      await frames('retry removes error', styled.focusNode!, 'Styled', true);
      expect(find.textContaining('Could not save.'), findsNothing);
      store.finish();
      await frames('retry success', styled.focusNode!, 'Styled', true);

      await reveal(tester, field('Bold'));
      final bold = tester.widget<Switch>(field('Bold'));
      bold.focusNode!.requestFocus();
      await frames(
        'leave for fitting row',
        bold.focusNode!,
        'Bold',
        false,
        transition: true,
      );
      await reveal(tester, field('Styled'));
      styled.focusNode!.requestFocus();
      await frames(
        'return without feedback',
        styled.focusNode!,
        'Styled',
        false,
        transition: true,
      );
    },
  );

  subtitleTest(
    'viewport and category changes release the conditional heading without losing focus',
    (tester) async {
      final store = _QueuedStore();
      final controller = FixtureController(
        store: store,
        scenario: const LineupScenario(
          settings: LineupSettings(largeFocusIndicators: true),
        ),
      );
      addTearDown(controller.dispose);
      await showSettings(
        tester,
        controller,
        size: const Size(412, 915),
        text: 2,
      );
      await reveal(tester, field('Styled'));
      final toggle = tester.widget<Switch>(field('Styled'));
      toggle.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      toggle.onChanged!(true);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('subtitle-scrolling-heading')),
        findsOneWidget,
      );
      store.finish();
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1920, 1080);
      for (var frame = 0; frame < 24; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(toggle.focusNode!.hasFocus, isTrue);
        final control = tester.getRect(field('Styled'));
        final currentViewport = tester.getRect(
          find.byKey(const ValueKey('subtitle-rows')),
        );
        expect(control.top, greaterThanOrEqualTo(currentViewport.top - .1));
        expect(control.bottom, lessThanOrEqualTo(currentViewport.bottom + .1));
        if (frame < 3) continue;
        expect(
          find.byKey(const ValueKey('subtitle-scrolling-heading')),
          findsNothing,
        );
        final viewport = tester.getRect(
          find.byKey(const ValueKey('subtitle-rows')),
        );
        final row = tester.getRect(
          find.byKey(const ValueKey('subtitle-row-subtitleStyled')),
        );
        expect(row.top - 6, greaterThanOrEqualTo(viewport.top - .1));
        expect(row.bottom + 6, lessThanOrEqualTo(viewport.bottom + .1));
        expect(tester.getSize(find.byType(SubtitleLayer)).height, 1080);
      }
      tester.view.physicalSize = const Size(412, 915);
      await tester.pumpAndSettle();
      tester.widget<Switch>(field('Styled')).onChanged!(false);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('subtitle-scrolling-heading')),
        findsOneWidget,
      );
      store.finish();
      await tester.pumpAndSettle();
      final appearance = find.widgetWithText(TextButton, 'Appearance').first;
      await tester.ensureVisible(appearance);
      await tester.tap(appearance);
      await tester.pumpAndSettle();
      final subtitles = find.widgetWithText(TextButton, 'Subtitles').first;
      await tester.ensureVisible(subtitles);
      await tester.tap(subtitles);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('subtitle-scrolling-heading')),
        findsNothing,
      );
    },
  );

  subtitleTest('leaving for the rail cancels an in-flight heading transition', (
    tester,
  ) async {
    final store = _QueuedStore();
    final controller = FixtureController(
      store: store,
      scenario: const LineupScenario(
        settings: LineupSettings(largeFocusIndicators: true),
      ),
    );
    addTearDown(controller.dispose);
    await showSettings(tester, controller, size: const Size(412, 915), text: 2);
    await reveal(tester, field('Styled'));
    final styled = tester.widget<Switch>(field('Styled'));
    styled.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    styled.onChanged!(true);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    store.finish();
    await tester.pumpAndSettle();
    await reveal(tester, field('Bold'));
    tester.widget<Switch>(field('Bold')).focusNode!.requestFocus();
    final transitionSpace = find.byKey(
      const ValueKey('subtitle-repinning-space'),
    );
    for (
      var frame = 0;
      frame < 6 && transitionSpace.evaluate().isEmpty;
      frame++
    ) {
      await tester.pump();
    }
    expect(transitionSpace, findsOneWidget);
    final rail = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Subtitles').first)
        .focusNode!;
    rail.requestFocus();
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(rail.hasFocus, isTrue);
      if (frame >= 2) {
        expect(
          find.byKey(const ValueKey('subtitle-repinning-space')),
          findsNothing,
        );
      }
    }
    await reveal(tester, field('Styled'));
    styled.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    expect(styled.focusNode!.hasFocus, isTrue);
    expect(
      find.byKey(const ValueKey('subtitle-repinning-space')),
      findsNothing,
    );
  });

  subtitleTest(
    'Font menu uses production families and opening menus never changes preview',
    (tester) async {
      final controller = FixtureController();
      addTearDown(controller.dispose);
      await showSettings(
        tester,
        controller,
        tv: true,
        size: const Size(960, 540),
      );
      for (final name in ['Size', 'TextColor', 'Font']) {
        await reveal(tester, field(name));
        await tester.tap(field(name));
        await tester.pumpAndSettle();
        if (name == 'Font') {
          for (
            var attempt = 0;
            attempt < 100 &&
                SubtitleFont.values.any(
                  (f) => !SubtitleFonts.shared.isReady(f),
                );
            attempt++
          ) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 5)),
            );
            await tester.pump();
          }
          for (final font in SubtitleFont.values) {
            expect(SubtitleFonts.shared.isReady(font), isTrue);
          }
          await tester.pumpAndSettle();
          for (final font in SubtitleFont.values) {
            final text = tester.widget<Text>(find.text(font.label).last);
            expect(text.style?.fontFamily, font.fontFamily);
          }
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(preview(tester).scale, 1);
        expect(preview(tester).font, SubtitleFont.standard);
        expect(preview(tester).textColor, 0xffffffff);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(controller.settings.subtitleStyle, const SubtitleStyle());
      }
    },
  );

  subtitleTest(
    'Settings suppresses underlying cues and remote keys send no transport',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view
        ..devicePixelRatio = 2
        ..physicalSize = const Size(1920, 1080);
      addTearDown(tester.view.reset);
      final controller = FixtureController(
        scenario: const LineupScenario(
          stage: SetupStage.ready,
          settings: LineupSettings(reduceMotion: true),
        ),
      );
      addTearDown(controller.dispose);
      final player = FixturePlayer.preloaded();
      player.emit(
        const PlayerStatus(state: PlayerState.playing, message: 'Playing'),
      );
      final fixture = UiFixture(
        controller: controller,
        player: player,
        profile: tvProfile,
      );
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      await openDestination(tester, 'Settings');
      final category = find.widgetWithText(TextButton, 'Subtitles').first;
      await tester.tap(category);
      await tester.pumpAndSettle();
      // The sole layer belongs to the Settings preview, with no Player cue layer.
      expect(find.byType(SubtitleLayer), findsOneWidget);
      final before = (
        player.plays,
        player.pauseCalls,
        player.stops,
        player.seeks.length,
      );
      for (final key in [
        LogicalKeyboardKey.mediaPlayPause,
        LogicalKeyboardKey.mediaPlay,
        LogicalKeyboardKey.mediaPause,
        LogicalKeyboardKey.mediaStop,
        LogicalKeyboardKey.mediaFastForward,
        LogicalKeyboardKey.mediaRewind,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowLeft,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }
      expect((
        player.plays,
        player.pauseCalls,
        player.stops,
        player.seeks.length,
      ), before);
    },
  );

  for (final config in [
    (size: const Size(1920, 1080), text: 1.0, tv: false),
    (size: const Size(1280, 720), text: 1.0, tv: false),
    (size: const Size(1260, 720), text: 1.0, tv: false),
    (size: const Size(1262, 720), text: 1.0, tv: false),
    (size: const Size(721, 720), text: 1.0, tv: false),
    (size: const Size(412, 915), text: 1.0, tv: false),
    (size: const Size(1920, 1080), text: 2.0, tv: false),
    (size: const Size(412, 915), text: 2.0, tv: false),
    (size: const Size(960, 540), text: 1.0, tv: true),
    (size: const Size(960, 540), text: 1.15, tv: true),
    (size: const Size(960, 540), text: 1.3, tv: true),
    (size: const Size(960, 540), text: 2.0, tv: true),
  ]) {
    subtitleTest('actual-size preview and focused complete rows at $config', (
      tester,
    ) async {
      final controller = FixtureController(
        scenario: const LineupScenario(
          settings: LineupSettings(largeFocusIndicators: true),
        ),
      );
      addTearDown(controller.dispose);
      await showSettings(
        tester,
        controller,
        size: config.size,
        text: config.text,
        tv: config.tv,
      );
      final layer = tester.getSize(find.byType(SubtitleLayer));
      final canvas = MediaQuery.sizeOf(
        tester.element(find.byType(SubtitleLayer)),
      );
      expect(layer.height, closeTo(canvas.shortestSide, .01));
      final previewRect = tester.getRect(
        find.byKey(const ValueKey('subtitle-preview')),
      );
      final rowsRect = tester.getRect(
        find.byKey(const ValueKey('subtitle-rows')),
      );
      if (config.size.width == 1260) {
        expect(previewRect.bottom, lessThanOrEqualTo(rowsRect.top));
      }
      if (config.size.width == 1262) {
        expect(previewRect.left, greaterThanOrEqualTo(rowsRect.right));
      }
      await reveal(tester, field('Size'));
      dropdown<SubtitleSize>(tester, 'Size').focusNode!.requestFocus();
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('subtitle-row-subtitleSize'));
      final viewport = find.byKey(const ValueKey('subtitle-rows'));
      final rowRect = tester.getRect(row);
      final viewportRect = tester.getRect(viewport);
      expect(rowRect.top, greaterThanOrEqualTo(viewportRect.top - .1));
      expect(rowRect.bottom, lessThanOrEqualTo(viewportRect.bottom + .1));
      await reveal(tester, field('Styled'));
      tester.widget<Switch>(field('Styled')).focusNode!.requestFocus();
      await tester.pumpAndSettle();
      final tallRow = tester.getRect(
        find.byKey(const ValueKey('subtitle-row-subtitleStyled')),
      );
      expect(
        tallRow.top,
        greaterThanOrEqualTo(tester.getRect(viewport).top - .1),
        reason:
            'row=$tallRow viewport=${tester.getRect(viewport)} crop=${tester.getSize(find.byKey(const ValueKey("subtitle-preview")))}',
      );
      expect(
        tallRow.bottom,
        lessThanOrEqualTo(tester.getRect(viewport).bottom + .1),
      );
      await reveal(tester, field('Font'));
      dropdown<SubtitleFont>(tester, 'Font').onChanged!(SubtitleFont.monoSans);
      await tester.pumpAndSettle();
      dropdown<SubtitleFont>(tester, 'Font').focusNode!.requestFocus();
      await tester.pumpAndSettle();
      final text = find.descendant(
        of: field('Font'),
        matching: find.text('Monospaced sans'),
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: text, matching: find.byType(RichText)),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      final textRect = tester.getRect(text);
      final fieldRect = tester.getRect(field('Font'));
      expect(textRect.top, greaterThanOrEqualTo(fieldRect.top - .1));
      expect(textRect.bottom, lessThanOrEqualTo(fieldRect.bottom + .1));
      expect(tester.takeException(), isNull);
    });
  }
}

class _QueuedStore extends MemoryAppStore {
  final _pending = <Completer<void>>[];
  int calls = 0;
  @override
  Future<void> save(value) async {
    calls++;
    final pending = Completer<void>();
    _pending.add(pending);
    await pending.future;
    await super.save(value);
  }

  void finish({bool fail = false}) {
    final pending = _pending.removeAt(0);
    if (fail) {
      pending.completeError(StateError('synthetic persistence failure'));
    } else {
      pending.complete();
    }
  }
}
