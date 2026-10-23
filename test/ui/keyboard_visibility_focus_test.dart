import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/app_ui.dart';
import 'package:lineup_desktop/ui/keyboard_visibility.dart';

Future<({FocusNode field, FocusNode other})> _pump(
  WidgetTester tester,
  ValueNotifier<bool?> visibility,
) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final field = FocusNode(debugLabel: 'Navigation field');
  final other = FocusNode(debugLabel: 'Other control');
  addTearDown(field.dispose);
  addTearDown(other.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: LineupTheme.forName(LineupThemeName.emberSteel, androidTv: true),
      builder: (context, child) =>
          KeyboardVisibilityScope(visibility: visibility, child: child!),
      home: Scaffold(
        body: LineupFocusScope(
          child: Column(
            children: [
              LineupTextFieldActivation(
                focusNode: field,
                builder: (context, focus, done) =>
                    TextField(focusNode: focus, onEditingComplete: done),
              ),
              TextButton(
                focusNode: other,
                onPressed: () {},
                child: const Text('Other'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (field: field, other: other);
}

Future<void> _activate(WidgetTester tester, FocusNode field) async {
  field.requestFocus();
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.select);
  await tester.pumpAndSettle();
  expect(tester.testTextInput.isVisible, isTrue);
  expect(field.hasPrimaryFocus, isFalse);
}

void main() {
  for (final initial in <bool?>[null, false]) {
    testWidgets(
      'initial $initial does not cancel editing; floating hide restores immediately',
      (tester) async {
        final visibility = ValueNotifier<bool?>(initial);
        addTearDown(visibility.dispose);
        final nodes = await _pump(tester, visibility);
        await _activate(tester, nodes.field);
        expect(tester.view.viewInsets.bottom, 0);
        visibility.value = true;
        await tester.pump();
        visibility.value = false;
        await tester.pumpAndSettle();
        expect(nodes.field.hasPrimaryFocus, isTrue);
        expect(tester.testTextInput.isVisible, isFalse);
        expect(tester.view.viewInsets.bottom, 0);
        // Done and a subsequent hidden/unknown observation carry no hide credit
        // into a fresh edit session.
        await _activate(tester, nodes.field);
        visibility.value = null;
        visibility.value = false;
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isTrue);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        await _activate(tester, nodes.field);
        visibility.value = true;
        visibility.value = false;
        await tester.pumpAndSettle();
        expect(nodes.field.hasPrimaryFocus, isTrue);
      },
    );
  }

  testWidgets('keyboard hide cannot steal another control or modal focus', (
    tester,
  ) async {
    final visibility = ValueNotifier<bool?>(null);
    addTearDown(visibility.dispose);
    final nodes = await _pump(tester, visibility);
    await _activate(tester, nodes.field);
    visibility.value = true;
    nodes.other.requestFocus();
    await tester.pumpAndSettle();
    visibility.value = false;
    await tester.pumpAndSettle();
    expect(nodes.other.hasPrimaryFocus, isTrue);
    await _activate(tester, nodes.field);
    visibility.value = true;
    final dialogFocus = FocusNode(debugLabel: 'Dialog action');
    addTearDown(dialogFocus.dispose);
    final dialog = showDialog<void>(
      context: nodes.field.context!,
      builder: (context) => AlertDialog(
        actions: [
          TextButton(
            focusNode: dialogFocus,
            autofocus: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    visibility.value = false;
    await tester.pumpAndSettle();
    expect(dialogFocus.hasPrimaryFocus, isTrue);
    Navigator.pop(dialogFocus.context!);
    await tester.pumpAndSettle();
    await dialog;
  });

  testWidgets(
    'paused, unknown and disposed observations cannot restore focus',
    (tester) async {
      final visibility = ValueNotifier<bool?>(null);
      addTearDown(visibility.dispose);
      final nodes = await _pump(tester, visibility);
      await _activate(tester, nodes.field);
      visibility.value = true;
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      visibility.value = false;
      await tester.pump();
      expect(nodes.field.hasPrimaryFocus, isFalse);
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      visibility.value = true;
      visibility.value = null;
      visibility.value = false;
      await tester.pumpAndSettle();
      expect(nodes.field.hasPrimaryFocus, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      visibility.value = true;
      visibility.value = false;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
  );
}
