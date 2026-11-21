import '../channels/channel.dart';
import '../channels/channel_builder.dart';
import '../channels/content_resolver.dart';
import '../plex/plex_models.dart';

typedef ChannelSetupAllocationOptions = ({
  ChannelBuildMode mode,
  PlaybackMode seriesMode,
  int seriesBlockSize,
  int alternateCopies,
  PlaybackMode? variantMode,
  int variantBlockSize,
  bool includeSpecials,
  int minimumItems,
  int maximumChannels,
});

/// Derived data for one setup view. Inventory and lineup lists are immutable
/// controller snapshots; replacing either snapshot invalidates its stage.
/// Configuration allocations are previews only. Review/commit must materialize
/// again with a fresh anchor rather than publish a cached preview schedule.
class ChannelSetupProjection {
  List<PlexLibrary>? _libraries;
  List<PlexMediaItem>? _items;
  List<PlexPlaylist>? _playlists;
  Set<String> _selectedLibraries = const {};
  Set<BuilderStrategy> _grouped = const {};
  List<BuilderStrategy> _order = const [];
  int? _minimum;
  List<PlexLibrary> _sourceLibraries = const [];
  final _sourceProposals = <(BuilderStrategy, bool), List<ChannelProposal>>{};
  Set<BuilderStrategy>? _enabled;
  List<ChannelProposal> _proposals = const [];
  List<Channel>? _existing;
  ChannelSetupAllocationOptions? _options;
  ChannelPlanAllocation? _allocation;
  ChannelOrder? _allocationOrder;
  bool? _reorderExisting;
  final _sourceEligibility = <(BuilderStrategy, bool), int>{};
  List<Channel>? _retainedLineup;
  final _retainedSourceCounts = <String, int>{};

  List<ChannelProposal> proposals({
    required List<PlexLibrary> libraries,
    required List<PlexMediaItem> items,
    required List<PlexPlaylist> playlists,
    required Set<String> selectedLibraries,
    required Set<BuilderStrategy> strategies,
    required List<BuilderStrategy> strategyOrder,
    required Set<BuilderStrategy> crossLibraryStrategies,
    required int minimumItems,
  }) {
    if (!identical(_items, items) || !identical(_playlists, playlists)) {
      _retainedSourceCounts.clear();
    }
    if (!identical(_libraries, libraries) ||
        !identical(_items, items) ||
        !identical(_playlists, playlists) ||
        !_sameSet(_selectedLibraries, selectedLibraries) ||
        !_sameSet(_grouped, crossLibraryStrategies) ||
        !_sameList(_order, strategyOrder) ||
        _minimum != minimumItems) {
      _libraries = libraries;
      _items = items;
      _playlists = playlists;
      _selectedLibraries = Set.of(selectedLibraries);
      _grouped = Set.of(crossLibraryStrategies);
      _order = List.of(strategyOrder);
      _minimum = minimumItems;
      _sourceLibraries = libraries
          .where((library) => selectedLibraries.contains(library.id))
          .toList();
      _sourceProposals.clear();
      _enabled = null;
    }
    if (_enabled == null || !_sameSet(_enabled!, strategies)) {
      _enabled = Set.of(strategies);
      _proposals = _build(strategies, strategyOrder: _order);
      _allocation = null;
      _sourceEligibility.clear();
    }
    return _proposals;
  }

  ChannelPlanAllocation configure({
    required List<Channel> existing,
    required ChannelSetupAllocationOptions options,
    ChannelOrder order = ChannelOrder.mixed,
    bool reorderExisting = false,
  }) {
    if (_allocation == null ||
        _allocationOrder != order ||
        _reorderExisting != reorderExisting ||
        !identical(_existing, existing) ||
        _options != options) {
      _existing = existing;
      _options = options;
      _allocationOrder = order;
      _reorderExisting = reorderExisting;
      _allocation = allocate(
        _proposals,
        existing: existing,
        options: options,
        order: order,
        reorderExisting: reorderExisting,
        strategyOrder: _order,
      );
      _sourceEligibility.clear();
    }
    return _allocation!;
  }

  Map<String, int> reviewSourceCounts(List<Channel> existing) {
    if (!identical(_retainedLineup, existing)) {
      _retainedLineup = existing;
      _retainedSourceCounts.clear();
    }
    final counts = {
      for (final proposal in _proposals)
        canonicalSourceIdentity(proposal.source): proposal.itemCount,
    };
    for (final channel in existing.where(
      (channel) => channel.builderKey != null,
    )) {
      final source = channel.source;
      final key = canonicalSourceIdentity(source);
      counts.putIfAbsent(
        key,
        () => _retainedSourceCounts.putIfAbsent(
          key,
          () => resolveContent(source, _items!, _playlists!).length,
        ),
      );
    }
    return counts;
  }

  int disabledEligibility(BuilderStrategy strategy) =>
      _eligibleOriginals(strategy, _grouped.contains(strategy));

  bool hasEligibleAlternateGrouping(BuilderStrategy strategy) {
    if (!supportsGrouping(strategy) || _sourceLibraries.length < 2) {
      return false;
    }
    final currentEligibility = _enabled!.contains(strategy)
        ? _allocation!.eligibleOriginalsByStrategy[strategy] ?? 0
        : disabledEligibility(strategy);
    return currentEligibility == 0 &&
        _eligibleOriginals(strategy, !_grouped.contains(strategy)) > 0;
  }

  static bool supportsGrouping(BuilderStrategy strategy) => const {
    BuilderStrategy.genres,
    BuilderStrategy.studios,
    BuilderStrategy.actors,
    BuilderStrategy.directors,
  }.contains(strategy);

  int _eligibleOriginals(BuilderStrategy strategy, bool grouped) {
    final key = (strategy, grouped);
    return _sourceEligibility.putIfAbsent(
      key,
      () =>
          allocate(
            _sourceProposals.putIfAbsent(
              key,
              () => _build(
                {strategy},
                crossLibraryStrategies: {if (grouped) strategy},
              ),
            ),
            existing: _existing!,
            options: _options!,
            order: _allocationOrder!,
            reorderExisting: _reorderExisting!,
            strategyOrder: _order,
          ).eligibleOriginalsByStrategy[strategy] ??
          0,
    );
  }

  List<ChannelProposal> _build(
    Set<BuilderStrategy> strategies, {
    List<BuilderStrategy> strategyOrder = BuilderStrategy.values,
    Set<BuilderStrategy>? crossLibraryStrategies,
  }) => buildChannelProposals(
    libraries: _sourceLibraries,
    items: _items!,
    playlists: _playlists!,
    strategies: strategies,
    strategyOrder: strategyOrder,
    crossLibraryStrategies: crossLibraryStrategies ?? _grouped,
    minimumItems: _minimum!,
    maximumChannels: null,
  );

  static ChannelPlanAllocation allocate(
    List<ChannelProposal> proposals, {
    required List<Channel> existing,
    required ChannelSetupAllocationOptions options,
    DateTime? anchor,
    ChannelOrder order = ChannelOrder.mixed,
    List<BuilderStrategy> strategyOrder = BuilderStrategy.values,
    List<PlexMediaItem> items = const [],
    List<PlexPlaylist> playlists = const [],
    bool reorderExisting = false,
    List<Channel> reviewedChannels = const [],
  }) => materializeChannelPlan(
    proposals: proposals,
    existing: existing,
    mode: options.mode,
    seriesMode: options.seriesMode,
    seriesBlockSize: options.seriesBlockSize,
    alternateCopies: options.alternateCopies,
    variantMode: options.variantMode,
    variantBlockSize: options.variantBlockSize,
    includeSpecials: options.includeSpecials,
    minimumItems: options.minimumItems,
    maximumChannels: options.maximumChannels,
    anchor: anchor,
    order: order,
    strategyOrder: strategyOrder,
    reorderExisting: reorderExisting,
    reviewedChannels: reviewedChannels,
    resolve: anchor == null
        ? null
        : (source) => resolveContent(source, items, playlists),
  );
}

bool _sameSet<T>(Set<T> a, Set<T> b) =>
    a.length == b.length && a.containsAll(b);
bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
