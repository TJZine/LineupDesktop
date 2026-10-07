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
    this.sourceIssueExplained = false,
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
  final bool sourceIssueExplained;
  final Map<String, Object?>? playableById;
  final ValueChanged<ChannelAirCheckStatus> onValidityChanged;

  @override
  State<ChannelAirCheck> createState() => _ChannelAirCheckState();
}

class _ChannelAirCheckState extends State<ChannelAirCheck> {
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

  TextStyle _airCheckButtonTextStyle({Color? color, FontWeight? fontWeight}) {
    final base =
        Theme.of(context).outlinedButtonTheme.style?.textStyle
            ?.resolve(const {}) ??
        Theme.of(context).textTheme.labelLarge ??
        const TextStyle(fontSize: 14);
    return base.copyWith(
      fontSize: (base.fontSize ?? 14),
      color: color,
      fontWeight: fontWeight,
    );
  }

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
        when preview.key == nextKey &&
            (preview.channel.name != widget.channel.name ||
                preview.channel.number != widget.channel.number)) {
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
      sourceLabel: widget.inclusionReason,
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
          sourceLabel: widget.inclusionReason,
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
              final preview = _project(
                schedule,
                request.key,
                request.channel,
                sourceLabel: request.sourceLabel,
              );
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
    required String sourceLabel,
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
      sourceLabel: sourceLabel,
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
        ? _project(
            previous.schedule,
            previous.key,
            previous.channel,
            sourceLabel: previous.sourceLabel,
          )
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
              padding: EdgeInsets.all((widget.compact ? 14 : 20)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _monitorHeader(now),
                  SizedBox(height: 10),
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
                  else if (preview == null &&
                      (!widget.sourceIssueExplained || _retryableError))
                    _emptyRibbon(_errorView(error!))
                  else if (preview == null)
                    const SizedBox.shrink()
                  else ...[
                    if (_stale)
                      Text(
                        'Previous schedule · ${preview.sourceLabel}',
                        key: const Key('air-check-retained-source'),
                      ),
                    Opacity(
                      key: const Key('air-check-schedule-content'),
                      opacity: _stale ? .5 : 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _facts(preview),
                          SizedBox(height: 8),
                          _selection(preview, now),
                          SizedBox(height: 8),
                          _verticalSchedule(preview, now),
                          Wrap(
                            spacing: 12,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'Schedule through ${_time(context, preview.window.lastProjectedEnd ?? preview.windowEnd)}',
                              ),
                              if (_futureHours < 24)
                                LineupInlineLink(
                                  onPressed: _stale
                                      ? null
                                      : () => _extendPreview(preview),
                                  child: const Text('Show next 6 hours'),
                                ),
                            ],
                          ),
                          if (preview.window.truncated)
                            Text(
                              'Preview truncated at ${_time(context, preview.window.lastProjectedEnd!)}; this is the last projected program end.',
                            ),
                          if (_unavailableCount(
                                preview.channel.source,
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
                        ],
                      ),
                    ),
                    if (_comparisonFailed) ...[
                      SizedBox(height: 8),
                      _comparisonErrorView(),
                    ],
                    if (error != null) ...[
                      SizedBox(height: 8),
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
        sourceLabel: preview.sourceLabel,
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
    final status = _stale || _error != null
        ? 'Out of date'
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
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: (widget.compact ? 16 : 24),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              status,
              style: TextStyle(
                color: roles.secondaryText,
                fontSize: (widget.compact ? 11 : 16),
                fontWeight: FontWeight.w400,
              ),
            ),
            if (_retryableError || _comparisonFailed)
              LineupInlineLink(
                onPressed: retry,
                child: Text(
                  _retryableError ? 'Retry Air Check' : 'Retry comparison',
                ),
              ),
          ],
        ),
        Text(
          '${_weekday(now.toLocal().weekday)} · ${_time(context, now)}',
          style: TextStyle(
            color: roles.secondaryText,
            fontWeight: FontWeight.w400,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _emptyRibbon(Widget child) => Container(
    constraints: BoxConstraints(minHeight: (widget.compact ? 76 : 104)),
    alignment: Alignment.centerLeft,
    padding: EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: LineupTheme.of(context).elevatedSurface,
      border: Border.all(color: LineupTheme.of(context).subtleBorder),
      borderRadius: BorderRadius.circular(LineupTheme.of(context).panelRadius),
    ),
    child: child,
  );

  Widget _facts(_AirCheckPreview preview) => Text(
    'Ch ${preview.channel.number} · ${preview.schedule.items.length} playable · ${_duration(preview.schedule.loopDuration)} cycle · ${_rhythm(preview.channel.playbackMode, preview.channel.blockSize)}',
    style: TextStyle(color: LineupTheme.of(context).secondaryText),
  );

  Widget _verticalSchedule(_AirCheckPreview preview, DateTime now) {
    final programs = _visiblePrograms(preview, now);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: widget.compact
            ? 360
            : (MediaQuery.sizeOf(context).height * .30).clamp(300, 680),
      ),
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
            child: LineupNavigationRow(
              selected: selected,
              key: ValueKey('air-check-program-${program.id}'),
              onPressed: activate,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: (widget.compact ? 10 : 14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: (widget.compact ? 76 : 94),
                      child: Text(
                        current
                            ? 'ON NOW'
                            : _time(context, program.scheduled.start),
                        style: TextStyle(
                          color: current
                              ? roles.liveAccent
                              : roles.secondaryText,
                          fontWeight: current
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            program.scheduled.item.title,
                            style: TextStyle(
                              fontSize: (widget.compact ? 14 : 20),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${_dateContext(program.scheduled.start)} · ${_time(context, program.scheduled.start)}–${_time(context, program.scheduled.end)}',
                            style: _airCheckButtonTextStyle(
                              color: roles.secondaryText,
                              fontWeight: FontWeight.w400,
                            ),
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
            fontSize: (widget.compact ? 11 : 16),
            fontWeight: FontWeight.w500,
            letterSpacing: .7,
          ),
        ),
        SizedBox(height: 6),
        Text(
          showTitle?.isNotEmpty == true ? showTitle! : item.title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: (widget.compact ? 16 : 28),
            fontWeight: FontWeight.w600,
          ),
        ),
        if (episode.isNotEmpty) Text(episode),
        SizedBox(height: 6),
        Text(
          '${_duration(selected.scheduled.end.difference(selected.scheduled.start))} · ${preview.sourceLabel}',
          style: TextStyle(color: LineupTheme.of(context).secondaryText),
        ),
        if (summary?.isNotEmpty == true) ...[
          SizedBox(height: 4),
          Text(summary!, maxLines: _synopsisExpanded ? null : 3),
          LineupInlineLink(
            onPressed: () =>
                setState(() => _synopsisExpanded = !_synopsisExpanded),

            child: Text(_synopsisExpanded ? 'Show less' : 'Read more'),
          ),
        ],
        if (current != null && current.id != selected.id)
          Align(
            alignment: Alignment.centerLeft,
            child: LineupInlineLink(
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
          width: (widget.compact ? 96 : 144),
          height: (widget.compact ? 72 : 108),
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
        SizedBox(width: 12),
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
    if (widget.sourceIssueExplained && !_retryableError) {
      return const SizedBox.shrink();
    }
    return Semantics(liveRegion: true, child: Text(message));
  }

  bool get _retryableError =>
      _error != null &&
      _error is! _AirCheckSourceIssue &&
      !(_error is ScheduleBuildException &&
          ((_error as ScheduleBuildException).reason ==
                  ScheduleFailureReason.noContent ||
              (_error as ScheduleBuildException).reason ==
                  ScheduleFailureReason.unsupportedSource));

  Widget _comparisonErrorView() => Semantics(
    liveRegion: true,
    child: Text(
      'Air Check could not compare this draft with the saved schedule. Retry before saving.',
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
    required this.sourceLabel,
    this.followUp,
  });

  final String key;
  final Channel channel;
  final bool baseline;
  final bool publishes;
  final int version;
  final String sourceLabel;
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
    required this.sourceLabel,
    required this.channel,
    required this.window,
    required this.key,
    required this.windowStart,
    required this.windowEnd,
    required this.ribbonStart,
    required this.ribbonEnd,
  });

  final ScheduleIndex schedule;
  final String sourceLabel;
  final Channel channel;
  final ScheduleWindowResult window;
  final String key;
  final DateTime windowStart;
  final DateTime windowEnd;
  final DateTime ribbonStart;
  final DateTime ribbonEnd;

  _AirCheckPreview withChannel(Channel value) => _AirCheckPreview(
    schedule: schedule,
    sourceLabel: sourceLabel,
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
  PlaybackMode.shuffle => 'Shuffle',
  PlaybackMode.block => 'Mini-marathons of ${blockSize ?? 3}',
};
