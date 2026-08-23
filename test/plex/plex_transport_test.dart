import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

void main() {
  test('transport timeouts surface a stable Plex error', () async {
    final response = Completer<http.Response>();
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      requestTimeout: const Duration(milliseconds: 5),
      httpClient: MockClient((_) => response.future),
    );
    await expectLater(
      client.createPin(),
      throwsA(
        isA<PlexException>().having(
          (exception) => exception.code,
          'code',
          'network-timeout',
        ),
      ),
    );
  });

  test('PIN requests send stable identity without a credential', () async {
    late http.Request request;
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((value) async {
        request = value;
        return http.Response(
          jsonEncode({
            'id': 5,
            'code': 'ABCD',
            'expiresAt': '2026-01-01T01:00:00Z',
          }),
          201,
        );
      }),
    );
    final pin = await client.createPin();
    expect(pin.code, 'ABCD');
    expect(
      request.headers['X-Plex-Client-Identifier'],
      'lineup-desktop-test-abcdefghijklmnopqrst',
    );
    expect(request.headers, isNot(contains('X-Plex-Token')));
  });

  test(
    'discovery rejects credential-bearing and unsupported connections',
    () async {
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode([
              {
                'clientIdentifier': 'safe',
                'name': 'Server',
                'provides': 'server',
                'accessToken': 'pms-token-sentinel',
                'connections': [
                  {
                    'uri': 'https://plex.example:32400',
                    'local': true,
                    'relay': false,
                  },
                  {
                    'uri': 'https://user:pass@bad.example',
                    'local': true,
                    'relay': false,
                  },
                  {'uri': 'ftp://bad.example', 'local': true, 'relay': false},
                  {
                    'uri': 'http://plaintext.example',
                    'local': true,
                    'relay': false,
                  },
                ],
              },
            ]),
            200,
          ),
        ),
      );
      final servers = await client.discoverServers('private-token');
      expect(servers.single.server.connections, hasLength(1));
      expect(
        servers.single.server.connections.single.uri.toString(),
        'https://plex.example:32400',
      );
      expect(servers.single.token, 'pms-token-sentinel');
      expect(servers.single.toString(), isNot(contains('pms-token-sentinel')));
    },
  );

  test('discovery omits resources without a non-empty PMS token', () async {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode([
            for (final token in [null, '', '   '])
              {
                'clientIdentifier': 'server-${token ?? 'missing'}',
                'name': 'Server',
                'provides': 'server',
                'accessToken': ?token,
                'connections': [
                  {
                    'uri': 'https://plex.example:32400',
                    'local': true,
                    'relay': false,
                  },
                ],
              },
          ]),
          200,
        ),
      ),
    );

    expect(await client.discoverServers('cloud-token'), isEmpty);
  });

  test(
    'connection probing binds the identity to the selected server',
    () async {
      final probed = <String>[];
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          probed.add(request.url.host);
          final id = request.url.host == 'wrong.example' ? 'other' : 'expected';
          return http.Response(
            '<MediaContainer machineIdentifier="$id"/>',
            200,
          );
        }),
      );
      final selected = await client.selectConnection(
        PlexServer(
          id: 'expected',
          name: 'Server',
          connections: [
            PlexConnection(
              uri: Uri.parse('https://wrong.example:32400'),
              local: true,
              relay: false,
            ),
            PlexConnection(
              uri: Uri.parse('https://right.example:32400'),
              local: true,
              relay: false,
            ),
          ],
        ),
        'secret',
      );
      expect(selected.uri.host, 'right.example');
      expect(selected.latency, isNotNull);
      expect(probed, containsAll(['wrong.example', 'right.example']));
    },
  );

  test('connection probing ignores a timed-out candidate', () async {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        if (request.url.host == 'slow.example') throw TimeoutException('slow');
        return http.Response(
          '<MediaContainer machineIdentifier="expected"/>',
          200,
        );
      }),
    );

    final selected = await client.selectConnection(
      PlexServer(
        id: 'expected',
        name: 'Server',
        connections: [
          PlexConnection(
            uri: Uri.parse('https://slow.example:32400'),
            local: true,
            relay: false,
          ),
          PlexConnection(
            uri: Uri.parse('https://ready.example:32400'),
            local: true,
            relay: false,
          ),
        ],
      ),
      'secret',
    );

    expect(selected.uri.host, 'ready.example');
  });

  for (final (status, code) in [
    (401, 'auth-required'),
    (403, 'access-denied'),
  ]) {
    test('connection probing preserves HTTP $status failures', () async {
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((_) async => http.Response('', status)),
      );

      await expectLater(
        client.selectConnection(
          PlexServer(
            id: 'expected',
            name: 'Server',
            connections: [
              PlexConnection(
                uri: Uri.parse('https://server.example:32400'),
                local: true,
                relay: false,
              ),
            ],
          ),
          'secret',
        ),
        throwsA(
          isA<PlexException>().having(
            (exception) => exception.code,
            'code',
            code,
          ),
        ),
      );
    });
  }

  test(
    'authorization failure does not hide a reachable same-tier endpoint',
    () async {
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          if (request.url.host == 'unauthorized.example') {
            return http.Response('', 401);
          }
          return http.Response(
            '<MediaContainer machineIdentifier="expected"/>',
            200,
          );
        }),
      );

      final selected = await client.selectConnection(
        PlexServer(
          id: 'expected',
          name: 'Server',
          connections: [
            PlexConnection(
              uri: Uri.parse('https://unauthorized.example:32400'),
              local: true,
              relay: false,
            ),
            PlexConnection(
              uri: Uri.parse('https://reachable.example:32400'),
              local: true,
              relay: false,
            ),
          ],
        ),
        'secret',
      );

      expect(selected.uri.host, 'reachable.example');
    },
  );

  test(
    'authorization failure does not prevent a reachable fallback tier',
    () async {
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          if (request.url.host == 'local.example') {
            return http.Response('', 403);
          }
          return http.Response(
            '<MediaContainer machineIdentifier="expected"/>',
            200,
          );
        }),
      );

      final selected = await client.selectConnection(
        PlexServer(
          id: 'expected',
          name: 'Server',
          connections: [
            PlexConnection(
              uri: Uri.parse('https://local.example:32400'),
              local: true,
              relay: false,
            ),
            PlexConnection(
              uri: Uri.parse('https://relay.example:32400'),
              local: false,
              relay: true,
            ),
          ],
        ),
        'secret',
      );

      expect(selected.uri.host, 'relay.example');
    },
  );

  test(
    'connection probing is bounded to eight advertised candidates',
    () async {
      var probes = 0;
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((_) async {
          probes++;
          return http.Response(
            '<MediaContainer machineIdentifier="other"/>',
            200,
          );
        }),
      );
      await expectLater(
        client.selectConnection(
          PlexServer(
            id: 'expected',
            name: 'Server',
            connections: List.generate(
              20,
              (index) => PlexConnection(
                uri: Uri.parse('https://server-$index.example:32400'),
                local: true,
                relay: false,
              ),
            ),
          ),
          'secret',
        ),
        throwsA(isA<PlexException>()),
      );
      expect(probes, 8);
    },
  );

  test('connection priority is applied before the probe bound', () async {
    final probed = <String>[];
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        probed.add(request.url.host);
        return http.Response(
          '<MediaContainer machineIdentifier="expected"/>',
          200,
        );
      }),
    );
    final selected = await client.selectConnection(
      PlexServer(
        id: 'expected',
        name: 'Server',
        connections: [
          for (var index = 0; index < 8; index++)
            PlexConnection(
              uri: Uri.parse('https://relay-$index.example:32400'),
              local: false,
              relay: true,
            ),
          PlexConnection(
            uri: Uri.parse('https://local.example:32400'),
            local: true,
            relay: false,
          ),
        ],
      ),
      'secret',
    );

    expect(selected.uri.host, 'local.example');
    expect(probed, contains('local.example'));
    expect(probed.length, lessThanOrEqualTo(8));
  });

  test('the probe bound reserves a reachable fallback tier', () async {
    final probed = <String>[];
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        probed.add(request.url.host);
        final id = request.url.host == 'relay.example' ? 'expected' : 'other';
        return http.Response('<MediaContainer machineIdentifier="$id"/>', 200);
      }),
    );
    final selected = await client.selectConnection(
      PlexServer(
        id: 'expected',
        name: 'Server',
        connections: [
          for (var index = 0; index < 8; index++)
            PlexConnection(
              uri: Uri.parse('https://local-$index.example:32400'),
              local: true,
              relay: false,
            ),
          PlexConnection(
            uri: Uri.parse('https://relay.example:32400'),
            local: false,
            relay: true,
          ),
        ],
      ),
      'secret',
    );

    expect(selected.uri.host, 'relay.example');
    expect(probed, contains('relay.example'));
    expect(probed.length, 8);
  });

  test('an empty ordered part list is unsupported media', () {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
    );
    expect(
      () => client.playbackDescriptor(
        server: Uri.parse('https://plex.example:32400'),
        item: PlexMediaItem(
          id: 'empty',
          title: 'Empty',
          type: 'movie',
          duration: Duration.zero,
        ),
      ),
      throwsA(
        isA<PlexException>().having(
          (exception) => exception.code,
          'code',
          'unsupported',
        ),
      ),
    );
  });

  test('direct play retains the selected Plex server origin', () {
    final descriptor = _directPlaybackDescriptor('/library/parts/1/file.mkv');

    expect(
      descriptor.single.uri,
      Uri.parse('https://plex.example:32400/library/parts/1/file.mkv'),
    );
  });

  test('multipart descriptors preserve order and origin', () {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
    );
    final descriptor = client.playbackDescriptor(
      server: Uri.parse('https://plex.example:32400'),
      item: PlexMediaItem(
        id: '1',
        title: 'Movie',
        type: 'movie',
        duration: Duration(minutes: 2),
        parts: [
          PlexMediaPart(
            path: '/library/parts/one.mkv',
            duration: Duration(minutes: 1),
          ),
          PlexMediaPart(path: '/library/parts/two.mkv'),
        ],
        container: 'mkv',
        videoCodec: 'h264',
        audioCodec: 'aac',
        dynamicRange: DynamicRange.sdr,
      ),
    );

    expect(descriptor.map((part) => part.uri), [
      Uri.parse('https://plex.example:32400/library/parts/one.mkv'),
      Uri.parse('https://plex.example:32400/library/parts/two.mkv'),
    ]);
    expect(descriptor.first.duration, const Duration(minutes: 1));
    expect(descriptor.last.duration, isNull);
    expect(
      descriptor.expand((part) => part.uri.queryParameters.keys),
      isNot(contains('X-Plex-Token')),
    );
    expect(
      () => descriptor.add(
        PlexPlaybackPartDescriptor(uri: Uri.parse('https://plex.example/new')),
      ),
      throwsUnsupportedError,
    );
  });

  test('multipart descriptors reject a cross-origin part', () {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
    );
    expect(
      () => client.playbackDescriptor(
        server: Uri.parse('https://plex.example:32400'),
        item: PlexMediaItem(
          id: '1',
          title: 'Movie',
          type: 'movie',
          duration: Duration(minutes: 2),
          parts: [
            PlexMediaPart(path: '/library/parts/one.mkv'),
            PlexMediaPart(path: 'https://attacker.example/two.mkv'),
          ],
          container: 'mkv',
          videoCodec: 'h264',
          audioCodec: 'aac',
          dynamicRange: DynamicRange.sdr,
        ),
      ),
      throwsA(isA<PlexException>()),
    );
  });

  for (final mismatch in {
    'host': 'https://attacker.example/file.mkv',
    'network path': '//attacker.example/file.mkv',
    'scheme': 'http://plex.example:32400/file.mkv',
    'port': 'https://plex.example:32401/file.mkv',
    'userinfo': 'https://user@plex.example:32400/file.mkv',
  }.entries) {
    test('direct play rejects ${mismatch.key} mismatch', () {
      expect(
        () => _directPlaybackDescriptor(mismatch.value),
        throwsA(
          isA<PlexException>().having(
            (exception) => exception.code,
            'code',
            'unsupported',
          ),
        ),
      );
    });
  }

  group('artwork transport', () {
    Matcher plexError(String code) => throwsA(
      isA<PlexException>().having((exception) => exception.code, 'code', code),
    );

    PlexClient client(
      Future<http.StreamedResponse> Function(http.BaseRequest, http.ByteStream)
      handler,
    ) => PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient.streaming(handler),
    );

    test('scopes credentials to the selected server', () async {
      late http.BaseRequest request;
      final plex = client((value, _) async {
        request = value;
        return http.StreamedResponse(Stream.value([1, 2, 3, 4]), 200);
      });

      final bytes = await plex.artwork(
        Uri.parse('https://plex.example:32400'),
        'secret',
        Uri.parse('/library/art/1'),
        maximumBytes: 4,
      );

      expect(bytes, [1, 2, 3, 4]);
      expect(request.url.host, 'plex.example');
      expect(request.headers['X-Plex-Token'], 'secret');
    });

    for (final mismatch in {
      'host': 'https://attacker.example/art',
      'scheme': 'http://plex.example:32400/art',
      'port': 'https://plex.example:32401/art',
      'userinfo': 'https://user@plex.example:32400/art',
    }.entries) {
      test('rejects ${mismatch.key} mismatch before sending', () async {
        final plex = client((_, _) async => throw StateError('sent request'));

        await expectLater(
          plex.artwork(
            Uri.parse('https://plex.example:32400'),
            'secret',
            Uri.parse(mismatch.value),
          ),
          plexError('artwork-unavailable'),
        );
      });
    }

    test('rejects redirects and cancels the response stream', () async {
      late http.BaseRequest request;
      final canceled = Completer<void>();
      final stream = StreamController<List<int>>(onCancel: canceled.complete);
      final plex = client((value, _) async {
        request = value;
        return http.StreamedResponse(
          stream.stream,
          302,
          headers: {'location': '/other'},
        );
      });

      await expectLater(
        plex.artwork(
          Uri.parse('https://plex.example:32400'),
          'secret',
          Uri.parse('/redirect'),
        ),
        plexError('artwork-unavailable'),
      );
      await canceled.future.timeout(const Duration(seconds: 1));

      expect(request.followRedirects, isFalse);
      expect(canceled.isCompleted, isTrue);
    });

    for (final failure in {401: 'auth-invalid', 403: 'access-denied'}.entries) {
      test('preserves ${failure.key} authorization classification', () async {
        final plex = client(
          (_, _) async =>
              http.StreamedResponse(const Stream.empty(), failure.key),
        );

        await expectLater(
          plex.artwork(
            Uri.parse('https://plex.example:32400'),
            'resource-token',
            Uri.parse('/art'),
          ),
          plexError(failure.value),
        );
      });
    }

    test('rejects declared-length overflow and cancels the stream', () async {
      final canceled = Completer<void>();
      final stream = StreamController<List<int>>(onCancel: canceled.complete);
      final plex = client(
        (_, _) async =>
            http.StreamedResponse(stream.stream, 200, contentLength: 4),
      );

      await expectLater(
        plex.artwork(
          Uri.parse('https://plex.example:32400'),
          'secret',
          Uri.parse('/library/art/1'),
          maximumBytes: 3,
        ),
        plexError('artwork-too-large'),
      );
      await canceled.future.timeout(const Duration(seconds: 1));

      expect(canceled.isCompleted, isTrue);
    });

    test('rejects streamed overflow', () async {
      final plex = client(
        (_, _) async => http.StreamedResponse(Stream.value([1, 2, 3, 4]), 200),
      );

      await expectLater(
        plex.artwork(
          Uri.parse('https://plex.example:32400'),
          'secret',
          Uri.parse('/library/art/1'),
          maximumBytes: 3,
        ),
        plexError('artwork-too-large'),
      );
    });
  });

  test(
    'show libraries load episode rows and playlists load their items',
    () async {
      final requests = <Uri>[];
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          requests.add(request.url);
          if (request.url.path == '/library/sections/7/all') {
            return http.Response(
              jsonEncode({
                'MediaContainer': {
                  'Metadata': [
                    {
                      'ratingKey': 'e1',
                      'key': '/library/metadata/e1',
                      'title': 'Pilot',
                      'type': 'episode',
                      'duration': '1000',
                      'year': '2026',
                    },
                  ],
                },
              }),
              200,
            );
          }
          if (request.url.path == '/playlists/all') {
            return http.Response(
              jsonEncode({
                'MediaContainer': {
                  'Metadata': [
                    {
                      'ratingKey': 'p1',
                      'key': 'https://attacker.example/steal',
                      'title': 'Favorites',
                    },
                  ],
                },
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'Metadata': [
                  {
                    'ratingKey': 'm1',
                    'key': '/library/metadata/m1',
                    'title': 'Movie',
                    'type': 'movie',
                    'duration': 1000,
                  },
                ],
              },
            }),
            200,
          );
        }),
      );
      final episodes = await client.libraryItems(
        Uri.parse('https://plex.example:32400'),
        'secret',
        '7',
        PlexLibraryType.show,
        isCurrent: () => true,
        onProgress: (_) {},
      );
      final playlists = await client.playlists(
        Uri.parse('https://plex.example:32400'),
        'secret',
      );
      expect(episodes.single.type, 'episode');
      expect(episodes.single.duration, const Duration(seconds: 1));
      expect(episodes.single.year, 2026);
      expect(requests.first.queryParameters['type'], '4');
      expect(playlists.playlists.single.title, 'Favorites');
      expect(playlists.playlists.single.items.single.id, 'm1');
      expect(requests.last.host, 'plex.example');
      expect(requests.last.path, '/playlists/p1/items');
      expect(playlists.failedIds, isEmpty);
    },
  );

  test(
    'library pagination reports exact progress without page snapshots',
    () async {
      var requests = 0;
      final progress = <PlexLibraryPageProgress>[];
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          requests++;
          final start = int.parse(
            request.url.queryParameters['X-Plex-Container-Start']!,
          );
          const total = 2505;
          final count = (total - start).clamp(0, 100);
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'totalSize': total,
                'Metadata': [
                  for (var index = 0; index < count; index++)
                    {
                      'ratingKey': '${start + index}',
                      'key': '/library/metadata/${start + index}',
                      'title': 'Item ${start + index}',
                      'type': 'movie',
                      'duration': 1000,
                    },
                ],
              },
            }),
            200,
          );
        }),
      );

      final items = await client.libraryItems(
        Uri.parse('https://plex.example:32400'),
        'secret',
        '7',
        PlexLibraryType.movie,
        isCurrent: () => true,
        onProgress: progress.add,
      );

      expect(items, hasLength(2505));
      expect(requests, 26);
      expect(
        progress.map((value) => value.completedItems),
        orderedEquals([
          for (var count = 100; count <= 2500; count += 100) count,
          2505,
        ]),
      );
      expect(progress.last.completedPages, 26);
      expect(progress.last.totalItems, 2505);
    },
  );

  test('library pagination checks cancellation before the next page', () async {
    var current = true;
    var requests = 0;
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((_) async {
        requests++;
        current = false;
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'totalSize': 200,
              'Metadata': [
                for (var index = 0; index < 100; index++)
                  {
                    'ratingKey': '$index',
                    'key': '/library/metadata/$index',
                    'title': 'Item $index',
                    'type': 'movie',
                    'duration': 1000,
                  },
              ],
            },
          }),
          200,
        );
      }),
    );

    await expectLater(
      client.libraryItems(
        Uri.parse('https://plex.example:32400'),
        'secret',
        '7',
        PlexLibraryType.movie,
        isCurrent: () => current,
        onProgress: (_) {},
      ),
      throwsA(
        isA<PlexException>().having((error) => error.code, 'code', 'cancelled'),
      ),
    );
    expect(requests, 1);
  });

  test(
    'one thousand full pages return when the reported total is reached',
    () async {
      var requests = 0;
      final page = jsonEncode({
        'MediaContainer': {
          'totalSize': 100000,
          'Metadata': [
            for (var index = 0; index < 100; index++)
              {
                'ratingKey': '$index',
                'key': '/library/metadata/$index',
                'title': 'Item $index',
                'type': 'movie',
                'duration': 1000,
              },
          ],
        },
      });
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((_) async {
          requests++;
          return http.Response(page, 200);
        }),
      );

      final items = await client.libraryItems(
        Uri.parse('https://plex.example:32400'),
        'secret',
        '7',
        PlexLibraryType.movie,
        isCurrent: () => true,
        onProgress: (_) {},
      );

      expect(items, hasLength(100000));
      expect(requests, 1000);
    },
  );

  test(
    'one thousand full library pages fail visibly instead of truncating',
    () async {
      var requests = 0;
      final page = jsonEncode({
        'MediaContainer': {
          'totalSize': 100001,
          'Metadata': [
            for (var index = 0; index < 100; index++)
              {
                'ratingKey': '$index',
                'key': '/library/metadata/$index',
                'title': 'Item $index',
                'type': 'movie',
                'duration': 1000,
              },
          ],
        },
      });
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((_) async {
          requests++;
          return http.Response(page, 200);
        }),
      );

      await expectLater(
        client.libraryItems(
          Uri.parse('https://plex.example:32400'),
          'secret',
          '7',
          PlexLibraryType.movie,
          isCurrent: () => true,
          onProgress: (_) {},
        ),
        throwsA(
          isA<PlexException>().having(
            (error) => error.code,
            'code',
            'library-scale-exceeded',
          ),
        ),
      );
      expect(requests, 1000);
    },
  );

  test(
    'Plex Home falls back from empty v2 users and missing v2 switch',
    () async {
      final paths = <String>[];
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          return switch (request.url.path) {
            '/api/v2/home/users' => http.Response(
              jsonEncode({'users': []}),
              200,
            ),
            '/api/home/users' => http.Response(
              '<MediaContainer><User id="7" title="Home &amp; Away" protected="0"/></MediaContainer>',
              200,
            ),
            '/api/v2/home/users/7/switch' => http.Response('', 404),
            '/api/home/users/7/switch' => http.Response(
              '<user authenticationToken="profile-secret"/>',
              200,
            ),
            _ => http.Response('', 500),
          };
        }),
      );
      final users = await client.homeUsers('account-secret');
      expect(users.single.name, 'Home & Away');
      expect(
        await client.switchHomeUser('account-secret', '7', null),
        'profile-secret',
      );
      expect(paths, [
        '/api/v2/home/users',
        '/api/home/users',
        '/api/v2/home/users/7/switch',
        '/api/home/users/7/switch',
      ]);
    },
  );
}

List<PlexPlaybackPartDescriptor> _directPlaybackDescriptor(String partPath) =>
    PlexClient(clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst')
        .playbackDescriptor(
          server: Uri.parse('https://plex.example:32400'),
          item: PlexMediaItem(
            id: '1',
            title: 'Movie',
            type: 'movie',
            duration: const Duration(minutes: 1),
            parts: [PlexMediaPart(path: partPath)],
            container: 'mkv',
            videoCodec: 'h264',
            audioCodec: 'aac',
            dynamicRange: DynamicRange.sdr,
          ),
        );
