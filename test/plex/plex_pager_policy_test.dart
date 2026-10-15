import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

void main() {
  final server = Uri.parse('https://synthetic.invalid');
  for (final endpoint in [
    'library items',
    'library metadata',
    'playlist catalog',
    'playlist items',
  ]) {
    test(
      '$endpoint enforces 1000 pages even with sparse unknown totals',
      () async {
        var requests = 0;
        final client = PlexClient(
          clientIdentifier: 'test',
          httpClient: MockClient((request) async {
            final catalog = request.url.path == '/playlists/all';
            final seedCatalog = endpoint == 'playlist items' && catalog;
            if (!seedCatalog) requests++;
            final start = int.parse(
              request.url.queryParameters['X-Plex-Container-Start']!,
            );
            expect(request.url.queryParameters['X-Plex-Container-Size'], '100');
            return http.Response(
              jsonEncode({
                'MediaContainer': {
                  'offset': start,
                  'size': 1,
                  if (seedCatalog) 'totalSize': 1,
                  'Metadata': [
                    {
                      'ratingKey': seedCatalog ? 'playlist' : '$start',
                      'title': 'Synthetic',
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
        addTearDown(client.close);
        final scaleError = throwsA(
          isA<PlexException>().having(
            (error) => error.code,
            'code',
            endpoint.startsWith('library')
                ? 'library-scale-exceeded'
                : 'playlist-scale-exceeded',
          ),
        );
        switch (endpoint) {
          case 'library items':
            await expectLater(
              client.libraryItems(
                server,
                'token',
                'library',
                PlexLibraryType.movie,
                isCurrent: () => true,
                onProgress: (_) {},
              ),
              scaleError,
            );
          case 'library metadata':
            await expectLater(
              client.libraryShowGenres(
                server,
                'token',
                'library',
                isCurrent: () => true,
              ),
              scaleError,
            );
          case 'playlist catalog':
            await expectLater(
              client.playlists(server, 'token', isCurrent: () => true),
              scaleError,
            );
          case 'playlist items':
            final result = await client.playlists(
              server,
              'token',
              isCurrent: () => true,
            );
            expect(result.playlists, isEmpty);
            expect(result.failedIds, {'playlist'});
        }
        expect(requests, 1000);
      },
    );
  }
}
