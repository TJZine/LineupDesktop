import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_shell.dart';
import 'package:lineup_desktop/app/lineup_restore_view.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/app/onboarding_view.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/app_ui.dart';

import '../support/ui_fixture.dart';

void main() {
  for (final picker in ['profiles', 'servers']) {
    for (final fail in [false, true]) {
      testWidgets('NAV-I2 cancellable $picker real save fail=$fail', (
        tester,
      ) async {
        final store = _ProfileRecoveryStore('picker')
          ..state = PersistedState(
            profileId: 'owner',
            selectedServerByProfile: const {'owner': 'server'},
            selectedLibraryIdsByProfileServer: const {
              'owner': {
                'server': ['movies'],
              },
            },
            channelsByProfileServer: {
              'owner': {
                'server': [
                  Channel(
                    id: 'saved',
                    number: 1,
                    name: 'Saved channel',
                    source: const LibrarySource(
                      libraryId: 'movies',
                      libraryType: PlexLibraryType.movie,
                    ),
                    playbackMode: PlaybackMode.sequential,
                    anchor: DateTime.utc(2026),
                    shuffleSeed: 1,
                  ),
                ],
              },
            },
          );
        final before = store.state.toJson();
        final plex = _PickerBoundaryPlex();
        final controller = LineupController(
          store: store,
          credentials: MemoryCredentialStore(accountToken: 'synthetic-account'),
          plex: plex,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        expect(controller.stage, SetupStage.ready);
        if (picker == 'profiles') {
          controller.showProfiles();
          expect(controller.profileSelectionCanCancel, isTrue);
          expect(controller.profileSelectionOriginStage, SetupStage.ready);
        } else {
          controller.showServers();
          expect(controller.serverSelectionCanCancel, isTrue);
        }
        await tester.pumpWidget(
          DeviceProfileScope(
            profile: tvProfile,
            child: MaterialApp(
              builder: LineupCanvas.builder,
              theme: LineupTheme.forName(
                LineupThemeName.emberSteel,
                formFactor: profileFor(true).formFactor,
              ),
              home: UpstreamOnboardingView(
                controller: controller,
                onLogout: () async {},
                openBrowser: () async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final state = tester.state<UpstreamOnboardingViewState>(
          find.byType(UpstreamOnboardingView),
        );
        store.holdPickerSave = true;
        final saves = store.saveCalls;
        final selection = picker == 'profiles'
            ? controller
                  .selectProfile(controller.profiles.last)
                  .then<void>((_) {})
            : controller.selectServer(controller.servers.single);
        await store.pickerSaveStarted.future;
        await tester.pump();
        expect(find.byKey(const Key('profile-pin-sheet')), findsNothing);
        expect(controller.busy, isTrue);
        expect(
          picker == 'profiles'
              ? controller.profileSelectionCanCancel
              : controller.serverSelectionCanCancel,
          isFalse,
        );
        expect(state.handleBack(), isTrue);
        expect(state.handleBack(), isTrue);
        expect(
          controller.stage,
          picker == 'profiles' ? SetupStage.profiles : SetupStage.servers,
        );
        expect(store.saveCalls, saves + 1);
        expect(store.state.toJson(), before);
        if (fail) {
          store.gate.completeError(StateError('synthetic picker save failure'));
        } else {
          store.gate.complete();
        }
        await selection;
        await tester.pumpAndSettle();
        expect(store.saveCalls, saves + 1);
        expect(controller.busy, isFalse);
        expect(controller.canSwitchServer, isTrue);
        if (fail) {
          expect(store.state.toJson(), before);
          expect(controller.profile?.id, 'owner');
          expect(controller.server?.id, 'server');
          expect(
            picker == 'profiles'
                ? controller.profileSelectionCanCancel
                : controller.serverSelectionCanCancel,
            isTrue,
          );
          if (picker == 'profiles') {
            expect(controller.profileSelectionOriginStage, SetupStage.ready);
          }
          expect(state.handleBack(), isTrue);
          await tester.pumpAndSettle();
          expect(controller.stage, SetupStage.ready);
        } else {
          expect(controller.error, isNull);
          expect(
            controller.stage,
            picker == 'profiles' ? SetupStage.servers : SetupStage.ready,
          );
          expect(controller.profileSelectionCanCancel, isFalse);
          expect(controller.serverSelectionCanCancel, isFalse);
          expect(
            store.state.profileId,
            picker == 'profiles' ? 'guest' : 'owner',
          );
        }
      });
    }
  }
  for (final failure in [
    'connection',
    'libraries',
    'server save',
    'server save success',
    'discovery',
    'wrong PIN',
    'profile save',
    'none',
    'saved success',
    'restore',
  ]) {
    testWidgets('real shell protected profile recovery: $failure', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final saved = ![
        'none',
        'wrong PIN',
        'profile save',
        'discovery',
      ].contains(failure);
      final store = _ProfileRecoveryStore(failure)
        ..state = PersistedState(
          settings: const LineupSettings(reduceMotion: true),
          selectedServerByProfile: saved
              ? const {'protected': 'server'}
              : const {},
          selectedLibraryIdsByProfileServer: failure == 'restore'
              ? const {
                  'protected': {
                    'server': ['movies'],
                  },
                }
              : const {},
          channelsByProfileServer: failure == 'restore'
              ? {
                  'protected': {
                    'server': [
                      Channel(
                        id: 'saved',
                        number: 1,
                        name: 'Saved channel',
                        source: const LibrarySource(
                          libraryId: 'movies',
                          libraryType: PlexLibraryType.movie,
                        ),
                        playbackMode: PlaybackMode.sequential,
                        anchor: DateTime.utc(2026),
                        shuffleSeed: 1,
                      ),
                    ],
                  },
                }
              : const {},
        );
      final plex = _ProfileRecoveryPlex(failure);
      final controller = LineupController(
        store: store,
        credentials: MemoryCredentialStore(accountToken: 'synthetic-account'),
        plex: plex,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.stage, SetupStage.profiles);
      await tester.pumpWidget(
        MaterialApp(
          builder: LineupCanvas.builder,
          home: LineupShell(
            controller: controller,
            player: FixturePlayer(),
            profile: desktopProfile,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-card-protected')));
      await tester.pumpAndSettle();
      for (final key in [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
      ]) {
        await tester.sendKeyEvent(key);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(plex.submittedPins, ['1234']);
      if ([
        'connection',
        'libraries',
        'server save',
        'discovery',
      ].contains(failure)) {
        expect(controller.profile?.id, 'protected');
        expect(store.state.profileId, 'protected');
        expect(controller.busy, isTrue);
        expect(controller.stage, SetupStage.servers);
        expect(find.byKey(const Key('profile-pin-sheet')), findsNothing);
        if (failure == 'server save') {
          expect(store.serverSaveStarted, isTrue);
          final state = tester.state<UpstreamOnboardingViewState>(
            find.byType(UpstreamOnboardingView),
          );
          expect(state.handleBack(), isTrue);
          expect(controller.stage, SetupStage.servers);
          store.gate.completeError(StateError('synthetic save failure'));
        } else {
          expect(plex.gatedRequestStarted, isTrue);
          final state = tester.state<UpstreamOnboardingViewState>(
            find.byType(UpstreamOnboardingView),
          );
          expect(state.handleBack(), isTrue);
          expect(controller.stage, SetupStage.servers);
          plex.gate.completeError(
            const PlexException(
              'server-unreachable',
              'Synthetic server unavailable.',
            ),
          );
        }
        await tester.pumpAndSettle();
        expect(controller.busy, isFalse);
        expect(controller.error, isNotNull);
        expect(controller.stage, SetupStage.servers);
        expect(controller.server, isNull);
        expect(store.state.profileId, 'protected');
        expect(find.byKey(const Key('profile-pin-sheet')), findsNothing);
        if (failure != 'discovery') {
          expect(find.text('Synthetic server'), findsWidgets);
        }
        expect(find.text('Refresh servers'), findsOneWidget);
      } else if (failure == 'server save success') {
        expect(controller.stage, SetupStage.servers);
        expect(controller.busy, isTrue);
        expect(store.serverSaveStarted, isTrue);
        final state = tester.state<UpstreamOnboardingViewState>(
          find.byType(UpstreamOnboardingView),
        );
        expect(state.handleBack(), isTrue);
        expect(controller.stage, SetupStage.servers);
        store.gate.complete();
        await tester.pumpAndSettle();
        expect(controller.busy, isFalse);
        expect(controller.error, isNull);
        expect(controller.stage, SetupStage.channelSetup);
      } else if (['wrong PIN', 'profile save'].contains(failure)) {
        if (failure == 'profile save') {
          expect(store.profileSaveStarted, isTrue);
          expect(controller.busy, isTrue);
          final state = tester.state<UpstreamOnboardingViewState>(
            find.byType(UpstreamOnboardingView),
          );
          expect(state.handleBack(), isTrue);
          expect(controller.stage, SetupStage.profiles);
          store.gate.completeError(StateError('synthetic profile failure'));
        }
        await tester.pumpAndSettle();
        expect(controller.profile, isNull);
        expect(store.state.profileId, isNull);
        expect(controller.stage, SetupStage.profiles);
        expect(controller.busy, isFalse);
        expect(controller.error, isNotNull);
        expect(find.byKey(const Key('profile-pin-sheet')), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('profile-card-protected')),
          findsOneWidget,
        );
      } else if (failure == 'restore') {
        expect(controller.server?.id, 'server');
        expect(store.state.profileId, 'protected');
        expect(controller.restoringSavedLineup, isTrue);
        expect(find.byType(LineupRestoreView), findsOneWidget);
        expect(find.byType(UpstreamOnboardingView), findsNothing);
        plex.scanGate.complete(const PlexLibraryScan(items: []));
        await tester.pumpAndSettle();
        expect(controller.busy, isFalse);
        expect(find.byKey(const Key('profile-pin-sheet')), findsNothing);
      } else {
        await tester.pumpAndSettle();
        expect(store.state.profileId, 'protected');
        expect(controller.busy, isFalse);
        expect(controller.error, isNull);
        expect(find.byKey(const Key('profile-pin-sheet')), findsNothing);
        expect(
          controller.stage,
          failure == 'none' ? SetupStage.servers : SetupStage.channelSetup,
        );
        if (failure == 'none') {
          expect(find.text('Synthetic server'), findsWidgets);
        } else {
          expect(find.byType(UpstreamOnboardingView), findsNothing);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('single-profile server picker exposes quiet Sign out', (
    tester,
  ) async {
    final controller = FixtureController(
      scenario: LineupScenario(
        stage: SetupStage.servers,
        profiles: const [
          PlexHomeUser(id: 'one', name: 'One', protected: false),
        ],
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: LineupCanvas.builder,
        home: UpstreamOnboardingView(
          controller: controller,
          onLogout: () async {},
          onRequestLogout: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No servers found'), findsOneWidget);
    expect(find.text('Refresh servers'), findsOneWidget);
    final signOut = find.widgetWithText(TextButton, 'Sign out');
    expect(signOut, findsOneWidget);
    expect(tester.widget<TextButton>(signOut).onPressed, isNotNull);
    controller.fixtureActor.present(LineupPresentation(busy: true));
    controller.notifyListeners();
    await tester.pump();
    expect(tester.widget<TextButton>(signOut).onPressed, isNull);
    controller.fixtureActor.present(LineupPresentation(busy: false));
    controller.notifyListeners();
    await tester.pump();
    expect(tester.widget<TextButton>(signOut).onPressed, isNotNull);
    expect(find.text('Switch profile'), findsNothing);
  });

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
          final controller = FixtureController(
            scenario: LineupScenario(
              settings: const LineupSettings(reduceMotion: true),
              stage: stage,
              profiles: const [
                PlexHomeUser(
                  id: 'guest',
                  name: 'Synthetic guest profile',
                  protected: false,
                ),
              ],
              servers: const [
                PlexServer(
                  id: 'server',
                  name: 'Synthetic local server',
                  connections: [],
                ),
              ],
            ),
          );
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
      final controller = FixtureController(
        scenario: LineupScenario(stage: stage),
      );
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
    LineupController controller, {
    Future<void> Function()? browser,
    bool accountOrigin = false,
    bool isTv = false,
    double textScale = 1,
    LineupThemeName themeName = LineupThemeName.emberSteel,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: DeviceProfileScope(
            profile: profileFor(isTv),
            child: LineupCanvas(
              reduceMotion: controller.settings.reduceMotion,
              child: child!,
            ),
          ),
        ),
        theme: LineupTheme.forName(
          themeName,
          largeFocusIndicators: false,
          formFactor: profileFor(isTv).formFactor,
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

  testWidgets(
    'NAV-I2 onboarding roots are side-effect-free and pickers cancel',
    (tester) async {
      final root = FixtureController(
        scenario: const LineupScenario(stage: SetupStage.profiles),
      );
      addTearDown(root.dispose);
      await show(tester, root, isTv: true);
      final rootState = tester.state<UpstreamOnboardingViewState>(
        find.byType(UpstreamOnboardingView),
      );
      expect(rootState.handleBack(), isFalse);
      expect(root.stage, SetupStage.profiles);

      await tester.pumpWidget(const SizedBox.shrink());
      final cancellable = _ServerController(
        scenario: const LineupScenario(
          stage: SetupStage.servers,
          server: PlexServer(id: 'server', name: 'Server', connections: []),
          servers: [PlexServer(id: 'server', name: 'Server', connections: [])],
          profiles: [
            PlexHomeUser(id: 'profile', name: 'Profile', protected: false),
          ],
          serverSelectionOrigin: SetupStage.ready,
        ),
      );
      addTearDown(cancellable.dispose);
      await show(tester, cancellable, isTv: true);
      final state = tester.state<UpstreamOnboardingViewState>(
        find.byType(UpstreamOnboardingView),
      );
      expect(state.handleBack(), isTrue);
      expect(cancellable.stage, SetupStage.ready);
      expect(cancellable.serverSelectionCanCancel, isFalse);
    },
  );

  testWidgets('NAV-I2 submitting PIN Back is claimed by the PIN owner', (
    tester,
  ) async {
    final controller = _PinController(
      scenario: const LineupScenario(
        stage: SetupStage.profiles,
        profiles: [
          PlexHomeUser(id: 'profile', name: 'Protected', protected: true),
        ],
      ),
    )..submitGate = Completer<void>();
    addTearDown(controller.dispose);
    await show(tester, controller, isTv: true);
    await tester.tap(find.byKey(const ValueKey('profile-card-profile')));
    await tester.pump();
    for (final key in [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
    ]) {
      await tester.sendKeyEvent(key);
    }
    await tester.pump();
    expect(find.byKey(const Key('profile-pin-sheet')), findsOneWidget);
    final state = tester.state<UpstreamOnboardingViewState>(
      find.byType(UpstreamOnboardingView),
    );
    expect(state.handleBack(), isTrue);
    expect(find.byKey(const Key('profile-pin-sheet')), findsOneWidget);
    controller.submitGate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('NAV-I2 desktop picker ignores non-Back navigation keys', (
    tester,
  ) async {
    final cases = [
      (
        stage: SetupStage.profiles,
        scenario: const LineupScenario(
          stage: SetupStage.profiles,
          profiles: [
            PlexHomeUser(id: 'profile', name: 'Profile', protected: false),
          ],
          profileSelectionOrigin: SetupStage.ready,
        ),
      ),
      (
        stage: SetupStage.servers,
        scenario: const LineupScenario(
          stage: SetupStage.servers,
          servers: [PlexServer(id: 'server', name: 'Server', connections: [])],
          serverSelectionOrigin: SetupStage.ready,
        ),
      ),
    ];

    for (final testCase in cases) {
      final controller = FixtureController(scenario: testCase.scenario);
      addTearDown(controller.dispose);
      await show(tester, controller);
      final navigation = tester
          .widgetList<Focus>(find.byType(Focus))
          .firstWhere(
            (focus) => focus.focusNode?.debugLabel == 'Onboarding navigation',
          )
          .focusNode!;
      navigation.requestFocus();
      await tester.pump();

      for (final key in [
        LogicalKeyboardKey.tab,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.keyX,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pump();
      }
      expect(controller.stage, testCase.stage);
      expect(
        testCase.stage == SetupStage.profiles
            ? controller.profileSelectionCanCancel
            : controller.serverSelectionCanCancel,
        isTrue,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(controller.stage, SetupStage.ready);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('NAV-I2 Back retries failed secure linking cancellation', (
    tester,
  ) async {
    final plex = _BackLinkPlex();
    final controller = LineupController(
      store: MemoryAppStore(),
      credentials: MemoryCredentialStore(accountToken: 'account-token'),
      plex: plex,
      pinPollInterval: const Duration(hours: 1),
    );
    addTearDown(controller.dispose);
    await controller.startLinking();
    final browser = Completer<void>();
    await show(tester, controller, browser: () => browser.future);
    await tester.tap(find.text('Open browser'));
    await tester.pump();

    final state = tester.state<UpstreamOnboardingViewState>(
      find.byType(UpstreamOnboardingView),
    );
    plex.cancelGate = Completer<void>();
    expect(state.handleBack(), isTrue);
    expect(state.handleBack(), isTrue);
    await plex.cancelStarted.future;
    expect(plex.cancelCalls, 1);
    browser.complete();
    plex.cancelGate!.complete();
    await tester.pumpAndSettle();
    expect(controller.stage, SetupStage.linking);
    expect(controller.secureCancellationRequired, isTrue);

    plex.failCancellation = false;
    expect(state.handleBack(), isTrue);
    await tester.pumpAndSettle();
    expect(plex.cancelCalls, 2);
    expect(controller.stage, SetupStage.welcome);
  });

  testWidgets(
    'injected TV capability controls onboarding traversal on desktop',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final controller = FixtureController(
        scenario: const LineupScenario(stage: SetupStage.welcome),
      );
      addTearDown(controller.dispose);

      try {
        await show(tester, controller, isTv: true);

        final navigation = tester
            .widgetList<Focus>(find.byType(Focus))
            .firstWhere(
              (focus) => focus.focusNode?.debugLabel == 'Onboarding navigation',
            );
        expect(navigation.skipTraversal, isTrue);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  for (final themeName in LineupThemeName.values) {
    for (final tv in [false, true]) {
      testWidgets(
        'Current badge follows actual profile focus: $themeName TV=$tv',
        (tester) async {
          const active = PlexHomeUser(
            id: 'active',
            name: 'Active viewer',
            protected: true,
            admin: true,
            restricted: true,
          );
          const other = PlexHomeUser(
            id: 'other',
            name: 'Other viewer',
            protected: false,
          );
          final controller = FixtureController(
            scenario: const LineupScenario(
              stage: SetupStage.profiles,
              profile: active,
              profiles: [active, other],
            ),
          );
          final strategy = FocusManager.instance.highlightStrategy;
          try {
            FocusManager.instance.highlightStrategy =
                FocusHighlightStrategy.alwaysTouch;
            await show(tester, controller, isTv: tv, themeName: themeName);
            final activeButton = find.widgetWithText(
              TextButton,
              'Active viewer',
            );
            final otherButton = find.widgetWithText(TextButton, 'Other viewer');
            final node = tester.widget<TextButton>(activeButton).focusNode!;
            final otherNode = tester.widget<TextButton>(otherButton).focusNode!;
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            otherNode.requestFocus();
            await tester.pumpAndSettle();
            final current = find.text('Current');
            final element = tester.element(current);
            final base = LineupTheme.of(element);
            Color ink(String label) => tester
                .widget<RichText>(
                  find.descendant(
                    of: find.text(label),
                    matching: find.byType(RichText),
                  ),
                )
                .text
                .style!
                .color!;
            expect(ink('Current'), base.progressFill);
            node.requestFocus();
            await tester.pumpAndSettle();
            expect(node.hasPrimaryFocus, isTrue);
            expect(
              FocusManager.instance.highlightMode,
              FocusHighlightMode.touch,
            );
            final focused = LineupTheme.of(tester.element(current));
            expect(
              ink('Current'),
              tv ? focused.primaryText : base.progressFill,
            );
            expect(ink('Admin'), focused.secondaryText);
            expect(ink('Restricted'), focused.secondaryText);
            if (tv) {
              final badge = tester.widget<DecoratedBox>(
                find
                    .ancestor(of: current, matching: find.byType(DecoratedBox))
                    .first,
              );
              final inset = (badge.decoration as BoxDecoration).color!;
              expect(inset, focused.elevatedSurface);
              final light = inset.computeLuminance();
              final dark = ink('Current').computeLuminance();
              expect((light + .05) / (dark + .05), greaterThanOrEqualTo(4.7));
            }
            expect(tester.element(current), same(element));
            otherNode.requestFocus();
            await tester.pumpAndSettle();
            expect(ink('Current'), base.progressFill);
            expect(tester.element(current), same(element));
            expect(
              tester.widget<TextButton>(activeButton).focusNode,
              same(node),
            );
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            controller.dispose();
            FocusManager.instance.highlightStrategy = strategy;
          }
        },
      );
    }
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
    final controller = FixtureController(
      scenario: LineupScenario(
        stage: SetupStage.profiles,
        profile: active,
        profiles: const [active, other],
        profileSelectionOrigin: SetupStage.ready,
      ),
    );
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

  testWidgets('Android TV profile focus uses shared fill ink and scale', (
    tester,
  ) async {
    const active = PlexHomeUser(
      id: 'active',
      name: 'Active viewer',
      protected: false,
    );
    final controller = FixtureController(
      scenario: const LineupScenario(
        stage: SetupStage.profiles,
        profile: active,
        profiles: [active],
      ),
    );
    addTearDown(controller.dispose);

    await show(tester, controller, isTv: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 160));

    expect(
      tester
          .widgetList<AnimatedScale>(find.byType(AnimatedScale))
          .any((scale) => scale.scale == 1.06),
      isTrue,
    );
    expect(
      LineupTheme.of(tester.element(find.text('Active viewer').last))
          .primaryText,
      const Color(0xFF090806),
    );
  });

  testWidgets('Android TV profile focus does not scale under Reduce Motion', (
    tester,
  ) async {
    const active = PlexHomeUser(
      id: 'active',
      name: 'Active viewer',
      protected: false,
    );
    final controller = FixtureController(
      scenario: const LineupScenario(
        settings: LineupSettings(reduceMotion: true),
        stage: SetupStage.profiles,
        profile: active,
        profiles: [active],
      ),
    );
    addTearDown(controller.dispose);

    await show(tester, controller, isTv: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 160));

    expect(
      tester
          .widgetList<AnimatedScale>(find.byType(AnimatedScale))
          .every((scale) => scale.scale == 1.0),
      isTrue,
    );
  });

  testWidgets('profile card clamp accepts a sub-pixel width constraint', (
    tester,
  ) async {
    final controller = FixtureController(
      scenario: LineupScenario(
        stage: SetupStage.profiles,
        profiles: const [
          PlexHomeUser(id: 'profile', name: 'Profile', protected: false),
        ],
      ),
    );
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

  testWidgets(
    'Android transfers remote focus from welcome to PIN actions',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = LineupController(
        store: MemoryAppStore(),
        credentials: MemoryCredentialStore(),
        plex: _PinPollingPlex(
          PlexPin(
            id: 71,
            code: 'REMOTE',
            expiresAt: DateTime.now().add(const Duration(minutes: 4)),
          ),
        ),
      );
      addTearDown(controller.dispose);
      var browserCalls = 0;
      await show(
        tester,
        controller,
        browser: () async {
          browserCalls++;
          throw StateError('No browser on this synthetic TV.');
        },
        isTv: true,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.stage, SetupStage.linking);
      expect(find.text('REMOTE'), findsOneWidget);
      final browser = find.widgetWithText(FilledButton, 'Open on this TV');
      expect(tester.widget<FilledButton>(browser).focusNode!.hasFocus, isTrue);
      expect(find.text('Copy code'), findsNothing);
      expect(
        find.bySemanticsLabel(
          'Open plex.tv/link in a browser on this TV, if available.',
        ),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(browserCalls, 1);
      expect(find.textContaining('Couldn’t open your browser'), findsOneWidget);
      expect(find.text('REMOTE'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(find.text('Copy code'), findsNothing);
      await controller.cancelLinking();
    },
    semanticsEnabled: true,
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('explicit browser failure retains complete code and QR', (
    tester,
  ) async {
    final controller = FixtureController(
      scenario: LineupScenario(
        stage: SetupStage.linking,
        activePin: PlexPin(
          id: 7,
          code: 'ABCDEF',
          expiresAt: DateTime.now().add(const Duration(minutes: 4)),
        ),
      ),
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
    final controller = FixtureController(
      scenario: LineupScenario(
        stage: SetupStage.linking,
        activePin: PlexPin(
          id: 1,
          code: 'FIRST',
          expiresAt: DateTime.now().add(const Duration(minutes: 4)),
        ),
      ),
    );
    addTearDown(controller.dispose);
    await show(tester, controller, browser: () => pending.future);
    await tester.tap(find.text('Open browser'));
    controller.fixtureActor.present(
      LineupPresentation(
        pin: (
          PlexPin(
            id: 2,
            code: 'SECOND',
            expiresAt: DateTime.now().add(const Duration(minutes: 4)),
          ),
        ),
      ),
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
      final controller = FixtureController(
        scenario: LineupScenario(
          stage: SetupStage.linking,
          activePin: PlexPin(
            id: 1,
            code: 'FIRST',
            expiresAt: DateTime.now().add(const Duration(minutes: 4)),
          ),
        ),
      );
      addTearDown(controller.dispose);
      var calls = 0;
      await show(
        tester,
        controller,
        browser: () => ++calls == 1 ? first.future : second.future,
      );
      await tester.tap(find.text('Open browser'));
      controller.fixtureActor.present(
        LineupPresentation(
          pin: (
            PlexPin(
              id: 2,
              code: 'SECOND',
              expiresAt: DateTime.now().add(const Duration(minutes: 4)),
            ),
          ),
        ),
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
    final controller = FixtureController(
      scenario: LineupScenario(
        stage: SetupStage.linking,
        activePin: PlexPin(
          id: 1,
          code: 'EXPIRED',
          expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
        ),
      ),
    );
    addTearDown(controller.dispose);
    await show(tester, controller);
    expect(find.text('Open browser'), findsNothing);
    expect(find.text('Get a new code'), findsOneWidget);
    expect(controller.activePin?.id, 1);
  });

  for (final (label, offset, expired) in [
    ('before', const Duration(seconds: -1), false),
    ('exactly at', Duration.zero, true),
    ('after', const Duration(seconds: 1), true),
  ]) {
    testWidgets('PIN clock $label expiration uses one boundary', (
      tester,
    ) async {
      final expiresAt = DateTime.utc(2026, 10, 15, 12);
      final now = expiresAt.add(offset);
      final controller = LineupController(
        store: MemoryAppStore(),
        credentials: MemoryCredentialStore(),
        plex: PlexClient(
          clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
          httpClient: testPlexHttpClient(),
        ),
        clock: () => now,
        scenario: LineupScenario(
          stage: SetupStage.linking,
          activePin: PlexPin(id: 9, code: 'CLOCK', expiresAt: expiresAt),
        ),
      );
      addTearDown(controller.dispose);

      expect(controller.pinExpired, expired);
      expect(controller.pinUsable, !expired);
      expect(controller.pinRemaining, expiresAt.difference(now));
      await show(tester, controller);

      if (expired) {
        expect(
          find.text('That code expired before sign-in finished.'),
          findsOneWidget,
        );
        expect(find.text('Get a new code'), findsOneWidget);
        expect(find.text('Open browser'), findsNothing);
      } else {
        expect(find.text('Open browser'), findsOneWidget);
        expect(find.text('Get a new code'), findsNothing);
      }
    });
  }

  test('PIN polling expires at the exact injected clock boundary', () async {
    final expiresAt = DateTime.utc(2026, 10, 15, 12);
    final plex = _PinPollingPlex(
      PlexPin(id: 10, code: 'POLL', expiresAt: expiresAt),
    );
    final controller = LineupController(
      store: MemoryAppStore(),
      credentials: MemoryCredentialStore(),
      plex: plex,
      clock: () => expiresAt,
      pinPollInterval: Duration.zero,
    );
    addTearDown(controller.dispose);

    await controller.startLinking();
    await Future<void>.delayed(Duration.zero);

    expect(plex.pollCalls, 0);
    expect(plex.cancelPinCalls, 0);
    expect(controller.activePin, isNull);
    expect(controller.error, 'The Plex link code expired. Request a new code.');
  });

  testWidgets('linking slots stay aligned across code and failure states', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(640, 560)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = FixtureController(
      scenario: LineupScenario(
        stage: SetupStage.linking,
        activePin: PlexPin(
          id: 1,
          code: 'ACTIVE',
          expiresAt: DateTime.now().add(const Duration(minutes: 4)),
        ),
      ),
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
      ..fixtureActor.present(
        LineupPresentation(
          pin: (
            PlexPin(
              id: 2,
              code: 'EXPIRED',
              expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
            ),
          ),
        ),
      )
      ..fixtureActor.present(LineupPresentation(error: (null,)));
    controller.notifyListeners();
    await tester.pump();
    final expiredState = [
      rect('linking-code-slot'),
      rect('linking-action-slot'),
      rect('linking-qr-slot'),
      rect('linking-footer'),
    ];

    controller
      ..fixtureActor.present(
        LineupPresentation(
          pin: (
            PlexPin(
              id: 3,
              code: 'FAILED',
              expiresAt: DateTime.now().add(const Duration(minutes: 4)),
            ),
          ),
        ),
      )
      ..fixtureActor.present(
        LineupPresentation(error: ('Synthetic safe Plex failure.',)),
      );
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
    final controller = _PinController(
      scenario: LineupScenario(
        stage: SetupStage.profiles,
        profiles: const [
          PlexHomeUser(id: 'profile', name: 'Test Profile', protected: true),
        ],
      ),
    );
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

  testWidgets('unexpected PIN submission failure restores focus and retry', (
    tester,
  ) async {
    final controller = _PinController(
      scenario: LineupScenario(
        stage: SetupStage.profiles,
        profiles: const [
          PlexHomeUser(id: 'profile', name: 'Test Profile', protected: true),
        ],
      ),
    )..throwOnSubmit = true;
    addTearDown(controller.dispose);
    await show(tester, controller);
    await tester.tap(find.byKey(const ValueKey('profile-card-profile')));
    await tester.pumpAndSettle();
    for (final key in [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
    ]) {
      await tester.sendKeyEvent(key);
    }
    await tester.pumpAndSettle();
    expect(controller.submitted, ['1234']);
    expect(tester.takeException(), isNull);
    expect(
      find.text('The profile could not be selected. Try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('private failure'), findsNothing);
    expect(find.textContaining('1234'), findsNothing);
    expect(find.bySemanticsLabel('Checking PIN'), findsNothing);
    expect(find.bySemanticsLabel('0 of 4 digits entered'), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Profile PIN digit 1',
    );

    controller.throwOnSubmit = false;
    for (final key in [
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit1,
    ]) {
      await tester.sendKeyEvent(key);
    }
    await tester.pumpAndSettle();
    expect(controller.submitted, ['1234', '4321']);
    expect(find.text('Incorrect PIN. Try again.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server action semantics follow pending and error state', (
    tester,
  ) async {
    const server = PlexServer(
      id: 'server',
      name: 'Test server',
      connections: [],
    );
    final controller = _ServerController(
      scenario: LineupScenario(
        stage: SetupStage.servers,
        servers: const [server],
      ),
    );
    addTearDown(controller.dispose);
    await show(tester, controller);

    // Being first in the list does not promote a server's action.
    expect(find.byType(FilledButton), findsNothing);
    expect(
      tester
          .getSemantics(find.widgetWithText(OutlinedButton, 'Connect'))
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
          .getSemantics(find.widgetWithText(OutlinedButton, 'Connecting…'))
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
          .getSemantics(find.widgetWithText(OutlinedButton, 'Retry'))
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
    final controller = _ServerController(
      scenario: LineupScenario(
        stage: SetupStage.servers,
        servers: const [server],
        profiles: const [
          PlexHomeUser(id: 'one', name: 'One', protected: false),
          PlexHomeUser(id: 'two', name: 'Two', protected: false),
        ],
      ),
    )..failSelection = true;
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
    final controller = _ServerController(
      scenario: LineupScenario(
        stage: SetupStage.servers,
        servers: [current, other],
        server: current,
        connection: PlexConnection(
          uri: Uri.parse('https://current.invalid'),
          local: true,
          relay: false,
        ),
        serverSelectionOrigin: SetupStage.ready,
      ),
    );
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
      56,
    );
    expect(
      tester.getSize(find.widgetWithText(OutlinedButton, 'Connect')).height,
      tester.getSize(find.widgetWithText(FilledButton, 'Continue')).height,
    );
    expect(find.byType(LineupCompactControls), findsNothing);
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
    final controller = _ServerController(
      scenario: LineupScenario(
        stage: SetupStage.servers,
        servers: [current],
        server: current,
        connection: PlexConnection(
          uri: Uri.parse('https://current.invalid'),
          local: true,
          relay: false,
          latency: const Duration(milliseconds: 126),
        ),
      ),
    );
    addTearDown(controller.dispose);
    await show(tester, controller);

    expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump();
    expect(controller.stage, SetupStage.channelSetup);
    expect(controller.selectCalls, 0);
  });

  for (final origin in [
    (
      name: 'ready Account',
      stage: SetupStage.ready,
      restoring: false,
      canCancelSetup: false,
      accountOrigin: true,
    ),
    (
      name: 'first setup Libraries',
      stage: SetupStage.channelSetup,
      restoring: false,
      canCancelSetup: false,
      accountOrigin: false,
    ),
    (
      name: 'regeneration Libraries',
      stage: SetupStage.channelSetup,
      restoring: false,
      canCancelSetup: true,
      accountOrigin: false,
    ),
    (
      name: 'saved-lineup Restore',
      stage: SetupStage.channelSetup,
      restoring: true,
      canCancelSetup: false,
      accountOrigin: false,
    ),
  ]) {
    testWidgets(
      'nested profile picker Back and Escape preserve ${origin.name} origin',
      (tester) async {
        const server = PlexServer(
          id: 'server',
          name: 'Server',
          connections: [],
        );
        const profile = PlexHomeUser(
          id: 'profile',
          name: 'Profile',
          protected: false,
        );
        final controller = _ServerController(
          scenario: LineupScenario(
            stage: origin.stage,
            server: server,
            connection: PlexConnection(
              uri: Uri.parse('https://server.invalid'),
              local: true,
              relay: false,
            ),
            servers: const [server],
            profiles: const [profile],
            restoringSavedLineup: origin.restoring,
            channelSetupCanCancel: origin.canCancelSetup,
          ),
        );
        addTearDown(controller.dispose);

        controller.showServers();
        controller.showProfiles();
        await show(tester, controller, accountOrigin: origin.accountOrigin);
        await tester.pumpAndSettle();

        expect(find.text('Back'), findsAtLeastNWidgets(1));
        expect(find.text('‹ Settings · Account'), findsNothing);
        await tester.tap(find.widgetWithText(TextButton, 'Back').last);
        await tester.pumpAndSettle();
        expect(controller.stage, SetupStage.servers);
        expect(controller.serverSelectionCanCancel, isTrue);
        expect(
          find.text(origin.accountOrigin ? '‹ Settings · Account' : 'Back'),
          findsOneWidget,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(controller.stage, origin.stage);
        expect(controller.serverSelectionCanCancel, isFalse);

        controller
          ..fixtureActor.serverSelected(server)
          ..fixtureActor.present(LineupPresentation(stage: origin.stage))
          ..fixtureActor.present(
            LineupPresentation(restoring: origin.restoring),
          )
          ..fixtureActor.present(
            LineupPresentation(canCancelSetup: origin.canCancelSetup),
          );
        controller.showServers();
        controller.showProfiles();
        await tester.pumpAndSettle();
        expect(find.text('Back'), findsAtLeastNWidgets(1));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(controller.stage, SetupStage.servers);
        expect(controller.serverSelectionCanCancel, isTrue);
        await tester.tap(
          find
              .widgetWithText(
                TextButton,
                origin.accountOrigin ? '‹ Settings · Account' : 'Back',
              )
              .last,
        );
        await tester.pumpAndSettle();
        expect(controller.stage, origin.stage);
        expect(controller.serverSelectionCanCancel, isFalse);
      },
    );
  }

  testWidgets(
    'nested protected PIN returns to Profiles without discarding Servers origin',
    (tester) async {
      const server = PlexServer(id: 'server', name: 'Server', connections: []);
      const profile = PlexHomeUser(
        id: 'profile',
        name: 'Protected profile',
        protected: true,
      );
      final controller = _ServerController(
        scenario: LineupScenario(
          stage: SetupStage.ready,
          server: server,
          connection: PlexConnection(
            uri: Uri.parse('https://server.invalid'),
            local: true,
            relay: false,
          ),
          servers: const [server],
          profiles: const [profile],
        ),
      );
      addTearDown(controller.dispose);

      controller.showServers();
      controller.showProfiles();
      await show(tester, controller, accountOrigin: true);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('profile-card-profile')));
      await tester.pump();
      expect(find.text('‹ Profiles'), findsOneWidget);
      expect(find.text('‹ Settings · Account'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(controller.stage, SetupStage.profiles);
      expect(
        find.byKey(const ValueKey('profile-card-profile')),
        findsOneWidget,
      );
      expect(find.text('Back'), findsOneWidget);

      await tester.tap(find.text('Back'));
      await tester.pump();
      expect(controller.stage, SetupStage.servers);
      expect(controller.serverSelectionCanCancel, isTrue);
      expect(find.text('‹ Settings · Account'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(controller.stage, SetupStage.ready);
      expect(controller.serverSelectionCanCancel, isFalse);
    },
  );

  testWidgets(
    'nested origin remains cancellable when its server is unavailable',
    (tester) async {
      final controller = _ServerController(
        scenario: LineupScenario(
          stage: SetupStage.ready,
          server: const PlexServer(
            id: 'server',
            name: 'Server',
            connections: [],
          ),
          servers: const [
            PlexServer(id: 'server', name: 'Server', connections: []),
          ],
          profiles: const [
            PlexHomeUser(id: 'profile', name: 'Profile', protected: false),
          ],
        ),
      );
      addTearDown(controller.dispose);

      controller.showServers();
      controller.fixtureActor.serverSelected(null);
      controller.showProfiles();
      await show(tester, controller, accountOrigin: true);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Back'));
      await tester.pump();
      expect(controller.stage, SetupStage.servers);
      expect(controller.serverSelectionCanCancel, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(controller.stage, SetupStage.ready);
    },
  );

  testWidgets('initial profile selection remains uncancellable', (
    tester,
  ) async {
    final controller = FixtureController(
      scenario: LineupScenario(
        stage: SetupStage.profiles,
        profiles: const [
          PlexHomeUser(id: 'profile', name: 'Profile', protected: false),
        ],
      ),
    );
    addTearDown(controller.dispose);
    await show(tester, controller);
    await tester.pumpAndSettle();

    expect(find.text('Back'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(controller.stage, SetupStage.profiles);

    expect(controller.profileSelectionCanCancel, isFalse);
  });

  testWidgets(
    'initial server picker Switch profile returns to Servers but Servers stays uncancellable',
    (tester) async {
      final controller = FixtureController(
        scenario: LineupScenario(
          stage: SetupStage.servers,
          server: null,
          serverSelectionOrigin: null,
          profiles: const [
            PlexHomeUser(id: 'one', name: 'One', protected: false),
            PlexHomeUser(id: 'two', name: 'Two', protected: false),
          ],
        ),
      );
      addTearDown(controller.dispose);
      await show(tester, controller);
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(OutlinedButton, 'Switch profile'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Switch profile'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, 'Back'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Back'));
      await tester.pumpAndSettle();
      expect(controller.stage, SetupStage.servers);
      expect(controller.serverSelectionCanCancel, isFalse);
      expect(find.widgetWithText(TextButton, 'Back'), findsNothing);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Switch profile'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(controller.stage, SetupStage.servers);
      expect(controller.serverSelectionCanCancel, isFalse);
      expect(find.widgetWithText(TextButton, 'Back'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(controller.stage, SetupStage.servers);
    },
  );

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
      final controller = _ServerController(
        scenario: LineupScenario(
          stage: SetupStage.servers,
          servers: [current, other],
          server: current,
        ),
      )..promoteSelection = true;
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
      controller.fixtureActor.serverSelected(current);
      expect(controller.continueCurrentServer(), isFalse);

      controller
        ..fixtureActor.present(LineupPresentation(stage: SetupStage.servers))
        ..fixtureActor.present(LineupPresentation(busy: true));
      expect(controller.continueCurrentServer(), isFalse);

      controller
        ..fixtureActor.serverSelected(null)
        ..fixtureActor.present(LineupPresentation(busy: false));
      expect(controller.continueCurrentServer(), isFalse);
    },
  );

  for (final tv in [false, true]) {
    testWidgets('account-origin PIN Back returns to '
        '${tv ? "Profiles on TV" : "Account on desktop"}', (tester) async {
      final controller = _PinController(
        scenario: LineupScenario(
          stage: SetupStage.profiles,
          server: const PlexServer(
            id: 'server',
            name: 'Server',
            connections: [],
          ),
          profileSelectionOrigin: SetupStage.ready,
          profiles: const [
            PlexHomeUser(
              id: 'profile',
              name: 'Protected profile',
              protected: true,
            ),
          ],
        ),
      );
      addTearDown(controller.dispose);
      await show(tester, controller, accountOrigin: true, isTv: tv);
      await tester.tap(find.byKey(const ValueKey('profile-card-profile')));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(
        find.text(tv ? '‹ Profiles' : '‹ Settings · Account'),
        findsOneWidget,
      );
      expect(
        find.text(tv ? '‹ Settings · Account' : '‹ Profiles'),
        findsNothing,
      );
      await tester.sendKeyEvent(
        tv ? LogicalKeyboardKey.goBack : LogicalKeyboardKey.escape,
        physicalKey: PhysicalKeyboardKey.escape,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-pin-sheet')), findsNothing);
      expect(controller.stage, tv ? SetupStage.profiles : SetupStage.ready);
      if (tv) {
        expect(
          find.byKey(const ValueKey('profile-card-profile')),
          findsOneWidget,
        );
      }
    });
  }
}

class _BackLinkPlex extends PlexClient {
  _BackLinkPlex()
    : super(
        clientIdentifier: 'lineup-desktop-link-boundary-client',
        httpClient: testPlexHttpClient(),
      );

  final pin = PlexPin(
    id: 17,
    code: 'BOUNDARY',
    expiresAt: DateTime.now().add(const Duration(minutes: 4)),
  );
  final cancelStarted = Completer<void>();
  Completer<void>? cancelGate;
  bool failCancellation = true;
  int cancelCalls = 0;

  @override
  Future<PlexPin> createPin() async => pin;

  @override
  Future<void> cancelPin(PlexPin value) async {
    cancelCalls++;
    if (!cancelStarted.isCompleted) cancelStarted.complete();
    final gate = cancelGate;
    if (gate != null) await gate.future;
    if (failCancellation) {
      throw const PlexException(
        'server-unreachable',
        'Synthetic cancellation failure.',
      );
    }
  }
}

class _PinController extends FixtureController {
  _PinController({super.scenario});

  final submitted = <String>[];
  bool throwOnSubmit = false;
  Completer<void>? submitGate;

  @override
  Future<bool> selectProfile(PlexHomeUser user, {String? pin}) async {
    submitted.add(pin ?? '');
    if (submitGate != null) await submitGate!.future;
    if (throwOnSubmit) throw StateError('private failure: $pin');
    fixtureActor.present(
      LineupPresentation(error: ('Incorrect PIN. Try again.',)),
    );
    return false;
  }
}

class _ServerController extends FixtureController {
  _ServerController({super.scenario});

  Completer<void>? pendingSelection;
  bool failSelection = false;
  bool promoteSelection = false;
  int selectCalls = 0;

  @override
  Future<void> selectServer(PlexServer server) async {
    selectCalls++;
    if (promoteSelection) {
      fixtureActor.serverSelected(server);
      notifyListeners();
    }
    final pending = pendingSelection;
    if (pending != null) {
      await pending.future;
      pendingSelection = null;
    }
    if (failSelection) {
      fixtureActor.present(
        LineupPresentation(error: ('Server selection failed.',)),
      );
      notifyListeners();
    }
  }

  @override
  Future<void> refreshServers() async {
    fixtureActor.present(
      LineupPresentation(error: ('Fresh discovery failed.',)),
    );
    notifyListeners();
  }
}

class _PinPollingPlex extends PlexClient {
  _PinPollingPlex(this.pin)
    : super(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: testPlexHttpClient(),
      );

  final PlexPin pin;
  int pollCalls = 0;
  int cancelPinCalls = 0;

  @override
  Future<PlexPin> createPin() async => pin;

  @override
  Future<String?> pollPin(PlexPin pin) async {
    pollCalls++;
    throw const PlexException('poll-failed', 'Synthetic poll control failure');
  }

  @override
  Future<void> cancelPin(PlexPin pin) async {
    cancelPinCalls++;
  }
}

class _ProfileRecoveryStore extends MemoryAppStore {
  _ProfileRecoveryStore(this.failure);
  final String failure;
  final gate = Completer<void>();
  bool serverSaveStarted = false;
  bool profileSaveStarted = false;
  bool holdPickerSave = false;
  final pickerSaveStarted = Completer<void>();
  int saveCalls = 0;
  @override
  Future<void> save(PersistedState value) async {
    saveCalls++;
    if (holdPickerSave) {
      holdPickerSave = false;
      pickerSaveStarted.complete();
      await gate.future;
    }
    if (failure == 'profile save') {
      profileSaveStarted = true;
      await gate.future;
    }
    if (failure == 'server save' &&
        value.selectedServerByProfile['protected'] != null &&
        state.profileId == 'protected') {
      serverSaveStarted = true;
      await gate.future;
    }
    if (failure == 'server save success' &&
        value.selectedServerByProfile['protected'] != null &&
        state.profileId == 'protected') {
      serverSaveStarted = true;
      await gate.future;
    }
    await super.save(value);
  }
}

class _PickerBoundaryPlex extends _ProfileRecoveryPlex {
  _PickerBoundaryPlex() : super('none');

  @override
  Future<List<PlexHomeUser>> homeUsers(String token) async => const [
    PlexHomeUser(id: 'owner', name: 'Owner', protected: false),
    PlexHomeUser(id: 'guest', name: 'Guest', protected: false),
  ];

  @override
  Future<PlexLibraryScan> scanLibrary(
    Uri server,
    String token,
    String libraryId,
    PlexLibraryType libraryType, {
    required bool Function() isCurrent,
    required void Function(PlexLibraryPageProgress) onProgress,
    void Function(PlexLibraryScanPhase)? onPhase,
    Future<void>? cancelled,
  }) async => PlexLibraryScan(
    items: [
      PlexMediaItem(
        id: 'movie',
        title: 'Movie',
        type: 'movie',
        libraryId: 'movies',
        duration: const Duration(minutes: 30),
        parts: [PlexMediaPart(path: '/synthetic/movie')],
      ),
    ],
  );
}

class _ProfileRecoveryPlex extends PlexClient {
  _ProfileRecoveryPlex(this.failure)
    : super(
        clientIdentifier: 'synthetic-client',
        httpClient: testPlexHttpClient(),
      );
  final String failure;
  final gate = Completer<void>();
  final scanGate = Completer<PlexLibraryScan>();
  final submittedPins = <String?>[];
  bool gatedRequestStarted = false;
  @override
  Future<PlexAccount> account(String token) async => const PlexAccount(
    id: 'owner',
    name: 'Owner',
    email: 'synthetic@example.invalid',
  );
  @override
  Future<List<PlexHomeUser>> homeUsers(String token) async => const [
    PlexHomeUser(id: 'owner', name: 'Owner', protected: false),
    PlexHomeUser(id: 'protected', name: 'Protected', protected: true),
  ];
  @override
  Future<String> switchHomeUser(String token, String id, String? pin) async {
    submittedPins.add(pin);
    if (failure == 'wrong PIN') {
      throw const PlexException('pin-invalid', 'Incorrect PIN. Try again.');
    }
    return 'synthetic-profile';
  }

  Future<void> _waitAt(String boundary) async {
    if (failure != boundary) return;
    gatedRequestStarted = true;
    await gate.future;
  }

  @override
  Future<List<PlexServerAccess>> discoverServers(String token) async {
    await _waitAt('discovery');
    return [
      PlexServerAccess(
        server: const PlexServer(
          id: 'server',
          name: 'Synthetic server',
          connections: [],
        ),
        token: 'synthetic-pms',
      ),
    ];
  }

  @override
  Future<PlexConnection> selectConnection(
    PlexServer server,
    String token,
  ) async {
    await _waitAt('connection');
    return PlexConnection(
      uri: Uri.parse('https://synthetic.invalid'),
      local: true,
      relay: false,
    );
  }

  @override
  Future<List<PlexLibrary>> libraries(Uri server, String token) async {
    await _waitAt('libraries');
    return const [
      PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
    ];
  }

  @override
  Future<PlexLibraryScan> scanLibrary(
    Uri server,
    String token,
    String libraryId,
    PlexLibraryType libraryType, {
    required bool Function() isCurrent,
    required void Function(PlexLibraryPageProgress progress) onProgress,
    void Function(PlexLibraryScanPhase phase)? onPhase,
    Future<void>? cancelled,
  }) => scanGate.future;
  @override
  Future<PlexPlaylistCatalog> playlists(
    Uri server,
    String token, {
    required bool Function() isCurrent,
    Future<void>? cancelled,
    void Function(PlexPlaylistProgress)? onProgress,
  }) async => const PlexPlaylistCatalog(playlists: [], failedIds: {});
}
