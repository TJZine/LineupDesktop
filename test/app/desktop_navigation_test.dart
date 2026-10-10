import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/ui/app_ui.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

import '../support/ui_fixture.dart';

const _firstRunProfileCases = [
  (label: 'zero profiles', profiles: <PlexHomeUser>[]),
  (
    label: 'one profile',
    profiles: [PlexHomeUser(id: 'one', name: 'One', protected: false)],
  ),
];

void main() {
  testWidgets('empty Guide Set up channels enters existing cancellable setup', (
    tester,
  ) async {
    final fixture = UiFixture()..controller.stage = SetupStage.ready;
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    expect(find.text('No channels yet'), findsOneWidget);
    await tester.tap(find.text('Set up channels'));
    await tester.pumpAndSettle();
    expect(fixture.controller.stage, SetupStage.channelSetup);
    expect(fixture.controller.channelSetupCanCancel, isTrue);
  });

  testWidgets('ready-state updates keep the open Lineup menu and focus', (
    tester,
  ) async {
    final fixture = UiFixture()..controller.stage = SetupStage.ready;
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open Lineup menu'));
    await tester.pumpAndSettle();
    final menu = find.byKey(const Key('immersive-app-menu'));
    final menuElement = tester.element(menu);
    final focus = FocusManager.instance.primaryFocus;
    fixture.controller.notifyListeners();
    await tester.pump();
    expect(tester.element(menu), same(menuElement));
    expect(FocusManager.instance.primaryFocus, same(focus));
  });

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
        for (final label in ['Guide', 'Player', 'Channels', 'Settings'])
          tester.getTopLeft(find.text(label).last).dy,
        tester.getTopLeft(find.byKey(const Key('app-menu-account'))).dy,
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

  for (final (index, name) in [(0, 'Guide'), (1, 'Channels'), (4, 'Player')]) {
    testWidgets('Settings keeps $name origin through Diagnostics and menu', (
      tester,
    ) async {
      final fixture = UiFixture(
        player: FixturePlayer()
          ..emit(
            const PlayerStatus(state: PlayerState.ready, message: 'Ready'),
          ),
      )..controller.stage = SetupStage.ready;
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      if (index != 0) await _routeShortcut(tester, index);
      await _routeShortcut(tester, 2);
      expect(find.text('‹ Back to $name'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Support'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Open Diagnostics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Diagnostics'));
      await tester.pumpAndSettle();
      expect(find.text('‹ Settings · Support'), findsOneWidget);
      // A menu selection has the same origin contract as the inline link.
      await openDestination(tester, 'Settings');
      expect(find.text('‹ Back to $name'), findsOneWidget);
      await tester.ensureVisible(find.text('Open Diagnostics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Diagnostics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('‹ Settings · Support'));
      await tester.pumpAndSettle();
      expect(find.text('‹ Back to $name'), findsOneWidget);
      await tester.tap(find.text('‹ Back to $name'));
      await tester.pumpAndSettle();
      expect(find.text('‹ Settings · Support'), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, name);
    });
  }

  testWidgets(
    'Channels menu and shortcut leave Studio through the dirty guard',
    (tester) async {
      final fixture = UiFixture()..controller.stage = SetupStage.ready;
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      await openDestination(tester, 'Channels');
      await tester.tap(find.text('Create a custom channel'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('studio-name')),
        'Draft name',
      );
      await openDestination(tester, 'Channels');
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('studio-name')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('immersive-app-menu')), findsNothing);
      await _routeShortcut(tester, 1);
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('studio-name')), findsNothing);
      expect(find.text('Create a custom channel'), findsOneWidget);
    },
  );

  testWidgets('Diagnostics shortcut Back returns through Support to Channels', (
    tester,
  ) async {
    final fixture = UiFixture()..controller.stage = SetupStage.ready;
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    await _routeShortcut(tester, 1);
    await _routeShortcut(tester, 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('‹ Back to Channels'), findsOneWidget);
    expect(find.text('Open Diagnostics'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('channels-app-menu')), findsOneWidget);
  });

  testWidgets('condensed bar keeps an accessible menu and first-run lockup', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(640, 480);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final fixture = UiFixture()..controller.stage = SetupStage.ready;
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    expect(find.text('LINEUP'), findsNothing);
    expect(find.byIcon(Icons.menu), findsOneWidget);
    await tester.tap(find.byKey(const Key('guide-app-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('immersive-app-menu')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    final onboarding = UiFixture()..controller.stage = SetupStage.servers;
    await tester.pumpWidget(onboarding.build());
    await tester.pumpAndSettle();
    expect(find.byType(LineupTopBar), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsNothing);
    expect(find.byTooltip('Open Lineup menu'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide workspace caps content while its bar keeps the corner', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(3440, 1440);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final fixture = UiFixture()..controller.stage = SetupStage.ready;
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    await openDestination(tester, 'Channels');
    final content = tester.getRect(
      find.byKey(const ValueKey('lineup-page-content')),
    );
    expect(content.width, closeTo(1824 * 4 / 3, .001));
    // getSize reports canvas units; getRect/positions include root scaling.
    final bar = tester.getSize(find.byKey(const ValueKey('lineup-top-bar')));
    expect(bar.height, 80);
    expect(bar.width, closeTo(2580, .001));
    expect(
      tester.getTopLeft(find.byKey(const Key('channels-app-menu'))).dx,
      48 * 4 / 3,
    );
    expect(content.center.dx, closeTo(1720, .001));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Account menu wraps names and uses measured status without a heading',
    (tester) async {
      final fixture = UiFixture()..controller.stage = SetupStage.ready;
      fixture.controller
        ..profile = const PlexHomeUser(
          id: 'guest',
          name: 'A long synthetic profile name',
          protected: false,
        )
        ..server = const PlexServer(
          id: 'server',
          name: 'A long synthetic server name',
          connections: [],
        )
        ..connection = PlexConnection(
          uri: Uri.parse('https://synthetic.invalid'),
          local: true,
          relay: false,
          latency: const Duration(milliseconds: 126),
        );
      await tester.pumpWidget(fixture.build());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('guide-app-menu')));
      await tester.pumpAndSettle();
      expect(find.text('Lineup'), findsNothing);
      expect(find.text('Account'), findsNothing);
      expect(find.byTooltip('Close Lineup menu'), findsNothing);
      expect(find.byType(LineupProfileAvatar), findsOneWidget);
      expect(find.text('Direct local · 126 ms'), findsOneWidget);
      expect(find.text('A long synthetic profile name'), findsOneWidget);
      await tester.tap(find.byKey(const Key('app-menu-account')));
      await tester.pumpAndSettle();
      expect(find.text('Plex Home profile'), findsOneWidget);
    },
  );

  testWidgets('Account sign out confirms first and reports owner failure', (
    tester,
  ) async {
    final controller = _LogoutController()..stage = SetupStage.ready;
    await tester.pumpWidget(UiFixture(controller: controller).build());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('guide-app-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('app-menu-account')));
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

  testWidgets('first-run server Sign out can cancel and return to Welcome', (
    tester,
  ) async {
    for (final testCase in _firstRunProfileCases) {
      final controller = _FirstRunLogoutController(failFirst: true)
        ..stage = SetupStage.servers
        ..profiles = testCase.profiles;
      addTearDown(controller.dispose);
      await tester.pumpWidget(UiFixture(controller: controller).build());
      await tester.pumpAndSettle();

      expect(find.text('No servers found'), findsOneWidget);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Sign out of Plex?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.stage, SetupStage.servers, reason: testCase.label);
      expect(controller.logoutCalls, 0, reason: testCase.label);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(LineupDestructiveButton, 'Sign out'),
      );
      await tester.pumpAndSettle();
      expect(controller.logoutCalls, 1, reason: testCase.label);
      expect(find.text('Could not sign out'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(controller.stage, SetupStage.servers, reason: testCase.label);

      controller.failFirst = false;
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(LineupDestructiveButton, 'Sign out'),
      );
      await tester.pumpAndSettle();
      expect(controller.logoutCalls, 2, reason: testCase.label);
      expect(controller.stage, SetupStage.welcome, reason: testCase.label);
      expect(find.text('Sign in to Plex'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('no-library setup Sign out keeps failed cleanup retryable', (
    tester,
  ) async {
    for (final testCase in _firstRunProfileCases) {
      final controller = _FirstRunLogoutController(failFirst: true)
        ..stage = SetupStage.channelSetup
        ..profiles = testCase.profiles
        ..server = const PlexServer(
          id: 'server',
          name: 'Synthetic server',
          connections: [],
        )
        ..libraries = const [];
      addTearDown(controller.dispose);
      await tester.pumpWidget(UiFixture(controller: controller).build());
      await tester.pumpAndSettle();

      expect(
        find.text('No movie or show libraries found'),
        findsOneWidget,
        reason: testCase.label,
      );
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Sign out of Plex?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.stage, SetupStage.channelSetup, reason: testCase.label);
      expect(controller.logoutCalls, 0, reason: testCase.label);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(LineupDestructiveButton, 'Sign out'),
      );
      await tester.pumpAndSettle();
      expect(controller.logoutCalls, 1, reason: testCase.label);
      expect(find.text('Could not sign out'), findsOneWidget);
      expect(find.text('Credential cleanup failed.'), findsWidgets);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(controller.stage, SetupStage.channelSetup, reason: testCase.label);

      controller.failFirst = false;
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(LineupDestructiveButton, 'Sign out'),
      );
      await tester.pumpAndSettle();
      expect(controller.logoutCalls, 2, reason: testCase.label);
      expect(controller.stage, SetupStage.welcome, reason: testCase.label);
      expect(find.text('Sign in to Plex'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }
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

class _FirstRunLogoutController extends FixtureController {
  _FirstRunLogoutController({this.failFirst = false});

  bool failFirst;
  int logoutCalls = 0;

  @override
  Future<bool> logout() async {
    logoutCalls++;
    if (failFirst && logoutCalls == 1) {
      error = 'Credential cleanup failed.';
      notifyListeners();
      return false;
    }
    return super.logout();
  }
}

Future<void> _routeShortcut(WidgetTester tester, int index) async {
  const keys = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
  ];
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(keys[index]);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}
