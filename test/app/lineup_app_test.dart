import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_app.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/app/onboarding_view.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/native_video_surface.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

import '../support/ui_fixture.dart';

void main() {
  testWidgets('root Reduce Motion setting disables descendant animations', (
    tester,
  ) async {
    final controller = _FakeController()
      ..settings = const LineupSettings(reduceMotion: true)
      ..stage = SetupStage.ready;
    await tester.pumpWidget(
      LineupBootstrap(player: _FakePlayer(), controller: controller),
    );
    await tester.pumpAndSettle();

    expect(
      MediaQuery.disableAnimationsOf(
        tester.element(find.text('Create a channel to build your Guide')),
      ),
      isTrue,
    );
  });

  testWidgets('empty first-run Channel Setup can return to server selection', (
    tester,
  ) async {
    final controller = _FakeController()..stage = SetupStage.channelSetup;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      LineupBootstrap(player: _FakePlayer(), controller: controller),
    );
    await tester.pumpAndSettle();

    final chooseServer = find.widgetWithText(
      OutlinedButton,
      'Choose another server',
    );
    expect(chooseServer, findsOneWidget);

    await tester.tap(chooseServer);
    expect(controller.stage, SetupStage.servers);
  });

  testWidgets('startup announcement is a labeled live region', (tester) async {
    final controller = _LoadingController();

    await tester.pumpWidget(
      LineupBootstrap(player: _FakePlayer(), controller: controller),
    );
    await tester.pump();

    final semantics = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Starting Lineup Desktop',
      ),
    );
    expect(semantics.properties.liveRegion, isTrue);

    controller.completeInitialization();
    await tester.pumpAndSettle();
  });

  testWidgets('shows honest empty states and supports shell navigation', (
    tester,
  ) async {
    final player = _FakePlayer();
    final controller = _FakeController()..stage = SetupStage.ready;

    await tester.pumpWidget(
      LineupBootstrap(player: player, controller: controller),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create a channel to build your Guide'), findsOneWidget);

    await openDestination(tester, 'Settings');

    expect(find.text('Theme'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(player.disposed, isTrue);
  });

  testWidgets('Guide and player routes transfer and restore focus explicitly', (
    tester,
  ) async {
    final controller = _FakeController()..stage = SetupStage.ready;
    await tester.pumpWidget(
      LineupBootstrap(player: _FakePlayer(), controller: controller),
    );
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Guide');

    await openDestination(tester, 'Player');
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Player');

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Guide');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Player');
  });

  testWidgets('Guide Backspace opens the Lineup menu without playback', (
    tester,
  ) async {
    final controller = _FakeController()..stage = SetupStage.ready;
    await tester.pumpWidget(
      LineupBootstrap(player: _FakePlayer(), controller: controller),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('immersive-app-menu')), findsOneWidget);
  });

  testWidgets('Ctrl destination shortcuts outrank Guide letter shortcuts', (
    tester,
  ) async {
    final controller = _FakeController()..stage = SetupStage.ready;
    await tester.pumpWidget(
      LineupBootstrap(player: _FakePlayer(), controller: controller),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Player');

    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Settings');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Guide');
  });

  testWidgets('F3 opens Settings from Guide and Player routes', (tester) async {
    final controller = _FakeController()..stage = SetupStage.ready;
    await tester.pumpWidget(
      LineupBootstrap(player: _FakePlayer(), controller: controller),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pumpAndSettle();
    expect(find.text('Theme'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Settings');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Player');

    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pumpAndSettle();

    expect(find.text('Theme'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Settings');
  });

  testWidgets('Settings switches profile/server routes and restores focus', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final selectedServer = PlexServer(
      id: 'server',
      name: 'Living Room',
      connections: [
        PlexConnection(
          uri: Uri.parse('https://plex.example:32400'),
          local: true,
          relay: false,
        ),
      ],
      owned: true,
    );
    final controller = _FakeController()
      ..stage = SetupStage.ready
      ..account = const PlexAccount(id: 'owner', name: 'Owner', email: '')
      ..profile = const PlexHomeUser(
        id: 'child',
        name: 'Child',
        protected: true,
      )
      ..profiles = const [
        PlexHomeUser(id: 'owner', name: 'Owner', protected: false),
        PlexHomeUser(id: 'child', name: 'Child', protected: true),
      ]
      ..servers = [selectedServer]
      ..server = selectedServer
      ..connection = PlexConnection(
        uri: Uri.parse('https://plex.example:32400'),
        local: true,
        relay: false,
        latency: const Duration(milliseconds: 18),
      );
    await tester.pumpWidget(
      LineupBootstrap(player: _FakePlayer(), controller: controller),
    );
    await tester.pumpAndSettle();

    await openDestination(tester, 'Settings');
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    expect(find.text('Switch profile'), findsOneWidget);
    expect(find.text('Switch server'), findsOneWidget);
    expect(
      find.textContaining('Direct local • 18 ms measured'),
      findsOneWidget,
    );

    await tester.tap(find.text('Switch server'));
    await tester.pumpAndSettle();
    expect(find.text('Reconnect'), findsOneWidget);
    expect(find.text('Clear saved server'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Settings');
  });

  testWidgets('Guide activation tunes and returns to the full player', (
    tester,
  ) async {
    final controller = _FakeController()
      ..stage = SetupStage.ready
      ..channels = [
        Channel(
          id: 'channel',
          number: 7,
          name: 'Synthetic Seven',
          source: const ManualSource([
            ChannelItem(
              id: 'program',
              title: 'Synthetic Program',
              duration: Duration(hours: 24),
            ),
          ]),
          playbackMode: PlaybackMode.sequential,
          anchor: DateTime.now().subtract(const Duration(hours: 1)),
          shuffleSeed: 7,
        ),
      ];
    final player = _FakePlayer();
    await tester.pumpWidget(
      LineupBootstrap(player: player, controller: controller),
    );
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Guide');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(player.loads, 1);
    expect(find.byKey(const Key('guide-picture-in-picture')), findsNothing);
    expect(find.byType(NativeVideoSurface), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Player');

    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pump();
    expect(find.byKey(const Key('guide-picture-in-picture')), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Guide');
  });

  testWidgets('closing Guide returns to Player instead of management history', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = _FakeController()
      ..stage = SetupStage.ready
      ..channels = [
        Channel(
          id: 'channel',
          number: 7,
          name: 'Synthetic Seven',
          source: const ManualSource([
            ChannelItem(
              id: 'program',
              title: 'Synthetic Program',
              duration: Duration(hours: 24),
            ),
          ]),
          playbackMode: PlaybackMode.sequential,
          anchor: DateTime.now().subtract(const Duration(hours: 1)),
          shuffleSeed: 7,
        ),
      ]
      ..currentChannelId = 'channel';
    final player = _PlayingPlayer();
    await tester.pumpWidget(
      LineupBootstrap(player: player, controller: controller),
    );
    await tester.pumpAndSettle();

    await openDestination(tester, 'Settings');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close Guide'));
    await tester.pumpAndSettle();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Player');
    expect(find.text('Theme'), findsNothing);
  });

  testWidgets('onboarding link action is keyboard reachable', (tester) async {
    final controller = _FakeController();
    await tester.pumpWidget(
      LineupBootstrap(player: _FakePlayer(), controller: controller),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.byType(FilledButton)),
      matchesSemantics(
        label: 'Sign in to Plex',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        isFocused: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(controller.linkingRequested, isTrue);
  });

  for (final key in [LogicalKeyboardKey.space, LogicalKeyboardKey.select]) {
    testWidgets('onboarding link action accepts ${key.keyLabel}', (
      tester,
    ) async {
      final controller = _FakeController();
      await tester.pumpWidget(
        LineupBootstrap(player: _FakePlayer(), controller: controller),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(key);
      await tester.pump();

      expect(controller.linkingRequested, isTrue);
    });
  }

  testWidgets('Plex linking presents QR, PIN cells, and cancellation', (
    tester,
  ) async {
    final controller = _FakeController()
      ..stage = SetupStage.linking
      ..activePin = PlexPin(
        id: 1,
        code: 'ABCD',
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      );
    await tester.pumpWidget(
      LineupBootstrap(player: _FakePlayer(), controller: controller),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('QR code for plex.tv/link'), findsOneWidget);
    expect(find.bySemanticsLabel('Plex link code A B C D'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    expect(controller.linkingCanceled, isTrue);
  });

  testWidgets('linking cancellation failure moves focus to secure retry', (
    tester,
  ) async {
    final controller = _FakeController()
      ..stage = SetupStage.linking
      ..activePin = PlexPin(
        id: 1,
        code: 'ABCD',
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      );
    await tester.pumpWidget(
      LineupBootstrap(player: _FakePlayer(), controller: controller),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final cancel = find.widgetWithText(TextButton, 'Cancel');
    expect(cancel, findsOneWidget);
    expect(
      tester.getSemantics(cancel),
      matchesSemantics(
        label: 'Cancel',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        isFocused: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );

    controller.requireSecureCancellation();
    await tester.pump();
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Retry secure cancellation',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(controller.linkingCanceled, isTrue);
  });

  testWidgets('busy profile selection moves focus to its enabled cancel', (
    tester,
  ) async {
    const child = PlexHomeUser(id: 'child', name: 'Child', protected: false);
    final controller = _FakeController()
      ..stage = SetupStage.profiles
      ..profiles = const [child]
      ..profileSelectionCanCancel = true;
    await tester.pumpWidget(
      LineupBootstrap(player: _FakePlayer(), controller: controller),
    );
    await tester.pumpAndSettle();

    controller.beginCancellableProfileSelection();
    await tester.pump();
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'Cancel profile selection',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(controller.profileSelectionCanceled, isTrue);
  });

  testWidgets('onboarding rebuilds without a listening parent', (tester) async {
    final controller = _FakeController()
      ..stage = SetupStage.linking
      ..activePin = PlexPin(
        id: 1,
        code: 'ABCD',
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: UpstreamOnboardingView(
          controller: controller,
          onLogout: () async {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Retry secure cancellation'), findsNothing);

    controller.requireSecureCancellation();
    await tester.pump();

    expect(find.text('Retry secure cancellation'), findsOneWidget);
  });

  testWidgets('onboarding reflects state-only controller notifications', (
    tester,
  ) async {
    const profile = PlexHomeUser(id: 'child', name: 'Child', protected: false);
    const server = PlexServer(
      id: 'server',
      name: 'Living Room',
      connections: [],
      owned: true,
    );
    final controller = _FakeController()
      ..stage = SetupStage.profiles
      ..profiles = const [profile];
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: UpstreamOnboardingView(
          controller: controller,
          onLogout: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Child'), findsOneWidget);

    controller
      ..servers = [server]
      ..stage = SetupStage.servers;
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Living Room'), findsOneWidget);

    controller.error = 'Server discovery needs attention.';
    controller.notifyListeners();
    await tester.pump();
    expect(find.text('Server discovery needs attention.'), findsOneWidget);

    controller
      ..stage = SetupStage.linking
      ..activePin = PlexPin(
        id: 1,
        code: 'ABCD',
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      );
    controller.notifyListeners();
    await tester.pumpAndSettle();
    controller.activePin = PlexPin(
      id: 2,
      code: 'WXYZ',
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    );
    controller.notifyListeners();
    await tester.pump();
    expect(find.bySemanticsLabel('Plex link code W X Y Z'), findsOneWidget);
  });

  testWidgets('protected profile PIN submits after four remote digits', (
    tester,
  ) async {
    const child = PlexHomeUser(id: 'child', name: 'Child', protected: true);
    final controller = _FakeController()
      ..stage = SetupStage.profiles
      ..profiles = const [child];
    await tester.pumpWidget(
      LineupBootstrap(player: _FakePlayer(), controller: controller),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Child'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('0 of 4 digits entered'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '1'));
    await tester.pump();
    expect(find.bySemanticsLabel('1 of 4 digits entered'), findsOneWidget);
    for (final digit in ['2', '3', '4']) {
      await tester.tap(find.widgetWithText(FilledButton, digit));
      await tester.pump();
    }
    expect(controller.selectedProfile, child);
    expect(controller.selectedPin, '1234');
  });

  testWidgets('presents initialization failures without entering the shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      LineupBootstrap(player: _FailingPlayer(), controller: _FakeController()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lineup Desktop could not start'), findsOneWidget);
    final failureSemantics = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Lineup Desktop could not start',
      ),
    );
    expect(failureSemantics.properties.liveRegion, isTrue);
    expect(
      find.ancestor(
        of: find.text('Lineup Desktop could not start'),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Restart the app'), findsOneWidget);
    expect(find.textContaining(_nativeInitializeFailureMessage), findsNothing);
    expect(find.text('Guide'), findsNothing);
  });

  testWidgets('real corrupt state reaches the live dismissible banner', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'lineup-bootstrap-test',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    File('${directory.path}/state.json').writeAsStringSync('{broken');
    final store = _PreparedFileAppStore(
      directory,
      clock: () => DateTime.utc(2026, 8, 23),
    );
    await tester.runAsync(store.prepare);
    final controller = LineupController(
      store: store,
      credentials: _MemoryCredentials(),
      plex: PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      ),
    );
    await tester.pumpWidget(
      LineupBootstrap(player: _FakePlayer(), controller: controller),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MaterialBanner), findsOneWidget);
    final semantics = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == controller.startupRecoveryNotice,
      ),
    );
    expect(semantics.properties.liveRegion, isTrue);
    expect(controller.startupRecoveryNotice, isNot(contains('/')));
    final theme = controller.settings.theme;

    await tester.tap(find.widgetWithText(TextButton, 'Dismiss'));
    await tester.pump();

    expect(find.byType(MaterialBanner), findsNothing);
    expect(controller.startupRecoveryNotice, isNull);
    expect(controller.settings.theme, theme);
  });

  testWidgets('quarantine collision makes startup fail visibly', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'lineup-bootstrap-test',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final stateFile = File('${directory.path}/state.json');
    stateFile.writeAsStringSync('{broken');
    final instant = DateTime.utc(2026, 8, 23);
    final quarantine = Directory(
      '${stateFile.path}.corrupt-${instant.millisecondsSinceEpoch}',
    );
    quarantine.createSync();
    final store = _PreparedFileAppStore(directory, clock: () => instant);
    await tester.runAsync(store.prepare);
    final controller = LineupController(
      store: store,
      credentials: _MemoryCredentials(),
      plex: PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      ),
    );
    await tester.pumpWidget(
      LineupBootstrap(player: _FakePlayer(), controller: controller),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lineup Desktop could not start'), findsOneWidget);
    expect(find.textContaining(directory.path), findsNothing);
    expect(stateFile.readAsStringSync(), '{broken');
    expect(quarantine.existsSync(), isTrue);
  });

  testWidgets('state directory read failure makes startup fail visibly', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'lineup-bootstrap-test',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final stateDirectory = Directory('${directory.path}/state.json');
    stateDirectory.createSync();
    final store = _PreparedFileAppStore(directory);
    await tester.runAsync(store.prepare);
    final controller = LineupController(
      store: store,
      credentials: _MemoryCredentials(),
      plex: PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      ),
    );
    await tester.pumpWidget(
      LineupBootstrap(player: _FakePlayer(), controller: controller),
    );
    await tester.pump();

    expect(find.text('Lineup Desktop could not start'), findsOneWidget);
    expect(find.textContaining(directory.path), findsNothing);
    expect(stateDirectory.existsSync(), isTrue);
    expect(
      directory.listSync().where(
        (entry) => entry.path.contains('state.json.corrupt-'),
      ),
      isEmpty,
    );
  });

  testWidgets('makes a missing required Windows engine explicit', (
    tester,
  ) async {
    await tester.pumpWidget(
      LineupBootstrap(
        player: _RequiredEngineFailingPlayer(),
        controller: _FakeController(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'The required Lineup DirectComposition Flutter engine is not active.',
      ),
      findsOneWidget,
    );
    expect(find.text(_requiredEngineNativeFailureMessage), findsNothing);
  });
}

class _FakeController extends LineupController {
  _FakeController()
    : super(
        store: _MemoryStore(),
        credentials: _MemoryCredentials(),
        plex: PlexClient(
          clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        ),
      );

  bool linkingRequested = false;
  bool linkingCanceled = false;
  bool profileSelectionCanceled = false;
  PlexHomeUser? selectedProfile;
  String? selectedPin;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> startLinking() async {
    linkingRequested = true;
  }

  @override
  Future<bool> cancelLinking() async {
    linkingCanceled = true;
    return true;
  }

  void requireSecureCancellation() {
    secureCancellationRequired = true;
    notifyListeners();
  }

  void beginCancellableProfileSelection() {
    busy = true;
    notifyListeners();
  }

  @override
  void cancelProfileSelection() {
    profileSelectionCanceled = true;
  }

  @override
  Future<void> selectProfile(PlexHomeUser selected, {String? pin}) async {
    selectedProfile = selected;
    selectedPin = pin;
  }

  @override
  LineupPlaybackRequest playbackFor(String itemId) =>
      LineupPlaybackRequest.parts([
        LineupPlaybackPart(uri: Uri.parse('lineup-test://synthetic')),
      ], () async {});

  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) async => buildSchedule(
    (channel.source as ManualSource).items,
    mode: channel.playbackMode,
    seed: channel.shuffleSeed,
  );
}

class _LoadingController extends _FakeController {
  final _initialization = Completer<void>();

  @override
  Future<void> initialize() => _initialization.future;

  void completeInitialization() => _initialization.complete();
}

class _PreparedFileAppStore extends FileAppStore {
  _PreparedFileAppStore(super.directory, {super.clock});

  AppStoreLoadResult? _result;
  Object? _error;

  Future<void> prepare() async {
    try {
      _result = await super.load();
    } catch (error) {
      _error = error;
    }
  }

  @override
  Future<AppStoreLoadResult> load() async {
    if (_error case final error?) throw error;
    return _result!;
  }
}

class _MemoryStore implements AppStore {
  @override
  Future<String> clientIdentifier() async =>
      'lineup-desktop-test-abcdefghijklmnopqrst';
  @override
  Future<AppStoreLoadResult> load() async =>
      const AppStoreLoadResult(PersistedState());

  @override
  Future<void> save(PersistedState state) async {}
}

class _MemoryCredentials implements CredentialStore {
  @override
  Future<void> clear() async {}
  @override
  Future<String?> readAccountToken() async => null;
  @override
  Future<String?> readProfileToken(String profileId) async => null;
  @override
  Future<void> writeAccountToken(String token) async {}
  @override
  Future<void> writeProfileToken(String profileId, String token) async {}
}

class _FakePlayer implements NativePlayer {
  bool disposed = false;
  int loads = 0;

  @override
  PlayerStatus get status => const PlayerStatus(
    state: PlayerState.idle,
    message: 'Playback test backend ready',
  );

  @override
  Duration get position => Duration.zero;

  @override
  Duration get duration => Duration.zero;

  @override
  PlayerTelemetry get telemetry => const PlayerTelemetry();

  @override
  List<PlayerTrack> get tracks => const [];

  @override
  Stream<PlayerEvent> get events => const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> load(Uri media, {String? plexToken, int? generation}) async {
    loads++;
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVideoRect(PlayerVideoRect rect) async {}

  @override
  Future<void> setFullscreen(bool fullscreen) async {}

  @override
  Future<void> selectTrack(PlayerTrackType type, int? id) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _PlayingPlayer extends _FakePlayer {
  @override
  PlayerStatus get status =>
      const PlayerStatus(state: PlayerState.playing, message: 'Playing');
}

const _nativeInitializeFailureMessage = 'libmpv could not create a client.';
const _requiredEngineNativeFailureMessage =
    'native wording is not part of the application contract';

class _FailingPlayer extends _FakePlayer {
  @override
  Future<void> initialize() async {
    throw PlatformException(
      code: 'initialize_failed',
      message: _nativeInitializeFailureMessage,
    );
  }
}

class _RequiredEngineFailingPlayer extends _FakePlayer {
  @override
  Future<void> initialize() async {
    throw PlatformException(
      code: 'required_engine_unavailable',
      message: _requiredEngineNativeFailureMessage,
    );
  }
}
