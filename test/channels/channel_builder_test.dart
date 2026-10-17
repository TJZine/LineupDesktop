import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/channels/channel_builder.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/content_resolver.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

void main() {
  test('block eligibility precedes channel limits and numbering', () {
    const library = PlexLibrary(
      id: 'tv',
      title: 'TV',
      type: PlexLibraryType.show,
    );
    final media = [
      for (var i = 0; i < 5; i++)
        _builderEpisode('special-$i', 0, 'A Specials'),
      for (var i = 0; i < 5; i++) _builderEpisode('regular-$i', 1, 'B Regular'),
    ];
    final proposals = buildChannelProposals(
      libraries: const [library],
      items: media,
      strategies: const {BuilderStrategy.collections},
      maximumChannels: null,
    );
    expect(proposals.map((proposal) => proposal.name), [
      'A Specials',
      'B Regular',
    ]);
    for (final mode in ChannelBuildMode.values) {
      final result = materializeChannelPlan(
        proposals: proposals,
        existing: const [],
        mode: mode,
        seriesMode: PlaybackMode.block,
        minimumItems: 5,
        maximumChannels: 1,
        anchor: DateTime.utc(2026),
      );
      expect(result.channels.single.name, 'B Regular', reason: mode.name);
      expect(result.channels.single.number, 1);
      expect(
        result.eligibleOriginalsByStrategy[BuilderStrategy.collections],
        1,
      );
      expect(result.excludedOriginals, 0);
      expect(result.truncated, isFalse);
      final schedule = buildChannelSchedule(
        result.channels.single,
        resolveContent(result.channels.single.source, media),
      );
      expect(schedule.items, hasLength(5));
    }
  });

  test('effective minimum and extras honor each playback policy', () {
    const library = PlexLibrary(
      id: 'tv',
      title: 'TV',
      type: PlexLibraryType.show,
    );
    final specials = [
      for (var i = 0; i < 5; i++)
        _builderEpisode('special-$i', 0, 'Collection'),
    ];
    ChannelPlanAllocation allocate(
      List<PlexMediaItem> media, {
      PlaybackMode playback = PlaybackMode.block,
      PlaybackMode? variant,
      bool includeSpecials = false,
      int minimum = 5,
    }) => materializeChannelPlan(
      proposals: buildChannelProposals(
        libraries: const [library],
        items: media,
        strategies: const {BuilderStrategy.collections},
      ),
      existing: const [],
      mode: ChannelBuildMode.replace,
      seriesMode: playback,
      variantMode: variant,
      alternateCopies: 1,
      includeSpecials: includeSpecials,
      minimumItems: minimum,
      anchor: DateTime.utc(2026),
    );
    expect(allocate(specials).channels, isEmpty);
    final included = allocate(specials, includeSpecials: true);
    expect(included.channels, hasLength(2));
    for (final channel in included.channels) {
      expect(
        buildChannelSchedule(
          channel,
          resolveContent(channel.source, specials),
        ).items,
        hasLength(5),
      );
    }
    final shuffled = allocate(
      specials,
      playback: PlaybackMode.shuffle,
      variant: PlaybackMode.block,
    );
    expect(shuffled.channels.map((channel) => channel.playbackMode), [
      PlaybackMode.shuffle,
      PlaybackMode.shuffle,
    ]);
    expect(shuffled.allocatedExtras, 1);
    expect(shuffled.excludedExtras, 0);
    final mixed = [...specials, _builderEpisode('regular', 1, 'Collection')];
    expect(allocate(mixed).channels, isEmpty);
    final usable = allocate(mixed, minimum: 1).channels.first;
    expect(
      buildChannelSchedule(
        usable,
        resolveContent(usable.source, mixed),
      ).items.single.id,
      'regular',
    );
    final sequential = allocate(
      specials,
      playback: PlaybackMode.sequential,
    ).channels.single;
    expect(
      buildChannelSchedule(
        sequential,
        resolveContent(sequential.source, specials),
      ).items,
      hasLength(5),
    );
  });

  test('proposal counts preserve resolved duplicates, filters and playlist occurrences', () {
    final special = _builderEpisode('shared', 0, 'Collection');
    final regular = _builderEpisode('regular', 1, 'Collection');
    final media = [
      special,
      _builderEpisode('shared', 1, 'Other'),
      _builderEpisode('shared', 1, 'Collection'),
      regular,
      _builderEpisode('whitespace', 1, ' Collection '),
      PlexMediaItem(
        id: 'shared',
        title: 'Movie',
        type: 'movie',
        libraryId: 'movies',
        duration: const Duration(minutes: 30),
        collections: const ['Collection'],
        parts: [PlexMediaPart(path: '/parts/movie')],
      ),
      const PlexMediaItem(
        id: 'unplayable',
        title: 'Unavailable',
        type: 'episode',
        libraryId: 'tv',
        duration: Duration(minutes: 20),
        collections: ['Collection'],
      ),
    ];
    final playlists = [
      PlexPlaylist(
        id: 'playlist',
        title: 'Playlist',
        items: [special, regular, regular],
      ),
    ];
    for (final grouped in [false, true]) {
      final proposals = buildChannelProposals(
        libraries: const [
          PlexLibrary(id: 'tv', title: 'TV', type: PlexLibraryType.show),
          PlexLibrary(
            id: 'movies',
            title: 'Movies',
            type: PlexLibraryType.movie,
          ),
        ],
        items: media,
        playlists: playlists,
        strategies: const {
          BuilderStrategy.collections,
          BuilderStrategy.playlists,
          BuilderStrategy.recentlyAdded,
        },
        crossLibraryStrategies: grouped ? {BuilderStrategy.collections} : {},
        minimumItems: 1,
        maximumChannels: null,
      );
      for (final proposal in proposals) {
        final content = resolveContent(proposal.source, media, playlists);
        expect(
          proposal.playableItemCount,
          content.length,
          reason: proposal.name,
        );
        try {
          final schedule = buildSchedule(
            content,
            mode: PlaybackMode.block,
            seed: 0,
            includeSpecials: false,
            scheduleVersion: currentScheduleVersion,
          );
          expect(
            proposal.blockItemCountWithoutSpecials,
            schedule.items.length,
            reason: proposal.name,
          );
        } on ScheduleBuildException catch (error) {
          expect(error.reason, ScheduleFailureReason.noContent);
          expect(
            proposal.blockItemCountWithoutSpecials,
            0,
            reason: proposal.name,
          );
        }
      }
      final playlist = proposals.singleWhere(
        (proposal) => proposal.strategy == BuilderStrategy.playlists,
      );
      expect(playlist.playableItemCount, 3);
      expect(playlist.blockItemCountWithoutSpecials, 2);
    }
  });

  test('builder output is deterministic and applies item minimums', () {
    final library = const PlexLibrary(
      id: '1',
      title: 'Movies',
      type: PlexLibraryType.movie,
    );
    final items = List.generate(
      6,
      (index) => PlexMediaItem(
        id: '$index',
        title: 'Movie $index',
        type: 'movie',
        duration: const Duration(minutes: 90),
        libraryId: '1',
        genres: const ['Comedy'],
        year: 1981,
      ),
    );
    final first = buildChannelProposals(libraries: [library], items: items);
    final second = buildChannelProposals(
      libraries: [library],
      items: items.reversed.toList(),
    );
    expect(
      first.map(
        (proposal) =>
            '${proposal.strategy.name}:${proposal.name}:${proposal.itemCount}',
      ),
      second.map(
        (proposal) =>
            '${proposal.strategy.name}:${proposal.name}:${proposal.itemCount}',
      ),
    );
    expect(first.any((proposal) => proposal.name == 'Comedy'), isTrue);
    expect(first.any((proposal) => proposal.name == '1980s'), isTrue);
  });

  test('builder omits tags below the minimum', () {
    const library = PlexLibrary(
      id: '1',
      title: 'Movies',
      type: PlexLibraryType.movie,
    );
    final items = [
      const PlexMediaItem(
        id: '1',
        title: 'One',
        type: 'movie',
        duration: Duration(minutes: 1),
        libraryId: '1',
        genres: ['Rare'],
      ),
    ];
    final proposals = buildChannelProposals(
      libraries: [library],
      items: items,
      strategies: const {BuilderStrategy.genres},
    );
    expect(proposals, isEmpty);
  });

  test('builder omits noncanonical years from decade proposals', () {
    const library = PlexLibrary(
      id: '1',
      title: 'Movies',
      type: PlexLibraryType.movie,
    );
    final proposals = buildChannelProposals(
      libraries: const [library],
      items: [
        for (final year in [-11, 999, 1981, 10000])
          PlexMediaItem(
            id: '$year',
            title: 'Movie $year',
            type: 'movie',
            duration: const Duration(minutes: 1),
            libraryId: '1',
            year: year,
          ),
      ],
      strategies: const {BuilderStrategy.decades},
      minimumItems: 1,
    );

    expect(proposals, hasLength(1));
    expect(proposals.single.name, '1980s');
    expect(proposals.single.itemCount, 1);
  });

  test('builder keeps playlists and collections as real sources', () {
    const library = PlexLibrary(
      id: '1',
      title: 'Movies',
      type: PlexLibraryType.movie,
    );
    final items = List.generate(
      5,
      (index) => PlexMediaItem(
        id: '$index',
        title: 'Movie $index',
        type: 'movie',
        duration: const Duration(minutes: 90),
        libraryId: '1',
        collections: const ['Friday Night'],
      ),
    );
    final proposals = buildChannelProposals(
      libraries: const [library],
      items: items,
      playlists: [PlexPlaylist(id: 'p1', title: 'Favorites', items: items)],
      strategies: const {
        BuilderStrategy.playlists,
        BuilderStrategy.collections,
      },
    );
    expect(proposals.map((proposal) => proposal.name), [
      'Favorites',
      'Friday Night',
    ]);
    expect(proposals.first.source, isA<PlaylistSource>());
    expect((proposals.first.source as PlaylistSource).playlistId, 'p1');
    expect((proposals.last.source as LibrarySource).filters, {
      LibraryFilter.collection: ['Friday Night'],
    });
  });

  test('cross-library tags interleave and respect configured priority', () {
    const libraries = [
      PlexLibrary(id: '1', title: 'A', type: PlexLibraryType.movie),
      PlexLibrary(id: '2', title: 'B', type: PlexLibraryType.movie),
    ];
    final items = [
      for (final library in libraries)
        for (var index = 0; index < 3; index++)
          PlexMediaItem(
            id: '${library.id}-$index',
            title: 'Movie',
            type: 'movie',
            duration: const Duration(minutes: 1),
            libraryId: library.id,
            genres: const ['Comedy'],
            year: 1981,
          ),
    ];
    final proposals = buildChannelProposals(
      libraries: libraries,
      items: items,
      strategies: const {BuilderStrategy.genres, BuilderStrategy.decades},
      strategyOrder: const [BuilderStrategy.decades, BuilderStrategy.genres],
      crossLibraryStrategies: const {BuilderStrategy.genres},
      minimumItems: 3,
    );
    expect(proposals.first.strategy, BuilderStrategy.decades);
    final comedy = proposals.singleWhere((value) => value.name == 'Comedy');
    expect(comedy.itemCount, 6);
    expect((comedy.source as MixedSource).interleave, isTrue);
  });

  test('series variants use mode and block size identity', () {
    const proposal = ChannelProposal(
      name: 'Series',
      source: LibrarySource(libraryId: 'tv', libraryType: PlexLibraryType.show),
      mode: PlaybackMode.shuffle,
      itemCount: 10,
      playableItemCount: 10,
      blockItemCountWithoutSpecials: 10,
      strategy: BuilderStrategy.recentlyAdded,
      series: true,
    );

    final cases =
        <
          ({
            PlaybackMode baseMode,
            PlaybackMode variantMode,
            int variantBlockSize,
            List<PlaybackMode> expectedModes,
            List<int?> expectedBlockSizes,
          })
        >[
          (
            baseMode: PlaybackMode.sequential,
            variantMode: PlaybackMode.shuffle,
            variantBlockSize: 3,
            expectedModes: [PlaybackMode.sequential, PlaybackMode.shuffle],
            expectedBlockSizes: [null, null],
          ),
          (
            baseMode: PlaybackMode.sequential,
            variantMode: PlaybackMode.block,
            variantBlockSize: 4,
            expectedModes: [PlaybackMode.sequential, PlaybackMode.block],
            expectedBlockSizes: [null, 4],
          ),
          (
            baseMode: PlaybackMode.block,
            variantMode: PlaybackMode.block,
            variantBlockSize: 3,
            expectedModes: [PlaybackMode.block],
            expectedBlockSizes: [3],
          ),
          (
            baseMode: PlaybackMode.block,
            variantMode: PlaybackMode.block,
            variantBlockSize: 4,
            expectedModes: [PlaybackMode.block, PlaybackMode.block],
            expectedBlockSizes: [3, 4],
          ),
        ];
    for (final testCase in cases) {
      final channels = materializeChannelPlan(
        proposals: const [proposal],
        existing: const [],
        mode: ChannelBuildMode.replace,
        seriesMode: testCase.baseMode,
        seriesBlockSize: 3,
        variantMode: testCase.variantMode,
        variantBlockSize: testCase.variantBlockSize,
        anchor: DateTime.utc(2026),
      ).channels;
      expect(
        channels.map((channel) => channel.playbackMode),
        testCase.expectedModes,
        reason: '${testCase.baseMode.name}->${testCase.variantMode.name}',
      );
      expect(
        channels.map((channel) => channel.blockSize),
        testCase.expectedBlockSizes,
      );
    }

    final channels = materializeChannelPlan(
      proposals: const [proposal],
      existing: const [],
      mode: ChannelBuildMode.replace,
      seriesMode: PlaybackMode.block,
      seriesBlockSize: 3,
      alternateCopies: 2,
      variantMode: PlaybackMode.sequential,
      anchor: DateTime.utc(2026),
    ).channels;
    expect(channels.map((channel) => channel.number), [1, 2, 3, 4]);
    expect(channels.map((channel) => channel.name), [
      'Series',
      'Series sequential',
      'Series Alt 1',
      'Series Alt 2',
    ]);
    expect(channels.first.blockSize, 3);
  });

  test(
    'TV recently added stays sequential while TV shuffle uses series mode',
    () {
      const library = PlexLibrary(
        id: 'tv',
        title: 'Shows',
        type: PlexLibraryType.show,
      );
      final items = [
        for (var index = 0; index < 5; index++)
          PlexMediaItem(
            id: '$index',
            title: 'Episode $index',
            type: 'episode',
            duration: const Duration(minutes: 20),
            libraryId: library.id,
            collections: const ['Collection'],
            parts: [PlexMediaPart(path: '/parts/$index')],
          ),
      ];

      final recentlyAdded = buildChannelProposals(
        libraries: const [library],
        items: items,
        strategies: const {BuilderStrategy.recentlyAdded},
      ).single;
      final recentlyAddedChannels = materializeChannelPlan(
        proposals: [recentlyAdded],
        existing: const [],
        mode: ChannelBuildMode.replace,
        seriesMode: PlaybackMode.block,
        alternateCopies: 2,
        anchor: DateTime.utc(2026),
      ).channels;

      expect(recentlyAdded.mode, PlaybackMode.sequential);
      expect(recentlyAddedChannels.map((channel) => channel.playbackMode), [
        PlaybackMode.sequential,
      ]);
      expect(recentlyAddedChannels.map((channel) => channel.name), [
        'Shows Recently Added',
      ]);

      final collection = buildChannelProposals(
        libraries: const [library],
        items: items,
        strategies: const {BuilderStrategy.collections},
      ).single;
      final collectionChannels = materializeChannelPlan(
        proposals: [collection],
        existing: const [],
        mode: ChannelBuildMode.replace,
        seriesMode: PlaybackMode.block,
        seriesBlockSize: 4,
        alternateCopies: 1,
        anchor: DateTime.utc(2026),
      ).channels;

      expect(collection.mode, PlaybackMode.shuffle);
      expect(collectionChannels.map((channel) => channel.playbackMode), [
        PlaybackMode.block,
        PlaybackMode.block,
      ]);
      expect(collectionChannels.map((channel) => channel.blockSize), [4, 4]);
    },
  );

  test('actor and director series proposals do not expand', () {
    for (final strategy in [
      BuilderStrategy.actors,
      BuilderStrategy.directors,
    ]) {
      final proposal = ChannelProposal(
        name: strategy.name,
        source: const LibrarySource(
          libraryId: 'tv',
          libraryType: PlexLibraryType.show,
        ),
        mode: PlaybackMode.shuffle,
        itemCount: 10,
        playableItemCount: 10,
        blockItemCountWithoutSpecials: 10,
        strategy: strategy,
        series: true,
      );
      final channels = materializeChannelPlan(
        proposals: [proposal],
        existing: const [],
        mode: ChannelBuildMode.replace,
        seriesMode: PlaybackMode.shuffle,
        alternateCopies: 2,
        variantMode: PlaybackMode.block,
        variantBlockSize: 4,
        anchor: DateTime.utc(2026),
      ).channels;
      expect(channels, hasLength(1), reason: strategy.name);
      expect(channels.single.playbackMode, PlaybackMode.shuffle);
    }
  });

  test('global limits allocate fairly across enabled strategies', () {
    const library = PlexLibrary(
      id: '1',
      title: 'Movies',
      type: PlexLibraryType.movie,
    );
    final items = [
      for (var index = 0; index < 12; index++)
        PlexMediaItem(
          id: '$index',
          title: 'Movie',
          type: 'movie',
          duration: const Duration(minutes: 1),
          libraryId: '1',
          genres: [index.isEven ? 'Comedy' : 'Drama'],
          year: index.isEven ? 1981 : 1991,
        ),
    ];
    final proposals = buildChannelProposals(
      libraries: const [library],
      items: items,
      strategies: const {BuilderStrategy.genres, BuilderStrategy.decades},
      maximumChannels: 2,
    );
    expect(proposals.map((proposal) => proposal.strategy).toSet(), {
      BuilderStrategy.genres,
      BuilderStrategy.decades,
    });
  });

  test('all eight strategy families produce eligible proposals', () {
    const library = PlexLibrary(
      id: '1',
      title: 'Movies',
      type: PlexLibraryType.movie,
    );
    final items = List.generate(
      5,
      (index) => PlexMediaItem(
        id: '$index',
        title: 'Movie',
        type: 'movie',
        duration: const Duration(minutes: 1),
        libraryId: '1',
        genres: const ['Comedy'],
        collections: const ['Collection'],
        studio: 'Studio',
        actors: const ['Actor'],
        directors: const ['Director'],
        year: 1981,
      ),
    );
    final proposals = buildChannelProposals(
      libraries: const [library],
      items: items,
      playlists: [PlexPlaylist(id: 'p', title: 'Playlist', items: items)],
    );
    expect(
      proposals.map((proposal) => proposal.strategy).toSet(),
      BuilderStrategy.values.toSet(),
    );
  });

  test('TV people channels normalize tags and require three series', () {
    const library = PlexLibrary(
      id: 'tv',
      title: 'Shows',
      type: PlexLibraryType.show,
    );
    List<PlexMediaItem> episodes(List<String> series) => [
      for (var index = 0; index < 6; index++)
        PlexMediaItem(
          id: '$series-$index',
          title: 'Episode',
          type: 'episode',
          duration: const Duration(minutes: 1),
          libraryId: 'tv',
          grandparentTitle: series[index % series.length],
          actors: const [' Actor '],
        ),
    ];
    final narrow = buildChannelProposals(
      libraries: const [library],
      items: episodes(['One', 'Two']),
      strategies: const {BuilderStrategy.actors},
    );
    final broad = buildChannelProposals(
      libraries: const [library],
      items: episodes(['One', 'Two', 'Three']),
      strategies: const {BuilderStrategy.actors},
    );
    expect(narrow, isEmpty);
    expect(broad.single.name, 'Actor');
  });

  test('TV people use stable series keys and canonical filter identity', () {
    const library = PlexLibrary(
      id: 'tv',
      title: 'Shows',
      type: PlexLibraryType.show,
    );
    for (final strategy in [
      BuilderStrategy.actors,
      BuilderStrategy.directors,
    ]) {
      final items = [
        for (final entry in const [
          ('series-1', ' Avery Vale '),
          ('series-2', 'avery vale'),
          ('series-3', 'AVERY VALE'),
        ])
          PlexMediaItem(
            id: entry.$1,
            title: 'Episode',
            type: 'episode',
            duration: const Duration(minutes: 1),
            libraryId: 'tv',
            parts: [PlexMediaPart(path: '/${entry.$1}')],
            grandparentTitle: 'Same title',
            grandparentRatingKey: entry.$1,
            actors: [entry.$2],
            directors: [entry.$2],
          ),
      ];

      final proposal = buildChannelProposals(
        libraries: const [library],
        items: items,
        strategies: {strategy},
        minimumItems: 3,
      ).single;

      expect(proposal.name, 'Avery Vale');
      expect((proposal.source as LibrarySource).filters, {
        strategy == BuilderStrategy.actors
            ? LibraryFilter.actor
            : LibraryFilter.director: [
          'avery vale',
        ],
      });
      expect(proposal.itemCount, 3);
      expect(resolveContent(proposal.source, items), hasLength(3));
    }
  });

  test('people merge identity ignores display casing and scan order', () {
    const library = PlexLibrary(
      id: 'tv',
      title: 'Shows',
      type: PlexLibraryType.show,
    );
    ChannelProposal proposal(List<String> names) => buildChannelProposals(
      libraries: const [library],
      items: [
        for (final (index, name) in names.indexed)
          PlexMediaItem(
            id: 'episode-$index',
            title: 'Episode',
            type: 'episode',
            duration: const Duration(minutes: 1),
            libraryId: 'tv',
            grandparentRatingKey: 'series-$index',
            actors: [name],
            parts: [PlexMediaPart(path: '/parts/$index')],
          ),
      ],
      strategies: const {BuilderStrategy.actors},
      minimumItems: 3,
    ).single;
    final forward = proposal(['Avery Vale', 'avery vale', 'AVERY VALE']);
    final reversed = proposal(['AVERY VALE', 'avery vale', 'Avery Vale']);
    expect(forward.name, 'Avery Vale');
    expect(reversed.name, forward.name);

    final first = materializeChannelPlan(
      proposals: [forward],
      existing: const [],
      mode: ChannelBuildMode.replace,
      anchor: DateTime.utc(2026),
    ).channels.single;

    final merged = materializeChannelPlan(
      proposals: [reversed],
      existing: [first],
      mode: ChannelBuildMode.merge,
      anchor: DateTime.utc(2027),
    ).channels;

    expect(merged, hasLength(1));
    expect(merged.single.id, first.id);
    expect(merged.single.builderKey, first.builderKey);
    expect(merged.single.name, 'Avery Vale');
  });

  test('TV people title fallback normalizes case and whitespace', () {
    const library = PlexLibrary(
      id: 'tv',
      title: 'Shows',
      type: PlexLibraryType.show,
    );
    final items = [
      for (final title in ['Same title', ' same TITLE ', 'Other title'])
        PlexMediaItem(
          id: title,
          title: 'Episode',
          type: 'episode',
          duration: const Duration(minutes: 1),
          libraryId: 'tv',
          grandparentTitle: title,
          actors: const ['Actor'],
        ),
    ];

    expect(
      buildChannelProposals(
        libraries: const [library],
        items: items,
        strategies: const {BuilderStrategy.actors},
        minimumItems: 3,
      ),
      isEmpty,
    );
  });

  test('people proposal breadth scales across a large tag catalog', () {
    const tagCount = 2000;
    const library = PlexLibrary(
      id: 'tv',
      title: 'Shows',
      type: PlexLibraryType.show,
    );
    final items = [
      for (var tagIndex = 0; tagIndex < tagCount; tagIndex++)
        for (var seriesIndex = 0; seriesIndex < 3; seriesIndex++)
          PlexMediaItem(
            id: '$tagIndex-$seriesIndex',
            title: 'Episode',
            type: 'episode',
            duration: const Duration(minutes: 1),
            libraryId: 'tv',
            grandparentTitle: 'Series $seriesIndex',
            actors: ['Actor $tagIndex'],
            directors: ['Director $tagIndex'],
          ),
    ];

    final proposals = buildChannelProposals(
      libraries: const [library],
      items: items,
      strategies: const {BuilderStrategy.actors, BuilderStrategy.directors},
      minimumItems: 3,
      maximumChannels: tagCount * 2,
    );

    expect(proposals, hasLength(tagCount * 2));
    expect(proposals.map((proposal) => proposal.itemCount).toSet(), {3});
    expect(proposals.map((proposal) => proposal.name).toSet(), {
      for (var index = 0; index < tagCount; index++) 'Actor $index',
      for (var index = 0; index < tagCount; index++) 'Director $index',
    });
  });

  test(
    'merge identity updates generated channels without matching custom names',
    () {
      const proposal = ChannelProposal(
        name: 'Comedy',
        source: LibrarySource(
          libraryId: 'movies',
          libraryType: PlexLibraryType.movie,
          filters: {
            LibraryFilter.genre: ['Comedy'],
          },
        ),
        mode: PlaybackMode.shuffle,
        itemCount: 10,
        playableItemCount: 10,
        blockItemCountWithoutSpecials: 10,
        strategy: BuilderStrategy.genres,
      );
      final first = materializeChannelPlan(
        proposals: const [proposal],
        existing: const [],
        mode: ChannelBuildMode.replace,
        anchor: DateTime.utc(2026),
      ).channels.single;
      final custom = Channel(
        id: 'custom',
        number: 2,
        name: 'Comedy',
        source: const LibrarySource(
          libraryId: 'other',
          libraryType: PlexLibraryType.movie,
        ),
        playbackMode: PlaybackMode.sequential,
        anchor: DateTime.utc(2026),
        shuffleSeed: 2,
      );
      final merged = materializeChannelPlan(
        proposals: const [proposal],
        existing: [first, custom],
        mode: ChannelBuildMode.merge,
        seriesMode: PlaybackMode.shuffle,
        anchor: DateTime.utc(2027),
      );
      expect(merged.channels.single.id, first.id);
      expect(merged.channels.single.number, first.number);
      expect(merged.channels.single.builderKey, first.builderKey);
    },
  );

  test('merge source comparison ignores map insertion order', () {
    const proposal = ChannelProposal(
      name: 'Comedy',
      source: LibrarySource(
        libraryId: 'movies',
        libraryType: PlexLibraryType.movie,
        filters: {
          LibraryFilter.genre: ['Comedy'],
          LibraryFilter.studio: ['Title'],
        },
      ),
      mode: PlaybackMode.shuffle,
      itemCount: 10,
      playableItemCount: 10,
      blockItemCountWithoutSpecials: 10,
      strategy: BuilderStrategy.genres,
    );
    final generated = materializeChannelPlan(
      proposals: const [proposal],
      existing: const [],
      mode: ChannelBuildMode.replace,
      anchor: DateTime.utc(2026),
    ).channels.single;
    final reordered = Channel(
      id: generated.id,
      number: generated.number,
      name: generated.name,
      source: const LibrarySource(
        libraryId: 'movies',
        libraryType: PlexLibraryType.movie,
        filters: {
          LibraryFilter.studio: ['Title'],
          LibraryFilter.genre: ['Comedy'],
        },
      ),
      playbackMode: generated.playbackMode,
      anchor: generated.anchor,
      shuffleSeed: generated.shuffleSeed,
      blockSize: generated.blockSize,
      builderKey: generated.builderKey,
    );

    final merged = materializeChannelPlan(
      proposals: const [proposal],
      existing: [reordered],
      mode: ChannelBuildMode.merge,
      anchor: DateTime.utc(2027),
    ).channels.single;

    expect(merged, same(reordered));
  });

  test('all build modes reserve sparse custom numbers through 1000', () {
    final proposals = List.generate(
      999,
      (index) => ChannelProposal(
        name: 'Drama $index',
        source: LibrarySource(
          libraryId: 'movies',
          libraryType: PlexLibraryType.movie,
          filters: {
            LibraryFilter.genre: ['Drama $index'],
          },
        ),
        mode: PlaybackMode.shuffle,
        itemCount: 10,
        playableItemCount: 10,
        blockItemCountWithoutSpecials: 10,
        strategy: BuilderStrategy.genres,
      ),
    );
    final custom = [
      Channel(
        id: 'custom-1',
        number: 1,
        name: 'Custom 1',
        source: const LibrarySource(
          libraryId: 'movies',
          libraryType: PlexLibraryType.movie,
        ),
        playbackMode: PlaybackMode.sequential,
        anchor: DateTime.utc(2026),
        shuffleSeed: 1,
      ),
      Channel(
        id: 'custom-1000',
        number: 1000,
        name: 'Custom 1000',
        source: const LibrarySource(
          libraryId: 'movies',
          libraryType: PlexLibraryType.movie,
        ),
        playbackMode: PlaybackMode.sequential,
        anchor: DateTime.utc(2026),
        shuffleSeed: 1000,
      ),
    ];

    for (final mode in ChannelBuildMode.values) {
      final result = materializeChannelPlan(
        proposals: proposals,
        existing: custom,
        mode: mode,
        maximumChannels: 1000,
        anchor: DateTime.utc(2027),
      );

      expect(result.channels.first.number, 2, reason: mode.name);
      expect(result.channels, hasLength(998), reason: mode.name);
      expect(
        result.channels.map((channel) => channel.number),
        isNot(contains(1000)),
        reason: mode.name,
      );
      expect(result.truncated, isTrue, reason: mode.name);
    }
  });

  test('merge identity remains stable when playback configuration changes', () {
    const proposal = ChannelProposal(
      name: 'Series',
      source: LibrarySource(libraryId: 'tv', libraryType: PlexLibraryType.show),
      mode: PlaybackMode.shuffle,
      itemCount: 10,
      playableItemCount: 10,
      blockItemCountWithoutSpecials: 10,
      strategy: BuilderStrategy.recentlyAdded,
      series: true,
    );
    final first = materializeChannelPlan(
      proposals: const [proposal],
      existing: const [],
      mode: ChannelBuildMode.replace,
      seriesMode: PlaybackMode.shuffle,
      anchor: DateTime.utc(2026),
    ).channels.single;
    final changed = materializeChannelPlan(
      proposals: const [proposal],
      existing: [first],
      mode: ChannelBuildMode.merge,
      seriesMode: PlaybackMode.block,
      seriesBlockSize: 5,
      anchor: DateTime.utc(2027),
    ).channels.single;
    expect(changed.id, first.id);
    expect(changed.number, first.number);
    expect(changed.playbackMode, PlaybackMode.block);
    expect(changed.blockSize, 5);
  });

  test('maximum 1000 uses a 1001-proposal overflow proof', () {
    const library = PlexLibrary(
      id: 'movies',
      title: 'Movies',
      type: PlexLibraryType.movie,
    );
    final proposals = buildChannelProposals(
      libraries: const [library],
      items: [
        for (var index = 0; index < 1001; index++)
          PlexMediaItem(
            id: '$index',
            title: 'Movie $index',
            type: 'movie',
            duration: const Duration(minutes: 1),
            libraryId: 'movies',
            genres: ['Genre $index'],
            parts: [PlexMediaPart(path: '/parts/$index')],
          ),
      ],
      strategies: const {BuilderStrategy.genres},
      minimumItems: 1,
      maximumChannels: 1001,
    );
    final result = materializeChannelPlan(
      proposals: proposals,
      existing: const [],
      mode: ChannelBuildMode.replace,
      maximumChannels: 1000,
      anchor: DateTime.utc(2026),
    );

    expect(proposals, hasLength(1001));
    expect(result.channels, hasLength(1000));
    expect(result.truncated, isTrue);
    expect(
      result.channels.any((channel) => channel.name == proposals.last.name),
      isFalse,
    );
  });

  test('truncation distinguishes exact and expanded boundaries', () {
    const proposal = ChannelProposal(
      name: 'Series',
      source: LibrarySource(libraryId: 'tv', libraryType: PlexLibraryType.show),
      mode: PlaybackMode.shuffle,
      itemCount: 10,
      playableItemCount: 10,
      blockItemCountWithoutSpecials: 10,
      strategy: BuilderStrategy.recentlyAdded,
      series: true,
    );
    final exact = materializeChannelPlan(
      proposals: const [proposal],
      existing: const [],
      mode: ChannelBuildMode.replace,
      alternateCopies: 1,
      maximumChannels: 2,
      anchor: DateTime.utc(2026),
    );
    final overflow = materializeChannelPlan(
      proposals: const [proposal],
      existing: const [],
      mode: ChannelBuildMode.replace,
      alternateCopies: 2,
      maximumChannels: 2,
      anchor: DateTime.utc(2026),
    );

    expect(exact.channels, hasLength(2));
    expect(exact.truncated, isFalse);
    expect(overflow.channels, hasLength(2));
    expect(overflow.truncated, isTrue);
  });

  test('merge continues updating matched entries after numbers run out', () {
    const newProposal = ChannelProposal(
      name: 'New',
      source: LibrarySource(
        libraryId: 'movies',
        libraryType: PlexLibraryType.movie,
        filters: {
          LibraryFilter.genre: ['New'],
        },
      ),
      mode: PlaybackMode.shuffle,
      itemCount: 10,
      playableItemCount: 10,
      blockItemCountWithoutSpecials: 10,
      strategy: BuilderStrategy.genres,
    );
    const matchedProposal = ChannelProposal(
      name: 'Series',
      source: LibrarySource(
        libraryId: 'tv',
        libraryType: PlexLibraryType.show,
        filters: {
          LibraryFilter.genre: ['Series'],
        },
      ),
      mode: PlaybackMode.shuffle,
      itemCount: 10,
      playableItemCount: 10,
      blockItemCountWithoutSpecials: 10,
      strategy: BuilderStrategy.genres,
    );
    final generated = materializeChannelPlan(
      proposals: const [matchedProposal],
      existing: const [],
      mode: ChannelBuildMode.replace,
      anchor: DateTime.utc(2026),
    ).channels.single;
    final matched = Channel(
      id: generated.id,
      number: 1000,
      name: generated.name,
      source: generated.source,
      playbackMode: generated.playbackMode,
      anchor: generated.anchor,
      shuffleSeed: generated.shuffleSeed,
      builderKey: generated.builderKey,
    );
    final existing = [
      for (var number = 1; number < 1000; number++)
        Channel(
          id: 'existing-$number',
          number: number,
          name: 'Existing $number',
          source: const LibrarySource(
            libraryId: 'movies',
            libraryType: PlexLibraryType.movie,
          ),
          playbackMode: PlaybackMode.shuffle,
          anchor: DateTime.utc(2026),
          shuffleSeed: number,
        ),
      matched,
    ];

    final result = materializeChannelPlan(
      proposals: const [newProposal, matchedProposal],
      existing: existing,
      mode: ChannelBuildMode.merge,
      seriesMode: PlaybackMode.block,
      seriesBlockSize: 4,
      anchor: DateTime.utc(2027),
    );

    expect(result.channels, hasLength(1));
    expect(result.channels.single.id, matched.id);
    expect(result.channels.single.number, 1000);
    expect(result.channels.single.playbackMode, PlaybackMode.block);
    expect(result.numberLimitExcluded, 1);
    expect(result.excludedOriginals, 1);
  });

  test(
    'merge updates a surviving extra after its original runs out of numbers',
    () {
      const proposal = ChannelProposal(
        name: 'Series',
        source: LibrarySource(
          libraryId: 'tv',
          libraryType: PlexLibraryType.show,
        ),
        mode: PlaybackMode.shuffle,
        itemCount: 10,
        playableItemCount: 10,
        blockItemCountWithoutSpecials: 10,
        strategy: BuilderStrategy.recentlyAdded,
        series: true,
      );
      final seeded = materializeChannelPlan(
        proposals: const [proposal],
        existing: const [],
        mode: ChannelBuildMode.replace,
        seriesMode: PlaybackMode.block,
        alternateCopies: 1,
        anchor: DateTime.utc(2026),
      ).channels;
      final survivingExtra = seeded.last;
      final existing = [
        for (var number = 1; number <= 1000; number++)
          if (number != survivingExtra.number)
            Channel(
              id: 'existing-$number',
              number: number,
              name: 'Existing $number',
              source: const LibrarySource(
                libraryId: 'movies',
                libraryType: PlexLibraryType.movie,
              ),
              playbackMode: PlaybackMode.shuffle,
              anchor: DateTime.utc(2026),
              shuffleSeed: number,
            ),
        survivingExtra,
      ];

      final result = materializeChannelPlan(
        proposals: const [proposal],
        existing: existing,
        mode: ChannelBuildMode.merge,
        seriesMode: PlaybackMode.block,
        includeSpecials: true,
        alternateCopies: 1,
        anchor: DateTime.utc(2027),
      );

      expect(result.channels, hasLength(1));
      expect(result.unmatchedGenerated, isEmpty);
      final updated = result.channels.single;
      expect(updated.id, survivingExtra.id);
      expect(updated.number, survivingExtra.number);
      expect(updated.builderKey, survivingExtra.builderKey);
      expect(updated.includeSpecials, isTrue);
      expect(updated.playbackMode, PlaybackMode.block);
      expect(result.numberLimitExcluded, 1);
      expect(result.allocatedOriginals, 0);
      expect(result.allocatedExtras, 1);
      expect(result.excludedOriginals, 1);
      expect(result.excludedExtras, 0);
    },
  );

  test('append and merge report channel-number exhaustion', () {
    final existing = [
      for (var number = 1; number <= 1000; number++)
        Channel(
          id: 'existing-$number',
          number: number,
          name: 'Existing $number',
          source: const LibrarySource(
            libraryId: 'movies',
            libraryType: PlexLibraryType.movie,
          ),
          playbackMode: PlaybackMode.shuffle,
          anchor: DateTime.utc(2026),
          shuffleSeed: number,
        ),
    ];
    const proposal = ChannelProposal(
      name: 'Drama',
      source: LibrarySource(
        libraryId: 'movies',
        libraryType: PlexLibraryType.movie,
        filters: {
          LibraryFilter.genre: ['Drama'],
        },
      ),
      mode: PlaybackMode.shuffle,
      itemCount: 10,
      playableItemCount: 10,
      blockItemCountWithoutSpecials: 10,
      strategy: BuilderStrategy.genres,
    );

    for (final mode in [ChannelBuildMode.append, ChannelBuildMode.merge]) {
      final result = materializeChannelPlan(
        proposals: const [proposal],
        existing: existing,
        mode: mode,
        anchor: DateTime.utc(2027),
      );
      expect(result.channels, isEmpty, reason: mode.name);
      expect(result.truncated, isTrue, reason: mode.name);
    }
  });

  test('append skips existing generated keys and reports the count', () {
    const proposal = ChannelProposal(
      name: 'Series',
      source: LibrarySource(libraryId: 'tv', libraryType: PlexLibraryType.show),
      mode: PlaybackMode.shuffle,
      itemCount: 10,
      playableItemCount: 10,
      blockItemCountWithoutSpecials: 10,
      strategy: BuilderStrategy.collections,
      series: true,
    );
    final existing = materializeChannelPlan(
      proposals: const [proposal],
      existing: const [],
      mode: ChannelBuildMode.replace,
      alternateCopies: 1,
      anchor: DateTime.utc(2026),
    ).channels;

    final result = materializeChannelPlan(
      proposals: const [proposal],
      existing: existing,
      mode: ChannelBuildMode.append,
      alternateCopies: 1,
      anchor: DateTime.utc(2027),
    );

    expect(result.channels, isEmpty);
    expect(result.existingSkipped, 2);
    expect(result.allocatedOriginals, 0);
    expect(result.allocatedExtras, 0);
    expect(result.excludedOriginals, 0);
    expect(result.excludedExtras, 0);
    expect(result.truncated, isFalse);
  });

  test('merge reuses exact channels without resetting their schedule', () {
    const proposal = ChannelProposal(
      name: 'Series',
      source: LibrarySource(libraryId: 'tv', libraryType: PlexLibraryType.show),
      mode: PlaybackMode.shuffle,
      itemCount: 10,
      playableItemCount: 10,
      blockItemCountWithoutSpecials: 10,
      strategy: BuilderStrategy.recentlyAdded,
      series: true,
    );
    final existing = materializeChannelPlan(
      proposals: const [proposal],
      existing: const [],
      mode: ChannelBuildMode.replace,
      seriesMode: PlaybackMode.block,
      seriesBlockSize: 4,
      anchor: DateTime.utc(2026),
    ).channels.single;
    final merged = materializeChannelPlan(
      proposals: const [proposal],
      existing: [existing],
      mode: ChannelBuildMode.merge,
      seriesMode: PlaybackMode.block,
      seriesBlockSize: 4,
      anchor: DateTime.utc(2027),
    ).channels.single;

    expect(merged, same(existing));
    expect(merged.anchor, DateTime.utc(2026));
  });

  test('changed merge match receives every requested material field', () {
    const proposal = ChannelProposal(
      name: 'Series',
      source: LibrarySource(libraryId: 'tv', libraryType: PlexLibraryType.show),
      mode: PlaybackMode.shuffle,
      itemCount: 10,
      playableItemCount: 10,
      blockItemCountWithoutSpecials: 10,
      strategy: BuilderStrategy.recentlyAdded,
      series: true,
    );
    final generated = materializeChannelPlan(
      proposals: const [proposal],
      existing: const [],
      mode: ChannelBuildMode.replace,
      seriesMode: PlaybackMode.block,
      seriesBlockSize: 5,
      anchor: DateTime.utc(2026),
    ).channels.single;
    final staleShuffleSeed = generated.shuffleSeed + 1;
    final stale = Channel(
      id: generated.id,
      number: 42,
      name: 'Old name',
      source: const ManualSource([]),
      playbackMode: PlaybackMode.sequential,
      anchor: DateTime.utc(2025),
      shuffleSeed: staleShuffleSeed,
      builderKey: generated.builderKey,
    );
    final changed = materializeChannelPlan(
      proposals: const [proposal],
      existing: [stale],
      mode: ChannelBuildMode.merge,
      seriesMode: PlaybackMode.block,
      seriesBlockSize: 5,
      anchor: DateTime.utc(2027),
    ).channels.single;

    expect(changed, isNot(same(stale)));
    expect(changed.id, stale.id);
    expect(changed.number, 42);
    expect(changed.name, 'Old name');
    expect(changed.source.toJson(), proposal.source.toJson());
    expect(changed.playbackMode, PlaybackMode.block);
    expect(changed.blockSize, 5);
    expect(changed.anchor, DateTime.utc(2025));
    expect(changed.shuffleSeed, staleShuffleSeed);
    expect(changed.builderKey, stale.builderKey);
  });

  test('merge allocation reports unmatched generated channels separately', () {
    const proposal = ChannelProposal(
      name: 'Comedy',
      source: LibrarySource(
        libraryId: 'movies',
        libraryType: PlexLibraryType.movie,
        filters: {
          LibraryFilter.genre: ['Comedy'],
        },
      ),
      mode: PlaybackMode.shuffle,
      itemCount: 10,
      playableItemCount: 10,
      blockItemCountWithoutSpecials: 10,
      strategy: BuilderStrategy.genres,
    );
    final matched = materializeChannelPlan(
      proposals: const [proposal],
      existing: const [],
      mode: ChannelBuildMode.replace,
      anchor: DateTime.utc(2026),
    ).channels.single;
    final unmatched = Channel(
      id: 'unmatched',
      number: 2,
      name: 'Unmatched',
      source: const ManualSource([]),
      playbackMode: PlaybackMode.sequential,
      anchor: DateTime.utc(2026),
      shuffleSeed: 2,
      builderKey: 'stale-generated-key',
    );
    final custom = Channel(
      id: 'custom',
      number: 3,
      name: 'Custom',
      source: const ManualSource([]),
      playbackMode: PlaybackMode.sequential,
      anchor: DateTime.utc(2026),
      shuffleSeed: 3,
    );
    final existing = [matched, unmatched, custom];

    final merged = materializeChannelPlan(
      proposals: const [proposal],
      existing: existing,
      mode: ChannelBuildMode.merge,
      anchor: DateTime.utc(2027),
    );

    expect(merged.channels.map((channel) => channel.id), [matched.id]);
    expect(merged.unmatchedGenerated.map((channel) => channel.id), [
      unmatched.id,
    ]);
    expect(() => merged.unmatchedGenerated.add(custom), throwsUnsupportedError);

    for (final mode in [ChannelBuildMode.replace, ChannelBuildMode.append]) {
      final allocation = materializeChannelPlan(
        proposals: const [proposal],
        existing: existing,
        mode: mode,
        anchor: DateTime.utc(2027),
      );
      expect(allocation.unmatchedGenerated, isEmpty, reason: mode.name);
    }
  });

  test('plan composition preserves custom channels across every mode', () {
    Channel channel(String id, int number, {String? builderKey}) => Channel(
      id: id,
      number: number,
      name: id,
      source: const ManualSource([]),
      playbackMode: PlaybackMode.sequential,
      anchor: DateTime.utc(2026),
      shuffleSeed: number,
      builderKey: builderKey,
    );

    final custom = channel('custom', 30);
    final staleMatch = channel('stale-match', 20, builderKey: 'genre:drama');
    final staleOther = channel('stale-other', 10, builderKey: 'genre:comedy');
    final planned = channel('planned', 20, builderKey: 'genre:drama');

    expect(
      composeChannelPlan(
        existing: [custom, staleMatch, staleOther],
        planned: [planned],
        mode: ChannelBuildMode.replace,
      ).map((channel) => channel.id),
      ['planned', 'custom'],
    );
    expect(
      composeChannelPlan(
        existing: [custom, staleMatch, staleOther],
        planned: [planned],
        mode: ChannelBuildMode.append,
      ).map((channel) => channel.id),
      ['stale-other', 'stale-match', 'planned', 'custom'],
    );
    expect(
      composeChannelPlan(
        existing: [custom, staleMatch, staleOther],
        planned: [planned],
        mode: ChannelBuildMode.merge,
      ).map((channel) => channel.id),
      ['stale-other', 'planned', 'custom'],
    );
  });

  test('allocation fills originals before fair extra-version rounds', () {
    ChannelProposal proposal(String name) => ChannelProposal(
      name: name,
      source: LibrarySource(libraryId: name, libraryType: PlexLibraryType.show),
      mode: PlaybackMode.shuffle,
      itemCount: 20,
      playableItemCount: 20,
      blockItemCountWithoutSpecials: 20,
      strategy: BuilderStrategy.recentlyAdded,
      series: true,
    );

    final result = materializeChannelPlan(
      proposals: [proposal('First'), proposal('Second')],
      existing: const [],
      mode: ChannelBuildMode.replace,
      alternateCopies: 2,
      variantMode: PlaybackMode.block,
      variantBlockSize: 4,
      maximumChannels: 6,
      anchor: DateTime.utc(2026),
    );

    expect(result.channels.map((channel) => channel.name), [
      'First',
      'Second',
      'First block',
      'Second block',
      'First Alt 1',
      'Second Alt 1',
    ]);
    expect(result.allocatedOriginals, 2);
    expect(result.excludedOriginals, 0);
    expect(result.allocatedExtras, 4);
    expect(result.excludedExtras, 2);
    expect(
      result.allocatedChannelsByStrategy[BuilderStrategy.recentlyAdded],
      6,
    );
    expect(result.truncated, isTrue);
  });

  test('excluded originals never receive extra versions', () {
    ChannelProposal proposal(String name) => ChannelProposal(
      name: name,
      source: LibrarySource(libraryId: name, libraryType: PlexLibraryType.show),
      mode: PlaybackMode.shuffle,
      itemCount: 20,
      playableItemCount: 20,
      blockItemCountWithoutSpecials: 20,
      strategy: BuilderStrategy.recentlyAdded,
      series: true,
    );

    final result = materializeChannelPlan(
      proposals: [proposal('First'), proposal('Second'), proposal('Excluded')],
      existing: const [],
      mode: ChannelBuildMode.replace,
      alternateCopies: 2,
      maximumChannels: 2,
      anchor: DateTime.utc(2026),
    );

    expect(result.channels.map((channel) => channel.name), ['First', 'Second']);
    expect(result.allocatedOriginals, 2);
    expect(result.excludedOriginals, 1);
    expect(result.allocatedExtras, 0);
    expect(result.excludedExtras, 4);
  });

  test('in-order originals keep only a requested different-mode version', () {
    const proposal = ChannelProposal(
      name: 'Series',
      source: LibrarySource(
        libraryId: 'shows',
        libraryType: PlexLibraryType.show,
      ),
      mode: PlaybackMode.shuffle,
      itemCount: 20,
      playableItemCount: 20,
      blockItemCountWithoutSpecials: 20,
      strategy: BuilderStrategy.recentlyAdded,
      series: true,
    );

    final result = materializeChannelPlan(
      proposals: const [proposal],
      existing: const [],
      mode: ChannelBuildMode.replace,
      seriesMode: PlaybackMode.sequential,
      alternateCopies: 3,
      variantMode: PlaybackMode.block,
      maximumChannels: 10,
      anchor: DateTime.utc(2026),
    );

    expect(result.channels, hasLength(2));
    expect(result.channels.last.playbackMode, PlaybackMode.block);
    expect(result.allocatedExtras, 1);
    expect(result.excludedExtras, 0);
  });

  test('reviewed specials setting updates matched generated channels', () {
    const proposal = ChannelProposal(
      name: 'Series',
      source: LibrarySource(
        libraryId: 'shows',
        libraryType: PlexLibraryType.show,
      ),
      mode: PlaybackMode.shuffle,
      itemCount: 20,
      playableItemCount: 20,
      blockItemCountWithoutSpecials: 20,
      strategy: BuilderStrategy.recentlyAdded,
      series: true,
    );
    final existing = materializeChannelPlan(
      proposals: const [proposal],
      existing: const [],
      mode: ChannelBuildMode.replace,
      seriesMode: PlaybackMode.block,
      includeSpecials: true,
      anchor: DateTime.utc(2026),
    ).channels.single;

    final updated = materializeChannelPlan(
      proposals: const [proposal],
      existing: [existing],
      mode: ChannelBuildMode.merge,
      seriesMode: PlaybackMode.block,
      includeSpecials: false,
      anchor: DateTime.utc(2027),
    ).channels.single;

    expect(updated.id, existing.id);
    expect(updated.includeSpecials, isFalse);
    expect(updated, isNot(same(existing)));
  });

  test(
    'merge reuses equivalent non-block channels when specials is requested',
    () {
      const proposal = ChannelProposal(
        name: 'Movies',
        source: LibrarySource(
          libraryId: 'movies',
          libraryType: PlexLibraryType.movie,
        ),
        mode: PlaybackMode.shuffle,
        itemCount: 20,
        playableItemCount: 20,
        blockItemCountWithoutSpecials: 20,
        strategy: BuilderStrategy.recentlyAdded,
      );
      final existing = materializeChannelPlan(
        proposals: const [proposal],
        existing: const [],
        mode: ChannelBuildMode.replace,
        anchor: DateTime.utc(2026),
      ).channels.single;

      final merged = materializeChannelPlan(
        proposals: const [proposal],
        existing: [existing],
        mode: ChannelBuildMode.merge,
        includeSpecials: true,
        anchor: DateTime.utc(2027),
      ).channels.single;

      expect(merged, same(existing));
      expect(merged.includeSpecials, isFalse);
    },
  );

  test(
    'proposal discovery can return the complete balanced candidate pool',
    () {
      const library = PlexLibrary(
        id: 'movies',
        title: 'Movies',
        type: PlexLibraryType.movie,
      );
      final items = [
        for (var index = 0; index < 3; index++)
          PlexMediaItem(
            id: '$index',
            title: 'Movie $index',
            type: 'movie',
            duration: const Duration(minutes: 1),
            libraryId: 'movies',
            genres: ['Genre $index'],
          ),
      ];

      expect(
        buildChannelProposals(
          libraries: const [library],
          items: items,
          strategies: const {BuilderStrategy.genres},
          minimumItems: 1,
          maximumChannels: 2,
        ),
        hasLength(2),
      );
      expect(
        buildChannelProposals(
          libraries: const [library],
          items: items,
          strategies: const {BuilderStrategy.genres},
          minimumItems: 1,
          maximumChannels: null,
        ),
        hasLength(3),
      );
    },
  );
}

PlexMediaItem _builderEpisode(String id, int season, String collection) =>
    PlexMediaItem(
      id: id,
      title: id,
      type: 'episode',
      duration: const Duration(minutes: 20),
      libraryId: 'tv',
      grandparentRatingKey: 'show',
      grandparentTitle: 'Show',
      seasonNumber: season,
      episodeNumber: 1,
      collections: [collection],
      parts: [PlexMediaPart(path: '/parts/$id')],
    );
