import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../plex/plex_models.dart';
import 'channel.dart';
import 'content_resolver.dart';
import 'library_facets.dart';
import 'scheduler.dart';

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

BuilderStrategy? channelSourceType(Channel channel) =>
    channel.builderKey == null ? null : _generatedSourceType(channel.source);

BuilderStrategy? _generatedSourceType(ContentSource source) {
  switch (source) {
    case PlaylistSource():
      return BuilderStrategy.playlists;
    case MixedSource(:final sources):
      return sources.map(_generatedSourceType).nonNulls.firstOrNull;
    case LibrarySource(:final filters, :final order):
      if (order == LibraryOrder.addedDescending) {
        return BuilderStrategy.recentlyAdded;
      }
      return switch (filters.keys.firstOrNull) {
        LibraryFilter.collection => BuilderStrategy.collections,
        LibraryFilter.genre => BuilderStrategy.genres,
        LibraryFilter.studio => BuilderStrategy.studios,
        LibraryFilter.actor => BuilderStrategy.actors,
        LibraryFilter.decade => BuilderStrategy.decades,
        LibraryFilter.director => BuilderStrategy.directors,
        null => null,
      };
    case ManualSource():
      return null;
  }
}

enum ChannelBuildMode { replace, append, merge }

const playbackModeLabels = {
  PlaybackMode.shuffle: 'Shuffle',
  PlaybackMode.sequential: 'In order',
  PlaybackMode.block: 'Mini-marathons',
};

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
    this.sourceLibraries = const {},
    this.sourceLibrariesIncomplete = false,
    this.playlistKind = ChannelKind.unknown,
    this.playlistLibraryIds = const {},
    required this.playableItemCount,
    required this.blockItemCountWithoutSpecials,
  });

  final String name;
  final ContentSource source;
  final PlaybackMode mode;
  final int itemCount;
  final BuilderStrategy strategy;
  final bool series;
  final Map<String, String> sourceLibraries;
  final bool sourceLibrariesIncomplete;
  final ChannelKind playlistKind;
  final Set<String> playlistLibraryIds;

  /// Resolved inventory counts used to allocate each playback version.
  /// Apply validates the current inventory independently of these proposal facts.
  final int playableItemCount;
  final int blockItemCountWithoutSpecials;
}

List<ChannelProposal> buildChannelProposals({
  required List<PlexLibrary> libraries,
  required List<PlexMediaItem> items,
  List<PlexPlaylist> playlists = const [],
  Set<BuilderStrategy> strategies = const {...BuilderStrategy.values},
  List<BuilderStrategy> strategyOrder = BuilderStrategy.values,
  Set<BuilderStrategy> crossLibraryStrategies = const {},
  int minimumItems = 5,
  int? maximumChannels = 200,
}) {
  final proposals = <ChannelProposal>[];
  final sourceLibraries = libraries.toList();
  final scannedById = {for (final item in items) item.id: item};
  final titleById = {
    for (final library in libraries) library.id: library.title,
  };
  final blockInclusion = <PlexMediaItem, bool>{};
  bool includedWithoutSpecials(PlexMediaItem item) =>
      blockInclusion.putIfAbsent(
        item,
        () => scheduleIncludesItem(
          channelItemFor(item),
          mode: PlaybackMode.block,
          includeSpecials: false,
        ),
      );

  ({int playable, int withoutSpecials}) contentCounts(
    Iterable<PlexMediaItem> media, {
    bool unique = false,
  }) {
    final seen = <String>{};
    var playable = 0;
    var withoutSpecials = 0;
    for (final item in media) {
      if (!item.isPlayable || (unique && !seen.add(item.id))) continue;
      playable++;
      if (includedWithoutSpecials(item)) withoutSpecials++;
    }
    return (playable: playable, withoutSpecials: withoutSpecials);
  }

  void addTags(BuilderStrategy strategy, LibraryFilter filter) {
    if (!strategies.contains(strategy)) return;
    final countsByLibrary = <PlexLibrary, Map<String, int>>{};
    final playableCountsByLibrary = <PlexLibrary, Map<String, int>>{};
    final blockCountsByLibrary = <PlexLibrary, Map<String, int>>{};
    final seriesByLibrary = <PlexLibrary, Map<String, Set<String>>>{};
    final tagLabels = <String, String>{};
    final requiresSeriesBreadth = {
      BuilderStrategy.actors,
      BuilderStrategy.directors,
    }.contains(strategy);
    for (final library in sourceLibraries) {
      final counts = <String, int>{};
      final playableCounts = <String, int>{};
      final blockCounts = <String, int>{};
      final seenPlayableByTag = <String, Set<String>>{};
      final seriesByTag = <String, Set<String>>{};
      for (final item in items.where((item) => item.libraryId == library.id)) {
        final selectedTags = <String, String>{};
        final matchingTags = <String>{};
        for (final value in libraryFacetValues(item, filter)) {
          final label = value.trim();
          if (label.isEmpty) continue;
          final tag = requiresSeriesBreadth
              ? canonicalFilterIdentity(filter, label)
              : label;
          selectedTags.putIfAbsent(tag, () => label);
          if (requiresSeriesBreadth || value == tag) matchingTags.add(tag);
          tagLabels.update(
            tag,
            (current) => requiresSeriesBreadth
                ? _preferredPersonLabel(current, label)
                : current,
            ifAbsent: () => label,
          );
        }
        for (final tag in selectedTags.keys) {
          counts[tag] = (counts[tag] ?? 0) + 1;
          if (matchingTags.contains(tag) &&
              item.isPlayable &&
              (seenPlayableByTag[tag] ??= {}).add(item.id)) {
            playableCounts[tag] = (playableCounts[tag] ?? 0) + 1;
            if (includedWithoutSpecials(item)) {
              blockCounts[tag] = (blockCounts[tag] ?? 0) + 1;
            }
          }
          if (requiresSeriesBreadth && library.type == PlexLibraryType.show) {
            final series = _peopleSeriesKey(library.id, item);
            if (series != null) (seriesByTag[tag] ??= {}).add(series);
          }
        }
      }
      countsByLibrary[library] = counts;
      playableCountsByLibrary[library] = playableCounts;
      blockCountsByLibrary[library] = blockCounts;
      seriesByLibrary[library] = seriesByTag;
    }
    bool eligible(PlexLibrary library, String tag, {bool minimum = true}) {
      final count = countsByLibrary[library]![tag] ?? 0;
      if (count == 0 || (minimum && count < minimumItems)) return false;
      if (library.type != PlexLibraryType.show || !requiresSeriesBreadth) {
        return true;
      }
      return (seriesByLibrary[library]![tag]?.length ?? 0) >= 3;
    }

    if (crossLibraryStrategies.contains(strategy) &&
        sourceLibraries.length > 1) {
      final tags = <String>{
        for (final counts in countsByLibrary.values) ...counts.keys,
      };
      for (final tag in tags) {
        final sources = <LibrarySource>[];
        var count = 0;
        var playableCount = 0;
        var blockCount = 0;
        for (final library in sourceLibraries) {
          final libraryCount = countsByLibrary[library]![tag] ?? 0;
          if (!eligible(library, tag, minimum: false)) continue;
          count += libraryCount;
          playableCount += playableCountsByLibrary[library]![tag] ?? 0;
          blockCount += blockCountsByLibrary[library]![tag] ?? 0;
          sources.add(
            LibrarySource(
              libraryId: library.id,
              libraryType: library.type,
              filters: {
                filter: [tag],
              },
            ),
          );
        }
        if (count >= minimumItems) {
          proposals.add(
            ChannelProposal(
              name: tagLabels[tag]!,
              source: sources.length == 1
                  ? sources.single
                  : MixedSource(sources: sources, interleave: true),
              sourceLibraries: Map.unmodifiable({
                for (final source in sources)
                  source.libraryId: titleById[source.libraryId]!,
              }),
              mode: PlaybackMode.shuffle,
              itemCount: count,
              playableItemCount: playableCount,
              blockItemCountWithoutSpecials: blockCount,
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
            name: tagLabels[entry.key]!,
            sourceLibraries: Map.unmodifiable({library.id: library.title}),
            source: LibrarySource(
              libraryId: library.id,
              libraryType: library.type,
              filters: {
                filter: [entry.key],
              },
            ),
            mode: PlaybackMode.shuffle,
            itemCount: entry.value,
            playableItemCount:
                playableCountsByLibrary[library]![entry.key] ?? 0,
            blockItemCountWithoutSpecials:
                blockCountsByLibrary[library]![entry.key] ?? 0,
            strategy: strategy,
          ),
        );
      }
    }
  }

  if (strategies.contains(BuilderStrategy.playlists)) {
    for (final playlist in playlists) {
      if (playlist.items.length < minimumItems) continue;
      final counts = contentCounts(playlist.items);
      final membership = playlistLibraryMembership(playlist.items, scannedById);
      proposals.add(
        ChannelProposal(
          name: playlist.title,
          source: PlaylistSource(playlist.id),
          sourceLibraries: Map.unmodifiable({
            for (final id in membership.ids) id: ?titleById[id],
          }),
          sourceLibrariesIncomplete: membership.incomplete,
          playlistLibraryIds: Set.unmodifiable(membership.ids),
          playlistKind: channelKindFor(
            PlaylistSource(playlist.id),
            playlists: {playlist.id: playlist.items.map(channelItemFor)},
          ),
          mode: PlaybackMode.shuffle,
          itemCount: playlist.items.length,
          playableItemCount: counts.playable,
          blockItemCountWithoutSpecials: counts.withoutSpecials,
          strategy: BuilderStrategy.playlists,
          series: playlist.items.any((item) => item.type == 'episode'),
        ),
      );
    }
  }
  addTags(BuilderStrategy.collections, LibraryFilter.collection);
  if (strategies.contains(BuilderStrategy.recentlyAdded)) {
    for (final library in libraries) {
      final itemCount = items
          .where((item) => item.libraryId == library.id)
          .length;
      if (itemCount >= minimumItems) {
        final counts = contentCounts(
          items.where((item) => item.libraryId == library.id),
          unique: true,
        );
        proposals.add(
          ChannelProposal(
            name: 'Recently Added',
            sourceLibraries: Map.unmodifiable({library.id: library.title}),
            source: LibrarySource(
              libraryId: library.id,
              libraryType: library.type,
              order: LibraryOrder.addedDescending,
            ),
            mode: PlaybackMode.sequential,
            itemCount: itemCount,
            playableItemCount: counts.playable,
            blockItemCountWithoutSpecials: counts.withoutSpecials,
            strategy: BuilderStrategy.recentlyAdded,
          ),
        );
      }
    }
  }
  addTags(BuilderStrategy.genres, LibraryFilter.genre);
  addTags(BuilderStrategy.studios, LibraryFilter.studio);
  addTags(BuilderStrategy.actors, LibraryFilter.actor);
  addTags(BuilderStrategy.directors, LibraryFilter.director);
  addTags(BuilderStrategy.decades, LibraryFilter.decade);
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
    if (count != 0) return count;
    final name = a.name.compareTo(b.name);
    if (name != 0) return name;
    return canonicalSourceIdentity(a.source)
        .compareTo(canonicalSourceIdentity(b.source));
  });
  final buckets = [
    for (final strategy in strategyOrder)
      proposals.where((proposal) => proposal.strategy == strategy).toList(),
  ];
  final balanced = <ChannelProposal>[];
  for (
    var index = 0;
    (maximumChannels == null || balanced.length < maximumChannels) &&
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

String _preferredPersonLabel(String first, String second) {
  bool hasMixedCase(String value) =>
      value != value.toLowerCase() && value != value.toUpperCase();
  final firstIsMixed = hasMixedCase(first);
  final secondIsMixed = hasMixedCase(second);
  if (firstIsMixed != secondIsMixed) return firstIsMixed ? first : second;
  return first.compareTo(second) <= 0 ? first : second;
}

String? _peopleSeriesKey(String libraryId, PlexMediaItem item) {
  final ratingKey = item.grandparentRatingKey?.trim();
  if (ratingKey?.isNotEmpty == true) return '$libraryId:key:$ratingKey';
  final title = item.grandparentTitle?.trim();
  if (title?.isNotEmpty == true) {
    return '$libraryId:title:${title!.toLowerCase()}';
  }
  return null;
}

typedef ChannelPlanAllocation = ({
  List<Channel> channels,
  int allocatedOriginals,
  int excludedOriginals,
  int allocatedExtras,
  int excludedExtras,
  int numberLimitExcluded,
  int existingSkipped,
  List<Channel> unmatchedGenerated,
  Map<BuilderStrategy, int> eligibleOriginalsByStrategy,
  Map<BuilderStrategy, int> allocatedOriginalsByStrategy,
  Map<BuilderStrategy, int> allocatedChannelsByStrategy,
  bool truncated,
});

ChannelPlanAllocation materializeChannelPlan({
  required List<ChannelProposal> proposals,
  required List<Channel> existing,
  required ChannelBuildMode mode,
  PlaybackMode seriesMode = PlaybackMode.shuffle,
  int seriesBlockSize = 3,
  int alternateCopies = 0,
  PlaybackMode? variantMode,
  int variantBlockSize = 3,
  bool includeSpecials = false,
  int minimumItems = 1,
  int maximumChannels = 200,
  DateTime? anchor,
  ChannelOrder order = ChannelOrder.mixed,
  List<BuilderStrategy> strategyOrder = BuilderStrategy.values,
  List<ChannelItem> Function(ContentSource source)? resolve,
  bool reorderExisting = false,
}) {
  final createdAt = anchor ?? DateTime.now().toUtc();
  final resolvedBySource = <String, List<ChannelItem>>{};
  final proposalByKey = <String, ChannelProposal>{};
  final originals =
      <
        ({
          ChannelProposal proposal,
          String suffix,
          PlaybackMode mode,
          int? blockSize,
        })
      >[];
  for (final proposal in proposals) {
    final isSeries =
        proposal.mode == PlaybackMode.shuffle &&
        (proposal.series || _containsShows(proposal.source));
    final baseMode = isSeries ? seriesMode : proposal.mode;
    final baseBlockSize = baseMode == PlaybackMode.block
        ? seriesBlockSize
        : null;
    originals.add((
      proposal: proposal,
      suffix: '',
      mode: baseMode,
      blockSize: baseBlockSize,
    ));
  }
  bool eligible(
    ({
      ChannelProposal proposal,
      String suffix,
      PlaybackMode mode,
      int? blockSize,
    })
    entry,
  ) {
    final count = entry.mode == PlaybackMode.block && !includeSpecials
        ? entry.proposal.blockItemCountWithoutSpecials
        : entry.proposal.playableItemCount;
    return count >= minimumItems;
  }

  final eligibleOriginals = originals.where(eligible).toList();
  final used = mode == ChannelBuildMode.replace
      ? existing
            .where((channel) => channel.builderKey == null)
            .map((channel) => channel.number)
            .toSet()
      : existing.map((channel) => channel.number).toSet();
  final output = <Channel>[];
  final allocatedOriginalsByStrategy = <BuilderStrategy, int>{};
  final allocatedChannelsByStrategy = <BuilderStrategy, int>{};
  final existingBuilderKeys = mode == ChannelBuildMode.append
      ? existing
            .map((channel) => channel.builderKey)
            .whereType<String>()
            .toSet()
      : const <String>{};
  final existingByBuilderKey = {
    for (final channel in existing.reversed) ?channel.builderKey: channel,
  };
  final stableGrouped =
      mode == ChannelBuildMode.merge &&
      order == ChannelOrder.grouped &&
      !reorderExisting;
  final lastByType = <BuilderStrategy, int>{};
  final existingGeneratedNumbers = <int>[];
  var highest = 0;
  if (stableGrouped) {
    for (final channel in existing) {
      if (channel.number > highest) highest = channel.number;
      if (channel.builderKey != null) {
        existingGeneratedNumbers.add(channel.number);
      }
      if (channelSourceType(channel) case final type?) {
        if (channel.number > (lastByType[type] ?? 0)) {
          lastByType[type] = channel.number;
        }
      }
    }
    existingGeneratedNumbers.sort();
  }

  int groupedNumber(BuilderStrategy type) {
    final last = lastByType[type];
    if (last != null) {
      final end =
          existingGeneratedNumbers
              .where((number) => number > last)
              .firstOrNull ??
          (highest + 1);
      for (var number = last + 1; number < end; number++) {
        if (!used.contains(number)) return number;
      }
    }
    return highest + 1;
  }

  final selectedOriginals =
      <
        ({
          ChannelProposal proposal,
          String suffix,
          PlaybackMode mode,
          int? blockSize,
        })
      >[];
  final expansionOriginals =
      <
        ({
          ChannelProposal proposal,
          String suffix,
          PlaybackMode mode,
          int? blockSize,
        })
      >[];
  var next = 1;
  var numberLimitExcluded = 0;
  var existingSkipped = 0;
  var skippedOriginals = 0;
  var skippedExtras = 0;

  Channel? materialize(
    ({
      ChannelProposal proposal,
      String suffix,
      PlaybackMode mode,
      int? blockSize,
    })
    entry,
  ) {
    final proposal = entry.proposal;
    final suffix = entry.suffix;
    final name = switch (suffix) {
      '' => proposal.name,
      _ when suffix.startsWith(' Alt ') =>
        '${proposal.name} ${int.parse(suffix.substring(5)) + 1}',
      _ when entry.mode == PlaybackMode.sequential =>
        '${proposal.name} In Order',
      _ => '${proposal.name} ${playbackModeLabels[entry.mode]!}',
    };
    final kind = proposal.source is PlaylistSource
        ? proposal.playlistKind
        : channelKindFor(proposal.source);
    final builderKey = _builderKey(entry.proposal, entry.suffix);
    proposalByKey[builderKey] = proposal;
    final normalizedIncludeSpecials =
        entry.mode == PlaybackMode.block && includeSpecials;
    final prior = existingByBuilderKey[builderKey];
    final matched = mode == ChannelBuildMode.merge ? prior : null;
    if (!stableGrouped) {
      while (matched == null && used.contains(next) && next <= 1000) {
        next++;
      }
    }
    final number =
        matched?.number ??
        (stableGrouped ? groupedNumber(proposal.strategy) : next);
    if (number > 1000) return null;
    final sameSource =
        matched != null &&
        canonicalSourceEquals(matched.source, proposal.source);
    final sourceLibraries = sameSource && proposal.source is PlaylistSource
        ? playlistSourceLibraries(
            currentIds: proposal.playlistLibraryIds,
            currentTitles: proposal.sourceLibraries,
            savedTitles: matched.sourceLibraries,
          )
        : proposal.sourceLibraries;
    final sourceLibrariesIncomplete =
        proposal.sourceLibrariesIncomplete ||
        !proposal.playlistLibraryIds.every(sourceLibraries.containsKey);
    if (sameSource &&
        matched.playbackMode == entry.mode &&
        matched.blockSize == entry.blockSize &&
        matched.includeSpecials == normalizedIncludeSpecials &&
        matched.kind == kind &&
        matched.sourceLibrariesIncomplete == sourceLibrariesIncomplete &&
        canonicalChannelValueEquals(matched.sourceLibraries, sourceLibraries)) {
      return matched;
    }
    final id = matched?.id ?? createChannelId();
    final channel = Channel(
      id: id,
      number: number,
      name: matched?.name ?? name,
      source: entry.proposal.source,
      playbackMode: entry.mode,
      anchor: matched?.anchor ?? createdAt,
      favorite: mode == ChannelBuildMode.append
          ? false
          : prior?.favorite ?? false,
      kind: kind,
      sourceLibraries: sourceLibraries,
      sourceLibrariesIncomplete: sourceLibrariesIncomplete,
      shuffleSeed: matched?.shuffleSeed ?? stableChannelSeed(id),
      blockSize: entry.blockSize,
      builderKey: builderKey,
      includeSpecials: normalizedIncludeSpecials,
    );
    used.add(number);
    if (matched == null) {
      if (stableGrouped) {
        lastByType[proposal.strategy] = number;
        if (number > highest) highest = number;
      } else {
        next++;
      }
    }
    if (matched != null || resolve == null) return channel;
    final source = channel.source;
    final content = resolvedBySource.putIfAbsent(
      canonicalSourceIdentity(source),
      () => resolve(source),
    );
    return channel.copyWith(
      anchor: staggeredChannelAnchor(
        channel: channel,
        content: content,
        createdAt: createdAt,
      ),
    );
  }

  for (final entry in eligibleOriginals) {
    if (output.length == maximumChannels) break;
    if (existingBuilderKeys.contains(
      _builderKey(entry.proposal, entry.suffix),
    )) {
      existingSkipped++;
      skippedOriginals++;
      expansionOriginals.add(entry);
      continue;
    }
    final channel = materialize(entry);
    if (channel == null) {
      numberLimitExcluded++;
      expansionOriginals.add(entry);
      continue;
    }
    output.add(channel);
    allocatedChannelsByStrategy.update(
      entry.proposal.strategy,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    selectedOriginals.add(entry);
    expansionOriginals.add(entry);
    allocatedOriginalsByStrategy.update(
      entry.proposal.strategy,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }

  final extrasByOriginal = [
    for (final original in expansionOriginals)
      _extraVersions(
        original,
        alternateCopies: alternateCopies,
        variantMode: variantMode,
        variantBlockSize: variantBlockSize,
      ).where(eligible).toList(),
  ];
  final eligibleExtras = extrasByOriginal.fold<int>(
    0,
    (total, extras) => total + extras.length,
  );
  var allocatedExtras = 0;
  for (
    var round = 0;
    output.length < maximumChannels &&
        extrasByOriginal.any((extras) => round < extras.length);
    round++
  ) {
    for (final extras in extrasByOriginal) {
      if (round >= extras.length) continue;
      if (existingBuilderKeys.contains(
        _builderKey(extras[round].proposal, extras[round].suffix),
      )) {
        existingSkipped++;
        skippedExtras++;
        continue;
      }
      final channel = materialize(extras[round]);
      if (channel == null) {
        numberLimitExcluded++;
        continue;
      }
      output.add(channel);
      allocatedChannelsByStrategy.update(
        extras[round].proposal.strategy,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      allocatedExtras++;
      if (output.length == maximumChannels) break;
    }
  }
  final excludedOriginals =
      eligibleOriginals.length - selectedOriginals.length - skippedOriginals;
  final excludedExtras = eligibleExtras - allocatedExtras - skippedExtras;
  final plannedBuilderKeys = output
      .map((channel) => channel.builderKey)
      .whereType<String>()
      .toSet();
  final unmatchedGenerated = mode == ChannelBuildMode.merge
      ? existing
            .where(
              (channel) =>
                  channel.builderKey != null &&
                  !plannedBuilderKeys.contains(channel.builderKey),
            )
            .toList()
      : const <Channel>[];
  final retained = switch (mode) {
    ChannelBuildMode.replace => existing.where(
      (channel) => channel.builderKey == null,
    ),
    ChannelBuildMode.append => existing,
    ChannelBuildMode.merge => existing.where(
      (channel) => !plannedBuilderKeys.contains(channel.builderKey),
    ),
  };
  final named = _nameNewChannels(output, retained, existing, mode);
  final ordered = switch ((order, reorderExisting)) {
    (ChannelOrder.grouped, _) when mode != ChannelBuildMode.merge =>
      _numberChannelsByOrder(named, retained, proposalByKey, strategyOrder),
    (ChannelOrder.mixed, true) when mode != ChannelBuildMode.merge =>
      _numberChannelsByOrder(named, retained, proposalByKey, null),
    _ => named,
  };
  return (
    channels: List.unmodifiable(ordered),
    allocatedOriginals: selectedOriginals.length,
    excludedOriginals: excludedOriginals,
    allocatedExtras: allocatedExtras,
    excludedExtras: excludedExtras,
    numberLimitExcluded: numberLimitExcluded,
    existingSkipped: existingSkipped,
    unmatchedGenerated: List.unmodifiable(unmatchedGenerated),
    eligibleOriginalsByStrategy: Map.unmodifiable({
      for (final strategy in BuilderStrategy.values)
        strategy: eligibleOriginals
            .where((entry) => entry.proposal.strategy == strategy)
            .length,
    }),
    allocatedOriginalsByStrategy: Map.unmodifiable({
      for (final strategy in BuilderStrategy.values)
        strategy: allocatedOriginalsByStrategy[strategy] ?? 0,
    }),
    allocatedChannelsByStrategy: Map.unmodifiable({
      for (final strategy in BuilderStrategy.values)
        strategy: allocatedChannelsByStrategy[strategy] ?? 0,
    }),
    truncated: excludedOriginals > 0 || excludedExtras > 0,
  );
}

List<
  ({ChannelProposal proposal, String suffix, PlaybackMode mode, int? blockSize})
>
_extraVersions(
  ({ChannelProposal proposal, String suffix, PlaybackMode mode, int? blockSize})
  original, {
  required int alternateCopies,
  required PlaybackMode? variantMode,
  required int variantBlockSize,
}) {
  final proposal = original.proposal;
  final replicable =
      (proposal.series || _containsShows(proposal.source)) &&
      !{
        BuilderStrategy.actors,
        BuilderStrategy.directors,
      }.contains(proposal.strategy);
  if (!replicable) return const [];
  final extras =
      <
        ({
          ChannelProposal proposal,
          String suffix,
          PlaybackMode mode,
          int? blockSize,
        })
      >[];
  if (variantMode != null) {
    final blockSize = variantMode == PlaybackMode.block
        ? variantBlockSize
        : null;
    final duplicate =
        variantMode == original.mode &&
        (variantMode != PlaybackMode.block || blockSize == original.blockSize);
    if (!duplicate) {
      extras.add((
        proposal: proposal,
        suffix: ' ${variantMode.name}',
        mode: variantMode,
        blockSize: blockSize,
      ));
    }
  }
  if (original.mode != PlaybackMode.sequential) {
    for (var copy = 1; copy <= alternateCopies; copy++) {
      extras.add((
        proposal: proposal,
        suffix: ' Alt $copy',
        mode: original.mode,
        blockSize: original.blockSize,
      ));
    }
  }
  return extras;
}

List<Channel> _nameNewChannels(
  List<Channel> channels,
  Iterable<Channel> retained,
  List<Channel> existing,
  ChannelBuildMode mode,
) {
  final savedIds = mode == ChannelBuildMode.merge
      ? existing.map((channel) => channel.id).toSet()
      : const <String>{};
  final fixed = [
    ...retained,
    ...channels.where((c) => savedIds.contains(c.id)),
  ];
  final fresh = channels.where((c) => !savedIds.contains(c.id));
  final origins = <String, Set<String>>{};
  final claimed = <String, Set<String?>>{};
  for (final channel in fixed) {
    (claimed[channel.name] ??= {}).add(channel.libraryTitle);
  }
  for (final channel in [
    ...fixed.where((c) => c.builderKey != null),
    ...fresh,
  ]) {
    if (channel.libraryTitle case final library?) {
      (origins[channel.name] ??= {}).add(library);
    }
  }
  final requested = {...claimed.keys, ...channels.map((c) => c.name)};
  final result = <Channel>[];
  for (final channel in channels) {
    if (savedIds.contains(channel.id)) {
      result.add(channel);
      continue;
    }
    final peers = claimed[channel.name] ??= {};
    final library = channel.libraryTitle;
    final shared = (origins[channel.name]?.length ?? 0) > 1;
    if (shared ? library != null && !peers.contains(library) : peers.isEmpty) {
      peers.add(library);
      result.add(channel);
      continue;
    }
    var twin = 2;
    var name = '${channel.name} $twin';
    while (!requested.add(name)) {
      name = '${channel.name} ${++twin}';
    }
    result.add(channel.copyWith(name: name));
  }
  return result;
}

List<Channel> _numberChannelsByOrder(
  List<Channel> planned,
  Iterable<Channel> retained,
  Map<String, ChannelProposal> proposalByKey,
  List<BuilderStrategy>? strategyOrder,
) {
  var ordered = planned;
  if (strategyOrder != null) {
    final priority = {
      for (final (index, strategy) in strategyOrder.indexed) strategy: index,
    };
    final rows = planned.indexed.toList()
      ..sort((left, right) {
        final a = proposalByKey[left.$2.builderKey]!;
        final b = proposalByKey[right.$2.builderKey]!;
        final type = (priority[a.strategy] ?? priority.length).compareTo(
          priority[b.strategy] ?? priority.length,
        );
        if (type != 0) return type;
        final count = b.itemCount.compareTo(a.itemCount);
        return count != 0 ? count : left.$1.compareTo(right.$1);
      });
    ordered = rows.map((row) => row.$2).toList();
  }
  final reserved = retained.map((channel) => channel.number).toSet();
  var next = 1;
  return [
    for (final channel in ordered)
      () {
        while (reserved.contains(next)) {
          next++;
        }
        final number = next++;
        return number == channel.number
            ? channel
            : channel.copyWith(number: number);
      }(),
  ];
}

/// Orders the surviving generated roster after Review has applied its removal
/// choices. A source with no current inventory sorts after populated peers.
List<Channel> orderSurvivingChannels({
  required List<Channel> channels,
  required ChannelOrder order,
  required List<BuilderStrategy> strategyOrder,
  required Map<String, int> sourceCounts,
}) {
  final generated = <BuilderStrategy?, List<Channel>>{};
  final custom = <Channel>[];
  for (final channel in channels) {
    if (channel.builderKey == null) {
      custom.add(channel);
    } else {
      (generated[channelSourceType(channel)] ??= []).add(channel);
    }
  }
  final groups = [
    for (final type in [...strategyOrder, null]) ?generated[type],
  ];
  for (final rows in groups) {
    rows.sort((a, b) {
      int count(Channel row) =>
          sourceCounts[canonicalSourceIdentity(row.source)] ?? 0;
      final compared = count(b).compareTo(count(a));
      return compared != 0 ? compared : a.number.compareTo(b.number);
    });
  }
  final ordered = order == ChannelOrder.grouped
      ? groups.expand((rows) => rows)
      : [
          for (var i = 0; groups.any((rows) => i < rows.length); i++)
            for (final rows in groups)
              if (i < rows.length) rows[i],
        ];
  final reserved = custom.map((c) => c.number).toSet();
  var number = 1;
  final result = [...custom];
  for (final channel in ordered) {
    while (reserved.contains(number)) {
      number++;
    }
    result.add(
      channel.number == number ? channel : channel.copyWith(number: number),
    );
    number++;
  }
  return List.unmodifiable(
    result..sort((a, b) => a.number.compareTo(b.number)),
  );
}

List<Channel> composeChannelPlan({
  required List<Channel> existing,
  required List<Channel> planned,
  required ChannelBuildMode mode,
}) {
  final channels = switch (mode) {
    ChannelBuildMode.replace => [
      ...existing.where((channel) => channel.builderKey == null),
      ...planned,
    ],
    ChannelBuildMode.append => [...existing, ...planned],
    ChannelBuildMode.merge => [
      ...existing.where(
        (channel) =>
            channel.builderKey == null ||
            !planned.any(
              (candidate) => candidate.builderKey == channel.builderKey,
            ),
      ),
      ...planned,
    ],
  }..sort((a, b) => a.number.compareTo(b.number));
  return List.unmodifiable(channels);
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
