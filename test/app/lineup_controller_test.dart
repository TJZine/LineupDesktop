import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

void main() {
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

    await controller.completeAudioSetup(
      externalAudio: true,
      directPlayFallback: true,
    );

    expect(controller.stage, SetupStage.audio);
    expect(controller.settings.audioSetupComplete, isFalse);
    expect(controller.error, contains('Could not save audio settings'));
  });

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
}

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
  int pollCalls = 0;

  @override
  Future<PlexAccount> account(String token) =>
      accountHandler?.call(token) ?? Future.value(accountResult);

  @override
  Future<List<PlexHomeUser>> homeUsers(String accountToken) async =>
      homeUsersResult;

  @override
  Future<List<PlexServer>> discoverServers(String token) async {
    discoveredTokens.add(token);
    return const [];
  }

  @override
  Future<PlexPin> createPin() async => pinResult!;

  @override
  Future<String?> pollPin(PlexPin pin) {
    pollCalls++;
    return pollHandler?.call(pin) ?? Future.value();
  }

  @override
  Future<void> cancelPin(PlexPin pin) async {}

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
  Future<List<PlexPlaylist>> playlists(Uri server, String token) async =>
      const [];

  @override
  void close() {}
}
