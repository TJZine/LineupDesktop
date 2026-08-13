import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/app_theme.dart';
import 'native_player.dart';
import 'native_video_surface.dart';
import 'player_coordinator.dart';

class PlayerView extends StatefulWidget {
  const PlayerView({
    required this.controller,
    required this.openGuide,
    this.initialMediaPath,
    super.key,
  });

  final PlayerCoordinator controller;
  final VoidCallback openGuide;
  final String? initialMediaPath;

  @override
  State<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<PlayerView> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    final path = widget.initialMediaPath;
    if (path != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await widget.controller.player.load(_mediaUri(path));
          widget.controller.showOsd();
        } catch (_) {
          // The coordinator/player status owns the visible failure state.
        }
      });
    }
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
      controller.closeOverlay();
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
      unawaited(controller.player.stop());
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
    final unsupported = controller.status.state == PlayerState.unsupported;
    return Material(
      color: Colors.transparent,
      child: Focus(
        autofocus: true,
        onKeyEvent: _key,
        child: MouseRegion(
          cursor: controller.cursorVisible
              ? SystemMouseCursors.basic
              : SystemMouseCursors.none,
          onHover: (_) => controller.showCursor(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: controller.showOsd,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (unsupported)
                  const ColoredBox(color: LineupTheme.obsidian)
                else
                  NativeVideoSurface(player: controller.player),
                if (unsupported)
                  _Unsupported(message: controller.status.message),
                if (controller.status.state == PlayerState.loading ||
                    controller.tuning)
                  const _Loading(),
                switch (controller.overlay) {
                  PlayerOverlay.osd => _Osd(controller: controller),
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

class _Osd extends StatelessWidget {
  const _Osd({required this.controller});
  final PlayerCoordinator controller;

  @override
  Widget build(BuildContext context) {
    final channel = controller.currentChannel;
    final program = controller.currentProgram;
    final duration = controller.duration.inMilliseconds;
    final position = controller.position.inMilliseconds.clamp(
      0,
      duration <= 0 ? 1 : duration,
    );
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.all(28),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xE8151820),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white24),
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
                        color: LineupTheme.brass,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${channel.number}',
                        style: const TextStyle(
                          color: LineupTheme.obsidian,
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
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (program?.scheduled.item.showTitle != null)
                          Text(program!.scheduled.item.showTitle!),
                      ],
                    ),
                  ),
                  Text(_quality(controller.telemetry)),
                ],
              ),
              const SizedBox(height: 12),
              Semantics(
                label: 'Playback progress',
                value:
                    '${_duration(controller.position)} of ${_duration(controller.duration)}',
                child: Slider(
                  value: position.toDouble(),
                  max: (duration <= 0 ? 1 : duration).toDouble(),
                  onChanged: duration <= 0
                      ? null
                      : (value) => controller.player.seek(
                          Duration(milliseconds: value.round()),
                        ),
                ),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: controller.status.state == PlayerState.playing
                        ? 'Pause'
                        : 'Play',
                    onPressed: controller.togglePlayback,
                    icon: Icon(
                      controller.status.state == PlayerState.playing
                          ? Icons.pause
                          : Icons.play_arrow,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Audio tracks',
                    onPressed: () =>
                        controller.showTracks(PlayerTrackType.audio),
                    icon: const Icon(Icons.audiotrack),
                  ),
                  IconButton(
                    tooltip: 'Subtitles',
                    onPressed: () =>
                        controller.showTracks(PlayerTrackType.subtitle),
                    icon: const Icon(Icons.subtitles_outlined),
                  ),
                  IconButton(
                    tooltip: 'Sleep timer',
                    onPressed: controller.cycleSleepTimer,
                    icon: const Icon(Icons.bedtime_outlined),
                  ),
                  Text(
                    controller.sleepDuration == null
                        ? 'Sleep off'
                        : 'Sleep ${controller.sleepDuration!.inMinutes}m',
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: controller.fullscreen
                        ? 'Exit fullscreen'
                        : 'Fullscreen',
                    onPressed: controller.toggleFullscreen,
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
    );
  }
}

class _MiniGuide extends StatelessWidget {
  const _MiniGuide({required this.controller});
  final PlayerCoordinator controller;

  @override
  Widget build(BuildContext context) {
    final channels = controller.lineup.channels;
    final selected = controller.miniGuideChannelIndex;
    final start = (selected - 3).clamp(0, channels.length);
    final end = (start + 7).clamp(0, channels.length);
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Material(
          color: const Color(0xEE151820),
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            width: 520,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Semantics(
                container: true,
                label: 'Mini Guide',
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: end - start,
                  itemBuilder: (context, offset) {
                    final channel = channels[start + offset];
                    final focused = channel.id == controller.miniGuideChannelId;
                    final program = controller.guide.currentProgram(channel.id);
                    return ListTile(
                      selected: focused,
                      leading: Text('${channel.number}'),
                      title: Text(channel.name),
                      subtitle: Text(
                        program?.scheduled.item.title ?? 'Schedule loading…',
                      ),
                      trailing: channel.id == controller.lineup.currentChannelId
                          ? const Icon(Icons.play_circle_fill)
                          : null,
                      onTap: () => controller.tune(channel.id),
                    );
                  },
                ),
              ),
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
    return Center(
      child: Card(
        child: SizedBox(
          width: 460,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  type == PlayerTrackType.audio ? 'Audio tracks' : 'Subtitles',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (type == PlayerTrackType.subtitle)
                  ListTile(
                    leading: Icon(
                      tracks.any((track) => track.selected)
                          ? Icons.radio_button_unchecked
                          : Icons.radio_button_checked,
                    ),
                    title: const Text('Off'),
                    onTap: () => controller.selectTrack(type, null),
                  ),
                for (final track in tracks)
                  ListTile(
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
                    subtitle: track.codec == null ? null : Text(track.codec!),
                    onTap: () => controller.selectTrack(type, track.id),
                  ),
                TextButton(
                  onPressed: controller.closeOverlay,
                  child: const Text('Back'),
                ),
              ],
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
  const _Loading();
  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      liveRegion: true,
      label: 'Playback loading',
      child: CircularProgressIndicator(),
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
          'Player preview',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(message),
      ],
    ),
  );
}

Uri _mediaUri(String value) {
  if (Platform.isWindows &&
      (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value) || value.startsWith(r'\\'))) {
    return Uri.file(value, windows: true);
  }
  final parsed = Uri.tryParse(value);
  return parsed != null && parsed.hasScheme
      ? parsed
      : Uri.file(value, windows: Platform.isWindows);
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
