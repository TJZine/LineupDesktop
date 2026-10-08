import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channels/channel.dart';
import '../settings/lineup_settings.dart';
import '../ui/app_theme.dart';
import '../ui/app_ui.dart';
import 'focused_ticker.dart';
import 'guide_controller.dart';

const _guideTimelineGutter = 1.0;
const _guideEdgeContentInset = 12.0;

class GuideLayoutPolicy {
  const GuideLayoutPolicy._({
    required this.compact,
    required this.timeHeaderHeight,
    required this.padding,
    required this.channelRailWidth,
    required this.showcaseHeight,
    required this.pictureWidth,
    required this.rowHeight,
    required this.minimumRows,
    required this.compactLogo,
  });

  factory GuideLayoutPolicy.forSize(
    Size size, {
    required bool hasPicture,
    double textScale = 1,
    double? timeHeaderHeight,
  }) {
    final width = size.width.isFinite
        ? size.width.clamp(0.0, 10000.0).toDouble()
        : 0.0;
    final height = size.height.isFinite
        ? size.height.clamp(0.0, 10000.0).toDouble()
        : 0.0;
    final compact = width < LineupLayout.expandedNavigation;
    final padding = horizontalPadding(size);
    const minimumRows = 5;
    final chromeHeight =
        toolbarHeight(size, textScale: textScale) +
        10 +
        controlsHeight(size, textScale: textScale) +
        (timeHeaderHeight ?? 38 * textScale);
    final minimumRowHeight = 58 * textScale;
    final available = math.max(0.0, height - chromeHeight);
    // The aperture keeps its approved responsive footprint independently of
    // the full-bleed grid. Its compact budget reserves 70% for reference rows;
    // the former 20px frame reserve now goes to the grid, not to a larger PiP.
    final pictureControlHeight = controlHeight(size, textScale: textScale);
    final pictureControlsHeight =
        controlsWrapForWidth(math.max(0.0, width - 40), textScale: textScale)
        ? pictureControlHeight * 2
        : math.max(56.0, pictureControlHeight);
    final pictureAvailable = math.max(
      0.0,
      height -
          20 -
          toolbarHeight(size, textScale: textScale) -
          10 -
          pictureControlsHeight -
          (timeHeaderHeight ?? 38 * textScale),
    );
    // Preserve the prior five 0.001px row tails in the aperture budget.
    const pictureRoundingAllowance = 0.005;
    final compactPictureHeight =
        pictureAvailable * 0.3 + pictureRoundingAllowance;
    final referencePictureHeight =
        height - 1080 + 324 + pictureRoundingAllowance;
    final pictureAllocation = math.max(
      0.0,
      math.min(
        math.max(compactPictureHeight, referencePictureHeight),
        pictureAvailable - minimumRowHeight * minimumRows,
      ),
    );
    // Keep the information area's allocation as well as the aperture size.
    // Freed frame space goes to the five rows; 16:10 extra height stays here.
    final showcaseHeight = math.max(0.0, pictureAllocation - 0.01);
    final rowHeight = math.max(
      minimumRowHeight,
      (available - showcaseHeight) / minimumRows,
    );
    final pictureHeight = math.min(324.0, pictureAllocation);
    // The extra width exposed by full-bleed belongs to the companion panel.
    final widthBudget = math.max(0.0, width - 360 - 12 - 40);
    final pictureWidth = hasPicture
        ? math.min(pictureHeight * 16 / 9, widthBudget)
        : pictureHeight * 16 / 9;
    return GuideLayoutPolicy._(
      compact: compact,
      timeHeaderHeight: timeHeaderHeight ?? 38 * textScale,
      padding: padding,
      channelRailWidth:
          (width >= 1800
              ? 300
              : width >= 1100
              ? 208
              : 176) *
          textScale.clamp(1, 1.5),
      showcaseHeight: showcaseHeight,
      pictureWidth: pictureWidth,
      rowHeight: rowHeight,
      minimumRows: minimumRows,
      compactLogo: showcaseHeight < 180 * textScale,
    );
  }

  static double toolbarHeight(Size size, {double textScale = 1}) => 80;

  static double horizontalPadding(Size size) => 0;

  static double availableWidth(Size size) =>
      (size.width - horizontalPadding(size) * 2).clamp(0.0, double.infinity);

  static double controlHeight(Size size, {double textScale = 1}) {
    final fontSize = 18.0;
    final enlargedContent = fontSize * textScale * 1.4 + 16;
    return math.max(48, enlargedContent);
  }

  static bool controlsWrapForWidth(
    double availableWidth, {
    double textScale = 1,
  }) => availableWidth < 1000 * textScale;

  static bool controlsWrap(Size size, {double textScale = 1}) {
    return controlsWrapForWidth(
      availableWidth(size) - _guideEdgeContentInset * 2,
      textScale: textScale,
    );
  }

  static double controlsHeight(Size size, {double textScale = 1}) {
    final height = controlHeight(size, textScale: textScale);
    return controlsWrap(size, textScale: textScale)
        ? height * 2
        : math.max(56, height);
  }

  /// Whole-row offsets, including the trailing edge of a five-row viewport.
  static double snapRowOffset(
    double offset,
    double rowHeight,
    double maxOffset,
  ) {
    if (rowHeight <= 0) return 0;
    final lastRow = ((maxOffset + 0.000001) / rowHeight).floor();
    return (offset / rowHeight).round().clamp(0, lastRow) * rowHeight;
  }

  final bool compact;
  final double timeHeaderHeight;
  final double padding;
  final double channelRailWidth;
  final double showcaseHeight;
  final double pictureWidth;
  final double rowHeight;
  final int minimumRows;
  final bool compactLogo;
}

class _GuideRowScrollController extends ScrollController {
  _GuideRowScrollController({
    required this.rowHeight,
    super.initialScrollOffset,
  });

  final double Function() rowHeight;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _GuideRowScrollPosition(
    rowHeight: rowHeight,
    physics: physics,
    context: context,
    initialPixels: initialScrollOffset,
    oldPosition: oldPosition,
  );
}

class _GuideRowScrollPosition extends ScrollPositionWithSingleContext {
  _GuideRowScrollPosition({
    required this.rowHeight,
    required super.physics,
    required super.context,
    required super.initialPixels,
    super.oldPosition,
  });

  final double Function() rowHeight;

  @override
  void jumpTo(double value) => super.jumpTo(
    GuideLayoutPolicy.snapRowOffset(value, rowHeight(), maxScrollExtent),
  );

  @override
  void pointerScroll(double delta) {
    if (delta == 0) return;
    final rows = math.max(1, (delta.abs() / rowHeight()).round());
    super.pointerScroll(delta.sign * rows * rowHeight());
  }
}

class _GuideRowScrollPhysics extends ScrollPhysics {
  const _GuideRowScrollPhysics({required this.rowHeight, super.parent});

  final double rowHeight;

  @override
  _GuideRowScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _GuideRowScrollPhysics(
        rowHeight: rowHeight,
        parent: buildParent(ancestor),
      );

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (position.outOfRange) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    final direction = velocity.abs() > tolerance.velocity
        ? velocity.sign * rowHeight / 2
        : 0.0;
    final target = GuideLayoutPolicy.snapRowOffset(
      position.pixels + direction,
      rowHeight,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 0.000001) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }
}

class GuideView extends StatefulWidget {
  const GuideView({
    required this.controller,
    required this.onClose,
    required this.onTune,
    this.onOpenMenu,
    this.onSetUpChannels,
    this.showIdleArtwork = false,
    this.pictureInPicture,
    this.onOpenPlayer,
    this.playbackMessage,
    this.watchingChannelId,
    this.focusNode,
    super.key,
  });

  final GuideController controller;
  final VoidCallback onClose;
  final Future<void> Function(String channelId) onTune;
  final LineupMenuCallback? onOpenMenu;
  final Widget? pictureInPicture;
  final VoidCallback? onSetUpChannels;
  final bool showIdleArtwork;
  final VoidCallback? onOpenPlayer;
  final String? playbackMessage;
  final String? watchingChannelId;
  final FocusNode? focusNode;

  @override
  State<GuideView> createState() => _GuideViewState();
}

class _GuideViewState extends State<GuideView>
    with SingleTickerProviderStateMixin {
  final _retryFocus = FocusNode(debugLabel: 'Guide retry all schedules');
  final _setupFocus = FocusNode(debugLabel: 'Guide set up channels');
  bool _allVisibleFailed = false;
  final _menuFocus = FocusNode(debugLabel: 'Guide Lineup menu');
  final _guideFocus = FocusNode(debugLabel: 'Guide grid');
  final _searchFocus = FocusNode(debugLabel: 'Guide channel search');
  final _searchController = TextEditingController();
  late final AnimationController _activityPulse;
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
    _searchController.text = widget.controller.searchQuery;
    _searchController.addListener(_searchChanged);
    _activityPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    widget.controller.refreshForPresentation();
    widget.controller.addListener(_changed);
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestViewport());
  }

  @override
  void dispose() {
    _retryFocus.dispose();
    _setupFocus.dispose();
    _menuFocus.dispose();
    _guideFocus.dispose();
    _searchFocus.dispose();
    _searchController
      ..removeListener(_searchChanged)
      ..dispose();
    _activityPulse.dispose();
    widget.controller.removeListener(_changed);
    _clockTimer?.cancel();
    _scroll
      ?..removeListener(_scrolled)
      ..dispose();
    super.dispose();
  }

  void _searchChanged() {
    widget.controller.setSearchQuery(_searchController.text);
  }

  KeyEventResult _searchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_searchController.text.isNotEmpty) {
        _searchController.clear();
      } else {
        (widget.focusNode ?? _guideFocus).requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (widget.controller.channels.isNotEmpty) {
        (widget.focusNode ?? _guideFocus).requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  ScrollController _scrollFor(double rowHeight) {
    final existing = _scroll;
    if (existing == null) {
      _effectiveRowHeight = rowHeight;
      final created = _GuideRowScrollController(
        rowHeight: () => _effectiveRowHeight!,
        initialScrollOffset:
            (widget.controller.verticalOffsetFor(rowHeight) / rowHeight)
                .round() *
            rowHeight,
      )..addListener(_scrolled);
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
    final searchQuery = widget.controller.searchQuery;
    if (_searchController.text != searchQuery) {
      _searchController.value = TextEditingValue(
        text: searchQuery,
        selection: TextSelection.collapsed(offset: searchQuery.length),
      );
    }
    _syncActivityPulse();
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
      final first = ((scroll.offset + 0.000001) / rowHeight).floor();
      if (index < first || index >= first + _visibleRows) {
        final target = (index * rowHeight).clamp(
          0.0,
          scroll.position.maxScrollExtent,
        );
        // Reveal a whole row without animating through partial header rows.
        scroll.jumpTo(target);
      }
      _requestViewport();
    });
  }

  void _syncActivityPulse() {
    final active =
        !widget.controller.lineup.settings.reduceMotion &&
        widget.controller.activeLoadCount > 0;
    if (active && !_activityPulse.isAnimating) {
      _activityPulse.repeat();
    } else if (!active && _activityPulse.isAnimating) {
      _activityPulse
        ..stop()
        ..value = 0.5;
    }
  }

  void _scrolled() {
    if (mounted) setState(() {});
    _requestViewport();
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
    final first = scroll.hasClients
        ? ((scroll.offset + 0.000001) / rowHeight).floor()
        : 0;
    if (scroll.hasClients) {
      widget.controller.rememberVerticalOffset(scroll.offset, rowHeight);
    }
    widget.controller.requestViewport(first, _visibleRows);
    _syncActivityPulse();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (_retryFocus.hasFocus) {
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.space ||
          key == LogicalKeyboardKey.select) {
        widget.controller.retryFailedRows();
        (widget.focusNode ?? _guideFocus).requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        (widget.focusNode ?? _guideFocus).requestFocus();
      }
    }
    final keyboard = HardwareKeyboard.instance;
    final commandModified =
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed;
    if (key == LogicalKeyboardKey.keyF &&
        (keyboard.isControlPressed || keyboard.isMetaPressed)) {
      _searchFocus.requestFocus();
    } else if (key == LogicalKeyboardKey.arrowUp) {
      widget.controller.moveVertical(-1);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      widget.controller.moveVertical(1);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      widget.controller.moveHorizontal(-1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (_allVisibleFailed) {
        _retryFocus.requestFocus();
      } else if (widget.controller.lineup.channels.isEmpty) {
        _setupFocus.requestFocus();
      } else {
        widget.controller.moveHorizontal(1);
      }
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
      if (_setupFocus.hasFocus) {
        widget.onSetUpChannels?.call();
        return KeyEventResult.handled;
      }
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
    compact: policy.compact,
    watchingChannelId: widget.watchingChannelId,
    onClose: widget.onClose,
    onOpenMenu: widget.onOpenMenu,
    menuFocus: _menuFocus,
  );

  Widget _showcase(GuideLayoutPolicy policy) => SizedBox(
    height: policy.showcaseHeight,
    child: _GuideShowcase(
      controller: widget.controller,
      picture: widget.pictureInPicture,
      showIdleArtwork: widget.showIdleArtwork,
      pictureWidth: policy.pictureWidth,
      compactLogo: policy.compactLogo,
      playbackMessage: widget.playbackMessage,
      onOpenPlayer: widget.onOpenPlayer,
    ),
  );

  Widget _schedule(GuideLayoutPolicy policy, List<Channel> channels) {
    final scroll = _scrollFor(policy.rowHeight);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _guideEdgeContentInset,
          ),
          child: _GuideControls(
            key: const Key('guide-control-content'),
            controller: widget.controller,
            railWidth: policy.channelRailWidth,
            searchController: _searchController,
            searchFocus: _searchFocus,
            onSearchKey: _searchKey,
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final now = widget.controller.now;
              final visible = GuideGeometry.visibleRows(
                scrollOffset: scroll.hasClients ? scroll.offset : 0,
                viewportHeight:
                    constraints.maxHeight - policy.timeHeaderHeight + 0.000001,
                rowHeight: policy.rowHeight,
                totalRows: channels.length,
              );
              _visibleRows = visible.count;
              final offset = scroll.hasClients ? scroll.offset : 0.0;
              final lastVisible =
                  ((offset + constraints.maxHeight - policy.timeHeaderHeight) /
                          policy.rowHeight)
                      .ceil()
                      .clamp(0, channels.length);
              _allVisibleFailed =
                  lastVisible > visible.first &&
                  channels
                      .skip(visible.first)
                      .take(lastVisible - visible.first)
                      .every(
                        (channel) =>
                            widget.controller.row(channel.id).state ==
                            GuideLoadState.error,
                      );
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _requestViewport(),
              );
              final timelineWidth =
                  constraints.maxWidth -
                  policy.channelRailWidth -
                  _guideTimelineGutter;
              final fraction =
                  now.difference(widget.controller.windowStart).inMicroseconds /
                  widget.controller.windowEnd
                      .difference(widget.controller.windowStart)
                      .inMicroseconds;
              return Stack(
                children: [
                  if (fraction >= 0 && fraction < 1)
                    Positioned(
                      left:
                          policy.channelRailWidth +
                          _guideTimelineGutter +
                          timelineWidth * fraction,
                      top: 0,
                      bottom: 0,
                      child: Semantics(
                        container: true,
                        label: 'Current time',
                        child: IgnorePointer(
                          child: Container(
                            key: const Key('guide-now-line'),
                            width: 2,
                            color: LineupTheme.of(context).liveAccent,
                          ),
                        ),
                      ),
                    ),
                  Column(
                    children: [
                      _TimeHeader(
                        controller: widget.controller,
                        railWidth: policy.channelRailWidth,
                        height: policy.timeHeaderHeight,
                      ),
                      Expanded(
                        child: channels.isEmpty
                            ? _NoMatchingChannels(
                                onSetUpChannels: widget.onSetUpChannels,
                                setupFocus: _setupFocus,
                                filtered: widget
                                    .controller
                                    .lineup
                                    .channels
                                    .isNotEmpty,
                              )
                            : ListView.builder(
                                key: const Key('guide-schedule-list'),
                                controller: scroll,
                                physics: _GuideRowScrollPhysics(
                                  rowHeight: policy.rowHeight,
                                ),
                                padding: EdgeInsets.zero,
                                itemExtent: policy.rowHeight,
                                itemCount: channels.length,
                                itemBuilder: (context, index) => _GuideRow(
                                  channel: channels[index],
                                  watchingChannelId: widget.watchingChannelId,
                                  controller: widget.controller,
                                  railWidth: policy.channelRailWidth,
                                  hideSchedule: _allVisibleFailed,
                                  showProvenance:
                                      policy.rowHeight >=
                                      78 *
                                          MediaQuery.textScalerOf(context)
                                              .scale(1),
                                  onTune: widget.onTune,
                                  now: now,
                                  activityPulse: _activityPulse,
                                ),
                              ),
                      ),
                    ],
                  ),
                  if (_allVisibleFailed)
                    Positioned(
                      left: policy.channelRailWidth + _guideTimelineGutter,
                      right: 0,
                      top: policy.timeHeaderHeight,
                      bottom: 0,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                "Schedules couldn't load",
                                style: Theme.of(context).textTheme.titleLarge,
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Focus(
                              onKeyEvent: (node, event) {
                                if (event is! KeyDownEvent) {
                                  return KeyEventResult.ignored;
                                }
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowLeft) {
                                  (widget.focusNode ?? _guideFocus)
                                      .requestFocus();
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.select) {
                                  widget.controller.retryFailedRows();
                                  (widget.focusNode ?? _guideFocus)
                                      .requestFocus();
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              },
                              child: OutlinedButton(
                                focusNode: _retryFocus,
                                onPressed: () {
                                  widget.controller.retryFailedRows();
                                  (widget.focusNode ?? _guideFocus)
                                      .requestFocus();
                                },
                                child: const Text('Retry'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
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
      focusNode: widget.focusNode ?? _guideFocus,
      autofocus: true,
      onKeyEvent: _key,
      child: Material(
        key: const Key('classic-guide'),
        color: Colors.transparent,
        child: LayoutBuilder(
          builder: (context, outer) {
            final policy = GuideLayoutPolicy.forSize(
              outer.biggest,
              hasPicture: widget.pictureInPicture != null,
              textScale: MediaQuery.textScalerOf(context).scale(1),
              timeHeaderHeight: _TimeHeader.requiredHeight(
                context,
                widget.controller,
              ),
            );
            final schedule = _schedule(policy, channels);
            final theme = Theme.of(context);
            return DefaultTextStyle(
              style: theme.textTheme.bodyMedium!,
              child: _ClassicGuideSurface(
                color: roles.deepBackground,
                showcaseHeight: policy.showcaseHeight,
                toolbar: _toolbar(policy),
                showcase: _showcase(policy),
                body: schedule,
              ),
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
    required this.showcaseHeight,
    required this.toolbar,
    required this.showcase,
    required this.body,
  });

  final Color color;
  final double showcaseHeight;
  final Widget toolbar;
  final Widget? showcase;
  final Widget body;

  // Overlap opaque neighbors across fractional 16:9 edges so rasterization
  // cannot leave an alpha seam outside the PlayerSurface aperture.
  static const _paintOverlap = 2.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ColoredBox(
          color: color,
          child: Column(
            children: [
              toolbar,
              const SizedBox(width: double.infinity, height: 2),
            ],
          ),
        ),
        if (showcase != null)
          SizedBox(
            key: const Key('guide-information-area'),
            height: showcaseHeight,
            child: OverflowBox(
              alignment: Alignment.center,
              minHeight: showcaseHeight + _paintOverlap,
              maxHeight: showcaseHeight + _paintOverlap,
              child: SizedBox(
                height: showcaseHeight + _paintOverlap,
                child: showcase!,
              ),
            ),
          ),
        Expanded(
          child: ColoredBox(
            color: color,
            child: Padding(
              padding: EdgeInsets.only(top: showcase == null ? 0 : 8),
              child: body,
            ),
          ),
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.watchingChannelId,
    required this.compact,
    required this.onClose,
    required this.onOpenMenu,
    required this.menuFocus,
  });
  final GuideController controller;
  final String? watchingChannelId;
  final bool compact;
  final VoidCallback onClose;
  final LineupMenuCallback? onOpenMenu;
  final FocusNode menuFocus;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final enlargedControls = textScale > 1;
    final roles = LineupTheme.of(context);
    final now = controller.now.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final tunedChannel = controller.lineup.channels
        .where((channel) => channel.id == watchingChannelId)
        .firstOrNull;
    final tunedProgram = tunedChannel == null
        ? null
        : controller.currentProgram(tunedChannel.id);
    final showPlaying =
        tunedChannel != null && controller.lineup.settings.nowWatchingBanner;
    final showDate = size.width >= 1100;
    final supportingStyle = TextStyle(
      fontSize: 18.0,
      color: roles.secondaryText,
    );

    return LineupTopBar(
      inset: _guideEdgeContentInset,
      menuKey: const Key('guide-app-menu'),
      menuFocusNode: menuFocus,
      onOpenMenu: onOpenMenu,
      trailing: Row(
        children: [
          if (showPlaying) ...[
            SizedBox(width: 20.0),
            Expanded(
              child: Text(
                '${tunedChannel.number} · ${tunedChannel.name}${tunedProgram == null ? '' : ' — ${tunedProgram.scheduled.item.title}'}',
                key: const Key('guide-now-playing-context'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: supportingStyle,
              ),
            ),
          ] else
            const Spacer(),
          if (showDate)
            Text(
              '${localizations.formatMediumDate(now)}  ·  ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(now))}',
              key: const Key('guide-current-date-time'),
              maxLines: 1,
              style: supportingStyle.copyWith(color: roles.mutedText),
            ),
          SizedBox(width: 8),
          IconButton(
            tooltip: 'Close Guide',
            onPressed: onClose,
            constraints: enlargedControls
                ? BoxConstraints(minWidth: 48, minHeight: 48)
                : null,
            iconSize: 24,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _GuideControls extends StatelessWidget {
  const _GuideControls({
    super.key,
    required this.controller,
    required this.railWidth,
    required this.searchController,
    required this.searchFocus,
    required this.onSearchKey,
  });

  final GuideController controller;
  final double railWidth;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final FocusOnKeyEventCallback onSearchKey;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    final controlStyle = Theme.of(context).textTheme.bodyMedium!
        .copyWith(fontSize: 18.0, color: LineupTheme.of(context).secondaryText);
    final controlHeight = GuideLayoutPolicy.controlHeight(
      size,
      textScale: textScale,
    );
    final enlargedControls = textScale > 1;
    final roles = LineupTheme.of(context);
    final libraryIds = controller.availableLibraryIds.toList()..sort();
    final selectedLibrary = controller.libraryFilterId;
    final selectedLibraryName = selectedLibrary == null
        ? null
        : _libraryName(controller, selectedLibrary);
    Widget menuItemContent(Widget child) => child;
    final picker = SizedBox(
      width: railWidth,
      height: controlHeight,
      child: DropdownButtonHideUnderline(
        child: LineupDropdownBox(
          compact: true,
          enabled: true,
          child: DropdownButton<String?>(
            key: const Key('guide-library-picker'),
            style: controlStyle,
            isExpanded: true,
            isDense: enlargedControls,
            padding: EdgeInsets.symmetric(horizontal: _guideEdgeContentInset),
            iconSize: 24,
            itemHeight: enlargedControls ? null : controlHeight,
            value: selectedLibrary,
            hint: Text(selectedLibrary == null ? 'All libraries' : 'Libraries'),
            selectedItemBuilder: (context) => [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('All libraries'),
              ),
              for (final _ in libraryIds)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Libraries'),
                ),
            ],
            items: lineupMenuItems([
              DropdownMenuItem(
                value: null,
                child: menuItemContent(const Text('All libraries')),
              ),
              for (final id in libraryIds)
                DropdownMenuItem(
                  value: id,
                  child: menuItemContent(Text(_libraryName(controller, id))),
                ),
            ], selectedLibrary),
            onChanged: controller.setLibraryFilter,
            dropdownColor: LineupTheme.of(context).elevatedSurface,
          ),
        ),
      ),
    );
    final label = selectedLibraryName == null
        ? const SizedBox.shrink()
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  selectedLibraryName,
                  key: const Key('guide-active-library-label'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16.0, color: roles.mutedText),
                ),
              ),
              IconButton(
                tooltip: 'Remove library filter',
                onPressed: () => controller.setLibraryFilter(null),
                iconSize: 17,
                icon: const Icon(Icons.close),
              ),
            ],
          );
    final searchStyle = controlStyle.copyWith(height: 1);
    final searchLineHeight = _textHeight(
      searchStyle,
      MediaQuery.textScalerOf(context),
      Directionality.of(context),
    );
    final searchVerticalPadding = math.max(
      0.0,
      (controlHeight - searchLineHeight) / 2,
    );
    Widget search(double width) => SizedBox(
      width: width,
      height: controlHeight,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: searchController,
        builder: (context, value, child) => Focus(
          onKeyEvent: onSearchKey,
          child: TextField(
            key: const Key('guide-channel-search'),
            style: searchStyle,
            textAlignVertical: TextAlignVertical.center,
            controller: searchController,
            focusNode: searchFocus,
            decoration: InputDecoration(
              hintText: 'Search channels',
              hintStyle: searchStyle.copyWith(color: roles.mutedText),
              isDense: true,
              constraints: BoxConstraints.tightFor(height: controlHeight),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: searchVerticalPadding,
              ),
              suffixIcon: value.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: searchController.clear,
                      icon: Icon(Icons.close, size: 17),
                    ),
            ),
          ),
        ),
      ),
    );
    final navigation = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const Key('guide-earlier'),
          tooltip: 'Earlier by 30 minutes',
          onPressed: controller.canBrowseEarlier
              ? () => controller.moveWindow(-1)
              : null,
          iconSize: 24,
          icon: const Icon(Icons.chevron_left),
        ),
        TextButton(onPressed: controller.playToNow, child: const Text('Now')),
        IconButton(
          key: const Key('guide-later'),
          tooltip: 'Later by 30 minutes',
          onPressed: () => controller.moveWindow(1),
          iconSize: 24,
          icon: const Icon(Icons.chevron_right),
        ),
        SizedBox(width: 8),
        DropdownButtonHideUnderline(
          child: LineupDropdownBox(
            compact: true,
            enabled: true,
            child: DropdownButton<int>(
              key: const Key('guide-hours'),
              style: controlStyle,
              isDense: enlargedControls,
              iconSize: 24,
              itemHeight: enlargedControls ? null : controlHeight,
              padding: null,
              value:
                  LineupSettings.guideHoursOptions.contains(
                    controller.guideHours,
                  )
                  ? controller.guideHours
                  : null,
              hint: const Text('Hours'),
              selectedItemBuilder: (context) => [
                for (final hours in LineupSettings.guideHoursOptions)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('$hours hours'),
                  ),
              ],
              items: lineupMenuItems(
                [
                  for (final hours in LineupSettings.guideHoursOptions)
                    DropdownMenuItem(
                      value: hours,
                      child: menuItemContent(Text('$hours hours')),
                    ),
                ],
                LineupSettings.guideHoursOptions.contains(controller.guideHours)
                    ? controller.guideHours
                    : null,
              ),
              onChanged: (hours) {
                if (hours != null) unawaited(controller.setGuideHours(hours));
              },
              dropdownColor: LineupTheme.of(context).elevatedSurface,
            ),
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (GuideLayoutPolicy.controlsWrapForWidth(
          constraints.maxWidth,
          textScale: textScale,
        )) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  picker,
                  SizedBox(width: 8),
                  Expanded(child: label),
                ],
              ),
              Row(
                children: [
                  Expanded(child: search(double.infinity)),
                  SizedBox(width: 8),
                  navigation,
                ],
              ),
            ],
          );
        }
        return ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: GuideLayoutPolicy.controlsHeight(
              size,
              textScale: textScale,
            ),
          ),
          child: Row(
            children: [
              picker,
              SizedBox(width: 8),
              Expanded(child: label),
              search(340.0),
              SizedBox(width: 8),
              navigation,
            ],
          ),
        );
      },
    );
  }
}

class _GuideShowcase extends StatefulWidget {
  const _GuideShowcase({
    required this.controller,
    required this.picture,
    required this.showIdleArtwork,
    required this.pictureWidth,
    required this.compactLogo,
    required this.playbackMessage,
    required this.onOpenPlayer,
  });

  final GuideController controller;
  final Widget? picture;
  final bool showIdleArtwork;
  final double pictureWidth;
  final bool compactLogo;
  final String? playbackMessage;
  final VoidCallback? onOpenPlayer;

  @override
  State<_GuideShowcase> createState() => _GuideShowcaseState();
}

class _GuideShowcaseState extends State<_GuideShowcase> {
  String? _artworkProgramId;
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
        : '${program.id}|${widget.controller.lineup.contentGeneration}|${item?.showThumb}|${item?.poster}|${item?.backdrop}|${item?.clearLogo}|${settings.guideInfoBackgroundMode.name}|${settings.preferClearLogos}|${widget.showIdleArtwork}';
    if (artworkKey == _artworkProgramId) return;
    _artworkProgramId = artworkKey;
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
      if (settings.guideInfoBackgroundMode == GuideInfoBackgroundMode.artwork ||
          widget.showIdleArtwork)
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
    final channel = controller.focusedChannel;
    final focusedProgram = controller.focusedProgram;
    final selectedProgram = controller.selectedProgram;
    final program =
        focusedProgram ??
        (channel != null &&
                controller.row(channel.id).state == GuideLoadState.ready &&
                selectedProgram?.channelId == channel.id
            ? selectedProgram
            : null);
    _ensureArtwork(program);
    final idlePicture =
        widget.showIdleArtwork && _backdrop != null && channel != null;
    final picture = widget.showIdleArtwork
        ? AnimatedSwitcher(
            duration: controller.lineup.settings.reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 400),
            child: idlePicture
                ? KeyedSubtree(
                    key: ValueKey(_artworkProgramId),
                    child: Image.memory(
                      _backdrop!,
                      key: const Key('guide-idle-backdrop'),
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) =>
                          widget.picture ?? const SizedBox.shrink(),
                      frameBuilder: (context, image, frame, synchronous) =>
                          Stack(
                            key: const Key('guide-idle-artwork'),
                            fit: StackFit.expand,
                            children: [
                              image,
                              ColoredBox(
                                color: Colors.black.withValues(alpha: .6),
                              ),
                              Center(
                                child: Text(
                                  'Select to watch · ${channel.name}',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                    ),
                  )
                : KeyedSubtree(
                    key: const ValueKey('idle-picture-fallback'),
                    child: widget.picture ?? const SizedBox.shrink(),
                  ),
          )
        : widget.picture;
    final pictureRadius = const BorderRadiusDirectional.only(
      topEnd: Radius.circular(12),
      bottomEnd: Radius.circular(12),
    ).resolve(Directionality.of(context));
    final pictureFrame = Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(borderRadius: pictureRadius, child: picture),
        CustomPaint(
          key: const Key('guide-picture-corner-mask'),
          painter: _CornerMaskPainter(
            color: LineupTheme.of(context).deepBackground,
            borderRadius: pictureRadius,
          ),
        ),
      ],
    );
    final pictureContent = widget.onOpenPlayer == null
        ? pictureFrame
        : Semantics(
            button: true,
            label: 'Now playing picture in picture. Open full player.',
            onTap: widget.onOpenPlayer,
            child: InkWell(
              excludeFromSemantics: true,
              onTap: widget.onOpenPlayer,
              borderRadius: pictureRadius,
              child: pictureFrame,
            ),
          );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (picture != null) ...[
          SizedBox(
            width: widget.pictureWidth,
            child: Align(
              child: AspectRatio(
                key: const Key('guide-picture-in-picture'),
                aspectRatio: 16 / 9,
                child: pictureContent,
              ),
            ),
          ),
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
            color: LineupTheme.of(context).deepBackground,
            child: _Details(
              controller: controller,
              program: program,
              backdrop: _backdrop,
              clearLogo: _clearLogo,
              dynamicColor: _dynamicColor,
              compactLogo: widget.compactLogo,
              playbackMessage: widget.playbackMessage,
            ),
          ),
        ),
      ],
    );
  }
}

class _CornerMaskPainter extends CustomPainter {
  const _CornerMaskPainter({required this.color, required this.borderRadius});

  final Color color;
  final BorderRadius borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(borderRadius.toRRect(Offset.zero & size));
    canvas.drawPath(mask, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CornerMaskPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.borderRadius != borderRadius;
}

class _TimeHeader extends StatelessWidget {
  const _TimeHeader({
    required this.controller,
    required this.railWidth,
    required this.height,
  });
  final double height;

  static double requiredHeight(
    BuildContext context,
    GuideController controller,
  ) {
    final scaler = MediaQuery.textScalerOf(context);
    final minimum = 38 * scaler.scale(1);
    final hasMidnight = List.generate(
      controller.guideHours * 2,
      (index) =>
          controller.windowStart.add(Duration(minutes: 30 * index)).toLocal(),
    ).any((tick) => tick.hour == 0 && tick.minute == 0);
    if (!hasMidnight) return minimum;
    final theme = Theme.of(context);
    final timeStyle = theme.textTheme.bodyMedium!;
    final dateStyle = timeStyle.merge(theme.textTheme.labelSmall);
    final direction = Directionality.of(context);
    return math.max(
      minimum,
      _textHeight(timeStyle, scaler, direction) +
          _textHeight(dateStyle, scaler, direction),
    );
  }

  final GuideController controller;
  final double railWidth;

  @override
  Widget build(BuildContext context) {
    final slots = controller.guideHours * 2;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final headerHeight = height;
    if (slots <= 0) return SizedBox(height: headerHeight);
    return SizedBox(
      height: headerHeight,
      child: Row(
        children: [
          SizedBox(
            width: railWidth,
            child: Padding(
              padding: EdgeInsets.only(left: _guideEdgeContentInset),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  MaterialLocalizations.of(context)
                      .formatMediumDate(controller.windowStart.toLocal()),
                  key: const Key('guide-window-date'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          const SizedBox(width: _guideTimelineGutter),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                if (!width.isFinite || width < 2) {
                  return const SizedBox.shrink();
                }
                final slotWidth = width / slots;
                final stride = (68 * textScale / slotWidth).ceil().clamp(
                  1,
                  slots,
                );
                return Row(
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
                              ? Padding(
                                  padding: EdgeInsets.only(left: 12),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Builder(
                                      builder: (context) {
                                        final tick = controller.windowStart.add(
                                          Duration(minutes: 30 * index),
                                        );
                                        final localTick = tick.toLocal();
                                        final midnight =
                                            localTick.hour == 0 &&
                                            localTick.minute == 0;
                                        return Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _time(context, localTick),
                                              overflow: TextOverflow.clip,
                                              maxLines: 1,
                                            ),
                                            if (midnight)
                                              Text(
                                                MaterialLocalizations.of(
                                                  context,
                                                ).formatMediumDate(localTick),
                                                key: const Key(
                                                  'guide-midnight-date',
                                                ),
                                                maxLines: 1,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color: LineupTheme.of(
                                                        context,
                                                      ).progressFill,
                                                    ),
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                )
                              : null,
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
    required this.watchingChannelId,
    required this.railWidth,
    required this.showProvenance,
    required this.hideSchedule,
    required this.onTune,
    required this.now,
    required this.activityPulse,
  });
  final Channel channel;
  final GuideController controller;
  final String? watchingChannelId;
  final double railWidth;
  final bool showProvenance;
  final bool hideSchedule;
  final Future<void> Function(String channelId) onTune;
  final DateTime now;
  final Animation<double> activityPulse;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final focusedChannel = channel.id == controller.focusedChannelId;
    final focusChannelRail =
        focusedChannel && controller.focusedProgram == null;
    final selectedChannel = channel.id == controller.selectedChannelId;
    final tunedChannel = watchingChannelId == channel.id;
    final showSource =
        showProvenance && controller.lineup.settings.guideShowChannelSources;
    final focusFill = roles.focusedText == roles.onFocus
        ? roles.focusedSurface
        : Color.alphaBlend(
            roles.focusBorder.withValues(alpha: 0.24),
            roles.primarySurface,
          );
    final data = controller.row(channel.id);
    void focusCurrentProgram() {
      final current = controller.currentProgram(channel.id);
      if (current != null) {
        controller.focusProgram(current);
      } else {
        final index = controller.channels.indexWhere(
          (row) => row.id == channel.id,
        );
        if (index >= 0) {
          controller.moveVertical(index - controller.focusedChannelIndex);
        }
      }
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
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
                padding: EdgeInsets.symmetric(
                  horizontal: _guideEdgeContentInset,
                ),
                decoration: BoxDecoration(
                  color: focusChannelRail ? focusFill : roles.primarySurface,
                  border: Border(
                    bottom: BorderSide(
                      color: LineupTheme.of(context).subtleBorder,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: railWidth < 180 ? 40 : 48,
                      child: Text(
                        '${channel.number}',
                        style: TextStyle(
                          color: focusChannelRail
                              ? roles.focusedText
                              : roles.secondaryText,
                          fontSize: (showProvenance ? 28 : 22),
                          fontWeight: FontWeight.w500,
                          fontFeatures: const [ui.FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final nameStyle = DefaultTextStyle.of(context).style
                              .copyWith(
                                fontSize: 18,
                                color: focusChannelRail
                                    ? roles.focusedText
                                    : roles.primaryText,
                                fontWeight: FontWeight.w500,
                              );
                          final painter = TextPainter(
                            text: TextSpan(
                              text: channel.name,
                              style: nameStyle,
                            ),
                            textDirection: Directionality.of(context),
                            textScaler: MediaQuery.textScalerOf(context),
                          )..layout(maxWidth: constraints.maxWidth);
                          final lineHeight = painter
                              .computeLineMetrics()
                              .first
                              .height;
                          final supportStyle = DefaultTextStyle.of(context)
                              .style
                              .copyWith(
                                fontSize: (showProvenance ? 16 : 14),
                                color: roles.mutedText,
                              );
                          final supportHeight = _textHeight(
                            supportStyle,
                            MediaQuery.textScalerOf(context),
                            Directionality.of(context),
                          );
                          final supportLabel = tunedChannel
                              ? 'Watching'
                              : _channelProvenance(controller, channel);
                          final availableLines =
                              ((constraints.maxHeight -
                                          ((tunedChannel || showSource)
                                              ? supportHeight
                                              : 0)) /
                                      lineHeight)
                                  .floor()
                                  .clamp(1, 1000);
                          final nameHeight = painter.height.ceilToDouble();
                          painter.dispose();
                          final showSupport =
                              (tunedChannel || showSource) &&
                              nameHeight + supportHeight <=
                                  constraints.maxHeight;
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Tooltip(
                                message: channel.name,
                                child: Text(
                                  channel.name,
                                  softWrap: true,
                                  maxLines: availableLines,
                                  overflow: TextOverflow.ellipsis,
                                  style: nameStyle,
                                ),
                              ),
                              if (showSupport)
                                tunedChannel
                                    ? ExcludeSemantics(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.max,
                                          children: [
                                            Icon(
                                              Icons.play_arrow_rounded,
                                              size: 14,
                                              color: roles.secondaryText,
                                            ),
                                            SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                supportLabel,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: supportStyle.copyWith(
                                                  color: roles.secondaryText,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : Text(
                                        supportLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: supportStyle,
                                      ),
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
          const SizedBox(width: _guideTimelineGutter),
          Expanded(
            child: hideSchedule
                ? const SizedBox.expand()
                : _Programs(
                    channel: channel,
                    data: data,
                    controller: controller,
                    onTune: onTune,
                    now: now,
                    activityPulse: activityPulse,
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
    required this.now,
    required this.activityPulse,
  });
  final Channel channel;
  final GuideRowData data;
  final GuideController controller;
  final Future<void> Function(String channelId) onTune;
  final DateTime now;
  final Animation<double> activityPulse;

  @override
  Widget build(BuildContext context) {
    if (data.state == GuideLoadState.loading ||
        data.state == GuideLoadState.retrying) {
      return _ScheduleStatus(
        label: data.state == GuideLoadState.retrying
            ? 'Retrying…'
            : 'Loading schedule…',
        pulse: activityPulse,
        reduceMotion: controller.lineup.settings.reduceMotion,
      );
    }
    if (data.state == GuideLoadState.error) {
      return Semantics(
        label: 'Schedule failed to load',
        button: true,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Schedule unavailable ·'),
            SizedBox(width: 8),
            LineupInlineLink(
              onPressed: () => controller.retry(channel.id),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (data.programs.isEmpty) {
      return const Center(
        child: Text('No programs scheduled in this time range'),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              for (final program in data.programs)
                _programCell(program, constraints.maxWidth, now),
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
    return _ProgramCell(
      key: ValueKey(program.id),
      program: program,
      focused: program.id == controller.focusedProgramId,
      selected: program.id == controller.selectedProgramId,
      current: current,
      nowOffset: current
          ? viewportWidth *
                    now.difference(controller.windowStart).inMicroseconds /
                    controller.windowEnd
                        .difference(controller.windowStart)
                        .inMicroseconds -
                rect.left
          : null,
      past: !program.scheduled.end.isAfter(now),
      left: rect.left,
      width: rect.width,
      onTap: () => controller.focusProgram(program),
      onDoubleTap: () {
        if (!program.isCurrentAt(controller.now)) {
          controller.focusProgram(program);
          return;
        }
        controller.selectProgram(program);
        unawaited(onTune(channel.id));
      },
      reduceMotion: controller.lineup.settings.reduceMotion,
    );
  }
}

class _ScheduleStatus extends StatelessWidget {
  const _ScheduleStatus({
    required this.label,
    required this.pulse,
    required this.reduceMotion,
  });

  final String label;
  final Animation<double> pulse;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: reduceMotion
                ? const AlwaysStoppedAnimation(0.7)
                : TweenSequence<double>([
                    TweenSequenceItem(
                      tween: Tween(begin: 0.45, end: 0.82),
                      weight: 50,
                    ),
                    TweenSequenceItem(
                      tween: Tween(begin: 0.82, end: 0.45),
                      weight: 50,
                    ),
                  ]).animate(pulse),
            child: Container(
              key: const Key('guide-schedule-activity-dot'),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: LineupTheme.of(context).progressFill,
                shape: BoxShape.circle,
              ),
            ),
          ),
          SizedBox(width: 9),
          Text(label),
        ],
      ),
    ),
  );
}

class _NoMatchingChannels extends StatelessWidget {
  const _NoMatchingChannels({
    required this.filtered,
    this.onSetUpChannels,
    this.setupFocus,
  });

  final bool filtered;
  final VoidCallback? onSetUpChannels;
  final FocusNode? setupFocus;

  @override
  Widget build(BuildContext context) => Center(
    child: filtered
        ? const Text(
            'No matching channels\nTry another channel name or number.',
            textAlign: TextAlign.center,
          )
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'No channels yet',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Set up your channels to start watching.',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: LineupTheme.of(context).secondaryText),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  focusNode: setupFocus,
                  onPressed: onSetUpChannels,
                  child: const Text('Set up channels'),
                ),
              ],
            ),
          ),
  );
}

class _ProgramCell extends StatefulWidget {
  const _ProgramCell({
    required this.program,
    required this.focused,
    required this.selected,
    required this.current,
    required this.past,
    required this.left,
    required this.width,
    required this.onTap,
    required this.reduceMotion,
    this.onDoubleTap,
    this.nowOffset,
    super.key,
  });
  final GuideProgram program;
  final bool focused;
  final bool selected;
  final bool current;
  final bool past;
  final double left;
  final double width;
  final VoidCallback onTap;
  final bool reduceMotion;
  final VoidCallback? onDoubleTap;
  final double? nowOffset;

  @override
  State<_ProgramCell> createState() => _ProgramCellState();
}

class _ProgramCellState extends State<_ProgramCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final focusFill = roles.focusedText == roles.onFocus
        ? roles.focusedSurface
        : Color.alphaBlend(
            roles.focusBorder.withValues(alpha: 0.24),
            roles.primarySurface,
          );
    final fill = widget.focused
        ? focusFill
        : _hovered || widget.selected
        ? roles.elevatedSurface
        : widget.past
        ? roles.primarySurface.withValues(alpha: 0.56)
        : roles.primarySurface.withValues(alpha: 0.55);
    // Guide focus is deliberately fill-only, including Large focus indicators.
    final border = Border.all(color: Colors.transparent, width: 1);

    return Positioned(
      left: widget.left,
      width: widget.width.clamp(28, 2000),
      top: 0,
      bottom: 0,
      child: Padding(
        padding: EdgeInsets.zero,
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

                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  color: fill,
                  border: border,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: 1,
                      child: ColoredBox(color: roles.subtleBorder),
                    ),
                    if (widget.nowOffset case final x?
                        when x >= 0 && x < widget.width)
                      Positioned(
                        left:
                            x -
                            border.dimensions
                                .resolve(Directionality.of(context))
                                .left,
                        top: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: ColoredBox(
                            key: const Key('guide-cell-now-line'),
                            color: roles.liveAccent,
                            child: const SizedBox(width: 2),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 6,
                      ),
                      child: _ProgramCellContent(
                        program: widget.program,
                        focused: widget.focused,
                        current: widget.current,
                        past: widget.past,
                        reduceMotion: widget.reduceMotion,
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
        final double gap = 12.0;
        final scaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        final roles = LineupTheme.of(context);
        final titleStyle = LineupTypography.guideTitle.copyWith(
          color: focused
              ? roles.focusedText
              : past
              ? roles.mutedText
              : null,
        );
        final secondaryStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          height: 1.1,
          fontSize: 18.0,
          color: focused ? roles.focusedText : roles.mutedText,
        );
        final tagStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          height: 1.1,
          fontSize: 14.0,
          color: focused ? roles.focusedText : null,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
        );
        final time =
            '${_time(context, program.scheduled.start)}–${_time(context, program.scheduled.end)}';
        final liveWidth = current ? 7 + gap : 0.0;
        final titleWidth = _textWidth(
          primaryTitle,
          titleStyle,
          scaler,
          direction,
        );
        final tagWidth = episodeCode == null
            ? 0.0
            : _textWidth(episodeCode, tagStyle, scaler, direction);
        final showEpisode =
            episodeCode != null &&
            titleWidth + tagWidth + liveWidth + gap <= constraints.maxWidth;
        final subtitleWidth = episodeTitle == null
            ? 0.0
            : _textWidth(episodeTitle, secondaryStyle, scaler, direction);
        final timeWidth = _textWidth(time, secondaryStyle, scaler, direction);
        final showTime = episodeTitle == null
            ? timeWidth <= constraints.maxWidth
            : subtitleWidth + timeWidth + gap <= constraints.maxWidth;
        final showBottom =
            constraints.maxHeight >=
            _textHeight(titleStyle, scaler, direction) +
                _textHeight(secondaryStyle, scaler, direction);
        return ClipRect(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  if (current) ...[
                    Container(
                      key: const Key('guide-airing-dot'),
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: LineupTheme.of(context).liveAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: gap),
                  ],
                  Expanded(
                    child: FocusedTicker(
                      text: primaryTitle,
                      focused: focused,
                      reduceMotion: reduceMotion,
                      style: titleStyle,
                    ),
                  ),
                  if (showEpisode) ...[
                    SizedBox(width: gap),
                    Text(episodeCode, style: tagStyle),
                  ],
                ],
              ),
              if (showBottom && (episodeTitle != null || showTime))
                Row(
                  children: [
                    if (episodeTitle != null)
                      if (showTime)
                        SizedBox(
                          width: subtitleWidth,
                          child: FocusedTicker(
                            text: episodeTitle,
                            focused: focused,
                            reduceMotion: reduceMotion,
                            style: secondaryStyle,
                          ),
                        )
                      else
                        Expanded(
                          child: FocusedTicker(
                            text: episodeTitle,
                            focused: focused,
                            reduceMotion: reduceMotion,
                            style: secondaryStyle,
                          ),
                        ),
                    if (episodeTitle != null && showTime)
                      SizedBox(
                        width: gap,
                        child: Center(child: Text('·', style: secondaryStyle)),
                      ),
                    if (showTime)
                      Text(
                        time,
                        maxLines: 1,
                        style: secondaryStyle?.copyWith(
                          fontFeatures: const [ui.FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

double _textHeight(
  TextStyle? style,
  TextScaler scaler,
  TextDirection direction,
) {
  final painter = TextPainter(
    text: TextSpan(text: 'Ag', style: style),
    textDirection: direction,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final height = painter.height.ceilToDouble();
  painter.dispose();
  return height;
}

double _textWidth(
  String text,
  TextStyle? style,
  TextScaler scaler,
  TextDirection direction,
) {
  return TextPainter.computeWidth(
    text: TextSpan(text: text, style: style),
    textDirection: direction,
    textScaler: scaler,
    maxLines: 1,
  );
}

class _Details extends StatelessWidget {
  const _Details({
    required this.controller,
    required this.program,
    required this.backdrop,
    required this.clearLogo,
    required this.dynamicColor,
    required this.compactLogo,
    required this.playbackMessage,
  });
  final GuideProgram? program;
  final Uint8List? backdrop;
  final Uint8List? clearLogo;
  final Color? dynamicColor;
  final GuideController controller;
  final bool compactLogo;
  final String? playbackMessage;

  @override
  Widget build(BuildContext context) {
    final channel = controller.focusedChannel;
    final roles = LineupTheme.of(context);
    final bleedColor = dynamicColor ?? roles.progressFill;
    final settings = controller.lineup.settings;
    final backgroundMode = settings.guideInfoBackgroundMode;
    final backgroundGradient = switch (backgroundMode) {
      GuideInfoBackgroundMode.bleed => RadialGradient(
        center: const Alignment(0.52, -0.02),
        radius: 1.7,
        colors: [
          Color.alphaBlend(
            bleedColor.withValues(alpha: 0.65),
            roles.primarySurface,
          ),
          roles.primarySurface,
          roles.deepBackground,
        ],
        stops: const [0, 0.62, 1],
      ),
      GuideInfoBackgroundMode.themeDefault => LinearGradient(
        colors: [roles.primarySurface, roles.deepBackground],
      ),
      GuideInfoBackgroundMode.artwork => LinearGradient(
        colors: [roles.primarySurface, roles.deepBackground],
      ),
    };
    return ClipRect(
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
                backdrop != null) ...[
              Positioned.fill(
                child: Image.memory(
                  backdrop!,
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
              padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: program == null
                            ? _GuideDetailsPlaceholder(
                                controller: controller,
                                channel: channel,
                                playbackMessage: playbackMessage,
                              )
                            : _ProgramDetails(
                                program: program!,
                                channel: channel,
                                clearLogo: settings.preferClearLogos
                                    ? clearLogo
                                    : null,
                                compactLogo: compactLogo,
                                playbackMessage: playbackMessage,
                                now: controller.now,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideDetailsPlaceholder extends StatelessWidget {
  const _GuideDetailsPlaceholder({
    required this.controller,
    required this.channel,
    required this.playbackMessage,
  });

  final GuideController controller;
  final Channel? channel;
  final String? playbackMessage;

  @override
  Widget build(BuildContext context) {
    if (controller.channels.isEmpty && controller.lineup.channels.isNotEmpty) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'No matching channels\nTry another channel name or number.',
        ),
      );
    }
    final inspected = channel;
    if (inspected == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: controller.lineup.channels.isEmpty
            ? const SizedBox.shrink()
            : Text(playbackMessage ?? 'Move to a program for details.'),
      );
    }
    final data = controller.row(inspected.id);
    final status = switch (data.state) {
      GuideLoadState.loading => 'Loading schedule…',
      GuideLoadState.retrying => 'Retrying…',
      GuideLoadState.error => 'Schedule unavailable',
      GuideLoadState.ready => 'No programs scheduled in this time range',
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${inspected.number} • ${inspected.name}',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: LineupTheme.of(context).progressFill,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text(status),
        ],
      ),
    );
  }
}

class _ProgramDetails extends StatelessWidget {
  const _ProgramDetails({
    required this.program,
    required this.channel,
    required this.clearLogo,
    required this.compactLogo,
    required this.playbackMessage,
    required this.now,
  });
  final GuideProgram program;
  final Channel? channel;
  final Uint8List? clearLogo;
  final bool compactLogo;
  final String? playbackMessage;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final item = program.scheduled.item;
    final roles = LineupTheme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final enlarged = scaler.scale(1) > 1;
    // Keep a wrapping separator attached to the preceding metadata segment.
    final metadataSeparator = enlarged ? '\u00a0· ' : ' · ';
    final hasSynopsis = item.summary?.trim().isNotEmpty == true;
    final duration = program.scheduled.end.difference(program.scheduled.start);
    final elapsed = Duration(
      milliseconds: now
          .difference(program.scheduled.start)
          .inMilliseconds
          .clamp(0, math.max(0, duration.inMilliseconds)),
    );
    final remaining = _duration(duration - elapsed);
    final current = program.isCurrentAt(now);
    final past = !now.isBefore(program.scheduled.end);
    final metadataStyle = LineupTypography.body.copyWith(
      height: 1.2,
      color: roles.secondaryText,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );
    final bodyStyle = LineupTypography.body.copyWith(
      height: 1.3,
      color: roles.secondaryText,
    );
    final channelStyle = TextStyle(
      fontSize: 16,
      height: 1.2,
      color: roles.mutedText,
      fontWeight: FontWeight.w500,
    );
    final airing =
        '${_time(context, program.scheduled.start)}–${_time(context, program.scheduled.end)}';
    final timeLine = [
      airing,
      if (current) '$remaining left' else if (!past) _duration(item.duration),
    ].join(metadataSeparator);
    final factsLine = [
      if (item.year != null) '${item.year}',
      ...item.genres.take(3),
    ].join(metadataSeparator);
    final eyebrow = Text(
      channel == null ? '' : '${channel!.number} • ${channel!.name}',
      key: const Key('guide-info-channel'),
      style: channelStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final title = Text(
      item.showTitle ?? item.title,
      key: const Key('guide-clear-logo-fallback'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: LineupTypography.programTitle.copyWith(color: roles.primaryText),
    );
    final episode = [
      ?_episodeCode(item),
      if (item.showTitle != null) item.title,
    ].join(' · ');
    final badges = _mediaBadges(item);
    return LayoutBuilder(
      builder: (context, box) {
        // Keep the existing type hierarchy. Compact spacing releases height to
        // the facts before constraining the synopsis, including enlarged text.
        final dense = box.maxHeight < 270 || enlarged;
        final mergeFacts = dense && !enlarged;
        final gap = dense ? 4.0 : 10.0;
        final logoHeight = compactLogo || dense ? 42.0 : 64.0;
        final identityFlex = box.maxHeight < 220
            ? 6
            : compactLogo || dense
            ? 5
            : 4;
        final identity = Column(
          key: const Key('guide-program-identity'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            eyebrow,
            SizedBox(height: gap),
            if (clearLogo != null)
              SizedBox(
                height: logoHeight,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: compactLogo || dense ? 280 : 420,
                  ),
                  child: ClearLogoImage(
                    clearLogo!,
                    imageKey: const Key('guide-clear-logo'),
                    fallback: title,
                    semanticLabel: '${item.showTitle ?? item.title} logo',
                  ),
                ),
              )
            else
              title,
            if (episode.isNotEmpty) ...[
              SizedBox(height: gap),
              Text(
                episode,
                key: const Key('guide-info-episode'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 22,
                  height: 1.2,
                  color: roles.secondaryText,
                ),
              ),
            ],
            SizedBox(height: gap),
            Text(
              mergeFacts && factsLine.isNotEmpty
                  ? '$timeLine · $factsLine'
                  : timeLine,
              key: const Key('guide-program-meta'),
              style: metadataStyle,
            ),
            if (!mergeFacts && factsLine.isNotEmpty) ...[
              SizedBox(height: gap),
              Text(
                factsLine,
                key: const Key('guide-info-genres'),
                style: metadataStyle,
              ),
            ],
            if (badges.isNotEmpty) ...[
              SizedBox(height: gap),
              Wrap(
                key: const Key('guide-program-badges'),
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final badge in badges) _GuideMediaBadge(label: badge),
                ],
              ),
            ],
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: hasSynopsis ? identityFlex : 1,
                    child: SingleChildScrollView(child: identity),
                  ),
                  if (hasSynopsis) ...[
                    const SizedBox(width: 32),
                    Expanded(
                      flex: 10 - identityFlex,
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: _lineHeight(context, channelStyle) + gap,
                        ),
                        child: LayoutBuilder(
                          builder: (context, synopsisBox) {
                            final lineHeight = _lineHeight(context, bodyStyle);
                            final lines = math.max(
                              1,
                              (synopsisBox.maxHeight / lineHeight).floor(),
                            );
                            return Text(
                              item.summary!,
                              key: const Key('guide-program-synopsis'),
                              maxLines: lines,
                              overflow: TextOverflow.ellipsis,
                              style: bodyStyle,
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (current) ...[
              SizedBox(height: gap),
              Semantics(
                label: '${_duration(elapsed)} elapsed, $remaining remaining',
                child: LinearProgressIndicator(
                  key: const Key('guide-program-progress'),
                  value: duration.inMilliseconds <= 0
                      ? 0
                      : elapsed.inMilliseconds / duration.inMilliseconds,
                  minHeight: 4,
                ),
              ),
            ],
            if (playbackMessage != null)
              Text(
                playbackMessage!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: metadataStyle,
              ),
          ],
        );
      },
    );
  }

  double _lineHeight(BuildContext context, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(
        text: 'Ag',
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }
}

class _GuideMediaBadge extends StatelessWidget {
  const _GuideMediaBadge({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: roles.elevatedSurface.withValues(alpha: .82),
        border: Border.all(color: roles.subtleBorder),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(label, style: Theme.of(context).textTheme.labelMedium),
      ),
    );
  }
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

String _time(BuildContext context, DateTime value) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(value.toLocal()),
      alwaysUse24HourFormat: false,
    );

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
