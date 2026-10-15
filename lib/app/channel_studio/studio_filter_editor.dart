part of '../channel_studio_view.dart';

class _StudioFilterEditor extends StatefulWidget {
  const _StudioFilterEditor({
    required this.draft,
    required this.inventory,
    required this.selectedLibraries,
    required this.libraries,
    required this.picker,
    required this.saving,
    required this.inventoryStatus,
    required this.sourceExplanation,
    required this.onChanged,
    super.key,
  });
  final ChannelStudioDraft draft;
  final _StudioInventory inventory;
  final List<PlexLibrary> selectedLibraries;
  final List<PlexLibrary> libraries;
  final _FilterPickerController picker;
  final bool saving;
  final Widget inventoryStatus;
  final String? sourceExplanation;
  final VoidCallback onChanged;
  @override
  State<_StudioFilterEditor> createState() => _StudioFilterEditorState();
}

class _StudioFilterEditorState extends State<_StudioFilterEditor>
    with _StudioFilterControls<_StudioFilterEditor> {
  final _librarySearch = TextEditingController();
  ChannelStudioDraft get _session => widget.draft;
  @override
  _FilterPickerController get _picker => widget.picker;
  @override
  _StudioInventory get _playableInventory => widget.inventory;
  @override
  List<PlexLibrary> get _selectedLibraries => widget.selectedLibraries;
  @override
  List<PlexLibrary> get _libraries => widget.libraries;
  @override
  bool get _saving => widget.saving;
  @override
  bool get _browse => false;
  @override
  Map<LibraryFilter, List<String>> get _currentFilters => _session.filters;
  @override
  String? get _currentLibraryId => _session.filterLibraryId;
  @override
  String? get _currentMediaType => null;
  @override
  String get _currentSearch => '';
  @override
  bool get _includeWatched => _session.filterIncludeWatched;
  @override
  void _filtersChanged(VoidCallback apply) => _filterChanged(apply);
  void _filterChanged([VoidCallback? apply]) {
    apply?.call();
    widget.onChanged();
  }

  @override
  void dispose() {
    _librarySearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final facets = _facetOptions(_session.filterLibraryId);
    final matches = _filteredInventory(
      libraryId: _session.filterLibraryId,
      filters: _session.filters,
      includeWatched: _session.filterIncludeWatched,
      search: _librarySearch.text,
    );
    if (_activeFilterKey case final key?) {
      return _filterPickerPanel(key);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.inventoryStatus,
        LineupField(
          label: 'Search',
          child: TextField(
            key: const Key('studio-library-search'),
            controller: _librarySearch,
            decoration: const InputDecoration(
              hintText: 'Search title or show title',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final double gap = 16;
            final width = constraints.maxWidth >= 700
                ? (constraints.maxWidth - gap) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: gap,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: width,
                  child: _libraryDropdown(
                    key: const Key('studio-filter-library'),
                    value: _session.filterLibraryId,
                    onChanged: (value) =>
                        _filterChanged(() => _session.filterLibraryId = value),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _filterControl(
                        'collection',
                        facets.values['collection'] ?? const [],
                        facets.labels['collection'] ?? const {},
                      ),
                      if ((_session.filters[LibraryFilter.collection]?.length ??
                              0) >
                          3)
                        TextButton(
                          onPressed: () => setState(() {
                            if (!_expandedFilterSummaries.remove(
                              'collection',
                            )) {
                              _expandedFilterSummaries.add('collection');
                            }
                          }),
                          child: Text(
                            _expandedFilterSummaries.contains('collection')
                                ? 'Show fewer collections'
                                : 'Show all selected collections',
                          ),
                        ),
                      if (_expandedFilterSummaries.contains('collection'))
                        Text(
                          (_session.filters[LibraryFilter.collection] ??
                                  const [])
                              .map(
                                (value) =>
                                    facets.labels['collection']?[value] ??
                                    value,
                              )
                              .join(', '),
                          style: _studioSupportStyle(context),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        SizedBox(height: 12),
        LineupFieldButton(
          label: 'Media type',
          value:
              _selectedLibraries
                      .where(
                        (library) => library.id == _session.filterLibraryId,
                      )
                      .firstOrNull
                      ?.type ==
                  PlexLibraryType.show
              ? 'TV episodes'
              : 'Movies',
          onPressed: null,
        ),
        SizedBox(height: 12),
        _filterChips(facets, browse: false),
        SizedBox(height: 12),
        Text(
          'Any selected value within each filter; all filters together.',
          style: _studioSupportStyle(context),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 330),
            child: Material(
              type: MaterialType.transparency,
              child: SwitchListTile(
                key: const Key('studio-filter-include-watched'),
                contentPadding: EdgeInsets.zero,
                value: _session.filterIncludeWatched,
                title: Text(
                  'Include watched items',
                  style: _studioBodyStyle(context),
                ),
                onChanged: _saving
                    ? null
                    : (value) => _filterChanged(
                        () => _session.filterIncludeWatched = value,
                      ),
              ),
            ),
          ),
        ),
        SizedBox(height: 16),
        Divider(height: 1, color: roles.subtleBorder),
        SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 4,
          children: [
            Text(
              'Matching programs',
              style: _studioSectionHeadingStyle(context),
            ),
            Text(
              '${matches.length} matching programs',
              style: _studioSupportStyle(context),
            ),
          ],
        ),
        _studioSourceExplanation(context, widget.sourceExplanation),
        if (matches.isEmpty &&
            _programmingError(_resolveDraftContent()) == null)
          Text(
            'No programs match. Remove a filter or include watched items.',
            style: _studioSupportStyle(context),
          ),
        for (final item in matches.take(5))
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: roles.subtleBorder)),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(item.title, style: _studioBodyStyle(context)),
            ),
          ),
        if (matches.length > 5)
          Text(
            'Showing 5 of ${matches.length} matching programs.',
            style: _studioSupportStyle(context),
          ),
      ],
    );
  }
}
