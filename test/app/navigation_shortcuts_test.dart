import 'package:flutter/foundation.dart';
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

  group('command modifier', () {
    // The binding verifies this global before tearDown callbacks run, so each
    // test also resets it inline.
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    testWidgets('is Command on macOS and Ctrl does not trigger', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await expectChord(
        tester,
        triggers: meta,
        rejected: control,
        reason: 'macOS',
      );
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('is Ctrl elsewhere and Command does not trigger', (
      tester,
    ) async {
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
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
