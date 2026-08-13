import 'dart:async';

import 'package:flutter/services.dart';

import 'native_player.dart';

class WindowsNativePlayer implements NativePlayer {
  static const _channel = MethodChannel('lineup/native_player');

  final _events = StreamController<PlayerEvent>.broadcast(sync: true);
  PlayerStatus _status = const PlayerStatus(
    state: PlayerState.idle,
    message: 'Native player not initialized',
  );
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  PlayerTelemetry _telemetry = const PlayerTelemetry();
  List<PlayerTrack> _tracks = const [];
  Completer<void>? _pendingLoad;
  bool _initialized = false;

  @override
  PlayerStatus get status => _status;

  @override
  Duration get position => _position;

  @override
  Duration get duration => _duration;

  @override
  PlayerTelemetry get telemetry => _telemetry;

  @override
  List<PlayerTrack> get tracks => _tracks;

  @override
  Stream<PlayerEvent> get events => _events.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _channel.setMethodCallHandler(_handleNativeCall);
    try {
      await _channel.invokeMethod<Object?>('initialize');
    } catch (_) {
      _channel.setMethodCallHandler(null);
      rethrow;
    }
    _initialized = true;
    _setStatus(PlayerState.idle, 'Native libmpv player ready');
  }

  @override
  Future<void> load(Uri media) async {
    _requireInitialized();
    final pending = Completer<void>();
    _pendingLoad?.completeError(
      const PlayerUnavailable('A newer media load replaced this request.'),
    );
    _pendingLoad = pending;
    try {
      await _channel.invokeMethod<void>('load', {'uri': media.toString()});
      await pending.future.timeout(const Duration(seconds: 30));
    } finally {
      if (identical(_pendingLoad, pending)) _pendingLoad = null;
    }
  }

  @override
  Future<void> play() => _invoke('play');

  @override
  Future<void> pause() => _invoke('pause');

  @override
  Future<void> seek(Duration position) => _invoke('seek', {
    'seconds': position.inMicroseconds / Duration.microsecondsPerSecond,
  });

  @override
  Future<void> setVideoRect(PlayerVideoRect rect) => _invoke('setVideoRect', {
    'left': rect.left,
    'top': rect.top,
    'width': rect.width,
    'height': rect.height,
    'scale': rect.scale,
  });

  @override
  Future<void> setFullscreen(bool fullscreen) =>
      _invoke('setFullscreen', {'fullscreen': fullscreen});

  @override
  Future<void> selectTrack(PlayerTrackType type, int? id) =>
      _invoke('selectTrack', {'type': type.name, 'id': id});

  @override
  Future<void> setVolume(double volume) =>
      _invoke('setVolume', {'volume': volume});

  @override
  Future<void> stop() => _invoke('stop');

  @override
  Future<void> dispose() async {
    _pendingLoad?.completeError(
      const PlayerUnavailable('The native player was disposed.'),
    );
    _pendingLoad = null;
    if (!_initialized) return;
    _initialized = false;
    await _channel.invokeMethod<void>('dispose');
    _channel.setMethodCallHandler(null);
    _setStatus(PlayerState.stopped, 'Native player disposed');
  }

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    _requireInitialized();
    await _channel.invokeMethod<void>(method, arguments);
  }

  void _requireInitialized() {
    if (!_initialized) {
      throw const PlayerUnavailable('The native player is not initialized.');
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'event') return;
    final event = Map<Object?, Object?>.from(call.arguments as Map);
    switch (event['type']) {
      case 'state':
        _handleState(event);
      case 'property':
        _handleProperty(event['name'] as String?, event['value']);
    }
  }

  void _handleState(Map<Object?, Object?> event) {
    final state = switch (event['state']) {
      'loading' => PlayerState.loading,
      'playing' => PlayerState.playing,
      'paused' => PlayerState.paused,
      'stopped' => PlayerState.stopped,
      'error' => PlayerState.error,
      _ => PlayerState.idle,
    };
    final message = event['message'] as String? ?? state.name;
    _setStatus(state, message);
    if (state == PlayerState.playing) {
      _pendingLoad?.complete();
    } else if (state == PlayerState.error) {
      _pendingLoad?.completeError(PlayerUnavailable(message));
    }
  }

  void _handleProperty(String? name, Object? value) {
    switch (name) {
      case 'pause':
        if (_status.state == PlayerState.playing ||
            _status.state == PlayerState.paused) {
          _status = PlayerStatus(
            state: value == true ? PlayerState.paused : PlayerState.playing,
            message: value == true ? 'Paused' : 'Playing',
          );
        }
      case 'time-pos':
        _position = _durationFromSeconds(value);
      case 'duration':
        _duration = _durationFromSeconds(value);
      case 'track-list':
        _tracks = _decodeTracks(value);
      case 'video-format':
        _telemetry = _copyTelemetry(videoFormat: value as String?);
      case 'video-codec':
        _telemetry = _copyTelemetry(videoCodec: value as String?);
      case 'current-vo':
        _telemetry = _copyTelemetry(videoOutput: value as String?);
      case 'hwdec-current':
        _telemetry = _copyTelemetry(hardwareDecoder: value as String?);
      case 'video-params':
        _applyVideoParameters(value);
    }
    _emit();
  }

  Duration _durationFromSeconds(Object? value) {
    final seconds = value is num ? value.toDouble() : 0.0;
    if (!seconds.isFinite || seconds < 0) return Duration.zero;
    return Duration(microseconds: (seconds * 1000000).round());
  }

  List<PlayerTrack> _decodeTracks(Object? value) {
    if (value is! List) return const [];
    final tracks = <PlayerTrack>[];
    for (final item in value) {
      if (item is! Map) continue;
      final track = _decodeTrack(Map<Object?, Object?>.from(item));
      if (track != null) tracks.add(track);
    }
    return tracks;
  }

  PlayerTrack? _decodeTrack(Map<Object?, Object?> item) {
    final id = item['id'];
    final type = switch (item['type']) {
      'video' => PlayerTrackType.video,
      'audio' => PlayerTrackType.audio,
      'sub' => PlayerTrackType.subtitle,
      _ => null,
    };
    if (id is! int || type == null) return null;
    return PlayerTrack(
      id: id,
      type: type,
      selected: item['selected'] == true,
      title: item['title'] as String?,
      language: item['lang'] as String?,
      codec: item['codec'] as String?,
    );
  }

  void _applyVideoParameters(Object? value) {
    if (value is! Map) return;
    final parameters = Map<Object?, Object?>.from(value);
    _telemetry = _copyTelemetry(
      width: parameters['w'] as int?,
      height: parameters['h'] as int?,
      pixelFormat: parameters['pixelformat'] as String?,
      hardwarePixelFormat: parameters['hw-pixelformat'] as String?,
      primaries: parameters['primaries'] as String?,
      gamma: parameters['gamma'] as String?,
      colorMatrix: parameters['colormatrix'] as String?,
      signalPeak: (parameters['sig-peak'] as num?)?.toDouble(),
    );
  }

  PlayerTelemetry _copyTelemetry({
    String? videoOutput,
    String? hardwareDecoder,
    String? videoCodec,
    String? videoFormat,
    int? width,
    int? height,
    String? pixelFormat,
    String? hardwarePixelFormat,
    String? primaries,
    String? gamma,
    String? colorMatrix,
    double? signalPeak,
  }) {
    return PlayerTelemetry(
      videoOutput: videoOutput ?? _telemetry.videoOutput,
      hardwareDecoder: hardwareDecoder ?? _telemetry.hardwareDecoder,
      videoCodec: videoCodec ?? _telemetry.videoCodec,
      videoFormat: videoFormat ?? _telemetry.videoFormat,
      width: width ?? _telemetry.width,
      height: height ?? _telemetry.height,
      pixelFormat: pixelFormat ?? _telemetry.pixelFormat,
      hardwarePixelFormat:
          hardwarePixelFormat ?? _telemetry.hardwarePixelFormat,
      primaries: primaries ?? _telemetry.primaries,
      gamma: gamma ?? _telemetry.gamma,
      colorMatrix: colorMatrix ?? _telemetry.colorMatrix,
      signalPeak: signalPeak ?? _telemetry.signalPeak,
    );
  }

  void _setStatus(PlayerState state, String message) {
    _status = PlayerStatus(state: state, message: message);
    _emit();
  }

  void _emit() {
    if (_events.isClosed) return;
    _events.add(
      PlayerEvent(
        status: _status,
        position: _position,
        duration: _duration,
        telemetry: _telemetry,
        tracks: List.unmodifiable(_tracks),
      ),
    );
  }
}
