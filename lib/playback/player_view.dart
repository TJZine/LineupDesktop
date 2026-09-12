import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../channels/channel.dart';
import '../guide/guide_controller.dart';
import '../guide/focused_ticker.dart';
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
  final LineupMenuCallback? openMenu;
  final FocusNode? focusNode;

  @override
  State<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<PlayerView> with WidgetsBindingObserver {
  late PlayerOverlay _renderedOverlay;
  var _overlayTransitionDuration = const Duration(milliseconds: 350);
  final _menuFocus = FocusNode(debugLabel: 'Player Lineup menu');
  final _sleepFocus = FocusNode(debugLabel: 'Player sleep timer');
  Timer? _sleepCountdownTimer;
  var _appActive = true;

  @override
  void initState() {
    super.initState();
    _renderedOverlay = widget.controller.overlay;
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_changed);
    _syncSleepCountdownTimer();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    _sleepCountdownTimer?.cancel();
    _menuFocus.dispose();
    _sleepFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (_appActive == active) return;
    setState(() => _appActive = active);
    _syncSleepCountdownTimer();
    if (active) unawaited(widget.controller.checkSleepDeadline());
  }

  void _changed() {
    if (!mounted) return;
    _syncSleepCountdownTimer();
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

  void _syncSleepCountdownTimer() {
    final showCountdown =
        _appActive &&
        widget.controller.overlay == PlayerOverlay.sleepTimer &&
        widget.controller.sleepDeadline != null;
    if (!showCountdown) {
      _sleepCountdownTimer?.cancel();
      _sleepCountdownTimer = null;
      return;
    }
    _sleepCountdownTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      if (!_appActive ||
          widget.controller.overlay != PlayerOverlay.sleepTimer ||
          widget.controller.sleepDeadline == null) {
        _syncSleepCountdownTimer();
        return;
      }
      setState(() {});
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
        final restoreSleep = controller.overlay == PlayerOverlay.sleepTimer;
        controller.closeOverlay();
        if (restoreSleep) _restoreSleepFocus();
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
      controller.showSleepTimer();
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

  void _restoreSleepFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sleepFocus.requestFocus();
    });
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
            onTap: () {
              if (controller.overlay == PlayerOverlay.miniGuide) {
                controller.closeOverlay();
              } else if (controller.overlay == PlayerOverlay.sleepTimer) {
                controller.closeOverlay();
                _restoreSleepFocus();
              } else {
                controller.showOsd();
              }
            },
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
                        menuFocus: _menuFocus,
                        sleepFocus: _sleepFocus,
                      ),
                      PlayerOverlay.nowPlaying => _NowPlaying(
                        controller: controller,
                      ),
                      PlayerOverlay.miniGuide => _MiniGuide(
                        controller: controller,
                        active: _appActive,
                        openGuide: widget.openGuide,
                      ),
                      PlayerOverlay.audioTracks => _Tracks(
                        controller: controller,
                        type: PlayerTrackType.audio,
                      ),
                      PlayerOverlay.subtitleTracks => _Tracks(
                        controller: controller,
                        type: PlayerTrackType.subtitle,
                      ),
                      PlayerOverlay.sleepTimer => _SleepTimerPicker(
                        controller: controller,
                        triggerFocus: _sleepFocus,
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
  const _Osd({
    required this.controller,
    required this.menuFocus,
    required this.sleepFocus,
    this.openMenu,
  });
  final PlayerCoordinator controller;
  final LineupMenuCallback? openMenu;
  final FocusNode menuFocus;
  final FocusNode sleepFocus;

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
    final largeDesktop = size.width >= 1920 && size.height >= 900;
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
    final sleepRemaining = controller.sleepRemaining;
    final remainingMinutes = sleepRemaining == null
        ? null
        : (sleepRemaining.inSeconds / Duration.secondsPerMinute).ceil();
    final sleepLabel = remainingMinutes == null
        ? 'Sleep'
        : 'Stops in $remainingMinutes min';
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
        tooltip: sleepRemaining == null ? 'Stop playback after…' : sleepLabel,
        icon: Icons.bedtime_outlined,
        focusNode: sleepFocus,
        onPressed: controller.showSleepTimer,
        compact: !expanded,
      ),
    ];
    final windowActions = <Widget>[
      if (openMenu != null)
        Builder(
          builder: (invokerContext) => IconButton(
            key: const Key('player-app-menu'),
            focusNode: menuFocus,
            tooltip: 'Open Lineup menu',
            onPressed: () => openMenu!(invokerContext, menuFocus),
            icon: const Icon(Icons.menu),
          ),
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
    final item = program?.scheduled.item;
    final showTitle = item?.showTitle?.trim();
    final primaryTitle = showTitle?.isNotEmpty == true ? showTitle! : title;
    final episodeFacts = item == null ? null : _osdEpisodeFacts(item);
    final statusFacts = [
      episodeFacts,
      _statusLabel(controller.status.state),
    ].nonNulls.toList(growable: false);
    final identity = Column(
      key: const Key('player-osd-identity'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (controller.lineup.settings.preferClearLogos &&
            program != null &&
            logoPath != null)
          _PlayerArtwork(
            key: ValueKey((
              program.id,
              controller.lineup.contentGeneration,
              logoPath,
            )),
            imageKey: const Key('player-osd-logo'),
            semanticLabel: primaryTitle,
            future: controller.guide.artworkFor(
              program,
              GuideArtworkKind.clearLogo,
            ),
            fit: BoxFit.contain,
            fallback: _OsdTitle(title: primaryTitle),
            clearLogo: true,
            logoMaximumSize: Size(
              size.width >= 1920 ? 520 : 360,
              size.height >= 900 ? 128 : 72,
            ),
            logoMinimumVisibleSize: Size(96, size.height >= 900 ? 28 : 24),
          )
        else
          _OsdTitle(title: primaryTitle),
        if (statusFacts.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            statusFacts.join(' • '),
            key: const Key('player-osd-status'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: roles.primaryText.withValues(alpha: 0.88),
              fontSize: largeDesktop ? 16 : 14,
              fontWeight: FontWeight.w400,
            ),
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
    final osdSecondaryStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: roles.primaryText.withValues(alpha: 0.88),
      fontSize: horizontal ? (largeDesktop ? 16 : 14) : null,
      fontWeight: FontWeight.w400,
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
          style: osdSecondaryStyle?.copyWith(
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
                style: osdSecondaryStyle,
              ),
            ),
          ),
        ],
      ],
    );
    Widget actionGroup(List<Widget> children) =>
        Row(mainAxisSize: MainAxisSize.min, children: children);
    final groupedActions = Row(
      key: const Key('player-osd-action-groups'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dvrControlsEnabled) ...[
          actionGroup(transportActions),
          const SizedBox(width: 16),
        ],
        actionGroup(optionActions),
        const SizedBox(width: 16),
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
              osdPresentation: true,
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
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final largeDesktop = size.width >= 1920 && size.height >= 900;
    final horizontal = size.width >= 1200 && size.height >= 640;
    return Semantics(
      container: true,
      label: title,
      excludeSemantics: true,
      child: Text(
        title,
        key: const Key('player-osd-title'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: LineupTheme.of(context).primaryText,
          fontSize: largeDesktop
              ? 28
              : horizontal
              ? 24
              : null,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ChannelBug extends StatelessWidget {
  const _ChannelBug({
    required this.channel,
    this.osdPresentation = false,
    super.key,
  });

  final Channel channel;
  final bool osdPresentation;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final size = MediaQuery.sizeOf(context);
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
              fontSize: osdPresentation
                  ? (size.width >= 1920 && size.height >= 900 ? 16 : 14)
                  : null,
              fontWeight: osdPresentation ? FontWeight.w500 : FontWeight.w800,
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
    final episodeFacts = [
      if (item.seasonNumber != null) 'S${item.seasonNumber}',
      if (item.episodeNumber != null) 'E${item.episodeNumber}',
      if (timingDuration > Duration.zero) '${timingDuration.inMinutes} min',
    ].join(' · ');
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
                  child: _NowPlayingShelfLayout(
                    maxHeight: shelfHeight,
                    poster: showPoster
                        ? Stack(
                            key: const Key('player-now-playing-poster'),
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
                          )
                        : null,
                    content: Padding(
                      padding: EdgeInsets.fromLTRB(
                        denseShelf ? 18 : 28,
                        denseShelf ? 16 : 24,
                        denseShelf ? 18 : 28,
                        denseShelf ? 14 : 20,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Flexible(
                            fit: FlexFit.loose,
                            child: SingleChildScrollView(
                              key: const Key('player-now-playing-details'),
                              primary: false,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                  if (episodeFacts.isNotEmpty) ...[
                                    SizedBox(height: denseShelf ? 8 : 10),
                                    Text(
                                      episodeFacts,
                                      key: const Key(
                                        'player-now-playing-episode',
                                      ),
                                      style: _nowPlayingSecondaryStyle(
                                        context,
                                        dense: denseShelf,
                                      ),
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
                                      style: _nowPlayingSecondaryStyle(
                                        context,
                                        dense: denseShelf,
                                      ),
                                    ),
                                  ],
                                  if (!compact && badges.isNotEmpty) ...[
                                    const SizedBox(height: 14),
                                    Wrap(
                                      key: const Key(
                                        'player-now-playing-badges',
                                      ),
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
                                      style: _nowPlayingSecondaryStyle(
                                        context,
                                        dense: denseShelf,
                                      ),
                                    ),
                                  ],
                                  if (item.summary case final summary?) ...[
                                    SizedBox(height: denseShelf ? 10 : 14),
                                    Text(
                                      summary,
                                      key: const Key(
                                        'player-now-playing-summary',
                                      ),
                                      maxLines: item.cast.isEmpty
                                          ? (denseShelf ? 3 : 4)
                                          : (denseShelf ? 2 : 3),
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
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
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
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
                            style: _nowPlayingSecondaryStyle(
                              context,
                              dense: denseShelf,
                            ),
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

class _NowPlayingShelfLayout extends StatelessWidget {
  const _NowPlayingShelfLayout({
    required this.maxHeight,
    required this.content,
    this.poster,
  });
  final double maxHeight;
  final Widget content;
  final Widget? poster;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxHeight: maxHeight - 1),
    child: Stack(
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: poster == null
                ? 0
                : (maxHeight * 2 / 3).clamp(190, 374).toDouble(),
          ),
          child: content,
        ),
        if (poster != null)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: (maxHeight * 2 / 3).clamp(190, 374).toDouble(),
            child: poster!,
          ),
      ],
    ),
  );
}

TextStyle? _nowPlayingSecondaryStyle(
  BuildContext context, {
  required bool dense,
}) => Theme.of(context).textTheme.bodyMedium?.copyWith(
  color: LineupTheme.of(context).primaryText.withValues(alpha: 0.88),
  fontSize: dense ? 14 : 16,
);

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
      final item = widget.program.scheduled.item;
      final showTitle = item.showTitle?.trim();
      final logoMaxHeight = widget.hasCast && widget.compact
          ? 58.0
          : widget.compact
          ? 84.0
          : 132.0;
      final logoMaxWidth = widget.compact ? 360.0 : 600.0;
      return LayoutBuilder(
        builder: (context, available) {
          final logoFallback = OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: 0,
            maxWidth: available.maxWidth,
            minHeight: 0,
            maxHeight: double.infinity,
            fit: OverflowBoxFit.deferToChild,
            child: switch (showTitle) {
              final value? when value.isNotEmpty => Text(
                value,
                key: const Key('player-now-playing-series'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _nowPlayingSeriesStyle(context, dense: widget.compact),
              ),
              _ => const SizedBox.shrink(),
            },
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (bytes == null)
                logoFallback
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.min(available.maxWidth, logoMaxWidth),
                    maxHeight: logoMaxHeight,
                  ),
                  child: ClearLogoImage(
                    bytes,
                    imageKey: const Key('player-now-playing-logo'),
                    excludeFromSemantics: true,
                    maximumSize: Size(logoMaxWidth, logoMaxHeight),
                    minimumVisibleSize: Size(96, widget.compact ? 20 : 28),
                    fallback: logoFallback,
                  ),
                ),
              SizedBox(height: widget.compact ? 8 : 12),
              Text(
                widget.program.scheduled.item.title,
                key: const Key('player-now-playing-title'),
                maxLines: widget.compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: _nowPlayingTitleStyle(context, dense: widget.compact),
              ),
            ],
          );
        },
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
          item.showTitle!.trim(),
          key: const Key('player-now-playing-series'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _nowPlayingSeriesStyle(context, dense: compact),
        ),
        const SizedBox(height: 6),
      ],
      Text(
        item.title,
        key: const Key('player-now-playing-title'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: _nowPlayingTitleStyle(context, dense: compact),
      ),
    ],
  );
}

TextStyle? _nowPlayingSeriesStyle(
  BuildContext context, {
  required bool dense,
}) => _nowPlayingSecondaryStyle(
  context,
  dense: dense,
)?.copyWith(fontSize: dense ? 16 : 20, fontWeight: FontWeight.w500);

TextStyle _nowPlayingTitleStyle(BuildContext context, {required bool dense}) =>
    (Theme.of(context).textTheme.bodyLarge ?? const TextStyle()).copyWith(
      color: LineupTheme.of(context).primaryText,
      fontSize: dense ? 24 : 28,
      fontWeight: FontWeight.w600,
    );

/*
 * Keep the logo bounds on the image path only. ClearLogoImage's fallback is
 * intentionally independent so a failed logo cannot constrain the title.
 */

class _PlayerArtwork extends StatelessWidget {
  const _PlayerArtwork({
    required this.future,
    required this.fit,
    this.fallback = const SizedBox.shrink(),
    this.imageKey,
    this.semanticLabel,
    this.clearLogo = false,
    this.logoMaximumSize,
    this.logoMinimumVisibleSize,
    super.key,
  });

  final Future<Uint8List?> future;
  final BoxFit fit;
  final Widget fallback;
  final Key? imageKey;
  final String? semanticLabel;
  final bool clearLogo;
  final Size? logoMaximumSize;
  final Size? logoMinimumVisibleSize;

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: future,
    builder: (context, snapshot) => snapshot.data == null
        ? fallback
        : clearLogo
        ? ClearLogoImage(
            snapshot.data!,
            maximumSize: logoMaximumSize,
            minimumVisibleSize: logoMinimumVisibleSize,
            fallback: fallback,
            imageKey: imageKey,
            semanticLabel: semanticLabel,
            excludeFromSemantics: semanticLabel == null,
          )
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
    final columnLimit = dense ? 72.0 : 104.0;
    final columnCount = visible.length + (hidden > 0 ? 1 : 0);
    final spacing = math.max(0, columnCount - 1) * 8.0;
    return Column(
      key: const Key('player-now-playing-cast'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : columnCount * columnLimit + spacing;
            final columnWidth = math.min(
              columnLimit,
              math.max(0.0, (width - spacing) / columnCount),
            );
            final constrained = width < columnCount * columnLimit + spacing;
            final children = <Widget>[
              for (final (index, member) in visible.indexed)
                _NowPlayingCastColumn(
                  key: ValueKey('player-now-playing-cast-column-$index'),
                  width: columnWidth,
                  diameter: diameter,
                  index: index,
                  member: member,
                  controller: controller,
                  roles: roles,
                  dense: dense,
                ),
              if (hidden > 0)
                _NowPlayingCastMore(
                  width: columnWidth,
                  diameter: diameter,
                  hidden: hidden,
                  roles: roles,
                ),
            ];
            return constrained
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final child in children)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: child == children.last ? 0 : 8,
                            ),
                            child: child,
                          ),
                        ),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (index, child) in children.indexed) ...[
                        if (index > 0) const SizedBox(width: 8),
                        child,
                      ],
                    ],
                  );
          },
        ),
      ],
    );
  }
}

class _NowPlayingCastColumn extends StatelessWidget {
  const _NowPlayingCastColumn({
    required this.width,
    required this.diameter,
    required this.index,
    required this.member,
    required this.controller,
    required this.roles,
    required this.dense,
    super.key,
  });

  final double width;
  final double diameter;
  final int index;
  final ChannelCastMember member;
  final PlayerCoordinator controller;
  final LineupThemeRoles roles;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final portrait = member.portrait;
    final nameStyle = _nowPlayingSecondaryStyle(
      context,
      dense: dense,
    )?.copyWith(fontSize: dense ? 12 : 14, height: 1.3);
    var displayName = member.name;
    final words = member.name.trim().split(RegExp(r'\s+'));
    if (words.length > 2) {
      final measure = TextPainter(
        text: TextSpan(text: member.name, style: nameStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        maxLines: 2,
      )..layout(maxWidth: width);
      if (measure.didExceedMaxLines) {
        displayName = [
          words.first,
          ...words
              .skip(1)
              .take(words.length - 2)
              .map((word) => '${word.characters.first}.'),
          words.last,
        ].join(' ');
      }
      measure.dispose();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
              child: portrait == null
                  ? _CastFallback(index: index, roles: roles)
                  : _PlayerArtwork(
                      future: controller.guide.artworkForPath(portrait),
                      fit: BoxFit.cover,
                      fallback: _CastFallback(index: index, roles: roles),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: width,
          height:
              MediaQuery.textScalerOf(context).scale(dense ? 12 : 14) * 1.3 * 2,
          child: Tooltip(
            message: member.name,
            excludeFromSemantics: true,
            child: Text(
              displayName,
              key: ValueKey('player-now-playing-cast-name-$index'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: nameStyle,
            ),
          ),
        ),
      ],
    );
  }
}

class _NowPlayingCastMore extends StatelessWidget {
  const _NowPlayingCastMore({
    required this.width,
    required this.diameter,
    required this.hidden,
    required this.roles,
  });

  final double width;
  final double diameter;
  final int hidden;
  final LineupThemeRoles roles;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
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
      const SizedBox(height: 6),
      SizedBox(width: width, child: const SizedBox.shrink()),
    ],
  );
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
  const _MiniGuide({
    required this.controller,
    required this.active,
    required this.openGuide,
  });
  final PlayerCoordinator controller;
  final bool active;
  final VoidCallback openGuide;

  @override
  Widget build(BuildContext context) {
    final channels = controller.miniGuideChannels;
    final roles = LineupTheme.of(context);
    final size = MediaQuery.sizeOf(context);
    final scale = LineupLayout.scaleFor(size);
    final horizontal =
        size.height >= 720 && !LineupLayout.isCompactWidth(size.width);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final layoutTextScale = textScale < 1 ? 1.0 : textScale;
    final large = horizontal && size.width >= 1920 && size.height >= 1080;
    final rowHeight = horizontal
        ? (large ? 66.0 : 56.0) * scale * layoutTextScale
        : null;
    final channelColumnWidth = (large ? 365.0 : 250.0) * scale;
    final columnGap = (large ? 36.0 : 24.0) * scale;
    final contentInset =
        (horizontal ? (large ? 48.0 : 32.0) : roles.overlaySafeArea) * scale;
    final rowInset = (large ? 18.0 : 12.0) * scale;
    final fadeTail = (large ? 110.0 : 80.0) * scale;
    final scaledTheme = Theme.of(context).copyWith(
      textTheme: Theme.of(context).textTheme.apply(fontSizeFactor: scale),
    );
    return Theme(
      data: scaledTheme,
      child: DefaultTextStyle(
        style: scaledTheme.textTheme.bodyMedium!,
        child: Builder(
          builder: (context) => Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              bottom: false,
              child: CustomPaint(
                painter: _MiniGuideFadePainter(
                  scrim: roles.scrim,
                  tailHeight: fadeTail,
                ),
                child: Container(
                  key: const Key('mini-guide-shelf'),
                  width: double.infinity,
                  constraints: BoxConstraints(maxHeight: size.height),
                  padding: EdgeInsets.fromLTRB(
                    contentInset,
                    12 * scale,
                    contentInset,
                    16 * scale,
                  ),
                  child: Semantics(
                    container: true,
                    explicitChildNodes: true,
                    label: 'Mini Guide',
                    child: SingleChildScrollView(
                      key: const Key('mini-guide-scroll'),
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerSignal: (event) {
                          if (event is! PointerScrollEvent ||
                              event.scrollDelta.dy == 0) {
                            return;
                          }
                          GestureBinding.instance.pointerSignalResolver
                              .register(event, (_) {
                                controller.moveMiniGuide(
                                  event.scrollDelta.dy > 0 ? 1 : -1,
                                );
                              });
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 12 * scale,
                              runSpacing: 4 * scale,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ExcludeSemantics(
                                      child: Text(
                                        'Mini Guide',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              fontSize:
                                                  (large ? 26 : 20) * scale,
                                              fontWeight: FontWeight.w500,
                                            ),
                                      ),
                                    ),
                                    SizedBox(width: 20 * scale),
                                    Text(
                                      _time(context, controller.guide.now),
                                      style: TextStyle(
                                        color: roles.secondaryText,
                                        fontSize: (large ? 18 : 14) * scale,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        foregroundColor: roles.secondaryText,
                                        minimumSize: Size(0, 44 * scale),
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 8 * scale,
                                        ),
                                        textStyle: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              fontSize:
                                                  (large ? 18 : 14) * scale,
                                              fontWeight: FontWeight.w400,
                                            ),
                                      ),
                                      onPressed: () {
                                        controller.showFullGuide();
                                        openGuide();
                                      },
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text('Full Guide'),
                                          SizedBox(width: 8 * scale),
                                          const ExcludeSemantics(
                                            child: Icon(
                                              Icons.arrow_forward,
                                              size: 16,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        foregroundColor: roles.secondaryText,
                                        minimumSize: Size(0, 44 * scale),
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 8 * scale,
                                        ),
                                        textStyle: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              fontSize:
                                                  (large ? 18 : 14) * scale,
                                              fontWeight: FontWeight.w400,
                                            ),
                                      ),
                                      onPressed: controller.closeOverlay,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text('Close'),
                                          SizedBox(width: 8 * scale),
                                          const ExcludeSemantics(
                                            child: Icon(Icons.close, size: 16),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            if (horizontal)
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                  rowInset,
                                  0,
                                  rowInset,
                                  large ? 8 * scale : 6 * scale,
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: channelColumnWidth,
                                      child: Text(
                                        'Channel',
                                        style: TextStyle(
                                          color: roles.secondaryText,
                                          fontSize: (large ? 16 : 12) * scale,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: columnGap),
                                    Expanded(
                                      flex: 115,
                                      child: Text(
                                        'On now',
                                        style: TextStyle(
                                          color: roles.secondaryText,
                                          fontSize: (large ? 16 : 12) * scale,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: columnGap),
                                    Expanded(
                                      flex: 100,
                                      child: Text(
                                        'Up next',
                                        style: TextStyle(
                                          color: roles.secondaryText,
                                          fontSize: (large ? 16 : 12) * scale,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            for (final (index, channel) in channels.indexed)
                              _MiniGuideRow(
                                controller: controller,
                                channel: channel,
                                rowHeight: rowHeight,
                                channelColumnWidth: channelColumnWidth,
                                columnGap: columnGap,
                                active: active,
                                large: large,
                                scale: scale,
                                rowInset: rowInset,
                                isLast: index == channels.length - 1,
                              ),
                            SizedBox(height: 8 * scale),
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 12 * scale,
                              runSpacing: 4 * scale,
                              children: [
                                Text(
                                  'Up / Down · Browse · Enter Tune · Esc Close',
                                  style: TextStyle(
                                    color: roles.secondaryText,
                                    fontSize: (large ? 16 : 12) * scale,
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Previous channel',
                                      constraints: BoxConstraints(
                                        minWidth: 44 * scale,
                                        minHeight: 44 * scale,
                                      ),
                                      padding: EdgeInsets.zero,
                                      onPressed: () =>
                                          controller.moveMiniGuide(-1),
                                      icon: const Icon(Icons.arrow_upward),
                                    ),
                                    IconButton(
                                      tooltip: 'Next channel',
                                      constraints: BoxConstraints(
                                        minWidth: 44 * scale,
                                        minHeight: 44 * scale,
                                      ),
                                      padding: EdgeInsets.zero,
                                      onPressed: () =>
                                          controller.moveMiniGuide(1),
                                      icon: const Icon(Icons.arrow_downward),
                                    ),
                                  ],
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
    required this.channelColumnWidth,
    required this.columnGap,
    required this.active,
    required this.large,
    required this.scale,
    required this.rowInset,
    required this.isLast,
  });

  final PlayerCoordinator controller;
  final Channel channel;
  final double? rowHeight;
  final double channelColumnWidth;
  final double columnGap;
  final bool active;
  final bool large;
  final double scale;
  final double rowInset;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final focused = channel.id == controller.miniGuideChannelId;
    final foreground = focused ? roles.focusedText : roles.primaryText;
    final tuned =
        channel.id == controller.lineup.currentChannelId &&
        !controller.tuning &&
        controller.error == null &&
        const {
          PlayerState.playing,
          PlayerState.paused,
          PlayerState.buffering,
          PlayerState.seeking,
        }.contains(controller.status.state);
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
    final titleStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: foreground,
      fontSize: (large ? 20 : 14) * scale,
      fontWeight: FontWeight.w500,
    );
    final metadataStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: roles.secondaryText,
      fontSize: (large ? 16 : 12) * scale,
    );
    final nextTitleStyle = titleStyle?.copyWith(
      color: roles.secondaryText,
      fontWeight: FontWeight.w400,
    );
    Widget ticker(String text, Key key, {TextStyle? style}) => FocusedTicker(
      key: key,
      text: text,
      focused: focused,
      active: active,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
      style: style,
    );
    final channelIdentity = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ticker(
          channel.name,
          Key('mini-guide-channel-${channel.id}'),
          style: titleStyle,
        ),
        if (tuned)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: (large ? 14 : 12) * scale,
                  color: roles.secondaryText,
                ),
              ),
              SizedBox(width: 4 * scale),
              Text(
                'Watching',
                style: metadataStyle?.copyWith(
                  fontSize: (large ? 14 : 12) * scale,
                ),
              ),
            ],
          ),
      ],
    );
    final row = controller.guide.row(channel.id);
    final unavailable = row.state == GuideLoadState.error;
    final currentText = unavailable
        ? 'Schedule unavailable'
        : current?.scheduled.item.title ?? 'Loading schedule…';
    final currentTitle = ticker(
      currentText,
      Key('mini-guide-current-${channel.id}'),
      style: titleStyle,
    );
    final currentCell = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        currentTitle,
        if (current != null)
          Text(
            '${_time(context, current.scheduled.start)}–${_time(context, current.scheduled.end)}',
            maxLines: 1,
            style: metadataStyle,
          ),
        if (current != null) ...[
          const SizedBox(height: 3),
          LinearProgressIndicator(
            value: progress.clamp(0, 1),
            minHeight: 2,
            color: roles.progressFill,
            backgroundColor: roles.progressTrack.withValues(alpha: 0.72),
            semanticsLabel: 'Program progress',
          ),
        ],
      ],
    );
    final nextTitle = next == null
        ? null
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ticker(
                next.scheduled.item.title,
                Key('mini-guide-next-${channel.id}'),
                style: nextTitleStyle,
              ),
              Text(
                _time(context, next.scheduled.start),
                maxLines: 1,
                style: metadataStyle,
              ),
            ],
          );
    final number = SizedBox(
      width: (large ? 46.0 : 32.0) * scale,
      child: Text('${channel.number}', style: titleStyle),
    );
    return Semantics(
      key: Key('mini-guide-row-${channel.id}'),
      selected: focused,
      label:
          'Channel ${channel.number}, ${channel.name}. Now $currentText.${next == null ? '' : ' Next ${next.scheduled.item.title}.'}${tuned ? ' Now watching.' : ''}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: focused
              ? roles.progressFill.withValues(alpha: 0.16)
              : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: focused ? roles.focusBorder : Colors.transparent,
              width: roles.focusBorderWidth,
            ),
            bottom: BorderSide(
              color: isLast
                  ? Colors.transparent
                  : roles.primaryText.withValues(alpha: 0.10),
            ),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => controller.focusMiniGuideChannel(channel.id),
            onDoubleTap: unsupported || unavailable
                ? null
                : () {
                    controller.focusMiniGuideChannel(channel.id);
                    unawaited(controller.tuneMiniGuideSelection());
                  },
            child: rowHeight == null
                ? Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: rowInset,
                      vertical: 7 * scale,
                    ),
                    child: Row(
                      children: [
                        number,
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              channelIdentity,
                              currentCell,
                              ?nextTitle,
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : SizedBox(
                    height: rowHeight,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: rowInset),
                      child: Row(
                        children: [
                          SizedBox(
                            width: channelColumnWidth,
                            child: Row(
                              children: [
                                number,
                                Expanded(child: channelIdentity),
                              ],
                            ),
                          ),
                          SizedBox(width: columnGap),
                          Expanded(flex: 115, child: currentCell),
                          SizedBox(width: columnGap),
                          Expanded(
                            flex: 100,
                            child: nextTitle ?? const SizedBox.shrink(),
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

class _MiniGuideFadePainter extends CustomPainter {
  const _MiniGuideFadePainter({required this.scrim, required this.tailHeight});

  final Color scrim;
  final double tailHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & Size(size.width, size.height + tailHeight);
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        scrim.withValues(alpha: 0.78),
        scrim.withValues(alpha: 0.66),
        scrim.withValues(alpha: 0.62),
        scrim.withValues(alpha: 0.52),
        scrim.withValues(alpha: 0.20),
        Colors.transparent,
      ],
      stops: const [0, 0.30, 0.65, 0.76, 0.88, 1],
    );
    canvas.drawRect(bounds, Paint()..shader = gradient.createShader(bounds));
  }

  @override
  bool shouldRepaint(covariant _MiniGuideFadePainter oldDelegate) =>
      scrim != oldDelegate.scrim || tailHeight != oldDelegate.tailHeight;
}

double _playerDrawerGeometryScale(Size size) => math
    .min(size.width / 1920, size.height / 1080)
    .clamp(2 / 3, 1.35)
    .toDouble();

class _SleepTimerPicker extends StatelessWidget {
  const _SleepTimerPicker({
    required this.controller,
    required this.triggerFocus,
  });

  final PlayerCoordinator controller;
  final FocusNode triggerFocus;

  void _choose(Duration? duration) {
    controller.setSleepTimer(duration);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (triggerFocus.canRequestFocus) triggerFocus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final size = MediaQuery.sizeOf(context);
    final scale = LineupLayout.scaleFor(size);
    final geometryScale = _playerDrawerGeometryScale(size);
    final supportingText = Color.lerp(
      roles.secondaryText,
      roles.primaryText,
      0.65,
    )!;
    final scaledTheme = Theme.of(context).copyWith(
      textTheme: Theme.of(context).textTheme.apply(fontSizeFactor: scale),
    );
    final selected = controller.sleepDuration;
    final remaining = controller.sleepRemaining;
    final choices = <(String, Duration?)>[
      ('Off', null),
      ('30 minutes', const Duration(minutes: 30)),
      ('1 hour', const Duration(hours: 1)),
      ('90 minutes', const Duration(minutes: 90)),
    ];
    return Theme(
      data: scaledTheme,
      child: DefaultTextStyle(
        style: scaledTheme.textTheme.bodyMedium!,
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                24 * scale,
                24 * scale,
                roles.overlaySafeArea * scale,
                132 * scale,
              ),
              child: Material(
                key: const Key('sleep-timer-picker'),
                color: roles.scrim.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(roles.panelRadius),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 354 * geometryScale,
                    maxHeight: (MediaQuery.sizeOf(context).height - 180).clamp(
                      240,
                      double.infinity,
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        12 * geometryScale,
                        24 * geometryScale,
                        12 * geometryScale,
                        12 * geometryScale,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 18 * geometryScale,
                            ),
                            child: Text(
                              'Stop playback after…',
                              style: scaledTheme.textTheme.titleMedium
                                  ?.copyWith(color: roles.primaryText),
                            ),
                          ),
                          if (remaining case final value?)
                            Padding(
                              padding: EdgeInsets.only(
                                top: 8 * geometryScale,
                                left: 18 * geometryScale,
                                right: 18 * geometryScale,
                              ),
                              child: Text(
                                'Stops in ${(value.inSeconds / 60).ceil()} min',
                                style: scaledTheme.textTheme.bodySmall
                                    ?.copyWith(color: supportingText),
                              ),
                            ),
                          SizedBox(height: 18 * geometryScale),
                          for (final choice in choices)
                            ListTile(
                              key: Key(
                                'sleep-timer-${choice.$2?.inMinutes ?? 'off'}',
                              ),
                              dense: true,
                              minTileHeight: 60 * geometryScale,
                              selected: choice.$2 == selected,
                              selectedTileColor: roles.progressFill.withValues(
                                alpha: 0.10,
                              ),
                              focusColor: roles.focusedSurface,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 18 * geometryScale,
                              ),
                              autofocus: choice.$2 == selected,
                              title: Text(
                                choice.$1,
                                style: scaledTheme.textTheme.bodyLarge
                                    ?.copyWith(
                                      color: roles.primaryText,
                                      fontSize: 13 * scale,
                                    ),
                              ),
                              trailing: choice.$2 == selected
                                  ? Icon(
                                      Icons.check,
                                      color: roles.progressFill,
                                      semanticLabel: 'Selected preset',
                                    )
                                  : null,
                              onTap: () => _choose(choice.$2),
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
  final _scrollController = ScrollController();
  final _selectedRowKey = GlobalKey();
  late final int? _initialSelectedTrackId;

  @override
  void initState() {
    super.initState();
    _initialSelectedTrackId = widget.controller.tracks
        .where((track) => track.type == widget.type && track.selected)
        .firstOrNull
        ?.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final selectedContext = _selectedRowKey.currentContext;
      if (selectedContext != null) {
        Scrollable.ensureVisible(selectedContext, alignment: 0.5);
      }
    });
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
        final size = constraints.biggest;
        final scale = LineupLayout.scaleFor(size);
        final geometryScale = _playerDrawerGeometryScale(size);
        final railWidth = math.min(
          constraints.maxWidth * 0.4,
          600.0 * geometryScale,
        );
        final fadeWidth = math.min(
          100.0 * geometryScale,
          constraints.maxWidth - railWidth,
        );
        final padding = constraints.maxWidth <= 800
            ? EdgeInsets.all(20 * geometryScale)
            : EdgeInsets.fromLTRB(
                36 * geometryScale,
                48 * geometryScale,
                48 * geometryScale,
                36 * geometryScale,
              );
        final textTheme = Theme.of(context).textTheme;
        TextStyle? scaled(TextStyle? style) => style?.fontSize == null
            ? style
            : style!.copyWith(fontSize: style.fontSize! * scale);
        final supportingText = Color.lerp(
          roles.secondaryText,
          roles.primaryText,
          0.65,
        )!;
        return Align(
          alignment: Alignment.centerRight,
          child: FocusScope(
            child: Container(
              key: const Key('playback-options-fade'),
              width: railWidth + fadeWidth,
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.transparent,
                    roles.scrim.withValues(alpha: 0.34),
                    roles.scrim.withValues(alpha: 0.74),
                    roles.scrim.withValues(alpha: 0.82),
                  ],
                  stops: const [0, 0.10, 0.22, 1],
                ),
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  key: const Key('playback-options-rail'),
                  width: railWidth,
                  child: Padding(
                    padding: padding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.type == PlayerTrackType.audio
                                    ? 'Audio'
                                    : 'Subtitles',
                                style: scaled(textTheme.headlineSmall)
                                    ?.copyWith(fontWeight: FontWeight.w500),
                              ),
                            ),
                            TextButton(
                              autofocus:
                                  tracks.isEmpty &&
                                  widget.type != PlayerTrackType.subtitle,
                              onPressed: widget.controller.closeOverlay,
                              style: TextButton.styleFrom(
                                textStyle: scaled(textTheme.labelLarge),
                                foregroundColor: supportingText,
                              ),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                        SizedBox(height: 36 * geometryScale),
                        if (tracks.isEmpty &&
                            widget.type == PlayerTrackType.subtitle)
                          Padding(
                            padding: EdgeInsets.only(bottom: 12 * scale),
                            child: Text(
                              widget.controller.tuning ||
                                      widget.controller.status.state ==
                                          PlayerState.loading
                                  ? 'Loading tracks…'
                                  : 'No subtitle tracks available',
                              style: scaled(textTheme.bodyMedium),
                            ),
                          ),
                        Expanded(
                          child: ClipRect(
                            child:
                                tracks.isEmpty &&
                                    widget.type == PlayerTrackType.audio
                                ? Center(
                                    child: Text(
                                      widget.controller.tuning ||
                                              widget.controller.status.state ==
                                                  PlayerState.loading
                                          ? 'Loading tracks…'
                                          : 'No audio tracks available',
                                      style: scaled(textTheme.bodyMedium),
                                    ),
                                  )
                                // Native track projection is bounded to 256 rows.
                                // Lay them out once so wrapped labels can be
                                // focused/revealed without estimating row heights.
                                : SingleChildScrollView(
                                    key: const Key('playback-options-list'),
                                    controller: _scrollController,
                                    child: Column(
                                      children: [
                                        for (
                                          var index = 0;
                                          index <
                                              tracks.length +
                                                  (widget.type ==
                                                          PlayerTrackType
                                                              .subtitle
                                                      ? 1
                                                      : 0);
                                          index++
                                        ) ...[
                                          if (index > 0)
                                            Divider(
                                              height: 1,
                                              color: roles.subtleBorder
                                                  .withValues(alpha: 0.45),
                                            ),
                                          Builder(
                                            builder: (context) {
                                              final off =
                                                  widget.type ==
                                                      PlayerTrackType
                                                          .subtitle &&
                                                  index == 0;
                                              final track = off
                                                  ? null
                                                  : tracks[index -
                                                        (widget.type ==
                                                                PlayerTrackType
                                                                    .subtitle
                                                            ? 1
                                                            : 0)];
                                              final selected = off
                                                  ? selectedTrack == null
                                                  : track!.selected;
                                              final metadata = track == null
                                                  ? const <String>[]
                                                  : [
                                                      if (track.language !=
                                                          null)
                                                        track.language!,
                                                      if (track.codec != null)
                                                        track.codec!,
                                                    ];
                                              final title = off
                                                  ? 'Off'
                                                  : track!.title ??
                                                        track.language ??
                                                        '${track.type.name} ${track.id}';
                                              final metadataText = metadata
                                                  .join(' • ');
                                              final tooltip =
                                                  metadataText.isEmpty
                                                  ? title
                                                  : '$title\n$metadataText';
                                              final pending =
                                                  widget
                                                          .controller
                                                          .pendingTrackType ==
                                                      widget.type &&
                                                  widget
                                                          .controller
                                                          .pendingTrackId ==
                                                      track?.id;
                                              return Material(
                                                key:
                                                    (off
                                                        ? _initialSelectedTrackId ==
                                                              null
                                                        : track!.id ==
                                                              _initialSelectedTrackId)
                                                    ? _selectedRowKey
                                                    : null,
                                                color: Colors.transparent,
                                                child: ListTile(
                                                  key: Key(
                                                    off
                                                        ? 'playback-track-off'
                                                        : 'playback-track-${widget.type.name}-${track!.id}',
                                                  ),
                                                  autofocus: selected,
                                                  selected: selected,
                                                  selectedTileColor: roles
                                                      .progressFill
                                                      .withValues(alpha: 0.10),
                                                  focusColor:
                                                      roles.focusedSurface,
                                                  contentPadding:
                                                      EdgeInsets.symmetric(
                                                        horizontal: 12 * scale,
                                                        vertical: 8 * scale,
                                                      ),
                                                  title: Tooltip(
                                                    message: tooltip,
                                                    excludeFromSemantics: true,
                                                    child: Text(
                                                      title,
                                                      semanticsLabel: title,
                                                      maxLines: 3,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      softWrap: true,
                                                      style:
                                                          scaled(
                                                            textTheme.bodyLarge,
                                                          )?.copyWith(
                                                            color: roles
                                                                .primaryText,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                    ),
                                                  ),
                                                  subtitle: metadata.isEmpty
                                                      ? null
                                                      : Text(
                                                          metadataText,
                                                          semanticsLabel:
                                                              metadataText,
                                                          maxLines: 3,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          softWrap: true,
                                                          style:
                                                              scaled(
                                                                textTheme
                                                                    .bodyMedium,
                                                              )?.copyWith(
                                                                color:
                                                                    supportingText,
                                                              ),
                                                        ),
                                                  trailing: SizedBox(
                                                    width: 30 * scale,
                                                    child: Center(
                                                      child: pending
                                                          ? SizedBox.square(
                                                              dimension:
                                                                  18 * scale,
                                                              child: const CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                                semanticsLabel: 'Changing track',
                                                              ),
                                                            )
                                                          : selected
                                                          ? Icon(
                                                              Icons.check,
                                                              color: roles
                                                                  .progressFill,
                                                              semanticLabel:
                                                                  'Selected',
                                                            )
                                                          : const SizedBox.shrink(),
                                                    ),
                                                  ),
                                                  onTap: () => widget.controller
                                                      .selectTrack(
                                                        widget.type,
                                                        track?.id,
                                                      ),
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                          ),
                        ),
                        if (widget.controller.trackSelectionError
                            case final error?)
                          Padding(
                            padding: EdgeInsets.only(top: 10 * scale),
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
                        Padding(
                          padding: EdgeInsets.only(top: 20 * geometryScale),
                          child: Text(
                            'Up/Down Browse · Enter Select · Esc Close',
                            style: scaled(textTheme.bodySmall)
                                ?.copyWith(color: supportingText),
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
  FocusNode? focusNode,
}) {
  final roles = LineupTheme.of(context);
  final size = MediaQuery.sizeOf(context);
  return ConstrainedBox(
    constraints: BoxConstraints(maxWidth: compact ? 132 : 180),
    child: Tooltip(
      message: tooltip,
      child: TextButton.icon(
        key: key,
        focusNode: focusNode,
        onPressed: onPressed,
        icon: Icon(icon, size: compact ? 17 : 18),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: roles.primaryText,
            fontSize: size.width >= 1920 && size.height >= 900 ? 16 : 14,
            fontWeight: FontWeight.w500,
          ),
        ),
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

String? _osdEpisodeFacts(ChannelItem item) {
  final numbered = [
    if (item.seasonNumber != null) 'S${item.seasonNumber}',
    if (item.episodeNumber != null) 'E${item.episodeNumber}',
  ].join(' · ');
  final showTitle = item.showTitle?.trim();
  if (showTitle?.isNotEmpty != true) return numbered.isEmpty ? null : numbered;

  final episodeTitle = item.title.trim();
  if (numbered.isEmpty) {
    return episodeTitle.isEmpty || episodeTitle == showTitle
        ? null
        : episodeTitle;
  }
  return episodeTitle.isEmpty || episodeTitle == showTitle
      ? numbered
      : '$numbered — $episodeTitle';
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
