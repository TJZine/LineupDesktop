import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/navigation_shortcuts.dart';

void main() {
  testWidgets(
    'OS Back uses visible-surface callback while attached-keyboard Esc keeps focused leaf behavior',
    (tester) async {
      var systemBack = 0;
      final keys = <LogicalKeyboardKey>[];
      await tester.pumpWidget(
        MaterialApp(
          home: AndroidBackScope(
            onSystemBack: () {
              systemBack++;
              return true;
            },
            child: Focus(
              autofocus: true,
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent) {
                  keys.add(event.logicalKey);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(keys, [LogicalKeyboardKey.escape]);
      expect(systemBack, 0);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(systemBack, 1);
      expect(keys, [LogicalKeyboardKey.escape]);
    },
  );
}
