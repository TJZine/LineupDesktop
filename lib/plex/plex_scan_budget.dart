import 'dart:async';

import 'plex_models.dart';

/// Finite work limits for one complete inventory attempt, including recovery.
///
/// Existing pagers allow 100,000 rows per endpoint. These aggregate ceilings
/// admit multiple such libraries with collections and playlists, while bounding
/// their combined cost. Entries conservatively count raw rows, tag memberships
/// and staged output (including reused output), rather than estimating heap
/// bytes. Compatibility fixtures include two 5,000-item libraries, five
/// overlapping collections per library, three genres per item and a 500-item
/// playlist, including the controller's staging charges (608 requests). Existing
/// sparse-page and large-collection boundary fixtures also remain supported.
/// Representative minimum-TV compatibility remains physical acceptance.
class PlexScanLimits {
  const PlexScanLimits({
    this.receivedBytes = 128 * 1024 * 1024,
    this.retainedEntries = 500000,
    this.requests = 10000,
    this.elapsed = const Duration(minutes: 10),
    this.concurrentRequests = 8,
  }) : assert(receivedBytes > 0),
       assert(retainedEntries > 0),
       assert(requests > 0),
       assert(concurrentRequests > 0);

  final int receivedBytes;
  final int retainedEntries;
  final int requests;
  final Duration elapsed;
  final int concurrentRequests;
}

class PlexScanLimitException extends PlexException {
  const PlexScanLimitException(this.limit)
    : super(
        'scan-limit-exceeded',
        'This scan exceeded its safe resource limits. Select fewer libraries and retry.',
      );

  final String limit;
}

/// Async scope keeps retries, discovery and connection probes on the same
/// budget without adding scan-only parameters to every authentication API.
/// It is never stored in inventory or shared with unrelated async operations.
class PlexScanBudget {
  PlexScanBudget(this.limits, {Future<void>? cancelled}) {
    _timer = Timer(limits.elapsed, () => _exhaust('elapsed'));
    unawaited(cancelled?.then((_) => cancel()));
  }

  static final Object _zoneKey = Object();
  static PlexScanBudget? get current =>
      Zone.current[_zoneKey] as PlexScanBudget?;

  final PlexScanLimits limits;
  final _watch = Stopwatch()..start();
  final _stopped = Completer<void>();
  final Set<Completer<void>> _waiters = {};
  late final Timer _timer;
  PlexScanLimitException? _failure;
  int _bytes = 0;
  int _entries = 0;
  int _requests = 0;
  int _active = 0;
  bool _closed = false;

  Future<void> get stopped => _stopped.future;
  Duration get remaining => limits.elapsed - _watch.elapsed;
  bool get isActive => !_closed && !_stopped.isCompleted;

  Future<T> run<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: {_zoneKey: this});

  void check() {
    if (_failure case final failure?) throw failure;
    if (_watch.elapsed >= limits.elapsed && !_closed) {
      _exhaust('elapsed');
      throw _failure!;
    }
    if (!isActive) {
      throw const PlexException('cancelled', 'Library scan cancelled.');
    }
  }

  void _exhaust(String limit) {
    if (_closed) return;
    _failure ??= PlexScanLimitException(limit);
    cancel();
  }

  void cancel() {
    if (!_stopped.isCompleted) _stopped.complete();
  }

  void receive(int count) {
    check();
    if (count > limits.receivedBytes - _bytes) {
      _exhaust('received-bytes');
      throw _failure!;
    }
    _bytes += count;
  }

  void retain(int count) {
    check();
    if (count > limits.retainedEntries - _entries) {
      _exhaust('retained-entries');
      throw _failure!;
    }
    _entries += count;
  }

  void retainMedia(Iterable<PlexMediaItem> items) {
    for (final item in items) {
      retain(1 + item.collections.length + item.genres.length);
    }
  }

  Future<void> acquireRequest() async {
    while (true) {
      check();
      if (_active < limits.concurrentRequests) {
        if (_requests >= limits.requests) {
          _exhaust('requests');
          throw _failure!;
        }
        _requests++;
        _active++;
        return;
      }
      final waiter = Completer<void>();
      _waiters.add(waiter);
      try {
        await Future.any([waiter.future, stopped]);
      } finally {
        _waiters.remove(waiter);
      }
    }
  }

  void releaseRequest() {
    _active--;
    for (final waiter in _waiters.toList()) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  void close() {
    _closed = true;
    _timer.cancel();
    cancel();
  }
}
