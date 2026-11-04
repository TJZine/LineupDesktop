part of 'guide_view.dart';

class _HandheldGuideHeader extends StatelessWidget {
  const _HandheldGuideHeader({
    required this.onNow,
    required this.onFilter,
    required this.onSearch,
    required this.library,
    required this.query,
  });

  final VoidCallback onNow;
  final VoidCallback onFilter;
  final VoidCallback onSearch;
  final String? library;
  final String query;

  @override
  Widget build(BuildContext context) {
    final extent = math.max(54.0, LineupCanvas.minimumTouchExtentOf(context));
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 8, 10),
        child: Row(
          children: [
            Image.asset('assets/branding/lineup-logo-mark.png', height: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Guide',
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: LineupTypography.title(
                  30,
                  92,
                ).copyWith(color: LineupTheme.of(context).primaryText),
              ),
            ),
            LineupTouchTarget(
              onPressed: onNow,
              child: TextButton(
                key: const Key('handheld-guide-now'),
                onPressed: onNow,
                child: const Text('Now'),
              ),
            ),
            _headerIcon(
              extent,
              'Filter by library',
              Icons.tune,
              onFilter,
              library,
            ),
            _headerIcon(
              extent,
              'Search channels',
              Icons.search,
              onSearch,
              query.isEmpty ? null : query,
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerIcon(
    double extent,
    String label,
    IconData icon,
    VoidCallback onPressed,
    String? value,
  ) => _HandheldGuideIcon(
    extent: extent,
    label: value == null ? label : '$label: $value',
    active: value != null,
    icon: icon,
    onPressed: onPressed,
  );
}

class _HandheldGuideIcon extends StatelessWidget {
  const _HandheldGuideIcon({
    required this.extent,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.active = false,
  });

  final double extent;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    excludeFromSemantics: true,
    child: IconButton(
      constraints: BoxConstraints.tightFor(
        width: active ? 64 : extent,
        height: extent,
      ),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        minimumSize: Size.square(extent),
        visualDensity: VisualDensity.standard,
      ),
      onPressed: onPressed,
      icon: active
          ? Container(
              width: 64,
              height: 32,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: LineupTheme.of(context).selectedSurface,
                shape: const StadiumBorder(),
              ),
              child: Icon(icon, size: 26, semanticLabel: label),
            )
          : Icon(icon, size: 26, semanticLabel: label),
    ),
  );
}

Future<void> _openHandheldLibraryFilter(
  BuildContext context,
  GuideController controller,
) async {
  final libraryIds = controller.availableLibraryIds.toList()..sort();
  // The record distinguishes selecting All libraries from dismissing.
  final result = await showHandheldChoiceSheet<({String? libraryId})>(
    context,
    title: 'Filter by library',
    selected: (libraryId: controller.libraryFilterId),
    choices: [
      const HandheldChoice(value: (libraryId: null), label: 'All libraries'),
      for (final id in libraryIds)
        HandheldChoice(
          value: (libraryId: id),
          label: _libraryName(controller, id),
        ),
    ],
  );
  if (context.mounted && result != null) {
    controller.setLibraryFilter(result.libraryId);
  }
}

Future<void> _openHandheldChannelSearch(
  BuildContext context,
  TextEditingController controller,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  backgroundColor: LineupTheme.of(context).elevatedSurface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  ),
  builder: (context) {
    void close() => Navigator.of(context).pop();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _GuideSearchDragHandle(),
              Semantics(
                header: true,
                child: Text(
                  'Search channels',
                  style: LineupTypography.title(
                    24,
                    90,
                  ).copyWith(color: LineupTheme.of(context).primaryText),
                ),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => TextField(
                  key: const Key('guide-channel-search'),
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => close(),
                  decoration: InputDecoration(
                    hintText: 'Channel name or number',
                    constraints: BoxConstraints(
                      minHeight: LineupCanvas.minimumTouchExtentOf(context),
                    ),
                    suffixIcon: value.text.isEmpty
                        ? null
                        : _HandheldGuideIcon(
                            extent: LineupCanvas.minimumTouchExtentOf(context),
                            label: 'Clear search',
                            icon: Icons.close,
                            onPressed: controller.clear,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: LineupTouchTarget(
                  onPressed: close,
                  child: TextButton(
                    onPressed: close,
                    child: const Text('Done'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  },
);

class _GuideSearchDragHandle extends StatelessWidget {
  const _GuideSearchDragHandle();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: Center(
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color:
              Theme.of(context).bottomSheetTheme.dragHandleColor ??
              Theme.of(context).colorScheme.onSurfaceVariant,
          shape: const StadiumBorder(),
        ),
        child: const SizedBox(width: 32, height: 4),
      ),
    ),
  );
}

const _handheldTimelineStorageKey = 'handheld-guide-timeline-start';

extension _PortraitGuideLayout on _GuideViewState {
  void _setHandheldTimelineStart(DateTime? start) {
    if (_handheldTimelineStart.value == start) return;
    _handheldTimelineStart.value = start;
    PageStorage.maybeOf(context)?.writeState(context, (
      widget.controller,
      widget.controller.lineup.contentGeneration,
      start,
    ), identifier: _handheldTimelineStorageKey);
  }

  void _returnToNow() {
    _setHandheldTimelineStart(null);
    widget.controller.playToNow();
  }

  Widget _buildHandheldGuide(BuildContext context, bool compositionChanged) {
    final controller = widget.controller;
    final channels = controller.channels;
    final phone = LineupCanvas.windowSizeOf(context).shortestSide < 600;
    final rowScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3);
    final rowHeight = (phone ? 84 : 80) * rowScale;
    final scroll = _scrollFor(
      rowHeight,
      compositionChanged: compositionChanged,
    );
    final watchingChannel = controller.lineup.channels
        .where((channel) => channel.id == widget.watchingChannelId)
        .firstOrNull;
    final picture = widget.pictureInPicture;
    final openPlayer = widget.onOpenPlayer;
    final library = controller.libraryFilterId;
    final rulerHeight = 32 * rowScale;
    return _HandheldGuideFrame(
      reservedScheduleHeight: rulerHeight + 2 * rowHeight,
      minimumPictureHeight: LineupCanvas.minimumTouchExtentOf(context),
      header: ColoredBox(
        color: LineupTheme.of(context).deepBackground,
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _searchController,
          builder: (context, value, _) => _HandheldGuideHeader(
            onNow: _returnToNow,
            onFilter: () => _openHandheldLibraryFilter(context, controller),
            onSearch: () =>
                _openHandheldChannelSearch(context, _searchController),
            library: library == null ? null : _libraryName(controller, library),
            query: controller.searchQuery.isEmpty ? '' : value.text.trim(),
          ),
        ),
      ),
      picture: picture == null || openPlayer == null
          ? null
          : _HandheldGuideAction(
              key: const Key('guide-picture-in-picture'),
              label: 'Now playing picture in picture. Open full player.',
              onTap: openPlayer,
              child: picture,
            ),
      strip: picture == null || openPlayer == null
          ? null
          : ValueListenableBuilder<DateTime>(
              valueListenable: _presentationClock,
              builder: (context, _, _) => _HandheldNowStrip(
                controller: controller,
                channel: watchingChannel,
                program: watchingChannel == null
                    ? null
                    : controller.currentProgram(watchingChannel.id),
                onOpenPlayer: openPlayer,
              ),
            ),
      schedule: ColoredBox(
        color: LineupTheme.of(context).deepBackground,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final rows = GuideGeometry.visibleRows(
              scrollOffset: scroll.hasClients ? scroll.offset : 0,
              viewportHeight: constraints.maxHeight - rulerHeight,
              rowHeight: rowHeight,
              totalRows: channels.length,
            );
            _visibleRows = rows.count;
            _scheduleViewportRequest();
            _allVisibleFailed =
                channels.isNotEmpty &&
                channels.every(
                  (channel) =>
                      controller.row(channel.id).state == GuideLoadState.error,
                );
            return _HandheldGuideTimeline(
              controller: controller,
              clock: _presentationClock,
              timelineStart: _handheldTimelineStart,
              onTimelineStartChanged: _setHandheldTimelineStart,
              railWidth: phone ? 100 : 120,
              phone: phone,
              rowHeight: rowHeight,
              rulerHeight: rulerHeight,
              scroll: scroll,
              watchingChannelId: widget.watchingChannelId,
              allFailed: _allVisibleFailed,
              retryFocus: _retryFocus,
              setupFocus: _setupFocus,
              onSetUpChannels: widget.onSetUpChannels,
              onTune: widget.onTune,
              onProgramTap: (channel, program) =>
                  _handleHandheldProgramTap(context, channel, program),
              onProgramDetails: (channel, program) =>
                  _showHandheldProgram(context, channel, program),
            );
          },
        ),
      ),
    );
  }

  void _handleHandheldProgramTap(
    BuildContext context,
    Channel channel,
    GuideProgram program,
  ) {
    final controller = widget.controller;
    final now = controller.now;
    if (program.isCurrentAt(now) &&
        controller.currentProgram(channel.id, now)?.id == program.id) {
      controller.selectProgram(program);
      unawaited(widget.onTune(channel.id));
    } else {
      _showHandheldProgram(context, channel, program);
    }
  }

  void _showHandheldProgram(
    BuildContext context,
    Channel channel,
    GuideProgram program,
  ) {
    final controller = widget.controller;
    controller.focusProgram(program);
    final generation = controller.lineup.contentGeneration;
    final poster = controller.artworkFor(program);
    final color = poster.then(
      (bytes) => bytes == null ? null : _artworkColor(bytes),
    );
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .9,
        ),
        builder: (context) => ListenableBuilder(
          listenable: Listenable.merge([controller, _presentationClock]),
          builder: (context, _) {
            final now = controller.now;
            final current = controller.currentProgram(channel.id, now);
            final canWatch =
                generation == controller.lineup.contentGeneration &&
                current != null &&
                program.scheduled.end.isAfter(now);
            return _HandheldProgramSheet(
              channel: channel,
              program: program,
              now: now,
              poster: poster,
              color: color,
              onWatch: !canWatch
                  ? null
                  : () {
                      final pressedAt = controller.now;
                      if (generation != controller.lineup.contentGeneration ||
                          !program.scheduled.end.isAfter(pressedAt)) {
                        return;
                      }
                      final airing = controller.currentProgram(
                        channel.id,
                        pressedAt,
                      );
                      if (airing == null || !airing.isCurrentAt(pressedAt)) {
                        return;
                      }
                      Navigator.of(context).pop();
                      controller.selectProgram(airing);
                      unawaited(widget.onTune(channel.id));
                    },
            );
          },
        ),
      ),
    );
  }
}

// Measure the real header and full-width strip before allocating the picture.
// The picture stays the same render child when its rectangle changes.
class _HandheldGuideFrame extends MultiChildRenderObjectWidget {
  _HandheldGuideFrame({
    required this.reservedScheduleHeight,
    required this.minimumPictureHeight,
    required Widget header,
    required Widget? picture,
    required Widget? strip,
    required Widget schedule,
  }) : super(children: [header, ?picture, ?strip, schedule]);

  final double reservedScheduleHeight;
  final double minimumPictureHeight;

  @override
  _HandheldGuideFrameRender createRenderObject(BuildContext context) =>
      _HandheldGuideFrameRender(reservedScheduleHeight, minimumPictureHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _HandheldGuideFrameRender renderObject,
  ) {
    renderObject.update(reservedScheduleHeight, minimumPictureHeight);
  }
}

class _HandheldGuideFrameParentData extends ContainerBoxParentData<RenderBox> {}

class _HandheldGuideFrameRender extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HandheldGuideFrameParentData>,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          _HandheldGuideFrameParentData
        > {
  _HandheldGuideFrameRender(
    this._reservedScheduleHeight,
    this._minimumPictureHeight,
  );

  double _reservedScheduleHeight;
  double _minimumPictureHeight;

  void update(double reservedScheduleHeight, double minimumPictureHeight) {
    if (_reservedScheduleHeight == reservedScheduleHeight &&
        _minimumPictureHeight == minimumPictureHeight) {
      return;
    }
    _reservedScheduleHeight = reservedScheduleHeight;
    _minimumPictureHeight = minimumPictureHeight;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HandheldGuideFrameParentData) {
      child.parentData = _HandheldGuideFrameParentData();
    }
  }

  void _place(RenderBox child, double left, double top) {
    (child.parentData! as _HandheldGuideFrameParentData).offset = Offset(
      left,
      top,
    );
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    final header = firstChild!;
    final schedule = lastChild!;
    final width = size.width;
    final widthOnly = BoxConstraints.tightFor(width: width);
    header.layout(widthOnly, parentUsesSize: true);
    _place(header, 0, 0);
    var top = header.size.height;
    if (childAfter(header) != schedule) {
      final picture = childAfter(header)!;
      final strip = childAfter(picture)!;
      strip.layout(widthOnly, parentUsesSize: true);
      final fullHeight = width / _guidePictureAspectRatio;
      final stripHeight = strip.size.height;
      final heightForStripAndPicture =
          size.height - top - _reservedScheduleHeight;
      if (heightForStripAndPicture >= fullHeight + stripHeight) {
        picture.layout(
          BoxConstraints.tightFor(width: width, height: fullHeight),
        );
        _place(picture, 0, top);
        _place(strip, 0, top + fullHeight);
        top += fullHeight + stripHeight;
      } else {
        final compactHeight = math.max(
          0.0,
          math.min(
            math.min(
              stripHeight,
              math.max(_minimumPictureHeight, heightForStripAndPicture),
            ),
            math.min(
              (size.height - top),
              width / (2 * _guidePictureAspectRatio),
            ),
          ),
        );
        final pictureWidth = compactHeight * _guidePictureAspectRatio;
        picture.layout(
          BoxConstraints.tightFor(width: pictureWidth, height: compactHeight),
        );
        strip.layout(
          BoxConstraints.tightFor(
            width: width - pictureWidth,
            height: compactHeight,
          ),
        );
        _place(picture, 0, top);
        _place(strip, pictureWidth, top);
        top += compactHeight;
      }
    }
    schedule.layout(
      BoxConstraints.tightFor(
        width: width,
        height: math.max(0, size.height - top),
      ),
    );
    _place(schedule, 0, top);
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
