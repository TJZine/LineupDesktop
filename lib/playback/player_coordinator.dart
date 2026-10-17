import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../app/lineup_controller.dart';
import '../channels/channel.dart';
import '../diagnostics/diagnostics.dart';
import '../guide/guide_controller.dart';
import '../plex/plex_models.dart';
import 'native_player.dart';
import 'display_matching.dart';

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
  static const _catchUpTolerance = Duration(seconds: 30);
  static const _prematureEndTolerance = Duration(seconds: 30);
  static const _nativeStopTimeout = Duration(seconds: 10);
  static const _trackConfirmationTimeout = Duration(seconds: 5);

  PlayerCoordinator({
    required this.player,
    required this.lineup,
    required this.guide,
    this.overlayTimeout,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _indexChannels();
    _status = player.status;
    _position = player.position;
    _duration = player.duration;
    _telemetry = player.telemetry;
    _tracks = player.tracks;
    _contentGeneration = lineup.contentGeneration;
    _osdAutoHideSeconds = lineup.settings.osdAutoHideSeconds;
    _displayMatching = DisplayMatching(
      player: player,
      clock: _clock,
      changed: notifyListeners,
    );
    _displaySubscription = player.displayReports.listen(
      _displayMatching.receive,
    );
    _subscription = player.events.listen(_event);
    lineup.addListener(_lineupChanged);
    guide.addListener(_guideChanged);
    notifyListeners();
  }

  late final DisplayMatching _displayMatching;
  StreamSubscription<DisplayMatchingReport>? _displaySubscription;
  bool _playerDestinationVisible = true;
  bool get displayHoldActive => _displayMatching.holdActive;
  DisplayMatchingReport get displayReport => _displayMatching.report;
  void setPlayerDestinationVisible(bool value) {
    if (_playerDestinationVisible == value) return;
    _playerDestinationVisible = value;
    notifyListeners();
  }

  final NativePlayer player;
  final LineupController lineup;
  final GuideController guide;
  final Duration? overlayTimeout;
  final DateTime Function() _clock;
  GuideProgram? _resolvingProgram;
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
  Timer? _noticeTimer;
  Timer? _busyTimer;
  String? _notice;
  String? _busyLabel;
  (int, bool, PlayerState)? _busyIdentity;

  int _overlayEpoch = 0;
  int _overlayPresentationGeneration = 0;
  bool _overlayFocusSuspended = false;
  int _sleepEpoch = 0;
  PlayerOverlay _overlay = PlayerOverlay.none;
  String _channelNumber = '';
  String? _miniGuideChannelId;
  int? _miniGuideWindowStart;
  String? _error;
  bool _fullscreen = false;
  bool _cursorVisible = true;
  bool _cursorIdle = false;
  bool _tuning = false;
  bool _canRetry = false;
  Duration? _sleepDuration;
  DateTime? _sleepDeadline;
  bool _sleepPickerOpen = false;
  _TrackConfirmation _trackConfirmation = _TrackConfirmation();
  int _tuneGeneration = 0;
  int? _continuationGeneration;
  bool get _preservePresentation => _continuationGeneration == _tuneGeneration;
  int _controlGeneration = 0;
  int _playbackIntentRevision = 0;
  bool _userPaused = false;
  int _trackSelectionGeneration = 0;
  int _seekGeneration = 0;
  int _fullscreenEpoch = 0;
  int _nativeLoadGeneration = 0;
  _PlaybackLoad? _activeLoad;
  int? get _activeLoadGeneration => _activeLoad?.generation;
  int get _activePartIndex => _activeLoad?.partIndex ?? 0;
  final Map<int, Duration> _partDurations = {};
  int? _advancingGeneration;
  // Tunes run serially: a losing tune can clean up only its own load or
  // the pending stop, never a newer tune's load.
  Future<void> _tuneOperations = Future.value();
  Future<void>? _nativeStopOperation;
  bool _nativeCleanupRequired = false;
  Future<void> _scopeCleanup = Future.value();
  Future<void> _fullscreenOperations = Future.value();
  bool _scopeCleanupPending = false;
  bool _disposed = false;
  bool _publishing = false;
  bool _republish = false;
  bool _initialMediaRequested = false;
  _ActiveProgram? _active;
  _AuthorizationRecovery? _authorizationRecovery;
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
  PlaybackDiagnosticSnapshot get diagnosticPlaybackSnapshot =>
      PlaybackDiagnosticSnapshot(
        state: _status.state,
        displayReport: displayReport,
        receivedTelemetry:
            _activeLoadGeneration != null &&
                const {
                  PlayerState.ready,
                  PlayerState.playing,
                  PlayerState.paused,
                  PlayerState.buffering,
                  PlayerState.seeking,
                  PlayerState.error,
                }.contains(_status.state)
            ? _telemetry
            : null,
      );
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
        : _miniGuideWindowStart ??
              (selected - 2 + channels.length) % channels.length;
    return List.generate(
      count,
      (offset) => channels[(start + offset) % channels.length],
      growable: false,
    );
  }

  String? get notice => _notice;
  String? get busyLabel => _busyLabel;
  String get channelNumberLabel {
    final channel = _channelByNumber[int.tryParse(_channelNumber)];
    return channel == null
        ? _channelNumber
        : '$_channelNumber · ${channel.name}';
  }

  String? get error => _error;
  bool get fullscreen => _fullscreen;
  bool get cursorVisible => _cursorVisible;
  bool get tuning => _tuning;
  bool get canRetry => _canRetry;
  bool get hasPlaybackIntent =>
      _tuning ||
      _activeLoad != null ||
      _active != null ||
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
  DateTime? get sleepDeadline => _sleepDeadline;
  bool get sleepPickerOpen => _sleepPickerOpen;
  Duration? get sleepRemaining {
    final deadline = _sleepDeadline;
    if (deadline == null) return null;
    final remaining = deadline.difference(_clock());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  PlayerTrackType? get pendingTrackType => _trackConfirmation.type;
  int? get pendingTrackId => _trackConfirmation.id;
  String? get trackSelectionError => _trackConfirmation.error;
  Channel? get currentChannel {
    final index = _channelIndexById[lineup.currentChannelId];
    return index == null ? null : _indexedChannels[index];
  }

  /// The active channel is watching only after tuning settles into a live
  /// playback state. A deleted/orphaned active program has no visible channel.
  String? get watchingChannelId =>
      !tuning &&
          error == null &&
          const {
            PlayerState.playing,
            PlayerState.paused,
            PlayerState.buffering,
            PlayerState.seeking,
          }.contains(status.state)
      ? _active?.channel?.id
      : null;

  /// A display hold presents loading while preserving the native state used
  /// for playback intent, including the ability to pause during preparation.
  PlayerState get presentedState =>
      displayHoldActive ? PlayerState.loading : status.state;

  GuideProgram? get currentProgram {
    final id = lineup.currentChannelId;
    return _resolvingProgram ??
        _active?.program ??
        (id == null ? null : guide.currentProgram(id));
  }

  GuideProgram? get nextProgram {
    final id = lineup.currentChannelId;
    final represented = _resolvingProgram ?? _active?.program;
    if (represented != null) {
      return guide.currentProgram(
        represented.channelId,
        represented.scheduled.end,
      );
    }
    return id == null ? null : guide.nextProgram(id);
  }

  void _showNotice(
    String message, {
    Duration duration = const Duration(seconds: 6),
  }) {
    _noticeTimer?.cancel();
    _notice = message;
    _noticeTimer = Timer(duration, () {
      if (_disposed) return;
      _notice = null;
      notifyListeners();
    });
    notifyListeners();
  }

  void _clearTransientStatus() {
    _numberTimer?.cancel();
    _numberTimer = null;
    _channelNumber = '';
    _noticeTimer?.cancel();
    _notice = null;
    _reconcileBusy(clear: true);
  }

  /// Reconciles display and busy state before publishing. Reconciliation-origin
  /// requests join that publication; listener-origin requests get another round.
  /// Late callbacks and further rounds after disposal are ignored.
  @override
  void notifyListeners() {
    if (_disposed) return;
    if (_publishing) {
      _republish = true;
      return;
    }
    _publishing = true;
    try {
      do {
        if (_disposed) break;
        _reconcile();
        if (_disposed) break;
        _republish = false;
        super.notifyListeners();
      } while (!_disposed && _republish);
    } finally {
      _publishing = false;
    }
  }

  void _reconcile() {
    _updateDisplaySession();
    _reconcileBusy();
  }

  void _reconcileBusy({bool clear = false}) {
    if (clear) {
      _busyTimer?.cancel();
      _busyTimer = null;
      _busyLabel = null;
      _busyIdentity = null;
      return;
    }
    final busy =
        !_scopeCleanupPending &&
        _error == null &&
        (displayHoldActive ||
            _tuning ||
            _status.state == PlayerState.loading ||
            _status.state == PlayerState.buffering);
    final identity = busy
        ? displayHoldActive
              ? (
                  _activeLoadGeneration ?? _tuneGeneration,
                  false,
                  PlayerState.loading,
                )
              : (_tuneGeneration, _tuning, _status.state)
        : null;
    if (_busyIdentity != identity) {
      _busyTimer?.cancel();
      _busyLabel = null;
      _busyIdentity = identity;
      if (identity != null) {
        _busyTimer = Timer(const Duration(seconds: 2), () {
          if (_disposed || _busyIdentity != identity) return;
          _busyLabel =
              !displayHoldActive &&
                  !_tuning &&
                  _status.state == PlayerState.buffering
              ? 'Buffering…'
              : 'Starting playback…';
          notifyListeners();
        });
      }
    }
  }

  void _updateDisplaySession() {
    _displayMatching.updateSession(
      displayMatchingSession(
        active: _displayMatching.session,
        enabled: lineup.settings.matchDisplayHdr,
        fullscreen: _fullscreen,
        intent:
            hasPlaybackIntent &&
            (!_scopeCleanupPending) &&
            (_nativeStopOperation == null || _tuning),
        playerVisible: _playerDestinationVisible,
        fullGuide: _overlay == PlayerOverlay.fullGuide,
        error: _error != null || _overlay == PlayerOverlay.error,
      ),
      userPaused: _userPaused,
    );
  }

  Object get _eventVisibleFacts => (
    (
      _status.state,
      _status.message,
      _status.recoverable,
      _status.failureCode,
      _status.httpStatus,
    ),
    _position.inMicroseconds ~/
        const Duration(milliseconds: 250).inMicroseconds,
    _duration,
    (
      _telemetry.videoOutput,
      _telemetry.hardwareDecoder,
      _telemetry.videoCodec,
      _telemetry.videoFormat,
      _telemetry.width,
      _telemetry.height,
      _telemetry.pixelFormat,
      _telemetry.hardwarePixelFormat,
      _telemetry.primaries,
      _telemetry.gamma,
      _telemetry.colorMatrix,
      _telemetry.signalPeak,
      _telemetry.targetGamma,
      _telemetry.targetPrimaries,
      _telemetry.targetPixelFormat,
    ),
    _tracks,
    _overlay,
    _overlayPresentationGeneration,
    _error,
    _trackConfirmation.type,
    _trackConfirmation.id,
  );

  void _event(PlayerEvent event) {
    if (event.generation != _activeLoadGeneration) return;
    final load = _activeLoad;
    final terminal = const {
      PlayerState.error,
      PlayerState.ended,
      PlayerState.stopped,
      PlayerState.idle,
      PlayerState.unsupported,
    }.contains(event.status.state);
    if (terminal &&
        (event.status.state == PlayerState.error || load?.replacing != true)) {
      _displayMatching.cancelLoad();
    }
    if (event.position > Duration.zero) {
      load?.lastPositivePosition = event.position;
    }
    if (event.duration > Duration.zero) {
      load?.lastPositiveDuration = event.duration;
    }
    final previousFacts = _eventVisibleFacts;
    final previousState = _status.state;
    final holdTransition = _displayMatching.suppressTransition(
      event.status.state,
    );
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
    final playback = _activeLoad?.request ?? _active?.request;
    if (playback != null &&
        _activePartIndex < playback.parts.length &&
        _usesAggregateCoordinates(playback)) {
      final offset = _partOffset(_activePartIndex)!;
      _position = offset + event.position;
      _duration = _partDurations.values.fold(Duration.zero, (a, b) => a + b);
    } else {
      _position = event.position;
      _duration = event.duration;
    }
    _telemetry = event.telemetry;
    _tracks = event.tracks;
    if (event.generation case final generation? when !terminal) {
      _displayMatching.observe(generation, event.telemetry, event.position);
      if (event.tracksUpdated) {
        _displayMatching.tracksUpdated(
          generation,
          noVideo: !event.tracks.any(
            (track) => track.type == PlayerTrackType.video && track.selected,
          ),
        );
      }
    }
    if (const {
      PlayerState.idle,
      PlayerState.ended,
      PlayerState.stopped,
      PlayerState.unsupported,
    }.contains(event.status.state)) {
      _telemetry = const PlayerTelemetry();
      _tracks = const [];
    }
    if (_trackConfirmation.type case final type?) {
      final confirmed =
          type == PlayerTrackType.subtitle && _trackConfirmation.id == null
          ? !_tracks.any((track) => track.type == type && track.selected)
          : _tracks.any(
              (track) =>
                  track.type == type &&
                  track.id == _trackConfirmation.id &&
                  track.selected,
            );
      if (confirmed) {
        _clearTrackSelection();
      }
    }
    if (_activeLoad?.replacing == true &&
        const {
          PlayerState.ready,
          PlayerState.playing,
          PlayerState.paused,
          PlayerState.buffering,
          PlayerState.seeking,
        }.contains(event.status.state)) {
      _activeLoad?.replacing = false;
    }
    if (event.status.state == PlayerState.error) {
      if (_isAuthorizationFailure(event.status) &&
          _activeLoadGeneration != null &&
          playback != null) {
        final rejectedGeneration = _activeLoadGeneration!;
        final pending = _authorizationRecoveryFor(playback, rejectedGeneration);
        if (pending != null) return;
        final load = _activeLoad!;
        if (!load.authorizationRetried) {
          final recover = playback.authorizationRecovery;
          if (recover != null) {
            final recovery = _AuthorizationRecovery(load);
            _authorizationRecovery = recovery;
            load.recovery = recovery;
            recovery.result = _recoverAuthorization(
              recovery,
              identical(playback, _active?.request),
              load.target ?? _nativePosition,
              Future.sync(recover),
            );
            if (!load.pending) {
              unawaited(_settleActiveAuthorization(recovery));
            }
            return;
          }
        }
      }
      _displayMatching.cancelLoad();
      final audioCodec = event.tracks
          .where(
            (track) => track.type == PlayerTrackType.audio && track.selected,
          )
          .firstOrNull
          ?.codec;
      lineup.diagnostics.add(DiagnosticEvent.nativePlaybackFailed, {
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
      _releaseActive();
      _setOverlay(PlayerOverlay.error, timed: false);
    } else {
      switch (event.status.state) {
        case PlayerState.loading:
          if (_preservePresentation) break;
          _cancelOverlayTimer();
          if (_overlay == PlayerOverlay.osd) {
            _presentOverlay(PlayerOverlay.none);
          }
          break;
        case PlayerState.ready:
        case PlayerState.paused:
        case PlayerState.buffering:
        case PlayerState.seeking:
          if (holdTransition) break;
          if (!_preservePresentation &&
              event.status.state != previousState &&
              _overlay != PlayerOverlay.nowPlaying) {
            _setOverlay(PlayerOverlay.osd);
          }
          break;
        case PlayerState.playing:
          if (holdTransition) break;
          if (!_preservePresentation &&
              previousState != PlayerState.playing &&
              _overlay == PlayerOverlay.osd) {
            _scheduleOverlayHide(_overlay);
          }
          break;
        case PlayerState.ended:
        case PlayerState.stopped:
          final generation = _activeLoadGeneration;
          final request = _active?.request;
          if (request == null && playback == null) {
            _activeLoad = null;
            if (!_preservePresentation) {
              _cancelOverlayTimer();
              if (_overlay != PlayerOverlay.error) {
                _presentOverlay(PlayerOverlay.none);
              }
            }
            break;
          }
          if (event.status.state == PlayerState.stopped &&
              _activeLoad?.replacing == true) {
            _activeLoad?.replacing = false;
            break;
          }
          if (_activeLoad?.replacing == true) break;
          if (event.status.state == PlayerState.stopped) {
            _retireEndedPlayback();
            break;
          }
          if (load == null) break;
          final knownDuration =
              load.lastPositiveDuration ??
              (playback == null
                  ? null
                  : playback.parts[load.partIndex].duration);
          final position = load.lastPositivePosition > Duration.zero
              ? load.lastPositivePosition
              : load.startTarget ?? Duration.zero;
          final target = load.target ?? Duration.zero;
          final observedProgress = position > target ? position : target;
          if (knownDuration != null &&
              observedProgress < knownDuration - _prematureEndTolerance) {
            unawaited(_failPrematureEnd(load.tuneGeneration));
            break;
          }
          if (generation != null &&
              request != null &&
              _advancingGeneration != generation) {
            _advancingGeneration = generation;
            if (_partDurations[_activePartIndex] == null &&
                load.lastPositiveDuration != null) {
              _partDurations[_activePartIndex] = load.lastPositiveDuration!;
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
    if (_preservePresentation &&
        load != null &&
        (event.status.state == PlayerState.ready ||
            event.status.state == PlayerState.playing)) {
      _continuationGeneration = null;
    }
    if (!_disposed && previousFacts != _eventVisibleFacts) notifyListeners();
  }

  Future<bool> tune(String channelId) => _tune(channelId);

  Future<bool> _tune(String channelId, {GuideProgram? endedProgram}) {
    final deadline = _sleepDeadline;
    if (deadline != null && !_clock().isBefore(deadline)) {
      return _expireSleepTimer(_sleepEpoch).then((_) => false);
    }
    _userPaused = false;
    if (endedProgram == null) _clearTransientStatus();
    _resolvingProgram = null;
    final generation = ++_tuneGeneration;
    _continuationGeneration = endedProgram == null ? null : generation;
    ++_controlGeneration;
    _invalidateAuthorizationRecovery();
    _tuning = true;
    final nativeStop = _beginNativeStop();
    _canRetry = false;
    _error = null;
    _retryChannelId = channelId;
    if (endedProgram == null) {
      _cancelOverlayTimer();
      _presentOverlay(PlayerOverlay.osd);
    }
    notifyListeners();
    final operation = _tuneOperations.then(
      (_) => _performTune(channelId, generation, nativeStop, endedProgram),
    );
    _tuneOperations = operation.then<void>((_) {}).catchError((_) {});
    return operation;
  }

  Future<void> loadInitialMedia(Uri media) async {
    if (_initialMediaRequested) return;
    _initialMediaRequested = true;
    _userPaused = false;
    if (await _expireSleepIfNeeded()) return;
    _clearTransientStatus();
    final generation = ++_tuneGeneration;
    ++_controlGeneration;
    try {
      await _load(media);
      if (!_disposed && generation == _tuneGeneration) showOsd();
    } catch (error) {
      if (_disposed || generation != _tuneGeneration) return;
      await _stopQuietly();
      if (_disposed || generation != _tuneGeneration) return;
      _reportUnexpectedPlaybackFailure(error, 'while loading initial media');
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
    GuideProgram? endedProgram,
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
    var program = await guide.ensureCurrentProgram(channelId);
    if (generation != _tuneGeneration) return false;
    if (program == null) {
      if (endedProgram != null) {
        _tuning = false;
        _retireEndedPlayback();
        return false;
      }
      _tuning = false;
      _canRetry = true;
      _error = 'The current program could not be loaded.';
      _setOverlay(PlayerOverlay.error, timed: false);
      return false;
    }
    var fromBeginning = false;
    if (endedProgram != null) {
      final successor = guide.currentProgram(
        channelId,
        endedProgram.scheduled.end,
      );
      if (successor != null &&
          successor.id != endedProgram.id &&
          _clock().difference(successor.scheduled.start) <= _catchUpTolerance) {
        program = successor;
        fromBeginning = true;
      }
      if (program.id == endedProgram.id) {
        _tuning = false;
        _retireEndedPlayback();
        return false;
      }
    }
    _resolvingProgram = program;
    LineupPlaybackRequest? request;
    LineupPlaybackRequest? replaced;
    _ActiveProgram? active;
    final contentGeneration = lineup.contentGeneration;
    bool ownsTune() =>
        !_disposed &&
        generation == _tuneGeneration &&
        contentGeneration == lineup.contentGeneration;
    final previousChannelId = lineup.currentChannelId;
    Future<bool> fail(Object error) async {
      _invalidateAuthorizationRecovery();
      if (active != null && identical(_active, active)) _releaseActive();
      if (request != null) _releaseActive(ifRequest: request);
      if (replaced != null) _releaseActive(ifRequest: replaced);
      if (request != null) await _stopQuietly();
      if (!ownsTune()) return false;
      _tuning = false;
      _canRetry = true;
      _recordPlaybackFailure(error);
      _error = _safePlaybackError(error);
      _setOverlay(PlayerOverlay.error, timed: false);
      return false;
    }

    try {
      request = lineup.playbackFor(program.scheduled.item.id);
      replaced = _active?.request;
      final elapsed = _clock().difference(program.scheduled.start);
      request = await _loadPlayback(
        request,
        initialPosition: !fromBeginning && elapsed > const Duration(seconds: 2)
            ? elapsed
            : null,
      );
      _invalidateAuthorizationRecovery();
      if (replaced != null) _releaseActive(ifRequest: replaced);
      if (generation != _tuneGeneration) {
        if (_supersededByTune) await _stopQuietly();
        return false;
      }
      active = _commitActive(request, program, channelId);
      await lineup.setCurrentChannel(channelId);
      if (!ownsTune()) {
        if (identical(_active, active)) _releaseActive();
        if (_supersededByTune) await _stopQuietly();
        return false;
      }
      // Authorization recovery replaces the request within this session. A
      // released session instead means that playback failed during the save.
      if (!identical(_active, active)) {
        _tuning = false;
        if (lineup.currentChannelId == channelId &&
            previousChannelId != channelId) {
          await lineup.setCurrentChannel(previousChannelId);
        }
        await _stopQuietly();
        if (ownsTune()) notifyListeners();
        return false;
      }
      _tuning = false;
      _canRetry = false;
      _error = null;
      if (endedProgram == null) {
        showOsd();
      } else {
        notifyListeners();
      }
      return !_disposed &&
          generation == _tuneGeneration &&
          identical(_active, active) &&
          _active?.channel?.id == channelId &&
          lineup.currentChannelId == channelId &&
          !_tuning &&
          _error == null;
    } on LineupScopeSuperseded catch (error) {
      return await fail(error);
    } on _PlaybackSuperseded catch (error) {
      return await fail(error);
    } catch (error) {
      if (ownsTune()) {
        _reportUnexpectedPlaybackFailure(error, 'while tuning a channel');
      }
      return await fail(error);
    } finally {
      if (generation == _tuneGeneration) _resolvingProgram = null;
    }
  }

  bool get _supersededByTune => _tuning || _disposed;

  _ActiveProgram _commitActive(
    LineupPlaybackRequest request,
    GuideProgram program,
    String channelId,
  ) => _active = _ActiveProgram(
    request: request,
    program: program,
    channel: lineup.channels
        .where((channel) => channel.id == channelId)
        .firstOrNull,
  );

  void _releaseActive({LineupPlaybackRequest? ifRequest}) {
    if (ifRequest == null || identical(_active?.request, ifRequest)) {
      _active = null;
    }
  }

  void _replaceActiveRequest(LineupPlaybackRequest request) {
    _active?.request = request;
  }

  void _refreshActiveChannel(Channel channel) {
    _active?.channel = channel;
  }

  Future<void> retry() async {
    final id = _retryChannelId ?? currentChannel?.id;
    if (id != null) await tune(id);
  }

  Future<void> _load(Uri media) => _startLoad(media).readiness;

  _PlaybackLoad _startLoad(
    Uri media, {
    LineupPlaybackRequest? request,
    int partIndex = 0,
    Duration? target,
    bool authorizationRetried = false,
  }) {
    if (_nativeStopOperation != null) {
      throw const PlayerUnavailable('Playback stop is still pending.');
    }
    final load = _PlaybackLoad(
      generation: ++_nativeLoadGeneration,
      tuneGeneration: _tuneGeneration,
      request: request,
      partIndex: partIndex,
      target: target,
      replacing: _activeLoad != null,
      authorizationRetried: authorizationRetried,
    );
    _activeLoad = load;
    _displayMatching.cancelLoad();
    _updateDisplaySession();
    final startPaused = _displayMatching.beginLoad(
      load.generation,
      target,
      userPaused: _userPaused,
    );
    _nativeCleanupRequired = true;
    _nativePosition = Duration.zero;
    _telemetry = const PlayerTelemetry();
    _tracks = const [];
    _clearTrackSelection();
    load.readiness = Future<void>.sync(
      () => player.load(
        media,
        plexToken: request?.plexToken,
        generation: load.generation,
        startPaused: startPaused,
      ),
    );
    unawaited(
      load.readiness.then(
        (_) {
          if (!_ownsLoad(load)) return;
          _displayMatching.ready(load.generation);
          if (displayHoldActive) notifyListeners();
        },
        onError: (Object _) {
          if (_ownsLoad(load)) _displayMatching.cancelLoad();
        },
      ),
    );
    return load;
  }

  Future<LineupPlaybackRequest> _loadPlayback(
    LineupPlaybackRequest request, {
    Duration? initialPosition,
  }) async {
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
    final loaded = await _loadPartAtPosition(
      request,
      target?.$1 ?? 0,
      target?.$2,
    );
    if (loaded == null) {
      throw const PlayerUnavailable('Playback load was superseded.');
    }
    return loaded;
  }

  Future<LineupPlaybackRequest?> _loadPartAtPosition(
    LineupPlaybackRequest request,
    int partIndex,
    Duration? position, {
    bool authorizationRetried = false,
    _AuthorizationRecovery? recovery,
  }) {
    if (recovery == null) _invalidateAuthorizationRecovery();
    final load = _startLoad(
      request.parts[partIndex].uri,
      request: request,
      partIndex: partIndex,
      target: position,
      authorizationRetried: authorizationRetried,
    );
    if (recovery != null) recovery.replacement = load;
    final operation = _completePartLoad(load);
    load.operation = operation;
    return operation;
  }

  bool _ownsLoad(_PlaybackLoad load) =>
      !_disposed &&
      load.tuneGeneration == _tuneGeneration &&
      identical(_activeLoad, load);

  Future<LineupPlaybackRequest?> _completePartLoad(_PlaybackLoad load) async {
    try {
      Object? failure;
      StackTrace? failureStack;
      try {
        await load.readiness;
      } catch (error, stack) {
        failure = error;
        failureStack = stack;
      }
      final recovery = load.recovery;
      if (recovery != null) {
        return await _completeLoadRecovery(recovery);
      }
      if (!_ownsLoad(load)) return null;
      if (failure != null) {
        Error.throwWithStackTrace(failure, failureStack!);
      }
      while (load.target != null) {
        final target = load.target!;
        if (_nativePosition != target) {
          try {
            await player.seek(target);
          } catch (_) {
            if (load.recovery case final recovery?) {
              return await _completeLoadRecovery(recovery);
            }
            rethrow;
          }
        }
        if (load.recovery case final recovery?) {
          return await _completeLoadRecovery(recovery);
        }
        if (!_ownsLoad(load)) return null;
        _nativePosition = target;
        if (load.target == target) load.target = null;
      }
      return load.request;
    } catch (error) {
      final recovery = load.recovery;
      final ownsFailure = recovery == null
          ? _ownsLoad(load)
          : identical(_authorizationRecovery, recovery) &&
                _ownsLoad(recovery.replacement ?? recovery.rejected);
      if (!ownsFailure) return null;
      if (identical(_active?.request, load.request)) {
        _reportUnexpectedPlaybackFailure(
          error,
          'while completing a playback part load',
        );
        await _failTransition(error, load.tuneGeneration);
        return null;
      }
      rethrow;
    } finally {
      load.pending = false;
    }
  }

  Future<LineupPlaybackRequest> _completeLoadRecovery(
    _AuthorizationRecovery recovery,
  ) async {
    final next = await recovery.result;
    if (!_disposed && recovery.rejected.tuneGeneration == _tuneGeneration) {
      _clearAuthorizationRecovery(recovery);
    }
    return next;
  }

  Future<LineupPlaybackRequest> _recoverAuthorization(
    _AuthorizationRecovery recovery,
    bool wasActive,
    Duration localPosition,
    Future<LineupPlaybackRequest> replacement,
  ) async {
    final rejected = recovery.rejected;
    final next = await replacement;
    if (!_ownsLoad(rejected) ||
        !identical(_authorizationRecovery, recovery) ||
        (wasActive && !identical(_active?.request, rejected.request))) {
      throw const _PlaybackSuperseded();
    }
    final loaded = await _loadPartAtPosition(
      next,
      rejected.partIndex.clamp(0, next.parts.length - 1),
      rejected.target ?? localPosition,
      authorizationRetried: true,
      recovery: recovery,
    );
    if (loaded == null ||
        !_ownsLoad(recovery.replacement!) ||
        (wasActive && !identical(_active?.request, rejected.request))) {
      throw const _PlaybackSuperseded();
    }
    if (wasActive) _replaceActiveRequest(next);
    return next;
  }

  static bool _isAuthorizationFailure(PlayerStatus status) =>
      status.failureCode == 'http_error' &&
      (status.httpStatus == 401 || status.httpStatus == 403);

  Future<LineupPlaybackRequest>? _authorizationRecoveryFor(
    LineupPlaybackRequest request,
    int generation,
  ) {
    final recovery = _authorizationRecovery;
    return recovery != null &&
            identical(request, recovery.rejected.request) &&
            generation == recovery.rejected.generation
        ? recovery.result
        : null;
  }

  void _clearAuthorizationRecovery(_AuthorizationRecovery recovery) {
    if (identical(_authorizationRecovery, recovery)) {
      _invalidateAuthorizationRecovery();
    }
  }

  void _invalidateAuthorizationRecovery() {
    _authorizationRecovery = null;
  }

  Future<void> _settleActiveAuthorization(
    _AuthorizationRecovery recovery,
  ) async {
    Future<void> fail(Object error) async {
      if (!_ownsAuthorizationRecoveryFailure(recovery)) return;
      await _failTransition(error, recovery.rejected.tuneGeneration);
    }

    try {
      await recovery.result;
      _clearAuthorizationRecovery(recovery);
      if (!_disposed) notifyListeners();
    } on _PlaybackSuperseded catch (error) {
      await fail(error);
    } catch (error) {
      if (_ownsAuthorizationRecoveryFailure(recovery)) {
        _reportUnexpectedPlaybackFailure(
          error,
          'while recovering playback authorization',
        );
      }
      await fail(error);
    }
  }

  bool _ownsAuthorizationRecoveryFailure(_AuthorizationRecovery recovery) =>
      identical(_authorizationRecovery, recovery) &&
      identical(_active?.request, recovery.rejected.request) &&
      _ownsLoad(recovery.replacement ?? recovery.rejected);

  bool _usesAggregateCoordinates(LineupPlaybackRequest request) =>
      request.parts.length == _partDurations.length &&
      request.parts.asMap().keys.every(_partDurations.containsKey);

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

  (int, Duration)? _interactivePartForPosition(
    LineupPlaybackRequest request,
    Duration position,
  ) {
    if (_usesAggregateCoordinates(request)) {
      return _partForPosition(request, position);
    }
    final load = _activeLoad;
    if (load == null ||
        load.request == null ||
        load.tuneGeneration != _tuneGeneration) {
      return null;
    }
    return (
      load.partIndex,
      position < Duration.zero ? Duration.zero : position,
    );
  }

  Future<void> _advancePart(
    LineupPlaybackRequest request,
    int completedGeneration,
  ) async {
    final tuneGeneration = _tuneGeneration;
    if (_disposed ||
        !identical(_active?.request, request) ||
        _activeLoadGeneration != completedGeneration) {
      if (_advancingGeneration == completedGeneration) {
        _advancingGeneration = null;
      }
      return;
    }
    if (_activePartIndex == request.parts.length - 1) {
      final ended = _active?.program;
      final channelId = _active?.channel?.id;
      if (ended != null && channelId != null) {
        await _tune(channelId, endedProgram: ended);
      } else {
        _retireEndedPlayback();
      }
      return;
    }
    await _loadPartAtPosition(request, _activePartIndex + 1, null);
    if (_advancingGeneration == completedGeneration) {
      _advancingGeneration = null;
    }
    if (!_disposed && tuneGeneration == _tuneGeneration) notifyListeners();
  }

  void _retireEndedPlayback() {
    _retirePlaybackIntent();
    _cancelOverlayTimer();
    if (_overlay != PlayerOverlay.error) _presentOverlay(PlayerOverlay.none);
    notifyListeners();
  }

  Future<void> _failPrematureEnd(int generation) {
    _status = const PlayerStatus(
      state: PlayerState.error,
      message: 'Playback error',
      recoverable: true,
      failureCode: 'premature_end',
    );
    return _failTransition(
      const PlayerUnavailable('Premature end', failureCode: 'premature_end'),
      generation,
    );
  }

  Future<void> _failTransition(Object error, int tuneGeneration) async {
    final nativeStop = _beginNativeStop();
    _invalidateAuthorizationRecovery();
    if (nativeStop != null) {
      try {
        await nativeStop;
      } catch (_) {}
    }
    if (_disposed || tuneGeneration != _tuneGeneration) return;
    _tuning = false;
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

  Future<void> togglePlayback() {
    final playing = displayHoldActive || _activeLoad?.pending == true
        ? !_userPaused
        : _status.state == PlayerState.playing;
    return playing ? pause() : play();
  }

  Future<void> play() => _setPlaybackPaused(false);

  Future<void> pause() => _setPlaybackPaused(true);

  Future<void> stop() async {
    _clearSleepTimer();
    final generation = ++_tuneGeneration;
    ++_controlGeneration;
    _tuning = false;
    _canRetry = false;
    _invalidateAuthorizationRecovery();
    final nativeStop = _beginNativeStop(force: true)!;
    if (!_disposed) notifyListeners();
    final operation = _tuneOperations.then((_) async {
      await nativeStop;
      if (_disposed || generation != _tuneGeneration) return;
      _status = const PlayerStatus(
        state: PlayerState.stopped,
        message: 'Stopped',
      );
      notifyListeners();
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
    final playback = _active?.request;
    final target = playback == null
        ? null
        : _interactivePartForPosition(playback, position);
    final load = _activeLoad;
    void fail(Object error) {
      if (_ownsSeek(seekGeneration, tuneGeneration)) {
        _publishControlFailure('seek', error);
      }
      return;
    }

    try {
      if (playback != null && target != null && load != null) {
        if (target.$1 != load.partIndex) {
          if (await _loadPartAtPosition(playback, target.$1, target.$2) ==
              null) {
            return;
          }
        } else if (load.pending || _authorizationRecovery != null) {
          load.target = target.$2;
          final recovery = _authorizationRecovery;
          if (load.pending) {
            if (await load.operation == null) return;
          } else if (recovery != null) {
            await recovery.result;
          }
        } else {
          await player.seek(target.$2);
        }
      } else {
        await player.seek(target?.$2 ?? position);
      }
    } on _PlaybackSuperseded catch (error) {
      fail(error);
      return;
    } catch (error) {
      if (_ownsSeek(seekGeneration, tuneGeneration)) {
        _reportUnexpectedPlaybackFailure(error, 'while seeking playback');
      }
      fail(error);
      return;
    }
    if (!_ownsSeek(seekGeneration, tuneGeneration)) return;
    showOsd();
  }

  Future<void> selectTrack(PlayerTrackType type, int? id) async {
    final trackSelectionGeneration = ++_trackSelectionGeneration;
    final tuneGeneration = _tuneGeneration;
    final loadGeneration = _activeLoadGeneration;
    _clearTrackSelection();
    _trackConfirmation = _TrackConfirmation(type: type, id: id);
    notifyListeners();
    try {
      await player.selectTrack(type, id);
      if (!_ownsTrackSelection(
            trackSelectionGeneration,
            tuneGeneration,
            loadGeneration,
          ) ||
          _trackConfirmation.type != type ||
          _trackConfirmation.id != id) {
        return;
      }
      _trackConfirmation.timer = Timer(_trackConfirmationTimeout, () {
        if (!_ownsTrackSelection(
              trackSelectionGeneration,
              tuneGeneration,
              loadGeneration,
            ) ||
            _trackConfirmation.type != type ||
            _trackConfirmation.id != id) {
          return;
        }
        _clearTrackSelection(error: 'Could not change this track. Try again.');
        _recordPlaybackFailure(
          const PlayerUnavailable(
            'Track selection confirmation timed out.',
            failureCode: 'wait_timeout',
          ),
          operation: type == PlayerTrackType.audio
              ? 'audio_track'
              : 'subtitle_track',
        );
        notifyListeners();
      });
    } catch (error) {
      if (_ownsTrackSelection(
            trackSelectionGeneration,
            tuneGeneration,
            loadGeneration,
          ) &&
          _trackConfirmation.type == type &&
          _trackConfirmation.id == id) {
        _clearTrackSelection(error: 'Could not change this track. Try again.');
        _recordPlaybackFailure(
          error,
          operation: type == PlayerTrackType.audio
              ? 'audio_track'
              : 'subtitle_track',
        );
        notifyListeners();
      }
    }
  }

  bool _ownsTrackSelection(
    int selectionGeneration,
    int tuneGeneration,
    int? loadGeneration,
  ) =>
      !_disposed &&
      selectionGeneration == _trackSelectionGeneration &&
      tuneGeneration == _tuneGeneration &&
      loadGeneration == _activeLoadGeneration;

  void _clearTrackSelection({String? error}) {
    _trackConfirmation.timer?.cancel();
    _trackConfirmation = _TrackConfirmation(error: error);
  }

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

  Future<void> _setPlaybackPaused(bool paused) async {
    if (_disposed) return;
    final intentRevision = ++_playbackIntentRevision;
    final controlGeneration = ++_controlGeneration;
    final tuneGeneration = _tuneGeneration;
    final load = _activeLoad;
    _userPaused = paused;
    if (paused) {
      _displayMatching.userPause();
    } else {
      _displayMatching.userPlay();
    }
    bool current() =>
        !_disposed &&
        intentRevision == _playbackIntentRevision &&
        tuneGeneration == _tuneGeneration &&
        identical(load, _activeLoad);
    try {
      if (!paused && await _expireSleepIfNeeded()) return;
      // Load applies its captured pause flag on the native worker. A control
      // must follow it, and only the latest intent may survive this wait.
      if (load != null) await load.readiness;
      if (!current()) return;
      await (paused ? player.pause() : player.play());
    } catch (error) {
      if (current() &&
          _ownsPlaybackControl(controlGeneration, tuneGeneration)) {
        _publishControlFailure(paused ? 'pause' : 'play', error);
      }
      return;
    }
    if (current() && _ownsPlaybackControl(controlGeneration, tuneGeneration)) {
      showOsd();
    }
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
    _showNotice('Playback controls are temporarily unavailable. Try again.');
  }

  void showOsd() {
    _sleepPickerOpen = false;
    _setOverlay(PlayerOverlay.osd);
  }

  void showNowPlaying() {
    if (currentProgram == null) return;
    _setOverlay(PlayerOverlay.nowPlaying, timed: false);
  }

  void showMiniGuide() {
    _miniGuideChannelId =
        lineup.currentChannelId ?? lineup.channels.firstOrNull?.id;
    final selected = miniGuideChannelIndex;
    _miniGuideWindowStart = _indexedChannels.length <= 5 || selected < 0
        ? 0
        : (selected - 2 + _indexedChannels.length) % _indexedChannels.length;
    _requestMiniGuideRows();
    _setOverlay(PlayerOverlay.miniGuide, timed: false);
  }

  void showFullGuide() {
    final selected = miniGuideChannelId;
    if (_overlay == PlayerOverlay.miniGuide && selected != null) {
      final target = guide.channels.indexWhere(
        (channel) => channel.id == selected,
      );
      if (target >= 0) guide.moveVertical(target - guide.focusedChannelIndex);
    }
    _setOverlay(PlayerOverlay.fullGuide, timed: false);
  }

  void showSleepTimer() {
    if (_overlay != PlayerOverlay.osd) {
      _setOverlay(PlayerOverlay.osd, timed: false);
    } else {
      _cancelOverlayTimer();
    }
    _sleepPickerOpen = true;
    notifyListeners();
  }

  void showTracks(PlayerTrackType type) {
    if (_overlay != PlayerOverlay.none &&
        _overlay != PlayerOverlay.osd &&
        _overlay != PlayerOverlay.nowPlaying) {
      return;
    }
    if (type != PlayerTrackType.subtitle &&
        !_tracks.any((track) => track.type == type)) {
      return;
    }
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
    if (!miniGuideChannels.any(
      (channel) => channel.id == _miniGuideChannelId,
    )) {
      _miniGuideWindowStart = (next - 2 + channels.length) % channels.length;
    }
    _requestMiniGuideRows();
    _setOverlay(PlayerOverlay.miniGuide, timed: false);
  }

  void focusMiniGuideChannel(String channelId) {
    if (!_channelIndexById.containsKey(channelId)) return;
    _miniGuideChannelId = channelId;
    _requestMiniGuideRows();
    _setOverlay(PlayerOverlay.miniGuide, timed: false);
  }

  Future<void> tuneMiniGuideSelection() async {
    final id = miniGuideChannelId;
    if (id != null) await tune(id);
  }

  void closeOverlay() {
    if (_overlay == PlayerOverlay.channelNumber) {
      _numberTimer?.cancel();
      _numberTimer = null;
      _channelNumber = '';
    }
    if (_sleepPickerOpen) {
      closeSleepPicker();
      return;
    }
    if (_overlay == PlayerOverlay.audioTracks ||
        _overlay == PlayerOverlay.subtitleTracks) {
      showOsd();
      return;
    }
    _cancelOverlayTimer();
    _presentOverlay(PlayerOverlay.none);
    notifyListeners();
  }

  /// Dismiss the sleep picker before another OSD action runs.
  ///
  /// The picker is a sub-state of the OSD, so dismissing it must not create a
  /// new overlay presentation. Its normal OSD timeout resumes after the
  /// action, while focus-driven suspension remains authoritative.
  void closeSleepPicker() {
    if (!_sleepPickerOpen) return;
    _sleepPickerOpen = false;
    if (_overlay == PlayerOverlay.osd) {
      _scheduleOverlayHide(PlayerOverlay.osd);
    }
    notifyListeners();
  }

  void overlayFocusChanged(
    PlayerOverlay overlay,
    int presentationGeneration,
    bool focused,
  ) {
    if (_overlay != overlay ||
        _overlayPresentationGeneration != presentationGeneration ||
        overlay != PlayerOverlay.osd) {
      return;
    }
    if (focused) {
      _overlayFocusSuspended = true;
      _cancelOverlayTimer();
      return;
    }
    if (!_overlayFocusSuspended) return;
    _overlayFocusSuspended = false;
    _scheduleOverlayHide(overlay);
  }

  void appendChannelDigit(String digit) {
    if (!RegExp(r'^\d$').hasMatch(digit)) return;
    _channelNumber = '$_channelNumber$digit';
    if (_channelNumber.length > 4) _channelNumber = digit;
    _noticeTimer?.cancel();
    _notice = null;
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
      closeOverlay();
      _showNotice('Not in this lineup', duration: const Duration(seconds: 3));
      return;
    }
    await tune(channel.id);
  }

  void setSleepTimer(Duration? duration) {
    final epoch = ++_sleepEpoch;
    _sleepTimer?.cancel();
    _sleepDuration = duration;
    _sleepDeadline = duration == null ? null : _clock().add(duration);
    if (duration != null) {
      _sleepTimer = Timer(duration, () => _expireSleepTimer(epoch));
    }
    showOsd();
  }

  Future<bool> _expireSleepIfNeeded() async {
    final deadline = _sleepDeadline;
    if (deadline == null || _clock().isBefore(deadline)) return false;
    await _expireSleepTimer(_sleepEpoch);
    return true;
  }

  Future<void> checkSleepDeadline() async {
    await _expireSleepIfNeeded();
  }

  Future<void> _expireSleepTimer(int epoch) async {
    if (_disposed || epoch != _sleepEpoch) return;
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepDuration = null;
    _sleepDeadline = null;
    final tuneGeneration = ++_tuneGeneration;
    ++_controlGeneration;
    _tuning = false;
    _canRetry = false;
    _invalidateAuthorizationRecovery();
    final nativeStop = _beginNativeStop(force: true)!;
    try {
      await nativeStop;
    } catch (error) {
      if (_disposed ||
          epoch != _sleepEpoch ||
          tuneGeneration != _tuneGeneration) {
        return;
      }
      _recordPlaybackFailure(error);
      _showNotice(
        'Playback could not be stopped when the sleep timer expired.',
      );
      return;
    }
    if (_disposed ||
        epoch != _sleepEpoch ||
        tuneGeneration != _tuneGeneration) {
      return;
    }
    _releaseActive();
    _telemetry = const PlayerTelemetry();
    _tracks = const [];
    _status = const PlayerStatus(
      state: PlayerState.stopped,
      message: 'Playback stopped by timer',
    );
    _presentOverlay(PlayerOverlay.none);
    notifyListeners();
  }

  void _clearSleepTimer() {
    ++_sleepEpoch;
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepDuration = null;
    _sleepDeadline = null;
  }

  void showCursor() {
    _cursorTimer?.cancel();
    _cursorIdle = false;
    if (!_cursorVisible) {
      _cursorVisible = true;
      notifyListeners();
    }
    _cursorTimer = Timer(const Duration(seconds: 3), () {
      _cursorIdle = true;
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
    } else if (_overlay == PlayerOverlay.osd) {
      _overlayFocusSuspended = false;
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
    if ((_overlayFocusSuspended || _sleepPickerOpen) && _overlay == value) {
      return;
    }
    final epoch = ++_overlayEpoch;
    _overlayTimer = Timer(
      timeout ??
          overlayTimeout ??
          Duration(seconds: lineup.settings.osdAutoHideSeconds),
      () {
        if (_disposed || epoch != _overlayEpoch || _overlay != value) return;
        _overlayTimer = null;
        _presentOverlay(PlayerOverlay.none);
        if (_status.state == PlayerState.playing && _cursorIdle) {
          _cursorVisible = false;
        }
        notifyListeners();
      },
    );
  }

  void _presentOverlay(PlayerOverlay value) {
    _overlayPresentationGeneration++;
    _overlayFocusSuspended = false;
    _sleepPickerOpen = false;
    _overlay = value;
  }

  void _cancelOverlayTimer() {
    _overlayEpoch++;
    _overlayTimer?.cancel();
    _overlayTimer = null;
  }

  void _lineupChanged() {
    final activeChannel = _active?.channel;
    final replacement = activeChannel == null
        ? null
        : lineup.channels
              .where((channel) => channel.id == activeChannel.id)
              .firstOrNull;
    final activeChannelChanged =
        activeChannel != null &&
        (replacement == null ||
            canonicalScheduleIdentity(replacement) !=
                canonicalScheduleIdentity(activeChannel));
    if (activeChannel != null && replacement != null && !activeChannelChanged) {
      _refreshActiveChannel(replacement);
    }
    if (_contentGeneration != lineup.contentGeneration ||
        activeChannelChanged) {
      _contentGeneration = lineup.contentGeneration;
      ++_controlGeneration;
      ++_seekGeneration;
      final fullscreenCleanup = _queueFullscreenReset();
      if (_active != null || _tuning || _nativeCleanupRequired) {
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
    _clearTransientStatus();
    _cancelOverlayTimer();
    _clearSleepTimer();
    _cursorTimer?.cancel();
    _cursorTimer = null;
    _cursorVisible = true;
    _cursorIdle = false;
    _presentOverlay(PlayerOverlay.none);
    _miniGuideChannelId = null;
    _miniGuideWindowStart = null;
    _retryChannelId = null;
    _releaseActive();
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
    } catch (_) {}
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
    _displayMatching.cancelLoad();
    ++_trackSelectionGeneration;
    _clearTrackSelection();
    _activeLoad = null;
    _resolvingProgram = null;
    _advancingGeneration = null;
    _releaseActive();
  }

  void _reportUnexpectedPlaybackFailure(Object error, String context) {
    switch (error) {
      case PlayerUnavailable() ||
          PlexException() ||
          LineupScopeSuperseded() ||
          _PlaybackSuperseded() ||
          TimeoutException() ||
          PlatformException() ||
          FileSystemException():
        return;
      default:
        // Caught values and stacks may contain media URLs or credentials. The
        // report is deliberately new, fixed data, just like cleanup reporting.
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: StateError('Unexpected playback operation failure.'),
            library: 'Lineup Desktop',
            context: ErrorDescription(context),
          ),
        );
    }
  }

  void _recordPlaybackFailure(Object error, {String operation = 'request'}) {
    final rawCode = switch (error) {
      PlexException(:final code) => code,
      PlayerUnavailable(:final failureCode) => failureCode,
      _ => 'unexpected',
    };
    final code = Diagnostics.failureCategory(rawCode) ?? 'unexpected';
    lineup.diagnostics.add(DiagnosticEvent.playbackRequestFailed, {
      if (operation != 'request') 'operation': operation,
      'code': code,
    });
  }

  static String _safePlaybackError(Object error) => switch (error) {
    PlexException(:final message) => message,
    PlayerUnavailable(failureCode: 'premature_end') =>
      'Playback ended before the program finished.',
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
    _clearTransientStatus();
    if (_disposed) return;
    final fullscreenReset = _queueFullscreenReset();
    _disposed = true;
    _displayMatching.dispose();
    unawaited(_cancelPlayerSubscription(_displaySubscription));
    _displaySubscription = null;
    ++_tuneGeneration;
    ++_controlGeneration;
    ++_sleepEpoch;
    _activeLoad = null;
    _tuning = false;
    lineup.removeListener(_lineupChanged);
    guide.removeListener(_guideChanged);
    unawaited(_cancelPlayerSubscription(_subscription));
    _subscription = null;
    _cancelOverlayTimer();
    _sleepTimer?.cancel();
    _cursorTimer?.cancel();
    _clearTrackSelection();
    _releaseActive();
    _resolvingProgram = null;
    unawaited(fullscreenReset.catchError((_) {}));
    super.dispose();
  }

  Future<void> _cancelPlayerSubscription(
    StreamSubscription<Object?>? subscription,
  ) async {
    try {
      await subscription?.cancel();
    } catch (_) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: StateError('Native player subscription cleanup failed.'),
          library: 'Lineup Desktop',
          context: ErrorDescription('while cancelling native player events'),
        ),
      );
    }
  }
}

final class _PlaybackSuperseded implements Exception {
  const _PlaybackSuperseded();
}

// Authorization refresh and channel metadata updates retain this session identity.
final class _ActiveProgram {
  _ActiveProgram({
    required this.request,
    required this.channel,
    required this.program,
  });

  LineupPlaybackRequest request;
  Channel? channel;
  final GuideProgram program;
}

final class _TrackConfirmation {
  _TrackConfirmation({this.type, this.id, this.error});

  final PlayerTrackType? type;
  final int? id;
  final String? error;
  Timer? timer;
}

class _PlaybackLoad {
  _PlaybackLoad({
    required this.generation,
    required this.tuneGeneration,
    required this.request,
    required this.partIndex,
    required this.target,
    required this.replacing,
    required this.authorizationRetried,
  }) : startTarget = target;

  final int generation;
  final int tuneGeneration;
  final LineupPlaybackRequest? request;
  final int partIndex;
  final bool authorizationRetried;
  final Duration? startTarget;
  Duration lastPositivePosition = Duration.zero;
  Duration? lastPositiveDuration;
  Duration? target;
  bool replacing;
  bool pending = true;
  late final Future<void> readiness;
  Future<LineupPlaybackRequest?>? operation;
  _AuthorizationRecovery? recovery;
}

class _AuthorizationRecovery {
  _AuthorizationRecovery(this.rejected);

  final _PlaybackLoad rejected;
  _PlaybackLoad? replacement;
  late final Future<LineupPlaybackRequest> result;
}
