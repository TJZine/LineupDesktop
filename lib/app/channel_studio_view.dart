import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channels/channel.dart';
import '../channels/content_resolver.dart';
import '../plex/plex_models.dart';
import '../ui/app_theme.dart';
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

typedef _DraftResolution = ({
  ContentSource? source,
  List<ChannelItem>? content,
  String? sourceError,
});

typedef _FacetOptions = ({
  Map<String, List<String>> values,
  Map<String, Map<String, String>> labels,
});

class _ManualEntry {
  _ManualEntry({
    required this.id,
    required this.item,
    required this.occurrence,
  });

  final String id;
  ChannelItem item;
  final int occurrence;
}

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

String _preferredFacetLabel(LibraryFilter filter, String first, String second) {
  if (filter != LibraryFilter.actor && filter != LibraryFilter.director) {
    return first.compareTo(second) <= 0 ? first : second;
  }
  bool hasMixedCase(String value) =>
      value != value.toLowerCase() && value != value.toUpperCase();
  final firstIsMixed = hasMixedCase(first);
  final secondIsMixed = hasMixedCase(second);
  if (firstIsMixed != secondIsMixed) return firstIsMixed ? first : second;
  return first.compareTo(second) <= 0 ? first : second;
}

class ChannelStudioView extends StatefulWidget {
  const ChannelStudioView({
    required this.controller,
    required this.mode,
    required this.onBack,
    required this.onSaved,
    required this.onTune,
    required this.onDuplicate,
    required this.onOpenGenerateLineup,
    this.onOpenChannel,
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
  final Future<void> Function(Channel channel)? onOpenChannel;
  final DateTime Function()? clock;

  @override
  State<ChannelStudioView> createState() => ChannelStudioViewState();
}

class ChannelStudioViewState extends State<ChannelStudioView> {
  static const _countAnnouncementDelay = Duration(milliseconds: 300);
  GlobalKey<FormState> _form = GlobalKey<FormState>();
  final _backFocus = FocusNode(debugLabel: 'Back to Channels');
  final _recoveryFocus = FocusNode(debugLabel: 'Use saved Studio version');
  final _nameFocus = FocusNode(debugLabel: 'Channel name');
  final _numberFocus = FocusNode(debugLabel: 'Channel number');
  final _saveFocus = FocusNode(debugLabel: 'Save channel');
  final _searchFocus = FocusNode(debugLabel: 'Search programming');
  final _filterPickerSearch = TextEditingController();
  final _filterControlFocus = <String, FocusNode>{};
  late final TextEditingController _name;
  late final TextEditingController _number;
  late final TextEditingController _search;
  late String _id;
  late ContentSource _source;
  late PlaybackMode _playbackMode;
  late DateTime _anchor;
  late int _shuffleSeed;
  DateTime? _candidateAnchor;
  int? _candidateShuffleSeed;
  late int? _blockSize;
  late bool _includeSpecials;
  late String? _builderKey;
  late Channel? _expectedBase;
  late bool _generated;
  late bool _sourceReadOnly;
  _SourceChoice? _sourceChoice;
  late List<_ManualEntry> _manualEntries;
  final _manualKeyCounts = <String, int>{};
  late bool _filterIncludeWatched;
  String? _playlistId;
  String? _filterLibraryId;
  final _filters = <LibraryFilter, List<String>>{};
  String? _activeFilterKey;
  List<String> _activeFilterValues = const [];
  Map<String, String> _activeFilterLabels = const {};
  Set<String> _activeAvailableFilterValues = const {};
  final LinkedHashSet<String> _pendingFilterValues = LinkedHashSet();
  bool _showPendingFilterValues = false;
  String? _manualLibraryId;
  String? _manualMediaType;
  final _manualFilters = <String, String>{};
  final LinkedHashSet<String> _browseSelection = LinkedHashSet();
  final Map<String, PlexMediaItem> _browseSelectionItems = {};
  bool _browseSelecting = false;
  bool _showBrowseSelected = false;
  List<_ManualEntry> _lastAddedEntries = const [];
  final _rundownFocus = <_ManualEntry, FocusNode>{};
  late final TextEditingController _rundownSearch;
  final _browseScroll = ScrollController();
  final _rundownScroll = ScrollController();
  bool _manualRundown = false;
  Timer? _countAnnouncementTimer;
  String _settledCountLabel = '';
  late Map<String, Object?> _baselineDraftSignature;
  bool _dirty = false;
  bool _saving = false;
  bool _tuning = false;
  int _tuneEpoch = 0;
  bool _conflict = false;
  bool _baseDeleted = false;
  String? _error;
  String? _success;
  ChannelAirCheckStatus? _airCheckStatus;

  double get _uiScale => LineupLayout.scaleFor(MediaQuery.sizeOf(context));
  bool _scheduleIdentityCommitted = false;
  late ({
    List<PlexMediaItem> media,
    List<PlexPlaylist> playlists,
    Map<String, PlexMediaItem> byId,
  })
  _playableInventory;

  bool get _busy => _saving || _tuning;
  bool get saving => _saving;
  bool get dirty => _dirty;
  int? get _effectiveBlockSize =>
      _playbackMode == PlaybackMode.block ? (_blockSize ?? 3) : null;
  bool get _effectiveIncludeSpecials =>
      _playbackMode == PlaybackMode.block && _includeSpecials;
  ChannelStudioMode get _effectiveMode => _expectedBase != null && !_generated
      ? ChannelStudioMode.editCustom
      : widget.mode;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  void _loadInitial() {
    _refreshPlayableInventory();
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
    _rundownSearch = TextEditingController();
    _source = original?.source ?? _defaultSource();
    _playbackMode = original?.playbackMode ?? PlaybackMode.shuffle;
    _anchor =
        original?.anchor ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    _shuffleSeed = original?.shuffleSeed ?? 0;
    _blockSize = original?.blockSize;
    _includeSpecials = original?.includeSpecials ?? false;
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
        : LibrarySource(
            libraryId: library.id,
            libraryType: library.type,
            order: LibraryOrder.title,
          );
  }

  void _configureSource(ContentSource source) {
    _sourceReadOnly = _generated;
    _sourceChoice = switch (source) {
      LibrarySource() => _SourceChoice.library,
      PlaylistSource() => _SourceChoice.playlist,
      ManualSource() => _SourceChoice.handPicked,
      MixedSource() => null,
    };
    final replacedFocus = _rundownFocus.values.toList(growable: false);
    _rundownFocus.clear();
    if (replacedFocus.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final focus in replacedFocus) {
          focus.dispose();
        }
      });
    }
    _manualKeyCounts.clear();
    _manualEntries = switch (source) {
      ManualSource(:final items) => items.map(_newManualEntry).toList(),
      _ => <_ManualEntry>[],
    };
    _manualRundown = _manualEntries.isNotEmpty;
    _filterIncludeWatched = switch (source) {
      LibrarySource(:final includeWatched) => includeWatched,
      _ => true,
    };
    _playlistId = switch (source) {
      PlaylistSource(:final playlistId) => playlistId,
      _ => _playableInventory.playlists.firstOrNull?.id,
    };
    _filterLibraryId = switch (source) {
      LibrarySource(:final libraryId) => libraryId,
      _ => widget.controller.selectedLibraryIds.firstOrNull,
    };
    _filters
      ..clear()
      ..addAll(switch (source) {
        LibrarySource(:final filters) => filters,
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
    _backFocus.dispose();
    _recoveryFocus.dispose();
    _name.dispose();
    _number.dispose();
    _search.dispose();
    _rundownSearch.dispose();
    _browseScroll.dispose();
    _rundownScroll.dispose();
    _filterPickerSearch.dispose();
    _nameFocus.dispose();
    _numberFocus.dispose();
    _saveFocus.dispose();
    _searchFocus.dispose();
    _countAnnouncementTimer?.cancel();
    for (final node in _rundownFocus.values) {
      node.dispose();
    }
    for (final node in _filterControlFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _changed([VoidCallback? change]) => setState(() {
    change?.call();
    _dirty = !canonicalChannelValueEquals(
      _draftSignature,
      _baselineDraftSignature,
    );
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
      'includeSpecials': _playbackMode == PlaybackMode.block
          ? _includeSpecials
          : false,
      'builderKey': _builderKey,
    };
  }

  Object get _sourceDraftSignature => switch (_sourceChoice) {
    _SourceChoice.library => {
      'type': 'library',
      'libraryId': _filterLibraryId,
      'includeWatched': _filterIncludeWatched,
      'filters': {
        for (final entry in _filters.entries)
          entry.key.name: [...entry.value]..sort(),
      },
      'order': _libraryDraftOrder(
        _filterLibraryId,
        includeWatched: _filterIncludeWatched,
        filters: _filters,
      ).name,
    },
    _SourceChoice.playlist => {'type': 'playlist', 'playlistId': _playlistId},
    _SourceChoice.filter => {
      'type': 'filter',
      'libraryId': _filterLibraryId,
      'includeWatched': _filterIncludeWatched,
      'filters': {
        for (final entry in _filters.entries)
          entry.key.name: [...entry.value]..sort(),
      },
      'order': _libraryDraftOrder(
        _filterLibraryId,
        includeWatched: _filterIncludeWatched,
        filters: _filters,
      ).name,
    },
    _SourceChoice.handPicked => _manualDraftSignature,
    null => _source.toJson(),
  };

  Map<String, Object?> get _manualDraftSignature {
    final counts = <String, int>{};
    for (final entry in _manualEntries) {
      counts.update(entry.id, (count) => count + 1, ifAbsent: () => 1);
    }
    return {
      'type': 'manual',
      'items': [
        for (final entry in _manualEntries)
          counts[entry.id] == 1
              ? entry.id
              : {'id': entry.id, 'snapshot': entry.item.toJson()},
      ],
    };
  }

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
    _refreshPlayableInventory();
    final noNumber = _lowestFreeNumber() == null && _number.text.trim().isEmpty;
    final persisted = _expectedBase != null;
    final saved = !_dirty && persisted;
    final number = int.tryParse(_number.text);
    final validNumber = _validateNumber(_number.text) == null;
    final identityLooksValid = _name.text.trim().isNotEmpty && validNumber;
    final draftResolution = _generated ? null : _resolveDraftContent();
    final programmingError = draftResolution == null
        ? null
        : _programmingError(draftResolution);
    final hasShowGrouping =
        draftResolution?.content?.any(
          (item) =>
              item.showTitle?.trim().isNotEmpty == true ||
              item.showThumb?.trim().isNotEmpty == true,
        ) ??
        false;
    final confirmedMovieOnly = _confirmedMovieOnly(draftResolution);
    _stageScheduleIdentity(programmingError);
    final theme = Theme.of(context);
    final compact = LineupLayout.isCompactWidth(
      MediaQuery.sizeOf(context).width,
    );
    final baseFontSize = compact ? 14.0 : 18.0;
    final inputDecorationTheme = _uiScale > 1
        ? theme.inputDecorationTheme.copyWith(
            contentPadding: EdgeInsets.fromLTRB(
              12 * _uiScale,
              24 * _uiScale,
              12 * _uiScale,
              16 * _uiScale,
            ),
            prefixIconConstraints: BoxConstraints(
              minWidth: 48 * _uiScale,
              minHeight: 48 * _uiScale,
            ),
            suffixIconConstraints: BoxConstraints(
              minWidth: 48 * _uiScale,
              minHeight: 48 * _uiScale,
            ),
          )
        : theme.inputDecorationTheme;
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: inputDecorationTheme.copyWith(
          floatingLabelStyle: TextStyle(
            fontSize: _studioSize(24, 18),
            color: LineupTheme.of(context).secondaryText,
          ),
        ),
        textTheme: theme.textTheme.copyWith(
          bodyMedium: theme.textTheme.bodyMedium?.copyWith(
            fontSize: baseFontSize,
          ),
          bodyLarge: theme.textTheme.bodyLarge?.copyWith(
            fontSize: baseFontSize,
          ),
          titleMedium: theme.textTheme.titleMedium?.copyWith(
            fontSize: baseFontSize,
          ),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: LineupPage(
          traversalPolicy: OrderedTraversalPolicy(),
          title: _name.text.trim().isEmpty ? 'New channel' : _name.text.trim(),
          titleWidget: Builder(
            builder: (_) => _studioTitle(
              validNumber ? number : null,
              saved,
              persisted: persisted,
              noNumber: noNumber,
              identityLooksValid: identityLooksValid,
              programmingError: programmingError,
            ),
          ),
          child: Builder(
            builder: (context) => SingleChildScrollView(
              key: const Key('studio-scroll'),
              child: AbsorbPointer(
                absorbing: _busy,
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null && !_conflict && !_baseDeleted) ...[
                        LineupNotice(message: _error!),
                      ],
                      if (_success != null) ...[
                        SizedBox(height: 12 * _uiScale),
                        Semantics(liveRegion: true, child: Text(_success!)),
                      ],
                      if (_saving) ...[
                        SizedBox(height: 12 * _uiScale),
                        Semantics(
                          liveRegion: true,
                          container: true,
                          label: 'Saving channel',
                          child: const Text('Saving channel…'),
                        ),
                      ],
                      if (noNumber) ...[
                        SizedBox(height: 12 * _uiScale),
                        const LineupNotice(
                          message: 'No channel numbers are available. Free or renumber a channel from Channels before saving.',
                        ),
                      ],
                      if (_conflict || _baseDeleted) ...[_recoveryInterlock()],
                      if (_error != null ||
                          _success != null ||
                          _saving ||
                          noNumber ||
                          _conflict ||
                          _baseDeleted)
                        SizedBox(height: 12 * _uiScale),
                      if (_hasPendingProgrammingChoice) ...[
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _activeFilterKey != null
                                ? 'Finish this filter with Done, or cancel it, before saving or tuning.'
                                : 'Add the selected programs, or cancel selection, before saving or tuning.',
                          ),
                        ),
                        SizedBox(height: 12 * _uiScale),
                      ],
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final programming = _programmingCard();
                          final station = _stationCard(
                            hasShowGrouping: hasShowGrouping,
                            confirmedMovieOnly: confirmedMovieOnly,
                          );
                          final preview = ChannelAirCheck(
                            controller: widget.controller,
                            channel: _previewDraft,
                            originalChannel: _expectedBase,
                            clock: _clock,
                            compact:
                                constraints.maxWidth <
                                LineupLayout.compact * _uiScale,
                            inclusionReason: _sourceLabel(
                              _displaySource,
                              widget.controller,
                            ),
                            sourceIssue: programmingError,
                            playableById: _playableInventory.byId,
                            onValidityChanged: (status) {
                              if (!mounted || _airCheckStatus == status) return;
                              setState(() => _airCheckStatus = status);
                              if (_isCurrentAirCheckStatus(status)) {
                                _commitScheduleIdentity();
                              }
                            },
                          );
                          return constraints.maxWidth <
                                  LineupLayout.compact * _uiScale
                              ? Column(
                                  children: [
                                    FocusTraversalOrder(
                                      order: const NumericFocusOrder(1),
                                      child: station,
                                    ),
                                    SizedBox(height: 16 * _uiScale),
                                    FocusTraversalOrder(
                                      order: const NumericFocusOrder(2),
                                      child: programming,
                                    ),
                                    SizedBox(height: 16 * _uiScale),
                                    FocusTraversalOrder(
                                      order: const NumericFocusOrder(3),
                                      child: preview,
                                    ),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    FocusTraversalOrder(
                                      order: const NumericFocusOrder(1),
                                      child: station,
                                    ),
                                    SizedBox(height: 16 * _uiScale),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          flex: 5,
                                          child: FocusTraversalOrder(
                                            order: const NumericFocusOrder(2),
                                            child: programming,
                                          ),
                                        ),
                                        SizedBox(width: 16 * _uiScale),
                                        Expanded(
                                          flex: 4,
                                          child: FocusTraversalOrder(
                                            order: const NumericFocusOrder(3),
                                            child: preview,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _studioTitle(
    int? number,
    bool saved, {
    required bool persisted,
    required bool noNumber,
    required bool identityLooksValid,
    required String? programmingError,
  }) {
    final roles = LineupTheme.of(context);
    final compact = LineupLayout.isCompactWidth(
      MediaQuery.sizeOf(context).width,
    );
    final name = _name.text.trim().isEmpty ? 'New channel' : _name.text.trim();
    final status = _conflict
        ? 'My draft retained'
        : _baseDeleted
        ? 'Source deleted'
        : _dirty
        ? 'Unsaved changes'
        : saved
        ? 'Saved'
        : 'Draft';
    final mode = _modeLabel(_effectiveMode);
    final titleStyle = Theme.of(context).textTheme.headlineMedium?.copyWith(
      fontSize: (compact ? 24 : 36) * _uiScale,
      fontWeight: FontWeight.w600,
    );
    final statusStyle = _studioBodyStyle(
      color: _conflict || _baseDeleted
          ? Theme.of(context).colorScheme.error
          : roles.secondaryText,
    );
    final wordmarkStyle = TextStyle(
      color: roles.primaryText,
      fontFamily: 'Arial',
      fontSize: (compact ? 14 : 18) * _uiScale,
      fontWeight: FontWeight.w400,
      letterSpacing: 1.5,
    );
    final contextStyle = _studioSupportStyle(fontWeight: FontWeight.w600);
    final back = FocusTraversalOrder(
      order: const NumericFocusOrder(0),
      child: TextButton.icon(
        focusNode: _backFocus,
        autofocus: true,
        onPressed: _busy ? null : () => unawaited(_leave()),
        style: _studioTextButtonStyle(),
        icon: _uiScale > 1
            ? Icon(Icons.arrow_back, size: 24 * _uiScale)
            : const Icon(Icons.arrow_back),
        label: const Text('Back to Channels'),
      ),
    );
    final actions = Align(
      widthFactor: 1,
      alignment: Alignment.centerRight,
      child: _studioActions(
        persisted: persisted,
        saved: saved,
        noNumber: noNumber,
        identityLooksValid: identityLooksValid,
        programmingError: programmingError,
      ),
    );
    final titleAndActions = LayoutBuilder(
      builder: (context, constraints) {
        final narrow = compact || constraints.maxWidth < 1000 * _uiScale;
        final title = Semantics(
          header: true,
          excludeSemantics: true,
          label:
              '${number == null ? 'No channel number' : 'Channel $number'}, $name, ${_modeHeaderLabel(_effectiveMode)}, $mode, $status',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, softWrap: true, style: titleStyle),
              SizedBox(height: 4 * _uiScale),
              Wrap(
                spacing: 8 * _uiScale,
                runSpacing: 2 * _uiScale,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(mode, style: statusStyle),
                  Text('·', style: statusStyle),
                  Text(status, style: statusStyle),
                ],
              ),
            ],
          ),
        );
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              SizedBox(height: 12 * _uiScale),
              actions,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            SizedBox(width: 24 * _uiScale),
            actions,
          ],
        );
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 24 * _uiScale,
          runSpacing: 8 * _uiScale,
          children: [
            back,
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16 * _uiScale,
              children: [
                Text('LINEUP', style: wordmarkStyle),
                Text(
                  '/',
                  style: _studioBodyStyle(color: roles.secondaryText)
                      .copyWith(fontSize: (compact ? 14 : 18) * _uiScale),
                ),
                Text('CHANNEL STUDIO', style: contextStyle),
              ],
            ),
          ],
        ),
        Divider(height: 1, color: roles.subtleBorder),
        SizedBox(height: 20 * _uiScale),
        titleAndActions,
      ],
    );
  }

  double _studioSize(double wide, double compact) =>
      (LineupLayout.isCompactWidth(MediaQuery.sizeOf(context).width)
          ? compact
          : wide) *
      _uiScale;

  TextStyle _studioBodyStyle({Color? color, FontWeight? fontWeight}) =>
      Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: _studioSize(18, 14),
        color: color,
        fontWeight: fontWeight,
      ) ??
      TextStyle(
        fontSize: _studioSize(18, 14),
        color: color,
        fontWeight: fontWeight,
      );

  TextStyle _studioSupportStyle({Color? color, FontWeight? fontWeight}) =>
      Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: _studioSize(16, 14),
        color: color ?? LineupTheme.of(context).secondaryText,
        fontWeight: fontWeight,
      ) ??
      TextStyle(
        fontSize: _studioSize(16, 14),
        color: color ?? LineupTheme.of(context).secondaryText,
        fontWeight: fontWeight,
      );

  TextStyle _studioSectionHeadingStyle() =>
      Theme.of(context).textTheme.titleLarge?.copyWith(
        fontSize: _studioSize(24, 20),
        fontWeight: FontWeight.w600,
      ) ??
      TextStyle(fontSize: _studioSize(24, 20), fontWeight: FontWeight.w600);

  TextStyle _studioControlStyle() =>
      Theme.of(context).textTheme.labelLarge
          ?.copyWith(fontSize: _studioSize(18, 14)) ??
      TextStyle(fontSize: _studioSize(18, 14));

  double? get _studioDropdownItemHeight => _uiScale > 1 ? 48 * _uiScale : null;

  ButtonStyle _studioScaledTextButtonStyle() =>
      (Theme.of(context).textButtonTheme.style ?? const ButtonStyle()).copyWith(
        minimumSize: WidgetStatePropertyAll(Size(64 * _uiScale, 40 * _uiScale)),
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(
            horizontal: 12 * _uiScale,
            vertical: 8 * _uiScale,
          ),
        ),
        iconSize: WidgetStatePropertyAll(18 * _uiScale),
        textStyle: WidgetStatePropertyAll(
          Theme.of(context).textTheme.labelLarge
              ?.apply(fontSizeFactor: _uiScale),
        ),
      );

  ButtonStyle _studioScaledOutlinedButtonStyle() {
    final theme = Theme.of(context);
    final base = theme.outlinedButtonTheme.style ?? const ButtonStyle();
    final textStyle =
        base.textStyle?.resolve(const {}) ?? const TextStyle(fontSize: 17);
    return base.copyWith(
      minimumSize: WidgetStatePropertyAll(Size(148 * _uiScale, 54 * _uiScale)),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          horizontal: 24 * _uiScale,
          vertical: 16 * _uiScale,
        ),
      ),
      iconSize: WidgetStatePropertyAll(18 * _uiScale),
      textStyle: WidgetStatePropertyAll(
        textStyle.copyWith(fontSize: (textStyle.fontSize ?? 17) * _uiScale),
      ),
    );
  }

  ButtonStyle _studioScaledFilledButtonStyle() {
    final theme = Theme.of(context);
    final base = theme.filledButtonTheme.style ?? const ButtonStyle();
    final textStyle =
        base.textStyle?.resolve(const {}) ?? const TextStyle(fontSize: 17);
    return base.copyWith(
      minimumSize: WidgetStatePropertyAll(Size(148 * _uiScale, 54 * _uiScale)),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          horizontal: 24 * _uiScale,
          vertical: 16 * _uiScale,
        ),
      ),
      iconSize: WidgetStatePropertyAll(18 * _uiScale),
      textStyle: WidgetStatePropertyAll(
        textStyle.copyWith(fontSize: (textStyle.fontSize ?? 17) * _uiScale),
      ),
    );
  }

  double _studioSegmentVerticalPadding(TextStyle textStyle) {
    if (_uiScale <= 1) return 0;
    final fontSize = textStyle.fontSize ?? 14;
    final targetHeight = 40 * _uiScale;
    return targetHeight > fontSize ? (targetHeight - fontSize) / 2 : 0;
  }

  ButtonStyle _studioTextButtonStyle() => TextButton.styleFrom(
    minimumSize: Size(0, 48 * _uiScale),
    padding: EdgeInsets.symmetric(
      horizontal: 16 * _uiScale,
      vertical: 12 * _uiScale,
    ),
    iconSize: _uiScale > 1 ? 18 * _uiScale : null,
    textStyle: _studioControlStyle(),
  );

  ButtonStyle _studioOutlinedButtonStyle() => OutlinedButton.styleFrom(
    minimumSize: Size(0, 48 * _uiScale),
    padding: EdgeInsets.symmetric(
      horizontal: 16 * _uiScale,
      vertical: 12 * _uiScale,
    ),
    iconSize: _uiScale > 1 ? 18 * _uiScale : null,
    textStyle: _studioControlStyle(),
  );

  ButtonStyle _studioFilledButtonStyle() => FilledButton.styleFrom(
    minimumSize: Size(0, 48 * _uiScale),
    padding: EdgeInsets.symmetric(
      horizontal: 16 * _uiScale,
      vertical: 12 * _uiScale,
    ),
    iconSize: _uiScale > 1 ? 18 * _uiScale : null,
    textStyle: _studioControlStyle(),
  );

  ButtonStyle _studioIconButtonStyle() => IconButton.styleFrom(
    minimumSize: Size(48 * _uiScale, 48 * _uiScale),
    padding: EdgeInsets.all(8 * _uiScale),
    iconSize: 24 * _uiScale,
  );

  ButtonStyle _studioSourceStyle() {
    final roles = LineupTheme.of(context);
    final controlStyle = _studioControlStyle();
    return ButtonStyle(
      padding: WidgetStatePropertyAll(
        _uiScale > 1
            ? EdgeInsets.symmetric(
                horizontal: 16 * _uiScale,
                vertical: _studioSegmentVerticalPadding(controlStyle),
              )
            : const EdgeInsets.symmetric(horizontal: 16),
      ),
      iconSize: _uiScale > 1 ? WidgetStatePropertyAll(18 * _uiScale) : null,
      textStyle: WidgetStatePropertyAll(controlStyle),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? roles.mutedText
            : states.contains(WidgetState.selected)
            ? roles.primaryText
            : roles.secondaryText,
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? roles.selectedSurface
            : Colors.transparent,
      ),
      side: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? BorderSide(
                color: roles.focusBorder,
                width: roles.focusBorderWidth,
              )
            : BorderSide.none,
      ),
    );
  }

  Widget _studioSwitchTile({
    Key? key,
    required bool value,
    required Widget title,
    required ValueChanged<bool>? onChanged,
    EdgeInsetsGeometry? contentPadding,
  }) {
    if (_uiScale <= 1) {
      return SwitchListTile(
        key: key,
        contentPadding: contentPadding,
        value: value,
        title: title,
        onChanged: onChanged,
      );
    }
    final control = SizedBox(
      width: 60,
      height: 40,
      child: Center(
        child: ExcludeFocus(
          child: Switch(value: value, onChanged: onChanged),
        ),
      ),
    );
    return MergeSemantics(
      key: key,
      child: ListTile(
        contentPadding:
            contentPadding ?? EdgeInsets.symmetric(horizontal: 16 * _uiScale),
        minTileHeight: 56 * _uiScale,
        horizontalTitleGap: 16 * _uiScale,
        trailing: SizedBox(
          width: 60 * _uiScale,
          height: 40 * _uiScale,
          child: Transform.scale(scale: _uiScale, child: control),
        ),
        title: title,
        onTap: onChanged == null ? null : () => onChanged(!value),
      ),
    );
  }

  Widget _studioCheckboxTile({
    Key? key,
    required bool value,
    required Widget title,
    required ValueChanged<bool?>? onChanged,
    ListTileControlAffinity controlAffinity = ListTileControlAffinity.leading,
    EdgeInsetsGeometry? contentPadding,
  }) {
    if (_uiScale <= 1) {
      return CheckboxListTile(
        key: key,
        controlAffinity: controlAffinity,
        contentPadding: contentPadding,
        value: value,
        title: title,
        onChanged: onChanged,
      );
    }
    return CheckboxListTile(
      key: key,
      controlAffinity: controlAffinity,
      contentPadding:
          contentPadding ?? EdgeInsets.symmetric(horizontal: 16 * _uiScale),
      minTileHeight: 56 * _uiScale,
      minLeadingWidth: 40 * _uiScale,
      horizontalTitleGap: 16 * _uiScale,
      checkboxScaleFactor: _uiScale,
      value: value,
      title: title,
      onChanged: onChanged,
    );
  }

  Widget _studioActions({
    required bool persisted,
    required bool saved,
    required bool noNumber,
    required bool identityLooksValid,
    required String? programmingError,
  }) {
    final recovering = _conflict || _baseDeleted;
    final showSave =
        !recovering && (!_generated || !persisted || _dirty || _saving);
    final canSave =
        !_busy &&
        !_hasPendingProgrammingChoice &&
        (!persisted || _dirty) &&
        !noNumber &&
        !(identityLooksValid && programmingError != null) &&
        !(identityLooksValid && !_airCheckCanSave);
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8 * _uiScale,
      runSpacing: 8 * _uiScale,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (_generated && !recovering)
          FocusTraversalOrder(
            order: const NumericFocusOrder(4),
            child: OutlinedButton(
              onPressed: _busy ? null : _duplicate,
              style: _studioOutlinedButtonStyle(),
              child: const Text('Duplicate as custom'),
            ),
          ),
        if (persisted && !recovering)
          FocusTraversalOrder(
            order: const NumericFocusOrder(4),
            child: saved
                ? FilledButton.icon(
                    key: const Key('studio-tune'),
                    onPressed: _busy ? null : _tune,
                    style: _studioFilledButtonStyle(),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Tune in'),
                  )
                : OutlinedButton.icon(
                    key: const Key('studio-tune'),
                    onPressed: canSave ? _confirmSaveAndTune : null,
                    style: _studioOutlinedButtonStyle(),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Tune in'),
                  ),
          ),
        if (showSave)
          FocusTraversalOrder(
            order: const NumericFocusOrder(4),
            child: FilledButton(
              focusNode: _saveFocus,
              onPressed: canSave ? _save : null,
              style: _studioFilledButtonStyle(),
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
          ),
      ],
    );
  }

  Widget _recoveryInterlock() {
    final roles = LineupTheme.of(context);
    final error = Theme.of(context).colorScheme.error;
    final current = _currentBase;
    final recoverySide = WidgetStateProperty.resolveWith(
      (states) => BorderSide(
        color: states.contains(WidgetState.focused)
            ? roles.focusBorder
            : roles.defaultBorder,
        width: states.contains(WidgetState.focused)
            ? roles.focusBorderWidth
            : 1,
      ),
    );
    final recoveryButtonStyle = _uiScale > 1
        ? _studioScaledOutlinedButtonStyle().copyWith(side: recoverySide)
        : ButtonStyle(side: recoverySide);
    return Semantics(
      liveRegion: true,
      container: true,
      label: _error,
      child: Container(
        padding: EdgeInsets.all(16 * _uiScale),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            error.withValues(alpha: 0.08),
            roles.primarySurface,
          ),
          border: Border.all(color: error.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(roles.panelRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.report_problem_outlined,
                  color: error,
                  size: 24 * _uiScale,
                ),
                SizedBox(width: 12 * _uiScale),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _baseDeleted
                            ? 'This channel was deleted'
                            : 'Another edit was saved first',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.apply(fontSizeFactor: _uiScale)
                            .copyWith(fontWeight: FontWeight.w800),
                      ),
                      SizedBox(height: 4 * _uiScale),
                      Text(
                        _baseDeleted
                            ? 'Your draft is retained for reference, but it will not recreate the deleted channel.'
                            : 'Your complete draft is retained. Choose which version should own channel ${_number.text}.',
                        style: TextStyle(color: roles.secondaryText),
                      ),
                      if (!_baseDeleted && current != null) ...[
                        SizedBox(height: 10 * _uiScale),
                        _recoveryVersion('SAVED NOW', current.name),
                        _recoveryVersion(
                          'YOUR DRAFT',
                          _name.text.trim().isEmpty
                              ? 'Unnamed channel'
                              : _name.text.trim(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 12 * _uiScale),
            Wrap(
              spacing: 10 * _uiScale,
              runSpacing: 10 * _uiScale,
              children: [
                if (_baseDeleted) ...[
                  OutlinedButton(
                    focusNode: _saveFocus,
                    style: recoveryButtonStyle,
                    onPressed: _saving ? null : _prepareSaveAsNew,
                    child: const Text('Save as new custom channel'),
                  ),
                  OutlinedButton(
                    style: recoveryButtonStyle,
                    onPressed: _saving ? null : _reload,
                    child: const Text('Return to Channels'),
                  ),
                ] else ...[
                  OutlinedButton(
                    focusNode: _recoveryFocus,
                    style: recoveryButtonStyle,
                    onPressed: _saving ? null : _confirmUseSaved,
                    child: const Text('Use saved version…'),
                  ),
                  OutlinedButton(
                    focusNode: _saveFocus,
                    style: recoveryButtonStyle,
                    onPressed: _saving ? null : _confirmReapply,
                    child: const Text('Replace saved version with my draft…'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _recoveryVersion(String label, String value) => Padding(
    padding: EdgeInsets.only(top: 3 * _uiScale),
    child: Row(
      children: [
        SizedBox(
          width: 92 * _uiScale,
          child: Text(
            label,
            style: TextStyle(
              color: LineupTheme.of(context).mutedText,
              fontSize: 11 * _uiScale,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  Widget _programmingCard() {
    final roles = LineupTheme.of(context);
    return DefaultTextStyle.merge(
      style: _studioBodyStyle(),
      child: Column(
        key: const Key('studio-programming'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 16 * _uiScale,
            runSpacing: 4 * _uiScale,
            children: [
              Text('Programming', style: _studioSectionHeadingStyle()),
              Text(
                _sourceLabel(_displaySource, widget.controller),
                style: _studioSupportStyle(color: roles.secondaryText),
              ),
            ],
          ),
          SizedBox(height: 16 * _uiScale),
          if (_sourceReadOnly)
            const Text(
              'Programming is read-only and will be preserved exactly.',
            )
          else ...[
            if (_source is MixedSource && _sourceChoice == null) ...[
              _inventoryStatus(),
              const Text(
                'This mixed source is preserved exactly. Choose a source below only if you want to replace it.',
              ),
              SizedBox(height: 8 * _uiScale),
            ],
            LayoutBuilder(
              builder: (context, constraints) => SegmentedButton<_SourceChoice>(
                key: const Key('studio-source-choices'),
                direction:
                    MediaQuery.textScalerOf(context).scale(14) > 21 ||
                        constraints.maxWidth < 480 * _uiScale
                    ? Axis.vertical
                    : Axis.horizontal,
                multiSelectionEnabled: false,
                emptySelectionAllowed: _source is MixedSource,
                segments: const [
                  ButtonSegment(
                    value: _SourceChoice.library,
                    label: Text('Library'),
                  ),
                  ButtonSegment(
                    value: _SourceChoice.playlist,
                    label: Text('Plex playlist'),
                  ),
                  ButtonSegment(
                    value: _SourceChoice.handPicked,
                    label: Text('Hand-picked'),
                  ),
                ],
                selected: {?_sourceChoice},
                showSelectedIcon: false,
                style: _studioSourceStyle(),
                onSelectionChanged: _saving
                    ? null
                    : (value) =>
                          _changed(() => _sourceChoice = value.singleOrNull),
              ),
            ),
            SizedBox(height: 8 * _uiScale),
            switch (_sourceChoice) {
              _SourceChoice.library => _filterEditor(),
              _SourceChoice.playlist => _playlistEditor(),
              _SourceChoice.filter => _filterEditor(),
              _SourceChoice.handPicked => _manualEditor(),
              null => const SizedBox.shrink(),
            },
          ],
        ],
      ),
    );
  }

  Widget _playlistEditor() {
    final available = _playableInventory.playlists;
    final selected = available.any((playlist) => playlist.id == _playlistId);
    final otherUses = widget.controller.channels.where(
      (channel) =>
          channel.id != _id &&
          channel.source is PlaylistSource &&
          (channel.source as PlaylistSource).playlistId == _playlistId,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _inventoryStatus(),
        const Text(
          'Uses an existing Plex playlist. Manage its contents in Plex.',
        ),
        if (_playlistId != null && !selected)
          Text(
            'Playlist $_playlistId is unavailable — retained until replaced.',
          ),
        DropdownButtonFormField<String>(
          key: const Key('studio-playlist'),
          isExpanded: true,
          iconSize: 24 * _uiScale,
          itemHeight: _studioDropdownItemHeight,
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
        if (otherUses.isNotEmpty) ...[
          SizedBox(height: 8 * _uiScale),
          const Text('Also used by'),
          for (final channel in otherUses)
            ListTile(
              contentPadding: EdgeInsets.zero,
              minTileHeight: _uiScale > 1 ? 56 * _uiScale : null,
              title: Text('${channel.number} · ${channel.name}'),
              trailing: TextButton(
                onPressed: _saving || widget.onOpenChannel == null
                    ? null
                    : () => widget.onOpenChannel!(channel),
                style: _uiScale > 1 ? _studioScaledTextButtonStyle() : null,
                child: const Text('Open channel'),
              ),
            ),
        ],
      ],
    );
  }

  Widget _filterEditor() {
    final roles = LineupTheme.of(context);
    final facets = _facetOptions(_filterLibraryId);
    final matches = _filteredInventory(
      libraryId: _filterLibraryId,
      filters: _filters,
      includeWatched: _filterIncludeWatched,
    );
    if (_activeFilterKey case final key?) {
      return _filterPickerPanel(key);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _inventoryStatus(),
        LayoutBuilder(
          builder: (context, constraints) {
            final gap = 16 * _uiScale;
            final width = constraints.maxWidth >= 700 * _uiScale
                ? (constraints.maxWidth - gap) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: gap,
              runSpacing: 12 * _uiScale,
              children: [
                SizedBox(
                  width: width,
                  child: _libraryDropdown(
                    key: const Key('studio-filter-library'),
                    value: _filterLibraryId,
                    onChanged: (value) =>
                        _filterChanged(() => _filterLibraryId = value),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _filterControl(
                    'collection',
                    facets.values['collection'] ?? const [],
                    facets.labels['collection'] ?? const {},
                  ),
                ),
              ],
            );
          },
        ),
        if ((facets.values['collection'] ?? const []).isEmpty)
          Text(
            'This library has no collections. Other filters remain available.',
            style: _studioSupportStyle(),
          ),
        SizedBox(height: 16 * _uiScale),
        Text('Filters', style: _studioBodyStyle(fontWeight: FontWeight.w600)),
        SizedBox(height: 16 * _uiScale),
        LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final columns = textScale > 1.4
                ? 1
                : constraints.maxWidth >= 960 * _uiScale
                ? 3
                : constraints.maxWidth >= 640 * _uiScale
                ? 2
                : 1;
            final gap = 16 * _uiScale;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: 12 * _uiScale,
              children: [
                for (final key in _facetKeys.where(
                  (key) => key != 'collection',
                ))
                  SizedBox(
                    width: width,
                    child: _filterControl(
                      key,
                      facets.values[key] ?? const [],
                      facets.labels[key] ?? const {},
                    ),
                  ),
              ],
            );
          },
        ),
        SizedBox(height: 12 * _uiScale),
        Text(
          'Any selected value within each filter; all filters together.',
          style: _studioSupportStyle(),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 330 * _uiScale),
            child: Material(
              type: MaterialType.transparency,
              child: _studioSwitchTile(
                key: const Key('studio-filter-include-watched'),
                contentPadding: EdgeInsets.zero,
                value: _filterIncludeWatched,
                title: Text('Include watched items', style: _studioBodyStyle()),
                onChanged: _saving
                    ? null
                    : (value) =>
                          _filterChanged(() => _filterIncludeWatched = value),
              ),
            ),
          ),
        ),
        SizedBox(height: 16 * _uiScale),
        Divider(height: 1, color: roles.subtleBorder),
        SizedBox(height: 16 * _uiScale),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16 * _uiScale,
          runSpacing: 4 * _uiScale,
          children: [
            Text('Matching programs', style: _studioSectionHeadingStyle()),
            Text(
              '${matches.length} matching programs',
              style: _studioSupportStyle(),
            ),
          ],
        ),
        for (final item in matches.take(5))
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: roles.subtleBorder)),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8 * _uiScale),
              child: Text(item.title, style: _studioBodyStyle()),
            ),
          ),
        if (matches.length > 5)
          Text(
            'Showing 5 of ${matches.length} matching programs.',
            style: _studioSupportStyle(),
          ),
      ],
    );
  }

  Widget _filterControl(
    String key,
    List<String> values,
    Map<String, String> labels,
  ) {
    final filter = _libraryFilter(key);
    final selected = _filters[filter] ?? const [];
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
    final roles = LineupTheme.of(context);
    return ListenableBuilder(
      key: Key('studio-filter-$key'),
      listenable: focus,
      builder: (context, _) => OutlinedButton(
        focusNode: focus,
        onPressed: _saving
            ? null
            : () => _openFilterPicker(key, values, labels),
        style: OutlinedButton.styleFrom(
          minimumSize: Size.zero,
          padding: EdgeInsets.zero,
          alignment: Alignment.centerLeft,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: roles.primaryText,
          textStyle: _studioBodyStyle(),
          side: BorderSide.none,
        ),
        child: InputDecorator(
          isEmpty: false,
          isFocused: focus.hasFocus,
          decoration: InputDecoration(
            labelText: _facetLabel(key),
            floatingLabelBehavior: FloatingLabelBehavior.always,
            enabled: !_saving,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 16 * _uiScale,
              vertical: 16 * _uiScale,
            ),
          ),
          child: Row(
            children: [
              Expanded(child: Text(summary, softWrap: true)),
              Icon(
                Icons.expand_more,
                color: roles.secondaryText,
                size: _uiScale > 1 ? 24 * _uiScale : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openFilterPicker(
    String key,
    List<String> values,
    Map<String, String> labels,
  ) {
    final filter = _libraryFilter(key);
    setState(() {
      _activeFilterKey = key;
      _activeFilterValues = ({...values, ...?_filters[filter]}.toList()
        ..sort());
      _activeAvailableFilterValues = values.toSet();
      _activeFilterLabels = Map.unmodifiable(labels);
      _pendingFilterValues
        ..clear()
        ..addAll(_filters[filter] ?? const []);
      _showPendingFilterValues = false;
      _filterPickerSearch.clear();
    });
  }

  Widget _filterPickerPanel(String key) {
    final query = _filterPickerSearch.text.trim().toLowerCase();
    final visible = _activeFilterValues
        .where(
          (value) =>
              (!_showPendingFilterValues ||
                  _pendingFilterValues.contains(value)) &&
              value.toLowerCase().contains(query),
        )
        .toList(growable: false);
    final pendingFilters = Map<LibraryFilter, List<String>>.from(_filters);
    if (_pendingFilterValues.isEmpty) {
      pendingFilters.remove(_libraryFilter(key));
    } else {
      pendingFilters[_libraryFilter(key)] = _pendingFilterValues.toList();
    }
    final count = _filteredInventory(
      libraryId: _filterLibraryId,
      filters: pendingFilters,
      includeWatched: _filterIncludeWatched,
    ).length;
    final unavailable = _pendingFilterValues
        .where((value) => !_activeAvailableFilterValues.contains(value))
        .toSet();
    Widget valueTile(String value) => _studioCheckboxTile(
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
        media.size.width >= LineupLayout.compact * _uiScale &&
        media.textScaler.scale(14) <= 21;
    return Material(
      type: MaterialType.transparency,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _closeFilterPicker(key),
        },
        child: Focus(
          autofocus: true,
          child: Column(
            key: Key('studio-filter-picker-$key'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Choose ${_facetLabel(key).toLowerCase()} values',
                style: _studioSectionHeadingStyle(),
              ),
              SizedBox(height: 4 * _uiScale),
              Text(
                _libraryTitle(_filterLibraryId),
                style: _studioSupportStyle(),
              ),
              SizedBox(height: 8 * _uiScale),
              TextField(
                controller: _filterPickerSearch,
                autofocus: true,
                style: _studioBodyStyle(),
                decoration: const InputDecoration(
                  labelText: 'Search values',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                ),
                onChanged: (_) => setState(() {}),
              ),
              Wrap(
                spacing: 8 * _uiScale,
                runSpacing: 8 * _uiScale,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => setState(
                      () =>
                          _showPendingFilterValues = !_showPendingFilterValues,
                    ),
                    style: _studioTextButtonStyle(),
                    child: Text('${_pendingFilterValues.length} selected'),
                  ),
                  TextButton(
                    onPressed: _pendingFilterValues.isEmpty
                        ? null
                        : () => setState(_pendingFilterValues.clear),
                    style: _studioTextButtonStyle(),
                    child: const Text('Clear selection'),
                  ),
                  if (unavailable.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(
                        () => _pendingFilterValues.removeAll(unavailable),
                      ),
                      style: _studioTextButtonStyle(),
                      child: Text('Remove ${unavailable.length} unavailable'),
                    ),
                  Text(
                    '$count matching programs',
                    style: _studioSupportStyle(),
                  ),
                ],
              ),
              if (independentlyScrollable)
                SizedBox(
                  height: (media.size.height * .29).clamp(
                    180 * _uiScale,
                    460 * _uiScale,
                  ),
                  child: ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) => valueTile(visible[index]),
                  ),
                )
              else
                for (final value in visible) valueTile(value),
              SizedBox(height: 12 * _uiScale),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8 * _uiScale,
                runSpacing: 8 * _uiScale,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => _closeFilterPicker(key),
                    style: _studioTextButtonStyle(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      final result = _pendingFilterValues.toList();
                      final filter = _libraryFilter(key);
                      _filterChanged(() {
                        if (result.isEmpty) {
                          _filters.remove(filter);
                        } else {
                          _filters[filter] = List.unmodifiable(result);
                        }
                        _activeFilterKey = null;
                      });
                      _restoreFilterFocus(key);
                    },
                    style: _studioFilledButtonStyle(),
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

  void _closeFilterPicker(String key) {
    setState(() => _activeFilterKey = null);
    _restoreFilterFocus(key);
  }

  void _restoreFilterFocus(String key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _filterControlFocus[key]?.requestFocus();
    });
  }

  String _libraryTitle(String? id) =>
      widget.controller.libraries
          .where((library) => library.id == id)
          .firstOrNull
          ?.title ??
      id ??
      'Library';

  Widget _studioBrowseResultRow({
    required PlexMediaItem item,
    required bool available,
    required Set<String> selectedIds,
  }) {
    final titleStyle = _studioBodyStyle();
    final subtitleStyle = _studioSupportStyle();
    final selected = selectedIds.contains(item.id);
    final onTap = selected
        ? null
        : _browseSelecting
        ? () => _toggleBrowseSelection(item)
        : () => _addManualItem(item);
    final browseCheckbox = Checkbox(
      value: _browseSelection.contains(item.id),
      onChanged: selected ? null : (_) => _toggleBrowseSelection(item),
    );
    final subtitle = item.grandparentTitle != null || !available
        ? Text(
            [
              ?item.grandparentTitle,
              if (!available) 'Unavailable — retained off air if added',
            ].join(' · '),
            style: subtitleStyle,
          )
        : null;
    final action = _browseSelecting
        ? null
        : TextButton(
            onPressed: _saving || selected ? null : () => _addManualItem(item),
            style: _studioScaledTextButtonStyle(),
            child: Text(selected ? 'Added' : 'Add'),
          );
    return Semantics(
      key: Key('studio-result-${item.id}'),
      container: true,
      button: onTap != null,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: 72 * _uiScale),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 16 * _uiScale,
                vertical: 8 * _uiScale,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (_browseSelecting) ...[
                    SizedBox(
                      width: 48 * _uiScale,
                      height: 48 * _uiScale,
                      child: Center(
                        child: Transform.scale(
                          scale: _uiScale,
                          child: browseCheckbox,
                        ),
                      ),
                    ),
                    SizedBox(width: 16 * _uiScale),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title, style: titleStyle),
                        ?subtitle,
                      ],
                    ),
                  ),
                  if (action != null) ...[
                    SizedBox(width: 16 * _uiScale),
                    action,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _manualEditor() {
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
    final selectedIds = _manualEntries.map((entry) => entry.id).toSet();
    final rundownQuery = _rundownSearch.text.trim().toLowerCase();
    final rundownEntries = [
      for (var index = 0; index < _manualEntries.length; index++)
        if (_manualEntrySearchText(
          _manualEntries[index],
          inventoryById,
        ).contains(rundownQuery))
          (entry: _manualEntries[index], index: index),
    ];
    final countLabel =
        '${visible.length} matching, ${_manualEntries.length} selected';
    final roles = LineupTheme.of(context);
    Widget stageTab({
      required Key key,
      required bool selected,
      required String label,
      required VoidCallback? onPressed,
    }) => Semantics(
      selected: selected,
      button: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? roles.progressFill : Colors.transparent,
              width: 2 * _uiScale,
            ),
          ),
        ),
        child: TextButton(
          key: key,
          onPressed: onPressed,
          style: _studioTextButtonStyle().copyWith(
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? roles.mutedText
                  : selected
                  ? roles.primaryText
                  : roles.secondaryText,
            ),
          ),
          child: Text(label),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _inventoryStatus(hasInventory: inventory.isNotEmpty),
        Wrap(
          spacing: 8 * _uiScale,
          runSpacing: 8 * _uiScale,
          children: [
            stageTab(
              key: const Key('studio-manual-browse-stage'),
              selected: !_manualRundown,
              label: 'Browse library · ${visible.length}',
              onPressed: _saving
                  ? null
                  : () => setState(() => _manualRundown = false),
            ),
            stageTab(
              key: const Key('studio-manual-rundown-stage'),
              selected: _manualRundown,
              label: 'Channel programs · ${_manualEntries.length}',
              onPressed: _saving
                  ? null
                  : () => setState(() => _manualRundown = true),
            ),
          ],
        ),
        SizedBox(height: 6 * _uiScale),
        Text(countLabel, style: _studioSupportStyle()),
        if (_settledCountLabel.isNotEmpty)
          Semantics(
            liveRegion: true,
            label: _settledCountLabel,
            child: const SizedBox.shrink(),
          ),
        SizedBox(height: 12 * _uiScale),
        if (!_manualRundown) ...[
          TextField(
            key: const Key('studio-search'),
            controller: _search,
            focusNode: _searchFocus,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: 'Search title or show title',
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
            onChanged: (_) => _browseChanged(),
          ),
          SizedBox(height: 12 * _uiScale),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 960 * _uiScale
                  ? 4
                  : constraints.maxWidth >= 700 * _uiScale
                  ? 3
                  : constraints.maxWidth >= 480 * _uiScale
                  ? 2
                  : 1;
              final gap = 12 * _uiScale;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: 16 * _uiScale,
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
                    child: DropdownButtonFormField<String>(
                      key: const Key('studio-media-type'),
                      isExpanded: true,
                      iconSize: 24 * _uiScale,
                      itemHeight: _studioDropdownItemHeight,
                      initialValue: _manualMediaType ?? '',
                      style: _studioBodyStyle(),
                      decoration: const InputDecoration(
                        labelText: 'Media type',
                        hintText: 'All types',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
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
                              () => _manualMediaType = value?.isEmpty == true
                                  ? null
                                  : value,
                            ),
                    ),
                  ),
                  for (final key in _facetKeys)
                    SizedBox(
                      width: width,
                      child: _facetDropdown(
                        key: key,
                        values: facets.values[key] ?? const [],
                        labels: facets.labels[key] ?? const {},
                        selected: _manualFilters[key],
                        onChanged: (value) => _browseChanged(() {
                          if (value == null) {
                            _manualFilters.remove(key);
                          } else {
                            _manualFilters[key] = value;
                          }
                        }),
                      ),
                    ),
                ],
              );
            },
          ),
          SizedBox(height: 12 * _uiScale),
          Wrap(
            spacing: 8 * _uiScale,
            runSpacing: 8 * _uiScale,
            children: _browseSelecting
                ? [
                    Text(
                      '${_browseSelection.length} selected${_browseSelection.where((id) => !visible.any((item) => item.id == id)).isEmpty ? '' : ' · selections outside this view'}${unavailableSelections == 0 ? '' : ' · $unavailableSelections unavailable; retained off air if added'}',
                    ),
                    TextButton(
                      onPressed: _browseSelection.isEmpty
                          ? null
                          : () => _setShowBrowseSelected(true),
                      style: _uiScale > 1
                          ? _studioScaledTextButtonStyle()
                          : null,
                      child: const Text('Show selected'),
                    ),
                    if (_showBrowseSelected)
                      TextButton(
                        onPressed: () => _setShowBrowseSelected(false),
                        style: _uiScale > 1
                            ? _studioScaledTextButtonStyle()
                            : null,
                        child: const Text('Back to results'),
                      ),
                    TextButton(
                      onPressed: () => setState(() {
                        _browseSelecting = false;
                        _browseSelection.clear();
                        _browseSelectionItems.clear();
                        _showBrowseSelected = false;
                      }),
                      style: _uiScale > 1
                          ? _studioScaledTextButtonStyle()
                          : null,
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: _browseSelection.isEmpty
                          ? null
                          : _addBrowseSelected,
                      style: _uiScale > 1
                          ? _studioScaledFilledButtonStyle()
                          : null,
                      child: Text('Add selected (${_browseSelection.length})'),
                    ),
                  ]
                : [
                    OutlinedButton(
                      onPressed: () => setState(() => _browseSelecting = true),
                      style: _uiScale > 1
                          ? _studioScaledOutlinedButtonStyle()
                          : null,
                      child: const Text('Select'),
                    ),
                    if (_lastAddedEntries.isNotEmpty)
                      TextButton(
                        onPressed: _undoLastAddition,
                        style: _uiScale > 1
                            ? _studioScaledTextButtonStyle()
                            : null,
                        child: const Text('Undo last addition'),
                      ),
                  ],
          ),
          SizedBox(
            height: _studioSize(300, 300),
            child: ListView.builder(
              key: const Key('studio-results'),
              controller: _browseScroll,
              itemCount: shown.length,
              itemBuilder: (context, index) {
                final item = shown[index];
                final available = _playableInventory.byId.containsKey(item.id);
                if (_uiScale > 1) {
                  return _studioBrowseResultRow(
                    item: item,
                    available: available,
                    selectedIds: selectedIds,
                  );
                }
                final browseCheckbox = Checkbox(
                  value: _browseSelection.contains(item.id),
                  onChanged: selectedIds.contains(item.id)
                      ? null
                      : (_) => _toggleBrowseSelection(item),
                );
                return ListTile(
                  key: Key('studio-result-${item.id}'),
                  minTileHeight: _uiScale > 1 ? 56 * _uiScale : null,
                  contentPadding: _uiScale > 1
                      ? EdgeInsets.symmetric(horizontal: 16 * _uiScale)
                      : null,
                  horizontalTitleGap: _uiScale > 1 ? 16 * _uiScale : null,
                  title: Text(item.title),
                  subtitle: item.grandparentTitle != null || !available
                      ? Text(
                          [
                            ?item.grandparentTitle,
                            if (!available)
                              'Unavailable — retained off air if added',
                          ].join(' · '),
                        )
                      : null,
                  leading: _browseSelecting
                      ? _uiScale > 1
                            ? SizedBox(
                                width: 48 * _uiScale,
                                height: 48 * _uiScale,
                                child: Center(
                                  child: Transform.scale(
                                    scale: _uiScale,
                                    child: browseCheckbox,
                                  ),
                                ),
                              )
                            : browseCheckbox
                      : null,
                  trailing: _browseSelecting
                      ? null
                      : TextButton(
                          onPressed: _saving || selectedIds.contains(item.id)
                              ? null
                              : () => _addManualItem(item),
                          style: _uiScale > 1
                              ? _studioScaledTextButtonStyle()
                              : null,
                          child: Text(
                            selectedIds.contains(item.id) ? 'Added' : 'Add',
                          ),
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
              labelText: 'Find a channel program',
              suffixIcon: rundownQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear channel program search',
                      onPressed: () => setState(_rundownSearch.clear),
                      icon: Icon(Icons.clear, size: 24 * _uiScale),
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          SizedBox(height: 8 * _uiScale),
          Text(
            _manualEntries.isEmpty
                ? 'No programs selected. Return to Browse library to add programming.'
                : '${rundownEntries.length} of ${_manualEntries.length} shown · Alt+Up/Down reorders · Delete removes${rundownQuery.isEmpty ? '' : ' · Clear search to drag reorder'}',
          ),
          SizedBox(height: 8 * _uiScale),
          SizedBox(
            height: rundownEntries.isEmpty ? 0 : 420 * _uiScale,
            child: ReorderableListView.builder(
              key: const Key('studio-rundown'),
              scrollController: _rundownScroll,
              buildDefaultDragHandles: false,
              itemCount: rundownEntries.length,
              onReorderItem: _saving || rundownQuery.isNotEmpty
                  ? (_, _) {}
                  : (from, to) => _reorderManual(from, to),
              itemBuilder: (context, visibleIndex) {
                final item = rundownEntries[visibleIndex];
                return _rundownRow(
                  item.entry,
                  item.index,
                  !inventoryById.containsKey(item.entry.id),
                  inventoryById,
                  dragIndex: rundownQuery.isEmpty ? visibleIndex : null,
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  void _addManualItem(PlexMediaItem item) {
    _refreshPlayableInventory();
    final current = _playableInventory.byId[item.id];
    if (current == null) {
      setState(() {});
      return;
    }
    final entry = _newManualEntry(channelItemFor(current));
    _changed(() {
      _manualEntries.add(entry);
      _lastAddedEntries = [entry];
    });
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
    final added = <_ManualEntry>[];
    _refreshPlayableInventory();
    _changed(() {
      for (final id in _browseSelection) {
        if (_manualEntries.any((entry) => entry.id == id)) continue;
        if (_playableInventory.byId[id] ?? _browseSelectionItems[id]
            case final item?) {
          final entry = _newManualEntry(channelItemFor(item));
          _manualEntries.add(entry);
          added.add(entry);
        }
      }
      _lastAddedEntries = List.unmodifiable(added);
      _browseSelection.clear();
      _browseSelectionItems.clear();
      _browseSelecting = false;
      _showBrowseSelected = false;
    });
  }

  void _undoLastAddition() {
    final undo = _lastAddedEntries.toSet();
    _changed(() {
      _removeManualEntriesWhere(undo.contains);
      _lastAddedEntries = const [];
    });
  }

  void _refreshPlayableInventory() {
    _playableInventory = widget.controller.playableInventory;
  }

  List<PlexLibrary> get _selectedLibraries => widget.controller.libraries
      .where(
        (library) => widget.controller.selectedLibraryIds.contains(library.id),
      )
      .toList(growable: false);

  Widget _inventoryStatus({bool? hasInventory}) {
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
            style: _uiScale > 1 ? _studioScaledTextButtonStyle() : null,
            child: const Text('Retry in Generate lineup'),
          ),
        ],
      );
    }
    if (!(hasInventory ?? _playableInventory.byId.isNotEmpty)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'No usable programming is loaded. A new channel needs a selected Plex movie/show library or video playlist.',
          ),
          TextButton(
            onPressed: _saving ? null : _openGenerateLineup,
            style: _uiScale > 1 ? _studioScaledTextButtonStyle() : null,
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
      iconSize: 24 * _uiScale,
      itemHeight: _studioDropdownItemHeight,
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
    required Map<String, String> labels,
    required String? selected,
    required ValueChanged<String?> onChanged,
  }) {
    final fieldValue = selected ?? '';
    return SizedBox(
      key: Key('studio-facet-$key'),
      child: DropdownButtonFormField<String>(
        key: ValueKey(fieldValue),
        isExpanded: true,
        iconSize: 24 * _uiScale,
        itemHeight: _studioDropdownItemHeight,
        initialValue: fieldValue,
        decoration: InputDecoration(labelText: _facetLabel(key)),
        items: [
          const DropdownMenuItem(value: '', child: Text('Any')),
          if (selected != null && !values.contains(selected))
            DropdownMenuItem(
              value: selected,
              child: Text('$selected (unavailable — retained)'),
            ),
          for (final value in values)
            DropdownMenuItem(value: value, child: Text(labels[value] ?? value)),
        ],
        onChanged: _saving
            ? null
            : (value) => onChanged(value?.isEmpty == true ? null : value),
      ),
    );
  }

  _FacetOptions _facetOptions(
    String? libraryId, {
    Iterable<PlexMediaItem>? inventory,
  }) {
    final values = {for (final key in _facetKeys) key: <String>{}};
    final labels = {for (final key in _facetKeys) key: <String, String>{}};
    void add(String key, String raw) {
      final filter = _libraryFilter(key);
      final identity = canonicalFilterIdentity(filter, raw);
      if (identity.isEmpty) return;
      final label = raw.trim();
      values[key]!.add(identity);
      labels[key]!.update(
        identity,
        (current) => _preferredFacetLabel(filter, current, label),
        ifAbsent: () => label,
      );
    }

    for (final item in (inventory ?? _playableInventory.byId.values).where(
      (item) => libraryId == null || item.libraryId == libraryId,
    )) {
      for (final value in item.collections) {
        add('collection', value);
      }
      for (final value in item.genres) {
        add('genre', value);
      }
      if (item.studio case final studio? when studio.isNotEmpty) {
        add('studio', studio);
      }
      for (final value in item.actors) {
        add('actor', value);
      }
      for (final value in item.directors) {
        add('director', value);
      }
      if (channelDecadeForYear(item.year) case final decade?) {
        add('decade', decade);
      }
    }
    return (
      values: {
        for (final entry in values.entries)
          entry.key: entry.value.toList()..sort(),
      },
      labels: {
        for (final entry in labels.entries)
          entry.key: Map<String, String>.unmodifiable(entry.value),
      },
    );
  }

  List<PlexMediaItem> _filteredInventory({
    Iterable<PlexMediaItem>? inventory,
    String? libraryId,
    String? mediaType,
    Map<Object, Object> filters = const {},
    String search = '',
    bool includeWatched = true,
  }) {
    final query = search.trim().toLowerCase();
    var items = (inventory ?? _playableInventory.byId.values).where(
      (item) =>
          (libraryId == null || item.libraryId == libraryId) &&
          (includeWatched || !item.viewed) &&
          (mediaType == null || item.type == mediaType) &&
          (query.isEmpty ||
              item.title.toLowerCase().contains(query) ||
              (item.grandparentTitle?.toLowerCase().contains(query) ?? false)),
    );
    for (final filter in filters.entries) {
      final key = filter.key is LibraryFilter
          ? (filter.key as LibraryFilter).name
          : filter.key as String;
      final values = filter.value is List<String>
          ? filter.value as List<String>
          : [filter.value as String];
      items = switch (key) {
        'collection' => items.where(
          (item) => item.collections.any(values.contains),
        ),
        'genre' => items.where((item) => item.genres.any(values.contains)),
        'studio' => items.where((item) => values.contains(item.studio)),
        'actor' => items.where(
          (item) => item.actors.any(
            (value) => values.contains(
              canonicalFilterIdentity(LibraryFilter.actor, value),
            ),
          ),
        ),
        'director' => items.where(
          (item) => item.directors.any(
            (value) => values.contains(
              canonicalFilterIdentity(LibraryFilter.director, value),
            ),
          ),
        ),
        'decade' => items.where(
          (item) => values.contains(channelDecadeForYear(item.year)),
        ),
        'sort' when values.single == 'added:desc' =>
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
      '${_manualMatches.length} matching, ${_manualEntries.length} selected';

  Widget _rundownRow(
    _ManualEntry entry,
    int index,
    bool unavailable,
    Map<String, PlexMediaItem> inventoryById, {
    int? dragIndex,
  }) {
    final title = _manualEntryTitle(entry, inventoryById);
    final repeatedTitle =
        _manualEntries
            .where(
              (candidate) =>
                  _manualEntryTitle(candidate, inventoryById) == title,
            )
            .length >
        1;
    final positionedTitle = repeatedTitle
        ? '$title, item ${index + 1} of ${_manualEntries.length}'
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
      '${index + 1} of ${_manualEntries.length}',
      _compactDuration(duration),
      if (season != null || episode != null)
        'S${season ?? '—'} E${episode ?? '—'}',
    ];
    final tile = ListTile(
      key: entry.occurrence == 1 ? Key('studio-rundown-${entry.id}') : null,
      title: Text(title),
      minTileHeight: _uiScale > 1 ? 56 * _uiScale : null,
      contentPadding: _uiScale > 1
          ? EdgeInsets.symmetric(horizontal: 16 * _uiScale)
          : null,
      horizontalTitleGap: _uiScale > 1 ? 16 * _uiScale : null,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(facts.join(' · ')),
          if (unavailable) const Text('Unavailable — retained until removed'),
        ],
      ),
      trailing: Wrap(
        spacing: 4 * _uiScale,
        children: [
          if (dragIndex case final visibleIndex?)
            Tooltip(
              message: 'Drag $positionedTitle to reorder',
              child: ReorderableDragStartListener(
                index: visibleIndex,
                child: Icon(Icons.drag_handle, size: 24 * _uiScale),
              ),
            ),
          IconButton(
            tooltip: 'Move $positionedTitle earlier in $_draftChannelLabel',
            onPressed: _saving || index == 0
                ? null
                : () => _moveManual(entry, -1),
            style: _uiScale > 1 ? _studioIconButtonStyle() : null,
            icon: const Icon(Icons.arrow_upward),
          ),
          IconButton(
            tooltip: 'Move $positionedTitle later in $_draftChannelLabel',
            onPressed: _saving || index == _manualEntries.length - 1
                ? null
                : () => _moveManual(entry, 1),
            style: _uiScale > 1 ? _studioIconButtonStyle() : null,
            icon: const Icon(Icons.arrow_downward),
          ),
          IconButton(
            tooltip: 'Move $positionedTitle before or after another program',
            onPressed: _saving ? null : () => _moveManualTo(entry),
            style: _uiScale > 1 ? _studioIconButtonStyle() : null,
            icon: const Icon(Icons.low_priority),
          ),
          IconButton(
            tooltip: 'Remove $positionedTitle from $_draftChannelLabel',
            onPressed: _saving ? null : () => _removeManual(entry),
            style: _uiScale > 1 ? _studioIconButtonStyle() : null,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
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
                border: Border.all(
                  color: focus.hasFocus
                      ? roles.focusBorder
                      : Colors.transparent,
                  width: focus.hasFocus ? roles.focusBorderWidth : 1,
                ),
                borderRadius: BorderRadius.circular(roles.panelRadius),
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
    _ManualEntry entry,
    Map<String, PlexMediaItem> inventoryById,
  ) => inventoryById[entry.id]?.title ?? entry.item.title;

  String _manualEntrySearchText(
    _ManualEntry entry,
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

  String get _draftChannelLabel => _name.text.trim().isEmpty
      ? 'new channel'
      : 'channel ${_name.text.trim()}';

  void _moveManual(_ManualEntry entry, int delta) {
    if (_saving) return;
    final from = _manualEntries.indexOf(entry);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= _manualEntries.length) return;
    _changed(() {
      _manualEntries.removeAt(from);
      _manualEntries.insert(to, entry);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rundownFocus[entry]?.requestFocus();
    });
  }

  void _reorderManual(int from, int to) {
    if (_saving || from == to) return;
    final entry = _manualEntries[from];
    _changed(() {
      _manualEntries.removeAt(from);
      _manualEntries.insert(to, entry);
    });
  }

  Future<void> _moveManualTo(_ManualEntry entry) async {
    final target = await showDialog<({int index, bool after})>(
      context: context,
      builder: (context) => _MoveProgramDialog(
        entries: _manualEntries,
        moving: entry,
        titleFor: (candidate) =>
            _manualEntryTitle(candidate, _playableInventory.byId),
      ),
    );
    if (target == null || !mounted) return;
    final from = _manualEntries.indexOf(entry);
    if (from < 0) return;
    _changed(() {
      _manualEntries.removeAt(from);
      var destination = target.index;
      if (from < destination) destination--;
      if (target.after) destination++;
      _manualEntries.insert(destination.clamp(0, _manualEntries.length), entry);
    });
  }

  void _removeManual(_ManualEntry entry) {
    if (_saving) return;
    final index = _manualEntries.indexOf(entry);
    if (index < 0) return;
    _changed(() {
      _manualEntries.removeAt(index);
      if (_manualEntries.isEmpty) _manualRundown = false;
    });
    final nextEntry = _manualEntries.isEmpty
        ? null
        : _manualEntries[index.clamp(0, _manualEntries.length - 1)];
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

  _ManualEntry _newManualEntry(ChannelItem item) {
    final count = (_manualKeyCounts[item.id] ?? 0) + 1;
    _manualKeyCounts[item.id] = count;
    return _ManualEntry(id: item.id, item: item, occurrence: count);
  }

  void _removeManualEntriesWhere(bool Function(_ManualEntry) test) {
    final removed = _manualEntries.where(test).toList(growable: false);
    _manualEntries.removeWhere(test);
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

  Widget _stationCard({
    required bool hasShowGrouping,
    required bool confirmedMovieOnly,
  }) {
    final roles = LineupTheme.of(context);
    return Container(
      key: const Key('studio-station'),
      padding: EdgeInsets.only(top: 8 * _uiScale, bottom: 16 * _uiScale),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: roles.subtleBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              final numberWidth =
                  120 * _uiScale * (textScale > 1 ? textScale : 1);
              final identity = Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const Key('studio-name'),
                      controller: _name,
                      focusNode: _nameFocus,
                      enabled: !_saving,
                      style: _studioBodyStyle(),
                      decoration: const InputDecoration(
                        labelText: 'Channel name',
                        hintText: 'Required',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                      ),
                      onChanged: (_) => _changed(),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Enter a channel name.'
                          : null,
                    ),
                  ),
                  SizedBox(width: 12 * _uiScale),
                  SizedBox(
                    width: numberWidth,
                    child: TextFormField(
                      key: const Key('studio-number'),
                      controller: _number,
                      focusNode: _numberFocus,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      style: _studioBodyStyle(),
                      decoration: const InputDecoration(
                        labelText: 'Number',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                      ),
                      onChanged: (_) => _changed(),
                      validator: _validateNumber,
                    ),
                  ),
                ],
              );
              final playback = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_generated) ...[
                    Text(
                      'Playback order · Read-only',
                      style: _studioSupportStyle(),
                    ),
                    SizedBox(height: 12 * _uiScale),
                    Text(
                      _rhythmLabel(_playbackMode, _blockSize),
                      style: _studioBodyStyle(),
                    ),
                  ] else
                    _playbackEditor(confirmedMovieOnly),
                ],
              );
              if (constraints.maxWidth < 760 * _uiScale) {
                return Column(
                  children: [
                    identity,
                    SizedBox(height: 12 * _uiScale),
                    playback,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 9, child: identity),
                  SizedBox(width: 24 * _uiScale),
                  Expanded(flex: 11, child: playback),
                ],
              );
            },
          ),
          if (_conflictingChannel != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _saving || _lowestFreeNumber() == null
                    ? null
                    : _useNextAvailable,
                style: _uiScale > 1 ? _studioScaledTextButtonStyle() : null,
                child: const Text('Use next available'),
              ),
            ),
          if (!_generated &&
              confirmedMovieOnly &&
              _playbackMode != PlaybackMode.block)
            Focus(
              child: Semantics(
                key: const Key('studio-mini-marathon-explanation'),
                focusable: true,
                child: const Text(
                  'Mini-marathons is available when this source includes episodes with series information.',
                ),
              ),
            ),
          if (_generated) ...[
            SizedBox(height: 12 * _uiScale),
            Text(
              'Generator recipe: ${_sourceLabel(_source, widget.controller)}. Schedule timing stays the same.',
            ),
          ] else if (_playbackMode == PlaybackMode.block) ...[
            if (!hasShowGrouping) SizedBox(height: 12 * _uiScale),
            if (!hasShowGrouping)
              Focus(
                child: Semantics(
                  key: const Key('studio-mini-marathon-explanation'),
                  focusable: true,
                  child: const Text(
                    'Mini-marathons needs episodes grouped by show title or show artwork. Choose another rhythm or add grouped episodes.',
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _playbackEditor(bool confirmedMovieOnly) => LayoutBuilder(
    builder: (context, constraints) {
      final block = _playbackMode == PlaybackMode.block;
      final inline =
          block &&
          constraints.maxWidth >= 740 * _uiScale &&
          MediaQuery.textScalerOf(context).scale(14) <= 21;
      return Wrap(
        spacing: 12 * _uiScale,
        runSpacing: 16 * _uiScale,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: inline
                ? constraints.maxWidth - 474 * _uiScale
                : constraints.maxWidth,
            child: DropdownButtonFormField<PlaybackMode>(
              key: const Key('studio-playback-order'),
              initialValue: _playbackMode,
              isExpanded: true,
              iconSize: 24 * _uiScale,
              itemHeight: _studioDropdownItemHeight,
              decoration: const InputDecoration(
                labelText: 'Playback order',
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
              items: [
                const DropdownMenuItem(
                  value: PlaybackMode.shuffle,
                  child: Text('Shuffle'),
                ),
                const DropdownMenuItem(
                  value: PlaybackMode.sequential,
                  child: Text('In order'),
                ),
                DropdownMenuItem(
                  value: PlaybackMode.block,
                  enabled:
                      !confirmedMovieOnly ||
                      _playbackMode == PlaybackMode.block,
                  child: const Text('Mini-marathons'),
                ),
              ],
              onChanged: _busy
                  ? null
                  : (value) {
                      if (value == null) return;
                      _changed(() {
                        _playbackMode = value;
                        _blockSize ??= 3;
                      });
                    },
            ),
          ),
          if (block) ...[
            SizedBox(
              width: inline ? 220 * _uiScale : constraints.maxWidth,
              child: DropdownButtonFormField<int>(
                key: const Key('studio-block-size'),
                isExpanded: true,
                iconSize: 24 * _uiScale,
                itemHeight: _studioDropdownItemHeight,
                initialValue: (_blockSize ?? 3) >= 2 && (_blockSize ?? 3) <= 5
                    ? _blockSize ?? 3
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Episodes per block',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                ),
                items: [
                  for (var size = 2; size <= 5; size++)
                    DropdownMenuItem(value: size, child: Text('$size')),
                ],
                onChanged: _saving
                    ? null
                    : (value) => _changed(() => _blockSize = value),
              ),
            ),
            SizedBox(
              width: inline ? 230 * _uiScale : constraints.maxWidth,
              child: _studioSwitchTile(
                key: const Key('studio-include-specials'),
                contentPadding: EdgeInsets.zero,
                value: _includeSpecials,
                title: const Text('Include specials'),
                onChanged: _saving
                    ? null
                    : (value) => _changed(() => _includeSpecials = value),
              ),
            ),
            if (_includeSpecials)
              const Text('Season 0 specials play after regular seasons.'),
          ],
        ],
      );
    },
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
      includeSpecials: _includeSpecials,
      scheduleVersion: widget.channel!.scheduleVersion,
      scheduleTransition: widget.channel!.scheduleTransition,
    );
    widget.onDuplicate(source);
  }

  ContentSource _editedSource() {
    if (_sourceReadOnly) return _source;
    return switch (_sourceChoice) {
      _SourceChoice.library => _librarySource(
        _filterLibraryId,
        filters: Map.unmodifiable(_filters),
      ),
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
    final available = _playableInventory.byId;
    return _manualEntries
        .map((entry) {
          final item = available[entry.id];
          return item == null ? entry.item : channelItemFor(item);
        })
        .toList(growable: false);
  }

  LibrarySource _librarySource(
    String? id, {
    Map<LibraryFilter, List<String>> filters = const {},
  }) {
    final library = _selectedLibraries
        .where((library) => library.id == id)
        .firstOrNull;
    if (library == null) throw const FormatException('Select a library.');
    return LibrarySource(
      libraryId: library.id,
      libraryType: library.type,
      includeWatched: _filterIncludeWatched,
      filters: filters,
      order: _libraryDraftOrder(
        library.id,
        includeWatched: _filterIncludeWatched,
        filters: filters,
        libraryType: library.type,
      ),
    );
  }

  LibraryOrder _libraryDraftOrder(
    String? libraryId, {
    required bool includeWatched,
    Map<LibraryFilter, List<String>> filters = const {},
    PlexLibraryType? libraryType,
  }) {
    final original = _source;
    if (original is! LibrarySource || libraryId == null) {
      return _playbackMode == PlaybackMode.sequential
          ? LibraryOrder.title
          : LibraryOrder.supplied;
    }
    final type =
        libraryType ??
        _selectedLibraries
            .where((library) => library.id == libraryId)
            .firstOrNull
            ?.type;
    if (type == null) return original.order;
    final candidate = LibrarySource(
      libraryId: libraryId,
      libraryType: type,
      includeWatched: includeWatched,
      filters: filters,
      order: original.order,
    );
    final recipeUnchanged = canonicalSourceEquals(original, candidate);
    final originalMode =
        _expectedBase?.playbackMode ?? widget.channel?.playbackMode;
    if (recipeUnchanged &&
        (original.order == LibraryOrder.addedDescending ||
            originalMode == _playbackMode)) {
      return original.order;
    }
    return _playbackMode == PlaybackMode.sequential
        ? LibraryOrder.title
        : LibraryOrder.supplied;
  }

  _DraftResolution _resolveDraftContent() {
    late final ContentSource source;
    try {
      source = _editedSource();
    } on FormatException catch (error) {
      return (source: null, content: null, sourceError: error.message);
    }
    try {
      return (
        source: source,
        content: resolveContent(
          source,
          _playableInventory.media,
          _playableInventory.playlists,
        ),
        sourceError: null,
      );
    } on FormatException {
      return (source: source, content: null, sourceError: null);
    }
  }

  bool _confirmedMovieOnly(_DraftResolution? resolution) {
    final content = resolution?.content;
    if (content == null || content.isEmpty) return false;
    if (resolution!.source is LibrarySource &&
        widget.controller.libraryScanStatus != LibraryScanStatus.complete) {
      return false;
    }
    return content.every((item) => item.mediaKind == ChannelMediaKind.movie);
  }

  String? _programmingError(_DraftResolution resolution) {
    if (resolution.sourceError case final error?) return error;
    final source = resolution.source;
    if (source == null) return 'Choose a programming source.';
    final liveSourceError = _liveSourceError(source, resolution.content);
    if (liveSourceError != null) return liveSourceError;
    final resolved = resolution.content;
    if (resolved == null) {
      return 'This source contains an unsupported filter and cannot be broadened. Choose a supported replacement.';
    }
    switch (source) {
      case ManualSource(:final items):
        if (items.isEmpty) return 'Select at least one program.';
      case MixedSource():
        if (resolved.isEmpty && !hasNonemptyRetainedManualContent(source)) {
          return 'This preserved mixed source has no currently playable programs. Choose a replacement source.';
        }
      case LibrarySource() || PlaylistSource():
        break;
    }
    if (_playbackMode == PlaybackMode.block &&
        !resolved.any(
          (item) =>
              item.showTitle?.trim().isNotEmpty == true ||
              item.showThumb?.trim().isNotEmpty == true,
        )) {
      return 'Mini-marathons needs episodes grouped by show title or show artwork.';
    }
    if (_playbackMode == PlaybackMode.block &&
        ((_blockSize ?? 3) < 2 || (_blockSize ?? 3) > 5)) {
      return 'Choose a mini-marathon size from 2 to 5.';
    }
    return null;
  }

  String? _liveSourceError(ContentSource source, List<ChannelItem>? resolved) {
    switch (source) {
      case LibrarySource(:final libraryId, :final filters):
        if (!_selectedLibraries.any((library) => library.id == libraryId)) {
          return 'The saved library is unavailable. Choose a selected Plex library.';
        }
        if (widget.controller.libraryScanStatus == LibraryScanStatus.scanning) {
          return filters.isNotEmpty
              ? 'Checking filters while library programming loads.'
              : 'Checking library programming while the selected Plex library finishes loading.';
        }
        final available = _facetOptions(libraryId).values;
        final missing = [
          for (final entry in filters.entries)
            ...entry.value.where(
              (value) =>
                  !(available[entry.key.name] ?? const []).contains(value),
            ),
        ];
        if (missing.isNotEmpty &&
            widget.controller.libraryScanStatus == LibraryScanStatus.complete) {
          return '${missing.length} selected filter ${missing.length == 1 ? 'value is' : 'values are'} unavailable. Replace or remove them before saving.';
        }
        if (resolved == null) {
          return 'This source contains an unsupported filter. Choose a supported replacement.';
        }
        if (resolved.isEmpty) {
          return 'This library and its filters match no playable programs. Choose a replacement source.';
        }
      case PlaylistSource(:final playlistId):
        if (!_playableInventory.playlists.any(
          (playlist) => playlist.id == playlistId,
        )) {
          return 'The saved playlist is unavailable. Choose an available video playlist.';
        }
        if (resolved?.isEmpty ?? false) {
          return 'This playlist has no playable programs. Choose another playlist.';
        }
      case MixedSource(:final sources):
        for (final child in sources) {
          List<ChannelItem>? childContent;
          try {
            childContent = resolveContent(
              child,
              _playableInventory.media,
              _playableInventory.playlists,
            );
          } on FormatException {
            childContent = null;
          }
          if (_liveSourceError(child, childContent) case final error?) {
            return error;
          }
        }
      case ManualSource():
        break;
    }
    return null;
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
    includeSpecials: _effectiveIncludeSpecials,
    scheduleVersion: _retainsSchedule(_editedSource())
        ? _expectedBase!.scheduleVersion
        : currentScheduleVersion,
    scheduleTransition: _retainsSchedule(_editedSource())
        ? _expectedBase!.scheduleTransition
        : null,
  );

  Channel get _previewDraft => Channel(
    id: _id,
    number: int.tryParse(_number.text) ?? 1,
    name: _name.text.trim().isEmpty ? 'New channel' : _name.text.trim(),
    source: _displaySource,
    playbackMode: _playbackMode,
    anchor: _candidateAnchor ?? _anchor,
    shuffleSeed: _candidateShuffleSeed ?? _shuffleSeed,
    blockSize: _generated
        ? _blockSize
        : widget.mode == ChannelStudioMode.duplicateCustom
        ? _blockSize
        : _playbackMode == PlaybackMode.block
        ? (_blockSize ?? 3)
        : null,
    builderKey: _builderKey,
    includeSpecials: _effectiveIncludeSpecials,
    scheduleVersion: _retainsSchedule(_displaySource)
        ? _expectedBase!.scheduleVersion
        : currentScheduleVersion,
    scheduleTransition: _retainsSchedule(_displaySource)
        ? _expectedBase!.scheduleTransition
        : null,
  );

  bool _retainsSchedule(ContentSource source) {
    final base = _expectedBase;
    return base != null &&
        canonicalSourceEquals(base.source, source) &&
        base.playbackMode == _playbackMode &&
        (_playbackMode != PlaybackMode.block ||
            (base.blockSize ?? 3) == _effectiveBlockSize) &&
        base.includeSpecials == _effectiveIncludeSpecials;
  }

  bool _isCurrentAirCheckStatus(ChannelAirCheckStatus? status) =>
      status != null &&
      status.snapshotKey ==
          channelAirCheckSnapshotKey(
            _previewDraft,
            widget.controller.contentGeneration,
          ) &&
      (status.validity == ChannelAirCheckValidity.valid ||
          status.validity == ChannelAirCheckValidity.retainedOffAir);

  bool get _airCheckCanSave => _isCurrentAirCheckStatus(_airCheckStatus);
  bool get _hasPendingProgrammingChoice =>
      _activeFilterKey != null || _browseSelecting;

  void _stageScheduleIdentity(String? programmingError) {
    if (_scheduleIdentityCommitted ||
        programmingError != null ||
        _candidateAnchor != null) {
      return;
    }
    _candidateAnchor = _clock().toUtc();
    _candidateShuffleSeed = stableChannelSeed(_id);
  }

  void _commitScheduleIdentity() {
    if (_scheduleIdentityCommitted || !mounted) return;
    final anchor = _candidateAnchor;
    final seed = _candidateShuffleSeed;
    if (anchor == null || seed == null) return;
    setState(() {
      _anchor = anchor;
      _shuffleSeed = seed;
      _candidateAnchor = null;
      _candidateShuffleSeed = null;
      _scheduleIdentityCommitted = true;
      _baselineDraftSignature = {
        ..._baselineDraftSignature,
        'anchor': anchor.toIso8601String(),
        'shuffleSeed': seed,
      };
      _dirty = !canonicalChannelValueEquals(
        _draftSignature,
        _baselineDraftSignature,
      );
    });
  }

  Future<void> _save({Channel? rebasedExpected}) async {
    if (_busy) return;
    if (_hasPendingProgrammingChoice) {
      setState(
        () => _error = _activeFilterKey != null
            ? 'Finish or cancel the open filter before saving.'
            : 'Add or cancel the selected programs before saving.',
      );
      return;
    }
    _refreshPlayableInventory();
    final valid = _form.currentState?.validate() ?? false;
    if (!valid) {
      setState(
        () => _error =
            'Fix the highlighted channel identity fields before saving.',
      );
      _focusAndReveal(_name.text.trim().isEmpty ? _nameFocus : _numberFocus);
      return;
    }
    if (!_generated && _programmingError(_resolveDraftContent()) != null) {
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
      final committed = await widget.controller.saveChannel(
        draft,
        expectedBase: rebasedExpected ?? _expectedBase,
      );
      if (!mounted) return;
      setState(() {
        if (committed.source case ManualSource(:final items)
            when items.length == _manualEntries.length) {
          for (var index = 0; index < items.length; index++) {
            _manualEntries[index].item = items[index];
          }
        }
        _expectedBase = committed;
        _source = committed.source;
        _dirty = false;
        _baselineDraftSignature = _draftSignature;
        _saving = false;
        _generated = committed.builderKey != null;
        _success = 'Channel saved.';
      });
      widget.onSaved(committed.id);
    } catch (error) {
      if (!mounted) return;
      final current = _currentBase;
      final stale =
          _expectedBase != null &&
          (current == null ||
              !canonicalChannelValueEquals(
                current.toJson(),
                _expectedBase!.toJson(),
              ));
      setState(() {
        _saving = false;
        _baseDeleted = stale && current == null;
        _conflict = stale && current != null;
        _error = _baseDeleted
            ? 'This channel was deleted while you were editing. It will not be recreated.'
            : _conflict
            ? 'This channel changed while you were editing. Choose the saved version or deliberately replace it with your retained draft.'
            : safeFormError(
                error,
                'The channel could not be saved. No lineup changes were saved.',
              );
      });
      _focusAndReveal(_conflict ? _recoveryFocus : _saveFocus);
    }
  }

  void _focusAndReveal(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      node.requestFocus();
      final focusContext = node.context;
      if (focusContext != null) {
        unawaited(Scrollable.ensureVisible(focusContext, alignment: 0.35));
      }
    });
  }

  Widget _scaledStudioDialog(
    BuildContext context, {
    required Widget title,
    required Widget content,
    required List<Widget> actions,
  }) {
    final scale = LineupLayout.scaleFor(MediaQuery.sizeOf(context));
    final dialog = AlertDialog(
      insetPadding: scale > 1
          ? EdgeInsets.symmetric(horizontal: 40 * scale, vertical: 24 * scale)
          : null,
      titlePadding: scale > 1
          ? EdgeInsets.only(
              left: 24 * scale,
              top: 24 * scale,
              right: 24 * scale,
            )
          : null,
      contentPadding: scale > 1
          ? EdgeInsets.fromLTRB(24 * scale, 16 * scale, 24 * scale, 24 * scale)
          : null,
      actionsPadding: scale > 1
          ? EdgeInsets.only(
              left: 24 * scale,
              right: 24 * scale,
              bottom: 24 * scale,
            )
          : null,
      buttonPadding: scale > 1
          ? EdgeInsets.symmetric(horizontal: 8 * scale)
          : null,
      actionsOverflowButtonSpacing: scale > 1 ? 8 * scale : null,
      title: title,
      content: content,
      actions: actions,
    );
    if (scale <= 1) return dialog;
    final theme = Theme.of(context);
    final textTheme = theme.textTheme.apply(fontSizeFactor: scale);
    final filledTextStyle = theme.filledButtonTheme.style?.textStyle?.resolve(
      const {},
    );
    return Theme(
      data: theme.copyWith(
        textTheme: textTheme,
        dialogTheme: theme.dialogTheme.copyWith(
          insetPadding: EdgeInsets.symmetric(
            horizontal: 40 * scale,
            vertical: 24 * scale,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: theme.textButtonTheme.style?.copyWith(
            minimumSize: WidgetStatePropertyAll(Size(64 * scale, 40 * scale)),
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 8 * scale),
            ),
            textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: theme.filledButtonTheme.style?.copyWith(
            minimumSize: WidgetStatePropertyAll(Size(148 * scale, 54 * scale)),
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(
                horizontal: 24 * scale,
                vertical: 16 * scale,
              ),
            ),
            textStyle: WidgetStatePropertyAll(
              filledTextStyle?.copyWith(
                fontSize: (filledTextStyle.fontSize ?? 17) * scale,
              ),
            ),
          ),
        ),
      ),
      child: dialog,
    );
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
      _form = GlobalKey<FormState>();
      _source = current.source;
      _playbackMode = current.playbackMode;
      _anchor = current.anchor;
      _shuffleSeed = current.shuffleSeed;
      _blockSize = current.blockSize;
      _includeSpecials = current.includeSpecials;
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

  Future<void> _confirmUseSaved() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => _scaledStudioDialog(
            context,
            title: const Text('Use the saved version?'),
            content: const Text(
              'Your complete Studio draft will be discarded and the newer saved channel will be loaded.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep my draft'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Use saved version'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed && mounted) _reload();
  }

  void _prepareSaveAsNew() {
    final number = _lowestFreeNumber();
    if (number == null) {
      setState(
        () => _error = 'No channel numbers are available. Return to Channels and free a number first.',
      );
      return;
    }
    setState(() {
      _id = createChannelId();
      _number.text = '$number';
      _expectedBase = null;
      _builderKey = null;
      _generated = false;
      _sourceReadOnly = false;
      _baseDeleted = false;
      _conflict = false;
      _scheduleIdentityCommitted = false;
      _candidateAnchor = null;
      _candidateShuffleSeed = null;
      _dirty = true;
      _error = 'Review the available channel number and schedule preview, then save this new custom channel.';
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
          builder: (context) => _scaledStudioDialog(
            context,
            title: const Text('Replace the saved version?'),
            content: const Text(
              'The newer saved channel will be replaced with your complete Studio draft.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep my draft open'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Replace saved version'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed && mounted) await _save(rebasedExpected: current);
  }

  Future<void> _tune() async {
    if (_busy) return;
    final epoch = ++_tuneEpoch;
    final channelId = _id;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _tuning = true;
      _error = null;
    });
    var tuned = false;
    try {
      tuned = await widget.onTune(channelId);
    } catch (_) {
      tuned = false;
    }
    if (!mounted || epoch != _tuneEpoch) return;
    if (tuned) {
      setState(() => _tuning = false);
      return;
    }
    setState(() {
      _tuning = false;
      _error = _success == 'Channel saved.'
          ? 'Playback could not start, but your channel changes were saved.'
          : 'Playback could not start. Your saved lineup is unchanged.';
    });
  }

  Future<void> _confirmSaveAndTune() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => _scaledStudioDialog(
            context,
            title: const Text('Save changes and tune in?'),
            content: const Text(
              'Your changes to this channel will be saved before playback starts.',
            ),
            actions: [
              TextButton(
                autofocus: true,
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save and tune in'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    await _save();
    if (mounted && !_dirty && !_saving && _expectedBase != null) await _tune();
  }
}

String channelSourceLabel(ContentSource source, LineupController controller) =>
    _sourceLabel(source, controller);

String _sourceLabel(
  ContentSource source,
  LineupController controller,
) => switch (source) {
  LibrarySource(
    :final libraryId,
    :final includeWatched,
    :final filters,
    :final order,
  ) =>
    [
      'Library: ${controller.libraries.where((library) => library.id == libraryId).firstOrNull?.title ?? libraryId}',
      for (final filter in filters.entries) ?_filterFact(filter),
      if (order == LibraryOrder.addedDescending) 'Newest first',
      includeWatched ? 'includes watched' : 'unwatched only',
    ].join(' • '),
  ManualSource(:final items) => '${items.length} hand-picked programs',
  PlaylistSource(:final playlistId) =>
    'Playlist: ${controller.availablePlaylists.where((playlist) => playlist.id == playlistId).firstOrNull?.title ?? playlistId}',
  MixedSource(:final sources, :final interleave) =>
    '${sources.length}-source mix • ${interleave ? 'interleaved' : 'in sequence'}',
};

String? _filterFact(MapEntry<LibraryFilter, List<String>> filter) =>
    '${_facetLabel(filter.key.name)}: ${filter.value.join(', ')}';

LibraryFilter _libraryFilter(String key) =>
    LibraryFilter.values.where((filter) => filter.name == key).first;

String channelRhythmLabel(PlaybackMode mode, int? blockSize) =>
    _rhythmLabel(mode, blockSize);

String _rhythmLabel(PlaybackMode mode, [int? blockSize]) => switch (mode) {
  PlaybackMode.sequential => 'In order',
  PlaybackMode.shuffle => 'Shuffle',
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

String _compactDuration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  return [if (hours > 0) '${hours}h', if (minutes > 0) '${minutes}m'].join(' ');
}

class _MoveProgramDialog extends StatefulWidget {
  const _MoveProgramDialog({
    required this.entries,
    required this.moving,
    required this.titleFor,
  });

  final List<_ManualEntry> entries;
  final _ManualEntry moving;
  final String Function(_ManualEntry entry) titleFor;

  @override
  State<_MoveProgramDialog> createState() => _MoveProgramDialogState();
}

class _MoveProgramDialogState extends State<_MoveProgramDialog> {
  _ManualEntry? _target;
  bool _after = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _label(_ManualEntry entry) {
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
    final scale = LineupLayout.scaleFor(size);
    final theme = Theme.of(context);
    final dialogTextTheme = theme.textTheme.apply(fontSizeFactor: scale);
    final segmentFontSize = dialogTextTheme.labelLarge?.fontSize ?? 14;
    final segmentVerticalPadding = scale > 1
        ? (40 * scale > segmentFontSize
              ? (40 * scale - segmentFontSize) / 2
              : 0.0)
        : 0.0;
    final actionStyle = scale > 1
        ? TextButton.styleFrom(
            minimumSize: Size(64 * scale, 40 * scale),
            padding: EdgeInsets.symmetric(
              horizontal: 12 * scale,
              vertical: 8 * scale,
            ),
            textStyle: dialogTextTheme.labelLarge,
          )
        : null;
    final moveStyle = scale > 1
        ? FilledButton.styleFrom(
            minimumSize: Size(148 * scale, 54 * scale),
            padding: EdgeInsets.symmetric(
              horizontal: 24 * scale,
              vertical: 16 * scale,
            ),
            textStyle: theme.filledButtonTheme.style?.textStyle
                ?.resolve(const {})
                ?.copyWith(fontSize: 17 * scale),
          )
        : null;
    final inputDecorationTheme = scale > 1
        ? theme.inputDecorationTheme.copyWith(
            contentPadding: EdgeInsets.fromLTRB(
              12 * scale,
              24 * scale,
              12 * scale,
              16 * scale,
            ),
            prefixIconConstraints: BoxConstraints(
              minWidth: 48 * scale,
              minHeight: 48 * scale,
            ),
            suffixIconConstraints: BoxConstraints(
              minWidth: 48 * scale,
              minHeight: 48 * scale,
            ),
          )
        : theme.inputDecorationTheme;
    final dialog = AlertDialog(
      insetPadding: scale > 1
          ? EdgeInsets.symmetric(horizontal: 40 * scale, vertical: 24 * scale)
          : null,
      titlePadding: scale > 1
          ? EdgeInsets.only(
              left: 24 * scale,
              top: 24 * scale,
              right: 24 * scale,
            )
          : null,
      contentPadding: scale > 1
          ? EdgeInsets.fromLTRB(24 * scale, 16 * scale, 24 * scale, 24 * scale)
          : null,
      actionsPadding: scale > 1
          ? EdgeInsets.only(
              left: 24 * scale,
              right: 24 * scale,
              bottom: 24 * scale,
            )
          : null,
      buttonPadding: scale > 1
          ? EdgeInsets.symmetric(horizontal: 8 * scale)
          : null,
      actionsOverflowButtonSpacing: scale > 1 ? 8 * scale : null,
      title: Text('Move ${widget.titleFor(widget.moving)}'),
      content: SizedBox(
        width: (size.width - 128 * scale).clamp(0.0, 520 * scale),
        height: (size.height - viewInsets.vertical - 200 * scale).clamp(
          0.0,
          380 * scale,
        ),
        child: Column(
          children: [
            TextField(
              key: const Key('move-program-search'),
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Find program',
                contentPadding: inputDecorationTheme.contentPadding,
              ),
              onChanged: (_) => setState(() {}),
            ),
            SizedBox(height: 8 * scale),
            Expanded(
              child: RadioGroup<_ManualEntry>(
                groupValue: _target,
                onChanged: (value) => setState(() => _target = value),
                child: ListView(
                  children: [
                    for (final entry in targets)
                      RadioListTile<_ManualEntry>(
                        value: entry,
                        radioScaleFactor: scale,
                        minTileHeight: scale > 1 ? 56 * scale : null,
                        horizontalTitleGap: scale > 1 ? 16 * scale : null,
                        contentPadding: scale > 1
                            ? EdgeInsets.symmetric(horizontal: 16 * scale)
                            : null,
                        title: Text(_label(entry)),
                      ),
                  ],
                ),
              ),
            ),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Before')),
                ButtonSegment(value: true, label: Text('After')),
              ],
              selected: {_after},
              style: scale > 1
                  ? ButtonStyle(
                      padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(
                          horizontal: 16 * scale,
                          vertical: segmentVerticalPadding,
                        ),
                      ),
                      iconSize: WidgetStatePropertyAll(18 * scale),
                    )
                  : null,
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
          style: actionStyle,
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _target == null
              ? null
              : () => Navigator.pop(context, (
                  index: widget.entries.indexOf(_target!),
                  after: _after,
                )),
          style: moveStyle,
          child: const Text('Move'),
        ),
      ],
    );
    return scale > 1
        ? Theme(
            data: theme.copyWith(
              textTheme: dialogTextTheme,
              inputDecorationTheme: inputDecorationTheme,
            ),
            child: dialog,
          )
        : dialog;
  }
}
