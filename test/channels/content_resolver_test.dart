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

  test('playlist sources resolve current Plex playlist contents', () {
    const source = PlaylistSource('playlist');
    final resolved = resolveContent(source, const [], [
      PlexPlaylist(id: 'playlist', title: 'Favorites', items: media),
    ]);
    expect(resolved.map((item) => item.id), media.map((item) => item.id));
  });

  test('maps distinct episode artwork and prefers the show poster', () {
    final item = channelItemFor(
      const PlexMediaItem(
        id: 'episode',
        key: '/episode',
        title: 'Episode',
        type: 'episode',
        duration: Duration(minutes: 1),
        grandparentTitle: 'Show',
        thumbPath: '/episode/thumb',
        grandparentThumbPath: '/show/thumb',
        artPath: '/show/art',
        clearLogoPath: '/show/clearlogo',
      ),
    );

    expect(item.artwork, Uri.parse('/episode/thumb'));
    expect(item.showThumb, '/show/thumb');
    expect(item.backdrop, Uri.parse('/show/art'));
    expect(item.clearLogo, Uri.parse('/show/clearlogo'));
  });

  test(
    'channel item artwork additions round-trip while old artwork remains valid',
    () {
      const oldJson = {
        'id': 'old',
        'title': 'Old item',
        'durationMs': 60000,
        'artwork': '/old/poster',
      };
      final oldItem = ChannelItem.fromJson(oldJson);
      expect(oldItem.artwork, Uri.parse('/old/poster'));
      expect(oldItem.backdrop, isNull);
      expect(oldItem.clearLogo, isNull);

      final item = ChannelItem(
        id: 'new',
        title: 'New item',
        duration: Duration(minutes: 1),
        artwork: Uri(path: '/poster'),
        backdrop: Uri(path: '/backdrop'),
        clearLogo: Uri(path: '/logo'),
      );
      expect(ChannelItem.fromJson(item.toJson()).toJson(), item.toJson());
    },
  );
}
