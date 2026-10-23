import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_ui.dart';

void main() {
  testWidgets('TV field handles Done, inset dismissal and connection closure', (
    tester,
  ) async {
    final navigation = FocusNode();
    final next = FocusNode();
    addTearDown(next.dispose);
    addTearDown(navigation.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: LineupTheme.forName(LineupThemeName.emberSteel, androidTv: true),
        home: Scaffold(
          body: LineupFocusScope(
            child: Column(
              children: [
                LineupTextFieldActivation(
                  focusNode: navigation,
                  builder: (context, focus, done) =>
                      TextField(focusNode: focus, onEditingComplete: done),
                ),
                TextButton(
                  focusNode: next,
                  onPressed: () {},
                  child: const Text('Next'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    navigation.requestFocus();
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    Future<void> activate() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);
    }

    await activate();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(navigation.hasPrimaryFocus, isTrue);
    expect(tester.testTextInput.isVisible, isFalse);
    await activate();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    tester.view.resetViewInsets();
    expect(navigation.hasPrimaryFocus, isTrue);
    expect(tester.testTextInput.isVisible, isFalse);
    await activate();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.testTextInput.closeConnection();
    await tester.pumpAndSettle();
    expect(navigation.hasPrimaryFocus, isTrue);
    await activate();
    tester.testTextInput
        .hide(); // Floating IME: no inset or connection-close event.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(next.hasPrimaryFocus, isTrue);
  });
}
