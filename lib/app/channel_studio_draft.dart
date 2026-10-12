import '../channels/channel.dart';
import '../plex/plex_models.dart';

enum StudioSourceChoice { library, playlist, filter, handPicked }

/// The editable programming and schedule identity of one Studio session.
/// Text controllers, inventory discovery and pending picker choices belong to
/// the view; persistence and conflict detection belong to the controller.
class ChannelStudioDraft {
  ChannelStudioDraft({
    required this.id,
    required this.source,
    required this.duplicate,
    required this.generated,
    this.expectedBase,
    Channel? original,
  }) : originalMode = original?.playbackMode,
       playbackMode = original?.playbackMode ?? PlaybackMode.shuffle,
       anchor =
           original?.anchor ??
           DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
       shuffleSeed = original?.shuffleSeed ?? 0,
       blockSize = original?.blockSize,
       includeSpecials = original?.includeSpecials ?? false,
       builderKey = generated ? original?.builderKey : null,
       scheduleIdentityCommitted = original != null;

  final bool duplicate;
  final PlaybackMode? originalMode;
  String id;
  ContentSource source;
  PlaybackMode playbackMode;
  DateTime anchor;
  int shuffleSeed;
  int? blockSize;
  bool includeSpecials;
  String? builderKey;
  Channel? expectedBase;
  bool generated;
  bool sourceReadOnly = false;
  StudioSourceChoice? sourceChoice;
  bool filterIncludeWatched = true;
  String? playlistId;
  String? filterLibraryId;
  final filters = <LibraryFilter, List<String>>{};

  void configureSource({String? defaultPlaylistId, String? defaultLibraryId}) {
    sourceReadOnly = generated;
    sourceChoice = switch (source) {
      LibrarySource() => StudioSourceChoice.library,
      PlaylistSource() => StudioSourceChoice.playlist,
      ManualSource() => StudioSourceChoice.handPicked,
      MixedSource() => null,
    };
    filterIncludeWatched = switch (source) {
      LibrarySource(:final includeWatched) => includeWatched,
      _ => true,
    };
    playlistId = switch (source) {
      PlaylistSource(:final playlistId) => playlistId,
      _ => defaultPlaylistId,
    };
    filterLibraryId = switch (source) {
      LibrarySource(:final libraryId) => libraryId,
      _ => defaultLibraryId,
    };
    filters
      ..clear()
      ..addAll(switch (source) {
        LibrarySource(:final filters) => filters,
        _ => const {},
      });
  }

  DateTime? _candidateAnchor;
  int? _candidateSeed;
  bool scheduleIdentityCommitted;
  late Map<String, Object?> _baseline;
  bool dirty = false;

  int? get effectiveBlockSize =>
      playbackMode == PlaybackMode.block ? (blockSize ?? 3) : null;
  bool get effectiveIncludeSpecials =>
      playbackMode == PlaybackMode.block && includeSpecials;
  int? get _projectedBlockSize =>
      generated || duplicate ? blockSize : effectiveBlockSize;

  LibraryOrder _libraryOrder(
    String? libraryId, {
    required bool includeWatched,
    required Map<LibraryFilter, List<String>> filters,
    PlexLibraryType? libraryType,
  }) {
    final original = source;
    final changedOrder = playbackMode == PlaybackMode.sequential
        ? LibraryOrder.title
        : LibraryOrder.supplied;
    if (original is! LibrarySource || libraryId == null) return changedOrder;
    if (libraryType == null) return original.order;
    final candidate = LibrarySource(
      libraryId: libraryId,
      libraryType: libraryType,
      includeWatched: includeWatched,
      filters: filters,
      order: original.order,
    );
    if (canonicalSourceEquals(original, candidate) &&
        (original.order == LibraryOrder.addedDescending ||
            (expectedBase?.playbackMode ?? originalMode) == playbackMode)) {
      return original.order;
    }
    return changedOrder;
  }

  ContentSource editedSource({
    required List<PlexLibrary> libraries,
    required List<ChannelItem> manualItems,
  }) {
    if (sourceReadOnly) return source;
    switch (sourceChoice) {
      case StudioSourceChoice.library || StudioSourceChoice.filter:
        final library = libraries
            .where((library) => library.id == filterLibraryId)
            .firstOrNull;
        if (library == null) throw const FormatException('Select a library.');
        return LibrarySource(
          libraryId: library.id,
          libraryType: library.type,
          includeWatched: filterIncludeWatched,
          filters: Map.unmodifiable(filters),
          order: _libraryOrder(
            library.id,
            libraryType: library.type,
            includeWatched: filterIncludeWatched,
            filters: filters,
          ),
        );
      case StudioSourceChoice.playlist:
        if (playlistId == null) {
          throw const FormatException('Select a playlist.');
        }
        return PlaylistSource(playlistId!);
      case StudioSourceChoice.handPicked:
        return ManualSource(manualItems);
      case null:
        return source;
    }
  }

  Map<String, Object?> signature({
    required String name,
    required String number,
    required List<PlexLibrary> libraries,
    required List<ChannelItem> manualItems,
  }) => {
    'name': name.trim(),
    // Invalid raw edits remain distinct even though preview needs a safe number.
    'number': int.tryParse(number) ?? number.trim(),
    'source': _sourceIdentity(libraries, manualItems),
    'playbackMode': playbackMode.name,
    'anchor': anchor.toIso8601String(),
    'shuffleSeed': shuffleSeed,
    'blockSize': _projectedBlockSize,
    'includeSpecials': effectiveIncludeSpecials,
    'builderKey': builderKey,
  };

  Object _sourceIdentity(List<PlexLibrary> libraries, List<ChannelItem> items) {
    switch (sourceChoice) {
      case StudioSourceChoice.library || StudioSourceChoice.filter:
        return {
          'type': sourceChoice == StudioSourceChoice.library
              ? 'library'
              : 'filter',
          'libraryId': filterLibraryId,
          'includeWatched': filterIncludeWatched,
          'filters': {
            for (final entry in filters.entries)
              entry.key.name: [...entry.value]..sort(),
          },
          'order': _libraryOrder(
            filterLibraryId,
            libraryType: libraries
                .where((library) => library.id == filterLibraryId)
                .firstOrNull
                ?.type,
            includeWatched: filterIncludeWatched,
            filters: filters,
          ).name,
        };
      case StudioSourceChoice.playlist:
        return {'type': 'playlist', 'playlistId': playlistId};
      case StudioSourceChoice.handPicked:
        final counts = <String, int>{};
        for (final item in items) {
          counts.update(item.id, (count) => count + 1, ifAbsent: () => 1);
        }
        return {
          'type': 'manual',
          'items': [
            for (final item in items)
              counts[item.id] == 1
                  ? item.id
                  : {'id': item.id, 'snapshot': item.toJson()},
          ],
        };
      case null:
        return source.toJson();
    }
  }

  void acceptBaseline(Map<String, Object?> signature) {
    _baseline = signature;
    dirty = false;
  }

  void updateDirty(Map<String, Object?> signature) {
    dirty = !canonicalChannelValueEquals(signature, _baseline);
  }

  /// Projection is side-effect free. Preview uses staged timing and safe text
  /// placeholders; saving requires validated text and committed timing.
  Channel project({
    required String name,
    required String number,
    required ContentSource programming,
    required bool preview,
  }) {
    final retainsSchedule = _retainsSchedule(programming);
    return Channel(
      id: id,
      number: preview ? (int.tryParse(number) ?? 1) : int.parse(number),
      name: preview && name.trim().isEmpty ? 'New channel' : name.trim(),
      source: programming,
      playbackMode: playbackMode,
      anchor: preview ? (_candidateAnchor ?? anchor) : anchor,
      shuffleSeed: preview ? (_candidateSeed ?? shuffleSeed) : shuffleSeed,
      blockSize: _projectedBlockSize,
      builderKey: builderKey,
      includeSpecials: effectiveIncludeSpecials,
      scheduleVersion: retainsSchedule
          ? expectedBase!.scheduleVersion
          : currentScheduleVersion,
      scheduleTransition: retainsSchedule
          ? expectedBase!.scheduleTransition
          : null,
    );
  }

  /// Duplicating an inspected recipe preserves raw generator values, including
  /// fields that are inactive in its current playback mode.
  Channel duplicateRecipe({
    required String name,
    required String number,
    required Channel template,
  }) => Channel(
    id: id,
    number: int.tryParse(number) ?? template.number,
    name: name.trim(),
    source: source,
    playbackMode: playbackMode,
    anchor: anchor,
    shuffleSeed: shuffleSeed,
    blockSize: blockSize,
    builderKey: builderKey,
    includeSpecials: includeSpecials,
    scheduleVersion: template.scheduleVersion,
    scheduleTransition: template.scheduleTransition,
  );

  bool _retainsSchedule(ContentSource programming) {
    final base = expectedBase;
    return base != null &&
        canonicalSourceEquals(base.source, programming) &&
        base.playbackMode == playbackMode &&
        (playbackMode != PlaybackMode.block ||
            (base.blockSize ?? 3) == effectiveBlockSize) &&
        base.includeSpecials == effectiveIncludeSpecials;
  }

  void stageScheduleIdentity(DateTime Function() clock, {required bool valid}) {
    if (scheduleIdentityCommitted || !valid || _candidateAnchor != null) return;
    _candidateAnchor = clock().toUtc();
    _candidateSeed = stableChannelSeed(id);
  }

  void commitScheduleIdentity(Map<String, Object?> signature) {
    if (scheduleIdentityCommitted) return;
    final candidate = _candidateAnchor;
    final seed = _candidateSeed;
    if (candidate == null || seed == null) return;
    anchor = candidate;
    shuffleSeed = seed;
    _candidateAnchor = null;
    _candidateSeed = null;
    scheduleIdentityCommitted = true;
    _baseline = {
      ..._baseline,
      'anchor': anchor.toIso8601String(),
      'shuffleSeed': shuffleSeed,
    };
    updateDirty({
      ...signature,
      'anchor': anchor.toIso8601String(),
      'shuffleSeed': shuffleSeed,
    });
  }

  void loadSaved(Channel channel) {
    source = channel.source;
    playbackMode = channel.playbackMode;
    anchor = channel.anchor;
    shuffleSeed = channel.shuffleSeed;
    blockSize = channel.blockSize;
    includeSpecials = channel.includeSpecials;
    builderKey = channel.builderKey;
    expectedBase = channel;
    generated = channel.builderKey != null;
    scheduleIdentityCommitted = true;
    _candidateAnchor = null;
    _candidateSeed = null;
  }

  void prepareSaveAsNew(String newId) {
    id = newId;
    expectedBase = null;
    builderKey = null;
    generated = false;
    sourceReadOnly = false;
    scheduleIdentityCommitted = false;
    _candidateAnchor = null;
    _candidateSeed = null;
    dirty = true;
  }
}
