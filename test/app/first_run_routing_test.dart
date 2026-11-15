import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lineup_desktop/app/channel_setup/library_step.dart';
import 'package:lineup_desktop/app/channel_setup_view.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/app/lineup_shell.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';

import '../support/ui_fixture.dart';

const _owner = PlexHomeUser(id: 'owner', name: 'Owner', protected: false);
const _viewer = PlexHomeUser(id: 'viewer', name: 'Viewer', protected: true);
const _accountToken = 'synthetic-account';
const _profileToken = 'synthetic-viewer';

PlexLibraryScan _playableScan() => PlexLibraryScan(
  items: [
    PlexMediaItem(
      id: 'movie',
      title: 'Synthetic movie',
      type: 'movie',
      libraryId: 'movies',
      duration: const Duration(minutes: 30),
      parts: [PlexMediaPart(path: '/synthetic/movie')],
    ),
  ],
);

void main() {
  test(
    'signed-in startup keeps the picker hidden through the single probe',
    () async {
      final probe = Completer<int>();
      final fixture = _RoutingFixture()
        ..plex.probeResponses['media'] = probe.future;
      final stages = <SetupStage>[];
      fixture.controller.addListener(
        () => stages.add(fixture.controller.stage),
      );
      final startup = fixture.controller.initialize();
      await fixture.plex.firstProbe.future;
      expect(fixture.controller.busy, isTrue);
      expect(fixture.controller.server, isNull);
      expect(stages, isNot(contains(SetupStage.servers)));
      probe.complete(200);
      await startup;

      expect(stages, isNot(contains(SetupStage.servers)));
      expect(fixture.controller.stage, SetupStage.channelSetup);
      expect(fixture.controller.firstLibrariesOrigin, isNull);
      expect(fixture.controller.connection?.latency, isNotNull);
      expect(fixture.plex.probes, [('media', 'synthetic-owner-pms')]);
      expect(fixture.store.state.selectedServerByProfile, {'owner': 'media'});
    },
  );

  for (final reconnect in [false, true]) {
    test(
      'startup probe exhaustion records the exact row (saved=$reconnect)',
      () async {
        final fixture = _RoutingFixture(
          state: reconnect
              ? const PersistedState(
                  selectedServerByProfile: {'owner': 'media'},
                )
              : null,
        )..plex.probeResponses['media'] = Future.value(503);
        await fixture.controller.initialize();

        expect(fixture.controller.stage, SetupStage.servers);
        expect(fixture.controller.serverProbeFailure?.serverId, 'media');
        expect(fixture.controller.server, isNull);
        expect(fixture.plex.probes, [('media', 'synthetic-owner-pms')]);
        await fixture.controller.refreshServers();
        expect(fixture.controller.serverProbeFailure, isNull);
        expect(fixture.plex.probes, hasLength(1));
      },
    );
  }

  test(
    'saved profile reconnect selects its scoped server from several',
    () async {
      final fixture = _RoutingFixture(
        profiles: [_owner, _viewer],
        servers: ['media', 'archive'],
        state: const PersistedState(
          selectedServerByProfile: {'viewer': 'archive'},
        ),
      )..plex.probeResponses['archive'] = Future.value(503);
      await fixture.controller.initialize();
      expect(fixture.controller.stage, SetupStage.profiles);
      expect(fixture.plex.probes, isEmpty);

      expect(
        await fixture.controller.selectProfile(_viewer, pin: '1234'),
        isTrue,
      );
      expect(fixture.controller.stage, SetupStage.servers);
      expect(fixture.controller.serverProbeFailure?.serverId, 'archive');
      expect(fixture.plex.probes, [('archive', 'synthetic-viewer-pms')]);

      fixture.plex.probeResponses['archive'] = Future.value(200);
      await fixture.controller.selectServer(fixture.controller.servers.last);
      expect(fixture.controller.server?.id, 'archive');
      expect(fixture.controller.stage, SetupStage.channelSetup);
      expect(fixture.controller.serverProbeFailure, isNull);
    },
  );

  test(
    'new explicit selection retires the failure even if authorization fails',
    () async {
      final fixture = _RoutingFixture(servers: ['media', 'archive'])
        ..plex.probeResponses.addAll({
          'media': Future.value(503),
          'archive': Future.value(403),
        });
      final controller = fixture.controller;
      await controller.initialize();
      expect(controller.stage, SetupStage.servers);
      expect(fixture.plex.probes, isEmpty);

      await controller.selectServer(controller.servers.first);
      expect(controller.serverProbeFailure?.serverId, 'media');
      await controller.selectServer(controller.servers.last);
      expect(controller.serverProbeFailure, isNull);
      expect(controller.error, 'This Plex profile cannot access that server.');
      expect(fixture.plex.probes.map((entry) => entry.$1), [
        'media',
        'archive',
        'archive',
      ]);
    },
  );

  test('chosen route exhaustion during library authorization recovery has no row status', () async {
    final fixture = _RoutingFixture(servers: ['media', 'archive']);
    fixture.plex.libraryAuthorizationDenied = true;
    final controller = fixture.controller;
    await controller.initialize();
    await controller.selectServer(controller.servers.first);

    expect(fixture.plex.probes.map((entry) => entry.$1), ['media', 'media']);
    expect(controller.stage, SetupStage.servers);
    expect(controller.error, isNotNull);
    expect(controller.serverProbeFailure, isNull);
  });

  test(
    'a superseded probe cannot change the successful new selection',
    () async {
      final stale = Completer<int>();
      final fixture = _RoutingFixture(servers: ['media', 'archive'])
        ..plex.probeResponses['media'] = stale.future;
      final controller = fixture.controller;
      await controller.initialize();
      final attempt = controller.selectServer(controller.servers.first);
      await fixture.plex.firstProbe.future;

      await controller.refreshServers();
      await controller.selectServer(controller.servers.last);
      stale.complete(503);
      await attempt;
      await Future<void>.delayed(Duration.zero);

      expect(controller.stage, SetupStage.channelSetup);
      expect(controller.server?.id, 'archive');
      expect(controller.serverProbeFailure, isNull);
      expect(controller.error, isNull);
      expect(fixture.store.state.selectedServerByProfile, {'owner': 'archive'});
    },
  );

  test(
    'authorization scope retirement drops a previously published probe failure',
    () async {
      final fixture = _RoutingFixture()
        ..plex.probeResponses['media'] = Future.value(503);
      final controller = fixture.controller;
      await controller.initialize();
      expect(controller.serverProbeFailure?.serverId, 'media');
      controller.cancelPlaybackAuthorization();
      expect(controller.serverProbeFailure, isNull);
      expect(controller.error, isNull);
    },
  );

  testWidgets('Account switching waits for an explicit picker selection', (
    tester,
  ) async {
    final fixture = _RoutingFixture(servers: ['media', 'archive']);
    final controller = fixture.controller;
    await controller.initialize();
    await controller.selectServer(controller.servers.first);
    controller.fixtureActor.present(
      LineupPresentation(stage: SetupStage.ready),
    );

    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _show(tester, fixture, tv: false);
    await openDestination(tester, 'Settings');
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Switch server'));
    await tester.tap(find.text('Switch server'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a server'), findsOneWidget);
    expect(fixture.plex.probes, [('media', 'synthetic-owner-pms')]);

    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(fixture.plex.probes.last, ('archive', 'synthetic-owner-pms'));
    expect(fixture.store.state.selectedServerByProfile, {'owner': 'archive'});
    expect(find.text('Choose libraries'), findsOneWidget);
    expect(controller.firstLibrariesOrigin, isNull);
  });

  test(
    'nested setup reentry keeps a new profile’s sole server explicit',
    () async {
      final fixture = _RoutingFixture(profiles: [_owner, _viewer]);
      final controller = fixture.controller;
      await controller.initialize();
      await controller.selectProfile(_owner);
      expect(controller.firstLibrariesOrigin, FirstLibrariesOrigin.profiles);
      fixture.plex.scanResult = _playableScan();
      expect(await controller.scanLibraries({'movies'}), isTrue);
      expect(await controller.commitLibraryScan({'movies'}), isTrue);
      controller.completeChannelSetup();
      await controller.enterChannelSetup();

      controller.showServers();
      controller.showProfiles();
      expect(await controller.selectProfile(_viewer, pin: '1234'), isTrue);
      expect(controller.stage, SetupStage.servers);
      expect(fixture.plex.probes, [('media', 'synthetic-owner-pms')]);
      await controller.selectServer(controller.servers.single);
      expect(controller.firstLibrariesOrigin, isNull);
    },
  );

  testWidgets('TV Back cancels a scan and returns from Channels to Libraries', (
    tester,
  ) async {
    final fixture = _RoutingFixture(signedIn: false);
    final controller = fixture.controller;
    final scan = fixture.plex.scanGate = Completer<PlexLibraryScan>();
    await _show(tester, fixture, tv: true);
    await tester.tap(find.text('Sign in to Plex'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    final scanAction = find.byKey(const ValueKey('scan-selected-libraries'));
    await tester.tap(scanAction);
    await tester.pump();
    expect(controller.libraryScanStatus, LibraryScanStatus.scanning);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(controller.libraryScanStatus, LibraryScanStatus.cancelled);
    expect(controller.firstLibrariesOrigin, FirstLibrariesOrigin.signIn);
    expect(find.text('Choose libraries'), findsOneWidget);

    scan.complete(_playableScan());
    fixture.plex.scanGate = null;
    await tester.pumpAndSettle();
    fixture.plex.scanResult = await scan.future;
    await tester.tap(scanAction);
    await tester.pumpAndSettle();
    expect(find.text('Choose channels'), findsOneWidget);
    expect(controller.firstLibrariesOrigin, isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('library-selection-list')),
      findsOneWidget,
    );
    expect(controller.stage, SetupStage.channelSetup);
    expect(fixture.credentials.accountToken, _accountToken);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));

  for (final tv in [false, true]) {
    testWidgets(
      'first Libraries Back returns to the protected profile grid (TV=$tv)',
      (tester) async {
        final gate = Completer<int>();
        final fixture = _RoutingFixture(profiles: [_owner, _viewer])
          ..plex.probeResponses['media'] = gate.future;
        await fixture.controller.initialize();
        await _show(tester, fixture, tv: tv);
        await tester.tap(find.byKey(const ValueKey('profile-card-viewer')));
        await tester.pumpAndSettle();
        await _submitPin(tester);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(fixture.controller.busy, isTrue);
        expect(fixture.plex.probes, [('media', 'synthetic-viewer-pms')]);
        expect(find.text('Choose a server'), findsNothing);
        expect(find.text('Choose libraries'), findsNothing);

        gate.complete(200);
        await tester.pumpAndSettle();
        expect(find.text('Choose libraries'), findsOneWidget);
        expect(find.byKey(const Key('profile-pin-sheet')), findsNothing);

        await _back(tester, tv: tv, label: 'Back to profiles');
        expect(fixture.controller.stage, SetupStage.profiles);
        expect(fixture.controller.profile, isNull);
        expect(fixture.controller.server, isNull);
        expect(fixture.controller.connection, isNull);
        expect(fixture.controller.libraries, isEmpty);
        expect(fixture.credentials.accountToken, _accountToken);
        expect(fixture.credentials.profileTokens, {'viewer': _profileToken});
        expect(fixture.store.state.selectedServerByProfile, {
          'viewer': 'media',
        });

        await tester.tap(find.byKey(const ValueKey('profile-card-viewer')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('profile-pin-sheet')), findsOneWidget);
        expect(fixture.plex.profileSwitches, ['1234']);
        expect(fixture.plex.probes, hasLength(1));
      },
    );

    testWidgets(
      'nested first Libraries picker opens the new profile’s sole server (TV=$tv)',
      (tester) async {
        final fixture = _RoutingFixture(profiles: [_owner, _viewer]);
        final controller = fixture.controller;
        await controller.initialize();
        await _show(tester, fixture, tv: tv);

        await tester.tap(find.byKey(const ValueKey('profile-card-owner')));
        await tester.pumpAndSettle();
        expect(controller.firstLibrariesOrigin, FirstLibrariesOrigin.profiles);

        Future<void> openNestedPicker() async {
          await tester.tap(find.text('Switch server'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Switch profile'));
          await tester.pumpAndSettle();
          expect(controller.stage, SetupStage.profiles);
          expect(controller.profile?.id, 'owner');
          expect(controller.server?.id, 'media');
        }

        await openNestedPicker();
        await _back(tester, tv: tv, label: 'Back');
        expect(controller.stage, SetupStage.servers);
        await _back(tester, tv: tv, label: 'Back');
        expect(controller.firstLibrariesOrigin, FirstLibrariesOrigin.profiles);
        expect(fixture.plex.probes, [('media', 'synthetic-owner-pms')]);

        await openNestedPicker();
        await tester.tap(find.byKey(const ValueKey('profile-card-viewer')));
        await tester.pumpAndSettle();
        final probe = Completer<int>();
        fixture.plex.probeResponses['media'] = probe.future;
        await _submitPin(tester);
        await tester.pump();
        expect(find.text('Choose a server'), findsNothing);
        expect(controller.busy, isTrue);
        expect(fixture.plex.probes.last, ('media', 'synthetic-viewer-pms'));

        probe.complete(200);
        await tester.pumpAndSettle();
        expect(find.text('Choose libraries'), findsOneWidget);
        expect(controller.firstLibrariesOrigin, FirstLibrariesOrigin.profiles);
        expect(controller.profile?.id, 'viewer');
        expect(fixture.store.state.selectedServerByProfile, {
          'owner': 'media',
          'viewer': 'media',
        });
        await _back(tester, tv: tv, label: 'Back to profiles');
        expect(controller.stage, SetupStage.profiles);
        expect(controller.profile, isNull);
        expect(controller.server, isNull);
        expect(controller.connection, isNull);
        expect(controller.firstLibrariesOrigin, isNull);
      },
    );

    for (final failStop in [false, true]) {
      testWidgets(
        'first Libraries sign-in Back fences setup actions (TV=$tv, failed stop=$failStop)',
        (tester) async {
          final fixture = _RoutingFixture(signedIn: false);
          final controller = fixture.controller;
          final player = _GatedStopPlayer();
          await _show(tester, fixture, tv: tv, player: player);
          await tester.tap(find.text('Sign in to Plex'));
          await tester.pump();
          expect(controller.activePin, isNotNull);
          await tester.pump(const Duration(seconds: 1));
          await tester.pumpAndSettle();
          expect(find.text('Choose a server'), findsNothing);
          expect(find.text('Choose libraries'), findsOneWidget);
          expect(fixture.plex.pinPolls, 1);

          final scanAction = find.byKey(
            const ValueKey('scan-selected-libraries'),
          );
          final switchAction = find.byKey(
            const ValueKey('setup-switch-server'),
          );
          final staleSwitch = tester
              .widget<TextButton>(switchAction)
              .onPressed!;
          final staleBack = tv
              ? null
              : tester
                    .widget<TextButton>(
                      find.widgetWithText(TextButton, 'Back to sign-in'),
                    )
                    .onPressed;
          final staleScan = tester.widget<FilledButton>(scanAction).onPressed!;
          final staleCommit = tester
              .widget<SetupLibraryStep>(find.byType(SetupLibraryStep))
              .onCommit;
          final beforeState = fixture.store.state;
          final saves = fixture.store.savedStates.length;
          final stop = player.stopGate = Completer<void>();
          if (failStop) {
            // Deliver Back when the scan settles, before the view's async scan
            // continuation can implicitly commit the ready libraries.
            final setup = tester.state<UpstreamChannelSetupViewState>(
              find.byType(UpstreamChannelSetupView),
            );
            var backStarted = false;
            void backOnSettledScan() {
              if (!backStarted &&
                  !controller.busy &&
                  controller.libraryScanStatus == LibraryScanStatus.complete) {
                backStarted = true;
                expect(setup.handleBack(), isTrue);
              }
            }

            controller.addListener(backOnSettledScan);
            fixture.plex.scanResult = _playableScan();
            await tester.tap(scanAction);
            await tester.pumpAndSettle();
            controller.removeListener(backOnSettledScan);
            expect(backStarted, isTrue);
            expect(fixture.plex.libraryScans, 1);
            expect(
              tester
                  .widget<FilledButton>(
                    find.byKey(const ValueKey('continue-ready-libraries')),
                  )
                  .onPressed,
              isNull,
            );
            expect(
              tester
                  .widget<OutlinedButton>(
                    find.byKey(const ValueKey('scan-again-libraries')),
                  )
                  .onPressed,
              isNull,
            );
          } else {
            await _back(tester, tv: tv, label: 'Back to sign-in');
            expect(tester.widget<FilledButton>(scanAction).onPressed, isNull);
          }
          expect(tester.widget<TextButton>(switchAction).onPressed, isNull);
          expect(fixture.credentials.accountToken, _accountToken);
          expect(controller.stage, SetupStage.channelSetup);
          expect(controller.firstLibrariesOrigin, FirstLibrariesOrigin.signIn);
          expect(fixture.store.savedStates, hasLength(saves));

          // Old callbacks can still arrive after the authorization transition
          // starts, including before the next frame.
          staleSwitch();
          staleScan();
          await staleCommit({'movies'});
          await tester.pumpAndSettle();
          expect(controller.stage, SetupStage.channelSetup);
          expect(fixture.plex.libraryScans, failStop ? 1 : 0);
          expect(fixture.store.state, same(beforeState));
          expect(fixture.store.savedStates, hasLength(saves));

          if (failStop) {
            stop.completeError(StateError('Synthetic stop failure'));
            await tester.pumpAndSettle();
            expect(find.text('Could not sign out'), findsOneWidget);
            expect(find.text('You are still signed in.'), findsOneWidget);
            expect(controller.server?.id, 'media');
            expect(fixture.credentials.accountToken, _accountToken);
            expect(fixture.store.savedStates, hasLength(saves));

            player.stopGate = null;
            await tester.tap(find.text('Retry stopping playback'));
            await tester.pumpAndSettle();
            expect(find.text('Could not sign out'), findsNothing);
            expect(fixture.credentials.accountToken, _accountToken);
            expect(
              tester.widget<TextButton>(switchAction).onPressed,
              isNotNull,
            );
            expect(
              tester
                  .widget<FilledButton>(
                    find.byKey(const ValueKey('continue-ready-libraries')),
                  )
                  .onPressed,
              isNotNull,
            );
            expect(fixture.store.savedStates, hasLength(saves));
            await _back(tester, tv: tv, label: 'Back to sign-in');
          } else {
            stop.complete();
            await tester.pumpAndSettle();
          }

          expect(find.text('Sign in to Plex'), findsOneWidget);
          staleBack?.call();
          staleSwitch();
          staleScan();
          await staleCommit({'movies'});
          expect(controller.stage, SetupStage.welcome);
          expect(fixture.credentials.accountToken, isNull);
          expect(fixture.credentials.profileTokens, isEmpty);
          expect(controller.activePin, isNull);
          expect(controller.server, isNull);
          expect(controller.firstLibrariesOrigin, isNull);
          expect(fixture.store.state.selectedServerByProfile, {
            'owner': 'media',
          });
          expect(fixture.store.savedStates, hasLength(saves));
          await tester.pump(const Duration(seconds: 2));
          expect(fixture.plex.pinPolls, 1);
        },
      );
    }
  }

  testWidgets(
    'automatic failure is a single live row status with a Retry action',
    (tester) async {
      final fixture = _RoutingFixture()
        ..plex.probeResponses['media'] = Future.value(503);
      await fixture.controller.initialize();
      final semantics = tester.ensureSemantics();
      await _show(tester, fixture, tv: true);

      expect(find.text('Choose a server'), findsOneWidget);
      expect(find.text('Unreachable'), findsOneWidget);
      expect(find.bySemanticsLabel('Unreachable'), findsOneWidget);
      expect(find.text(fixture.controller.error!), findsNothing);
      final retry = find.widgetWithText(OutlinedButton, 'Retry');
      expect(tester.getSemantics(retry).getSemanticsData().label, 'Retry');
      expect(
        Focus.of(tester.element(find.text('Retry'))).hasPrimaryFocus,
        isTrue,
      );
      fixture.plex.probeResponses['media'] = Future.value(200);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('Choose libraries'), findsOneWidget);
      expect(fixture.plex.probes, hasLength(2));
      semantics.dispose();
    },
  );
}

Future<void> _show(
  WidgetTester tester,
  _RoutingFixture fixture, {
  required bool tv,
  FixturePlayer? player,
}) async {
  final native = player ?? FixturePlayer();
  addTearDown(native.dispose);
  final profile = tv ? tvProfile : desktopProfile;
  await tester.pumpWidget(
    DeviceProfileScope(
      profile: profile,
      child: MaterialApp(
        builder: LineupCanvas.builder,
        home: LineupShell(
          controller: fixture.controller,
          player: native,
          profile: profile,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _submitPin(WidgetTester tester) async {
  for (final key in [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
  ]) {
    await tester.sendKeyEvent(key);
  }
}

Future<void> _back(
  WidgetTester tester, {
  required bool tv,
  required String label,
}) async {
  if (tv) {
    await tester.sendKeyEvent(
      LogicalKeyboardKey.goBack,
      physicalKey: PhysicalKeyboardKey.escape,
    );
  } else {
    await tester.tap(find.widgetWithText(TextButton, label));
  }
  await tester.pumpAndSettle();
}

class _RoutingFixture {
  _RoutingFixture({
    List<PlexHomeUser> profiles = const [_owner],
    List<String> servers = const ['media'],
    PersistedState? state,
    bool signedIn = true,
  }) : store = MemoryAppStore(initial: state),
       credentials = MemoryCredentialStore(
         accountToken: signedIn ? _accountToken : null,
       ),
       plex = _RoutingPlex(profiles, servers) {
    controller = LineupController(
      store: store,
      credentials: credentials,
      plex: plex,
    );
    addTearDown(controller.dispose);
  }

  final MemoryAppStore store;
  final MemoryCredentialStore credentials;
  final _RoutingPlex plex;
  late final LineupController controller;
}

class _RoutingPlex extends PlexClient {
  factory _RoutingPlex(List<PlexHomeUser> profiles, List<String> serverIds) {
    final responses = <String, Future<int>>{};
    final probes = <(String, String?)>[];
    final firstProbe = Completer<void>();
    final client = MockClient((request) async {
      expect(request.url.path, '/identity');
      final id = request.url.host.split('.').first;
      probes.add((id, request.headers['x-plex-token']));
      if (!firstProbe.isCompleted) firstProbe.complete();
      return http.Response(
        '{"machineIdentifier":"$id"}',
        await (responses[id] ?? Future.value(200)),
      );
    });
    return _RoutingPlex._(
      profiles,
      serverIds,
      responses,
      probes,
      firstProbe,
      client,
    );
  }

  _RoutingPlex._(
    this.profiles,
    this.serverIds,
    this.probeResponses,
    this.probes,
    this.firstProbe,
    http.Client client,
  ) : super(clientIdentifier: 'synthetic-routing-client', httpClient: client);

  final List<PlexHomeUser> profiles;
  final List<String> serverIds;
  final Map<String, Future<int>> probeResponses;
  final List<(String, String?)> probes;
  final Completer<void> firstProbe;
  final profileSwitches = <String?>[];
  int pinPolls = 0;
  int libraryScans = 0;
  bool libraryAuthorizationDenied = false;
  PlexLibraryScan scanResult = const PlexLibraryScan(items: []);
  Completer<PlexLibraryScan>? scanGate;

  @override
  Future<PlexAccount> account(String token) async =>
      const PlexAccount(id: 'owner', name: 'Owner', email: '');

  @override
  Future<List<PlexHomeUser>> homeUsers(String token) async => profiles;

  @override
  Future<String> switchHomeUser(String token, String id, String? pin) async {
    profileSwitches.add(pin);
    expect(id, anyOf('viewer', 'owner'));
    return id == 'viewer' ? _profileToken : _accountToken;
  }

  @override
  Future<PlexPin> createPin() async => PlexPin(
    id: 1,
    code: 'TEST',
    expiresAt: DateTime.now().add(const Duration(minutes: 4)),
  );

  @override
  Future<String?> pollPin(PlexPin pin) async {
    pinPolls++;
    return _accountToken;
  }

  @override
  Future<void> cancelPin(PlexPin pin) async {}

  @override
  Future<List<PlexServerAccess>> discoverServers(String token) async => [
    for (final id in serverIds)
      PlexServerAccess(
        token: token == _profileToken
            ? 'synthetic-viewer-pms'
            : 'synthetic-owner-pms',
        server: PlexServer(
          id: id,
          name: id == 'media' ? 'Media room' : 'Archive',
          connections: [
            PlexConnection(
              uri: Uri.parse('https://$id.invalid'),
              local: true,
              relay: false,
            ),
          ],
        ),
      ),
  ];

  @override
  Future<List<PlexLibrary>> libraries(Uri server, String token) async {
    if (libraryAuthorizationDenied) {
      probeResponses['media'] = Future.value(503);
      throw const PlexException(
        'access-denied',
        'Library authorization failed.',
      );
    }
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
  }) async {
    libraryScans++;
    return scanGate?.future ?? scanResult;
  }

  @override
  Future<PlexPlaylistCatalog> playlists(
    Uri server,
    String token, {
    required bool Function() isCurrent,
    Future<void>? cancelled,
    void Function(PlexPlaylistProgress)? onProgress,
  }) async => const PlexPlaylistCatalog(playlists: [], failedIds: {});
}

class _GatedStopPlayer extends FixturePlayer {
  Completer<void>? stopGate;

  @override
  Future<void> stop() async {
    await super.stop();
    await stopGate?.future;
  }
}
