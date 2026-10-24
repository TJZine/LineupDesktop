import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/app_ui.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';

import '../support/golden_test_support.dart';

void main() {
  setUpAll(loadPinnedTestFonts);

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.android,
  ]) {
    for (final name in LineupThemeName.values) {
      testWidgets(
        'local segmented styles preserve ring and fill contracts: $platform $name',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          final tv = platform == TargetPlatform.android;
          try {
            await tester.pumpWidget(
              MaterialApp(
                theme: LineupTheme.forName(name, androidTv: tv),
                builder: LineupCanvas.builder,
                home: Scaffold(
                  body: Center(
                    child: LineupSegmentedControl<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('One')),
                        ButtonSegment(value: 1, label: Text('Two')),
                      ],
                      selected: const {0},
                      onSelectionChanged: (_) {},
                    ),
                  ),
                ),
              ),
            );
            final finder = find.byType(SegmentedButton<int>);
            final roles = LineupTheme.of(tester.element(finder));
            void checkStyles({required bool keyboard}) {
              final style = tester.widget<SegmentedButton<int>>(finder).style!;
              for (final selected in [false, true]) {
                for (final hovered in [false, true]) {
                  for (final focused in [false, true]) {
                    final states = {
                      if (selected) WidgetState.selected,
                      if (hovered) WidgetState.hovered,
                      if (focused) WidgetState.focused,
                    };
                    expect(
                      style.backgroundColor!.resolve(states),
                      tv && focused
                          ? roles.focusedSurface
                          : selected
                          ? roles.selectedSurface
                          : !tv && hovered
                          ? roles.primaryText.withValues(alpha: .08)
                          : Colors.transparent,
                      reason: '$states keyboard=$keyboard',
                    );
                    expect(
                      style.foregroundColor!.resolve(states),
                      tv && focused
                          ? roles.onFocus
                          : selected
                          ? roles.primaryText
                          : roles.secondaryText,
                    );
                    expect(
                      style.foregroundColor!.resolve({
                        ...states,
                        WidgetState.disabled,
                      }),
                      roles.mutedText,
                    );
                    expect(
                      style.textStyle!.resolve(states)!.fontWeight,
                      selected ? FontWeight.w600 : FontWeight.w500,
                    );
                    final expectedSide = tv
                        ? focused && keyboard
                              ? BorderSide.none
                              : BorderSide(color: roles.subtleBorder, width: 1)
                        : focused && keyboard
                        ? BorderSide(
                            color: roles.focusBorder,
                            width: roles.focusBorderWidth,
                          )
                        : BorderSide.none;
                    expect(
                      style.side!.resolve(states),
                      expectedSide,
                      reason: '$states keyboard=$keyboard',
                    );
                  }
                }
              }
              // The local framed control must not redefine the global style
              // used by other segmented-button consumers.
              expect(
                LineupTheme.segmentedStyle(roles).side!.resolve({}),
                BorderSide(color: roles.subtleBorder, width: 1),
              );
            }

            Focus.of(tester.element(find.text('One'))).requestFocus();
            await tester.pumpAndSettle();
            checkStyles(keyboard: tv);
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            await tester.pumpAndSettle();
            checkStyles(keyboard: true);
            final focused = FocusManager.instance.primaryFocus;
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
            );
            await mouse.addPointer(location: const Offset(10, 10));
            await mouse.moveTo(const Offset(20, 10));
            await tester.pumpAndSettle();
            checkStyles(keyboard: false);
            expect(FocusManager.instance.primaryFocus, same(focused));
            expect(tester.widget<SegmentedButton<int>>(finder).selected, {0});
            await mouse.removePointer();
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );
    }
  }

  test('bundled Instrument width axis narrows titles without a transform', () {
    double width(TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: 'Midsummer television', style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    expect(
      width(LineupTypography.programTitle),
      lessThan(width(LineupTypography.title(54, 100))),
    );
    expect(LineupTypography.programTitle.fontFamilyFallback, ['Inter']);
    expect(LineupTypography.body.fontVariations, isNull);
    expect(LineupTypography.control.fontVariations, isNull);
  });

  test('connection status uses measured quality facts only', () {
    PlexConnection connection({int? ms, bool relay = false}) => PlexConnection(
      uri: Uri.parse('https://fixture.invalid'),
      local: true,
      relay: relay,
      latency: ms == null ? null : Duration(milliseconds: ms),
    );
    expect(
      LineupConnectionStatus.description(connection(ms: 126)),
      'Direct local · 126 ms',
    );
    expect(LineupConnectionStatus.hasWarning(connection(ms: 126)), isFalse);
    expect(
      LineupConnectionStatus.description(connection(ms: 499)),
      'Direct local · 499 ms',
    );
    expect(
      LineupConnectionStatus.description(connection(ms: 500)),
      'Direct local · Very slow · 500 ms',
    );
    expect(LineupConnectionStatus.hasWarning(connection(ms: 500)), isTrue);
    expect(
      LineupConnectionStatus.description(connection(ms: 340, relay: true)),
      'Relay · Limited · 340 ms',
    );
    expect(
      LineupConnectionStatus.hasWarning(connection(ms: 340, relay: true)),
      isTrue,
    );
    expect(
      LineupConnectionStatus.description(connection(relay: true)),
      'Not measured yet',
    );
    expect(LineupConnectionStatus.hasWarning(connection(relay: true)), isFalse);
    expect(LineupConnectionStatus.description(null), 'Not measured yet');
  });

  for (final (platform, tv) in [
    (TargetPlatform.android, false),
    (TargetPlatform.android, true),
    (TargetPlatform.windows, false),
    (TargetPlatform.windows, true),
    (TargetPlatform.macOS, false),
    (TargetPlatform.macOS, true),
  ]) {
    testWidgets('TV keys change focus modality: $platform TV=$tv', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      final focus = FocusNode();
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: LineupTheme.forName(
              LineupThemeName.emberSteel,
              androidTv: tv,
            ),
            builder: LineupCanvas.builder,
            home: Scaffold(
              body: FilledButton(
                focusNode: focus,
                onPressed: () {},
                child: const Text('Continue'),
              ),
            ),
          ),
        );
        focus.requestFocus();
        await tester.pump();
        final control = find.byType(FilledButton);
        final roles = LineupTheme.of(tester.element(control));
        final fillFocus = roles.focusTreatment == LineupFocusTreatment.fill;
        BorderSide side() =>
            Theme.of(tester.element(control)).filledButtonTheme.style!.side!
                .resolve({WidgetState.focused})!;
        Color background() =>
            Theme.of(tester.element(control))
                .filledButtonTheme
                .style!
                .backgroundColor!
                .resolve({WidgetState.focused})!;
        Color foreground() =>
            Theme.of(tester.element(control))
                .filledButtonTheme
                .style!
                .foregroundColor!
                .resolve({WidgetState.focused})!;
        for (final key in [
          LogicalKeyboardKey.channelUp,
          LogicalKeyboardKey.channelDown,
          LogicalKeyboardKey.guide,
          LogicalKeyboardKey.info,
          LogicalKeyboardKey.contextMenu,
        ]) {
          await tester.tap(control);
          await tester.pump();
          expect(side(), BorderSide.none);
          await tester.sendKeyEvent(
            key,
            physicalKey: PhysicalKeyboardKey.escape,
            platform: 'android',
          );
          await tester.pump();
          expect(
            side(),
            tv
                ? fillFocus
                      ? roles.largeFocusIndicators
                            ? isNot(BorderSide.none)
                            : BorderSide.none
                      : isNot(BorderSide.none)
                : BorderSide.none,
          );
          expect(
            background(),
            tv && fillFocus ? roles.focusedSurface : roles.progressFill,
          );
          expect(foreground(), roles.onFocus);
          expect(focus.hasPrimaryFocus, isTrue);
        }
        await tester.sendKeyEvent(
          LogicalKeyboardKey.arrowRight,
          platform: 'android',
        );
        await tester.pump();
        expect(
          side().width,
          tv && fillFocus && !roles.largeFocusIndicators ? 0 : 3,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        focus.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets(
    'pointer hides the ring and keyboard restores it without moving focus or selection',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: LineupTheme.forName(LineupThemeName.emberSteel),
          builder: LineupCanvas.builder,
          home: Scaffold(
            body: Column(
              children: [
                FilledButton(
                  key: const Key('action'),
                  focusNode: node,
                  onPressed: () {},
                  child: const Text('Continue'),
                ),
                const LineupRowSurface(
                  selected: true,
                  child: Text('Selected channel'),
                ),
              ],
            ),
          ),
        ),
      );
      node.requestFocus();
      await tester.pump();
      final action = find.byKey(const Key('action'));
      BorderSide side() =>
          Theme.of(tester.element(action)).filledButtonTheme.style!.side!
              .resolve({WidgetState.focused})!;
      expect(node.hasFocus, isTrue);
      expect(side(), BorderSide.none);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(side().color, LineupTheme.of(tester.element(action)).focusBorder);
      expect(node.hasFocus, isTrue);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(600, 400));
      await mouse.moveTo(const Offset(610, 400));
      await tester.pump();
      expect(side(), BorderSide.none);
      expect(node.hasFocus, isTrue);
      expect(
        tester.widget<LineupRowSurface>(find.byType(LineupRowSurface)).selected,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(node.hasFocus, isTrue);
      expect(side().width, 3);
      await tester.tap(action);
      await tester.pump();
      expect(side(), BorderSide.none);
      expect(node.hasFocus, isTrue);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('persistent field label and focused error remain visible', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: LineupTheme.forName(LineupThemeName.emberSteel),
        builder: LineupCanvas.builder,
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: LineupField(
              label: 'Channel name',
              child: TextField(
                focusNode: node,
                decoration: const InputDecoration(
                  errorText: 'Enter a channel name.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Evening cinema');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(find.text('Channel name'), findsOneWidget);
    expect(find.text('Enter a channel name.'), findsOneWidget);
    final context = tester.element(find.byType(TextField));
    final border =
        Theme.of(context).inputDecorationTheme.focusedErrorBorder!
            as OutlineInputBorder;
    expect(border.borderSide.color, LineupTheme.of(context).liveAccent);
    expect(border.borderSide.width, 3);
  });
}
