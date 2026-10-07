import 'dart:ui' show PointerDeviceKind;

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
