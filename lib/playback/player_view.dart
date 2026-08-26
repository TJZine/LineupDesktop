import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channels/channel.dart';
import '../guide/guide_controller.dart';
import '../ui/app_theme.dart';
import '../ui/app_ui.dart';
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
  late PlayerOverlay _renderedOverlay;
  var _overlayTransitionDuration = const Duration(milliseconds: 350);

  @override
  void initState() {
    super.initState();
    _renderedOverlay = widget.controller.overlay;
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final nextOverlay = widget.controller.overlay;
    setState(() {
      final transitioningNowPlaying =
          _renderedOverlay == PlayerOverlay.nowPlaying ||
          nextOverlay == PlayerOverlay.nowPlaying;
      final transitioningTracks =
          _renderedOverlay == PlayerOverlay.audioTracks ||
          _renderedOverlay == PlayerOverlay.subtitleTracks ||
          nextOverlay == PlayerOverlay.audioTracks ||
          nextOverlay == PlayerOverlay.subtitleTracks;
      final transitioningMiniGuide =
          _renderedOverlay == PlayerOverlay.miniGuide ||
          nextOverlay == PlayerOverlay.miniGuide;
      _overlayTransitionDuration = Duration(
        milliseconds: transitioningNowPlaying
            ? 200
            : transitioningTracks
            ? 300
            : transitioningMiniGuide
            ? 300
            : 350,
      );
      _renderedOverlay = nextOverlay;
    });
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final initialPress = event is KeyDownEvent;
    final controller = widget.controller;
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.goBack) {
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
        key == LogicalKeyboardKey.numpadEnter ||
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
            key == LogicalKeyboardKey.keyF ||
            key == LogicalKeyboardKey.f11 ||
            key == LogicalKeyboardKey.keyJ ||
            key == LogicalKeyboardKey.keyK ||
            key == LogicalKeyboardKey.keyL ||
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
    final showingNowPlaying = controller.overlay == PlayerOverlay.nowPlaying;
    if (controller.overlay == PlayerOverlay.channelNumber) {
      final digit = _digit(key);
      if (digit != null) {
        controller.appendChannelDigit(digit);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.select) {
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
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select) {
      if (controller.overlay == PlayerOverlay.miniGuide) {
        unawaited(controller.tuneMiniGuideSelection());
      } else if (showingNowPlaying) {
        controller.showOsd();
      } else if (controller.overlay == PlayerOverlay.none) {
        controller.showOsd();
      } else {
        return KeyEventResult.ignored;
      }
    } else if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.keyK ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      if (controller.overlay != PlayerOverlay.none &&
          controller.overlay != PlayerOverlay.osd &&
          !showingNowPlaying) {
        return KeyEventResult.ignored;
      }
      unawaited(controller.togglePlayback());
      controller.showOsd();
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.keyJ) {
      if (controller.overlay != PlayerOverlay.none &&
          controller.overlay != PlayerOverlay.osd &&
          !showingNowPlaying) {
        return KeyEventResult.ignored;
      }
      unawaited(controller.seekBy(const Duration(seconds: -10)));
      controller.showOsd();
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyL) {
      if (controller.overlay == PlayerOverlay.miniGuide) {
        controller.showFullGuide();
        widget.openGuide();
      } else if (controller.overlay == PlayerOverlay.none ||
          controller.overlay == PlayerOverlay.osd ||
          showingNowPlaying) {
        unawaited(controller.seekBy(const Duration(seconds: 30)));
        controller.showOsd();
      } else {
        return KeyEventResult.ignored;
      }
    } else if (key == LogicalKeyboardKey.arrowUp &&
        controller.overlay == PlayerOverlay.none) {
      controller.showMiniGuide();
    } else if (key == LogicalKeyboardKey.arrowDown &&
        (controller.overlay == PlayerOverlay.none || showingNowPlaying)) {
      controller.showOsd();
    } else if (initialPress && key == LogicalKeyboardKey.keyI) {
      showingNowPlaying
          ? controller.closeOverlay()
          : controller.showNowPlaying();
    } else if (initialPress &&
        (key == LogicalKeyboardKey.keyF || key == LogicalKeyboardKey.f11)) {
      unawaited(controller.toggleFullscreen());
    } else if (initialPress && key == LogicalKeyboardKey.keyS) {
      controller.cycleSleepTimer();
    } else if (key == LogicalKeyboardKey.keyA) {
      controller.showTracks(PlayerTrackType.audio);
    } else if (key == LogicalKeyboardKey.keyC) {
      controller.showTracks(PlayerTrackType.subtitle);
    } else if (key == LogicalKeyboardKey.mediaPlay) {
      unawaited(controller.player.play());
      if (showingNowPlaying) controller.showOsd();
    } else if (key == LogicalKeyboardKey.mediaPause) {
      unawaited(controller.player.pause());
      if (showingNowPlaying) controller.showOsd();
    } else if (key == LogicalKeyboardKey.mediaStop) {
      unawaited(controller.requestStop());
    } else if (key == LogicalKeyboardKey.mediaRewind) {
      unawaited(controller.seekBy(const Duration(seconds: -10)));
      if (showingNowPlaying) controller.showOsd();
    } else if (key == LogicalKeyboardKey.mediaFastForward) {
      unawaited(controller.seekBy(const Duration(seconds: 30)));
      if (showingNowPlaying) controller.showOsd();
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
    final overlay = controller.overlay;
    final presentationGeneration = controller.overlayPresentationGeneration;
    final presentationKey = ValueKey((overlay, presentationGeneration));
    final transitionDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _overlayTransitionDuration;
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
                AnimatedSwitcher(
                  duration: transitionDuration,
                  reverseDuration: transitionDuration,
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    alignment: Alignment.center,
                    children: [
                      for (final child in previousChildren)
                        ExcludeFocus(child: ExcludeSemantics(child: child)),
                      ?currentChild,
                    ],
                  ),
                  transitionBuilder: (child, animation) {
                    final fade = CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOut,
                      reverseCurve: Curves.easeIn,
                    );
                    final transitioned = FadeTransition(
                      opacity: fade,
                      child: child,
                    );
                    final childOverlay =
                        (child.key as ValueKey<(PlayerOverlay, int)>).value.$1;
                    if (childOverlay == PlayerOverlay.nowPlaying) {
                      return SlideTransition(
                        position: Tween(
                          begin: const Offset(-1, 0),
                          end: Offset.zero,
                        ).animate(fade),
                        child: transitioned,
                      );
                    }
                    if (childOverlay == PlayerOverlay.audioTracks ||
                        childOverlay == PlayerOverlay.subtitleTracks) {
                      return SlideTransition(
                        position: Tween(
                          begin: const Offset(1, 0),
                          end: Offset.zero,
                        ).animate(fade),
                        child: transitioned,
                      );
                    }
                    if (childOverlay == PlayerOverlay.miniGuide) {
                      return SlideTransition(
                        position: Tween(
                          begin: const Offset(0, -1),
                          end: Offset.zero,
                        ).animate(fade),
                        child: transitioned,
                      );
                    }
                    if (childOverlay != PlayerOverlay.osd) {
                      return transitioned;
                    }
                    return SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 1),
                        end: Offset.zero,
                      ).animate(fade),
                      child: transitioned,
                    );
                  },
                  child: Focus(
                    key: presentationKey,
                    canRequestFocus: false,
                    onFocusChange: (focused) {
                      if (!focused ||
                          FocusManager.instance.highlightMode ==
                              FocusHighlightMode.traditional) {
                        controller.overlayFocusChanged(
                          overlay,
                          presentationGeneration,
                          focused,
                        );
                      }
                    },
                    child: switch (overlay) {
                      PlayerOverlay.osd => _Osd(
                        controller: controller,
                        openMenu: widget.openMenu,
                      ),
                      PlayerOverlay.nowPlaying => _NowPlaying(
                        controller: controller,
                      ),
                      PlayerOverlay.miniGuide => _MiniGuide(
                        controller: controller,
                      ),
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
                      PlayerOverlay.error => _ErrorOverlay(
                        controller: controller,
                      ),
                      PlayerOverlay.none ||
                      PlayerOverlay.fullGuide => const SizedBox.shrink(),
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
    final hasError = controller.error != null;
    final preparing =
        !hasError && (state == PlayerState.loading || controller.tuning);
    final roles = LineupTheme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (unsupported)
          ColoredBox(color: roles.deepBackground)
        else
          NativeVideoSurface(player: controller.player),
        if (unsupported) _Unsupported(message: controller.status.message),
        if (preparing) const _Loading(label: 'Preparing playback'),
        if (!hasError && !preparing && state == PlayerState.buffering)
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
    final size = MediaQuery.sizeOf(context);
    final horizontalInset = (size.width * 0.05).clamp(24.0, 96.0);
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
    final expanded = !LineupLayout.isCompactWidth(size.width);
    // 720p desktop still has enough room for the broadcast-style progress
    // lane; keep the compact 800x600 regime stacked so every action remains
    // reachable without crowding the identity block.
    final horizontal = size.width >= 1200 && size.height >= 640;
    final transportActions = <Widget>[
      IconButton(
        tooltip: 'Previous channel',
        onPressed: unsupported ? null : controller.previousChannel,
        iconSize: 28,
        icon: const Icon(Icons.skip_previous),
      ),
      IconButton(
        tooltip: controller.status.state == PlayerState.playing
            ? 'Pause'
            : 'Play',
        onPressed: unsupported ? null : controller.togglePlayback,
        iconSize: 36,
        icon: Icon(
          controller.status.state == PlayerState.playing
              ? Icons.pause
              : Icons.play_arrow,
        ),
      ),
      IconButton(
        tooltip: 'Next channel',
        onPressed: unsupported ? null : controller.nextChannel,
        iconSize: 28,
        icon: const Icon(Icons.skip_next),
      ),
    ];
    final optionActions = <Widget>[
      IconButton(
        tooltip: audioAvailable ? 'Audio tracks' : 'Audio tracks unavailable',
        onPressed: audioAvailable
            ? () => controller.showTracks(PlayerTrackType.audio)
            : null,
        icon: const Icon(Icons.audiotrack),
      ),
      IconButton(
        tooltip: subtitlesAvailable ? 'Subtitles' : 'Subtitles unavailable',
        onPressed: subtitlesAvailable
            ? () => controller.showTracks(PlayerTrackType.subtitle)
            : null,
        icon: const Icon(Icons.subtitles_outlined),
      ),
      IconButton(
        tooltip: 'Sleep timer',
        onPressed: controller.cycleSleepTimer,
        icon: const Icon(Icons.bedtime_outlined),
      ),
      if (expanded)
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 8),
          child: Text(
            controller.sleepDuration == null
                ? 'Sleep off'
                : 'Sleep ${controller.sleepDuration!.inMinutes}m',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: roles.secondaryText),
          ),
        ),
    ];
    final windowActions = <Widget>[
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
        onPressed: unsupported ? null : controller.toggleFullscreen,
        icon: Icon(
          controller.fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
        ),
      ),
    ];
    final identity = Row(
      key: const Key('player-osd-identity'),
      children: [
        if (channel != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                [
                  channel?.name,
                  program?.scheduled.item.showTitle,
                  _statusLabel(controller.status.state),
                  if (quality.isNotEmpty) quality,
                ].nonNulls.join(' • '),
                key: const Key('player-osd-status'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: roles.secondaryText),
              ),
            ],
          ),
        ),
      ],
    );
    final progress = Column(
      key: const Key('player-osd-progress-block'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: 'Playback progress',
          value:
              '${_duration(controller.position)} of ${_duration(controller.duration)}',
          child: Slider(
            value: position.toDouble(),
            max: (duration <= 0 ? 1 : duration).toDouble(),
            onChanged: duration <= 0 || unsupported
                ? null
                : (value) =>
                      controller.seekTo(Duration(milliseconds: value.round())),
          ),
        ),
        Row(
          children: [
            Text(
              '${_duration(controller.position)} / ${_duration(controller.duration)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: roles.secondaryText,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (next != null && expanded)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Up next • ${next.scheduled.item.title}',
                      key: const Key('player-osd-next'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: roles.mutedText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
    Widget actionGroup(List<Widget> children, {bool separated = true}) =>
        DecoratedBox(
          decoration: BoxDecoration(
            border: separated
                ? Border(left: BorderSide(color: roles.subtleBorder))
                : null,
          ),
          child: Padding(
            padding: EdgeInsets.only(left: separated ? 8 : 0),
            child: Row(mainAxisSize: MainAxisSize.min, children: children),
          ),
        );
    final groupedActions = Row(
      key: const Key('player-osd-action-groups'),
      mainAxisSize: MainAxisSize.min,
      children: [
        actionGroup(transportActions, separated: false),
        actionGroup(optionActions),
        actionGroup(windowActions),
      ],
    );
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Container(
          key: const Key('player-osd-surface'),
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            horizontalInset,
            horizontal
                ? (size.height >= 900 ? 44 : 20)
                : (size.height >= 720 ? 56 : 40),
            horizontalInset,
            8,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                roles.scrim.withValues(alpha: 0.08),
                roles.scrim.withValues(alpha: 0.30),
                roles.scrim.withValues(alpha: 0.45),
              ],
              stops: const [0, 0.20, 0.60, 1],
            ),
          ),
          child: Semantics(
            container: true,
            label: 'Playback controls',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (horizontal)
                  Row(
                    key: const Key('player-osd-horizontal-layout'),
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(flex: 5, child: identity),
                      const SizedBox(width: 24),
                      Expanded(flex: 4, child: progress),
                      const SizedBox(width: 24),
                      groupedActions,
                    ],
                  )
                else ...[
                  identity,
                  const SizedBox(height: 6),
                  progress,
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      key: const Key('player-osd-stacked-controls'),
                      mainAxisSize: MainAxisSize.min,
                      children: [groupedActions],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.controller});

  final PlayerCoordinator controller;

  @override
  Widget build(BuildContext context) {
    final program = controller.currentProgram;
    if (program == null) return const SizedBox.shrink();
    final item = program.scheduled.item;
    final channel = controller.currentChannel;
    final telemetry = controller.telemetry;
    final roles = LineupTheme.of(context);
    final size = MediaQuery.sizeOf(context);
    final compact =
        LineupLayout.isCompactWidth(size.width) || size.height < 650;
    final shelfWidth = size.width >= 2560
        ? size.width.clamp(0, 1500).toDouble()
        : (size.width * 0.95).clamp(0, 1180).toDouble();
    final shelfHeight = compact
        ? (size.height * 0.56).clamp(300, 380).toDouble()
        : (size.height * 0.50).clamp(380, 560).toDouble();
    final denseShelf = compact || shelfHeight < 440;
    final showPoster = size.width >= 700 && size.height >= 500;
    final preferLogo = controller.lineup.settings.preferClearLogos;
    final posterPath = _artworkPath(item, GuideArtworkKind.poster);
    final logoPath = _artworkPath(item, GuideArtworkKind.clearLogo);
    final generation = controller.lineup.contentGeneration;
    final elapsed = controller.guide.now.difference(program.scheduled.start);
    final span = program.scheduled.end.difference(program.scheduled.start);
    final progress = span.inMilliseconds <= 0
        ? 0.0
        : (elapsed.inMilliseconds / span.inMilliseconds).clamp(0.0, 1.0);
    final episode = _episodeLabel(item);
    final badges = <String>{
      if (item.year != null) '${item.year}',
      ?item.contentRating,
      ...item.genres.take(3),
      ?item.resolution,
      if (telemetry.width != null && telemetry.height != null)
        '${telemetry.width}×${telemetry.height}',
      ?item.videoCodec,
      ?telemetry.videoCodec,
      ?item.audioCodec,
      if (item.audioChannels case final channels?) '${channels}ch',
      if (telemetry.isHdr) 'HDR' else ?item.dynamicRange,
      ?telemetry.hardwareDecoder,
    }.toList(growable: false);
    final semanticFacts = [
      'Now playing',
      if (channel != null) 'Channel ${channel.number}, ${channel.name}',
      ?item.showTitle,
      item.title,
      ?episode,
      '${_time(context, program.scheduled.start)} to ${_time(context, program.scheduled.end)}',
      '${(progress * 100).round()} percent complete',
      if (controller.duration > Duration.zero)
        '${_duration(controller.position)} of ${_duration(controller.duration)} playback',
      ...badges,
      ?item.summary,
    ].join('. ');
    final artworkIdentity = (program.id, generation);

    return Align(
      key: const Key('player-now-playing-surface'),
      alignment: Alignment.bottomLeft,
      child: SafeArea(
        top: false,
        right: false,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: Semantics(
            container: true,
            label: semanticFacts,
            excludeSemantics: true,
            child: Container(
              key: const Key('player-now-playing-shelf'),
              width: shelfWidth,
              height: shelfHeight,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: roles.subtleBorder),
                  right: BorderSide(color: roles.subtleBorder),
                ),
                borderRadius: BorderRadius.only(
                  topRight: const Radius.circular(16),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    roles.scrim.withValues(alpha: 0.62),
                    roles.overlaySurface.withValues(alpha: 0.86),
                  ],
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (showPoster) ...[
                    SizedBox(
                      key: const Key('player-now-playing-poster'),
                      width: (shelfHeight * 2 / 3).clamp(190, 374),
                      height: shelfHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          posterPath == null
                              ? _ArtworkFallback(roles: roles)
                              : _PlayerArtwork(
                                  key: ValueKey((
                                    artworkIdentity,
                                    GuideArtworkKind.poster,
                                    posterPath,
                                  )),
                                  future: controller.guide.artworkFor(program),
                                  fit: BoxFit.cover,
                                  fallback: _ArtworkFallback(roles: roles),
                                ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: SizedBox(
                              width: compact ? 48 : 64,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.transparent,
                                      roles.overlaySurface.withValues(
                                        alpha: 0.72,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        denseShelf ? 18 : 28,
                        denseShelf ? 16 : 24,
                        denseShelf ? 18 : 28,
                        denseShelf ? 14 : 20,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (channel != null)
                            Text(
                              '${channel.number}  •  ${channel.name}',
                              key: const Key('player-now-playing-channel'),
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: roles.progressFill,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                  ),
                            ),
                          SizedBox(height: denseShelf ? 6 : 14),
                          if (preferLogo && logoPath != null)
                            _NowPlayingIdentity(
                              key: ValueKey((
                                artworkIdentity,
                                GuideArtworkKind.clearLogo,
                                logoPath,
                                preferLogo,
                              )),
                              controller: controller,
                              program: program,
                              compact: denseShelf,
                            )
                          else
                            _NowPlayingTitle(item: item, compact: denseShelf),
                          if (episode != null) ...[
                            SizedBox(height: denseShelf ? 8 : 10),
                            Text(
                              episode,
                              key: const Key('player-now-playing-episode'),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: roles.secondaryText,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                          if (!compact && badges.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Wrap(
                              key: const Key('player-now-playing-badges'),
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final badge in badges)
                                  _NowPlayingBadge(label: badge),
                              ],
                            ),
                          ],
                          if (item.summary case final summary?) ...[
                            SizedBox(height: denseShelf ? 8 : 12),
                            Text(
                              summary,
                              key: const Key('player-now-playing-summary'),
                              maxLines: denseShelf ? 2 : 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: roles.secondaryText,
                                    height: 1.45,
                                  ),
                            ),
                          ],
                          const Spacer(),
                          LinearProgressIndicator(
                            key: const Key('player-now-playing-progress'),
                            value: progress,
                            minHeight: 5,
                            color: roles.progressFill,
                            backgroundColor: roles.progressTrack,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            [
                              if (controller.duration > Duration.zero)
                                '${_duration(controller.position)} / ${_duration(controller.duration)}',
                              '${_time(context, program.scheduled.start)}–${_time(context, program.scheduled.end)}',
                            ].join('  •  '),
                            key: const Key('player-now-playing-time'),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: roles.secondaryText),
                          ),
                        ],
                      ),
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

class _NowPlayingIdentity extends StatefulWidget {
  const _NowPlayingIdentity({
    required this.controller,
    required this.program,
    required this.compact,
    super.key,
  });

  final PlayerCoordinator controller;
  final GuideProgram program;
  final bool compact;

  @override
  State<_NowPlayingIdentity> createState() => _NowPlayingIdentityState();
}

class _NowPlayingIdentityState extends State<_NowPlayingIdentity> {
  late final Future<Uint8List?> _logo = widget.controller.guide.artworkFor(
    widget.program,
    GuideArtworkKind.clearLogo,
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _logo,
    builder: (context, snapshot) {
      final bytes = snapshot.data;
      if (bytes == null) {
        return _NowPlayingTitle(
          item: widget.program.scheduled.item,
          compact: widget.compact,
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: widget.compact ? 360 : 600,
              maxHeight: widget.compact ? 84 : 132,
            ),
            child: Image.memory(
              bytes,
              key: const Key('player-now-playing-logo'),
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              gaplessPlayback: false,
              excludeFromSemantics: true,
              frameBuilder: (context, child, frame, synchronous) =>
                  synchronous || frame != null
                  ? child
                  : _NowPlayingTitle(
                      item: widget.program.scheduled.item,
                      compact: widget.compact,
                    ),
              errorBuilder: (_, _, _) => _NowPlayingTitle(
                item: widget.program.scheduled.item,
                compact: widget.compact,
              ),
            ),
          ),
          if (widget.program.scheduled.item.showTitle != null) ...[
            SizedBox(height: widget.compact ? 8 : 12),
            Text(
              widget.program.scheduled.item.title,
              key: const Key('player-now-playing-title'),
              maxLines: widget.compact ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ],
      );
    },
  );
}

class _NowPlayingTitle extends StatelessWidget {
  const _NowPlayingTitle({required this.item, required this.compact});

  final ChannelItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (item.showTitle != null) ...[
        Text(
          item.showTitle!.toUpperCase(),
          key: const Key('player-now-playing-series'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
      ],
      Text(
        item.title,
        key: const Key('player-now-playing-title'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style:
            (compact
                    ? Theme.of(context).textTheme.headlineMedium
                    : Theme.of(context).textTheme.displaySmall)
                ?.copyWith(fontWeight: FontWeight.w900),
      ),
    ],
  );
}

class _PlayerArtwork extends StatelessWidget {
  const _PlayerArtwork({
    required this.future,
    required this.fit,
    this.fallback = const SizedBox.shrink(),
    super.key,
  });

  final Future<Uint8List?> future;
  final BoxFit fit;
  final Widget fallback;

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: future,
    builder: (context, snapshot) => snapshot.data == null
        ? fallback
        : Image.memory(
            snapshot.data!,
            fit: fit,
            gaplessPlayback: false,
            excludeFromSemantics: true,
            frameBuilder: (context, child, frame, synchronous) =>
                synchronous || frame != null ? child : fallback,
            errorBuilder: (_, _, _) => fallback,
          ),
  );
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback({required this.roles});

  final LineupThemeRoles roles;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: roles.primarySurface,
    child: Icon(Icons.movie_outlined, size: 64, color: roles.mutedText),
  );
}

class _NowPlayingBadge extends StatelessWidget {
  const _NowPlayingBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: roles.elevatedSurface.withValues(alpha: 0.82),
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

class _MiniGuide extends StatelessWidget {
  const _MiniGuide({required this.controller});
  final PlayerCoordinator controller;

  @override
  Widget build(BuildContext context) {
    final channels = controller.miniGuideChannels;
    final roles = LineupTheme.of(context);
    final height = MediaQuery.sizeOf(context).height;
    final rowHeight = height < 720 ? null : (height >= 900 ? 48.0 : 56.0);
    final compressed = height >= 900;
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        bottom: false,
        child: Container(
          key: const Key('mini-guide-shelf'),
          width: double.infinity,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height,
          ),
          padding: EdgeInsets.fromLTRB(
            roles.overlaySafeArea,
            compressed ? 8 : 12,
            roles.overlaySafeArea,
            compressed ? 10 : 16,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                roles.scrim.withValues(alpha: 0.60),
                roles.scrim.withValues(alpha: 0.48),
                roles.scrim.withValues(alpha: 0.24),
                Colors.transparent,
              ],
              stops: const [0, 0.50, 0.80, 1],
            ),
            border: Border(bottom: BorderSide(color: roles.subtleBorder)),
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(roles.panelRadius),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            label: 'Mini Guide',
            child: SingleChildScrollView(
              key: const Key('mini-guide-scroll'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final channel in channels)
                    _MiniGuideRow(
                      controller: controller,
                      channel: channel,
                      rowHeight: rowHeight,
                    ),
                  SizedBox(height: compressed ? 4 : 8),
                  Text(
                    'UP/DOWN Browse • CH± Page • OK Watch • RIGHT Full Guide • BACK Close',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: compressed ? 11 : 12),
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

class _MiniGuideRow extends StatelessWidget {
  const _MiniGuideRow({
    required this.controller,
    required this.channel,
    required this.rowHeight,
  });

  final PlayerCoordinator controller;
  final Channel channel;
  final double? rowHeight;

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
    final spanMilliseconds = current == null
        ? 0
        : current.scheduled.end
              .difference(current.scheduled.start)
              .inMilliseconds;
    final progress = current == null || spanMilliseconds == 0
        ? 0.0
        : now.difference(current.scheduled.start).inMilliseconds /
              spanMilliseconds;
    final horizontal = rowHeight != null;
    final channelIdentity = Row(
      children: [
        Expanded(
          child: Text(
            channel.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
          ),
        ),
        if (tuned)
          Icon(
            Icons.play_circle_fill,
            size: horizontal ? 16 : 18,
            color: foreground,
          ),
      ],
    );
    final currentTitle = Text(
      current?.scheduled.item.title ?? 'Schedule loading…',
      key: Key('mini-guide-current-${channel.id}'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: foreground),
    );
    final progressBar = current == null
        ? null
        : LinearProgressIndicator(
            value: progress.clamp(0, 1),
            minHeight: 2,
            color: focused ? foreground : null,
            backgroundColor: focused
                ? foreground.withValues(alpha: 0.25)
                : null,
            semanticsLabel: 'Program progress',
          );
    final nextTitle = next == null
        ? null
        : Text(
            'Next • ${next.scheduled.item.title}',
            key: Key('mini-guide-next-${channel.id}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: foreground),
          );
    final tuneButton = IconButton(
      style: focused
          ? IconButton.styleFrom(
              foregroundColor: foreground,
              disabledForegroundColor: foreground.withValues(alpha: 0.70),
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
    );
    final number = SizedBox(
      width: 46,
      child: Text(
        '${channel.number}',
        style:
            (horizontal
                    ? Theme.of(context).textTheme.bodyLarge
                    : Theme.of(context).textTheme.titleMedium)
                ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
      ),
    );
    return Semantics(
      key: Key('mini-guide-row-${channel.id}'),
      selected: focused,
      label:
          'Channel ${channel.number}, ${channel.name}. Now ${current?.scheduled.item.title ?? 'schedule loading'}.${next == null ? '' : ' Next ${next.scheduled.item.title}.'}${tuned ? ' Now watching.' : ''}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: focused ? roles.focusedSurface : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: focused ? roles.focusBorder : Colors.transparent,
              width: focused ? roles.focusBorderWidth : 3,
            ),
            bottom: BorderSide(color: roles.subtleBorder),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => controller.focusMiniGuideChannel(channel.id),
            child: rowHeight == null
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        number,
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              channelIdentity,
                              currentTitle,
                              ?progressBar,
                              ?nextTitle,
                            ],
                          ),
                        ),
                        tuneButton,
                      ],
                    ),
                  )
                : SizedBox(
                    height: rowHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          number,
                          SizedBox(
                            width: (MediaQuery.sizeOf(context).width * 0.16)
                                .clamp(120, 260),
                            child: channelIdentity,
                          ),
                          const SizedBox(width: 16),
                          Expanded(child: currentTitle),
                          const SizedBox(width: 16),
                          if (progressBar != null)
                            SizedBox(
                              width: (MediaQuery.sizeOf(context).width * 0.12)
                                  .clamp(96, 220),
                              child: progressBar,
                            ),
                          if (nextTitle != null) ...[
                            const SizedBox(width: 16),
                            SizedBox(
                              width: (MediaQuery.sizeOf(context).width * 0.20)
                                  .clamp(140, 360),
                              child: nextTitle,
                            ),
                          ],
                          tuneButton,
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

class _Tracks extends StatefulWidget {
  const _Tracks({required this.controller, required this.type});
  final PlayerCoordinator controller;
  final PlayerTrackType type;

  @override
  State<_Tracks> createState() => _TracksState();
}

class _TracksState extends State<_Tracks> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    final tracks = widget.controller.tracks
        .where((track) => track.type == widget.type)
        .toList();
    final selectedIndex = tracks.indexWhere((track) => track.selected);
    final listIndex = selectedIndex < 0
        ? 0
        : selectedIndex + (widget.type == PlayerTrackType.subtitle ? 1 : 0);
    _scrollController = ScrollController(
      initialScrollOffset: (listIndex * 74.0 - 120).clamp(0, double.infinity),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tracks = widget.controller.tracks
        .where((track) => track.type == widget.type)
        .toList();
    final roles = LineupTheme.of(context);
    final selectedTrack = tracks.where((track) => track.selected).firstOrNull;
    return LayoutBuilder(
      builder: (context, constraints) {
        final railWidth = (constraints.maxWidth * 0.4).clamp(0.0, 420.0);
        final padding = constraints.maxWidth <= 800 ? 20.0 : 28.0;
        return Align(
          alignment: Alignment.centerRight,
          child: FocusScope(
            child: Container(
              key: const Key('playback-options-rail'),
              width: railWidth,
              height: double.infinity,
              padding: EdgeInsets.all(padding),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    roles.scrim.withValues(alpha: 0.54),
                    roles.scrim.withValues(alpha: 0.74),
                  ],
                ),
                border: Border(left: BorderSide(color: roles.subtleBorder)),
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(roles.panelRadius),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'PLAYBACK OPTIONS',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: roles.mutedText,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.type == PlayerTrackType.audio
                        ? 'Audio'
                        : 'Subtitles',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: ClipRect(
                      child: ListView.separated(
                        key: const Key('playback-options-list'),
                        controller: _scrollController,
                        itemCount:
                            tracks.length +
                            (widget.type == PlayerTrackType.subtitle ? 1 : 0),
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final off =
                              widget.type == PlayerTrackType.subtitle &&
                              index == 0;
                          final track = off
                              ? null
                              : tracks[index -
                                    (widget.type == PlayerTrackType.subtitle
                                        ? 1
                                        : 0)];
                          final selected = off
                              ? selectedTrack == null
                              : track!.selected;
                          final metadata = track == null
                              ? const <String>[]
                              : [
                                  if (track.language != null) track.language!,
                                  if (track.codec != null) track.codec!,
                                ];
                          final shape = RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              roles.panelRadius,
                            ),
                            side: BorderSide(
                              color: selected
                                  ? roles.progressFill
                                  : roles.subtleBorder,
                              width: selected ? 2 : 1,
                            ),
                          );
                          return Material(
                            color: Colors.transparent,
                            shape: shape,
                            clipBehavior: Clip.antiAlias,
                            child: ListTile(
                              key: Key(
                                off
                                    ? 'playback-track-off'
                                    : 'playback-track-${widget.type.name}-${track!.id}',
                              ),
                              autofocus: selected,
                              selected: selected,
                              selectedTileColor: roles.selectedSurface,
                              focusColor: roles.focusedSurface,
                              shape: shape,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 2,
                              ),
                              title: Text(
                                off
                                    ? 'Off'
                                    : track!.title ??
                                          track.language ??
                                          '${track.type.name} ${track.id}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: metadata.isEmpty
                                  ? null
                                  : Text(
                                      metadata.join(' • '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              trailing: selected
                                  ? Icon(
                                      Icons.check_circle,
                                      color: roles.progressFill,
                                      semanticLabel: 'Selected',
                                    )
                                  : null,
                              onTap: () => widget.controller.selectTrack(
                                widget.type,
                                track?.id,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    autofocus:
                        tracks.isEmpty &&
                        widget.type != PlayerTrackType.subtitle,
                    onPressed: widget.controller.closeOverlay,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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

Uri? _artworkPath(ChannelItem item, GuideArtworkKind kind) => switch (kind) {
  GuideArtworkKind.poster =>
    item.showThumb == null || item.showThumb!.isEmpty
        ? item.poster
        : Uri.tryParse(item.showThumb!) ?? item.poster,
  GuideArtworkKind.backdrop => item.backdrop,
  GuideArtworkKind.clearLogo => item.clearLogo,
};

String? _episodeLabel(ChannelItem item) {
  final season = item.seasonNumber;
  final episode = item.episodeNumber;
  if (season == null && episode == null) return null;
  return [
    if (season != null) 'Season $season',
    if (episode != null) 'Episode $episode',
  ].join(' • ');
}

String _time(BuildContext context, DateTime value) =>
    MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(value));

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
