import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/content_resolver.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

void main() {
  const media = [
    PlexMediaItem(
      id: 'a',
      key: '/a',
      title: 'A',
      type: 'movie',
      duration: Duration(minutes: 1),
      libraryId: 'movies',
      genres: ['Comedy'],
    ),
    PlexMediaItem(
      id: 'b',
      key: '/b',
      title: 'B',
      type: 'movie',
      duration: Duration(minutes: 1),
      libraryId: 'movies',
      genres: ['Drama'],
      viewed: true,
    ),
    PlexMediaItem(
      id: 'c',
      key: '/c',
      title: 'C',
      type: 'episode',
      duration: Duration(minutes: 1),
      libraryId: 'shows',
    ),
  ];

  test(
    'library resolution respects provenance, filters, and watched policy',
    () {
      final items = resolveContent(
        const LibrarySource(
          libraryId: 'movies',
          libraryType: PlexLibraryType.movie,
          includeWatched: false,
          filters: {'genre': 'Comedy'},
        ),
        media,
      );
      expect(items.map((item) => item.id), ['a']);
    },
  );

  test('mixed interleave is stable for uneven sources', () {
    final source = MixedSource(
      interleave: true,
      sources: [
        ManualSource([channelItemFor(media[0]), channelItemFor(media[1])]),
        ManualSource([channelItemFor(media[2])]),
      ],
    );
    expect(resolveContent(source, media).map((item) => item.id), [
      'a',
      'c',
      'b',
    ]);
  });
}
