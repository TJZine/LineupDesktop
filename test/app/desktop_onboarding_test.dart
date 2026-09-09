import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/app/onboarding_view.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';

import '../support/ui_fixture.dart';

void main() {
  Future<void> show(
    WidgetTester tester,
    FixtureController controller, {
    Future<void> Function()? browser,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LineupTheme.forName(
          LineupThemeName.emberSteel,
          largeFocusIndicators: false,
        ),
        home: UpstreamOnboardingView(
          controller: controller,
          onLogout: () async {},
          openBrowser: browser ?? () async {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('returning profiles expose active selection and a Back action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    const active = PlexHomeUser(
      id: 'active',
      name: 'Active viewer',
      protected: false,
    );
    const other = PlexHomeUser(
      id: 'other',
      name: 'Other viewer',
      protected: false,
    );
    final controller = FixtureController()
      ..stage = SetupStage.profiles
      ..profile = active
      ..profiles = const [active, other]
      ..profileSelectionCanCancel = true;
    addTearDown(controller.dispose);
    await show(tester, controller);
    for (final (name, selected) in [
      ('Active viewer', true),
      ('Other viewer', false),
    ]) {
      final node = tester.getSemantics(find.widgetWithText(TextButton, name));
      expect(
        node.getSemanticsData().flagsCollection.isSelected,
        selected ? ui.Tristate.isTrue : ui.Tristate.isFalse,
      );
    }
    expect(find.widgetWithText(TextButton, 'Back'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cancel'), findsNothing);
    semantics.dispose();
  });

  testWidgets('explicit browser failure retains complete code and QR', (
    tester,
  ) async {
    final controller = FixtureController()
      ..stage = SetupStage.linking
      ..activePin = PlexPin(
        id: 7,
        code: 'ABCDEF',
        expiresAt: DateTime.now().add(const Duration(minutes: 4)),
      );
    addTearDown(controller.dispose);
    var calls = 0;
    await show(
      tester,
      controller,
      browser: () async {
        calls++;
        throw StateError('Synthetic launcher failure');
      },
    );
    expect(calls, 0);
    expect(find.text('ABCDEF'), findsOneWidget);
    await tester.tap(find.text('Open browser'));
    await tester.pump();
    expect(calls, 1);
    expect(find.textContaining('Couldn’t open your browser'), findsOneWidget);
    expect(find.text('ABCDEF'), findsOneWidget);
    expect(controller.activePin?.id, 7);
    expect(controller.stage, SetupStage.linking);
  });

  testWidgets('late launcher completion cannot write into another attempt', (
    tester,
  ) async {
    final pending = Completer<void>();
    final controller = FixtureController()
      ..stage = SetupStage.linking
      ..activePin = PlexPin(
        id: 1,
        code: 'FIRST',
        expiresAt: DateTime.now().add(const Duration(minutes: 4)),
      );
    addTearDown(controller.dispose);
    await show(tester, controller, browser: () => pending.future);
    await tester.tap(find.text('Open browser'));
    controller.activePin = PlexPin(
      id: 2,
      code: 'SECOND',
      expiresAt: DateTime.now().add(const Duration(minutes: 4)),
    );
    pending.completeError(StateError('Obsolete launcher failure'));
    await tester.pump();
    expect(find.textContaining('Couldn’t open your browser'), findsNothing);
    expect(find.text('SECOND'), findsOneWidget);
  });

  testWidgets(
    'a new linking attempt can launch while the old browser call is pending',
    (tester) async {
      final first = Completer<void>();
      final second = Completer<void>();
      final controller = FixtureController()
        ..stage = SetupStage.linking
        ..activePin = PlexPin(
          id: 1,
          code: 'FIRST',
          expiresAt: DateTime.now().add(const Duration(minutes: 4)),
        );
      addTearDown(controller.dispose);
      var calls = 0;
      await show(
        tester,
        controller,
        browser: () => ++calls == 1 ? first.future : second.future,
      );
      await tester.tap(find.text('Open browser'));
      controller.activePin = PlexPin(
        id: 2,
        code: 'SECOND',
        expiresAt: DateTime.now().add(const Duration(minutes: 4)),
      );
      controller.notifyListeners();
      await tester.pump();
      await tester.tap(find.text('Open browser'));
      expect(calls, 2);
      first.complete();
      await tester.pump();
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Open browser'),
      );
      expect(button.onPressed, isNull);
      second.complete();
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Open browser'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('expired code cannot launch and is replaced only explicitly', (
    tester,
  ) async {
    final controller = FixtureController()
      ..stage = SetupStage.linking
      ..activePin = PlexPin(
        id: 1,
        code: 'EXPIRED',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
    addTearDown(controller.dispose);
    await show(tester, controller);
    expect(find.text('Open browser'), findsNothing);
    expect(find.text('Get a new code'), findsOneWidget);
    expect(controller.activePin?.id, 1);
  });

  testWidgets('PIN fourth digit submits; empty Backspace retains dialog', (
    tester,
  ) async {
    final controller = _PinController()
      ..stage = SetupStage.profiles
      ..profiles = const [
        PlexHomeUser(id: 'profile', name: 'Test Profile', protected: true),
      ];
    addTearDown(controller.dispose);
    await show(tester, controller);
    await tester.tap(find.text('Test Profile'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    expect(find.byKey(const Key('profile-pin-sheet')), findsOneWidget);
    for (final key in [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
    ]) {
      await tester.sendKeyEvent(key);
    }
    await tester.pump();
    expect(controller.submitted, ['1234']);
    expect(find.text('Incorrect PIN. Try again.'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    expect(find.byKey(const Key('profile-pin-sheet')), findsOneWidget);
  });
}

class _PinController extends FixtureController {
  final submitted = <String>[];
  @override
  Future<bool> selectProfile(PlexHomeUser user, {String? pin}) async {
    submitted.add(pin ?? '');
    error = 'Incorrect PIN. Try again.';
    return false;
  }
}
