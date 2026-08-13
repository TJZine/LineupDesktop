import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channels/channel.dart';
import '../settings/lineup_settings.dart';
import '../ui/app_theme.dart';
import 'guide_controller.dart';

class GuideView extends StatefulWidget {
  const GuideView({
    required this.controller,
    required this.onClose,
    required this.onTune,
    super.key,
  });

  final GuideController controller;
  final VoidCallback onClose;
  final Future<void> Function(String channelId) onTune;

  @override
  State<GuideView> createState() => _GuideViewState();
}

class _GuideViewState extends State<GuideView> {
  final _scroll = ScrollController();
  Timer? _clockTimer;
  int _visibleRows = 8;
  bool _revealScheduled = false;

  double get _rowHeight =>
      widget.controller.density == GuideDensity.compact ? 58 : 78;

  @override
  void initState() {
    super.initState();
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
    setState(() {});
    if (_revealScheduled) return;
    _revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealScheduled = false;
      if (!mounted || !_scroll.hasClients) return;
      final index = widget.controller.selectedChannelIndex;
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
      final selected = widget.controller.selectedProgram;
      if (selected?.isCurrentAt(DateTime.now()) == true) {
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
    return Focus(
      autofocus: true,
      onKeyEvent: _key,
      child: Material(
        color: LineupTheme.obsidian.withValues(alpha: 0.97),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
            child: Column(
              children: [
                _Toolbar(
                  controller: widget.controller,
                  onClose: widget.onClose,
                ),
                const SizedBox(height: 12),
                if (channels.isEmpty)
                  const Expanded(child: _EmptyGuide())
                else
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        _visibleRows = (constraints.maxHeight / _rowHeight)
                            .ceil()
                            .clamp(1, channels.length);
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _requestViewport(),
                        );
                        return Column(
                          children: [
                            _TimeHeader(controller: widget.controller),
                            Expanded(
                              child: ListView.builder(
                                controller: _scroll,
                                itemExtent: _rowHeight,
                                itemCount: channels.length,
                                itemBuilder: (context, index) => _GuideRow(
                                  channel: channels[index],
                                  controller: widget.controller,
                                  onTune: widget.onTune,
                                ),
                              ),
                            ),
                            _Details(controller: widget.controller),
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller, required this.onClose});
  final GuideController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final libraryIds = controller.availableLibraryIds.toList()..sort();
    return Row(
      children: [
        Text('Guide', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(width: 20),
        Text('${controller.channels.length} channels'),
        const Spacer(),
        if (libraryIds.isNotEmpty)
          DropdownButton<String?>(
            value: controller.libraryFilterId,
            hint: const Text('All libraries'),
            items: [
              const DropdownMenuItem(value: null, child: Text('All libraries')),
              for (final id in libraryIds)
                DropdownMenuItem(
                  value: id,
                  child: Text(_libraryName(controller, id)),
                ),
            ],
            onChanged: controller.setLibraryFilter,
          ),
        const SizedBox(width: 12),
        TextButton.icon(
          onPressed: controller.playToNow,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Play to now'),
        ),
        IconButton(
          tooltip: 'Close Guide',
          onPressed: onClose,
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

class _TimeHeader extends StatelessWidget {
  const _TimeHeader({required this.controller});
  final GuideController controller;

  @override
  Widget build(BuildContext context) {
    final slots = controller.guideHours * 2;
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          const SizedBox(
            width: 210,
            child: Padding(
              padding: EdgeInsets.only(left: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('CHANNEL'),
              ),
            ),
          ),
          for (var index = 0; index < slots; index++)
            Expanded(
              child: Text(
                _time(
                  context,
                  controller.windowStart.add(Duration(minutes: 30 * index)),
                ),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
        ],
      ),
    );
  }
}

class _GuideRow extends StatelessWidget {
  const _GuideRow({
    required this.channel,
    required this.controller,
    required this.onTune,
  });
  final Channel channel;
  final GuideController controller;
  final Future<void> Function(String channelId) onTune;

  @override
  Widget build(BuildContext context) {
    final selectedChannel = channel.id == controller.selectedChannelId;
    final data = controller.row(channel.id);
    return Semantics(
      container: true,
      label: 'Channel ${channel.number}, ${channel.name}',
      selected: selectedChannel,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            InkWell(
              onTap: () {
                final current = controller.currentProgram(channel.id);
                if (current != null) controller.selectProgram(current);
              },
              child: Container(
                width: 210,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: selectedChannel
                      ? LineupTheme.brass.withValues(alpha: 0.2)
                      : LineupTheme.smoke,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(8),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
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
                    if (controller.lineup.currentChannelId == channel.id)
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
        child: LinearProgressIndicator(minHeight: 2),
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
        final totalMs = controller.windowEnd
            .difference(controller.windowStart)
            .inMilliseconds;
        final now = DateTime.now();
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              for (final program in data.programs)
                _ProgramCell(
                  program: program,
                  selected: program.id == controller.selectedProgramId,
                  current: program.isCurrentAt(now),
                  left:
                      constraints.maxWidth *
                      program.scheduled.start
                          .difference(controller.windowStart)
                          .inMilliseconds /
                      totalMs,
                  width:
                      constraints.maxWidth *
                      program.scheduled.end
                          .difference(program.scheduled.start)
                          .inMilliseconds /
                      totalMs,
                  onTap: () => controller.selectProgram(program),
                  onDoubleTap: program.isCurrentAt(now)
                      ? () => onTune(channel.id)
                      : null,
                  reduceMotion: controller.lineup.settings.reduceMotion,
                  largeFocus: controller.lineup.settings.largeFocusIndicators,
                ),
              if (!now.isBefore(controller.windowStart) &&
                  now.isBefore(controller.windowEnd))
                Positioned(
                  left:
                      constraints.maxWidth *
                      now.difference(controller.windowStart).inMilliseconds /
                      totalMs,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2, color: Colors.redAccent),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ProgramCell extends StatelessWidget {
  const _ProgramCell({
    required this.program,
    required this.selected,
    required this.current,
    required this.left,
    required this.width,
    required this.onTap,
    required this.reduceMotion,
    required this.largeFocus,
    this.onDoubleTap,
  });
  final GuideProgram program;
  final bool selected;
  final bool current;
  final double left;
  final double width;
  final VoidCallback onTap;
  final bool reduceMotion;
  final bool largeFocus;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) => Positioned(
    left: left,
    width: width.clamp(28, 2000),
    top: 0,
    bottom: 0,
    child: Padding(
      padding: const EdgeInsets.only(right: 3),
      child: Semantics(
        button: current,
        selected: selected,
        label:
            '${program.scheduled.item.title}, ${_time(context, program.scheduled.start)} to ${_time(context, program.scheduled.end)}${current ? ', currently playing' : ''}',
        child: InkWell(
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 90),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: current
                  ? const Color(0xFF294B46)
                  : selected
                  ? LineupTheme.brass.withValues(alpha: 0.28)
                  : LineupTheme.smoke,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: selected ? LineupTheme.brass : Colors.white12,
                width: selected ? (largeFocus ? 5 : 3) : 1,
              ),
            ),
            child: Text(
              program.scheduled.item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _Details extends StatelessWidget {
  const _Details({required this.controller});
  final GuideController controller;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedProgram;
    return SizedBox(
      height: 100,
      child: Card(
        margin: const EdgeInsets.only(top: 8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: selected == null
              ? const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Move to a program to see details.'),
                )
              : Row(
                  children: [
                    SizedBox(
                      width: 112,
                      height: 72,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: FutureBuilder(
                          future: controller.artworkFor(selected),
                          builder: (context, snapshot) => snapshot.data == null
                              ? const ColoredBox(
                                  color: LineupTheme.smoke,
                                  child: Icon(Icons.movie_outlined, size: 34),
                                )
                              : Image.memory(
                                  snapshot.data!,
                                  fit: BoxFit.cover,
                                  cacheWidth: 360,
                                  errorBuilder: (_, _, _) =>
                                      const Icon(Icons.broken_image_outlined),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            selected.scheduled.item.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            [
                              selected.scheduled.item.showTitle,
                              '${_time(context, selected.scheduled.start)}–${_time(context, selected.scheduled.end)}',
                            ].nonNulls.join(' • '),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
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
