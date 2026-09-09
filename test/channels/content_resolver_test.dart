import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/content_resolver.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

void main() {
  test('decades use one canonical four-digit representation', () {
    expect(channelDecadeForYear(1981), '1980s');
    expect(channelDecadeForYear(1000), '1000s');
    expect(channelDecadeForYear(9999), '9990s');
    for (final year in [null, -11, 999, 10000]) {
      expect(channelDecadeForYear(year), isNull, reason: '$year');
    }
  });

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

  test('supported filters and newest-first sorting remain strict', () {
    final dated = [
      PlexMediaItem(
        id: 'older',
        title: 'Older',
        type: 'movie',
        duration: const Duration(minutes: 1),
        libraryId: 'movies',
        parts: [PlexMediaPart(path: '/older')],
        genres: const ['Comedy'],
        collections: const ['Favorites'],
        studio: 'Studio',
        actors: const ['Actor'],
        directors: const ['Director'],
        year: 1994,
        addedAt: DateTime.utc(2020),
      ),
      PlexMediaItem(
        id: 'newer',
        title: 'Newer',
        type: 'movie',
        duration: const Duration(minutes: 1),
        libraryId: 'movies',
        parts: [PlexMediaPart(path: '/newer')],
        genres: const ['Comedy'],
        collections: const ['Favorites'],
        studio: 'Studio',
        actors: const ['Actor'],
        directors: const ['Director'],
        year: 1998,
        addedAt: DateTime.utc(2021),
      ),
    ];
    for (final filter in const {
      'genre': 'Comedy',
      'collection': 'Favorites',
      'studio': 'Studio',
      'actor': 'Actor',
      'director': 'Director',
      'decade': '1990s',
    }.entries) {
      expect(
        resolveContent(
          LibrarySource(
            libraryId: 'movies',
            libraryType: PlexLibraryType.movie,
            filters: {filter.key: filter.value},
          ),
          dated,
        ).length,
        2,
      );
    }
    expect(
      resolveContent(
        const LibrarySource(
          libraryId: 'movies',
          libraryType: PlexLibraryType.movie,
          filters: {'sort': 'added:desc'},
        ),
        dated,
      ).map((item) => item.id),
      ['newer', 'older'],
    );
    for (final filters in const [
      {'future': 'anything'},
      {'decade': '1995s'},
      {'decade': '90s'},
      {'decade': '990s'},
      {'decade': '-10s'},
      {'decade': '10000s'},
      {'sort': 'title:asc'},
    ]) {
      expect(
        () => resolveContent(
          LibrarySource(
            libraryId: 'movies',
            libraryType: PlexLibraryType.movie,
            filters: filters,
          ),
          dated,
        ),
        throwsFormatException,
      );
    }
  });

  test('people filters normalize names consistently with proposals', () {
    final people = [
      for (final entry in const [
        ('one', ' Avery Vale '),
        ('two', 'avery vale'),
      ])
        PlexMediaItem(
          id: entry.$1,
          title: entry.$1,
          type: 'movie',
          duration: const Duration(minutes: 1),
          libraryId: 'movies',
          parts: [PlexMediaPart(path: '/${entry.$1}')],
          actors: [entry.$2, entry.$2.toUpperCase()],
          directors: [entry.$2, entry.$2.toUpperCase()],
        ),
    ];

    for (final filter in const [
      {'actor': 'avery vale'},
      {'director': 'AVERY VALE'},
    ]) {
      expect(
        resolveContent(
          LibrarySource(
            libraryId: 'movies',
            libraryType: PlexLibraryType.movie,
            filters: filter,
          ),
          people,
        ).map((item) => item.id),
        ['one', 'two'],
      );
    }
  });

  test('manual content refreshes in stored order without mutation', () {
    const retained = ManualSource([
      ChannelItem(id: 'b', title: 'Old B', duration: Duration(seconds: 1)),
      ChannelItem(
        id: 'missing',
        title: 'Missing',
        duration: Duration(seconds: 1),
      ),
      ChannelItem(id: 'a', title: 'Old A', duration: Duration(seconds: 1)),
    ]);
    final before = retained.toJson();

    final resolved = resolveContent(retained, media);

    expect(resolved.map((item) => item.id), ['b', 'a']);
    expect(resolved.map((item) => item.title), ['B', 'A']);
    expect(retained.toJson(), before);
  });

  test('playable media IDs keep media-first then playlist item order', () {
    final mediaWinner = media.first;
    final firstPlaylistWinner = PlexMediaItem(
      id: 'playlist-only',
      title: 'First playlist winner',
      type: 'movie',
      duration: const Duration(minutes: 1),
      parts: [PlexMediaPart(path: '/playlist-first')],
    );
    final projection = playableMediaById(media, [
      PlexPlaylist(
        id: 'first',
        title: 'First',
        items: [
          PlexMediaItem(
            id: mediaWinner.id,
            title: 'Playlist duplicate',
            type: 'movie',
            duration: const Duration(minutes: 1),
            parts: [PlexMediaPart(path: '/duplicate')],
          ),
          firstPlaylistWinner,
        ],
      ),
      PlexPlaylist(
        id: 'second',
        title: 'Second',
        items: [
          PlexMediaItem(
            id: firstPlaylistWinner.id,
            title: 'Later playlist duplicate',
            type: 'movie',
            duration: const Duration(minutes: 1),
            parts: [PlexMediaPart(path: '/playlist-later')],
          ),
          const PlexMediaItem(
            id: 'unplayable',
            title: 'Unplayable',
            type: 'movie',
            duration: Duration(minutes: 1),
          ),
        ],
      ),
    ]);

    expect(projection.keys, ['a', 'b', 'c', 'playlist-only']);
    expect(projection['a'], same(mediaWinner));
    expect(projection['playlist-only'], same(firstPlaylistWinner));
    expect(() => projection['new'] = mediaWinner, throwsUnsupportedError);
  });

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

  test('mixed manual library and playlist ordering is deterministic', () {
    final playlistItem = PlexMediaItem(
      id: 'playlist-item',
      title: 'Playlist',
      type: 'movie',
      duration: const Duration(minutes: 1),
      parts: [PlexMediaPart(path: '/playlist')],
    );
    final sources = [
      const ManualSource([
        ChannelItem(id: 'b', title: 'Stored B', duration: Duration(seconds: 1)),
        ChannelItem(id: 'a', title: 'Stored A', duration: Duration(seconds: 1)),
      ]),
      const LibrarySource(
        libraryId: 'shows',
        libraryType: PlexLibraryType.show,
      ),
      const PlaylistSource('playlist'),
    ];
    final playlists = [
      PlexPlaylist(id: 'playlist', title: 'Playlist', items: [playlistItem]),
    ];

    expect(
      resolveContent(
        MixedSource(sources: sources),
        media,
        playlists,
      ).map((item) => item.id),
      ['b', 'a', 'c', 'playlist-item'],
    );
    expect(
      resolveContent(
        MixedSource(sources: sources, interleave: true),
        media,
        playlists,
      ).map((item) => item.id),
      ['b', 'c', 'playlist-item', 'a'],
    );
  });

  test('mixed omits unavailable manual items and fails closed recursively', () {
    const unavailable = ManualSource([
      ChannelItem(
        id: 'missing',
        title: 'Missing',
        duration: Duration(minutes: 1),
      ),
      ChannelItem(
        id: 'unplayable',
        title: 'Unplayable',
        duration: Duration(minutes: 1),
      ),
    ]);
    final unplayable = PlexMediaItem(
      id: 'unplayable',
      title: 'Unplayable now',
      type: 'movie',
      duration: const Duration(minutes: 1),
    );

    expect(
      resolveContent(const MixedSource(sources: [unavailable]), [unplayable]),
      isEmpty,
    );
    expect(
      () => resolveContent(
        const MixedSource(
          sources: [
            MixedSource(
              sources: [
                LibrarySource(
                  libraryId: 'movies',
                  libraryType: PlexLibraryType.movie,
                  filters: {'future': 'value'},
                ),
              ],
            ),
          ],
        ),
        media,
      ),
      throwsFormatException,
    );
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
        thumbPath: '/library/metadata/episode/thumb',
        grandparentThumbPath: '/library/metadata/show/thumb',
        artPath: '/library/metadata/show/art',
        clearLogoPath: '/library/metadata/show/clearlogo',
      ),
    );

    expect(item.poster, Uri.parse('/library/metadata/episode/thumb'));
    expect(item.showThumb, '/library/metadata/show/thumb');
    expect(item.backdrop, Uri.parse('/library/metadata/show/art'));
    expect(item.clearLogo, Uri.parse('/library/metadata/show/clearlogo'));
  });

  test('maps Plex cast facts without changing the actor-name projection', () {
    final item = channelItemFor(
      const PlexMediaItem(
        id: 'episode',
        title: 'Episode',
        type: 'episode',
        duration: Duration(minutes: 1),
        actors: ['Avery Vale'],
        cast: [
          PlexCastMember(
            name: 'Avery Vale',
            role: 'Detective Rowan',
            thumbPath: '/library/metadata/avery/thumb',
          ),
          PlexCastMember(name: 'Mina Park'),
          PlexCastMember(
            name: 'Unsafe Absolute',
            role: 'Reporter',
            thumbPath: 'https://plex.invalid/library/metadata/2/thumb',
          ),
          PlexCastMember(
            name: 'Unsafe Token',
            role: 'Dispatcher',
            thumbPath: '/library/metadata/3/thumb?X-Plex-Token=secret',
          ),
          PlexCastMember(
            name: 'Unsafe Fragment',
            role: 'Archivist',
            thumbPath: '/library/metadata/4/thumb#private',
          ),
          PlexCastMember(
            name: 'Unsafe Transcode',
            thumbPath: '/photo/:/transcode?url=private',
          ),
          PlexCastMember(
            name: 'Unsafe File',
            thumbPath: '/Users/private/cast.png',
          ),
        ],
      ),
    );

    expect(item.cast.first.name, 'Avery Vale');
    expect(item.cast.first.role, 'Detective Rowan');
    expect(
      item.cast.first.portrait,
      Uri.parse('/library/metadata/avery/thumb'),
    );
    expect(item.cast[2].name, 'Unsafe Absolute');
    expect(item.cast[2].role, 'Reporter');
    expect(item.cast[3].name, 'Unsafe Token');
    expect(item.cast[3].role, 'Dispatcher');
    expect(item.cast[4].name, 'Unsafe Fragment');
    expect(item.cast[4].role, 'Archivist');
    expect(
      item.cast.skip(1).map((member) => member.portrait),
      everyElement(isNull),
    );
  });

  test('maps trusted Plex metadata cast portraits only for cast', () {
    const trusted = 'https://metadata-static.plex.tv/f/people/avery-vale.jpg';
    final item = channelItemFor(
      const PlexMediaItem(
        id: 'episode',
        title: 'Episode',
        type: 'episode',
        duration: Duration(minutes: 1),
        thumbPath: trusted,
        cast: [
          PlexCastMember(name: 'Avery Vale', thumbPath: trusted),
          PlexCastMember(
            name: 'Lookalike',
            thumbPath:
                'https://metadata-static.plex.tv.evil.example/f/people/a.jpg',
          ),
        ],
      ),
    );

    expect(item.poster, isNull);
    expect(item.cast.first.portrait, Uri.parse(trusted));
    expect(item.cast.last.portrait, isNull);
  });

  test('drops noncanonical artwork from manually supplied Plex models', () {
    const unsafe = '/library/metadata/1/thumb?X-Plex-Token=secret';
    final item = channelItemFor(
      const PlexMediaItem(
        id: 'unsafe',
        title: 'Unsafe artwork',
        type: 'movie',
        duration: Duration(minutes: 1),
        thumbPath: unsafe,
        grandparentThumbPath: unsafe,
        artPath: unsafe,
        clearLogoPath: unsafe,
        cast: [PlexCastMember(name: 'Actor', thumbPath: unsafe)],
      ),
    );

    expect(item.showThumb, isNull);
    expect(item.poster, isNull);
    expect(item.backdrop, isNull);
    expect(item.clearLogo, isNull);
    expect(item.cast.single.portrait, isNull);
  });

  test('unsafe persisted artwork is removed on revival and serialization', () {
    for (final field in ['showThumb', 'poster', 'backdrop', 'clearLogo']) {
      for (final unsafe in [
        'https://plex.invalid/library/metadata/1/thumb',
        '/library/metadata/1/thumb?X-Plex-Token=secret',
        '/library/metadata/1/thumb#private',
        '/Users/private/poster.png',
      ]) {
        final item = ChannelItem.fromJson({
          'id': 'item',
          'title': 'Item',
          'durationMs': 60000,
          field: unsafe,
        });

        expect(item.toJson(), isNot(contains(field)), reason: '$field $unsafe');
        expect(item.toJson().toString(), isNot(contains(unsafe)));
      }
    }
  });

  test('channel item poster, backdrop, and logo round-trip canonically', () {
    final item = ChannelItem(
      id: 'new',
      title: 'New item',
      duration: Duration(minutes: 1),
      showTitle: 'Show',
      showThumb: '/library/metadata/show/thumb',
      poster: Uri(path: '/library/metadata/item/thumb'),
      backdrop: Uri(path: '/library/metadata/item/art'),
      clearLogo: Uri(path: '/library/metadata/show/clearlogo'),
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
      cast: [
        ChannelCastMember(
          name: 'Avery Vale',
          role: 'Detective Rowan',
          portrait: Uri.parse('/library/metadata/avery/thumb'),
        ),
        ChannelCastMember(name: 'Mina Park'),
      ],
    );
    expect(ChannelItem.fromJson(item.toJson()).toJson(), item.toJson());
    expect(
      item.toJson(),
      containsPair('poster', '/library/metadata/item/thumb'),
    );
    expect(item.toJson(), isNot(contains('artwork')));
  });

  test('channel item JSON remains backward compatible without cast', () {
    final item = ChannelItem.fromJson(const {
      'id': 'legacy-current',
      'title': 'Legacy current item',
      'durationMs': 60000,
    });

    expect(item.cast, isEmpty);
    expect(item.toJson(), isNot(contains('cast')));
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

  test('bulk channel validation preserves identity semantics', () {
    Channel channel(String id, int number) => Channel(
      id: id,
      number: number,
      name: 'Channel $number',
      source: const PlaylistSource('playlist'),
      playbackMode: PlaybackMode.sequential,
      anchor: DateTime.utc(2026),
      shuffleSeed: number,
    );

    final channels = [
      for (var number = 1; number <= 1000; number++) channel('$number', number),
    ];
    expect(() => validateChannels(channels), returnsNormally);
    expect(
      () => validateChannels([channel('same', 7), channel('same', 7)]),
      throwsFormatException,
    );
    expect(
      () => validateChannels([channel('same', 7), channel('same', 8)]),
      throwsFormatException,
    );
    expect(
      () => validateChannels([channel('first', 7), channel('second', 7)]),
      throwsFormatException,
    );
  });
}
