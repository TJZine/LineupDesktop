part of 'lineup_controller.dart';

typedef _LibraryScanResult = ({
  Set<String> failedPlaylistIds,
  Map<String, Set<String>> failedCollectionTitles,
  Map<String, PlexCollectionFailure> collectionDiscoveryFailures,
  List<PlexMediaItem> media,
  List<PlexPlaylist> playlists,
  LibraryScanStatus status,
});

enum LibraryScanStatus {
  idle,
  scanning,
  complete,
  empty,
  unsupported,
  transientFailure,
  cancelled,
}

@immutable
class LibraryScanFact {
  const LibraryScanFact({
    required this.status,
    this.phase = PlexLibraryScanPhase.items,
    this.completedPages = 0,
    this.completedItems = 0,
    this.totalItems,
  });

  final LibraryScanStatus status;
  final PlexLibraryScanPhase phase;
  final int completedPages;
  final int completedItems;
  final int? totalItems;
}

class _LibraryScanRow {
  const _LibraryScanRow({
    required this.fact,
    this.items,
    this.failedTitles = const {},
    this.discoveryFailure,
  });

  final LibraryScanFact fact;
  final List<PlexMediaItem>? items;
  final Set<String> failedTitles;
  final PlexCollectionFailure? discoveryFailure;

  bool get needsRetry =>
      const {
        LibraryScanStatus.transientFailure,
        LibraryScanStatus.cancelled,
        LibraryScanStatus.idle,
      }.contains(fact.status) ||
      discoveryFailure != null ||
      failedTitles.isNotEmpty;

  _LibraryScanRow withFact(LibraryScanFact value) => _LibraryScanRow(
    fact: value,
    items: items,
    failedTitles: failedTitles,
    discoveryFailure: discoveryFailure,
  );
}

class _ScanReadiness {
  const _ScanReadiness({
    required this.contentScope,
    required this.scope,
    required this.rows,
    required this.result,
    required this.catalogUnavailable,
  });

  final int contentScope;
  final ({String? profileId, String serverId})? scope;
  final Map<String, _LibraryScanRow> rows;
  final _LibraryScanResult result;
  final bool catalogUnavailable;
}

@immutable
class _ScanCommitCandidate {
  const _ScanCommitCandidate({
    required this.readiness,
    required this.libraryIds,
    required this.media,
    required this.playlists,
    required this.evidence,
    required this.status,
  });

  final _ScanReadiness readiness;
  final Set<String> libraryIds;
  final List<PlexMediaItem> media;
  final List<PlexPlaylist> playlists;
  final _LibraryScanResult evidence;
  final LibraryScanStatus status;
}

class _ScanAttempt {
  const _ScanAttempt({required this.previous, required this.retry});

  final _ScanReadiness? previous;
  final bool retry;
}

class _LibraryScanState {
  LibraryScanStatus status = LibraryScanStatus.idle;
  Map<String, _LibraryScanRow> rows = const {};
  ({String? profileId, String serverId})? scope;
  int? _rowContentScope;
  _ScanReadiness? _ready;
  _ScanAttempt? _attempt;
  Map<String, _LibraryScanRow> _retryBaseline = const {};
  Completer<void>? _cancelled;
  Object? failure;
  bool discoveryObsolete = false;
  bool catalogUnavailable = true;
  Set<String> failedPlaylistIds = const {};
  PlexPlaylistProgress? playlistProgress;

  Set<String> get ids => Set.unmodifiable(rows.keys);
  _LibraryScanResult? get readiness => _ready?.result;
  int? get readinessScope => _ready?.contentScope;
  Map<String, LibraryScanFact> get facts => Map.unmodifiable({
    for (final entry in rows.entries) entry.key: entry.value.fact,
  });
  Map<String, Set<String>> get failedCollectionTitles => Map.unmodifiable({
    for (final entry in rows.entries)
      if (entry.value.items != null) entry.key: entry.value.failedTitles,
  });
  Map<String, PlexCollectionFailure> get collectionDiscoveryFailures =>
      Map.unmodifiable({
        for (final entry in rows.entries)
          entry.key: ?entry.value.discoveryFailure,
      });
  Set<String> get retryIds => Set.unmodifiable(
    rows.entries
        .where((entry) => entry.value.needsRetry)
        .map((entry) => entry.key),
  );
  Set<String> readyIds(int contentScope) => _ready?.contentScope != contentScope
      ? const {}
      : Set.unmodifiable(
          rows.entries
              .where(
                (entry) =>
                    entry.value.fact.status == LibraryScanStatus.complete,
              )
              .map((entry) => entry.key),
        );

  LibraryScanStatus get currentStatus => status;

  void restoreStatus(LibraryScanStatus value) => status = value;

  List<PlexMediaItem> inventoryFor(Iterable<String> inventoryOrder) => [
    for (final id in inventoryOrder) ...?rows[id]?.items,
  ];

  _ScanCommitCandidate? candidateFor(
    Set<String> ids,
    int contentScope,
    Iterable<String> inventoryOrder,
  ) {
    final ready = _ready;
    if (ready == null ||
        ready.contentScope != contentScope ||
        ids.isEmpty ||
        !ids.every(
          (id) => ready.rows[id]?.fact.status == LibraryScanStatus.complete,
        )) {
      return null;
    }
    return _ScanCommitCandidate(
      readiness: ready,
      libraryIds: Set.unmodifiable(ids),
      media: List.unmodifiable([
        for (final id in inventoryOrder)
          if (ids.contains(id))
            ...?ready.rows[id]?.items?.where((item) => item.isPlayable),
      ]),
      playlists: ready.result.playlists,
      evidence: ready.result,
      status: LibraryScanStatus.complete,
    );
  }

  bool isCurrent(_ScanCommitCandidate candidate, int contentScope) =>
      candidate.readiness.contentScope == contentScope &&
      identical(_ready, candidate.readiness);

  void didCommit(_ScanCommitCandidate candidate) => status = candidate.status;

  int get completedPages =>
      rows.values.fold(0, (total, row) => total + row.fact.completedPages);
  int get completedItems =>
      rows.values.fold(0, (total, row) => total + row.fact.completedItems);
  int? get totalItems {
    if (rows.isEmpty || rows.values.any((row) => row.fact.totalItems == null)) {
      return null;
    }
    return rows.values.fold<int>(
      0,
      (total, row) => total + row.fact.totalItems!,
    );
  }

  PlexLibraryScanPhase get phase {
    final active = rows.values.where(
      (row) => const {
        LibraryScanStatus.scanning,
        LibraryScanStatus.idle,
      }.contains(row.fact.status),
    );
    if (active.isEmpty) {
      return rows.isEmpty
          ? PlexLibraryScanPhase.items
          : rows.values.last.fact.phase;
    }
    if (active.any((row) => row.fact.phase == PlexLibraryScanPhase.items)) {
      return PlexLibraryScanPhase.items;
    }
    return active.first.fact.phase;
  }

  void installScenario(
    Map<String, LibraryScanFact> facts,
    LibraryScanStatus value,
    int contentScope,
    String? profileId,
    String? serverId,
  ) {
    rows = Map.unmodifiable({
      for (final entry in facts.entries)
        entry.key: _LibraryScanRow(fact: entry.value),
    });
    scope = serverId == null
        ? null
        : (profileId: profileId, serverId: serverId);
    _rowContentScope = contentScope;
    status = value;
  }

  void beginRefresh({required bool retry}) {
    _attempt = _ScanAttempt(previous: _ready, retry: retry);
    _ready = null;
    failure = null;
  }

  Set<String> prepare(
    Set<String> selectedIds,
    ({String? profileId, String serverId}) selectedScope,
    int contentScope, {
    required bool retryFailedOnly,
    required Set<String>? retryLibraryIds,
  }) {
    final retain =
        (retryFailedOnly || retryLibraryIds != null) &&
        _rowContentScope == contentScope &&
        scope == selectedScope &&
        setEquals(ids, selectedIds);
    _retryBaseline = retain ? rows : const {};
    final retainedIds = <String>{
      for (final id in selectedIds)
        if (retain &&
            (retryLibraryIds != null
                ? !retryLibraryIds.contains(id)
                : rows[id]!.items != null && !rows[id]!.needsRetry))
          id,
    };
    rows = Map.unmodifiable({
      for (final id in selectedIds)
        id: retainedIds.contains(id)
            ? rows[id]!
            : (_retryBaseline[id] ??
                      const _LibraryScanRow(
                        fact: LibraryScanFact(status: LibraryScanStatus.idle),
                      ))
                  .withFact(
                    const LibraryScanFact(status: LibraryScanStatus.idle),
                  ),
    });
    scope = selectedScope;
    _rowContentScope = contentScope;
    discoveryObsolete = false;
    catalogUnavailable = true;
    failedPlaylistIds = const {};
    status = LibraryScanStatus.scanning;
    return retainedIds;
  }

  void _setFact(String id, LibraryScanFact fact) {
    rows = Map.unmodifiable({...rows, id: rows[id]!.withFact(fact)});
  }

  void startLibrary(String id) =>
      _setFact(id, const LibraryScanFact(status: LibraryScanStatus.scanning));

  void setPhase(String id, PlexLibraryScanPhase phase) {
    final current = rows[id]!.fact;
    _setFact(
      id,
      LibraryScanFact(
        status: LibraryScanStatus.scanning,
        phase: phase,
        completedPages: current.completedPages,
        completedItems: current.completedItems,
        totalItems: current.totalItems,
      ),
    );
  }

  void reportProgress(String id, PlexLibraryPageProgress progress) {
    final current = rows[id]!.fact;
    _setFact(
      id,
      LibraryScanFact(
        status: LibraryScanStatus.scanning,
        phase: current.phase,
        completedPages: progress.completedPages > current.completedPages
            ? progress.completedPages
            : current.completedPages,
        completedItems: progress.completedItems > current.completedItems
            ? progress.completedItems
            : current.completedItems,
        totalItems:
            progress.totalItems != null &&
                (current.totalItems == null ||
                    progress.totalItems! > current.totalItems!)
            ? progress.totalItems
            : current.totalItems,
      ),
    );
  }

  void completeLibrary(String id, PlexLibraryScan scan) {
    final current = rows[id]!.fact;
    final items = scan.items;
    final fact = LibraryScanFact(
      status: items.isEmpty
          ? LibraryScanStatus.empty
          : items.any((item) => item.isPlayable)
          ? LibraryScanStatus.complete
          : LibraryScanStatus.unsupported,
      phase: current.phase,
      completedPages: current.completedPages,
      completedItems: items.length > current.completedItems
          ? items.length
          : current.completedItems,
      totalItems: current.totalItems,
    );
    rows = Map.unmodifiable({
      ...rows,
      id: _LibraryScanRow(
        fact: fact,
        items: List.unmodifiable(items.map((item) => item.immutableCopy())),
        failedTitles: Set.unmodifiable(scan.collections.failedTitles),
        discoveryFailure: scan.collections.failure,
      ),
    });
  }

  void failLibrary(String id) {
    final retained = _retryBaseline[id];
    if (retained?.items != null) {
      discoveryObsolete = true;
      rows = Map.unmodifiable({...rows, id: retained!});
      return;
    }
    final current = rows[id]!.fact;
    _setFact(
      id,
      LibraryScanFact(
        status: LibraryScanStatus.transientFailure,
        phase: current.phase,
        completedPages: current.completedPages,
        completedItems: current.completedItems,
        totalItems: current.totalItems,
      ),
    );
  }

  void completeCatalog(
    PlexPlaylistCatalog catalog, {
    required bool unavailable,
  }) {
    catalogUnavailable = unavailable;
    failedPlaylistIds = Set.unmodifiable(catalog.failedIds);
  }

  _LibraryScanResult result(
    List<PlexMediaItem> media,
    List<PlexPlaylist> playlists,
  ) => (
    failedCollectionTitles: Map.unmodifiable({
      for (final entry in rows.entries)
        if (entry.value.failedTitles.isNotEmpty)
          entry.key: entry.value.failedTitles,
    }),
    collectionDiscoveryFailures: collectionDiscoveryFailures,
    failedPlaylistIds: failedPlaylistIds,
    media: List.unmodifiable(media.map((item) => item.immutableCopy())),
    playlists: List.unmodifiable(
      playlists.map((playlist) => playlist.immutableCopy()),
    ),
    status:
        rows.values.any(
          (row) => const {
            LibraryScanStatus.transientFailure,
            LibraryScanStatus.cancelled,
            LibraryScanStatus.idle,
          }.contains(row.fact.status),
        )
        ? LibraryScanStatus.transientFailure
        : media.isNotEmpty
        ? LibraryScanStatus.complete
        : rows.values.any((row) => row.items?.isNotEmpty ?? false)
        ? LibraryScanStatus.unsupported
        : LibraryScanStatus.empty,
  );

  void stage(_LibraryScanResult result, int contentScope) {
    _ready = _ScanReadiness(
      contentScope: contentScope,
      scope: scope,
      rows: rows,
      result: result,
      catalogUnavailable: catalogUnavailable,
    );
    status = result.status;
  }

  void _retainPrevious(int contentScope) {
    final previous = _attempt?.previous;
    if (previous == null ||
        previous.contentScope != contentScope ||
        !previous.rows.values.any(
          (row) => row.fact.status == LibraryScanStatus.complete,
        )) {
      return;
    }
    _ready = previous;
    rows = previous.rows;
    scope = previous.scope;
    _rowContentScope = previous.contentScope;
    catalogUnavailable = previous.catalogUnavailable;
    failedPlaylistIds = previous.result.failedPlaylistIds;
    status = previous.result.status;
    discoveryObsolete = true;
  }

  void finishRefresh(int contentScope, {required bool failed}) {
    if (failed && _attempt?.retry == false) _retainPrevious(contentScope);
    _attempt = null;
    _retryBaseline = const {};
  }

  void interruptRefresh(int contentScope) {
    _retainPrevious(contentScope);
    _attempt = null;
    _retryBaseline = const {};
  }

  void cancel(int contentScope) {
    status = LibraryScanStatus.cancelled;
    rows = Map.unmodifiable({
      for (final entry in rows.entries)
        entry.key: entry.value.fact.status == LibraryScanStatus.scanning
            ? entry.value.withFact(
                LibraryScanFact(
                  status: LibraryScanStatus.cancelled,
                  phase: entry.value.fact.phase,
                  completedPages: entry.value.fact.completedPages,
                  completedItems: entry.value.fact.completedItems,
                  totalItems: entry.value.fact.totalItems,
                ),
              )
            : entry.value,
    });
    interruptRefresh(contentScope);
  }

  Completer<void> startIo() => _cancelled = Completer<void>();
  void cancelIo() {
    final cancelled = _cancelled;
    _cancelled = null;
    playlistProgress = null;
    if (cancelled != null && !cancelled.isCompleted) cancelled.complete();
  }

  void finishIo(Completer<void> cancelled) {
    if (!cancelled.isCompleted) cancelled.complete();
    if (identical(_cancelled, cancelled)) {
      _cancelled = null;
      playlistProgress = null;
    }
  }

  void reset() {
    cancelIo();
    rows = const {};
    scope = null;
    _rowContentScope = null;
    _ready = null;
    _attempt = null;
    _retryBaseline = const {};
    failure = null;
    discoveryObsolete = false;
    catalogUnavailable = true;
    failedPlaylistIds = const {};
    status = LibraryScanStatus.idle;
  }
}
