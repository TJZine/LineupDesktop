import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lineup_desktop/platform/device_profile.dart';

import '../channels/channel.dart';
import '../channels/scheduler.dart';
import '../guide/guide_controller.dart';
import '../ui/app_theme.dart';
import '../ui/app_ui.dart';
import 'lineup_controller.dart';
import 'air_check_verification.dart';
export 'air_check_verification.dart'
    show
        ChannelAirCheckValidity,
        channelAirCheckDebounce,
        channelAirCheckSnapshotKey;

class ChannelAirCheck extends StatefulWidget {
  const ChannelAirCheck({
    required this.controller,
    required this.channel,
    required this.clock,
    required this.compact,
    required this.inclusionReason,
    required this.verification,
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
  final AirCheckVerification verification;

  @override
  State<ChannelAirCheck> createState() => _ChannelAirCheckState();
}

class _ChannelAirCheckState extends State<ChannelAirCheck> {
  String? _selectedId;
  bool _selectionFollowsNow = true;
  bool _synopsisExpanded = false;
  AirCheckPreview? get _preview => widget.verification.result.preview;
  Object? get _error => widget.verification.result.error;
  bool get _comparisonFailed => widget.verification.comparisonFailed;
  bool get _stale => widget.verification.stale;
  int get _futureHours => widget.verification.futureHours;
  void retry() => widget.verification.retry();

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
    widget.verification.addListener(_verificationChanged);
    if (_preview case final preview?) {
      _preserveSelection(preview, widget.clock());
    }
  }

  @override
  void didUpdateWidget(ChannelAirCheck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.verification != widget.verification) {
      oldWidget.verification.removeListener(_verificationChanged);
      widget.verification.addListener(_verificationChanged);
    }
  }

  void _verificationChanged() {
    if (!mounted) return;
    setState(() {
      if (_preview case final preview?) {
        _preserveSelection(preview, widget.clock());
      }
    });
  }

  @override
  void dispose() {
    widget.verification.removeListener(_verificationChanged);
    super.dispose();
  }

  List<GuideProgram> _visiblePrograms(AirCheckPreview preview, DateTime now) =>
      preview.programs
          .where((program) => program.scheduled.end.isAfter(now))
          .toList(growable: false);

  void _preserveSelection(AirCheckPreview preview, DateTime now) {
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
    return error is ScheduleBuildException &&
        error.reason == ScheduleFailureReason.noContent;
  }

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
                                      : widget.verification.extendHorizon,
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
                          if (widget.verification.changesOnNow)
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

  Widget _facts(AirCheckPreview preview) => Text(
    'Ch ${preview.channel.number} · ${preview.schedule.items.length} playable · ${_duration(preview.schedule.loopDuration)} cycle · ${_rhythm(preview.channel.playbackMode, preview.channel.blockSize)}',
    style: TextStyle(color: LineupTheme.of(context).secondaryText),
  );

  Widget _verticalSchedule(AirCheckPreview preview, DateTime now) {
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
              child: Builder(
                builder: (context) {
                  final roles = LineupTheme.of(context);
                  final focused =
                      DeviceProfile.of(context).isTv &&
                      Focus.of(context).hasFocus &&
                      LineupFocusScope.visible(context);
                  return Padding(
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
                                  ? (focused
                                        ? roles.primaryText
                                        : roles.liveAccent)
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
                  );
                },
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

  Widget _selection(AirCheckPreview preview, DateTime now) {
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
      AirCheckSourceIssue(:final message) => message,
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
      _error is! AirCheckSourceIssue &&
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
