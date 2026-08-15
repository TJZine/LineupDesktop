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
  miniGuide,
  fullGuide,
  audioTracks,
  subtitleTracks,
  channelNumber,
  error,
}

class PlayerCoordinator extends ChangeNotifier {
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
  late PlayerTelemetry _telemetry;
  late List<PlayerTrack> _tracks;
  StreamSubscription<PlayerEvent>? _subscription;
  Timer? _overlayTimer;
  Timer? _sleepTimer;
  Timer? _numberTimer;
  Timer? _cursorTimer;
  int _overlayEpoch = 0;
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
  int? _activeLoadGeneration;
  Future<void> _tuneOperations = Future.value();
  Future<void> _scopeCleanup = Future.value();
  bool _scopeCleanupPending = false;
  bool _disposed = false;
  bool _initialMediaRequested = false;
  LineupPlaybackRequest? _activePlayback;
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
    if (event.generation != null && event.generation != _activeLoadGeneration) {
      return;
    }
    _status = event.status.state == PlayerState.error
        ? PlayerStatus(
            state: PlayerState.error,
            message: 'Playback error',
            recoverable: event.status.recoverable,
          )
        : event.status;
    _position = event.position;
    _duration = event.duration;
    _telemetry = event.telemetry;
    _tracks = event.tracks;
    if (event.status.state == PlayerState.error) {
      final audioCodec = event.tracks
          .where(
            (track) => track.type == PlayerTrackType.audio && track.selected,
          )
          .firstOrNull
          ?.codec;
      lineup.diagnostics.add('playback', 'Native playback failed', {
        'reason': event.status.message,
        'videoCodec': event.telemetry.videoCodec,
        'audioCodec': audioCodec,
        'videoOutput': event.telemetry.videoOutput,
        'hardwareDecoder': event.telemetry.hardwareDecoder,
      });
      _activeLoadGeneration = null;
      _error =
          'Playback stopped unexpectedly. Retry or choose another channel.';
      _tuning = false;
      _canRetry = event.status.recoverable && _retryChannelId != null;
      final playback = _activePlayback;
      _activePlayback = null;
      _activeChannel = null;
      unawaited(_release(playback));
      _setOverlay(PlayerOverlay.error, timed: false);
    } else {
      switch (event.status.state) {
        case PlayerState.loading:
          _cancelOverlayTimer();
          if (_overlay == PlayerOverlay.osd) _overlay = PlayerOverlay.none;
          break;
        case PlayerState.ready:
        case PlayerState.paused:
        case PlayerState.buffering:
        case PlayerState.seeking:
          _setOverlay(PlayerOverlay.osd, timed: false);
          break;
        case PlayerState.playing:
          if (_overlay == PlayerOverlay.osd) _scheduleOverlayHide(_overlay);
          break;
        case PlayerState.ended:
        case PlayerState.stopped:
          _activeLoadGeneration = null;
          _cancelOverlayTimer();
          if (_overlay != PlayerOverlay.error) {
            _overlay = PlayerOverlay.none;
          }
          final playback = _activePlayback;
          _activePlayback = null;
          _activeChannel = null;
          unawaited(_release(playback));
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

  Future<void> tune(String channelId) {
    final generation = ++_tuneGeneration;
    _tuning = true;
    _canRetry = false;
    _error = null;
    _retryChannelId = channelId;
    _cancelOverlayTimer();
    _overlay = PlayerOverlay.osd;
    notifyListeners();
    final operation = _tuneOperations.then(
      (_) => _performTune(channelId, generation),
    );
    _tuneOperations = operation.catchError((_) {});
    return operation;
  }

  Future<void> loadInitialMedia(Uri media) async {
    if (_initialMediaRequested) return;
    _initialMediaRequested = true;
    final generation = ++_tuneGeneration;
    try {
      await _load(media, generation);
      if (!_disposed && generation == _tuneGeneration) showOsd();
    } catch (error) {
      if (_disposed || generation != _tuneGeneration) return;
      _recordPlaybackFailure(error);
      _error = _safePlaybackError(error);
      _canRetry = false;
      _setOverlay(PlayerOverlay.error, timed: false);
    }
  }

  Future<void> _performTune(String channelId, int generation) async {
    if (generation != _tuneGeneration) return;
    GuideProgram? program;
    try {
      program = await guide.ensureCurrentProgram(channelId);
    } on TimeoutException {
      program = null;
    }
    if (generation != _tuneGeneration) return;
    if (program == null) {
      _tuning = false;
      _canRetry = true;
      _error = 'The current program could not be loaded.';
      _setOverlay(PlayerOverlay.error, timed: false);
      return;
    }
    LineupPlaybackRequest? request;
    final previousChannelId = lineup.currentChannelId;
    try {
      request = lineup.playbackFor(program.scheduled.item.id);
      await _load(request.uri, generation, plexToken: request.plexToken);
      if (generation != _tuneGeneration) {
        if (_tuning || _disposed) await _stopQuietly();
        await _release(request);
        return;
      }
      final replaced = _activePlayback;
      _activePlayback = request;
      _activeChannel = lineup.channels
          .where((channel) => channel.id == channelId)
          .firstOrNull;
      unawaited(_release(replaced));
      final elapsed = DateTime.now().difference(program.scheduled.start);
      if (elapsed > const Duration(seconds: 2)) await player.seek(elapsed);
      if (generation != _tuneGeneration) {
        if (identical(_activePlayback, request)) {
          _activePlayback = null;
          _activeChannel = null;
        }
        if (_tuning || _disposed) await _stopQuietly();
        await _release(request);
        return;
      }
      if (!identical(_activePlayback, request)) {
        await _stopQuietly();
        await _release(request);
        return;
      }
      await lineup.setCurrentChannel(channelId);
      if (generation != _tuneGeneration) {
        if (identical(_activePlayback, request)) _activePlayback = null;
        if (lineup.currentChannelId == channelId &&
            previousChannelId != channelId) {
          await lineup.setCurrentChannel(previousChannelId);
        }
        if (_tuning || _disposed) await _stopQuietly();
        await _release(request);
        return;
      }
      if (!identical(_activePlayback, request)) {
        if (lineup.currentChannelId == channelId &&
            previousChannelId != channelId) {
          await lineup.setCurrentChannel(previousChannelId);
        }
        await _stopQuietly();
        await _release(request);
        return;
      }
      _tuning = false;
      _canRetry = false;
      showOsd();
    } catch (error) {
      if (identical(_activePlayback, request)) {
        _activePlayback = null;
        _activeChannel = null;
      }
      if (request != null) await _stopQuietly();
      await _release(request);
      if (generation != _tuneGeneration) return;
      _tuning = false;
      _canRetry = true;
      _recordPlaybackFailure(error);
      _error = _safePlaybackError(error);
      _setOverlay(PlayerOverlay.error, timed: false);
    }
  }

  Future<void> retry() async {
    final id = _retryChannelId ?? currentChannel?.id;
    if (id != null) await tune(id);
  }

  Future<void> _load(Uri media, int generation, {String? plexToken}) {
    _activeLoadGeneration = generation;
    return player.load(media, plexToken: plexToken, generation: generation);
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
      _status.state == PlayerState.playing ? player.pause() : player.play();

  Future<void> stop() async {
    ++_tuneGeneration;
    _tuning = false;
    _canRetry = false;
    if (!_disposed) notifyListeners();
    final operation = _tuneOperations.then((_) async {
      final playback = _activePlayback;
      _activePlayback = null;
      _activeChannel = null;
      try {
        await player.stop();
      } finally {
        await _release(playback);
      }
    });
    _tuneOperations = operation.catchError((_) {});
    await operation;
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
    return player.seek(target);
  }

  Future<void> seekTo(Duration position) async {
    await player.seek(position);
    showOsd();
  }

  Future<void> selectTrack(PlayerTrackType type, int? id) async {
    await player.selectTrack(type, id);
    showOsd();
  }

  Future<void> toggleFullscreen() async {
    final next = !_fullscreen;
    await player.setFullscreen(next);
    if (_disposed) return;
    _fullscreen = next;
    notifyListeners();
  }

  void showOsd() => _setOverlay(PlayerOverlay.osd);
  void showMiniGuide() {
    _miniGuideChannelId =
        lineup.currentChannelId ?? lineup.channels.firstOrNull?.id;
    _requestMiniGuideRows();
    _setOverlay(PlayerOverlay.miniGuide, timeout: const Duration(seconds: 8));
  }

  void showFullGuide() => _setOverlay(PlayerOverlay.fullGuide, timed: false);

  void showTracks(PlayerTrackType type) {
    if (_overlay != PlayerOverlay.osd) return;
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
    _overlay = PlayerOverlay.none;
    notifyListeners();
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
        await stop();
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
    _overlay = value;
    notifyListeners();
    if (timed && _status.state == PlayerState.playing) {
      _scheduleOverlayHide(value, timeout: timeout);
    }
  }

  void _scheduleOverlayHide(PlayerOverlay value, {Duration? timeout}) {
    _overlayTimer?.cancel();
    final epoch = ++_overlayEpoch;
    _overlayTimer = Timer(
      timeout ??
          overlayTimeout ??
          Duration(seconds: lineup.settings.osdAutoHideSeconds),
      () {
        if (_disposed || epoch != _overlayEpoch || _overlay != value) return;
        _overlayTimer = null;
        _overlay = PlayerOverlay.none;
        notifyListeners();
      },
    );
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
      if (_activePlayback != null || _tuning || _activeLoadGeneration != null) {
        if (!_scopeCleanupPending) {
          _scopeCleanupPending = true;
          _scopeCleanup = _stopForScopeChange()
              .catchError((Object error) {
                _recordPlaybackFailure(error);
              })
              .whenComplete(() => _scopeCleanupPending = false);
        }
      } else {
        _resetScopeState();
      }
    }
    if (_osdAutoHideSeconds != lineup.settings.osdAutoHideSeconds) {
      _osdAutoHideSeconds = lineup.settings.osdAutoHideSeconds;
      if (overlayTimeout == null &&
          _overlay == PlayerOverlay.osd &&
          _status.state == PlayerState.playing) {
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
    if (_overlay == PlayerOverlay.miniGuide || _overlay == PlayerOverlay.osd) {
      notifyListeners();
    }
  }

  Future<void> _stopForScopeChange() async {
    final wasFullscreen = _fullscreen;
    _resetScopeState();
    if (wasFullscreen) {
      try {
        await player.setFullscreen(false);
      } catch (error) {
        if (!_disposed) _recordPlaybackFailure(error);
      }
    }
    if (_disposed) return;
    await stop();
  }

  void _resetScopeState() {
    _cancelOverlayTimer();
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepDuration = null;
    _numberTimer?.cancel();
    _numberTimer = null;
    _channelNumber = '';
    _cursorTimer?.cancel();
    _cursorTimer = null;
    _cursorVisible = true;
    _overlay = PlayerOverlay.none;
    _miniGuideChannelId = null;
    _retryChannelId = null;
    _activeChannel = null;
    _error = null;
    _fullscreen = false;
  }

  void _requestMiniGuideRows() {
    guide.requestChannels(miniGuideChannels);
  }

  Future<void> _release(LineupPlaybackRequest? playback) async {
    if (playback == null) return;
    try {
      await playback.release();
    } catch (_) {
      // Playback lease cleanup is best effort.
    }
  }

  Future<void> _stopQuietly() async {
    try {
      await player.stop();
    } catch (_) {
      // The original tune failure remains the useful error.
    }
  }

  void _recordPlaybackFailure(Object error) {
    lineup.diagnostics.add('playback', 'Playback request failed', {
      'error': error.toString(),
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
    _disposed = true;
    ++_tuneGeneration;
    _activeLoadGeneration = null;
    _tuning = false;
    lineup.removeListener(_lineupChanged);
    guide.removeListener(_guideChanged);
    _subscription?.cancel();
    _cancelOverlayTimer();
    _sleepTimer?.cancel();
    _numberTimer?.cancel();
    _cursorTimer?.cancel();
    final playback = _activePlayback;
    _activePlayback = null;
    unawaited(_release(playback));
    super.dispose();
  }
}
