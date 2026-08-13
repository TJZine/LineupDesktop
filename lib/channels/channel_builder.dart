import '../plex/plex_models.dart';
import 'channel.dart';

enum BuilderStrategy {
  playlists,
  collections,
  recentlyAdded,
  genres,
  studios,
  actors,
  decades,
  directors,
}

class ChannelProposal {
  const ChannelProposal({
    required this.name,
    required this.source,
    required this.mode,
    required this.itemCount,
    required this.strategy,
  });

  final String name;
  final ContentSource source;
  final PlaybackMode mode;
  final int itemCount;
  final BuilderStrategy strategy;
}

List<ChannelProposal> buildChannelProposals({
  required List<PlexLibrary> libraries,
  required List<PlexMediaItem> items,
  Set<BuilderStrategy> strategies = const {
    BuilderStrategy.recentlyAdded,
    BuilderStrategy.genres,
    BuilderStrategy.studios,
    BuilderStrategy.actors,
    BuilderStrategy.decades,
    BuilderStrategy.directors,
  },
  int minimumItems = 5,
  int maximumChannels = 200,
}) {
  final proposals = <ChannelProposal>[];
  final movieLibraries = libraries
      .where((library) => library.type == PlexLibraryType.movie)
      .toList();

  void addTags(
    BuilderStrategy strategy,
    Iterable<String> Function(PlexMediaItem) select,
    String filterKey,
  ) {
    if (!strategies.contains(strategy)) return;
    final counts = <String, int>{};
    for (final item in items) {
      for (final tag
          in select(item)
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toSet()) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    for (final entry
        in counts.entries.where((entry) => entry.value >= minimumItems).toList()
          ..sort(
            (a, b) => b.value.compareTo(a.value) != 0
                ? b.value.compareTo(a.value)
                : a.key.compareTo(b.key),
          )) {
      for (final library in movieLibraries.take(1)) {
        proposals.add(
          ChannelProposal(
            name: entry.key,
            source: LibrarySource(
              libraryId: library.id,
              libraryType: library.type,
              filters: {filterKey: entry.key},
            ),
            mode: PlaybackMode.shuffle,
            itemCount: entry.value,
            strategy: strategy,
          ),
        );
      }
    }
  }

  if (strategies.contains(BuilderStrategy.recentlyAdded)) {
    for (final library in libraries) {
      if (items.length >= minimumItems) {
        proposals.add(
          ChannelProposal(
            name: '${library.title} Recently Added',
            source: LibrarySource(
              libraryId: library.id,
              libraryType: library.type,
              filters: const {'sort': 'added:desc'},
            ),
            mode: PlaybackMode.sequential,
            itemCount: items.length,
            strategy: BuilderStrategy.recentlyAdded,
          ),
        );
      }
    }
  }
  addTags(BuilderStrategy.genres, (item) => item.genres, 'genre');
  addTags(
    BuilderStrategy.studios,
    (item) => [if (item.studio != null) item.studio!],
    'studio',
  );
  addTags(BuilderStrategy.actors, (item) => item.actors, 'actor');
  addTags(BuilderStrategy.directors, (item) => item.directors, 'director');
  if (strategies.contains(BuilderStrategy.decades)) {
    addTags(
      BuilderStrategy.decades,
      (item) => [if (item.year != null) '${item.year! ~/ 10 * 10}s'],
      'decade',
    );
  }
  proposals.sort((a, b) {
    final strategy = a.strategy.index.compareTo(b.strategy.index);
    if (strategy != 0) return strategy;
    final count = b.itemCount.compareTo(a.itemCount);
    return count != 0 ? count : a.name.compareTo(b.name);
  });
  return proposals.take(maximumChannels).toList(growable: false);
}
