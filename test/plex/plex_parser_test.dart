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
      'Media': [
        {
          'container': 'MKV',
          'videoCodec': 'HEVC',
          'audioCodec': 'EAC3',
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
  });

  test('rejects missing media identity', () {
    expect(() => parseMediaItem({'title': 'No id'}), throwsA(isA<Exception>()));
  });
}
