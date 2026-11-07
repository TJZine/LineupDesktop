import 'dart:async';

import 'native_player.dart';

enum SessionAlignmentOutcome { noneNeeded, landed, timedOut, failed }

/// One clock per admitted session load. All results are part-relative source
/// positions. The coordinator adds the preceding parts' aggregate offset.
final class PlexSessionClock {
  PlexSessionClock({
    required this.desktop,
    required this.requested,
    required this.offset,
  }) : outcome = desktop ? SessionAlignmentOutcome.noneNeeded : null;

  static const _origin = Duration(seconds: 10);
  static const _tolerance = Duration(milliseconds: 500);
  final bool desktop;
  final Duration requested;
  final Duration offset;
  final _ready = Completer<Duration?>();
  Duration? _adjustment;
  Duration? _firstAdjustment;
  Duration? _demuxerStart;
  Duration? lead;
  SessionAlignmentOutcome? outcome;
  int? landingMs;
  bool loggedAlignment = false;
  bool loggedLead = false;
  bool loggedEstimate = false;

  bool get mapped => desktop ? _demuxerStart != null : _adjustment != null;
  String get basis => mapped
      ? 'mapped'
      : desktop
      ? 'estimated'
      : 'raw';

  Duration observe(PlayerEvent event) {
    if (desktop) {
      final sample = event.telemetry.demuxerStartTime;
      if (sample != null && sample.isFinite && sample.abs() <= 1000000) {
        _demuxerStart = Duration(
          microseconds: (sample * Duration.microsecondsPerSecond).round(),
        );
      }
    } else {
      _adjustment = event.sessionAdjustment;
      _firstAdjustment ??= _adjustment;
      final first = _firstAdjustment;
      if (!_ready.isCompleted &&
          first != null &&
          _adjustment != null &&
          event.positionUpdated &&
          const {
            PlayerState.playing,
            PlayerState.paused,
            PlayerState.ready,
          }.contains(event.status.state)) {
        final error = (event.position - first - _origin - requested).abs();
        final target = requested + first + _origin;
        _ready.complete(
          error <= _tolerance
              ? null
              : Duration(
                  milliseconds: target.isNegative ? 0 : target.inMilliseconds,
                ),
        );
      }
    }

    final adjustment = _adjustment;
    final unbounded = desktop
        ? event.position +
              (_demuxerStart ?? offset) -
              (_demuxerStart == null ? Duration.zero : _origin)
        : adjustment != null
        ? event.position - adjustment - _origin
        : event.position;
    final position = unbounded.isNegative ? Duration.zero : unbounded;
    if (mapped && event.positionUpdated) lead ??= requested - position;
    return position;
  }

  Future<void> align(NativePlayer player, Future<void> cancelled) async {
    if (desktop) return;
    try {
      final target = await Future.any([
        _ready.future.timeout(const Duration(seconds: 2)),
        cancelled.then<Duration?>((_) => null),
      ]);
      if (target == null) {
        outcome = SessionAlignmentOutcome.noneNeeded;
      } else if (player is SessionAlignmentPlayer) {
        final watch = Stopwatch()..start();
        await Future.any([
          (player as SessionAlignmentPlayer)
              .alignSession(target)
              .timeout(const Duration(seconds: 5)),
          cancelled,
        ]);
        landingMs = watch.elapsedMilliseconds;
        outcome = SessionAlignmentOutcome.landed;
      } else {
        outcome = SessionAlignmentOutcome.failed;
      }
    } on TimeoutException {
      outcome = SessionAlignmentOutcome.timedOut;
    } catch (_) {
      outcome = SessionAlignmentOutcome.failed;
    }
  }
}
