import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lineup_desktop/app/lineup_app.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/app/lineup_restore_view.dart';
import 'package:lineup_desktop/app/setup_result_atmosphere.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

import '../support/ui_fixture.dart';

class _SurfaceController extends FixtureController {
  PlexLibraryScanPhase phase = PlexLibraryScanPhase.items;
  PlexPlaylistProgress? playlistProgress;
  @override
  PlexPlaylistProgress? get playlistScanProgress => playlistProgress;
  bool switchingAllowed = true;
  int scans = 0;
  @override
  PlexLibraryScanPhase get libraryScanPhase => phase;
  @override
  bool get canSwitchServer => switchingAllowed;
  @override
  Set<String> get libraryScanReadyIds => {'movies'};
  @override
  Map<String, LibraryScanFact> get libraryScanFacts => {
    'movies': LibraryScanFact(
      status: libraryScanStatus,
      phase: phase,
      completedItems: 1200,
    ),
  };
  @override
  Future<bool> scanLibraries(
    Set<String> ids, {
    bool retryFailedOnly = false,
  }) async {
    scans++;
    return true;
  }
}

Future<void> _pump(
  WidgetTester tester,
  _SurfaceController controller, {
  Size size = const Size(1920, 1080),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  controller.settings = const LineupSettings(reduceMotion: true);
  await tester.pumpWidget(UiFixture(controller: controller).build());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('restore routing, phase-only live region, and server switch', (
    tester,
  ) async {
    final c = _SurfaceController()
      ..stage = SetupStage.channelSetup
      ..restoringSavedLineup = true
      ..libraryScanStatus = LibraryScanStatus.scanning
      ..libraryScanCompletedItems = 1200
      ..libraryScanTotalItems = 5000;
    addTearDown(c.dispose);
    final semantics = tester.ensureSemantics();
    await _pump(tester, c);
    expect(find.byType(LineupRestoreView), findsOneWidget);
    expect(find.text('Loading your lineup…'), findsOneWidget);
    expect(find.text('Checking items · 1,200 of 5,000'), findsOneWidget);
    expect(find.byKey(const ValueKey('library-selection-list')), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('Cancel scan'), findsNothing);
    final status = find.byKey(const ValueKey('library-scan-phase'));
    expect(tester.getSemantics(status).label, 'Checking items');
    c.libraryScanCompletedItems = 1300;
    c.notifyListeners();
    await tester.pump();
    expect(find.text('Checking items · 1,300 of 5,000'), findsOneWidget);
    expect(tester.getSemantics(status).label, 'Checking items');
    c.libraryScanTotalItems = null;
    c.notifyListeners();
    await tester.pump();
    expect(find.text('Checking items · 1,300'), findsOneWidget);
    for (final phase in [
      PlexLibraryScanPhase.collections,
      PlexLibraryScanPhase.showGenres,
    ]) {
      c.phase = phase;
      c.notifyListeners();
      await tester.pump();
      expect(
        tester.getSemantics(status).label,
        phase == PlexLibraryScanPhase.collections
            ? 'Loading collections'
            : 'Loading show details',
      );
      expect(tester.widget<Semantics>(status).properties.liveRegion, isTrue);
    }
    c.playlistProgress = const PlexPlaylistProgress();
    c.notifyListeners();
    await tester.pump();
    expect(find.text('Finding playlists'), findsOneWidget);
    expect(tester.getSemantics(status).label, 'Finding playlists');
    for (final completed in [0, 4]) {
      c.playlistProgress = PlexPlaylistProgress(
        completedPlaylists: completed,
        totalPlaylists: 8,
      );
      c.notifyListeners();
      await tester.pump();
      expect(find.text('Loading playlists · $completed of 8'), findsOneWidget);
      expect(tester.getSemantics(status).label, 'Loading playlists');
    }
    expect(
      tester
          .widget<SetupResultAtmosphere>(find.byType(SetupResultAtmosphere))
          .applying,
      isTrue,
    );
    c.switchingAllowed = false;
    c.notifyListeners();
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('restore-switch-server')),
          )
          .onPressed,
      isNull,
    );
    c.switchingAllowed = true;
    c.notifyListeners();
    await tester.pump();
    await tester.tap(find.text('Switch server'));
    await tester.pumpAndSettle();
    expect(c.stage, SetupStage.servers);
    semantics.dispose();
  });

  for (final size in [const Size(1920, 1080), const Size(960, 720)]) {
    for (final empty in [false, true]) {
      testWidgets(
        'library step ${empty ? 'empty' : 'settled'} offers server switch at $size',
        (tester) async {
          final c = _SurfaceController()
            ..stage = SetupStage.ready
            ..libraries = empty
                ? []
                : const [
                    PlexLibrary(
                      id: 'movies',
                      title: 'Movies',
                      type: PlexLibraryType.movie,
                    ),
                  ]
            // An empty server may still have a saved library selection.
            ..selectedLibraryIds = {'movies'}
            ..libraryScanStatus = LibraryScanStatus.complete;
          c.enterChannelSetup();
          addTearDown(c.dispose);
          await _pump(tester, c, size: size);
          expect(find.text('Switch server'), findsOneWidget);
          expect(find.text('Cancel'), findsOneWidget);
          if (!empty) {
            expect(
              tester.getTopLeft(find.text('Switch server')).dx,
              closeTo(
                tester.getTopLeft(find.text('Review your libraries')).dx,
                .1,
              ),
            );
            expect(find.text('Scan again'), findsOneWidget);
            expect(find.text('Continue with 1 library'), findsOneWidget);
            await tester.tap(find.text('Scan again'));
            await tester.pumpAndSettle();
            expect(c.scans, 1);
            expect(find.text('Review your libraries'), findsOneWidget);
            expect(find.text('Shape your lineup'), findsNothing);
          } else {
            expect(
              find.text('Select the Plex libraries to scan for channel ideas.'),
              findsNothing,
            );
            expect(find.text('Scan again'), findsNothing);
            expect(
              find.byKey(const ValueKey('scan-selected-libraries')),
              findsNothing,
            );
            final switchServer = find.byKey(
              const ValueKey('setup-switch-server'),
            );
            expect(
              tester.widget<FilledButton>(switchServer).onPressed,
              isNotNull,
            );
            expect(
              find.widgetWithText(TextButton, 'Switch server'),
              findsNothing,
            );
            expect(
              find.text(
                'Choose another Plex server with accessible libraries.',
              ),
              findsOneWidget,
            );
          }
          await tester.tap(find.text('Switch server'));
          await tester.pumpAndSettle();
          expect(c.stage, SetupStage.servers);
        },
      );
    }
  }

  testWidgets(
    'setup scan exposes enrichment and keeps Switch server usable while busy',
    (tester) async {
      final c = _SurfaceController()
        ..stage = SetupStage.channelSetup
        ..busy = true
        ..phase = PlexLibraryScanPhase.collections
        ..libraryScanStatus = LibraryScanStatus.scanning
        ..libraries = const [
          PlexLibrary(
            id: 'movies',
            title: 'Movies',
            type: PlexLibraryType.movie,
          ),
        ];
      addTearDown(c.dispose);
      await _pump(tester, c);
      expect(find.text('Loading collections'), findsWidgets);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('setup-switch-server')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Switch server'));
      await tester.pumpAndSettle();
      expect(c.stage, SetupStage.servers);
    },
  );

  testWidgets(
    'setup phase displays bounded playlist work after library facts complete',
    (tester) async {
      final c = _SurfaceController()
        ..stage = SetupStage.channelSetup
        ..libraryScanStatus = LibraryScanStatus.scanning
        ..playlistProgress = const PlexPlaylistProgress(
          completedPlaylists: 4,
          totalPlaylists: 8,
        )
        ..libraries = const [
          PlexLibrary(
            id: 'movies',
            title: 'Movies',
            type: PlexLibraryType.movie,
          ),
        ];
      addTearDown(c.dispose);
      await _pump(tester, c);
      expect(find.text('Loading playlists · 4 of 8'), findsOneWidget);
      expect(find.text('Checking items · 0'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final theme in LineupThemeName.values) {
    testWidgets(
      'restore adapts across the resolution matrix in ${theme.label}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        for (final size in const [
          Size(960, 720),
          Size(1280, 720),
          Size(1366, 768),
          Size(1536, 864),
          Size(1920, 1080),
          Size(1920, 1200),
          Size(2560, 1440),
          Size(3440, 1440),
          Size(3840, 2160),
        ]) {
          tester.view.physicalSize = size;
          final c = _SurfaceController()
            ..stage = SetupStage.channelSetup
            ..restoringSavedLineup = true
            ..settings = LineupSettings(theme: theme, reduceMotion: true);
          await tester.pumpWidget(UiFixture(controller: c).build());
          await tester.pumpAndSettle();
          expect(find.text('Loading your lineup…'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
        tester.view.physicalSize = const Size(1920, 1080);
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        final c = _SurfaceController()
          ..stage = SetupStage.channelSetup
          ..restoringSavedLineup = true
          ..settings = LineupSettings(theme: theme, reduceMotion: true);
        await tester.pumpWidget(UiFixture(controller: c).build());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('native initialization remains a barrier during real restore', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fixture = _realRestoreFixture();
    final player = _GatedPlayer();
    await tester.pumpWidget(
      LineupBootstrap(controller: fixture.controller, player: player),
    );
    await _waitForRestore(tester, fixture.plex);
    expect(fixture.controller.restoringSavedLineup, isTrue);
    expect(_startupSplash, findsOneWidget);
    expect(find.text('Loading your lineup…'), findsNothing);
    expect(fixture.plex.completedScans, 0);

    player.finish.complete();
    await tester.pumpAndSettle();
    expect(_startupSplash, findsNothing);
    expect(find.text('Loading your lineup…'), findsOneWidget);
    expect(find.byKey(const ValueKey('library-selection-list')), findsNothing);
    expect(fixture.plex.completedScans, 0);
    fixture.plex.finish.complete();
    await tester.pumpAndSettle();
    expect(fixture.controller.stage, SetupStage.ready);
  });

  for (final cancelPicker in [false, true]) {
    testWidgets(
      'real startup keeps ${cancelPicker ? 'restarted restore' : 'server picker'} visible before obsolete scan unwinds',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final fixture = _realRestoreFixture();
        await tester.pumpWidget(
          LineupBootstrap(
            controller: fixture.controller,
            player: FixturePlayer(),
          ),
        );
        await _waitForRestore(tester, fixture.plex);
        await tester.pumpAndSettle();
        expect(find.text('Loading your lineup…'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('library-selection-list')),
          findsNothing,
        );
        await tester.tap(find.text('Switch server'));
        await tester.pumpAndSettle();
        expect(fixture.controller.stage, SetupStage.servers);
        expect(find.text('Choose a server'), findsOneWidget);
        expect(find.text('Synthetic server'), findsOneWidget);
        expect(_startupSplash, findsNothing);
        expect(fixture.plex.finish.isCompleted, isFalse);
        expect(fixture.plex.completedScans, 0);

        if (cancelPicker) {
          await tester.tap(find.text('Back'));
          await tester.pumpAndSettle();
          expect(fixture.controller.restoringSavedLineup, isTrue);
          expect(find.text('Loading your lineup…'), findsOneWidget);
          expect(fixture.plex.scans, 2);
          expect(fixture.plex.completedScans, 0);
          expect(
            find.byKey(const ValueKey('library-selection-list')),
            findsNothing,
          );
          expect(_startupSplash, findsNothing);
        }
        fixture.plex.finish.complete();
        await tester.pumpAndSettle();
        expect(
          fixture.controller.stage,
          cancelPicker ? SetupStage.ready : SetupStage.servers,
        );
        if (!cancelPicker) expect(find.text('Choose a server'), findsOneWidget);
        expect(
          fixture
              .store
              .state
              .channelsByProfileServer['owner']!['server']!
              .single
              .id,
          'saved',
        );
      },
    );
  }

  testWidgets(
    'saved startup to Generate lineup to Continue uses restored inventory without storage reset',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fixture = _realRestoreFixture();
      final c = fixture.controller;
      final plex = fixture.plex;
      final store = fixture.store;
      addTearDown(c.dispose);
      await tester.pumpWidget(
        LineupBootstrap(
          controller: c,
          player: FixturePlayer(),
          guideClock: () => DateTime.utc(2026, 1, 15),
        ),
      );
      for (var i = 0; i < 30 && !c.restoringSavedLineup; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(c.restoringSavedLineup, isTrue);
      await tester.pump();
      expect(find.text('Loading your lineup…'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('library-selection-list')),
        findsNothing,
      );
      plex.finish.complete();
      await tester.pumpAndSettle();
      expect(c.stage, SetupStage.ready);
      await openDestination(tester, 'Channels');
      await tester.tap(find.text('Generate lineup'));
      await tester.pumpAndSettle();
      expect(find.text('Continue with 1 library'), findsOneWidget);
      await tester.tap(find.text('Continue with 1 library'));
      await tester.pumpAndSettle();
      expect(find.text('Shape your lineup'), findsOneWidget);
      expect(plex.scans, 1);
      expect(c.channels.single.id, 'saved');
      expect(
        store.state.channelsByProfileServer['owner']!['server']!.single.id,
        'saved',
      );
      expect(
        store.state.selectedLibraryIdsByProfileServer['owner']!['server'],
        ['movies'],
      );
    },
  );
}

Finder get _startupSplash => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.label == 'Starting Lineup Desktop',
);

Future<void> _waitForRestore(WidgetTester tester, _RestorePlex plex) async {
  for (var i = 0; i < 30 && plex.scans == 0; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(
    plex.scans,
    1,
    reason: 'Real startup must reach its gated restore scan.',
  );
  await tester.pump();
}

({LineupController controller, _RestorePlex plex, FixtureStore store})
_realRestoreFixture() {
  final channel = Channel(
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
  );
  final store = FixtureStore()
    ..state = PersistedState(
      settings: const LineupSettings(reduceMotion: true),
      selectedServerByProfile: const {'owner': 'server'},
      selectedLibraryIdsByProfileServer: const {
        'owner': {
          'server': ['movies'],
        },
      },
      channelsByProfileServer: {
        'owner': {
          'server': [channel],
        },
      },
    );
  final plex = _RestorePlex();
  final controller = LineupController(
    store: store,
    credentials: _Credentials(),
    plex: plex,
  );
  addTearDown(controller.dispose);
  return (controller: controller, plex: plex, store: store);
}

class _GatedPlayer extends FixturePlayer {
  final finish = Completer<void>();
  @override
  Future<void> initialize() => finish.future;
}

class _Credentials implements CredentialStore {
  @override
  Future<String?> readAccountToken() async => 'synthetic-token';
  @override
  Future<String?> readProfileToken(String id) async => null;
  @override
  Future<void> clear() async {}
  @override
  Future<void> writeAccountToken(String token) async {}
  @override
  Future<void> writeProfileToken(String id, String token) async {}
}

class _RestorePlex extends PlexClient {
  _RestorePlex()
    : super(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient(
          (_) async => throw StateError('unexpected HTTP'),
        ),
      );
  final finish = Completer<void>();
  int scans = 0;
  int completedScans = 0;
  final server = PlexServer(
    id: 'server',
    name: 'Synthetic server',
    connections: [
      PlexConnection(
        uri: Uri.parse('https://synthetic.invalid'),
        local: true,
        relay: false,
      ),
    ],
    owned: true,
  );
  @override
  Future<PlexAccount> account(String token) async =>
      const PlexAccount(id: 'owner', name: 'Owner', email: '');
  @override
  Future<List<PlexHomeUser>> homeUsers(String token) async => [];
  @override
  Future<List<PlexServerAccess>> discoverServers(String token) async => [
    PlexServerAccess(server: server, token: 'synthetic-pms-token'),
  ];
  @override
  Future<PlexConnection> selectConnection(
    PlexServer server,
    String token,
  ) async => server.connections.single;
  @override
  Future<List<PlexLibrary>> libraries(Uri server, String token) async => const [
    PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
  ];
  @override
  Future<PlexLibraryScan> scanLibrary(
    Uri server,
    String token,
    String id,
    PlexLibraryType type, {
    required bool Function() isCurrent,
    required void Function(PlexLibraryPageProgress) onProgress,
    void Function(PlexLibraryScanPhase)? onPhase,
    Future<void>? cancelled,
  }) async {
    scans++;
    onPhase?.call(PlexLibraryScanPhase.items);
    await finish.future;
    completedScans++;
    return PlexLibraryScan(
      items: [
        PlexMediaItem(
          id: 'movie',
          title: 'Synthetic movie',
          type: 'movie',
          duration: const Duration(minutes: 60),
          libraryId: id,
          parts: [PlexMediaPart(path: '/parts/movie')],
        ),
      ],
    );
  }

  @override
  Future<PlexPlaylistCatalog> playlists(
    Uri server,
    String token, {
    required bool Function() isCurrent,
    Future<void>? cancelled,
    void Function(PlexPlaylistProgress progress)? onProgress,
  }) async => const PlexPlaylistCatalog(playlists: [], failedIds: {});
}
