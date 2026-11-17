import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:lineup_desktop/platform/device_profile.dart';

import '../app/navigation_shortcuts.dart';
import '../channels/channel.dart';
import '../channels/channel_artwork.dart';
import '../ui/media_badges.dart';
import '../guide/guide_controller.dart';
import '../guide/focused_ticker.dart';
import '../settings/lineup_settings.dart';
import '../ui/app_theme.dart';
import '../ui/app_ui.dart';
import '../ui/channel_identity.dart';
import '../ui/lineup_canvas.dart';
import 'native_player.dart';
import 'native_video_surface.dart';
import 'subtitle_layer.dart';
import 'player_coordinator.dart';
import 'player_key_resolver.dart';
import 'player_track_label.dart';

class PlayerView extends StatefulWidget {
  const PlayerView({
    required this.controller,
    required this.openGuide,
    this.openMenu,
    this.onBackToGuide,
    this.onOpenDiagnostics,
    this.focusNode,
    super.key,
  });

  final PlayerCoordinator controller;
  final VoidCallback openGuide;
  final VoidCallback? onBackToGuide;
  final VoidCallback? onOpenDiagnostics;
  final LineupMenuCallback? openMenu;
  final FocusNode? focusNode;

  @override
  State<PlayerView> createState() => PlayerViewState();
}

enum _PlayerControl {
  guide,
  previous,
  playback,
  next,
  subtitles,
  audio,
  sleep,
  menu,
  close,
  moreInfo,
}

PlayerTrackType? _trackOverlayType(PlayerOverlay overlay) => switch (overlay) {
  PlayerOverlay.audioTracks => PlayerTrackType.audio,
  PlayerOverlay.subtitleTracks => PlayerTrackType.subtitle,
  _ => null,
};

bool _isBottomPanel(PlayerOverlay overlay) =>
    overlay == PlayerOverlay.osd || overlay == PlayerOverlay.nowPlaying;

bool _usesTrackPopover(PlayerTrackType type, List<PlayerTrack> tracks) =>
    tracks.where((track) => track.type == type).length +
        (type == PlayerTrackType.subtitle ? 1 : 0) <=
    6;

_PlayerControl _trackControl(PlayerTrackType type) =>
    type == PlayerTrackType.subtitle
    ? _PlayerControl.subtitles
    : _PlayerControl.audio;

class PlayerViewState extends State<PlayerView> with WidgetsBindingObserver {
  final _trackDisplays = PlayerTrackDisplayCache();
  final _subtitleAvoidance = SubtitlePanelAvoidance();
  final _subtitleLayerKey = GlobalKey();
  final _overlayFocus = FocusNode(debugLabel: 'Player overlay controls');
  late PlayerOverlay _renderedOverlay;
  late int _bottomPanelGeneration;
  var _overlayTransitionDuration = const Duration(milliseconds: 350);
  final _controls = {
    for (final control in _PlayerControl.values)
      control: FocusNode(
        debugLabel: switch (control) {
          _PlayerControl.menu => 'Player Lineup menu',
          _PlayerControl.sleep => 'Player sleep timer',
          _ => 'Player ${control.name}',
        },
      ),
  };
  FocusNode get _menuFocus => _controls[_PlayerControl.menu]!;
  FocusNode get _sleepFocus => _controls[_PlayerControl.sleep]!;
  _PlayerControl _lastAction = _PlayerControl.subtitles;
  PlayerOverlay? _trackOrigin;
  bool _trackPopoverOpen = false;
  bool get _isTv => DeviceProfile.of(context).isTv;
  var _pickerAnchors = _newPickerAnchors();

  static Map<_PlayerControl, _PickerAnchorHandle> _newPickerAnchors() => {
    _PlayerControl.sleep: _PickerAnchorHandle(),
    _PlayerControl.audio: _PickerAnchorHandle(),
    _PlayerControl.subtitles: _PickerAnchorHandle(),
  };
  Timer? _visibleClockTimer;
  var _appActive = true;
  var _focusRecoveryScheduled = false;
  var _keyboardInput = false;
  final _internalRootFocus = FocusNode(debugLabel: 'Player root');
  FocusNode get _rootFocus => widget.focusNode ?? _internalRootFocus;

  @override
  void initState() {
    super.initState();
    _renderedOverlay = widget.controller.overlay;
    if (_trackOverlayType(_renderedOverlay) case final type?) {
      _trackPopoverOpen = _usesTrackPopover(type, widget.controller.tracks);
    }
    _bottomPanelGeneration = widget.controller.overlayPresentationGeneration;
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_changed);
    HardwareKeyboard.instance.addHandler(_trackKeyboardInput);
    FocusManager.instance.addListener(_scheduleFocusRecovery);
    _syncVisibleClockTimer();
    for (final entry in _controls.entries) {
      entry.value.addListener(() {
        if (entry.value.hasPrimaryFocus &&
            entry.key != _PlayerControl.close &&
            entry.key != _PlayerControl.moreInfo) {
          _lastAction = entry.key;
        }
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _isTv &&
          widget.controller.overlay == PlayerOverlay.nowPlaying) {
        _focusTvAction(first: true);
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    FocusManager.instance.removeListener(_scheduleFocusRecovery);
    WidgetsBinding.instance.removeObserver(this);
    _visibleClockTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_trackKeyboardInput);
    _subtitleAvoidance.dispose();
    _internalRootFocus.dispose();
    _overlayFocus.dispose();
    for (final node in _controls.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (_appActive == active) return;
    setState(() => _appActive = active);
    _syncVisibleClockTimer();
    if (active) {
      unawaited(widget.controller.checkSleepDeadline());
      _scheduleFocusRecovery();
    }
  }

  bool get _canOwnFocus =>
      mounted &&
      _appActive &&
      widget.controller.overlay != PlayerOverlay.fullGuide &&
      _rootFocus.parent != null &&
      _rootFocus.canRequestFocus &&
      ModalRoute.of(context)?.isCurrent == true;

  bool get _focusStrandedAbovePlayer {
    final primary = FocusManager.instance.primaryFocus;
    return primary == null ||
        (primary is FocusScopeNode && _rootFocus.ancestors.contains(primary));
  }

  void _scheduleFocusRecovery() {
    if (!mounted ||
        !_appActive ||
        _focusRecoveryScheduled ||
        !_focusStrandedAbovePlayer) {
      return;
    }
    _focusRecoveryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusRecoveryScheduled = false;
      // Modal/menu focus and pending autofocus must settle first. Reclaim only
      // empty focus or an ancestor scope, never a control or another route.
      if (_canOwnFocus && _focusStrandedAbovePlayer) {
        _rootFocus.requestFocus();
      }
    });
    // Focus loss and resume need not otherwise schedule a frame.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Object? _lastHiddenFacts;
  Object? _lastBottomPanelFacts;
  Duration? _lastPosition;
  List<PlayerTrack> _lastTracks = const [];

  // Keep this next to the consumers: the bottom panel's timing/progress widgets
  // subscribe separately. Other notifications (including Guide enrichment with
  // unchanged position) still refresh the complete presentation.
  Object get _bottomPanelFacts {
    final controller = widget.controller;
    final program = controller.currentProgram;
    final next = controller.nextProgram;
    final sleepRemaining = controller.sleepRemaining;
    return (
      _hiddenFacts,
      controller.duration,
      controller.telemetry,
      program?.id,
      program?.scheduled.item,
      next?.id,
      next?.scheduled.item,
      controller.presentedState,
      controller.playbackToggleWillPause,
      controller.fullscreen,
      controller.sleepDuration,
      controller.sleepDeadline,
      sleepRemaining == null ? null : (sleepRemaining.inSeconds / 60).ceil(),
      controller.sleepPickerOpen,
      controller.lineup.contentGeneration,
    );
  }

  // These are the facts read by the hidden Player chrome and PlayerSurface.
  // Position is visible only on the stopped/error slate at its zero boundary.
  Object get _hiddenFacts {
    final controller = widget.controller;
    return (
      controller.overlay,
      controller.overlayPresentationGeneration,
      controller.currentChannel,
      controller.status.state,
      controller.status.message,
      controller.error,
      controller.canRetry,
      controller.notice,
      controller.busyLabel,
      controller.cursorVisible,
      controller.channelTagWindowActive,
      controller.displayHoldActive,
      controller.tuning,
      controller.hasPlaybackIntent,
      controller.lineup.settings,
      controller.hasStartedPlayback,
    );
  }

  void _changed() {
    if (!mounted) return;
    _syncVisibleClockTimer();
    final nextOverlay = widget.controller.overlay;
    final hiddenFacts = _hiddenFacts;
    final bottomPanelFacts = _bottomPanelFacts;
    final hiddenUnchanged = _lastHiddenFacts == hiddenFacts;
    final positionOnly =
        _lastPosition != widget.controller.position &&
        _lastBottomPanelFacts == bottomPanelFacts &&
        listEquals(_lastTracks, widget.controller.tracks);
    _lastHiddenFacts = hiddenFacts;
    _lastBottomPanelFacts = bottomPanelFacts;
    _lastPosition = widget.controller.position;
    _lastTracks = widget.controller.tracks;
    if (_renderedOverlay == nextOverlay &&
        ((nextOverlay == PlayerOverlay.none && hiddenUnchanged) ||
            ((nextOverlay == PlayerOverlay.osd ||
                    nextOverlay == PlayerOverlay.nowPlaying) &&
                positionOnly))) {
      return;
    }
    final nextTrackType = _trackOverlayType(nextOverlay);
    final previousTrackType = _trackOverlayType(_renderedOverlay);
    final enteringTracks = nextTrackType != null && previousTrackType == null;
    final leavingTracks = previousTrackType != null && nextTrackType == null;
    if (enteringTracks) _trackOrigin = _renderedOverlay;
    if (_isTv) {
      if (leavingTracks &&
          nextOverlay == PlayerOverlay.osd &&
          _trackOrigin == PlayerOverlay.nowPlaying) {
        _trackOrigin = null;
        widget.controller.showNowPlaying();
        return;
      }
      final leavingInfo =
          _renderedOverlay == PlayerOverlay.programInfo &&
          nextOverlay != PlayerOverlay.programInfo;
      if (leavingInfo && _canOwnFocus && _rootFocus.hasFocus) {
        _rootFocus.requestFocus();
      }
      if (leavingInfo && nextOverlay == PlayerOverlay.nowPlaying) {
        _restoreMoreInfoFocus();
      } else if ((_renderedOverlay != nextOverlay &&
              nextOverlay == PlayerOverlay.nowPlaying) ||
          ((_renderedOverlay == PlayerOverlay.nowPlaying || leavingTracks) &&
              nextOverlay == PlayerOverlay.osd)) {
        _focusTvAction(
          first: nextOverlay == PlayerOverlay.nowPlaying && !leavingTracks,
        );
      }
    }
    final wasBottom = _isBottomPanel(_renderedOverlay);
    final isBottom = _isBottomPanel(nextOverlay);
    final wasPopover = _trackPopoverOpen;
    final isPopover =
        nextTrackType != null &&
        (nextTrackType == previousTrackType
            ? wasPopover
            : _usesTrackPopover(nextTrackType, widget.controller.tracks));
    if (wasBottom &&
        !isBottom &&
        _canOwnFocus &&
        _rootFocus.hasFocus &&
        FocusManager.instance.primaryFocus?.context
                ?.findAncestorWidgetOfExactType<_Osd>()
                ?.controller ==
            widget.controller) {
      // Keep ownership across retirement before another key can arrive.
      _rootFocus.requestFocus();
    }
    final bottomPanelChanged =
        _renderedOverlay != nextOverlay && wasBottom && isBottom;
    if (leavingTracks) {
      if (!_isTv &&
          _keyboardInput &&
          isBottom &&
          _isBottomPanel(_trackOrigin ?? PlayerOverlay.none)) {
        final invoker = _controls[_trackControl(previousTrackType)]!;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_canOwnFocus &&
              _isBottomPanel(widget.controller.overlay) &&
              _isLiveControl(invoker)) {
            invoker.requestFocus();
            widget.controller.overlayFocusChanged(
              widget.controller.overlay,
              widget.controller.overlayPresentationGeneration,
              true,
            );
          }
        });
      }
      _trackOrigin = null;
    }
    setState(() {
      _trackPopoverOpen = isPopover;
      if (!(wasBottom || wasPopover) && (isBottom || isPopover)) {
        _bottomPanelGeneration =
            widget.controller.overlayPresentationGeneration;
        // The outgoing AnimatedSwitcher child may still have its leaders.
        _pickerAnchors = _newPickerAnchors();
      }
      final transitioningNowPlaying =
          _renderedOverlay == PlayerOverlay.nowPlaying ||
          nextOverlay == PlayerOverlay.nowPlaying;
      final transitioningTracks =
          _renderedOverlay == PlayerOverlay.audioTracks ||
          _renderedOverlay == PlayerOverlay.subtitleTracks ||
          nextOverlay == PlayerOverlay.audioTracks ||
          nextOverlay == PlayerOverlay.subtitleTracks;
      final transitioningInfo =
          _renderedOverlay == PlayerOverlay.programInfo ||
          nextOverlay == PlayerOverlay.programInfo;
      final transitioningMiniGuide =
          _renderedOverlay == PlayerOverlay.miniGuide ||
          nextOverlay == PlayerOverlay.miniGuide;
      _overlayTransitionDuration = Duration(
        milliseconds: transitioningInfo
            ? 300
            : transitioningNowPlaying
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
        if (mounted && _overlayFocus.hasFocus && _keyboardInput && !_isTv) {
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
      if (_isTv &&
          _rootFocus.hasFocus &&
          widget.controller.overlay == PlayerOverlay.osd &&
          !widget.controller.sleepPickerOpen) {
        widget.controller.showOsd();
      }
      if (!_isTv && _rootFocus.hasFocus && !_rootFocus.hasPrimaryFocus) {
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

  bool handleBack() {
    final controller = widget.controller;
    if (controller.sleepPickerOpen) {
      controller.closeSleepPicker();
      _restoreSleepFocus();
      return true;
    }
    return _executeKey(
          resolvePlayerKey(
            LogicalKeyboardKey.goBack,
            overlay: controller.overlay,
            tvRemote: _isTv,
            dvr: controller.lineup.settings.dvrControlsEnabled,
            unsupported: controller.status.state == PlayerState.unsupported,
            initialPress: true,
            hasProgram: false,
          ),
        ) !=
        KeyEventResult.ignored;
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (navigationShortcutDestination(event.logicalKey) != null) {
      return KeyEventResult.ignored;
    }
    final controller = widget.controller;
    var tvOsdAtBottom = false;
    if (_isTv &&
        {
          LogicalKeyboardKey.goBack,
          LogicalKeyboardKey.escape,
          LogicalKeyboardKey.backspace,
        }.contains(event.logicalKey)) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      return handleBack() ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (_isTv && !controller.sleepPickerOpen) {
      final key = event.logicalKey;
      final overlay = controller.overlay;
      final slateFocused =
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<_StoppedSlate>() !=
          null;
      if (slateFocused &&
          {
            LogicalKeyboardKey.arrowLeft,
            LogicalKeyboardKey.arrowRight,
            LogicalKeyboardKey.arrowUp,
            LogicalKeyboardKey.arrowDown,
            LogicalKeyboardKey.select,
            LogicalKeyboardKey.enter,
            LogicalKeyboardKey.numpadEnter,
          }.contains(key)) {
        // These are ordinary focusable recovery buttons, not video shortcuts.
        return KeyEventResult.ignored;
      }
      if (key == LogicalKeyboardKey.mediaRewind ||
          key == LogicalKeyboardKey.mediaFastForward) {
        if (controller.lineup.settings.dvrControlsEnabled &&
            controller.status.state != PlayerState.unsupported) {
          return _executeKey(
            key == LogicalKeyboardKey.mediaRewind
                ? PlayerAction.rewind
                : PlayerAction.fastForward,
          );
        }
        return KeyEventResult.handled;
      }
      if ((overlay == PlayerOverlay.none ||
              (overlay == PlayerOverlay.osd && _rootFocus.hasPrimaryFocus)) &&
          (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter)) {
        controller.showOsd();
        _focusTvAction();
        return KeyEventResult.handled;
      }
      if (overlay == PlayerOverlay.osd || overlay == PlayerOverlay.nowPlaying) {
        final focused = _controls.entries
            .where((entry) => entry.value.hasPrimaryFocus)
            .firstOrNull
            ?.key;
        if (focused != null) {
          tvOsdAtBottom = overlay == PlayerOverlay.osd;
          // Let the focused button's ActivateIntent own Select, rather than
          // the desktop Enter shortcut that collapses Now Playing.
          if (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter) {
            return KeyEventResult.ignored;
          }
          if (key == LogicalKeyboardKey.arrowLeft ||
              key == LogicalKeyboardKey.arrowRight) {
            final actions = _availableTvActions;
            if (actions.isEmpty) return KeyEventResult.handled;
            final index = actions.indexOf(focused);
            final next =
                (index + (key == LogicalKeyboardKey.arrowLeft ? -1 : 1)).clamp(
                  0,
                  actions.length - 1,
                );
            _controls[actions[next]]!.requestFocus();
            return KeyEventResult.handled;
          }
          if (overlay == PlayerOverlay.nowPlaying &&
              (key == LogicalKeyboardKey.arrowUp ||
                  key == LogicalKeyboardKey.arrowDown)) {
            if (key == LogicalKeyboardKey.arrowUp) {
              final moreInfo = _controls[_PlayerControl.moreInfo]!;
              if (focused == _PlayerControl.moreInfo) {
                _controls[_PlayerControl.close]!.requestFocus();
              } else if (focused != _PlayerControl.close &&
                  _isLiveControl(moreInfo)) {
                moreInfo.requestFocus();
              } else {
                _controls[_PlayerControl.close]!.requestFocus();
              }
            } else {
              final moreInfo = _controls[_PlayerControl.moreInfo]!;
              if (focused == _PlayerControl.close && _isLiveControl(moreInfo)) {
                moreInfo.requestFocus();
              } else {
                _focusTvAction(first: true);
              }
            }
            return KeyEventResult.handled;
          }
        }
      }
    }
    return _executeKey(
      resolvePlayerKey(
        event.logicalKey,
        overlay: controller.overlay,
        tvRemote: _isTv,
        dvr: controller.lineup.settings.dvrControlsEnabled,
        unsupported: controller.status.state == PlayerState.unsupported,
        initialPress: event is KeyDownEvent,
        tvOsdAtBottom: tvOsdAtBottom,
        commandPressed:
            defaultTargetPlatform == TargetPlatform.macOS &&
            HardwareKeyboard.instance.isMetaPressed,
        hasProgram:
            (event.logicalKey == LogicalKeyboardKey.arrowDown &&
                    (controller.overlay == PlayerOverlay.none ||
                        controller.overlay == PlayerOverlay.osd)) ||
                (_isTv &&
                    (event.logicalKey == LogicalKeyboardKey.info ||
                        event.logicalKey == LogicalKeyboardKey.keyI))
            ? controller.currentProgram != null
            : false,
      ),
    );
  }

  KeyEventResult _executeKey(PlayerCommand command) {
    final controller = widget.controller;
    if (command.closesSleepPicker) controller.closeSleepPicker();
    switch (command) {
      case PlayerAction.ignored:
        return KeyEventResult.ignored;
      case PlayerAction.consumed:
        break;
      case PlayerAction.backToGuide:
        controller.showFullGuide();
        (widget.onBackToGuide ?? widget.openGuide)();
      case PlayerAction.openGuide:
        controller.showFullGuide();
        widget.openGuide();
      case PlayerAction.openMenu:
        final openMenu = widget.openMenu;
        if (openMenu == null) return KeyEventResult.ignored;
        controller.closeSleepPicker();
        final menuContext = _menuFocus.context;
        final menuVisible =
            controller.overlay == PlayerOverlay.osd ||
            controller.overlay == PlayerOverlay.nowPlaying;
        // FocusNode retains its last context after the animated OSD retires.
        // Hidden/reader menus belong to the live Player, not that old button.
        final menuBox = menuVisible && menuContext?.mounted == true
            ? menuContext!.findRenderObject()
            : null;
        if (_menuFocus.parent != null &&
            _menuFocus.canRequestFocus &&
            menuBox is RenderBox &&
            menuBox.attached &&
            menuBox.hasSize) {
          openMenu(menuContext!, _menuFocus);
        } else {
          final primary = FocusManager.instance.primaryFocus;
          final primaryContext = primary?.context;
          final scope = switch (controller.overlay) {
            PlayerOverlay.audioTracks ||
            PlayerOverlay.subtitleTracks ||
            PlayerOverlay.programInfo => primary?.enclosingScope,
            PlayerOverlay.none || PlayerOverlay.error
                when _isTv &&
                    primaryContext?.mounted == true &&
                    primaryContext!
                            .findAncestorWidgetOfExactType<_StoppedSlate>() !=
                        null =>
              primary?.enclosingScope,
            _ => null,
          };
          // Return through the drawer or recovery scope's focus history.
          final returnToScope =
              scope != null &&
              scope.parent != null &&
              scope.context?.mounted == true &&
              scope.canRequestFocus &&
              scope.ancestors.contains(_rootFocus);
          openMenu(context, returnToScope ? scope : _rootFocus);
        }
      case PlayerAction.collapseNowPlaying || PlayerAction.closeOverlay:
        final restoreSleep = controller.sleepPickerOpen;
        command == PlayerAction.collapseNowPlaying
            ? controller.showOsd()
            : controller.closeOverlay();
        if (restoreSleep) _restoreSleepFocus();
      case AppendChannelDigit(:final digit):
        controller.appendChannelDigit(digit);
      case PlayerAction.commitChannelNumber:
        unawaited(controller.commitChannelNumber());
      case PlayerAction.miniGuideUp:
        controller.moveMiniGuide(-1);
      case PlayerAction.miniGuideDown:
        controller.moveMiniGuide(1);
      case PlayerAction.miniGuidePageUp:
        controller.moveMiniGuide(-7);
      case PlayerAction.miniGuidePageDown:
        controller.moveMiniGuide(7);
      case PlayerAction.previousChannel:
        unawaited(controller.previousChannel());
      case PlayerAction.nextChannel:
        unawaited(controller.nextChannel());
      case PlayerAction.tuneMiniGuide:
        unawaited(controller.tuneMiniGuideSelection());
      case PlayerAction.showOsd:
        controller.showOsd();
        if (_isTv) _focusTvAction(first: true);
      case PlayerAction.showOsdFromInfo:
        controller.showOsd();
      case PlayerAction.togglePlayback:
        unawaited(controller.togglePlayback());
        if (controller.overlay != PlayerOverlay.programInfo) {
          controller.showOsd();
        }
      case PlayerAction.seekBackward || PlayerAction.rewind:
        unawaited(controller.seekBy(const Duration(seconds: -10)));
        if (command == PlayerAction.seekBackward) controller.showOsd();
      case PlayerAction.seekForward || PlayerAction.fastForward:
        unawaited(controller.seekBy(const Duration(seconds: 30)));
        if (command == PlayerAction.seekForward) controller.showOsd();
      case PlayerAction.showMiniGuide:
        controller.showMiniGuide();
      case PlayerAction.showNowPlaying:
        controller.showNowPlaying();
      case PlayerAction.toggleFullscreen:
        unawaited(controller.toggleFullscreen());
      case PlayerAction.showSleepTimer:
        controller.showSleepTimer();
      case PlayerAction.showAudioTracks:
        controller.showTracks(PlayerTrackType.audio);
      case PlayerAction.showSubtitleTracks:
        controller.showTracks(PlayerTrackType.subtitle);
      case PlayerAction.play || PlayerAction.playAndShowOsd:
        unawaited(controller.play());
        if (command == PlayerAction.playAndShowOsd) controller.showOsd();
      case PlayerAction.pause || PlayerAction.pauseAndShowOsd:
        unawaited(controller.pause());
        if (command == PlayerAction.pauseAndShowOsd) controller.showOsd();
      case PlayerAction.stop:
        unawaited(controller.requestStop());
    }
    return KeyEventResult.handled;
  }

  void _restoreMoreInfoFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_canOwnFocus ||
          widget.controller.overlay != PlayerOverlay.nowPlaying) {
        return;
      }
      final invoker = _controls[_PlayerControl.moreInfo]!;
      if (_isLiveControl(invoker)) {
        invoker.requestFocus();
      } else {
        final actions = _availableTvActions;
        (actions.isEmpty ? _rootFocus : _controls[actions.first]!)
            .requestFocus();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _restoreSleepFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        (_keyboardInput ? _sleepFocus : _rootFocus).requestFocus();
      }
    });
  }

  // FocusNode retains its last context after its widget detaches. A retired
  // action cannot accept navigation or restore focus for a later program.
  bool _isLiveControl(FocusNode node) =>
      node.parent != null &&
      node.context?.mounted == true &&
      node.canRequestFocus;

  List<_PlayerControl> get _availableTvActions => [
    for (final entry in _controls.entries)
      if (entry.key != _PlayerControl.close &&
          entry.key != _PlayerControl.moreInfo &&
          _isLiveControl(entry.value))
        entry.key,
  ];

  void _focusTvAction({bool first = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_canOwnFocus) return;
      final overlay = widget.controller.overlay;
      if (overlay != PlayerOverlay.osd && overlay != PlayerOverlay.nowPlaying) {
        return;
      }
      final actions = _availableTvActions;
      if (actions.isEmpty) return;
      final target = !first && actions.contains(_lastAction)
          ? _lastAction
          : actions.contains(_PlayerControl.subtitles)
          ? _PlayerControl.subtitles
          : actions.first;
      _controls[target]!.requestFocus();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    _lastHiddenFacts = _hiddenFacts;
    _lastBottomPanelFacts = _bottomPanelFacts;
    _lastPosition = controller.position;
    _lastTracks = controller.tracks;
    final overlay = controller.overlay;
    final infoProgram = overlay == PlayerOverlay.programInfo
        ? controller.currentProgram
        : null;
    final presentationGeneration = controller.overlayPresentationGeneration;
    final bottomPanel = _isBottomPanel(overlay);
    final trackType = _trackOverlayType(overlay);
    final trackPopover = _trackPopoverOpen ? trackType : null;
    final showsBottomPanel = bottomPanel || trackPopover != null;
    final presentationKey = ValueKey((
      showsBottomPanel ? PlayerOverlay.osd : overlay,
      showsBottomPanel ? _bottomPanelGeneration : presentationGeneration,
    ));
    final desktop = DeviceProfile.of(context).formFactor == FormFactor.desktop;
    final insets = _PlayerInsets.of(context);
    final channel = controller.currentChannel;
    final channelTagSuppressed =
        channel == null ||
        controller.notice != null ||
        controller.busyLabel != null ||
        controller.error != null ||
        (!bottomPanel && overlay != PlayerOverlay.none);
    final showChannelTag =
        !channelTagSuppressed &&
        (bottomPanel || controller.channelTagWindowActive);
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
                } else if (_trackOverlayType(controller.overlay) != null) {
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
                    onOpenDiagnostics: widget.onOpenDiagnostics,
                    subtitleAvoidance: _subtitleAvoidance,
                    subtitleLayerKey: _subtitleLayerKey,
                    onClose: () {
                      controller.showFullGuide();
                      widget.openGuide();
                    },
                  ),
                  if (overlay != PlayerOverlay.channelNumber &&
                      overlay != PlayerOverlay.programInfo &&
                      (controller.notice != null ||
                          controller.busyLabel != null))
                    _StatusBug(
                      controller: controller,
                      text: controller.notice ?? controller.busyLabel!,
                    ),
                  Focus(
                    focusNode: _overlayFocus,
                    canRequestFocus: false,
                    onFocusChange: (focused) {
                      controller.overlayFocusChanged(
                        overlay,
                        presentationGeneration,
                        focused && _keyboardInput && !_isTv,
                      );
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AnimatedSwitcher(
                          duration: transitionDuration,
                          reverseDuration: transitionDuration,
                          layoutBuilder: (currentChild, previousChildren) =>
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  for (final child in previousChildren)
                                    if (overlay != PlayerOverlay.programInfo)
                                      ExcludeFocus(
                                        child: ExcludeSemantics(
                                          // Dispose tooltip overlays with their retiring
                                          // semantics origin, before further label updates.
                                          child: TooltipVisibility(
                                            visible: false,
                                            child: child,
                                          ),
                                        ),
                                      ),
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
                                childOverlay == PlayerOverlay.subtitleTracks ||
                                childOverlay == PlayerOverlay.programInfo) {
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
                            return SubtitlePanelAnimationRepaint(
                              avoidance: _subtitleAvoidance,
                              animation: fade,
                              child: SlideTransition(
                                position: Tween(
                                  begin: const Offset(0, 1),
                                  end: Offset.zero,
                                ).animate(fade),
                                child: transitioned,
                              ),
                            );
                          },
                          child: _OverlayTextTheme(
                            key: presentationKey,
                            child: switch (overlay) {
                              _ when showsBottomPanel => _Osd(
                                trackDisplays: _trackDisplays,
                                detailsExpanded:
                                    overlay == PlayerOverlay.nowPlaying ||
                                    (trackPopover != null &&
                                        _trackOrigin ==
                                            PlayerOverlay.nowPlaying),
                                trackPopover: trackPopover,
                                controller: controller,
                                subtitleAvoidance: _subtitleAvoidance,
                                subtitleLayerKey: _subtitleLayerKey,
                                openMenu: widget.openMenu,
                                openGuide: widget.openGuide,
                                menuFocus: _menuFocus,
                                sleepFocus: _sleepFocus,
                                pickerAnchors: _pickerAnchors,
                                restoreSleepFocus: _restoreSleepFocus,
                                controls: _controls,
                              ),
                              PlayerOverlay.programInfo =>
                                infoProgram == null
                                    ? const SizedBox.shrink()
                                    : _NowPlayingInfo(
                                        controller: controller,
                                        program: infoProgram,
                                      ),
                              PlayerOverlay.miniGuide => _MiniGuide(
                                controller: controller,
                                active: _appActive,
                                openGuide: widget.openGuide,
                              ),
                              PlayerOverlay.audioTracks => _Tracks(
                                trackDisplays: _trackDisplays,
                                controller: controller,
                                type: PlayerTrackType.audio,
                              ),
                              PlayerOverlay.subtitleTracks => _Tracks(
                                trackDisplays: _trackDisplays,
                                controller: controller,
                                type: PlayerTrackType.subtitle,
                              ),
                              PlayerOverlay.channelNumber => _ChannelNumber(
                                controller: controller,
                              ),
                              PlayerOverlay.error => const SizedBox.shrink(),
                              PlayerOverlay.none ||
                              PlayerOverlay.fullGuide ||
                              PlayerOverlay.osd ||
                              PlayerOverlay.nowPlaying =>
                                const SizedBox.shrink(),
                            },
                          ),
                        ),
                        Positioned(
                          top: insets.top,
                          right: insets.right,
                          child: _AnimatedChannelBug(
                            visible: showChannelTag,
                            suppressed: channelTagSuppressed,
                            interactive: desktop && bottomPanel,
                            duration: _overlayTransitionDuration,
                            child: channel == null
                                ? const SizedBox.shrink()
                                : _OverlayTextTheme(
                                    child: _ChannelBug(
                                      key: const Key('player-osd-channel-bug'),
                                      channel: channel,
                                      controller: controller,
                                      interactive:
                                          desktop &&
                                          bottomPanel &&
                                          showChannelTag,
                                    ),
                                  ),
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
    );
  }
}

class PlayerSurface extends StatelessWidget {
  const PlayerSurface({
    required this.controller,
    this.showErrors = false,
    this.showSubtitles = true,
    this.fullPlayer = false,
    this.subtitleAvoidance,
    this.subtitleLayerKey,
    this.onClose,
    this.onOpenDiagnostics,
    super.key,
  });

  final PlayerCoordinator controller;
  final bool showErrors;
  final bool showSubtitles;
  final bool fullPlayer;
  final SubtitlePanelAvoidance? subtitleAvoidance;
  final GlobalKey? subtitleLayerKey;
  final VoidCallback? onClose;
  final VoidCallback? onOpenDiagnostics;

  @override
  Widget build(BuildContext context) {
    final state = controller.status.state;
    final unsupported = state == PlayerState.unsupported;
    final hasError = controller.error != null;
    final preparing =
        !hasError &&
        (controller.displayHoldActive ||
            state == PlayerState.loading ||
            controller.tuning);
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
      if (unavailable && controller.overlay == PlayerOverlay.miniGuide) {
        return ColoredBox(color: roles.deepBackground);
      }
      return _StoppedSlate(
        controller: controller,
        onClose: onClose,
        onOpenDiagnostics: onOpenDiagnostics,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        if (unsupported)
          ColoredBox(color: roles.deepBackground)
        else
          NativeVideoSurface(player: controller.player),
        if (showSubtitles)
          SubtitleLayer(
            avoidance: fullPlayer ? subtitleAvoidance : null,
            cues: controller.subtitleCues,
            appearance: controller.subtitleAppearance,
            presentationKey: fullPlayer ? subtitleLayerKey : null,
          ),
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

/// The panel and tag share their resting insets, independently of motion.
class _PlayerInsets {
  const _PlayerInsets(this.safe, this.left, this.right, this.top);

  factory _PlayerInsets.of(BuildContext context) {
    final horizontal = (MediaQuery.sizeOf(context).width * 0.05)
        .clamp(24.0, 96.0)
        .toDouble();
    final tv = DeviceProfile.of(context).isTv;
    final safe = tv
        ? LineupCanvas.contentInsets(
            context,
            minimum: EdgeInsets.symmetric(horizontal: horizontal, vertical: 24),
          )
        : EdgeInsets.zero;
    return _PlayerInsets(
      safe,
      tv ? safe.left : horizontal,
      tv ? safe.right : horizontal,
      tv ? safe.top : 24,
    );
  }

  final EdgeInsets safe;
  final double left;
  final double right;
  final double top;
}

class _AnimatedChannelBug extends StatelessWidget {
  const _AnimatedChannelBug({
    required this.visible,
    required this.suppressed,
    required this.interactive,
    required this.duration,
    required this.child,
  });

  final bool visible;
  final bool suppressed;
  final bool interactive;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      ignoring: !interactive || !visible,
      child: ExcludeSemantics(
        excluding: !visible,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: visible ? 1 : 0),
          duration: duration,
          curve: visible ? Curves.easeOut : Curves.easeIn,
          child: child,
          // Suppression replaces the tag immediately (notably the status bug
          // in the same corner). Ordinary dismissal retains its fade and rise.
          builder: (context, value, child) =>
              suppressed || (value == 0 && !visible)
              ? const SizedBox.shrink()
              : Transform.translate(
                  offset: Offset(0, reduceMotion ? 0 : -12 * (1 - value)),
                  child: Opacity(opacity: value, child: child),
                ),
        ),
      ),
    );
  }
}

class _Osd extends StatelessWidget {
  const _Osd({
    required this.trackDisplays,
    required this.controller,
    required this.menuFocus,
    required this.sleepFocus,
    required this.pickerAnchors,
    required this.restoreSleepFocus,
    required this.controls,
    required this.subtitleAvoidance,
    required this.subtitleLayerKey,
    required this.openGuide,
    this.openMenu,
    this.trackPopover,
    this.detailsExpanded = false,
  });
  final bool detailsExpanded;
  final PlayerTrackDisplayCache trackDisplays;
  final PlayerCoordinator controller;
  final LineupMenuCallback? openMenu;
  final VoidCallback openGuide;
  final FocusNode menuFocus;
  final FocusNode sleepFocus;
  final Map<_PlayerControl, _PickerAnchorHandle> pickerAnchors;
  final PlayerTrackType? trackPopover;
  final VoidCallback restoreSleepFocus;
  final Map<_PlayerControl, FocusNode> controls;
  final SubtitlePanelAvoidance subtitleAvoidance;
  final GlobalKey subtitleLayerKey;

  @override
  Widget build(BuildContext context) {
    final displays = trackDisplays.forTracks(controller.tracks);
    final roles = LineupTheme.of(context);
    final size = MediaQuery.sizeOf(context);
    final insets = _PlayerInsets.of(context);
    final safe = insets.safe;
    final leftInset = insets.left;
    final rightInset = insets.right;
    final dvrControlsEnabled = controller.lineup.settings.dvrControlsEnabled;
    final bottomInset = math.max(30.0, safe.bottom);
    final program = controller.currentProgram;
    final audioAvailable = controller.tracks.any(
      (track) => track.type == PlayerTrackType.audio,
    );
    final subtitlesAvailable = controller.tracks.any(
      (track) => track.type == PlayerTrackType.subtitle,
    );
    final unsupported = controller.status.state == PlayerState.unsupported;
    final horizontal = size.width >= 1200 && size.height >= 640;

    final desktop = DeviceProfile.of(context).formFactor == FormFactor.desktop;
    final guideAction = desktop
        ? _osdAction(
            context,
            key: const Key('player-osd-guide'),
            focusNode: controls[_PlayerControl.guide],
            label: 'Guide',
            tooltip: 'Open Guide',
            icon: Icons.grid_view_outlined,
            onPressed: () {
              controller.closeSleepPicker();
              controller.showFullGuide();
              openGuide();
            },
          )
        : null;
    final actionStyle = _playerActionStyle(context);
    final transportActions = <Widget>[
      IconButton(
        focusNode: controls[_PlayerControl.previous],
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
        icon: const Icon(
          Icons.skip_previous,
          semanticLabel: 'Previous channel',
        ),
      ),
      IconButton(
        focusNode: controls[_PlayerControl.playback],
        style: actionStyle,
        tooltip: controller.playbackToggleWillPause ? 'Pause' : 'Play',
        onPressed: unsupported
            ? null
            : () {
                controller.closeSleepPicker();
                unawaited(controller.togglePlayback());
              },
        padding: null,
        iconSize: 36,
        icon: Icon(
          controller.playbackToggleWillPause ? Icons.pause : Icons.play_arrow,
          semanticLabel: controller.playbackToggleWillPause ? 'Pause' : 'Play',
        ),
      ),
      IconButton(
        focusNode: controls[_PlayerControl.next],
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
        icon: const Icon(Icons.skip_next, semanticLabel: 'Next channel'),
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
        : displays.displayFor(selectedAudio);
    final audioLabel = audioDisplay == null || audioDisplay.compactText == null
        ? 'Audio'
        : 'Audio ${audioDisplay.compactText}';
    final audioDescription =
        audioDisplay?.tooltipText ??
        (audioAvailable ? 'Audio tracks' : 'Audio tracks unavailable');
    final subtitlesDisplay = selectedSubtitles == null
        ? null
        : displays.displayFor(selectedSubtitles);
    final subtitlesValue = selectedSubtitles == null
        ? 'Off'
        : subtitlesDisplay?.compactText;
    final subtitlesLabel = ['Subtitles', ?subtitlesValue].join(' ');
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
        : 'Sleep ${remainingMinutes}m';
    final optionActions = <Widget>[
      _PickerAnchor(
        handle: pickerAnchors[_PlayerControl.subtitles]!,
        child: _osdAction(
          context,
          key: const Key('player-osd-subtitles'),
          focusNode: controls[_PlayerControl.subtitles],
          label: 'Subtitles',
          value: subtitlesValue,
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
      ),
      _PickerAnchor(
        handle: pickerAnchors[_PlayerControl.audio]!,
        child: _osdAction(
          context,
          key: const Key('player-osd-audio'),
          focusNode: controls[_PlayerControl.audio],
          label: 'Audio',
          value: audioDisplay?.compactText,
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
      ),
      _PickerAnchor(
        handle: pickerAnchors[_PlayerControl.sleep]!,
        child: _osdAction(
          context,
          key: const Key('player-osd-sleep'),
          label: 'Sleep',
          value: remainingMinutes == null ? null : '${remainingMinutes}m',
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
          builder: (invokerContext) => _osdAction(
            context,
            key: const Key('player-app-menu'),
            focusNode: menuFocus,
            label: 'More',
            tooltip: 'Lineup menu',
            semanticLabel: 'Lineup menu',
            icon: Icons.menu,
            onPressed: () {
              controller.closeSleepPicker();
              openMenu!(invokerContext, menuFocus);
            },
          ),
        ),
      if (!DeviceProfile.of(context).isTv)
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
            semanticLabel: controller.fullscreen
                ? 'Exit full screen'
                : 'Full screen',
          ),
        ),
    ];
    final title = program?.scheduled.item.title ?? 'Nothing playing';
    final logoPath = program == null
        ? null
        : _artworkPath(program.scheduled.item, GuideArtworkKind.clearLogo);
    final item = program?.scheduled.item;
    final primaryTitle = item == null ? title : _programTitle(item);
    final episodeFacts = item == null ? null : _osdEpisodeFacts(item);
    final statusFacts = [
      episodeFacts,
      _statusLabel(controller.presentedState),
    ].nonNulls.toList(growable: false);
    final programIdentity = Column(
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
            logoMaximumSize: Size((size.width >= 1920 ? 520 : 360), 168),
            logoMinimumVisibleSize: Size(96, (size.height >= 900 ? 28 : 24)),
          )
        else
          _OsdTitle(title: primaryTitle),
        if (statusFacts.isNotEmpty) ...[
          SizedBox(height: 8),
          Text(
            statusFacts.join(' · '),
            key: const Key('player-osd-status'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: roles.secondaryText,
              fontSize: 26,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ],
    );
    void openProgramDetails() {
      controller.closeSleepPicker();
      controller.showNowPlaying();
    }

    final identity = KeyedSubtree(
      key: const Key('player-osd-identity'),
      child: desktop && program != null
          ? Semantics(
              container: true,
              explicitChildNodes: true,
              label: 'Show program details',
              button: true,
              onTap: openProgramDetails,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  onTap: openProgramDetails,
                  child: programIdentity,
                ),
              ),
            )
          : programIdentity,
    );
    final osdSecondaryStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: roles.secondaryText,
      fontSize: 18,
      fontWeight: FontWeight.w400,
    );
    final playbackStatus = Text(
      _statusLabel(controller.presentedState) ?? '',
      style: osdSecondaryStyle,
    );
    final progress = _OsdProgress(
      controller: controller,
      detailsExpanded: detailsExpanded,
      part: _OsdProgressPart.timing,
    );
    Widget actionGroup(List<Widget> children) =>
        Row(mainAxisSize: MainAxisSize.min, children: children);
    final availableWidth = size.width - leftInset - rightInset;
    final labelStyle = _osdOptionStyle(context).textStyle?.resolve({});
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
    double labelledActionWidth(String label) => math
        .max(minimumWidth, _textWidth(context, label, labelStyle) + 26 + 8 + 40)
        .ceilToDouble();
    final baselineStandardWidth =
        [
          subtitlesLabel,
          audioLabel,
          sleepLabel,
        ].map(labelledActionWidth).fold(0.0, (total, width) => total + width) +
        (openMenu == null ? 0 : labelledActionWidth('More')) +
        (desktop ? iconActionWidth : 0) +
        6 * (optionActions.length + windowActions.length);
    final transportWidth = dvrControlsEnabled ? 168 : 0;
    final baselineControlsWidth = baselineStandardWidth + transportWidth;
    final wrapActions = baselineControlsWidth > availableWidth * .65;
    final standardWidth =
        baselineStandardWidth + (desktop ? labelledActionWidth('Guide') : 0);
    // The Guide action can wrap within its row. Keep the baseline choice
    // between beside-title and below-title controls.
    final controlsWidth = math.min(
      standardWidth + transportWidth,
      wrapActions ? availableWidth : availableWidth * .65,
    );
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
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ?guideAction,
                      ...optionActions,
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
    final pickerOpen = trackPopover != null;
    Widget bottomPanel({required Widget child}) => IgnorePointer(
      ignoring: pickerOpen,
      child: ExcludeSemantics(
        excluding: pickerOpen,
        child: ExcludeFocus(
          excluding: pickerOpen,
          child: TooltipVisibility(
            visible: !pickerOpen && TooltipVisibility.of(context),
            child: Align(alignment: Alignment.bottomCenter, child: child),
          ),
        ),
      ),
    );

    final panel = bottomPanel(
      child: SafeArea(
        top: false,
        left: !DeviceProfile.of(context).isTv,
        right: !DeviceProfile.of(context).isTv,
        bottom: !DeviceProfile.of(context).isTv,
        child: _BottomPanelExpansion(
          child: SubtitlePanelReporter(
            avoidance: subtitleAvoidance,
            presentationKey: subtitleLayerKey,
            feather: detailsExpanded ? 180 : _OsdPanelMaterial.feather,
            child: CustomPaint(
              painter: _OsdPanelMaterial(
                expanded: detailsExpanded,
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
                  leftInset,
                  detailsExpanded
                      ? 20
                      : horizontal
                      ? (size.height >= 900 ? 44 : 20)
                      : (size.height >= 720 ? 56 : 40),
                  rightInset,
                  bottomInset,
                ),
                child: _consumeOverlayPadding(
                  context,
                  Semantics(
                    container: true,
                    label: 'Playback controls',
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (detailsExpanded) ...[
                          Flexible(
                            fit: FlexFit.loose,
                            child: _NowPlaying(
                              closeFocus: controls[_PlayerControl.close]!,
                              moreInfoFocus: controls[_PlayerControl.moreInfo]!,
                              controller: controller,
                              maxHeight: math.max(
                                80,
                                size.height -
                                    (wrapActions ? 280 : 190) -
                                    (dvrControlsEnabled ? 40 : 0) +
                                    // The additive compact More info action must
                                    // not crop the shelf's four cast/role pairs.
                                    (DeviceProfile.of(context).isTv ? 52 : 0),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (horizontal && !wrapActions)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(child: playbackStatus),
                                const SizedBox(width: 24),
                                groupedActions,
                              ],
                            )
                          else ...[
                            playbackStatus,
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
      ),
    );
    final type = trackPopover;
    final sleepOpen = controller.sleepPickerOpen;
    final anchor = type != null
        ? _trackControl(type)
        : (sleepOpen ? _PlayerControl.sleep : null);
    return Stack(
      fit: StackFit.expand,
      children: [
        _PlayerPickerLayout(
          controller: controller,
          panel: panel,
          anchor: pickerAnchors[anchor],
          preferredWidth: type != null
              ? _trackPopoverWidth(context, controller, displays, type)
              : sleepOpen
              ? _sleepPopoverWidth(context, sleepLabel)
              : 0,
          surfaceKey: Key(
            type == null ? 'sleep-timer-picker' : 'player-track-popover',
          ),
          picker: type != null
              ? _Tracks(
                  type: type,
                  controller: controller,
                  trackDisplays: trackDisplays,
                  inPopover: true,
                )
              : sleepOpen
              ? _SleepTimerPicker(
                  controller: controller,
                  restoreFocus: restoreSleepFocus,
                )
              : null,
        ),
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

enum _OsdProgressPart { timing, line }

class _OsdProgress extends StatelessWidget {
  const _OsdProgress({
    required this.controller,
    required this.detailsExpanded,
    required this.part,
  });
  final PlayerCoordinator controller;
  final bool detailsExpanded;
  final _OsdProgressPart part;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final dvrControlsEnabled = controller.lineup.settings.dvrControlsEnabled;
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
    final progressValue = duration <= 0 ? 0.0 : position.toDouble() / duration;
    final remaining = duration <= 0
        ? null
        : _wholeMinutesLeft(
            displayedPosition,
            Duration(milliseconds: duration),
          );
    final osdSecondaryStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: roles.secondaryText,
      fontSize: 20,
      fontWeight: FontWeight.w400,
    );
    if (part == _OsdProgressPart.timing) {
      return Row(
        key: const Key('player-osd-progress-block'),
        children: [
          Text(
            '${_duration(displayedPosition)} / ${_duration(timingDuration)}',
            key: const Key('player-osd-timing'),
            style: osdSecondaryStyle?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            flex: 3,
            child: _OsdProgress(
              controller: controller,
              detailsExpanded: detailsExpanded,
              part: _OsdProgressPart.line,
            ),
          ),
          if (remaining != null) ...[
            const SizedBox(width: 20),
            Text(
              remaining,
              key: const Key('player-osd-remaining'),
              style: osdSecondaryStyle,
            ),
          ],
          if (next != null) ...[
            const SizedBox(width: 24),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Up next · ${_time(context, next.scheduled.start)} · ${next.scheduled.item.title}',
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
    }
    final sliderInteractive =
        controller.duration > Duration.zero &&
        controller.status.state != PlayerState.unsupported;
    // Keep the transparent seek target on the inset visible lane. Its Overlay
    // gives the full semantics/touch target room beyond the four-pixel track.
    final slider = Overlay.wrap(
      key: ValueKey(sliderInteractive),
      clipBehavior: Clip.none,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 4,
          activeTrackColor: Colors.transparent,
          inactiveTrackColor: Colors.transparent,
          thumbShape: SliderComponentShape.noThumb,
          overlayShape: SliderComponentShape.noOverlay,
        ),
        child: Slider(
          label: 'Playback progress',
          semanticFormatterCallback: DeviceProfile.of(context).isTv
              ? (value) =>
                    '${_duration(Duration(milliseconds: value.round()))} of ${_duration(timingDuration)}'
              : null,
          value: sliderPosition,
          max: sliderMax,
          onChanged: sliderInteractive
              ? (value) =>
                    controller.seekTo(Duration(milliseconds: value.round()))
              : null,
        ),
      ),
    );
    return SizedBox(
      key: const Key('player-osd-progress-line'),
      height: 48,
      child: SizedBox(
        child: Semantics(
          container: true,
          label: dvrControlsEnabled ? null : 'Playback progress',
          value: dvrControlsEnabled
              ? null
              : '${_duration(displayedPosition)} of ${_duration(timingDuration)}',
          child: Stack(
            fit: StackFit.expand,
            children: [
              Align(
                alignment: Alignment.center,
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
                KeyedSubtree(
                  key: DeviceProfile.of(context).isTv
                      ? const Key('player-safe-dvr-target')
                      : null,
                  child: slider,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelBug extends StatefulWidget {
  const _ChannelBug({
    required this.channel,
    required this.controller,
    required this.interactive,
    super.key,
  });

  final Channel channel;
  final PlayerCoordinator controller;
  final bool interactive;
  @override
  State<_ChannelBug> createState() => _ChannelBugState();
}

class _ChannelBugState extends State<_ChannelBug> {
  bool _hovering = false;
  bool _focused = false;

  @override
  void didUpdateWidget(_ChannelBug oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.interactive) {
      _hovering = false;
      _focused = false;
    }
  }

  void _openMiniGuide() {
    widget.controller.closeSleepPicker();
    widget.controller.showMiniGuide();
  }

  void _step({required bool up}) {
    widget.controller.closeSleepPicker();
    unawaited(
      up
          ? widget.controller.previousChannel()
          : widget.controller.nextChannel(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final size = MediaQuery.sizeOf(context);
    final channel = widget.channel;
    final libraryTag = ChannelIdentity.libraryTagFor(
      channel,
      widget.controller.lineup.channels,
    );
    final label = ChannelIdentity.label(channel, libraryTag: libraryTag);
    final interactive = widget.interactive;
    final border = interactive && LineupFocusScope.visible(context, _focused);
    final shape = StadiumBorder(
      side: BorderSide(
        color: border ? roles.focusBorder : roles.subtleBorder,
        width: border ? roles.focusBorderWidth : 1,
      ),
    );
    final labelStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: roles.primaryText,
      fontSize: 22,
      fontWeight: FontWeight.w600,
    );
    const verticalPadding = 10.0;
    final badgeHeight = math.max(
      52.0,
      _textSize(context, channel.name, labelStyle).height + 2 * verticalPadding,
    );
    final identity = Container(
      constraints: BoxConstraints(
        minHeight: badgeHeight,
        maxWidth: size.width * .65,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: verticalPadding,
      ),
      child: ChannelIdentity(
        channel: channel,
        libraryTag: libraryTag,
        showSemantics: false,
        nameStyle: labelStyle,
      ),
    );
    final badge = Semantics(
      container: true,
      button: interactive ? true : null,
      focusable: interactive ? true : null,
      focused: interactive ? _focused : null,
      label: interactive ? '$label. Open Mini Guide' : label,
      onTap: interactive ? _openMiniGuide : null,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _overlayColor(context, widget.controller),
          borderRadius: BorderRadius.circular(999),
          border: Border.fromBorderSide(shape.side),
        ),
        child: interactive
            ? Material(
                type: MaterialType.transparency,
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.enter):
                        _openMiniGuide,
                    const SingleActivator(LogicalKeyboardKey.numpadEnter):
                        _openMiniGuide,
                  },
                  child: InkWell(
                    customBorder: shape,
                    onTap: _openMiniGuide,
                    onFocusChange: (focused) {
                      if (mounted && widget.interactive) {
                        setState(() => _focused = focused);
                      }
                    },
                    hoverColor: Colors.transparent,
                    focusColor: Colors.transparent,
                    child: identity,
                  ),
                ),
              )
            : identity,
      ),
    );
    if (!interactive) return badge;
    final canStep = widget.controller.status.state != PlayerState.unsupported;
    return MouseRegion(
      // Enter can fire when the badge appears beneath a stationary pointer.
      // Wait for actual pointer movement before showing the steppers.
      onHover: (_) {
        if (!_hovering) setState(() => _hovering = true);
      },
      onExit: (_) {
        if (_hovering) setState(() => _hovering = false);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (_hovering && canStep) ...[
            ExcludeFocus(
              child: Material(
                color: _overlayColor(context, widget.controller),
                key: const Key('player-channel-step-pill'),
                shape: const StadiumBorder(),
                child: SizedBox(
                  height: badgeHeight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Channel up',
                        onPressed: () => _step(up: true),
                        icon: const Icon(Icons.keyboard_arrow_up),
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        style: IconButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        constraints: BoxConstraints.tightFor(
                          width: 36,
                          height: badgeHeight,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Channel down',
                        onPressed: () => _step(up: false),
                        icon: const Icon(Icons.keyboard_arrow_down),
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        style: IconButton.styleFrom(
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        constraints: BoxConstraints.tightFor(
                          width: 36,
                          height: badgeHeight,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          badge,
        ],
      ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({
    required this.controller,
    required this.maxHeight,
    required this.closeFocus,
    required this.moreInfoFocus,
  });
  final FocusNode closeFocus;
  final FocusNode moreInfoFocus;

  final PlayerCoordinator controller;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final program = controller.currentProgram;
    if (program == null) return const SizedBox.shrink();
    final item = program.scheduled.item;
    final cast = controller.guide.castFor(program).cast;
    final roles = LineupTheme.of(context);
    final size = MediaQuery.sizeOf(context);
    final dense = size.height < 900;
    final generation = controller.lineup.contentGeneration;
    final artworkIdentity = (program.id, generation);
    final posterPath = _artworkPath(item, GuideArtworkKind.poster);
    final logoPath = _artworkPath(item, GuideArtworkKind.clearLogo);
    final episode = _episodeLabel(item);
    final (:editorial, :badges) = _nowPlayingFacts(controller, program);
    final castFacts = cast
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
    const posterWidth = 248.0;

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
                  focusNode: closeFocus,
                  style: _playerActionStyle(context).copyWith(
                    padding: const WidgetStatePropertyAll(
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
                      ExcludeSemantics(
                        child: SizedBox(
                          key: const Key('player-now-playing-poster'),
                          width: posterWidth,
                          height: math.min(posterWidth * 1.5, maxHeight - 64),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: posterPath == null
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
                          ),
                        ),
                      ),
                      SizedBox(width: dense ? 24 : 32),
                    ],
                    Expanded(
                      child: SingleChildScrollView(
                        key: const Key('player-now-playing-details'),
                        primary: false,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final summaryStyle = Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(
                                  color: roles.primaryText,
                                  fontSize: 21,
                                  height: 1.45,
                                );
                            final summary = item.summary;
                            var summaryClamped = false;
                            if (DeviceProfile.of(context).isTv &&
                                summary != null) {
                              final painter =
                                  TextPainter(
                                    text: TextSpan(
                                      text: summary,
                                      style: summaryStyle,
                                    ),
                                    textDirection: Directionality.of(context),
                                    textScaler: MediaQuery.textScalerOf(
                                      context,
                                    ),
                                    locale: Localizations.maybeLocaleOf(
                                      context,
                                    ),
                                    maxLines: 3,
                                  )..layout(
                                    maxWidth: math.min(
                                      1040,
                                      constraints.maxWidth,
                                    ),
                                  );
                              summaryClamped = painter.didExceedMaxLines;
                              painter.dispose();
                            }
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // The summary owns these visual facts. Keep the cast
                                // tooltip origins outside any semantics exclusion.
                                ExcludeSemantics(
                                  child:
                                      controller
                                              .lineup
                                              .settings
                                              .preferClearLogos &&
                                          logoPath != null
                                      ? _NowPlayingIdentity(
                                          key: ValueKey((
                                            artworkIdentity,
                                            GuideArtworkKind.clearLogo,
                                            logoPath,
                                          )),
                                          controller: controller,
                                          program: program,
                                          compact: dense,
                                        )
                                      : _NowPlayingTitle(
                                          item: item,
                                          compact: dense,
                                        ),
                                ),
                                if (editorial.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  ExcludeSemantics(
                                    child: Text(
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
                                  ),
                                ],
                                if (badges.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  ExcludeSemantics(
                                    child: Wrap(
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
                                  ),
                                ],
                                if (item.summary case final summary?) ...[
                                  const SizedBox(height: 12),
                                  ExcludeSemantics(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 1040,
                                      ),
                                      child: Text(
                                        summary,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        key: const Key(
                                          'player-now-playing-summary',
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyLarge
                                            ?.copyWith(
                                              color: roles.primaryText,
                                              fontSize: 21,
                                              height: 1.45,
                                            ),
                                      ),
                                    ),
                                  ),
                                ],
                                if (DeviceProfile.of(context).isTv &&
                                    (summaryClamped || cast.length > 4)) ...[
                                  const SizedBox(height: 8),
                                  TextButton(
                                    key: const Key('player-more-info'),
                                    focusNode: moreInfoFocus,
                                    style: LineupTheme.buttonStyle(
                                      roles,
                                      LineupButtonTier.text,
                                      compact: true,
                                      focusVisible: LineupFocusScope.visible(
                                        context,
                                      ),
                                    ),
                                    onPressed: controller.showProgramInfo,
                                    child: const Text('More info'),
                                  ),
                                ],
                                if (cast.isNotEmpty) ...[
                                  const SizedBox(height: 14),
                                  _NowPlayingCast(
                                    controller: controller,
                                    cast: cast,
                                    dense: dense,
                                  ),
                                ],
                              ],
                            );
                          },
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

({String editorial, List<String> badges}) _nowPlayingFacts(
  PlayerCoordinator controller,
  GuideProgram program,
) {
  final item = program.scheduled.item;
  final duration = controller.duration > Duration.zero
      ? controller.duration
      : program.scheduled.end.difference(program.scheduled.start);
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
  final badges = mediaBadges(
    item,
    surface: MediaBadgeSurface.nowPlaying,
    runtimeHdr: controller.telemetry.isHdr,
    effectiveVideoCodec: videoCodec,
  );
  return (editorial: editorial, badges: badges);
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
      final useFilmLogoAsTitle =
          item.mediaKind == ChannelMediaKind.movie &&
          _programTitle(item) == item.title;
      final title = Text(
        item.title,
        key: const Key('player-now-playing-title'),
        maxLines: widget.compact ? 1 : 2,
        overflow: TextOverflow.ellipsis,
        style: _nowPlayingTitleStyle(context, dense: widget.compact),
      );
      const logoMaxHeight = 110.0;
      const logoMaxWidth = logoMaxHeight * 6;
      return LayoutBuilder(
        builder: (context, available) {
          Widget clearLogo(Uint8List bytes, Widget fallback) => ClearLogoImage(
            bytes,
            imageKey: const Key('player-now-playing-logo'),
            maximumVisibleHeight: 110,
            excludeFromSemantics: true,
            maximumSize: const Size(logoMaxWidth, logoMaxHeight),
            minimumVisibleSize: Size(96, widget.compact ? 20 : 28),
            fallback: fallback,
          );
          final titleGap = widget.compact ? 8.0 : 12.0;
          if (bytes != null && useFilmLogoAsTitle) {
            // Cap the art, while giving an artwork fallback the full text slot.
            return clearLogo(
              bytes,
              Padding(
                padding: EdgeInsets.only(top: titleGap),
                child: title,
              ),
            );
          }
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
                  child: clearLogo(bytes, logoFallback),
                ),
              SizedBox(height: titleGap),
              title,
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
      fontSize: 40,
      color: LineupTheme.of(context).primaryText,
      shadows: _overlayTextShadow,
    );

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
        : LayoutBuilder(
            builder: (context, slot) => Image(
              // Decode covering the painted slot, not the original artwork.
              image: fit == BoxFit.cover
                  ? CoverResizeImage.forSlot(context, snapshot.data!, slot)
                  : MemoryImage(snapshot.data!),
              key: imageKey,
              fit: fit,
              gaplessPlayback: false,
              semanticLabel: semanticLabel,
              excludeFromSemantics: semanticLabel == null,
              frameBuilder: (context, child, frame, synchronous) =>
                  synchronous || frame != null ? child : fallback,
              errorBuilder: (_, _, _) => fallback,
            ),
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
            fontSize: Theme.of(context).textTheme.labelMedium?.fontSize ?? 12,
          ),
        ),
      ),
    );
  }
}

double _textWidth(BuildContext context, String text, TextStyle? style) =>
    _textSize(context, text, style).width;

Size _textSize(BuildContext context, String text, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
    maxLines: 1,
  )..layout();
  final size = painter.size;
  painter.dispose();
  return size;
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
    const diameter = 56.0;
    const gap = 24.0;
    final nameStyle = _nowPlayingSecondaryStyle(
      context,
      dense: dense,
    )?.copyWith(fontSize: 20, height: 1.3, color: roles.primaryText);
    final roleStyle = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: roles.secondaryText, fontSize: 18);
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
    )?.copyWith(fontSize: 20, height: 1.3, color: roles.primaryText);
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
        ExcludeSemantics(
          child: SizedBox.square(
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
        ),
        SizedBox(height: 6),
        SizedBox(
          width: width,
          child: Tooltip(
            message: member.name,
            excludeFromSemantics: true,
            child: ExcludeSemantics(
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
        ),
        if (member.role case final role? when role.trim().isNotEmpty) ...[
          const SizedBox(height: 3),
          SizedBox(
            width: width,
            child: Tooltip(
              message: role,
              excludeFromSemantics: true,
              child: ExcludeSemantics(
                child: Text(
                  role,
                  key: ValueKey('player-now-playing-cast-role-$index'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: roles.secondaryText, fontSize: 18),
                ),
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
    final isTv = DeviceProfile.of(context).isTv;
    final horizontal =
        size.height >= 720 && !LineupLayout.isCompactWidth(size.width);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final layoutTextScale = textScale < 1 ? 1.0 : textScale;
    final large = horizontal && size.width >= 1920 && size.height >= 1080;
    final rowHeight = horizontal ? 84.0 * layoutTextScale : null;
    final channelColumnWidth = (large ? 365.0 : 250.0);
    final columnGap = (large ? 36.0 : 24.0);
    final contentInset = (horizontal
        ? (large ? 48.0 : 32.0)
        : roles.overlaySafeArea);
    final contentPadding = isTv
        ? LineupCanvas.contentInsets(
            context,
            minimum: EdgeInsets.fromLTRB(contentInset, 12, contentInset, 16),
          )
        : EdgeInsets.fromLTRB(contentInset, 12, contentInset, 16);
    final rowInset = (large ? 18.0 : 12.0);
    const fadeTail = 55.0;
    final theme = Theme.of(context);
    // Keep one aligned number column for the five built rows. The reference
    // floor grows with platform text, and actual glyphs may require more room.
    final numberStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w500,
    );
    final numberColumnWidth = channels.fold<double>(
      46 * math.max(1, textScale),
      (width, channel) => math.max(
        width,
        _textWidth(context, '${channel.number}', numberStyle).ceilToDouble() +
            1,
      ),
    );
    final actionLabelStyle = LineupTypography.tvLabelStyle(context);
    return DefaultTextStyle(
      style: theme.textTheme.bodyMedium!,
      child: Builder(
        builder: (context) => Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            top: !isTv,
            left: !isTv,
            right: !isTv,
            bottom: false,
            child: CustomPaint(
              painter: _MiniGuideFadePainter(
                scrim: _overlayColor(context, controller),
                lighter:
                    controller.lineup.settings.overlayTransparency ==
                    OverlayTransparency.moreTransparent,
                tailHeight: fadeTail,
                footerExtent: 8 + 48 + contentPadding.bottom,
              ),
              child: Container(
                key: const Key('mini-guide-shelf'),
                width: double.infinity,
                constraints: BoxConstraints(maxHeight: size.height),
                padding: contentPadding,
                child: _consumeOverlayPadding(
                  context,
                  Semantics(
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
                                        fontSize: isTv
                                            ? LineupTypography.tvTextFloor
                                            : 18,
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
                                          Text(
                                            'Full Guide',
                                            style: actionLabelStyle,
                                          ),
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
                                          Text(
                                            'Close',
                                            style: actionLabelStyle,
                                          ),
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
                                numberColumnWidth: numberColumnWidth,
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
                                      icon: Icon(
                                        Icons.arrow_upward,
                                        size: 24,
                                        semanticLabel: 'Previous channel',
                                      ),
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
                                      icon: Icon(
                                        Icons.arrow_downward,
                                        size: 24,
                                        semanticLabel: 'Next channel',
                                      ),
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
    required this.numberColumnWidth,
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
  final double numberColumnWidth;
  final double columnGap;
  final bool active;
  final bool large;
  final double rowInset;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final focused = channel.id == controller.miniGuideChannelId;
    final tuned = channel.id == controller.watchingChannelId;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LineupRowSurface(
          selected: tuned || (focused && !LineupFocusScope.visible(context)),
          focused: focused,
          child: Builder(
            builder: (context) {
              final roles = LineupTheme.of(context);
              final foreground = roles.primaryText;
              final filledFocus =
                  DeviceProfile.of(context).isTv &&
                  roles.focusTreatment == LineupFocusTreatment.fill &&
                  LineupFocusScope.visible(context, focused);
              final unsupported =
                  controller.status.state == PlayerState.unsupported;
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
              final titleStyle = Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(
                    color: foreground,
                    shadows: filledFocus ? const [] : null,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  );
              final metadataStyle = Theme.of(context).textTheme.bodySmall
                  ?.copyWith(
                    color: roles.secondaryText,
                    fontSize: 18,
                    shadows: filledFocus ? const [] : null,
                  );
              final nextTitleStyle = titleStyle?.copyWith(
                color: roles.secondaryText,
                fontWeight: FontWeight.w400,
              );
              Widget ticker(String text, Key key, {TextStyle? style}) =>
                  FocusedTicker(
                    key: key,
                    text: text,
                    focused: focused,
                    active: active,
                    reduceMotion: MediaQuery.disableAnimationsOf(context),
                    style: style,
                  );
              final libraryTag = ChannelIdentity.libraryTagFor(
                channel,
                controller.lineup.channels,
              );
              final identityLabel = ChannelIdentity.label(
                channel,
                libraryTag: libraryTag,
              );
              final channelIdentity = ChannelIdentity(
                channel: channel,
                libraryTag: libraryTag,
                nameStyle: titleStyle,
                numberWidth: numberColumnWidth,
                numberAlignment: TextAlign.end,
                supportStyle: metadataStyle,
                showSemantics: false,
                allowTagBelow: false,
                tickerBuilder: (style) {
                  final key = Key('mini-guide-channel-${channel.id}');
                  if (focused &&
                      active &&
                      !MediaQuery.disableAnimationsOf(context)) {
                    return ticker(channel.name, key, style: style);
                  }
                  return Text(
                    channel.name,
                    key: key,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: style,
                  );
                },
              );
              final inlineIdentity = Row(
                children: [
                  Flexible(child: channelIdentity),
                  if (tuned) ...[
                    const SizedBox(width: 8),
                    Text('Watching', style: metadataStyle),
                  ],
                ],
              );
              final row = controller.guide.row(channel.id);
              final unavailable = row.state == GuideLoadState.error;
              final currentText = unavailable
                  ? 'Schedule unavailable'
                  : current == null
                  ? 'Loading schedule…'
                  : _programTitle(current.scheduled.item);
              final currentSupport = current == null
                  ? null
                  : _miniGuideProgramSupport(context, current);
              final nextText = next == null
                  ? null
                  : _programTitle(next.scheduled.item);
              final nextSupport = next == null
                  ? null
                  : _miniGuideProgramSupport(context, next, upcoming: true);
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
                  if (currentSupport != null)
                    Text(
                      currentSupport,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: metadataStyle,
                    ),
                  if (current != null) ...[
                    SizedBox(height: 3),
                    LinearProgressIndicator(
                      value: progress.clamp(0, 1),
                      minHeight: 2,
                      color: roles.progressFill,
                      backgroundColor: roles.progressTrack.withValues(
                        alpha: 0.72,
                      ),
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
                          nextText!,
                          Key('mini-guide-next-${channel.id}'),
                          style: nextTitleStyle,
                        ),
                        Text(
                          nextSupport!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: metadataStyle,
                        ),
                      ],
                    );
              final semantics = [
                identityLabel,
                'Now $currentText',
                if (current?.scheduled.item.showTitle?.trim().isNotEmpty ==
                    true)
                  ?currentSupport,
                if (nextText != null) 'Next $nextText',
                if (next?.scheduled.item.showTitle?.trim().isNotEmpty == true)
                  ?nextSupport,
                if (tuned) 'Now watching',
              ].join('. ');
              return Semantics(
                key: Key('mini-guide-row-${channel.id}'),
                selected: focused,
                label: '$semantics.',
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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  inlineIdentity,
                                  Padding(
                                    padding: EdgeInsetsDirectional.only(
                                      start: channelIdentity.nameIndent(
                                        context,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [currentCell, ?nextTitle],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : SizedBox(
                              height: rowHeight,
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: rowInset,
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: channelColumnWidth,
                                      child: inlineIdentity,
                                    ),
                                    SizedBox(width: columnGap),
                                    Expanded(flex: 115, child: currentCell),
                                    SizedBox(width: columnGap),
                                    Expanded(
                                      flex: 100,
                                      child:
                                          nextTitle ?? const SizedBox.shrink(),
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
    required this.footerExtent,
  });

  final double footerExtent;
  final Color scrim;
  final double tailHeight;
  final bool lighter;

  @override
  void paint(Canvas canvas, Size size) {
    final fadeStart = math.max(0.0, size.height - footerExtent + 24);
    final content = Rect.fromLTWH(0, 0, size.width, fadeStart);
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
    final tail = Rect.fromLTWH(0, fadeStart, size.width, tailHeight);
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
      tailHeight != oldDelegate.tailHeight ||
      footerExtent != oldDelegate.footerExtent;
}

// Lay out the OSD first so the picker can use the actual button bounds on
// this frame. A paint-time follower cannot host Flutter's track tooltips,
// which need their anchor's position during layout.
class _PlayerPickerLayout extends StatelessWidget {
  const _PlayerPickerLayout({
    required this.controller,
    required this.panel,
    required this.anchor,
    required this.preferredWidth,
    required this.surfaceKey,
    required this.picker,
  });

  final PlayerCoordinator controller;
  final Widget panel;
  final _PickerAnchorHandle? anchor;
  final double preferredWidth;
  final Key surfaceKey;
  final Widget? picker;

  @override
  Widget build(BuildContext context) => CustomMultiChildLayout(
    delegate: _PlayerPickerPlacement(
      anchor: anchor,
      preferredWidth: preferredWidth,
      insets: DeviceProfile.of(context).isTv
          ? LineupCanvas.contentInsets(context)
          : MediaQuery.paddingOf(context),
    ),
    children: [
      LayoutId(id: _PickerSlot.panel, child: panel),
      if (picker case final picker?)
        LayoutId(
          id: _PickerSlot.popover,
          child: Material(
            key: surfaceKey,
            color: _overlayColor(context, controller),
            borderRadius: const BorderRadius.all(Radius.circular(8)),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: picker,
            ),
          ),
        ),
    ],
  );
}

class _PickerAnchorHandle {
  _RenderPickerAnchor? attachedBox;
}

class _PickerAnchor extends SingleChildRenderObjectWidget {
  const _PickerAnchor({required this.handle, required super.child});

  final _PickerAnchorHandle handle;

  @override
  _RenderPickerAnchor createRenderObject(BuildContext context) =>
      _RenderPickerAnchor(handle);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPickerAnchor renderObject,
  ) {
    renderObject.handle = handle;
  }
}

class _RenderPickerAnchor extends RenderProxyBox {
  _RenderPickerAnchor(this._handle);

  _PickerAnchorHandle _handle;
  set handle(_PickerAnchorHandle value) {
    if (identical(_handle, value)) return;
    _clearAnchor();
    _handle = value;
    if (attached) _handle.attachedBox = this;
  }

  // Layout reads the attached render anchor directly. An outgoing animated
  // panel can retain an inactive widget context until its last frame.
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _handle.attachedBox = this;
  }

  @override
  void detach() {
    _clearAnchor();
    super.detach();
  }

  void _clearAnchor() {
    if (identical(_handle.attachedBox, this)) _handle.attachedBox = null;
  }

  // RenderBox.size only permits a layout read by the direct parent.
  var laidOutSize = Size.zero;

  @override
  void performLayout() {
    super.performLayout();
    laidOutSize = size;
  }
}

enum _PickerSlot { panel, popover }

class _PlayerPickerPlacement extends MultiChildLayoutDelegate {
  _PlayerPickerPlacement({
    required this.anchor,
    required this.insets,
    required this.preferredWidth,
  });

  final _PickerAnchorHandle? anchor;
  final EdgeInsets insets;
  final double preferredWidth;

  @override
  void performLayout(Size size) {
    layoutChild(_PickerSlot.panel, BoxConstraints.tight(size));
    positionChild(_PickerSlot.panel, Offset.zero);
    if (!hasChild(_PickerSlot.popover)) return;

    final target = anchor?.attachedBox;
    final parent = _layoutParent(target);
    final rect = target != null && parent != null
        ? MatrixUtils.transformRect(
            target.getTransformTo(parent),
            Offset.zero & target.laidOutSize,
          )
        : Rect.fromLTWH(
            size.width - insets.right,
            size.height - insets.bottom,
            0,
            0,
          );
    const gap = 8.0;
    final width = math.min(
      preferredWidth,
      math.max(0.0, size.width - insets.horizontal),
    );
    final right = rect.right.clamp(
      insets.left + width,
      math.max(insets.left + width, size.width - insets.right),
    );
    final bottom = math.max(insets.top, rect.top - gap);
    final popover = layoutChild(
      _PickerSlot.popover,
      BoxConstraints.tightFor(width: width)
          .copyWith(maxHeight: bottom - insets.top),
    );
    positionChild(
      _PickerSlot.popover,
      Offset(right - popover.width, bottom - popover.height),
    );
  }

  RenderCustomMultiChildLayoutBox? _layoutParent(RenderObject? target) {
    RenderObject? node = target;
    while (node != null) {
      if (node is RenderCustomMultiChildLayoutBox &&
          identical(node.delegate, this)) {
        return node;
      }
      node = node.parent;
    }
    return null;
  }

  @override
  bool shouldRelayout(_PlayerPickerPlacement oldDelegate) => true;
}

const _pickerPadding = 12.0;
const _trackRowPadding = 12.0;
const _trackTrailingWidth = 30.0;

double _popoverWidth(BuildContext context, double contentWidth) {
  final maxWidth = DeviceProfile.of(context).isTv
      ? 720.0
      : MediaQuery.sizeOf(context).width * .40;
  return math.min(maxWidth, math.max(354.0, contentWidth));
}

double _trackPopoverWidth(
  BuildContext context,
  PlayerCoordinator controller,
  PlayerTrackDisplayProjection displays,
  PlayerTrackType type,
) {
  final theme = Theme.of(context).textTheme;
  final titleStyle = theme.bodyLarge?.copyWith(
    fontSize: 23,
    fontWeight: FontWeight.w600,
  );
  // Keep the same horizontal padding and leading reserve as the track tiles,
  // including room for the trailing selection glyph and its title gap.
  const rowExtras =
      2 * (_pickerPadding + _trackRowPadding) + _trackTrailingWidth + 22;
  var width =
      _textWidth(
        context,
        type == PlayerTrackType.audio ? 'Audio' : 'Subtitles',
        theme.titleLarge?.copyWith(fontSize: 26),
      ) +
      _sleepCloseWidth(context) +
      2 * _pickerPadding;
  for (final track in controller.tracks) {
    if (track.type != type) continue;
    final display = displays.displayFor(track);
    width = math.max(
      width,
      math.max(
            _textWidth(context, display.primaryText, titleStyle),
            _textWidth(
              context,
              displays.pickerSecondaryFactsFor(track).join(' · '),
              theme.bodyMedium?.copyWith(fontSize: 19),
            ),
          ) +
          rowExtras,
    );
  }
  return _popoverWidth(context, width.ceilToDouble());
}

const _sleepChoices = <(String, Duration?)>[
  ('Off', null),
  ('30 minutes', Duration(minutes: 30)),
  ('1 hour', Duration(hours: 1)),
  ('90 minutes', Duration(minutes: 90)),
];

const _sleepPickerTitle = 'Sleep timer';
const _sleepTilePadding = 16.0;
const _sleepTileTitleGap = 16.0;
const _sleepSelectionSize = 20.0;

TextStyle? _sleepTileTextStyle(BuildContext context) =>
    (ListTileTheme.of(context).titleTextStyle ??
            Theme.of(context).textTheme.bodyLarge)
        ?.copyWith(fontSize: 23, fontWeight: FontWeight.w600);

TextButton _sleepCloseButton(VoidCallback onPressed) =>
    TextButton(onPressed: onPressed, child: const _OverlayCloseLabel());

double _sleepCloseWidth(BuildContext context) {
  final button = _sleepCloseButton(() {});
  final themeStyle = button.themeStyleOf(context);
  final defaultStyle = button.defaultStyleOf(context);
  // Match ButtonStyleButton's precedence for an enabled, resting Close button.
  T? resolveStyle<T>(T? Function(ButtonStyle style) value) =>
      (button.style == null ? null : value(button.style!)) ??
      (themeStyle == null ? null : value(themeStyle)) ??
      value(defaultStyle);
  T? resolve<T>(
    WidgetStateProperty<T?>? Function(ButtonStyle style) property,
  ) => resolveStyle((style) => property(style)?.resolve({}));

  final density = resolveStyle((style) => style.visualDensity)!;
  final dx = density.baseSizeAdjustment.dx;
  final padding = resolve((style) => style.padding)!.horizontal;
  final constraints = density.effectiveConstraints(
    BoxConstraints(
      minWidth: resolve((style) => style.minimumSize)!.width,
      maxWidth: resolve((style) => style.maximumSize)!.width,
    ),
  );
  final contentWidth =
      _textWidth(
        context,
        _OverlayCloseLabel.label,
        resolve((style) => style.textStyle),
      ) +
      _OverlayCloseLabel.gap +
      _OverlayCloseLabel.iconSize +
      padding +
      2 * math.max(0, dx);
  final fixedWidth = resolve((style) => style.fixedSize)?.width;
  final buttonWidth = constraints.constrainWidth(
    fixedWidth != null && fixedWidth.isFinite ? fixedWidth : contentWidth,
  );
  return resolveStyle((style) => style.tapTargetSize) ==
          MaterialTapTargetSize.padded
      ? math.max(buttonWidth, kMinInteractiveDimension + dx)
      : buttonWidth;
}

double _sleepPopoverWidth(BuildContext context, String state) {
  final theme = Theme.of(context);
  var width = math.max(
    _textWidth(context, state, theme.textTheme.bodySmall),
    _textWidth(
          context,
          _sleepPickerTitle,
          theme.textTheme.titleLarge?.copyWith(fontSize: 26),
        ) +
        _sleepCloseWidth(context),
  );
  final tileStyle = _sleepTileTextStyle(context);
  for (final (label, _) in _sleepChoices) {
    width = math.max(
      width,
      _textWidth(context, label, tileStyle) +
          2 * _sleepTilePadding +
          _sleepTileTitleGap +
          _sleepSelectionSize,
    );
  }
  return _popoverWidth(context, (width + 2 * _pickerPadding).ceilToDouble());
}

/// Flutter can break an overwide word in the middle. Ellipsize just that word
/// and let the surrounding words wrap at the normal boundaries.
Widget _pickerChoiceText(String label, TextStyle? style) => LayoutBuilder(
  builder: (context, constraints) {
    String fitWord(String word) {
      if (_textWidth(context, word, style) <= constraints.maxWidth) return word;
      final units = word.characters;
      var lower = 0;
      var upper = units.length;
      while (lower < upper) {
        final middle = (lower + upper + 1) ~/ 2;
        if (_textWidth(context, '${units.take(middle)}…', style) <=
            constraints.maxWidth) {
          lower = middle;
        } else {
          upper = middle - 1;
        }
      }
      return '${units.take(lower)}…';
    }

    final fitted = _textWidth(context, label, style) <= constraints.maxWidth
        ? label
        : label.split(' ').map(fitWord).join(' ');
    return Text(
      fitted,
      style: style,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  },
);

class _SleepTimerPicker extends StatelessWidget {
  const _SleepTimerPicker({
    required this.controller,
    required this.restoreFocus,
  });

  final PlayerCoordinator controller;
  final VoidCallback restoreFocus;

  void _choose(Duration? duration) {
    controller.setSleepTimer(duration);
    restoreFocus();
  }

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final supportingText = Color.lerp(
      roles.secondaryText,
      roles.primaryText,
      0.65,
    )!;
    final theme = Theme.of(context);
    final selected = controller.sleepDuration;
    final remaining = controller.sleepRemaining;
    // A newly opened TV picker must take focus from its invoking action.
    // Its selected preset can autofocus within this fresh scope; without it,
    // the already-focused OSD scope keeps the arrow keys on the action row.
    Widget pickerFocus(Widget child) => DeviceProfile.of(context).isTv
        ? FocusScope(autofocus: true, child: child)
        : child;
    return pickerFocus(
      FocusTraversalGroup(
        child: Shortcuts(
          shortcuts: <ShortcutActivator, Intent>{
            const SingleActivator(LogicalKeyboardKey.arrowUp):
                const DirectionalFocusIntent(TraversalDirection.up),
            const SingleActivator(LogicalKeyboardKey.arrowDown):
                const DirectionalFocusIntent(TraversalDirection.down),
            const SingleActivator(LogicalKeyboardKey.enter):
                const ActivateIntent(),
            const SingleActivator(LogicalKeyboardKey.numpadEnter):
                const ActivateIntent(),
            const SingleActivator(LogicalKeyboardKey.space):
                const ActivateIntent(),
            const SingleActivator(LogicalKeyboardKey.select):
                const ActivateIntent(),
            const SingleActivator(LogicalKeyboardKey.mediaPlayPause):
                const ActivateIntent(),
          },
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(_pickerPadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _sleepPickerTitle,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 26,
                          ),
                        ),
                      ),
                      _sleepCloseButton(() {
                        controller.closeOverlay();
                        restoreFocus();
                      }),
                    ],
                  ),
                  if (remaining != null)
                    Text(
                      'Sleep · ${(remaining.inSeconds / 60).ceil()}m',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: supportingText,
                        fontSize: 19,
                      ),
                    ),
                  for (final choice in _sleepChoices)
                    LineupRowSurface(
                      selected: choice.$2 == selected,
                      child: ListTile(
                        key: Key(
                          'sleep-timer-${choice.$2?.inMinutes ?? 'off'}',
                        ),
                        minTileHeight: 44,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: _sleepTilePadding,
                        ),
                        horizontalTitleGap: _sleepTileTitleGap,
                        titleTextStyle: _sleepTileTextStyle(context),
                        autofocus: choice.$2 == selected,
                        title: Text(choice.$1),
                        trailing: choice.$2 == selected
                            ? Icon(
                                Icons.check,
                                color: roles.progressFill,
                                size: _sleepSelectionSize,
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
    );
  }
}

class _Tracks extends StatefulWidget {
  const _Tracks({
    required this.controller,
    required this.type,
    required this.trackDisplays,
    this.inPopover = false,
  });
  final PlayerTrackDisplayCache trackDisplays;
  final PlayerCoordinator controller;
  final PlayerTrackType type;
  final bool inPopover;

  @override
  State<_Tracks> createState() => _TracksState();
}

class _TracksState extends State<_Tracks> {
  final _focusScope = FocusScopeNode(debugLabel: 'Track reader');
  final _closeFocus = FocusNode(debugLabel: 'Track reader Close');
  final _scrollController = ScrollController();
  final _selectedRowKey = GlobalKey();
  late final int? _initialSelectedTrackId;

  @override
  void initState() {
    super.initState();
    _focusScope.addListener(_restoreRetiredTrackFocus);
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

  void _restoreRetiredTrackFocus() {
    if (!_focusScope.hasPrimaryFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The menu returns through scope history. If native tracks retired its
      // last row, give the still-open reader a stable, actionable fallback.
      if (mounted &&
          _focusScope.hasPrimaryFocus &&
          _closeFocus.canRequestFocus) {
        _closeFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusScope.dispose();
    _closeFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displays = widget.trackDisplays.forTracks(widget.controller.tracks);
    final tracks = widget.controller.tracks
        .where((track) => track.type == widget.type)
        .toList();
    final roles = LineupTheme.of(context);
    final fillFocus = roles.focusTreatment == LineupFocusTreatment.fill;
    final selectedTrack = tracks.where((track) => track.selected).firstOrNull;
    final textTheme = Theme.of(context).textTheme;
    Widget present(Widget child) {
      if (widget.inPopover) {
        return FocusScope(
          node: _focusScope,
          autofocus: true,
          child: Padding(
            padding: const EdgeInsets.all(_pickerPadding),
            child: child,
          ),
        );
      }
      return _PlaybackDrawer(
        controller: widget.controller,
        focusScope: _focusScope,
        child: child,
      );
    }

    return present(
      Column(
        mainAxisSize: widget.inPopover ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.type == PlayerTrackType.audio ? 'Audio' : 'Subtitles',
                  style: widget.inPopover
                      ? textTheme.titleLarge?.copyWith(fontSize: 26)
                      : textTheme.headlineSmall?.copyWith(fontSize: 36),
                ),
              ),
              TextButton(
                focusNode: _closeFocus,
                autofocus:
                    tracks.isEmpty && widget.type != PlayerTrackType.subtitle,
                onPressed: widget.controller.closeOverlay,
                child: const _OverlayCloseLabel(),
              ),
            ],
          ),
          SizedBox(height: widget.inPopover ? 8 : 36),
          if (tracks.isEmpty && widget.type == PlayerTrackType.subtitle)
            Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                widget.controller.tuning ||
                        widget.controller.status.state == PlayerState.loading
                    ? 'Loading tracks…'
                    : 'No subtitle tracks available',
                style: textTheme.bodyMedium,
              ),
            ),
          Flexible(
            fit: widget.inPopover ? FlexFit.loose : FlexFit.tight,
            child: _TrackListFade(
              child: tracks.isEmpty && widget.type == PlayerTrackType.audio
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
                  : SingleChildScrollView(
                      key: const Key('playback-options-list'),
                      controller: _scrollController,
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index <
                                tracks.length +
                                    (widget.type == PlayerTrackType.subtitle
                                        ? 1
                                        : 0);
                            index++
                          ) ...[
                            if (index > 0)
                              Divider(
                                height: 1,
                                color: roles.subtleBorder.withValues(
                                  alpha: 0.45,
                                ),
                              ),
                            Builder(
                              builder: (context) {
                                final off =
                                    widget.type == PlayerTrackType.subtitle &&
                                    index == 0;
                                final track = off
                                    ? null
                                    : tracks[index -
                                          (widget.type ==
                                                  PlayerTrackType.subtitle
                                              ? 1
                                              : 0)];
                                final selected = off
                                    ? selectedTrack == null
                                    : track!.selected;
                                final display = track == null
                                    ? null
                                    : displays.displayFor(track);
                                final title = off
                                    ? 'Off'
                                    : display!.primaryText;
                                final metadata = track == null
                                    ? const <String>[]
                                    : displays.pickerSecondaryFactsFor(track);
                                final metadataText = metadata.join(' · ');

                                final tooltip = display?.tooltipText ?? title;
                                final pending =
                                    widget.controller.pendingTrackType ==
                                        widget.type &&
                                    widget.controller.pendingTrackId ==
                                        track?.id;
                                final semanticLabel = track == null
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

                                Widget choiceText(
                                  String text,
                                  TextStyle? style,
                                ) => widget.inPopover
                                    ? _pickerChoiceText(text, style)
                                    : Text(
                                        text,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: style,
                                      );

                                Widget choiceLabel(
                                  String text,
                                  TextStyle? Function(LineupThemeRoles) style,
                                ) => fillFocus
                                    ? Builder(
                                        builder: (context) => choiceText(
                                          text,
                                          style(LineupTheme.of(context)),
                                        ),
                                      )
                                    : choiceText(text, style(roles));

                                final titleWidget = choiceLabel(
                                  title,
                                  (roles) => textTheme.bodyLarge?.copyWith(
                                    color: roles.primaryText,
                                    fontSize: 23,
                                    fontWeight: FontWeight.w600,
                                  ),
                                );
                                final subtitleWidget = metadata.isEmpty
                                    ? null
                                    : choiceLabel(
                                        metadataText,
                                        (roles) =>
                                            textTheme.bodyMedium?.copyWith(
                                              color: roles.secondaryText,
                                              fontSize: 19,
                                            ),
                                      );
                                final Widget trailingWidget = fillFocus
                                    ? Builder(
                                        builder: (context) {
                                          final rowRoles = LineupTheme.of(
                                            context,
                                          );
                                          return _trackTrailing(
                                            pending: pending,
                                            selected: selected,
                                            progressFill: rowRoles.progressFill,
                                          );
                                        },
                                      )
                                    : _trackTrailing(
                                        pending: pending,
                                        selected: selected,
                                        progressFill: roles.progressFill,
                                      );

                                return Focus(
                                  canRequestFocus: false,
                                  skipTraversal: true,
                                  onFocusChange: (focused) {
                                    if (!focused) return;
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          if (mounted && context.mounted) {
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
                                            ? _initialSelectedTrackId == null
                                            : track!.id ==
                                                  _initialSelectedTrackId)
                                        ? _selectedRowKey
                                        : null,
                                    color: Colors.transparent,
                                    child: Tooltip(
                                      message: tooltip,
                                      excludeFromSemantics: true,
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
                                                  horizontal: _trackRowPadding,
                                                  vertical: 8,
                                                ),
                                            title: titleWidget,
                                            subtitle: subtitleWidget,
                                            trailing: trailingWidget,
                                            onTap: selectTrack,
                                          ),
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
          if (!widget.inPopover) const SizedBox(height: 24),
          if (widget.controller.trackSelectionError case final error?)
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
        ],
      ),
    );
  }
}

/// TV's explicit readonly focus owner keeps arrows reading long content rather
/// than moving between individual cast rows. Close is the only action.
class _NowPlayingInfo extends StatefulWidget {
  const _NowPlayingInfo({required this.controller, required this.program});
  final PlayerCoordinator controller;
  final GuideProgram program;

  @override
  State<_NowPlayingInfo> createState() => _NowPlayingInfoState();
}

class _NowPlayingInfoState extends State<_NowPlayingInfo> {
  final _close = FocusNode(debugLabel: 'More info Close');
  final _reader = FocusNode(debugLabel: 'More info reading');
  final _scroll = ScrollController();

  @override
  void dispose() {
    _close.dispose();
    _reader.dispose();
    _scroll.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (_close.hasFocus && key == LogicalKeyboardKey.arrowDown) {
      _reader.requestFocus();
      return KeyEventResult.handled;
    }
    if (!_reader.hasPrimaryFocus || !_scroll.hasClients) {
      return KeyEventResult.ignored;
    }
    final position = _scroll.position;
    if (key == LogicalKeyboardKey.arrowUp &&
        position.pixels <= position.minScrollExtent) {
      _close.requestFocus();
      return KeyEventResult.handled;
    }
    final amount = switch (key) {
      LogicalKeyboardKey.arrowDown => 48.0,
      LogicalKeyboardKey.arrowUp => -48.0,
      _ => null,
    };
    if (amount == null) return KeyEventResult.ignored;
    _scroll.jumpTo(
      (position.pixels + amount).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    return KeyEventResult.handled;
  }

  @override
  void didUpdateWidget(covariant _NowPlayingInfo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.program.id == widget.program.id) return;
    // A new scheduled program is a new document, never an old scroll offset.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.program.scheduled.item;
    final cast = widget.controller.guide.castFor(widget.program).cast;
    final (:editorial, :badges) = _nowPlayingFacts(
      widget.controller,
      widget.program,
    );
    return Material(
      type: MaterialType.transparency,
      child: FocusScope(
        onKeyEvent: _key,
        child: _PlaybackDrawer(
          controller: widget.controller,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'More info',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  TextButton(
                    key: const Key('player-more-info-close'),
                    focusNode: _close,
                    onPressed: widget.controller.closeOverlay,
                    child: _OverlayCloseLabel(
                      style: LineupTypography.tvLabelStyle(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Focus(
                  focusNode: _reader,
                  autofocus: true,
                  child: AnimatedBuilder(
                    animation: _reader,
                    builder: (context, _) {
                      final roles = LineupTheme.of(context);
                      final focused = LineupFocusScope.visible(
                        context,
                        _reader.hasPrimaryFocus,
                      );
                      return Semantics(
                        label: 'Program information',
                        focusable: true,
                        focused: _reader.hasPrimaryFocus,
                        child: LineupFocusFrame(
                          focused: focused,
                          child: Padding(
                            padding: roles.largeFocusIndicators
                                ? const EdgeInsets.all(
                                    LineupFocusFrame.contentClearance,
                                  )
                                : EdgeInsets.zero,
                            child: DecoratedBox(
                              key: const Key('player-more-info-reading'),
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: focused
                                        ? roles.focusedSurface
                                        : roles.subtleBorder,
                                    width: 4,
                                  ),
                                ),
                              ),
                              child: RawScrollbar(
                                key: const Key('player-more-info-scrollbar'),
                                controller: _scroll,
                                thumbVisibility: true,
                                thumbColor: focused
                                    ? roles.focusedSurface
                                    : roles.secondaryText.withValues(alpha: .5),
                                thickness: 4,
                                radius: const Radius.circular(2),
                                child: Builder(
                                  builder: (context) {
                                    final ink = LineupTheme.of(context);
                                    return SingleChildScrollView(
                                      key: const Key('player-more-info-scroll'),
                                      controller: _scroll,
                                      padding: const EdgeInsets.fromLTRB(
                                        20,
                                        4,
                                        20,
                                        16,
                                      ),
                                      child: DefaultTextStyle.merge(
                                        style: TextStyle(
                                          color: ink.primaryText,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            if (item.showTitle
                                                case final series?)
                                              Text(
                                                series,
                                                style: TextStyle(
                                                  color: ink.secondaryText,
                                                  shadows: const [],
                                                ),
                                              ),
                                            Text(
                                              item.title,
                                              style: LineupTypography
                                                  .programTitle
                                                  .copyWith(
                                                    color: ink.primaryText,
                                                    shadows: const [],
                                                  ),
                                            ),
                                            if (editorial.isNotEmpty) ...[
                                              const SizedBox(height: 8),
                                              Text(
                                                editorial,
                                                style: TextStyle(
                                                  color: ink.secondaryText,
                                                  shadows: const [],
                                                ),
                                              ),
                                            ],
                                            if (badges.isNotEmpty) ...[
                                              const SizedBox(height: 12),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 8,
                                                children: [
                                                  for (final badge in badges)
                                                    _NowPlayingBadge(
                                                      label: badge,
                                                    ),
                                                ],
                                              ),
                                            ],
                                            if (item.summary
                                                case final summary?) ...[
                                              const SizedBox(height: 16),
                                              Text(
                                                summary,
                                                key: const Key(
                                                  'player-more-info-summary',
                                                ),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyLarge
                                                    ?.copyWith(
                                                      color: ink.primaryText,
                                                      shadows: const [],
                                                      height: 1.45,
                                                    ),
                                              ),
                                            ],
                                            if (cast.isNotEmpty) ...[
                                              const SizedBox(height: 24),
                                              Text(
                                                'Cast',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      color: ink.primaryText,
                                                      shadows: const [],
                                                    ),
                                              ),
                                              for (
                                                var i = 0;
                                                i < cast.length;
                                                i++
                                              )
                                                Padding(
                                                  key: ValueKey(
                                                    'player-more-info-cast-$i',
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 8,
                                                      ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .stretch,
                                                    children: [
                                                      Text(cast[i].name),
                                                      if (cast[i].role
                                                          case final role?)
                                                        Text(
                                                          role,
                                                          style: TextStyle(
                                                            color: ink
                                                                .secondaryText,
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Text(
                  'Up/Down Scroll · Back Close',
                  key: const Key('player-more-info-hint'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: LineupTheme.of(context).secondaryText,
                    fontSize: DeviceProfile.of(context).isTv
                        ? LineupTypography.tvTextFloor
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaybackDrawer extends StatelessWidget {
  const _PlaybackDrawer({
    required this.controller,
    required this.child,
    this.focusScope,
  });
  final PlayerCoordinator controller;
  final FocusScopeNode? focusScope;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final railWidth = math.min(constraints.maxWidth * 0.4, 600.0);
        final fadeWidth = math.min(55.0, constraints.maxWidth - railWidth);
        final basePadding = constraints.maxWidth <= 800
            ? EdgeInsets.all(20)
            : EdgeInsets.fromLTRB(36, 48, 48, 36);
        final padding = DeviceProfile.of(context).isTv
            ? LineupCanvas.contentInsets(
                context,
                minimum: basePadding,
              ).copyWith(left: basePadding.left)
            : basePadding;
        return Align(
          alignment: Alignment.centerRight,
          child: FocusScope(
            node: focusScope,
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
                    _overlayColor(context, controller),
                    _overlayColor(context, controller),
                    _overlayColor(context, controller),
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
                    child: _consumeOverlayPadding(context, child),
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

Widget _trackTrailing({
  required bool pending,
  required bool selected,
  required Color progressFill,
}) => SizedBox(
  width: _trackTrailingWidth,
  child: Center(
    child: pending
        ? SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : selected
        ? Icon(Icons.check, color: progressFill, size: 24)
        : const SizedBox.shrink(),
  ),
);

class _ChannelNumber extends StatelessWidget {
  const _ChannelNumber({required this.controller});
  final PlayerCoordinator controller;
  @override
  Widget build(BuildContext context) => _StatusBug(
    controller: controller,
    text: controller.enteredChannelNumber,
    numberEntry: true,
  );
}

class _StatusBug extends StatelessWidget {
  const _StatusBug({
    required this.controller,
    required this.text,
    this.numberEntry = false,
  });
  final PlayerCoordinator controller;
  final String text;
  final bool numberEntry;
  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final channel = numberEntry ? controller.enteredChannel : null;
    final libraryTag = channel == null
        ? null
        : ChannelIdentity.libraryTagFor(channel, controller.lineup.channels);
    final entryProgram = channel == null
        ? null
        : controller.guide.currentProgram(channel.id);
    final entryRemaining = entryProgram == null
        ? null
        : _wholeMinutesLeft(
            controller.guide.now.difference(entryProgram.scheduled.start),
            entryProgram.scheduled.end.difference(entryProgram.scheduled.start),
          );
    final entryDescription = entryProgram == null
        ? null
        : [entryProgram.scheduled.item.title, ?entryRemaining].join(' · ');
    final liveLabel = !numberEntry
        ? text
        : channel == null
        ? '$text. Not in this lineup'
        : [
            ChannelIdentity.label(channel, libraryTag: libraryTag),
            ?entryDescription,
          ].join('. ');
    final style = Theme.of(context).textTheme.bodyLarge
        ?.copyWith(color: roles.primaryText, shadows: _overlayTextShadow);
    return Align(
      alignment: numberEntry ? Alignment.topCenter : Alignment.topRight,
      child: SafeArea(
        left: !DeviceProfile.of(context).isTv,
        top: !DeviceProfile.of(context).isTv,
        right: !DeviceProfile.of(context).isTv,
        bottom: !DeviceProfile.of(context).isTv,
        child: Padding(
          padding: DeviceProfile.of(context).isTv
              ? LineupCanvas.contentInsets(
                  context,
                  minimum: const EdgeInsets.all(24),
                )
              : const EdgeInsets.all(24),
          child: _consumeOverlayPadding(
            context,
            Semantics(
              container: true,
              liveRegion: true,
              label: liveLabel,
              excludeSemantics: true,
              child: Container(
                key: numberEntry
                    ? const Key('channel-number-buffer')
                    : const Key('player-status-bug'),
                constraints: BoxConstraints(
                  maxWidth: numberEntry
                      ? 460
                      : MediaQuery.sizeOf(context).width * .65,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _overlayColor(context, controller),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: numberEntry
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            text,
                            key: const Key('channel-number-digits'),
                            style: LineupTypography.programTitle.copyWith(
                              color: roles.primaryText,
                              fontSize: 84,
                            ),
                          ),
                          if (channel != null)
                            ChannelIdentity(
                              channel: channel,
                              libraryTag: libraryTag,
                              numberText: '',
                              nameStyle: style?.copyWith(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                              ),
                              showSemantics: false,
                            )
                          else
                            Text(
                              'Not in this lineup',
                              style: style?.copyWith(fontSize: 22),
                            ),
                          if (entryDescription != null)
                            Text(
                              entryDescription,
                              key: const Key('channel-number-program'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: style?.copyWith(
                                fontSize: 19,
                                color: roles.secondaryText,
                              ),
                            ),
                        ],
                      )
                    : Text(text, style: style),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StoppedSlate extends StatelessWidget {
  const _StoppedSlate({
    required this.controller,
    this.onClose,
    this.onOpenDiagnostics,
  });
  final PlayerCoordinator controller;
  final VoidCallback? onClose;
  final VoidCallback? onOpenDiagnostics;
  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final failed =
        controller.error != null ||
        controller.status.state == PlayerState.error;
    final unsupported = controller.status.state == PlayerState.unsupported;
    final title = unsupported
        ? 'Playback unavailable'
        : failed && !controller.hasStartedPlayback
        ? "Couldn't start playback"
        : 'Playback stopped';
    final channel = controller.currentChannel;
    final slate = ColoredBox(
      color: roles.deepBackground,
      child: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: DeviceProfile.of(context).isTv
                ? LineupCanvas.contentInsets(
                    context,
                    minimum: const EdgeInsets.all(24),
                  )
                : const EdgeInsets.all(24),
            child: _consumeOverlayPadding(
              context,
              Semantics(
                liveRegion: true,
                label: failed ? 'Playback error' : title,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (channel != null)
                      ChannelIdentity(
                        channel: channel,
                        libraryTag: ChannelIdentity.libraryTagFor(
                          channel,
                          controller.lineup.channels,
                        ),
                        nameStyle: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(color: roles.secondaryText),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      controller.error ??
                          (failed
                              ? PlaybackFailureCause.unknown.message
                              : controller.status.message),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      children: [
                        if (controller.canRetry)
                          FilledButton(
                            autofocus: DeviceProfile.of(context).isTv,
                            onPressed: controller.retry,
                            child: Text(failed ? 'Try again' : 'Retry'),
                          ),
                        OutlinedButton(
                          autofocus:
                              DeviceProfile.of(context).isTv &&
                              !controller.canRetry,
                          onPressed: controller.showMiniGuide,
                          child: Text(
                            failed
                                ? 'Choose another channel'
                                : 'Browse channels',
                          ),
                        ),
                        if (failed && onOpenDiagnostics != null)
                          TextButton(
                            onPressed: onOpenDiagnostics,
                            child: const Text('Details'),
                          ),
                        if (!failed)
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
      ),
    );
    if (!DeviceProfile.of(context).isTv) return slate;
    final active =
        controller.overlay == PlayerOverlay.none ||
        controller.overlay == PlayerOverlay.error;
    // Enter once per active slate presentation, and let its default button
    // autofocus within a fresh scope. Covered recovery controls must not take
    // remote focus or expose accessibility actions behind another overlay.
    return active
        ? FocusScope(autofocus: true, child: slate)
        : ExcludeFocus(child: ExcludeSemantics(child: slate));
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
  String? value,
  required String? tooltip,
  String? semanticLabel,
  required IconData icon,
  required VoidCallback? onPressed,
  FocusNode? focusNode,
}) {
  final action = Semantics(
    label: semanticLabel,
    button: semanticLabel == null ? null : true,
    enabled: semanticLabel == null ? null : onPressed != null,
    onTap: semanticLabel == null ? null : onPressed,
    excludeSemantics: semanticLabel != null,
    child: TextButton(
      key: key,
      style: _osdOptionStyle(context),
      focusNode: focusNode,
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 26),
          const SizedBox(width: 8),
          Flexible(
            child: Builder(
              builder: (context) {
                final roles = LineupTheme.of(context);
                final style = DefaultTextStyle.of(context).style;
                return Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (value != null)
                        TextSpan(
                          text: ' $value',
                          style: TextStyle(
                            fontWeight: FontWeight.w400,
                            color: style.color == roles.onFocus
                                ? roles.onFocus
                                : roles.secondaryText,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
  return ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 44),
    child: tooltip == null
        ? action
        : Tooltip(
            message: tooltip,
            excludeFromSemantics: semanticLabel != null,
            child: action,
          ),
  );
}

Uri? _artworkPath(ChannelItem item, GuideArtworkKind kind) => switch (kind) {
  GuideArtworkKind.poster => posterPath(item),
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
  ].join(' · ');
}

String _programTitle(ChannelItem item) {
  final showTitle = item.showTitle?.trim();
  return showTitle?.isNotEmpty == true ? showTitle! : item.title;
}

String _miniGuideProgramSupport(
  BuildContext context,
  GuideProgram program, {
  bool upcoming = false,
}) {
  final scheduled = program.scheduled;
  final start = _time(context, scheduled.start);
  final end = _time(context, scheduled.end);
  final episode = scheduled.item.showTitle?.trim().isNotEmpty == true;
  if (!episode) return upcoming ? start : '$start–$end';

  // In 12-hour locales, say the period once when both times share it.
  final period = RegExp(r' (AM|PM)$').firstMatch(end)?.group(0);
  final rangeStart = period != null && start.endsWith(period)
      ? start.substring(0, start.length - period.length)
      : start;
  return '${scheduled.item.title} · $rangeStart–$end';
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

Widget _consumeOverlayPadding(BuildContext context, Widget child) {
  final consume = DeviceProfile.of(context).isTv;
  return MediaQuery.removePadding(
    context: context,
    removeLeft: consume,
    removeTop: consume,
    removeRight: consume,
    removeBottom: consume,
    child: child,
  );
}

ButtonStyle _playerActionStyle(BuildContext context) {
  final roles = LineupTheme.of(context);
  return LineupTheme.buttonStyle(
    roles,
    LineupButtonTier.text,
    compact: true,
    focusVisible: LineupFocusScope.visible(context),
  ).copyWith(
    textStyle: WidgetStatePropertyAll(
      LineupTypography.button
          .copyWith(fontSize: 16)
          .copyWith(shadows: _overlayTextShadow),
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? roles.secondaryText.withValues(alpha: .45)
          : roles.focusTreatment == LineupFocusTreatment.fill &&
                states.contains(WidgetState.focused)
          ? roles.onFocus
          : roles.secondaryText,
    ),
    minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
  );
}

ButtonStyle _osdOptionStyle(BuildContext context) {
  final roles = LineupTheme.of(context);
  return _playerActionStyle(context).copyWith(
    textStyle: WidgetStatePropertyAll(
      LineupTypography.button
          .copyWith(fontSize: 22, fontWeight: FontWeight.w600)
          .copyWith(shadows: _overlayTextShadow),
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? roles.secondaryText.withValues(alpha: .45)
          : roles.focusTreatment == LineupFocusTreatment.fill &&
                states.contains(WidgetState.focused)
          ? roles.onFocus
          : roles.primaryText,
    ),
    minimumSize: const WidgetStatePropertyAll(Size(44, 60)),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
    ),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20)),
  );
}

class _OsdPanelMaterial extends CustomPainter {
  const _OsdPanelMaterial({
    required this.color,
    required this.collapsedFade,
    this.expanded = false,
  });
  static const feather = 55.0;

  final Color color;
  final bool collapsedFade;
  final bool expanded;

  @override
  void paint(Canvas canvas, Size size) {
    final fadeHeight = expanded ? 180.0 : feather;
    final bounds = Rect.fromLTWH(
      0,
      -fadeHeight,
      size.width,
      size.height + fadeHeight,
    );
    final join = fadeHeight / bounds.height;
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
      color != oldDelegate.color ||
      collapsedFade != oldDelegate.collapsedFade ||
      expanded != oldDelegate.expanded;
}

class _TrackListFade extends StatelessWidget {
  const _TrackListFade({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DeviceProfile.of(context).isTv
      ? ClipRect(child: child)
      : ShaderMask(
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
  const _OverlayCloseLabel({this.style});

  final TextStyle? style;

  static const label = 'Close';
  static const gap = 6.0;
  static const iconSize = 16.0;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: style),
      const SizedBox(width: gap),
      const ExcludeSemantics(child: Icon(Icons.close, size: iconSize)),
    ],
  );
}
