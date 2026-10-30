import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/app/lineup_shell.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/playback/player_coordinator.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/player_view.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

import '../support/ui_fixture.dart';

const _handheld = DeviceProfile(
  host: TargetPlatform.android,
  formFactor: FormFactor.handheld,
);
final _now = DateTime.utc(2026, 1, 15, 3, 17);

void main() {
  const platform = MethodChannel('lineup/platform');
  var backgrounded = 0;
  late FocusNode elsewhere;
  setUp(() {
    backgrounded = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, (call) async {
          if (call.method == 'moveTaskToBack') backgrounded++;
          return true;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform, null),
  );

  void handheldTest(String name, WidgetTesterCallback body) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      elsewhere = FocusNode(debugLabel: 'Stranded touch focus');
      addTearDown(elsewhere.dispose);
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1280, 800);
      addTearDown(tester.view.reset);
      try {
        await body(tester);
      } finally {
        elsewhere.unfocus();
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  Future<void> navigate(WidgetTester tester, String name) async {
    if (find.byType(PlayerView).evaluate().isNotEmpty) {
      final key = switch (name) {
        'Channels' => LogicalKeyboardKey.digit2,
        'Settings' => LogicalKeyboardKey.digit3,
        _ => throw StateError('Unhandled test navigation: $name'),
      };
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      return;
    }
    await openDestination(tester, name);
  }

  Future<void> focusElsewhere(WidgetTester tester) async {
    elsewhere.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(elsewhere));
  }

  Future<void> showFixture(WidgetTester tester, UiFixture fixture) =>
      tester.pumpWidget(Focus(focusNode: elsewhere, child: fixture.build()));

  handheldTest(
    'root OS Back backgrounds, while PIN returns to Profiles without signing out',
    (tester) async {
      final welcome = UiFixture(
        profile: _handheld,
        scenario: const LineupScenario(stage: SetupStage.welcome),
      );
      await showFixture(tester, welcome);
      await tester.pumpAndSettle();
      await focusElsewhere(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(backgrounded, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      final pin = UiFixture(
        profile: _handheld,
        scenario: const LineupScenario(
          stage: SetupStage.profiles,
          account: PlexAccount(
            id: 'fixture',
            name: 'Viewer',
            email: 'viewer@example.invalid',
          ),
          profiles: [
            PlexHomeUser(id: 'protected', name: 'Viewer', protected: true),
          ],
        ),
      );
      await showFixture(tester, pin);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-card-protected')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-pin-sheet')), findsOneWidget);
      await focusElsewhere(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-pin-sheet')), findsNothing);
      expect(pin.controller.stage, SetupStage.profiles);
      expect(pin.controller.account?.id, 'fixture');
      expect(backgrounded, 1);
    },
  );

  handheldTest(
    'idle Setup libraries root backgrounds without leaving Setup or signing out',
    (tester) async {
      final fixture = UiFixture(
        profile: _handheld,
        scenario: const LineupScenario(
          stage: SetupStage.channelSetup,
          settings: LineupSettings(reduceMotion: true),
          account: PlexAccount(
            id: 'setup-account',
            name: 'Viewer',
            email: 'viewer@example.invalid',
          ),
        ),
      );
      await showFixture(tester, fixture);
      await tester.pumpAndSettle();
      expect(fixture.controller.canSwitchServer, isTrue);
      expect(fixture.controller.channelSetupCanCancel, isFalse);
      await focusElsewhere(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(backgrounded, 1);
      expect(fixture.controller.stage, SetupStage.channelSetup);
      expect(fixture.controller.account?.id, 'setup-account');
    },
  );

  handheldTest('linking OS Back runs Cancel with unrelated focus', (
    tester,
  ) async {
    final fixture = UiFixture(
      profile: _handheld,
      scenario: LineupScenario(stage: SetupStage.linking),
    );
    await showFixture(tester, fixture);
    await tester.pumpAndSettle();
    await focusElsewhere(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(fixture.controller.stage, SetupStage.welcome);
    expect(backgrounded, 0);
  });

  handheldTest(
    'menu and dialog close before a destination regardless of focus',
    (tester) async {
      final fixture = _ready();
      await showFixture(tester, fixture);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Open Lineup menu'));
      await tester.pumpAndSettle();
      await focusElsewhere(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('immersive-app-menu')), findsNothing);
      expect(backgrounded, 0);
      final context = tester.element(find.byType(LineupShell));
      final dialog = showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('Pending confirmation')),
      );
      await tester.pumpAndSettle();
      await focusElsewhere(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await dialog;
      expect(find.text('Pending confirmation'), findsNothing);
      expect(backgrounded, 0);
    },
  );

  handheldTest(
    'Channels header and OS Back share the retained Player origin without tuning',
    (tester) async {
      final fixture = _ready();
      await showFixture(tester, fixture);
      await tester.pumpAndSettle();
      await navigate(tester, 'Player');
      await navigate(tester, 'Channels');
      expect(find.text('‹ Back to Player'), findsOneWidget);
      await focusElsewhere(tester);
      final loads = fixture.player.loads.length;
      final selected = fixture.controller.currentChannelId;
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PlayerView), findsOneWidget);
      expect(fixture.player.loads.length, loads);
      expect(fixture.controller.currentChannelId, selected);
      await navigate(tester, 'Channels');
      await tester.tap(find.text('‹ Back to Player'));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerView), findsOneWidget);
      expect(backgrounded, 0);
    },
  );

  handheldTest(
    'Player picker then Mini Guide and Now Playing resolve before Player to Guide',
    (tester) async {
      final fixture = _ready();
      await showFixture(tester, fixture);
      await tester.pumpAndSettle();
      await navigate(tester, 'Player');
      final controller = tester
          .widget<PlayerView>(find.byType(PlayerView))
          .controller;
      controller.showOsd();
      controller.showSleepTimer();
      await tester.pumpAndSettle();
      await focusElsewhere(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(controller.sleepPickerOpen, isFalse);
      expect(controller.overlay, PlayerOverlay.osd);
      controller.showTracks(PlayerTrackType.subtitle);
      await tester.pumpAndSettle();
      await focusElsewhere(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(controller.overlay, PlayerOverlay.osd);
      controller.showMiniGuide();
      await tester.pumpAndSettle();
      await focusElsewhere(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(controller.overlay, PlayerOverlay.osd);
      final tuning = controller.tune('channel');
      await tester.pump();
      await tester.pump();
      expect(await tuning, isTrue, reason: controller.error);
      fixture.player.emit(
        const PlayerStatus(state: PlayerState.playing, message: 'Playing'),
      );
      await tester.pumpAndSettle();
      controller.showNowPlaying();
      await tester.pumpAndSettle();
      expect(controller.overlay, PlayerOverlay.nowPlaying);
      await focusElsewhere(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(controller.overlay, PlayerOverlay.osd);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PlayerView), findsNothing);
      expect(backgrounded, 0);
    },
  );

  handheldTest(
    'Settings dropdown and destination Back preserve the visible origin',
    (tester) async {
      final fixture = _ready();
      await showFixture(tester, fixture);
      await tester.pumpAndSettle();
      await navigate(tester, 'Settings');
      await tester.tap(
        find.byKey(const ValueKey('settings-field-Player overlays')),
      );
      await tester.pumpAndSettle();
      await focusElsewhere(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('‹ Back to Guide'), findsOneWidget);
      expect(backgrounded, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guide-channel-search')), findsOneWidget);
      expect(backgrounded, 0);
    },
  );

  handheldTest('Diagnostics OS Back returns to its visible Settings target', (
    tester,
  ) async {
    final fixture = _ready();
    await showFixture(tester, fixture);
    await tester.pumpAndSettle();
    await navigate(tester, 'Settings');
    await tester.tap(find.text('Support').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Open Diagnostics'));
    await tester.tap(find.text('Open Diagnostics'));
    await tester.pumpAndSettle();
    await focusElsewhere(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Open Diagnostics'), findsOneWidget);
    expect(backgrounded, 0);
  });

  handheldTest(
    'resize across composition classes preserves destination, selection and playback owner',
    (tester) async {
      final fixture = _ready();
      await showFixture(tester, fixture);
      await tester.pumpAndSettle();
      await navigate(tester, 'Player');
      final original = tester.state<PlayerViewState>(find.byType(PlayerView));
      final loads = fixture.player.loads.length;
      final selected = fixture.controller.currentChannelId;
      for (final window in [
        const Size(960, 600),
        const Size(800, 1280),
        const Size(1280, 800),
      ]) {
        tester.view.physicalSize = window;
        await tester.pumpAndSettle();
        expect(
          tester.state<PlayerViewState>(find.byType(PlayerView)),
          same(original),
        );
        expect(fixture.controller.currentChannelId, selected);
        expect(fixture.player.loads.length, loads);
        expect(fixture.player.stops, 0);
      }
    },
  );

  handheldTest(
    'inactive preserves media and hidden stops through handheld shell policy',
    (tester) async {
      final fixture = _ready();
      await showFixture(tester, fixture);
      await tester.pumpAndSettle();
      final loads = fixture.player.loads.length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(fixture.player.stops, 0);
      expect(fixture.player.loads.length, loads);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      expect(fixture.player.stops, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    },
  );
}

UiFixture _ready() => UiFixture(
  profile: _handheld,
  player: FixturePlayer.preloaded()
    ..emit(const PlayerStatus(state: PlayerState.ready, message: 'Ready')),
  guideClock: () => _now,
  controller: _BackController(
    scenario: LineupScenario(
      stage: SetupStage.ready,
      settings: const LineupSettings(reduceMotion: true),
      currentChannelId: 'channel',
      channels: [
        Channel(
          id: 'channel',
          number: 7,
          name: 'Channel',
          source: const ManualSource([
            ChannelItem(
              id: 'program',
              title: 'Program',
              duration: Duration(hours: 24),
            ),
          ]),
          playbackMode: PlaybackMode.sequential,
          anchor: _now.subtract(const Duration(hours: 1)),
          shuffleSeed: 1,
        ),
      ],
    ),
  ),
);

class _BackController extends FixtureController {
  _BackController({required super.scenario});
  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) async => buildSchedule(
    (channel.source as ManualSource).items,
    mode: channel.playbackMode,
    seed: channel.shuffleSeed,
  );

  @override
  LineupPlaybackRequest playbackFor(String itemId) =>
      LineupPlaybackRequest.parts([
        LineupPlaybackPart(
          uri: Uri.parse('https://synthetic.invalid/$itemId.mkv'),
          duration: const Duration(hours: 24),
        ),
      ]);
}
