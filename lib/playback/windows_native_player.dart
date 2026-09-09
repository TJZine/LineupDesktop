import 'dart:async';

import 'package:flutter/services.dart';

import 'native_player.dart';

class WindowsNativePlayer implements NativePlayer {
  static const _channel = MethodChannel('lineup/native_player');
  static const _nativePlaybackFailureCodes = {
    'http_error',
    'network_error',
    'audio_decode_error',
    'video_decode_error',
    'audio_output_error',
    'video_output_error',
    'source_open_error',
    'container_error',
    'correlation_error',
    'command_error',
    'event_queue_overflow',
    'mpv_error',
  };
  static const _nativeCommandFailureCodes = {
    'required_engine_unavailable',
    'initialize_failed',
    'dispose_in_progress',
    'not_initialized',
    'invalid_argument',
    'insecure_media_uri',
    'command_queue_full',
    'window_error',
  };
  static WindowsNativePlayer? _handlerOwner;

  WindowsNativePlayer({Duration? loadTimeout, Duration? stopTimeout})
    : _loadTimeout = loadTimeout ?? const Duration(seconds: 30),
      _stopTimeout = stopTimeout ?? const Duration(seconds: 10);

  final _events = StreamController<PlayerEvent>.broadcast(sync: true);
  final Duration _loadTimeout;
  final Duration _stopTimeout;
  int _nextStopId = 0;
  (int, Completer<void>)? _pendingStop;
  Future<void>? _stopOperation;
  PlayerStatus _status = const PlayerStatus(
    state: PlayerState.idle,
    message: 'Native player not initialized',
  );
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  PlayerTelemetry _telemetry = const PlayerTelemetry();
  List<PlayerTrack> _tracks = const [];
  Completer<void>? _pendingLoad;
  Future<void> _lifecycle = Future.value();
  int _nextLoadId = 0;
  int? _activeLoadId;
  int? _activeGeneration;
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
  Future<void> initialize() => _serializeLifecycle(() async {
    if (_initialized) return;
    if (_handlerOwner != null && !identical(_handlerOwner, this)) {
      throw const PlayerUnavailable(
        'Another Windows native player already owns the platform channel.',
      );
    }
    _handlerOwner = this;
    _channel.setMethodCallHandler(_handleNativeCall);
    try {
      await _invokeNative<Object?>('initialize');
    } catch (_) {
      if (identical(_handlerOwner, this)) {
        _channel.setMethodCallHandler(null);
        _handlerOwner = null;
      }
      rethrow;
    }
    _initialized = true;
    _setStatus(PlayerState.idle, 'Native libmpv player ready');
  });

  @override
  Future<void> load(Uri media, {String? plexToken, int? generation}) async {
    if (plexToken != null &&
        (media.scheme.toLowerCase() != 'https' ||
            !media.hasAuthority ||
            media.host.isEmpty)) {
      throw const PlayerUnavailable(
        'Authenticated Plex media requires HTTPS.',
        failureCode: 'insecure_media_uri',
      );
    }
    await _lifecycle;
    await _stopOperation;
    _requireInitialized();
    final loadId = ++_nextLoadId;
    final pending = Completer<void>();
    _completePendingLoadError(
      const PlayerUnavailable('A newer media load replaced this request.'),
    );
    _pendingLoad = pending;
    _activeLoadId = loadId;
    _activeGeneration = generation;
    _resetMediaState();
    _setStatus(PlayerState.loading, 'Loading media');
    try {
      final completion = pending.future
          .timeout(_loadTimeout)
          .then<(Object, StackTrace)?>(
            (_) => null,
            onError: (Object error, StackTrace stackTrace) =>
                (error, stackTrace),
          );
      await _invokeNative<void>('load', {
        'uri': media.toString(),
        'plexToken': plexToken,
        'loadId': loadId,
      });
      final failure = await completion;
      if (failure != null) {
        Error.throwWithStackTrace(failure.$1, failure.$2);
      }
    } catch (error) {
      if (identical(_pendingLoad, pending)) {
        _activeLoadId = null;
        _setStatus(
          PlayerState.error,
          error is TimeoutException
              ? 'Media load timed out'
              : error is PlayerUnavailable
              ? error.message
              : 'Media load failed',
          recoverable: true,
          failureCode: switch (error) {
            PlayerUnavailable(:final failureCode) => failureCode,
            TimeoutException() => 'load_timeout',
            _ => _status.failureCode,
          },
          httpStatus: _status.httpStatus,
        );
        _activeGeneration = null;
      }
      rethrow;
    } finally {
      if (identical(_pendingLoad, pending)) {
        _pendingLoad = null;
      }
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
  Future<void> stop() {
    final existing = _stopOperation;
    if (existing != null) return existing;
    final stopId = ++_nextStopId;
    final pending = Completer<void>();
    _pendingStop = (stopId, pending);
    _completePendingLoadError(
      const PlayerUnavailable('The media load was stopped.'),
    );
    _pendingLoad = null;
    _activeLoadId = null;
    _activeGeneration = null;
    Future<void> performStop() async {
      // Queue acceptance is separate from native stop execution and idle proof.
      final completion = pending.future.then<Object?>(
        (_) => null,
        onError: (Object error) => error,
      );
      await _invoke('stop', {'stopId': stopId});
      final failure = await completion;
      if (failure != null) throw failure;
      if (_pendingStop?.$1 != stopId) return;
      _resetMediaState();
      _setStatus(PlayerState.stopped, 'Stopped');
    }

    late final Future<void> operation;
    operation = performStop()
        .timeout(
          _stopTimeout,
          onTimeout: () => throw const PlayerUnavailable(
            'Native playback did not stop in time.',
            failureCode: 'stop_timeout',
          ),
        )
        .whenComplete(() {
          if (identical(_stopOperation, operation)) {
            _stopOperation = null;
            _pendingStop = null;
          }
        });
    _stopOperation = operation;
    return operation;
  }

  @override
  Future<void> dispose() => _serializeLifecycle(() async {
    final stop = _pendingStop;
    if (stop != null && !stop.$2.isCompleted) {
      stop.$2.completeError(
        const PlayerUnavailable('The native player was disposed.'),
      );
    }
    _pendingStop = null;
    _completePendingLoadError(
      const PlayerUnavailable('The native player was disposed.'),
    );
    _pendingLoad = null;
    _activeLoadId = null;
    _activeGeneration = null;
    if (!_initialized) return;
    _initialized = false;
    try {
      await _invokeNative<void>('dispose');
    } finally {
      if (identical(_handlerOwner, this)) {
        _channel.setMethodCallHandler(null);
        _handlerOwner = null;
      }
      _resetMediaState();
      _setStatus(PlayerState.stopped, 'Native player disposed');
    }
  });

  Future<void> _serializeLifecycle(Future<void> Function() operation) {
    final next = _lifecycle.then((_) => operation());
    _lifecycle = next.catchError((_) {});
    return next;
  }

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    await _lifecycle;
    _requireInitialized();
    await _invokeNative<void>(method, arguments);
  }

  Future<T?> _invokeNative<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      final code = _nativeCommandFailureCodes.contains(error.code)
          ? error.code
          : 'native_command_error';
      throw PlayerUnavailable(
        _nativeCommandFailureMessage(code),
        failureCode: code,
      );
    }
  }

  void _requireInitialized() {
    if (!_initialized) {
      throw const PlayerUnavailable('The native player is not initialized.');
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'event') return;
    if (call.arguments is! Map) return;
    final event = Map<Object?, Object?>.from(call.arguments as Map);
    if (event['type'] == 'stopResult') {
      final pending = _pendingStop;
      if (pending == null ||
          event['stopId'] != pending.$1 ||
          pending.$2.isCompleted) {
        return;
      }
      if (event['success'] == true) {
        pending.$2.complete();
      } else {
        pending.$2.completeError(
          const PlayerUnavailable(
            'Native playback could not be stopped.',
            failureCode: 'stop_failed',
          ),
        );
      }
      return;
    }
    if (!_isCurrentLoadEvent(event)) return;
    switch (event['type']) {
      case 'state':
        _handleState(event);
      case 'property':
        _handleProperty(event['name'] as String?, event['value']);
    }
  }

  bool _isCurrentLoadEvent(Map<Object?, Object?> event) {
    final loadId = event['loadId'];
    return loadId is int && loadId == _activeLoadId;
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
    final failureCode = event['failureCode'] is String
        ? _normalizedPlaybackFailureCode(event['failureCode'] as String)
        : null;
    final message = failureCode != null
        ? _nativeFailureMessage(event, failureCode)
        : event['message'] as String? ?? state.name;
    _setStatus(
      state,
      message,
      recoverable: state == PlayerState.error,
      failureCode: failureCode,
      httpStatus: event['httpStatus'] is int
          ? event['httpStatus'] as int
          : null,
    );
    if (state == PlayerState.playing) {
      final pending = _pendingLoad;
      if (pending != null && !pending.isCompleted) pending.complete();
    } else if (state == PlayerState.error) {
      _completePendingLoadError(
        PlayerUnavailable(
          message,
          failureCode: failureCode ?? 'native_playback_error',
        ),
      );
    }
  }

  static String _normalizedPlaybackFailureCode(String code) =>
      _nativePlaybackFailureCodes.contains(code) ? code : 'native_error';

  String _nativeFailureMessage(
    Map<Object?, Object?> event,
    String failureCode,
  ) => switch (failureCode) {
    'http_error' when event['httpStatus'] is int =>
      'Media server returned HTTP ${event['httpStatus']}',
    'http_error' => 'Media server rejected the request',
    'network_error' => 'Media server connection failed',
    'audio_decode_error' => 'Audio decoding failed',
    'video_decode_error' => 'Video decoding failed',
    'audio_output_error' => 'Audio output could not start',
    'video_output_error' => 'Video output could not start',
    'source_open_error' => 'Media source could not be opened',
    'container_error' => 'Media container could not be read',
    'correlation_error' => 'Media load tracking failed',
    'command_error' => 'Media player command failed',
    'event_queue_overflow' => 'Media player event queue overflowed',
    'mpv_error' when event['message'] is String => event['message'] as String,
    _ => 'Media playback failed',
  };

  static String _nativeCommandFailureMessage(String code) => switch (code) {
    'required_engine_unavailable' =>
      'The required Windows video engine is unavailable.',
    'initialize_failed' => 'The native player could not initialize.',
    'dispose_in_progress' => 'The native player is shutting down.',
    'not_initialized' => 'The native player is not initialized.',
    'invalid_argument' => 'The native player rejected a command.',
    'insecure_media_uri' => 'Authenticated Plex media requires HTTPS.',
    'command_queue_full' => 'The native player is busy. Try again.',
    'window_error' => 'The playback window could not be updated.',
    _ => 'The native player command failed.',
  };

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
        _tracks = List.unmodifiable(_decodeTracks(value));
      case 'video-format':
        _telemetry = _copyTelemetry(videoFormat: value);
      case 'video-codec':
        _telemetry = _copyTelemetry(videoCodec: value);
      case 'current-vo':
        _telemetry = _copyTelemetry(videoOutput: value);
      case 'hwdec-current':
        _telemetry = _copyTelemetry(hardwareDecoder: value);
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
    if (value == null) {
      _telemetry = _copyTelemetry(
        width: null,
        height: null,
        pixelFormat: null,
        hardwarePixelFormat: null,
        primaries: null,
        gamma: null,
        colorMatrix: null,
        signalPeak: null,
      );
      return;
    }
    if (value is! Map) return;
    final parameters = Map<Object?, Object?>.from(value);
    final width = parameters['w'];
    final height = parameters['h'];
    final pixelFormat = parameters['pixelformat'];
    final hardwarePixelFormat = parameters['hw-pixelformat'];
    final primaries = parameters['primaries'];
    final gamma = parameters['gamma'];
    final colorMatrix = parameters['colormatrix'];
    final signalPeak = parameters['sig-peak'];
    if ((width != null && width is! int) ||
        (height != null && height is! int) ||
        (pixelFormat != null && pixelFormat is! String) ||
        (hardwarePixelFormat != null && hardwarePixelFormat is! String) ||
        (primaries != null && primaries is! String) ||
        (gamma != null && gamma is! String) ||
        (colorMatrix != null && colorMatrix is! String) ||
        (signalPeak != null && signalPeak is! num)) {
      return;
    }
    _telemetry = _copyTelemetry(
      width: width,
      height: height,
      pixelFormat: pixelFormat,
      hardwarePixelFormat: hardwarePixelFormat,
      primaries: primaries,
      gamma: gamma,
      colorMatrix: colorMatrix,
      signalPeak: signalPeak,
    );
  }

  PlayerTelemetry _copyTelemetry({
    Object? videoOutput = _unchanged,
    Object? hardwareDecoder = _unchanged,
    Object? videoCodec = _unchanged,
    Object? videoFormat = _unchanged,
    Object? width = _unchanged,
    Object? height = _unchanged,
    Object? pixelFormat = _unchanged,
    Object? hardwarePixelFormat = _unchanged,
    Object? primaries = _unchanged,
    Object? gamma = _unchanged,
    Object? colorMatrix = _unchanged,
    Object? signalPeak = _unchanged,
  }) {
    return PlayerTelemetry(
      videoOutput: videoOutput == _unchanged
          ? _telemetry.videoOutput
          : videoOutput as String?,
      hardwareDecoder: hardwareDecoder == _unchanged
          ? _telemetry.hardwareDecoder
          : hardwareDecoder as String?,
      videoCodec: videoCodec == _unchanged
          ? _telemetry.videoCodec
          : videoCodec as String?,
      videoFormat: videoFormat == _unchanged
          ? _telemetry.videoFormat
          : videoFormat as String?,
      width: width == _unchanged ? _telemetry.width : width as int?,
      height: height == _unchanged ? _telemetry.height : height as int?,
      pixelFormat: pixelFormat == _unchanged
          ? _telemetry.pixelFormat
          : pixelFormat as String?,
      hardwarePixelFormat: hardwarePixelFormat == _unchanged
          ? _telemetry.hardwarePixelFormat
          : hardwarePixelFormat as String?,
      primaries: primaries == _unchanged
          ? _telemetry.primaries
          : primaries as String?,
      gamma: gamma == _unchanged ? _telemetry.gamma : gamma as String?,
      colorMatrix: colorMatrix == _unchanged
          ? _telemetry.colorMatrix
          : colorMatrix as String?,
      signalPeak: signalPeak == _unchanged
          ? _telemetry.signalPeak
          : (signalPeak as num?)?.toDouble(),
    );
  }

  static const Object _unchanged = Object();

  void _completePendingLoadError(Object error) {
    final pending = _pendingLoad;
    if (pending != null && !pending.isCompleted) pending.completeError(error);
  }

  void _resetMediaState() {
    _position = Duration.zero;
    _duration = Duration.zero;
    _telemetry = const PlayerTelemetry();
    _tracks = const [];
  }

  void _setStatus(
    PlayerState state,
    String message, {
    bool recoverable = false,
    String? failureCode,
    int? httpStatus,
  }) {
    _status = PlayerStatus(
      state: state,
      message: message,
      recoverable: recoverable,
      failureCode: failureCode,
      httpStatus: httpStatus,
    );
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
        generation: _activeGeneration,
      ),
    );
  }
}
