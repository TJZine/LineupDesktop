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
  });

  factory GuideLayoutPolicy.forSize(Size size, {required bool hasPicture}) {
    final compact = size.width < 1100 || size.height < 720;
    return GuideLayoutPolicy._(
      compact: compact,
      padding: compact ? 12 : 20,
      channelRailWidth: compact ? 156 : (size.width >= 1800 ? 232 : 196),
      showcaseHeight: hasPicture ? (compact ? 126 : 184) : (compact ? 92 : 142),
      pictureWidth: compact ? 214 : (size.width >= 1800 ? 340 : 286),
    );
  }

  final bool compact;
  final double padding;
  final double channelRailWidth;
  final double showcaseHeight;
  final double pictureWidth;
}

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
  late final ScrollController _scroll;
  Timer? _clockTimer;
  int _visibleRows = 8;
  bool _revealScheduled = false;
  String? _lastFocusedChannelId;

  double get _rowHeight =>
      widget.controller.density == GuideDensity.compact ? 58 : 78;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController(
      initialScrollOffset: widget.controller.verticalOffset,
    );
    _lastFocusedChannelId = widget.controller.focusedChannelId;
    widget.controller.addListener(_changed);
    _scroll.addListener(_requestViewport);
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
      ..removeListener(_requestViewport)
      ..dispose();
    super.dispose();
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
      if (!mounted || !_scroll.hasClients) return;
      final index = widget.controller.focusedChannelIndex;
      if (index < 0) return;
      final first = (_scroll.offset / _rowHeight).floor();
      if (index < first || index >= first + _visibleRows) {
        _scroll.animateTo(
          (index * _rowHeight).clamp(0, _scroll.position.maxScrollExtent),
          duration: widget.controller.lineup.settings.reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
      _requestViewport();
    });
  }

  void _requestViewport() {
    if (!mounted) return;
    final first = _scroll.hasClients
        ? (_scroll.offset / _rowHeight).floor()
        : 0;
    if (_scroll.hasClients) {
      widget.controller.rememberVerticalOffset(_scroll.offset);
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
        color: widget.overlayMode ? Colors.transparent : roles.deepBackground,
        child: LayoutBuilder(
          builder: (context, outer) {
            final policy = GuideLayoutPolicy.forSize(
              outer.biggest,
              hasPicture: widget.pictureInPicture != null,
            );
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: widget.overlayMode
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          roles.scrim.withValues(alpha: 0.82),
                          roles.scrim,
                        ],
                        stops: const [0, 0.28, 0.62],
                      )
                    : null,
              ),
              child: Padding(
                padding: EdgeInsets.all(policy.padding),
                child: Column(
                  children: [
                    _Toolbar(
                      controller: widget.controller,
                      onClose: widget.onClose,
                      onOpenMenu: widget.onOpenMenu,
                      compact: policy.compact,
                    ),
                    const SizedBox(height: 10),
                    if (channels.isEmpty)
                      const Expanded(child: _EmptyGuide())
                    else
                      Expanded(
                        child: Column(
                          children: [
                            SizedBox(
                              height: policy.showcaseHeight,
                              child: _GuideShowcase(
                                controller: widget.controller,
                                picture: widget.pictureInPicture,
                                pictureWidth: policy.pictureWidth,
                                compact: policy.compact,
                                playbackMessage: widget.playbackMessage,
                                onOpenPlayer: widget.onOpenPlayer,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _TimeHeader(
                              controller: widget.controller,
                              railWidth: policy.channelRailWidth,
                            ),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  _visibleRows = GuideGeometry.visibleRows(
                                    scrollOffset: _scroll.hasClients
                                        ? _scroll.offset
                                        : 0,
                                    viewportHeight: constraints.maxHeight,
                                    rowHeight: _rowHeight,
                                    totalRows: channels.length,
                                  ).count;
                                  WidgetsBinding.instance.addPostFrameCallback(
                                    (_) => _requestViewport(),
                                  );
                                  return ListView.builder(
                                    controller: _scroll,
                                    itemExtent: _rowHeight,
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
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
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
          if (libraryIds.isNotEmpty)
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
    required this.playbackMessage,
    required this.onOpenPlayer,
  });

  final GuideController controller;
  final Widget? picture;
  final double pictureWidth;
  final bool compact;
  final String? playbackMessage;
  final VoidCallback? onOpenPlayer;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (picture != null) ...[
        SizedBox(
          key: const Key('guide-picture-in-picture'),
          width: pictureWidth,
          child: Semantics(
            button: onOpenPlayer != null,
            label: 'Now playing picture in picture. Open full player.',
            child: InkWell(
              onTap: onOpenPlayer,
              borderRadius: BorderRadius.circular(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(aspectRatio: 16 / 9, child: picture),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
      ],
      Expanded(
        child: _Details(
          controller: controller,
          compact: compact,
          playbackMessage: playbackMessage,
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
    return SizedBox(
      height: 38,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slotWidth = (constraints.maxWidth - railWidth) / slots;
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
                    width: focusedChannel ? 2 : 1,
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
    return _ProgramCell(
      key: ValueKey(program.id),
      program: program,
      focused: program.id == controller.focusedProgramId,
      selected: program.id == controller.selectedProgramId,
      current: program.isCurrentAt(now),
      past: !program.scheduled.end.isAfter(now),
      progress: program.isCurrentAt(now)
          ? now.difference(program.scheduled.start).inMilliseconds /
                program.scheduled.end
                    .difference(program.scheduled.start)
                    .inMilliseconds
          : 0,
      left: rect.left,
      width: rect.width,
      onTap: () => controller.focusProgram(program),
      onDoubleTap: program.isCurrentAt(now)
          ? () {
              controller.selectProgram(program);
              unawaited(onTune(channel.id));
            }
          : null,
      reduceMotion: controller.lineup.settings.reduceMotion,
      largeFocus: controller.lineup.settings.largeFocusIndicators,
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
    required this.largeFocus,
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
  final bool largeFocus;
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
        button: widget.current,
        selected: widget.selected,
        focused: widget.focused,
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
                      ? (widget.largeFocus ? 5 : 3)
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
    required this.playbackMessage,
  });
  final GuideController controller;
  final bool compact;
  final String? playbackMessage;

  @override
  Widget build(BuildContext context) {
    final program = controller.focusedProgram ?? controller.selectedProgram;
    final channel = controller.channels
        .where((channel) => channel.id == program?.channelId)
        .firstOrNull;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 18,
          vertical: compact ? 8 : 12,
        ),
        child: program == null
            ? Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  playbackMessage ?? 'Move to a program for details.',
                ),
              )
            : Row(
                children: [
                  if (!compact)
                    SizedBox(
                      width: 112,
                      height: 86,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: FutureBuilder(
                          future: controller.artworkFor(program),
                          builder: (context, snapshot) => snapshot.data == null
                              ? ColoredBox(
                                  color: LineupTheme.of(context).primarySurface,
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
                                  errorBuilder: (_, _, _) =>
                                      const Icon(Icons.broken_image_outlined),
                                ),
                        ),
                      ),
                    ),
                  if (!compact) const SizedBox(width: 14),
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
                                  color: LineupTheme.of(context).progressFill,
                                ),
                          ),
                        Text(
                          program.scheduled.item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          [
                            program.scheduled.item.showTitle,
                            '${_time(context, program.scheduled.start)}–${_time(context, program.scheduled.end)}',
                            program.isCurrentAt(controller.now)
                                ? 'Airing now'
                                : program.scheduled.end.isBefore(controller.now)
                                ? 'Ended'
                                : 'Upcoming',
                          ].nonNulls.join(' • '),
                          maxLines: compact ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (playbackMessage != null && !compact)
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
