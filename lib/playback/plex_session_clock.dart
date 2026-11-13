import 'dart:async';

import 'native_player.dart';

enum SessionAlignmentOutcome { noneNeeded, landed, timedOut, failed, imprecise }

/// One clock per admitted session load. All results are part-relative source
/// positions. The coordinator adds the preceding parts' aggregate offset.
final class PlexSessionClock {
  PlexSessionClock({
    required this.desktop,
    required this.requested,
    required this.offset,
  });

  static const _origin = Duration(seconds: 10);
  static const _tolerance = Duration(milliseconds: 500);
  final bool desktop;
  final Duration requested;
  final Duration offset;
  final _ready = Completer<Duration?>();
  Duration? _adjustment;
  Duration? _firstAdjustment;
  Duration? _demuxerStart;
  Duration? _observedPosition;
  Duration? lead;
  SessionAlignmentOutcome? outcome;
  int? landingMs;
  Duration? landingError;
  bool loggedAlignment = false;
  bool loggedLead = false;
  bool loggedEstimate = false;

  bool get mapped => desktop ? _demuxerStart != null : _adjustment != null;
  String get basis => mapped
      ? 'mapped'
      : desktop
      ? 'estimated'
      : 'raw';

  Duration seekBase({required bool alignmentHeld}) =>
      alignmentHeld ? requested : _observedPosition ?? requested;

  Duration observe(PlayerEvent event, {required bool active}) {
    if (desktop) {
      final sample = event.telemetry.demuxerStartTime;
      if (sample != null && sample.isFinite && sample.abs() <= 1000000) {
        _demuxerStart = Duration(
          microseconds: (sample * Duration.microsecondsPerSecond).round(),
        );
        if (_canDecide(event, active)) {
          final error =
              (requested - _desktopPosition(event.position, _demuxerStart!))
                  .abs();
          _decide(
            error > _tolerance ? requested + _origin - _demuxerStart! : null,
          );
        }
      }
    } else {
      _adjustment = event.sessionAdjustment ?? _adjustment;
      _firstAdjustment ??= _adjustment;
      final first = _firstAdjustment;
      if (first != null &&
          event.sessionAdjustment != null &&
          _canDecide(event, active)) {
        final error = (event.position - first - _origin - requested).abs();
        _decide(error > _tolerance ? requested + first + _origin : null);
      }
    }

    final adjustment = _adjustment;
    final start = _demuxerStart;
    final unbounded = desktop
        ? start == null
              ? event.position + offset
              : _desktopPosition(event.position, start)
        : adjustment != null
        ? event.position - adjustment - _origin
        : event.position;
    final position = unbounded.isNegative ? Duration.zero : unbounded;
    if (active && (event.positionUpdated || _observedPosition != null)) {
      _observedPosition = position;
    }
    if (mapped && event.positionUpdated) lead ??= requested - position;
    return position;
  }

  bool _canDecide(PlayerEvent event, bool active) =>
      !_ready.isCompleted &&
      active &&
      event.positionUpdated &&
      const {
        PlayerState.playing,
        PlayerState.paused,
        PlayerState.ready,
      }.contains(event.status.state);

  static Duration _desktopPosition(Duration position, Duration start) =>
      position + start - _origin;

  void _decide(Duration? target) => _ready.complete(
    target == null
        ? null
        : Duration(milliseconds: target.isNegative ? 0 : target.inMilliseconds),
  );

  Future<void> align(NativePlayer player, Future<void> cancelled) async {
    try {
      final (current, target) = await Future.any([
        _ready.future.then((target) => (true, target)),
        cancelled.then((_) => (false, null)),
      ]).timeout(const Duration(seconds: 2));
      if (!current) return;
      if (target == null) {
        outcome = SessionAlignmentOutcome.noneNeeded;
      } else if (player is SessionAlignmentPlayer) {
        final watch = Stopwatch()..start();
        final (current, landing) = await Future.any([
          (player as SessionAlignmentPlayer)
              .alignSession(target)
              .then((landing) => (true, landing)),
          cancelled.then((_) => (false, null)),
        ]).timeout(const Duration(seconds: 5));
        if (!current) return;
        if (desktop && landing == null) {
          outcome = SessionAlignmentOutcome.failed;
          return;
        }
        landingMs = watch.elapsedMilliseconds;
        if (landing != null) {
          landingError =
              _desktopPosition(landing.position, landing.demuxerStart) -
              requested;
        }
        outcome = (landingError?.abs() ?? Duration.zero) > _tolerance
            ? SessionAlignmentOutcome.imprecise
            : SessionAlignmentOutcome.landed;
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
