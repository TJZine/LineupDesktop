import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_app.dart';
import 'package:lineup_desktop/ui/keyboard_visibility.dart';

import '../support/ui_fixture.dart';

void main() {
  const platform = MethodChannel('lineup/platform');
  final calls = <String>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async {
          calls.add(call.method);
          return false;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, null),
  );

  for (final tv in [false, true]) {
    testWidgets('bootstrap owns one optional visibility source (TV: $tv)', (
      tester,
    ) async {
      final controller = FixtureController();
      final player = FixturePlayer();
      Widget app() => LineupBootstrap(
        controller: controller,
        player: player,
        profile: profileFor(tv),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final navigatorContext = tester.element(find.byType(Navigator).first);
      final source = KeyboardVisibilityScope.maybeOf(navigatorContext);
      expect(source, tv ? isNotNull : isNull);
      expect(calls, tv ? ['watchKeyboardVisibility'] : isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(
        calls,
        tv ? ['watchKeyboardVisibility', 'unwatchKeyboardVisibility'] : isEmpty,
      );
    });
  }

  testWidgets('injected scope reaches overlays and remains caller-owned', (
    tester,
  ) async {
    final visibility = ValueNotifier<bool?>(null);
    addTearDown(visibility.dispose);
    await tester.pumpWidget(
      LineupBootstrap(
        controller: FixtureController(),
        player: FixturePlayer(),
        profile: profileFor(true),
        keyboardVisibility: visibility,
      ),
    );
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    final dialog = showDialog<void>(
      context: navigator.context,
      builder: (context) {
        expect(KeyboardVisibilityScope.maybeOf(context), same(visibility));
        return const AlertDialog(content: Text('Synthetic overlay'));
      },
    );
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();
    await dialog;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    visibility.value = true;
    expect(calls, isEmpty);
  });
}
