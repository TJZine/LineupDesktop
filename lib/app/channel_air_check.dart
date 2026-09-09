import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../channels/channel.dart';
import '../channels/scheduler.dart';
import '../guide/guide_controller.dart';
import '../ui/app_theme.dart';
import '../ui/app_ui.dart';
import 'lineup_controller.dart';

const channelAirCheckDebounce = Duration(milliseconds: 80);

enum ChannelAirCheckValidity { unknown, valid, retainedOffAir }

typedef ChannelAirCheckStatus = ({
  String snapshotKey,
  ChannelAirCheckValidity validity,
});

class ChannelAirCheck extends StatefulWidget {
  const ChannelAirCheck({
    required this.controller,
    required this.channel,
    required this.clock,
    required this.compact,
    required this.inclusionReason,
    required this.onValidityChanged,
    this.originalChannel,
    this.sourceIssue,
    this.playableById,
    super.key,
  });

  final LineupController controller;
  final Channel channel;
  final Channel? originalChannel;
  final DateTime Function() clock;
  final bool compact;
  final String inclusionReason;
  final String? sourceIssue;
  final Map<String, Object?>? playableById;
  final ValueChanged<ChannelAirCheckStatus> onValidityChanged;

  @override
  State<ChannelAirCheck> createState() => ChannelAirCheckState();
}

class ChannelAirCheckState extends State<ChannelAirCheck> {
  static const _tick = Duration(seconds: 30);

  Timer? _debounce;
  Timer? _clockTimer;
  _AirCheckRequest? _active;
  _AirCheckRequest? _pending;
  _AirCheckPreview? _preview;
  ScheduleIndex? _originalSchedule;
  String? _originalScheduleKey;
  Object? _originalScheduleError;
  String? _originalScheduleErrorKey;
  String? _originalOffAirKey;
  Object? _error;
  String? _selectedId;
  bool _selectionFollowsNow = true;
  bool _disposed = false;
  int _futureHours = 6;
  bool _synopsisExpanded = false;
  int _requestVersion = 0;
  ChannelAirCheckStatus? _reportedStatus;
  late String _targetKey;
  String? _wantedOriginalKey;

  double get _uiScale => LineupLayout.scaleFor(MediaQuery.sizeOf(context));

  int get activeRequestCount => _active == null ? 0 : 1;
  int get pendingRequestCount => _pending == null ? 0 : 1;

  @override
  void initState() {
    super.initState();
    _targetKey = _snapshotKey(widget);
    _wantedOriginalKey = _originalKey(widget);
    _clockTimer = Timer.periodic(_tick, (_) => _advanceClock());
    _scheduleLoad(initial: true);
  }

  @override
  void didUpdateWidget(ChannelAirCheck oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextKey = _snapshotKey(widget);
    final nextOriginalKey = _originalKey(widget);
    if (_targetKey != nextKey ||
        _wantedOriginalKey != nextOriginalKey ||
        oldWidget.sourceIssue != widget.sourceIssue) {
      _targetKey = nextKey;
      _wantedOriginalKey = nextOriginalKey;
      _reportValidity(ChannelAirCheckValidity.unknown);
      _scheduleLoad();
    } else if (_preview case final preview?
        when preview.channel.name != widget.channel.name ||
            preview.channel.number != widget.channel.number) {
      _preview = preview.withChannel(widget.channel);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  void _scheduleLoad({bool initial = false}) {
    _debounce?.cancel();
    final version = ++_requestVersion;
    _pending = null;
    final issue = widget.sourceIssue;
    if (issue != null) {
      _error = _AirCheckSourceIssue(issue);
      _reportValidity(
        _canRetainOffAir(_error!)
            ? ChannelAirCheckValidity.retainedOffAir
            : ChannelAirCheckValidity.unknown,
      );
      if (mounted) setState(() {});
      return;
    }
    _reportValidity(ChannelAirCheckValidity.unknown);
    if (initial) {
      _enqueueRequired(version);
    } else {
      _debounce = Timer(
        channelAirCheckDebounce,
        () => _enqueueRequired(version),
      );
    }
  }

  void _enqueueRequired(int version) {
    if (_disposed || version != _requestVersion) return;
    final target = _AirCheckRequest(
      key: _targetKey,
      channel: widget.channel,
      baseline: false,
      publishes: true,
      version: version,
    );
    final original = widget.originalChannel;
    final originalKey = _wantedOriginalKey;
    if (original != null &&
        originalKey != null &&
        _originalScheduleKey != originalKey) {
      _enqueue(
        _AirCheckRequest(
          key: originalKey,
          channel: original,
          baseline: true,
          publishes: originalKey == _targetKey,
          version: version,
          followUp: originalKey == _targetKey ? null : target,
        ),
      );
      return;
    }
    _enqueue(target);
  }

  void retry() {
    _error = null;
    _scheduleLoad();
    if (mounted) setState(() {});
  }

  void _enqueue(_AirCheckRequest request) {
    if (_disposed) return;
    if (_active != null) {
      _pending = request;
      setState(() {});
      return;
    }
    _start(request);
  }

  void _start(_AirCheckRequest request) {
    _active = request;
    _error = null;
    if (request.baseline && request.key == _wantedOriginalKey) {
      _originalScheduleError = null;
      _originalScheduleErrorKey = null;
      _originalOffAirKey = null;
    }
    if (mounted) setState(() {});
    widget.controller
        .loadScheduleFor(request.channel)
        .then(
          (schedule) {
            if (_disposed) return;
            if (request.baseline && request.key == _wantedOriginalKey) {
              _originalSchedule = schedule;
              _originalScheduleKey = request.key;
              _originalScheduleError = null;
              _originalScheduleErrorKey = null;
              _originalOffAirKey = null;
            }
            if (request.publishes &&
                request.key == _targetKey &&
                request.version == _requestVersion) {
              final preview = _project(schedule, request.key, request.channel);
              _preview = preview;
              _error = null;
              _preserveSelection(preview, widget.clock());
              final validity = _comparisonReady
                  ? ChannelAirCheckValidity.valid
                  : ChannelAirCheckValidity.unknown;
              _reportValidity(validity, snapshotKey: request.key);
            }
          },
          onError: (Object error) {
            if (_disposed || request.version != _requestVersion) {
              return;
            }
            if (request.baseline && request.key == _wantedOriginalKey) {
              _originalSchedule = null;
              _originalScheduleKey = null;
              if (_isNoContentFailure(error)) {
                _originalOffAirKey = request.key;
                _originalScheduleError = null;
                _originalScheduleErrorKey = null;
              } else {
                _originalOffAirKey = null;
                _originalScheduleError = error;
                _originalScheduleErrorKey = request.key;
              }
            }
            if (request.key != _targetKey) return;
            _error = error;
            _reportValidity(
              _canRetainOffAir(error)
                  ? ChannelAirCheckValidity.retainedOffAir
                  : ChannelAirCheckValidity.unknown,
              snapshotKey: request.key,
            );
          },
        )
        .whenComplete(() {
          if (_disposed) return;
          if (identical(_active, request)) _active = null;
          final pending =
              _pending ??
              (request.version == _requestVersion ? request.followUp : null);
          _pending = null;
          if (pending != null) {
            _start(pending);
          } else if (mounted) {
            setState(() {});
          }
        });
  }

  _AirCheckPreview _project(
    ScheduleIndex schedule,
    String key,
    Channel channel, {
    int? futureHours,
  }) {
    final now = widget.clock().toUtc();
    final current = programAt(now, channel.anchor, schedule);
    final start = current.start;
    final requestedEnd = now.add(Duration(hours: futureHours ?? _futureHours));
    final projected = scheduleWindowResult(
      start,
      requestedEnd,
      channel.anchor,
      schedule,
    );
    final programs = projected.programs
        .where(
          (program) =>
              program.start == current.start ||
              !program.end.isAfter(requestedEnd),
        )
        .toList(growable: false);
    final result = ScheduleWindowResult(
      programs: programs,
      truncated: projected.truncated,
      lastProjectedEnd: programs.lastOrNull?.end,
    );
    return _AirCheckPreview(
      schedule: schedule,
      channel: channel,
      window: result,
      key: key,
      windowStart: start,
      windowEnd: requestedEnd,
      ribbonStart: now,
      ribbonEnd: now.add(const Duration(hours: 2)),
    );
  }

  void _advanceClock() {
    if (_disposed || _preview == null) return;
    final previous = _preview!;
    final now = widget.clock();
    final previousCurrentIndex = previous.programs.indexWhere(
      (item) => item.isCurrentAt(now),
    );
    final needsRollover =
        previousCurrentIndex < 0 ||
        previousCurrentIndex + 1 >= previous.programs.length ||
        now.isBefore(previous.ribbonStart) ||
        !now.isBefore(previous.ribbonEnd);
    final next = needsRollover
        ? _project(previous.schedule, previous.key, previous.channel)
        : previous;
    setState(() {
      _preview = next;
      _preserveSelection(next, now);
    });
  }

  List<GuideProgram> _visiblePrograms(_AirCheckPreview preview, DateTime now) =>
      preview.programs
          .where((program) => program.scheduled.end.isAfter(now))
          .toList(growable: false);

  void _preserveSelection(_AirCheckPreview preview, DateTime now) {
    final visible = _visiblePrograms(preview, now);
    final current = visible
        .where((program) => program.isCurrentAt(now))
        .firstOrNull;
    final selectedStillPresent = visible.any(
      (program) => program.id == _selectedId,
    );
    if (_selectionFollowsNow || !selectedStillPresent) {
      _selectedId = current?.id;
    }
  }

  bool _canRetainOffAir(Object error) {
    if (!hasNonemptyRetainedManualContent(widget.channel.source)) return false;
    return _isNoContentFailure(error);
  }

  bool get _comparisonReady =>
      widget.originalChannel == null ||
      _originalScheduleKey == _wantedOriginalKey ||
      _originalOffAirKey == _wantedOriginalKey;

  bool get _comparisonFailed =>
      _originalScheduleError != null &&
      _originalScheduleErrorKey == _wantedOriginalKey;

  void _reportValidity(
    ChannelAirCheckValidity validity, {
    String? snapshotKey,
  }) {
    final status = (snapshotKey: snapshotKey ?? _targetKey, validity: validity);
    if (_reportedStatus == status) return;
    _reportedStatus = status;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) widget.onValidityChanged(status);
    });
  }

  bool get _stale =>
      _preview != null &&
      (_active != null ||
          _pending != null ||
          _error != null ||
          _previewKey != _targetKey);

  String? get _previewKey => _preview?.key;

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final now = widget.clock();
    final error = _error;
    return Semantics(
      key: const Key('channel-air-check'),
      container: true,
      label:
          'Air Check for channel ${widget.channel.number} ${widget.channel.name}',
      child: Container(
        decoration: BoxDecoration(
          color: LineupTheme.of(context).primarySurface,
          border: Border.all(color: LineupTheme.of(context).subtleBorder),
          borderRadius: BorderRadius.circular(
            LineupTheme.of(context).panelRadius,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _monitorHeader(now),
                  const SizedBox(height: 10),
                  if (preview == null && error == null)
                    _emptyRibbon(
                      Semantics(
                        liveRegion: true,
                        label: 'Calculating schedule',
                        child: const Text(
                          'Calculating schedule…',
                          key: Key('air-check-loading'),
                        ),
                      ),
                    )
                  else if (preview == null)
                    _emptyRibbon(_errorView(error!))
                  else ...[
                    _facts(preview),
                    const SizedBox(height: 8),
                    _selection(preview, now),
                    const SizedBox(height: 8),
                    _verticalSchedule(preview, now),
                    if (_futureHours < 24)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: _stale
                              ? null
                              : () => _extendPreview(preview),
                          child: const Text('Show next 6 hours'),
                        ),
                      ),
                    Text(
                      'Coverage through ${_time(context, preview.window.lastProjectedEnd ?? preview.windowEnd)} · $_futureHours future hours requested',
                    ),
                    if (preview.window.truncated)
                      Text(
                        'Preview truncated at ${_time(context, preview.window.lastProjectedEnd!)}; this is the last projected program end.',
                      ),
                    if (_unavailableCount(
                          widget.channel.source,
                          widget.playableById ??
                              widget.controller.playableInventory.byId,
                        )
                        case final count when count > 0)
                      Text(
                        '$count unavailable hand-picked ${count == 1 ? 'item is' : 'items are'} retained but off air until available or removed.',
                      ),
                    if (_changesOnNow(preview, now))
                      const Text(
                        'Saving these programming changes may change what is on now',
                        key: Key('air-check-on-now-warning'),
                      ),
                    if (_comparisonFailed) ...[
                      const SizedBox(height: 8),
                      _comparisonErrorView(),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      if (preview.key != _targetKey)
                        const Text('Previous preview'),
                      _errorView(error),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _extendPreview(_AirCheckPreview preview) {
    final nextHours = (_futureHours + 6).clamp(6, 24);
    try {
      final expanded = _project(
        preview.schedule,
        preview.key,
        preview.channel,
        futureHours: nextHours,
      );
      setState(() {
        _futureHours = nextHours;
        _preview = expanded;
        _error = null;
        _preserveSelection(expanded, widget.clock());
      });
    } catch (error) {
      setState(() => _error = error);
    }
  }

  Widget _monitorHeader(DateTime now) {
    final roles = LineupTheme.of(context);
    final draft =
        widget.originalChannel == null ||
        _recipeKey(widget.originalChannel!) != _recipeKey(widget.channel);
    final status = _stale
        ? 'Updating — preview is stale'
        : draft
        ? 'Draft schedule'
        : 'Saved channel';
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 4,
          children: [
            Semantics(
              header: true,
              label: 'Schedule preview',
              child: Text(
                'Schedule preview',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              status,
              style: TextStyle(
                color: roles.secondaryText,
                fontSize: 11 * _uiScale,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Text(
          '${_weekday(now.toLocal().weekday)} · ${_time(context, now)}',
          style: TextStyle(
            color: roles.secondaryText,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _emptyRibbon(Widget child) => Container(
    constraints: BoxConstraints(minHeight: widget.compact ? 76 : 104),
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: LineupTheme.of(context).elevatedSurface,
      border: Border.all(color: LineupTheme.of(context).subtleBorder),
      borderRadius: BorderRadius.circular(LineupTheme.of(context).panelRadius),
    ),
    child: child,
  );

  Widget _facts(_AirCheckPreview preview) => Wrap(
    spacing: 10,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        'CH ${preview.channel.number} · ${preview.channel.name.toUpperCase()}',
        style: TextStyle(
          color: LineupTheme.of(context).progressFill,
          fontSize: 12 * _uiScale,
          fontWeight: FontWeight.w800,
        ),
      ),
      Text('${preview.schedule.items.length} playable'),
      Text('Cycle ${_duration(preview.schedule.loopDuration)}'),
      Text(_rhythm(preview.channel.playbackMode, preview.channel.blockSize)),
    ],
  );

  Widget _verticalSchedule(_AirCheckPreview preview, DateTime now) {
    final programs = _visiblePrograms(preview, now);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: ListView.separated(
        key: const Key('air-check-schedule-list'),
        shrinkWrap: true,
        itemCount: programs.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, color: LineupTheme.of(context).subtleBorder),
        itemBuilder: (context, index) {
          final program = programs[index];
          final current = program.isCurrentAt(now);
          final selected = program.id == _selectedId;
          final roles = LineupTheme.of(context);
          void activate() => setState(() {
            _selectedId = program.id;
            _selectionFollowsNow = false;
            _synopsisExpanded = false;
          });
          return Semantics(
            button: true,
            excludeSemantics: true,
            label:
                'Channel ${preview.channel.number} ${preview.channel.name}, ${program.scheduled.item.title}, ${_time(context, program.scheduled.start)} to ${_time(context, program.scheduled.end)}, ${current ? 'current' : 'upcoming'}',
            onTap: activate,
            child: OutlinedButton(
              key: ValueKey('air-check-program-${program.id}'),
              style: ButtonStyle(
                alignment: Alignment.centerLeft,
                padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                foregroundColor: WidgetStatePropertyAll(roles.primaryText),
                backgroundColor: WidgetStatePropertyAll(
                  selected ? roles.selectedSurface : Colors.transparent,
                ),
                side: WidgetStateProperty.resolveWith(
                  (states) => BorderSide(
                    color: states.contains(WidgetState.focused)
                        ? roles.focusBorder
                        : Colors.transparent,
                    width: states.contains(WidgetState.focused)
                        ? (roles.focusBorderWidth > 3
                              ? roles.focusBorderWidth
                              : 2)
                        : 1,
                  ),
                ),
              ),
              onPressed: activate,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 76,
                      child: Text(
                        current
                            ? 'ON NOW'
                            : _time(context, program.scheduled.start),
                        style: TextStyle(
                          color: current
                              ? roles.liveAccent
                              : roles.secondaryText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            program.scheduled.item.title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${_dateContext(program.scheduled.start)} · ${_time(context, program.scheduled.start)}–${_time(context, program.scheduled.end)}',
                            style: TextStyle(color: roles.secondaryText),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _dateContext(DateTime value) {
    final local = value.toLocal();
    final now = widget.clock().toLocal();
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return 'Today';
    }
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    if (local.year == tomorrow.year &&
        local.month == tomorrow.month &&
        local.day == tomorrow.day) {
      return 'Tomorrow';
    }
    return '${local.month}/${local.day}';
  }

  Widget _selection(_AirCheckPreview preview, DateTime now) {
    final visible = _visiblePrograms(preview, now);
    final selected = visible
        .where((program) => program.id == _selectedId)
        .firstOrNull;
    if (selected == null) return const SizedBox.shrink();
    final current = visible
        .where((program) => program.isCurrentAt(now))
        .firstOrNull;
    final item = selected.scheduled.item;
    final summary = item.summary?.trim();
    final showTitle = item.showTitle?.trim();
    final episode = [
      if (item.seasonNumber != null && item.episodeNumber != null)
        'S${item.seasonNumber} E${item.episodeNumber}',
      if (showTitle?.isNotEmpty == true && item.title != showTitle) item.title,
    ].join(' · ');
    final details = Column(
      key: const Key('air-check-selection'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${_temporal(selected, now).toUpperCase()} · ${_dateContext(selected.scheduled.start)} · ${_time(context, selected.scheduled.start)}–${_time(context, selected.scheduled.end)}',
          style: TextStyle(
            color: LineupTheme.of(context).secondaryText,
            fontSize: 11 * _uiScale,
            fontWeight: FontWeight.w800,
            letterSpacing: .7,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          showTitle?.isNotEmpty == true ? showTitle! : item.title,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (episode.isNotEmpty) Text(episode),
        const SizedBox(height: 3),
        Text(
          '${_duration(selected.scheduled.end.difference(selected.scheduled.start))} · ${widget.inclusionReason}',
          style: TextStyle(color: LineupTheme.of(context).secondaryText),
        ),
        if (summary?.isNotEmpty == true) ...[
          const SizedBox(height: 4),
          Text(summary!, maxLines: _synopsisExpanded ? null : 3),
          TextButton(
            onPressed: () =>
                setState(() => _synopsisExpanded = !_synopsisExpanded),
            child: Text(_synopsisExpanded ? 'Show less' : 'Read more'),
          ),
        ],
        if (current != null && current.id != selected.id)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() {
                _selectedId = current.id;
                _selectionFollowsNow = true;
                _synopsisExpanded = false;
              }),
              child: const Text('Back to now'),
            ),
          ),
      ],
    );
    final artwork = _artworkPath(selected.scheduled.item);
    if (artwork == null) return details;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96 * _uiScale,
          height: 72 * _uiScale,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              LineupTheme.of(context).panelRadius,
            ),
            child: _AirCheckArtwork(
              controller: widget.controller,
              path: artwork,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: details),
      ],
    );
  }

  Uri? _artworkPath(ChannelItem item) =>
      item.backdrop ??
      item.poster ??
      switch (item.showThumb) {
        final path? when path.isNotEmpty => Uri.tryParse(path),
        _ => null,
      };

  Widget _errorView(Object error) {
    final message = switch (error) {
      _ when _canRetainOffAir(error) => 'No retained hand-picked programs are currently available. They remain saved and explicitly off air.',
      _AirCheckSourceIssue(:final message) => message,
      ScheduleBuildException(reason: ScheduleFailureReason.unsupportedSource) => 'This source uses an unsupported filter. Replace it with supported programming.',
      ScheduleBuildException(reason: ScheduleFailureReason.noContent) =>
        'This source has no playable programs. Choose available programming.',
      _ => 'Air Check could not verify this schedule. Retry before saving.',
    };
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          Expanded(child: Text(message)),
          TextButton(onPressed: retry, child: const Text('Retry Air Check')),
        ],
      ),
    );
  }

  Widget _comparisonErrorView() => Semantics(
    liveRegion: true,
    child: Row(
      children: [
        const Expanded(
          child: Text(
            'Air Check could not compare this draft with the saved schedule. Retry before saving.',
          ),
        ),
        TextButton(onPressed: retry, child: const Text('Retry comparison')),
      ],
    ),
  );

  int _unavailableCount(
    ContentSource source,
    Map<String, Object?> playableById,
  ) => switch (source) {
    ManualSource(:final items) =>
      items.where((item) => !playableById.containsKey(item.id)).length,
    MixedSource(:final sources) => sources.fold(
      0,
      (count, source) => count + _unavailableCount(source, playableById),
    ),
    LibrarySource() || PlaylistSource() => 0,
  };

  bool _changesOnNow(_AirCheckPreview preview, DateTime now) {
    final original = widget.originalChannel;
    final originalSchedule = _originalSchedule;
    if (original == null ||
        _recipeKey(original) == _recipeKey(widget.channel)) {
      return false;
    }
    if (_originalOffAirKey == _wantedOriginalKey) return true;
    if (originalSchedule == null ||
        _originalScheduleKey != _wantedOriginalKey) {
      return false;
    }
    return programAt(now, original.anchor, originalSchedule).item.id !=
        programAt(now, preview.channel.anchor, preview.schedule).item.id;
  }
}

class _AirCheckRequest {
  const _AirCheckRequest({
    required this.key,
    required this.channel,
    required this.baseline,
    required this.publishes,
    required this.version,
    this.followUp,
  });

  final String key;
  final Channel channel;
  final bool baseline;
  final bool publishes;
  final int version;
  final _AirCheckRequest? followUp;
}

class _AirCheckArtwork extends StatefulWidget {
  const _AirCheckArtwork({required this.controller, required this.path});

  final LineupController controller;
  final Uri path;

  @override
  State<_AirCheckArtwork> createState() => _AirCheckArtworkState();
}

class _AirCheckArtworkState extends State<_AirCheckArtwork> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.artworkForPath(widget.path);
  }

  @override
  void didUpdateWidget(_AirCheckArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.path != widget.path) {
      _future = widget.controller.artworkForPath(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _future,
    builder: (context, snapshot) => switch (snapshot.data) {
      final bytes? => Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
      null => ColoredBox(color: LineupTheme.of(context).elevatedSurface),
    },
  );
}

class _AirCheckPreview {
  const _AirCheckPreview({
    required this.schedule,
    required this.channel,
    required this.window,
    required this.key,
    required this.windowStart,
    required this.windowEnd,
    required this.ribbonStart,
    required this.ribbonEnd,
  });

  final ScheduleIndex schedule;
  final Channel channel;
  final ScheduleWindowResult window;
  final String key;
  final DateTime windowStart;
  final DateTime windowEnd;
  final DateTime ribbonStart;
  final DateTime ribbonEnd;

  _AirCheckPreview withChannel(Channel value) => _AirCheckPreview(
    schedule: schedule,
    channel: value,
    window: window,
    key: key,
    windowStart: windowStart,
    windowEnd: windowEnd,
    ribbonStart: ribbonStart,
    ribbonEnd: ribbonEnd,
  );
  List<GuideProgram> get programs => window.programs
      .map(
        (scheduled) =>
            GuideProgram(channelId: 'air-check', scheduled: scheduled),
      )
      .toList(growable: false);
}

class _AirCheckSourceIssue {
  const _AirCheckSourceIssue(this.message);
  final String message;
}

bool _isNoContentFailure(Object error) =>
    error is ScheduleBuildException &&
    error.reason == ScheduleFailureReason.noContent;

String channelAirCheckSnapshotKey(Channel channel, int contentGeneration) =>
    '${_recipeKey(channel)}|$contentGeneration';

String _snapshotKey(ChannelAirCheck widget) => channelAirCheckSnapshotKey(
  widget.channel,
  widget.controller.contentGeneration,
);

String? _originalKey(ChannelAirCheck widget) => widget.originalChannel == null
    ? null
    : channelAirCheckSnapshotKey(
        widget.originalChannel!,
        widget.controller.contentGeneration,
      );

String _recipeKey(Channel channel) => canonicalScheduleIdentity(channel);

String _temporal(GuideProgram program, DateTime now) => program.isCurrentAt(now)
    ? 'current'
    : !program.scheduled.end.isAfter(now)
    ? 'past'
    : 'future';

String _time(BuildContext context, DateTime value) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(value.toLocal()),
      alwaysUse24HourFormat: false,
    );

String _weekday(int weekday) =>
    const ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'][weekday - 1];

String _duration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}

String _rhythm(PlaybackMode mode, int? blockSize) => switch (mode) {
  PlaybackMode.sequential => 'In order',
  PlaybackMode.shuffle => 'Mix it up',
  PlaybackMode.block => 'Mini-marathons of ${blockSize ?? 3}',
};
