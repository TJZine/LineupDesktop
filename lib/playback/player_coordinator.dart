import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app/lineup_controller.dart';
import '../channels/channel.dart';
import '../guide/guide_controller.dart';
import '../plex/plex_models.dart';
import 'native_player.dart';

enum PlayerOverlay {
  none,
  osd,
  nowPlaying,
  miniGuide,
  fullGuide,
  audioTracks,
  subtitleTracks,
  channelNumber,
  error,
}

class PlayerCoordinator extends ChangeNotifier {
  static const _nativeStopTimeout = Duration(seconds: 10);

  PlayerCoordinator({
    required this.player,
    required this.lineup,
    required this.guide,
    this.overlayTimeout,
  }) {
    _indexChannels();
    _status = player.status;
    _position = player.position;
    _duration = player.duration;
    _telemetry = player.telemetry;
    _tracks = player.tracks;
    _contentGeneration = lineup.contentGeneration;
    _osdAutoHideSeconds = lineup.settings.osdAutoHideSeconds;
    _subscription = player.events.listen(_event);
    lineup.addListener(_lineupChanged);
    guide.addListener(_guideChanged);
  }

  final NativePlayer player;
  final LineupController lineup;
  final GuideController guide;
  final Duration? overlayTimeout;
  late PlayerStatus _status;
  late Duration _position;
  late Duration _duration;
  Duration _nativePosition = Duration.zero;
  late PlayerTelemetry _telemetry;
  late List<PlayerTrack> _tracks;
  StreamSubscription<PlayerEvent>? _subscription;
  Timer? _overlayTimer;
  Timer? _sleepTimer;
  Timer? _numberTimer;
  Timer? _cursorTimer;
  int _overlayEpoch = 0;
  int _overlayPresentationGeneration = 0;
  bool _overlayFocusSuspended = false;
  int _sleepEpoch = 0;
  PlayerOverlay _overlay = PlayerOverlay.none;
  String _channelNumber = '';
  String? _miniGuideChannelId;
  String? _error;
  bool _fullscreen = false;
  bool _cursorVisible = true;
  bool _tuning = false;
  bool _canRetry = false;
  Duration? _sleepDuration;
  int _tuneGeneration = 0;
  int _controlGeneration = 0;
  int _seekGeneration = 0;
  int _fullscreenEpoch = 0;
  int _nativeLoadGeneration = 0;
  int? _activeLoadGeneration;
  int? _knownTargetGeneration;
  Duration? _knownLocalTarget;
  int _activePartIndex = 0;
  (int, Future<void>)? _pendingNativeLoad;
  (int, int, Future<LineupPlaybackRequest?>)? _pendingSeekPart;
  final Map<int, Duration> _partDurations = {};
  int? _advancingGeneration;
  int? _nativeReplacementGeneration;
  Future<void> _tuneOperations = Future.value();
  Future<void>? _nativeStopOperation;
  bool _nativeCleanupRequired = false;
  Future<void> _scopeCleanup = Future.value();
  Future<void> _fullscreenOperations = Future.value();
  bool _scopeCleanupPending = false;
  bool _disposed = false;
  bool _initialMediaRequested = false;
  LineupPlaybackRequest? _activePlayback;
  LineupPlaybackRequest? _provisionalPlayback;
  Future<LineupPlaybackRequest>? _authorizationRecovery;
  LineupPlaybackRequest? _authorizationRecoveryRequest;
  int? _authorizationRecoveryGeneration;
  LineupPlaybackRequest? _retryCeilingRequest;
  int? _retryCeilingGeneration;
  Channel? _activeChannel;
  String? _retryChannelId;
  List<Channel> _indexedChannels = const [];
  late int _contentGeneration;
  late int _osdAutoHideSeconds;
  Map<String, int> _channelIndexById = const {};
  Map<int, Channel> _channelByNumber = const {};

  PlayerStatus get status => _status;
  Duration get position => _position;
  Duration get duration => _duration;
  PlayerTelemetry get telemetry => _telemetry;
  List<PlayerTrack> get tracks => _tracks;
  PlayerOverlay get overlay => _overlay;
  int get overlayPresentationGeneration => _overlayPresentationGeneration;
  String get channelNumber => _channelNumber;
  String? get miniGuideChannelId =>
      _miniGuideChannelId ??
      lineup.currentChannelId ??
      lineup.channels.firstOrNull?.id;
  int get miniGuideChannelIndex =>
      _channelIndexById[miniGuideChannelId] ??
      (_indexedChannels.isEmpty ? -1 : 0);
  List<Channel> get miniGuideChannels {
    final channels = _indexedChannels;
    final selected = miniGuideChannelIndex;
    if (channels.isEmpty || selected < 0) return const [];
    final count = channels.length.clamp(0, 5);
    final start = channels.length <= 5
        ? 0
        : (selected - 2 + channels.length) % channels.length;
    return List.generate(
      count,
      (offset) => channels[(start + offset) % channels.length],
      growable: false,
    );
  }

  String? get error => _error;
  bool get fullscreen => _fullscreen;
  bool get cursorVisible => _cursorVisible;
  bool get tuning => _tuning;
  bool get canRetry => _canRetry;
  bool get hasPlaybackIntent =>
      _tuning ||
      _activePlayback != null ||
      switch (_status.state) {
        PlayerState.loading ||
        PlayerState.ready ||
        PlayerState.playing ||
        PlayerState.paused ||
        PlayerState.buffering ||
        PlayerState.seeking => true,
        _ => false,
      };
  Duration? get sleepDuration => _sleepDuration;
  Channel? get currentChannel {
    final index = _channelIndexById[lineup.currentChannelId];
    return index == null ? null : _indexedChannels[index];
  }

  GuideProgram? get currentProgram {
    final id = lineup.currentChannelId;
    return id == null ? null : guide.currentProgram(id);
  }

  GuideProgram? get nextProgram {
    final id = lineup.currentChannelId;
    return id == null ? null : guide.nextProgram(id);
  }

  void _event(PlayerEvent event) {
    if (event.generation != _activeLoadGeneration) return;
    _status = event.status.state == PlayerState.error
        ? PlayerStatus(
            state: PlayerState.error,
            message: 'Playback error',
            recoverable: event.status.recoverable,
            failureCode: event.status.failureCode,
            httpStatus: event.status.httpStatus,
          )
        : event.status;
    if (event.status.state != PlayerState.error ||
        event.position > Duration.zero ||
        _nativePosition == Duration.zero) {
      _nativePosition = event.position;
    }
    final playback = _provisionalPlayback ?? _activePlayback;
    if (playback != null &&
        _activePartIndex < playback.parts.length &&
        _allPartDurationsKnown(playback)) {
      final offset = _partOffset(_activePartIndex)!;
      _position = offset + event.position;
      _duration = _partDurations.values.fold(Duration.zero, (a, b) => a + b);
    } else {
      _position = event.position;
      _duration = event.duration;
    }
    _telemetry = event.telemetry;
    _tracks = event.tracks;
    if (_nativeReplacementGeneration == event.generation &&
        const {
          PlayerState.ready,
          PlayerState.playing,
          PlayerState.paused,
          PlayerState.buffering,
          PlayerState.seeking,
        }.contains(event.status.state)) {
      _nativeReplacementGeneration = null;
    }
    if (event.status.state == PlayerState.error) {
      if (_isAuthorizationFailure(event.status) &&
          _activeLoadGeneration != null &&
          playback != null) {
        final rejectedGeneration = _activeLoadGeneration!;
        final pending = _authorizationRecoveryFor(playback, rejectedGeneration);
        if (pending != null) return;
        final retryCeilingReached =
            identical(playback, _retryCeilingRequest) &&
            rejectedGeneration == _retryCeilingGeneration;
        if (!retryCeilingReached) {
          final rejected = playback;
          final wasActive = identical(rejected, _activePlayback);
          final recover = rejected.authorizationRecovery;
          if (recover != null) {
            _authorizationRecoveryRequest = rejected;
            _authorizationRecoveryGeneration = rejectedGeneration;
            _authorizationRecovery = _recoverAuthorization(
              rejected,
              wasActive,
              _tuneGeneration,
              rejectedGeneration,
              _knownTargetGeneration == rejectedGeneration
                  ? _knownLocalTarget ?? Duration.zero
                  : _nativePosition,
              Future.sync(recover),
            );
            if (wasActive && _knownTargetGeneration != rejectedGeneration) {
              unawaited(
                _settleActiveAuthorization(
                  rejected,
                  rejectedGeneration,
                  _tuneGeneration,
                  _authorizationRecovery!,
                ),
              );
            }
            return;
          }
        }
      }
      final audioCodec = event.tracks
          .where(
            (track) => track.type == PlayerTrackType.audio && track.selected,
          )
          .firstOrNull
          ?.codec;
      lineup.diagnostics.add('playback', 'Native playback failed', {
        'failureCode': event.status.failureCode,
        'httpStatus': event.status.httpStatus,
        'videoCodec': event.telemetry.videoCodec,
        'audioCodec': audioCodec,
        'videoOutput': event.telemetry.videoOutput,
        'hardwareDecoder': event.telemetry.hardwareDecoder,
      });
      unawaited(_stopQuietly());
      _invalidateAuthorizationRecovery();
      _error = 'Playback failed. Retry or choose another channel.';
      _tuning = false;
      _canRetry = event.status.recoverable && _retryChannelId != null;
      _activePlayback = null;
      _provisionalPlayback = null;
      _activeChannel = null;
      _setOverlay(PlayerOverlay.error, timed: false);
    } else {
      switch (event.status.state) {
        case PlayerState.loading:
          _cancelOverlayTimer();
          if (_overlay == PlayerOverlay.osd) {
            _presentOverlay(PlayerOverlay.none);
          }
          break;
        case PlayerState.ready:
        case PlayerState.paused:
        case PlayerState.buffering:
        case PlayerState.seeking:
          if (_overlay != PlayerOverlay.nowPlaying) {
            _setOverlay(PlayerOverlay.osd);
          }
          break;
        case PlayerState.playing:
          if (_overlay == PlayerOverlay.osd) _scheduleOverlayHide(_overlay);
          break;
        case PlayerState.ended:
        case PlayerState.stopped:
          final generation = _activeLoadGeneration;
          final request = _activePlayback;
          if (request == null && playback == null) {
            _activeLoadGeneration = null;
            _cancelOverlayTimer();
            if (_overlay != PlayerOverlay.error) {
              _presentOverlay(PlayerOverlay.none);
            }
            break;
          }
          if (event.status.state == PlayerState.stopped &&
              _nativeReplacementGeneration == generation) {
            _nativeReplacementGeneration = null;
            break;
          }
          if (event.status.state == PlayerState.ended &&
              _nativeReplacementGeneration == generation) {
            _nativeReplacementGeneration = null;
          }
          if (generation != null &&
              request != null &&
              _advancingGeneration != generation) {
            _advancingGeneration = generation;
            if (_partDurations[_activePartIndex] == null &&
                event.duration > Duration.zero) {
              _partDurations[_activePartIndex] = event.duration;
            }
            unawaited(_advancePart(request, generation));
          }
          break;
        case PlayerState.idle:
        case PlayerState.unsupported:
          _cancelOverlayTimer();
          break;
        case PlayerState.error:
          break;
      }
    }
    if (!_disposed) notifyListeners();
  }

  Future<bool> tune(String channelId) {
    final generation = ++_tuneGeneration;
    ++_controlGeneration;
    _invalidateAuthorizationRecovery();
    final nativeStop = _beginNativeStop();
    _tuning = true;
    _canRetry = false;
    _error = null;
    _retryChannelId = channelId;
    _cancelOverlayTimer();
    _presentOverlay(PlayerOverlay.osd);
    notifyListeners();
    final operation = _tuneOperations.then(
      (_) => _performTune(channelId, generation, nativeStop),
    );
    _tuneOperations = operation.then<void>((_) {}).catchError((_) {});
    return operation;
  }

  Future<void> loadInitialMedia(Uri media) async {
    if (_initialMediaRequested) return;
    _initialMediaRequested = true;
    final generation = ++_tuneGeneration;
    ++_controlGeneration;
    try {
      await _load(media);
      if (!_disposed && generation == _tuneGeneration) showOsd();
    } catch (error) {
      if (_disposed || generation != _tuneGeneration) return;
      await _stopQuietly();
      if (_disposed || generation != _tuneGeneration) return;
      _recordPlaybackFailure(error);
      _error = _safePlaybackError(error);
      _canRetry = false;
      _setOverlay(PlayerOverlay.error, timed: false);
    }
  }

  Future<bool> _performTune(
    String channelId,
    int generation,
    Future<void>? nativeStop,
  ) async {
    if (generation != _tuneGeneration) return false;
    if (nativeStop != null) {
      try {
        await nativeStop;
        _status = const PlayerStatus(
          state: PlayerState.stopped,
          message: 'Stopped',
        );
      } catch (error) {
        if (generation != _tuneGeneration) return false;
        _tuning = false;
        _canRetry = true;
        _recordPlaybackFailure(error);
        _error = _safePlaybackError(error);
        _setOverlay(PlayerOverlay.error, timed: false);
        return false;
      }
    }
    if (generation != _tuneGeneration) return false;
    final program = await guide.ensureCurrentProgram(channelId);
    if (generation != _tuneGeneration) return false;
    if (program == null) {
      _tuning = false;
      _canRetry = true;
      _error = 'The current program could not be loaded.';
      _setOverlay(PlayerOverlay.error, timed: false);
      return false;
    }
    LineupPlaybackRequest? request;
    LineupPlaybackRequest? replaced;
    final previousChannelId = lineup.currentChannelId;
    try {
      request = lineup.playbackFor(program.scheduled.item.id);
      replaced = _activePlayback;
      final elapsed = DateTime.now().difference(program.scheduled.start);
      request = await _loadPlayback(
        request,
        generation,
        initialPosition: elapsed > const Duration(seconds: 2) ? elapsed : null,
      );
      _invalidateAuthorizationRecovery();
      if (identical(_activePlayback, replaced)) {
        _activePlayback = null;
        _activeChannel = null;
      }
      if (generation != _tuneGeneration) {
        if (_tuning || _disposed) await _stopQuietly();
        return false;
      }
      _activePlayback = request;
      _provisionalPlayback = null;
      _activeChannel = lineup.channels
          .where((channel) => channel.id == channelId)
          .firstOrNull;
      if (generation != _tuneGeneration) {
        if (identical(_activePlayback, request)) {
          _activePlayback = null;
          _activeChannel = null;
        }
        if (_tuning || _disposed) await _stopQuietly();
        return false;
      }
      if (!identical(_activePlayback, request)) {
        await _stopQuietly();
        return false;
      }
      await lineup.setCurrentChannel(channelId);
      if (generation != _tuneGeneration) {
        if (identical(_activePlayback, request)) _activePlayback = null;
        if (lineup.currentChannelId == channelId &&
            previousChannelId != channelId) {
          await lineup.setCurrentChannel(previousChannelId);
        }
        if (_tuning || _disposed) await _stopQuietly();
        return false;
      }
      if (!identical(_activePlayback, request)) {
        if (lineup.currentChannelId == channelId &&
            previousChannelId != channelId) {
          await lineup.setCurrentChannel(previousChannelId);
        }
        await _stopQuietly();
        return false;
      }
      _tuning = false;
      _canRetry = false;
      _error = null;
      showOsd();
      return !_disposed &&
          generation == _tuneGeneration &&
          identical(_activePlayback, request) &&
          _activeChannel?.id == channelId &&
          lineup.currentChannelId == channelId &&
          !_tuning &&
          _error == null;
    } catch (error) {
      _provisionalPlayback = null;
      _invalidateAuthorizationRecovery();
      if (identical(_activePlayback, request)) {
        _activePlayback = null;
        _activeChannel = null;
      }
      if (identical(_activePlayback, replaced)) {
        _activePlayback = null;
        _activeChannel = null;
      }
      if (request != null) await _stopQuietly();
      if (generation != _tuneGeneration) return false;
      _tuning = false;
      _canRetry = true;
      _recordPlaybackFailure(error);
      _error = _safePlaybackError(error);
      _setOverlay(PlayerOverlay.error, timed: false);
      return false;
    }
  }

  Future<void> retry() async {
    final id = _retryChannelId ?? currentChannel?.id;
    if (id != null) await tune(id);
  }

  Future<void> _load(
    Uri media, {
    String? plexToken,
    Duration? knownLocalTarget,
    LineupPlaybackRequest? retryCeilingRequest,
  }) {
    if (_nativeStopOperation != null) {
      return Future.error(
        const PlayerUnavailable('Playback stop is still pending.'),
      );
    }
    if (retryCeilingRequest == null) _pendingSeekPart = null;
    final generation = ++_nativeLoadGeneration;
    _activeLoadGeneration = generation;
    _nativeCleanupRequired = true;
    _retryCeilingRequest = retryCeilingRequest;
    _retryCeilingGeneration = retryCeilingRequest == null ? null : generation;
    _knownTargetGeneration = knownLocalTarget == null ? null : generation;
    _knownLocalTarget = knownLocalTarget;
    _nativePosition = Duration.zero;
    final load = player.load(
      media,
      plexToken: plexToken,
      generation: generation,
    );
    _pendingNativeLoad = (generation, load);
    // Every seek into this part shares readiness, including part advancement.
    unawaited(
      load.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
        if (_pendingNativeLoad?.$1 == generation) _pendingNativeLoad = null;
      }),
    );
    return load;
  }

  Future<LineupPlaybackRequest> _loadPlayback(
    LineupPlaybackRequest request,
    int tuneGeneration, {
    Duration? initialPosition,
  }) async {
    _provisionalPlayback = request;
    final replacementGeneration = _nativeLoadGeneration + 1;
    if (_activeLoadGeneration != null) {
      _nativeReplacementGeneration = replacementGeneration;
    }
    _partDurations
      ..clear()
      ..addEntries([
        for (var index = 0; index < request.parts.length; index++)
          if (request.parts[index].duration case final duration?)
            MapEntry(index, duration),
      ]);
    final target = initialPosition == null
        ? null
        : _partForPosition(request, initialPosition);
    _activePartIndex = target?.$1 ?? 0;
    final localPosition = target?.$2;
    int? loadGeneration;
    try {
      final load = _load(
        request.parts[_activePartIndex].uri,
        plexToken: request.plexToken,
        knownLocalTarget: localPosition,
      );
      loadGeneration = _activeLoadGeneration;
      await load;
      final recovery = _authorizationRecoveryFor(request, loadGeneration!);
      if (recovery != null) return await recovery;
      if (_disposed || tuneGeneration != _tuneGeneration) return request;
      if (_activeLoadGeneration != loadGeneration ||
          !identical(_provisionalPlayback, request)) {
        throw const PlayerUnavailable('Playback load was superseded.');
      }
      if (localPosition != null && localPosition > Duration.zero) {
        await player.seek(localPosition);
      }
      if (_disposed || tuneGeneration != _tuneGeneration) return request;
      if (_activeLoadGeneration != loadGeneration ||
          !identical(_provisionalPlayback, request)) {
        throw const PlayerUnavailable('Playback load was superseded.');
      }
      if (_knownTargetGeneration == loadGeneration) {
        _knownTargetGeneration = null;
        _knownLocalTarget = null;
      }
      if (localPosition != null) _nativePosition = localPosition;
    } catch (_) {
      final recovery = _authorizationRecoveryFor(request, loadGeneration ?? -1);
      if (recovery == null) rethrow;
      return await recovery;
    }
    return request;
  }

  Future<LineupPlaybackRequest> _recoverAuthorization(
    LineupPlaybackRequest rejected,
    bool wasActive,
    int tuneGeneration,
    int rejectedGeneration,
    Duration localPosition,
    Future<LineupPlaybackRequest> replacement,
  ) async {
    final partIndex = _activePartIndex;
    final next = await replacement;
    if (_disposed ||
        tuneGeneration != _tuneGeneration ||
        _activeLoadGeneration != rejectedGeneration ||
        (wasActive
            ? !identical(_activePlayback, rejected)
            : !identical(_provisionalPlayback, rejected)) ||
        !identical(rejected, _authorizationRecoveryRequest) ||
        rejectedGeneration != _authorizationRecoveryGeneration) {
      throw StateError('Playback request was superseded.');
    }
    _provisionalPlayback = next;
    final nativeReplacementGeneration = _nativeLoadGeneration + 1;
    _nativeReplacementGeneration = nativeReplacementGeneration;
    _activePartIndex = partIndex.clamp(0, next.parts.length - 1);
    final load = _load(
      next.parts[_activePartIndex].uri,
      plexToken: next.plexToken,
      retryCeilingRequest: next,
      knownLocalTarget: _knownTargetGeneration == rejectedGeneration
          ? _knownLocalTarget ?? localPosition
          : localPosition,
    );
    final replacementGeneration = _activeLoadGeneration!;
    await load;
    if (_disposed ||
        tuneGeneration != _tuneGeneration ||
        _activeLoadGeneration != replacementGeneration ||
        !identical(_provisionalPlayback, next) ||
        (wasActive && !identical(_activePlayback, rejected))) {
      throw StateError('Playback request was superseded.');
    }
    final resumePosition = _knownTargetGeneration == replacementGeneration
        ? _knownLocalTarget ?? localPosition
        : localPosition;
    if (resumePosition > Duration.zero) await player.seek(resumePosition);
    if (_disposed ||
        tuneGeneration != _tuneGeneration ||
        _activeLoadGeneration != replacementGeneration ||
        !identical(_provisionalPlayback, next) ||
        (wasActive && !identical(_activePlayback, rejected))) {
      throw StateError('Playback request was superseded.');
    }
    _nativePosition = resumePosition;
    if (wasActive) {
      _activePlayback = next;
      _provisionalPlayback = null;
    }
    return next;
  }

  static bool _isAuthorizationFailure(PlayerStatus status) =>
      status.failureCode == 'http_error' &&
      (status.httpStatus == 401 || status.httpStatus == 403);

  Future<LineupPlaybackRequest>? _authorizationRecoveryFor(
    LineupPlaybackRequest request,
    int generation,
  ) =>
      identical(request, _authorizationRecoveryRequest) &&
          generation == _authorizationRecoveryGeneration
      ? _authorizationRecovery
      : null;

  void _clearAuthorizationRecovery(
    LineupPlaybackRequest request,
    int generation,
  ) {
    if (!identical(request, _authorizationRecoveryRequest) ||
        generation != _authorizationRecoveryGeneration) {
      return;
    }
    _invalidateAuthorizationRecovery();
  }

  void _invalidateAuthorizationRecovery() {
    _authorizationRecovery = null;
    _authorizationRecoveryRequest = null;
    _authorizationRecoveryGeneration = null;
  }

  Future<void> _settleActiveAuthorization(
    LineupPlaybackRequest rejected,
    int rejectedGeneration,
    int tuneGeneration,
    Future<LineupPlaybackRequest> recovery,
  ) async {
    try {
      await recovery;
      _clearAuthorizationRecovery(rejected, rejectedGeneration);
      if (!_disposed) notifyListeners();
    } catch (error) {
      if (!_ownsAuthorizationRecoveryFailure(rejected, rejectedGeneration)) {
        return;
      }
      await _failTransition(error, tuneGeneration);
    }
  }

  bool _ownsAuthorizationRecoveryFailure(
    LineupPlaybackRequest rejected,
    int rejectedGeneration,
  ) {
    if (_authorizationRecoveryFor(rejected, rejectedGeneration) == null ||
        !identical(_activePlayback, rejected)) {
      return false;
    }
    final retryGeneration = _retryCeilingGeneration;
    if (retryGeneration == null) {
      return _activeLoadGeneration == rejectedGeneration;
    }
    return _activeLoadGeneration == retryGeneration &&
        _provisionalPlayback != null &&
        !identical(_provisionalPlayback, rejected);
  }

  bool _allPartDurationsKnown(LineupPlaybackRequest request) =>
      request.parts.length == _partDurations.length;

  Duration? _partOffset(int partIndex) {
    var offset = Duration.zero;
    for (var index = 0; index < partIndex; index++) {
      final duration = _partDurations[index];
      if (duration == null) return null;
      offset += duration;
    }
    return offset;
  }

  (int, Duration)? _partForPosition(
    LineupPlaybackRequest request,
    Duration position,
  ) {
    var remaining = position < Duration.zero ? Duration.zero : position;
    for (var index = 0; index < request.parts.length; index++) {
      final duration = _partDurations[index];
      if (index == request.parts.length - 1) {
        return (
          index,
          duration != null && remaining > duration ? duration : remaining,
        );
      }
      if (duration == null) return null;
      if (remaining < duration) return (index, remaining);
      remaining -= duration;
    }
    return null;
  }

  Future<void> _advancePart(
    LineupPlaybackRequest request,
    int completedGeneration,
  ) async {
    final tuneGeneration = _tuneGeneration;
    if (_disposed ||
        !identical(_activePlayback, request) ||
        _activeLoadGeneration != completedGeneration) {
      if (_advancingGeneration == completedGeneration) {
        _advancingGeneration = null;
      }
      return;
    }
    if (_activePartIndex == request.parts.length - 1) {
      _activeLoadGeneration = null;
      _advancingGeneration = null;
      _activePlayback = null;
      _activeChannel = null;
      _cancelOverlayTimer();
      if (_overlay != PlayerOverlay.error) {
        _presentOverlay(PlayerOverlay.none);
      }
      if (!_disposed) notifyListeners();
      return;
    }
    _activePartIndex++;
    _provisionalPlayback = request;
    final replacementGeneration = _nativeLoadGeneration + 1;
    _nativeReplacementGeneration = replacementGeneration;
    try {
      await _load(
        request.parts[_activePartIndex].uri,
        plexToken: request.plexToken,
      );
      final recovery = _authorizationRecoveryFor(
        request,
        replacementGeneration,
      );
      if (recovery != null) {
        final next = await recovery;
        if (tuneGeneration != _tuneGeneration ||
            !identical(_activePlayback, next)) {
          return;
        }
        _clearAuthorizationRecovery(request, replacementGeneration);
        if (_advancingGeneration == completedGeneration) {
          _advancingGeneration = null;
        }
        if (!_disposed) notifyListeners();
        return;
      }
      if (_disposed ||
          tuneGeneration != _tuneGeneration ||
          !identical(_activePlayback, request) ||
          _activeLoadGeneration != replacementGeneration) {
        return;
      }
    } catch (error) {
      final recovery = _authorizationRecoveryFor(
        request,
        replacementGeneration,
      );
      if (recovery != null) {
        try {
          final next = await recovery;
          if (tuneGeneration != _tuneGeneration ||
              !identical(_activePlayback, next)) {
            return;
          }
          _clearAuthorizationRecovery(request, replacementGeneration);
          if (_advancingGeneration == completedGeneration) {
            _advancingGeneration = null;
          }
          return;
        } catch (recoveryError) {
          if (tuneGeneration != _tuneGeneration ||
              !_ownsAuthorizationRecoveryFailure(
                request,
                replacementGeneration,
              )) {
            return;
          }
          await _failTransition(recoveryError, tuneGeneration);
          return;
        }
      }
      if (tuneGeneration != _tuneGeneration ||
          _activeLoadGeneration != replacementGeneration ||
          !identical(_activePlayback, request) ||
          !identical(_provisionalPlayback, request)) {
        return;
      }
      await _failTransition(error, tuneGeneration);
      return;
    }
    if (identical(_provisionalPlayback, request)) {
      _provisionalPlayback = null;
    }
    if (_advancingGeneration == completedGeneration) {
      _advancingGeneration = null;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _failTransition(Object error, int tuneGeneration) async {
    final nativeStop = _beginNativeStop();
    _invalidateAuthorizationRecovery();
    if (nativeStop != null) {
      try {
        await nativeStop;
      } catch (_) {
        // The transition failure remains the useful error.
      }
    }
    if (_disposed || tuneGeneration != _tuneGeneration) return;
    _recordPlaybackFailure(error);
    _error = _safePlaybackError(error);
    _canRetry = true;
    _setOverlay(PlayerOverlay.error, timed: false);
  }

  Future<void> previousChannel() => _tuneOffset(-1);
  Future<void> nextChannel() => _tuneOffset(1);

  Future<void> _tuneOffset(int offset) async {
    final channels = _indexedChannels;
    if (channels.isEmpty) return;
    final index = _channelIndexById[lineup.currentChannelId] ?? 0;
    final next = ((index < 0 ? 0 : index) + offset) % channels.length;
    await tune(channels[next < 0 ? next + channels.length : next].id);
  }

  Future<void> togglePlayback() =>
      _status.state == PlayerState.playing ? pause() : play();

  Future<void> play() => _runPlaybackControl('play', player.play);

  Future<void> pause() => _runPlaybackControl('pause', player.pause);

  Future<void> stop() async {
    ++_tuneGeneration;
    ++_controlGeneration;
    _tuning = false;
    _canRetry = false;
    _invalidateAuthorizationRecovery();
    final nativeStop = _beginNativeStop(force: true)!;
    if (!_disposed) notifyListeners();
    final operation = _tuneOperations.then((_) async {
      await nativeStop;
      _status = const PlayerStatus(
        state: PlayerState.stopped,
        message: 'Stopped',
      );
    });
    _tuneOperations = operation.catchError((_) {});
    await operation;
  }

  Future<void> requestStop() async {
    final replaceNowPlaying = _overlay == PlayerOverlay.nowPlaying;
    final nowPlayingGeneration = _overlayPresentationGeneration;
    try {
      await stop();
      if (!_disposed &&
          replaceNowPlaying &&
          _overlay == PlayerOverlay.nowPlaying &&
          _overlayPresentationGeneration == nowPlayingGeneration) {
        showOsd();
      }
    } catch (error) {
      if (_disposed) return;
      _recordPlaybackFailure(error);
      _error =
          'Playback could not be stopped. Retry or choose another channel.';
      _canRetry = _retryChannelId != null;
      _setOverlay(PlayerOverlay.error, timed: false);
    }
  }

  Future<bool> logout() async {
    if (!await lineup.logout()) return false;
    await _scopeCleanup;
    return true;
  }

  Future<void> seekBy(Duration offset) {
    final requested = _position + offset;
    final target = requested < Duration.zero
        ? Duration.zero
        : _duration > Duration.zero && requested > _duration
        ? _duration
        : requested;
    return seekTo(target);
  }

  Future<void> seekTo(Duration position) async {
    final seekGeneration = ++_seekGeneration;
    final tuneGeneration = _tuneGeneration;
    var playback = _activePlayback;
    final target = playback == null
        ? null
        : _partForPosition(playback, position);
    final changingPart =
        playback != null && target != null && target.$1 != _activePartIndex;
    final pending = _pendingNativeLoad;
    final shared = _pendingSeekPart;
    final sharedReadiness =
        shared != null && shared.$1 == target?.$1 && shared.$2 == tuneGeneration
        ? shared.$3
        : null;
    if (playback != null &&
        target != null &&
        (changingPart ||
            (pending != null && pending.$1 == _activeLoadGeneration) ||
            sharedReadiness != null ||
            _authorizationRecovery != null)) {
      final previousGeneration = _activeLoadGeneration;
      _advancingGeneration = previousGeneration;
      final replacementGeneration = changingPart
          ? _nativeLoadGeneration + 1
          : _authorizationRecoveryGeneration ?? _activeLoadGeneration!;
      if (changingPart) {
        _activePartIndex = target.$1;
        _nativeReplacementGeneration = replacementGeneration;
      }
      _knownTargetGeneration = changingPart
          ? replacementGeneration
          : _activeLoadGeneration;
      _knownLocalTarget = target.$2;
      try {
        final load = changingPart
            ? _load(
                playback.parts[_activePartIndex].uri,
                plexToken: playback.plexToken,
                knownLocalTarget: target.$2,
              )
            : pending?.$2 ?? Future<void>.value();
        final rejected = playback;
        final readiness =
            sharedReadiness ??
            _awaitSeekPart(
              rejected,
              replacementGeneration,
              tuneGeneration,
              load,
            );
        _pendingSeekPart = (target.$1, tuneGeneration, readiness);
        try {
          playback = await readiness;
        } finally {
          if (identical(_pendingSeekPart?.$3, readiness)) {
            _pendingSeekPart = null;
          }
        }
        if (!_ownsSeek(seekGeneration, tuneGeneration) ||
            playback == null ||
            !identical(_activePlayback, playback)) {
          return;
        }
        final generation = _activeLoadGeneration;
        if (generation == null) return;
        if (_nativePosition != target.$2) await player.seek(target.$2);
        if (!_ownsSeek(seekGeneration, tuneGeneration) ||
            !identical(_activePlayback, playback) ||
            _activeLoadGeneration != generation) {
          return;
        }
        _nativePosition = target.$2;
        if (_knownTargetGeneration == generation) {
          _knownTargetGeneration = null;
          _knownLocalTarget = null;
        }
      } catch (error) {
        if (_ownsSeek(seekGeneration, tuneGeneration)) {
          _publishControlFailure('seek', error);
        }
        return;
      } finally {
        if (_advancingGeneration == previousGeneration) {
          _advancingGeneration = null;
        }
      }
    } else {
      try {
        await player.seek(target?.$2 ?? position);
      } catch (error) {
        if (_ownsSeek(seekGeneration, tuneGeneration)) {
          _publishControlFailure('seek', error);
        }
        return;
      }
    }
    if (!_ownsSeek(seekGeneration, tuneGeneration)) return;
    showOsd();
  }

  Future<LineupPlaybackRequest?> _awaitSeekPart(
    LineupPlaybackRequest request,
    int generation,
    int tuneGeneration,
    Future<void> load,
  ) async {
    Object? failure;
    try {
      await load;
    } catch (error) {
      failure = error;
    }
    // Position generations may supersede each other, but never their shared
    // load dependency. Only replacement media or a new tune retires its error.
    final recovery = _authorizationRecoveryFor(request, generation);
    if (recovery != null) {
      try {
        final next = await recovery;
        if (_disposed ||
            tuneGeneration != _tuneGeneration ||
            !identical(_activePlayback, next)) {
          return null;
        }
        _clearAuthorizationRecovery(request, generation);
        return next;
      } catch (error) {
        if (tuneGeneration == _tuneGeneration &&
            _ownsAuthorizationRecoveryFailure(request, generation)) {
          await _failTransition(error, tuneGeneration);
        }
        return null;
      }
    }
    if (_disposed ||
        tuneGeneration != _tuneGeneration ||
        _activeLoadGeneration != generation ||
        !identical(_activePlayback, request)) {
      return null;
    }
    if (failure != null) {
      await _failTransition(failure, tuneGeneration);
      return null;
    }
    return request;
  }

  Future<void> selectTrack(PlayerTrackType type, int? id) =>
      _runPlaybackControl(switch (type) {
        PlayerTrackType.video => 'video_track',
        PlayerTrackType.audio => 'audio_track',
        PlayerTrackType.subtitle => 'subtitle_track',
      }, () => player.selectTrack(type, id));

  Future<void> toggleFullscreen() {
    final controlGeneration = ++_controlGeneration;
    final tuneGeneration = _tuneGeneration;
    final epoch = _fullscreenEpoch;
    final operation = _fullscreenOperations.then((_) async {
      if (_disposed || epoch != _fullscreenEpoch) return;
      final next = !_fullscreen;
      try {
        await player.setFullscreen(next);
      } catch (error) {
        if (epoch == _fullscreenEpoch &&
            _ownsPlaybackControl(controlGeneration, tuneGeneration)) {
          _publishControlFailure('fullscreen', error);
        }
        return;
      }
      if (_disposed || epoch != _fullscreenEpoch) return;
      _fullscreen = next;
      notifyListeners();
    });
    _fullscreenOperations = operation.catchError((_) {});
    return operation;
  }

  Future<void> _runPlaybackControl(
    String operation,
    Future<void> Function() command,
  ) async {
    final controlGeneration = ++_controlGeneration;
    final tuneGeneration = _tuneGeneration;
    try {
      await command();
    } catch (error) {
      if (_ownsPlaybackControl(controlGeneration, tuneGeneration)) {
        _publishControlFailure(operation, error);
      }
      return;
    }
    if (_ownsPlaybackControl(controlGeneration, tuneGeneration)) showOsd();
  }

  bool _ownsPlaybackControl(int controlGeneration, int tuneGeneration) =>
      !_disposed &&
      controlGeneration == _controlGeneration &&
      tuneGeneration == _tuneGeneration;

  bool _ownsSeek(int seekGeneration, int tuneGeneration) =>
      !_disposed &&
      seekGeneration == _seekGeneration &&
      tuneGeneration == _tuneGeneration;

  void _publishControlFailure(String operation, Object error) {
    _recordPlaybackFailure(error, operation: operation);
    _error = 'Playback controls are temporarily unavailable. Try again.';
    _canRetry = _retryChannelId != null;
    _setOverlay(PlayerOverlay.error, timed: false);
  }

  void showOsd() => _setOverlay(PlayerOverlay.osd);

  void showNowPlaying() {
    if (currentProgram == null) return;
    _setOverlay(PlayerOverlay.nowPlaying, timed: false);
  }

  void showMiniGuide() {
    _miniGuideChannelId =
        lineup.currentChannelId ?? lineup.channels.firstOrNull?.id;
    _requestMiniGuideRows();
    _setOverlay(PlayerOverlay.miniGuide, timeout: const Duration(seconds: 8));
  }

  void showFullGuide() => _setOverlay(PlayerOverlay.fullGuide, timed: false);

  void showTracks(PlayerTrackType type) {
    if (_overlay != PlayerOverlay.none &&
        _overlay != PlayerOverlay.osd &&
        _overlay != PlayerOverlay.nowPlaying) {
      return;
    }
    if (!_tracks.any((track) => track.type == type)) return;
    _setOverlay(
      type == PlayerTrackType.audio
          ? PlayerOverlay.audioTracks
          : PlayerOverlay.subtitleTracks,
      timed: false,
    );
  }

  void moveMiniGuide(int offset) {
    final channels = _indexedChannels;
    if (channels.isEmpty) return;
    final index = _channelIndexById[miniGuideChannelId] ?? 0;
    final raw = (index < 0 ? 0 : index) + offset;
    final next = ((raw % channels.length) + channels.length) % channels.length;
    _miniGuideChannelId = channels[next].id;
    _requestMiniGuideRows();
    _setOverlay(PlayerOverlay.miniGuide, timeout: const Duration(seconds: 8));
  }

  void focusMiniGuideChannel(String channelId) {
    if (!_channelIndexById.containsKey(channelId)) return;
    _miniGuideChannelId = channelId;
    _requestMiniGuideRows();
    _setOverlay(PlayerOverlay.miniGuide, timeout: const Duration(seconds: 8));
  }

  Future<void> tuneMiniGuideSelection() async {
    final id = miniGuideChannelId;
    if (id != null) await tune(id);
  }

  void closeOverlay() {
    if (_overlay == PlayerOverlay.audioTracks ||
        _overlay == PlayerOverlay.subtitleTracks) {
      showOsd();
      return;
    }
    _cancelOverlayTimer();
    _presentOverlay(PlayerOverlay.none);
    notifyListeners();
  }

  void overlayFocusChanged(
    PlayerOverlay overlay,
    int presentationGeneration,
    bool focused,
  ) {
    if (_overlay != overlay ||
        _overlayPresentationGeneration != presentationGeneration ||
        (overlay != PlayerOverlay.osd && overlay != PlayerOverlay.miniGuide)) {
      return;
    }
    if (focused) {
      _overlayFocusSuspended = true;
      _cancelOverlayTimer();
      return;
    }
    if (!_overlayFocusSuspended) return;
    _overlayFocusSuspended = false;
    _scheduleOverlayHide(
      overlay,
      timeout: overlay == PlayerOverlay.miniGuide
          ? const Duration(seconds: 8)
          : null,
    );
  }

  void appendChannelDigit(String digit) {
    if (!RegExp(r'^\d$').hasMatch(digit)) return;
    _channelNumber = '$_channelNumber$digit';
    if (_channelNumber.length > 4) _channelNumber = digit;
    _numberTimer?.cancel();
    _setOverlay(PlayerOverlay.channelNumber, timed: false);
    _numberTimer = Timer(const Duration(seconds: 2), commitChannelNumber);
  }

  Future<void> commitChannelNumber() async {
    _numberTimer?.cancel();
    final number = int.tryParse(_channelNumber);
    _channelNumber = '';
    final channel = _channelByNumber[number];
    if (channel == null) {
      _error = 'Channel ${number ?? ''} is not in this lineup.';
      _setOverlay(PlayerOverlay.error, timed: false);
      return;
    }
    await tune(channel.id);
  }

  void cycleSleepTimer() {
    final epoch = ++_sleepEpoch;
    _sleepTimer?.cancel();
    _sleepDuration = switch (_sleepDuration?.inMinutes) {
      null => const Duration(minutes: 30),
      30 => const Duration(minutes: 60),
      60 => const Duration(minutes: 90),
      _ => null,
    };
    final duration = _sleepDuration;
    if (duration != null) {
      _sleepTimer = Timer(duration, () async {
        try {
          await stop();
        } catch (error) {
          if (_disposed || epoch != _sleepEpoch) return;
          _sleepTimer = null;
          _sleepDuration = null;
          _recordPlaybackFailure(error);
          _error =
              'Playback could not be stopped when the sleep timer expired.';
          _setOverlay(PlayerOverlay.error, timed: false);
          return;
        }
        if (_disposed || epoch != _sleepEpoch) return;
        _sleepTimer = null;
        _sleepDuration = null;
        notifyListeners();
      });
    }
    showOsd();
  }

  void showCursor() {
    _cursorTimer?.cancel();
    if (!_cursorVisible) {
      _cursorVisible = true;
      notifyListeners();
    }
    _cursorTimer = Timer(const Duration(seconds: 3), () {
      if (_status.state == PlayerState.playing &&
          _overlay == PlayerOverlay.none) {
        _cursorVisible = false;
        notifyListeners();
      }
    });
  }

  void handlePointerActivity() {
    showCursor();
    if (_overlay == PlayerOverlay.none) {
      showOsd();
    } else if (_overlay == PlayerOverlay.osd &&
        _status.state == PlayerState.playing) {
      _scheduleOverlayHide(PlayerOverlay.osd);
    }
  }

  void _setOverlay(
    PlayerOverlay value, {
    bool timed = true,
    Duration? timeout,
  }) {
    _cancelOverlayTimer();
    if (_overlay != value) _presentOverlay(value);
    notifyListeners();
    if (timed) {
      _scheduleOverlayHide(value, timeout: timeout);
    }
  }

  void _scheduleOverlayHide(PlayerOverlay value, {Duration? timeout}) {
    _overlayTimer?.cancel();
    _overlayTimer = null;
    if (_overlayFocusSuspended && _overlay == value) return;
    final epoch = ++_overlayEpoch;
    _overlayTimer = Timer(
      timeout ??
          overlayTimeout ??
          Duration(seconds: lineup.settings.osdAutoHideSeconds),
      () {
        if (_disposed || epoch != _overlayEpoch || _overlay != value) return;
        _overlayTimer = null;
        _presentOverlay(PlayerOverlay.none);
        notifyListeners();
      },
    );
  }

  void _presentOverlay(PlayerOverlay value) {
    _overlayPresentationGeneration++;
    _overlayFocusSuspended = false;
    _overlay = value;
  }

  void _cancelOverlayTimer() {
    _overlayEpoch++;
    _overlayTimer?.cancel();
    _overlayTimer = null;
  }

  void _lineupChanged() {
    final activeChannelChanged =
        _activeChannel != null &&
        !lineup.channels.any((channel) => identical(channel, _activeChannel));
    if (_contentGeneration != lineup.contentGeneration ||
        activeChannelChanged) {
      _contentGeneration = lineup.contentGeneration;
      ++_controlGeneration;
      ++_seekGeneration;
      final fullscreenCleanup = _queueFullscreenReset();
      if (_activePlayback != null || _tuning || _nativeCleanupRequired) {
        ++_tuneGeneration;
        _tuning = false;
        _canRetry = false;
        _invalidateAuthorizationRecovery();
        _resetScopeState();
        if (!_scopeCleanupPending) {
          _scopeCleanupPending = true;
          final nativeStop = _beginNativeStop(force: true)!;
          _scopeCleanup = _stopForScopeChange(fullscreenCleanup, nativeStop)
              .catchError((Object error) {
                if (!_disposed) {
                  _recordPlaybackFailure(error, operation: 'scope_cleanup');
                }
              })
              .whenComplete(() => _scopeCleanupPending = false);
        } else {
          final previousCleanup = _scopeCleanup;
          _scopeCleanup = Future.wait([previousCleanup, fullscreenCleanup])
              .then<void>((_) {})
              .catchError((Object error) {
                if (!_disposed) {
                  _recordPlaybackFailure(error, operation: 'scope_cleanup');
                }
              });
        }
      } else {
        _resetScopeState();
        final previousCleanup = _scopeCleanup;
        _scopeCleanup = Future.wait([previousCleanup, fullscreenCleanup])
            .then<void>((_) {})
            .catchError((Object error) {
              if (!_disposed) {
                _recordPlaybackFailure(error, operation: 'scope_cleanup');
              }
            });
      }
    }
    if (_osdAutoHideSeconds != lineup.settings.osdAutoHideSeconds) {
      _osdAutoHideSeconds = lineup.settings.osdAutoHideSeconds;
      if (overlayTimeout == null && _overlay == PlayerOverlay.osd) {
        _scheduleOverlayHide(_overlay);
      }
    }
    final previousMiniIndex = miniGuideChannelIndex;
    if (!identical(_indexedChannels, lineup.channels)) _indexChannels();
    if (!_channelIndexById.containsKey(_miniGuideChannelId)) {
      if (_indexedChannels.isEmpty) {
        _miniGuideChannelId = null;
      } else {
        final fallback = previousMiniIndex < 0
            ? 0
            : previousMiniIndex.clamp(0, _indexedChannels.length - 1);
        _miniGuideChannelId = _indexedChannels[fallback].id;
      }
    }
    if (currentChannel == null && lineup.channels.isNotEmpty) {
      _error = null;
    }
    if (_overlay == PlayerOverlay.miniGuide) _requestMiniGuideRows();
    notifyListeners();
  }

  void _guideChanged() {
    if (_overlay == PlayerOverlay.nowPlaying && currentProgram == null) {
      closeOverlay();
    } else if (_overlay == PlayerOverlay.miniGuide ||
        _overlay == PlayerOverlay.osd ||
        _overlay == PlayerOverlay.nowPlaying) {
      notifyListeners();
    }
  }

  Future<void> _stopForScopeChange(
    Future<void> fullscreen,
    Future<void> nativeStop,
  ) async {
    final stop = _tuneOperations.then((_) async {
      await nativeStop;
      if (!_disposed) {
        _status = const PlayerStatus(
          state: PlayerState.stopped,
          message: 'Stopped',
        );
      }
    });
    _tuneOperations = stop.catchError((_) {});
    await fullscreen;
    await stop;
  }

  Future<void> _queueFullscreenReset() {
    ++_fullscreenEpoch;
    _fullscreen = false;
    final operation = _fullscreenOperations.then(
      (_) => player.setFullscreen(false),
    );
    _fullscreenOperations = operation.catchError((_) {});
    return operation;
  }

  void _resetScopeState() {
    _cancelOverlayTimer();
    ++_sleepEpoch;
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepDuration = null;
    _numberTimer?.cancel();
    _numberTimer = null;
    _channelNumber = '';
    _cursorTimer?.cancel();
    _cursorTimer = null;
    _cursorVisible = true;
    _presentOverlay(PlayerOverlay.none);
    _miniGuideChannelId = null;
    _retryChannelId = null;
    _activeChannel = null;
    _error = null;
  }

  void _requestMiniGuideRows() {
    guide.requestChannels(miniGuideChannels);
  }

  Future<void> _stopQuietly() async {
    final stop = _beginNativeStop();
    if (stop == null) return;
    try {
      await stop;
    } catch (_) {
      // The original tune failure remains the useful error.
    }
  }

  Future<void>? _beginNativeStop({bool force = false}) {
    final pending = _nativeStopOperation;
    if (pending != null) {
      return pending;
    }
    if (!force && !_nativeCleanupRequired) return null;
    _nativeCleanupRequired = true;
    _retirePlaybackIntent();
    late final Future<void> operation;
    operation = Future<void>.sync(player.stop)
        .timeout(
          _nativeStopTimeout,
          onTimeout: () => throw const PlayerUnavailable(
            'Native playback did not stop within 10 seconds.',
          ),
        )
        .then((_) {
          _nativeCleanupRequired = false;
        })
        .whenComplete(() {
          if (identical(_nativeStopOperation, operation)) {
            _nativeStopOperation = null;
          }
        });
    unawaited(operation.catchError((_) {}));
    _nativeStopOperation = operation;
    return operation;
  }

  void _retirePlaybackIntent() {
    _pendingSeekPart = null;
    _activeLoadGeneration = null;
    _advancingGeneration = null;
    _nativeReplacementGeneration = null;
    _activePlayback = null;
    _provisionalPlayback = null;
    _activeChannel = null;
    _retryCeilingRequest = null;
    _retryCeilingGeneration = null;
  }

  void _recordPlaybackFailure(Object error, {String operation = 'request'}) {
    final rawCode = switch (error) {
      PlexException(:final code) => code,
      PlayerUnavailable(:final failureCode) => failureCode,
      _ => 'unexpected',
    };
    final code = RegExp(r'^[a-z][a-z0-9_-]{0,63}$').hasMatch(rawCode)
        ? rawCode
        : 'unexpected';
    lineup.diagnostics.add('playback', 'Playback request failed', {
      if (operation != 'request') 'operation': operation,
      'code': code,
    });
  }

  static String _safePlaybackError(Object error) => switch (error) {
    PlexException(:final message) => message,
    PlayerUnavailable() =>
      'Playback could not start. Retry or choose another channel.',
    _ => 'Playback could not start. Retry or choose another channel.',
  };

  void _indexChannels() {
    _indexedChannels = lineup.channels;
    _channelIndexById = {
      for (var index = 0; index < _indexedChannels.length; index++)
        _indexedChannels[index].id: index,
    };
    _channelByNumber = {
      for (final channel in _indexedChannels) channel.number: channel,
    };
  }

  @override
  void dispose() {
    if (_disposed) return;
    final fullscreenReset = _queueFullscreenReset();
    _disposed = true;
    ++_tuneGeneration;
    ++_controlGeneration;
    ++_sleepEpoch;
    _activeLoadGeneration = null;
    _tuning = false;
    lineup.removeListener(_lineupChanged);
    guide.removeListener(_guideChanged);
    _subscription?.cancel();
    _cancelOverlayTimer();
    _sleepTimer?.cancel();
    _numberTimer?.cancel();
    _cursorTimer?.cancel();
    _activePlayback = null;
    _provisionalPlayback = null;
    unawaited(fullscreenReset.catchError((_) {}));
    super.dispose();
  }
}
