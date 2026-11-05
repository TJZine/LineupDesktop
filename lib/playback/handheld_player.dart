part of 'player_view.dart';

class _HandheldPortraitPlayer extends StatelessWidget {
  const _HandheldPortraitPlayer({
    required this.controller,
    required this.trackDisplays,
    required this.surface,
    required this.scrollStorage,
    required this.onMinimize,
  });

  final PlayerCoordinator controller;
  final PlayerTrackDisplayCache trackDisplays;
  final PlayerSurface surface;
  final PageStorageBucket scrollStorage;
  final VoidCallback onMinimize;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final insets = LineupCanvas.contentInsets(context);
    final channel = controller.currentChannel;
    final program = controller.currentProgram;
    final item = program?.scheduled.item;
    final now = controller.guide.now;
    final channels = controller.lineup.channels;
    final stopped = _showStoppedVideo(controller);
    final sheet =
        controller.sleepPickerOpen ||
        controller.overlay == PlayerOverlay.audioTracks ||
        controller.overlay == PlayerOverlay.subtitleTracks;
    final info =
        controller.overlay == PlayerOverlay.programInfo && program != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: sheet || info,
          child: ExcludeFocus(
            excluding: sheet || info,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ColoredBox(
                  color: roles.deepBackground,
                  child: SizedBox(height: insets.top),
                ),
                AspectRatio(
                  key: const Key('handheld-player-video'),
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      surface,
                      Positioned(
                        top: 4,
                        left: math.max(4, insets.left),
                        child: _PortraitVideoAction(
                          key: const Key('handheld-player-minimize'),
                          label: 'Minimize to Guide',
                          icon: Icons.keyboard_arrow_down,
                          onPressed: onMinimize,
                        ),
                      ),
                      if (controller.canToggleFullscreen)
                        Positioned(
                          right: math.max(4, insets.right),
                          bottom: 6,
                          child: _PortraitVideoAction(
                            label: controller.fullscreen
                                ? 'Exit full screen'
                                : 'Full screen',
                            icon: controller.fullscreen
                                ? Icons.fullscreen_exit
                                : Icons.fullscreen,
                            onPressed: () =>
                                unawaited(controller.toggleFullscreen()),
                          ),
                        ),
                      if (program != null)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: _HandheldProgramProgress(
                            program: program,
                            now: now,
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ColoredBox(
                    color: roles.deepBackground,
                    child: PageStorage(
                      bucket: scrollStorage,
                      child: ListView.builder(
                        key: const PageStorageKey('handheld-player-content'),
                        padding: EdgeInsets.fromLTRB(
                          insets.left,
                          18,
                          insets.right,
                          24 + insets.bottom,
                        ),
                        itemCount: channels.length + 1,
                        itemBuilder: (context, index) {
                          if (index != 0) {
                            final row = channels[index - 1];
                            return _HandheldPlayerChannelRow(
                              channel: row,
                              program: controller.guide.currentProgram(
                                row.id,
                                now,
                              ),
                              now: now,
                              watching: controller.watchingChannelId == row.id,
                              onTune: () => unawaited(controller.tune(row.id)),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (channel != null)
                                  Text(
                                    '${channel.number} · ${channel.name}',
                                    style: LineupTypography.small.copyWith(
                                      color: roles.secondaryText,
                                    ),
                                  ),
                                const SizedBox(height: 6),
                                _HandheldPlayerTitle(
                                  item?.showTitle ??
                                      item?.title ??
                                      'Nothing playing',
                                  style: LineupTypography.title(
                                    30,
                                    90,
                                  ).copyWith(color: roles.primaryText),
                                ),
                                if (item != null)
                                  _HandheldPlayerEpisodeFacts(item: item),
                                if (program != null)
                                  _HandheldPlayerTiming(
                                    controller: controller,
                                    program: program,
                                    now: now,
                                  ),
                                if (stopped) ...[
                                  const SizedBox(height: 16),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      if (controller.canRetry)
                                        FilledButton(
                                          style: FilledButton.styleFrom(
                                            minimumSize: const Size(56, 54),
                                          ),
                                          onPressed: controller.retry,
                                          child: const Text('Retry'),
                                        ),
                                      Text(
                                        'Or choose another channel below.',
                                        style: LineupTypography.body.copyWith(
                                          color: roles.secondaryText,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _trackChip(PlayerTrackType.subtitle),
                                    _trackChip(PlayerTrackType.audio),
                                    _chip(
                                      Icons.bedtime_outlined,
                                      switch (controller.sleepRemaining) {
                                        final remaining? =>
                                          'Sleep · ${(remaining.inSeconds / 60).ceil()}m',
                                        null => 'Sleep',
                                      },
                                      controller.showSleepTimer,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 26),
                                Text(
                                  'CHANNELS',
                                  style: LineupTypography.small.copyWith(
                                    color: roles.mutedText,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (sheet)
          _HandheldPlayerPicker(
            controller: controller,
            trackDisplays: trackDisplays,
          ),
        if (info) _NowPlayingInfo(controller: controller, program: program),
      ],
    );
  }

  Widget _trackChip(PlayerTrackType type) {
    final subtitle = type == PlayerTrackType.subtitle;
    final name = subtitle ? 'Subtitles' : 'Audio';
    final tracks = controller.tracks;
    final selected = tracks
        .where((t) => t.type == type && t.selected)
        .firstOrNull;
    final detail = selected == null
        ? (subtitle ? 'Off' : 'Default')
        : trackDisplays.forTracks(tracks).displayFor(selected).compactText;
    return _chip(
      subtitle ? Icons.subtitles_outlined : Icons.audiotrack,
      detail == null ? name : '$name · $detail',
      tracks.any((track) => track.type == type)
          ? () {
              if (controller.overlay != PlayerOverlay.nowPlaying &&
                  controller.overlay != PlayerOverlay.osd &&
                  controller.overlay != PlayerOverlay.none) {
                controller.showOsd();
              }
              controller.showTracks(type);
            }
          : null,
    );
  }

  Widget _chip(IconData icon, String label, VoidCallback? onPressed) =>
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 54)),
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        label: Text(label),
      );
}

class _HandheldPlayerTitle extends StatelessWidget {
  const _HandheldPlayerTitle(this.title, {required this.style, this.textAlign});

  final String title;
  final TextStyle style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final fontSize = style.fontSize!;
    if (scaler.scale(fontSize) <= fontSize) {
      return Text(title, style: style, textAlign: textAlign);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;

        TextStyle? fitWord(String word) {
          if (_textWidth(context, word, style) <= available ||
              _textWidth(context, word, style, scaler: TextScaler.noScaling) >
                  available) {
            return null;
          }
          // Find the smallest font that the active scaler maps to text 1.0.
          var low = 0.0;
          var high = fontSize;
          for (var step = 0; step < 16; step++) {
            final mid = (low + high) / 2;
            if (scaler.scale(mid) < fontSize) {
              low = mid;
            } else {
              high = mid;
            }
          }
          low = high;
          high = fontSize;
          for (var step = 0; step < 16; step++) {
            final mid = (low + high) / 2;
            if (_textWidth(context, word, style.copyWith(fontSize: mid)) <=
                available - 0.5) {
              low = mid;
            } else {
              high = mid;
            }
          }
          return TextStyle(fontSize: low);
        }

        return Text.rich(
          TextSpan(
            children: [
              for (final part in RegExp(r'\s+|\S+').allMatches(title))
                TextSpan(text: part.group(0), style: fitWord(part.group(0)!)),
            ],
          ),
          style: style,
          textAlign: textAlign,
        );
      },
    );
  }
}

class _PortraitVideoAction extends StatelessWidget {
  const _PortraitVideoAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    style: IconButton.styleFrom(
      minimumSize: const Size.square(56),
      foregroundColor: LineupTheme.of(context).primaryText,
    ),
    onPressed: onPressed,
    icon: Icon(icon, size: 32),
  );
}

class _HandheldPlayerEpisodeFacts extends StatelessWidget {
  const _HandheldPlayerEpisodeFacts({required this.item});

  final ChannelItem item;

  @override
  Widget build(BuildContext context) {
    final facts = [
      ?_osdEpisodeFacts(item),
      if (item.showTitle != null) item.title,
    ];
    if (facts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        facts.join(' · '),
        style: LineupTypography.body.copyWith(
          color: LineupTheme.of(context).secondaryText,
        ),
      ),
    );
  }
}

class _HandheldPlayerTiming extends StatelessWidget {
  const _HandheldPlayerTiming({
    required this.controller,
    required this.program,
    required this.now,
  });

  final PlayerCoordinator controller;
  final GuideProgram program;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scheduled = program.scheduled;
    final next = controller.guide
        .nextProgram(program.channelId)
        ?.scheduled
        .item;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        [
          '${_time(context, scheduled.start)}–${_time(context, scheduled.end)}',
          _scheduledMinutesLeft(program, now),
          if (next != null) 'Up next ${next.showTitle ?? next.title}',
        ].join(' · '),
        style: LineupTypography.body.copyWith(
          fontSize: 16,
          color: LineupTheme.of(context).mutedText,
        ),
      ),
    );
  }
}

String _scheduledMinutesLeft(GuideProgram program, DateTime now) {
  final scheduled = program.scheduled;
  return _wholeMinutesLeft(
        now.difference(scheduled.start),
        scheduled.end.difference(scheduled.start),
      ) ??
      '0m left';
}

class _HandheldPlayerChannelRow extends StatelessWidget {
  const _HandheldPlayerChannelRow({
    required this.channel,
    required this.program,
    required this.now,
    required this.watching,
    required this.onTune,
  });

  final Channel channel;
  final GuideProgram? program;
  final DateTime now;
  final bool watching;
  final VoidCallback onTune;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final item = program?.scheduled.item;
    final numberWidth = math.max(
      76.0,
      MediaQuery.textScalerOf(context).scale(44),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Material(
        color: watching ? roles.selectedSurface : roles.elevatedSurface,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: watching ? null : onTune,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 76),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: numberWidth,
                    color: watching ? roles.tunedSurface : roles.primarySurface,
                    alignment: Alignment.center,
                    child: Text(
                      '${channel.number}',
                      style: LineupTypography.title(
                        26,
                        90,
                      ).copyWith(color: roles.primaryText),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox.shrink(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item?.showTitle ?? item?.title ?? channel.name,
                                style: LineupTypography.control.copyWith(
                                  fontSize: 17,
                                  color: roles.primaryText,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    if (watching)
                                      TextSpan(
                                        text: '● Watching · ',
                                        style: TextStyle(
                                          color: roles.liveAccent,
                                        ),
                                      ),
                                    TextSpan(
                                      text: [
                                        channel.name,
                                        if (program case final program?)
                                          _scheduledMinutesLeft(program, now),
                                      ].join(' · '),
                                    ),
                                  ],
                                ),
                                style: LineupTypography.body.copyWith(
                                  fontSize: 15,
                                  color: roles.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (program case final program?)
                          _HandheldProgramProgress(
                            program: program,
                            now: now,
                            height: 3,
                          )
                        else
                          const SizedBox.shrink(),
                      ],
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
}

class _HandheldProgramProgress extends StatelessWidget {
  const _HandheldProgramProgress({
    required this.program,
    required this.now,
    this.height = 4,
  });

  final GuideProgram program;
  final DateTime now;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheduled = program.scheduled;
    final duration = scheduled.end.difference(scheduled.start).inMilliseconds;
    final elapsed = now.difference(scheduled.start).inMilliseconds;
    return SizedBox(
      height: height,
      child: FractionallySizedBox(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: duration <= 0 ? 0 : (elapsed / duration).clamp(0, 1),
        child: ColoredBox(color: LineupTheme.of(context).progressFill),
      ),
    );
  }
}

class _HandheldStoppedVideo extends StatelessWidget {
  const _HandheldStoppedVideo({required this.controller});

  final PlayerCoordinator controller;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    return ColoredBox(
      color: roles.primarySurface,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(60, 12, 60, 12),
          child: Semantics(
            liveRegion: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _HandheldPlayerTitle(
                  _stoppedTitle(controller),
                  textAlign: TextAlign.center,
                  style: LineupTypography.title(
                    26,
                    90,
                  ).copyWith(color: roles.primaryText),
                ),
                const SizedBox(height: 6),
                Text(
                  controller.error ?? controller.status.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: LineupTypography.body.copyWith(
                    fontSize: 16,
                    color: roles.secondaryText,
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

class _HandheldPlayerPicker extends StatelessWidget {
  const _HandheldPlayerPicker({
    required this.controller,
    required this.trackDisplays,
  });

  final PlayerCoordinator controller;
  final PlayerTrackDisplayCache trackDisplays;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final sleep = controller.sleepPickerOpen;
    final subtitles = controller.overlay == PlayerOverlay.subtitleTracks;
    final type = subtitles ? PlayerTrackType.subtitle : PlayerTrackType.audio;
    final displays = trackDisplays.forTracks(controller.tracks);
    final tracks = controller.tracks.where((track) => track.type == type);
    final insets = LineupCanvas.contentInsets(context);
    final title = sleep
        ? 'Sleep timer'
        : subtitles
        ? 'Subtitles'
        : 'Audio';
    return Stack(
      fit: StackFit.expand,
      children: [
        ModalBarrier(
          color: roles.scrim.withValues(alpha: .55),
          dismissible: true,
          onDismiss: controller.closeOverlay,
          semanticsLabel: 'Close $title',
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            widthFactor: 1,
            heightFactor: .62,
            child: Material(
              key: const Key('handheld-player-sheet'),
              color: roles.primarySurface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: FocusScope(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        24 + insets.left,
                        12,
                        12 + insets.right,
                        8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _HandheldPlayerTitle(
                              title,
                              style: LineupTypography.title(
                                26,
                                90,
                              ).copyWith(color: roles.primaryText),
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              minimumSize: const Size(54, 54),
                            ),
                            onPressed: controller.closeOverlay,
                            child: const Text('Done'),
                          ),
                        ],
                      ),
                    ),
                    if (controller.trackSelectionError case final error?
                        when !sleep)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            error,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          12 + insets.left,
                          0,
                          12 + insets.right,
                          24 + insets.bottom,
                        ),
                        children: sleep
                            ? [
                                for (final (label, duration) in _sleepChoices)
                                  _option(
                                    roles,
                                    title: label,
                                    selected:
                                        duration == controller.sleepDuration,
                                    onTap: () =>
                                        controller.setSleepTimer(duration),
                                  ),
                              ]
                            : [
                                if (subtitles)
                                  _option(
                                    roles,
                                    title: 'Off',
                                    selected: !tracks.any(
                                      (track) => track.selected,
                                    ),
                                    onTap: () => unawaited(
                                      controller.selectTrack(type, null),
                                    ),
                                  ),
                                for (final track in tracks)
                                  _option(
                                    roles,
                                    title: displays
                                        .displayFor(track)
                                        .primaryText,
                                    detail: displays
                                        .displayFor(track)
                                        .secondaryFacts
                                        .join(' · '),
                                    selected: track.selected,
                                    onTap: () => unawaited(
                                      controller.selectTrack(type, track.id),
                                    ),
                                  ),
                              ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _option(
    LineupThemeRoles roles, {
    required String title,
    String? detail,
    required bool selected,
    required VoidCallback onTap,
  }) => ListTile(
    minTileHeight: 64,
    selected: selected,
    selectedColor: roles.primaryText,
    selectedTileColor: roles.selectedSurface,
    title: Text(title),
    subtitle: detail == null || detail.isEmpty
        ? null
        : Text(
            detail,
            style: LineupTypography.body.copyWith(
              fontSize: 15,
              color: roles.secondaryText,
            ),
          ),
    trailing: selected ? const Icon(Icons.check) : null,
    onTap: onTap,
  );
}
