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
    final dvrControlsEnabled = controller.lineup.settings.dvrControlsEnabled;
    final ordinaryPlayerContext =
        controller.overlay == PlayerOverlay.none ||
        controller.overlay == PlayerOverlay.osd ||
        controller.overlay == PlayerOverlay.nowPlaying;
    final mediaTransportKey =
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause ||
        key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaStop ||
        key == LogicalKeyboardKey.mediaRewind ||
        key == LogicalKeyboardKey.mediaFastForward;
    final keyboardTransportKey =
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.keyJ ||
        key == LogicalKeyboardKey.keyK ||
        key == LogicalKeyboardKey.keyL ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
    if (!dvrControlsEnabled &&
        (mediaTransportKey ||
            (ordinaryPlayerContext && keyboardTransportKey))) {
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
      unawaited(controller.play());
      if (showingNowPlaying) controller.showOsd();
    } else if (key == LogicalKeyboardKey.mediaPause) {
      unawaited(controller.pause());
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
    final rawPosition = controller.position.inMilliseconds;
    final position = duration > 0
        ? rawPosition.clamp(0, duration)
        : rawPosition < 0
        ? 0
        : rawPosition;
    final sliderMax = (duration > 0 ? duration : 1).toDouble();
    final sliderPosition = position.toDouble().clamp(0.0, sliderMax);
    final displayedPosition = Duration(milliseconds: position.toInt());
    final audioAvailable = controller.tracks.any(
      (track) => track.type == PlayerTrackType.audio,
    );
    final subtitlesAvailable = controller.tracks.any(
      (track) => track.type == PlayerTrackType.subtitle,
    );
    final unsupported = controller.status.state == PlayerState.unsupported;
    final dvrControlsEnabled = controller.lineup.settings.dvrControlsEnabled;
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
    final selectedAudio = controller.tracks
        .where((track) => track.type == PlayerTrackType.audio && track.selected)
        .firstOrNull;
    final selectedSubtitles = controller.tracks
        .where(
          (track) => track.type == PlayerTrackType.subtitle && track.selected,
        )
        .firstOrNull;
    final audioLabel = _osdTrackLabel('Audio', selectedAudio);
    final subtitlesLabel = selectedSubtitles == null
        ? '${expanded ? 'Subtitles' : 'Subs'} • Off'
        : _osdTrackLabel(expanded ? 'Subtitles' : 'Subs', selectedSubtitles);
    final sleepLabel = controller.sleepDuration == null
        ? 'Sleep • Off'
        : 'Sleep • ${controller.sleepDuration!.inMinutes}m';
    final optionActions = <Widget>[
      _osdAction(
        context,
        key: const Key('player-osd-subtitles'),
        label: subtitlesLabel,
        tooltip: subtitlesAvailable ? 'Subtitles' : 'Subtitles unavailable',
        icon: Icons.subtitles_outlined,
        onPressed: subtitlesAvailable
            ? () => controller.showTracks(PlayerTrackType.subtitle)
            : null,
        compact: !expanded,
      ),
      _osdAction(
        context,
        key: const Key('player-osd-audio'),
        label: audioLabel,
        tooltip: audioAvailable ? 'Audio tracks' : 'Audio tracks unavailable',
        icon: Icons.audiotrack,
        onPressed: audioAvailable
            ? () => controller.showTracks(PlayerTrackType.audio)
            : null,
        compact: !expanded,
      ),
      _osdAction(
        context,
        key: const Key('player-osd-sleep'),
        label: sleepLabel,
        tooltip: 'Sleep timer',
        icon: Icons.bedtime_outlined,
        onPressed: controller.cycleSleepTimer,
        compact: !expanded,
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
    final title = program?.scheduled.item.title ?? 'Nothing playing';
    final logoPath = program == null
        ? null
        : _artworkPath(program.scheduled.item, GuideArtworkKind.clearLogo);
    final statusFacts = [
      program?.scheduled.item.showTitle,
      _statusLabel(controller.status.state),
    ].nonNulls.toList(growable: false);
    final identity = Column(
      key: const Key('player-osd-identity'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (controller.lineup.settings.preferClearLogos &&
            program != null &&
            logoPath != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320, maxHeight: 68),
            child: _PlayerArtwork(
              key: ValueKey((
                program.id,
                controller.lineup.contentGeneration,
                logoPath,
              )),
              imageKey: const Key('player-osd-logo'),
              semanticLabel: title,
              future: controller.guide.artworkFor(
                program,
                GuideArtworkKind.clearLogo,
              ),
              fit: BoxFit.contain,
              fallback: _OsdTitle(title: title),
            ),
          )
        else
          _OsdTitle(title: title),
        if (statusFacts.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            statusFacts.join(' • '),
            key: const Key('player-osd-status'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: roles.secondaryText),
          ),
        ],
      ],
    );
    final progressValue = duration <= 0 ? 0.0 : position.toDouble() / duration;
    final remaining = duration <= 0
        ? null
        : _wholeMinutesLeft(
            displayedPosition,
            Duration(milliseconds: duration),
          );
    final progress = Row(
      key: const Key('player-osd-progress-block'),
      children: [
        Text(
          [
            '${_duration(displayedPosition)} / ${_duration(controller.duration)}',
            ?remaining,
          ].join(' • '),
          key: const Key('player-osd-timing'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: roles.secondaryText,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (next != null) ...[
          const SizedBox(width: 16),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Up next • ${_time(context, next.scheduled.start)} • '
                '${next.scheduled.item.title}',
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
        ],
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
        if (dvrControlsEnabled) actionGroup(transportActions, separated: false),
        actionGroup(optionActions, separated: dvrControlsEnabled),
        actionGroup(windowActions),
      ],
    );
    final progressLine = Positioned(
      key: const Key('player-osd-progress-line'),
      left: 0,
      right: 0,
      bottom: 0,
      child: SizedBox(
        height: 40,
        child: Semantics(
          label: 'Playback progress',
          value:
              '${_duration(displayedPosition)} of ${_duration(controller.duration)}',
          child: Stack(
            fit: StackFit.expand,
            children: [
              Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  height: 4,
                  child: LinearProgressIndicator(
                    value: progressValue,
                    color: roles.progressFill,
                    backgroundColor: roles.progressTrack,
                  ),
                ),
              ),
              if (dvrControlsEnabled)
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    activeTrackColor: Colors.transparent,
                    inactiveTrackColor: Colors.transparent,
                    thumbShape: SliderComponentShape.noThumb,
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    value: sliderPosition,
                    max: sliderMax,
                    onChanged: duration <= 0 || unsupported
                        ? null
                        : (value) => controller.seekTo(
                            Duration(milliseconds: value.round()),
                          ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        Align(
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
                12 + (dvrControlsEnabled ? 40 : 0),
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
                          Expanded(child: identity),
                          const SizedBox(width: 24),
                          groupedActions,
                        ],
                      )
                    else ...[
                      identity,
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          key: const Key('player-osd-stacked-controls'),
                          mainAxisSize: MainAxisSize.min,
                          children: [groupedActions],
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    progress,
                  ],
                ),
              ),
            ),
          ),
        ),
        if (channel != null)
          Positioned(
            top: 24,
            right: horizontalInset,
            child: _ChannelBug(
              key: const Key('player-osd-channel-bug'),
              channel: channel,
            ),
          ),
        progressLine,
      ],
    );
  }
}

class _OsdTitle extends StatelessWidget {
  const _OsdTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: title,
    excludeSemantics: true,
    child: Text(
      title,
      key: const Key('player-osd-title'),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w800),
    ),
  );
}

class _ChannelBug extends StatelessWidget {
  const _ChannelBug({required this.channel, super.key});

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    return Semantics(
      container: true,
      button: false,
      label: 'Channel ${channel.number}, ${channel.name}',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: roles.overlaySurface.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: roles.subtleBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            '${channel.number} • ${channel.name}',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: roles.primaryText,
              fontWeight: FontWeight.w800,
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
        ? (size.height * (item.cast.isEmpty ? 0.56 : 0.63))
              .clamp(300, 380)
              .toDouble()
        : (size.height * (item.cast.isEmpty ? 0.50 : 0.54))
              .clamp(
                item.cast.isEmpty ? 380 : 432,
                item.cast.isEmpty ? 560 : 580,
              )
              .toDouble();
    final denseShelf = compact || shelfHeight < 440;
    final showPoster = size.width >= 700 && size.height >= 500;
    final preferLogo = controller.lineup.settings.preferClearLogos;
    final posterPath = _artworkPath(item, GuideArtworkKind.poster);
    final logoPath = _artworkPath(item, GuideArtworkKind.clearLogo);
    final generation = controller.lineup.contentGeneration;
    final elapsed = controller.guide.now.difference(program.scheduled.start);
    final span = program.scheduled.end.difference(program.scheduled.start);
    final nativeDuration = controller.duration;
    final nativeTimingAvailable = nativeDuration > Duration.zero;
    final timingDuration = nativeTimingAvailable ? nativeDuration : span;
    final rawTimingPosition = nativeTimingAvailable
        ? controller.position
        : elapsed;
    final timingPosition = timingDuration <= Duration.zero
        ? Duration.zero
        : Duration(
            milliseconds: rawTimingPosition.inMilliseconds
                .clamp(0, timingDuration.inMilliseconds)
                .toInt(),
          );
    final progress = timingDuration.inMilliseconds <= 0
        ? 0.0
        : timingPosition.inMilliseconds / timingDuration.inMilliseconds;
    final episode = _episodeLabel(item);
    final dynamicRange = _dynamicRangeLabel(item.dynamicRange, telemetry.isHdr);
    final badges = <String>[
      ?item.contentRating,
      if (item.resolution case final resolution?) resolution.toUpperCase(),
      ?dynamicRange,
      if (item.audioCodec case final audioCodec?) audioCodec.toUpperCase(),
      if (item.audioChannels case final channels?) _audioChannels(channels),
    ];
    final editorial = [
      if (item.year != null) '${item.year}',
      ...item.genres.where((genre) => genre.trim().isNotEmpty).take(3),
    ].join(' • ');
    final itemResolution = item.resolution?.toLowerCase();
    final dimensions = telemetry.width != null && telemetry.height != null
        ? '${telemetry.width}×${telemetry.height}'
        : null;
    final dimensionsMatchCatalog =
        dimensions != null &&
        ((itemResolution == '1080p' && telemetry.height == 1080) ||
            (itemResolution == '720p' && telemetry.height == 720) ||
            (itemResolution == '4k' &&
                telemetry.height != null &&
                telemetry.height! >= 2000));
    final runtimeFacts = <String>[
      if (dimensions != null && !dimensionsMatchCatalog) dimensions,
      if (telemetry.videoCodec case final videoCodec?) videoCodec.toUpperCase(),
      ?telemetry.hardwareDecoder,
    ];
    final playbackFacts = runtimeFacts.isEmpty
        ? switch (item.videoCodec) {
            final codec? when codec.trim().isNotEmpty =>
              'Source • ${codec.toUpperCase()}',
            _ => null,
          }
        : ['Playback', ...runtimeFacts].join(' • ');
    final playbackTime =
        '${_duration(timingPosition)} / ${_duration(timingDuration)}';
    final castFacts = item.cast
        .map(
          (member) => member.role == null
              ? member.name
              : '${member.name} as ${member.role}',
        )
        .join(', ');
    final semanticFacts = [
      'Now playing',
      ?item.showTitle,
      item.title,
      ?episode,
      if (timingDuration > Duration.zero)
        '${_humanDuration(timingDuration)} runtime',
      if (editorial.isNotEmpty) editorial,
      ...badges,
      ?playbackFacts,
      '$playbackTime playback',
      ?item.summary,
      if (castFacts.isNotEmpty) 'Cast: $castFacts',
    ].join('. ');
    final artworkIdentity = (program.id, generation);

    return Stack(
      fit: StackFit.expand,
      children: [
        Align(
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
                                      future: controller.guide.artworkFor(
                                        program,
                                      ),
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
                                  hasCast: item.cast.isNotEmpty,
                                )
                              else
                                _NowPlayingTitle(
                                  item: item,
                                  compact: denseShelf,
                                ),
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
                              if (timingDuration > Duration.zero) ...[
                                SizedBox(height: denseShelf ? 4 : 6),
                                Text(
                                  _humanDuration(timingDuration),
                                  key: const Key('player-now-playing-runtime'),
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: roles.mutedText),
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
                              if (!compact && playbackFacts != null) ...[
                                SizedBox(height: denseShelf ? 8 : 10),
                                Text(
                                  playbackFacts,
                                  key: const Key(
                                    'player-now-playing-runtime-facts',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: roles.mutedText),
                                ),
                              ],
                              if (editorial.isNotEmpty) ...[
                                SizedBox(height: denseShelf ? 8 : 10),
                                Text(
                                  editorial,
                                  key: const Key(
                                    'player-now-playing-editorial',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: roles.mutedText),
                                ),
                              ],
                              if (item.summary case final summary?) ...[
                                SizedBox(height: denseShelf ? 10 : 14),
                                Text(
                                  summary,
                                  key: const Key('player-now-playing-summary'),
                                  maxLines: item.cast.isEmpty
                                      ? (denseShelf ? 3 : 4)
                                      : (denseShelf ? 2 : 3),
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(
                                        color: roles.primaryText,
                                        height: 1.45,
                                      ),
                                ),
                              ],
                              if (item.cast.isNotEmpty) ...[
                                SizedBox(height: denseShelf ? 10 : 14),
                                _NowPlayingCast(
                                  controller: controller,
                                  cast: item.cast,
                                  compact: compact,
                                  dense: denseShelf,
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
                                playbackTime,
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
        ),
        if (channel != null)
          Positioned(
            top: 24,
            right: (size.width * 0.05).clamp(24.0, 96.0),
            child: _ChannelBug(
              key: const Key('player-now-playing-channel-bug'),
              channel: channel,
            ),
          ),
      ],
    );
  }
}

class _NowPlayingIdentity extends StatefulWidget {
  const _NowPlayingIdentity({
    required this.controller,
    required this.program,
    required this.compact,
    required this.hasCast,
    super.key,
  });

  final PlayerCoordinator controller;
  final GuideProgram program;
  final bool compact;
  final bool hasCast;

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
              maxHeight: widget.hasCast && widget.compact
                  ? 58
                  : widget.compact
                  ? 84
                  : 132,
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
    this.imageKey,
    this.semanticLabel,
    super.key,
  });

  final Future<Uint8List?> future;
  final BoxFit fit;
  final Widget fallback;
  final Key? imageKey;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: future,
    builder: (context, snapshot) => snapshot.data == null
        ? fallback
        : Image.memory(
            snapshot.data!,
            key: imageKey,
            fit: fit,
            gaplessPlayback: false,
            semanticLabel: semanticLabel,
            excludeFromSemantics: semanticLabel == null,
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

class _NowPlayingCast extends StatelessWidget {
  const _NowPlayingCast({
    required this.controller,
    required this.cast,
    required this.compact,
    required this.dense,
  });

  final PlayerCoordinator controller;
  final List<ChannelCastMember> cast;
  final bool compact;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final limit = compact ? 4 : 5;
    final visible = cast.take(limit).toList(growable: false);
    final hidden = cast.length - visible.length;
    final diameter = dense ? 40.0 : 46.0;
    return Column(
      key: const Key('player-now-playing-cast'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final (index, member) in visible.indexed) ...[
              if (index > 0) const SizedBox(width: 8),
              SizedBox.square(
                key: ValueKey('player-now-playing-cast-portrait-$index'),
                dimension: diameter,
                child: ClipOval(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: roles.elevatedSurface,
                      border: Border.all(color: roles.subtleBorder),
                      shape: BoxShape.circle,
                    ),
                    child: member.portrait == null
                        ? _CastFallback(index: index, roles: roles)
                        : _PlayerArtwork(
                            future: controller.guide.artworkForPath(
                              member.portrait!,
                            ),
                            fit: BoxFit.cover,
                            fallback: _CastFallback(index: index, roles: roles),
                          ),
                  ),
                ),
              ),
            ],
            if (hidden > 0) ...[
              const SizedBox(width: 8),
              SizedBox.square(
                dimension: diameter,
                child: DecoratedBox(
                  key: const Key('player-now-playing-cast-more'),
                  decoration: BoxDecoration(
                    color: roles.elevatedSurface,
                    border: Border.all(color: roles.subtleBorder),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '+$hidden',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: roles.primaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          cast.map((member) => member.name).join(' • '),
          key: const Key('player-now-playing-cast-names'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: roles.secondaryText),
        ),
      ],
    );
  }
}

class _CastFallback extends StatelessWidget {
  const _CastFallback({required this.index, required this.roles});

  final int index;
  final LineupThemeRoles roles;

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: ValueKey('player-now-playing-cast-fallback-$index'),
    color: roles.elevatedSurface,
    child: Icon(Icons.person, color: roles.mutedText),
  );
}

class _MiniGuide extends StatelessWidget {
  const _MiniGuide({required this.controller});
  final PlayerCoordinator controller;

  @override
  Widget build(BuildContext context) {
    final channels = controller.miniGuideChannels;
    final roles = LineupTheme.of(context);
    final size = MediaQuery.sizeOf(context);
    final horizontal =
        size.height >= 720 && !LineupLayout.isCompactWidth(size.width);
    final rowHeight = horizontal ? (size.height >= 900 ? 48.0 : 56.0) : null;
    final compressed = size.height >= 900;
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        bottom: false,
        child: Container(
          key: const Key('mini-guide-shelf'),
          width: double.infinity,
          constraints: BoxConstraints(maxHeight: size.height),
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

String? _wholeMinutesLeft(Duration position, Duration duration) {
  if (duration <= Duration.zero) return null;
  final remaining = duration - position;
  if (remaining <= Duration.zero) return '0m left';
  const millisecondsPerMinute =
      Duration.secondsPerMinute * Duration.millisecondsPerSecond;
  final minutes =
      (remaining.inMilliseconds + millisecondsPerMinute - 1) ~/
      millisecondsPerMinute;
  return '${minutes}m left';
}

String _osdTrackLabel(String category, PlayerTrack? track) {
  final title = track?.title?.trim();
  final language = track?.language?.trim();
  final detail = title?.isNotEmpty == true
      ? title
      : language?.isNotEmpty == true
      ? language
      : null;
  return detail == null ? category : '$category • $detail';
}

Widget _osdAction(
  BuildContext context, {
  required Key key,
  required String label,
  required String tooltip,
  required IconData icon,
  required VoidCallback? onPressed,
  required bool compact,
}) {
  final roles = LineupTheme.of(context);
  return ConstrainedBox(
    constraints: BoxConstraints(maxWidth: compact ? 132 : 180),
    child: Tooltip(
      message: tooltip,
      child: TextButton.icon(
        key: key,
        onPressed: onPressed,
        icon: Icon(icon, size: compact ? 17 : 18),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: TextButton.styleFrom(
          foregroundColor: roles.primaryText,
          padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 8),
          minimumSize: const Size(0, 40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      ),
    ),
  );
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

String? _dynamicRangeLabel(String? value, bool telemetryIsHdr) {
  final catalog = switch (value?.toLowerCase()) {
    'sdr' => 'SDR',
    'hdr' => 'HDR',
    'hdr10' => 'HDR10',
    'hlg' => 'HLG',
    'dolbyvision' || 'dolby vision' => 'DOLBY VISION',
    final value? when value.trim().isNotEmpty => value.toUpperCase(),
    _ => null,
  };
  if (!telemetryIsHdr) return catalog;
  return switch (catalog) {
    'HDR10' || 'HLG' || 'DOLBY VISION' => catalog,
    _ => 'HDR',
  };
}

String _audioChannels(int channels) => switch (channels) {
  1 => 'MONO',
  2 => 'STEREO',
  6 => '5.1',
  8 => '7.1',
  _ => '${channels}ch',
};

String _humanDuration(Duration value) {
  final minutes = value.inMinutes;
  final hours = minutes ~/ 60;
  final remainder = minutes.remainder(60);
  if (hours == 0) return '${remainder}m';
  if (remainder == 0) return '${hours}h';
  return '${hours}h ${remainder}m';
}

String _time(BuildContext context, DateTime value) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(value.toLocal()),
      alwaysUse24HourFormat: false,
    );

String? _statusLabel(PlayerState state) => switch (state) {
  PlayerState.idle => null,
  PlayerState.loading => 'Loading',
  PlayerState.ready => null,
  PlayerState.playing => null,
  PlayerState.paused => 'Paused',
  PlayerState.buffering => 'Buffering',
  PlayerState.seeking => 'Seeking',
  PlayerState.ended => 'Ended',
  PlayerState.stopped => 'Stopped',
  PlayerState.error => 'Playback error',
  PlayerState.unsupported => 'Unsupported',
};
