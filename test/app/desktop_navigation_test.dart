import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/playback/native_player.dart';

import '../support/ui_fixture.dart';

void main() {
  for (final window in const [Size(1920, 1080), Size(3840, 2160)]) {
    testWidgets('menu anchor follows its canvas invoker at $window', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.5;
      tester.view.physicalSize = window * 1.5;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fixture = UiFixture()..controller.stage = SetupStage.ready;
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      final invoker = find.byKey(const Key('guide-app-menu'));
      Rect drawn(Finder finder) {
        final box = tester.renderObject<RenderBox>(finder);
        return MatrixUtils.transformRect(
          box.getTransformTo(null),
          Offset.zero & box.size,
        );
      }

      final anchor = drawn(invoker);
      await tester.tap(invoker);
      await tester.pumpAndSettle();
      final menu = drawn(find.byKey(const Key('immersive-app-menu')));
      final scale = window.height / 1080;
      expect(menu.top, closeTo(anchor.bottom + 8 * scale, .001));
      expect(
        menu.left,
        closeTo(
          (anchor.right - menu.width).clamp(
            16 * scale,
            window.width - menu.width - 16 * scale,
          ),
          .001,
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Guide Lineup menu',
      );
    });
  }

  testWidgets('Lineup menu is bounded, traps focus, and restores its invoker', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 420);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final fixture = UiFixture()..controller.stage = SetupStage.ready;
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();

    final invoker = find.byKey(const Key('guide-app-menu'));
    await tester.tap(invoker);
    await tester.pumpAndSettle();

    final menu = find.byKey(const Key('immersive-app-menu'));
    final box = tester.renderObject<RenderBox>(menu);
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    expect(rect.left, greaterThanOrEqualTo(16 * .8));
    expect(rect.top, greaterThanOrEqualTo(16 * .8));
    expect(rect.right, lessThanOrEqualTo(800 - 16 * .8));
    expect(rect.bottom, lessThanOrEqualTo(420 - 16 * .8 + .001));
    expect(find.text('Choose a channel in Guide'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Player'))
          .onPressed,
      isNull,
    );

    for (var index = 0; index < 8; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<Card>()
            ?.key,
        const Key('immersive-app-menu'),
      );
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(menu, findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Guide Lineup menu');
  });

  testWidgets(
    'menu order, same-route dismissal, and outside click are stable',
    (tester) async {
      final fixture = UiFixture()..controller.stage = SetupStage.ready;
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('guide-app-menu')));
      await tester.pumpAndSettle();

      final tops = [
        for (final label in [
          'Guide',
          'Player',
          'Channels',
          'Settings',
          'Account',
        ])
          tester.getTopLeft(find.text(label).last).dy,
      ];
      expect(tops, orderedEquals([...tops]..sort()));

      await tester.tap(find.text('Guide').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('immersive-app-menu')), findsNothing);

      await tester.tap(find.byKey(const Key('guide-app-menu')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('immersive-app-menu')), findsNothing);
      expect(find.byKey(const Key('classic-guide')), findsOneWidget);
    },
  );

  testWidgets('Settings retains category and returns to its origin', (
    tester,
  ) async {
    final fixture = UiFixture()..controller.stage = SetupStage.ready;
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();

    await openDestination(tester, 'Settings');
    await tester.tap(find.widgetWithText(TextButton, 'Playback'));
    await tester.pumpAndSettle();
    expect(find.text('Player controls auto-hide'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('classic-guide')), findsOneWidget);

    await openDestination(tester, 'Settings');
    expect(find.text('Player controls auto-hide'), findsOneWidget);
  });

  testWidgets('Account sign out confirms first and reports owner failure', (
    tester,
  ) async {
    final controller = _LogoutController()..stage = SetupStage.ready;
    await tester.pumpWidget(UiFixture(controller: controller).build());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('guide-app-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account').last);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign out of Plex'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out of Plex'));
    await tester.pumpAndSettle();

    expect(controller.logoutCalls, 0);
    expect(find.text('Sign out of Plex?'), findsOneWidget);
    expect(Focus.of(tester.element(find.text('Cancel'))).hasFocus, isTrue);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.logoutCalls, 0);

    await tester.drag(find.byType(ListView).last, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign out of Plex'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out of Plex'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out').last);
    await tester.pumpAndSettle();
    expect(controller.logoutCalls, 1);
    expect(find.text('Could not sign out'), findsOneWidget);
    expect(find.text('Credential cleanup failed.'), findsOneWidget);
  });

  testWidgets('Player route remains unavailable until playback exists', (
    tester,
  ) async {
    final player = FixturePlayer();
    final fixture = UiFixture(player: player)
      ..controller.stage = SetupStage.ready;
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('classic-guide')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    final readyPlayer = FixturePlayer()
      ..emit(const PlayerStatus(state: PlayerState.ready, message: 'Ready'));
    final readyFixture = UiFixture(player: readyPlayer)
      ..controller.stage = SetupStage.ready;
    await tester.pumpWidget(readyFixture.build());
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Player');
  });

  testWidgets('Backspace remains editing in an empty text field', (
    tester,
  ) async {
    final fixture = UiFixture()..controller.stage = SetupStage.ready;
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    await openDestination(tester, 'Channels');
    await tester.tap(find.text('Create a custom channel'));
    await tester.pumpAndSettle();

    final name = find.byKey(const Key('studio-name'));
    await tester.enterText(name, '');
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    expect(name, findsOneWidget);
    expect(find.text('Discard changes?'), findsNothing);
  });
}

class _LogoutController extends FixtureController {
  int logoutCalls = 0;

  @override
  Future<bool> logout() async {
    logoutCalls++;
    error = 'Credential cleanup failed.';
    return false;
  }
}
