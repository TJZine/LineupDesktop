import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../channels/channel.dart';
import 'lineup_controller.dart';

typedef _ChannelHealthSignature = ({
  int contentGeneration,
  int channelRevision,
});

class _ChannelHealthEntry {
  const _ChannelHealthEntry(this.signature, this.issue);

  final _ChannelHealthSignature signature;
  final bool issue;
}

class _PendingChannelHealth {
  const _PendingChannelHealth(this.channel, this.signature);

  final Channel channel;
  final _ChannelHealthSignature signature;
}

/// Loads and caches the schedule-health result for visible channels.
///
/// The monitor owns health request currentness, bounded scheduling, and cache
/// invalidation. A successful result is cached just like a failed result;
/// [issueFor] therefore returns `false` for a known healthy channel and `null`
/// only when that channel has no current result.
class ChannelHealthMonitor extends ChangeNotifier {
  ChannelHealthMonitor({required LineupController controller})
    : _controller = controller,
      _contentGeneration = controller.contentGeneration {
    controller.addListener(_controllerChanged);
  }

  static const maximumActiveLoads = 2;
  static const maximumPendingRequests = 12;
  static const maximumCachedEntries = 1000;

  final LineupController _controller;
  final LinkedHashMap<String, _ChannelHealthEntry> _cache = LinkedHashMap();
  final Queue<_PendingChannelHealth> _pending = Queue();
  final Map<String, _ChannelHealthSignature> _active = {};
  int _activeLoads = 0;
  int _epoch = 0;
  int _contentGeneration;
  bool _disposed = false;

  /// Returns `true` for a current schedule issue, `false` for a current
  /// healthy result, or `null` when the channel has not completed a load.
  bool? issueFor(String id) {
    if (_disposed) return null;
    final entry = _cache[id];
    if (entry == null) return null;
    final channel = _channelFor(id);
    if (channel == null || entry.signature != _signatureFor(channel)) {
      return null;
    }
    return entry.issue;
  }

  /// Requests a current health result for [channel].
  ///
  /// Callers that discover a channel while building UI must defer this call
  /// until after the frame. The monitor itself may start the request
  /// immediately once that transition is reached.
  void request(Channel channel) {
    if (_disposed) return;
    _synchronizeControllerState();
    if (_enqueue(channel)) _pump();
  }

  @visibleForTesting
  int get activeLoadCount => _activeLoads;

  @visibleForTesting
  int get pendingRequestCount => _pending.length;

  @visibleForTesting
  int get cachedEntryCount => _cache.length;

  void _controllerChanged() {
    if (_disposed) return;
    final changed = _synchronizeControllerState();
    if (changed) notifyListeners();
  }

  bool _synchronizeControllerState() {
    var changed = false;
    final contentGeneration = _controller.contentGeneration;
    if (contentGeneration != _contentGeneration) {
      _contentGeneration = contentGeneration;
      _epoch++;
      changed = _cache.isNotEmpty || _pending.isNotEmpty || changed;
      _cache.clear();
      _pending.clear();
    }

    final liveIds = _controller.channels.map((channel) => channel.id).toSet();
    final cachedIds = _cache.keys.toList(growable: false);
    for (final id in cachedIds) {
      final channel = _channelFor(id);
      if (!liveIds.contains(id) ||
          channel == null ||
          _cache[id]!.signature != _signatureFor(channel)) {
        _cache.remove(id);
        changed = true;
      }
    }
    _pending.removeWhere((pending) {
      final channel = _channelFor(pending.channel.id);
      final stale =
          channel == null || pending.signature != _signatureFor(channel);
      changed |= stale;
      return stale;
    });
    return changed;
  }

  bool _enqueue(Channel channel) {
    final current = _channelFor(channel.id);
    if (current == null) return false;
    final signature = _signatureFor(current);
    final cached = _cache[channel.id];
    if (cached?.signature == signature) {
      _cache.remove(channel.id);
      _cache[channel.id] = cached!;
      return false;
    }
    if (_active[channel.id] == signature) {
      return false;
    }
    if (_pending.any(
      (pending) =>
          pending.channel.id == channel.id && pending.signature == signature,
    )) {
      return false;
    }
    _pending.removeWhere((pending) => pending.channel.id == channel.id);
    if (_pending.length >= maximumPendingRequests) _pending.removeFirst();
    _pending.add(_PendingChannelHealth(current, signature));
    return true;
  }

  void _pump() {
    if (_disposed) return;
    var blocked = 0;
    while (_activeLoads < maximumActiveLoads && _pending.isNotEmpty) {
      final pending = _pending.removeFirst();
      final channel = pending.channel;
      if (_active.containsKey(channel.id)) {
        _pending.add(pending);
        blocked++;
        if (blocked >= _pending.length) break;
        continue;
      }
      blocked = 0;
      final current = _channelFor(channel.id);
      if (current == null || _signatureFor(current) != pending.signature) {
        if (current != null) _enqueue(current);
        continue;
      }
      _activeLoads++;
      _active[channel.id] = pending.signature;
      unawaited(_load(channel, pending.signature, _epoch));
    }
  }

  Future<void> _load(
    Channel channel,
    _ChannelHealthSignature signature,
    int epoch,
  ) async {
    var issue = false;
    try {
      await _controller.loadScheduleFor(channel);
    } catch (_) {
      issue = true;
    } finally {
      _finish(channel.id, signature, issue, epoch);
    }
  }

  void _finish(
    String id,
    _ChannelHealthSignature signature,
    bool issue,
    int epoch,
  ) {
    _activeLoads--;
    if (_active[id] == signature) _active.remove(id);
    if (_disposed) return;

    final current = _channelFor(id);
    if (epoch == _epoch &&
        current != null &&
        _signatureFor(current) == signature) {
      _cache.remove(id);
      _cache[id] = _ChannelHealthEntry(signature, issue);
      while (_cache.length > maximumCachedEntries) {
        _cache.remove(_cache.keys.first);
      }
      notifyListeners();
    } else if (current != null) {
      _enqueue(current);
    }
    _pump();
  }

  Channel? _channelFor(String id) =>
      _controller.channels.where((channel) => channel.id == id).firstOrNull;

  _ChannelHealthSignature _signatureFor(Channel channel) => (
    contentGeneration: _contentGeneration,
    channelRevision: _controller.channelRevision(channel.id),
  );

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    _pending.clear();
    _cache.clear();
    _controller.removeListener(_controllerChanged);
    super.dispose();
  }
}
