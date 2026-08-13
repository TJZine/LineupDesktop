import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lineup_desktop/plex/plex_client.dart';

void main() {
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
