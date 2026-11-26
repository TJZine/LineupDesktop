import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_app.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/playback/native_player.dart';

import 'test_doubles.dart';
import 'device_profile_test_support.dart';
export 'test_doubles.dart';
export 'device_profile_test_support.dart';

/// A schedule for tests that need the populated Guide controls.
Channel syntheticGuideChannel() => Channel(
  id: 'synthetic-guide',
  number: 7,
  name: 'Synthetic channel',
  source: const ManualSource([
    ChannelItem(
      id: 'synthetic-program',
      title: 'Synthetic program',
      duration: Duration(hours: 3),
    ),
  ]),
  playbackMode: PlaybackMode.sequential,
  anchor: DateTime.utc(2026, 1, 15),
  shuffleSeed: 1,
);

/// Deterministic UI states for widget tests. This file is not imported by the
/// production composition root.
class UiFixture {
  UiFixture({
    FixtureController? controller,
    LineupScenario? scenario,
    FixturePlayer? player,
    this.guideClock,
    this.profile = desktopProfile,
  }) : assert(controller == null || scenario == null),
       controller = controller ?? FixtureController(scenario: scenario),
       player = player ?? FixturePlayer();

  final FixtureController controller;
  final FixturePlayer player;
  final DateTime Function()? guideClock;
  final DeviceProfile? profile;

  Widget build() => LineupBootstrap(
    player: player,
    controller: controller,
    guideClock: guideClock,
    profile: profile,
  );
}

class FixtureController extends LineupController {
  FixtureController({
    MemoryAppStore? store,
    bool restoreOnInitialize = false,
    LineupScenario? scenario,
    DateTime Function()? clock,
    DateTime Function()? scheduleClock,
  }) : this._(
         store ?? MemoryAppStore(),
         restoreOnInitialize,
         scenario,
         clock,
         scheduleClock,
       );

  FixtureController._(
    MemoryAppStore store,
    this.restoreOnInitialize,
    LineupScenario? scenario,
    DateTime Function()? clock,
    DateTime Function()? scheduleClock,
  ) : fixtureStore = store,
      super(
        store: store,
        clock: clock,
        scheduleClock: scheduleClock,
        credentials: MemoryCredentialStore(),
        plex: _FixturePlex(
          clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
          httpClient: testPlexHttpClient(),
        ),
      ) {
    installScenario(
      (scenario ?? const LineupScenario()).withDefaults(
        LineupScenario(
          connection: PlexConnection(
            uri: Uri.parse('https://synthetic.invalid'),
            local: true,
            relay: false,
          ),
        ),
      ),
    );
  }

  final MemoryAppStore fixtureStore;
  final bool restoreOnInitialize;

  @override
  Future<void> initialize() =>
      restoreOnInitialize ? super.initialize() : Future.value();
}

class _FixturePlex extends PlexClient {
  _FixturePlex({required super.clientIdentifier, required super.httpClient});

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
  }) async => const PlexLibraryScan(items: []);
}

Future<void> openDestination(WidgetTester tester, String destination) async {
  if (destination == 'Player') {
    // Some playback fixtures intentionally have no scheduled channel. The
    // shortcut works for those; the menu only lists a tuned channel.
    final modifier = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.sendKeyUpEvent(modifier);
  } else {
    await tester.tap(find.byTooltip('Open Lineup menu'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(
      find
          .text(destination == 'Channels' ? 'Manage channels' : destination)
          .last,
    );
  }
  await tester.pumpAndSettle();
}

class FixturePlayer extends FakeNativePlayer {
  FixturePlayer()
    : super(
        initialStatus: const PlayerStatus(
          state: PlayerState.idle,
          message: 'Test player is idle',
        ),
        emitLoadingOnLoad: true,
      );

  FixturePlayer.preloaded()
    : super(
        initialStatus: const PlayerStatus(
          state: PlayerState.idle,
          message: 'Test player is idle',
        ),
        emitLoadingOnLoad: true,
        initialGeneration: null,
      );
}
