import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

void main() {
  final sources = [
    '/library/metadata/1/thumb',
    '/photo/people/1',
    'https://metadata-static.plex.tv/people/1.jpg',
    'https://images.example/1.jpg?size=large',
    'http://images.example/1.jpg',
  ];
  for (final source in sources) {
    test('selected PMS transcodes portrait source $source', () async {
      final requests = <http.Request>[];
      final controller = await _controller((request) async {
        requests.add(request);
        return http.Response.bytes([1, 2, 3], 200);
      });
      expect(
        await controller.artworkForPath(
          Uri.parse(source),
          width: 180,
          height: 180,
        ),
        [1, 2, 3],
      );
      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.url.origin, _servers.first.connections.single.uri.origin);
      expect(request.url.path, '/photo/:/transcode');
      expect(request.url.queryParameters, {
        'width': '180',
        'height': '180',
        'minSize': '1',
        'upscale': '1',
        'url': source,
      });
      expect(request.headers['X-Plex-Token'], 'pms-token');
      expect(request.url.toString(), isNot(contains('pms-token')));
      expect(request.followRedirects, isFalse);
    });
  }

  test('unsafe portrait sources are rejected before transport', () async {
    final controller = await _controller(
      (_) async => throw StateError('unexpected request'),
    );
    for (final source in [
      'https://user@images.example/1',
      'https://images.example/1#fragment',
      'file:///portrait',
      '//images.example/portrait',
      '/library/../portrait',
      '/library/%2e%2e/portrait',
      '/library/portrait?secret=1',
      'https://images.example/${'x' * 2048}',
    ]) {
      expect(canonicalPlexCastPortraitText(source), isNull);
      if (source == '/library/../portrait') continue;
      expect(
        await controller.artworkForPath(
          Uri.parse(source),
          width: 72,
          height: 72,
        ),
        isNull,
      );
    }
  });

  test(
    'failed transcoder records only bounded source/failure counts',
    () async {
      final controller = await _controller((_) async => http.Response('', 500));
      expect(
        await controller.artworkForPath(
          Uri.parse('https://images.example/private-name.jpg'),
          width: 72,
          height: 72,
        ),
        isNull,
      );
      final entry = controller.diagnostics.entries.single;
      expect(entry.message, 'Cast portrait unavailable');
      expect(entry.context, {
        'code': 'portrait_https',
        'failureCode': 'unavailable',
        'count': 1,
      });
      expect(entry.context.toString(), isNot(contains('private-name')));
      expect(entry.context.toString(), isNot(contains('images.example')));
    },
  );

  for (final retirement in ['switch', 'logout']) {
    test('$retirement rejects a late successful portrait', () async {
      final started = Completer<void>();
      final response = Completer<http.Response>();
      final controller = await _controller((_) {
        started.complete();
        return response.future;
      });
      final portrait = controller.artworkForPath(
        Uri.parse('https://images.example/1.jpg'),
        width: 72,
        height: 72,
      );
      await started.future;
      if (retirement == 'switch') {
        await controller.selectServer(_servers.last);
        expect(controller.server?.id, 'b');
      } else {
        await controller.logout();
        expect(controller.server, isNull);
      }
      response.complete(http.Response.bytes([1, 2, 3], 200));
      expect(await portrait, isNull);
      expect(
        controller.diagnostics.entries.where(
          (entry) => entry.message == 'Cast portrait unavailable',
        ),
        isEmpty,
      );
    });
  }
}

Future<LineupController> _controller(
  Future<http.Response> Function(http.Request) handler,
) async {
  final plex = _PortraitPlex(handler);
  final controller = LineupController(
    store: _Store(),
    credentials: _Credentials(),
    plex: plex,
  );
  addTearDown(controller.dispose);
  await controller.initialize();
  expect(controller.server?.id, 'a');
  return controller;
}

final _servers = [
  for (final id in ['a', 'b'])
    PlexServer(
      id: id,
      name: 'Synthetic',
      connections: [
        PlexConnection(
          uri: Uri.parse('https://server-$id.example:32400'),
          local: false,
          relay: false,
        ),
      ],
    ),
];

class _PortraitPlex extends PlexClient {
  _PortraitPlex(Future<http.Response> Function(http.Request) handler)
    : super(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient(handler),
      );
  @override
  Future<PlexAccount> account(String token) async =>
      const PlexAccount(id: 'owner', name: 'Owner', email: '');
  @override
  Future<List<PlexHomeUser>> homeUsers(String token) async => const [];
  @override
  Future<List<PlexServerAccess>> discoverServers(String token) async => [
    for (final server in _servers)
      PlexServerAccess(server: server, token: 'pms-token'),
  ];
  @override
  Future<PlexConnection> selectConnection(
    PlexServer server,
    String token,
  ) async => server.connections.single;
  @override
  Future<List<PlexLibrary>> libraries(Uri server, String token) async =>
      const [];
}

class _Store implements AppStore {
  PersistedState state = const PersistedState(
    selectedServerByProfile: {'owner': 'a'},
    settings: LineupSettings(diagnosticsEnabled: true),
  );
  @override
  Future<AppStoreLoadResult> load() async => AppStoreLoadResult(state);
  @override
  Future<void> save(PersistedState value) async => state = value;
  @override
  Future<String> clientIdentifier() async =>
      'lineup-desktop-test-abcdefghijklmnopqrst';
}

class _Credentials implements CredentialStore {
  @override
  Future<String?> readAccountToken() async => 'account-token';
  @override
  Future<String?> readProfileToken(String profileId) async => null;
  @override
  Future<void> writeAccountToken(String token) async {}
  @override
  Future<void> writeProfileToken(String profileId, String token) async {}
  @override
  Future<void> clear() async {}
}
