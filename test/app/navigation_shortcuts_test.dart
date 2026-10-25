import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/navigation_shortcuts.dart';

void main() {
  const destinations = [
    (LogicalKeyboardKey.digit1, ShellDestination.guide),
    (LogicalKeyboardKey.keyG, ShellDestination.guide),
    (LogicalKeyboardKey.digit2, ShellDestination.channels),
    (LogicalKeyboardKey.digit3, ShellDestination.settings),
    (LogicalKeyboardKey.comma, ShellDestination.settings),
    (LogicalKeyboardKey.digit4, ShellDestination.diagnostics),
    (LogicalKeyboardKey.digit5, ShellDestination.player),
    (LogicalKeyboardKey.keyP, ShellDestination.player),
  ];
  const meta = [LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaRight];
  const control = [
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
  ];

  Future<void> expectChord(
    WidgetTester tester, {
    required List<LogicalKeyboardKey> triggers,
    required List<LogicalKeyboardKey> rejected,
    required String reason,
  }) async {
    for (final modifier in rejected) {
      await tester.sendKeyDownEvent(modifier);
      expect(
        commandModifier(HardwareKeyboard.instance),
        isFalse,
        reason: reason,
      );
      expect(navigationShortcutDestination(LogicalKeyboardKey.digit1), isNull);
      await tester.sendKeyUpEvent(modifier);
    }
    for (final modifier in triggers) {
      await tester.sendKeyDownEvent(modifier);
      expect(
        commandModifier(HardwareKeyboard.instance),
        isTrue,
        reason: reason,
      );
      for (final (key, destination) in destinations) {
        expect(navigationShortcutDestination(key), destination);
      }
      expect(navigationShortcutDestination(LogicalKeyboardKey.keyQ), isNull);
      await tester.sendKeyUpEvent(modifier);
    }
  }

  testWidgets(
    'final Back callback runs once for focused and stranded dispatch',
    (tester) async {
      var calls = 0;
      var backgrounds = 0;
      var claim = true;
      final outside = FocusNode(debugLabel: 'Outside root Back');
      final inside = FocusNode(debugLabel: 'Inside root Back');
      addTearDown(outside.dispose);
      addTearDown(inside.dispose);
      const platform = MethodChannel('lineup/platform');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(platform, (
        _,
      ) async {
        backgrounds++;
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Focus(
            focusNode: outside,
            child: AndroidBackScope(
              onUnhandledBack: () {
                calls++;
                return claim;
              },
              child: Focus(
                focusNode: inside,
                autofocus: true,
                child: const SizedBox(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(inside.hasPrimaryFocus, isTrue);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(calls, 1);
      expect(backgrounds, 0);
      outside.requestFocus();
      await tester.pump();
      expect(outside.hasPrimaryFocus, isTrue);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(calls, 2);
      expect(backgrounds, 0);
      claim = false;
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(calls, 3);
      expect(backgrounds, 1);
      inside.requestFocus();
      await tester.pump();
      for (final key in [
        LogicalKeyboardKey.goBack,
        LogicalKeyboardKey.escape,
        LogicalKeyboardKey.backspace,
      ]) {
        final before = calls;
        await tester.sendKeyDownEvent(
          key,
          physicalKey: PhysicalKeyboardKey.escape,
        );
        await tester.pump();
        await tester.sendKeyRepeatEvent(
          key,
          physicalKey: PhysicalKeyboardKey.escape,
        );
        await tester.sendKeyUpEvent(
          key,
          physicalKey: PhysicalKeyboardKey.escape,
        );
        await tester.pump();
        expect(calls, before + 1);
      }
      expect(backgrounds, 4);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Android root Back uses focused key ownership or backgrounds once',
    (tester) async {
      var backgrounded = 0;
      var handled = 0;
      var consume = true;
      const platform = MethodChannel('lineup/platform');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(platform, (
        call,
      ) async {
        expect(call.method, 'moveTaskToBack');
        backgrounded++;
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AndroidBackScope(
            child: Focus(
              autofocus: true,
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.goBack &&
                    consume) {
                  handled++;
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // All OS Back ingress is native-normalized to route requests. Direct
      // logical keys still share the same action owner (not native proof).
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(handled, 1);
      expect(backgrounded, 0);
      await tester.sendKeyEvent(
        LogicalKeyboardKey.goBack,
        physicalKey: PhysicalKeyboardKey.escape,
      );
      await tester.pump();
      expect(handled, 2);
      expect(backgrounded, 0);
      // A subsequent standalone predictive request is never suppressed by
      // a previous logical key, including after its focus/frame update.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(handled, 3);
      expect(backgrounded, 0);
      consume = false;
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(backgrounded, 1);
      await tester.sendKeyEvent(
        LogicalKeyboardKey.goBack,
        physicalKey: PhysicalKeyboardKey.escape,
      );
      await tester.pump();
      expect(backgrounded, 2);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(backgrounded, 3);
    },
  );

  testWidgets('Android root Back leaves an overlaid dialog to Navigator', (
    tester,
  ) async {
    var backgrounded = 0;
    const platform = MethodChannel('lineup/platform');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(platform, (
      _,
    ) async {
      backgrounded++;
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AndroidBackScope(
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const AlertDialog(content: Text('Dialog')),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Dialog'), findsNothing);
    expect(backgrounded, 0);
  });

  group('command modifier', () {
    // The binding verifies the override before tearDown callbacks run, so each
    // test resets it in a finally block.

    testWidgets('is Command on macOS and Ctrl does not trigger', (
      tester,
    ) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        await expectChord(
          tester,
          triggers: meta,
          rejected: control,
          reason: 'macOS',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('is Ctrl elsewhere and Command does not trigger', (
      tester,
    ) async {
      try {
        for (final platform in TargetPlatform.values) {
          if (platform == TargetPlatform.macOS) continue;
          debugDefaultTargetPlatformOverride = platform;
          await expectChord(
            tester,
            triggers: control,
            rejected: meta,
            reason: '$platform',
          );
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
