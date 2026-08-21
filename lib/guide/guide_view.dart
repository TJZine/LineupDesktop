import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channels/channel.dart';
import '../settings/lineup_settings.dart';
import '../ui/app_theme.dart';
import '../ui/app_ui.dart';
import 'guide_controller.dart';

class GuideLayoutPolicy {
  static const _comfortableGuideHeight = 900.0;

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
    final compact =
        size.width < LineupLayout.expandedNavigation ||
        size.height < _comfortableGuideHeight;
    final padding =
        size.width < LineupLayout.expandedNavigation || size.height < 720
        ? 12.0
        : 20.0;
    final minimumRows = size.height < 720
        ? 4
        : size.height < 1080
        ? 5
        : 7;
    final rowHeight =
        size.height < _comfortableGuideHeight || density == GuideDensity.compact
        ? 58.0
        : 78.0;
    final rowBudget =
        size.height -
        (padding * 2 + 48 + 10 + 8 + 38) -
        minimumRows * rowHeight;
    final availableShowcaseHeight = rowBudget.clamp(0.0, double.infinity);
    final targetPictureHeight = size.height < 720
        ? _lerp(236.25, 281.25, (size.height - 600) / 120)
        : size.height < _comfortableGuideHeight
        ? _lerp(281.25, 360, (size.height - 720) / 180)
        : size.height < 1080
        ? _lerp(360, 378, (size.height - _comfortableGuideHeight) / 180)
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
      showSecondaryMetadata: size.height >= _comfortableGuideHeight,
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
        key == LogicalKeyboardKey.keyP ||
        key == LogicalKeyboardKey.home) {
      widget.controller.playToNow();
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.select) {
      final selected = widget.controller.selectFocusedProgram();
      if (selected?.isCurrentAt(widget.controller.now) == true) {
        unawaited(widget.onTune(selected!.channelId));
      }
    } else if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.keyG ||
        key == LogicalKeyboardKey.f2) {
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
                  child: Column(
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
                  ),
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
                onTap: onOpenPlayer,
                child: InkWell(
                  excludeFromSemantics: true,
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
    void focusCurrentProgram() {
      final current = controller.currentProgram(channel.id);
      if (current != null) controller.focusProgram(current);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Semantics(
            container: true,
            button: true,
            label:
                'Channel ${channel.number}, ${channel.name}${tunedChannel ? ', now watching' : ''}',
            selected: selectedChannel,
            focused: focusedChannel,
            onTap: focusCurrentProgram,
            child: InkWell(
              excludeFromSemantics: true,
              onTap: focusCurrentProgram,
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
                        child: Icon(Icons.play_circle_fill, size: 17),
                      ),
                  ],
                ),
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

class _Details extends StatefulWidget {
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
  State<_Details> createState() => _DetailsState();
}

class _DetailsState extends State<_Details> {
  String? _artworkProgramId;
  Uint8List? _artwork;
  Color? _dynamicColor;
  int _artworkToken = 0;

  @override
  void dispose() {
    _artworkToken++;
    super.dispose();
  }

  void _ensureArtwork(GuideProgram? program) {
    if (program?.id == _artworkProgramId) return;
    _artworkProgramId = program?.id;
    _artwork = null;
    _dynamicColor = null;
    final token = ++_artworkToken;
    if (program == null) return;
    unawaited(_loadArtwork(program, token));
  }

  Future<void> _loadArtwork(GuideProgram program, int token) async {
    final artwork = await widget.controller.artworkFor(program);
    if (!mounted || token != _artworkToken) return;
    setState(() {
      _artwork = artwork;
      _dynamicColor = artwork == null ? null : _artworkHashColor(artwork);
    });
    if (artwork == null) return;
    final color = await _artworkColor(artwork);
    if (!mounted || token != _artworkToken || color == null) return;
    setState(() => _dynamicColor = color);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final program = controller.focusedProgram ?? controller.selectedProgram;
    _ensureArtwork(program);
    final channel = controller.channels
        .where((channel) => channel.id == program?.channelId)
        .firstOrNull;
    final tunedChannel = controller.channels
        .where((channel) => channel.id == controller.lineup.currentChannelId)
        .firstOrNull;
    final tunedProgram = tunedChannel == null
        ? null
        : controller.currentProgram(tunedChannel.id);
    final roles = LineupTheme.of(context);
    final dynamicColor = _dynamicColor ?? roles.progressFill;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: AnimatedContainer(
        key: const Key('guide-info-dynamic-background'),
        duration: controller.lineup.settings.reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              roles.primarySurface,
              Color.alphaBlend(
                dynamicColor.withValues(alpha: 0.36),
                roles.primarySurface,
              ),
              roles.primarySurface,
            ],
            stops: const [0, 0.72, 1],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_artwork != null)
              Positioned.fill(
                left: MediaQuery.sizeOf(context).width * 0.28,
                child: Opacity(
                  opacity: 0.12,
                  child: Image.memory(
                    _artwork!,
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 12 : 18,
                vertical: widget.compact ? 8 : 12,
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
                        color: roles.liveAccent,
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
                              widget.playbackMessage ??
                                  'Move to a program for details.',
                            ),
                          )
                        : _ProgramDetails(
                            program: program,
                            channel: channel,
                            artwork: _artwork,
                            showArtwork: widget.showArtwork,
                            showSecondaryMetadata: widget.showSecondaryMetadata,
                            artworkWidth: widget.artworkWidth,
                            playbackMessage: widget.playbackMessage,
                            now: controller.now,
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

class _ProgramDetails extends StatelessWidget {
  const _ProgramDetails({
    required this.program,
    required this.channel,
    required this.artwork,
    required this.showArtwork,
    required this.showSecondaryMetadata,
    required this.artworkWidth,
    required this.playbackMessage,
    required this.now,
  });

  final GuideProgram program;
  final Channel? channel;
  final Uint8List? artwork;
  final bool showArtwork;
  final bool showSecondaryMetadata;
  final double artworkWidth;
  final String? playbackMessage;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final item = program.scheduled.item;
    final episode = _episodeCode(item);
    final badges = _mediaBadges(item);
    return Row(
      children: [
        if (showArtwork)
          SizedBox(
            key: const Key('guide-focused-artwork'),
            width: artworkWidth,
            height: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: artwork == null
                  ? ColoredBox(
                      color: LineupTheme.of(context).primarySurface,
                      child: const Icon(Icons.movie_outlined, size: 34),
                    )
                  : Image.memory(
                      artwork!,
                      fit: BoxFit.cover,
                      cacheWidth: 360,
                      gaplessPlayback: true,
                      semanticLabel: 'Artwork for ${item.title}',
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined),
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
                  '${channel!.number} • ${channel!.name}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: LineupTheme.of(context).progressFill,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (item.showTitle != null)
                Text(
                  item.showTitle!.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              Text(
                item.title,
                maxLines: showSecondaryMetadata ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style:
                    (showSecondaryMetadata
                            ? Theme.of(context).textTheme.headlineSmall
                            : Theme.of(context).textTheme.titleLarge)
                        ?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                [
                  ?episode,
                  if (item.year != null) '${item.year}',
                  '${_time(context, program.scheduled.start)}–${_time(context, program.scheduled.end)}',
                  program.isCurrentAt(now)
                      ? 'Airing now'
                      : program.scheduled.end.isBefore(now)
                      ? 'Ended'
                      : 'Upcoming',
                ].join(' • '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (showSecondaryMetadata && item.genres.isNotEmpty)
                Text(
                  item.genres.take(3).join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (showSecondaryMetadata && badges.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Wrap(
                    key: const Key('guide-program-badges'),
                    spacing: 6,
                    runSpacing: 4,
                    children: [for (final badge in badges) _Badge(badge)],
                  ),
                ),
              if (showSecondaryMetadata && item.summary != null)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    item.summary!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              if (playbackMessage != null && showSecondaryMetadata)
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
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

String? _episodeCode(ChannelItem item) {
  final season = item.seasonNumber;
  final episode = item.episodeNumber;
  if (season == null && episode == null) return null;
  return 'S${(season ?? 0).toString().padLeft(2, '0')}E${(episode ?? 0).toString().padLeft(2, '0')}';
}

List<String> _mediaBadges(ChannelItem item) => [
  item.contentRating,
  item.resolution?.toUpperCase(),
  switch (item.dynamicRange) {
    'hdr10' => 'HDR10',
    'hlg' => 'HLG',
    'dolbyVision' => 'DOLBY VISION',
    _ => null,
  },
  item.videoCodec?.toUpperCase(),
  item.audioCodec?.toUpperCase(),
  if (item.audioChannels != null) '${item.audioChannels} CH',
].nonNulls.toList();

Future<Color?> _artworkColor(Uint8List bytes) async {
  ui.Codec? codec;
  ui.Image? image;
  try {
    codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 24,
      targetHeight: 24,
    );
    final frame = await codec.getNextFrame();
    image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return _artworkHashColor(bytes);
    var red = 0.0;
    var green = 0.0;
    var blue = 0.0;
    var total = 0.0;
    for (var offset = 0; offset < data.lengthInBytes; offset += 4) {
      final alpha = data.getUint8(offset + 3);
      if (alpha < 128) continue;
      final r = data.getUint8(offset);
      final g = data.getUint8(offset + 1);
      final b = data.getUint8(offset + 2);
      final range =
          [r, g, b].reduce((a, b) => a > b ? a : b) -
          [r, g, b].reduce((a, b) => a < b ? a : b);
      final weight = 1 + range / 128;
      red += r * weight;
      green += g * weight;
      blue += b * weight;
      total += weight;
    }
    if (total == 0) return _artworkHashColor(bytes);
    final sampled = Color.fromARGB(
      255,
      (red / total).round(),
      (green / total).round(),
      (blue / total).round(),
    );
    final hsl = HSLColor.fromColor(sampled);
    return hsl
        .withSaturation(hsl.saturation.clamp(0.35, 0.78))
        .withLightness(hsl.lightness.clamp(0.28, 0.52))
        .toColor();
  } catch (_) {
    return _artworkHashColor(bytes);
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}

Color _artworkHashColor(Uint8List bytes) {
  if (bytes.isEmpty) return const Color(0xFF455A64);
  var hash = 0x811c9dc5;
  final stride = (bytes.length ~/ 256).clamp(1, bytes.length);
  for (var index = 0; index < bytes.length; index += stride) {
    hash = ((hash ^ bytes[index]) * 0x01000193) & 0xffffffff;
  }
  return HSLColor.fromAHSL(
    1,
    (hash & 0xffff) * 360 / 0xffff,
    0.62,
    0.42,
  ).toColor();
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
