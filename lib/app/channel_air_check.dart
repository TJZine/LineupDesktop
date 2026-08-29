import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../channels/channel.dart';
import '../channels/scheduler.dart';
import '../guide/guide_controller.dart';
import '../ui/app_theme.dart';
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
  static const _pastContext = Duration(hours: 1);
  static const _window = Duration(hours: 6);

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
  int _requestVersion = 0;
  ChannelAirCheckStatus? _reportedStatus;
  late String _targetKey;
  String? _wantedOriginalKey;

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
              _selectedId = preview.programs
                  .where((program) => program.isCurrentAt(widget.clock()))
                  .firstOrNull
                  ?.id;
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
    Channel channel,
  ) {
    final now = widget.clock().toUtc();
    final start = now.subtract(_pastContext);
    var result = scheduleWindowResult(
      start,
      start.add(_window),
      channel.anchor,
      schedule,
    );
    var projectedStart = start;
    if (!(result.lastProjectedEnd?.isAfter(now) ?? false)) {
      projectedStart = now;
      result = scheduleWindowResult(
        now,
        start.add(_window),
        channel.anchor,
        schedule,
      );
    }
    return _AirCheckPreview(
      schedule: schedule,
      channel: channel,
      window: result,
      key: key,
      windowStart: projectedStart,
      windowEnd: start.add(_window),
      ribbonStart: start,
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
    final current = next.programs
        .where((item) => item.isCurrentAt(now))
        .firstOrNull;
    final selectedStillPresent = next.programs.any(
      (item) => item.id == _selectedId,
    );
    setState(() {
      _preview = next;
      if (_selectionFollowsNow || !selectedStillPresent) {
        _selectedId = current?.id;
      }
    });
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: LineupTheme.of(context).elevatedSurface,
          border: Border.all(color: LineupTheme.of(context).defaultBorder),
          borderRadius: BorderRadius.circular(
            LineupTheme.of(context).panelRadius,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 4,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Air Check',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (_stale) const Text('Updating — preview is stale'),
                ],
              ),
              const SizedBox(height: 8),
              if (preview == null && error == null)
                Semantics(
                  liveRegion: true,
                  label: 'Calculating schedule',
                  child: const Text(
                    'Calculating schedule…',
                    key: Key('air-check-loading'),
                  ),
                )
              else if (preview == null)
                _errorView(error!)
              else ...[
                _facts(preview),
                const SizedBox(height: 8),
                _ribbon(preview, now),
                const SizedBox(height: 8),
                _selection(preview, now),
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
                  _errorView(error),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _facts(_AirCheckPreview preview) => Wrap(
    spacing: 16,
    runSpacing: 4,
    children: [
      Text('${preview.schedule.items.length} playable'),
      Text('Cycle ${_duration(preview.schedule.loopDuration)}'),
      Text(_rhythm(preview.channel.playbackMode, preview.channel.blockSize)),
    ],
  );

  Widget _ribbon(_AirCheckPreview preview, DateTime now) {
    final all = preview.programs;
    final currentIndex = all.indexWhere((program) => program.isCurrentAt(now));
    final ribbonStart = preview.ribbonStart;
    final ribbonEnd = preview.ribbonEnd;
    final visible = widget.compact
        ? all.skip(currentIndex < 0 ? 0 : currentIndex).take(2).toList()
        : all
              .where(
                (program) =>
                    program.scheduled.end.isAfter(ribbonStart) &&
                    program.scheduled.start.isBefore(ribbonEnd),
              )
              .take(64)
              .toList();
    final start = widget.compact ? preview.windowStart : ribbonStart;
    final end = widget.compact ? preview.windowEnd : ribbonEnd;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return SizedBox(
      height: (widget.compact ? 76 : 104) + (textScale - 1).clamp(0, 1) * 52,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          fit: StackFit.expand,
          children: [
            for (var index = 0; index < visible.length; index++)
              _programButton(
                visible[index],
                now,
                start,
                end,
                constraints.maxWidth,
                compactIndex: index,
              ),
            if (!widget.compact && !now.isBefore(start) && now.isBefore(end))
              Positioned(
                left: GuideGeometry.programRect(
                  windowStart: start,
                  windowEnd: end,
                  programStart: now,
                  programEnd: now,
                  viewportWidth: constraints.maxWidth,
                ).left,
                top: 0,
                bottom: 0,
                child: ExcludeSemantics(
                  child: Container(
                    key: const Key('air-check-now-line'),
                    width: 2,
                    color: LineupTheme.of(context).liveAccent,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _programButton(
    GuideProgram program,
    DateTime now,
    DateTime start,
    DateTime end,
    double width, {
    required int compactIndex,
  }) {
    final state = _temporal(program, now);
    final selected = program.id == _selectedId;
    final rect = widget.compact
        ? null
        : GuideGeometry.programRect(
            windowStart: start,
            windowEnd: end,
            programStart: program.scheduled.start,
            programEnd: program.scheduled.end,
            viewportWidth: width,
          );
    final semanticLabel =
        'Channel ${widget.channel.number} ${widget.channel.name}, ${program.scheduled.item.title}, ${_time(context, program.scheduled.start)} to ${_time(context, program.scheduled.end)}, $state${selected ? ', selected' : ''}';
    if (!widget.compact && rect!.width < 56) {
      return Positioned(
        left: rect.left,
        top: 0,
        bottom: 0,
        width: rect.width.clamp(1, width),
        child: Semantics(
          button: true,
          selected: selected,
          label: semanticLabel,
          child: OutlinedButton(
            key: ValueKey('air-check-program-${program.id}'),
            onPressed: () => setState(() {
              _selectedId = program.id;
              _selectionFollowsNow = false;
            }),
            style: ButtonStyle(
              padding: const WidgetStatePropertyAll(EdgeInsets.zero),
              minimumSize: const WidgetStatePropertyAll(Size.zero),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: WidgetStatePropertyAll(
                selected
                    ? LineupTheme.of(context).selectedSurface
                    : LineupTheme.of(context).primarySurface,
              ),
              side: WidgetStateProperty.resolveWith((states) {
                final focused = states.contains(WidgetState.focused);
                return BorderSide(
                  color: focused
                      ? LineupTheme.of(context).focusBorder
                      : selected
                      ? LineupTheme.of(context).progressFill
                      : LineupTheme.of(context).subtleBorder,
                  width: focused
                      ? LineupTheme.of(context).focusBorderWidth
                      : selected
                      ? 2
                      : 1,
                );
              }),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      );
    }
    final button = Semantics(
      selected: selected,
      label: semanticLabel,
      child: OutlinedButton(
        key: ValueKey('air-check-program-${program.id}'),
        onPressed: () => setState(() {
          _selectedId = program.id;
          _selectionFollowsNow = false;
        }),
        style: ButtonStyle(
          alignment: Alignment.centerLeft,
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 8),
          ),
          side: WidgetStateProperty.resolveWith((states) {
            final focused = states.contains(WidgetState.focused);
            return BorderSide(
              color: focused
                  ? LineupTheme.of(context).focusBorder
                  : selected
                  ? LineupTheme.of(context).progressFill
                  : LineupTheme.of(context).subtleBorder,
              width: focused
                  ? LineupTheme.of(context).focusBorderWidth
                  : selected
                  ? 2
                  : 1,
            );
          }),
        ),
        child: ExcludeSemantics(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                state == 'current' ? 'ON NOW' : state.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              Text(
                program.scheduled.item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(_time(context, program.scheduled.start)),
            ],
          ),
        ),
      ),
    );
    if (widget.compact) {
      return Positioned(
        left: compactIndex.clamp(0, 1) * (width / 2),
        top: 0,
        bottom: 0,
        width: width / 2,
        child: button,
      );
    }
    return Positioned(
      left: rect!.left,
      top: 0,
      bottom: 0,
      width: rect.width.clamp(42, width),
      child: button,
    );
  }

  Widget _selection(_AirCheckPreview preview, DateTime now) {
    final selected = preview.programs
        .where((program) => program.id == _selectedId)
        .firstOrNull;
    if (selected == null) return const SizedBox.shrink();
    return Text(
      '${selected.scheduled.item.title} • ${_time(context, selected.scheduled.start)}–${_time(context, selected.scheduled.end)} • ${_temporal(selected, now)} • ${widget.inclusionReason}',
      key: const Key('air-check-selection'),
    );
  }

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

String _recipeKey(Channel channel) => jsonEncode({
  'source': channel.source.toJson(),
  'mode': channel.playbackMode.name,
  'block': channel.blockSize,
  'anchor': channel.anchor.toUtc().toIso8601String(),
  'seed': channel.shuffleSeed,
});

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
