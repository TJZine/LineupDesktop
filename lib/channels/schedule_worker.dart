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

class ScheduleWorker {
  ScheduleWorker(this.media, this.playlists);

  final List<PlexMediaItem> media;
  final List<PlexPlaylist> playlists;
  final Map<int, Completer<ScheduleIndex>> _pending = {};
  Future<SendPort>? _starting;
  Isolate? _isolate;
  ReceivePort? _responses;
  SendPort? _requests;
  int _nextRequest = 0;
  bool _disposed = false;

  Future<ScheduleIndex> build(Channel channel) async {
    if (_disposed) throw StateError('Schedule worker is disposed');
    final port = await (_starting ??= _start());
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

  Future<SendPort> _start() async {
    final ready = Completer<SendPort>();
    final responses = ReceivePort();
    _responses = responses;
    void fail(Object error, [StackTrace? stackTrace]) {
      if (!identical(_responses, responses)) return;
      if (!ready.isCompleted) ready.completeError(error, stackTrace);
      for (final completer in _pending.values) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
      _pending.clear();
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      _requests = null;
      _starting = null;
      _responses = null;
      responses.close();
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
        if (!ready.isCompleted) ready.complete(message);
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
    late final Isolate isolate;
    try {
      isolate = await Isolate.spawn(
        _run,
        [responses.sendPort, media, playlists],
        onExit: responses.sendPort,
        onError: responses.sendPort,
        errorsAreFatal: true,
        debugName: 'Lineup schedule worker',
      );
    } catch (_) {
      if (identical(_responses, responses)) {
        _responses = null;
        _isolate = null;
        _requests = null;
        _starting = null;
        responses.close();
      }
      rethrow;
    }
    if (_disposed) {
      isolate.kill(priority: Isolate.immediate);
      if (!ready.isCompleted) {
        ready.completeError(StateError('Schedule worker was disposed'));
      }
    } else if (!identical(_responses, responses)) {
      isolate.kill(priority: Isolate.immediate);
    } else {
      _isolate = isolate;
    }
    return ready.future;
  }

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
          buildSchedule(
            resolveContent(channel.source, media, playlists),
            mode: channel.playbackMode,
            seed: channel.shuffleSeed,
            blockSize: channel.blockSize ?? 3,
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
