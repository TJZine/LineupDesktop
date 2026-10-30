import 'package:flutter/material.dart';
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
  }) : this._(store ?? MemoryAppStore(), restoreOnInitialize, scenario);

  FixtureController._(
    MemoryAppStore store,
    this.restoreOnInitialize,
    LineupScenario? scenario,
  ) : fixtureStore = store,
      super(
        store: store,
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
  await tester.tap(find.byTooltip('Open Lineup menu'));
  await tester.pump(const Duration(milliseconds: 250));
  await tester.tap(find.text(destination).last);
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
