import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../plex/plex_models.dart';
import 'channel.dart';
import 'content_resolver.dart';

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

enum ChannelBuildMode { replace, append, merge }

const builderStrategyLabels = {
  BuilderStrategy.playlists: 'Playlists',
  BuilderStrategy.collections: 'Collections',
  BuilderStrategy.recentlyAdded: 'Recently Added',
  BuilderStrategy.genres: 'Genres',
  BuilderStrategy.studios: 'Studios',
  BuilderStrategy.actors: 'Actors',
  BuilderStrategy.decades: 'Decades',
  BuilderStrategy.directors: 'Directors',
};

class ChannelProposal {
  const ChannelProposal({
    required this.name,
    required this.source,
    required this.mode,
    required this.itemCount,
    required this.strategy,
    this.series = false,
  });

  final String name;
  final ContentSource source;
  final PlaybackMode mode;
  final int itemCount;
  final BuilderStrategy strategy;
  final bool series;
}

List<ChannelProposal> buildChannelProposals({
  required List<PlexLibrary> libraries,
  required List<PlexMediaItem> items,
  List<PlexPlaylist> playlists = const [],
  Set<BuilderStrategy> strategies = const {...BuilderStrategy.values},
  List<BuilderStrategy> strategyOrder = BuilderStrategy.values,
  Set<BuilderStrategy> crossLibraryStrategies = const {},
  int minimumItems = 5,
  int maximumChannels = 200,
}) {
  final proposals = <ChannelProposal>[];
  final sourceLibraries = libraries.toList();

  void addTags(
    BuilderStrategy strategy,
    Iterable<String> Function(PlexMediaItem) select,
    String filterKey,
  ) {
    if (!strategies.contains(strategy)) return;
    final countsByLibrary = <PlexLibrary, Map<String, int>>{};
    for (final library in sourceLibraries) {
      final counts = <String, int>{};
      for (final item in items.where((item) => item.libraryId == library.id)) {
        for (final tag
            in select(item)
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toSet()) {
          counts[tag] = (counts[tag] ?? 0) + 1;
        }
      }
      countsByLibrary[library] = counts;
    }
    bool eligible(PlexLibrary library, String tag, {bool minimum = true}) {
      final count = countsByLibrary[library]![tag] ?? 0;
      if (count == 0 || (minimum && count < minimumItems)) return false;
      if (library.type != PlexLibraryType.show ||
          !{
            BuilderStrategy.actors,
            BuilderStrategy.directors,
          }.contains(strategy)) {
        return true;
      }
      final series = items
          .where(
            (item) =>
                item.libraryId == library.id &&
                select(item).contains(tag) &&
                item.grandparentTitle != null,
          )
          .map((item) => item.grandparentTitle)
          .toSet();
      return series.length >= 3;
    }

    if (crossLibraryStrategies.contains(strategy) &&
        sourceLibraries.length > 1) {
      final tags = <String>{
        for (final counts in countsByLibrary.values) ...counts.keys,
      };
      for (final tag in tags) {
        final sources = <ContentSource>[];
        var count = 0;
        for (final library in sourceLibraries) {
          final libraryCount = countsByLibrary[library]![tag] ?? 0;
          if (!eligible(library, tag, minimum: false)) continue;
          count += libraryCount;
          sources.add(
            LibrarySource(
              libraryId: library.id,
              libraryType: library.type,
              filters: {filterKey: tag},
            ),
          );
        }
        if (count >= minimumItems) {
          proposals.add(
            ChannelProposal(
              name: tag,
              source: sources.length == 1
                  ? sources.single
                  : MixedSource(sources: sources, interleave: true),
              mode: PlaybackMode.shuffle,
              itemCount: count,
              strategy: strategy,
            ),
          );
        }
      }
      return;
    }
    for (final library in sourceLibraries) {
      for (final entry in countsByLibrary[library]!.entries.where(
        (entry) => eligible(library, entry.key),
      )) {
        proposals.add(
          ChannelProposal(
            name: sourceLibraries.length == 1
                ? entry.key
                : '${library.title} • ${entry.key}',
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

  if (strategies.contains(BuilderStrategy.playlists)) {
    for (final playlist in playlists) {
      if (playlist.items.length < minimumItems) continue;
      proposals.add(
        ChannelProposal(
          name: playlist.title,
          source: PlaylistSource(playlist.id),
          mode: PlaybackMode.shuffle,
          itemCount: playlist.items.length,
          strategy: BuilderStrategy.playlists,
          series: playlist.items.any((item) => item.type == 'episode'),
        ),
      );
    }
  }
  addTags(
    BuilderStrategy.collections,
    (item) => item.collections,
    'collection',
  );
  if (strategies.contains(BuilderStrategy.recentlyAdded)) {
    for (final library in libraries) {
      final itemCount = items
          .where((item) => item.libraryId == library.id)
          .length;
      if (itemCount >= minimumItems) {
        proposals.add(
          ChannelProposal(
            name: '${library.title} Recently Added',
            source: LibrarySource(
              libraryId: library.id,
              libraryType: library.type,
              filters: const {'sort': 'added:desc'},
            ),
            mode: PlaybackMode.sequential,
            itemCount: itemCount,
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
  addTags(
    BuilderStrategy.decades,
    (item) => [?channelDecadeForYear(item.year)],
    'decade',
  );
  final priority = {
    for (var index = 0; index < strategyOrder.length; index++)
      strategyOrder[index]: index,
  };
  proposals.sort((a, b) {
    final strategy = (priority[a.strategy] ?? strategyOrder.length).compareTo(
      priority[b.strategy] ?? strategyOrder.length,
    );
    if (strategy != 0) return strategy;
    final count = b.itemCount.compareTo(a.itemCount);
    return count != 0 ? count : a.name.compareTo(b.name);
  });
  final buckets = [
    for (final strategy in strategyOrder)
      proposals.where((proposal) => proposal.strategy == strategy).toList(),
  ];
  final balanced = <ChannelProposal>[];
  for (
    var index = 0;
    balanced.length < maximumChannels &&
        buckets.any((bucket) => index < bucket.length);
    index++
  ) {
    for (final bucket in buckets) {
      if (index < bucket.length) balanced.add(bucket[index]);
      if (balanced.length == maximumChannels) break;
    }
  }
  return List.unmodifiable(balanced);
}

({List<Channel> channels, bool truncated}) materializeChannelPlan({
  required List<ChannelProposal> proposals,
  required List<Channel> existing,
  required ChannelBuildMode mode,
  PlaybackMode seriesMode = PlaybackMode.shuffle,
  int seriesBlockSize = 3,
  int alternateCopies = 0,
  PlaybackMode? variantMode,
  int variantBlockSize = 3,
  int maximumChannels = 1000,
  DateTime? anchor,
}) {
  final expanded =
      <
        ({
          ChannelProposal proposal,
          String suffix,
          PlaybackMode mode,
          int? blockSize,
        })
      >[];
  for (final proposal in proposals) {
    final isSeries = proposal.series || _containsShows(proposal.source);
    final baseMode = isSeries ? seriesMode : proposal.mode;
    final baseBlockSize = baseMode == PlaybackMode.block
        ? seriesBlockSize
        : null;
    expanded.add((
      proposal: proposal,
      suffix: '',
      mode: baseMode,
      blockSize: baseBlockSize,
    ));
    final replicable =
        isSeries &&
        !{
          BuilderStrategy.actors,
          BuilderStrategy.directors,
        }.contains(proposal.strategy);
    if (replicable && baseMode != PlaybackMode.sequential) {
      for (var copy = 1; copy <= alternateCopies; copy++) {
        expanded.add((
          proposal: proposal,
          suffix: ' Alt $copy',
          mode: baseMode,
          blockSize: baseBlockSize,
        ));
      }
    }
    if (isSeries && baseMode != PlaybackMode.sequential) {
      if (variantMode != null && variantMode != baseMode) {
        expanded.add((
          proposal: proposal,
          suffix: ' ${variantMode.name}',
          mode: variantMode,
          blockSize: variantMode == PlaybackMode.block
              ? variantBlockSize
              : null,
        ));
      }
    }
  }
  final used = mode == ChannelBuildMode.replace
      ? existing
            .where((channel) => channel.builderKey == null)
            .map((channel) => channel.number)
            .toSet()
      : existing.map((channel) => channel.number).toSet();
  final output = <Channel>[];
  var next = 1;
  var truncated = false;
  for (final entry in expanded) {
    if (output.length == maximumChannels) {
      truncated = true;
      break;
    }
    final name = '${entry.proposal.name}${entry.suffix}';
    final builderKey = _builderKey(entry.proposal, entry.suffix);
    final matched = mode == ChannelBuildMode.merge
        ? existing
              .where(
                (channel) =>
                    channel.builderKey != null &&
                    channel.builderKey == builderKey,
              )
              .firstOrNull
        : null;
    while (matched == null && used.contains(next) && next <= 1000) {
      next++;
    }
    if (matched == null && next > 1000) {
      truncated = true;
      break;
    }
    if (matched != null &&
        jsonEncode(matched.source.toJson()) ==
            jsonEncode(entry.proposal.source.toJson()) &&
        matched.playbackMode == entry.mode &&
        matched.blockSize == entry.blockSize) {
      output.add(matched);
      continue;
    }
    final id = matched?.id ?? createChannelId();
    final number = matched?.number ?? next;
    output.add(
      Channel(
        id: id,
        number: number,
        name: matched?.name ?? name,
        source: entry.proposal.source,
        playbackMode: entry.mode,
        anchor: matched?.anchor ?? anchor ?? DateTime.now().toUtc(),
        shuffleSeed: matched?.shuffleSeed ?? id.hashCode,
        blockSize: entry.blockSize,
        builderKey: builderKey,
      ),
    );
    used.add(number);
    if (matched == null) next++;
  }
  return (channels: List.unmodifiable(output), truncated: truncated);
}

bool _containsShows(ContentSource source) => switch (source) {
  LibrarySource(:final libraryType) => libraryType == PlexLibraryType.show,
  MixedSource(:final sources) => sources.any(_containsShows),
  ManualSource() => false,
  PlaylistSource() => false,
};

String _builderKey(ChannelProposal proposal, String suffix) => sha256
    .convert(
      utf8.encode(
        jsonEncode({
          'strategy': proposal.strategy.name,
          'source': proposal.source.toJson(),
          'suffix': suffix,
        }),
      ),
    )
    .toString();
