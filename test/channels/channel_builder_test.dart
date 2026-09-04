import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/channels/channel_builder.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

void main() {
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
      'collection': 'Friday Night',
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

  test('series ordering and variants expand without losing stable numbers', () {
    const proposal = ChannelProposal(
      name: 'Series',
      source: LibrarySource(libraryId: 'tv', libraryType: PlexLibraryType.show),
      mode: PlaybackMode.shuffle,
      itemCount: 10,
      strategy: BuilderStrategy.recentlyAdded,
    );
    final channels = materializeChannelPlan(
      proposals: const [proposal],
      existing: const [],
      mode: ChannelBuildMode.replace,
      seriesMode: PlaybackMode.block,
      alternateCopies: 2,
      variantMode: PlaybackMode.sequential,
      anchor: DateTime.utc(2026),
    ).channels;
    expect(channels.map((channel) => channel.number), [1, 2, 3, 4]);
    expect(channels.map((channel) => channel.name), [
      'Series',
      'Series Alt 1',
      'Series Alt 2',
      'Series sequential',
    ]);
    expect(channels.first.blockSize, 3);
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
          filters: {'genre': 'Comedy'},
        ),
        mode: PlaybackMode.shuffle,
        itemCount: 10,
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
        filters: {'genre': 'Comedy', 'sort': 'title'},
      ),
      mode: PlaybackMode.shuffle,
      itemCount: 10,
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
        filters: {'sort': 'title', 'genre': 'Comedy'},
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
          filters: {'genre': 'Drama $index'},
        ),
        mode: PlaybackMode.shuffle,
        itemCount: 10,
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

  test('maximum channels applies after series expansion', () {
    const proposal = ChannelProposal(
      name: 'Series',
      source: LibrarySource(libraryId: 'tv', libraryType: PlexLibraryType.show),
      mode: PlaybackMode.shuffle,
      itemCount: 10,
      strategy: BuilderStrategy.recentlyAdded,
      series: true,
    );
    final result = materializeChannelPlan(
      proposals: const [proposal],
      existing: const [],
      mode: ChannelBuildMode.replace,
      alternateCopies: 3,
      variantMode: PlaybackMode.block,
      maximumChannels: 2,
      anchor: DateTime.utc(2026),
    );
    expect(result.channels, hasLength(2));
    expect(result.truncated, isTrue);
  });

  test('merge identity remains stable when playback configuration changes', () {
    const proposal = ChannelProposal(
      name: 'Series',
      source: LibrarySource(libraryId: 'tv', libraryType: PlexLibraryType.show),
      mode: PlaybackMode.shuffle,
      itemCount: 10,
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
        filters: {'genre': 'Drama'},
      ),
      mode: PlaybackMode.shuffle,
      itemCount: 10,
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

  test('merge reuses exact channels without resetting their schedule', () {
    const proposal = ChannelProposal(
      name: 'Series',
      source: LibrarySource(libraryId: 'tv', libraryType: PlexLibraryType.show),
      mode: PlaybackMode.shuffle,
      itemCount: 10,
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
}
