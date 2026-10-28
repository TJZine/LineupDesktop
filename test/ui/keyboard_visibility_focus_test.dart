import '../support/device_profile_test_support.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/app_ui.dart';
import 'package:lineup_desktop/ui/keyboard_visibility.dart';

Future<({FocusNode field, FocusNode other})> _pump(
  WidgetTester tester,
  ValueNotifier<bool?> visibility, {
  ValueNotifier<bool>? enabled,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final field = FocusNode(debugLabel: 'Navigation field');
  final other = FocusNode(debugLabel: 'Other control');
  addTearDown(field.dispose);
  addTearDown(other.dispose);
  await tester.pumpWidget(
    DeviceProfileScope(
      profile: profileFor(true),
      child: MaterialApp(
        theme: LineupTheme.forName(
          LineupThemeName.emberSteel,
          formFactor: profileFor(true).formFactor,
        ),
        builder: (context, child) =>
            KeyboardVisibilityScope(visibility: visibility, child: child!),
        home: Scaffold(
          body: LineupFocusScope(
            child: Column(
              children: [
                if (enabled != null)
                  ValueListenableBuilder<bool>(
                    valueListenable: enabled,
                    builder: (context, value, _) => LineupTextFieldActivation(
                      enabled: value,
                      focusNode: field,
                      builder: (context, focus, done) =>
                          TextField(focusNode: focus, onEditingComplete: done),
                    ),
                  )
                else
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

  testWidgets('paused hide restores the same live editor only on resume', (
    tester,
  ) async {
    final visibility = ValueNotifier<bool?>(null);
    addTearDown(visibility.dispose);
    final nodes = await _pump(tester, visibility);
    await _activate(tester, nodes.field);
    visibility.value = true;
    _pause(tester);
    visibility.value = false;
    await tester.pumpAndSettle();
    expect(nodes.field.hasPrimaryFocus, isFalse);
    _resume(tester);
    await tester.pumpAndSettle();
    expect(nodes.field.hasPrimaryFocus, isTrue);
    expect(tester.testTextInput.isVisible, isFalse);
    await _activate(tester, nodes.field);
    visibility.value = true;
    _pause(tester);
    visibility.value = null;
    visibility.value = false;
    _resume(tester);
    await tester.pumpAndSettle();
    expect(nodes.field.hasPrimaryFocus, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    visibility.value = true;
    visibility.value = false;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('native shown supersedes inset hide until native hidden', (
    tester,
  ) async {
    final visibility = ValueNotifier<bool?>(false);
    addTearDown(visibility.dispose);
    addTearDown(tester.view.resetViewInsets);
    final nodes = await _pump(tester, visibility);
    await _activate(tester, nodes.field);
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pumpAndSettle();
    visibility.value = true;
    await tester.pumpAndSettle();
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(nodes.field.hasPrimaryFocus, isFalse);
    expect(tester.testTextInput.isVisible, isTrue);
    visibility.value = false;
    await tester.pumpAndSettle();
    expect(nodes.field.hasPrimaryFocus, isTrue);
    expect(tester.testTextInput.isVisible, isFalse);
    // Native truth discarded prior inset credit; a fresh edit with native
    // unknown cannot inherit the preceding docked-to-floating transition.
    visibility.value = null;
    await _activate(tester, nodes.field);
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(nodes.field.hasPrimaryFocus, isFalse);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('inset hide restores navigation while resumed', (tester) async {
    final visibility = ValueNotifier<bool?>(null);
    addTearDown(visibility.dispose);
    addTearDown(tester.view.resetViewInsets);
    final nodes = await _pump(tester, visibility);
    await _activate(tester, nodes.field);
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pumpAndSettle();
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(nodes.field.hasPrimaryFocus, isTrue);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('paused inset hide reconciles only on resume', (tester) async {
    final visibility = ValueNotifier<bool?>(null);
    addTearDown(visibility.dispose);
    addTearDown(tester.view.resetViewInsets);
    final nodes = await _pump(tester, visibility);
    await _activate(tester, nodes.field);
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pumpAndSettle();
    _pause(tester);
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(nodes.field.hasPrimaryFocus, isFalse);
    expect(tester.testTextInput.isVisible, isTrue);
    _resume(tester);
    await tester.pumpAndSettle();
    expect(nodes.field.hasPrimaryFocus, isTrue);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('covered inset hide retires history without taking modal focus', (
    tester,
  ) async {
    final visibility = ValueNotifier<bool?>(null);
    addTearDown(visibility.dispose);
    addTearDown(tester.view.resetViewInsets);
    final nodes = await _pump(tester, visibility);
    await _activate(tester, nodes.field);
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pumpAndSettle();
    final editor = FocusManager.instance.primaryFocus;
    _pause(tester);
    final dialog = showDialog<void>(
      context: nodes.field.context!,
      requestFocus: false,
      builder: (_) => const AlertDialog(content: Text('Covering route')),
    );
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, same(editor));
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, same(editor));
    expect(nodes.field.hasPrimaryFocus, isFalse);
    _resume(tester);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, same(editor));
    Navigator.pop(nodes.field.context!);
    await tester.pumpAndSettle();
    await dialog;
    // Returning to the field cannot spend hide history from a covered route.
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(nodes.field.hasPrimaryFocus, isFalse);
  });

  for (final retirement in [
    'other control',
    'modal',
    'modal without focus',
    'disabled',
    'disposed',
  ]) {
    testWidgets(
      'resume never restores a paused editor retired by $retirement',
      (tester) async {
        final visibility = ValueNotifier<bool?>(null);
        final enabled = ValueNotifier(true);
        addTearDown(visibility.dispose);
        addTearDown(enabled.dispose);
        final nodes = await _pump(tester, visibility, enabled: enabled);
        await _activate(tester, nodes.field);
        visibility.value = true;
        _pause(tester);
        FocusNode? dialogFocus;
        Future<void>? dialog;
        switch (retirement) {
          case 'other control':
            nodes.other.requestFocus();
          case 'modal':
          case 'modal without focus':
            dialogFocus = FocusNode(debugLabel: 'Paused modal');
            addTearDown(dialogFocus.dispose);
            dialog = showDialog<void>(
              context: nodes.field.context!,
              requestFocus: retirement != 'modal without focus',
              builder: (context) => AlertDialog(
                actions: [
                  TextButton(
                    focusNode: dialogFocus,
                    autofocus: retirement != 'modal without focus',
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          case 'disabled':
            enabled.value = false;
          case 'disposed':
            await tester.pumpWidget(const SizedBox.shrink());
        }
        await tester.pumpAndSettle();
        if (retirement == 'modal without focus') {
          expect(
            tester
                .widget<EditableText>(find.byType(EditableText))
                .focusNode
                .hasPrimaryFocus,
            isTrue,
          );
        }
        visibility.value = false;
        await tester.pump();
        expect(nodes.field.hasPrimaryFocus, isFalse);
        _resume(tester);
        await tester.pumpAndSettle();
        expect(nodes.field.hasPrimaryFocus, isFalse);
        if (retirement == 'other control') {
          expect(nodes.other.hasPrimaryFocus, isTrue);
        }
        if (dialogFocus != null) {
          if (retirement == 'modal') {
            expect(dialogFocus.hasPrimaryFocus, isTrue);
          }
          Navigator.pop(dialogFocus.context!);
          await tester.pumpAndSettle();
          await dialog;
          expect(nodes.field.hasPrimaryFocus, isFalse);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}

void _pause(WidgetTester tester) {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

void _resume(WidgetTester tester) {
  for (final state in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}
