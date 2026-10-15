import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/navigation_shortcuts.dart';

void main() {
  testWidgets('command modifier remains Ctrl on every platform', (
    tester,
  ) async {
    final originalPlatform = debugDefaultTargetPlatformOverride;
    addTearDown(() => debugDefaultTargetPlatformOverride = originalPlatform);
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      expect(commandModifier(HardwareKeyboard.instance), isFalse);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      expect(commandModifier(HardwareKeyboard.instance), isFalse);
      expect(navigationShortcutDestination(LogicalKeyboardKey.digit1), isNull);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      for (final control in [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.controlRight,
      ]) {
        await tester.sendKeyDownEvent(control);
        expect(
          commandModifier(HardwareKeyboard.instance),
          isTrue,
          reason: '$platform / $control',
        );
        for (final (key, destination) in [
          (LogicalKeyboardKey.digit1, ShellDestination.guide),
          (LogicalKeyboardKey.keyG, ShellDestination.guide),
          (LogicalKeyboardKey.digit2, ShellDestination.channels),
          (LogicalKeyboardKey.digit3, ShellDestination.settings),
          (LogicalKeyboardKey.comma, ShellDestination.settings),
          (LogicalKeyboardKey.digit4, ShellDestination.diagnostics),
          (LogicalKeyboardKey.digit5, ShellDestination.player),
          (LogicalKeyboardKey.keyP, ShellDestination.player),
        ]) {
          expect(navigationShortcutDestination(key), destination);
        }
        expect(navigationShortcutDestination(LogicalKeyboardKey.keyQ), isNull);
        await tester.sendKeyUpEvent(control);
      }
    }
  });
}
