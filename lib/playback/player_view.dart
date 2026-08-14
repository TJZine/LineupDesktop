import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channels/channel.dart';
import '../ui/app_theme.dart';
import 'native_player.dart';
import 'native_video_surface.dart';
import 'player_coordinator.dart';

class PlayerView extends StatefulWidget {
  const PlayerView({
    required this.controller,
    required this.openGuide,
    this.openMenu,
    this.focusNode,
    super.key,
  });

  final PlayerCoordinator controller;
  final VoidCallback openGuide;
  final VoidCallback? openMenu;
  final FocusNode? focusNode;

  @override
  State<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<PlayerView> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final controller = widget.controller;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (controller.overlay == PlayerOverlay.none) {
        controller.showFullGuide();
        widget.openGuide();
      } else {
        controller.closeOverlay();
      }
      return KeyEventResult.handled;
    }
    final unsupported = controller.status.state == PlayerState.unsupported;
    final selects =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.mediaPlayPause;
    if (unsupported &&
        (_digit(key) != null ||
            key == LogicalKeyboardKey.mediaPlay ||
            key == LogicalKeyboardKey.mediaPause ||
            key == LogicalKeyboardKey.mediaStop ||
            key == LogicalKeyboardKey.mediaRewind ||
            key == LogicalKeyboardKey.mediaFastForward ||
            ((key == LogicalKeyboardKey.pageUp ||
                    key == LogicalKeyboardKey.pageDown) &&
                controller.overlay != PlayerOverlay.miniGuide) ||
            (controller.overlay == PlayerOverlay.none &&
                (selects ||
                    key == LogicalKeyboardKey.arrowLeft ||
                    key == LogicalKeyboardKey.arrowRight)) ||
            (controller.overlay == PlayerOverlay.miniGuide && selects))) {
      return KeyEventResult.handled;
    }
    if (controller.overlay == PlayerOverlay.audioTracks ||
        controller.overlay == PlayerOverlay.subtitleTracks ||
        controller.overlay == PlayerOverlay.error) {
      return KeyEventResult.ignored;
    }
    if (controller.overlay == PlayerOverlay.channelNumber) {
      final digit = _digit(key);
      if (digit != null) {
        controller.appendChannelDigit(digit);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.select) {
        unawaited(controller.commitChannelNumber());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.keyG || key == LogicalKeyboardKey.f2) {
      controller.showFullGuide();
      widget.openGuide();
    } else if (controller.overlay == PlayerOverlay.miniGuide &&
        key == LogicalKeyboardKey.arrowUp) {
      controller.moveMiniGuide(-1);
    } else if (controller.overlay == PlayerOverlay.miniGuide &&
        key == LogicalKeyboardKey.arrowDown) {
      controller.moveMiniGuide(1);
    } else if (key == LogicalKeyboardKey.pageUp) {
      controller.overlay == PlayerOverlay.miniGuide
          ? controller.moveMiniGuide(-7)
          : unawaited(controller.previousChannel());
    } else if (key == LogicalKeyboardKey.pageDown) {
      controller.overlay == PlayerOverlay.miniGuide
          ? controller.moveMiniGuide(7)
          : unawaited(controller.nextChannel());
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      if (controller.overlay == PlayerOverlay.miniGuide) {
        unawaited(controller.tuneMiniGuideSelection());
      } else if (controller.overlay == PlayerOverlay.none) {
        unawaited(controller.togglePlayback());
      } else {
        return KeyEventResult.ignored;
      }
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      if (controller.overlay != PlayerOverlay.none) {
        return KeyEventResult.ignored;
      }
      unawaited(controller.seekBy(const Duration(seconds: -10)));
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (controller.overlay == PlayerOverlay.miniGuide) {
        controller.showFullGuide();
        widget.openGuide();
      } else if (controller.overlay == PlayerOverlay.none) {
        unawaited(controller.seekBy(const Duration(seconds: 30)));
      } else {
        return KeyEventResult.ignored;
      }
    } else if (key == LogicalKeyboardKey.arrowUp &&
        controller.overlay == PlayerOverlay.none) {
      controller.showMiniGuide();
    } else if (key == LogicalKeyboardKey.arrowDown &&
        controller.overlay == PlayerOverlay.none) {
      controller.showOsd();
    } else if (key == LogicalKeyboardKey.mediaPlay) {
      unawaited(controller.player.play());
    } else if (key == LogicalKeyboardKey.mediaPause) {
      unawaited(controller.player.pause());
    } else if (key == LogicalKeyboardKey.mediaStop) {
      unawaited(controller.stop());
    } else if (key == LogicalKeyboardKey.mediaRewind) {
      unawaited(controller.seekBy(const Duration(seconds: -10)));
    } else if (key == LogicalKeyboardKey.mediaFastForward) {
      unawaited(controller.seekBy(const Duration(seconds: 30)));
    } else {
      final digit = _digit(key);
      if (digit == null) return KeyEventResult.ignored;
      controller.appendChannelDigit(digit);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Material(
      color: Colors.transparent,
      child: Focus(
        focusNode: widget.focusNode,
        canRequestFocus: controller.overlay != PlayerOverlay.fullGuide,
        autofocus: true,
        onKeyEvent: _key,
        child: MouseRegion(
          cursor: controller.cursorVisible
              ? SystemMouseCursors.basic
              : SystemMouseCursors.none,
          onHover: (_) => controller.handlePointerActivity(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: controller.showOsd,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PlayerSurface(controller: controller),
                switch (controller.overlay) {
                  PlayerOverlay.osd => _Osd(
                    controller: controller,
                    openMenu: widget.openMenu,
                  ),
                  PlayerOverlay.miniGuide => _MiniGuide(controller: controller),
                  PlayerOverlay.audioTracks => _Tracks(
                    controller: controller,
                    type: PlayerTrackType.audio,
                  ),
                  PlayerOverlay.subtitleTracks => _Tracks(
                    controller: controller,
                    type: PlayerTrackType.subtitle,
                  ),
                  PlayerOverlay.channelNumber => _ChannelNumber(
                    controller: controller,
                  ),
                  PlayerOverlay.error => _ErrorOverlay(controller: controller),
                  PlayerOverlay.none ||
                  PlayerOverlay.fullGuide => const SizedBox.shrink(),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The one Flutter geometry used for both the full player and Guide PiP.
class PlayerSurface extends StatelessWidget {
  const PlayerSurface({
    required this.controller,
    this.showErrors = false,
    super.key,
  });

  final PlayerCoordinator controller;
  final bool showErrors;

  @override
  Widget build(BuildContext context) {
    final state = controller.status.state;
    final unsupported = state == PlayerState.unsupported;
    final roles = LineupTheme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (unsupported)
          ColoredBox(color: roles.deepBackground)
        else
          NativeVideoSurface(player: controller.player),
        if (unsupported) _Unsupported(message: controller.status.message),
        if (state == PlayerState.loading || controller.tuning)
          const _Loading(label: 'Preparing playback'),
        if (state == PlayerState.buffering)
          const _Loading(label: 'Buffering playback'),
        if (showErrors && controller.error != null)
          _SurfaceError(controller: controller),
      ],
    );
  }
}

class _SurfaceError extends StatelessWidget {
  const _SurfaceError({required this.controller});
  final PlayerCoordinator controller;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: LineupTheme.of(context).deepBackground,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline),
            const SizedBox(height: 8),
            Text(
              controller.error ?? controller.status.message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            if (controller.canRetry)
              TextButton(
                onPressed: controller.retry,
                child: const Text('Retry'),
              ),
          ],
        ),
      ),
    ),
  );
}

class _Osd extends StatelessWidget {
  const _Osd({required this.controller, this.openMenu});
  final PlayerCoordinator controller;
  final VoidCallback? openMenu;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final channel = controller.currentChannel;
    final program = controller.currentProgram;
    final next = controller.nextProgram;
    final duration = controller.duration.inMilliseconds;
    final position = controller.position.inMilliseconds.clamp(
      0,
      duration <= 0 ? 1 : duration,
    );
    final audioAvailable = controller.tracks.any(
      (track) => track.type == PlayerTrackType.audio,
    );
    final subtitlesAvailable = controller.tracks.any(
      (track) => track.type == PlayerTrackType.subtitle,
    );
    final unsupported = controller.status.state == PlayerState.unsupported;
    final quality = _quality(controller.telemetry);
    return Focus(
      onFocusChange: controller.setOverlayInteraction,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          minimum: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              decoration: BoxDecoration(
                color: roles.overlaySurface,
                borderRadius: BorderRadius.circular(roles.panelRadius),
                border: Border.all(color: roles.defaultBorder),
                boxShadow: [BoxShadow(color: roles.scrim, blurRadius: 24)],
              ),
              child: Semantics(
                container: true,
                label: 'Playback controls',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        if (channel != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: roles.progressFill,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${channel.number}',
                              style: TextStyle(
                                color: roles.onFocus,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                program?.scheduled.item.title ??
                                    channel?.name ??
                                    'Nothing playing',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text(
                                [
                                  program?.scheduled.item.showTitle,
                                  _statusLabel(controller.status.state),
                                  if (quality.isNotEmpty) quality,
                                ].nonNulls.join(' • '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Semantics(
                      label: 'Playback progress',
                      value:
                          '${_duration(controller.position)} of ${_duration(controller.duration)}',
                      child: Slider(
                        value: position.toDouble(),
                        max: (duration <= 0 ? 1 : duration).toDouble(),
                        onChanged: duration <= 0 || unsupported
                            ? null
                            : (value) => controller.seekTo(
                                Duration(milliseconds: value.round()),
                              ),
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          '${_duration(controller.position)} / ${_duration(controller.duration)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const Spacer(),
                        if (next != null &&
                            MediaQuery.sizeOf(context).width >= 900)
                          Flexible(
                            child: Text(
                              'Up next • ${next.scheduled.item.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Previous channel',
                          onPressed: unsupported
                              ? null
                              : controller.previousChannel,
                          icon: const Icon(Icons.skip_previous),
                        ),
                        IconButton(
                          tooltip:
                              controller.status.state == PlayerState.playing
                              ? 'Pause'
                              : 'Play',
                          onPressed: unsupported
                              ? null
                              : controller.togglePlayback,
                          icon: Icon(
                            controller.status.state == PlayerState.playing
                                ? Icons.pause
                                : Icons.play_arrow,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next channel',
                          onPressed: unsupported
                              ? null
                              : controller.nextChannel,
                          icon: const Icon(Icons.skip_next),
                        ),
                        IconButton(
                          tooltip: audioAvailable
                              ? 'Audio tracks'
                              : 'Audio tracks unavailable',
                          onPressed: audioAvailable
                              ? () =>
                                    controller.showTracks(PlayerTrackType.audio)
                              : null,
                          icon: const Icon(Icons.audiotrack),
                        ),
                        IconButton(
                          tooltip: subtitlesAvailable
                              ? 'Subtitles'
                              : 'Subtitles unavailable',
                          onPressed: subtitlesAvailable
                              ? () => controller.showTracks(
                                  PlayerTrackType.subtitle,
                                )
                              : null,
                          icon: const Icon(Icons.subtitles_outlined),
                        ),
                        IconButton(
                          tooltip: 'Sleep timer',
                          onPressed: controller.cycleSleepTimer,
                          icon: const Icon(Icons.bedtime_outlined),
                        ),
                        if (MediaQuery.sizeOf(context).width >= 900)
                          Text(
                            controller.sleepDuration == null
                                ? 'Sleep off'
                                : 'Sleep ${controller.sleepDuration!.inMinutes}m',
                          ),
                        const Spacer(),
                        if (openMenu != null)
                          IconButton(
                            key: const Key('player-app-menu'),
                            tooltip: 'Open Lineup menu',
                            onPressed: openMenu,
                            icon: const Icon(Icons.menu),
                          ),
                        IconButton(
                          tooltip: unsupported
                              ? 'Fullscreen unavailable without playback'
                              : controller.fullscreen
                              ? 'Exit fullscreen'
                              : 'Fullscreen',
                          onPressed: unsupported
                              ? null
                              : controller.toggleFullscreen,
                          icon: Icon(
                            controller.fullscreen
                                ? Icons.fullscreen_exit
                                : Icons.fullscreen,
                          ),
                        ),
                      ],
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

class _MiniGuide extends StatelessWidget {
  const _MiniGuide({required this.controller});
  final PlayerCoordinator controller;

  @override
  Widget build(BuildContext context) {
    final channels = controller.miniGuideChannels;
    final roles = LineupTheme.of(context);
    return Focus(
      onFocusChange: controller.setOverlayInteraction,
      child: Align(
        alignment: Alignment.topCenter,
        child: SafeArea(
          minimum: const EdgeInsets.all(16),
          child: Material(
            key: const Key('mini-guide-shelf'),
            color: roles.overlaySurface,
            borderRadius: BorderRadius.circular(roles.panelRadius),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 1180,
                maxHeight: MediaQuery.sizeOf(context).height - 32,
              ),
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Semantics(
                    container: true,
                    explicitChildNodes: true,
                    label: 'Mini Guide',
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'On now',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        for (final channel in channels)
                          _MiniGuideRow(
                            controller: controller,
                            channel: channel,
                          ),
                        const SizedBox(height: 8),
                        const Text(
                          'UP/DOWN Browse • CH± Page • OK Watch • RIGHT Full Guide • BACK Close',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniGuideRow extends StatelessWidget {
  const _MiniGuideRow({required this.controller, required this.channel});

  final PlayerCoordinator controller;
  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final focused = channel.id == controller.miniGuideChannelId;
    final foreground = focused ? roles.focusedText : roles.primaryText;
    final tuned = channel.id == controller.lineup.currentChannelId;
    final unsupported = controller.status.state == PlayerState.unsupported;
    final current = controller.guide.currentProgram(channel.id);
    final next = controller.guide.nextProgram(channel.id);
    final now = controller.guide.now;
    final progress = current == null
        ? 0.0
        : now.difference(current.scheduled.start).inMilliseconds /
              current.scheduled.end
                  .difference(current.scheduled.start)
                  .inMilliseconds;
    return Semantics(
      selected: focused,
      label:
          'Channel ${channel.number}, ${channel.name}. Now ${current?.scheduled.item.title ?? 'schedule loading'}.${next == null ? '' : ' Next ${next.scheduled.item.title}.'}${tuned ? ' Now watching.' : ''}',
      child: Card(
        color: focused ? roles.focusedSurface : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: focused ? roles.focusBorder : roles.subtleBorder,
            width: focused ? roles.focusBorderWidth : 1,
          ),
        ),
        child: InkWell(
          onTap: () => controller.focusMiniGuideChannel(channel.id),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 46,
                  child: Text(
                    '${channel.number}',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(color: foreground),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              channel.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: foreground,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (tuned)
                            Icon(
                              Icons.play_circle_fill,
                              size: 18,
                              color: foreground,
                              semanticLabel: 'Now watching',
                            ),
                        ],
                      ),
                      Text(
                        current?.scheduled.item.title ?? 'Schedule loading…',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: foreground),
                      ),
                      if (current != null)
                        LinearProgressIndicator(
                          value: progress.clamp(0, 1),
                          minHeight: 2,
                          color: focused ? foreground : null,
                          backgroundColor: focused
                              ? foreground.withValues(alpha: 0.25)
                              : null,
                          semanticsLabel: 'Program progress',
                        ),
                      if (next != null)
                        Text(
                          'Next • ${next.scheduled.item.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: foreground),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  style: focused
                      ? IconButton.styleFrom(
                          foregroundColor: foreground,
                          disabledForegroundColor: foreground.withValues(
                            alpha: 0.70,
                          ),
                        )
                      : null,
                  tooltip: unsupported
                      ? 'Playback unavailable'
                      : tuned
                      ? 'Watching this channel'
                      : 'Watch channel',
                  onPressed: tuned || unsupported
                      ? null
                      : () => controller.tune(channel.id),
                  icon: const Icon(Icons.play_arrow),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tracks extends StatelessWidget {
  const _Tracks({required this.controller, required this.type});
  final PlayerCoordinator controller;
  final PlayerTrackType type;

  @override
  Widget build(BuildContext context) {
    final tracks = controller.tracks
        .where((track) => track.type == type)
        .toList();
    final roles = LineupTheme.of(context);
    return Focus(
      onFocusChange: controller.setOverlayInteraction,
      child: Align(
        alignment: Alignment.centerRight,
        child: SafeArea(
          minimum: EdgeInsets.all(roles.overlaySafeArea),
          child: Card(
            key: const Key('playback-options-rail'),
            child: SizedBox(
              width: 460,
              height: double.infinity,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Text(
                      type == PlayerTrackType.audio
                          ? 'Audio tracks'
                          : 'Subtitles',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        key: const Key('playback-options-list'),
                        children: [
                          if (type == PlayerTrackType.subtitle)
                            ListTile(
                              autofocus: true,
                              leading: Icon(
                                tracks.any((track) => track.selected)
                                    ? Icons.radio_button_unchecked
                                    : Icons.radio_button_checked,
                              ),
                              title: const Text('Off'),
                              onTap: () => controller.selectTrack(type, null),
                            ),
                          for (final (index, track) in tracks.indexed)
                            ListTile(
                              autofocus:
                                  type == PlayerTrackType.audio && index == 0,
                              leading: Icon(
                                track.selected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                              ),
                              title: Text(
                                track.title ??
                                    track.language ??
                                    '${track.type.name} ${track.id}',
                              ),
                              subtitle: track.codec == null
                                  ? null
                                  : Text(track.codec!),
                              onTap: () =>
                                  controller.selectTrack(type, track.id),
                            ),
                        ],
                      ),
                    ),
                    TextButton(
                      autofocus: tracks.isEmpty,
                      onPressed: controller.closeOverlay,
                      child: const Text('Back'),
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

class _ChannelNumber extends StatelessWidget {
  const _ChannelNumber({required this.controller});
  final PlayerCoordinator controller;
  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      liveRegion: true,
      label: 'Channel number ${controller.channelNumber}',
      child: Card(
        key: const Key('channel-number-buffer'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 24),
          child: Text(
            controller.channelNumber,
            style: Theme.of(context).textTheme.displayMedium,
          ),
        ),
      ),
    ),
  );
}

class _ErrorOverlay extends StatelessWidget {
  const _ErrorOverlay({required this.controller});
  final PlayerCoordinator controller;
  @override
  Widget build(BuildContext context) => Center(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          liveRegion: true,
          label: 'Playback error',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 42),
              const SizedBox(height: 12),
              Text(controller.error ?? 'Playback failed.'),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                children: [
                  if (controller.canRetry)
                    FilledButton(
                      onPressed: controller.retry,
                      child: const Text('Retry'),
                    ),
                  TextButton(
                    onPressed: controller.closeOverlay,
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Loading extends StatelessWidget {
  const _Loading({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      liveRegion: true,
      label: label,
      child: const CircularProgressIndicator(),
    ),
  );
}

class _Unsupported extends StatelessWidget {
  const _Unsupported({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.desktop_windows_outlined, size: 54),
        const SizedBox(height: 18),
        Text(
          'Playback unavailable',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(message),
      ],
    ),
  );
}

String? _digit(LogicalKeyboardKey key) {
  final keys = {
    LogicalKeyboardKey.digit0: '0',
    LogicalKeyboardKey.digit1: '1',
    LogicalKeyboardKey.digit2: '2',
    LogicalKeyboardKey.digit3: '3',
    LogicalKeyboardKey.digit4: '4',
    LogicalKeyboardKey.digit5: '5',
    LogicalKeyboardKey.digit6: '6',
    LogicalKeyboardKey.digit7: '7',
    LogicalKeyboardKey.digit8: '8',
    LogicalKeyboardKey.digit9: '9',
    LogicalKeyboardKey.numpad0: '0',
    LogicalKeyboardKey.numpad1: '1',
    LogicalKeyboardKey.numpad2: '2',
    LogicalKeyboardKey.numpad3: '3',
    LogicalKeyboardKey.numpad4: '4',
    LogicalKeyboardKey.numpad5: '5',
    LogicalKeyboardKey.numpad6: '6',
    LogicalKeyboardKey.numpad7: '7',
    LogicalKeyboardKey.numpad8: '8',
    LogicalKeyboardKey.numpad9: '9',
  };
  return keys[key];
}

String _duration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

String _quality(PlayerTelemetry value) => [
  if (value.width != null && value.height != null)
    '${value.width}×${value.height}',
  if (value.videoCodec != null) value.videoCodec!,
  if (value.isHdr) 'HDR',
  if (value.hardwareDecoder != null) value.hardwareDecoder!,
].join(' • ');

String _statusLabel(PlayerState state) => switch (state) {
  PlayerState.idle => 'Idle',
  PlayerState.loading => 'Loading',
  PlayerState.ready => 'Ready',
  PlayerState.playing => 'Playing',
  PlayerState.paused => 'Paused',
  PlayerState.buffering => 'Buffering',
  PlayerState.seeking => 'Seeking',
  PlayerState.ended => 'Ended',
  PlayerState.stopped => 'Stopped',
  PlayerState.error => 'Playback error',
  PlayerState.unsupported => 'Unsupported',
};
