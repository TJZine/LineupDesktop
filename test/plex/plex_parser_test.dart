import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

void main() {
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
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
    );
    addTearDown(client.close);

    expect(item.parts.map((part) => part.path), ['/library/parts/valid.mkv']);
    expect(item.parts.single.duration, const Duration(seconds: 1));
    expect(unsupported.parts, isEmpty);
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

  test('rejects missing media identity', () {
    expect(() => parseMediaItem({'title': 'No id'}), throwsA(isA<Exception>()));
  });
}
