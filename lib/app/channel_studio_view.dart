import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channels/channel.dart';
import '../channels/content_resolver.dart';
import '../plex/plex_models.dart';
import '../ui/app_ui.dart';
import 'channel_air_check.dart';
import 'form_error.dart';
import 'lineup_controller.dart';

enum ChannelStudioMode {
  createCustom,
  editCustom,
  inspectGenerated,
  duplicateCustom,
}

enum _SourceChoice { library, playlist, filter, handPicked }

const _facetKeys = [
  'collection',
  'genre',
  'studio',
  'actor',
  'director',
  'decade',
];

String _facetLabel(String key) => switch (key) {
  'collection' => 'Collection',
  'genre' => 'Genre',
  'studio' => 'Studio',
  'actor' => 'Actor',
  'director' => 'Director',
  'decade' => 'Decade',
  _ => key,
};

class ChannelStudioView extends StatefulWidget {
  const ChannelStudioView({
    required this.controller,
    required this.mode,
    required this.onBack,
    required this.onSaved,
    required this.onTune,
    required this.onDuplicate,
    required this.onOpenGenerateLineup,
    this.channel,
    this.clock,
    super.key,
  });

  final LineupController controller;
  final ChannelStudioMode mode;
  final Channel? channel;
  final Future<void> Function(String? focusChannelId) onBack;
  final ValueChanged<String> onSaved;
  final Future<bool> Function(String channelId) onTune;
  final ValueChanged<Channel> onDuplicate;
  final Future<void> Function() onOpenGenerateLineup;
  final DateTime Function()? clock;

  @override
  State<ChannelStudioView> createState() => ChannelStudioViewState();
}

class ChannelStudioViewState extends State<ChannelStudioView> {
  static const _countAnnouncementDelay = Duration(milliseconds: 300);
  static const _resultWindow = 100;
  final _form = GlobalKey<FormState>();
  final _nameFocus = FocusNode(debugLabel: 'Channel name');
  final _numberFocus = FocusNode(debugLabel: 'Channel number');
  final _saveFocus = FocusNode(debugLabel: 'Save channel');
  final _searchFocus = FocusNode(debugLabel: 'Search programming');
  late final TextEditingController _name;
  late final TextEditingController _number;
  late final TextEditingController _search;
  late String _id;
  late ContentSource _source;
  late PlaybackMode _playbackMode;
  late DateTime _anchor;
  late int _shuffleSeed;
  late int? _blockSize;
  late String? _builderKey;
  late Channel? _expectedBase;
  late bool _generated;
  late bool _sourceReadOnly;
  _SourceChoice? _sourceChoice;
  late List<String> _manualIds;
  late Map<String, ChannelItem> _retainedManualItems;
  late String? _libraryId;
  late bool _includeWatched;
  late bool _filterIncludeWatched;
  String? _playlistId;
  String? _filterLibraryId;
  final _filters = <String, String>{};
  String? _manualLibraryId;
  String? _manualMediaType;
  final _manualFilters = <String, String>{};
  final _rundownFocus = <String, FocusNode>{};
  Timer? _countAnnouncementTimer;
  String _settledCountLabel = '';
  late Map<String, Object?> _baselineDraftSignature;
  bool _dirty = false;
  bool _saving = false;
  bool _conflict = false;
  bool _baseDeleted = false;
  String? _error;
  String? _success;
  ChannelAirCheckValidity _airCheckValidity = ChannelAirCheckValidity.unknown;
  bool _scheduleIdentityCommitted = false;

  bool get saving => _saving;
  bool get dirty => _dirty;
  ChannelStudioMode get _effectiveMode => _expectedBase != null && !_generated
      ? ChannelStudioMode.editCustom
      : widget.mode;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  void _loadInitial() {
    final original = widget.channel;
    _expectedBase = switch (widget.mode) {
      ChannelStudioMode.editCustom ||
      ChannelStudioMode.inspectGenerated => original,
      _ => null,
    };
    _generated = widget.mode == ChannelStudioMode.inspectGenerated;
    _scheduleIdentityCommitted = original != null;
    _id = widget.mode == ChannelStudioMode.createCustom
        ? createChannelId()
        : widget.mode == ChannelStudioMode.duplicateCustom
        ? createChannelId()
        : original!.id;
    final nextNumber = _lowestFreeNumber();
    final initialNumber = switch (widget.mode) {
      ChannelStudioMode.createCustom ||
      ChannelStudioMode.duplicateCustom => nextNumber,
      _ => original!.number,
    };
    _name = TextEditingController(
      text: widget.mode == ChannelStudioMode.duplicateCustom
          ? '${original!.name} copy'
          : original?.name ?? '',
    );
    _number = TextEditingController(text: initialNumber?.toString() ?? '');
    _search = TextEditingController();
    _source = original?.source ?? _defaultSource();
    _playbackMode = original?.playbackMode ?? PlaybackMode.shuffle;
    _anchor = original?.anchor ?? _clock().toUtc();
    _shuffleSeed = original?.shuffleSeed ?? _id.hashCode;
    _blockSize = original?.blockSize;
    _builderKey = _generated ? original!.builderKey : null;
    _configureSource(_source);
    _baselineDraftSignature = _draftSignature;
  }

  DateTime _clock() => (widget.clock ?? DateTime.now)();

  ContentSource _defaultSource() {
    final library = widget.controller.libraries
        .where((item) => widget.controller.selectedLibraryIds.contains(item.id))
        .firstOrNull;
    return library == null
        ? const ManualSource([])
        : LibrarySource(libraryId: library.id, libraryType: library.type);
  }

  void _configureSource(ContentSource source) {
    _sourceReadOnly = _generated;
    _sourceChoice = switch (source) {
      LibrarySource(:final filters) =>
        filters.isEmpty ? _SourceChoice.library : _SourceChoice.filter,
      PlaylistSource() => _SourceChoice.playlist,
      ManualSource() => _SourceChoice.handPicked,
      MixedSource() => null,
    };
    _manualIds = switch (source) {
      ManualSource(:final items) => items.map((item) => item.id).toList(),
      _ => <String>[],
    };
    _retainedManualItems = switch (source) {
      ManualSource(:final items) => {for (final item in items) item.id: item},
      _ => <String, ChannelItem>{},
    };
    _libraryId = switch (source) {
      LibrarySource(:final libraryId) => libraryId,
      _ => widget.controller.selectedLibraryIds.firstOrNull,
    };
    _includeWatched = switch (source) {
      LibrarySource(:final includeWatched) => includeWatched,
      _ => true,
    };
    _filterIncludeWatched = switch (source) {
      LibrarySource(:final includeWatched, :final filters)
          when filters.isNotEmpty =>
        includeWatched,
      _ => true,
    };
    _playlistId = switch (source) {
      PlaylistSource(:final playlistId) => playlistId,
      _ => widget.controller.playableInventory.playlists.firstOrNull?.id,
    };
    _filterLibraryId = switch (source) {
      LibrarySource(:final libraryId, :final filters) when filters.isNotEmpty =>
        libraryId,
      _ => widget.controller.selectedLibraryIds.firstOrNull,
    };
    _filters
      ..clear()
      ..addAll(switch (source) {
        LibrarySource(:final filters) when filters.isNotEmpty => filters,
        _ => const {},
      });
    _manualLibraryId = null;
    _manualMediaType = null;
    _manualFilters.clear();
  }

  int? _lowestFreeNumber() {
    final reusableId = _expectedBase == null ? null : _id;
    final used = widget.controller.channels
        .where((channel) => channel.id != reusableId)
        .map((channel) => channel.number)
        .toSet();
    for (var number = 1; number <= 1000; number++) {
      if (!used.contains(number)) return number;
    }
    return null;
  }

  Channel? get _currentBase => widget.controller.channels
      .where((channel) => channel.id == _id)
      .firstOrNull;

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    _search.dispose();
    _nameFocus.dispose();
    _numberFocus.dispose();
    _saveFocus.dispose();
    _searchFocus.dispose();
    _countAnnouncementTimer?.cancel();
    for (final node in _rundownFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _changed([VoidCallback? change]) => setState(() {
    change?.call();
    _dirty = !_canonicalEquals(_draftSignature, _baselineDraftSignature);
    _success = null;
  });

  Map<String, Object?> get _draftSignature {
    return {
      'name': _name.text.trim(),
      'number': int.tryParse(_number.text) ?? _number.text.trim(),
      'source': _sourceDraftSignature,
      'playbackMode': _playbackMode.name,
      'anchor': _anchor.toIso8601String(),
      'shuffleSeed': _shuffleSeed,
      'blockSize':
          _generated || widget.mode == ChannelStudioMode.duplicateCustom
          ? _blockSize
          : _playbackMode == PlaybackMode.block
          ? (_blockSize ?? 3)
          : null,
      'builderKey': _builderKey,
    };
  }

  Object get _sourceDraftSignature => switch (_sourceChoice) {
    _SourceChoice.library => {
      'type': 'library',
      'libraryId': _libraryId,
      'includeWatched': _includeWatched,
    },
    _SourceChoice.playlist => {'type': 'playlist', 'playlistId': _playlistId},
    _SourceChoice.filter => {
      'type': 'filter',
      'libraryId': _filterLibraryId,
      'includeWatched': _filterIncludeWatched,
      'filters': Map<String, String>.of(_filters),
    },
    _SourceChoice.handPicked => {
      'type': 'manual',
      'ids': List<String>.of(_manualIds),
    },
    null => _source.toJson(),
  };

  void _filterChanged([VoidCallback? change]) {
    _changed(change);
    _scheduleCountAnnouncement();
  }

  void _browseChanged([VoidCallback? change]) {
    setState(change ?? () {});
    _scheduleCountAnnouncement();
  }

  void _scheduleCountAnnouncement() {
    _countAnnouncementTimer?.cancel();
    _countAnnouncementTimer = Timer(_countAnnouncementDelay, () {
      if (!mounted) return;
      setState(() => _settledCountLabel = _countLabel);
    });
  }

  @override
  Widget build(BuildContext context) {
    final noNumber = _lowestFreeNumber() == null && _number.text.trim().isEmpty;
    final saved = !_dirty && _expectedBase != null;
    final number = int.tryParse(_number.text);
    final validNumber = _validateNumber(_number.text) == null;
    final identityLooksValid = _name.text.trim().isNotEmpty && validNumber;
    final programmingError = _programmingError;
    return LineupPage(
      title:
          '${_name.text.trim().isEmpty ? 'New channel' : _name.text.trim()} • ${validNumber ? 'Channel $number' : 'No channel number'} • ${_modeHeaderLabel(_effectiveMode)} • ${_generated ? 'Generated' : 'Custom'}',
      actions: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          TextButton.icon(
            onPressed: _saving ? null : () => unawaited(_leave()),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back to Channels'),
          ),
          if (!_generated)
            TextButton(
              onPressed: _saving ? null : () => unawaited(_leave()),
              child: const Text('Cancel'),
            ),
          if (_generated)
            OutlinedButton(
              onPressed: _saving ? null : _duplicate,
              child: const Text('Duplicate as custom'),
            ),
          if (saved)
            OutlinedButton.icon(
              onPressed: _saving ? null : _tune,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Tune in'),
            ),
          FilledButton(
            focusNode: _saveFocus,
            onPressed:
                _saving ||
                    noNumber ||
                    (identityLooksValid && programmingError != null) ||
                    (identityLooksValid && !_airCheckCanSave) ||
                    (_generated && !_dirty)
                ? null
                : _save,
            child: Text(
              _saving
                  ? 'Saving…'
                  : switch (_effectiveMode) {
                      ChannelStudioMode.editCustom => 'Save changes',
                      ChannelStudioMode.inspectGenerated => 'Save identity',
                      _ => 'Save channel',
                    },
            ),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text(_modeLabel(_effectiveMode))),
                  Chip(label: Text(_generated ? 'Generated' : 'Custom')),
                  Chip(
                    label: Text(
                      _dirty
                          ? 'Unsaved changes'
                          : saved
                          ? 'Saved'
                          : 'Draft',
                    ),
                  ),
                  if (_number.text.trim().isNotEmpty)
                    Chip(label: Text('Channel ${_number.text}')),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                LineupNotice(message: _error!),
              ],
              if (_success != null) ...[
                const SizedBox(height: 12),
                Semantics(liveRegion: true, child: Text(_success!)),
              ],
              if (_saving) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  container: true,
                  label: 'Saving channel',
                  child: const Text('Saving channel…'),
                ),
              ],
              if (noNumber) ...[
                const SizedBox(height: 12),
                const LineupNotice(
                  message: 'No channel numbers are available. Free or renumber a channel from Channels before saving.',
                ),
              ],
              if (_conflict || _baseDeleted) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _saving ? null : _reload,
                      child: Text(
                        _baseDeleted ? 'Reload lineup' : 'Reload channel',
                      ),
                    ),
                    if (_conflict)
                      FilledButton(
                        onPressed: _saving ? null : _confirmReapply,
                        child: const Text('Reapply my changes'),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) => ChannelAirCheck(
                  controller: widget.controller,
                  channel: _previewDraft,
                  originalChannel: _expectedBase,
                  clock: _clock,
                  compact: constraints.maxWidth < LineupLayout.compact,
                  inclusionReason: _sourceLabel(
                    _displaySource,
                    widget.controller,
                  ),
                  sourceIssue: programmingError,
                  onFirstValid: _commitScheduleIdentity,
                  onValidityChanged: (validity) {
                    if (!mounted || _airCheckValidity == validity) return;
                    setState(() {
                      _airCheckValidity = validity;
                      if (validity == ChannelAirCheckValidity.retainedOffAir) {
                        _scheduleIdentityCommitted = true;
                      }
                    });
                  },
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final programming = _programmingCard();
                  final station = _stationCard();
                  return constraints.maxWidth < LineupLayout.compact
                      ? Column(
                          children: [
                            programming,
                            const SizedBox(height: 16),
                            station,
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: programming),
                            const SizedBox(width: 16),
                            Expanded(flex: 2, child: station),
                          ],
                        );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _programmingCard() => LineupSection(
    title: 'Programming',
    children: [
      Text(_sourceLabel(_displaySource, widget.controller)),
      const SizedBox(height: 8),
      if (_sourceReadOnly)
        const Text('Programming is read-only and will be preserved exactly.')
      else ...[
        if (_source is MixedSource && _sourceChoice == null) ...[
          _inventoryStatus(),
          const Text(
            'This mixed source is preserved exactly. Choose a source below only if you want to replace it.',
          ),
          const SizedBox(height: 8),
        ],
        SegmentedButton<_SourceChoice>(
          multiSelectionEnabled: false,
          emptySelectionAllowed: _source is MixedSource,
          segments: const [
            ButtonSegment(value: _SourceChoice.library, label: Text('Library')),
            ButtonSegment(
              value: _SourceChoice.playlist,
              label: Text('Playlist'),
            ),
            ButtonSegment(
              value: _SourceChoice.filter,
              label: Text('Collection or filter'),
            ),
            ButtonSegment(
              value: _SourceChoice.handPicked,
              label: Text('Hand-picked'),
            ),
          ],
          selected: {?_sourceChoice},
          onSelectionChanged: _saving
              ? null
              : (value) => _changed(() => _sourceChoice = value.singleOrNull),
        ),
        const SizedBox(height: 12),
        switch (_sourceChoice) {
          _SourceChoice.library => _libraryEditor(),
          _SourceChoice.playlist => _playlistEditor(),
          _SourceChoice.filter => _filterEditor(),
          _SourceChoice.handPicked => _manualEditor(),
          null => const SizedBox.shrink(),
        },
      ],
    ],
  );

  Widget _libraryEditor() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _inventoryStatus(),
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue:
            widget.controller.libraries.any(
              (library) =>
                  library.id == _libraryId &&
                  widget.controller.selectedLibraryIds.contains(library.id),
            )
            ? _libraryId
            : null,
        decoration: const InputDecoration(labelText: 'Content library'),
        items: [
          for (final library in widget.controller.libraries.where(
            (library) =>
                widget.controller.selectedLibraryIds.contains(library.id),
          ))
            DropdownMenuItem(value: library.id, child: Text(library.title)),
        ],
        onChanged: _saving
            ? null
            : (value) => _changed(() => _libraryId = value),
      ),
      SwitchListTile(
        value: _includeWatched,
        title: const Text('Include watched items'),
        onChanged: _saving
            ? null
            : (value) => _changed(() => _includeWatched = value),
      ),
    ],
  );

  Widget _playlistEditor() {
    final available = widget.controller.playableInventory.playlists;
    final selected = available.any((playlist) => playlist.id == _playlistId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _inventoryStatus(),
        if (_playlistId != null && !selected)
          Text(
            'Playlist $_playlistId is unavailable — retained until replaced.',
          ),
        DropdownButtonFormField<String>(
          key: const Key('studio-playlist'),
          isExpanded: true,
          initialValue: selected ? _playlistId : null,
          decoration: const InputDecoration(labelText: 'Video playlist'),
          items: [
            for (final playlist in available)
              DropdownMenuItem(value: playlist.id, child: Text(playlist.title)),
          ],
          onChanged: _saving
              ? null
              : (value) => _changed(() => _playlistId = value),
        ),
      ],
    );
  }

  Widget _filterEditor() {
    final facets = _facetOptions(_filterLibraryId);
    final matches = _filteredInventory(
      libraryId: _filterLibraryId,
      filters: _filters,
      includeWatched: _filterIncludeWatched,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _inventoryStatus(),
        _libraryDropdown(
          key: const Key('studio-filter-library'),
          value: _filterLibraryId,
          onChanged: (value) => _filterChanged(() {
            _filterLibraryId = value;
            _filters.clear();
          }),
        ),
        for (final key in _facetKeys)
          _facetDropdown(
            key: key,
            values: facets[key] ?? const [],
            selected: _filters[key],
            onChanged: (value) => _filterChanged(() {
              if (value == null) {
                _filters.remove(key);
              } else {
                _filters[key] = value;
              }
            }),
          ),
        SwitchListTile(
          key: const Key('studio-filter-include-watched'),
          value: _filterIncludeWatched,
          title: const Text('Include watched items'),
          onChanged: _saving
              ? null
              : (value) => _filterChanged(() => _filterIncludeWatched = value),
        ),
        SwitchListTile(
          key: const Key('studio-newest-first'),
          value: _filters['sort'] == 'added:desc',
          title: const Text('Newest first'),
          onChanged: _saving
              ? null
              : (value) => _filterChanged(() {
                  if (value) {
                    _filters['sort'] = 'added:desc';
                  } else {
                    _filters.remove('sort');
                  }
                }),
        ),
        Text('${matches.length} matching programs'),
        for (final item in matches.take(5)) Text(item.title),
        if (matches.length > 5)
          Text('Showing 5 of ${matches.length} matching programs.'),
      ],
    );
  }

  Widget _manualEditor() {
    final visible = _manualMatches;
    final shown = visible.take(_resultWindow).toList(growable: false);
    final unavailable = _manualIds
        .where((id) => !_inventoryById.containsKey(id))
        .toList(growable: false);
    _pruneRundownFocus();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _inventoryStatus(),
        TextField(
          key: const Key('studio-search'),
          controller: _search,
          focusNode: _searchFocus,
          enabled: !_saving,
          decoration: const InputDecoration(
            labelText: 'Search title or show title',
          ),
          onChanged: (_) => _browseChanged(),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 220,
              child: _libraryDropdown(
                key: const Key('studio-manual-library'),
                value: _manualLibraryId,
                allowAll: true,
                onChanged: (value) =>
                    _browseChanged(() => _manualLibraryId = value),
              ),
            ),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                key: const Key('studio-media-type'),
                isExpanded: true,
                initialValue: _manualMediaType,
                decoration: const InputDecoration(labelText: 'Media type'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('All types')),
                  for (final type
                      in _inventory.map((item) => item.type).toSet())
                    DropdownMenuItem(value: type, child: Text(type)),
                ],
                onChanged: _saving
                    ? null
                    : (value) => _browseChanged(
                        () => _manualMediaType = value?.isEmpty == true
                            ? null
                            : value,
                      ),
              ),
            ),
          ],
        ),
        for (final key in _facetKeys)
          _facetDropdown(
            key: key,
            values: _facetOptions(_manualLibraryId)[key] ?? const [],
            selected: _manualFilters[key],
            onChanged: (value) => _browseChanged(() {
              if (value == null) {
                _manualFilters.remove(key);
              } else {
                _manualFilters[key] = value;
              }
            }),
          ),
        Text(_countLabel),
        if (_settledCountLabel.isNotEmpty)
          Semantics(
            liveRegion: true,
            label: _settledCountLabel,
            child: const SizedBox.shrink(),
          ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed:
                  _saving || !shown.any((item) => !_manualIds.contains(item.id))
                  ? null
                  : _selectVisible,
              child: const Text('Select visible'),
            ),
            TextButton(
              onPressed:
                  _saving || !shown.any((item) => _manualIds.contains(item.id))
                  ? null
                  : _clearVisible,
              child: const Text('Clear visible'),
            ),
          ],
        ),
        if (visible.length > _resultWindow)
          Text(
            'Showing the first $_resultWindow of ${visible.length} matches. Narrow the filters to see more.',
          ),
        SizedBox(
          height: 240,
          child: ListView.builder(
            key: const Key('studio-results'),
            itemCount: shown.length,
            itemBuilder: (context, index) {
              final item = shown[index];
              return CheckboxListTile(
                key: Key('studio-result-${item.id}'),
                value: _manualIds.contains(item.id),
                title: Text(item.title),
                subtitle: item.grandparentTitle == null
                    ? null
                    : Text(item.grandparentTitle!),
                onChanged: _saving
                    ? null
                    : (selected) => _toggleManual(item.id, selected == true),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Selected programming',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        if (_manualIds.isEmpty) const Text('No programs selected.'),
        SizedBox(
          height: _manualIds.isEmpty ? 0 : 240,
          child: ListView.builder(
            key: const Key('studio-rundown'),
            itemCount: _manualIds.length,
            itemBuilder: (context, index) => _rundownRow(
              _manualIds[index],
              index,
              unavailable.contains(_manualIds[index]),
            ),
          ),
        ),
      ],
    );
  }

  void _toggleManual(String id, bool selected) => _changed(() {
    if (selected && !_manualIds.contains(id)) {
      _manualIds.add(id);
      if (_inventoryById[id] case final item?) {
        _retainedManualItems[id] = channelItemFor(item);
      }
    } else if (!selected) {
      _manualIds.remove(id);
      _retainedManualItems.remove(id);
    }
    _settledCountLabel = '';
    _scheduleCountAnnouncement();
  });

  List<PlexMediaItem> get _inventory {
    final playable = widget.controller.playableInventory;
    final byId = <String, PlexMediaItem>{};
    for (final item in playable.media) {
      byId.putIfAbsent(item.id, () => item);
    }
    for (final playlist in playable.playlists) {
      for (final item in playlist.items) {
        byId.putIfAbsent(item.id, () => item);
      }
    }
    return byId.values.toList(growable: false);
  }

  Map<String, PlexMediaItem> get _inventoryById => {
    for (final item in _inventory) item.id: item,
  };

  List<PlexLibrary> get _selectedLibraries => widget.controller.libraries
      .where(
        (library) => widget.controller.selectedLibraryIds.contains(library.id),
      )
      .toList(growable: false);

  Widget _inventoryStatus() {
    final status = widget.controller.libraryScanStatus;
    if (status == LibraryScanStatus.scanning) {
      final total = widget.controller.libraryScanTotalItems;
      return Semantics(
        key: const Key('studio-inventory-status'),
        liveRegion: true,
        container: true,
        child: Text(
          total == null
              ? 'Loading programming: ${widget.controller.libraryScanCompletedItems} items loaded.'
              : 'Loading programming: ${widget.controller.libraryScanCompletedItems} of $total items loaded.',
        ),
      );
    }
    if (status == LibraryScanStatus.cancelled ||
        status == LibraryScanStatus.transientFailure) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            key: const Key('studio-inventory-status'),
            liveRegion: true,
            container: true,
            child: Text(
              status == LibraryScanStatus.cancelled
                  ? 'Library loading was cancelled. The last usable programming and this draft were preserved.'
                  : 'Library loading failed. The last usable programming and this draft were preserved.',
            ),
          ),
          TextButton(
            onPressed: _saving ? null : _openGenerateLineup,
            child: const Text('Retry in Generate lineup'),
          ),
        ],
      );
    }
    if (_inventory.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'No usable programming is loaded. A new channel needs a selected Plex movie/show library or video playlist.',
          ),
          TextButton(
            onPressed: _saving ? null : _openGenerateLineup,
            child: const Text('Open Generate lineup'),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _openGenerateLineup() async {
    await widget.onOpenGenerateLineup();
  }

  Widget _libraryDropdown({
    required Key key,
    required String? value,
    required ValueChanged<String?> onChanged,
    bool allowAll = false,
  }) {
    final selected = _selectedLibraries.any((library) => library.id == value);
    return DropdownButtonFormField<String>(
      key: key,
      isExpanded: true,
      initialValue: selected
          ? value
          : allowAll
          ? ''
          : null,
      decoration: const InputDecoration(labelText: 'Library'),
      items: [
        if (allowAll)
          const DropdownMenuItem(value: '', child: Text('All libraries')),
        for (final library in _selectedLibraries)
          DropdownMenuItem(value: library.id, child: Text(library.title)),
      ],
      onChanged: _saving
          ? null
          : (value) => onChanged(value?.isEmpty == true ? null : value),
    );
  }

  Widget _facetDropdown({
    required String key,
    required List<String> values,
    required String? selected,
    required ValueChanged<String?> onChanged,
  }) => DropdownButtonFormField<String>(
    key: Key('studio-facet-$key'),
    isExpanded: true,
    initialValue: selected,
    decoration: InputDecoration(labelText: _facetLabel(key)),
    items: [
      const DropdownMenuItem(value: '', child: Text('Any')),
      if (selected != null && !values.contains(selected))
        DropdownMenuItem(
          value: selected,
          child: Text('$selected (unavailable — retained)'),
        ),
      for (final value in values)
        DropdownMenuItem(value: value, child: Text(value)),
    ],
    onChanged: _saving
        ? null
        : (value) => onChanged(value?.isEmpty == true ? null : value),
  );

  Map<String, List<String>> _facetOptions(String? libraryId) {
    final values = {for (final key in _facetKeys) key: <String>{}};
    for (final item in _inventory.where(
      (item) => libraryId == null || item.libraryId == libraryId,
    )) {
      values['collection']!.addAll(item.collections);
      values['genre']!.addAll(item.genres);
      if (item.studio case final studio? when studio.isNotEmpty) {
        values['studio']!.add(studio);
      }
      values['actor']!.addAll(item.actors);
      values['director']!.addAll(item.directors);
      if (item.year case final year?) {
        values['decade']!.add('${year ~/ 10 * 10}s');
      }
    }
    return {
      for (final entry in values.entries)
        entry.key: entry.value.toList()..sort(),
    };
  }

  List<PlexMediaItem> _filteredInventory({
    String? libraryId,
    String? mediaType,
    Map<String, String> filters = const {},
    String search = '',
    bool includeWatched = true,
  }) {
    final query = search.trim().toLowerCase();
    var items = _inventory.where(
      (item) =>
          (libraryId == null || item.libraryId == libraryId) &&
          (includeWatched || !item.viewed) &&
          (mediaType == null || item.type == mediaType) &&
          (query.isEmpty ||
              item.title.toLowerCase().contains(query) ||
              (item.grandparentTitle?.toLowerCase().contains(query) ?? false)),
    );
    for (final filter in filters.entries) {
      items = switch (filter.key) {
        'collection' => items.where(
          (item) => item.collections.contains(filter.value),
        ),
        'genre' => items.where((item) => item.genres.contains(filter.value)),
        'studio' => items.where((item) => item.studio == filter.value),
        'actor' => items.where((item) => item.actors.contains(filter.value)),
        'director' => items.where(
          (item) => item.directors.contains(filter.value),
        ),
        'decade' => items.where(
          (item) =>
              item.year != null && '${item.year! ~/ 10 * 10}s' == filter.value,
        ),
        'sort' when filter.value == 'added:desc' =>
          items.toList()..sort(
            (left, right) =>
                (right.addedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                    .compareTo(
                      left.addedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
                    ),
          ),
        _ => const Iterable<PlexMediaItem>.empty(),
      };
    }
    return items.toList(growable: false);
  }

  List<PlexMediaItem> get _manualMatches => _filteredInventory(
    libraryId: _manualLibraryId,
    mediaType: _manualMediaType,
    filters: _manualFilters,
    search: _search.text,
  );

  String get _countLabel =>
      '${_manualMatches.length} matching, ${_manualIds.length} selected';

  List<PlexMediaItem> get _renderedManualMatches =>
      _manualMatches.take(_resultWindow).toList(growable: false);

  void _selectVisible() => _changed(() {
    for (final item in _renderedManualMatches) {
      if (!_manualIds.contains(item.id)) {
        _manualIds.add(item.id);
        _retainedManualItems[item.id] = channelItemFor(item);
      }
    }
    _settledCountLabel = '';
    _scheduleCountAnnouncement();
  });

  void _clearVisible() {
    final visibleIds = _renderedManualMatches.map((item) => item.id).toSet();
    _changed(() {
      _manualIds.removeWhere(visibleIds.contains);
      _retainedManualItems.removeWhere((id, _) => visibleIds.contains(id));
      _settledCountLabel = '';
      _scheduleCountAnnouncement();
    });
  }

  Widget _rundownRow(String id, int index, bool unavailable) {
    final current = _inventoryById[id];
    final retained = _retainedManualItems[id];
    final title = current?.title ?? retained?.title ?? id;
    final focus = _rundownFocus.putIfAbsent(
      id,
      () => FocusNode(debugLabel: 'Selected program $title'),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () =>
            _moveManual(id, -1),
        const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): () =>
            _moveManual(id, 1),
        const SingleActivator(LogicalKeyboardKey.delete): () =>
            _removeManual(id),
      },
      child: Focus(
        focusNode: focus,
        child: ListTile(
          key: Key('studio-rundown-$id'),
          title: Text(title),
          subtitle: unavailable
              ? const Text('Unavailable — retained until removed')
              : Text('${index + 1} of ${_manualIds.length}'),
          trailing: Wrap(
            spacing: 4,
            children: [
              IconButton(
                tooltip: 'Move $title earlier in $_draftChannelLabel',
                onPressed: _saving || index == 0
                    ? null
                    : () => _moveManual(id, -1),
                icon: const Icon(Icons.arrow_upward),
              ),
              IconButton(
                tooltip: 'Move $title later in $_draftChannelLabel',
                onPressed: _saving || index == _manualIds.length - 1
                    ? null
                    : () => _moveManual(id, 1),
                icon: const Icon(Icons.arrow_downward),
              ),
              IconButton(
                tooltip: 'Remove $title from $_draftChannelLabel',
                onPressed: _saving ? null : () => _removeManual(id),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _draftChannelLabel => _name.text.trim().isEmpty
      ? 'new channel'
      : 'channel ${_name.text.trim()}';

  void _moveManual(String id, int delta) {
    if (_saving) return;
    final from = _manualIds.indexOf(id);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= _manualIds.length) return;
    _changed(() {
      _manualIds.removeAt(from);
      _manualIds.insert(to, id);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rundownFocus[id]?.requestFocus();
    });
  }

  void _removeManual(String id) {
    if (_saving) return;
    final index = _manualIds.indexOf(id);
    if (index < 0) return;
    _changed(() {
      _manualIds.removeAt(index);
      _retainedManualItems.remove(id);
    });
    final nextId = _manualIds.isEmpty
        ? null
        : _manualIds[index.clamp(0, _manualIds.length - 1)];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (nextId == null) {
        _searchFocus.requestFocus();
      } else {
        _rundownFocus[nextId]?.requestFocus();
      }
    });
  }

  void _pruneRundownFocus() {
    final removed = _rundownFocus.keys
        .where((id) => !_manualIds.contains(id))
        .toList(growable: false);
    for (final id in removed) {
      _rundownFocus.remove(id)?.dispose();
    }
  }

  Widget _stationCard() => LineupSection(
    title: 'Station',
    children: [
      TextFormField(
        key: const Key('studio-name'),
        controller: _name,
        focusNode: _nameFocus,
        autofocus: true,
        enabled: !_saving,
        decoration: const InputDecoration(
          labelText: 'Channel name',
          hintText: 'Required',
        ),
        onChanged: (_) => _changed(),
        validator: (value) => value == null || value.trim().isEmpty
            ? 'Enter a channel name.'
            : null,
      ),
      const SizedBox(height: 12),
      TextFormField(
        key: const Key('studio-number'),
        controller: _number,
        focusNode: _numberFocus,
        enabled: !_saving,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Channel number (1–1000)'),
        onChanged: (_) => _changed(),
        validator: _validateNumber,
      ),
      if (_conflictingChannel != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _saving || _lowestFreeNumber() == null
                ? null
                : _useNextAvailable,
            child: const Text('Use next available'),
          ),
        ),
      const SizedBox(height: 12),
      InputDecorator(
        decoration: InputDecoration(
          labelText: _generated
              ? 'Playback rhythm (read-only)'
              : 'Playback rhythm',
        ),
        child: _generated
            ? Text(_rhythmLabel(_playbackMode, _blockSize))
            : SegmentedButton<PlaybackMode>(
                segments: const [
                  ButtonSegment(
                    value: PlaybackMode.sequential,
                    label: Text('In order'),
                  ),
                  ButtonSegment(
                    value: PlaybackMode.shuffle,
                    label: Text('Mix it up'),
                  ),
                  ButtonSegment(
                    value: PlaybackMode.block,
                    label: Text('Mini-marathons'),
                  ),
                ],
                selected: {_playbackMode},
                onSelectionChanged: _saving
                    ? null
                    : (value) => _changed(() {
                        _playbackMode = value.single;
                        _blockSize ??= 3;
                      }),
              ),
      ),
      if (_generated) ...[
        const SizedBox(height: 12),
        Text(
          'Generator recipe: ${_sourceLabel(_source, widget.controller)}. Schedule timing stays the same.',
        ),
      ] else if (_playbackMode == PlaybackMode.block) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          key: const Key('studio-block-size'),
          isExpanded: true,
          initialValue: (_blockSize ?? 3) >= 2 && (_blockSize ?? 3) <= 5
              ? _blockSize ?? 3
              : null,
          decoration: const InputDecoration(labelText: 'Episodes per show'),
          items: [
            for (var size = 2; size <= 5; size++)
              DropdownMenuItem(value: size, child: Text('$size')),
          ],
          onChanged: _saving
              ? null
              : (value) => _changed(() => _blockSize = value),
        ),
        if (!_hasShowGrouping)
          const Text(
            'Mini-marathons needs episodes grouped by show title or show artwork. Choose another rhythm or add grouped episodes.',
          ),
      ],
    ],
  );

  Channel? get _conflictingChannel {
    final number = int.tryParse(_number.text);
    if (number == null) return null;
    return widget.controller.channels
        .where((channel) => channel.id != _id && channel.number == number)
        .firstOrNull;
  }

  String? _validateNumber(String? value) {
    final number = int.tryParse(value ?? '');
    if (number == null || number < 1 || number > 1000) {
      return 'Enter a number from 1 to 1000.';
    }
    final conflict = _conflictingChannel;
    return conflict == null
        ? null
        : 'Channel $number is already used by ${conflict.name}.';
  }

  void _useNextAvailable() {
    final next = _lowestFreeNumber();
    if (next == null) return;
    _changed(() {
      _number.text = '$next';
    });
  }

  Future<void> _leave() async {
    await widget.onBack(_expectedBase?.id ?? widget.channel?.id);
  }

  void _duplicate() {
    final source = Channel(
      id: _id,
      number: int.tryParse(_number.text) ?? widget.channel!.number,
      name: _name.text.trim(),
      source: _source,
      playbackMode: _playbackMode,
      anchor: _anchor,
      shuffleSeed: _shuffleSeed,
      blockSize: _blockSize,
      builderKey: _builderKey,
    );
    widget.onDuplicate(source);
  }

  ContentSource _editedSource() {
    if (_sourceReadOnly) return _source;
    return switch (_sourceChoice) {
      _SourceChoice.library => _librarySource(_libraryId),
      _SourceChoice.playlist =>
        _playlistId == null
            ? throw const FormatException('Select a playlist.')
            : PlaylistSource(_playlistId!),
      _SourceChoice.filter => _librarySource(
        _filterLibraryId,
        filters: Map.unmodifiable(_filters),
      ),
      _SourceChoice.handPicked => ManualSource(_manualItems()),
      null => _source,
    };
  }

  List<ChannelItem> _manualItems() {
    final available = _inventoryById;
    return _manualIds
        .map((id) {
          final item = available[id];
          return item == null ? _retainedManualItems[id] : channelItemFor(item);
        })
        .nonNulls
        .toList(growable: false);
  }

  LibrarySource _librarySource(
    String? id, {
    Map<String, String> filters = const {},
  }) {
    final library = _selectedLibraries
        .where((library) => library.id == id)
        .firstOrNull;
    if (library == null) throw const FormatException('Select a library.');
    return LibrarySource(
      libraryId: library.id,
      libraryType: library.type,
      includeWatched: _sourceChoice == _SourceChoice.library
          ? _includeWatched
          : _filterIncludeWatched,
      filters: filters,
    );
  }

  List<ChannelItem> get _resolvedDraftContent {
    try {
      return resolveContent(
        _editedSource(),
        _inventory,
        widget.controller.playableInventory.playlists,
      );
    } on FormatException {
      return const [];
    }
  }

  bool get _hasShowGrouping => _resolvedDraftContent.any(
    (item) =>
        item.showTitle?.trim().isNotEmpty == true ||
        item.showThumb?.trim().isNotEmpty == true,
  );

  String? get _programmingError {
    if (_generated) return null;
    ContentSource source;
    try {
      source = _editedSource();
    } on FormatException catch (error) {
      return error.message;
    }
    final liveSourceError = _liveSourceError(source);
    if (liveSourceError != null) return liveSourceError;
    List<ChannelItem> resolved;
    try {
      resolved = resolveContent(
        source,
        _inventory,
        widget.controller.playableInventory.playlists,
      );
    } on FormatException {
      return 'This source contains an unsupported filter and cannot be broadened. Choose a supported replacement.';
    }
    switch (source) {
      case ManualSource(:final items):
        if (items.isEmpty) return 'Select at least one program.';
      case MixedSource():
        if (resolved.isEmpty && !_hasRetainedContent(source)) {
          return 'This preserved mixed source has no currently playable programs. Choose a replacement source.';
        }
      case LibrarySource() || PlaylistSource():
        break;
    }
    if (_playbackMode == PlaybackMode.block && !_hasShowGrouping) {
      return 'Mini-marathons needs episodes grouped by show title or show artwork.';
    }
    if (_playbackMode == PlaybackMode.block &&
        ((_blockSize ?? 3) < 2 || (_blockSize ?? 3) > 5)) {
      return 'Choose a mini-marathon size from 2 to 5.';
    }
    return null;
  }

  String? _liveSourceError(ContentSource source) {
    switch (source) {
      case LibrarySource(:final libraryId):
        if (!_selectedLibraries.any((library) => library.id == libraryId)) {
          return 'The saved library is unavailable. Choose a selected Plex library.';
        }
        try {
          if (resolveContent(
            source,
            _inventory,
            widget.controller.playableInventory.playlists,
          ).isEmpty) {
            return 'This library and its filters match no playable programs. Choose a replacement source.';
          }
        } on FormatException {
          return 'This source contains an unsupported filter. Choose a supported replacement.';
        }
      case PlaylistSource(:final playlistId):
        if (!widget.controller.playableInventory.playlists.any(
          (playlist) => playlist.id == playlistId,
        )) {
          return 'The saved playlist is unavailable. Choose an available video playlist.';
        }
        if (resolveContent(
          source,
          _inventory,
          widget.controller.playableInventory.playlists,
        ).isEmpty) {
          return 'This playlist has no playable programs. Choose another playlist.';
        }
      case MixedSource(:final sources):
        for (final child in sources) {
          if (_liveSourceError(child) case final error?) return error;
        }
      case ManualSource():
        break;
    }
    return null;
  }

  bool _hasRetainedContent(ContentSource source) => switch (source) {
    ManualSource(:final items) => items.isNotEmpty,
    MixedSource(:final sources) => sources.any(_hasRetainedContent),
    LibrarySource() || PlaylistSource() => false,
  };

  Channel _draft() => Channel(
    id: _id,
    number: int.parse(_number.text),
    name: _name.text.trim(),
    source: _editedSource(),
    playbackMode: _playbackMode,
    anchor: _anchor,
    shuffleSeed: _shuffleSeed,
    blockSize: _generated
        ? _blockSize
        : widget.mode == ChannelStudioMode.duplicateCustom
        ? _blockSize
        : _playbackMode == PlaybackMode.block
        ? (_blockSize ?? 3)
        : null,
    builderKey: _builderKey,
  );

  Channel get _previewDraft => Channel(
    id: _id,
    number: int.tryParse(_number.text) ?? 1,
    name: _name.text.trim().isEmpty ? 'New channel' : _name.text.trim(),
    source: _displaySource,
    playbackMode: _playbackMode,
    anchor: _anchor,
    shuffleSeed: _shuffleSeed,
    blockSize: _generated
        ? _blockSize
        : widget.mode == ChannelStudioMode.duplicateCustom
        ? _blockSize
        : _playbackMode == PlaybackMode.block
        ? (_blockSize ?? 3)
        : null,
    builderKey: _builderKey,
  );

  bool get _airCheckCanSave =>
      _airCheckValidity == ChannelAirCheckValidity.valid ||
      _airCheckValidity == ChannelAirCheckValidity.retainedOffAir;

  void _commitScheduleIdentity() {
    if (_scheduleIdentityCommitted || !mounted) return;
    setState(() => _scheduleIdentityCommitted = true);
  }

  Future<void> _save({Channel? rebasedExpected}) async {
    final valid = _form.currentState?.validate() ?? false;
    if (!valid) {
      setState(
        () => _error =
            'Fix the highlighted channel identity fields before saving.',
      );
      if (_name.text.trim().isEmpty) {
        _nameFocus.requestFocus();
      } else {
        _numberFocus.requestFocus();
      }
      return;
    }
    if (_programmingError != null) {
      return;
    }
    if (!_airCheckCanSave || !_scheduleIdentityCommitted) {
      setState(
        () => _error = 'Air Check must verify this schedule before the channel can be saved.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
      _conflict = false;
      _baseDeleted = false;
    });
    try {
      final draft = _draft();
      await widget.controller.saveChannel(
        draft,
        expectedBase: rebasedExpected ?? _expectedBase,
      );
      if (!mounted) return;
      setState(() {
        _expectedBase = draft;
        _source = draft.source;
        _dirty = false;
        _baselineDraftSignature = _draftSignature;
        _saving = false;
        _generated = draft.builderKey != null;
        _success = 'Channel saved.';
      });
      widget.onSaved(draft.id);
    } catch (error) {
      if (!mounted) return;
      final current = _currentBase;
      final stale =
          _expectedBase != null &&
          (current == null ||
              !_canonicalEquals(current.toJson(), _expectedBase!.toJson()));
      setState(() {
        _saving = false;
        _baseDeleted = stale && current == null;
        _conflict = stale && current != null;
        _error = _baseDeleted
            ? 'This channel was deleted while you were editing. It will not be recreated.'
            : _conflict
            ? 'This channel changed while you were editing. Reload it or deliberately reapply your changes.'
            : safeFormError(
                error,
                'The channel could not be saved. No lineup changes were saved.',
              );
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _saveFocus.requestFocus();
      });
    }
  }

  ContentSource get _displaySource {
    try {
      return _editedSource();
    } on FormatException {
      return _source;
    }
  }

  void _reload() {
    final current = _currentBase;
    if (current == null) {
      unawaited(widget.onBack(null));
      return;
    }
    _name.text = current.name;
    _number.text = '${current.number}';
    setState(() {
      _source = current.source;
      _playbackMode = current.playbackMode;
      _anchor = current.anchor;
      _shuffleSeed = current.shuffleSeed;
      _blockSize = current.blockSize;
      _builderKey = current.builderKey;
      _expectedBase = current;
      _configureSource(current.source);
      _dirty = false;
      _baselineDraftSignature = _draftSignature;
      _conflict = false;
      _baseDeleted = false;
      _error = null;
      _success = null;
    });
  }

  Future<void> _confirmReapply() async {
    final current = _currentBase;
    if (current == null) {
      setState(() {
        _conflict = false;
        _baseDeleted = true;
        _error = 'This channel was deleted while you were editing. It will not be recreated.';
      });
      return;
    }
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Reapply your changes?'),
            content: const Text(
              'This will replace the newer channel with your complete Studio draft.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Reapply changes'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed && mounted) await _save(rebasedExpected: current);
  }

  Future<void> _tune() async {
    setState(() {
      _error = null;
      _success = null;
    });
    if (await widget.onTune(_id) || !mounted) return;
    setState(
      () => _error =
          'The saved channel could not be tuned. Your lineup is unchanged.',
    );
  }
}

bool _canonicalEquals(Object? left, Object? right) {
  if (left is Map && right is Map) {
    return left.length == right.length &&
        left.entries.every(
          (entry) =>
              right.containsKey(entry.key) &&
              _canonicalEquals(entry.value, right[entry.key]),
        );
  }
  if (left is List && right is List) {
    return left.length == right.length &&
        Iterable<int>.generate(left.length)
            .every((index) => _canonicalEquals(left[index], right[index]));
  }
  return left == right;
}

String channelSourceLabel(ContentSource source, LineupController controller) =>
    _sourceLabel(source, controller);

String _sourceLabel(
  ContentSource source,
  LineupController controller,
) => switch (source) {
  LibrarySource(:final libraryId, :final includeWatched, :final filters) => [
    'Library: ${controller.libraries.where((library) => library.id == libraryId).firstOrNull?.title ?? libraryId}',
    for (final filter in filters.entries) ?_filterFact(filter),
    includeWatched ? 'includes watched' : 'unwatched only',
  ].join(' • '),
  ManualSource(:final items) => '${items.length} hand-picked programs',
  PlaylistSource(:final playlistId) =>
    'Playlist: ${controller.availablePlaylists.where((playlist) => playlist.id == playlistId).firstOrNull?.title ?? playlistId}',
  MixedSource(:final sources, :final interleave) =>
    '${sources.length}-source mix • ${interleave ? 'interleaved' : 'in sequence'}',
};

String? _filterFact(MapEntry<String, String> filter) => switch (filter) {
  MapEntry(key: 'collection', :final value) => 'Collection: $value',
  MapEntry(key: 'genre', :final value) => 'Genre: $value',
  MapEntry(key: 'studio', :final value) => 'Studio: $value',
  MapEntry(key: 'actor', :final value) => 'Actor: $value',
  MapEntry(key: 'director', :final value) => 'Director: $value',
  MapEntry(key: 'decade', :final value) => 'Decade: $value',
  MapEntry(key: 'sort', value: 'added:desc') => 'Newest first',
  _ => null,
};

String channelRhythmLabel(PlaybackMode mode, int? blockSize) =>
    _rhythmLabel(mode, blockSize);

String _rhythmLabel(PlaybackMode mode, [int? blockSize]) => switch (mode) {
  PlaybackMode.sequential => 'In order',
  PlaybackMode.shuffle => 'Mix it up',
  PlaybackMode.block => 'Mini-marathons of ${blockSize ?? 3}',
};

String _modeLabel(ChannelStudioMode mode) => switch (mode) {
  ChannelStudioMode.createCustom => 'Create custom channel',
  ChannelStudioMode.editCustom => 'Edit custom channel',
  ChannelStudioMode.inspectGenerated => 'Inspect generated channel',
  ChannelStudioMode.duplicateCustom => 'Duplicate as custom',
};

String _modeHeaderLabel(ChannelStudioMode mode) => switch (mode) {
  ChannelStudioMode.createCustom => 'Create',
  ChannelStudioMode.editCustom => 'Edit',
  ChannelStudioMode.inspectGenerated => 'Inspect',
  ChannelStudioMode.duplicateCustom => 'Duplicate',
};
