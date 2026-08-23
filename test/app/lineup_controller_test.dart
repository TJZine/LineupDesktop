import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/channel_builder.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/playback/stream_policy.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

void main() {
  test(
    'artworkForPath uses the active authenticated server transport',
    () async {
      final selected = _server('server');
      final plex = _FakePlex()
        ..serversResult = [selected]
        ..connectionResult = selected.connections.single;
      final controller = LineupController(
        store: _MemoryStore(
          const PersistedState(selectedServerByProfile: {'owner': 'server'}),
        ),
        credentials: _MemoryCredentials(accountToken: 'account-token'),
        plex: plex,
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      final bytes = await controller.artworkForPath(Uri.parse('/show/art'));

      expect(bytes, Uint8List.fromList([1, 2, 3]));
      expect(plex.artworkServer, controller.connection!.uri);
      expect(plex.artworkPath, Uri.parse('/show/art'));
      expect(plex.artworkToken, 'pms-token');
    },
  );

  test('selected-server requests use only the PMS resource token', () async {
    const owner = PlexHomeUser(id: 'owner', name: 'Owner', protected: false);
    const child = PlexHomeUser(id: 'child', name: 'Child', protected: false);
    final selected = _server('server');
    final item = PlexMediaItem(
      id: 'movie',
      key: '/library/metadata/movie',
      title: 'Movie',
      type: 'movie',
      duration: const Duration(minutes: 1),
      libraryId: 'movies',
      partPath: '/library/parts/movie/file.mp4',
      container: 'mp4',
      videoCodec: 'h264',
      audioCodec: 'aac',
      dynamicRange: DynamicRange.sdr,
    );
    final plex = _FakePlex()
      ..resourceToken = 'pms-token-sentinel'
      ..homeUsersResult = const [owner, child]
      ..switchHomeUserHandler = (accountToken, userId, _) async {
        expect(accountToken, 'cloud-token-sentinel');
        expect(userId, 'child');
        return 'home-token-sentinel';
      }
      ..serversResult = [selected]
      ..connectionResult = selected.connections.single
      ..librariesResult = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ]
      ..libraryItemsHandler = (_, _, _, _) async => [item];
    final store = _MemoryStore(
      const PersistedState(selectedServerByProfile: {'child': 'server'}),
    );
    final controller = LineupController(
      store: store,
      credentials: _MemoryCredentials(accountToken: 'cloud-token-sentinel'),
      plex: plex,
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await controller.selectProfile(child);
    controller.diagnostics.enabled = true;
    await controller.setLibraries({'movies'});
    await controller.artworkForPath(Uri.parse('/art'));
    final playback = controller.playbackFor('movie');
    await playback.release();

    expect(plex.accountTokens, ['cloud-token-sentinel']);
    expect(plex.homeUsersTokens, ['cloud-token-sentinel']);
    expect(plex.discoveredTokens, ['home-token-sentinel']);
    expect(plex.selectedTokens, everyElement('pms-token-sentinel'));
    expect(plex.libraryTokens, everyElement('pms-token-sentinel'));
    expect(plex.itemTokens, everyElement('pms-token-sentinel'));
    expect(plex.playlistTokens, everyElement('pms-token-sentinel'));
    expect(plex.artworkToken, 'pms-token-sentinel');
    expect(playback.plexToken, 'pms-token-sentinel');
    expect(plex.releaseTokens, ['pms-token-sentinel']);
    expect(
      [
        ...plex.selectedTokens,
        ...plex.libraryTokens,
        ...plex.itemTokens,
        ...plex.playlistTokens,
        plex.artworkToken,
        playback.plexToken,
        ...plex.releaseTokens,
      ].whereType<String>(),
      everyElement('pms-token-sentinel'),
    );
    expect(controller.servers.single.toString(), isNot(contains('sentinel')));
    expect(store.state.toJson().toString(), isNot(contains('sentinel')));
    final diagnosticSnapshot = [
      for (final entry in controller.diagnostics.entries)
        {
          'area': entry.area,
          'message': entry.message,
          'context': entry.context,
        },
    ];
    expect(diagnosticSnapshot.toString(), isNot(contains('sentinel')));
    expect(
      controller.diagnostics.entries.single.message,
      'Plex playback selected',
    );
    expect(controller.diagnostics.entries.single.context, {
      'mode': 'directPlay',
      'container': 'mp4',
      'videoCodec': 'h264',
      'audioCodec': 'aac',
      'dynamicRange': 'sdr',
    });
  });

  test('concurrent PMS authorization failures coalesce one refresh', () async {
    final selected = _server('server');
    final refresh = Completer<List<PlexServerAccess>>();
    var discoveries = 0;
    final artworkTokens = <String>[];
    final plex = _FakePlex()
      ..serversResult = [selected]
      ..connectionResult = selected.connections.single
      ..discoverServersHandler = (_) {
        discoveries++;
        if (discoveries == 1) {
          return Future.value([
            PlexServerAccess(server: selected, token: 'pms-token-1'),
          ]);
        }
        return refresh.future;
      }
      ..artworkHandler = (_, token, _) async {
        artworkTokens.add(token);
        if (token == 'pms-token-1') {
          throw const PlexException('auth-invalid', 'Expired');
        }
        return Uint8List.fromList([4]);
      };
    final controller = LineupController(
      store: _MemoryStore(
        const PersistedState(selectedServerByProfile: {'owner': 'server'}),
      ),
      credentials: _MemoryCredentials(accountToken: 'cloud-token'),
      plex: plex,
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    final first = controller.artworkForPath(Uri.parse('/one'));
    final second = controller.artworkForPath(Uri.parse('/two'));
    await Future<void>.delayed(Duration.zero);
    expect(discoveries, 2);
    refresh.complete([
      PlexServerAccess(server: selected, token: 'pms-token-2'),
    ]);

    expect(await Future.wait([first, second]), [
      Uint8List.fromList([4]),
      Uint8List.fromList([4]),
    ]);
    expect(discoveries, 2);
    expect(artworkTokens, [
      'pms-token-1',
      'pms-token-1',
      'pms-token-2',
      'pms-token-2',
    ]);
  });

  test(
    'server selection never substitutes the cloud token for missing access',
    () async {
      final plex = _FakePlex();
      final controller = LineupController(
        store: _MemoryStore(),
        credentials: _MemoryCredentials(accountToken: 'cloud-token-sentinel'),
        plex: plex,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      await controller.selectServer(_server('missing'));

      expect(controller.server, isNull);
      expect(controller.error, 'Plex server authorization is unavailable.');
      expect(plex.selectedTokens, isEmpty);
    },
  );

  test(
    'saved server restore fails when discovery has no access record',
    () async {
      final plex = _FakePlex();
      final controller = LineupController(
        store: _MemoryStore(
          const PersistedState(selectedServerByProfile: {'owner': 'missing'}),
        ),
        credentials: _MemoryCredentials(accountToken: 'cloud-token-sentinel'),
        plex: plex,
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.server, isNull);
      expect(controller.connection, isNull);
      expect(controller.stage, SetupStage.servers);
      expect(controller.error, 'Plex server authorization is unavailable.');
      expect(plex.selectedTokens, isEmpty);
    },
  );

  test('PMS authorization retries stop after one refreshed request', () async {
    final selected = _server('server');
    var discoveries = 0;
    var artworkCalls = 0;
    final plex = _FakePlex()
      ..serversResult = [selected]
      ..connectionResult = selected.connections.single
      ..discoverServersHandler = (_) async {
        discoveries++;
        return [
          PlexServerAccess(
            server: selected,
            token: discoveries == 1 ? 'pms-token-1' : 'pms-token-2',
          ),
        ];
      }
      ..artworkHandler = (_, _, _) async {
        artworkCalls++;
        throw const PlexException('auth-invalid', 'Expired');
      };
    final controller = LineupController(
      store: _MemoryStore(
        const PersistedState(selectedServerByProfile: {'owner': 'server'}),
      ),
      credentials: _MemoryCredentials(accountToken: 'cloud-token'),
      plex: plex,
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    await expectLater(
      controller.artworkForPath(Uri.parse('/art')),
      throwsA(isA<PlexException>()),
    );

    expect(discoveries, 2);
    expect(artworkCalls, 2);
  });

  test(
    'logout prevents an in-flight PMS refresh from installing access',
    () async {
      final selected = _server('server');
      final refresh = Completer<List<PlexServerAccess>>();
      var discoveries = 0;
      final plex = _FakePlex()
        ..serversResult = [selected]
        ..connectionResult = selected.connections.single
        ..discoverServersHandler = (_) {
          discoveries++;
          return discoveries == 1
              ? Future.value([
                  PlexServerAccess(server: selected, token: 'pms-token-1'),
                ])
              : refresh.future;
        }
        ..artworkHandler = (_, _, _) async =>
            throw const PlexException('auth-invalid', 'Expired');
      final controller = LineupController(
        store: _MemoryStore(
          const PersistedState(selectedServerByProfile: {'owner': 'server'}),
        ),
        credentials: _MemoryCredentials(accountToken: 'cloud-token'),
        plex: plex,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      final artwork = controller.artworkForPath(Uri.parse('/art'));
      await Future<void>.delayed(Duration.zero);
      expect(await controller.logout(), isTrue);
      refresh.complete([
        PlexServerAccess(server: selected, token: 'pms-token-2'),
      ]);
      await expectLater(artwork, throwsA(isA<PlexException>()));

      expect(controller.server, isNull);
      expect(controller.connection, isNull);
      expect(controller.servers, isEmpty);
    },
  );

  test('profile supersession prevents stale PMS access installation', () async {
    const owner = PlexHomeUser(id: 'owner', name: 'Owner', protected: false);
    const child = PlexHomeUser(id: 'child', name: 'Child', protected: false);
    final ownerServer = _server('owner-server');
    final childServer = _server('child-server');
    final staleRefresh = Completer<List<PlexServerAccess>>();
    var discoveries = 0;
    final artworkTokens = <String>[];
    final plex = _FakePlex()
      ..homeUsersResult = const [owner, child]
      ..discoverServersHandler = (token) {
        discoveries++;
        if (discoveries == 1) {
          return Future.value([
            PlexServerAccess(server: ownerServer, token: 'owner-pms-1'),
          ]);
        }
        if (discoveries == 2) return staleRefresh.future;
        expect(token, 'profile-token');
        return Future.value([
          PlexServerAccess(server: childServer, token: 'child-pms'),
        ]);
      }
      ..artworkHandler = (_, token, _) async {
        artworkTokens.add(token);
        if (token == 'owner-pms-1') {
          throw const PlexException('auth-invalid', 'Expired');
        }
        return Uint8List.fromList([7]);
      };
    final controller = LineupController(
      store: _MemoryStore(
        const PersistedState(
          profileId: 'owner',
          selectedServerByProfile: {'owner': 'owner-server'},
        ),
      ),
      credentials: _MemoryCredentials(accountToken: 'cloud-token'),
      plex: plex,
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    final staleArtwork = controller.artworkForPath(Uri.parse('/old'));
    await Future<void>.delayed(Duration.zero);
    await controller.selectProfile(child);
    await controller.selectServer(childServer);
    staleRefresh.complete([
      PlexServerAccess(server: ownerServer, token: 'owner-pms-2'),
    ]);
    await expectLater(staleArtwork, throwsA(isA<PlexException>()));

    expect(controller.profile, child);
    expect(controller.server?.id, 'child-server');
    expect(controller.connection?.uri, childServer.connections.single.uri);
    expect(await controller.artworkForPath(Uri.parse('/child')), [7]);
    expect(artworkTokens.last, 'child-pms');
  });

  test(
    'server supersession starts an unmatched refresh and rejects stale access',
    () async {
      final first = _server('first');
      final second = _server('second');
      final staleRefresh = Completer<List<PlexServerAccess>>();
      var discoveries = 0;
      final plex = _FakePlex()
        ..discoverServersHandler = (_) {
          discoveries++;
          if (discoveries == 1) {
            return Future.value([
              PlexServerAccess(server: first, token: 'first-pms-1'),
              PlexServerAccess(server: second, token: 'second-pms-1'),
            ]);
          }
          if (discoveries == 2) return staleRefresh.future;
          return Future.value([
            PlexServerAccess(server: first, token: 'first-pms-1'),
            PlexServerAccess(server: second, token: 'second-pms-2'),
          ]);
        }
        ..librariesHandler = (_, token) async {
          if (token == 'second-pms-1') {
            throw const PlexException('auth-invalid', 'Expired');
          }
          return const [];
        }
        ..artworkHandler = (_, token, _) async {
          if (token == 'first-pms-1') {
            throw const PlexException('auth-invalid', 'Expired');
          }
          return Uint8List.fromList([8]);
        };
      final controller = LineupController(
        store: _MemoryStore(
          const PersistedState(selectedServerByProfile: {'owner': 'first'}),
        ),
        credentials: _MemoryCredentials(accountToken: 'cloud-token'),
        plex: plex,
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      final staleArtwork = controller.artworkForPath(Uri.parse('/first'));
      await Future<void>.delayed(Duration.zero);
      await controller.selectServer(second);
      expect(discoveries, 3);
      expect(controller.server?.id, 'second');
      expect(plex.libraryTokens, contains('second-pms-2'));

      staleRefresh.complete([
        PlexServerAccess(server: first, token: 'first-pms-2'),
        PlexServerAccess(server: second, token: 'second-pms-1'),
      ]);
      await expectLater(staleArtwork, throwsA(isA<PlexException>()));

      expect(controller.server?.id, 'second');
      expect(controller.connection?.uri, second.connections.single.uri);
      expect(await controller.artworkForPath(Uri.parse('/second')), [8]);
      expect(plex.artworkToken, 'second-pms-2');
    },
  );

  test('selection cancellation rejects its stale PMS refresh', () async {
    final old = _server('old');
    final next = _server('next');
    final refresh = Completer<List<PlexServerAccess>>();
    var discoveries = 0;
    final plex = _FakePlex()
      ..discoverServersHandler = (_) {
        discoveries++;
        return discoveries == 1
            ? Future.value([
                PlexServerAccess(server: old, token: 'old-pms'),
                PlexServerAccess(server: next, token: 'next-pms-1'),
              ])
            : refresh.future;
      }
      ..selectConnectionHandler = (server, token) async {
        if (server.id == 'next' && token == 'next-pms-1') {
          throw const PlexException('auth-required', 'Expired');
        }
        return server.connections.single;
      };
    final controller = LineupController(
      store: _MemoryStore(
        const PersistedState(selectedServerByProfile: {'owner': 'old'}),
      ),
      credentials: _MemoryCredentials(accountToken: 'cloud-token'),
      plex: plex,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller
      ..stage = SetupStage.ready
      ..showServers();

    final selection = controller.selectServer(next);
    await Future<void>.delayed(Duration.zero);
    expect(discoveries, 2);
    controller.cancelServerSelection();
    refresh.complete([
      PlexServerAccess(server: old, token: 'old-pms'),
      PlexServerAccess(server: next, token: 'next-pms-2'),
    ]);
    await selection;

    expect(controller.server?.id, 'old');
    expect(controller.connection?.uri, old.connections.single.uri);
    await controller.artworkForPath(Uri.parse('/old'));
    expect(plex.artworkToken, 'old-pms');
  });

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
    final selected = _server('server');
    final controller = LineupController(
      store: _MemoryStore(
        const PersistedState(selectedServerByProfile: {'owner': 'server'}),
      ),
      credentials: _MemoryCredentials(accountToken: 'token'),
      plex: _FakePlex()
        ..serversResult = [selected]
        ..connectionResult = selected.connections.single
        ..librariesResult = const [
          PlexLibrary(
            id: 'movies',
            title: 'Movies',
            type: PlexLibraryType.movie,
          ),
        ]
        ..libraryItemsHandler = (_, _, _, _) async =>
            throw const PlexException('offline', 'opaque-secret-sentinel'),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller
      ..stage = SetupStage.channelSetup
      ..diagnostics.enabled = true;

    final loaded = await controller.setLibraries({'movies'});

    expect(loaded, isFalse);
    expect(controller.stage, SetupStage.channelSetup);
    expect(controller.error, 'opaque-secret-sentinel');
    expect(controller.diagnostics.entries.single.message, 'Operation failed');
    expect(controller.diagnostics.entries.single.context, {'code': 'offline'});
    expect(
      '${controller.diagnostics.entries.single.message}'
      '${controller.diagnostics.entries.single.context}',
      isNot(contains('opaque-secret-sentinel')),
    );
  });

  test(
    'playlist diagnostics retain Plex code and bounded failure count',
    () async {
      final selected = _server('server');
      var calls = 0;
      final plex = _FakePlex()
        ..serversResult = [selected]
        ..connectionResult = selected.connections.single
        ..librariesResult = const [
          PlexLibrary(
            id: 'movies',
            title: 'Movies',
            type: PlexLibraryType.movie,
          ),
        ]
        ..playlistsHandler = (_, _) async {
          calls++;
          if (calls == 1) {
            throw const PlexException(
              'playlist-failed',
              'opaque-secret-sentinel',
            );
          }
          return const PlexPlaylistCatalog(
            playlists: [],
            failedIds: {'missing-1', 'missing-2'},
          );
        };
      final controller = LineupController(
        store: _MemoryStore(
          const PersistedState(selectedServerByProfile: {'owner': 'server'}),
        ),
        credentials: _MemoryCredentials(accountToken: 'token'),
        plex: plex,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller
        ..stage = SetupStage.channelSetup
        ..diagnostics.enabled = true;

      expect(await controller.setLibraries({'movies'}), isTrue);
      var entry = controller.diagnostics.entries.single;
      expect(entry.message, 'Playlist discovery unavailable');
      expect(entry.context, {'code': 'playlist-failed'});
      expect(
        '${entry.message}${entry.context}',
        isNot(contains('opaque-secret-sentinel')),
      );

      controller.diagnostics.enabled = false;
      controller.diagnostics.enabled = true;
      expect(await controller.setLibraries({'movies'}), isTrue);
      entry = controller.diagnostics.entries.single;
      expect(entry.message, 'Some playlists could not be loaded');
      expect(entry.context, {'count': 2});
    },
  );

  test('audio persistence failure stays retryable and visible', () async {
    final controller =
        LineupController(
            store: _MemoryStore()
              ..failNextSave = true
              ..failureMessage = 'opaque-secret-sentinel',
            credentials: _MemoryCredentials(),
            plex: _FakePlex(),
          )
          ..stage = SetupStage.audio
          ..diagnostics.enabled = true;
    addTearDown(controller.dispose);

    await controller.completeAudioSetup();

    expect(controller.stage, SetupStage.audio);
    expect(controller.settings.audioSetupComplete, isFalse);
    expect(controller.error, contains('Could not save audio settings'));
    final entry = controller.diagnostics.entries.single;
    expect(entry.message, 'Audio setup persistence failed');
    expect(entry.context, {'code': 'unexpected'});
    expect(
      '${entry.message}${entry.context}',
      isNot(contains('opaque-secret-sentinel')),
    );
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

  test('PIN polling diagnostics retain only the Plex failure code', () async {
    final plex = _FakePlex()
      ..pinResult = PlexPin(
        id: 6,
        code: 'EFGH',
        expiresAt: DateTime.now().add(const Duration(minutes: 1)),
      )
      ..pollHandler = (_) async =>
          throw const PlexException('poll-failed', 'opaque-secret-sentinel');
    final controller = LineupController(
      store: _MemoryStore(),
      credentials: _MemoryCredentials(),
      plex: plex,
      pinPollInterval: const Duration(milliseconds: 1),
    )..diagnostics.enabled = true;
    addTearDown(controller.dispose);

    await controller.startLinking();
    while (controller.diagnostics.entries.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await controller.cancelLinking();

    for (final entry in controller.diagnostics.entries) {
      expect(entry.message, 'PIN poll failed');
      expect(entry.context, {'code': 'poll-failed'});
      expect(
        '${entry.message}${entry.context}',
        isNot(contains('opaque-secret-sentinel')),
      );
    }
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

  test(
    'failed settings settles before a queued channel transaction derives',
    () async {
      final store = _ControlledSaveStore();
      final selected = _server('server');
      final controller = LineupController(
        store: store,
        credentials: _MemoryCredentials(),
        plex: _FakePlex(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller
        ..account = const PlexAccount(id: 'owner', name: 'Owner', email: '')
        ..server = selected
        ..connection = selected.connections.single;
      store.blockNext(fail: true);

      final settings = controller.updateSettings(
        const LineupSettings(diagnosticsEnabled: true),
      );
      await store.blockedSaveStarted.future;
      final channel = controller.saveChannel(_channel('queued'));
      await Future<void>.delayed(Duration.zero);

      expect(controller.channels, isEmpty);
      store.releaseBlockedSave();
      await expectLater(settings, throwsStateError);
      await channel;

      expect(controller.settings.diagnosticsEnabled, isFalse);
      expect(controller.channels.single.id, 'queued');
      expect(store.state.settings.diagnosticsEnabled, isFalse);
      expect(
        store.state.channelsByProfileServer['owner']!['server']!.single.id,
        'queued',
      );
    },
  );

  test('failed channel settles before queued settings derives', () async {
    final store = _ControlledSaveStore();
    final selected = _server('server');
    final existing = _channel('existing');
    final controller = LineupController(
      store: store,
      credentials: _MemoryCredentials(),
      plex: _FakePlex(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller
      ..account = const PlexAccount(id: 'owner', name: 'Owner', email: '')
      ..server = selected
      ..connection = selected.connections.single
      ..channels = [existing]
      ..currentChannelId = existing.id;
    store.blockNext(fail: true);

    final channel = controller.deleteChannel(existing.id);
    await store.blockedSaveStarted.future;
    final settings = controller.updateSettings(
      const LineupSettings(nowWatchingBanner: false),
    );
    store.releaseBlockedSave();

    await expectLater(channel, throwsStateError);
    await settings;
    expect(controller.channels, [existing]);
    expect(controller.currentChannelId, existing.id);
    expect(controller.settings.nowWatchingBanner, isFalse);
    expect(store.state.settings.nowWatchingBanner, isFalse);
    expect(store.state.channelsByProfileServer['owner']!['server'], [existing]);
  });

  test(
    'failed settings settles before a queued current-channel mutation',
    () async {
      final store = _ControlledSaveStore();
      final selected = _server('server');
      final first = _channel('first');
      final second = Channel(
        id: 'second',
        number: 2,
        name: 'Second channel',
        source: first.source,
        playbackMode: first.playbackMode,
        anchor: first.anchor,
        shuffleSeed: first.shuffleSeed,
      );
      final controller = LineupController(
        store: store,
        credentials: _MemoryCredentials(),
        plex: _FakePlex(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller
        ..account = const PlexAccount(id: 'owner', name: 'Owner', email: '')
        ..server = selected
        ..channels = [first, second]
        ..currentChannelId = first.id;
      store.blockNext(fail: true);

      final settings = controller.updateSettings(
        const LineupSettings(diagnosticsEnabled: true),
      );
      await store.blockedSaveStarted.future;
      final current = controller.setCurrentChannel(second.id);
      await Future<void>.delayed(Duration.zero);

      expect(controller.currentChannelId, first.id);
      store.releaseBlockedSave();
      await expectLater(settings, throwsStateError);
      await current;
      expect(controller.settings.diagnosticsEnabled, isFalse);
      expect(controller.currentChannelId, second.id);
      expect(
        store.state.currentChannelByProfileServer['owner']!['server'],
        second.id,
      );
    },
  );

  test(
    'failed settings settles before a queued library transaction applies',
    () async {
      final selected = _server('server');
      final store = _ControlledSaveStore(
        const PersistedState(selectedServerByProfile: {'owner': 'server'}),
      );
      final plex = _FakePlex()
        ..homeUsersResult = const [
          PlexHomeUser(id: 'owner', name: 'Owner', protected: false),
        ]
        ..serversResult = [selected]
        ..connectionResult = selected.connections.single
        ..librariesResult = const [
          PlexLibrary(
            id: 'movies',
            title: 'Movies',
            type: PlexLibraryType.movie,
          ),
        ];
      final controller = LineupController(
        store: store,
        credentials: _MemoryCredentials(accountToken: 'account-token'),
        plex: plex,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      store.blockNext(fail: true);

      final settings = controller.updateSettings(
        const LineupSettings(diagnosticsEnabled: true),
      );
      await store.blockedSaveStarted.future;
      final libraries = controller.setLibraries({'movies'});
      await Future<void>.delayed(Duration.zero);
      store.releaseBlockedSave();

      await expectLater(settings, throwsStateError);
      expect(await libraries, isTrue);
      expect(controller.settings.diagnosticsEnabled, isFalse);
      expect(controller.selectedLibraryIds, {'movies'});
      expect(store.state.settings.diagnosticsEnabled, isFalse);
      expect(
        store.state.selectedLibraryIdsByProfileServer['owner']!['server'],
        ['movies'],
      );
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

  test('profile scope apply waits for an older state transaction', () async {
    const owner = PlexHomeUser(id: 'owner', name: 'Owner', protected: false);
    const child = PlexHomeUser(id: 'child', name: 'Child', protected: false);
    final store = _ControlledSaveStore();
    final controller = LineupController(
      store: store,
      credentials: _MemoryCredentials(accountToken: 'account-token'),
      plex: _FakePlex()..homeUsersResult = const [owner, child],
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller
      ..profile = owner
      ..stage = SetupStage.ready;
    store.blockNext();

    final settings = controller.updateSettings(
      const LineupSettings(nowWatchingBanner: false),
    );
    await store.blockedSaveStarted.future;
    final selection = controller.selectProfile(child);
    await Future<void>.delayed(Duration.zero);

    expect(controller.profile, owner);
    store.releaseBlockedSave();
    await settings;
    await selection;

    expect(controller.profile, child);
    expect(store.savedStates[store.savedStates.length - 2].profileId, owner.id);
    expect(store.savedStates.last.profileId, child.id);
  });

  test('server scope apply waits for an older state transaction', () async {
    final oldServer = _server('old');
    final nextServer = _server('next');
    final store = _ControlledSaveStore(
      const PersistedState(selectedServerByProfile: {'owner': 'old'}),
    );
    final plex = _FakePlex()
      ..homeUsersResult = const [
        PlexHomeUser(id: 'owner', name: 'Owner', protected: false),
      ]
      ..serversResult = [oldServer, nextServer]
      ..librariesResult = const [];
    final controller = LineupController(
      store: store,
      credentials: _MemoryCredentials(accountToken: 'account-token'),
      plex: plex,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.stage = SetupStage.ready;
    store.blockNext();

    final settings = controller.updateSettings(
      const LineupSettings(nowWatchingBanner: false),
    );
    await store.blockedSaveStarted.future;
    final selection = controller.selectServer(nextServer);
    await Future<void>.delayed(Duration.zero);

    expect(controller.server?.id, oldServer.id);
    store.releaseBlockedSave();
    await settings;
    await selection;

    expect(controller.server?.id, nextServer.id);
    expect(
      store.savedStates[store.savedStates.length - 2].selectedServerByProfile,
      {'owner': oldServer.id},
    );
    expect(store.savedStates.last.selectedServerByProfile, {
      'owner': nextServer.id,
    });
  });

  test(
    'target authorization refresh waits for queued server scope apply',
    () async {
      final oldServer = _server('old');
      final nextServer = _server('next');
      final refreshedNext = PlexConnection(
        uri: Uri.parse('https://next-refreshed.example:32400'),
        local: true,
        relay: false,
        latency: const Duration(milliseconds: 8),
      );
      final targetLibrariesRequested = Completer<void>();
      var discoveries = 0;
      final store = _ControlledSaveStore(
        const PersistedState(selectedServerByProfile: {'owner': 'old'}),
      );
      final plex = _FakePlex()
        ..homeUsersResult = const [
          PlexHomeUser(id: 'owner', name: 'Owner', protected: false),
        ]
        ..serversResult = [oldServer, nextServer]
        ..discoverServersHandler = (_) async {
          discoveries++;
          return [
            PlexServerAccess(
              server: oldServer,
              token: discoveries == 1 ? 'old-token-1' : 'old-token-2',
            ),
            PlexServerAccess(
              server: nextServer,
              token: discoveries == 1 ? 'next-token-1' : 'next-token-2',
            ),
          ];
        }
        ..selectConnectionHandler = (selected, token) async {
          if (selected.id == nextServer.id && token == 'next-token-1') {
            throw const PlexException('auth-invalid', 'Expired');
          }
          if (selected.id == nextServer.id) return refreshedNext;
          return oldServer.connections.single;
        }
        ..librariesHandler = (_, token) async {
          if (token == 'next-token-2' &&
              !targetLibrariesRequested.isCompleted) {
            targetLibrariesRequested.complete();
          }
          return const [];
        };
      final controller = LineupController(
        store: store,
        credentials: _MemoryCredentials(accountToken: 'account-token'),
        plex: plex,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller.stage = SetupStage.ready;
      store.blockNext();

      final settings = controller.updateSettings(
        const LineupSettings(nowWatchingBanner: false),
      );
      await store.blockedSaveStarted.future;
      final selection = controller.selectServer(nextServer);
      await targetLibrariesRequested.future;

      expect(discoveries, 2);
      expect(controller.server?.id, oldServer.id);
      expect(controller.connection, oldServer.connections.single);
      await controller.artworkForPath(Uri.parse('/old-art'));
      expect(plex.artworkServer, oldServer.connections.single.uri);
      expect(plex.artworkToken, 'old-token-2');

      store.releaseBlockedSave();
      await settings;
      await selection;

      expect(controller.server?.id, nextServer.id);
      expect(controller.connection, refreshedNext);
      await controller.artworkForPath(Uri.parse('/next-art'));
      expect(plex.artworkServer, refreshedNext.uri);
      expect(plex.artworkToken, 'next-token-2');
    },
  );

  test(
    'failed old transaction rolls back while profile network later fails',
    () async {
      const owner = PlexHomeUser(id: 'owner', name: 'Owner', protected: false);
      const child = PlexHomeUser(id: 'child', name: 'Child', protected: false);
      final switched = Completer<String>();
      final store = _ControlledSaveStore();
      final controller = LineupController(
        store: store,
        credentials: _MemoryCredentials(accountToken: 'account-token'),
        plex: _FakePlex()
          ..homeUsersResult = const [owner, child]
          ..switchHomeUserHandler = (_, _, _) => switched.future,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller
        ..profile = owner
        ..stage = SetupStage.ready;
      store.blockNext(fail: true);

      final settings = controller.updateSettings(
        const LineupSettings(diagnosticsEnabled: true),
      );
      await store.blockedSaveStarted.future;
      final selection = controller.selectProfile(child);
      switched.completeError(StateError('switch failed'));
      await selection;
      store.releaseBlockedSave();

      await expectLater(settings, throwsStateError);
      expect(controller.settings.diagnosticsEnabled, isFalse);
      expect(controller.profile, owner);
    },
  );

  test(
    'logout waits for an applied state transaction before clearing',
    () async {
      final store = _ControlledSaveStore();
      final controller = LineupController(
        store: store,
        credentials: _MemoryCredentials(accountToken: 'account-token'),
        plex: _FakePlex(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller
        ..account = const PlexAccount(id: 'owner', name: 'Owner', email: '')
        ..stage = SetupStage.ready;
      store.blockNext();

      final settings = controller.updateSettings(
        const LineupSettings(nowWatchingBanner: false),
      );
      await store.blockedSaveStarted.future;
      final logout = controller.logout();
      await Future<void>.delayed(Duration.zero);

      expect(controller.account?.id, 'owner');
      store.releaseBlockedSave();
      await settings;
      expect(await logout, isTrue);
      expect(store.state.settings.nowWatchingBanner, isFalse);
      expect(controller.account, isNull);
      expect(controller.stage, SetupStage.welcome);
    },
  );

  test('queued stale mutation never calls store save', () async {
    final store = _ControlledSaveStore();
    final selected = _server('server');
    final controller = LineupController(
      store: store,
      credentials: _MemoryCredentials(accountToken: 'account-token'),
      plex: _FakePlex(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller
      ..account = const PlexAccount(id: 'owner', name: 'Owner', email: '')
      ..server = selected
      ..channels = const []
      ..stage = SetupStage.ready;
    var stalePublished = false;
    controller.addListener(() {
      stalePublished |= controller.channels.any(
        (channel) => channel.id == 'stale',
      );
    });
    store.blockNext();

    final settings = controller.updateSettings(
      const LineupSettings(nowWatchingBanner: false),
    );
    await store.blockedSaveStarted.future;
    final stale = controller.saveChannel(_channel('stale'));
    final logout = controller.logout();
    store.releaseBlockedSave();

    await settings;
    await stale;
    expect(await logout, isTrue);
    expect(store.saveCalls, 1);
    expect(store.state.channelsByProfileServer['owner']!['server'], isEmpty);
    expect(controller.channels, isEmpty);
    expect(stalePublished, isFalse);
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
        ..pollHandler = (_) async {
          return 'late-token';
        }
        ..cancelPinFailure = const PlexException(
          'cancel-failed',
          'opaque-secret-sentinel',
        );
      final controller = LineupController(
        store: _MemoryStore(),
        credentials: credentials,
        plex: plex,
        pinPollInterval: const Duration(milliseconds: 1),
      );
      controller.diagnostics.enabled = true;
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
      expect(controller.diagnostics.entries.map((entry) => entry.message), [
        'Credential cleanup failed',
        'PIN cancellation failed',
      ]);
      expect(controller.diagnostics.entries.map((entry) => entry.context), [
        {'code': 'unexpected'},
        {'code': 'cancel-failed'},
      ]);
      expect(
        controller.diagnostics.entries
            .map((entry) => '${entry.message}${entry.context}')
            .join(),
        isNot(contains('opaque-secret-sentinel')),
      );

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
            ..account = const PlexAccount(id: 'owner', name: 'Owner', email: '')
            ..diagnostics.enabled = true;
      addTearDown(controller.dispose);

      expect(await controller.logout(), isFalse);

      expect(controller.stage, SetupStage.ready);
      expect(controller.account?.id, 'owner');
      expect(controller.error, contains('securely sign out'));
      expect(controller.error, isNot(contains('opaque-secret-sentinel')));
      expect(
        controller.diagnostics.entries.single.message,
        'Credential cleanup failed',
      );
      expect(controller.diagnostics.entries.single.context, {
        'code': 'unexpected',
      });
      expect(
        '${controller.diagnostics.entries.single.message}'
        '${controller.diagnostics.entries.single.context}',
        isNot(contains('opaque-secret-sentinel')),
      );
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
      ..serversResult = [nextServer]
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
      plex: _FakePlex()
        ..serversResult = [nextServer]
        ..connectionResult = nextServer.connections.single,
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

  test('a failed settings transaction settles before the next value', () async {
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
    final newer = controller.updateSettings(
      const LineupSettings(nowWatchingBanner: false),
    );
    store.failFirstSave.complete();
    await expectLater(stale, throwsStateError);
    await newer;

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
  String failureMessage = 'save failed';

  @override
  Future<String> clientIdentifier() async =>
      'lineup-desktop-test-abcdefghijklmnopqrst';

  @override
  Future<PersistedState> load() async => state;

  @override
  Future<void> save(PersistedState value) async {
    if (failNextSave) {
      failNextSave = false;
      throw StateError(failureMessage);
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
    if (clearCalls == 1) throw StateError('opaque-secret-sentinel');
    await super.clear();
  }
}

class _BlockingFailOnceClearCredentials extends _BlockingCredentials
    with _FailOnceClear {}

class _FailingClearCredentials extends _MemoryCredentials {
  _FailingClearCredentials({super.accountToken});

  @override
  Future<void> clear() async {
    throw StateError('opaque-secret-sentinel');
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

class _ControlledSaveStore extends _MemoryStore {
  _ControlledSaveStore([super.state]);

  Completer<void> blockedSaveStarted = Completer<void>();
  Completer<void> _release = Completer<void>();
  final List<PersistedState> savedStates = [];
  var saveCalls = 0;
  var _blocked = false;
  var _fail = false;

  void blockNext({bool fail = false}) {
    assert(!_blocked);
    blockedSaveStarted = Completer<void>();
    _release = Completer<void>();
    _blocked = true;
    _fail = fail;
  }

  void releaseBlockedSave() => _release.complete();

  @override
  Future<void> save(PersistedState value) async {
    saveCalls++;
    if (_blocked) {
      blockedSaveStarted.complete();
      await _release.future;
      final fail = _fail;
      _blocked = false;
      _fail = false;
      if (fail) throw StateError('save failed');
    }
    await super.save(value);
    savedStates.add(value);
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
  Future<List<PlexLibrary>> Function(Uri, String)? librariesHandler;
  Future<PlexPlaylistCatalog> Function(Uri, String)? playlistsHandler;
  Future<List<PlexServerAccess>> Function(String)? discoverServersHandler;
  Future<Uint8List> Function(Uri, String, Uri)? artworkHandler;
  final discoveredTokens = <String>[];
  final accountTokens = <String>[];
  final homeUsersTokens = <String>[];
  final selectedTokens = <String>[];
  final libraryTokens = <String>[];
  final itemTokens = <String>[];
  final playlistTokens = <String>[];
  final releaseTokens = <String>[];
  List<PlexServer> serversResult = const [];
  String resourceToken = 'pms-token';
  PlexConnection? connectionResult;
  Future<PlexConnection> Function(PlexServer, String)? selectConnectionHandler;
  Future<String> Function(String, String, String?)? switchHomeUserHandler;
  List<PlexLibrary> librariesResult = const [];
  int pollCalls = 0;
  int cancelPinCalls = 0;
  Object? cancelPinFailure;
  int librariesCalls = 0;
  Uri? artworkServer;
  Uri? artworkPath;
  String? artworkToken;

  @override
  Future<PlexAccount> account(String token) {
    accountTokens.add(token);
    return accountHandler?.call(token) ?? Future.value(accountResult);
  }

  @override
  Future<List<PlexHomeUser>> homeUsers(String accountToken) async {
    homeUsersTokens.add(accountToken);
    return homeUsersResult;
  }

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
  Future<List<PlexServerAccess>> discoverServers(String token) async {
    discoveredTokens.add(token);
    final handler = discoverServersHandler;
    if (handler != null) return handler(token);
    return [
      for (final server in serversResult)
        PlexServerAccess(server: server, token: resourceToken),
    ];
  }

  @override
  Future<PlexConnection> selectConnection(
    PlexServer server,
    String token,
  ) async {
    selectedTokens.add(token);
    final handler = selectConnectionHandler;
    if (handler != null) return handler(server, token);
    return connectionResult ?? server.connections.first;
  }

  @override
  Future<List<PlexLibrary>> libraries(Uri server, String token) async {
    librariesCalls++;
    libraryTokens.add(token);
    return librariesHandler?.call(server, token) ?? librariesResult;
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
    final failure = cancelPinFailure;
    cancelPinFailure = null;
    if (failure != null) throw failure;
  }

  @override
  Future<List<PlexMediaItem>> libraryItems(
    Uri server,
    String token,
    String libraryId,
    PlexLibraryType libraryType,
  ) async {
    itemTokens.add(token);
    return await libraryItemsHandler?.call(
          server,
          token,
          libraryId,
          libraryType,
        ) ??
        const [];
  }

  @override
  Future<PlexPlaylistCatalog> playlists(Uri server, String token) async {
    playlistTokens.add(token);
    return playlistsHandler?.call(server, token) ??
        const PlexPlaylistCatalog(playlists: [], failedIds: {});
  }

  @override
  Future<Uint8List> artwork(
    Uri server,
    String token,
    Uri path, {
    int maximumBytes = 4 * 1024 * 1024,
  }) async {
    artworkServer = server;
    artworkPath = path;
    artworkToken = token;
    final handler = artworkHandler;
    if (handler != null) return handler(server, token, path);
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> releasePlaybackSession({
    required Uri server,
    required String token,
    required String sessionId,
  }) async {
    releaseTokens.add(token);
  }

  @override
  void close() {}
}
