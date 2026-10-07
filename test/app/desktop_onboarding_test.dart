import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/app/onboarding_view.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/app_ui.dart';

import '../support/ui_fixture.dart';

void main() {
  testWidgets(
    'onboarding reflows at the two floor-constrained desktop windows',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final window in const [Size(1280, 720), Size(1366, 768)]) {
        tester.view.physicalSize = window;
        for (final stage in [
          SetupStage.welcome,
          SetupStage.linking,
          SetupStage.profiles,
          SetupStage.servers,
        ]) {
          final controller = FixtureController()
            ..settings = const LineupSettings(reduceMotion: true)
            ..stage = stage
            ..profiles = const [
              PlexHomeUser(
                id: 'guest',
                name: 'Synthetic guest profile',
                protected: false,
              ),
            ]
            ..servers = const [
              PlexServer(
                id: 'server',
                name: 'Synthetic local server',
                connections: [],
              ),
            ];
          await tester.pumpWidget(
            MaterialApp(
              builder: LineupCanvas.builder,
              home: UpstreamOnboardingView(
                controller: controller,
                onLogout: () async {},
                openBrowser: () async {},
              ),
            ),
          );
          await tester.pump();
          expect(
            find.byKey(const ValueKey('onboarding-content')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull, reason: '$window $stage');
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        }
      }
    },
  );

  testWidgets('first-run focused tasks use a centred 1040 canvas column', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(3440, 1440);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final stage in [
      SetupStage.linking,
      SetupStage.profiles,
      SetupStage.servers,
      SetupStage.welcome,
    ]) {
      final controller = FixtureController()..stage = stage;
      await tester.pumpWidget(
        MaterialApp(
          builder: LineupCanvas.builder,
          home: UpstreamOnboardingView(
            controller: controller,
            onLogout: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (stage == SetupStage.welcome) {
        expect(find.byType(LineupTopBar), findsNothing);
      } else {
        final column = find.byKey(const ValueKey('onboarding-content'));
        expect(tester.getSize(column).width, 1040);
        expect(tester.getRect(column).center.dx, closeTo(1720, .001));
        expect(find.byType(LineupTopBar), findsOneWidget);
        expect(find.byTooltip('Open Lineup menu'), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });

  Future<void> show(
    WidgetTester tester,
    FixtureController controller, {
    Future<void> Function()? browser,
    bool accountOrigin = false,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: LineupCanvas.builder(context, child),
        ),
        theme: LineupTheme.forName(
          LineupThemeName.emberSteel,
          largeFocusIndicators: false,
        ),
        home: UpstreamOnboardingView(
          controller: controller,
          onLogout: () async {},
          openBrowser: browser ?? () async {},
          accountOrigin: accountOrigin,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('returning profiles expose active selection and a Back action', (
    tester,
  ) async {
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
    final avatars = find.byType(LineupProfileAvatar);
    expect(
      tester.getTopLeft(avatars.first).dy,
      tester.getTopLeft(avatars.last).dy,
    );
  }, semanticsEnabled: true);

  testWidgets('profile card clamp accepts a sub-pixel width constraint', (
    tester,
  ) async {
    final controller = FixtureController()
      ..stage = SetupStage.profiles
      ..profiles = const [
        PlexHomeUser(id: 'profile', name: 'Profile', protected: false),
      ];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: LineupCanvas.builder,
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 0.5,
            child: UpstreamOnboardingView(
              controller: controller,
              onLogout: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final errors = <Object>[];
    Object? error = tester.takeException();
    while (error != null) {
      errors.add(error);
      error = tester.takeException();
    }
    expect(
      errors,
      everyElement(
        isA<FlutterError>().having(
          (error) => error.toString(),
          'message',
          contains('overflowed'),
        ),
      ),
    );
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

  testWidgets('linking slots stay aligned across code and failure states', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(640, 560)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = FixtureController()
      ..stage = SetupStage.linking
      ..activePin = PlexPin(
        id: 1,
        code: 'ACTIVE',
        expiresAt: DateTime.now().add(const Duration(minutes: 4)),
      );
    addTearDown(controller.dispose);
    await show(tester, controller, textScale: 1.75);

    Rect rect(String key) => tester.getRect(find.byKey(ValueKey(key)));
    final codeState = [
      rect('linking-code-slot'),
      rect('linking-action-slot'),
      rect('linking-qr-slot'),
      rect('linking-footer'),
    ];

    controller
      ..activePin = PlexPin(
        id: 2,
        code: 'EXPIRED',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      )
      ..error = null;
    controller.notifyListeners();
    await tester.pump();
    final expiredState = [
      rect('linking-code-slot'),
      rect('linking-action-slot'),
      rect('linking-qr-slot'),
      rect('linking-footer'),
    ];

    controller
      ..activePin = PlexPin(
        id: 3,
        code: 'FAILED',
        expiresAt: DateTime.now().add(const Duration(minutes: 4)),
      )
      ..error = 'Synthetic safe Plex failure.';
    controller.notifyListeners();
    await tester.pump();
    final failureState = [
      rect('linking-code-slot'),
      rect('linking-action-slot'),
      rect('linking-qr-slot'),
      rect('linking-footer'),
    ];

    for (var index = 0; index < codeState.length; index++) {
      expect(
        expiredState[index],
        codeState[index],
        reason: 'expired slot $index',
      );
      expect(
        failureState[index],
        codeState[index],
        reason: 'failure slot $index',
      );
    }
    final separator = tester.widget<Visibility>(
      find
          .ancestor(of: find.text('or'), matching: find.byType(Visibility))
          .first,
    );
    expect(separator.visible, isFalse);
    expect(
      find.text('That code expired before sign-in finished.'),
      findsNothing,
    );
    expect(find.text('Synthetic safe Plex failure.'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    await tester.tap(find.byKey(const ValueKey('profile-card-profile')));
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

  testWidgets('server action semantics follow pending and error state', (
    tester,
  ) async {
    const server = PlexServer(
      id: 'server',
      name: 'Test server',
      connections: [],
    );
    final controller = _ServerController()
      ..stage = SetupStage.servers
      ..servers = const [server];
    addTearDown(controller.dispose);
    await show(tester, controller);

    expect(
      tester
          .getSemantics(find.widgetWithText(FilledButton, 'Connect'))
          .getSemanticsData()
          .label,
      'Connect to Test server',
    );

    final pending = Completer<void>();
    controller.pendingSelection = pending;
    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(
      tester
          .getSemantics(find.widgetWithText(FilledButton, 'Connecting…'))
          .getSemanticsData()
          .label,
      'Connecting…',
    );

    pending.complete();
    await tester.pump();
    controller.failSelection = true;
    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(
      tester
          .getSemantics(find.widgetWithText(FilledButton, 'Retry'))
          .getSemanticsData()
          .label,
      'Retry',
    );
  }, semanticsEnabled: true);

  testWidgets('refresh and profile switch clear stale server errors', (
    tester,
  ) async {
    const server = PlexServer(
      id: 'server',
      name: 'Test server',
      connections: [],
    );
    final controller = _ServerController()
      ..stage = SetupStage.servers
      ..servers = const [server]
      ..profiles = const [
        PlexHomeUser(id: 'one', name: 'One', protected: false),
        PlexHomeUser(id: 'two', name: 'Two', protected: false),
      ]
      ..failSelection = true;
    addTearDown(controller.dispose);
    await show(tester, controller);

    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(find.text('Server selection failed.'), findsOneWidget);

    await tester.tap(find.text('Refresh servers'));
    await tester.pump();
    expect(find.text('Fresh discovery failed.'), findsOneWidget);
    expect(find.text('Server selection failed.'), findsNothing);

    await tester.tap(find.text('Connect'));
    await tester.pump();
    await tester.tap(find.text('Switch profile'));
    await tester.pump();
    controller.showServers();
    await tester.pump();
    expect(find.text('Server selection failed.'), findsNothing);
  });

  testWidgets('current server Continue returns without selecting again', (
    tester,
  ) async {
    final current = PlexServer(
      id: 'current',
      name: 'Current server',
      connections: const [],
    );
    final other = PlexServer(
      id: 'other',
      name: 'Other server',
      connections: [
        PlexConnection(
          uri: Uri.parse('https://other.invalid'),
          local: false,
          relay: false,
          latency: Duration(milliseconds: 126),
        ),
      ],
    );
    final controller = _ServerController()
      ..stage = SetupStage.servers
      ..servers = [current, other]
      ..server = current
      ..connection = PlexConnection(
        uri: Uri.parse('https://current.invalid'),
        local: true,
        relay: false,
      )
      ..serverSelectionCanCancel = true;
    addTearDown(controller.dispose);
    await show(tester, controller, accountOrigin: true);

    expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Connect'), findsOneWidget);
    expect(
      tester.getSize(find.widgetWithText(FilledButton, 'Continue')).height,
      56,
    );
    expect(
      tester
          .getSize(
            find.descendant(
              of: find.widgetWithText(OutlinedButton, 'Connect'),
              matching: find.byType(Material),
            ),
          )
          .height,
      44,
    );
    expect(find.text('‹ Settings · Account'), findsOneWidget);
    expect(find.text('Not measured yet'), findsOneWidget);
    expect(find.text('Direct remote · 126 ms'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump();
    expect(controller.selectCalls, 0);
    expect(controller.stage, SetupStage.ready);
  });

  testWidgets('first-run current Continue enters setup without reconnecting', (
    tester,
  ) async {
    final current = PlexServer(
      id: 'current',
      name: 'Current server',
      connections: const [],
    );
    final controller = _ServerController()
      ..stage = SetupStage.servers
      ..servers = [current]
      ..server = current
      ..connection = PlexConnection(
        uri: Uri.parse('https://current.invalid'),
        local: true,
        relay: false,
        latency: const Duration(milliseconds: 126),
      );
    addTearDown(controller.dispose);
    await show(tester, controller);

    expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump();
    expect(controller.stage, SetupStage.channelSetup);
    expect(controller.selectCalls, 0);
  });

  testWidgets(
    'pending and failed current selections keep one label and do not reconnect on Continue',
    (tester) async {
      final current = PlexServer(
        id: 'current',
        name: 'Current server',
        connections: const [],
      );
      final other = PlexServer(
        id: 'other',
        name: 'Other server',
        connections: const [],
      );
      final controller = _ServerController()
        ..stage = SetupStage.servers
        ..servers = [current, other]
        ..server = current
        ..promoteSelection = true;
      addTearDown(controller.dispose);
      await show(tester, controller);

      final pending = Completer<void>();
      controller.pendingSelection = pending;
      await tester.tap(find.widgetWithText(OutlinedButton, 'Connect'));
      await tester.pump();
      final pendingButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Connecting…'),
      );
      expect(pendingButton.onPressed, isNull);
      expect(
        tester
            .getSemantics(find.widgetWithText(FilledButton, 'Connecting…'))
            .getSemanticsData()
            .label,
        'Connecting…',
      );

      pending.complete();
      await tester.pumpAndSettle();
      controller.failSelection = true;
      await tester.tap(find.widgetWithText(OutlinedButton, 'Connect'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.widgetWithText(FilledButton, 'Continue'))
            .getSemanticsData()
            .label,
        'Continue',
      );
      final calls = controller.selectCalls;
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pump();
      expect(controller.selectCalls, calls);
    },
    semanticsEnabled: true,
  );

  test(
    'continue current server rejects busy, missing, and incorrect stages',
    () {
      final controller = FixtureController();
      addTearDown(controller.dispose);
      final current = PlexServer(
        id: 'current',
        name: 'Current server',
        connections: const [],
      );
      controller.server = current;
      expect(controller.continueCurrentServer(), isFalse);

      controller
        ..stage = SetupStage.servers
        ..busy = true;
      expect(controller.continueCurrentServer(), isFalse);

      controller
        ..busy = false
        ..server = null;
      expect(controller.continueCurrentServer(), isFalse);
    },
  );

  testWidgets('account-origin PIN back returns directly to Account', (
    tester,
  ) async {
    final controller = _PinController()
      ..stage = SetupStage.profiles
      ..server = const PlexServer(id: 'server', name: 'Server', connections: [])
      ..profileSelectionCanCancel = true
      ..profiles = const [
        PlexHomeUser(id: 'profile', name: 'Protected profile', protected: true),
      ];
    addTearDown(controller.dispose);
    await show(tester, controller, accountOrigin: true);
    await tester.tap(find.byKey(const ValueKey('profile-card-profile')));
    await tester.pump();

    expect(find.byType(Dialog), findsNothing);
    expect(find.text('‹ Settings · Account'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(controller.stage, SetupStage.ready);
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

class _ServerController extends FixtureController {
  Completer<void>? pendingSelection;
  bool failSelection = false;
  bool promoteSelection = false;
  int selectCalls = 0;

  @override
  Future<void> selectServer(PlexServer server) async {
    selectCalls++;
    if (promoteSelection) {
      this.server = server;
      notifyListeners();
    }
    final pending = pendingSelection;
    if (pending != null) {
      await pending.future;
      pendingSelection = null;
    }
    if (failSelection) {
      error = 'Server selection failed.';
      notifyListeners();
    }
  }

  @override
  Future<void> refreshServers() async {
    error = 'Fresh discovery failed.';
    notifyListeners();
  }
}
