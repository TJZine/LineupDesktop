import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

void main() {
  test('formats connection routes and measured latency boundaries', () {
    PlexConnection connection({
      required bool local,
      required bool relay,
      required int latency,
    }) => PlexConnection(
      uri: Uri.parse('https://synthetic.invalid'),
      local: local,
      relay: relay,
      latency: Duration(milliseconds: latency),
    );

    expect(
      plexConnectionDescription(
        connection(local: true, relay: false, latency: 99),
      ),
      'Direct local • 99 ms measured',
    );
    expect(
      plexConnectionDescription(
        connection(local: false, relay: false, latency: 100),
      ),
      'Direct remote • 100 ms measured • Slow',
    );
    expect(
      plexConnectionDescription(
        connection(local: false, relay: false, latency: 499),
      ),
      'Direct remote • 499 ms measured • Slow',
    );
    expect(
      plexConnectionDescription(
        connection(local: true, relay: true, latency: 500),
      ),
      'Relay • Limited • 500 ms measured • Very slow',
    );
    expect(
      plexConnectionKind(connection(local: true, relay: true, latency: 1)),
      PlexConnectionKind.relay,
    );
  });

  test('parses collection metadata for builder sources', () {
    final item = parseMediaItem({
      'ratingKey': '1',
      'title': 'Movie',
      'type': 'movie',
      'duration': 1000,
      'Collection': [
        {'tag': 'Friday Night'},
      ],
    });
    expect(item.collections, ['Friday Night']);
  });

  test('parses media, part, and Dolby Vision facts', () {
    final item = parseMediaItem({
      'ratingKey': '42',
      'key': '/library/metadata/42',
      'title': 'Pilot',
      'type': 'episode',
      'duration': 3600000,
      'grandparentTitle': 'Show',
      'summary': 'A first episode.',
      'contentRating': 'TV-14',
      'parentIndex': 1,
      'index': 2,
      'Media': [
        {
          'container': 'MKV',
          'videoCodec': 'HEVC',
          'audioCodec': 'EAC3',
          'videoResolution': '4k',
          'audioChannels': 6,
          'Part': [
            {
              'key': '/library/parts/1/file.mkv',
              'Stream': [
                {'codec': 'dovi'},
              ],
            },
          ],
        },
      ],
    });
    expect(item.container, 'mkv');
    expect(item.videoCodec, 'hevc');
    expect(item.dynamicRange, DynamicRange.dolbyVision);
    expect(item.summary, 'A first episode.');
    expect(item.contentRating, 'TV-14');
    expect(item.seasonNumber, 1);
    expect(item.episodeNumber, 2);
    expect(item.videoResolution, '4k');
    expect(item.audioChannels, 6);
  });

  test('preserves every ordered part with positive nullable durations', () {
    final item = parseMediaItem({
      'ratingKey': 'multi',
      'key': '/library/metadata/multi',
      'title': 'Multi-part movie',
      'type': 'movie',
      'duration': 3000,
      'Media': [
        {
          'container': 'mkv',
          'videoCodec': 'h264',
          'audioCodec': 'aac',
          'Part': [
            {'key': '/library/parts/one.mkv', 'duration': 1000},
            {'key': '/library/parts/two.mkv', 'duration': 0},
            {'key': '/library/parts/three.mkv', 'duration': -1},
          ],
        },
        {
          'container': 'mp4',
          'Part': [
            {'key': '/ignored-alternate.mp4'},
          ],
        },
      ],
    });

    expect(item.parts.map((part) => part.path), [
      '/library/parts/one.mkv',
      '/library/parts/two.mkv',
      '/library/parts/three.mkv',
    ]);
    expect(item.parts.map((part) => part.duration), [
      const Duration(seconds: 1),
      null,
      null,
    ]);
  });

  test('drops media parts without a usable path', () {
    final item = parseMediaItem({
      'ratingKey': 'malformed-parts',
      'title': 'Malformed parts',
      'type': 'movie',
      'duration': 3000,
      'Media': [
        {
          'Part': [
            {'duration': 1000},
            {'key': '   ', 'duration': 1000},
            {'key': '/library/parts/valid.mkv', 'duration': 1000},
          ],
        },
      ],
    });
    final unsupported = parseMediaItem({
      'ratingKey': 'no-usable-parts',
      'title': 'No usable parts',
      'type': 'movie',
      'duration': 1000,
      'Media': [
        {
          'Part': [
            {},
            {'key': ''},
          ],
        },
      ],
    });
    final zeroDuration = parseMediaItem({
      'ratingKey': 'zero-duration',
      'title': 'Zero duration',
      'type': 'movie',
      'duration': 0,
      'Media': [
        {
          'Part': [
            {'key': '/library/parts/zero-duration.mkv'},
          ],
        },
      ],
    });
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
    );
    addTearDown(client.close);

    expect(item.parts.map((part) => part.path), ['/library/parts/valid.mkv']);
    expect(item.parts.single.duration, const Duration(seconds: 1));
    expect(item.isPlayable, isTrue);
    expect(unsupported.parts, isEmpty);
    expect(unsupported.isPlayable, isFalse);
    expect(zeroDuration.parts, hasLength(1));
    expect(zeroDuration.duration, Duration.zero);
    expect(zeroDuration.isPlayable, isFalse);
    expect(
      () => client.playbackDescriptor(
        server: Uri.parse('https://plex.example:32400'),
        item: unsupported,
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

  test(
    'accepts quoted numeric metadata and ignores invalid optional values',
    () {
      final item = parseMediaItem({
        'ratingKey': 'quoted',
        'key': '/library/metadata/quoted',
        'title': 'Quoted metadata',
        'type': 'episode',
        'duration': '3600000',
        'year': '2026',
        'parentIndex': '1',
        'index': '2',
        'addedAt': '1720000000',
        'viewCount': '1',
        'Media': [
          {'audioChannels': '6'},
        ],
      });

      expect(item.duration, const Duration(hours: 1));
      expect(item.year, 2026);
      expect(item.seasonNumber, 1);
      expect(item.episodeNumber, 2);
      expect(item.audioChannels, 6);
      expect(item.addedAt, isNotNull);
      expect(item.viewed, isTrue);

      final invalid = parseMediaItem({
        'ratingKey': 'invalid',
        'key': '/library/metadata/invalid',
        'title': 'Invalid metadata',
        'type': 'movie',
        'duration': 'not-a-number',
        'year': true,
        'addedAt': 1e300,
        'viewCount': double.infinity,
      });
      expect(invalid.duration, Duration.zero);
      expect(invalid.year, isNull);
      expect(invalid.addedAt, isNull);
      expect(invalid.viewed, isFalse);
    },
  );

  test('parses episode artwork facts including show poster and clear logo', () {
    final item = parseMediaItem({
      'ratingKey': 'episode-1',
      'key': '/library/metadata/episode-1',
      'title': 'Episode',
      'type': 'episode',
      'duration': 1000,
      'thumb': '/library/metadata/episode-1/thumb',
      'grandparentThumb': '/library/metadata/show-1/thumb',
      'art': '/library/metadata/show-1/art',
      'Image': [
        {'type': 'clearArt', 'url': '/library/metadata/show-1/clearart'},
        {'type': 'clearLogo', 'url': '/library/metadata/show-1/clearlogo'},
      ],
    });

    expect(item.thumbPath, '/library/metadata/episode-1/thumb');
    expect(item.grandparentThumbPath, '/library/metadata/show-1/thumb');
    expect(item.artPath, '/library/metadata/show-1/art');
    expect(item.clearLogoPath, '/library/metadata/show-1/clearlogo');
  });

  test('parses trimmed, deduplicated cast facts and actor names', () {
    final item = parseMediaItem({
      'ratingKey': 'cast-1',
      'title': 'Episode',
      'type': 'episode',
      'duration': 1000,
      'Role': [
        {
          'tag': '  Avery Vale  ',
          'role': '  Detective Rowan  ',
          'thumb': ' /library/metadata/avery/thumb ',
        },
        {'tag': 'avery vale', 'role': 'Duplicate'},
        {'tag': '   ', 'role': 'Blank'},
        {'role': 'Missing name'},
        'malformed',
        {'tag': 'Mina Park'},
        {
          'tag': 'Unsafe Absolute',
          'role': 'Reporter',
          'thumb': 'https://plex.invalid/library/metadata/2/thumb',
        },
        {
          'tag': 'Unsafe Token',
          'role': 'Dispatcher',
          'thumb': '/library/metadata/3/thumb?X-Plex-Token=secret',
        },
        {
          'tag': 'Unsafe Fragment',
          'role': 'Archivist',
          'thumb': '/library/metadata/4/thumb#private',
        },
      ],
    });

    expect(item.actors, [
      'Avery Vale',
      'Mina Park',
      'Unsafe Absolute',
      'Unsafe Token',
      'Unsafe Fragment',
    ]);
    expect(item.cast, hasLength(5));
    expect(item.cast.first.name, 'Avery Vale');
    expect(item.cast.first.role, 'Detective Rowan');
    expect(item.cast.first.thumbPath, '/library/metadata/avery/thumb');
    expect(item.cast[1].role, isNull);
    expect(item.cast[2].role, 'Reporter');
    expect(item.cast[3].role, 'Dispatcher');
    expect(item.cast[4].role, 'Archivist');
    expect(
      item.cast.skip(1),
      everyElement(
        predicate<PlexCastMember>((member) {
          return member.thumbPath == null;
        }),
      ),
    );
  });

  test('rejects missing media identity', () {
    expect(() => parseMediaItem({'title': 'No id'}), throwsA(isA<Exception>()));
  });
}
