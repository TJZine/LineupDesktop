part of '../channel_studio_view.dart';

class _StudioManualEditor extends StatefulWidget {
  const _StudioManualEditor({
    required this.rundown,
    required this.inventory,
    required this.readInventory,
    required this.selectedLibraries,
    required this.libraries,
    required this.picker,
    required this.saving,
    required this.active,
    required this.sourceRevision,
    required this.name,
    required this.inventoryStatus,
    required this.sourceExplanation,
    required this.onChanged,
    required this.onSelectionPendingChanged,
  });
  final ManualRundown rundown;
  final _StudioInventory inventory;
  final _StudioInventory Function() readInventory;
  final List<PlexLibrary> selectedLibraries;
  final List<PlexLibrary> libraries;
  final _FilterPickerController picker;
  final bool saving;
  final bool active;
  final int sourceRevision;
  final String name;
  final Widget inventoryStatus;
  final String? sourceExplanation;
  final VoidCallback onChanged;
  final ValueChanged<bool> onSelectionPendingChanged;
  @override
  State<_StudioManualEditor> createState() => _StudioManualEditorState();
}

class _StudioManualEditorState extends State<_StudioManualEditor>
    with _StudioFilterControls<_StudioManualEditor> {
  static const _countAnnouncementDelay = Duration(milliseconds: 300);
  final _search = TextEditingController();
  final _rundownSearch = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'Search programming');
  final _rundownFocus = <ManualOccurrence, FocusNode>{};
  final _browseScroll = ScrollController();
  final _rundownScroll = ScrollController();
  final _browseSelection = <String>{};
  final _browseSelectionItems = <String, PlexMediaItem>{};
  final _manualFilters = <LibraryFilter, List<String>>{};
  String? _manualLibraryId;
  String? _manualMediaType;
  bool _manualRundown = false;
  bool _browseSelecting = false;
  bool _showBrowseSelected = false;
  Timer? _countAnnouncementTimer;
  String _settledCountLabel = '';
  late _StudioInventory _inventorySnapshot;
  @override
  _StudioInventory get _playableInventory => _inventorySnapshot;
  set _playableInventory(_StudioInventory value) => _inventorySnapshot = value;
  ManualRundown get _rundown => widget.rundown;
  @override
  _FilterPickerController get _picker => widget.picker;
  @override
  List<PlexLibrary> get _selectedLibraries => widget.selectedLibraries;
  @override
  List<PlexLibrary> get _libraries => widget.libraries;
  @override
  bool get _saving => widget.saving;
  @override
  bool get _browse => true;
  @override
  Map<LibraryFilter, List<String>> get _currentFilters => _manualFilters;
  @override
  String? get _currentLibraryId => _manualLibraryId;
  @override
  String? get _currentMediaType => _manualMediaType;
  @override
  String get _currentSearch => _search.text;
  @override
  bool get _includeWatched => true;
  @override
  void _filtersChanged(VoidCallback apply) => _browseChanged(apply);

  @override
  void initState() {
    super.initState();
    _playableInventory = widget.inventory;
    _manualRundown = _rundown.occurrences.isNotEmpty;
  }

  @override
  void didUpdateWidget(_StudioManualEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _playableInventory = widget.inventory;
    if (oldWidget.sourceRevision != widget.sourceRevision) {
      _retireRemovedFocus(_rundownFocus.keys.toList(growable: false));
      _manualRundown = _rundown.occurrences.isNotEmpty;
      _manualLibraryId = null;
      _manualMediaType = null;
      _manualFilters.clear();
    }
    if (oldWidget.active && !widget.active) {
      _clearSelection();
    }
  }

  void _refreshPlayableInventory() {
    _playableInventory = widget.readInventory();
  }

  void _changed([VoidCallback? apply]) {
    setState(() {
      apply?.call();
    });
    widget.onChanged();
  }

  void _browseChanged([VoidCallback? apply]) {
    setState(apply ?? () {});
    _scheduleCountAnnouncement();
  }

  void _scheduleCountAnnouncement() {
    _countAnnouncementTimer?.cancel();
    _countAnnouncementTimer = Timer(_countAnnouncementDelay, () {
      if (mounted) setState(() => _settledCountLabel = _countLabel);
    });
  }

  void _setSelecting(bool value) {
    setState(() => _browseSelecting = value);
    widget.onSelectionPendingChanged(value);
  }

  void _clearSelection() {
    _browseSelecting = false;
    _browseSelection.clear();
    _browseSelectionItems.clear();
    _showBrowseSelected = false;
  }

  void _cancelSelection() {
    setState(_clearSelection);
    widget.onSelectionPendingChanged(false);
  }

  Widget _pendingHint() => Semantics(
    liveRegion: true,
    child: Text(
      _picker.activeKey != null
          ? 'Finish this filter with Done, or cancel it, before saving or tuning.'
          : 'Add the selected programs, or cancel selection, before saving or tuning.',
      style: _studioSupportStyle(context),
    ),
  );
  @override
  void dispose() {
    _countAnnouncementTimer?.cancel();
    _search.dispose();
    _rundownSearch.dispose();
    _searchFocus.dispose();
    _browseScroll.dispose();
    _rundownScroll.dispose();
    for (final node in _rundownFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    // Reuse one immutable snapshot for this projection and its row closures.
    final entries = _rundown.occurrences;
    final inventory = _playableInventory.byId.values;
    final inventoryById = _playableInventory.byId;
    final facets = _facetOptions(_manualLibraryId, inventory: inventory);
    final visible = _filteredInventory(
      inventory: inventory,
      libraryId: _manualLibraryId,
      mediaType: _manualMediaType,
      filters: _manualFilters,
      search: _search.text,
    );
    final shown = _showBrowseSelected
        ? _browseSelection
              .map(
                (id) =>
                    _playableInventory.byId[id] ?? _browseSelectionItems[id],
              )
              .nonNulls
              .toList(growable: false)
        : visible;
    final unavailableSelections = _browseSelection
        .where((id) => !_playableInventory.byId.containsKey(id))
        .length;
    final selectedIds = entries.map((entry) => entry.id).toSet();
    final rundownQuery = _rundownSearch.text.trim().toLowerCase();
    final rundownEntries = [
      if (_manualRundown)
        for (var index = 0; index < entries.length; index++)
          if (_manualEntrySearchText(
            entries[index],
            inventoryById,
          ).contains(rundownQuery))
            (entry: entries[index], index: index),
    ];
    final countLabel = '${visible.length} matching · ${entries.length} added';
    return LineupCompactControls(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.inventoryStatus,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              LineupTab(
                key: const Key('studio-manual-browse-stage'),
                selected: !_manualRundown,
                label: 'Browse library',
                count: visible.length,
                onPressed: _saving
                    ? null
                    : () => setState(() => _manualRundown = false),
              ),
              LineupTab(
                key: const Key('studio-manual-rundown-stage'),
                selected: _manualRundown,
                label: 'Channel programs',
                count: entries.length,
                onPressed: _saving
                    ? null
                    : () => setState(() => _manualRundown = true),
              ),
            ],
          ),
          SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(countLabel, style: _studioSupportStyle(context)),
              if (!_manualRundown && !_browseSelecting)
                OutlinedButton(
                  onPressed: () => _setSelecting(true),
                  child: const Text('Select'),
                ),
            ],
          ),
          if (_settledCountLabel.isNotEmpty)
            Semantics(
              liveRegion: true,
              label: _settledCountLabel,
              child: const SizedBox.shrink(),
            ),
          _studioSourceExplanation(context, widget.sourceExplanation),
          SizedBox(height: 12),
          if (!_manualRundown && _activeFilterKey != null)
            _filterPickerPanel(_activeFilterKey!)
          else if (!_manualRundown) ...[
            LineupField(
              label: 'Search',
              child: TextField(
                key: const Key('studio-search'),
                controller: _search,
                focusNode: _searchFocus,
                enabled: !_saving,
                decoration: const InputDecoration(
                  hintText: 'Search title or show title',
                ),
                onChanged: (_) => _browseChanged(),
              ),
            ),
            SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 960
                    ? 4
                    : constraints.maxWidth >= 700
                    ? 3
                    : constraints.maxWidth >= 480
                    ? 2
                    : 1;
                final double gap = 12;
                final width =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: 16,
                  children: [
                    SizedBox(
                      width: width,
                      child: _libraryDropdown(
                        key: const Key('studio-manual-library'),
                        value: _manualLibraryId,
                        allowAll: true,
                        onChanged: (value) =>
                            _browseChanged(() => _manualLibraryId = value),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: LineupField(
                        label: 'Media type',
                        child: lineupDropdownField<String>(
                          context: context,
                          key: const Key('studio-media-type'),
                          isExpanded: true,
                          iconSize: 24,
                          itemHeight: null,
                          initialValue: _manualMediaType ?? '',
                          style: _studioBodyStyle(context),
                          decoration: const InputDecoration(
                            hintText: 'All types',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('All types'),
                            ),
                            for (final type
                                in inventory.map((item) => item.type).toSet())
                              DropdownMenuItem(value: type, child: Text(type)),
                          ],
                          onChanged: _saving
                              ? null
                              : (value) => _browseChanged(
                                  () => _manualMediaType =
                                      value?.isEmpty == true ? null : value,
                                ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            SizedBox(height: 12),
            _filterChips(facets, browse: true),
            Text(
              'Any selected value within each filter; all filters together.',
              style: _studioSupportStyle(context),
            ),
            SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _browseSelecting
                  ? [
                      Text(
                        '${_browseSelection.length} selected${_browseSelection.where((id) => !visible.any((item) => item.id == id)).isEmpty ? '' : ' · selections outside this view'}${unavailableSelections == 0 ? '' : ' · $unavailableSelections unavailable; retained off air if added'}',
                      ),
                      _pendingHint(),
                      TextButton(
                        onPressed: _browseSelection.isEmpty
                            ? null
                            : () => _setShowBrowseSelected(true),
                        child: const Text('Show selected'),
                      ),
                      if (_showBrowseSelected)
                        TextButton(
                          onPressed: () => _setShowBrowseSelected(false),
                          child: const Text('Back to results'),
                        ),
                      TextButton(
                        onPressed: _cancelSelection,
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: _browseSelection.isEmpty
                            ? null
                            : _addBrowseSelected,
                        child: Text(
                          'Add selected (${_browseSelection.length})',
                        ),
                      ),
                    ]
                  : [
                      if (_rundown.canUndo)
                        TextButton(
                          onPressed: _undoLastAddition,
                          child: const Text('Undo last addition'),
                        ),
                    ],
            ),
            if (shown.isEmpty)
              Text(
                'No programs match. Remove a filter or include watched items.',
                style: _studioSupportStyle(context),
              ),
            SizedBox(
              height: _studioSize(context, 300, 300),
              child: ListView.builder(
                key: const Key('studio-results'),
                controller: _browseScroll,
                itemCount: shown.length,
                itemBuilder: (context, index) {
                  final item = shown[index];
                  final available = _playableInventory.byId.containsKey(
                    item.id,
                  );

                  final browseCheckbox = Checkbox(
                    value: _browseSelection.contains(item.id),
                    onChanged: selectedIds.contains(item.id)
                        ? null
                        : (_) => _toggleBrowseSelection(item),
                  );
                  return ListTile(
                    key: Key('studio-result-${item.id}'),
                    minTileHeight: null,
                    title: Text(
                      item.title,
                      style: _studioBodyStyle(
                        context,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitleTextStyle: _studioSupportStyle(context),
                    subtitle: Text(
                      [
                        if (item.grandparentTitle?.isNotEmpty == true)
                          item.grandparentTitle!,
                        if (item.seasonNumber != null ||
                            item.episodeNumber != null)
                          'S${item.seasonNumber ?? '—'} E${item.episodeNumber ?? '—'}',
                        _compactDuration(item.duration),
                        if (!available)
                          'Unavailable — retained off air if added',
                      ].join(' · '),
                    ),
                    leading: _browseSelecting ? browseCheckbox : null,
                    trailing: selectedIds.contains(item.id)
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check,
                                size: 20,
                                color: LineupTheme.of(context).progressFill,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Added',
                                style: _studioSupportStyle(context),
                              ),
                            ],
                          )
                        : _browseSelecting
                        ? null
                        : OutlinedButton(
                            onPressed: _saving
                                ? null
                                : () => _addManualItem(item),
                            child: const Text('Add'),
                          ),
                    onTap: selectedIds.contains(item.id)
                        ? null
                        : _browseSelecting
                        ? () => _toggleBrowseSelection(item)
                        : () => _addManualItem(item),
                  );
                },
              ),
            ),
          ] else ...[
            TextField(
              key: const Key('studio-rundown-search'),
              controller: _rundownSearch,
              decoration: InputDecoration(
                hintText: 'Search channel programs',
                suffixIcon: rundownQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear channel program search',
                        onPressed: () => setState(_rundownSearch.clear),
                        icon: Icon(
                          Icons.clear,
                          size: 24,
                          semanticLabel: 'Clear channel program search',
                        ),
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            SizedBox(height: 8),
            Text(
              entries.isEmpty
                  ? 'No programs selected. Return to Browse library to add programming.'
                  : '${rundownEntries.length} of ${entries.length} shown · Alt+Up/Down reorders · Delete removes${rundownQuery.isEmpty ? '' : ' · Clear search to drag reorder'}',
            ),
            SizedBox(height: 8),
            SizedBox(
              height: rundownEntries.isEmpty ? 0 : 420,
              child: ReorderableListView.builder(
                key: const Key('studio-rundown'),
                scrollController: _rundownScroll,
                buildDefaultDragHandles: false,
                itemCount: rundownEntries.length,
                onReorderItem: _saving || rundownQuery.isNotEmpty
                    ? (_, _) {}
                    : _reorderManual,
                itemBuilder: (context, visibleIndex) {
                  final item = rundownEntries[visibleIndex];
                  return _rundownRow(
                    item.entry,
                    item.index,
                    !inventoryById.containsKey(item.entry.id),
                    inventoryById,
                    dragIndex: rundownQuery.isEmpty ? visibleIndex : null,
                    entries: entries,
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _addManualItem(PlexMediaItem item) {
    _refreshPlayableInventory();
    final current = _playableInventory.byId[item.id];
    if (current == null) {
      setState(() {});
      return;
    }
    _changed(() => _rundown.addCurrent(current.id, _playableInventory.byId));
  }

  void _toggleBrowseSelection(PlexMediaItem item) => setState(() {
    if (_browseSelection.remove(item.id)) {
      _browseSelectionItems.remove(item.id);
    } else {
      _browseSelection.add(item.id);
      _browseSelectionItems[item.id] = item;
    }
  });

  void _setShowBrowseSelected(bool value) {
    setState(() => _showBrowseSelected = value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _browseScroll.hasClients) _browseScroll.jumpTo(0);
    });
  }

  void _addBrowseSelected() {
    _refreshPlayableInventory();
    _changed(() {
      _rundown.addBatch(
        _browseSelection,
        _playableInventory.byId,
        _browseSelectionItems,
      );
      _browseSelection.clear();
      _browseSelectionItems.clear();
      _browseSelecting = false;
      _showBrowseSelected = false;
    });
    widget.onSelectionPendingChanged(false);
  }

  void _undoLastAddition() {
    // Focus retirement needs the occurrences from before the mutation.
    final previous = _rundown.occurrences;
    _changed(_rundown.undoLastAddition);
    _retireRemovedFocus(previous);
  }

  List<PlexMediaItem> get _manualMatches => _filteredInventory(
    libraryId: _manualLibraryId,
    mediaType: _manualMediaType,
    filters: _manualFilters,
    search: _search.text,
  );

  String get _countLabel =>
      '${_manualMatches.length} matching · ${_rundown.occurrences.length} added';

  Widget _rundownRow(
    ManualOccurrence entry,
    int index,
    bool unavailable,
    Map<String, PlexMediaItem> inventoryById, {
    int? dragIndex,
    required List<ManualOccurrence> entries,
  }) {
    final title = _manualEntryTitle(entry, inventoryById);
    final repeatedTitle =
        entries
            .where(
              (candidate) =>
                  _manualEntryTitle(candidate, inventoryById) == title,
            )
            .length >
        1;
    final positionedTitle = repeatedTitle
        ? '$title, item ${index + 1} of ${entries.length}'
        : title;
    final focus = _rundownFocus.putIfAbsent(
      entry,
      () => FocusNode(debugLabel: 'Selected program $positionedTitle'),
    );
    focus.debugLabel = 'Selected program $positionedTitle';
    final liveItem = inventoryById[entry.id];
    final duration = liveItem?.duration ?? entry.item.duration;
    final season = liveItem?.seasonNumber ?? entry.item.seasonNumber;
    final episode = liveItem?.episodeNumber ?? entry.item.episodeNumber;
    final facts = [
      '${index + 1} of ${entries.length}',
      _compactDuration(duration),
      if (season != null || episode != null)
        'S${season ?? '—'} E${episode ?? '—'}',
    ];
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        lineupArrowButton(
          tooltip: 'Move $positionedTitle earlier in $_draftChannelLabel',
          onPressed: _saving || index == 0
              ? null
              : () => _moveManual(entry, -1),
          icon: Icons.arrow_upward,
        ),
        lineupArrowButton(
          tooltip: 'Move $positionedTitle later in $_draftChannelLabel',
          onPressed: _saving || index == entries.length - 1
              ? null
              : () => _moveManual(entry, 1),
          icon: Icons.arrow_downward,
        ),
        TextButton(
          onPressed: _saving ? null : () => _moveManualTo(entry),
          child: const Text('Move to…'),
        ),
        IconButton(
          tooltip: 'Remove from channel',
          onPressed: _saving ? null : () => _removeManual(entry),
          icon: const Icon(Icons.close, semanticLabel: 'Remove from channel'),
        ),
      ],
    );
    final tile = LayoutBuilder(
      builder: (context, constraints) {
        final wrapActions =
            constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
            640;
        return ListTile(
          key: entry.occurrence == 1 ? Key('studio-rundown-${entry.id}') : null,
          title: Text(
            title,
            style: _studioBodyStyle(context, fontWeight: FontWeight.w500),
          ),
          subtitleTextStyle: _studioSupportStyle(context),
          minTileHeight: null,
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(facts.join(' · ')),
              if (unavailable)
                const Text('Unavailable — retained until removed'),
              if (wrapActions)
                Align(alignment: Alignment.centerRight, child: actions),
            ],
          ),
          trailing: wrapActions ? null : actions,
          leading: dragIndex == null
              ? null
              : Tooltip(
                  message: 'Drag $positionedTitle to reorder',
                  child: ReorderableDragStartListener(
                    index: dragIndex,
                    child: const Icon(Icons.drag_handle, size: 24),
                  ),
                ),
        );
      },
    );
    return CallbackShortcuts(
      key: ObjectKey(entry),
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () =>
            _moveManual(entry, -1),
        const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): () =>
            _moveManual(entry, 1),
        const SingleActivator(LogicalKeyboardKey.delete): () =>
            _removeManual(entry),
      },
      child: Focus(
        focusNode: focus,
        child: ListenableBuilder(
          listenable: focus,
          builder: (context, child) {
            final roles = LineupTheme.of(context);
            return Container(
              decoration: BoxDecoration(
                color: focus.hasFocus ? roles.selectedSurface : null,
                border: Border(
                  left: BorderSide(
                    color: focus.hasFocus
                        ? roles.progressFill
                        : Colors.transparent,
                    width: 3,
                  ),
                ),
                borderRadius: BorderRadius.zero,
              ),
              foregroundDecoration: BoxDecoration(
                border: Border.all(
                  color: LineupFocusScope.visible(context, focus.hasFocus)
                      ? roles.focusBorder
                      : Colors.transparent,
                  width: LineupFocusScope.visible(context, focus.hasFocus)
                      ? roles.focusBorderWidth
                      : 1,
                ),
              ),
              child: child,
            );
          },
          child: repeatedTitle
              ? Semantics(
                  container: true,
                  label:
                      '$positionedTitle${unavailable ? ', unavailable — retained until removed' : ''}',
                  child: tile,
                )
              : tile,
        ),
      ),
    );
  }

  String _manualEntryTitle(
    ManualOccurrence entry,
    Map<String, PlexMediaItem> inventoryById,
  ) => inventoryById[entry.id]?.title ?? entry.item.title;

  String _manualEntrySearchText(
    ManualOccurrence entry,
    Map<String, PlexMediaItem> inventoryById,
  ) {
    final item = inventoryById[entry.id];
    return [
      item?.title ?? entry.item.title,
      item?.grandparentTitle ?? entry.item.showTitle,
      item?.seasonNumber ?? entry.item.seasonNumber,
      item?.episodeNumber ?? entry.item.episodeNumber,
      entry.id,
    ].join(' ').toLowerCase();
  }

  String get _draftChannelLabel => widget.name.trim().isEmpty
      ? 'new channel'
      : 'channel ${widget.name.trim()}';

  void _moveManual(ManualOccurrence entry, int delta) {
    if (_saving) return;
    final entries = _rundown.occurrences;
    final from = entries.indexOf(entry);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= entries.length) return;
    _changed(() {
      _rundown.move(entry, delta);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rundownFocus[entry]?.requestFocus();
    });
  }

  void _reorderManual(int from, int to) {
    if (_saving || from == to) return;
    _changed(() => _rundown.reorder(from, to));
  }

  Future<void> _moveManualTo(ManualOccurrence entry) async {
    final entries = _rundown.occurrences;
    final target = await showDialog<({int index, bool after})>(
      context: context,
      builder: (context) => _MoveProgramDialog(
        entries: entries,
        moving: entry,
        titleFor: (candidate) =>
            _manualEntryTitle(candidate, _playableInventory.byId),
      ),
    );
    if (target == null || !mounted) return;
    _changed(() {
      _rundown.moveTo(entry, target.index, after: target.after);
    });
  }

  void _removeManual(ManualOccurrence entry) {
    if (_saving) return;
    final entries = _rundown.occurrences;
    final index = entries.indexOf(entry);
    if (index < 0) return;
    late List<ManualOccurrence> remaining;
    _changed(() {
      _rundown.remove(entry);
      remaining = _rundown.occurrences;
      if (remaining.isEmpty) _manualRundown = false;
    });
    final nextEntry = remaining.isEmpty
        ? null
        : remaining[index.clamp(0, remaining.length - 1)];
    final removedFocus = _rundownFocus.remove(entry);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (nextEntry == null) {
          _searchFocus.requestFocus();
        } else {
          _rundownFocus[nextEntry]?.requestFocus();
        }
      }
      removedFocus?.dispose();
    });
  }

  void _retireRemovedFocus(List<ManualOccurrence> previous) {
    final current = _rundown.occurrences.toSet();
    final removed = previous.where((entry) => !current.contains(entry));
    final removedFocus = removed
        .map(_rundownFocus.remove)
        .nonNulls
        .toList(growable: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final focus in removedFocus) {
        focus.dispose();
      }
    });
  }
}

class _MoveProgramDialog extends StatefulWidget {
  const _MoveProgramDialog({
    required this.entries,
    required this.moving,
    required this.titleFor,
  });

  final List<ManualOccurrence> entries;
  final ManualOccurrence moving;
  final String Function(ManualOccurrence entry) titleFor;

  @override
  State<_MoveProgramDialog> createState() => _MoveProgramDialogState();
}

class _MoveProgramDialogState extends State<_MoveProgramDialog> {
  ManualOccurrence? _target;
  bool _after = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _label(ManualOccurrence entry) {
    final title = widget.titleFor(entry);
    final matches = widget.entries
        .where((candidate) => widget.titleFor(candidate) == title)
        .toList();
    final occurrence = matches.indexOf(entry) + 1;
    return '$title · position ${widget.entries.indexOf(entry) + 1}${matches.length > 1 ? ' · occurrence $occurrence of ${matches.length}' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final targets = widget.entries
        .where(
          (entry) =>
              !identical(entry, widget.moving) &&
              _label(entry).toLowerCase().contains(query),
        )
        .toList(growable: false);
    if (_target == null || !targets.contains(_target)) {
      _target = targets.firstOrNull;
    }
    final size = MediaQuery.sizeOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);

    final dialog = AlertDialog(
      title: Text('Move ${widget.titleFor(widget.moving)}'),
      content: SizedBox(
        width: (size.width - 128).clamp(0.0, 520),
        height: (size.height - viewInsets.vertical - 200).clamp(0.0, 380),
        child: Column(
          children: [
            TextField(
              key: const Key('move-program-search'),
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(hintText: 'Search programs'),
              onChanged: (_) => setState(() {}),
            ),
            SizedBox(height: 8),
            Expanded(
              child: RadioGroup<ManualOccurrence>(
                groupValue: _target,
                onChanged: (value) => setState(() => _target = value),
                child: ListView(
                  children: [
                    for (final entry in targets)
                      RadioListTile<ManualOccurrence>(
                        value: entry,

                        minTileHeight: null,
                        title: Text(_label(entry)),
                      ),
                  ],
                ),
              ),
            ),
            LineupSegmentedControl<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Before')),
                ButtonSegment(value: true, label: Text('After')),
              ],
              selected: {_after},
              onSelectionChanged: (value) =>
                  setState(() => _after = value.single),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _target == null
              ? null
              : () => Navigator.pop(context, (
                  index: widget.entries.indexOf(_target!),
                  after: _after,
                )),
          child: const Text('Move'),
        ),
      ],
    );
    return dialog;
  }
}
