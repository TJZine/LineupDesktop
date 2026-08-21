import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/playback/stream_policy.dart';
import 'package:lineup_desktop/plex/plex_client.dart';

void main() {
  test('parses collection metadata for builder sources', () {
    final item = parseMediaItem({
      'ratingKey': '1',
      'key': '/library/metadata/1',
      'title': 'Movie',
      'type': 'movie',
      'duration': 1000,
      'Collection': [
        {'tag': 'Friday Night'},
      ],
    });
    expect(item.collections, ['Friday Night']);
  });

  test('parses media, part, streams, and Dolby Vision facts', () {
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
          'DOVIPresent': true,
          'Part': [
            {
              'key': '/library/parts/1/file.mkv',
              'Stream': [
                {'id': 1, 'streamType': 2, 'codec': 'eac3', 'selected': 1},
                {'id': 2, 'streamType': 3, 'codec': 'srt', 'key': '/subs/2'},
              ],
            },
          ],
        },
      ],
    });
    expect(item.container, 'mkv');
    expect(item.videoCodec, 'hevc');
    expect(item.dynamicRange, DynamicRange.dolbyVision);
    expect(item.tracks.last.delivery, SubtitleDelivery.sidecar);
    expect(item.summary, 'A first episode.');
    expect(item.contentRating, 'TV-14');
    expect(item.seasonNumber, 1);
    expect(item.episodeNumber, 2);
    expect(item.videoResolution, '4k');
    expect(item.audioChannels, 6);
  });

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
