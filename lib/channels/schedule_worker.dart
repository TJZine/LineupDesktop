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

sealed class _ScheduleWorkerMessage {
  const _ScheduleWorkerMessage();
}

final class _ScheduleWorkerBootstrap extends _ScheduleWorkerMessage {
  const _ScheduleWorkerBootstrap(this.output, this.media, this.playlists);

  final SendPort output;
  final List<PlexMediaItem> media;
  final List<PlexPlaylist> playlists;
}

final class _ScheduleWorkerRequest extends _ScheduleWorkerMessage {
  const _ScheduleWorkerRequest(this.id, this.channel);

  final int id;
  final Channel channel;
}

final class _ScheduleWorkerResult extends _ScheduleWorkerMessage {
  const _ScheduleWorkerResult.success(this.id, this.schedule)
    : failureReason = null,
      remoteErrorMessage = null,
      remoteErrorStack = null;

  const _ScheduleWorkerResult.failure(this.id, this.failureReason)
    : schedule = null,
      remoteErrorMessage = null,
      remoteErrorStack = null;

  const _ScheduleWorkerResult.unexpected(
    this.id,
    this.remoteErrorMessage,
    this.remoteErrorStack,
  ) : schedule = null,
      failureReason = null;

  final int id;
  final ScheduleIndex? schedule;
  final ScheduleFailureReason? failureReason;
  final String? remoteErrorMessage;
  final String? remoteErrorStack;
}

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
      port.send(_ScheduleWorkerRequest(id, channel));
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

    responses.listen((Object? message) {
      if (!identical(_responses, responses)) return;
      if (message == null) {
        fail(StateError('Schedule worker exited unexpectedly'));
        return;
      }
      if (_isVmErrorMessage(message)) {
        final error = RemoteError(
          (message as List<Object?>)[0] as String,
          message[1] as String,
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
      if (message is _ScheduleWorkerResult) {
        final completer = _pending.remove(message.id);
        if (completer == null) return;
        if (message.remoteErrorMessage != null &&
            message.remoteErrorStack != null) {
          final error = RemoteError(
            message.remoteErrorMessage!,
            message.remoteErrorStack!,
          );
          completer.completeError(error, error.stackTrace);
        } else if (message.schedule != null) {
          completer.complete(message.schedule);
        } else if (message.failureReason != null) {
          completer.completeError(
            ScheduleBuildException(message.failureReason!),
          );
        } else {
          completer.completeError(
            StateError('Schedule worker could not build the schedule'),
          );
        }
        return;
      }
      final requestId = _correlatedRequestId(message);
      if (requestId != null) {
        final completer = _pending.remove(requestId);
        if (completer == null) return;
        completer.completeError(
          const FormatException('Schedule worker sent an invalid response'),
        );
        return;
      }
      fail(const FormatException('Schedule worker sent an invalid response'));
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
  ) => Isolate.spawn<_ScheduleWorkerBootstrap>(
    _run,
    _ScheduleWorkerBootstrap(responses, media, playlists),
    onExit: responses,
    onError: responses,
    errorsAreFatal: true,
    debugName: 'Lineup schedule worker',
  );

  static void _run(_ScheduleWorkerBootstrap bootstrap) {
    final output = bootstrap.output;
    final media = bootstrap.media;
    final playlists = bootstrap.playlists;
    final requests = ReceivePort();
    output.send(requests.sendPort);
    requests.listen((message) {
      if (message is! _ScheduleWorkerRequest) return;
      try {
        output.send(
          _ScheduleWorkerResult.success(
            message.id,
            buildChannelSchedule(
              message.channel,
              resolveContent(message.channel.source, media, playlists),
            ),
          ),
        );
      } on ScheduleBuildException catch (error) {
        output.send(_ScheduleWorkerResult.failure(message.id, error.reason));
      } on FormatException {
        output.send(
          _ScheduleWorkerResult.failure(
            message.id,
            ScheduleFailureReason.unsupportedSource,
          ),
        );
      } catch (error, stackTrace) {
        output.send(
          _ScheduleWorkerResult.unexpected(
            message.id,
            error.toString(),
            stackTrace.toString(),
          ),
        );
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

bool _isVmErrorMessage(Object message) =>
    message is List &&
    message.length == 2 &&
    message[0] is String &&
    message[1] is String;

int? _correlatedRequestId(Object message) =>
    message is List && message.isNotEmpty && message[0] is int
    ? message[0] as int
    : null;
