import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lineup_desktop/platform/device_profile.dart';

import '../channels/channel.dart';
import '../channels/content_resolver.dart';
import '../plex/plex_models.dart';
import '../ui/app_theme.dart';
import '../ui/app_ui.dart';
import 'channel_air_check.dart';
import 'air_check_verification.dart';
import 'channel_studio_draft.dart';
import 'form_error.dart';
import 'manual_rundown.dart';
import 'lineup_controller.dart';

part 'channel_studio/studio_filter_controls.dart';
part 'channel_studio/studio_filter_editor.dart';
part 'channel_studio/studio_filter_picker.dart';
part 'channel_studio/studio_inventory.dart';
part 'channel_studio/studio_inventory_queries.dart';
part 'channel_studio/studio_manual_editor.dart';
part 'channel_studio/studio_playlist.dart';
part 'channel_studio/studio_programming.dart';
part 'channel_studio/studio_recovery.dart';
part 'channel_studio/studio_station.dart';
part 'channel_studio/studio_style.dart';
part 'channel_studio/studio_title.dart';

typedef _StudioInventory = ({
  List<PlexMediaItem> media,
  List<PlexPlaylist> playlists,
  Map<String, PlexMediaItem> byId,
});

enum ChannelStudioMode {
  createCustom,
  editCustom,
  inspectGenerated,
  duplicateCustom,
}

typedef _DraftResolution = ({
  ContentSource? source,
  List<ChannelItem>? content,
  String? sourceError,
});

typedef _FacetOptions = ({
  Map<String, List<String>> values,
  Map<String, Map<String, String>> labels,
});

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
    this.onOpenMenu,
    this.menuFocusNode,
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
  final LineupMenuCallback? onOpenMenu;
  final FocusNode? menuFocusNode;
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
  GlobalKey<FormState> _form = GlobalKey<FormState>();
  final _titleKey = GlobalKey<_StudioTitleState>();
  var _stationKey = GlobalKey<_StudioStationState>();
  var _programmingKey = GlobalKey<_StudioProgrammingState>();
  final _recoveryKey = GlobalKey<_StudioRecoveryState>();
  late final TextEditingController _name;
  late final TextEditingController _number;
  late final ChannelStudioDraft _session;
  int _sourceRevision = 0;
  _StudioPendingChoice? _pendingProgrammingChoice;
  bool _saving = false;
  bool _tuning = false;
  int _tuneEpoch = 0;
  bool _conflict = false;
  bool _baseDeleted = false;
  String? _error;
  String? _success;
  late final AirCheckVerification _verification;
  String? _verificationInputKey;

  late _StudioInventory _playableInventory;

  bool get _busy => _saving || _tuning;
  bool get saving => _saving;
  bool get dirty => _session.dirty;

  /// Cancels a reachable nested Studio choice without leaving the editor.
  ///
  /// A pending choice may briefly outlive its child during a rebuild. In that
  /// case the parent still claims Back so it cannot fall through to the dirty
  /// Studio leave guard and discard the draft.
  bool cancelPendingChoice() {
    final programming = _programmingKey.currentState;
    if (programming != null) {
      final cancelled = programming.cancelPendingChoice();
      return cancelled || _pendingProgrammingChoice != null;
    }
    return _pendingProgrammingChoice != null;
  }

  ChannelStudioMode get _effectiveMode =>
      _session.expectedBase != null && !_session.generated
      ? ChannelStudioMode.editCustom
      : widget.mode;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _verification = AirCheckVerification(
      loadSchedule: (channel) => widget.controller.loadScheduleFor(channel),
      clock: _clock,
    );
    _verification.addListener(_verificationChanged);
    _updateVerification();
  }

  void _loadInitial() {
    _refreshPlayableInventory();
    final original = widget.channel;
    _session = ChannelStudioDraft(
      id:
          widget.mode == ChannelStudioMode.createCustom ||
              widget.mode == ChannelStudioMode.duplicateCustom
          ? createChannelId()
          : original!.id,
      source: original?.source ?? _defaultSource(),
      duplicate: widget.mode == ChannelStudioMode.duplicateCustom,
      original: original,
      generated: widget.mode == ChannelStudioMode.inspectGenerated,
      expectedBase: switch (widget.mode) {
        ChannelStudioMode.editCustom ||
        ChannelStudioMode.inspectGenerated => original,
        _ => null,
      },
    );
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
    _configureSource();
    _session.acceptBaseline(_draftSignature);
  }

  @override
  void didUpdateWidget(ChannelStudioView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateVerification();
  }

  void _updateVerification() {
    _refreshPlayableInventory();
    final resolution = _session.generated ? null : _resolveDraftContent();
    final issue = resolution == null ? null : _programmingError(resolution);
    _session.stageScheduleIdentity(_clock, valid: issue == null);
    final source = resolution?.source ?? _session.source;
    final preview = _session.project(
      name: _name.text,
      number: _number.text,
      programming: source,
      preview: true,
    );
    _verificationInputKey = channelAirCheckSnapshotKey(
      preview,
      widget.controller.contentGeneration,
    );
    _verification.update(
      preview,
      _session.expectedBase,
      widget.controller.contentGeneration,
      issue,
      sourceLabel: _sourceLabel(source, widget.controller),
    );
  }

  void _verificationChanged() {
    if (!mounted) return;
    final result = _verification.result;
    if (result.revisionKey != _verificationInputKey) return;
    setState(() {
      if (result.validity == ChannelAirCheckValidity.valid ||
          result.validity == ChannelAirCheckValidity.retainedOffAir) {
        _session.commitScheduleIdentity(_draftSignature);
      }
    });
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

  void _configureSource() {
    _session.configureSource(
      defaultPlaylistId: _playableInventory.playlists.firstOrNull?.id,
      defaultLibraryId: widget.controller.selectedLibraryIds.firstOrNull,
    );
    _sourceRevision++;
    _pendingProgrammingChoice = null;
  }

  List<PlexLibrary> get _selectedLibraries => widget.controller.libraries
      .where(
        (library) => widget.controller.selectedLibraryIds.contains(library.id),
      )
      .toList(growable: false);

  void _refreshPlayableInventory() {
    _playableInventory = widget.controller.playableInventory;
  }

  int? _lowestFreeNumber() {
    final reusableId = _session.expectedBase == null ? null : _session.id;
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
      .where((channel) => channel.id == _session.id)
      .firstOrNull;

  @override
  void dispose() {
    _verification.removeListener(_verificationChanged);
    _verification.dispose();
    _name.dispose();
    _number.dispose();
    super.dispose();
  }

  void _changed([VoidCallback? change]) {
    setState(() {
      change?.call();
      _session.updateDirty(_draftSignature);
      _success = null;
    });
    _updateVerification();
  }

  Map<String, Object?> get _draftSignature => _session.signature(
    name: _name.text,
    number: _number.text,
    libraries: _selectedLibraries,
  );

  @override
  Widget build(BuildContext context) {
    _refreshPlayableInventory();
    final noNumber = _lowestFreeNumber() == null && _number.text.trim().isEmpty;
    final persisted = _session.expectedBase != null;
    final saved = !_session.dirty && persisted;
    final number = int.tryParse(_number.text);
    final validNumber = _validateNumber(_number.text) == null;
    final draftResolution = _session.generated ? null : _resolveDraftContent();
    final programmingError = draftResolution == null
        ? null
        : _programmingError(draftResolution);
    final sourceExplanation = _sourceExplanationMessage(draftResolution);
    final hasShowGrouping =
        draftResolution?.content?.any(
          (item) =>
              item.showTitle?.trim().isNotEmpty == true ||
              item.showThumb?.trim().isNotEmpty == true,
        ) ??
        false;
    final confirmedMovieOnly = _confirmedMovieOnly(draftResolution);
    final theme = Theme.of(context);
    final compact = LineupLayout.isCompactWidth(
      MediaQuery.sizeOf(context).width,
    );
    final baseFontSize = compact ? 14.0 : 18.0;
    return Theme(
      data: theme.copyWith(
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
          topBar: LineupTopBar(
            menuKey: const Key('studio-app-menu'),
            onOpenMenu: widget.onOpenMenu,
            menuFocusNode: widget.menuFocusNode,
          ),
          title: _name.text.trim().isEmpty ? 'New channel' : _name.text.trim(),
          titleWidget: _StudioTitle(
            key: _titleKey,
            name: _name.text,
            number: validNumber ? number : null,
            mode: _effectiveMode,
            saved: saved,
            persisted: persisted,
            conflict: _conflict,
            baseDeleted: _baseDeleted,
            dirty: _session.dirty,
            generated: _session.generated,
            busy: _busy,
            saving: _saving,
            canSave: _canSave,
            hasPendingChoice: _hasPendingProgrammingChoice,
            pendingHint: _pendingProgrammingHint,
            onLeave: _leave,
            onDuplicate: _duplicate,
            onTune: _tune,
            onSaveAndTune: _confirmSaveAndTune,
            onSave: _save,
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
                        SizedBox(height: 12),
                        Semantics(liveRegion: true, child: Text(_success!)),
                      ],
                      if (_saving) ...[
                        SizedBox(height: 12),
                        Semantics(
                          liveRegion: true,
                          container: true,
                          label: 'Saving channel',
                          child: const Text('Saving channel…'),
                        ),
                      ],
                      if (noNumber) ...[
                        SizedBox(height: 12),
                        const LineupNotice(
                          message: 'No channel numbers are available. Free or renumber a channel from Channels before saving.',
                        ),
                      ],
                      if (_conflict || _baseDeleted) ...[
                        _StudioRecovery(
                          key: _recoveryKey,
                          baseDeleted: _baseDeleted,
                          saving: _saving,
                          error: _error,
                          name: _name.text,
                          number: _number.text,
                          currentName: _currentBase?.name,
                          headingStyle: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          onSaveAsNew: _prepareSaveAsNew,
                          onReturn: _reload,
                          onUseSaved: _confirmUseSaved,
                          onReplace: _confirmReapply,
                        ),
                      ],
                      if (_error != null ||
                          _success != null ||
                          _saving ||
                          noNumber ||
                          _conflict ||
                          _baseDeleted)
                        SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final programming = _StudioProgramming(
                            key: _programmingKey,
                            draft: _session,
                            inventory: _playableInventory,
                            readInventory: () =>
                                widget.controller.playableInventory,
                            selectedLibraries: _selectedLibraries,
                            libraries: widget.controller.libraries,
                            channels: widget.controller.channels,
                            name: _name.text,
                            sourceLabel: _sourceLabel(
                              _displaySource,
                              widget.controller,
                            ),
                            sourceExplanation: sourceExplanation,
                            programmingError: programmingError,
                            inventoryStatus: _StudioInventoryStatus(
                              status: widget.controller.libraryScanStatus,
                              totalItems:
                                  widget.controller.libraryScanTotalItems,
                              completedItems:
                                  widget.controller.libraryScanCompletedItems,
                              hasInventory: _playableInventory.byId.isNotEmpty,
                              saving: _saving,
                              onGenerate: widget.onOpenGenerateLineup,
                            ),
                            saving: _saving,
                            sourceRevision: _sourceRevision,
                            onChanged: _changed,
                            onPendingChanged: (choice) {
                              if (_pendingProgrammingChoice != choice) {
                                setState(
                                  () => _pendingProgrammingChoice = choice,
                                );
                              }
                            },
                            onOpenChannel: widget.onOpenChannel,
                          );
                          final station = _StudioStation(
                            key: _stationKey,
                            draft: _session,
                            name: _name,
                            number: _number,
                            saving: _saving,
                            busy: _busy,
                            hasShowGrouping: hasShowGrouping,
                            confirmedMovieOnly: confirmedMovieOnly,
                            hasNumberConflict: _conflictingChannel != null,
                            hasFreeNumber: _lowestFreeNumber() != null,
                            sourceSummary: _sourceLabel(
                              _session.source,
                              widget.controller,
                            ),
                            validateNumber: _validateNumber,
                            onChanged: _changed,
                            onUseNext: _useNextAvailable,
                          );
                          final preview = ChannelAirCheck(
                            controller: widget.controller,
                            channel: _previewDraft,
                            originalChannel: _session.expectedBase,
                            clock: _clock,
                            compact:
                                constraints.maxWidth /
                                    MediaQuery.textScalerOf(context).scale(1) <
                                LineupLayout.compact,
                            inclusionReason: _sourceLabel(
                              _displaySource,
                              widget.controller,
                            ),
                            sourceIssue: programmingError,
                            sourceIssueExplained: sourceExplanation != null,
                            playableById: _playableInventory.byId,
                            verification: _verification,
                          );
                          return constraints.maxWidth /
                                      MediaQuery.textScalerOf(context)
                                          .scale(1) <
                                  LineupLayout.compact
                              ? Column(
                                  children: [
                                    FocusTraversalOrder(
                                      order: const NumericFocusOrder(1),
                                      child: station,
                                    ),
                                    SizedBox(height: 16),
                                    FocusTraversalOrder(
                                      order: const NumericFocusOrder(2),
                                      child: programming,
                                    ),
                                    SizedBox(height: 16),
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
                                    SizedBox(height: 16),
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
                                        SizedBox(width: 16),
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

  String? _sourceExplanationMessage([_DraftResolution? resolution]) {
    final resolved = resolution ?? _resolveDraftContent();
    final error = _programmingError(resolved);
    if (error != null) return error;
    return resolved.content?.isEmpty == true &&
            resolved.source != null &&
            hasNonemptyRetainedManualContent(resolved.source!)
        ? 'No retained hand-picked programs are currently available. They remain saved and explicitly off air.'
        : null;
  }

  Channel? get _conflictingChannel {
    final number = int.tryParse(_number.text);
    if (number == null) return null;
    return widget.controller.channels
        .where(
          (channel) => channel.id != _session.id && channel.number == number,
        )
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
    await widget.onBack(_session.expectedBase?.id ?? widget.channel?.id);
  }

  void _duplicate() {
    final source = _session.duplicateRecipe(
      name: _name.text,
      number: _number.text,
      template: widget.channel!,
    );
    widget.onDuplicate(source);
  }

  ContentSource _editedSource() => _session.editedSource(
    libraries: _selectedLibraries,
    available: _playableInventory.byId,
  );

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
    if (_session.playbackMode == PlaybackMode.block &&
        !resolved.any(
          (item) =>
              item.showTitle?.trim().isNotEmpty == true ||
              item.showThumb?.trim().isNotEmpty == true,
        )) {
      return 'Mini-marathons needs episodes grouped by show title or show artwork.';
    }
    final blockSize = _session.effectiveBlockSize;
    if (blockSize != null && (blockSize < 2 || blockSize > 5)) {
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
        final available = _studioFacetOptions(
          libraryId,
          inventory: _playableInventory.byId.values,
        ).values;
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
          return 'No programs match. Remove a filter or include watched items.';
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

  Channel _draft() => _session.project(
    name: _name.text,
    number: _number.text,
    programming: _editedSource(),
    preview: false,
  );

  Channel get _previewDraft => _session.project(
    name: _name.text,
    number: _number.text,
    programming: _displaySource,
    preview: true,
  );

  bool get _airCheckCanSave {
    final result = _verification.result;
    return result.revisionKey ==
            channelAirCheckSnapshotKey(
              _previewDraft,
              widget.controller.contentGeneration,
            ) &&
        (result.validity == ChannelAirCheckValidity.valid ||
            result.validity == ChannelAirCheckValidity.retainedOffAir);
  }

  bool get _hasPendingProgrammingChoice => _pendingProgrammingChoice != null;
  String get _pendingProgrammingHint =>
      _pendingProgrammingChoice == _StudioPendingChoice.filter
      ? 'Finish this filter with Done, or cancel it, before saving or tuning.'
      : 'Add the selected programs, or cancel selection, before saving or tuning.';

  bool get _canSave {
    final persisted = _session.expectedBase != null;
    final identityLooksValid =
        _name.text.trim().isNotEmpty && _validateNumber(_number.text) == null;
    final programmingError = _session.generated
        ? null
        : _programmingError(_resolveDraftContent());
    return !_busy &&
        !_hasPendingProgrammingChoice &&
        (!persisted || _session.dirty) &&
        !(_lowestFreeNumber() == null && _number.text.trim().isEmpty) &&
        !(identityLooksValid && programmingError != null) &&
        !(identityLooksValid && !_airCheckCanSave) &&
        _session.scheduleIdentityCommitted;
  }

  Future<void> _save({Channel? rebasedExpected}) async {
    if (_busy) return;
    if (_hasPendingProgrammingChoice) {
      setState(
        () => _error = _pendingProgrammingChoice == _StudioPendingChoice.filter
            ? 'Finish or cancel the open filter before saving.'
            : 'Add or cancel the selected programs before saving.',
      );
      return;
    }
    _updateVerification();
    final valid = _form.currentState?.validate() ?? false;
    if (!valid) {
      setState(
        () => _error =
            'Fix the highlighted channel identity fields before saving.',
      );
      _stationKey.currentState?.focusIdentity(name: _name.text.trim().isEmpty);
      return;
    }
    if (!_session.generated &&
        _programmingError(_resolveDraftContent()) != null) {
      return;
    }
    if (!_canSave) {
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
        expectedBase: rebasedExpected ?? _session.expectedBase,
      );
      if (!mounted) return;
      setState(() {
        _session.loadSaved(committed);
        _session.acceptBaseline(_draftSignature);
        _saving = false;
        _success = 'Channel saved.';
      });
      _updateVerification();
      widget.onSaved(committed.id);
    } catch (error) {
      if (!mounted) return;
      final current = _currentBase;
      final stale =
          _session.expectedBase != null &&
          (current == null ||
              !canonicalChannelValueEquals(
                current.toJson(),
                _session.expectedBase!.toJson(),
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_conflict || _baseDeleted) {
          _recoveryKey.currentState?.focusPrimary();
        } else {
          _titleKey.currentState?.focusSave();
        }
      });
    }
  }

  ContentSource get _displaySource {
    try {
      return _editedSource();
    } on FormatException {
      return _session.source;
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
      _stationKey = GlobalKey<_StudioStationState>();
      _programmingKey = GlobalKey<_StudioProgrammingState>();
      _session.loadSaved(current);
      _configureSource();
      _session.acceptBaseline(_draftSignature);
      _conflict = false;
      _baseDeleted = false;
      _error = null;
      _success = null;
    });
    _updateVerification();
  }

  Future<void> _confirmUseSaved() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
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
      _session.prepareSaveAsNew(createChannelId());
      _number.text = '$number';
      _baseDeleted = false;
      _conflict = false;
      _error = 'Review the available channel number and schedule preview, then save this new custom channel.';
    });
    _updateVerification();
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
    final channelId = _session.id;
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
          builder: (context) => AlertDialog(
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
    if (mounted &&
        !_session.dirty &&
        !_saving &&
        _session.expectedBase != null) {
      await _tune();
    }
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
