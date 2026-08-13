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
        key: '/$index',
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
        key: '/1',
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
        key: '/library/metadata/$index',
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
    expect(proposals.first.source, isA<ManualSource>());
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
            key: '/${library.id}/$index',
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
    );
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
          key: '/$index',
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
        key: '/$index',
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

  test('TV people channels require breadth across three series', () {
    const library = PlexLibrary(
      id: 'tv',
      title: 'Shows',
      type: PlexLibraryType.show,
    );
    List<PlexMediaItem> episodes(List<String> series) => [
      for (var index = 0; index < 6; index++)
        PlexMediaItem(
          id: '$series-$index',
          key: '/$index',
          title: 'Episode',
          type: 'episode',
          duration: const Duration(minutes: 1),
          libraryId: 'tv',
          grandparentTitle: series[index % series.length],
          actors: const ['Actor'],
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
}
