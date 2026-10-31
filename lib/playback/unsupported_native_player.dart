import 'dart:async';

import 'package:flutter/foundation.dart';

import 'native_player.dart';

class UnsupportedNativePlayer implements NativePlayer {
  @override
  final subtitleCues = ValueNotifier<SubtitleCues>(const SubtitleCues.empty());
  @override
  Future<void> setSubtitlePresentation({
    required double scale,
    required double imageRaise,
    required bool lineupDrawsStyled,
  }) async {}

  UnsupportedNativePlayer({required this.message});

  static const platformMessage = 'Playback is not implemented on this platform';
  static const platformFailureMessage =
      'Native playback is not implemented on this platform.';

  final String message;

  PlayerStatus get _unsupported =>
      PlayerStatus(state: PlayerState.unsupported, message: message);

  @override
  PlayerStatus get status => _unsupported;

  @override
  Duration get position => Duration.zero;

  @override
  Duration get duration => Duration.zero;

  @override
  PlayerTelemetry get telemetry => const PlayerTelemetry();

  @override
  List<PlayerTrack> get tracks => const [];

  @override
  DisplayMatchingReport get displayReport =>
      const DisplayMatchingReport.unavailable();

  @override
  Stream<PlayerEvent> get events => const Stream.empty();

  @override
  Stream<DisplayMatchingReport> get displayReports => const Stream.empty();

  @override
  bool get fullscreen => false;

  @override
  PlayerCapabilities get capabilities => const PlayerCapabilities.unavailable();

  @override
  Stream<bool> get fullscreenChanges => const Stream.empty();

  @override
  Future<void> initialize() async {}

  Never _unavailable() => throw PlayerUnavailable(platformFailureMessage);

  @override
  Future<void> load(
    Uri media, {
    String? plexToken,
    int? generation,
    bool startPaused = false,
    Duration? startPosition,
  }) async => _unavailable();

  @override
  Future<void> setDisplayMatching(DisplayMatchingRequest request) async {}

  @override
  Future<void> play() async => _unavailable();

  @override
  Future<void> pause() async => _unavailable();

  @override
  Future<void> seek(
    Duration position, {
    SeekMode mode = SeekMode.exact,
  }) async => _unavailable();

  @override
  Future<void> setVideoRect(PlayerVideoRect rect) async => _unavailable();

  @override
  Future<void> setFullscreen(bool fullscreen) async => _unavailable();

  @override
  Future<void> selectTrack(PlayerTrackType type, int? id) async =>
      _unavailable();

  @override
  Future<void> setVolume(double volume) async => _unavailable();

  @override
  Future<void> stop() async => _unavailable();

  @override
  Future<void> dispose() async {}
}
