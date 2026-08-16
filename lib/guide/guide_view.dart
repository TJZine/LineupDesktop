import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channels/channel.dart';
import '../settings/lineup_settings.dart';
import '../ui/app_theme.dart';
import 'guide_controller.dart';

class GuideLayoutPolicy {
  const GuideLayoutPolicy._({
    required this.compact,
    required this.padding,
    required this.channelRailWidth,
    required this.showcaseHeight,
    required this.pictureWidth,
    required this.rowHeight,
    required this.minimumRows,
    required this.showSecondaryMetadata,
    required this.artworkWidth,
  });

  factory GuideLayoutPolicy.forSize(
    Size size, {
    required bool hasPicture,
    bool overlayMode = false,
    GuideDensity density = GuideDensity.comfortable,
  }) {
    final compact = size.width < 1100 || size.height < 900;
    final padding = size.width < 1100 || size.height < 720 ? 12.0 : 20.0;
    final minimumRows = size.height < 720
        ? 4
        : size.height < 1080
        ? 5
        : 7;
    final rowHeight = size.height < 900 || density == GuideDensity.compact
        ? 58.0
        : 78.0;
    final rowBudget =
        size.height -
        (padding * 2 + 48 + 10 + 8 + 38) -
        minimumRows * rowHeight;
    final availableShowcaseHeight = rowBudget.clamp(0.0, double.infinity);
    final targetPictureHeight = size.height < 720
        ? _lerp(236.25, 281.25, (size.height - 600) / 120)
        : size.height < 900
        ? _lerp(281.25, 360, (size.height - 720) / 180)
        : size.height < 1080
        ? _lerp(360, 378, (size.height - 900) / 180)
        : 378.0;
    final richShowcase = hasPicture || overlayMode;
    var showcaseHeight = richShowcase
        ? targetPictureHeight.clamp(0.0, availableShowcaseHeight)
        : (compact ? 126.0 : 142.0).clamp(0.0, availableShowcaseHeight);
    var pictureWidth = showcaseHeight * 16 / 9;
    if (hasPicture) {
      final minimumDetailsWidth = compact ? 300.0 : 360.0;
      final widthBudget = size.width - padding * 2 - 12 - minimumDetailsWidth;
      pictureWidth = pictureWidth.clamp(0.0, widthBudget.clamp(0.0, 672.0));
      showcaseHeight = pictureWidth * 9 / 16;
    }
    return GuideLayoutPolicy._(
      compact: compact,
      padding: padding,
      channelRailWidth: compact ? 156 : (size.width >= 1800 ? 232 : 196),
      showcaseHeight: showcaseHeight,
      pictureWidth: pictureWidth,
      rowHeight: rowHeight,
      minimumRows: minimumRows,
      showSecondaryMetadata: size.height >= 900,
      artworkWidth: (showcaseHeight * 0.62).clamp(132.0, 224.0),
    );
  }

  final bool compact;
  final double padding;
  final double channelRailWidth;
  final double showcaseHeight;
  final double pictureWidth;
  final double rowHeight;
  final int minimumRows;
  final bool showSecondaryMetadata;
  final double artworkWidth;
}

double _lerp(double start, double end, double t) =>
    start + (end - start) * t.clamp(0.0, 1.0);

class GuideView extends StatefulWidget {
  const GuideView({
    required this.controller,
    required this.onClose,
    required this.onTune,
    this.onOpenMenu,
    this.overlayMode = false,
    this.pictureInPicture,
    this.onOpenPlayer,
    this.playbackMessage,
    this.focusNode,
    super.key,
  });

  final GuideController controller;
  final VoidCallback onClose;
  final Future<void> Function(String channelId) onTune;
  final VoidCallback? onOpenMenu;
  final bool overlayMode;
  final Widget? pictureInPicture;
  final VoidCallback? onOpenPlayer;
  final String? playbackMessage;
  final FocusNode? focusNode;

  @override
  State<GuideView> createState() => _GuideViewState();
}

class _GuideViewState extends State<GuideView> {
  ScrollController? _scroll;
  Timer? _clockTimer;
  int _visibleRows = 8;
  double? _effectiveRowHeight;
  bool _rowHeightAdjustmentScheduled = false;
  bool _revealScheduled = false;
  String? _lastFocusedChannelId;

  @override
  void initState() {
    super.initState();
    _lastFocusedChannelId = widget.controller.focusedChannelId;
    widget.controller.addListener(_changed);
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestViewport());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _clockTimer?.cancel();
    _scroll
      ?..removeListener(_requestViewport)
      ..dispose();
    super.dispose();
  }

  ScrollController _scrollFor(double rowHeight) {
    final existing = _scroll;
    if (existing == null) {
      _effectiveRowHeight = rowHeight;
      final created = ScrollController(
        initialScrollOffset: widget.controller.verticalOffsetFor(rowHeight),
      )..addListener(_requestViewport);
      _scroll = created;
      return created;
    }

    final previousRowHeight = _effectiveRowHeight;
    if (previousRowHeight == null || previousRowHeight == rowHeight) {
      _effectiveRowHeight = rowHeight;
      return existing;
    }

    if (!_rowHeightAdjustmentScheduled && existing.hasClients) {
      widget.controller.rememberVerticalOffset(
        existing.offset,
        previousRowHeight,
      );
    }
    _effectiveRowHeight = rowHeight;
    if (!_rowHeightAdjustmentScheduled) {
      _rowHeightAdjustmentScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _rowHeightAdjustmentScheduled = false;
        final currentRowHeight = _effectiveRowHeight;
        if (!mounted || currentRowHeight == null || !existing.hasClients) {
          return;
        }
        existing.jumpTo(
          widget.controller
              .verticalOffsetFor(currentRowHeight)
              .clamp(0.0, existing.position.maxScrollExtent),
        );
        _requestViewport();
      });
    }
    return existing;
  }

  void _changed() {
    if (!mounted) return;
    final focusedChannelId = widget.controller.focusedChannelId;
    final revealFocus = focusedChannelId != _lastFocusedChannelId;
    _lastFocusedChannelId = focusedChannelId;
    setState(() {});
    if (!revealFocus) return;
    if (_revealScheduled) return;
    _revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealScheduled = false;
      final scroll = _scroll;
      final rowHeight = _effectiveRowHeight;
      if (!mounted ||
          scroll == null ||
          !scroll.hasClients ||
          rowHeight == null) {
        return;
      }
      final index = widget.controller.focusedChannelIndex;
      if (index < 0) return;
      final first = (scroll.offset / rowHeight).floor();
      if (index < first || index >= first + _visibleRows) {
        final target = (index * rowHeight).clamp(
          0.0,
          scroll.position.maxScrollExtent,
        );
        if (widget.controller.lineup.settings.reduceMotion) {
          scroll.jumpTo(target);
        } else {
          scroll.animateTo(
            target,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
          );
        }
      }
      _requestViewport();
    });
  }

  void _requestViewport() {
    final scroll = _scroll;
    final rowHeight = _effectiveRowHeight;
    if (!mounted ||
        scroll == null ||
        rowHeight == null ||
        _rowHeightAdjustmentScheduled) {
      return;
    }
    final first = scroll.hasClients ? (scroll.offset / rowHeight).floor() : 0;
    if (scroll.hasClients) {
      widget.controller.rememberVerticalOffset(scroll.offset, rowHeight);
    }
    widget.controller.requestViewport(first, _visibleRows);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      widget.controller.moveVertical(-1);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      widget.controller.moveVertical(1);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      widget.controller.moveHorizontal(-1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      widget.controller.moveHorizontal(1);
    } else if (key == LogicalKeyboardKey.pageUp) {
      widget.controller.page(-1, _visibleRows);
    } else if (key == LogicalKeyboardKey.pageDown) {
      widget.controller.page(1, _visibleRows);
    } else if (key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.keyP) {
      widget.controller.playToNow();
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.select) {
      final selected = widget.controller.selectFocusedProgram();
      if (selected?.isCurrentAt(widget.controller.now) == true) {
        unawaited(widget.onTune(selected!.channelId));
      }
    } else if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.keyG) {
      widget.onClose();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Widget _toolbar(GuideLayoutPolicy policy) => _Toolbar(
    controller: widget.controller,
    onClose: widget.onClose,
    onOpenMenu: widget.onOpenMenu,
    compact: policy.compact,
  );

  Widget _showcase(GuideLayoutPolicy policy) => SizedBox(
    height: policy.showcaseHeight,
    child: _GuideShowcase(
      controller: widget.controller,
      picture: widget.pictureInPicture,
      pictureWidth: policy.pictureWidth,
      compact: policy.compact,
      overlayMode: widget.overlayMode,
      showSecondaryMetadata: policy.showSecondaryMetadata,
      artworkWidth: policy.artworkWidth,
      playbackMessage: widget.playbackMessage,
      onOpenPlayer: widget.onOpenPlayer,
    ),
  );

  Widget _schedule(GuideLayoutPolicy policy, List<Channel> channels) {
    final scroll = _scrollFor(policy.rowHeight);
    return Column(
      children: [
        _TimeHeader(
          controller: widget.controller,
          railWidth: policy.channelRailWidth,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _visibleRows = GuideGeometry.visibleRows(
                scrollOffset: scroll.hasClients ? scroll.offset : 0,
                viewportHeight: constraints.maxHeight,
                rowHeight: policy.rowHeight,
                totalRows: channels.length,
              ).count;
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _requestViewport(),
              );
              return ListView.builder(
                key: const Key('guide-schedule-list'),
                controller: scroll,
                itemExtent: policy.rowHeight,
                itemCount: channels.length,
                itemBuilder: (context, index) => _GuideRow(
                  channel: channels[index],
                  controller: widget.controller,
                  railWidth: policy.channelRailWidth,
                  onTune: widget.onTune,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final channels = widget.controller.channels;
    final roles = LineupTheme.of(context);
    return Focus(
      focusNode: widget.focusNode,
      autofocus: true,
      onKeyEvent: _key,
      child: Material(
        key: Key(widget.overlayMode ? 'overlay-guide' : 'classic-guide'),
        color: Colors.transparent,
        child: LayoutBuilder(
          builder: (context, outer) {
            final policy = GuideLayoutPolicy.forSize(
              outer.biggest,
              hasPicture: widget.pictureInPicture != null,
              overlayMode: widget.overlayMode,
              density: widget.controller.density,
            );
            final schedule = channels.isEmpty
                ? const _EmptyGuide()
                : _schedule(policy, channels);
            final content = Column(
              children: [
                _toolbar(policy),
                const SizedBox(height: 10),
                if (channels.isEmpty)
                  Expanded(child: schedule)
                else
                  Expanded(
                    child: Column(
                      children: [
                        _showcase(policy),
                        const SizedBox(height: 8),
                        Expanded(child: schedule),
                      ],
                    ),
                  ),
              ],
            );
            if (widget.overlayMode) {
              return DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      roles.scrim.withValues(alpha: 0.36),
                      roles.scrim.withValues(alpha: 0.82),
                      roles.scrim,
                    ],
                    stops: const [0, 0.28, 0.62],
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.all(policy.padding),
                  child: content,
                ),
              );
            }
            return _ClassicGuideSurface(
              color: roles.deepBackground,
              padding: policy.padding,
              showcaseHeight: policy.showcaseHeight,
              toolbar: _toolbar(policy),
              showcase: channels.isEmpty ? null : _showcase(policy),
              body: schedule,
            );
          },
        ),
      ),
    );
  }
}

class _ClassicGuideSurface extends StatelessWidget {
  const _ClassicGuideSurface({
    required this.color,
    required this.padding,
    required this.showcaseHeight,
    required this.toolbar,
    required this.showcase,
    required this.body,
  });

  final Color color;
  final double padding;
  final double showcaseHeight;
  final Widget toolbar;
  final Widget? showcase;
  final Widget body;

  // Overlap opaque neighbors across fractional 16:9 edges so rasterization
  // cannot leave an alpha seam outside the PlayerSurface aperture.
  static const _paintOverlap = 2.0;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ColoredBox(
        color: color,
        child: Padding(
          padding: EdgeInsets.fromLTRB(padding, padding, padding, 0),
          child: toolbar,
        ),
      ),
      ColoredBox(
        color: color,
        child: const SizedBox(width: double.infinity, height: 10),
      ),
      if (showcase != null)
        SizedBox(
          height: showcaseHeight,
          child: OverflowBox(
            alignment: Alignment.center,
            minHeight: showcaseHeight + _paintOverlap,
            maxHeight: showcaseHeight + _paintOverlap,
            child: SizedBox(
              height: showcaseHeight + _paintOverlap,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ColoredBox(
                    color: color,
                    child: SizedBox(width: padding),
                  ),
                  Expanded(child: showcase!),
                  ColoredBox(
                    color: color,
                    child: SizedBox(width: padding),
                  ),
                ],
              ),
            ),
          ),
        ),
      Expanded(
        child: ColoredBox(
          color: color,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              padding,
              showcase == null ? 0 : 8,
              padding,
              padding,
            ),
            child: body,
          ),
        ),
      ),
    ],
  );
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.onClose,
    required this.onOpenMenu,
    required this.compact,
  });
  final GuideController controller;
  final VoidCallback onClose;
  final VoidCallback? onOpenMenu;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final libraryIds = controller.availableLibraryIds.toList()..sort();
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Image.asset('assets/branding/lineup-logo-mark.png', height: 26),
          const SizedBox(width: 9),
          Text('LINEUP', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(width: 10),
          Text('Guide', style: Theme.of(context).textTheme.labelLarge),
          if (!compact) ...[
            const SizedBox(width: 16),
            Text('${controller.channels.length} channels'),
          ],
          const Spacer(),
          if (controller.lineup.settings.libraryTabsEnabled &&
              libraryIds.isNotEmpty)
            DropdownButton<String?>(
              value: controller.libraryFilterId,
              hint: const Text('All libraries'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All libraries'),
                ),
                for (final id in libraryIds)
                  DropdownMenuItem(
                    value: id,
                    child: Text(_libraryName(controller, id)),
                  ),
              ],
              onChanged: controller.setLibraryFilter,
            ),
          const SizedBox(width: 8),
          if (onOpenMenu != null)
            IconButton(
              key: const Key('guide-app-menu'),
              tooltip: 'Open Lineup menu',
              onPressed: onOpenMenu,
              icon: const Icon(Icons.menu),
            ),
          TextButton.icon(
            onPressed: controller.playToNow,
            icon: const Icon(Icons.adjust),
            label: Text(compact ? 'Now' : 'Jump to now'),
          ),
          IconButton(
            tooltip: 'Close Guide',
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _GuideShowcase extends StatelessWidget {
  const _GuideShowcase({
    required this.controller,
    required this.picture,
    required this.pictureWidth,
    required this.compact,
    required this.overlayMode,
    required this.showSecondaryMetadata,
    required this.artworkWidth,
    required this.playbackMessage,
    required this.onOpenPlayer,
  });

  final GuideController controller;
  final Widget? picture;
  final double pictureWidth;
  final bool compact;
  final bool overlayMode;
  final bool showSecondaryMetadata;
  final double artworkWidth;
  final String? playbackMessage;
  final VoidCallback? onOpenPlayer;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (picture != null) ...[
        SizedBox(
          width: pictureWidth,
          child: Align(
            child: AspectRatio(
              key: const Key('guide-picture-in-picture'),
              aspectRatio: 16 / 9,
              child: Semantics(
                button: onOpenPlayer != null,
                label: 'Now playing picture in picture. Open full player.',
                child: InkWell(
                  onTap: onOpenPlayer,
                  borderRadius: BorderRadius.circular(12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: picture,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (overlayMode)
          const SizedBox(width: 12)
        else
          ColoredBox(
            color: LineupTheme.of(context).deepBackground,
            child: const SizedBox(width: 12),
          ),
      ],
      Expanded(
        child: ColoredBox(
          color: overlayMode
              ? Colors.transparent
              : LineupTheme.of(context).deepBackground,
          child: _Details(
            controller: controller,
            compact: compact,
            showArtwork: overlayMode,
            showSecondaryMetadata: showSecondaryMetadata,
            artworkWidth: artworkWidth,
            playbackMessage: playbackMessage,
          ),
        ),
      ),
    ],
  );
}

class _TimeHeader extends StatelessWidget {
  const _TimeHeader({required this.controller, required this.railWidth});
  final GuideController controller;
  final double railWidth;

  @override
  Widget build(BuildContext context) {
    final slots = controller.guideHours * 2;
    if (slots <= 0) return const SizedBox(height: 38);
    return SizedBox(
      height: 38,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final timelineWidth = constraints.maxWidth - railWidth;
          if (timelineWidth <= 0) return const SizedBox.shrink();
          final slotWidth = timelineWidth / slots;
          final stride = (68 / slotWidth).ceil().clamp(1, slots);
          return Row(
            children: [
              SizedBox(
                width: railWidth,
                child: const Padding(
                  padding: EdgeInsets.only(left: 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('CHANNEL'),
                  ),
                ),
              ),
              for (var index = 0; index < slots; index++)
                Expanded(
                  child: index % stride == 0
                      ? Text(
                          _time(
                            context,
                            controller.windowStart.add(
                              Duration(minutes: 30 * index),
                            ),
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.clip,
                          maxLines: 1,
                          style: Theme.of(context).textTheme.labelMedium,
                        )
                      : const SizedBox.shrink(),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _GuideRow extends StatelessWidget {
  const _GuideRow({
    required this.channel,
    required this.controller,
    required this.railWidth,
    required this.onTune,
  });
  final Channel channel;
  final GuideController controller;
  final double railWidth;
  final Future<void> Function(String channelId) onTune;

  @override
  Widget build(BuildContext context) {
    final focusedChannel = channel.id == controller.focusedChannelId;
    final selectedChannel = channel.id == controller.selectedChannelId;
    final tunedChannel = controller.lineup.currentChannelId == channel.id;
    final data = controller.row(channel.id);
    return Semantics(
      container: true,
      label:
          'Channel ${channel.number}, ${channel.name}${tunedChannel ? ', now watching' : ''}',
      selected: selectedChannel,
      focused: focusedChannel,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            InkWell(
              onTap: () {
                final current = controller.currentProgram(channel.id);
                if (current != null) controller.focusProgram(current);
              },
              child: AnimatedContainer(
                duration: controller.lineup.settings.reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 90),
                width: railWidth,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: tunedChannel
                      ? LineupTheme.of(context).tunedSurface
                      : selectedChannel
                      ? LineupTheme.of(context).selectedSurface
                      : LineupTheme.of(context).primarySurface,
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(LineupTheme.of(context).panelRadius),
                  ),
                  border: Border.all(
                    color: focusedChannel
                        ? LineupTheme.of(context).focusBorder
                        : Colors.transparent,
                    width: focusedChannel
                        ? LineupTheme.of(context).focusBorderWidth
                        : 1,
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: railWidth < 180 ? 40 : 48,
                      child: Text(
                        '${channel.number}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        channel.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (tunedChannel)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(
                          Icons.play_circle_fill,
                          size: 17,
                          semanticLabel: 'Now watching',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _Programs(
                channel: channel,
                data: data,
                controller: controller,
                onTune: onTune,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Programs extends StatelessWidget {
  const _Programs({
    required this.channel,
    required this.data,
    required this.controller,
    required this.onTune,
  });
  final Channel channel;
  final GuideRowData data;
  final GuideController controller;
  final Future<void> Function(String channelId) onTune;

  @override
  Widget build(BuildContext context) {
    if (data.state == GuideLoadState.loading) {
      return Semantics(
        label: 'Schedule loading',
        liveRegion: true,
        child: const LinearProgressIndicator(minHeight: 2),
      );
    }
    if (data.state == GuideLoadState.error) {
      return Semantics(
        label: 'Schedule failed to load',
        button: true,
        child: InkWell(
          onTap: () => controller.retry(channel.id),
          child: const Center(
            child: Text('Schedule unavailable — select to retry'),
          ),
        ),
      );
    }
    if (data.programs.isEmpty) {
      return const Center(child: Text('No programs in this range'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final now = controller.now;
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              for (final program in data.programs)
                _programCell(program, constraints.maxWidth, now),
              if (!now.isBefore(controller.windowStart) &&
                  now.isBefore(controller.windowEnd))
                Positioned(
                  left: GuideGeometry.programRect(
                    windowStart: controller.windowStart,
                    windowEnd: controller.windowEnd,
                    programStart: now,
                    programEnd: now,
                    viewportWidth: constraints.maxWidth,
                  ).left,
                  top: 0,
                  bottom: 0,
                  child: Semantics(
                    label: 'Current time',
                    child: Container(
                      width: 2,
                      color: LineupTheme.of(context).liveAccent,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _programCell(
    GuideProgram program,
    double viewportWidth,
    DateTime now,
  ) {
    final rect = GuideGeometry.programRect(
      windowStart: controller.windowStart,
      windowEnd: controller.windowEnd,
      programStart: program.scheduled.start,
      programEnd: program.scheduled.end,
      viewportWidth: viewportWidth,
    );
    final current = program.isCurrentAt(now);
    final totalMicroseconds = program.scheduled.end
        .difference(program.scheduled.start)
        .inMicroseconds;
    return _ProgramCell(
      key: ValueKey(program.id),
      program: program,
      focused: program.id == controller.focusedProgramId,
      selected: program.id == controller.selectedProgramId,
      current: current,
      past: !program.scheduled.end.isAfter(now),
      progress: current && totalMicroseconds > 0
          ? now.difference(program.scheduled.start).inMicroseconds /
                totalMicroseconds
          : 0,
      left: rect.left,
      width: rect.width,
      onTap: () => controller.focusProgram(program),
      onDoubleTap: current
          ? () {
              controller.selectProgram(program);
              unawaited(onTune(channel.id));
            }
          : null,
      reduceMotion: controller.lineup.settings.reduceMotion,
    );
  }
}

class _ProgramCell extends StatefulWidget {
  const _ProgramCell({
    required this.program,
    required this.focused,
    required this.selected,
    required this.current,
    required this.past,
    required this.progress,
    required this.left,
    required this.width,
    required this.onTap,
    required this.reduceMotion,
    this.onDoubleTap,
    super.key,
  });
  final GuideProgram program;
  final bool focused;
  final bool selected;
  final bool current;
  final bool past;
  final double progress;
  final double left;
  final double width;
  final VoidCallback onTap;
  final bool reduceMotion;
  final VoidCallback? onDoubleTap;

  @override
  State<_ProgramCell> createState() => _ProgramCellState();
}

class _ProgramCellState extends State<_ProgramCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => Positioned(
    left: widget.left,
    width: widget.width.clamp(28, 2000),
    top: 0,
    bottom: 0,
    child: Padding(
      padding: const EdgeInsets.only(right: 3),
      child: Semantics(
        button: true,
        selected: widget.selected,
        focused: widget.focused,
        onTap: widget.onTap,
        label:
            '${widget.program.scheduled.item.title}, ${_time(context, widget.program.scheduled.start)} to ${_time(context, widget.program.scheduled.end)}${widget.current
                ? ', currently airing'
                : widget.past
                ? ', ended'
                : ', upcoming'}',
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: InkWell(
            excludeFromSemantics: true,
            onTap: widget.onTap,
            onDoubleTap: widget.onDoubleTap,
            child: AnimatedContainer(
              duration: widget.reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 90),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: widget.current
                    ? LineupTheme.of(context).tunedSurface
                    : widget.past
                    ? LineupTheme.of(context).primarySurface
                          .withValues(alpha: 0.56)
                    : widget.selected
                    ? LineupTheme.of(context).selectedSurface
                    : _hovered
                    ? LineupTheme.of(context).elevatedSurface
                    : LineupTheme.of(context).primarySurface,
                borderRadius: BorderRadius.circular(
                  LineupTheme.of(context).panelRadius,
                ),
                border: Border.all(
                  color: widget.focused
                      ? LineupTheme.of(context).focusBorder
                      : widget.selected
                      ? LineupTheme.of(context).defaultBorder
                      : LineupTheme.of(context).subtleBorder,
                  width: widget.focused
                      ? LineupTheme.of(context).focusBorderWidth
                      : widget.selected
                      ? 2
                      : 1,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.current)
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: widget.progress.clamp(0, 1),
                      child: ColoredBox(
                        color: LineupTheme.of(context).selectedSurface,
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.program.scheduled.item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.past
                            ? LineupTheme.of(context).mutedText
                            : null,
                        fontWeight: widget.focused
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _Details extends StatelessWidget {
  const _Details({
    required this.controller,
    required this.compact,
    required this.showArtwork,
    required this.showSecondaryMetadata,
    required this.artworkWidth,
    required this.playbackMessage,
  });
  final GuideController controller;
  final bool compact;
  final bool showArtwork;
  final bool showSecondaryMetadata;
  final double artworkWidth;
  final String? playbackMessage;

  @override
  Widget build(BuildContext context) {
    final program = controller.focusedProgram ?? controller.selectedProgram;
    final channel = controller.channels
        .where((channel) => channel.id == program?.channelId)
        .firstOrNull;
    final tunedChannel = controller.channels
        .where((channel) => channel.id == controller.lineup.currentChannelId)
        .firstOrNull;
    final tunedProgram = tunedChannel == null
        ? null
        : controller.currentProgram(tunedChannel.id);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 18,
          vertical: compact ? 8 : 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (tunedChannel != null &&
                controller.lineup.settings.nowWatchingBanner) ...[
              Text(
                key: const Key('guide-now-playing-context'),
                'NOW PLAYING  •  ${tunedChannel.number} ${tunedChannel.name}  •  ${tunedProgram?.scheduled.item.title ?? 'Schedule loading…'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: LineupTheme.of(context).liveAccent,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Expanded(
              child: program == null
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        playbackMessage ?? 'Move to a program for details.',
                      ),
                    )
                  : Row(
                      children: [
                        if (showArtwork)
                          SizedBox(
                            key: const Key('guide-focused-artwork'),
                            width: artworkWidth,
                            height: double.infinity,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: FutureBuilder(
                                future: controller.artworkFor(program),
                                builder: (context, snapshot) =>
                                    snapshot.data == null
                                    ? ColoredBox(
                                        color: LineupTheme.of(context)
                                            .primarySurface,
                                        child: const Icon(
                                          Icons.movie_outlined,
                                          size: 34,
                                        ),
                                      )
                                    : Image.memory(
                                        snapshot.data!,
                                        fit: BoxFit.cover,
                                        cacheWidth: 360,
                                        semanticLabel:
                                            'Artwork for ${program.scheduled.item.title}',
                                        errorBuilder: (_, _, _) => const Icon(
                                          Icons.broken_image_outlined,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        if (showArtwork) const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (channel != null)
                                Text(
                                  '${channel.number} • ${channel.name}',
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(
                                        color: LineupTheme.of(context)
                                            .progressFill,
                                      ),
                                ),
                              Text(
                                program.scheduled.item.title,
                                maxLines: showSecondaryMetadata ? 2 : 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    (showSecondaryMetadata
                                            ? Theme.of(context)
                                                  .textTheme
                                                  .headlineSmall
                                            : Theme.of(context)
                                                  .textTheme
                                                  .titleLarge)
                                        ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              Text(
                                [
                                  program.scheduled.item.showTitle,
                                  '${_time(context, program.scheduled.start)}–${_time(context, program.scheduled.end)}',
                                  program.isCurrentAt(controller.now)
                                      ? 'Airing now'
                                      : program.scheduled.end.isBefore(
                                          controller.now,
                                        )
                                      ? 'Ended'
                                      : 'Upcoming',
                                ].nonNulls.join(' • '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (playbackMessage != null &&
                                  showSecondaryMetadata)
                                Text(
                                  playbackMessage!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyGuide extends StatelessWidget {
  const _EmptyGuide();
  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      label: 'Guide has no channels',
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.live_tv_outlined, size: 52),
          SizedBox(height: 16),
          Text('Create a channel to build your Guide'),
        ],
      ),
    ),
  );
}

String _time(BuildContext context, DateTime value) => MaterialLocalizations.of(
  context,
).formatTimeOfDay(TimeOfDay.fromDateTime(value), alwaysUse24HourFormat: false);

String _libraryName(GuideController controller, String id) =>
    controller.lineup.libraries
        .where((library) => library.id == id)
        .map((library) => library.title)
        .firstOrNull ??
    id;
