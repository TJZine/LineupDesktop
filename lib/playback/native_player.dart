import 'dart:async';

abstract interface class NativePlayer {
  PlayerStatus get status;
  Duration get position;
  Duration get duration;
  PlayerTelemetry get telemetry;
  List<PlayerTrack> get tracks;

  /// A hot broadcast stream of player state snapshots.
  ///
  /// Implementations must allow multiple simultaneous listeners. Events
  /// emitted without listeners are not buffered for later delivery.
  Stream<PlayerEvent> get events;

  Future<void> initialize();

  /// Loads [media] for the caller's optional [generation].
  ///
  /// [generation] identifies the current load and may be projected on emitted
  /// events so callers can reject stale work.
  ///
  /// [plexToken] is sensitive authentication material. Implementations that
  /// perform network media loads must require HTTPS and send it only as an
  /// `X-Plex-Token` request header. They must not follow redirects while the
  /// header is attached unless every target is proven to retain the original
  /// HTTPS origin. They must never log it or append it to [media].
  Future<void> load(Uri media, {String? plexToken, int? generation});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVideoRect(PlayerVideoRect rect);
  Future<void> setFullscreen(bool fullscreen);
  Future<void> selectTrack(PlayerTrackType type, int? id);
  Future<void> setVolume(double volume);

  /// Immediately invalidates any active load before awaiting native cleanup.
  ///
  /// A pending [load] must settle with [PlayerUnavailable], and events from
  /// that retired load must be ignored even while native cleanup is pending.
  Future<void> stop();
  Future<void> dispose();
}

enum PlayerState {
  idle,
  loading,
  ready,
  playing,
  paused,
  buffering,
  seeking,
  ended,
  stopped,
  error,
  unsupported,
}

class PlayerStatus {
  const PlayerStatus({
    required this.state,
    required this.message,
    this.recoverable = false,
    this.failureCode,
    this.httpStatus,
  });

  final PlayerState state;
  final String message;
  final bool recoverable;
  final String? failureCode;
  final int? httpStatus;
}

class PlayerEvent {
  const PlayerEvent({
    required this.status,
    required this.position,
    required this.duration,
    required this.telemetry,
    required this.tracks,
    this.generation,
  });

  final PlayerStatus status;
  final Duration position;
  final Duration duration;
  final PlayerTelemetry telemetry;
  final List<PlayerTrack> tracks;

  /// Identifies the media load associated with this event.
  ///
  /// Production native players project the active generation onto emitted
  /// events so `PlayerCoordinator` can ignore events from superseded loads.
  final int? generation;
}

class PlayerVideoRect {
  const PlayerVideoRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.scale,
  });

  final double left;
  final double top;
  final double width;
  final double height;
  final double scale;

  @override
  bool operator ==(Object other) =>
      other is PlayerVideoRect &&
      left == other.left &&
      top == other.top &&
      width == other.width &&
      height == other.height &&
      scale == other.scale;

  @override
  int get hashCode => Object.hash(left, top, width, height, scale);
}

enum PlayerTrackType { video, audio, subtitle }

class PlayerTrack {
  const PlayerTrack({
    required this.id,
    required this.type,
    required this.selected,
    this.title,
    this.language,
    this.codec,
  });

  final int id;
  final PlayerTrackType type;
  final bool selected;
  final String? title;
  final String? language;
  final String? codec;
}

class PlayerTelemetry {
  const PlayerTelemetry({
    this.videoOutput,
    this.hardwareDecoder,
    this.videoCodec,
    this.videoFormat,
    this.width,
    this.height,
    this.pixelFormat,
    this.hardwarePixelFormat,
    this.primaries,
    this.gamma,
    this.colorMatrix,
    this.signalPeak,
  });

  final String? videoOutput;
  final String? hardwareDecoder;
  final String? videoCodec;
  final String? videoFormat;
  final int? width;
  final int? height;
  final String? pixelFormat;
  final String? hardwarePixelFormat;
  final String? primaries;
  final String? gamma;
  final String? colorMatrix;
  final double? signalPeak;

  bool get isHdr {
    final transfer = gamma?.toLowerCase();
    return transfer == 'pq' || transfer == 'hlg' || transfer == 'smpte-st-2084';
  }
}

class PlayerUnavailable implements Exception {
  const PlayerUnavailable(
    this.message, {
    this.failureCode = 'player_unavailable',
  });

  final String message;
  final String failureCode;

  @override
  String toString() => message;
}
