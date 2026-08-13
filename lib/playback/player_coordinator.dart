import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app/lineup_controller.dart';
import '../channels/channel.dart';
import '../guide/guide_controller.dart';
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
    this.overlayTimeout = const Duration(seconds: 4),
  }) {
    _indexChannels();
    _status = player.status;
    _position = player.position;
    _duration = player.duration;
    _telemetry = player.telemetry;
    _tracks = player.tracks;
    _subscription = player.events.listen(_event);
    lineup.addListener(_lineupChanged);
    guide.addListener(_guideChanged);
  }

  final NativePlayer player;
  final LineupController lineup;
  final GuideController guide;
  final Duration overlayTimeout;
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
  PlayerOverlay _overlay = PlayerOverlay.none;
  String _channelNumber = '';
  String? _miniGuideChannelId;
  String? _error;
  bool _fullscreen = false;
  bool _cursorVisible = true;
  bool _tuning = false;
  Duration? _sleepDuration;
  int _tuneGeneration = 0;
  Future<void> _tuneOperations = Future.value();
  bool _disposed = false;
  LineupPlaybackRequest? _activePlayback;
  List<Channel> _indexedChannels = const [];
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
  String? get error => _error;
  bool get fullscreen => _fullscreen;
  bool get cursorVisible => _cursorVisible;
  bool get tuning => _tuning;
  Duration? get sleepDuration => _sleepDuration;
  Channel? get currentChannel {
    final index = _channelIndexById[lineup.currentChannelId];
    return index == null ? null : _indexedChannels[index];
  }

  GuideProgram? get currentProgram {
    final id = lineup.currentChannelId;
    return id == null ? null : guide.currentProgram(id);
  }

  void _event(PlayerEvent event) {
    _status = event.status;
    _position = event.position;
    _duration = event.duration;
    _telemetry = event.telemetry;
    _tracks = event.tracks;
    if (event.status.state == PlayerState.error) {
      _error = event.status.message;
      _tuning = false;
      final playback = _activePlayback;
      _activePlayback = null;
      unawaited(_release(playback));
      _setOverlay(PlayerOverlay.error, timed: false);
    } else if (event.status.state == PlayerState.loading) {
      _overlayTimer?.cancel();
    }
    notifyListeners();
  }

  Future<void> tune(String channelId) {
    final generation = ++_tuneGeneration;
    _tuning = true;
    _error = null;
    _overlayTimer?.cancel();
    _overlay = PlayerOverlay.osd;
    notifyListeners();
    final operation = _tuneOperations.then(
      (_) => _performTune(channelId, generation),
    );
    _tuneOperations = operation.catchError((_) {});
    return operation;
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
      _error = 'The current program could not be loaded.';
      _setOverlay(PlayerOverlay.error, timed: false);
      return;
    }
    LineupPlaybackRequest? request;
    final previousChannelId = lineup.currentChannelId;
    try {
      request = lineup.playbackFor(program.scheduled.item.id);
      await player.load(request.uri);
      if (generation != _tuneGeneration) {
        if (_disposed) await _stopQuietly();
        await _release(request);
        return;
      }
      final replaced = _activePlayback;
      _activePlayback = request;
      unawaited(_release(replaced));
      final elapsed = DateTime.now().difference(program.scheduled.start);
      if (elapsed > const Duration(seconds: 2)) await player.seek(elapsed);
      if (generation != _tuneGeneration) {
        if (identical(_activePlayback, request)) _activePlayback = null;
        if (_disposed) await _stopQuietly();
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
        if (_disposed) await _stopQuietly();
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
      showOsd();
    } catch (error) {
      if (identical(_activePlayback, request)) {
        _activePlayback = null;
      }
      if (request != null) await _stopQuietly();
      await _release(request);
      if (generation != _tuneGeneration) return;
      _tuning = false;
      _error = error.toString();
      _setOverlay(PlayerOverlay.error, timed: false);
    }
  }

  Future<void> retry() async {
    final id = currentChannel?.id;
    if (id != null) await tune(id);
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
    notifyListeners();
    final operation = _tuneOperations.then((_) async {
      final playback = _activePlayback;
      _activePlayback = null;
      try {
        await player.stop();
      } finally {
        await _release(playback);
      }
    });
    _tuneOperations = operation.catchError((_) {});
    await operation;
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

  Future<void> selectTrack(PlayerTrackType type, int? id) async {
    await player.selectTrack(type, id);
    showOsd();
  }

  Future<void> toggleFullscreen() async {
    final next = !_fullscreen;
    await player.setFullscreen(next);
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
    _overlayTimer?.cancel();
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

  void _setOverlay(
    PlayerOverlay value, {
    bool timed = true,
    Duration? timeout,
  }) {
    _overlayTimer?.cancel();
    _overlay = value;
    notifyListeners();
    if (timed && _status.state == PlayerState.playing) {
      _overlayTimer = Timer(timeout ?? overlayTimeout, () {
        if (_overlay == value) {
          _overlay = PlayerOverlay.none;
          notifyListeners();
        }
      });
    }
  }

  void _lineupChanged() {
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

  void _requestMiniGuideRows() {
    final selected = miniGuideChannelIndex;
    if (selected < 0) return;
    final start = (selected - 3).clamp(0, _indexedChannels.length);
    final end = (start + 7).clamp(0, _indexedChannels.length);
    guide.requestChannels(_indexedChannels.getRange(start, end));
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
    _disposed = true;
    ++_tuneGeneration;
    _tuning = false;
    lineup.removeListener(_lineupChanged);
    guide.removeListener(_guideChanged);
    _subscription?.cancel();
    _overlayTimer?.cancel();
    _sleepTimer?.cancel();
    _numberTimer?.cancel();
    _cursorTimer?.cancel();
    final playback = _activePlayback;
    _activePlayback = null;
    unawaited(_release(playback));
    super.dispose();
  }
}
