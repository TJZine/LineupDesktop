import '../channels/channel.dart';
import '../channels/channel_builder.dart';
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
  final _disabledProposals = <BuilderStrategy, List<ChannelProposal>>{};
  Set<BuilderStrategy>? _enabled;
  List<ChannelProposal> _proposals = const [];
  List<Channel>? _existing;
  ChannelSetupAllocationOptions? _options;
  ChannelPlanAllocation? _allocation;
  final _disabledEligibility = <BuilderStrategy, int>{};

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
      _disabledProposals.clear();
      _enabled = null;
    }
    if (_enabled == null || !_sameSet(_enabled!, strategies)) {
      _enabled = Set.of(strategies);
      _proposals = _build(strategies, strategyOrder: _order);
      _allocation = null;
      _disabledEligibility.clear();
    }
    return _proposals;
  }

  ChannelPlanAllocation configure({
    required List<Channel> existing,
    required ChannelSetupAllocationOptions options,
  }) {
    if (_allocation == null ||
        !identical(_existing, existing) ||
        _options != options) {
      _existing = existing;
      _options = options;
      _allocation = allocate(_proposals, existing: existing, options: options);
      _disabledEligibility.clear();
    }
    return _allocation!;
  }

  int disabledEligibility(BuilderStrategy strategy) =>
      _disabledEligibility.putIfAbsent(
        strategy,
        () =>
            allocate(
              _disabledProposals.putIfAbsent(
                strategy,
                () => _build({strategy}),
              ),
              existing: _existing!,
              options: _options!,
            ).eligibleOriginalsByStrategy[strategy] ??
            0,
      );

  List<ChannelProposal> _build(
    Set<BuilderStrategy> strategies, {
    List<BuilderStrategy> strategyOrder = BuilderStrategy.values,
  }) => buildChannelProposals(
    libraries: _sourceLibraries,
    items: _items!,
    playlists: _playlists!,
    strategies: strategies,
    strategyOrder: strategyOrder,
    crossLibraryStrategies: _grouped,
    minimumItems: _minimum!,
    maximumChannels: null,
  );

  static ChannelPlanAllocation allocate(
    List<ChannelProposal> proposals, {
    required List<Channel> existing,
    required ChannelSetupAllocationOptions options,
    DateTime? anchor,
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
    anchor: anchor ?? DateTime.now().toUtc(),
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
