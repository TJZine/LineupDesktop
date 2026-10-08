import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../channels/channel.dart';
import '../guide/guide_controller.dart';
import '../guide/focused_ticker.dart';
import '../settings/lineup_settings.dart';
import '../ui/app_theme.dart';
import '../ui/app_ui.dart';
import 'native_player.dart';
import 'native_video_surface.dart';
import 'player_coordinator.dart';
import 'player_track_label.dart';

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
  late int _bottomPanelGeneration;
  var _overlayTransitionDuration = const Duration(milliseconds: 350);
  final _menuFocus = FocusNode(debugLabel: 'Player Lineup menu');
  final _sleepFocus = FocusNode(debugLabel: 'Player sleep timer');
  Timer? _visibleClockTimer;
  var _appActive = true;
  var _keyboardInput = false;
  final _internalRootFocus = FocusNode(debugLabel: 'Player root');
  FocusNode get _rootFocus => widget.focusNode ?? _internalRootFocus;

  @override
  void initState() {
    super.initState();
    _renderedOverlay = widget.controller.overlay;
    _bottomPanelGeneration = widget.controller.overlayPresentationGeneration;
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_changed);
    HardwareKeyboard.instance.addHandler(_trackKeyboardInput);
    _syncVisibleClockTimer();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    _visibleClockTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_trackKeyboardInput);
    _internalRootFocus.dispose();
    _menuFocus.dispose();
    _sleepFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (_appActive == active) return;
    setState(() => _appActive = active);
    _syncVisibleClockTimer();
    if (active) unawaited(widget.controller.checkSleepDeadline());
  }

  void _changed() {
    if (!mounted) return;
    _syncVisibleClockTimer();
    final nextOverlay = widget.controller.overlay;
    final bottomPanelChanged =
        _renderedOverlay != nextOverlay &&
        (_renderedOverlay == PlayerOverlay.osd ||
            _renderedOverlay == PlayerOverlay.nowPlaying) &&
        (nextOverlay == PlayerOverlay.osd ||
            nextOverlay == PlayerOverlay.nowPlaying);
    setState(() {
      if (!bottomPanelChanged &&
          _renderedOverlay != nextOverlay &&
          (nextOverlay == PlayerOverlay.osd ||
              nextOverlay == PlayerOverlay.nowPlaying)) {
        _bottomPanelGeneration =
            widget.controller.overlayPresentationGeneration;
      }
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
    if (bottomPanelChanged) {
      final generation = widget.controller.overlayPresentationGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            FocusManager.instance.primaryFocus?.context
                    ?.findAncestorWidgetOfExactType<_Osd>()
                    ?.controller ==
                widget.controller &&
            _keyboardInput) {
          // The shared panel retains focus across expansion, while the
          // coordinator retires each presentation's auto-hide suspension.
          widget.controller.overlayFocusChanged(nextOverlay, generation, true);
        }
      });
    }
  }

  bool get _needsVisibleClock =>
      _appActive &&
      switch (widget.controller.overlay) {
        PlayerOverlay.miniGuide ||
        PlayerOverlay.osd ||
        PlayerOverlay.nowPlaying => true,
        _ => false,
      };

  void _syncVisibleClockTimer() {
    if (!_needsVisibleClock) {
      _visibleClockTimer?.cancel();
      _visibleClockTimer = null;
      return;
    }
    // Schedule clocks and progress must advance even without native events.
    _visibleClockTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      if (!_needsVisibleClock) {
        _syncVisibleClockTimer();
        return;
      }
      setState(() {});
    });
  }

  bool _trackKeyboardInput(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _keyboardInput = true;
      if (_rootFocus.hasFocus && !_rootFocus.hasPrimaryFocus) {
        widget.controller.overlayFocusChanged(
          widget.controller.overlay,
          widget.controller.overlayPresentationGeneration,
          true,
        );
      }
    }
    return false;
  }

  void _trackPointerInput() {
    _keyboardInput = false;
    widget.controller.handlePointerActivity();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Shell route shortcuts must reach the shared navigation/leave guard.
    if (HardwareKeyboard.instance.isControlPressed &&
        const [
          LogicalKeyboardKey.digit1,
          LogicalKeyboardKey.digit2,
          LogicalKeyboardKey.digit3,
          LogicalKeyboardKey.digit4,
          LogicalKeyboardKey.digit5,
          LogicalKeyboardKey.keyG,
          LogicalKeyboardKey.keyP,
          LogicalKeyboardKey.comma,
        ].contains(event.logicalKey)) {
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
        final restoreSleep = controller.sleepPickerOpen;
        controller.overlay == PlayerOverlay.nowPlaying
            ? controller.showOsd()
            : controller.closeOverlay();
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
        controller.closeSleepPicker();
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
      controller.closeSleepPicker();
      controller.showFullGuide();
      widget.openGuide();
    } else if (controller.overlay == PlayerOverlay.miniGuide &&
        key == LogicalKeyboardKey.arrowUp) {
      controller.moveMiniGuide(-1);
    } else if (controller.overlay == PlayerOverlay.miniGuide &&
        key == LogicalKeyboardKey.arrowDown) {
      controller.moveMiniGuide(1);
    } else if (key == LogicalKeyboardKey.pageUp) {
      controller.closeSleepPicker();
      controller.overlay == PlayerOverlay.miniGuide
          ? controller.moveMiniGuide(-7)
          : unawaited(controller.previousChannel());
    } else if (key == LogicalKeyboardKey.pageDown) {
      controller.closeSleepPicker();
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
      controller.closeSleepPicker();
      unawaited(controller.togglePlayback());
      controller.showOsd();
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.keyJ) {
      if (controller.overlay != PlayerOverlay.none &&
          controller.overlay != PlayerOverlay.osd &&
          !showingNowPlaying) {
        return KeyEventResult.ignored;
      }
      controller.closeSleepPicker();
      unawaited(controller.seekBy(const Duration(seconds: -10)));
      controller.showOsd();
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyL) {
      if (controller.overlay == PlayerOverlay.miniGuide) {
        controller.closeSleepPicker();
        controller.showFullGuide();
        widget.openGuide();
      } else if (controller.overlay == PlayerOverlay.none ||
          controller.overlay == PlayerOverlay.osd ||
          showingNowPlaying) {
        controller.closeSleepPicker();
        unawaited(controller.seekBy(const Duration(seconds: 30)));
        controller.showOsd();
      } else {
        return KeyEventResult.ignored;
      }
    } else if (key == LogicalKeyboardKey.arrowUp &&
        (controller.overlay == PlayerOverlay.none ||
            controller.overlay == PlayerOverlay.osd)) {
      controller.closeSleepPicker();
      controller.showMiniGuide();
    } else if (key == LogicalKeyboardKey.arrowDown &&
        (controller.overlay == PlayerOverlay.none ||
            controller.overlay == PlayerOverlay.osd)) {
      controller.closeSleepPicker();
      controller.currentProgram == null
          ? controller.showOsd()
          : controller.showNowPlaying();
    } else if (initialPress && key == LogicalKeyboardKey.keyI) {
      controller.closeSleepPicker();
      showingNowPlaying ? controller.showOsd() : controller.showNowPlaying();
    } else if (initialPress &&
        (key == LogicalKeyboardKey.keyF || key == LogicalKeyboardKey.f11)) {
      controller.closeSleepPicker();
      unawaited(controller.toggleFullscreen());
    } else if (initialPress && key == LogicalKeyboardKey.keyS) {
      controller.showSleepTimer();
    } else if (key == LogicalKeyboardKey.keyA) {
      controller.closeSleepPicker();
      controller.showTracks(PlayerTrackType.audio);
    } else if (key == LogicalKeyboardKey.keyC) {
      controller.closeSleepPicker();
      controller.showTracks(PlayerTrackType.subtitle);
    } else if (key == LogicalKeyboardKey.mediaPlay) {
      controller.closeSleepPicker();
      unawaited(controller.play());
      if (showingNowPlaying) controller.showOsd();
    } else if (key == LogicalKeyboardKey.mediaPause) {
      controller.closeSleepPicker();
      unawaited(controller.pause());
      if (showingNowPlaying) controller.showOsd();
    } else if (key == LogicalKeyboardKey.mediaStop) {
      controller.closeSleepPicker();
      unawaited(controller.requestStop());
    } else if (key == LogicalKeyboardKey.mediaRewind) {
      controller.closeSleepPicker();
      unawaited(controller.seekBy(const Duration(seconds: -10)));
      if (showingNowPlaying) controller.showOsd();
    } else if (key == LogicalKeyboardKey.mediaFastForward) {
      controller.closeSleepPicker();
      unawaited(controller.seekBy(const Duration(seconds: 30)));
      if (showingNowPlaying) controller.showOsd();
    } else {
      final digit = _digit(key);
      if (digit == null) return KeyEventResult.ignored;
      controller.closeSleepPicker();
      controller.appendChannelDigit(digit);
    }
    return KeyEventResult.handled;
  }

  void _restoreSleepFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        (_keyboardInput ? _sleepFocus : _rootFocus).requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final sleepAnchor = LayerLink();
    final overlay = controller.overlay;
    final presentationGeneration = controller.overlayPresentationGeneration;
    final bottomPanel =
        overlay == PlayerOverlay.osd || overlay == PlayerOverlay.nowPlaying;
    final presentationKey = ValueKey((
      bottomPanel ? PlayerOverlay.osd : overlay,
      bottomPanel ? _bottomPanelGeneration : presentationGeneration,
    ));
    final transitionDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _overlayTransitionDuration;
    return Material(
      color: Colors.transparent,
      child: Focus(
        focusNode: _rootFocus,
        canRequestFocus: controller.overlay != PlayerOverlay.fullGuide,
        autofocus: true,
        onKeyEvent: _key,
        child: Listener(
          onPointerDown: (_) => _trackPointerInput(),
          child: MouseRegion(
            cursor: controller.cursorVisible
                ? SystemMouseCursors.basic
                : SystemMouseCursors.none,
            onHover: (_) => _trackPointerInput(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (controller.overlay == PlayerOverlay.miniGuide) {
                  controller.closeOverlay();
                } else if (controller.sleepPickerOpen) {
                  controller.closeOverlay();
                  _restoreSleepFocus();
                } else {
                  controller.showOsd();
                }
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PlayerSurface(
                    controller: controller,
                    fullPlayer: true,
                    onClose: () {
                      controller.showFullGuide();
                      widget.openGuide();
                    },
                  ),
                  if (overlay != PlayerOverlay.channelNumber &&
                      (controller.notice != null ||
                          controller.busyLabel != null))
                    _StatusBug(
                      controller: controller,
                      text: controller.notice ?? controller.busyLabel!,
                    ),
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
                          (child.key as ValueKey<(PlayerOverlay, int)>)
                              .value
                              .$1;
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
                    child: _OverlayTextTheme(
                      key: presentationKey,
                      child: Focus(
                        canRequestFocus: false,
                        onFocusChange: (focused) {
                          controller.overlayFocusChanged(
                            overlay,
                            presentationGeneration,
                            focused && _keyboardInput,
                          );
                        },
                        child: switch (overlay) {
                          PlayerOverlay.osd || PlayerOverlay.nowPlaying => _Osd(
                            detailsExpanded:
                                overlay == PlayerOverlay.nowPlaying,
                            controller: controller,
                            openMenu: widget.openMenu,
                            menuFocus: _menuFocus,
                            sleepFocus: _sleepFocus,
                            sleepAnchor: sleepAnchor,
                            restoreSleepFocus: _restoreSleepFocus,
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
                          PlayerOverlay.channelNumber => _ChannelNumber(
                            controller: controller,
                          ),
                          PlayerOverlay.error => const SizedBox.shrink(),
                          PlayerOverlay.none ||
                          PlayerOverlay.fullGuide => const SizedBox.shrink(),
                        },
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

/// The one Flutter geometry used for both the full player and Guide PiP.
class PlayerSurface extends StatelessWidget {
  const PlayerSurface({
    required this.controller,
    this.showErrors = false,
    this.fullPlayer = false,
    this.onClose,
    super.key,
  });

  final PlayerCoordinator controller;
  final bool showErrors;
  final bool fullPlayer;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final state = controller.status.state;
    final unsupported = state == PlayerState.unsupported;
    final hasError = controller.error != null;
    final preparing =
        !hasError && (state == PlayerState.loading || controller.tuning);
    final roles = LineupTheme.of(context);
    final unavailable =
        hasError ||
        state == PlayerState.error ||
        state == PlayerState.unsupported;
    final stopped =
        !controller.hasPlaybackIntent &&
        const {
          PlayerState.stopped,
          PlayerState.idle,
          PlayerState.ended,
        }.contains(state);
    if (fullPlayer && !preparing && (unavailable || stopped)) {
      return _StoppedSlate(controller: controller, onClose: onClose);
    }
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
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    final bodyStyle = textTheme.bodyMedium;
    return ColoredBox(
      color: roles.deepBackground,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : 0,
            ),
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 24),
                    SizedBox(height: 8),
                    Text(
                      controller.error ?? controller.status.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: bodyStyle,
                    ),
                    if (controller.canRetry)
                      LineupInlineLink(
                        onPressed: controller.retry,
                        child: const Text('Retry'),
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

// Keep the material bottom-anchored while its content grows upward. Bypass
// animation entirely for Reduce Motion, including asynchronous artwork sizes.
class _BottomPanelExpansion extends StatelessWidget {
  const _BottomPanelExpansion({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => MediaQuery.disableAnimationsOf(context)
      ? child
      : AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.bottomCenter,
          curve: Curves.easeOut,
          clipBehavior: Clip.none,
          child: child,
        );
}

class _Osd extends StatelessWidget {
  const _Osd({
    required this.controller,
    required this.menuFocus,
    required this.sleepFocus,
    required this.sleepAnchor,
    required this.restoreSleepFocus,
    this.openMenu,
    this.detailsExpanded = false,
  });
  final bool detailsExpanded;
  final PlayerCoordinator controller;
  final LineupMenuCallback? openMenu;
  final FocusNode menuFocus;
  final FocusNode sleepFocus;
  final LayerLink sleepAnchor;
  final VoidCallback restoreSleepFocus;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final size = MediaQuery.sizeOf(context);
    final horizontalInset = (size.width * 0.05).clamp(24.0, 96.0).toDouble();
    final channel = controller.currentChannel;
    final program = controller.currentProgram;
    final next = controller.nextProgram;
    final scheduleTiming =
        detailsExpanded &&
        controller.duration <= Duration.zero &&
        program != null;
    final timingDuration = scheduleTiming
        ? program.scheduled.end.difference(program.scheduled.start)
        : controller.duration;
    final duration = timingDuration.inMilliseconds;
    final rawPosition = scheduleTiming
        ? controller.guide.now
              .difference(program.scheduled.start)
              .inMilliseconds
        : controller.position.inMilliseconds;
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

    final actionStyle = _playerActionStyle(context);
    final transportActions = <Widget>[
      IconButton(
        style: actionStyle,
        tooltip: 'Previous channel',
        onPressed: unsupported
            ? null
            : () {
                controller.closeSleepPicker();
                unawaited(controller.previousChannel());
              },
        padding: null,
        iconSize: 28,
        icon: const Icon(Icons.skip_previous),
      ),
      IconButton(
        style: actionStyle,
        tooltip: controller.status.state == PlayerState.playing
            ? 'Pause'
            : 'Play',
        onPressed: unsupported
            ? null
            : () {
                controller.closeSleepPicker();
                unawaited(controller.togglePlayback());
              },
        padding: null,
        iconSize: 36,
        icon: Icon(
          controller.status.state == PlayerState.playing
              ? Icons.pause
              : Icons.play_arrow,
        ),
      ),
      IconButton(
        style: actionStyle,
        tooltip: 'Next channel',
        onPressed: unsupported
            ? null
            : () {
                controller.closeSleepPicker();
                unawaited(controller.nextChannel());
              },
        padding: null,
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
    final audioDisplay = selectedAudio == null
        ? null
        : formatPlayerTrackDisplay(selectedAudio, peers: controller.tracks);
    final audioLabel = audioDisplay == null || audioDisplay.compactText == null
        ? 'Audio'
        : 'Audio • ${audioDisplay.compactText}';
    final audioDescription =
        audioDisplay?.tooltipText ??
        (audioAvailable ? 'Audio tracks' : 'Audio tracks unavailable');
    final subtitlesDisplay = selectedSubtitles == null
        ? null
        : formatPlayerTrackDisplay(selectedSubtitles, peers: controller.tracks);
    final subtitlesLabel = subtitlesDisplay == null
        ? '${expanded ? 'Subtitles' : 'Subs'} • Off'
        : subtitlesDisplay.compactText == null
        ? (expanded ? 'Subtitles' : 'Subs')
        : '${expanded ? 'Subtitles' : 'Subs'} • ${subtitlesDisplay.compactText}';
    final subtitlesDescription = subtitlesDisplay == null
        ? (subtitlesAvailable
              ? 'Subtitle tracks: Off'
              : 'Subtitles unavailable')
        : subtitlesDisplay.tooltipText;
    final sleepRemaining = controller.sleepRemaining;
    final remainingMinutes = sleepRemaining == null
        ? null
        : (sleepRemaining.inSeconds / Duration.secondsPerMinute).ceil();
    final sleepLabel = remainingMinutes == null
        ? 'Sleep'
        : 'Sleep · ${remainingMinutes}m';
    final optionActions = <Widget>[
      _osdAction(
        context,
        key: const Key('player-osd-subtitles'),
        label: subtitlesLabel,
        tooltip: subtitlesDescription,
        semanticLabel: subtitlesDescription,
        icon: Icons.subtitles_outlined,
        onPressed: subtitlesAvailable
            ? () {
                controller.closeSleepPicker();
                controller.showTracks(PlayerTrackType.subtitle);
              }
            : null,
      ),
      _osdAction(
        context,
        key: const Key('player-osd-audio'),
        label: audioLabel,
        tooltip: audioDescription,
        semanticLabel: audioDescription,
        icon: Icons.audiotrack,
        onPressed: audioAvailable
            ? () {
                controller.closeSleepPicker();
                controller.showTracks(PlayerTrackType.audio);
              }
            : null,
      ),
      CompositedTransformTarget(
        link: sleepAnchor,
        child: _osdAction(
          context,
          key: const Key('player-osd-sleep'),
          label: sleepLabel,
          tooltip: sleepRemaining == null ? 'Stop playback after…' : sleepLabel,
          icon: Icons.bedtime_outlined,
          focusNode: sleepFocus,
          onPressed: controller.showSleepTimer,
        ),
      ),
    ];
    final windowActions = <Widget>[
      if (openMenu != null)
        Builder(
          builder: (invokerContext) => IconButton(
            style: actionStyle,
            key: const Key('player-app-menu'),
            focusNode: menuFocus,
            tooltip: 'Lineup menu',
            onPressed: () {
              controller.closeSleepPicker();
              openMenu!(invokerContext, menuFocus);
            },
            padding: null,
            iconSize: 20,
            icon: const Icon(Icons.menu),
          ),
        ),
      IconButton(
        style: actionStyle,
        tooltip: controller.fullscreen ? 'Exit full screen' : 'Full screen',
        onPressed: unsupported
            ? null
            : () {
                controller.closeSleepPicker();
                unawaited(controller.toggleFullscreen());
              },
        padding: null,
        iconSize: 20,
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
              (size.width >= 1920 ? 520 : 360),
              (size.height >= 900 ? 104 : 72),
            ),
            logoMinimumVisibleSize: Size(96, (size.height >= 900 ? 28 : 24)),
          )
        else
          _OsdTitle(title: primaryTitle),
        if (statusFacts.isNotEmpty) ...[
          SizedBox(height: 8),
          Text(
            statusFacts.join(' • '),
            key: const Key('player-osd-status'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: roles.secondaryText,
              fontSize: 18,
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
      color: roles.secondaryText,
      fontSize: 18,
      fontWeight: FontWeight.w400,
    );
    final progress = Row(
      key: const Key('player-osd-progress-block'),
      children: [
        Expanded(
          child: Text(
            [
              '${_duration(displayedPosition)} / ${_duration(timingDuration)}',
              ?remaining,
            ].join(' • '),
            key: const Key('player-osd-timing'),
            style: osdSecondaryStyle?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        if (next != null) ...[
          SizedBox(width: 16),
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
    final availableWidth = size.width - horizontalInset * 2;
    final labelStyle = actionStyle.textStyle?.resolve({});
    final minimumSize =
        actionStyle.minimumSize?.resolve({}) ?? const Size(44, 44);
    final padding = (actionStyle.padding?.resolve({}) ?? EdgeInsets.zero)
        .resolve(Directionality.of(context));
    final tapTarget =
        actionStyle.tapTargetSize ?? Theme.of(context).materialTapTargetSize;
    final minimumWidth = math.max(
      minimumSize.width,
      tapTarget == MaterialTapTargetSize.padded ? kMinInteractiveDimension : 0,
    );
    final iconActionWidth = math
        .max(minimumWidth, 20 + padding.horizontal)
        .ceilToDouble();
    final standardWidth =
        [subtitlesLabel, audioLabel, sleepLabel].fold<double>(
          0,
          (sum, label) =>
              sum +
              math
                  .max(
                    minimumWidth,
                    _textWidth(context, label, labelStyle) +
                        20 +
                        8 +
                        padding.horizontal,
                  )
                  .ceilToDouble(),
        ) +
        windowActions.length * iconActionWidth +
        16;
    final controlsWidth = standardWidth + (dvrControlsEnabled ? 168 : 0);
    final wrapActions = controlsWidth > availableWidth * .65;
    final groupedActions = SizedBox(
      width: math.min(controlsWidth, availableWidth),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.min(controlsWidth, constraints.maxWidth);
          return SizedBox(
            key: const Key('player-osd-action-groups'),
            width: width,
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 6,
              children: [
                if (dvrControlsEnabled) actionGroup(transportActions),
                SizedBox(
                  width: math.min(standardWidth, width),
                  child: Wrap(
                    key: const Key('player-osd-standard-actions'),
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ...optionActions,
                      const SizedBox(width: 16),
                      ...windowActions,
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
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
              '${_duration(displayedPosition)} of ${_duration(timingDuration)}',
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
                    onChanged:
                        controller.duration <= Duration.zero || unsupported
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
            child: _BottomPanelExpansion(
              child: CustomPaint(
                painter: _OsdPanelMaterial(
                  color: _overlayColor(context, controller, more: .62),
                  collapsedFade:
                      !detailsExpanded &&
                      controller.lineup.settings.overlayTransparency ==
                          OverlayTransparency.moreTransparent,
                ),
                child: Container(
                  key: const Key('player-osd-surface'),
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(
                    horizontalInset,
                    detailsExpanded
                        ? 20
                        : horizontal
                        ? (size.height >= 900 ? 44 : 20)
                        : (size.height >= 720 ? 56 : 40),
                    horizontalInset,
                    12 + (dvrControlsEnabled ? 40 : 0),
                  ),
                  child: Semantics(
                    container: true,
                    label: 'Playback controls',
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (detailsExpanded) ...[
                          _NowPlaying(
                            controller: controller,
                            maxHeight: math.max(
                              80,
                              size.height -
                                  (wrapActions ? 280 : 190) -
                                  (dvrControlsEnabled ? 40 : 0),
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (horizontal && !wrapActions)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Text(
                                    controller.status.state ==
                                            PlayerState.playing
                                        ? 'Playing'
                                        : _statusLabel(
                                                controller.status.state,
                                              ) ??
                                              'Ready',
                                    style: osdSecondaryStyle,
                                  ),
                                ),
                                const SizedBox(width: 24),
                                groupedActions,
                              ],
                            )
                          else ...[
                            Text(
                              controller.status.state == PlayerState.playing
                                  ? 'Playing'
                                  : _statusLabel(controller.status.state) ??
                                        'Ready',
                              style: osdSecondaryStyle,
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerRight,
                              child: groupedActions,
                            ),
                          ],
                        ] else if (horizontal && !wrapActions)
                          Row(
                            key: const Key('player-osd-horizontal-layout'),
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(child: identity),
                              SizedBox(width: 24),
                              groupedActions,
                            ],
                          )
                        else ...[
                          KeyedSubtree(
                            key: horizontal
                                ? const Key('player-osd-horizontal-layout')
                                : null,
                            child: identity,
                          ),
                          SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: wrapActions
                                ? groupedActions
                                : Row(
                                    key: const Key(
                                      'player-osd-stacked-controls',
                                    ),
                                    mainAxisSize: MainAxisSize.min,
                                    children: [groupedActions],
                                  ),
                          ),
                        ],
                        SizedBox(height: 10),
                        progress,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (channel != null &&
            controller.notice == null &&
            controller.busyLabel == null)
          Positioned(
            top: 24,
            right: horizontalInset,
            child: _ChannelBug(
              key: const Key('player-osd-channel-bug'),
              channel: channel,
              controller: controller,
              osdPresentation: true,
            ),
          ),
        if (controller.sleepPickerOpen)
          _SleepTimerPicker(
            controller: controller,
            restoreFocus: restoreSleepFocus,
            anchor: sleepAnchor,
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
    return Semantics(
      container: true,
      label: title,
      excludeSemantics: true,
      child: Text(
        title,
        key: const Key('player-osd-title'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: LineupTypography.osdTitle.copyWith(
          color: LineupTheme.of(context).primaryText,
          shadows: _overlayTextShadow,
        ),
      ),
    );
  }
}

class _ChannelBug extends StatelessWidget {
  const _ChannelBug({
    required this.channel,
    required this.controller,
    this.osdPresentation = false,
    super.key,
  });

  final Channel channel;
  final PlayerCoordinator controller;
  final bool osdPresentation;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final size = MediaQuery.sizeOf(context);
    final inheritedLabelSize =
        Theme.of(context).textTheme.labelLarge?.fontSize ?? 14;
    return Semantics(
      container: true,
      button: false,
      label: 'Channel ${channel.number}, ${channel.name}',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _overlayColor(context, controller),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: roles.subtleBorder),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            '${channel.number} • ${channel.name}',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: roles.primaryText,
              fontSize: osdPresentation
                  ? (size.width >= 1920 && size.height >= 900 ? 16 : 14)
                  : inheritedLabelSize,
              fontWeight: osdPresentation ? FontWeight.w500 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.controller, required this.maxHeight});

  final PlayerCoordinator controller;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final program = controller.currentProgram;
    if (program == null) return const SizedBox.shrink();
    final item = program.scheduled.item;
    final roles = LineupTheme.of(context);
    final size = MediaQuery.sizeOf(context);
    final dense = size.height < 900;
    final generation = controller.lineup.contentGeneration;
    final artworkIdentity = (program.id, generation);
    final posterPath = _artworkPath(item, GuideArtworkKind.poster);
    final logoPath = _artworkPath(item, GuideArtworkKind.clearLogo);
    final duration = controller.duration > Duration.zero
        ? controller.duration
        : program.scheduled.end.difference(program.scheduled.start);
    final episode = _episodeLabel(item);
    final numberedEpisode = [
      if (item.seasonNumber != null) 'S${item.seasonNumber}',
      if (item.episodeNumber != null) 'E${item.episodeNumber}',
    ].join(' ');
    final editorial = [
      if (numberedEpisode.isNotEmpty) numberedEpisode,
      if (duration > Duration.zero) '${duration.inMinutes} min',
      if (item.year != null) '${item.year}',
      ...item.genres.where((genre) => genre.trim().isNotEmpty).take(3),
    ].join(' · ');
    final videoCodec =
        formatPlayerVideoCodec(controller.telemetry.videoFormat) ??
        formatPlayerVideoCodec(item.videoCodec) ??
        formatPlayerVideoCodec(controller.telemetry.videoCodec);
    final badges = <String>[
      ?item.contentRating,
      if (item.resolution case final resolution?) resolution.toUpperCase(),
      ?_dynamicRangeLabel(item.dynamicRange, controller.telemetry.isHdr),
      ?videoCodec,
      if (item.audioCodec case final codec?) codec.toUpperCase(),
      if (item.audioChannels case final channels?) _audioChannels(channels),
    ];
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
      if (editorial.isNotEmpty) editorial,
      ...badges,
      ?item.summary,
      if (castFacts.isNotEmpty) 'Cast: $castFacts',
    ].join('. ');
    final posterWidth = dense ? 160.0 : 240.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: ConstrainedBox(
        key: const Key('player-now-playing-surface'),
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Now playing',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  key: const Key('player-now-playing-collapse'),
                  style: _playerActionStyle(context).copyWith(
                    padding: const WidgetStatePropertyAll(
                      // Center the 20px glyph like the fullscreen action's
                      // 48px target, while keeping the label-to-icon gap tight.
                      EdgeInsets.only(left: 10, right: 14),
                    ),
                  ),
                  onPressed: controller.showOsd,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Close'),
                      SizedBox(width: 6),
                      ExcludeSemantics(child: Icon(Icons.close, size: 20)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              fit: FlexFit.loose,
              child: Semantics(
                container: true,
                label: semanticFacts,
                explicitChildNodes: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (size.width >= 700 && size.height >= 500) ...[
                      SizedBox(
                        key: const Key('player-now-playing-poster'),
                        width: posterWidth,
                        height: math.min(posterWidth * 1.5, maxHeight - 64),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: posterPath == null
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
                        ),
                      ),
                      SizedBox(width: dense ? 24 : 32),
                    ],
                    Expanded(
                      child: ExcludeSemantics(
                        child: SingleChildScrollView(
                          key: const Key('player-now-playing-details'),
                          primary: false,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (controller.lineup.settings.preferClearLogos &&
                                  logoPath != null)
                                _NowPlayingIdentity(
                                  key: ValueKey((
                                    artworkIdentity,
                                    GuideArtworkKind.clearLogo,
                                    logoPath,
                                  )),
                                  controller: controller,
                                  program: program,
                                  compact: dense,
                                )
                              else
                                _NowPlayingTitle(item: item, compact: dense),
                              if (editorial.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  editorial,
                                  key: const Key(
                                    'player-now-playing-editorial',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _nowPlayingSecondaryStyle(
                                    context,
                                    dense: dense,
                                  ),
                                ),
                              ],
                              if (badges.isNotEmpty) ...[
                                const SizedBox(height: 12),
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
                                const SizedBox(height: 12),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 900,
                                  ),
                                  child: Text(
                                    summary,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    key: const Key(
                                      'player-now-playing-summary',
                                    ),
                                    style: Theme.of(context).textTheme.bodyLarge
                                        ?.copyWith(
                                          color: roles.primaryText,
                                          height: 1.45,
                                        ),
                                  ),
                                ),
                              ],
                              if (item.cast.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                _NowPlayingCast(
                                  controller: controller,
                                  cast: item.cast,
                                  dense: dense,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

TextStyle? _nowPlayingSecondaryStyle(
  BuildContext context, {
  required bool dense,
}) {
  return Theme.of(context).textTheme.bodyMedium
      ?.copyWith(color: LineupTheme.of(context).secondaryText, fontSize: 18);
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
      final item = widget.program.scheduled.item;
      final showTitle = item.showTitle?.trim();
      const logoMaxHeight = 72.0;
      // Keep the artwork slot proportional to its compact height, so the
      // shared relative-size guard evaluates this title-art layout rather
      // than the retired tall shelf's much wider reservation.
      const logoMaxWidth = logoMaxHeight * 6;
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
                    maximumVisibleHeight: 56,
                    excludeFromSemantics: true,
                    maximumSize: Size(logoMaxWidth, logoMaxHeight),
                    minimumVisibleSize: Size(96, (widget.compact ? 20 : 28)),
                    fallback: logoFallback,
                  ),
                ),
              SizedBox(height: (widget.compact ? 8 : 12)),
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
  Widget build(BuildContext context) {
    return Column(
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
          SizedBox(height: 6),
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
}

TextStyle? _nowPlayingSeriesStyle(
  BuildContext context, {
  required bool dense,
}) => _nowPlayingSecondaryStyle(
  context,
  dense: dense,
)?.copyWith(fontSize: 18, fontWeight: FontWeight.w500);

TextStyle _nowPlayingTitleStyle(BuildContext context, {required bool dense}) =>
    LineupTypography.programTitle.copyWith(
      color: LineupTheme.of(context).primaryText,
      shadows: _overlayTextShadow,
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
  Widget build(BuildContext context) {
    return ColoredBox(
      color: roles.primarySurface,
      child: Icon(Icons.movie_outlined, size: 64, color: roles.mutedText),
    );
  }
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
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontSize: (Theme.of(context).textTheme.labelMedium?.fontSize ?? 12),
          ),
        ),
      ),
    );
  }
}

double _textWidth(BuildContext context, String text, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

class _NowPlayingCast extends StatelessWidget {
  const _NowPlayingCast({
    required this.controller,
    required this.cast,
    required this.dense,
  });

  final PlayerCoordinator controller;
  final List<ChannelCastMember> cast;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    const limit = 4;
    final visible = cast.take(limit).toList(growable: false);
    final diameter = (dense ? 40.0 : 46.0);
    const gap = 24.0;
    final nameStyle = _nowPlayingSecondaryStyle(
      context,
      dense: dense,
    )?.copyWith(fontSize: 16, height: 1.3, color: roles.primaryText);
    final roleStyle = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: roles.secondaryText, fontSize: 14);
    final naturalWidths = [
      for (final member in visible)
        math.max(
          diameter,
          math.max(
            _textWidth(context, member.name, nameStyle),
            _textWidth(context, member.role ?? '', roleStyle),
          ),
        ),
    ];
    return LayoutBuilder(
      key: const Key('player-now-playing-cast'),
      builder: (context, constraints) {
        final widths = List<double>.of(naturalWidths);
        final available = math.max(
          0.0,
          constraints.maxWidth - gap * math.max(0, visible.length - 1),
        );
        // Preserve natural content widths when they fit. When constrained,
        // share the remaining space without reserving wide blank columns.
        var remaining = available;
        final pending = <int>{for (var i = 0; i < widths.length; i++) i};
        while (pending.isNotEmpty) {
          final share = remaining / pending.length;
          final fitting = pending.where((i) => widths[i] <= share).toList();
          if (fitting.isEmpty) {
            for (final i in pending) {
              widths[i] = share;
            }
            break;
          }
          for (final i in fitting) {
            remaining -= widths[i];
            pending.remove(i);
          }
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (index, member) in visible.indexed) ...[
              if (index > 0) const SizedBox(width: gap),
              _NowPlayingCastColumn(
                key: ValueKey('player-now-playing-cast-column-$index'),
                width: widths[index],
                diameter: diameter,
                index: index,
                member: member,
                controller: controller,
                roles: roles,
                dense: dense,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Measure painted bounds after layout: canvas pixels may be scaled before
/// they reach the window, independently of the device's pixel ratio.
class _CastPortrait extends StatefulWidget {
  const _CastPortrait({
    required this.portrait,
    required this.controller,
    required this.fallback,
  });
  final Uri portrait;
  final PlayerCoordinator controller;
  final Widget fallback;
  @override
  State<_CastPortrait> createState() => _CastPortraitState();
}

class _CastPortraitState extends State<_CastPortrait> {
  Future<Uint8List?>? _future;
  Object? _requestKey;
  bool _measurementPending = false;
  int? _generation;

  @override
  void didUpdateWidget(covariant _CastPortrait oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.portrait != widget.portrait ||
        oldWidget.controller != widget.controller) {
      _future = null;
      _requestKey = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final generation = widget.controller.lineup.contentGeneration;
    if (_generation != generation) {
      _generation = generation;
      _future = null;
      _requestKey = null;
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    if (!_measurementPending) {
      _measurementPending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _measurementPending = false;
        if (!mounted) return;
        final box = context.findRenderObject() as RenderBox;
        if (!box.hasSize) return;
        final painted = MatrixUtils.transformRect(
          box.getTransformTo(null),
          Offset.zero & box.size,
        );
        final width = (painted.width * dpr).ceil().clamp(1, 4096);
        final height = (painted.height * dpr).ceil().clamp(1, 4096);
        final key = (
          widget.controller,
          widget.controller.lineup.contentGeneration,
          widget.portrait,
          width,
          height,
        );
        if (key == _requestKey) return;
        setState(() {
          _requestKey = key;
          _future = widget.controller.guide.artworkForPath(
            widget.portrait,
            width: width,
            height: height,
          );
        });
      });
    }
    return _future == null
        ? widget.fallback
        : _PlayerArtwork(
            key: ValueKey(_requestKey),
            future: _future!,
            fit: BoxFit.cover,
            fallback: widget.fallback,
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
    )?.copyWith(fontSize: 16, height: 1.3, color: roles.primaryText);
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
      crossAxisAlignment: CrossAxisAlignment.start,
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
                  : _CastPortrait(
                      portrait: portrait,
                      controller: controller,
                      fallback: _CastFallback(index: index, roles: roles),
                    ),
            ),
          ),
        ),
        SizedBox(height: 6),
        SizedBox(
          width: width,
          child: Tooltip(
            message: member.name,
            excludeFromSemantics: true,
            child: Text(
              displayName,
              key: ValueKey('player-now-playing-cast-name-$index'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.start,
              style: nameStyle,
            ),
          ),
        ),
        if (member.role case final role? when role.trim().isNotEmpty) ...[
          const SizedBox(height: 3),
          SizedBox(
            width: width,
            child: Tooltip(
              message: role,
              child: Text(
                role,
                key: ValueKey('player-now-playing-cast-role-$index'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.start,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: roles.secondaryText, fontSize: 14),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CastFallback extends StatelessWidget {
  const _CastFallback({required this.index, required this.roles});

  final int index;
  final LineupThemeRoles roles;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: ValueKey('player-now-playing-cast-fallback-$index'),
      color: roles.elevatedSurface,
      child: Icon(Icons.person, size: 24, color: roles.mutedText),
    );
  }
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
    final horizontal =
        size.height >= 720 && !LineupLayout.isCompactWidth(size.width);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final layoutTextScale = textScale < 1 ? 1.0 : textScale;
    final large = horizontal && size.width >= 1920 && size.height >= 1080;
    final rowHeight = horizontal
        ? (large ? 66.0 : 56.0) * layoutTextScale
        : null;
    final channelColumnWidth = (large ? 365.0 : 250.0);
    final columnGap = (large ? 36.0 : 24.0);
    final contentInset = (horizontal
        ? (large ? 48.0 : 32.0)
        : roles.overlaySafeArea);
    final rowInset = (large ? 18.0 : 12.0);
    const fadeTail = 55.0;
    final theme = Theme.of(context);
    return DefaultTextStyle(
      style: theme.textTheme.bodyMedium!,
      child: Builder(
        builder: (context) => Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            bottom: false,
            child: CustomPaint(
              painter: _MiniGuideFadePainter(
                scrim: _overlayColor(context, controller),
                lighter:
                    controller.lineup.settings.overlayTransparency ==
                    OverlayTransparency.moreTransparent,
                tailHeight: fadeTail,
              ),
              child: Container(
                key: const Key('mini-guide-shelf'),
                width: double.infinity,
                constraints: BoxConstraints(maxHeight: size.height),
                padding: EdgeInsets.fromLTRB(
                  contentInset,
                  12,
                  contentInset,
                  16,
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
                        GestureBinding.instance.pointerSignalResolver.register(
                          event,
                          (_) {
                            controller.moveMiniGuide(
                              event.scrollDelta.dy > 0 ? 1 : -1,
                            );
                          },
                        );
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 12,
                            runSpacing: 4,
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
                                            fontSize: (large ? 26 : 20),
                                            fontWeight: FontWeight.w500,
                                          ),
                                    ),
                                  ),
                                  SizedBox(width: 20),
                                  Text(
                                    _time(context, controller.guide.now),
                                    style: TextStyle(
                                      color: roles.secondaryText,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      controller.showFullGuide();
                                      openGuide();
                                    },
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text('Full Guide'),
                                        SizedBox(width: 8),
                                        ExcludeSemantics(
                                          child: Icon(
                                            Icons.arrow_forward,
                                            size: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: controller.closeOverlay,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text('Close'),
                                        SizedBox(width: 8),
                                        ExcludeSemantics(
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
                                large ? 8 : 6,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: channelColumnWidth,
                                    child: Text(
                                      'Channel',
                                      style: TextStyle(
                                        color: roles.secondaryText,
                                        fontSize: 18,
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
                                        fontSize: 18,
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
                                        fontSize: 18,
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
                              rowInset: rowInset,
                              isLast: index == channels.length - 1,
                            ),
                          SizedBox(height: 8),
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              Text(
                                'Up / Down · Browse · Enter Tune · Esc Close',
                                style: TextStyle(
                                  color: roles.secondaryText,
                                  fontSize: 18,
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Previous channel',
                                    constraints: BoxConstraints(
                                      minWidth: 44,
                                      minHeight: 44,
                                    ),
                                    padding: EdgeInsets.zero,
                                    onPressed: () =>
                                        controller.moveMiniGuide(-1),
                                    icon: Icon(Icons.arrow_upward, size: 24),
                                  ),
                                  IconButton(
                                    tooltip: 'Next channel',
                                    constraints: BoxConstraints(
                                      minWidth: 44,
                                      minHeight: 44,
                                    ),
                                    padding: EdgeInsets.zero,
                                    onPressed: () =>
                                        controller.moveMiniGuide(1),
                                    icon: Icon(Icons.arrow_downward, size: 24),
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
  final double rowInset;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final focused = channel.id == controller.miniGuideChannelId;
    final foreground = roles.primaryText;
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
      fontSize: 18,
      fontWeight: FontWeight.w500,
    );
    final metadataStyle = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: roles.secondaryText, fontSize: 18);
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
                  size: (large ? 14 : 12),
                  color: roles.secondaryText,
                ),
              ),
              SizedBox(width: 4),
              Flexible(
                child: Text(
                  'Watching',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: metadataStyle,
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
          SizedBox(height: 3),
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
    final numberText = '${channel.number}';
    final numberMeasure = TextPainter(
      text: TextSpan(text: numberText, style: titleStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    )..layout();
    final numberWidth = math.max(
      (large ? 46.0 : 32.0),
      numberMeasure.width + 8,
    );
    numberMeasure.dispose();
    final number = SizedBox(
      width: numberWidth,
      child: Text(numberText, style: titleStyle),
    );
    return Semantics(
      key: Key('mini-guide-row-${channel.id}'),
      selected: focused,
      label:
          'Channel ${channel.number}, ${channel.name}. Now $currentText.${next == null ? '' : ' Next ${next.scheduled.item.title}.'}${tuned ? ' Now watching.' : ''}',
      child: LineupRowSurface(
        selected: focused,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isLast
                    ? Colors.transparent
                    : roles.primaryText.withValues(alpha: 0.10),
                width: 1.0,
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
                        vertical: 7,
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
      ),
    );
  }
}

class _MiniGuideFadePainter extends CustomPainter {
  const _MiniGuideFadePainter({
    required this.scrim,
    required this.tailHeight,
    required this.lighter,
  });

  final Color scrim;
  final double tailHeight;
  final bool lighter;

  @override
  void paint(Canvas canvas, Size size) {
    final content = Offset.zero & size;
    final paint = Paint()..color = scrim;
    if (lighter) {
      paint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          scrim.withValues(alpha: .78),
          scrim.withValues(alpha: .66),
          scrim.withValues(alpha: .62),
          scrim.withValues(alpha: .52),
        ],
        stops: const [0, .4, .85, 1],
      ).createShader(content);
    }
    canvas.drawRect(content, paint);
    final tail = Rect.fromLTWH(0, size.height, size.width, tailHeight);
    canvas.drawRect(
      tail,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lighter ? scrim.withValues(alpha: .52) : scrim,
            scrim.withValues(alpha: 0),
          ],
        ).createShader(tail),
    );
  }

  @override
  bool shouldRepaint(covariant _MiniGuideFadePainter oldDelegate) =>
      scrim != oldDelegate.scrim ||
      lighter != oldDelegate.lighter ||
      tailHeight != oldDelegate.tailHeight;
}

class _SleepTimerPicker extends StatelessWidget {
  const _SleepTimerPicker({
    required this.controller,
    required this.restoreFocus,
    required this.anchor,
  });

  final PlayerCoordinator controller;
  final VoidCallback restoreFocus;
  final LayerLink anchor;

  void _choose(Duration? duration) {
    controller.setSleepTimer(duration);
    restoreFocus();
  }

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final availableHeight =
        size.height - mediaQuery.padding.vertical - (24 + 132);
    final maxHeight = math
        .min(size.height - 180, availableHeight)
        .clamp(240.0, double.infinity)
        .toDouble();
    final supportingText = Color.lerp(
      roles.secondaryText,
      roles.primaryText,
      0.65,
    )!;
    final theme = Theme.of(context);
    final selected = controller.sleepDuration;
    final remaining = controller.sleepRemaining;
    final choices = <(String, Duration?)>[
      ('Off', null),
      ('30 minutes', const Duration(minutes: 30)),
      ('1 hour', const Duration(hours: 1)),
      ('90 minutes', const Duration(minutes: 90)),
    ];
    return Positioned.fill(
      child: Align(
        alignment: Alignment.topLeft,
        child: CompositedTransformFollower(
          link: anchor,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topRight,
          followerAnchor: Alignment.bottomRight,
          offset: const Offset(0, -8),
          child: Material(
            key: const Key('sleep-timer-picker'),
            color: _overlayColor(context, controller),
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 354,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Sleep timer',
                                style: theme.textTheme.titleLarge,
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                controller.closeOverlay();
                                restoreFocus();
                              },
                              child: const _OverlayCloseLabel(),
                            ),
                          ],
                        ),
                        if (remaining != null)
                          Text(
                            'Sleep · ${(remaining.inSeconds / 60).ceil()}m',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: supportingText,
                            ),
                          ),
                        for (final choice in choices)
                          LineupRowSurface(
                            selected: choice.$2 == selected,
                            child: ListTile(
                              key: Key(
                                'sleep-timer-${choice.$2?.inMinutes ?? 'off'}',
                              ),
                              minTileHeight: 44,
                              autofocus: choice.$2 == selected,
                              title: Text(choice.$1),
                              trailing: choice.$2 == selected
                                  ? Icon(
                                      Icons.check,
                                      color: roles.progressFill,
                                      size: 20,
                                      semanticLabel: 'Selected preset',
                                    )
                                  : null,
                              onTap: () => _choose(choice.$2),
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
        final railWidth = math.min(constraints.maxWidth * 0.4, 600.0);
        final fadeWidth = math.min(55.0, constraints.maxWidth - railWidth);
        final padding = constraints.maxWidth <= 800
            ? EdgeInsets.all(20)
            : EdgeInsets.fromLTRB(36, 48, 48, 36);
        final textTheme = Theme.of(context).textTheme;

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
                    _overlayColor(context, widget.controller),
                    _overlayColor(context, widget.controller),
                    _overlayColor(context, widget.controller),
                  ],
                  stops: [
                    0,
                    fadeWidth / (railWidth + fadeWidth),
                    fadeWidth / (railWidth + fadeWidth),
                    1,
                  ],
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
                                style: textTheme.headlineSmall,
                              ),
                            ),
                            TextButton(
                              autofocus:
                                  tracks.isEmpty &&
                                  widget.type != PlayerTrackType.subtitle,
                              onPressed: widget.controller.closeOverlay,
                              child: const _OverlayCloseLabel(),
                            ),
                          ],
                        ),
                        SizedBox(height: 36),
                        if (tracks.isEmpty &&
                            widget.type == PlayerTrackType.subtitle)
                          Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text(
                              widget.controller.tuning ||
                                      widget.controller.status.state ==
                                          PlayerState.loading
                                  ? 'Loading tracks…'
                                  : 'No subtitle tracks available',
                              style: textTheme.bodyMedium,
                            ),
                          ),
                        Expanded(
                          child: _TrackListFade(
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
                                      style: textTheme.bodyMedium,
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
                                              final display = track == null
                                                  ? null
                                                  : formatPlayerTrackDisplay(
                                                      track,
                                                      peers: tracks,
                                                    );
                                              final title = off
                                                  ? 'Off'
                                                  : display!.primaryText;
                                              final metadata =
                                                  display?.secondaryFacts ??
                                                  const <String>[];
                                              final metadataText = metadata
                                                  .join(' • ');

                                              final tooltip =
                                                  display?.tooltipText ?? title;
                                              final pending =
                                                  widget
                                                          .controller
                                                          .pendingTrackType ==
                                                      widget.type &&
                                                  widget
                                                          .controller
                                                          .pendingTrackId ==
                                                      track?.id;
                                              final semanticLabel =
                                                  track == null
                                                  ? 'Select subtitle track: Off.'
                                                  : display!.semanticsText;
                                              void selectTrack() {
                                                unawaited(
                                                  widget.controller.selectTrack(
                                                    widget.type,
                                                    track?.id,
                                                  ),
                                                );
                                              }

                                              return Focus(
                                                canRequestFocus: false,
                                                skipTraversal: true,
                                                onFocusChange: (focused) {
                                                  if (!focused) return;
                                                  WidgetsBinding.instance
                                                      .addPostFrameCallback((
                                                        _,
                                                      ) {
                                                        if (mounted &&
                                                            context.mounted) {
                                                          Scrollable.ensureVisible(
                                                            context,
                                                            alignment: .5,
                                                          );
                                                        }
                                                      });
                                                },
                                                child: Material(
                                                  key:
                                                      (off
                                                          ? _initialSelectedTrackId ==
                                                                null
                                                          : track!.id ==
                                                                _initialSelectedTrackId)
                                                      ? _selectedRowKey
                                                      : null,
                                                  color: Colors.transparent,
                                                  child: Semantics(
                                                    label: pending
                                                        ? '$semanticLabel Pending.'
                                                        : semanticLabel,
                                                    button: true,
                                                    selected: selected,
                                                    onTap: selectTrack,
                                                    excludeSemantics: true,
                                                    child: LineupRowSurface(
                                                      selected: selected,
                                                      child: ListTile(
                                                        key: Key(
                                                          off
                                                              ? 'playback-track-off'
                                                              : 'playback-track-${widget.type.name}-${track!.id}',
                                                        ),
                                                        autofocus: selected,
                                                        selected: selected,
                                                        minTileHeight: null,
                                                        contentPadding:
                                                            EdgeInsets.symmetric(
                                                              horizontal: 12,
                                                              vertical: 8,
                                                            ),
                                                        title: Tooltip(
                                                          message: tooltip,
                                                          excludeFromSemantics:
                                                              true,
                                                          child: Text(
                                                            title,
                                                            maxLines: 3,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            softWrap: true,
                                                            style: textTheme
                                                                .bodyLarge
                                                                ?.copyWith(
                                                                  color: roles
                                                                      .primaryText,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
                                                                ),
                                                          ),
                                                        ),
                                                        subtitle:
                                                            metadata.isEmpty
                                                            ? null
                                                            : Text(
                                                                metadataText,
                                                                maxLines: 3,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                softWrap: true,
                                                                style: textTheme
                                                                    .bodyMedium
                                                                    ?.copyWith(
                                                                      color:
                                                                          supportingText,
                                                                    ),
                                                              ),
                                                        trailing: SizedBox(
                                                          width: 30,
                                                          child: Center(
                                                            child: pending
                                                                ? SizedBox.square(
                                                                    dimension:
                                                                        18,
                                                                    child: CircularProgressIndicator(
                                                                      strokeWidth:
                                                                          2,
                                                                    ),
                                                                  )
                                                                : selected
                                                                ? Icon(
                                                                    Icons.check,
                                                                    color: roles
                                                                        .progressFill,
                                                                    size: 24,
                                                                  )
                                                                : const SizedBox.shrink(),
                                                          ),
                                                        ),
                                                        onTap: selectTrack,
                                                      ),
                                                    ),
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
                        SizedBox(height: 24),
                        if (widget.controller.trackSelectionError
                            case final error?)
                          Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                error,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ),
                        Padding(
                          key: const Key('playback-options-footer'),
                          padding: EdgeInsets.only(top: 20),
                          child: Text(
                            'Up/Down Browse · Enter Select · Esc Close',
                            style: textTheme.bodySmall?.copyWith(
                              color: supportingText,
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
      },
    );
  }
}

class _ChannelNumber extends StatelessWidget {
  const _ChannelNumber({required this.controller});
  final PlayerCoordinator controller;
  @override
  Widget build(BuildContext context) => _StatusBug(
    controller: controller,
    text: controller.channelNumberLabel,
    number: true,
  );
}

class _StatusBug extends StatelessWidget {
  const _StatusBug({
    required this.controller,
    required this.text,
    this.number = false,
  });
  final PlayerCoordinator controller;
  final String text;
  final bool number;
  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    return Align(
      alignment: Alignment.topRight,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Semantics(
            liveRegion: true,
            label: text,
            child: Container(
              key: number
                  ? const Key('channel-number-buffer')
                  : const Key('player-status-bug'),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * .65,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _overlayColor(context, controller),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: roles.primaryText,
                  shadows: _overlayTextShadow,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StoppedSlate extends StatelessWidget {
  const _StoppedSlate({required this.controller, this.onClose});
  final PlayerCoordinator controller;
  final VoidCallback? onClose;
  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final failed =
        controller.error != null ||
        controller.status.state == PlayerState.error;
    final title = controller.status.state == PlayerState.unsupported
        ? 'Playback unavailable'
        : failed && controller.position == Duration.zero
        ? "Couldn't start playback"
        : 'Playback stopped';
    final channel = controller.currentChannel;
    return ColoredBox(
      color: roles.deepBackground,
      child: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Semantics(
              liveRegion: true,
              label: failed ? 'Playback error' : title,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (channel != null)
                    Text(
                      '${channel.number} · ${channel.name}',
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(color: roles.secondaryText),
                    ),
                  const SizedBox(height: 12),
                  Text(title, style: Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(height: 12),
                  Text(
                    controller.error ?? controller.status.message,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    children: [
                      if (controller.canRetry)
                        FilledButton(
                          onPressed: controller.retry,
                          child: const Text('Retry'),
                        ),
                      OutlinedButton(
                        onPressed: controller.showMiniGuide,
                        child: const Text('Browse channels'),
                      ),
                      TextButton(
                        onPressed: onClose ?? controller.closeOverlay,
                        child: const Text('Close'),
                      ),
                    ],
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

class _Loading extends StatelessWidget {
  const _Loading({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        liveRegion: true,
        label: label,
        child: SizedBox.square(
          dimension: 56,
          child: CircularProgressIndicator(
            strokeWidth: 4,
            color: LineupTheme.of(context).progressFill,
            backgroundColor: LineupTheme.of(context).primaryText
                .withValues(alpha: .12),
          ),
        ),
      ),
    );
  }
}

class _Unsupported extends StatelessWidget {
  const _Unsupported({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final headlineStyle = textTheme.headlineSmall;

    final bodyStyle = textTheme.bodyMedium;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : 0,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.desktop_windows_outlined, size: 54),
                SizedBox(height: 18),
                Text('Playback unavailable', style: headlineStyle),
                SizedBox(height: 8),
                Text(message, style: bodyStyle),
              ],
            ),
          ),
        ),
      ),
    );
  }
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

Widget _osdAction(
  BuildContext context, {
  required Key key,
  required String label,
  required String tooltip,
  String? semanticLabel,
  required IconData icon,
  required VoidCallback? onPressed,
  FocusNode? focusNode,
}) {
  return ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 44),
    child: Tooltip(
      message: tooltip,
      excludeFromSemantics: semanticLabel != null,
      child: Semantics(
        label: semanticLabel,
        button: semanticLabel == null ? null : true,
        enabled: semanticLabel == null ? null : onPressed != null,
        onTap: semanticLabel == null ? null : onPressed,
        excludeSemantics: semanticLabel != null,
        child: TextButton(
          key: key,
          style: _playerActionStyle(context),
          focusNode: focusNode,
          onPressed: onPressed,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20),
              SizedBox(width: 8),
              Flexible(child: Text(label, softWrap: true)),
            ],
          ),
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

const _overlayTextShadow = [
  Shadow(color: Color(0x66000000), blurRadius: 3, offset: Offset(0, 1)),
];

double _overlayOpacity(PlayerCoordinator controller, {double more = .78}) =>
    switch (controller.lineup.settings.overlayTransparency) {
      OverlayTransparency.moreTransparent => more,
      OverlayTransparency.standard => .78,
      OverlayTransparency.reduced => .94,
    };
Color _overlayColor(
  BuildContext context,
  PlayerCoordinator controller, {
  double more = .78,
}) =>
    LineupTheme.of(context).overlaySurface
        .withValues(alpha: _overlayOpacity(controller, more: more));

ButtonStyle _playerActionStyle(BuildContext context) {
  final roles = LineupTheme.of(context);
  return LineupTheme.buttonStyle(
    roles,
    LineupButtonTier.text,
    compact: true,
    focusVisible: LineupFocusScope.visible(context),
  ).copyWith(
    textStyle: WidgetStatePropertyAll(
      LineupTypography.button.copyWith(
        fontSize: 16,
        shadows: _overlayTextShadow,
      ),
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? roles.secondaryText.withValues(alpha: .45)
          : roles.secondaryText,
    ),
    minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
  );
}

class _OsdPanelMaterial extends CustomPainter {
  const _OsdPanelMaterial({required this.color, required this.collapsedFade});
  final Color color;
  final bool collapsedFade;

  @override
  void paint(Canvas canvas, Size size) {
    const feather = 55.0;
    final bounds = Rect.fromLTWH(
      0,
      -feather,
      size.width,
      size.height + feather,
    );
    final join = feather / bounds.height;
    final colors = collapsedFade
        ? [
            color.withValues(alpha: 0),
            color.withValues(alpha: 0),
            color.withValues(alpha: .08),
            color.withValues(alpha: .30),
            color.withValues(alpha: .45),
          ]
        : [color.withValues(alpha: 0), color, color];
    final stops = collapsedFade
        ? [0.0, join, join + (1 - join) * .2, join + (1 - join) * .6, 1.0]
        : [0.0, join, 1.0];
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
          stops: stops,
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_OsdPanelMaterial oldDelegate) =>
      color != oldDelegate.color || collapsedFade != oldDelegate.collapsedFade;
}

class _TrackListFade extends StatelessWidget {
  const _TrackListFade({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ShaderMask(
    blendMode: BlendMode.dstIn,
    shaderCallback: (bounds) => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [
        Colors.transparent,
        Colors.white,
        Colors.white,
        Colors.transparent,
      ],
      stops: [
        0,
        math.min(8 / bounds.height, .1),
        math.max(1 - 8 / bounds.height, .9),
        1,
      ],
    ).createShader(bounds),
    child: ClipRect(child: child),
  );
}

class _OverlayTextTheme extends StatelessWidget {
  const _OverlayTextTheme({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    TextStyle? shadow(TextStyle? style) =>
        style?.copyWith(shadows: _overlayTextShadow);
    return Theme(
      data: theme.copyWith(
        textTheme: text.copyWith(
          displayLarge: shadow(text.displayLarge),
          displayMedium: shadow(text.displayMedium),
          displaySmall: shadow(text.displaySmall),
          headlineLarge: shadow(text.headlineLarge),
          headlineMedium: shadow(text.headlineMedium),
          headlineSmall: shadow(text.headlineSmall),
          titleLarge: shadow(text.titleLarge),
          titleMedium: shadow(text.titleMedium),
          titleSmall: shadow(text.titleSmall),
          bodyLarge: shadow(text.bodyLarge),
          bodyMedium: shadow(text.bodyMedium),
          bodySmall: shadow(text.bodySmall),
          labelLarge: shadow(text.labelLarge),
          labelMedium: shadow(text.labelMedium),
          labelSmall: shadow(text.labelSmall),
        ),
      ),
      child: child,
    );
  }
}

class _OverlayCloseLabel extends StatelessWidget {
  const _OverlayCloseLabel();

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('Close'),
      SizedBox(width: 6),
      ExcludeSemantics(child: Icon(Icons.close, size: 16)),
    ],
  );
}
