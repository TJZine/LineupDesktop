import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
      expect(probed, containsAll(['wrong.example', 'right.example']));
    },
  );

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
