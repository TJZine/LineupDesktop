import 'dart:async';

import 'package:flutter/material.dart';

import '../channels/channel.dart';
import '../channels/content_resolver.dart';
import '../ui/app_ui.dart';
import 'form_error.dart';
import 'lineup_controller.dart';

enum ChannelStudioMode {
  createCustom,
  editCustom,
  inspectGenerated,
  duplicateCustom,
}

class ChannelStudioView extends StatefulWidget {
  const ChannelStudioView({
    required this.controller,
    required this.mode,
    required this.onBack,
    required this.onSaved,
    required this.onTune,
    required this.onDuplicate,
    this.channel,
    super.key,
  });

  final LineupController controller;
  final ChannelStudioMode mode;
  final Channel? channel;
  final Future<void> Function(String? focusChannelId) onBack;
  final ValueChanged<String> onSaved;
  final Future<bool> Function(String channelId) onTune;
  final ValueChanged<Channel> onDuplicate;

  @override
  State<ChannelStudioView> createState() => ChannelStudioViewState();
}

class ChannelStudioViewState extends State<ChannelStudioView> {
  final _form = GlobalKey<FormState>();
  final _nameFocus = FocusNode(debugLabel: 'Channel name');
  final _numberFocus = FocusNode(debugLabel: 'Channel number');
  final _saveFocus = FocusNode(debugLabel: 'Save channel');
  late final TextEditingController _name;
  late final TextEditingController _number;
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
  late bool _manual;
  late List<String> _manualIds;
  late Map<String, ChannelItem> _retainedManualItems;
  late String? _libraryId;
  late bool _includeWatched;
  bool _dirty = false;
  bool _saving = false;
  bool _conflict = false;
  bool _baseDeleted = false;
  String? _error;
  String? _success;

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
    _source = original?.source ?? _defaultSource();
    _playbackMode = original?.playbackMode ?? PlaybackMode.shuffle;
    _anchor = original?.anchor ?? DateTime.now().toUtc();
    _shuffleSeed = original?.shuffleSeed ?? _id.hashCode;
    _blockSize = original?.blockSize;
    _builderKey = _generated ? original!.builderKey : null;
    _configureSource(_source);
  }

  ContentSource _defaultSource() {
    final library = widget.controller.libraries
        .where((item) => widget.controller.selectedLibraryIds.contains(item.id))
        .firstOrNull;
    return library == null
        ? const ManualSource([])
        : LibrarySource(libraryId: library.id, libraryType: library.type);
  }

  void _configureSource(ContentSource source) {
    _sourceReadOnly =
        _generated ||
        switch (source) {
          LibrarySource(:final filters) => filters.isNotEmpty,
          PlaylistSource() || MixedSource() => true,
          _ => false,
        };
    _manual = source is ManualSource;
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
    _nameFocus.dispose();
    _numberFocus.dispose();
    _saveFocus.dispose();
    super.dispose();
  }

  void _changed([VoidCallback? change]) => setState(() {
    change?.call();
    _dirty = true;
    _success = null;
  });

  @override
  Widget build(BuildContext context) {
    final noNumber = _lowestFreeNumber() == null && _number.text.trim().isEmpty;
    final saved = !_dirty && _expectedBase != null;
    final number = int.tryParse(_number.text);
    final validNumber = _validateNumber(_number.text) == null;
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
            onPressed: _saving || noNumber || (_generated && !_dirty)
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
      Text(_sourceLabel(_source, widget.controller)),
      const SizedBox(height: 8),
      if (_sourceReadOnly)
        const Text('Programming is read-only and will be preserved exactly.')
      else ...[
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Entire library')),
            ButtonSegment(value: true, label: Text('Hand-picked')),
          ],
          selected: {_manual},
          onSelectionChanged: _saving
              ? null
              : (value) => _changed(() => _manual = value.single),
        ),
        const SizedBox(height: 12),
        if (!_manual) _libraryEditor() else _manualEditor(),
      ],
    ],
  );

  Widget _libraryEditor() => Column(
    children: [
      DropdownButtonFormField<String>(
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

  Widget _manualEditor() {
    final availableById = {
      for (final item in widget.controller.availableMedia) item.id: item,
    };
    final unavailable = _manualIds
        .where((id) => !availableById.containsKey(id))
        .toList();
    return SizedBox(
      height: 260,
      child: ListView(
        children: [
          for (final id in unavailable)
            CheckboxListTile(
              value: true,
              title: Text(_retainedManualItems[id]?.title ?? id),
              subtitle: const Text('Unavailable — retained until removed'),
              onChanged: _saving ? null : (_) => _toggleManual(id, false),
            ),
          for (final item in widget.controller.availableMedia)
            CheckboxListTile(
              value: _manualIds.contains(item.id),
              title: Text(item.title),
              subtitle: item.grandparentTitle == null
                  ? null
                  : Text(item.grandparentTitle!),
              onChanged: _saving
                  ? null
                  : (selected) => _toggleManual(item.id, selected == true),
            ),
        ],
      ),
    );
  }

  void _toggleManual(String id, bool selected) => _changed(() {
    if (selected && !_manualIds.contains(id)) {
      _manualIds.add(id);
    } else if (!selected) {
      _manualIds.remove(id);
    }
  });

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
    if (_manual) {
      final available = {
        for (final item in widget.controller.availableMedia)
          item.id: channelItemFor(item),
      };
      final items = [
        for (final id in _manualIds)
          ?(available[id] ?? _retainedManualItems[id]),
      ];
      if (items.isEmpty) {
        throw const FormatException('Select at least one program.');
      }
      return ManualSource(items);
    }
    final library = widget.controller.libraries
        .where(
          (item) =>
              item.id == _libraryId &&
              widget.controller.selectedLibraryIds.contains(item.id),
        )
        .firstOrNull;
    if (library == null) throw const FormatException('Select a library.');
    return LibrarySource(
      libraryId: library.id,
      libraryType: library.type,
      includeWatched: _includeWatched,
    );
  }

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
        _dirty = false;
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
