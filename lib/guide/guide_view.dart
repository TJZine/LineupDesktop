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
  });

  factory GuideLayoutPolicy.forSize(
    Size size, {
    required bool hasPicture,
    double textScale = 1,
  }) {
    final width = size.width.isFinite ? size.width.clamp(0, 10000) : 0.0;
    final height = size.height.isFinite ? size.height.clamp(0, 10000) : 0.0;
    final scale = LineupLayout.scaleFor(size);
    final compact = width < LineupLayout.expandedNavigation || height < 900;
    final padding =
        (width < LineupLayout.expandedNavigation || height < 720
            ? 12.0
            : 20.0) *
        scale;
    const minimumRows = 5;
    final targetPictureHeight = height * 0.3;
    final chromeHeight =
        padding * 2 + (56 + 2 + 8 + 56 + 38 * textScale.clamp(1, 2)) * scale;
    final availableShowcaseHeight = (height - chromeHeight - 56).clamp(
      0.0,
      double.infinity,
    );
    var showcaseHeight = targetPictureHeight.clamp(
      0.0,
      availableShowcaseHeight,
    );
    var pictureWidth = showcaseHeight * 16 / 9;
    if (hasPicture) {
      final minimumDetailsWidth = compact ? 300.0 : 360.0;
      final widthBudget = width - padding * 2 - 12 - minimumDetailsWidth;
      pictureWidth = pictureWidth.clamp(0.0, widthBudget.clamp(0.0, 2000.0));
      showcaseHeight = pictureWidth * 9 / 16;
    }
    final rowHeight = ((height - chromeHeight - showcaseHeight) / 5)
        .clamp(58 * scale * textScale.clamp(1, 2), double.infinity)
        .toDouble();
    return GuideLayoutPolicy._(
      compact: compact,
      padding: padding,
      channelRailWidth:
          (compact ? 176 : (width >= 1800 ? 260 : 208)) *
          scale *
          textScale.clamp(1, 1.5),
      showcaseHeight: showcaseHeight,
      pictureWidth: pictureWidth,
      rowHeight: rowHeight,
      minimumRows: minimumRows,
      showSecondaryMetadata: showcaseHeight >= 180 * textScale.clamp(1, 2),
      showSummary: showcaseHeight >= 210 * textScale.clamp(1, 2),
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
}

class GuideView extends StatefulWidget {
  const GuideView({
    required this.controller,
    required this.onClose,
    required this.onTune,
    this.onOpenMenu,
    this.pictureInPicture,
    this.onOpenPlayer,
    this.playbackMessage,
    this.focusNode,
    super.key,
  });

  final GuideController controller;
  final VoidCallback onClose;
  final Future<void> Function(String channelId) onTune;
  final LineupMenuCallback? onOpenMenu;
  final Widget? pictureInPicture;
  final VoidCallback? onOpenPlayer;
  final String? playbackMessage;
  final FocusNode? focusNode;

  @override
  State<GuideView> createState() => _GuideViewState();
}

class _GuideViewState extends State<GuideView>
    with SingleTickerProviderStateMixin {
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
      ?..removeListener(_requestViewport)
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
    _syncActivityPulse();
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
    menuFocus: _menuFocus,
  );

  Widget _showcase(GuideLayoutPolicy policy) => SizedBox(
    height: policy.showcaseHeight,
    child: _GuideShowcase(
      controller: widget.controller,
      picture: widget.pictureInPicture,
      pictureWidth: policy.pictureWidth,
      compact: policy.compact,
      showSecondaryMetadata: policy.showSecondaryMetadata,
      showSummary: policy.showSummary,
      playbackMessage: widget.playbackMessage,
      onOpenPlayer: widget.onOpenPlayer,
    ),
  );

  Widget _schedule(GuideLayoutPolicy policy, List<Channel> channels) {
    final scroll = _scrollFor(policy.rowHeight);
    return Column(
      children: [
        _GuideControls(
          controller: widget.controller,
          railWidth: policy.channelRailWidth,
          searchController: _searchController,
          searchFocus: _searchFocus,
          onSearchKey: _searchKey,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final now = widget.controller.now;
              _visibleRows = GuideGeometry.visibleRows(
                scrollOffset: scroll.hasClients ? scroll.offset : 0,
                viewportHeight: constraints.maxHeight,
                rowHeight: policy.rowHeight,
                totalRows: channels.length,
              ).count;
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _requestViewport(),
              );
              final timelineWidth =
                  constraints.maxWidth - policy.channelRailWidth - 4;
              final fraction =
                  now.difference(widget.controller.windowStart).inMicroseconds /
                  widget.controller.windowEnd
                      .difference(widget.controller.windowStart)
                      .inMicroseconds;
              return Stack(
                children: [
                  Column(
                    children: [
                      _TimeHeader(
                        controller: widget.controller,
                        railWidth: policy.channelRailWidth,
                      ),
                      Expanded(
                        child: channels.isEmpty
                            ? _NoMatchingChannels(
                                filtered: widget
                                    .controller
                                    .lineup
                                    .channels
                                    .isNotEmpty,
                              )
                            : ListView.builder(
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
                                  now: now,
                                  activityPulse: _activityPulse,
                                ),
                              ),
                      ),
                    ],
                  ),
                  if (fraction >= 0 && fraction < 1)
                    Positioned(
                      left:
                          policy.channelRailWidth +
                          4 +
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
            );
            final schedule = _schedule(policy, channels);
            final scaledTheme = Theme.of(context).copyWith(
              textTheme: Theme.of(context).textTheme
                  .apply(fontSizeFactor: LineupLayout.scaleFor(outer.biggest)),
            );
            return Theme(
              data: scaledTheme,
              child: DefaultTextStyle(
                style: scaledTheme.textTheme.bodyMedium!,
                child: _ClassicGuideSurface(
                  color: roles.deepBackground,
                  padding: policy.padding,
                  showcaseHeight: policy.showcaseHeight,
                  toolbar: _toolbar(policy),
                  showcase: _showcase(policy),
                  body: schedule,
                ),
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
        child: const SizedBox(width: double.infinity, height: 2),
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
    required this.menuFocus,
  });
  final GuideController controller;
  final VoidCallback onClose;
  final LineupMenuCallback? onOpenMenu;
  final FocusNode menuFocus;

  @override
  Widget build(BuildContext context) {
    final now = controller.now.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final tunedChannel = controller.lineup.channels
        .where((channel) => channel.id == controller.lineup.currentChannelId)
        .firstOrNull;
    final tunedProgram = tunedChannel == null
        ? null
        : controller.currentProgram(tunedChannel.id);
    final showPlaying =
        tunedChannel != null && controller.lineup.settings.nowWatchingBanner;
    final showDate = MediaQuery.sizeOf(context).width >= 1100;
    return SizedBox(
      height: 56 * LineupLayout.scaleFor(MediaQuery.sizeOf(context)),
      child: Row(
        children: [
          if (onOpenMenu != null)
            Builder(
              builder: (invokerContext) => Tooltip(
                message: 'Open Lineup menu',
                child: TextButton.icon(
                  key: const Key('guide-app-menu'),
                  focusNode: menuFocus,
                  onPressed: () => onOpenMenu!(invokerContext, menuFocus),
                  icon: const Icon(Icons.menu, size: 19),
                  label: const Text('LINEUP'),
                ),
              ),
            )
          else
            Text(
              'LINEUP',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.8),
            ),
          const SizedBox(width: 20),
          Text('Guide', style: Theme.of(context).textTheme.bodyMedium),
          if (showPlaying) ...[
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                '${tunedChannel.number} · ${tunedChannel.name}${tunedProgram == null ? '' : ' — ${tunedProgram.scheduled.item.title}'}',
                key: const Key('guide-now-playing-context'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ] else
            const Spacer(),
          if (showDate)
            Text(
              '${localizations.formatMediumDate(now)}  ·  ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(now))}',
              key: const Key('guide-current-date-time'),
              maxLines: 1,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: LineupTheme.of(context).mutedText),
            ),
          const SizedBox(width: 8),
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

class _GuideControls extends StatelessWidget {
  const _GuideControls({
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
    final libraryIds = controller.availableLibraryIds.toList()..sort();
    final selectedLibrary = controller.libraryFilterId;
    final selectedLibraryName = selectedLibrary == null
        ? null
        : _libraryName(controller, selectedLibrary);
    final picker = SizedBox(
      width: railWidth,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          key: const Key('guide-library-picker'),
          isExpanded: true,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          value: selectedLibrary,
          hint: Text(selectedLibrary == null ? 'All libraries' : 'Libraries'),
          selectedItemBuilder: (context) => [
            const Text('All libraries'),
            for (final _ in libraryIds) const Text('Libraries'),
          ],
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
                  softWrap: true,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: LineupTheme.of(context).mutedText),
                ),
              ),
              IconButton(
                tooltip: 'Remove library filter',
                onPressed: () => controller.setLibraryFilter(null),
                icon: const Icon(Icons.close, size: 17),
              ),
            ],
          );
    Widget search(double width) => SizedBox(
      width: width,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: searchController,
        builder: (context, value, child) => Focus(
          onKeyEvent: onSearchKey,
          child: TextField(
            key: const Key('guide-channel-search'),
            controller: searchController,
            focusNode: searchFocus,
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Search channels',
              hintText: 'Channel name or number',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: value.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: searchController.clear,
                      icon: const Icon(Icons.close, size: 17),
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
          icon: const Icon(Icons.chevron_left),
        ),
        TextButton(onPressed: controller.playToNow, child: const Text('Now')),
        IconButton(
          key: const Key('guide-later'),
          tooltip: 'Later by 30 minutes',
          onPressed: () => controller.moveWindow(1),
          icon: const Icon(Icons.chevron_right),
        ),
        const SizedBox(width: 8),
        DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            key: const Key('guide-hours'),
            value:
                LineupSettings.guideHoursOptions.contains(controller.guideHours)
                ? controller.guideHours
                : null,
            hint: const Text('Hours'),
            items: [
              for (final hours in LineupSettings.guideHoursOptions)
                DropdownMenuItem(value: hours, child: Text('$hours hours')),
            ],
            onChanged: (hours) {
              if (hours != null) unawaited(controller.setGuideHours(hours));
            },
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <
            1000 * MediaQuery.textScalerOf(context).scale(1)) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  picker,
                  const SizedBox(width: 8),
                  Expanded(child: label),
                ],
              ),
              Row(
                children: [
                  Expanded(child: search(double.infinity)),
                  const SizedBox(width: 8),
                  navigation,
                ],
              ),
            ],
          );
        }
        return ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: 56 * LineupLayout.scaleFor(MediaQuery.sizeOf(context)),
          ),
          child: Row(
            children: [
              picker,
              const SizedBox(width: 8),
              Expanded(child: label),
              search(260),
              const SizedBox(width: 8),
              navigation,
            ],
          ),
        );
      },
    );
  }
}

class _GuideShowcase extends StatelessWidget {
  const _GuideShowcase({
    required this.controller,
    required this.picture,
    required this.pictureWidth,
    required this.compact,
    required this.showSecondaryMetadata,
    required this.showSummary,
    required this.playbackMessage,
    required this.onOpenPlayer,
  });

  final GuideController controller;
  final Widget? picture;
  final double pictureWidth;
  final bool compact;
  final bool showSecondaryMetadata;
  final bool showSummary;
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
            compact: compact,
            showSecondaryMetadata: showSecondaryMetadata,
            showSummary: showSummary,
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
    final headerHeight =
        38 *
        LineupLayout.scaleFor(MediaQuery.sizeOf(context)) *
        MediaQuery.textScalerOf(context).scale(1);
    if (slots <= 0) return SizedBox(height: headerHeight);
    return SizedBox(
      height: headerHeight,
      child: Row(
        children: [
          SizedBox(
            width: railWidth,
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
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
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                if (!width.isFinite || width < 2) {
                  return const SizedBox.shrink();
                }
                final slotWidth = width / slots;
                final stride = (68 / slotWidth).ceil().clamp(1, slots);
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
                                  ? Padding(
                                      padding: const EdgeInsets.only(left: 12),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Builder(
                                          builder: (context) {
                                            final tick = controller.windowStart
                                                .add(
                                                  Duration(minutes: 30 * index),
                                                );
                                            final midnight =
                                                tick.hour == 0 &&
                                                tick.minute == 0;
                                            return Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  _time(context, tick),
                                                  overflow: TextOverflow.clip,
                                                  maxLines: 1,
                                                ),
                                                if (midnight)
                                                  Text(
                                                    MaterialLocalizations.of(
                                                      context,
                                                    ).formatMediumDate(
                                                      tick.toLocal(),
                                                    ),
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
    required this.now,
    required this.activityPulse,
  });
  final Channel channel;
  final GuideController controller;
  final double railWidth;
  final bool showProvenance;
  final Future<void> Function(String channelId) onTune;
  final DateTime now;
  final Animation<double> activityPulse;

  @override
  Widget build(BuildContext context) {
    final focusedChannel = channel.id == controller.focusedChannelId;
    final focusChannelRail =
        focusedChannel && controller.focusedProgram == null;
    final selectedChannel = channel.id == controller.selectedChannelId;
    final tunedChannel = controller.lineup.currentChannelId == channel.id;
    final data = controller.row(channel.id);
    void focusCurrentProgram() {
      final current = controller.currentProgram(channel.id);
      if (current != null) controller.focusProgram(current);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
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
                  border: Border(
                    left: BorderSide(
                      color: focusChannelRail
                          ? LineupTheme.of(context).focusBorder
                          : Colors.transparent,
                      width: focusChannelRail
                          ? LineupTheme.of(context).focusBorderWidth
                          : 1,
                    ),
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
                          color: LineupTheme.of(context).progressFill,
                          fontSize:
                              (showProvenance ? 18 : 16) *
                              LineupLayout.scaleFor(MediaQuery.sizeOf(context)),
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [ui.FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final nameStyle = DefaultTextStyle.of(context).style
                              .copyWith(fontWeight: FontWeight.w600);
                          final painter = TextPainter(
                            text: TextSpan(
                              text: channel.name,
                              style: nameStyle,
                            ),
                            textDirection: Directionality.of(context),
                            textScaler: MediaQuery.textScalerOf(context),
                          )..layout(maxWidth: constraints.maxWidth);
                          final nameHeight = painter.height;
                          final lineHeight = painter
                              .computeLineMetrics()
                              .first
                              .height;
                          final availableLines =
                              (constraints.maxHeight / lineHeight)
                                  .floor()
                                  .clamp(1, 1000);
                          painter.dispose();
                          final provenanceStyle = Theme.of(context)
                              .textTheme
                              .labelSmall;
                          final provenanceHeight =
                              MediaQuery.textScalerOf(context)
                                  .scale(provenanceStyle?.fontSize ?? 12) *
                              (provenanceStyle?.height ?? 1.4);
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
                              if (showProvenance &&
                                  nameHeight + provenanceHeight <=
                                      constraints.maxHeight)
                                Text(
                                  _channelProvenance(controller, channel),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: provenanceStyle?.copyWith(
                                    color: LineupTheme.of(context).mutedText,
                                  ),
                                ),
                            ],
                          );
                        },
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
          const SizedBox(width: 1),
          Expanded(
            child: _Programs(
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
            const Text('Schedule unavailable'),
            const SizedBox(width: 8),
            TextButton(
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
          const SizedBox(width: 9),
          Text(label),
        ],
      ),
    ),
  );
}

class _NoMatchingChannels extends StatelessWidget {
  const _NoMatchingChannels({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      label: filtered ? 'No matching channels' : 'Guide has no channels',
      child: Text(
        filtered
            ? 'No matching channels\nTry another channel name or number.'
            : 'Create a channel to build your Guide',
        textAlign: TextAlign.center,
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
      padding: const EdgeInsets.only(right: 1),
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
                    ? LineupTheme.of(context).elevatedSurface
                    : widget.past
                    ? LineupTheme.of(context).primarySurface
                          .withValues(alpha: 0.56)
                    : widget.selected
                    ? LineupTheme.of(context).selectedSurface
                    : _hovered
                    ? LineupTheme.of(context).elevatedSurface
                    : LineupTheme.of(context).primarySurface
                          .withValues(alpha: 0.55),
                border: Border(
                  left: BorderSide(
                    color: widget.focused
                        ? LineupTheme.of(context).focusBorder
                        : widget.selected
                        ? LineupTheme.of(context).defaultBorder
                        : Colors.transparent,
                    width: widget.focused
                        ? LineupTheme.of(context).focusBorderWidth
                        : widget.selected
                        ? 2
                        : 1,
                  ),
                  bottom: BorderSide(
                    color: LineupTheme.of(context).subtleBorder,
                  ),
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
        final scaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        final titleStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: past ? LineupTheme.of(context).mutedText : null,
          fontWeight: FontWeight.w600,
        );
        final secondaryStyle = Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: LineupTheme.of(context).mutedText);
        final tagStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 10 * LineupLayout.scaleFor(MediaQuery.sizeOf(context)),
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        );
        final time =
            '${_time(context, program.scheduled.start)}–${_time(context, program.scheduled.end)}';
        final liveWidth = current ? 19.0 : 0.0;
        final titleWidth = _textWidth(
          primaryTitle,
          titleStyle,
          scaler,
          direction,
        );
        final tagWidth = episodeCode == null
            ? 0.0
            : _textWidth(episodeCode, tagStyle, scaler, direction) + 12;
        final showEpisode =
            episodeCode != null &&
            titleWidth + tagWidth + liveWidth + 12 <= constraints.maxWidth;
        final subtitleWidth = episodeTitle == null
            ? 0.0
            : _textWidth(episodeTitle, secondaryStyle, scaler, direction);
        final timeWidth = _textWidth(time, secondaryStyle, scaler, direction);
        final showTime = episodeTitle == null
            ? timeWidth <= constraints.maxWidth
            : subtitleWidth + timeWidth + 12 <= constraints.maxWidth;
        final showBottom = constraints.maxHeight >= scaler.scale(36);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Expanded(
                  child: FocusedTicker(
                    text: primaryTitle,
                    focused: focused,
                    reduceMotion: reduceMotion,
                    style: titleStyle,
                  ),
                ),
                if (showEpisode) ...[
                  const SizedBox(width: 12),
                  _CellEpisodeTag(episodeCode),
                ],
                if (current) ...[
                  const SizedBox(width: 12),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: LineupTheme.of(context).liveAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
            if (showBottom && (episodeTitle != null || showTime))
              Row(
                children: [
                  if (episodeTitle != null)
                    Expanded(
                      child: FocusedTicker(
                        text: episodeTitle,
                        focused: focused,
                        reduceMotion: reduceMotion,
                        style: secondaryStyle,
                      ),
                    ),
                  if (episodeTitle != null && showTime)
                    const SizedBox(width: 12),
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
        );
      },
    );
  }
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
        fontSize: 10 * LineupLayout.scaleFor(MediaQuery.sizeOf(context)),
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
    required this.showSecondaryMetadata,
    required this.showSummary,
    required this.playbackMessage,
  });
  final GuideController controller;
  final bool compact;
  final bool showSecondaryMetadata;
  final bool showSummary;
  final String? playbackMessage;

  @override
  State<_Details> createState() => _DetailsState();
}

class _DetailsState extends State<_Details> {
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
        : '${program.id}|${widget.controller.lineup.contentGeneration}|${item?.showThumb}|${item?.poster}|${item?.backdrop}|${item?.clearLogo}|${settings.guideInfoBackgroundMode.name}|${settings.preferClearLogos}';
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
    final channel = program == null
        ? controller.focusedChannel
        : controller.lineup.channels
              .where((channel) => channel.id == program.channelId)
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
                horizontal: widget.compact ? 14 : 20,
                vertical: widget.compact ? 10 : 14,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: program == null
                        ? _GuideDetailsPlaceholder(
                            controller: controller,
                            channel: channel,
                            playbackMessage: widget.playbackMessage,
                          )
                        : _ProgramDetails(
                            program: program,
                            channel: channel,
                            clearLogo: settings.preferClearLogos
                                ? _clearLogo
                                : null,
                            showSecondaryMetadata: widget.showSecondaryMetadata,
                            showSummary: widget.showSummary,
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
        child: Text(playbackMessage ?? 'Move to a program for details.'),
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
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
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
    required this.showSecondaryMetadata,
    required this.showSummary,
    required this.playbackMessage,
    required this.now,
  });

  final GuideProgram program;
  final Channel? channel;
  final Uint8List? clearLogo;
  final bool showSecondaryMetadata;
  final bool showSummary;
  final String? playbackMessage;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final item = program.scheduled.item;
    final episode = _episodeCode(item);
    final badges = _mediaBadges(item);
    final hasClearLogo = clearLogo != null;
    final scheduledDuration = program.scheduled.end.difference(
      program.scheduled.start,
    );
    final elapsedValue = now.difference(program.scheduled.start);
    final elapsed = elapsedValue.isNegative
        ? Duration.zero
        : elapsedValue > scheduledDuration
        ? scheduledDuration
        : elapsedValue;
    final progress = scheduledDuration.inMilliseconds <= 0
        ? 0.0
        : elapsed.inMilliseconds / scheduledDuration.inMilliseconds;
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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: showSecondaryMetadata
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              if (channel != null)
                Text(
                  '${channel!.number} • ${channel!.name}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: LineupTheme.of(context).progressFill,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
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
                    child: ClearLogoImage(
                      clearLogo!,
                      imageKey: const Key('guide-clear-logo'),
                      fallback: logoFallback,
                      semanticLabel: '${item.showTitle ?? item.title} logo',
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
                              ? Theme.of(context).textTheme.headlineMedium
                              : Theme.of(context).textTheme.headlineSmall)
                          ?.copyWith(fontWeight: FontWeight.w800),
                ),
              if (episode != null)
                Text(
                  episode,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  [
                    '${_time(context, program.scheduled.start)}–${_time(context, program.scheduled.end)}',
                    _duration(item.duration),
                    if (item.year != null) '${item.year}',
                    program.isCurrentAt(now)
                        ? 'Airing now'
                        : program.scheduled.end.isBefore(now)
                        ? 'Ended'
                        : 'Upcoming',
                  ].join('  ·  '),
                  key: const Key('guide-program-meta'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: LineupTheme.of(context).mutedText,
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                  ),
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
                  child: Text(
                    badges.join('  ·  '),
                    key: const Key('guide-program-badges'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: LineupTheme.of(context).mutedText),
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
              if (program.isCurrentAt(now)) ...[
                const SizedBox(height: 7),
                Semantics(
                  label:
                      '${_duration(elapsed)} elapsed, ${_duration(scheduledDuration - elapsed)} remaining',
                  child: LinearProgressIndicator(
                    key: const Key('guide-program-progress'),
                    value: progress,
                    minHeight: 3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_duration(elapsed)} elapsed  ·  ${_duration(scheduledDuration - elapsed)} remaining',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: LineupTheme.of(context).mutedText),
                ),
              ],
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
