import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/playback/stream_policy.dart';
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
      expect(servers.single.connections, hasLength(1));
      expect(
        servers.single.connections.single.uri.toString(),
        'https://plex.example:32400',
      );
    },
  );

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

  test('playback descriptors reject unsupported facts', () {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
    );
    expect(
      () => client.playbackDescriptor(
        server: Uri.parse('https://plex.example:32400'),
        token: 'secret',
        item: const PlexMediaItem(
          id: '1',
          key: '/library/metadata/1',
          title: 'Movie',
          type: 'movie',
          duration: Duration(minutes: 1),
          partPath: '/library/parts/1/file.mkv',
          dynamicRange: DynamicRange.unknown,
        ),
        capabilities: const StreamCapabilities(
          containers: {'mkv'},
          videoCodecs: {'h264'},
          audioCodecs: {'aac'},
        ),
      ),
      throwsA(isA<PlexException>()),
    );
  });

  test('direct stream targets the playable part with Plex HLS flags', () {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
    );
    final descriptor = client.playbackDescriptor(
      server: Uri.parse('https://plex.example:32400'),
      token: 'secret',
      item: const PlexMediaItem(
        id: '1',
        key: '/library/metadata/1',
        title: 'Movie',
        type: 'movie',
        duration: Duration(minutes: 1),
        partPath: '/library/parts/1/file.mkv',
        container: 'mkv',
        videoCodec: 'h264',
        audioCodec: 'aac',
        dynamicRange: DynamicRange.sdr,
      ),
      capabilities: const StreamCapabilities(
        containers: {'mp4'},
        videoCodecs: {'h264'},
        audioCodecs: {'aac'},
      ),
    );
    expect(descriptor.decision.kind, StreamDecisionKind.directStream);
    expect(
      descriptor.uri.queryParameters,
      containsPair('path', '/library/parts/1/file.mkv'),
    );
    expect(descriptor.uri.queryParameters, containsPair('protocol', 'hls'));
    expect(descriptor.uri.queryParameters, containsPair('directStream', '1'));
    expect(descriptor.uri.queryParameters, isNot(contains('directPlay')));
  });

  test('artwork stays credential-scoped and enforces its byte bound', () async {
    late http.Request request;
    final artworkUnavailable = throwsA(
      isA<PlexException>().having(
        (exception) => exception.code,
        'code',
        'artwork-unavailable',
      ),
    );
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((value) async {
        request = value;
        if (value.url.path == '/redirect') {
          return http.Response('', 302, headers: {'location': '/other'});
        }
        return http.Response.bytes([1, 2, 3, 4], 200);
      }),
    );
    final bytes = await client.artwork(
      Uri.parse('https://plex.example:32400'),
      'secret',
      Uri.parse('/library/art/1'),
      maximumBytes: 4,
    );
    expect(bytes, [1, 2, 3, 4]);
    expect(request.url.host, 'plex.example');
    expect(request.headers['X-Plex-Token'], 'secret');

    for (final mismatchedArtwork in [
      Uri.parse('https://attacker.example/art'),
      Uri.parse('http://plex.example:32400/art'),
      Uri.parse('https://plex.example:32401/art'),
      Uri.parse('https://user@plex.example:32400/art'),
    ]) {
      await expectLater(
        client.artwork(
          Uri.parse('https://plex.example:32400'),
          'secret',
          mismatchedArtwork,
        ),
        artworkUnavailable,
      );
    }

    await expectLater(
      client.artwork(
        Uri.parse('https://plex.example:32400'),
        'secret',
        Uri.parse('/redirect'),
      ),
      artworkUnavailable,
    );
    expect(request.url.path, '/redirect');
    expect(request.followRedirects, isFalse);

    await expectLater(
      client.artwork(
        Uri.parse('https://plex.example:32400'),
        'secret',
        Uri.parse('/library/art/1'),
        maximumBytes: 3,
      ),
      artworkUnavailable,
    );
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
                      'duration': 1000,
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
      );
      final playlists = await client.playlists(
        Uri.parse('https://plex.example:32400'),
        'secret',
      );
      expect(episodes.single.type, 'episode');
      expect(requests.first.queryParameters['type'], '4');
      expect(playlists.playlists.single.title, 'Favorites');
      expect(playlists.playlists.single.items.single.id, 'm1');
      expect(requests.last.host, 'plex.example');
      expect(requests.last.path, '/playlists/p1/items');
      expect(playlists.failedIds, isEmpty);
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
