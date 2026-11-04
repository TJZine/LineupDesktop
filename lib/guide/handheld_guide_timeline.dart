part of 'guide_view.dart';

class _HandheldGuideTimeline extends StatelessWidget {
  const _HandheldGuideTimeline({
    required this.controller,
    required this.clock,
    required this.timelineStart,
    required this.onTimelineStartChanged,
    required this.railWidth,
    required this.phone,
    required this.rowHeight,
    required this.rulerHeight,
    required this.scroll,
    required this.watchingChannelId,
    required this.allFailed,
    required this.retryFocus,
    required this.setupFocus,
    required this.onSetUpChannels,
    required this.onTune,
    required this.onProgramTap,
    required this.onProgramDetails,
  });

  final GuideController controller;
  final ValueNotifier<DateTime> clock;
  final ValueListenable<DateTime?> timelineStart;
  final ValueChanged<DateTime?> onTimelineStartChanged;
  final double railWidth;
  final bool phone;
  final double rowHeight;
  final double rulerHeight;
  final ScrollController scroll;
  final String? watchingChannelId;
  final bool allFailed;
  final FocusNode retryFocus;
  final FocusNode setupFocus;
  final VoidCallback? onSetUpChannels;
  final Future<void> Function(String) onTune;
  final void Function(Channel, GuideProgram) onProgramTap;
  final void Function(Channel, GuideProgram) onProgramDetails;

  static const _tileGap = 8.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final timelineLeft = railWidth + _tileGap;
      final width = math.max(0.0, box.maxWidth - timelineLeft);
      final perMinute = phone ? width * .55 / 30 : width / 75;
      final start = controller.windowStart;
      final minutes = _guideMinutes(controller.windowEnd.difference(start));
      final maximumOffset = math.max(0.0, minutes - (phone ? 30 / .55 : 75));
      final channels = controller.channels;
      double scrollMinutes(DateTime? anchor) =>
          _guideMinutes((anchor ?? start).difference(start))
              .clamp(0.0, maximumOffset);

      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        excludeFromSemantics: true,
        onHorizontalDragUpdate: perMinute == 0
            ? null
            : (details) {
                final offset =
                    (scrollMinutes(timelineStart.value) -
                            details.delta.dx / perMinute)
                        .clamp(0.0, maximumOffset);
                onTimelineStartChanged(
                  offset == 0
                      ? null
                      : start.add(
                          Duration(
                            microseconds:
                                (offset * Duration.microsecondsPerMinute)
                                    .round(),
                          ),
                        ),
                );
              },
        child: ValueListenableBuilder<DateTime?>(
          valueListenable: timelineStart,
          builder: (context, anchor, _) {
            final geometry = _HandheldTimelineGeometry(
              start: start,
              minutes: minutes,
              scrollMinutes: scrollMinutes(anchor),
              perMinute: perMinute,
              width: width,
            );
            return ValueListenableBuilder<DateTime>(
              valueListenable: clock,
              builder: (context, now, _) => Stack(
                children: [
                  Column(
                    children: [
                      MediaQuery.withClampedTextScaling(
                        maxScaleFactor: 1.3,
                        child: _HandheldGuideRuler(
                          geometry: geometry,
                          timelineLeft: timelineLeft,
                          height: rulerHeight,
                        ),
                      ),
                      Expanded(
                        child: channels.isEmpty
                            ? _NoMatchingChannels(
                                filtered: controller.lineup.channels.isNotEmpty,
                                onSetUpChannels: onSetUpChannels,
                                setupFocus: setupFocus,
                              )
                            : MediaQuery.withClampedTextScaling(
                                maxScaleFactor: 1.3,
                                child: ExcludeSemantics(
                                  excluding: allFailed,
                                  child: ListView.builder(
                                    key: const Key('guide-schedule-list'),
                                    controller: scroll,
                                    padding: EdgeInsets.zero,
                                    itemCount: channels.length,
                                    itemExtent: rowHeight,
                                    physics: _GuideRowScrollPhysics(
                                      rowHeight: rowHeight,
                                    ),
                                    itemBuilder: (context, index) {
                                      final channel = channels[index];
                                      return _HandheldGuideRow(
                                        controller: controller,
                                        channel: channel,
                                        railWidth: railWidth,
                                        tileGap: _tileGap,
                                        geometry: geometry,
                                        now: now,
                                        tuned: channel.id == watchingChannelId,
                                        quiet: allFailed,
                                        onTune: () =>
                                            unawaited(onTune(channel.id)),
                                        onProgramTap: (program) =>
                                            onProgramTap(channel, program),
                                        onProgramDetails: (program) =>
                                            onProgramDetails(channel, program),
                                      );
                                    },
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                  if (channels.isNotEmpty && !allFailed)
                    _HandheldNowLine(
                      geometry: geometry,
                      timelineLeft: timelineLeft,
                      now: now,
                    ),
                  if (allFailed)
                    Positioned.fill(
                      top: rulerHeight,
                      child: ColoredBox(
                        color: LineupTheme.of(context).deepBackground,
                        child: Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  "Schedules couldn't load",
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 12),
                                LineupTouchTarget(
                                  onPressed: controller.retryFailedRows,
                                  child: OutlinedButton(
                                    focusNode: retryFocus,
                                    onPressed: controller.retryFailedRows,
                                    child: const Text('Retry'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

class _HandheldTimelineGeometry {
  const _HandheldTimelineGeometry({
    required this.start,
    required this.minutes,
    required this.scrollMinutes,
    required this.perMinute,
    required this.width,
  });

  final DateTime start;
  final double minutes;
  final double scrollMinutes;
  final double perMinute;
  final double width;

  double x(DateTime time) =>
      (_guideMinutes(time.difference(start)) - scrollMinutes) * perMinute;
}

double _guideMinutes(Duration value) =>
    value.inMicroseconds / Duration.microsecondsPerMinute;

class _HandheldGuideRuler extends StatelessWidget {
  const _HandheldGuideRuler({
    required this.geometry,
    required this.timelineLeft,
    required this.height,
  });

  final _HandheldTimelineGeometry geometry;
  final double timelineLeft;
  final double height;

  @override
  Widget build(BuildContext context) {
    final style = LineupTypography.small.copyWith(
      color: LineupTheme.of(context).mutedText,
    );
    final first = (geometry.scrollMinutes / 30).floor() * 30;
    return SizedBox(
      key: const Key('handheld-guide-ruler'),
      height: height,
      child: Row(
        children: [
          SizedBox(
            width: timelineLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Text(
                'Today',
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(
            child: ClipRect(
              child: Stack(
                children: [
                  for (
                    var minute = first;
                    minute <= geometry.minutes &&
                        (minute - geometry.scrollMinutes) * geometry.perMinute <
                            geometry.width;
                    minute += 30
                  )
                    Positioned(
                      left:
                          (minute - geometry.scrollMinutes) *
                              geometry.perMinute +
                          2,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Text(
                          _time(
                            context,
                            geometry.start.add(Duration(minutes: minute)),
                          ),
                          style: style,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HandheldNowLine extends StatelessWidget {
  const _HandheldNowLine({
    required this.geometry,
    required this.timelineLeft,
    required this.now,
  });

  final _HandheldTimelineGeometry geometry;
  final double timelineLeft;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final x = geometry.x(now);
    if (x < 0 || x >= geometry.width) return const SizedBox.shrink();
    return Positioned(
      left: timelineLeft + x,
      top: 0,
      bottom: 0,
      child: Semantics(
        label: 'Current time',
        child: IgnorePointer(
          child: ColoredBox(
            color: LineupTheme.of(context).liveAccent,
            child: SizedBox(
              key: const Key('guide-now-line'),
              width: math.min(2, geometry.width - x),
            ),
          ),
        ),
      ),
    );
  }
}

class _HandheldGuideRow extends StatelessWidget {
  const _HandheldGuideRow({
    required this.controller,
    required this.channel,
    required this.railWidth,
    required this.tileGap,
    required this.geometry,
    required this.now,
    required this.tuned,
    required this.quiet,
    required this.onTune,
    required this.onProgramTap,
    required this.onProgramDetails,
  });

  final GuideController controller;
  final Channel channel;
  final double railWidth;
  final double tileGap;
  final _HandheldTimelineGeometry geometry;
  final DateTime now;
  final bool tuned;
  final bool quiet;
  final VoidCallback onTune;
  final ValueChanged<GuideProgram> onProgramTap;
  final ValueChanged<GuideProgram> onProgramDetails;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final row = controller.row(channel.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: railWidth,
            child: _HandheldGuideAction(
              key: ValueKey('handheld-guide-channel-${channel.id}'),
              label: 'Channel ${channel.number}, ${channel.name}. Watch.',
              onTap: onTune,
              color: tuned ? roles.tunedSurface : roles.elevatedSurface,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${channel.number}',
                      style: LineupTypography.title(
                        26,
                        90,
                      ).copyWith(color: roles.primaryText),
                    ),
                    _GuideWordText(
                      channel.name,
                      maxLines: 2,
                      style: LineupTypography.small.copyWith(
                        fontSize: 12,
                        height: 1.15,
                        letterSpacing: 0,
                        color: tuned ? roles.primaryText : roles.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: tileGap),
          Expanded(
            child: switch (row.state) {
              _ when quiet => const SizedBox.shrink(),
              GuideLoadState.ready => ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    for (final program in row.programs)
                      if (_cardGeometry(program) case final rect?)
                        Positioned(
                          left: rect.left,
                          width: rect.width,
                          top: 0,
                          bottom: 0,
                          child: _HandheldGuideCard(
                            key: ValueKey(program.id),
                            controller: controller,
                            channel: channel,
                            program: program,
                            now: now,
                            tuned: tuned,
                            visibleFractionStart: rect.visibleFractionStart,
                            visibleFractionEnd: rect.visibleFractionEnd,
                            onTap: () => onProgramTap(program),
                            onDetails: () => onProgramDetails(program),
                          ),
                        ),
                  ],
                ),
              ),
              _ => _rowStatus(
                context,
                failed: row.state == GuideLoadState.error,
              ),
            },
          ),
        ],
      ),
    );
  }

  ({
    double left,
    double width,
    double visibleFractionStart,
    double visibleFractionEnd,
  })?
  _cardGeometry(GuideProgram program) {
    final start = geometry.x(program.scheduled.start);
    final end = geometry.x(program.scheduled.end);
    final origin = -geometry.scrollMinutes * geometry.perMinute;
    // Each item owns half the space between it and its neighbor. The painted
    // card has the six-unit gap; clipped targets never overlap their neighbors.
    final left = math.max(0.0, math.max(origin, start));
    final right = math.min(geometry.width, end);
    if (right <= left) return null;
    final duration = end - start;
    return (
      left: left,
      width: right - left,
      visibleFractionStart: (left - start) / duration,
      visibleFractionEnd: (right - start) / duration,
    );
  }

  Widget _rowStatus(BuildContext context, {required bool failed}) {
    void retry() => controller.retry(channel.id);
    return ColoredBox(
      color: LineupTheme.of(context).primarySurface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                failed ? 'Schedule unavailable' : 'Loading schedule…',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (failed)
              LineupTouchTarget(
                onPressed: retry,
                child: TextButton(onPressed: retry, child: const Text('Retry')),
              ),
          ],
        ),
      ),
    );
  }
}

class _HandheldGuideAction extends StatelessWidget {
  const _HandheldGuideAction({
    required this.label,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.color,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    onTap: onTap,
    onLongPress: onLongPress,
    excludeSemantics: true,
    child: Material(
      type: color == null ? MaterialType.transparency : MaterialType.canvas,
      color: color,
      borderRadius: color == null ? null : BorderRadius.circular(8),
      child: InkWell(
        excludeFromSemantics: true,
        onTap: onTap,
        onLongPress: onLongPress,
        child: child,
      ),
    ),
  );
}

class _HandheldGuideCard extends StatelessWidget {
  const _HandheldGuideCard({
    required this.controller,
    required this.channel,
    required this.program,
    required this.now,
    required this.tuned,
    required this.visibleFractionStart,
    required this.visibleFractionEnd,
    required this.onTap,
    required this.onDetails,
    super.key,
  });

  final GuideController controller;
  final Channel channel;
  final GuideProgram program;
  final DateTime now;
  final bool tuned;
  final double visibleFractionStart;
  final double visibleFractionEnd;
  final VoidCallback onTap;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final item = program.scheduled.item;
    final title = item.showTitle ?? item.title;
    final current = program.isCurrentAt(now);
    final ended = !program.scheduled.end.isAfter(now);
    final watching = current && tuned;
    final start = _time(context, program.scheduled.start);
    final time = current
        ? '${_minutesLeft(program.scheduled.end.difference(now))} left'
        : start;
    final subtitle = watching ? '● Watching · $time' : time;
    final state = current
        ? 'On now, $time. Watch.'
        : ended
        ? 'Ended. Details.'
        : 'Starts $start. Details.';
    final surface = watching
        ? roles.selectedSurface
        : current
        ? roles.elevatedSurface
        : roles.primarySurface;
    return LayoutBuilder(
      builder: (context, box) {
        final leftGap = visibleFractionStart == 0
            ? math.min(3.0, box.maxWidth / 4)
            : 0.0;
        final rightGap = visibleFractionEnd == 1
            ? math.min(3.0, box.maxWidth / 4)
            : 0.0;
        final cardWidth = box.maxWidth - leftGap - rightGap;
        return _HandheldGuideAction(
          label: '$title, channel ${channel.number}. $state',
          onTap: onTap,
          onLongPress: onDetails,
          child: Padding(
            padding: EdgeInsets.only(left: leftGap, right: rightGap),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (cardWidth >= 30)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
                        child: Row(
                          children: [
                            if (current &&
                                cardWidth >= 150 &&
                                posterPath(item) != null) ...[
                              AspectRatio(
                                aspectRatio: 2 / 3,
                                child: _HandheldProgramPoster(
                                  controller: controller,
                                  program: program,
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: LineupTypography.control.copyWith(
                                      fontSize: 17,
                                      color: roles.primaryText,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: LineupTypography.body.copyWith(
                                      fontSize: 15,
                                      color: roles.secondaryText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (current)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(
                          minHeight: 3,
                          value:
                              ((_elapsedFraction(program, now) -
                                          visibleFractionStart) /
                                      (visibleFractionEnd -
                                          visibleFractionStart))
                                  .clamp(0.0, 1.0),
                          color: roles.progressFill,
                          backgroundColor: Colors.transparent,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
