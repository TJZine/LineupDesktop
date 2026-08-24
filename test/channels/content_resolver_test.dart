import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/content_resolver.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

void main() {
  final media = [
    PlexMediaItem(
      id: 'a',
      title: 'A',
      type: 'movie',
      duration: Duration(minutes: 1),
      libraryId: 'movies',
      parts: [PlexMediaPart(path: '/parts/a')],
      genres: ['Comedy'],
    ),
    PlexMediaItem(
      id: 'b',
      title: 'B',
      type: 'movie',
      duration: Duration(minutes: 1),
      libraryId: 'movies',
      parts: [PlexMediaPart(path: '/parts/b')],
      genres: ['Drama'],
      viewed: true,
    ),
    PlexMediaItem(
      id: 'c',
      title: 'C',
      type: 'episode',
      duration: Duration(minutes: 1),
      libraryId: 'shows',
      parts: [PlexMediaPart(path: '/parts/c')],
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

  test(
    'library and playlist sources reject positive-duration items without parts',
    () {
      const unsupported = PlexMediaItem(
        id: 'unsupported',
        title: 'Unsupported',
        type: 'movie',
        duration: Duration(minutes: 1),
        libraryId: 'movies',
      );
      const library = LibrarySource(
        libraryId: 'movies',
        libraryType: PlexLibraryType.movie,
      );
      const playlist = PlaylistSource('playlist');

      expect(resolveContent(library, const [unsupported]), isEmpty);
      expect(
        resolveContent(playlist, const [], const [
          PlexPlaylist(id: 'playlist', title: 'Playlist', items: [unsupported]),
        ]),
        isEmpty,
      );
    },
  );

  test('maps distinct episode artwork and prefers the show poster', () {
    final item = channelItemFor(
      const PlexMediaItem(
        id: 'episode',
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

    expect(item.poster, Uri.parse('/episode/thumb'));
    expect(item.showThumb, '/show/thumb');
    expect(item.backdrop, Uri.parse('/show/art'));
    expect(item.clearLogo, Uri.parse('/show/clearlogo'));
  });

  test('channel item poster, backdrop, and logo round-trip canonically', () {
    final item = ChannelItem(
      id: 'new',
      title: 'New item',
      duration: Duration(minutes: 1),
      showTitle: 'Show',
      showThumb: '/show-thumb',
      poster: Uri(path: '/poster'),
      backdrop: Uri(path: '/backdrop'),
      clearLogo: Uri(path: '/logo'),
      summary: 'Summary',
      contentRating: 'TV-14',
      genres: const ['Drama'],
      year: 2026,
      seasonNumber: 2,
      episodeNumber: 3,
      resolution: '1080',
      videoCodec: 'h264',
      audioCodec: 'aac',
      audioChannels: 6,
      dynamicRange: 'sdr',
    );
    expect(ChannelItem.fromJson(item.toJson()).toJson(), item.toJson());
    expect(item.toJson(), containsPair('poster', '/poster'));
    expect(item.toJson(), isNot(contains('artwork')));
  });

  test('legacy artwork is rejected without a poster fallback', () {
    expect(
      () => ChannelItem.fromJson(const {
        'id': 'old',
        'title': 'Old item',
        'durationMs': 60000,
        'artwork': '/old/poster',
      }),
      throwsFormatException,
    );
  });

  test('all content source variants round-trip canonically', () {
    final sources = <ContentSource>[
      const LibrarySource(
        libraryId: 'movies',
        libraryType: PlexLibraryType.movie,
        includeWatched: false,
        filters: {'genre': 'Comedy'},
      ),
      const PlaylistSource('playlist'),
      const ManualSource([
        ChannelItem(id: 'item', title: 'Item', duration: Duration(minutes: 1)),
      ]),
      const MixedSource(
        interleave: true,
        sources: [PlaylistSource('playlist')],
      ),
    ];

    for (final source in sources) {
      expect(ContentSource.fromJson(source.toJson()).toJson(), source.toJson());
    }
  });

  test('content sources reject missing, unknown, null, and invalid fields', () {
    for (final invalid in [
      {'type': 'playlist'},
      {'type': 'playlist', 'playlistId': 'playlist', 'future': true},
      {'type': 'library', 'libraryId': 'movies', 'libraryType': 'movie'},
      {
        'type': 'library',
        'libraryId': 'movies',
        'libraryType': 'future',
        'includeWatched': true,
      },
      {
        'type': 'library',
        'libraryId': 'movies',
        'libraryType': 'movie',
        'includeWatched': true,
        'filters': null,
      },
      {'type': 'manual', 'items': null},
      {'type': 'mixed', 'interleave': 1, 'sources': <Object?>[]},
      {'type': 'future'},
    ]) {
      expect(() => ContentSource.fromJson(invalid), throwsFormatException);
    }
  });

  test('channel items reject noncanonical fields and numeric values', () {
    const canonical = {'id': 'item', 'title': 'Item', 'durationMs': 60000};
    for (final invalid in [
      {...canonical}..remove('title'),
      {...canonical, 'future': true},
      {...canonical, 'durationMs': 60000.0},
      {...canonical, 'year': 2026.0},
      {...canonical, 'summary': null},
      {
        ...canonical,
        'genres': ['Drama', 7],
      },
    ]) {
      expect(() => ChannelItem.fromJson(invalid), throwsFormatException);
    }
  });

  test('channels round-trip and reject noncanonical persisted values', () {
    final channel = Channel(
      id: 'channel',
      number: 7,
      name: 'Channel',
      source: const PlaylistSource('playlist'),
      playbackMode: PlaybackMode.block,
      anchor: DateTime.utc(2026, 8, 23),
      shuffleSeed: 42,
      blockSize: 3,
      builderKey: 'builder',
    );
    expect(Channel.fromJson(channel.toJson()).toJson(), channel.toJson());

    final canonical = channel.toJson();
    for (final invalid in [
      {...canonical}..remove('anchor'),
      {...canonical, 'future': true},
      {...canonical, 'number': 7.0},
      {...canonical, 'shuffleSeed': 42.0},
      {...canonical, 'playbackMode': 'future'},
      {...canonical, 'blockSize': null},
      {...canonical, 'builderKey': null},
    ]) {
      expect(() => Channel.fromJson(invalid), throwsFormatException);
    }
  });
}
