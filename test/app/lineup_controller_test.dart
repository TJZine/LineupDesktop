import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/channel_builder.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

void main() {
  test('playback requests remove Plex tokens without an empty query', () {
    final tokenOnly = LineupPlaybackRequest(
      Uri.parse(
        'https://user@plex.example:32400/video%2Fpart?X-Plex-Token=secret#section%2Fone',
      ),
      () async {},
    );
    final mixed = LineupPlaybackRequest(
      Uri.parse(
        'https://plex.example/video?quality=original&X-Plex-Token=secret&quality=mobile#part',
      ),
      () async {},
    );

    expect(
      tokenOnly.uri,
      Uri.parse('https://user@plex.example:32400/video%2Fpart#section%2Fone'),
    );
    expect(tokenOnly.uri.hasQuery, isFalse);
    expect(mixed.uri.fragment, 'part');
    expect(mixed.uri.queryParametersAll, {
      'quality': ['original', 'mobile'],
    });
  });

  test(
    'replace applies the immutable plan produced by Channel Setup',
    () async {
      final controller = LineupController(
        store: _MemoryStore(),
        credentials: _MemoryCredentials(),
        plex: _FakePlex(),
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      final planned = List<Channel>.unmodifiable([_channel('planned')]);

      await controller.applyChannelPlan(
        planned,
        mode: ChannelBuildMode.replace,
      );

      expect(controller.channels.single.id, 'planned');
      expect(controller.stage, SetupStage.ready);
    },
  );

  test(
    'missing managed-profile token never falls back to owner scope',
    () async {
      final store = _MemoryStore(const PersistedState(profileId: 'child'));
      final credentials = _MemoryCredentials(accountToken: 'owner-token');
      final plex = _FakePlex()
        ..accountResult = const PlexAccount(
          id: 'owner',
          name: 'Owner',
          email: 'owner@example.test',
        )
        ..homeUsersResult = const [
          PlexHomeUser(id: 'child', name: 'Child', protected: true),
        ];
      final controller = LineupController(
        store: store,
        credentials: credentials,
        plex: plex,
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.stage, SetupStage.profiles);
      expect(controller.profile, isNull);
      expect(plex.discoveredTokens, isEmpty);
    },
  );

  test('failed library loading stays on Channel Setup with an error', () async {
    final controller =
        LineupController(
            store: _MemoryStore(),
            credentials: _MemoryCredentials(accountToken: 'token'),
            plex: _FakePlex()
              ..libraryItemsHandler = (_, _, _, _) async =>
                  throw const PlexException('offline', 'Library unavailable'),
          )
          ..connection = PlexConnection(
            uri: Uri.parse('https://plex.example:32400'),
            local: true,
            relay: false,
          )
          ..libraries = const [
            PlexLibrary(
              id: 'movies',
              title: 'Movies',
              type: PlexLibraryType.movie,
            ),
          ]
          ..stage = SetupStage.channelSetup;
    addTearDown(controller.dispose);
    await controller.initialize();
    controller
      ..connection = PlexConnection(
        uri: Uri.parse('https://plex.example:32400'),
        local: true,
        relay: false,
      )
      ..libraries = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ]
      ..stage = SetupStage.channelSetup;

    final loaded = await controller.setLibraries({'movies'});

    expect(loaded, isFalse);
    expect(controller.stage, SetupStage.channelSetup);
    expect(controller.error, 'Library unavailable');
  });

  test('audio persistence failure stays retryable and visible', () async {
    final controller = LineupController(
      store: _MemoryStore()..failNextSave = true,
      credentials: _MemoryCredentials(),
      plex: _FakePlex(),
    )..stage = SetupStage.audio;
    addTearDown(controller.dispose);

    await controller.completeAudioSetup();

    expect(controller.stage, SetupStage.audio);
    expect(controller.settings.audioSetupComplete, isFalse);
    expect(controller.error, contains('Could not save audio settings'));
  });

  test(
    'profile picker preference is honored before saved profile restore',
    () async {
      final store = _MemoryStore(
        const PersistedState(
          settings: LineupSettings(profilePickerOnStartup: true),
          profileId: 'owner',
        ),
      );
      final plex = _FakePlex()
        ..homeUsersResult = const [
          PlexHomeUser(id: 'owner', name: 'Owner', protected: false),
          PlexHomeUser(id: 'child', name: 'Child', protected: true),
        ];
      final controller = LineupController(
        store: store,
        credentials: _MemoryCredentials(accountToken: 'owner-token'),
        plex: plex,
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.stage, SetupStage.profiles);
      expect(controller.profile, isNull);
      expect(plex.discoveredTokens, isEmpty);
    },
  );

  test('a stale failure cannot overwrite logout state', () async {
    final account = Completer<PlexAccount>();
    final controller = LineupController(
      store: _MemoryStore(),
      credentials: _MemoryCredentials(accountToken: 'token'),
      plex: _FakePlex()..accountHandler = (_) => account.future,
    );
    addTearDown(controller.dispose);

    final initialization = controller.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(controller.busy, isTrue);

    await controller.logout();
    account.completeError(const PlexException('offline', 'Old failure'));
    await initialization;

    expect(controller.stage, SetupStage.welcome);
    expect(controller.error, isNull);
    expect(controller.busy, isFalse);
  });

  test('PIN polling never overlaps slow transport calls', () async {
    final poll = Completer<String?>();
    final plex = _FakePlex()
      ..pinResult = PlexPin(
        id: 5,
        code: 'ABCD',
        expiresAt: DateTime.now().add(const Duration(minutes: 1)),
      )
      ..pollHandler = (_) => poll.future;
    final controller = LineupController(
      store: _MemoryStore(),
      credentials: _MemoryCredentials(),
      plex: plex,
      pinPollInterval: const Duration(milliseconds: 5),
    );
    addTearDown(controller.dispose);

    await controller.startLinking();
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(plex.pollCalls, 1);

    await controller.logout();
    poll.complete(null);
  });

  test(
    'failed settings persistence does not leak into the next save',
    () async {
      final store = _MemoryStore()..failNextSave = true;
      final controller = LineupController(
        store: store,
        credentials: _MemoryCredentials(),
        plex: _FakePlex(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      await expectLater(
        controller.updateSettings(
          const LineupSettings(diagnosticsEnabled: true),
        ),
        throwsStateError,
      );
      await controller.saveChannel(
        Channel(
          id: 'channel',
          number: 1,
          name: 'Channel',
          source: const LibrarySource(
            libraryId: '1',
            libraryType: PlexLibraryType.movie,
          ),
          playbackMode: PlaybackMode.sequential,
          anchor: DateTime.utc(2026),
          shuffleSeed: 1,
        ),
      );

      expect(store.state.settings.diagnosticsEnabled, isFalse);
      expect(controller.channels.single.id, 'channel');
    },
  );

  test('logout clears a credential write that was already in flight', () async {
    final credentials = _BlockingCredentials();
    final plex = _FakePlex()
      ..pinResult = PlexPin(
        id: 7,
        code: 'ABCD',
        expiresAt: DateTime.now().add(const Duration(minutes: 1)),
      )
      ..pollHandler = (_) async => 'late-token';
    final controller = LineupController(
      store: _MemoryStore(),
      credentials: credentials,
      plex: plex,
      pinPollInterval: const Duration(milliseconds: 1),
    );
    addTearDown(controller.dispose);

    await controller.startLinking();
    await credentials.writeStarted.future;
    final logout = controller.logout();
    credentials.finishWrite.complete();
    await logout;

    expect(credentials.accountToken, isNull);
    expect(controller.stage, SetupStage.welcome);
  });

  test('overlapping logout calls share one busy credential cleanup', () async {
    final credentials = _BlockingClearCredentials(accountToken: 'token');
    final controller =
        LineupController(
            store: _MemoryStore(),
            credentials: credentials,
            plex: _FakePlex(),
          )
          ..stage = SetupStage.ready
          ..account = const PlexAccount(id: 'owner', name: 'Owner', email: '');
    addTearDown(controller.dispose);

    final first = controller.logout();
    await credentials.clearStarted.future;
    expect(controller.busy, isTrue);

    final second = controller.logout();
    expect(identical(first, second), isTrue);
    expect(credentials.clearCalls, 1);

    credentials.finishClear.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(controller.busy, isFalse);
    expect(controller.stage, SetupStage.welcome);
  });

  test(
    'failed PIN cancellation stays retryable without hiding a late token',
    () async {
      final credentials = _BlockingFailOnceClearCredentials();
      final plex = _FakePlex()
        ..pinResult = PlexPin(
          id: 8,
          code: 'WXYZ',
          expiresAt: DateTime.now().add(const Duration(minutes: 1)),
        )
        ..pollHandler = (_) async => 'late-token';
      final controller = LineupController(
        store: _MemoryStore(),
        credentials: credentials,
        plex: plex,
        pinPollInterval: const Duration(milliseconds: 1),
      );
      addTearDown(controller.dispose);

      await controller.startLinking();
      await credentials.writeStarted.future;
      final cancelled = controller.cancelLinking();
      credentials.finishWrite.complete();

      expect(await cancelled, isFalse);
      expect(controller.stage, SetupStage.linking);
      expect(controller.error, contains('securely cancel'));
      expect(controller.error, isNot(contains('late-token')));
      expect(credentials.accountToken, 'late-token');
      expect(plex.cancelPinCalls, 1);

      expect(await controller.cancelLinking(), isTrue);
      expect(controller.stage, SetupStage.welcome);
      expect(credentials.accountToken, isNull);
      expect(plex.cancelPinCalls, 2);
    },
  );

  test(
    'credential cleanup failure keeps the session and gives safe recovery',
    () async {
      final controller =
          LineupController(
              store: _MemoryStore(),
              credentials: _FailingClearCredentials(accountToken: 'token'),
              plex: _FakePlex(),
            )
            ..stage = SetupStage.ready
            ..account = const PlexAccount(
              id: 'owner',
              name: 'Owner',
              email: '',
            );
      addTearDown(controller.dispose);

      expect(await controller.logout(), isFalse);

      expect(controller.stage, SetupStage.ready);
      expect(controller.account?.id, 'owner');
      expect(controller.error, contains('securely sign out'));
      expect(controller.error, isNot(contains('keychain-token-secret')));
    },
  );

  test('failed secure logout can be retried successfully', () async {
    final credentials = _FailOnceClearCredentials(accountToken: 'token');
    final controller =
        LineupController(
            store: _MemoryStore(),
            credentials: credentials,
            plex: _FakePlex(),
          )
          ..stage = SetupStage.ready
          ..account = const PlexAccount(id: 'owner', name: 'Owner', email: '');
    addTearDown(controller.dispose);

    expect(await controller.logout(), isFalse);
    expect(controller.stage, SetupStage.ready);
    expect(await controller.logout(), isTrue);
    expect(controller.stage, SetupStage.welcome);
    expect(credentials.accountToken, isNull);
  });

  test('failed logout does not stale an in-flight settings consumer', () async {
    final store = _BlockingSaveStore();
    final controller =
        LineupController(
            store: store,
            credentials: _FailingClearCredentials(accountToken: 'token'),
            plex: _FakePlex(),
          )
          ..stage = SetupStage.ready
          ..account = const PlexAccount(id: 'owner', name: 'Owner', email: '');
    addTearDown(controller.dispose);

    final settings = controller.updateSettings(
      const LineupSettings(diagnosticsEnabled: true),
    );
    await store.saveStarted.future;
    final logout = controller.logout();
    store.finishSave.complete();

    await settings;
    expect(await logout, isFalse);
    expect(controller.settings.diagnosticsEnabled, isTrue);
    expect(controller.diagnostics.enabled, isTrue);
    expect(store.state.settings.diagnosticsEnabled, isTrue);
  });

  test('disposal rejects startup work completing after store load', () async {
    final store = _BlockingLoadStore();
    final controller = LineupController(
      store: store,
      credentials: _MemoryCredentials(accountToken: 'token'),
      plex: _FakePlex(),
    );

    final initialization = controller.initialize();
    controller.dispose();
    store.finishLoad.complete(
      const PersistedState(profileId: 'should-not-restore'),
    );
    await initialization;

    expect(controller.account, isNull);
    expect(controller.stage, SetupStage.welcome);
  });

  test(
    'server management preserves scoped lineups when selection is cleared',
    () async {
      final selected = _server('server-a');
      final channel = _channel('saved-channel');
      final store = _MemoryStore(
        PersistedState(
          settings: const LineupSettings(audioSetupComplete: true),
          profileId: 'owner',
          selectedServerByProfile: const {'owner': 'server-a'},
          channelsByProfileServer: {
            'owner': {
              'server-a': [channel],
            },
          },
        ),
      );
      final plex = _FakePlex()
        ..homeUsersResult = const [
          PlexHomeUser(id: 'owner', name: 'Owner', protected: false),
        ]
        ..serversResult = [selected]
        ..connectionResult = selected.connections.single;
      final controller = LineupController(
        store: store,
        credentials: _MemoryCredentials(accountToken: 'owner-token'),
        plex: plex,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller.stage = SetupStage.ready;

      controller.showServers();
      expect(controller.serverSelectionCanCancel, isTrue);
      controller.cancelServerSelection();
      expect(controller.stage, SetupStage.ready);

      controller.showServers();
      await controller.clearSavedServer();
      expect(controller.stage, SetupStage.servers);
      expect(controller.server, isNull);
      expect(store.state.selectedServerByProfile, isEmpty);
      expect(
        store.state.channelsByProfileServer['owner']!['server-a']!.single.id,
        'saved-channel',
      );
    },
  );

  test('server recovery cancellation rejects stale probe work', () async {
    final probe = Completer<PlexConnection>();
    final oldServer = _server('old');
    final nextServer = _server('next');
    final plex = _FakePlex()
      ..homeUsersResult = const [
        PlexHomeUser(id: 'owner', name: 'Owner', protected: false),
      ]
      ..selectConnectionHandler = (_, _) => probe.future;
    final controller = LineupController(
      store: _MemoryStore(),
      credentials: _MemoryCredentials(accountToken: 'token'),
      plex: plex,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller
      ..server = oldServer
      ..connection = oldServer.connections.single
      ..stage = SetupStage.ready
      ..showServers();

    final selection = controller.selectServer(nextServer);
    await Future<void>.delayed(Duration.zero);
    expect(controller.busy, isTrue);
    controller.cancelServerSelection();
    expect(controller.stage, SetupStage.ready);
    expect(controller.server?.id, 'old');
    probe.complete(nextServer.connections.single);
    await selection;

    expect(controller.server?.id, 'old');
    expect(plex.librariesCalls, 0);
  });

  test('profile recovery cancellation rejects stale switch work', () async {
    final switched = Completer<String>();
    final oldServer = _server('old');
    const owner = PlexHomeUser(id: 'owner', name: 'Owner', protected: false);
    const child = PlexHomeUser(id: 'child', name: 'Child', protected: true);
    final plex = _FakePlex()
      ..homeUsersResult = const [owner, child]
      ..switchHomeUserHandler = (_, _, _) => switched.future;
    final controller = LineupController(
      store: _MemoryStore(),
      credentials: _MemoryCredentials(accountToken: 'token'),
      plex: plex,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller
      ..profile = owner
      ..server = oldServer
      ..connection = oldServer.connections.single
      ..stage = SetupStage.ready
      ..showProfiles();

    final selection = controller.selectProfile(child, pin: '1234');
    await Future<void>.delayed(Duration.zero);
    expect(controller.busy, isTrue);
    controller.cancelProfileSelection();
    expect(controller.stage, SetupStage.ready);
    expect(controller.profile?.id, 'owner');
    switched.complete('child-token');
    await selection;

    expect(controller.profile?.id, 'owner');
    expect(controller.server?.id, 'old');
  });

  test(
    'profile cancellation is hidden before the save commit window',
    () async {
      final store = _BlockingSaveStore();
      const owner = PlexHomeUser(id: 'owner', name: 'Owner', protected: false);
      const child = PlexHomeUser(id: 'child', name: 'Child', protected: false);
      final controller = LineupController(
        store: store,
        credentials: _MemoryCredentials(accountToken: 'token'),
        plex: _FakePlex()..homeUsersResult = const [owner, child],
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller
        ..profile = owner
        ..server = _server('old')
        ..stage = SetupStage.ready
        ..showProfiles();
      var hiddenWhileBusy = false;
      controller.addListener(() {
        hiddenWhileBusy |=
            controller.busy && !controller.profileSelectionCanCancel;
      });

      final selection = controller.selectProfile(child);
      await store.saveStarted.future;

      expect(hiddenWhileBusy, isTrue);
      expect(controller.profileSelectionCanCancel, isFalse);
      store.finishSave.complete();
      await selection;
    },
  );

  test('server cancellation is hidden before the save commit window', () async {
    final store = _BlockingSaveStore();
    final oldServer = _server('old');
    final nextServer = _server('next');
    final controller = LineupController(
      store: store,
      credentials: _MemoryCredentials(accountToken: 'token'),
      plex: _FakePlex()..connectionResult = nextServer.connections.single,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller
      ..server = oldServer
      ..connection = oldServer.connections.single
      ..stage = SetupStage.ready
      ..showServers();
    var hiddenWhileBusy = false;
    controller.addListener(() {
      hiddenWhileBusy |=
          controller.busy && !controller.serverSelectionCanCancel;
    });

    final selection = controller.selectServer(nextServer);
    await store.saveStarted.future;

    expect(hiddenWhileBusy, isTrue);
    expect(controller.serverSelectionCanCancel, isFalse);
    store.finishSave.complete();
    await selection;
  });

  test('discovery clears an unavailable runtime server without crossing profile scope', () async {
    final selected = _server('server-a');
    final plex = _FakePlex()
      ..homeUsersResult = const [
        PlexHomeUser(id: 'owner', name: 'Owner', protected: false),
      ]
      ..serversResult = [selected]
      ..connectionResult = selected.connections.single;
    final controller = LineupController(
      store: _MemoryStore(
        const PersistedState(
          settings: LineupSettings(audioSetupComplete: true),
          profileId: 'owner',
          selectedServerByProfile: {'owner': 'server-a'},
        ),
      ),
      credentials: _MemoryCredentials(accountToken: 'owner-token'),
      plex: plex,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.stage = SetupStage.ready;

    plex.serversResult = const [];
    await controller.refreshServers();

    expect(controller.stage, SetupStage.servers);
    expect(controller.server, isNull);
    expect(controller.connection, isNull);
    expect(controller.channels, isEmpty);
  });

  test('a stale settings failure cannot roll back a newer value', () async {
    final store = _ConcurrentStore();
    final controller = LineupController(
      store: store,
      credentials: _MemoryCredentials(),
      plex: _FakePlex(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    final stale = controller.updateSettings(
      const LineupSettings(diagnosticsEnabled: true),
    );
    await store.firstSaveStarted.future;
    await controller.updateSettings(
      const LineupSettings(nowWatchingBanner: false),
    );
    store.failFirstSave.complete();
    await expectLater(stale, throwsStateError);

    expect(controller.settings.nowWatchingBanner, isFalse);
    expect(controller.settings.diagnosticsEnabled, isFalse);
  });
}

PlexServer _server(String id) => PlexServer(
  id: id,
  name: 'Server $id',
  connections: [
    PlexConnection(
      uri: Uri.parse('https://$id.example:32400'),
      local: true,
      relay: false,
      latency: const Duration(milliseconds: 12),
    ),
  ],
  owned: true,
);

Channel _channel(String id) => Channel(
  id: id,
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

class _MemoryStore implements AppStore {
  _MemoryStore([this.state = const PersistedState()]);

  PersistedState state;
  bool failNextSave = false;

  @override
  Future<String> clientIdentifier() async =>
      'lineup-desktop-test-abcdefghijklmnopqrst';

  @override
  Future<PersistedState> load() async => state;

  @override
  Future<void> save(PersistedState value) async {
    if (failNextSave) {
      failNextSave = false;
      throw StateError('save failed');
    }
    state = value;
  }
}

class _MemoryCredentials implements CredentialStore {
  _MemoryCredentials({this.accountToken, Map<String, String>? profileTokens})
    : profileTokens = profileTokens ?? {};

  String? accountToken;
  final Map<String, String> profileTokens;

  @override
  Future<void> clear() async {
    accountToken = null;
    profileTokens.clear();
  }

  @override
  Future<String?> readAccountToken() async => accountToken;

  @override
  Future<String?> readProfileToken(String profileId) async =>
      profileTokens[profileId];

  @override
  Future<void> writeAccountToken(String token) async => accountToken = token;

  @override
  Future<void> writeProfileToken(String profileId, String token) async =>
      profileTokens[profileId] = token;
}

class _BlockingCredentials extends _MemoryCredentials {
  _BlockingCredentials() : super();

  final writeStarted = Completer<void>();
  final finishWrite = Completer<void>();

  @override
  Future<void> writeAccountToken(String token) async {
    if (!writeStarted.isCompleted) writeStarted.complete();
    await finishWrite.future;
    await super.writeAccountToken(token);
  }
}

class _BlockingClearCredentials extends _MemoryCredentials {
  _BlockingClearCredentials({super.accountToken});

  final clearStarted = Completer<void>();
  final finishClear = Completer<void>();
  var clearCalls = 0;

  @override
  Future<void> clear() async {
    clearCalls++;
    if (!clearStarted.isCompleted) clearStarted.complete();
    await finishClear.future;
    await super.clear();
  }
}

mixin _FailOnceClear on _MemoryCredentials {
  var clearCalls = 0;

  @override
  Future<void> clear() async {
    clearCalls++;
    if (clearCalls == 1) throw StateError('keychain-token-secret');
    await super.clear();
  }
}

class _BlockingFailOnceClearCredentials extends _BlockingCredentials
    with _FailOnceClear {}

class _FailingClearCredentials extends _MemoryCredentials {
  _FailingClearCredentials({super.accountToken});

  @override
  Future<void> clear() async {
    throw StateError('keychain-token-secret');
  }
}

class _FailOnceClearCredentials extends _MemoryCredentials with _FailOnceClear {
  _FailOnceClearCredentials({super.accountToken});
}

class _BlockingSaveStore extends _MemoryStore {
  final saveStarted = Completer<void>();
  final finishSave = Completer<void>();

  @override
  Future<void> save(PersistedState value) async {
    if (!saveStarted.isCompleted) saveStarted.complete();
    await finishSave.future;
    await super.save(value);
  }
}

class _BlockingLoadStore extends _MemoryStore {
  final finishLoad = Completer<PersistedState>();

  @override
  Future<PersistedState> load() => finishLoad.future;
}

class _ConcurrentStore implements AppStore {
  PersistedState state = const PersistedState();
  final firstSaveStarted = Completer<void>();
  final failFirstSave = Completer<void>();
  var saves = 0;

  @override
  Future<String> clientIdentifier() async =>
      'lineup-desktop-test-abcdefghijklmnopqrst';

  @override
  Future<PersistedState> load() async => state;

  @override
  Future<void> save(PersistedState value) async {
    saves++;
    if (saves == 1) {
      firstSaveStarted.complete();
      await failFirstSave.future;
      throw StateError('save failed');
    }
    state = value;
  }
}

class _FakePlex extends PlexClient {
  _FakePlex()
    : super(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient(
          (_) async => throw StateError('unexpected HTTP'),
        ),
      );

  PlexAccount accountResult = const PlexAccount(
    id: 'owner',
    name: 'Owner',
    email: '',
  );
  List<PlexHomeUser> homeUsersResult = const [];
  PlexPin? pinResult;
  Future<PlexAccount> Function(String)? accountHandler;
  Future<String?> Function(PlexPin)? pollHandler;
  Future<List<PlexMediaItem>> Function(Uri, String, String, PlexLibraryType)?
  libraryItemsHandler;
  final discoveredTokens = <String>[];
  List<PlexServer> serversResult = const [];
  PlexConnection? connectionResult;
  Future<PlexConnection> Function(PlexServer, String)? selectConnectionHandler;
  Future<String> Function(String, String, String?)? switchHomeUserHandler;
  List<PlexLibrary> librariesResult = const [];
  int pollCalls = 0;
  int cancelPinCalls = 0;
  int librariesCalls = 0;

  @override
  Future<PlexAccount> account(String token) =>
      accountHandler?.call(token) ?? Future.value(accountResult);

  @override
  Future<List<PlexHomeUser>> homeUsers(String accountToken) async =>
      homeUsersResult;

  @override
  Future<String> switchHomeUser(
    String accountToken,
    String userId,
    String? pin,
  ) async {
    final handler = switchHomeUserHandler;
    if (handler != null) return handler(accountToken, userId, pin);
    return 'profile-token';
  }

  @override
  Future<List<PlexServer>> discoverServers(String token) async {
    discoveredTokens.add(token);
    return serversResult;
  }

  @override
  Future<PlexConnection> selectConnection(
    PlexServer server,
    String token,
  ) async {
    final handler = selectConnectionHandler;
    if (handler != null) return handler(server, token);
    return connectionResult ?? server.connections.first;
  }

  @override
  Future<List<PlexLibrary>> libraries(Uri server, String token) async {
    librariesCalls++;
    return librariesResult;
  }

  @override
  Future<PlexPin> createPin() async => pinResult!;

  @override
  Future<String?> pollPin(PlexPin pin) {
    pollCalls++;
    return pollHandler?.call(pin) ?? Future.value();
  }

  @override
  Future<void> cancelPin(PlexPin pin) async {
    cancelPinCalls++;
  }

  @override
  Future<List<PlexMediaItem>> libraryItems(
    Uri server,
    String token,
    String libraryId,
    PlexLibraryType libraryType,
  ) =>
      libraryItemsHandler?.call(server, token, libraryId, libraryType) ??
      Future.value(const []);

  @override
  Future<PlexPlaylistCatalog> playlists(Uri server, String token) async =>
      const PlexPlaylistCatalog(playlists: [], failedIds: {});

  @override
  void close() {}
}
