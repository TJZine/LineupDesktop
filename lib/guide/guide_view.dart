import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channels/channel.dart';
import '../settings/lineup_settings.dart';
import '../ui/app_theme.dart';
import '../ui/app_ui.dart';
import 'focused_ticker.dart';
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
    required this.showSummary,
    required this.artworkWidth,
  });

  factory GuideLayoutPolicy.forSize(
    Size size, {
    required bool hasPicture,
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
        : density == GuideDensity.compact && size.height >= 900
        ? 7
        : 5;
    final rowHeight = density == GuideDensity.compact
        ? (size.height >= 1080 ? 78.0 : 58.0)
        : size.height >= 1080
        ? 108.0
        : size.height >= _comfortableGuideHeight
        ? 78.0
        : 58.0;
    final rowBudget =
        size.height -
        (padding * 2 + 48 + 10 + 8 + 52) -
        minimumRows * rowHeight;
    final availableShowcaseHeight = rowBudget.clamp(0.0, double.infinity);
    final targetPictureHeight = size.height < 720
        ? _lerp(236.25, 281.25, (size.height - 600) / 120)
        : size.height < _comfortableGuideHeight
        ? _lerp(281.25, 360, (size.height - 720) / 180)
        : size.height < 1080
        ? _lerp(360, 378, (size.height - _comfortableGuideHeight) / 180)
        : 378.0;
    var showcaseHeight = targetPictureHeight.clamp(
      0.0,
      availableShowcaseHeight,
    );
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
      showSecondaryMetadata: showcaseHeight >= 300,
      showSummary: showcaseHeight >= 340,
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
  final bool showSummary;
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
    final keyboard = HardwareKeyboard.instance;
    final commandModified =
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed;
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
        (key == LogicalKeyboardKey.keyP && !commandModified) ||
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
        key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.goBack ||
        (key == LogicalKeyboardKey.keyG && !commandModified) ||
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
      showSummary: policy.showSummary,
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
                  showProvenance: policy.rowHeight >= 78,
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
    final tunedChannel = controller.lineup.channels
        .where((channel) => channel.id == controller.lineup.currentChannelId)
        .firstOrNull;
    final tunedProgram = tunedChannel == null
        ? null
        : controller.currentProgram(tunedChannel.id);
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Image.asset('assets/branding/lineup-logo-mark.png', height: 26),
          const SizedBox(width: 9),
          Text('LINEUP', style: Theme.of(context).textTheme.titleLarge),
          if (tunedChannel != null &&
              controller.lineup.settings.nowWatchingBanner) ...[
            const SizedBox(width: 18),
            Text(
              'NOW PLAYING',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: LineupTheme.of(context).mutedText,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${tunedChannel.number} • ${tunedChannel.name}${tunedProgram == null ? '' : ' — ${tunedProgram.scheduled.item.title}'}',
                key: const Key('guide-now-playing-context'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
          const Spacer(),
          if (!compact && MediaQuery.sizeOf(context).width >= 1500)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                'OK Select  ·  ←/→ Navigate  ·  BACK Close',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: LineupTheme.of(context).mutedText),
              ),
            ),
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
    required this.showSummary,
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
  final bool showSummary;
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
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: picture,
                      ),
                      if (!overlayMode)
                        CustomPaint(
                          key: const Key('guide-picture-corner-mask'),
                          painter: _CornerMaskPainter(
                            color: LineupTheme.of(context).deepBackground,
                            radius: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (overlayMode)
          const SizedBox(width: 12)
        else
          SizedBox(
            width: 12,
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: 13,
              maxWidth: 13,
              child: ColoredBox(color: LineupTheme.of(context).deepBackground),
            ),
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
            showSummary: showSummary,
            artworkWidth: artworkWidth,
            playbackMessage: playbackMessage,
          ),
        ),
      ),
    ],
  );
}

class _CornerMaskPainter extends CustomPainter {
  const _CornerMaskPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    canvas.drawPath(mask, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CornerMaskPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _TimeHeader extends StatelessWidget {
  const _TimeHeader({required this.controller, required this.railWidth});
  final GuideController controller;
  final double railWidth;

  @override
  Widget build(BuildContext context) {
    final slots = controller.guideHours * 2;
    if (slots <= 0) return const SizedBox(height: 52);
    final libraryIds = controller.availableLibraryIds.toList()..sort();
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          SizedBox(
            width: railWidth,
            child:
                controller.lineup.settings.libraryTabsEnabled &&
                    libraryIds.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(6, 5, 8, 5),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: LineupTheme.of(context).primarySurface,
                        border: Border.all(
                          color: LineupTheme.of(context).subtleBorder,
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          isExpanded: true,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
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
                      ),
                    ),
                  )
                : const Padding(
                    padding: EdgeInsets.only(left: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('CHANNEL'),
                    ),
                  ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                if (!width.isFinite || width < 2) {
                  return const SizedBox.shrink();
                }
                final slotWidth = width / slots;
                final stride = (68 / slotWidth).ceil().clamp(1, slots);
                final now = controller.now;
                final nowFraction =
                    now.difference(controller.windowStart).inMicroseconds /
                    controller.windowEnd
                        .difference(controller.windowStart)
                        .inMicroseconds;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Row(
                      children: [
                        for (var index = 0; index < slots; index++)
                          Expanded(
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: LineupTheme.of(context).subtleBorder,
                                  ),
                                ),
                              ),
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
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge,
                                    )
                                  : null,
                            ),
                          ),
                      ],
                    ),
                    if (nowFraction >= 0 && nowFraction < 1)
                      Positioned(
                        left: (width * nowFraction).clamp(0, width - 2),
                        top: 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: LineupTheme.of(context).deepBackground,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            child: Text(
                              'NOW',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: LineupTheme.of(context).liveAccent,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
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
    required this.railWidth,
    required this.showProvenance,
    required this.onTune,
  });
  final Channel channel;
  final GuideController controller;
  final double railWidth;
  final bool showProvenance;
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
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            channel.name,
                            maxLines: showProvenance ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (showProvenance)
                            Text(
                              _channelProvenance(controller, channel),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: LineupTheme.of(context).mutedText,
                                  ),
                            ),
                        ],
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
              for (var index = 0; index < controller.guideHours * 2; index++)
                Positioned(
                  left:
                      constraints.maxWidth *
                      index /
                      (controller.guideHours * 2),
                  top: 0,
                  bottom: 0,
                  child: SizedBox(
                    width: 1,
                    child: ColoredBox(
                      color: LineupTheme.of(context).subtleBorder,
                    ),
                  ),
                ),
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
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 14,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          LineupTheme.of(context).deepBackground
                              .withValues(alpha: 0.7),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 14,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          LineupTheme.of(context).deepBackground
                              .withValues(alpha: 0.7),
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
        onTap: widget.onDoubleTap ?? widget.onTap,
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
                color: widget.focused
                    ? LineupTheme.of(context).selectedSurface
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
                  _ProgramCellContent(
                    program: widget.program,
                    focused: widget.focused,
                    current: widget.current,
                    past: widget.past,
                    reduceMotion: widget.reduceMotion,
                  ),
                  if (widget.current)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 4,
                      child: ColoredBox(
                        color: LineupTheme.of(context).deepBackground,
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: widget.progress.clamp(0, 1),
                          child: ColoredBox(
                            color: LineupTheme.of(context).progressFill,
                          ),
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

class _ProgramCellContent extends StatelessWidget {
  const _ProgramCellContent({
    required this.program,
    required this.focused,
    required this.current,
    required this.past,
    required this.reduceMotion,
  });

  final GuideProgram program;
  final bool focused;
  final bool current;
  final bool past;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final item = program.scheduled.item;
    final episodeCode = _episodeCode(item);
    final isEpisode = item.showTitle != null || episodeCode != null;
    final primaryTitle = isEpisode ? item.showTitle ?? item.title : item.title;
    final episodeTitle = isEpisode && item.title != primaryTitle
        ? item.title
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 220;
        final medium = constraints.maxWidth >= 140;
        final tiny = constraints.maxWidth < 88;
        final richRow = constraints.maxHeight >= 56;
        final showEpisode = episodeCode != null && (wide || focused);
        final showSubtitle =
            episodeTitle != null && richRow && (medium || focused);
        final showTime = richRow && (wide || (focused && !isEpisode));
        final titleStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: past ? LineupTheme.of(context).mutedText : null,
          fontWeight: focused ? FontWeight.w800 : FontWeight.w600,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (showEpisode || current)
              Row(
                children: [
                  if (showEpisode) _CellEpisodeTag(episodeCode),
                  const Spacer(),
                  if (current)
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: LineupTheme.of(context).liveAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            if (tiny && !focused)
              Text(
                primaryTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              )
            else
              FocusedTicker(
                text: primaryTitle,
                focused: focused,
                reduceMotion: reduceMotion,
                style: titleStyle,
              ),
            if (showSubtitle)
              FocusedTicker(
                text: episodeTitle,
                focused: focused,
                reduceMotion: reduceMotion,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: LineupTheme.of(context).mutedText),
              ),
            if (showTime)
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${_time(context, program.scheduled.start)}–${_time(context, program.scheduled.end)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: LineupTheme.of(context).mutedText,
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CellEpisodeTag extends StatelessWidget {
  const _CellEpisodeTag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: LineupTheme.of(context).deepBackground.withValues(alpha: 0.5),
      border: Border.all(color: LineupTheme.of(context).defaultBorder),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
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
    required this.showSummary,
    required this.artworkWidth,
    required this.playbackMessage,
  });
  final GuideController controller;
  final bool compact;
  final bool showArtwork;
  final bool showSecondaryMetadata;
  final bool showSummary;
  final double artworkWidth;
  final String? playbackMessage;

  @override
  State<_Details> createState() => _DetailsState();
}

class _DetailsState extends State<_Details> {
  String? _artworkProgramId;
  Uint8List? _poster;
  Uint8List? _backdrop;
  Uint8List? _clearLogo;
  Color? _dynamicColor;
  int _artworkToken = 0;

  @override
  void dispose() {
    _artworkToken++;
    super.dispose();
  }

  void _ensureArtwork(GuideProgram? program) {
    final settings = widget.controller.lineup.settings;
    final item = program?.scheduled.item;
    final artworkKey = program == null
        ? null
        : '${program.id}|${widget.controller.lineup.contentGeneration}|${item?.showThumb}|${item?.artwork}|${item?.backdrop}|${item?.clearLogo}|${settings.guideInfoBackgroundMode.name}|${settings.preferClearLogos}';
    if (artworkKey == _artworkProgramId) return;
    _artworkProgramId = artworkKey;
    _poster = null;
    _backdrop = null;
    _clearLogo = null;
    _dynamicColor = null;
    final token = ++_artworkToken;
    if (program == null) return;
    unawaited(_loadArtwork(program, token));
  }

  Future<void> _loadArtwork(GuideProgram program, int token) async {
    final settings = widget.controller.lineup.settings;
    final artwork = await Future.wait([
      widget.controller.artworkFor(program),
      if (settings.guideInfoBackgroundMode == GuideInfoBackgroundMode.artwork)
        widget.controller.artworkFor(program, GuideArtworkKind.backdrop)
      else
        Future<Uint8List?>.value(),
      if (settings.preferClearLogos)
        widget.controller.artworkFor(program, GuideArtworkKind.clearLogo)
      else
        Future<Uint8List?>.value(),
    ]);
    if (!mounted || token != _artworkToken) return;
    final poster = artwork[0];
    setState(() {
      _poster = poster;
      _backdrop = artwork[1];
      _clearLogo = artwork[2];
      _dynamicColor = poster == null ? null : _artworkHashColor(poster);
    });
    if (poster == null) return;
    final color = await _artworkColor(poster);
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
    final roles = LineupTheme.of(context);
    final dynamicColor = _dynamicColor ?? roles.progressFill;
    final settings = controller.lineup.settings;
    final backgroundMode = settings.guideInfoBackgroundMode;
    final backgroundGradient = switch (backgroundMode) {
      GuideInfoBackgroundMode.bleed => RadialGradient(
        center: const Alignment(0.72, -0.15),
        radius: 1.25,
        colors: [
          Color.alphaBlend(
            dynamicColor.withValues(alpha: 0.48),
            roles.primarySurface,
          ),
          roles.primarySurface,
          roles.deepBackground,
        ],
        stops: const [0, 0.58, 1],
      ),
      GuideInfoBackgroundMode.themeDefault => LinearGradient(
        colors: [roles.primarySurface, roles.deepBackground],
      ),
      GuideInfoBackgroundMode.artwork => LinearGradient(
        colors: [roles.primarySurface, roles.deepBackground],
      ),
    };
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: AnimatedContainer(
        key: const Key('guide-info-dynamic-background'),
        duration: controller.lineup.settings.reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 400),
        decoration: BoxDecoration(gradient: backgroundGradient),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (backgroundMode == GuideInfoBackgroundMode.artwork &&
                _backdrop != null) ...[
              Positioned.fill(
                child: Image.memory(
                  _backdrop!,
                  key: const Key('guide-info-backdrop'),
                  fit: BoxFit.cover,
                  alignment: Alignment.centerRight,
                  gaplessPlayback: true,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        roles.deepBackground.withValues(alpha: 0.94),
                        roles.deepBackground.withValues(alpha: 0.56),
                        roles.deepBackground.withValues(alpha: 0.72),
                      ],
                      stops: const [0, 0.6, 1],
                    ),
                  ),
                ),
              ),
            ],
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 12 : 18,
                vertical: widget.compact ? 8 : 12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                            poster: _poster,
                            clearLogo: settings.preferClearLogos
                                ? _clearLogo
                                : null,
                            showArtwork: widget.showArtwork,
                            showSecondaryMetadata: widget.showSecondaryMetadata,
                            showSummary: widget.showSummary,
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
    required this.poster,
    required this.clearLogo,
    required this.showArtwork,
    required this.showSecondaryMetadata,
    required this.showSummary,
    required this.artworkWidth,
    required this.playbackMessage,
    required this.now,
  });

  final GuideProgram program;
  final Channel? channel;
  final Uint8List? poster;
  final Uint8List? clearLogo;
  final bool showArtwork;
  final bool showSecondaryMetadata;
  final bool showSummary;
  final double artworkWidth;
  final String? playbackMessage;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final item = program.scheduled.item;
    final episode = _episodeCode(item);
    final badges = _mediaBadges(item);
    final hasClearLogo = clearLogo != null;
    final logoFallback = Text(
      item.showTitle?.toUpperCase() ?? item.title,
      key: const Key('guide-clear-logo-fallback'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: item.showTitle != null
          ? Theme.of(context).textTheme.labelMedium
          : Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
    );
    return Row(
      children: [
        if (showArtwork)
          SizedBox(
            key: const Key('guide-focused-artwork'),
            width: artworkWidth,
            height: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: poster == null
                  ? ColoredBox(
                      color: LineupTheme.of(context).primarySurface,
                      child: const Icon(Icons.movie_outlined, size: 34),
                    )
                  : Image.memory(
                      poster!,
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
              if (hasClearLogo)
                Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: showSecondaryMetadata ? 360 : 240,
                      maxHeight: showSecondaryMetadata ? 52 : 36,
                    ),
                    child: Image.memory(
                      clearLogo!,
                      key: const Key('guide-clear-logo'),
                      fit: BoxFit.contain,
                      alignment: Alignment.centerLeft,
                      gaplessPlayback: true,
                      semanticLabel: '${item.showTitle ?? item.title} logo',
                      errorBuilder: (_, _, _) => logoFallback,
                    ),
                  ),
                ),
              if (item.showTitle != null && !hasClearLogo)
                Text(
                  item.showTitle!.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              if (item.showTitle != null || !hasClearLogo)
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
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Wrap(
                  key: const Key('guide-program-meta'),
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _InfoPill(
                      '${_time(context, program.scheduled.start)}–${_time(context, program.scheduled.end)}',
                    ),
                    _InfoPill(_duration(item.duration)),
                    if (episode != null) _InfoPill(episode),
                    if (item.year != null) _InfoPill('${item.year}'),
                    _InfoPill(
                      program.isCurrentAt(now)
                          ? 'Airing now'
                          : program.scheduled.end.isBefore(now)
                          ? 'Ended'
                          : 'Upcoming',
                    ),
                  ],
                ),
              ),
              if (showSecondaryMetadata && item.genres.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    item.genres.take(3).join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
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
              if (showSummary && item.summary != null)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      item.summary!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
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

class _InfoPill extends StatelessWidget {
  const _InfoPill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: LineupTheme.of(context).deepBackground.withValues(alpha: 0.42),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: LineupTheme.of(context).defaultBorder),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w700,
        fontFeatures: const [ui.FontFeature.tabularFigures()],
      ),
    ),
  );
}

String? _episodeCode(ChannelItem item) {
  final season = item.seasonNumber;
  final episode = item.episodeNumber;
  if (season == null || episode == null) return null;
  return 'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';
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
  item.audioCodec?.toUpperCase(),
  if (item.audioChannels != null) _audioChannels(item.audioChannels!),
].nonNulls.toList();

String _audioChannels(int channels) => switch (channels) {
  1 => 'MONO',
  2 => 'STEREO',
  6 => '5.1',
  8 => '7.1',
  _ => '$channels CH',
};

String _duration(Duration duration) {
  final totalMinutes = duration.inMinutes;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes.remainder(60);
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}

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

String _channelProvenance(
  GuideController controller,
  Channel channel,
) => switch (channel.source) {
  LibrarySource(:final libraryId, :final libraryType) =>
    '${_libraryName(controller, libraryId)} • ${libraryType == PlexLibraryType.movie ? 'Movies' : 'Shows'}',
  PlaylistSource() => 'Playlist',
  ManualSource() => 'Manual lineup',
  MixedSource() => 'Mixed sources',
};
