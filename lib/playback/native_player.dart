import 'dart:async';

abstract interface class NativePlayer {
  PlayerStatus get status;
  Duration get position;
  Duration get duration;
  PlayerTelemetry get telemetry;
  List<PlayerTrack> get tracks;
  Stream<PlayerEvent> get events;

  Future<void> initialize();
  Future<void> load(Uri media);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVideoRect(PlayerVideoRect rect);
  Future<void> setFullscreen(bool fullscreen);
  Future<void> selectTrack(PlayerTrackType type, int? id);
  Future<void> setVolume(double volume);
  Future<void> stop();
  Future<void> dispose();
}

enum PlayerState { idle, loading, playing, paused, stopped, error, unsupported }

class PlayerStatus {
  const PlayerStatus({required this.state, required this.message});

  final PlayerState state;
  final String message;
}

class PlayerEvent {
  const PlayerEvent({
    required this.status,
    required this.position,
    required this.duration,
    required this.telemetry,
    required this.tracks,
  });

  final PlayerStatus status;
  final Duration position;
  final Duration duration;
  final PlayerTelemetry telemetry;
  final List<PlayerTrack> tracks;
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
  const PlayerUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}
