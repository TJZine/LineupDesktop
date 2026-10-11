import 'dart:async';
import 'dart:isolate';

import '../plex/plex_models.dart';
import 'channel.dart';
import 'content_resolver.dart';
import 'scheduler.dart';

typedef ScheduleWorkerFactory = ScheduleWorker Function(
  List<PlexMediaItem> media,
  List<PlexPlaylist> playlists,
);

typedef ScheduleWorkerSpawn = Future<Isolate> Function(
  SendPort responses,
  List<PlexMediaItem> media,
  List<PlexPlaylist> playlists,
);

class ScheduleWorker {
  ScheduleWorker(this.media, this.playlists, {ScheduleWorkerSpawn? spawn})
    : _spawn = spawn ?? _spawnWorker;

  final List<PlexMediaItem> media;
  final List<PlexPlaylist> playlists;
  final ScheduleWorkerSpawn _spawn;
  final Map<int, Completer<ScheduleIndex>> _pending = {};
  Future<SendPort>? _starting;
  Completer<SendPort>? _startupReadiness;
  Isolate? _isolate;
  ReceivePort? _responses;
  SendPort? _requests;
  int _nextRequest = 0;
  bool _disposed = false;

  Future<ScheduleIndex> build(Channel channel) async {
    if (_disposed) throw StateError('Schedule worker is disposed');
    final port = await (_starting ?? _start());
    if (_disposed) throw StateError('Schedule worker is disposed');
    if (!identical(_requests, port)) {
      throw StateError('Schedule worker is unavailable');
    }
    final id = ++_nextRequest;
    final completer = Completer<ScheduleIndex>();
    _pending[id] = completer;
    try {
      port.send([id, channel]);
    } catch (_) {
      _pending.remove(id);
      rethrow;
    }
    return completer.future;
  }

  Future<SendPort> _start() {
    final ready = Completer<SendPort>();
    final responses = ReceivePort();
    _starting = ready.future;
    _startupReadiness = ready;
    _responses = responses;

    void retire() {
      if (!identical(_responses, responses)) return;
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      _requests = null;
      _starting = null;
      if (identical(_startupReadiness, ready)) {
        _startupReadiness = null;
      }
      _responses = null;
      responses.close();
    }

    void fail(Object error, [StackTrace? stackTrace]) {
      if (!identical(_responses, responses)) return;
      if (!ready.isCompleted) ready.completeError(error, stackTrace);
      for (final completer in _pending.values) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
      _pending.clear();
      retire();
    }

    responses.listen((message) {
      if (!identical(_responses, responses)) return;
      if (message == null) {
        fail(StateError('Schedule worker exited unexpectedly'));
        return;
      }
      if (message is List<Object?> && message.length == 2) {
        final error = RemoteError(
          message[0].toString(),
          message[1]?.toString() ?? '',
        );
        fail(error, error.stackTrace);
        return;
      }
      if (message is SendPort) {
        _requests = message;
        if (!ready.isCompleted) {
          ready.complete(message);
          if (identical(_startupReadiness, ready)) {
            _startupReadiness = null;
          }
        }
        return;
      }
      if (message is! List<Object?> ||
          message.length != 3 ||
          message[0] is! int) {
        fail(StateError('Schedule worker sent an invalid response'));
        return;
      }
      final values = message;
      final completer = _pending.remove(values[0] as int);
      if (completer == null) return;
      final schedule = values[1] as ScheduleIndex?;
      if (schedule == null) {
        final reason = values[2] as ScheduleFailureReason?;
        completer.completeError(
          reason == null
              ? StateError('Schedule worker could not build the schedule')
              : ScheduleBuildException(reason),
        );
      } else {
        completer.complete(schedule);
      }
    });

    Future<Isolate> spawning;
    try {
      spawning = _spawn(responses.sendPort, media, playlists);
    } catch (error, stackTrace) {
      fail(error, stackTrace);
      return ready.future;
    }

    unawaited(
      spawning.then<void>(
        (isolate) {
          if (_disposed || !identical(_responses, responses)) {
            isolate.kill(priority: Isolate.immediate);
            if (_disposed && identical(_responses, responses)) {
              fail(StateError('Schedule worker was disposed'));
            }
            return;
          }
          _isolate = isolate;
        },
        onError: (Object error, StackTrace stackTrace) {
          fail(error, stackTrace);
        },
      ),
    );
    return ready.future;
  }

  static Future<Isolate> _spawnWorker(
    SendPort responses,
    List<PlexMediaItem> media,
    List<PlexPlaylist> playlists,
  ) => Isolate.spawn(
    _run,
    [responses, media, playlists],
    onExit: responses,
    onError: responses,
    errorsAreFatal: true,
    debugName: 'Lineup schedule worker',
  );

  static void _run(List<Object?> bootstrap) {
    final output = bootstrap[0] as SendPort;
    final media = bootstrap[1] as List<PlexMediaItem>;
    final playlists = bootstrap[2] as List<PlexPlaylist>;
    final requests = ReceivePort();
    output.send(requests.sendPort);
    requests.listen((message) {
      final values = message as List<Object?>;
      final id = values[0] as int;
      final channel = values[1] as Channel;
      try {
        output.send([
          id,
          buildChannelSchedule(
            channel,
            resolveContent(channel.source, media, playlists),
          ),
          null,
        ]);
      } on ScheduleBuildException catch (error) {
        output.send([id, null, error.reason]);
      } on FormatException {
        output.send([id, null, ScheduleFailureReason.unsupportedSource]);
      } catch (_) {
        output.send([id, null, null]);
      }
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final startupReadiness = _startupReadiness;
    if (startupReadiness != null && !startupReadiness.isCompleted) {
      startupReadiness.completeError(
        StateError('Schedule worker was disposed'),
      );
    }
    _startupReadiness = null;
    _isolate?.kill(priority: Isolate.immediate);
    _responses?.close();
    _isolate = null;
    _responses = null;
    _requests = null;
    _starting = null;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Schedule worker was disposed'));
      }
    }
    _pending.clear();
  }
}
