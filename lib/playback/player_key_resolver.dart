import 'package:flutter/services.dart';

import '../ui/lineup_focus.dart' show androidTvKeyAlias;
import 'player_coordinator.dart';

sealed class PlayerCommand {
  const PlayerCommand();
  bool get closesSleepPicker;
}

enum PlayerAction implements PlayerCommand {
  ignored(false),
  consumed(false),
  backToGuide(false),
  collapseNowPlaying(false),
  closeOverlay(false),
  openMenu(false),
  commitChannelNumber(false),
  openGuide(true),
  miniGuideUp(false),
  miniGuideDown(false),
  miniGuidePageUp(true),
  miniGuidePageDown(true),
  previousChannel(true),
  nextChannel(true),
  tuneMiniGuide(false),
  showOsd(false),
  showOsdFromInfo(true),
  togglePlayback(true),
  seekBackward(true),
  seekForward(true),
  showMiniGuide(true),
  showNowPlaying(true),
  toggleFullscreen(true),
  showSleepTimer(false),
  showAudioTracks(true),
  showSubtitleTracks(true),
  play(true),
  playAndShowOsd(true),
  pause(true),
  pauseAndShowOsd(true),
  stop(true),
  rewind(true),
  fastForward(true);

  const PlayerAction(this.closesSleepPicker);
  @override
  final bool closesSleepPicker;
}

final class AppendChannelDigit extends PlayerCommand {
  const AppendChannelDigit(this.digit);
  final String digit;
  @override
  bool get closesSleepPicker => true;
}

final _backKeys = {
  LogicalKeyboardKey.escape,
  LogicalKeyboardKey.backspace,
  LogicalKeyboardKey.goBack,
};
final _guideKeys = {LogicalKeyboardKey.keyG, LogicalKeyboardKey.f2};
final _enterKeys = {
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.select,
};
final _mediaTransportKeys = {
  LogicalKeyboardKey.mediaPlay,
  LogicalKeyboardKey.mediaPause,
  LogicalKeyboardKey.mediaPlayPause,
  LogicalKeyboardKey.mediaStop,
  LogicalKeyboardKey.mediaRewind,
  LogicalKeyboardKey.mediaFastForward,
};
final _keyboardTransportKeys = {
  LogicalKeyboardKey.space,
  LogicalKeyboardKey.keyJ,
  LogicalKeyboardKey.keyK,
  LogicalKeyboardKey.keyL,
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight,
};
final _fullscreenKeys = {LogicalKeyboardKey.keyF, LogicalKeyboardKey.f11};
final _pageKeys = {LogicalKeyboardKey.pageUp, LogicalKeyboardKey.pageDown};

/// Resolves in the same priority order as the public Player interaction:
/// Back, transport availability, unsupported playback, overlay ownership, then
/// overlay-specific selection and ordinary actions. No focus/native side effects.
PlayerCommand resolvePlayerKey(
  LogicalKeyboardKey key, {
  required PlayerOverlay overlay,
  required bool androidTv,
  required bool dvr,
  required bool unsupported,
  required bool initialPress,
  required bool hasProgram,
  bool tvOsdAtBottom = false,
  // macOS only: Command chords belong to the app menu and system, so no
  // Player action may claim them. Ctrl handling is unchanged.
  bool commandPressed = false,
}) {
  if (commandPressed) return PlayerAction.ignored;
  // Android TV's Menu key is a shell action, not the optional Info command.
  // Resolve it before the shared TV aliases turn contextMenu into keyI.
  if (androidTv && key == LogicalKeyboardKey.contextMenu) {
    return PlayerAction.openMenu;
  }
  key = androidTvKeyAlias(key, androidTv: androidTv) ?? key;
  if (_backKeys.contains(key)) {
    return switch (overlay) {
      PlayerOverlay.none => PlayerAction.backToGuide,
      PlayerOverlay.nowPlaying => PlayerAction.collapseNowPlaying,
      _ => PlayerAction.closeOverlay,
    };
  }
  final ordinary = switch (overlay) {
    PlayerOverlay.none || PlayerOverlay.osd || PlayerOverlay.nowPlaying => true,
    _ => false,
  };
  final mediaTransport = _mediaTransportKeys.contains(key);
  if (!dvr &&
      (mediaTransport || (ordinary && _keyboardTransportKeys.contains(key)))) {
    return PlayerAction.consumed;
  }
  final digit = _digit(key);
  final enter = _enterKeys.contains(key);
  final selects =
      enter ||
      key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.mediaPlayPause;
  if (unsupported &&
      (digit != null ||
          (mediaTransport && key != LogicalKeyboardKey.mediaPlayPause) ||
          _fullscreenKeys.contains(key) ||
          key == LogicalKeyboardKey.keyJ ||
          key == LogicalKeyboardKey.keyK ||
          key == LogicalKeyboardKey.keyL ||
          (_pageKeys.contains(key) && overlay != PlayerOverlay.miniGuide) ||
          (overlay == PlayerOverlay.none &&
              (selects ||
                  key == LogicalKeyboardKey.arrowLeft ||
                  key == LogicalKeyboardKey.arrowRight)) ||
          (overlay == PlayerOverlay.miniGuide && selects))) {
    return PlayerAction.consumed;
  }
  // Program information is readonly: arrows/Select belong to its reader and
  // Close. Only explicit remote transport/channel commands escape to Player.
  // Availability and unsupported-media guards above remain authoritative.
  if (overlay == PlayerOverlay.programInfo) {
    if (_guideKeys.contains(key)) return PlayerAction.openGuide;
    if (unsupported && key == LogicalKeyboardKey.mediaPlayPause) {
      return PlayerAction.consumed;
    }
    return switch (key) {
      LogicalKeyboardKey.mediaPlayPause => PlayerAction.togglePlayback,
      LogicalKeyboardKey.mediaPlay => PlayerAction.play,
      LogicalKeyboardKey.mediaPause => PlayerAction.pause,
      LogicalKeyboardKey.mediaStop => PlayerAction.stop,
      LogicalKeyboardKey.mediaRewind => PlayerAction.rewind,
      LogicalKeyboardKey.mediaFastForward => PlayerAction.fastForward,
      LogicalKeyboardKey.pageUp => PlayerAction.previousChannel,
      LogicalKeyboardKey.pageDown => PlayerAction.nextChannel,
      _ => PlayerAction.ignored,
    };
  }
  final overlayOwnsKey = switch (overlay) {
    PlayerOverlay.audioTracks ||
    PlayerOverlay.subtitleTracks => !_guideKeys.contains(key),
    PlayerOverlay.error => !_pageKeys.contains(key),
    _ => false,
  };
  if (overlayOwnsKey) return PlayerAction.ignored;
  if (overlay == PlayerOverlay.channelNumber) {
    if (digit != null) return AppendChannelDigit(digit);
    return enter ? PlayerAction.commitChannelNumber : PlayerAction.ignored;
  }
  if (_guideKeys.contains(key)) return PlayerAction.openGuide;
  final miniGuide = overlay == PlayerOverlay.miniGuide;
  final nowPlaying = overlay == PlayerOverlay.nowPlaying;
  if (miniGuide && key == LogicalKeyboardKey.arrowUp) {
    return PlayerAction.miniGuideUp;
  }
  if (miniGuide && key == LogicalKeyboardKey.arrowDown) {
    return PlayerAction.miniGuideDown;
  }
  if (key == LogicalKeyboardKey.pageUp) {
    return miniGuide
        ? PlayerAction.miniGuidePageUp
        : PlayerAction.previousChannel;
  }
  if (key == LogicalKeyboardKey.pageDown) {
    return miniGuide
        ? PlayerAction.miniGuidePageDown
        : PlayerAction.nextChannel;
  }
  if (miniGuide && (enter || key == LogicalKeyboardKey.space)) {
    return PlayerAction.tuneMiniGuide;
  }
  if (enter) {
    return nowPlaying || overlay == PlayerOverlay.none
        ? PlayerAction.showOsd
        : PlayerAction.ignored;
  }
  if (key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.keyK ||
      key == LogicalKeyboardKey.mediaPlayPause) {
    return ordinary ? PlayerAction.togglePlayback : PlayerAction.ignored;
  }
  if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyJ) {
    return ordinary ? PlayerAction.seekBackward : PlayerAction.ignored;
  }
  if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.keyL) {
    if (miniGuide) return PlayerAction.openGuide;
    return ordinary ? PlayerAction.seekForward : PlayerAction.ignored;
  }
  if (key == LogicalKeyboardKey.arrowUp &&
      (overlay == PlayerOverlay.none || overlay == PlayerOverlay.osd)) {
    return PlayerAction.showMiniGuide;
  }
  if (key == LogicalKeyboardKey.arrowDown &&
      (overlay == PlayerOverlay.none || overlay == PlayerOverlay.osd)) {
    if (androidTv) {
      if (overlay == PlayerOverlay.none) return PlayerAction.showOsd;
      return tvOsdAtBottom && hasProgram
          ? PlayerAction.showNowPlaying
          : PlayerAction.consumed;
    }
    return hasProgram
        ? PlayerAction.showNowPlaying
        : PlayerAction.showOsdFromInfo;
  }
  if (initialPress && key == LogicalKeyboardKey.keyI) {
    return nowPlaying
        ? PlayerAction.showOsdFromInfo
        : androidTv && !hasProgram
        ? PlayerAction.showOsd
        : PlayerAction.showNowPlaying;
  }
  if (initialPress && _fullscreenKeys.contains(key)) {
    return PlayerAction.toggleFullscreen;
  }
  if (initialPress && key == LogicalKeyboardKey.keyS) {
    return PlayerAction.showSleepTimer;
  }
  return switch (key) {
    LogicalKeyboardKey.keyA => PlayerAction.showAudioTracks,
    LogicalKeyboardKey.keyC => PlayerAction.showSubtitleTracks,
    LogicalKeyboardKey.mediaPlay =>
      nowPlaying ? PlayerAction.playAndShowOsd : PlayerAction.play,
    LogicalKeyboardKey.mediaPause =>
      nowPlaying ? PlayerAction.pauseAndShowOsd : PlayerAction.pause,
    LogicalKeyboardKey.mediaStop => PlayerAction.stop,
    LogicalKeyboardKey.mediaRewind =>
      nowPlaying ? PlayerAction.seekBackward : PlayerAction.rewind,
    LogicalKeyboardKey.mediaFastForward =>
      nowPlaying ? PlayerAction.seekForward : PlayerAction.fastForward,
    _ => digit == null ? PlayerAction.ignored : AppendChannelDigit(digit),
  };
}

final _digits = <LogicalKeyboardKey, String>{
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

String? _digit(LogicalKeyboardKey key) => _digits[key];
