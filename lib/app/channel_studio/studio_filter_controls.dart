part of '../channel_studio_view.dart';

enum _StudioPendingChoice { filter, selection }

/// Shared only by the library filter editor and the manual browser.
/// Pending choices never mutate the draft until the picker applies them.
final class _FilterPickerController extends ChangeNotifier {
  _FilterPickerController({required this.onOpening});
  final VoidCallback onOpening;
  String? activeKey;
  bool forBrowse = false;
  List<String> values = const [];
  Map<String, String> labels = const {};
  Set<String> available = const {};
  final pending = LinkedHashSet<String>();
  bool showPending = false;

  void choose({required bool browse}) {
    if (activeKey == null) onOpening();
    forBrowse = browse;
    activeKey = 'choose';
    notifyListeners();
  }

  void open(
    String key,
    List<String> options,
    Map<String, String> optionLabels,
    List<String> selected, {
    required bool browse,
  }) {
    if (activeKey == null) onOpening();
    forBrowse = browse;
    activeKey = key;
    values = ({...options, ...selected}.toList()..sort());
    available = options.toSet();
    labels = Map.unmodifiable(optionLabels);
    pending
      ..clear()
      ..addAll(selected);
    showPending = false;
    notifyListeners();
  }

  void close({bool notify = true}) {
    activeKey = null;
    pending.clear();
    if (notify) notifyListeners();
  }
}

mixin _StudioFilterControls<T extends StatefulWidget> on State<T> {
  _FilterPickerController get _picker;
  _StudioInventory get _playableInventory;
  List<PlexLibrary> get _selectedLibraries;
  List<PlexLibrary> get _libraries;
  bool get _saving;
  bool get _browse;
  Map<LibraryFilter, List<String>> get _currentFilters;
  String? get _currentLibraryId;
  String? get _currentMediaType;
  String get _currentSearch;
  bool get _includeWatched;
  void _filtersChanged(VoidCallback apply);
  final _filterControlFocus = <String, FocusNode>{};
  final _expandedFilterSummaries = <String>{};
  String? get _activeFilterKey =>
      _picker.forBrowse == _browse ? _picker.activeKey : null;
  String _libraryTitle(String? id) =>
      _libraries.where((library) => library.id == id).firstOrNull?.title ??
      id ??
      'Library';

  _FacetOptions _facetOptions(
    String? libraryId, {
    Iterable<PlexMediaItem>? inventory,
  }) => _studioFacetOptions(
    libraryId,
    inventory: inventory ?? _playableInventory.byId.values,
  );
  List<PlexMediaItem> _filteredInventory({
    Iterable<PlexMediaItem>? inventory,
    String? libraryId,
    String? mediaType,
    Map<LibraryFilter, List<String>> filters = const {},
    String search = '',
    bool includeWatched = true,
  }) => _studioFilteredInventory(
    inventory: inventory ?? _playableInventory.byId.values,
    libraryId: libraryId,
    mediaType: mediaType,
    filters: filters,
    search: search,
    includeWatched: includeWatched,
  );

  void _openFilterPicker(
    String key,
    List<String> values,
    Map<String, String> labels, {
    bool browse = false,
  }) {
    _picker.open(
      key,
      values,
      labels,
      _currentFilters[_libraryFilter(key)] ?? const [],
      browse: _browse,
    );
  }

  Widget _filterPickerPanel(String key) => _StudioFilterPicker(
    key: ValueKey('filter-picker-$key'),
    picker: _picker,
    inventory: _playableInventory.byId.values,
    facets: _facetOptions(_currentLibraryId),
    filters: _currentFilters,
    libraryId: _currentLibraryId,
    libraryTitle: _libraryTitle(_currentLibraryId),
    mediaType: _currentMediaType,
    search: _currentSearch,
    includeWatched: _includeWatched,
    onCancel: () {
      _picker.close();
      _restoreFilterFocus(key);
    },
    onApply: (values) {
      _picker.close();
      _filtersChanged(() {
        final filter = _libraryFilter(key);
        if (values.isEmpty) {
          _currentFilters.remove(filter);
        } else {
          _currentFilters[filter] = List.unmodifiable(values);
        }
      });
      _restoreFilterFocus(key);
    },
  );

  void _restoreFilterFocus(String key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        (_filterControlFocus[key] ?? _filterControlFocus['choose'])
            ?.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    for (final node in _filterControlFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  Widget _filterControl(
    String key,
    List<String> values,
    Map<String, String> labels,
  ) {
    final filter = _libraryFilter(key);
    final selected = _currentFilters[filter] ?? const [];
    final selectedLabels = selected
        .map((value) => labels[value] ?? value)
        .toList(growable: false);
    final unavailable = selected
        .where((value) => !values.contains(value))
        .length;
    final focus = _filterControlFocus.putIfAbsent(
      key,
      () => FocusNode(debugLabel: 'Edit ${_facetLabel(key)} filter'),
    );
    final summary = selected.isEmpty
        ? key == 'collection'
              ? 'Any collection'
              : 'Any'
        : '${selectedLabels.take(3).join(', ')}${selected.length > 3 ? ' · +${selected.length - 3} more' : ''}${unavailable > 0 ? ' · $unavailable unavailable' : ''}';
    return LineupFieldButton(
      key: Key('studio-filter-$key'),
      label: _facetLabel(key),
      value: key == 'collection' && values.isEmpty && selected.isEmpty
          ? 'None in this library'
          : summary,
      focusNode: focus,
      onPressed:
          _saving || (key == 'collection' && values.isEmpty && selected.isEmpty)
          ? null
          : () => _openFilterPicker(key, values, labels),
    );
  }

  Widget _filterChips(_FacetOptions facets, {required bool browse}) {
    final filters = _currentFilters;
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final entry in filters.entries.where(
            (entry) => browse || entry.key != LibraryFilter.collection,
          )) ...[
            InputChip(
              key: Key(
                'studio-${browse ? 'browse' : 'applied'}-${entry.key.name}',
              ),
              focusNode: _filterControlFocus.putIfAbsent(
                entry.key.name,
                () => FocusNode(
                  debugLabel: 'Edit ${_facetLabel(entry.key.name)} filter',
                ),
              ),
              label: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: (constraints.maxWidth - 96).clamp(
                    0,
                    double.infinity,
                  ),
                ),
                child: Text(
                  '${_facetLabel(entry.key.name)}: ${entry.value.take(3).map((value) => facets.labels[entry.key.name]?[value] ?? value).join(', ')}${entry.value.length > 3 ? ' · +${entry.value.length - 3} more' : ''}',
                  style: _studioSupportStyle(context),
                ),
              ),
              onPressed: _saving
                  ? null
                  : () => _openFilterPicker(
                      entry.key.name,
                      facets.values[entry.key.name] ?? const [],
                      facets.labels[entry.key.name] ?? const {},
                      browse: browse,
                    ),
              onDeleted: _saving
                  ? null
                  : () => _filtersChanged(() => filters.remove(entry.key)),
              deleteIcon: const Icon(Icons.close, size: 20),
            ),
            if (entry.value.length > 3)
              TextButton(
                onPressed: () => setState(() {
                  final key =
                      '${browse ? 'browse' : 'library'}-${entry.key.name}';
                  if (!_expandedFilterSummaries.remove(key)) {
                    _expandedFilterSummaries.add(key);
                  }
                }),
                child: Text(
                  _expandedFilterSummaries.contains(
                        '${browse ? 'browse' : 'library'}-${entry.key.name}',
                      )
                      ? 'Show fewer ${_facetLabel(entry.key.name).toLowerCase()} values'
                      : 'Show all ${entry.value.length} ${_facetLabel(entry.key.name).toLowerCase()} values',
                ),
              ),
            if (_expandedFilterSummaries.contains(
              '${browse ? 'browse' : 'library'}-${entry.key.name}',
            ))
              Text(
                entry.value
                    .map(
                      (value) => facets.labels[entry.key.name]?[value] ?? value,
                    )
                    .join(', '),
                style: _studioSupportStyle(context),
              ),
          ],
          TextButton(
            key: Key('studio-${browse ? 'browse' : 'library'}-add-filter'),
            focusNode: _filterControlFocus.putIfAbsent(
              'choose',
              () => FocusNode(debugLabel: 'Add filter'),
            ),
            onPressed: _saving ? null : () => _picker.choose(browse: browse),
            child: const Text('+ Filter'),
          ),
        ],
      ),
    );
  }

  Widget _libraryDropdown({
    required Key key,
    required String? value,
    required ValueChanged<String?> onChanged,
    bool allowAll = false,
  }) {
    final selected = _selectedLibraries.any((library) => library.id == value);
    return LineupField(
      label: 'Library',
      child: lineupDropdownField<String>(
        context: context,
        key: key,
        isExpanded: true,
        iconSize: 24,
        itemHeight: null,
        initialValue: selected
            ? value
            : allowAll
            ? ''
            : null,
        decoration: const InputDecoration(),
        items: [
          if (allowAll)
            const DropdownMenuItem(value: '', child: Text('All libraries')),
          for (final library in _selectedLibraries)
            DropdownMenuItem(value: library.id, child: Text(library.title)),
        ],
        onChanged: _saving
            ? null
            : (value) => onChanged(value?.isEmpty == true ? null : value),
      ),
    );
  }
}
