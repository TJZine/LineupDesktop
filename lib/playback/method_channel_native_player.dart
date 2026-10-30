import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'native_player.dart';

class MethodChannelNativePlayer implements NativePlayer {
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
  static MethodChannelNativePlayer? _handlerOwner;

  MethodChannelNativePlayer({
    Duration? loadTimeout,
    Duration? stopTimeout,
    Duration? trackTimeout,
  }) : _loadTimeout = loadTimeout ?? const Duration(seconds: 30),
       _stopTimeout = stopTimeout ?? const Duration(seconds: 10),
       _trackTimeout = trackTimeout ?? const Duration(seconds: 5);

  final _subtitleCues = ValueNotifier<SubtitleCues>(const SubtitleCues.empty());
  @override
  ValueListenable<SubtitleCues> get subtitleCues => _subtitleCues;

  @override
  Future<void> setSubtitlePresentation({
    required double scale,
    required double imageRaise,
    required bool lineupDrawsStyled,
  }) {
    if (!scale.isFinite ||
        scale < 0.25 ||
        scale > 4 ||
        !imageRaise.isFinite ||
        imageRaise < 0 ||
        imageRaise > 0.25) {
      return Future.error(
        const PlayerUnavailable(
          "Invalid subtitle presentation.",
          failureCode: "invalid_argument",
        ),
      );
    }
    return _invoke("setSubtitlePresentation", {
      "scale": scale,
      "imageRaise": imageRaise,
      "lineupDrawsStyled": lineupDrawsStyled,
    });
  }

  final _events = StreamController<PlayerEvent>.broadcast(sync: true);
  final _displayReports = StreamController<DisplayMatchingReport>.broadcast(
    sync: true,
  );
  final _fullscreenChanges = StreamController<bool>.broadcast(sync: true);
  bool _fullscreen = false;
  // Lifecycle, observed selection and requested Off are separate facts. Until
  // the first track snapshot, a valid current cue can establish display content.
  bool _subtitleCuesActive = false;
  bool _subtitleTracksObserved = false;
  int? _subtitleTrackId;
  int? _subtitleCueTrackId;
  bool _subtitleSelectionPending = false;
  bool _subtitleOffRequested = false;
  int _subtitleSelectionRevision = 0;
  SubtitleCues _latestSubtitleCues = const SubtitleCues.empty();
  int _nativeEventEpoch = 0;
  final Duration _loadTimeout;
  final Duration _stopTimeout;
  final Duration _trackTimeout;
  int _nextStopId = 0;
  int _nextTrackRequestId = 0;
  (int, Completer<void>)? _pendingStop;
  final Map<int, (int, Completer<void>)> _pendingTrackSelections = {};
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
  PlayerCapabilities _capabilities = const PlayerCapabilities.unavailable();
  bool _paused = false;
  int _displayRevision = 0;
  DisplayMatchingReport _displayReport = const DisplayMatchingReport.initial();

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
  DisplayMatchingReport get displayReport => _displayReport;

  @override
  Stream<PlayerEvent> get events => _events.stream;

  @override
  Stream<DisplayMatchingReport> get displayReports => _displayReports.stream;

  @override
  bool get fullscreen => _fullscreen;

  @override
  PlayerCapabilities get capabilities => _capabilities;

  @override
  Stream<bool> get fullscreenChanges => _fullscreenChanges.stream;

  @override
  Future<void> initialize() => _serializeLifecycle(() async {
    if (_initialized) return;
    _capabilities = const PlayerCapabilities.unavailable();
    _displayRevision = 0;
    _displayReport = const DisplayMatchingReport.initial();
    if (_handlerOwner != null && !identical(_handlerOwner, this)) {
      throw const PlayerUnavailable(
        'Another native player already owns the platform channel.',
      );
    }
    _handlerOwner = this;
    _fullscreen = false;
    final eventEpoch = ++_nativeEventEpoch;
    _channel.setMethodCallHandler((call) async {
      if (eventEpoch != _nativeEventEpoch) return;
      await _handleNativeCall(call);
    });
    try {
      final reply = await _invokeNative<Object?>('initialize');
      try {
        _capabilities = _decodeCapabilities(reply);
        if (kDebugMode) {
          debugPrint(
            'LineupPlayer initialize_reply '
            'displayMatching=${_capabilities.displayMatching} '
            'fullscreen=${_capabilities.fullscreen.name}',
          );
        }
      } catch (error, stackTrace) {
        await _bestEffortInitializationDispose();
        Error.throwWithStackTrace(error, stackTrace);
      }
    } catch (_) {
      _capabilities = const PlayerCapabilities.unavailable();
      _fullscreen = false;
      ++_nativeEventEpoch;
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
  Future<void> load(
    Uri media, {
    String? plexToken,
    int? generation,
    bool startPaused = false,
    Duration? startPosition,
  }) async {
    if (startPosition != null && startPosition < Duration.zero) {
      throw const PlayerUnavailable(
        'The initial playback position must be non-negative.',
        failureCode: 'invalid_argument',
      );
    }
    if (plexToken != null &&
        (media.scheme.toLowerCase() != 'https' ||
            !media.hasAuthority ||
            media.host.isEmpty)) {
      throw const PlayerUnavailable(
        'Authenticated Plex media requires HTTPS.',
        failureCode: 'insecure_media_uri',
      );
    }
    _retireSubtitleCues();
    await _lifecycle;
    await _stopOperation;
    _requireInitialized();
    final loadId = ++_nextLoadId;
    final pending = Completer<void>();
    _completePendingTrackSelectionErrors(
      const PlayerUnavailable(
        'A newer media load replaced this track request.',
      ),
    );
    _completePendingLoadError(
      const PlayerUnavailable('A newer media load replaced this request.'),
    );
    _pendingLoad = pending;
    _activeLoadId = loadId;
    _activeGeneration = generation;
    _resetMediaState(startPaused: startPaused);
    _subtitleCuesActive = true;
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
        'startPaused': startPaused,
        if (startPosition != null)
          'startSeconds':
              startPosition.inMicroseconds / Duration.microsecondsPerSecond,
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
  Future<void> setDisplayMatching(DisplayMatchingRequest request) async {
    if (request.revision < 0) {
      throw ArgumentError.value(request.revision, 'revision');
    }
    await _lifecycle;
    _requireInitialized();
    if (request.revision <= _displayRevision) return;
    _displayRevision = request.revision;
    await _invokeNative<void>('setDisplayMatching', request.toJson());
  }

  @override
  Future<void> play() => _invoke('play');

  @override
  Future<void> pause() => _invoke('pause');

  @override
  Future<void> seek(Duration position, {SeekMode mode = SeekMode.exact}) =>
      _invoke('seek', {
        'seconds': position.inMicroseconds / Duration.microsecondsPerSecond,
        'mode': mode.name,
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
  Future<void> selectTrack(PlayerTrackType type, int? id) async {
    final subtitleRevision = type == PlayerTrackType.subtitle
        ? ++_subtitleSelectionRevision
        : null;
    final requestedLoad = _activeLoadId;
    if (subtitleRevision != null) {
      _subtitleOffRequested = id == null;
      _subtitleSelectionPending = true;
      // Hide the public cue while retaining its native snapshot for rejection.
      _hideSubtitleCues();
    }
    try {
      await _lifecycle;
      _requireInitialized();
      final loadId = _activeLoadId;
      if (loadId == null) {
        throw const PlayerUnavailable('No active media is available.');
      }
      final requestId = ++_nextTrackRequestId;
      final pending = Completer<void>();
      _pendingTrackSelections[requestId] = (loadId, pending);
      final completion = pending.future
          .timeout(
            _trackTimeout,
            onTimeout: () => throw const PlayerUnavailable(
              'Native track selection did not complete in time.',
              failureCode: 'wait_timeout',
            ),
          )
          .then<(Object, StackTrace)?>(
            (_) => null,
            onError: (Object error, StackTrace stackTrace) =>
                (error, stackTrace),
          );
      try {
        await _invokeNative<void>('selectTrack', {
          'type': type.name,
          'id': id,
          'loadId': loadId,
          'requestId': requestId,
        });
        final failure = await completion;
        if (failure != null) {
          Error.throwWithStackTrace(failure.$1, failure.$2);
        }
        if (subtitleRevision == _subtitleSelectionRevision) {
          _subtitleSelectionPending = false;
          if (id == null) _clearSubtitleCues();
        }
      } catch (error, stackTrace) {
        if (!pending.isCompleted) pending.completeError(error, stackTrace);
        rethrow;
      } finally {
        if (identical(_pendingTrackSelections[requestId]?.$2, pending)) {
          _pendingTrackSelections.remove(requestId);
        }
      }
    } catch (_) {
      if (subtitleRevision != null &&
          subtitleRevision == _subtitleSelectionRevision &&
          requestedLoad == _activeLoadId &&
          _subtitleCuesActive) {
        // Rejection did not change the observed selection. A later subtitle
        // request or retired load owns its own fence and cannot be undone here.
        _subtitleOffRequested = false;
        _subtitleSelectionPending = false;
        _reconcileSubtitleCues();
      }
      rethrow;
    }
  }

  @override
  Future<void> setVolume(double volume) =>
      _invoke('setVolume', {'volume': volume});

  @override
  Future<void> stop() {
    _retireSubtitleCues();
    final existing = _stopOperation;
    if (existing != null) return existing;
    final stopId = ++_nextStopId;
    final pending = Completer<void>();
    _pendingStop = (stopId, pending);
    _completePendingLoadError(
      const PlayerUnavailable('The media load was stopped.'),
    );
    _completePendingTrackSelectionErrors(
      const PlayerUnavailable('The media load was stopped.'),
    );
    _pendingLoad = null;
    _activeLoadId = null;
    _activeGeneration = null;
    Future<void> performStop() async {
      final completion = pending.future.then<Object?>(
        (_) => null,
        onError: (Object error) => error,
      );
      await _invoke('stop', {'stopId': stopId});
      final failure = await completion;
      // The completion future intentionally carries only the failure value.
      // ignore: only_throw_errors
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
  Future<void> dispose() {
    _retireSubtitleCues();
    return _serializeLifecycle(() async {
      _capabilities = const PlayerCapabilities.unavailable();
      _fullscreen = false;
      ++_nativeEventEpoch;
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
      _completePendingTrackSelectionErrors(
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
  }

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

  Future<void> _bestEffortInitializationDispose() async {
    try {
      await _invokeNative<void>('dispose');
    } catch (_) {
      // Initialization already failed validation. Teardown is best effort so
      // the Dart handler can still retire this native lifetime.
    }
  }

  static PlayerCapabilities _decodeCapabilities(Object? reply) {
    final hostDefaults = PlayerCapabilities.forHost(defaultTargetPlatform);
    if (reply is! Map) return hostDefaults;
    final result = Map<Object?, Object?>.from(reply);
    if (!result.containsKey('capabilities')) return hostDefaults;
    final raw = result['capabilities'];
    if (raw is! Map) {
      throw const PlayerUnavailable(
        'The native player returned malformed capabilities.',
        failureCode: 'initialize_failed',
      );
    }
    final capabilities = Map<Object?, Object?>.from(raw);
    final displayMatching = capabilities['displayMatching'];
    final fullscreen = switch (capabilities['fullscreen']) {
      'window' => PlayerFullscreenMode.window,
      'systemBars' => PlayerFullscreenMode.systemBars,
      'fixed' => PlayerFullscreenMode.fixed,
      _ => null,
    };
    if (displayMatching is! bool || fullscreen == null) {
      throw const PlayerUnavailable(
        'The native player returned malformed capabilities.',
        failureCode: 'initialize_failed',
      );
    }
    return PlayerCapabilities(
      displayMatching: displayMatching,
      fullscreen: fullscreen,
    );
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
    if (event['type'] == 'fullscreen') {
      final observed = event['fullscreen'];
      // The current owner includes initialization. The captured handler epoch
      // rejects callbacks from disposed/failed lifetimes before reaching here.
      if (!identical(_handlerOwner, this) || observed is! bool) {
        return;
      }
      _fullscreen = observed;
      if (!_fullscreenChanges.isClosed) _fullscreenChanges.add(observed);
      return;
    }
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
    if (event['type'] == 'trackResult') {
      final requestId = event['requestId'];
      final pending = requestId is int
          ? _pendingTrackSelections[requestId]
          : null;
      if (pending == null ||
          event['loadId'] != pending.$1 ||
          pending.$2.isCompleted) {
        return;
      }
      if (event['success'] == true) {
        pending.$2.complete();
      } else {
        pending.$2.completeError(
          const PlayerUnavailable(
            'Native track selection failed.',
            failureCode: 'command_error',
          ),
        );
      }
      return;
    }
    if (event['type'] == 'display') {
      final report = DisplayMatchingReport.tryParse(event);
      if (report == null || report.revision != _displayRevision) return;
      _displayReport = report;
      if (!_displayReports.isClosed) _displayReports.add(report);
      return;
    }
    if (event["type"] == "property" && event["name"] == "subtitle-cues") {
      if (!_isCurrentLoadEvent(event)) {
        _clearSubtitleCues();
        return;
      }
      if (!_subtitleCuesActive) return;
      final cues = SubtitleCues.tryParse(event["value"]);
      if (cues == null) {
        debugPrint("Malformed subtitle cues dropped.");
      } else {
        // Queue coalescing may deliver a current cue before the selected track
        // snapshot. Retain only this bounded latest value until reconciliation.
        _latestSubtitleCues = cues;
        // A cue received during selection may precede its track snapshot.
        // Otherwise it belongs to the currently observed selected track.
        _subtitleCueTrackId = _subtitleSelectionPending
            ? null
            : _subtitleTrackId;
        _reconcileSubtitleCues();
      }
      return;
    }
    if (!_isCurrentLoadEvent(event)) return;
    switch (event['type']) {
      case 'state':
        _handleState(event);
      case 'property':
        final name = event['name'];
        if (name is! String) return;
        _handleProperty(name, event['value']);
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
      'ended' => PlayerState.ended,
      'stopped' => PlayerState.stopped,
      'error' => PlayerState.error,
      _ => PlayerState.idle,
    };
    if (state == PlayerState.playing && event['paused'] is bool) {
      _paused = event['paused']! as bool;
    }
    final failureCode = switch (event['failureCode']) {
      final String code => _normalizedPlaybackFailureCode(code),
      _ => null,
    };
    final message = failureCode != null
        ? _nativeFailureMessage(event, failureCode)
        : switch (event['message']) {
            final String message => message,
            _ => state.name,
          };
    _setStatus(
      state == PlayerState.playing && _paused ? PlayerState.paused : state,
      state == PlayerState.playing && _paused ? 'Paused' : message,
      recoverable: state == PlayerState.error,
      failureCode: failureCode,
      httpStatus: switch (event['httpStatus']) {
        final int status => status,
        _ => null,
      },
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
    'http_error' => switch (event['httpStatus']) {
      final int status => 'Media server returned HTTP $status',
      _ => 'Media server rejected the request',
    },
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
    'mpv_error' => switch (event['message']) {
      final String message => message,
      _ => 'Media playback failed',
    },
    _ => 'Media playback failed',
  };

  static String _nativeCommandFailureMessage(String code) => switch (code) {
    'required_engine_unavailable' =>
      'The required video engine is unavailable.',
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
        _paused = value == true;
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
        final selectedSubtitle = _tracks
            .where((t) => t.type == PlayerTrackType.subtitle && t.selected)
            .firstOrNull;
        _subtitleTracksObserved = true;
        _subtitleTrackId = selectedSubtitle?.id;
        if (_subtitleTrackId == null) {
          _subtitleOffRequested = false;
          _clearSubtitleCues();
        } else if (_subtitleCueTrackId != null &&
            _subtitleCueTrackId != _subtitleTrackId) {
          // A pre-request cue cannot migrate to a different observed track.
          _clearSubtitleCues();
        } else {
          _subtitleCueTrackId = _subtitleTrackId;
          _reconcileSubtitleCues();
        }
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
      case 'video-target-params':
        _applyVideoTargetParameters(value);
    }
    _emit(tracksUpdated: name == 'track-list' && value is List);
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
    final selected = item['selected'];
    if (id is! int || id <= 0 || type == null || selected is! bool) {
      return null;
    }
    final channelCount = item['demux-channel-count'];
    return PlayerTrack(
      id: id,
      type: type,
      selected: selected,
      title: switch (item['title']) {
        final String value => value,
        _ => null,
      },
      language: switch (item['lang']) {
        final String value => value,
        _ => null,
      },
      codec: switch (item['codec']) {
        final String value => value,
        _ => null,
      },
      channelCount: channelCount is int && channelCount > 0
          ? channelCount
          : null,
      channelLayout: switch (item['demux-channels']) {
        final String value => value,
        _ => null,
      },
      forced: switch (item['forced']) {
        final bool value => value,
        _ => null,
      },
      external: switch (item['external']) {
        final bool value => value,
        _ => null,
      },
      hearingImpaired: switch (item['hearing-impaired']) {
        final bool value => value,
        _ => null,
      },
      visualImpaired: switch (item['visual-impaired']) {
        final bool value => value,
        _ => null,
      },
      commentary: switch (item['commentary']) {
        final bool value => value,
        _ => null,
      },
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

  void _applyVideoTargetParameters(Object? value) {
    if (value == null) {
      _telemetry = _copyTelemetry(
        targetGamma: null,
        targetPrimaries: null,
        targetPixelFormat: null,
      );
      return;
    }
    if (value is! Map) return;
    final parameters = Map<Object?, Object?>.from(value);
    final gamma = parameters['gamma'];
    final primaries = parameters['primaries'];
    final pixelFormat = parameters['pixelformat'];
    if ((gamma != null && gamma is! String) ||
        (primaries != null && primaries is! String) ||
        (pixelFormat != null && pixelFormat is! String)) {
      return;
    }
    _telemetry = _copyTelemetry(
      targetGamma: _normalizedVideoFact(gamma),
      targetPrimaries: _normalizedVideoFact(primaries),
      targetPixelFormat: _normalizedVideoFact(pixelFormat),
    );
  }

  static String? _normalizedVideoFact(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty ? null : normalized;
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
    Object? targetGamma = _unchanged,
    Object? targetPrimaries = _unchanged,
    Object? targetPixelFormat = _unchanged,
    Object? colorMatrix = _unchanged,
    Object? signalPeak = _unchanged,
  }) {
    bool validString(Object? value) =>
        value == _unchanged || value == null || value is String;
    bool validInt(Object? value) =>
        value == _unchanged || value == null || value is int;
    bool validNumber(Object? value) =>
        value == _unchanged || value == null || value is num;
    if (![
      videoOutput,
      hardwareDecoder,
      videoCodec,
      videoFormat,
      pixelFormat,
      hardwarePixelFormat,
      primaries,
      gamma,
      targetGamma,
      targetPrimaries,
      targetPixelFormat,
      colorMatrix,
    ].every(validString)) {
      return _telemetry;
    }
    if (![width, height].every(validInt) || !validNumber(signalPeak)) {
      return _telemetry;
    }
    return PlayerTelemetry(
      videoOutput: videoOutput == _unchanged
          ? _telemetry.videoOutput
          : videoOutput is String
          ? videoOutput
          : null,
      hardwareDecoder: hardwareDecoder == _unchanged
          ? _telemetry.hardwareDecoder
          : hardwareDecoder is String
          ? hardwareDecoder
          : null,
      videoCodec: videoCodec == _unchanged
          ? _telemetry.videoCodec
          : videoCodec is String
          ? videoCodec
          : null,
      videoFormat: videoFormat == _unchanged
          ? _telemetry.videoFormat
          : videoFormat is String
          ? videoFormat
          : null,
      width: width == _unchanged
          ? _telemetry.width
          : width is int
          ? width
          : null,
      height: height == _unchanged
          ? _telemetry.height
          : height is int
          ? height
          : null,
      pixelFormat: pixelFormat == _unchanged
          ? _telemetry.pixelFormat
          : pixelFormat is String
          ? pixelFormat
          : null,
      hardwarePixelFormat: hardwarePixelFormat == _unchanged
          ? _telemetry.hardwarePixelFormat
          : hardwarePixelFormat is String
          ? hardwarePixelFormat
          : null,
      primaries: primaries == _unchanged
          ? _telemetry.primaries
          : primaries is String
          ? primaries
          : null,
      gamma: gamma == _unchanged
          ? _telemetry.gamma
          : gamma is String
          ? gamma
          : null,
      targetGamma: targetGamma == _unchanged
          ? _telemetry.targetGamma
          : targetGamma is String
          ? targetGamma
          : null,
      targetPrimaries: targetPrimaries == _unchanged
          ? _telemetry.targetPrimaries
          : targetPrimaries is String
          ? targetPrimaries
          : null,
      targetPixelFormat: targetPixelFormat == _unchanged
          ? _telemetry.targetPixelFormat
          : targetPixelFormat is String
          ? targetPixelFormat
          : null,
      colorMatrix: colorMatrix == _unchanged
          ? _telemetry.colorMatrix
          : colorMatrix is String
          ? colorMatrix
          : null,
      signalPeak: signalPeak == _unchanged
          ? _telemetry.signalPeak
          : signalPeak is num
          ? signalPeak.toDouble()
          : null,
    );
  }

  static const Object _unchanged = Object();

  void _completePendingLoadError(Object error) {
    final pending = _pendingLoad;
    if (pending != null && !pending.isCompleted) pending.completeError(error);
  }

  void _completePendingTrackSelectionErrors(Object error) {
    final pending = _pendingTrackSelections.values.toList(growable: false);
    _pendingTrackSelections.clear();
    for (final selection in pending) {
      if (!selection.$2.isCompleted) selection.$2.completeError(error);
    }
  }

  void _retireSubtitleCues() {
    _subtitleCuesActive = false;
    ++_subtitleSelectionRevision;
    _subtitleOffRequested = false;
    _subtitleTracksObserved = false;
    _subtitleTrackId = null;
    _subtitleSelectionPending = false;
    _clearSubtitleCues();
  }

  void _reconcileSubtitleCues() {
    if (!_subtitleSelectionPending) _subtitleCueTrackId ??= _subtitleTrackId;
    _subtitleCues.value =
        _subtitleCuesActive &&
            (!_subtitleTracksObserved || _subtitleTrackId != null) &&
            !_subtitleOffRequested
        ? _latestSubtitleCues
        : const SubtitleCues.empty();
  }

  void _clearSubtitleCues() {
    _latestSubtitleCues = const SubtitleCues.empty();
    _subtitleCueTrackId = null;
    _hideSubtitleCues();
  }

  void _hideSubtitleCues() {
    if (!_subtitleCues.value.isEmpty) {
      _subtitleCues.value = const SubtitleCues.empty();
    }
  }

  void _resetMediaState({bool startPaused = false}) {
    _clearSubtitleCues();
    _subtitleTracksObserved = false;
    _subtitleTrackId = null;
    _subtitleOffRequested = false;
    _subtitleSelectionPending = false;
    _paused = startPaused;
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
    if (const {
      PlayerState.error,
      PlayerState.ended,
      PlayerState.stopped,
    }.contains(state)) {
      _retireSubtitleCues();
    }
    _status = PlayerStatus(
      state: state,
      message: message,
      recoverable: recoverable,
      failureCode: failureCode,
      httpStatus: httpStatus,
    );
    _emit();
  }

  void _emit({bool tracksUpdated = false}) {
    if (_events.isClosed) return;
    _events.add(
      PlayerEvent(
        status: _status,
        position: _position,
        duration: _duration,
        telemetry: _telemetry,
        tracks: _tracks,
        tracksUpdated: tracksUpdated,
        generation: _activeGeneration,
      ),
    );
  }
}
