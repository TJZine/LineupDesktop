import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/channel_builder.dart';
import 'package:lineup_desktop/channels/content_resolver.dart';
import 'package:lineup_desktop/channels/schedule_worker.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

Matcher _throwsScheduleFailure(ScheduleFailureReason reason) => throwsA(
  isA<ScheduleBuildException>().having(
    (error) => error.reason,
    'reason',
    reason,
  ),
);

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
      title: 'Movie',
      type: 'movie',
      duration: const Duration(minutes: 1),
      libraryId: 'movies',
      parts: [
        PlexMediaPart(
          path: '/library/parts/movie/one.mp4',
          duration: Duration(seconds: 30),
        ),
        PlexMediaPart(path: '/library/parts/movie/two.mp4'),
      ],
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
    plex.playbackDescriptorResult = [
      (
        uri: Uri.parse('https://plex.example/one.mp4'),
        duration: const Duration(seconds: 30),
      ),
      (uri: Uri.parse('https://plex.example/two.mp4'), duration: null),
    ];
    final playback = controller.playbackFor('movie');

    expect(plex.accountTokens, ['cloud-token-sentinel']);
    expect(plex.homeUsersTokens, ['cloud-token-sentinel']);
    expect(plex.discoveredTokens, ['home-token-sentinel']);
    expect(plex.selectedTokens, everyElement('pms-token-sentinel'));
    expect(plex.libraryTokens, everyElement('pms-token-sentinel'));
    expect(plex.itemTokens, everyElement('pms-token-sentinel'));
    expect(plex.playlistTokens, everyElement('pms-token-sentinel'));
    expect(plex.artworkToken, 'pms-token-sentinel');
    expect(playback.plexToken, 'pms-token-sentinel');
    expect(playback.parts.map((part) => part.uri), [
      Uri.parse('https://plex.example/one.mp4'),
      Uri.parse('https://plex.example/two.mp4'),
    ]);
    expect(
      [
        ...plex.selectedTokens,
        ...plex.libraryTokens,
        ...plex.itemTokens,
        ...plex.playlistTokens,
        plex.artworkToken,
        playback.plexToken,
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

  test('late old-token failure reuses refreshed PMS access', () async {
    final initialServer = _server('server');
    final refreshedConnection = PlexConnection(
      uri: Uri.parse('https://refreshed.example:32400'),
      local: true,
      relay: false,
    );
    final refreshedServer = PlexServer(
      id: initialServer.id,
      name: initialServer.name,
      owned: initialServer.owned,
      connections: [refreshedConnection],
    );
    final firstFailure = Completer<Uint8List>();
    final lateFailure = Completer<Uint8List>();
    final artworkRequests = <(Uri, String, Uri)>[];
    var discoveries = 0;
    final plex = _FakePlex()
      ..discoverServersHandler = (_) async {
        discoveries++;
        return [
          PlexServerAccess(
            server: discoveries == 1 ? initialServer : refreshedServer,
            token: discoveries == 1 ? 'pms-token-1' : 'pms-token-2',
          ),
        ];
      }
      ..selectConnectionHandler = (server, _) async {
        return server.connections.single;
      }
      ..artworkHandler = (server, token, path) {
        artworkRequests.add((server, token, path));
        if (token == 'pms-token-1') {
          return path.path == '/first'
              ? firstFailure.future
              : lateFailure.future;
        }
        return Future.value(Uint8List.fromList([4]));
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

    final first = controller.artworkForPath(Uri.parse('/first'));
    final second = controller.artworkForPath(Uri.parse('/second'));
    await Future<void>.delayed(Duration.zero);
    firstFailure.completeError(const PlexException('auth-invalid', 'Expired'));
    expect(await first, Uint8List.fromList([4]));

    lateFailure.completeError(const PlexException('auth-invalid', 'Expired'));
    expect(await second, Uint8List.fromList([4]));

    expect(discoveries, 2);
    expect(plex.selectedTokens, ['pms-token-1', 'pms-token-2']);
    expect(artworkRequests, [
      (
        initialServer.connections.single.uri,
        'pms-token-1',
        Uri.parse('/first'),
      ),
      (
        initialServer.connections.single.uri,
        'pms-token-1',
        Uri.parse('/second'),
      ),
      (refreshedConnection.uri, 'pms-token-2', Uri.parse('/first')),
      (refreshedConnection.uri, 'pms-token-2', Uri.parse('/second')),
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
    final tokenOnly = LineupPlaybackRequest.parts([
      LineupPlaybackPart(
        uri: Uri.parse(
          'https://user@plex.example:32400/video%2Fpart?X-Plex-Token=secret#section%2Fone',
        ),
      ),
    ]);
    final mixed = LineupPlaybackRequest.parts([
      LineupPlaybackPart(
        uri: Uri.parse(
          'https://plex.example/video?quality=original&X-Plex-Token=secret&quality=mobile#part',
        ),
      ),
    ]);

    expect(
      tokenOnly.parts.single.uri,
      Uri.parse('https://user@plex.example:32400/video%2Fpart#section%2Fone'),
    );
    expect(tokenOnly.parts.single.uri.hasQuery, isFalse);
    expect(mixed.parts.single.uri.fragment, 'part');
    expect(mixed.parts.single.uri.queryParametersAll, {
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
      controller
        ..stage = SetupStage.channelSetup
        ..connection = _server('server').connections.single
        ..availableMedia = [_playableMovie];
      final planned = List<Channel>.unmodifiable([
        _generatedChannel('planned', 1),
      ]);

      await controller.applyChannelPlan(
        planned,
        mode: ChannelBuildMode.replace,
      );

      expect(controller.channels.single.id, 'planned');
      expect(controller.stage, SetupStage.channelSetup);

      controller.completeChannelSetup();

      expect(controller.stage, SetupStage.ready);
    },
  );

  test('every build mode preserves custom channels exactly', () async {
    final custom = _channel('custom');
    final customJson = jsonEncode(custom.toJson());

    for (final mode in ChannelBuildMode.values) {
      final controller = LineupController(
        store: _MemoryStore(),
        credentials: _MemoryCredentials(),
        plex: _FakePlex(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller
        ..connection = _server('server').connections.single
        ..availableMedia = [_playableMovie]
        ..channels = [custom, _generatedChannel('old', 2)]
        ..currentChannelId = custom.id;

      await controller.applyChannelPlan([
        _generatedChannel('planned', 3),
      ], mode: mode);

      expect(
        jsonEncode(
          controller.channels
              .singleWhere((channel) => channel.id == custom.id)
              .toJson(),
        ),
        customJson,
        reason: mode.name,
      );
      expect(controller.currentChannelId, custom.id, reason: mode.name);
    }
  });

  test('replace falls back near a removed generated current channel', () async {
    final custom = _channel('custom');
    final removed = _generatedChannel('removed', 2);
    final replacement = _generatedChannel('replacement', 3);
    final controller = LineupController(
      store: _MemoryStore(),
      credentials: _MemoryCredentials(),
      plex: _FakePlex(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller
      ..connection = _server('server').connections.single
      ..availableMedia = [_playableMovie]
      ..channels = [custom, removed]
      ..currentChannelId = removed.id;

    await controller.applyChannelPlan([
      replacement,
    ], mode: ChannelBuildMode.replace);

    expect(controller.channels, [custom, replacement]);
    expect(controller.currentChannelId, replacement.id);
  });

  test(
    'refresh retains unmatched channels and replaces generated matches',
    () async {
      final custom = _channel('custom');
      final matched = _generatedChannel('matched', 2, builderKey: 'match');
      final unmatched = _generatedChannel('unmatched', 3);
      final replacement = Channel(
        id: matched.id,
        number: matched.number,
        name: matched.name,
        source: const LibrarySource(
          libraryId: 'movies',
          libraryType: PlexLibraryType.movie,
        ),
        playbackMode: PlaybackMode.shuffle,
        anchor: matched.anchor,
        shuffleSeed: matched.shuffleSeed,
        builderKey: matched.builderKey,
      );
      final controller = LineupController(
        store: _MemoryStore(),
        credentials: _MemoryCredentials(),
        plex: _FakePlex(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller
        ..connection = _server('server').connections.single
        ..availableMedia = [_playableMovie]
        ..channels = [custom, matched, unmatched];

      await controller.applyChannelPlan([
        replacement,
      ], mode: ChannelBuildMode.merge);

      expect(
        controller.channels,
        containsAll([custom, unmatched, replacement]),
      );
      expect(controller.channels, hasLength(3));
    },
  );

  test('invalid generated plans do not write or change state', () async {
    final store = _CountingMemoryStore();
    final custom = _channel('custom');
    final generated = _generatedChannel('generated', 2);
    final controller = LineupController(
      store: store,
      credentials: _MemoryCredentials(),
      plex: _FakePlex(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller
      ..connection = _server('server').connections.single
      ..availableMedia = [_playableMovie]
      ..channels = [custom, generated]
      ..currentChannelId = generated.id;

    await expectLater(
      controller.applyChannelPlan([
        _channel('unowned'),
      ], mode: ChannelBuildMode.replace),
      throwsFormatException,
    );
    expect(controller.channels, [custom, generated]);
    expect(controller.currentChannelId, generated.id);
    expect(store.saveCalls, 0);

    await expectLater(
      controller.applyChannelPlan([
        _generatedChannel('conflict', custom.number),
      ], mode: ChannelBuildMode.append),
      throwsFormatException,
    );
    expect(controller.channels, [custom, generated]);
    expect(controller.currentChannelId, generated.id);
    expect(store.saveCalls, 0);
  });

  test(
    'descriptor-invalid generated plans preserve lineup in every build mode',
    () async {
      for (final mode in ChannelBuildMode.values) {
        final store = _CountingMemoryStore();
        final custom = _channel('custom');
        final generated = _generatedChannel('generated', 2);
        final original = [custom, generated];
        final controller = LineupController(
          store: store,
          credentials: _MemoryCredentials(),
          plex: _FakePlex(),
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        controller
          ..connection = _server('server').connections.single
          ..availablePlaylists = const [
            PlexPlaylist(
              id: 'invalid',
              title: 'Invalid',
              items: [
                PlexMediaItem(
                  id: 'no-parts',
                  title: 'No parts',
                  type: 'movie',
                  duration: Duration(minutes: 1),
                ),
              ],
            ),
          ]
          ..channels = original
          ..currentChannelId = generated.id;
        final planned = Channel(
          id: 'planned-${mode.name}',
          number: 3,
          name: 'Invalid generated channel',
          source: const PlaylistSource('invalid'),
          playbackMode: PlaybackMode.sequential,
          anchor: DateTime.utc(2026),
          shuffleSeed: 3,
          builderKey: 'invalid-${mode.name}',
        );

        await expectLater(
          controller.applyChannelPlan([planned], mode: mode),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'Channel source has no playable content',
            ),
          ),
        );

        expect(controller.channels, same(original), reason: mode.name);
        expect(controller.currentChannelId, generated.id, reason: mode.name);
        expect(store.saveCalls, 0, reason: mode.name);
      }
    },
  );

  test(
    'unavailable generated manual recipes preserve lineup in every build mode',
    () async {
      const unavailable = ChannelItem(
        id: 'unavailable',
        title: 'Unavailable',
        duration: Duration(minutes: 30),
      );
      final recipes = <({String name, ContentSource source})>[
        (name: 'manual', source: const ManualSource([unavailable])),
        (
          name: 'nested manual',
          source: const MixedSource(
            sources: [
              MixedSource(
                sources: [
                  ManualSource([unavailable]),
                ],
              ),
            ],
          ),
        ),
      ];
      for (final recipe in recipes) {
        for (final mode in ChannelBuildMode.values) {
          final store = _CountingMemoryStore();
          final custom = _channel('custom');
          final generated = _generatedChannel('generated', 2);
          final original = [custom, generated];
          final controller = LineupController(
            store: store,
            credentials: _MemoryCredentials(),
            plex: _FakePlex(),
          );
          addTearDown(controller.dispose);
          await controller.initialize();
          controller
            ..connection = _server('server').connections.single
            ..availableMedia = [_playableMovie]
            ..channels = original
            ..currentChannelId = generated.id;
          final planned = Channel(
            id: 'planned-${recipe.name}-${mode.name}',
            number: 3,
            name: 'Unavailable generated channel',
            source: recipe.source,
            playbackMode: PlaybackMode.sequential,
            anchor: DateTime.utc(2026),
            shuffleSeed: 3,
            builderKey: 'unavailable-${recipe.name}-${mode.name}',
          );

          await expectLater(
            controller.applyChannelPlan([planned], mode: mode),
            throwsA(
              isA<FormatException>().having(
                (error) => error.message,
                'message',
                'Channel source has no playable content',
              ),
            ),
          );

          expect(controller.channels, same(original), reason: recipe.name);
          expect(
            controller.currentChannelId,
            generated.id,
            reason: recipe.name,
          );
          expect(store.saveCalls, 0, reason: recipe.name);
        }
      }
    },
  );

  test(
    'failed generated plan persistence rolls back lineup and current channel',
    () async {
      final store = _MemoryStore()..failNextSave = true;
      final custom = _channel('custom');
      final generated = _generatedChannel('generated', 2);
      final controller = LineupController(
        store: store,
        credentials: _MemoryCredentials(),
        plex: _FakePlex(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller
        ..connection = _server('server').connections.single
        ..availableMedia = [_playableMovie]
        ..channels = [custom, generated]
        ..currentChannelId = generated.id;

      await expectLater(
        controller.applyChannelPlan([
          _generatedChannel('replacement', 2),
        ], mode: ChannelBuildMode.replace),
        throwsStateError,
      );

      expect(controller.channels, [custom, generated]);
      expect(controller.currentChannelId, generated.id);
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

  test('library scans bound concurrency and publish inventory-ordered exact progress', () async {
    final selected = _server('server');
    var active = 0;
    var peak = 0;
    var requests = 0;
    final perLibrary = <String, int>{};
    final plex = _FakePlex()
      ..serversResult = [selected]
      ..connectionResult = selected.connections.single
      ..librariesResult = [
        for (var index = 0; index < 6; index++)
          PlexLibrary(
            id: 'library-$index',
            title: 'Library $index',
            type: PlexLibraryType.movie,
          ),
      ]
      ..libraryItemsScanHandler =
          (_, _, libraryId, _, isCurrent, onProgress) async {
            requests++;
            active++;
            perLibrary[libraryId] = (perLibrary[libraryId] ?? 0) + 1;
            peak = active > peak ? active : peak;
            final index = int.parse(libraryId.split('-').last);
            await Future<void>.delayed(Duration(milliseconds: 6 - index));
            active--;
            if (!isCurrent()) {
              throw const PlexException('cancelled', 'cancelled');
            }
            onProgress(const (
              completedPages: 1,
              completedItems: 1,
              totalItems: 1,
            ));
            return [
              PlexMediaItem(
                id: libraryId,
                title: libraryId,
                type: 'movie',
                duration: const Duration(minutes: 1),
                libraryId: libraryId,
                parts: [PlexMediaPart(path: '/parts/$libraryId')],
              ),
            ];
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
    final observedItems = <int>[];
    controller.addListener(() {
      if (controller.libraryScanStatus == LibraryScanStatus.scanning) {
        observedItems.add(controller.libraryScanCompletedItems);
      }
    });

    final loaded = await controller.setLibraries({
      'library-5',
      'library-4',
      'library-3',
      'library-2',
      'library-1',
      'library-0',
    });

    expect(loaded, isTrue);
    expect(peak, 4);
    expect(perLibrary.values, everyElement(1));
    expect(requests, 6);
    expect(
      controller.availableMedia.map((item) => item.libraryId),
      orderedEquals([for (var index = 0; index < 6; index++) 'library-$index']),
    );
    expect(observedItems, orderedEquals(observedItems.toList()..sort()));
    expect(controller.libraryScanCompletedPages, 6);
    expect(controller.libraryScanCompletedItems, 6);
    expect(controller.libraryScanTotalItems, 6);
    expect(controller.libraryScanStatus, LibraryScanStatus.complete);
    expect(
      controller.libraryScanFacts.values.map((fact) => fact.status),
      everyElement(LibraryScanStatus.complete),
    );
    expect(
      controller.libraryScanFacts.values.fold<int>(
        0,
        (total, fact) => total + fact.completedItems,
      ),
      controller.libraryScanCompletedItems,
    );
  });

  test(
    'authorization retry cannot regress aggregate library progress',
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
        ..libraryItemsScanHandler = (_, _, libraryId, _, _, onProgress) async {
          calls++;
          if (calls == 1) {
            onProgress(const (
              completedPages: 2,
              completedItems: 2,
              totalItems: 4,
            ));
            throw const PlexException('auth-required', 'refresh');
          }
          onProgress(const (
            completedPages: 1,
            completedItems: 1,
            totalItems: 3,
          ));
          onProgress(const (
            completedPages: 3,
            completedItems: 3,
            totalItems: 3,
          ));
          return [
            for (var index = 0; index < 3; index++)
              PlexMediaItem(
                id: '$index',
                title: 'Item $index',
                type: 'movie',
                duration: const Duration(minutes: 1),
                libraryId: libraryId,
                parts: [PlexMediaPart(path: '/parts/$libraryId')],
              ),
          ];
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
      final observed = <int>[];
      controller.addListener(() {
        if (controller.libraryScanStatus == LibraryScanStatus.scanning) {
          observed.add(controller.libraryScanCompletedItems);
        }
      });

      expect(await controller.setLibraries({'movies'}), isTrue);

      expect(calls, 2);
      expect(observed, orderedEquals(observed.toList()..sort()));
      expect(observed, containsAllInOrder([2, 2, 3]));
      expect(controller.libraryScanCompletedPages, 3);
      expect(controller.libraryScanCompletedItems, 3);
      expect(controller.libraryScanTotalItems, 4);
      expect(controller.libraryScanFacts['movies']!.completedPages, 3);
      expect(controller.libraryScanFacts['movies']!.completedItems, 3);
      expect(controller.libraryScanFacts['movies']!.totalItems, 4);
    },
  );

  test('per-library facts classify raw and playable results without partial install', () async {
    final selected = _server('server');
    final plex = _FakePlex()
      ..serversResult = [selected]
      ..connectionResult = selected.connections.single
      ..librariesResult = const [
        PlexLibrary(id: 'mixed', title: 'Mixed', type: PlexLibraryType.movie),
        PlexLibrary(id: 'empty', title: 'Empty', type: PlexLibraryType.movie),
        PlexLibrary(
          id: 'unsupported',
          title: 'Unsupported',
          type: PlexLibraryType.movie,
        ),
        PlexLibrary(id: 'shows', title: 'Shows', type: PlexLibraryType.show),
      ]
      ..libraryItemsScanHandler = (_, _, libraryId, _, _, onProgress) async {
        await Future<void>.delayed(
          Duration(
            milliseconds: {
              'mixed': 4,
              'empty': 3,
              'unsupported': 2,
              'shows': 1,
            }[libraryId]!,
          ),
        );
        final items = switch (libraryId) {
          'mixed' => [
            PlexMediaItem(
              id: 'playable',
              title: 'Playable',
              type: 'movie',
              duration: Duration(minutes: 1),
              libraryId: 'mixed',
              parts: [PlexMediaPart(path: '/parts/playable')],
            ),
            PlexMediaItem(
              id: 'no-part',
              title: 'No part',
              type: 'movie',
              duration: Duration(minutes: 1),
              libraryId: 'mixed',
            ),
          ],
          'unsupported' => [
            PlexMediaItem(
              id: 'unsupported',
              title: 'Unsupported',
              type: 'movie',
              duration: Duration(minutes: 1),
              libraryId: 'unsupported',
            ),
          ],
          'shows' => [
            PlexMediaItem(
              id: 'episode',
              title: 'Episode',
              type: 'episode',
              duration: Duration(minutes: 1),
              libraryId: 'shows',
              parts: [PlexMediaPart(path: '/parts/episode')],
            ),
          ],
          _ => const <PlexMediaItem>[],
        };
        onProgress((
          completedPages: 1,
          completedItems: items.length,
          totalItems: libraryId == 'unsupported' ? null : items.length,
        ));
        return items;
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

    expect(
      await controller.setLibraries({'mixed', 'empty', 'unsupported', 'shows'}),
      isTrue,
    );

    expect(controller.availableMedia.map((item) => item.id), [
      'playable',
      'episode',
    ]);
    expect(
      controller.libraryScanFacts['mixed']!.status,
      LibraryScanStatus.complete,
    );
    expect(controller.libraryScanFacts['mixed']!.completedItems, 2);
    expect(
      controller.libraryScanFacts['empty']!.status,
      LibraryScanStatus.empty,
    );
    expect(
      controller.libraryScanFacts['unsupported']!.status,
      LibraryScanStatus.unsupported,
    );
    expect(
      controller.libraryScanFacts['shows']!.status,
      LibraryScanStatus.complete,
    );
    expect(controller.libraryScanCompletedPages, 4);
    expect(controller.libraryScanCompletedItems, 4);
    expect(controller.libraryScanTotalItems, isNull);
    expect(
      () => controller.libraryScanFacts['other'] = const LibraryScanFact(
        status: LibraryScanStatus.idle,
      ),
      throwsUnsupportedError,
    );

    await controller.clearSavedServer();
    expect(controller.libraryScanFacts, isEmpty);
  });

  test('first library failure drains claimed peers and leaves queued libraries idle', () async {
    final selected = _server('server');
    final fourStarted = Completer<void>();
    final failFirst = Completer<void>();
    final releasePeers = Completer<void>();
    final firstFailed = Completer<void>();
    final started = <String>[];
    final plex = _FakePlex()
      ..serversResult = [selected]
      ..connectionResult = selected.connections.single
      ..librariesResult = [
        for (var index = 0; index < 7; index++)
          PlexLibrary(
            id: 'library-$index',
            title: 'Library $index',
            type: PlexLibraryType.movie,
          ),
      ]
      ..libraryItemsScanHandler = (_, _, libraryId, _, _, onProgress) async {
        started.add(libraryId);
        if (started.length == 4) fourStarted.complete();
        if (libraryId == 'library-0') {
          await failFirst.future;
          throw const PlexException('first', 'First failure');
        }
        onProgress(const (completedPages: 1, completedItems: 1, totalItems: 5));
        await releasePeers.future;
        if (libraryId == 'library-3') {
          throw const PlexException('second', 'Second failure');
        }
        onProgress(const (completedPages: 5, completedItems: 5, totalItems: 5));
        return [
          PlexMediaItem(
            id: libraryId,
            title: libraryId,
            type: 'movie',
            duration: const Duration(minutes: 1),
            libraryId: libraryId,
            parts: [PlexMediaPart(path: '/parts/$libraryId')],
          ),
        ];
      };
    final controller = LineupController(
      store: _MemoryStore(
        const PersistedState(selectedServerByProfile: {'owner': 'server'}),
      ),
      credentials: _MemoryCredentials(accountToken: 'token'),
      plex: plex,
    );
    addTearDown(controller.dispose);
    controller.addListener(() {
      if (controller.libraryScanFacts['library-0']?.status ==
              LibraryScanStatus.transientFailure &&
          !firstFailed.isCompleted) {
        firstFailed.complete();
      }
    });
    await controller.initialize();
    controller
      ..selectedLibraryIds = const {'committed'}
      ..availableMedia = [
        PlexMediaItem(
          id: 'committed',
          title: 'Committed',
          type: 'movie',
          duration: const Duration(minutes: 1),
          libraryId: 'committed',
          parts: [PlexMediaPart(path: '/parts/committed')],
        ),
      ];

    final scan = controller.setLibraries({
      for (var index = 0; index < 7; index++) 'library-$index',
    });
    await fourStarted.future;
    failFirst.complete();
    await firstFailed.future;
    final itemsAtFailure = controller.libraryScanCompletedItems;
    releasePeers.complete();

    expect(await scan, isFalse);
    expect(controller.error, 'First failure');
    expect(started, [for (var index = 0; index < 4; index++) 'library-$index']);
    expect(controller.libraryScanCompletedItems, itemsAtFailure);
    expect(controller.selectedLibraryIds, {'committed'});
    expect(controller.availableMedia.single.id, 'committed');
    expect(
      controller.libraryScanFacts['library-0']!.status,
      LibraryScanStatus.transientFailure,
    );
    expect(
      controller.libraryScanFacts['library-1']!.status,
      LibraryScanStatus.complete,
    );
    expect(
      controller.libraryScanFacts['library-2']!.status,
      LibraryScanStatus.complete,
    );
    expect(
      controller.libraryScanFacts['library-3']!.status,
      LibraryScanStatus.transientFailure,
    );
    for (var index = 4; index < 7; index++) {
      expect(
        controller.libraryScanFacts['library-$index']!.status,
        LibraryScanStatus.idle,
      );
    }
    expect(
      controller.libraryScanFacts.values.fold<int>(
        0,
        (total, fact) => total + fact.completedItems,
      ),
      controller.libraryScanCompletedItems,
    );
  });

  test('cancelled library scan preserves committed content and superseding scan wins', () async {
    final selected = _server('server');
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final plex = _FakePlex()
      ..serversResult = [selected]
      ..connectionResult = selected.connections.single
      ..librariesResult = const [
        PlexLibrary(id: 'first', title: 'First', type: PlexLibraryType.movie),
        PlexLibrary(id: 'second', title: 'Second', type: PlexLibraryType.movie),
      ]
      ..libraryItemsScanHandler =
          (_, _, libraryId, _, isCurrent, onProgress) async {
            if (libraryId == 'first') {
              firstStarted.complete();
              await releaseFirst.future;
              if (!isCurrent()) {
                throw const PlexException('cancelled', 'cancelled');
              }
            }
            onProgress(const (
              completedPages: 1,
              completedItems: 1,
              totalItems: 1,
            ));
            return [
              PlexMediaItem(
                id: libraryId,
                title: libraryId,
                type: 'movie',
                duration: const Duration(minutes: 1),
                libraryId: libraryId,
                parts: [PlexMediaPart(path: '/parts/$libraryId')],
              ),
            ];
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
      ..selectedLibraryIds = const {'committed'}
      ..availableMedia = const [
        PlexMediaItem(
          id: 'committed',
          title: 'Committed',
          type: 'movie',
          duration: Duration(minutes: 1),
        ),
      ];

    final first = controller.setLibraries({'first'});
    await firstStarted.future;
    controller.cancelLibraryScan();
    expect(controller.libraryScanStatus, LibraryScanStatus.cancelled);
    expect(controller.selectedLibraryIds, {'committed'});
    expect(controller.availableMedia.single.id, 'committed');

    final second = controller.setLibraries({'second'});
    releaseFirst.complete();
    expect(await first, isFalse);
    expect(await second, isTrue);
    expect(controller.selectedLibraryIds, {'second'});
    expect(controller.availableMedia.single.id, 'second');
    expect(controller.libraryScanStatus, LibraryScanStatus.complete);
    expect(controller.libraryScanFacts.keys, {'second'});
  });

  test(
    'route cancellation invalidates an active scan before returning ready',
    () async {
      final selected = _server('server');
      final started = Completer<void>();
      final release = Completer<void>();
      final store = _CountingMemoryStore(
        const PersistedState(selectedServerByProfile: {'owner': 'server'}),
      );
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
        ..libraryItemsScanHandler = (_, _, _, _, isCurrent, _) async {
          started.complete();
          await release.future;
          if (!isCurrent()) {
            throw const PlexException('cancelled', 'cancelled');
          }
          return const [];
        };
      final controller = LineupController(
        store: store,
        credentials: _MemoryCredentials(accountToken: 'token'),
        plex: plex,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller
        ..stage = SetupStage.channelSetup
        ..channelSetupCanCancel = true
        ..selectedLibraryIds = const {'committed'}
        ..availableMedia = const [
          PlexMediaItem(
            id: 'committed',
            title: 'Committed',
            type: 'movie',
            duration: Duration(minutes: 1),
          ),
        ];
      final savesBeforeScan = store.saveCalls;

      final scan = controller.setLibraries({'movies'});
      await started.future;
      controller.cancelChannelSetup();
      release.complete();

      expect(await scan, isFalse);
      expect(controller.stage, SetupStage.ready);
      expect(controller.selectedLibraryIds, {'committed'});
      expect(controller.availableMedia.single.id, 'committed');
      expect(store.saveCalls, savesBeforeScan);
    },
  );

  test('cancelling a scan schedules no queued fifth library', () async {
    final selected = _server('server');
    final fourStarted = Completer<void>();
    final release = Completer<void>();
    final started = <String>[];
    final plex = _FakePlex()
      ..serversResult = [selected]
      ..connectionResult = selected.connections.single
      ..librariesResult = [
        for (var index = 0; index < 5; index++)
          PlexLibrary(
            id: 'library-$index',
            title: 'Library $index',
            type: PlexLibraryType.movie,
          ),
      ]
      ..libraryItemsScanHandler = (_, _, libraryId, _, isCurrent, _) async {
        started.add(libraryId);
        if (started.length == 4) fourStarted.complete();
        await release.future;
        if (!isCurrent()) {
          throw const PlexException('cancelled', 'cancelled');
        }
        return const [];
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

    final scan = controller.setLibraries({
      for (var index = 0; index < 5; index++) 'library-$index',
    });
    await fourStarted.future;
    controller.cancelLibraryScan();
    release.complete();

    expect(await scan, isFalse);
    expect(started, [for (var index = 0; index < 4; index++) 'library-$index']);
    expect(controller.libraryScanStatus, LibraryScanStatus.cancelled);
    for (var index = 0; index < 4; index++) {
      expect(
        controller.libraryScanFacts['library-$index']!.status,
        LibraryScanStatus.cancelled,
      );
    }
    expect(
      controller.libraryScanFacts['library-4']!.status,
      LibraryScanStatus.idle,
    );
  });

  test(
    'library scan distinguishes empty unsupported and transient failures',
    () async {
      final selected = _server('server');
      var result = 0;
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
        ..libraryItemsHandler = (_, _, libraryId, _) async => switch (result) {
          0 => const [],
          1 => [
            PlexMediaItem(
              id: 'zero',
              title: 'Zero',
              type: 'movie',
              duration: Duration.zero,
              libraryId: libraryId,
            ),
          ],
          2 => throw const PlexException(
            'network-timeout',
            'Plex did not respond in time. Try again.',
          ),
          3 => throw const PlexException(
            'server-unreachable',
            'Plex request failed (503).',
          ),
          _ => throw const PlexException(
            'library-scale-exceeded',
            'This library is too large to scan safely.',
          ),
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

      expect(await controller.setLibraries({'movies'}), isTrue);
      expect(controller.libraryScanStatus, LibraryScanStatus.empty);
      result = 1;
      expect(await controller.setLibraries({'movies'}), isTrue);
      expect(controller.libraryScanStatus, LibraryScanStatus.unsupported);
      result = 2;
      expect(await controller.setLibraries({'movies'}), isFalse);
      expect(controller.libraryScanStatus, LibraryScanStatus.transientFailure);
      expect(controller.error, contains('did not respond'));
      result = 3;
      expect(await controller.setLibraries({'movies'}), isFalse);
      expect(controller.libraryScanStatus, LibraryScanStatus.transientFailure);
      expect(controller.error, contains('503'));
      result = 4;
      expect(await controller.setLibraries({'movies'}), isFalse);
      expect(controller.libraryScanStatus, LibraryScanStatus.transientFailure);
      expect(controller.error, contains('too large'));
    },
  );

  test('restored library scan failure reaches a terminal state', () async {
    final selected = _server('server');
    final plex = _FakePlex()
      ..serversResult = [selected]
      ..connectionResult = selected.connections.single
      ..librariesResult = const [
        PlexLibrary(id: 'movies', title: 'Movies', type: PlexLibraryType.movie),
      ]
      ..playlistsHandler = (_, _) async => throw const PlexException(
        'auth-invalid',
        'Plex authorization expired.',
      );
    final controller = LineupController(
      store: _MemoryStore(
        PersistedState(
          selectedServerByProfile: const {'owner': 'server'},
          selectedLibraryIdsByProfileServer: const {
            'owner': {
              'server': ['movies'],
            },
          },
          channelsByProfileServer: {
            'owner': {
              'server': [_channel('saved')],
            },
          },
        ),
      ),
      credentials: _MemoryCredentials(accountToken: 'token'),
      plex: plex,
    );
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.libraryScanStatus, LibraryScanStatus.transientFailure);
    expect(controller.busy, isFalse);
    expect(controller.error, 'Plex authorization expired.');
  });

  test(
    'restored playlist failure preserves the completed scan state',
    () async {
      final selected = _server('server');
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
        ..libraryItemsHandler = (_, _, _, _) async {
          return [
            PlexMediaItem(
              id: 'movie',
              title: 'Movie',
              type: 'movie',
              duration: const Duration(minutes: 1),
              libraryId: 'movies',
              parts: [PlexMediaPart(path: '/parts/movie')],
            ),
          ];
        }
        ..playlistsHandler = (_, _) async => const PlexPlaylistCatalog(
          playlists: [],
          failedIds: {'missing-playlist'},
        );
      final controller = LineupController(
        store: _MemoryStore(
          PersistedState(
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
                    source: const PlaylistSource('missing-playlist'),
                    playbackMode: PlaybackMode.sequential,
                    anchor: DateTime.utc(2026),
                    shuffleSeed: 1,
                  ),
                ],
              },
            },
          ),
        ),
        credentials: _MemoryCredentials(accountToken: 'token'),
        plex: plex,
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.libraryScanStatus, LibraryScanStatus.complete);
      expect(controller.busy, isFalse);
      expect(
        controller.error,
        'A playlist used by this lineup could not be loaded. Retry setup.',
      );
    },
  );

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

  test(
    'PIN polling failure stops safely without scheduling another poll',
    () async {
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
      while (controller.activePin != null) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(plex.pollCalls, 1);
      expect(plex.cancelPinCalls, 1);
      expect(controller.error, contains('could not complete Plex sign-in'));
      expect(controller.error, isNot(contains('opaque-secret-sentinel')));
      expect(controller.diagnostics.entries.single.message, 'PIN poll failed');
      expect(controller.diagnostics.entries.single.context, {
        'code': 'unexpected',
      });
      expect(
        '${controller.diagnostics.entries.single.message}'
        '${controller.diagnostics.entries.single.context}',
        isNot(contains('opaque-secret-sentinel')),
      );

      await controller.startLinking();
      expect(plex.createPinCalls, 2);
      expect(controller.activePin, isNotNull);
    },
  );

  for (final failurePoint in ['account', 'home']) {
    test(
      '$failurePoint failure retires the current PIN before credential write',
      () async {
        final plex = _FakePlex()
          ..pinResult = PlexPin(
            id: 61,
            code: 'SAFE',
            expiresAt: DateTime.now().add(const Duration(minutes: 1)),
          )
          ..pollHandler = (_) async => 'cloud-token-sentinel';
        if (failurePoint == 'account') {
          plex.accountHandler = (_) async => throw const PlexException(
            'auth-invalid',
            'opaque-secret-sentinel',
          );
        } else {
          plex.homeUsersHandler = (_) async => throw const PlexException(
            'parse-error',
            'opaque-secret-sentinel',
          );
        }
        final credentials = _MemoryCredentials();
        final controller = LineupController(
          store: _MemoryStore(),
          credentials: credentials,
          plex: plex,
          pinPollInterval: const Duration(milliseconds: 1),
        );
        addTearDown(controller.dispose);

        await controller.startLinking();
        while (controller.activePin != null) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));

        expect(plex.pollCalls, 1);
        expect(plex.cancelPinCalls, 1);
        expect(credentials.accountToken, isNull);
        expect(controller.account, isNull);
        expect(controller.profiles, isEmpty);
        expect(controller.error, isNot(contains('opaque-secret-sentinel')));
      },
    );
  }

  test('post-auth discovery failure keeps authenticated state and offers server retry', () async {
    final server = _server('server');
    var discoveries = 0;
    final plex = _FakePlex()
      ..pinResult = PlexPin(
        id: 64,
        code: 'SAFE',
        expiresAt: DateTime.now().add(const Duration(minutes: 1)),
      )
      ..discoverServersHandler = (_) async {
        discoveries++;
        if (discoveries == 1) {
          throw const PlexException(
            'network-unavailable',
            'Plex servers are unavailable.',
          );
        }
        return [PlexServerAccess(server: server, token: 'pms-token')];
      }
      ..pollHandler = (_) async => 'cloud-token-sentinel';
    final credentials = _MemoryCredentials();
    final controller = LineupController(
      store: _MemoryStore(),
      credentials: credentials,
      plex: plex,
      pinPollInterval: const Duration(milliseconds: 1),
    );
    addTearDown(controller.dispose);

    await controller.startLinking();
    while (controller.stage != SetupStage.servers || controller.busy) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }

    expect(credentials.accountToken, 'cloud-token-sentinel');
    expect(controller.account, plex.accountResult);
    expect(controller.activePin, isNull);
    expect(controller.error, 'Plex servers are unavailable.');
    expect(plex.cancelPinCalls, 0);

    await controller.refreshServers();

    expect(controller.error, isNull);
    expect(controller.servers.single.id, server.id);
    expect(plex.discoveredTokens, [
      'cloud-token-sentinel',
      'cloud-token-sentinel',
    ]);
  });

  test('a stale PIN failure cannot replace cancellation state', () async {
    final poll = Completer<String?>();
    final plex = _FakePlex()
      ..pinResult = PlexPin(
        id: 62,
        code: 'SAFE',
        expiresAt: DateTime.now().add(const Duration(minutes: 1)),
      )
      ..pollHandler = (_) => poll.future;
    final controller = LineupController(
      store: _MemoryStore(),
      credentials: _MemoryCredentials(),
      plex: plex,
      pinPollInterval: const Duration(milliseconds: 1),
    );
    addTearDown(controller.dispose);

    await controller.startLinking();
    while (plex.pollCalls == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await controller.cancelLinking();
    poll.completeError(const PlexException('auth-invalid', 'old failure'));
    await Future<void>.delayed(Duration.zero);

    expect(controller.stage, SetupStage.welcome);
    expect(controller.error, isNull);
  });

  test(
    'ambiguous credential write requires queued cleanup before a new PIN',
    () async {
      final credentials = _AmbiguousWriteCredentials();
      final plex = _FakePlex()
        ..pinResult = PlexPin(
          id: 63,
          code: 'SAFE',
          expiresAt: DateTime.now().add(const Duration(minutes: 1)),
        )
        ..homeUsersResult = const [
          PlexHomeUser(id: 'owner', name: 'Owner', protected: false),
        ]
        ..pollHandler = (_) async => 'cloud-token-sentinel';
      final controller = LineupController(
        store: _MemoryStore(),
        credentials: credentials,
        plex: plex,
        pinPollInterval: const Duration(milliseconds: 1),
      );
      addTearDown(controller.dispose);

      await controller.startLinking();
      while (!controller.secureCancellationRequired) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

      expect(controller.activePin?.id, 63);
      expect(controller.account, isNull);
      expect(controller.profiles, isEmpty);
      expect(controller.error, contains('secure credential storage'));
      expect(credentials.accountToken, 'cloud-token-sentinel');

      final retry = controller.startLinking();
      await credentials.clearStarted.future;
      expect(plex.createPinCalls, 1);
      credentials.finishClear.complete();
      await retry;
      expect(plex.createPinCalls, 1);
      expect(controller.stage, SetupStage.welcome);
      expect(credentials.accountToken, isNull);

      await controller.startLinking();
      expect(plex.createPinCalls, 2);
    },
  );

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
      controller
        ..connection = _server('server').connections.single
        ..availableMedia = [_playableMovie];

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
            libraryId: 'movies',
            libraryType: PlexLibraryType.movie,
          ),
          playbackMode: PlaybackMode.sequential,
          anchor: DateTime.utc(2026),
          shuffleSeed: 1,
        ),
        expectedBase: null,
      );

      expect(store.state.settings.diagnosticsEnabled, isFalse);
      expect(controller.channels.single.id, 'channel');
    },
  );

  test('saveChannel enforces create and canonical expected bases', () async {
    final store = _CountingMemoryStore();
    final controller = LineupController(
      store: store,
      credentials: _MemoryCredentials(),
      plex: _FakePlex(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final created = _manualChannel('channel', 'Created');

    await controller.saveChannel(created, expectedBase: null);
    expect(controller.channels.single.toJson(), created.toJson());
    expect(store.saveCalls, 1);

    await expectLater(
      controller.saveChannel(created, expectedBase: null),
      throwsFormatException,
    );
    await expectLater(
      controller.saveChannel(
        _manualChannel('missing', 'Missing edit'),
        expectedBase: _manualChannel('missing', 'Old missing'),
      ),
      throwsFormatException,
    );
    await expectLater(
      controller.saveChannel(
        _manualChannel('channel', 'Stale edit'),
        expectedBase: _manualChannel('channel', 'Different base'),
      ),
      throwsFormatException,
    );
    expect(store.saveCalls, 1);
    expect(controller.channels.single.toJson(), created.toJson());

    final edited = _manualChannel('channel', 'Edited');
    store.failNextSave = true;
    await expectLater(
      controller.saveChannel(edited, expectedBase: created),
      throwsStateError,
    );
    expect(controller.channels.single.toJson(), created.toJson());
    expect(store.saveCalls, 2);

    await controller.saveChannel(edited, expectedBase: created);
    expect(controller.channels.single.toJson(), edited.toJson());
    expect(store.saveCalls, 3);
  });

  test('saveChannel rejects unsupported filters without a write', () async {
    final store = _CountingMemoryStore();
    final controller = LineupController(
      store: store,
      credentials: _MemoryCredentials(),
      plex: _FakePlex(),
    )..availableMedia = [_playableMovie];
    addTearDown(controller.dispose);
    final channel = Channel(
      id: 'unsupported',
      number: 1,
      name: 'Unsupported',
      source: const LibrarySource(
        libraryId: 'movies',
        libraryType: PlexLibraryType.movie,
        filters: {'future': 'value'},
      ),
      playbackMode: PlaybackMode.sequential,
      anchor: DateTime.utc(2026),
      shuffleSeed: 1,
    );

    await expectLater(
      controller.saveChannel(channel, expectedBase: null),
      throwsFormatException,
    );
    expect(store.saveCalls, 0);
    expect(controller.channels, isEmpty);
  });

  test(
    'playlist-only content saves, schedules, and uses media-first playback',
    () async {
      final selected = _server('server');
      final plex = _FakePlex()
        ..serversResult = [selected]
        ..connectionResult = selected.connections.single;
      final controller = LineupController(
        store: _MemoryStore(
          const PersistedState(selectedServerByProfile: {'owner': 'server'}),
        ),
        credentials: _MemoryCredentials(accountToken: 'token'),
        plex: plex,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final playlistItem = PlexMediaItem(
        id: 'shared',
        title: 'Playlist item',
        type: 'movie',
        duration: const Duration(minutes: 2),
        parts: [PlexMediaPart(path: '/playlist')],
      );
      controller.availablePlaylists = [
        PlexPlaylist(id: 'playlist', title: 'Playlist', items: [playlistItem]),
      ];
      final channel = Channel(
        id: 'playlist-channel',
        number: 1,
        name: 'Playlist channel',
        source: const PlaylistSource('playlist'),
        playbackMode: PlaybackMode.sequential,
        anchor: DateTime.utc(2026),
        shuffleSeed: 1,
      );

      expect(controller.scheduleFor(channel).items.single.id, 'shared');
      await controller.saveChannel(channel, expectedBase: null);
      controller.playbackFor('shared');
      expect(plex.playbackItems.last.title, 'Playlist item');

      controller.availableMedia = [
        PlexMediaItem(
          id: 'shared',
          title: 'Library item',
          type: 'movie',
          duration: const Duration(minutes: 2),
          libraryId: 'movies',
          parts: [PlexMediaPart(path: '/library')],
        ),
      ];
      final exposed = controller.playableInventory;
      expect(exposed.byId['shared']!.title, 'Library item');
      expect(identical(exposed.byId['shared'], exposed.media.single), isTrue);
      controller.playbackFor('shared');
      expect(plex.playbackItems.last.title, 'Library item');
      expect(plex.playbackItems.last, same(exposed.byId['shared']));
    },
  );

  test(
    'empty live sources fail while retained manual content may save',
    () async {
      final store = _CountingMemoryStore();
      final controller = LineupController(
        store: store,
        credentials: _MemoryCredentials(),
        plex: _FakePlex(),
      )..connection = _server('server').connections.single;
      addTearDown(controller.dispose);
      for (final source in <ContentSource>[
        const LibrarySource(
          libraryId: 'movies',
          libraryType: PlexLibraryType.movie,
        ),
        const PlaylistSource('missing'),
      ]) {
        await expectLater(
          controller.saveChannel(
            Channel(
              id: source.runtimeType.toString(),
              number: 1,
              name: 'Empty',
              source: source,
              playbackMode: PlaybackMode.sequential,
              anchor: DateTime.utc(2026),
              shuffleSeed: 1,
            ),
            expectedBase: null,
          ),
          throwsFormatException,
        );
      }
      final retained = _manualChannel('retained', 'Retained');
      await controller.saveChannel(retained, expectedBase: null);
      expect(controller.channels.single.toJson(), retained.toJson());
      expect(store.saveCalls, 1);
    },
  );

  test(
    'descriptor-incompatible items never enter channel operations',
    () async {
      final controller =
          LineupController(
              store: _CountingMemoryStore(),
              credentials: _MemoryCredentials(),
              plex: _FakePlex(),
            )
            ..connection = _server('server').connections.single
            ..availablePlaylists = [
              PlexPlaylist(
                id: 'playlist',
                title: 'Playlist',
                items: [
                  const PlexMediaItem(
                    id: 'no-part',
                    title: 'No part',
                    type: 'movie',
                    duration: Duration(minutes: 1),
                  ),
                  PlexMediaItem(
                    id: 'zero',
                    title: 'Zero',
                    type: 'movie',
                    duration: Duration.zero,
                    parts: [PlexMediaPart(path: '/zero')],
                  ),
                  PlexMediaItem(
                    id: 'empty-path',
                    title: 'Empty path',
                    type: 'movie',
                    duration: const Duration(minutes: 1),
                    parts: [PlexMediaPart(path: '')],
                  ),
                  PlexMediaItem(
                    id: 'hostile',
                    title: 'Hostile',
                    type: 'movie',
                    duration: const Duration(minutes: 1),
                    parts: [
                      PlexMediaPart(path: '/safe'),
                      PlexMediaPart(path: 'https://hostile.invalid/later'),
                    ],
                  ),
                ],
              ),
            ];
      addTearDown(controller.dispose);
      final channel = _playlistChannel('invalid-playlist');

      expect(controller.playableInventory.playlists.single.items, isEmpty);

      expect(
        () => controller.scheduleFor(channel),
        _throwsScheduleFailure(ScheduleFailureReason.noContent),
      );
      await expectLater(
        controller.loadScheduleFor(channel),
        _throwsScheduleFailure(ScheduleFailureReason.noContent),
      );
      await expectLater(
        controller.saveChannel(channel, expectedBase: null),
        throwsFormatException,
      );
      for (final id in ['no-part', 'zero', 'empty-path', 'hostile']) {
        expect(() => controller.playbackFor(id), throwsA(isA<PlexException>()));
      }
      expect(controller.channels, isEmpty);
    },
  );

  test(
    'missing endpoints are empty and unexpected descriptor errors surface',
    () {
      final plex = _FakePlex();
      final missingEndpoint = LineupController(
        store: _MemoryStore(),
        credentials: _MemoryCredentials(),
        plex: plex,
      )..availableMedia = [_playableMovie];
      addTearDown(missingEndpoint.dispose);

      expect(
        () => missingEndpoint.scheduleFor(_channel('missing')),
        _throwsScheduleFailure(ScheduleFailureReason.noContent),
      );
      expect(missingEndpoint.playableInventory.media, isEmpty);
      expect(missingEndpoint.playableInventory.playlists, isEmpty);
      expect(plex.playbackItems, isEmpty);

      final broken =
          LineupController(
              store: _MemoryStore(),
              credentials: _MemoryCredentials(),
              plex: _ThrowingPlaybackPlex(),
            )
            ..connection = _server('server').connections.single
            ..availableMedia = [_playableMovie];
      addTearDown(broken.dispose);
      expect(() => broken.scheduleFor(_channel('broken')), throwsStateError);
    },
  );

  test(
    'same-server multipart playlist resolves saves schedules and tunes',
    () async {
      final selected = _server('server');
      final plex = _FakePlex()
        ..serversResult = [selected]
        ..connectionResult = selected.connections.single;
      final controller = LineupController(
        store: _MemoryStore(
          const PersistedState(selectedServerByProfile: {'owner': 'server'}),
        ),
        credentials: _MemoryCredentials(accountToken: 'token'),
        plex: plex,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller.availablePlaylists = [
        PlexPlaylist(
          id: 'playlist',
          title: 'Playlist',
          items: [
            PlexMediaItem(
              id: 'multipart',
              title: 'Multipart',
              type: 'movie',
              duration: const Duration(minutes: 2),
              parts: [
                PlexMediaPart(path: '/one'),
                PlexMediaPart(path: '/two'),
              ],
            ),
          ],
        ),
      ];
      final channel = _playlistChannel('multipart-channel');

      final playable = controller.playableInventory;
      expect(playable.playlists.single.items.single.id, 'multipart');
      expect(
        playable.playlists.single.items.single.parts.first.duration,
        isNull,
      );

      expect(controller.scheduleFor(channel).items.single.id, 'multipart');
      await controller.saveChannel(channel, expectedBase: null);
      expect(
        (await controller.loadScheduleFor(channel)).items.single.id,
        'multipart',
      );
      expect(controller.playbackFor('multipart').parts, hasLength(2));
    },
  );

  test(
    'playable projection and worker track endpoint and inventory identity',
    () async {
      final mediaInputs = <List<PlexMediaItem>>[];
      final playlistInputs = <List<PlexPlaylist>>[];
      final plex = _FakePlex();
      final controller =
          LineupController(
              store: _MemoryStore(),
              credentials: _MemoryCredentials(),
              plex: plex,
              scheduleWorkerFactory: (media, playlists) {
                mediaInputs.add(media);
                playlistInputs.add(playlists);
                return ScheduleWorker(media, playlists);
              },
            )
            ..connection = _server('server').connections.single
            ..availableMedia = [_playableMovie];
      addTearDown(controller.dispose);
      final channel = _channel('stable');

      final exposed = controller.playableInventory;
      final exposedAgain = controller.playableInventory;
      expect(identical(exposed.media, exposedAgain.media), isTrue);
      expect(identical(exposed.playlists, exposedAgain.playlists), isTrue);
      expect(identical(exposed.byId, exposedAgain.byId), isTrue);
      expect(() => exposed.media.add(_playableMovie), throwsUnsupportedError);
      expect(
        () => exposed.byId['other'] = _playableMovie,
        throwsUnsupportedError,
      );

      await controller.loadScheduleFor(channel);
      await controller.loadScheduleFor(channel);
      expect(mediaInputs, hasLength(1));
      expect(plex.playbackItems, hasLength(1));
      final firstMedia = mediaInputs.single;
      final firstPlaylists = playlistInputs.single;

      controller.availableMedia = List.of(controller.availableMedia);
      final rebuilt = controller.playableInventory;
      expect(identical(rebuilt.media, exposed.media), isFalse);
      expect(identical(rebuilt.byId, exposed.byId), isFalse);
      await controller.loadScheduleFor(channel);
      expect(mediaInputs, hasLength(2));
      expect(identical(mediaInputs.last, firstMedia), isFalse);
      expect(plex.playbackItems, hasLength(2));

      controller.availablePlaylists = [
        PlexPlaylist(
          id: 'playlist',
          title: 'Playlist',
          items: [_playableMovie],
        ),
      ];
      await controller.loadScheduleFor(channel);
      expect(playlistInputs, hasLength(3));
      expect(identical(playlistInputs.last, firstPlaylists), isFalse);
      expect(playlistInputs.last.single.items.single.id, 'movie');

      controller.availableMedia = [
        PlexMediaItem(
          id: 'origin-bound',
          title: 'Origin bound',
          type: 'movie',
          duration: const Duration(minutes: 1),
          libraryId: 'movies',
          parts: [
            PlexMediaPart(path: 'https://server.example:32400/origin-bound'),
          ],
        ),
      ];
      await controller.loadScheduleFor(channel);
      controller.connection = _server('other').connections.single;
      await expectLater(
        controller.loadScheduleFor(channel),
        _throwsScheduleFailure(ScheduleFailureReason.noContent),
      );
      expect(mediaInputs, hasLength(5));
    },
  );

  test(
    'custom source variants persist and reload with exact programming',
    () async {
      final store = _MemoryStore();
      final selected = _server('server');
      final fresh = PlexMediaItem(
        id: 'movie',
        title: 'Fresh movie',
        type: 'movie',
        duration: const Duration(minutes: 2),
        libraryId: 'movies',
        genres: const ['Comedy'],
        parts: [PlexMediaPart(path: '/movie')],
      );
      final playlistItem = PlexMediaItem(
        id: 'playlist-item',
        title: 'Playlist item',
        type: 'movie',
        duration: const Duration(minutes: 3),
        parts: [PlexMediaPart(path: '/playlist-item')],
      );
      final episodes = [
        for (final show in ['a', 'b'])
          for (var episode = 1; episode <= 5; episode++)
            PlexMediaItem(
              id: '$show$episode',
              title: '$show$episode',
              type: 'episode',
              duration: const Duration(minutes: 20),
              libraryId: 'shows',
              grandparentTitle: 'Show $show',
              parts: [PlexMediaPart(path: '/$show$episode')],
            ),
      ];
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
        ..availableMedia = [fresh, ...episodes]
        ..availablePlaylists = [
          PlexPlaylist(
            id: 'playlist',
            title: 'Playlist',
            items: [playlistItem],
          ),
        ];

      Channel custom(int number, ContentSource source) => Channel(
        id: 'custom-$number',
        number: number,
        name: 'Custom $number',
        source: source,
        playbackMode: PlaybackMode.sequential,
        anchor: DateTime.utc(2026),
        shuffleSeed: number,
      );

      final expected = [
        custom(
          1,
          const LibrarySource(
            libraryId: 'movies',
            libraryType: PlexLibraryType.movie,
          ),
        ),
        custom(2, const PlaylistSource('playlist')),
        custom(
          3,
          const LibrarySource(
            libraryId: 'movies',
            libraryType: PlexLibraryType.movie,
            includeWatched: false,
            filters: {'genre': 'Comedy', 'sort': 'added:desc'},
          ),
        ),
        custom(
          4,
          ManualSource([
            const ChannelItem(
              id: 'missing',
              title: 'Retained missing',
              duration: Duration(minutes: 4),
            ),
            channelItemFor(fresh),
          ]),
        ),
      ];
      for (final channel in expected) {
        await controller.saveChannel(channel, expectedBase: null);
      }
      const expectedBlockOrders = {
        2: ['a1', 'a2', 'b1', 'b2', 'a3', 'a4', 'b3', 'b4', 'a5', 'b5'],
        3: ['a1', 'a2', 'a3', 'b1', 'b2', 'b3', 'a4', 'a5', 'b4', 'b5'],
        4: ['a1', 'a2', 'a3', 'a4', 'b1', 'b2', 'b3', 'b4', 'a5', 'b5'],
        5: ['a1', 'a2', 'a3', 'a4', 'a5', 'b1', 'b2', 'b3', 'b4', 'b5'],
      };
      for (var size = 2; size <= 5; size++) {
        await controller.saveChannel(
          Channel(
            id: 'block-$size',
            number: size + 4,
            name: 'Block $size',
            source: ManualSource(episodes.map(channelItemFor).toList()),
            playbackMode: PlaybackMode.block,
            anchor: DateTime.utc(2026),
            shuffleSeed: 1,
            blockSize: size,
          ),
          expectedBase: null,
        );
      }

      final reloaded = PersistedState.fromJson(store.state.toJson())
          .channelsByProfileServer['owner']!['server']!;
      expect(reloaded, hasLength(8));
      for (var index = 0; index < expected.length; index++) {
        expect(
          reloaded[index].source.toJson(),
          expected[index].source.toJson(),
        );
        expect(reloaded[index].builderKey, isNull);
      }
      final manual = reloaded[3].source as ManualSource;
      expect(manual.items.map((item) => item.id), ['missing', 'movie']);
      expect(manual.items.first.title, 'Retained missing');
      expect(manual.items.last.title, 'Fresh movie');
      expect(controller.scheduleFor(reloaded[3]).items.map((item) => item.id), [
        'movie',
      ]);
      for (var size = 2; size <= 5; size++) {
        final channel = reloaded[size + 2];
        expect(channel.playbackMode, PlaybackMode.block);
        expect(channel.blockSize, size);
        expect(
          controller.scheduleFor(channel).items.map((item) => item.id),
          expectedBlockOrders[size],
        );
      }
    },
  );

  test('failed projection rebuild retries the same inventory identity', () {
    final plex = _ThrowOncePlaybackPlex('replacement');
    final controller =
        LineupController(
            store: _MemoryStore(),
            credentials: _MemoryCredentials(),
            plex: plex,
          )
          ..connection = _server('server').connections.single
          ..availableMedia = [_playableMovie];
    addTearDown(controller.dispose);
    final channel = _channel('retry');
    expect(controller.scheduleFor(channel).items.single.id, 'movie');
    final replacement = PlexMediaItem(
      id: 'replacement',
      title: 'Replacement',
      type: 'movie',
      duration: const Duration(minutes: 1),
      libraryId: 'movies',
      parts: [PlexMediaPart(path: '/replacement')],
    );
    final replacementInventory = <PlexMediaItem>[replacement];
    controller.availableMedia = replacementInventory;

    expect(() => controller.scheduleFor(channel), throwsStateError);
    expect(plex.attempts, 1);
    expect(identical(controller.availableMedia, replacementInventory), isTrue);

    expect(controller.scheduleFor(channel).items.single.id, 'replacement');
    expect(plex.attempts, 2);
  });

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
        ..connection = selected.connections.single
        ..availableMedia = [_playableMovie];
      store.blockNext(fail: true);

      final settings = controller.updateSettings(
        const LineupSettings(diagnosticsEnabled: true),
      );
      await store.blockedSaveStarted.future;
      final channel = controller.saveChannel(
        _channel('queued'),
        expectedBase: null,
      );
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
    final stale = controller.saveChannel(_channel('stale'), expectedBase: null);
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
        {'code': 'credential-cleanup-failed'},
        {'code': 'unexpected'},
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
      const AppStoreLoadResult(PersistedState(profileId: 'should-not-restore')),
    );
    await initialization;

    expect(controller.account, isNull);
    expect(controller.stage, SetupStage.welcome);
  });

  test(
    'startup corruption notice is bounded, path-free, and dismissible',
    () async {
      final controller = LineupController(
        store: _MemoryStore(const PersistedState(), true),
        credentials: _MemoryCredentials(),
        plex: _FakePlex(),
      );
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.initialize();

      expect(controller.startupRecoveryNotice, isNotNull);
      expect(controller.startupRecoveryNotice!.length, lessThan(100));
      expect(controller.startupRecoveryNotice, isNot(contains('state.json')));
      expect(controller.startupRecoveryNotice, isNot(contains('/')));
      final beforeDismiss = notifications;

      controller.dismissStartupRecoveryNotice();

      expect(controller.startupRecoveryNotice, isNull);
      expect(notifications, beforeDismiss + 1);
    },
  );

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
    expect(await selection, isFalse);

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

final _playableMovie = PlexMediaItem(
  id: 'movie',
  title: 'Movie',
  type: 'movie',
  duration: const Duration(minutes: 1),
  libraryId: 'movies',
  parts: [PlexMediaPart(path: '/movie')],
);

Channel _manualChannel(String id, String name) => Channel(
  id: id,
  number: 1,
  name: name,
  source: const ManualSource([
    ChannelItem(
      id: 'retained',
      title: 'Retained',
      duration: Duration(minutes: 1),
    ),
  ]),
  playbackMode: PlaybackMode.sequential,
  anchor: DateTime.utc(2026),
  shuffleSeed: 1,
);

Channel _playlistChannel(String id) => Channel(
  id: id,
  number: 1,
  name: 'Playlist',
  source: const PlaylistSource('playlist'),
  playbackMode: PlaybackMode.sequential,
  anchor: DateTime.utc(2026),
  shuffleSeed: 1,
);

Channel _generatedChannel(String id, int number, {String? builderKey}) =>
    Channel(
      id: id,
      number: number,
      name: 'Generated $id',
      source: const LibrarySource(
        libraryId: 'movies',
        libraryType: PlexLibraryType.movie,
      ),
      playbackMode: PlaybackMode.sequential,
      anchor: DateTime.utc(2026),
      shuffleSeed: number,
      builderKey: builderKey ?? 'generated-$id',
    );

class _MemoryStore implements AppStore {
  _MemoryStore([
    this.state = const PersistedState(),
    this.recoveredCorruptState = false,
  ]);

  PersistedState state;
  final bool recoveredCorruptState;
  bool failNextSave = false;
  String failureMessage = 'save failed';

  @override
  Future<String> clientIdentifier() async =>
      'lineup-desktop-test-abcdefghijklmnopqrst';

  @override
  Future<AppStoreLoadResult> load() async =>
      AppStoreLoadResult(state, recoveredCorruptState: recoveredCorruptState);

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

class _AmbiguousWriteCredentials extends _MemoryCredentials {
  final clearStarted = Completer<void>();
  final finishClear = Completer<void>();

  @override
  Future<void> writeAccountToken(String token) async {
    accountToken = token;
    throw StateError('opaque-secret-sentinel');
  }

  @override
  Future<void> clear() async {
    clearStarted.complete();
    await finishClear.future;
    await super.clear();
  }
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

class _CountingMemoryStore extends _MemoryStore {
  _CountingMemoryStore([super.state]);

  int saveCalls = 0;

  @override
  Future<void> save(PersistedState value) async {
    saveCalls++;
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
  final finishLoad = Completer<AppStoreLoadResult>();

  @override
  Future<AppStoreLoadResult> load() => finishLoad.future;
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
  Future<AppStoreLoadResult> load() async => AppStoreLoadResult(state);

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
  Future<List<PlexHomeUser>> Function(String)? homeUsersHandler;
  Future<String?> Function(PlexPin)? pollHandler;
  Future<List<PlexMediaItem>> Function(Uri, String, String, PlexLibraryType)?
  libraryItemsHandler;
  Future<List<PlexMediaItem>> Function(
    Uri,
    String,
    String,
    PlexLibraryType,
    bool Function(),
    void Function(PlexLibraryPageProgress),
  )?
  libraryItemsScanHandler;
  Future<List<PlexLibrary>> Function(Uri, String)? librariesHandler;
  Future<PlexPlaylistCatalog> Function(Uri, String)? playlistsHandler;
  Future<List<PlexServerAccess>> Function(String)? discoverServersHandler;
  Future<Uint8List> Function(Uri, String, Uri)? artworkHandler;
  List<PlexPlaybackPartDescriptor>? playbackDescriptorResult;
  final playbackItems = <PlexMediaItem>[];
  final discoveredTokens = <String>[];
  final accountTokens = <String>[];
  final homeUsersTokens = <String>[];
  final selectedTokens = <String>[];
  final libraryTokens = <String>[];
  final itemTokens = <String>[];
  final playlistTokens = <String>[];
  List<PlexServer> serversResult = const [];
  String resourceToken = 'pms-token';
  PlexConnection? connectionResult;
  Future<PlexConnection> Function(PlexServer, String)? selectConnectionHandler;
  Future<String> Function(String, String, String?)? switchHomeUserHandler;
  List<PlexLibrary> librariesResult = const [];
  int pollCalls = 0;
  int createPinCalls = 0;
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
    return homeUsersHandler?.call(accountToken) ?? homeUsersResult;
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
  Future<PlexPin> createPin() async {
    createPinCalls++;
    return pinResult!;
  }

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
    PlexLibraryType libraryType, {
    required bool Function() isCurrent,
    required void Function(PlexLibraryPageProgress progress) onProgress,
  }) async {
    itemTokens.add(token);
    final scanHandler = libraryItemsScanHandler;
    if (scanHandler != null) {
      return scanHandler(
        server,
        token,
        libraryId,
        libraryType,
        isCurrent,
        onProgress,
      );
    }
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
  List<PlexPlaybackPartDescriptor> playbackDescriptor({
    required Uri server,
    required PlexMediaItem item,
  }) {
    playbackItems.add(item);
    return playbackDescriptorResult ??
        super.playbackDescriptor(server: server, item: item);
  }

  @override
  void close() {}
}

class _ThrowingPlaybackPlex extends _FakePlex {
  @override
  List<PlexPlaybackPartDescriptor> playbackDescriptor({
    required Uri server,
    required PlexMediaItem item,
  }) => throw StateError('programmer error');
}

class _ThrowOncePlaybackPlex extends _FakePlex {
  _ThrowOncePlaybackPlex(this.itemId);

  final String itemId;
  int attempts = 0;

  @override
  List<PlexPlaybackPartDescriptor> playbackDescriptor({
    required Uri server,
    required PlexMediaItem item,
  }) {
    if (item.id == itemId) {
      attempts++;
      if (attempts == 1) throw StateError('unexpected projection failure');
    }
    return super.playbackDescriptor(server: server, item: item);
  }
}
