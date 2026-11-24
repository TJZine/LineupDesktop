import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:lineup_desktop/platform/device_profile.dart';

import '../channels/channel.dart';
import '../channels/scheduler.dart';
import '../guide/guide_controller.dart';
import '../ui/app_theme.dart';
import '../ui/schedule_wall_time.dart';
import '../ui/app_ui.dart';
import 'lineup_controller.dart';
import 'air_check_verification.dart';
export 'air_check_verification.dart'
    show ChannelAirCheckValidity, channelAirCheckDebounce;

class ChannelAirCheck extends StatefulWidget {
  const ChannelAirCheck({
    required this.controller,
    required this.channel,
    required this.clock,
    required this.compact,
    required this.inclusionReason,
    required this.verification,
    required this.hasUnsavedChanges,
    this.viewportHeight,
    this.sourceIssue,
    this.sourceIssueExplained = false,
    this.playableById,
    super.key,
  });

  final LineupController controller;
  final Channel channel;
  final double? viewportHeight;
  final DateTime Function() clock;
  final bool compact;
  final String inclusionReason;
  final String? sourceIssue;
  final bool sourceIssueExplained;
  final Map<String, Object?>? playableById;
  final AirCheckVerification verification;
  final bool hasUnsavedChanges;

  @override
  State<ChannelAirCheck> createState() => _ChannelAirCheckState();
}

class _ChannelAirCheckState extends State<ChannelAirCheck> {
  static const _borderWidth = 1.0;
  String? _selectedId;
  bool _selectionFollowsNow = true;
  bool _synopsisExpanded = false;
  final _scheduleScroll = ScrollController();
  final _backToNowFocus = FocusNode(debugLabel: 'Air Check Back to now');
  final _selectionAnchor = GlobalKey();
  final _headerAnchor = GlobalKey();
  final _firstRowAnchor = GlobalKey();
  final _emptyAnchor = GlobalKey();
  final _recoveryAnchor = GlobalKey();
  final _footerAnchor = GlobalKey();
  double? _panelHeight;
  double? _minimumUsefulHeight;
  double? _measuredWidth;
  TextScaler? _measuredTextScaler;
  bool _measureScheduled = false;

  void _measureAvailableHeight() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      final outer = Scrollable.maybeOf(context);
      final panel = context.findRenderObject();
      final viewport = outer?.context.findRenderObject();
      if (outer == null || panel is! RenderBox || viewport is! RenderBox) {
        return;
      }
      // Measure in the outer scrollable's canvas coordinates. Including its
      // offset makes the allocation independent of ordinary page scrolling.
      final contentTop =
          panel.localToGlobal(Offset.zero, ancestor: viewport).dy +
          outer.position.pixels;
      final viewportHeight =
          widget.viewportHeight ?? outer.position.viewportDimension;
      final remaining = viewportHeight - contentTop;
      final scaler = MediaQuery.textScalerOf(context);
      if (_measuredWidth != panel.size.width || _measuredTextScaler != scaler) {
        _minimumUsefulHeight = null;
        _measuredWidth = panel.size.width;
        _measuredTextScaler = scaler;
      }
      double? extent(GlobalKey key) {
        final box = key.currentContext?.findRenderObject();
        return box is RenderBox && box.hasSize ? box.size.height : null;
      }

      final header = extent(_headerAnchor);
      final program = extent(_firstRowAnchor);
      final empty = extent(_emptyAnchor);
      final recovery = extent(_recoveryAnchor);
      final footer = extent(_footerAnchor);
      final padding = 2 * ((widget.compact ? 14.0 : 20.0) + _borderWidth);
      final body = _preview == null ? empty ?? recovery ?? 0 : program;
      if (header != null &&
          body != null &&
          (_preview == null || footer != null)) {
        final usableBody = body > (recovery ?? 0) ? body : recovery ?? 0;
        _minimumUsefulHeight =
            padding +
            header +
            usableBody +
            (footer ?? 0) +
            (_preview == null ? 0 : 8);
      }
      // Small positive space is no more useful than a preview below the fold.
      // Keep the existing columns and let the outer editor scroll reveal one
      // usable, locally bounded viewport instead of crushing its fixed footer.
      final minimum = _minimumUsefulHeight;
      final fixedHeight = padding + (footer == null ? 0 : footer + 8);
      final height = footer != null && fixedHeight >= viewportHeight
          // The footer alone fills the viewport. Keep room for the schedule
          // and let the editor scroll to reveal the whole panel.
          ? viewportHeight + footer + 8
          : minimum != null && remaining >= minimum && remaining > fixedHeight
          ? remaining.clamp(0.0, viewportHeight)
          : viewportHeight;
      if (_panelHeight == null || (_panelHeight! - height).abs() > .1) {
        setState(() => _panelHeight = height);
      }
    });
  }

  void _revealInspectedProgram({required bool fromRemote}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scheduleScroll.jumpTo(0);
      final outer = Scrollable.maybeOf(context);
      final panel = context.findRenderObject();
      final viewport = outer?.context.findRenderObject();
      if (outer == null || panel is! RenderBox || viewport is! RenderBox) {
        return;
      }
      final contentTop =
          panel.localToGlobal(Offset.zero, ancestor: viewport).dy +
          outer.position.pixels;
      outer.position.jumpTo(
        contentTop.clamp(
          outer.position.minScrollExtent,
          outer.position.maxScrollExtent,
        ),
      );
      final backToNow = fromRemote && _backToNowFocus.parent != null
          ? _backToNowFocus.context?.findRenderObject()
          : null;
      if (backToNow != null) {
        _backToNowFocus.requestFocus();
        _scheduleScroll.position.ensureVisible(
          backToNow,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
        return;
      }
      final selection = _selectionAnchor.currentContext?.findRenderObject();
      final inner = _scheduleScroll.position.context.storageContext
          .findRenderObject();
      if (selection is RenderBox && selection.hasSize && inner is RenderBox) {
        final top =
            selection.localToGlobal(Offset.zero, ancestor: inner).dy +
            _scheduleScroll.offset;
        final target =
            selection.size.height <= _scheduleScroll.position.viewportDimension
            ? top +
                  selection.size.height -
                  _scheduleScroll.position.viewportDimension
            : top;
        _scheduleScroll.jumpTo(
          target.clamp(0.0, _scheduleScroll.position.maxScrollExtent),
        );
      }
    });
  }

  void _backToNow(GuideProgram current) {
    setState(() {
      _selectedId = current.id;
      _selectionFollowsNow = true;
      _synopsisExpanded = false;
    });
    _scheduleScroll.jumpTo(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scheduleScroll.hasClients) return;
      final row = _firstRowAnchor.currentContext?.findRenderObject();
      if (row != null) {
        _scheduleScroll.position.ensureVisible(
          row,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });
  }

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
    _scheduleScroll.dispose();
    _backToNowFocus.dispose();
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
    _measureAvailableHeight();
    return Semantics(
      key: const Key('channel-air-check'),
      container: true,
      label:
          'Air Check for channel ${widget.channel.number} ${widget.channel.name}',
      child: SizedBox(
        height:
            _panelHeight ??
            widget.viewportHeight ??
            MediaQuery.sizeOf(context).height,
        child: Container(
          decoration: BoxDecoration(
            color: LineupTheme.of(context).primarySurface,
            border: Border.all(
              color: LineupTheme.of(context).subtleBorder,
              width: _borderWidth,
            ),
            borderRadius: BorderRadius.circular(
              LineupTheme.of(context).panelRadius,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: EdgeInsets.all(widget.compact ? 14 : 20),
            child: LayoutBuilder(
              builder: (context, constraints) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: CustomScrollView(
                      key: const Key('air-check-schedule-list'),
                      controller: _scheduleScroll,
                      slivers: [
                        SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              KeyedSubtree(
                                key: _headerAnchor,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _monitorHeader(now),
                                    const SizedBox(height: 10),
                                    if (preview != null) ...[
                                      _facts(preview),
                                      if (error != null)
                                        Text(
                                          'Previous schedule · ${preview.sourceLabel}',
                                          style: TextStyle(
                                            color: LineupTheme.of(context)
                                                .secondaryText,
                                          ),
                                        ),
                                      const SizedBox(height: 8),
                                    ],
                                  ],
                                ),
                              ),
                              if (preview == null && error == null)
                                KeyedSubtree(
                                  key: _emptyAnchor,
                                  child: _emptyRibbon(
                                    Semantics(
                                      liveRegion: true,
                                      label: 'Calculating schedule',
                                      child: Text(
                                        'Calculating schedule…',
                                        key: const Key('air-check-loading'),
                                        style: LineupTypography.tvLabelStyle(
                                          context,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              if (preview != null) ...[
                                if (_hasNonCurrentSelection(preview, now))
                                  _selection(preview, now),
                                const SizedBox(height: 8),
                              ],
                              if (_comparisonFailed ||
                                  (error != null &&
                                      (!widget.sourceIssueExplained ||
                                          _retryableError)))
                                KeyedSubtree(
                                  key: _recoveryAnchor,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (_comparisonFailed)
                                        _comparisonErrorView(),
                                      if (error != null &&
                                          (!widget.sourceIssueExplained ||
                                              _retryableError))
                                        _errorView(error),
                                    ],
                                  ),
                                ),
                              if (preview != null && preview.window.truncated)
                                Text(
                                  'Preview truncated at ${ScheduleWallTime(preview.window.lastProjectedEnd!).timeLabel(context)}; this is the last projected program end.',
                                  style: TextStyle(
                                    color: LineupTheme.of(context)
                                        .secondaryText,
                                  ),
                                ),
                              if (_unavailableCount(
                                    widget.channel.source,
                                    widget.playableById ??
                                        widget
                                            .controller
                                            .playableInventory
                                            .byId,
                                  )
                                  case final count when count > 0)
                                Text(
                                  '$count unavailable hand-picked ${count == 1 ? 'item is' : 'items are'} retained but off air until available or removed.',
                                  style: TextStyle(
                                    color: LineupTheme.of(context)
                                        .secondaryText,
                                  ),
                                ),
                              if (widget.verification.changesOnNow)
                                Text(
                                  'Saving these programming changes may change what is on now',
                                  key: const Key('air-check-on-now-warning'),
                                  style: TextStyle(
                                    color: LineupTheme.of(context)
                                        .secondaryText,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (preview != null)
                          SliverOpacity(
                            key: const Key('air-check-schedule-content'),
                            opacity: _stale ? .5 : 1,
                            sliver: _verticalSchedule(preview, now),
                          ),
                      ],
                    ),
                  ),
                  if (preview != null)
                    ConstrainedBox(
                      // Keep the footer reachable until the panel can use its
                      // measured height, even if it wraps beyond the viewport.
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight,
                      ),
                      child: SingleChildScrollView(
                        primary: false,
                        padding: const EdgeInsets.only(top: 8),
                        child: KeyedSubtree(
                          key: _footerAnchor,
                          child: _footer(preview),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _hasNonCurrentSelection(AirCheckPreview preview, DateTime now) =>
      _visiblePrograms(preview, now).any(
        (program) => program.id == _selectedId && !program.isCurrentAt(now),
      );

  Widget _footer(AirCheckPreview preview) {
    return Wrap(
      key: const Key('air-check-footer'),
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Schedule through ${ScheduleWallTime(preview.window.lastProjectedEnd ?? preview.windowEnd).timeLabel(context)}',
              style: TextStyle(color: LineupTheme.of(context).secondaryText),
            ),
            if (_futureHours < 24)
              LineupInlineLink(
                onPressed: _stale ? null : widget.verification.extendHorizon,
                child: Text(
                  'Show next 6 hours',
                  style: LineupTypography.tvLabelStyle(context),
                ),
              ),
          ],
        ),
        if (_error == null && !_comparisonFailed)
          Text(
            _stale
                ? 'Updating…'
                : widget.hasUnsavedChanges
                ? 'Updates as you edit'
                : 'Matches the saved channel',
            key: const Key('air-check-state-note'),
            style: TextStyle(color: LineupTheme.of(context).mutedText),
          ),
      ],
    );
  }

  Widget _monitorHeader(DateTime now) {
    final roles = LineupTheme.of(context);
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
          '${_weekday(now.toLocal().weekday)} · ${ScheduleWallTime(now).timeLabel(context)}',
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
    return SliverList.separated(
      itemCount: programs.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: LineupTheme.of(context).subtleBorder),
      itemBuilder: (context, index) {
        final program = programs[index];
        final current = program.isCurrentAt(now);
        final startLabel = ScheduleWallTime(program.scheduled.start)
            .timeLabel(context);
        final endLabel = ScheduleWallTime(program.scheduled.end)
            .timeLabel(context);
        final selected = program.id == _selectedId;
        void activate({bool fromRemote = false}) {
          setState(() {
            _selectedId = program.id;
            _selectionFollowsNow = false;
            _synopsisExpanded = false;
          });
          // The detail lives above this lazy list; reveal it when inspected.
          _scheduleScroll.jumpTo(0);
          _revealInspectedProgram(fromRemote: fromRemote);
        }

        final row = Semantics(
          button: true,
          excludeSemantics: true,
          label:
              'Channel ${preview.channel.number} ${preview.channel.name}, ${program.scheduled.item.title}, $startLabel to $endLabel, ${current ? 'current' : 'upcoming'}',
          onTap: activate,
          child: LineupNavigationRow(
            selected: selected || current,
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
                          current ? 'ON NOW' : startLabel,
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
                      StudioProgramArtwork(
                        controller: widget.controller,
                        path:
                            program.scheduled.item.poster ??
                            _artworkPath(program.scheduled.item),
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
                              [
                                if (program.scheduled.item.showTitle
                                    case final title? when title.isNotEmpty)
                                  title,
                                if (program.scheduled.item.seasonNumber !=
                                        null ||
                                    program.scheduled.item.episodeNumber !=
                                        null)
                                  'S${program.scheduled.item.seasonNumber ?? '—'} E${program.scheduled.item.episodeNumber ?? '—'}',
                                '$startLabel–$endLabel',
                              ].join(' · '),
                              style: _airCheckButtonTextStyle(
                                color: roles.mutedText,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            if (current)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: LinearProgressIndicator(
                                  value:
                                      now
                                          .difference(program.scheduled.start)
                                          .inMilliseconds /
                                      program.scheduled.end
                                          .difference(program.scheduled.start)
                                          .inMilliseconds,
                                  minHeight: 2,
                                  color: roles.progressFill,
                                  backgroundColor: roles.subtleBorder,
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
        return KeyedSubtree(
          key: index == 0 ? _firstRowAnchor : null,
          child: DeviceProfile.of(context).isTv
              ? CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.select): () =>
                        activate(fromRemote: true),
                  },
                  child: row,
                )
              : row,
        );
      },
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
          '${_temporal(selected, now).toUpperCase()} · ${_dateContext(selected.scheduled.start)} · ${ScheduleWallTime(selected.scheduled.start).timeLabel(context)}–${ScheduleWallTime(selected.scheduled.end).timeLabel(context)}',
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

            child: Text(
              _synopsisExpanded ? 'Show less' : 'Read more',
              style: LineupTypography.tvLabelStyle(context),
            ),
          ),
        ],
        if (current != null && current.id != selected.id)
          Align(
            alignment: Alignment.centerLeft,
            child: LineupInlineLink(
              focusNode: _backToNowFocus,
              onPressed: () => _backToNow(current),
              child: const Text('Back to now'),
            ),
          ),
      ],
    );
    final artwork = _artworkPath(selected.scheduled.item);
    if (artwork == null) {
      return KeyedSubtree(key: _selectionAnchor, child: details);
    }
    return KeyedSubtree(
      key: _selectionAnchor,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: (widget.compact ? 96 : 144),
            height: (widget.compact ? 72 : 108),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                LineupTheme.of(context).panelRadius,
              ),
              child: StudioProgramArtwork(
                controller: widget.controller,
                path: artwork,
                width: widget.compact ? 96 : 144,
                height: widget.compact ? 72 : 108,
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(child: details),
        ],
      ),
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

class StudioProgramArtwork extends StatefulWidget {
  const StudioProgramArtwork({
    required this.controller,
    this.path,
    this.width = 44,
    this.height = 64,
    super.key,
  });

  final LineupController controller;
  final Uri? path;
  final double width;
  final double height;

  @override
  State<StudioProgramArtwork> createState() => _StudioProgramArtworkState();
}

class _StudioProgramArtworkState extends State<StudioProgramArtwork> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(StudioProgramArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.path != widget.path ||
        oldWidget.width != widget.width ||
        oldWidget.height != widget.height) {
      _future = _load();
    }
  }

  Future<Uint8List?> _load() {
    final path = widget.path;
    return path == null
        ? Future.value(null)
        : widget.controller.programArtworkForPath(
            path,
            width: (widget.width * 3).ceil(),
            height: (widget.height * 3).ceil(),
          );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    height: widget.height,
    child: FutureBuilder<Uint8List?>(
      key: ObjectKey(_future),
      future: _future,
      builder: (context, snapshot) {
        final placeholder = ColoredBox(
          color: LineupTheme.of(context).elevatedSurface,
        );
        final bytes = snapshot.data;
        return bytes == null
            ? placeholder
            : Image.memory(
                bytes,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder,
              );
      },
    ),
  );
}

String _temporal(GuideProgram program, DateTime now) => program.isCurrentAt(now)
    ? 'current'
    : !program.scheduled.end.isAfter(now)
    ? 'past'
    : 'future';

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
