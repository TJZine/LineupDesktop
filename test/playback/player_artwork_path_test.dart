import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/channel_artwork.dart';

void main() {
  test('poster path prefers series artwork and preserves item fallback', () {
    final poster = Uri.parse('/synthetic/poster');
    for (final (series, expected) in <(String?, Uri?)>[
      (null, poster),
      ('', poster),
      ('http://[', poster),
      ('/synthetic/series', Uri.parse('/synthetic/series')),
    ]) {
      expect(
        posterPath(
          ChannelItem(
            id: 'item',
            title: 'Program',
            duration: const Duration(minutes: 1),
            showThumb: series,
            poster: poster,
          ),
        ),
        expected,
      );
    }
    expect(
      posterPath(
        ChannelItem(
          id: 'empty',
          title: 'Program',
          duration: const Duration(minutes: 1),
        ),
      ),
      isNull,
    );
  });
}
