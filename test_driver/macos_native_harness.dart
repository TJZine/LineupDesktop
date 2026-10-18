import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lineup_desktop/app/lineup_app.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/playback/method_channel_native_player.dart';
import 'package:lineup_desktop/playback/native_player.dart';

import 'ui_harness.dart' show HarnessController;

/// Real-protocol development harness: the synthetic [HarnessController]
/// composition from `ui_harness.dart`, but with the production
/// [MethodChannelNativePlayer] and local media files.
///
/// `--dart-define=LINEUP_HARNESS_MEDIA=<path>[|<path>...]` lists absolute
/// media paths; channel N plays path N modulo the list length. With
/// `--dart-define=LINEUP_HARNESS_EXERCISE=true` the harness also drives a
/// load per media file, seek, volume, track selection, fullscreen, the video
/// rectangle, and stop through the real player. Every call outcome, state change, telemetry
/// change, and display report is printed with a `[harness]` prefix; media
/// paths are never printed. See docs/DEVELOPMENT.md.
void main() {
  final media = _mediaFromEnvironment();
  final player = HarnessLoggingPlayer(MethodChannelNativePlayer());
  final controller = LocalMediaHarnessController(media);
  runApp(LineupBootstrap(player: player, controller: controller));
  if (const bool.fromEnvironment('LINEUP_HARNESS_EXERCISE')) {
    unawaited(_exercise(player, media));
  }
}

List<Uri> _mediaFromEnvironment() {
  const configured = String.fromEnvironment('LINEUP_HARNESS_MEDIA');
  final media = [
    for (final path in configured.split('|'))
      if (path.isNotEmpty) Uri.file(path),
  ];
  if (media.isEmpty) {
    throw StateError(
      'Set --dart-define=LINEUP_HARNESS_MEDIA=<path>[|<path>...] to local '
      'media files the app can read.',
    );
  }
  return media;
}

void _log(String message) => debugPrint('[harness] $message');

/// Plays local media for the synthetic channels: `synthetic-<channel>-<n>`
/// items of channel index `channel` use media `channel % media.length`.
class LocalMediaHarnessController extends HarnessController {
  LocalMediaHarnessController(this.media);

  final List<Uri> media;

  @override
  LineupPlaybackRequest playbackFor(String itemId) {
    final channel = int.tryParse(itemId.split('-')[1]) ?? 0;
    return LineupPlaybackRequest.parts([
      LineupPlaybackPart(uri: media[channel % media.length]),
    ]);
  }
}

/// Forwards to the real player and logs each call's outcome and the
/// observable state it produces, without media identity.
class HarnessLoggingPlayer implements NativePlayer {
  HarnessLoggingPlayer(this._player) {
    _player.events.listen(_logEvent);
    _player.displayReports.listen(
      (report) => _log(
        'display revision=${report.revision} session=${report.session.name} '
        'outcome=${report.outcome.name} reason=${report.reason?.name} '
        'route=${report.route.name} activeColorMode=${report.activeColorMode}',
      ),
    );
  }

  @override
  bool get fullscreen => _player.fullscreen;
  @override
  Stream<bool> get fullscreenChanges => _player.fullscreenChanges;

  final NativePlayer _player;
  final _playing = StreamController<void>.broadcast();
  PlayerStatus? _lastStatus;
  PlayerTelemetry? _lastTelemetry;
  int? _lastTrackCount;

  /// Fires on every transition into [PlayerState.playing].
  Stream<void> get playing => _playing.stream;

  void _logEvent(PlayerEvent event) {
    final status = event.status;
    if (status.state != _lastStatus?.state ||
        status.message != _lastStatus?.message ||
        status.failureCode != _lastStatus?.failureCode) {
      _log(
        'state=${status.state.name} message="${status.message}" '
        'failure=${status.failureCode} generation=${event.generation}',
      );
      if (status.state == PlayerState.playing &&
          _lastStatus?.state != PlayerState.playing) {
        _playing.add(null);
      }
      _lastStatus = status;
    }
    final telemetry = event.telemetry;
    if (telemetry != _lastTelemetry) {
      _lastTelemetry = telemetry;
      _log(
        'telemetry vo=${telemetry.videoOutput} '
        'hwdec=${telemetry.hardwareDecoder} codec=${telemetry.videoCodec} '
        'size=${telemetry.width}x${telemetry.height} '
        'pixfmt=${telemetry.pixelFormat}/${telemetry.hardwarePixelFormat} '
        'primaries=${telemetry.primaries} gamma=${telemetry.gamma} '
        'colormatrix=${telemetry.colorMatrix} peak=${telemetry.signalPeak} '
        'target=${telemetry.targetGamma}/${telemetry.targetPrimaries}/'
        '${telemetry.targetPixelFormat}',
      );
    }
    if (event.tracks.length != _lastTrackCount) {
      _lastTrackCount = event.tracks.length;
      _log(
        'tracks ${[for (final track in event.tracks) '${track.type.name}:${track.id}${track.selected ? '*' : ''}'].join(' ')}',
      );
    }
  }

  Future<T> _call<T>(String name, Future<T> Function() call) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result = await call();
      _log('$name ok ${stopwatch.elapsedMilliseconds}ms');
      return result;
    } catch (error) {
      _log('$name failed ${stopwatch.elapsedMilliseconds}ms: $error');
      rethrow;
    }
  }

  @override
  PlayerStatus get status => _player.status;
  @override
  Duration get position => _player.position;
  @override
  Duration get duration => _player.duration;
  @override
  PlayerTelemetry get telemetry => _player.telemetry;
  @override
  List<PlayerTrack> get tracks => _player.tracks;
  @override
  DisplayMatchingReport get displayReport => _player.displayReport;
  @override
  Stream<PlayerEvent> get events => _player.events;
  @override
  Stream<DisplayMatchingReport> get displayReports => _player.displayReports;

  final _initialized = Completer<void>();

  /// Completes when the real player's initialize call succeeds.
  Future<void> get initialized => _initialized.future;

  @override
  Future<void> initialize() async {
    await _call('initialize', _player.initialize);
    if (!_initialized.isCompleted) _initialized.complete();
  }

  @override
  Future<void> load(
    Uri media, {
    String? plexToken,
    int? generation,
    bool startPaused = false,
    Duration? startPosition,
  }) => _call(
    'load generation=$generation',
    () => _player.load(
      media,
      plexToken: plexToken,
      generation: generation,
      startPaused: startPaused,
      startPosition: startPosition,
    ),
  );
  @override
  Future<void> setDisplayMatching(DisplayMatchingRequest request) => _call(
    'setDisplayMatching revision=${request.revision}',
    () => _player.setDisplayMatching(request),
  );
  @override
  Future<void> play() => _call('play', _player.play);
  @override
  Future<void> pause() => _call('pause', _player.pause);
  @override
  Future<void> seek(Duration position, {SeekMode mode = SeekMode.exact}) =>
      _call(
        'seek ${position.inSeconds}s',
        () => _player.seek(position, mode: mode),
      );
  @override
  Future<void> setVideoRect(PlayerVideoRect rect) => _call(
    'setVideoRect ${rect.left},${rect.top} ${rect.width}x${rect.height} '
    '@${rect.scale}',
    () => _player.setVideoRect(rect),
  );
  @override
  Future<void> setFullscreen(bool fullscreen) => _call(
    'setFullscreen $fullscreen',
    () => _player.setFullscreen(fullscreen),
  );
  @override
  Future<void> selectTrack(PlayerTrackType type, int? id) => _call(
    'selectTrack ${type.name}:$id',
    () => _player.selectTrack(type, id),
  );
  @override
  Future<void> setVolume(double volume) =>
      _call('setVolume $volume', () => _player.setVolume(volume));
  @override
  Future<void> stop() => _call('stop', _player.stop);
  @override
  Future<void> dispose() => _call('dispose', _player.dispose);
}

/// Drives the real player directly, the way [PlayerCoordinator] would after
/// a tune: one load per media file (each replacing the previous load), with
/// seek, volume, track selection, and fullscreen on the first, then stop.
/// The video rectangle is set explicitly because no Flutter video surface is
/// on screen before a tune.
Future<void> _exercise(HarnessLoggingPlayer player, List<Uri> media) async {
  Future<void> step(String name, Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      _log('exercise step "$name" failed');
    }
  }

  Future<void> pause(int seconds) =>
      Future<void>.delayed(Duration(seconds: seconds));

  await step('initialize', () => player.initialized);
  await pause(2);
  await step(
    'video rect',
    () => player.setVideoRect(
      const PlayerVideoRect(
        left: 40,
        top: 60,
        width: 640,
        height: 360,
        scale: 2,
      ),
    ),
  );
  for (var index = 0; index < media.length; index++) {
    _log('exercise load media $index');
    await step('load', () => player.load(media[index], generation: index + 1));
    await pause(4);
    if (index == 0) {
      await step('seek', () => player.seek(const Duration(seconds: 5)));
      await step('volume', () => player.setVolume(40));
      final audio = player.tracks
          .where((track) => track.type == PlayerTrackType.audio)
          .toList();
      await step(
        'track',
        () => audio.isEmpty
            ? player.selectTrack(PlayerTrackType.subtitle, null)
            : player.selectTrack(PlayerTrackType.audio, audio.first.id),
      );
      await step('enter fullscreen', () => player.setFullscreen(true));
      await pause(2);
      await step('exit fullscreen', () => player.setFullscreen(false));
      await step(
        'zero rect',
        () => player.setVideoRect(
          const PlayerVideoRect(left: 0, top: 0, width: 0, height: 0, scale: 2),
        ),
      );
      await pause(2);
      await step(
        'video rect',
        () => player.setVideoRect(
          const PlayerVideoRect(
            left: 0,
            top: 0,
            width: 960,
            height: 540,
            scale: 2,
          ),
        ),
      );
    }
    await pause(4);
  }
  await step('stop', player.stop);
  _log('exercise complete');
}
