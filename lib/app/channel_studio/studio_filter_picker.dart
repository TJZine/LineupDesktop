part of '../channel_studio_view.dart';

class _StudioFilterPicker extends StatefulWidget {
  const _StudioFilterPicker({
    required this.picker,
    required this.inventory,
    required this.facets,
    required this.filters,
    required this.libraryId,
    required this.libraryTitle,
    required this.mediaType,
    required this.search,
    required this.includeWatched,
    required this.onCancel,
    required this.onApply,
    super.key,
  });
  final _FilterPickerController picker;
  final Iterable<PlexMediaItem> inventory;
  final _FacetOptions facets;
  final Map<LibraryFilter, List<String>> filters;
  final String? libraryId;
  final String libraryTitle;
  final String? mediaType;
  final String search;
  final bool includeWatched;
  final VoidCallback onCancel;
  final ValueChanged<List<String>> onApply;
  @override
  State<_StudioFilterPicker> createState() => _StudioFilterPickerState();
}

class _StudioFilterPickerState extends State<_StudioFilterPicker> {
  final _filterPickerSearch = TextEditingController();
  final _filterPickerFocus = FocusNode(debugLabel: 'Search filter values');
  List<String> get _activeFilterValues => widget.picker.values;
  Set<String> get _activeAvailableFilterValues => widget.picker.available;
  Map<String, String> get _activeFilterLabels => widget.picker.labels;
  Set<String> get _pendingFilterValues => widget.picker.pending;
  bool get _showPendingFilterValues => widget.picker.showPending;
  set _showPendingFilterValues(bool value) => widget.picker.showPending = value;
  @override
  void initState() {
    super.initState();
    if (widget.picker.activeKey != 'choose') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _filterPickerFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _filterPickerSearch.dispose();
    _filterPickerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final key = widget.picker.activeKey!;
    final filters = widget.filters;
    final libraryId = widget.libraryId;
    if (key == 'choose') {
      final facets = widget.facets;
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              widget.onCancel(),
        },
        child: Focus(
          autofocus: true,
          child: Column(
            key: const Key('studio-filter-criteria'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Choose a filter',
                style: _studioSectionHeadingStyle(context),
              ),
              for (final criterion in _facetKeys)
                TextButton(
                  key: Key('studio-filter-$criterion'),
                  onPressed: () => widget.picker.open(
                    criterion,
                    facets.values[criterion] ?? const [],
                    facets.labels[criterion] ?? const {},
                    widget.filters[_libraryFilter(criterion)] ?? const [],
                    browse: widget.picker.forBrowse,
                  ),
                  child: Text(_facetLabel(criterion)),
                ),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      'Finish this filter with Done, or cancel it, before saving or tuning.',
                      style: _studioSupportStyle(context),
                    ),
                  ),
                  TextButton(
                    onPressed: () => widget.onCancel(),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    final query = _filterPickerSearch.text.trim().toLowerCase();
    final visible = _activeFilterValues
        .where(
          (value) =>
              (!_showPendingFilterValues ||
                  _pendingFilterValues.contains(value)) &&
              value.toLowerCase().contains(query),
        )
        .toList(growable: false);
    final pendingFilters = Map<LibraryFilter, List<String>>.from(filters);
    if (_pendingFilterValues.isEmpty) {
      pendingFilters.remove(_libraryFilter(key));
    } else {
      pendingFilters[_libraryFilter(key)] = _pendingFilterValues.toList();
    }
    final count = _studioFilteredInventory(
      inventory: widget.inventory,
      libraryId: libraryId,
      mediaType: widget.mediaType,
      search: widget.search,
      filters: pendingFilters,
      includeWatched: widget.includeWatched,
    ).length;
    final unavailable = _pendingFilterValues
        .where((value) => !_activeAvailableFilterValues.contains(value))
        .toSet();
    Widget valueTile(String value) => CheckboxListTile(
      controlAffinity: ListTileControlAffinity.leading,
      value: _pendingFilterValues.contains(value),
      title: Text(
        _activeAvailableFilterValues.contains(value)
            ? (_activeFilterLabels[value] ?? value)
            : '$value (unavailable — retained)',
      ),
      onChanged: (checked) => setState(() {
        checked == true
            ? _pendingFilterValues.add(value)
            : _pendingFilterValues.remove(value);
      }),
    );
    final media = MediaQuery.of(context);
    final independentlyScrollable =
        media.size.width >= LineupLayout.compact &&
        media.textScaler.scale(14) <= 21;
    return Material(
      type: MaterialType.transparency,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              widget.onCancel(),
        },
        child: Focus(
          autofocus: true,
          child: Column(
            key: Key('studio-filter-picker-$key'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Choose ${_facetLabel(key).toLowerCase()} values',
                style: _studioSectionHeadingStyle(context),
              ),
              SizedBox(height: 4),
              Text(widget.libraryTitle, style: _studioSupportStyle(context)),
              SizedBox(height: 8),
              LineupTextFieldActivation(
                focusNode: _filterPickerFocus,
                builder: (fieldContext, fieldFocus, finishEditing) => TextField(
                  controller: _filterPickerSearch,
                  focusNode: fieldFocus,
                  // TV arrival focuses the navigation node (initState) without
                  // editing; autofocus would grant the editor a keyboard.
                  autofocus: !DeviceProfile.of(fieldContext).isTv,
                  onEditingComplete: finishEditing,
                  style: _studioBodyStyle(fieldContext),
                  decoration: const InputDecoration(hintText: 'Search values'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => setState(
                      () =>
                          _showPendingFilterValues = !_showPendingFilterValues,
                    ),
                    child: Text('${_pendingFilterValues.length} selected'),
                  ),
                  TextButton(
                    onPressed: _pendingFilterValues.isEmpty
                        ? null
                        : () => setState(_pendingFilterValues.clear),
                    child: const Text('Clear selection'),
                  ),
                  if (unavailable.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(
                        () => _pendingFilterValues.removeAll(unavailable),
                      ),
                      child: Text('Remove ${unavailable.length} unavailable'),
                    ),
                  Text(
                    '$count matching programs',
                    style: _studioSupportStyle(context),
                  ),
                ],
              ),
              if (independentlyScrollable)
                SizedBox(
                  height: (media.size.height * .29).clamp(180, 460),
                  child: ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) => valueTile(visible[index]),
                  ),
                )
              else
                for (final value in visible) valueTile(value),
              SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      'Finish this filter with Done, or cancel it, before saving or tuning.',
                      style: _studioSupportStyle(context),
                    ),
                  ),
                  TextButton(
                    onPressed: () => widget.onCancel(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      widget.onApply(_pendingFilterValues.toList());
                    },
                    child: const Text('Done'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
