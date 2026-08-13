import 'dart:async';
import 'dart:isolate';

import '../plex/plex_models.dart';
import 'channel.dart';
import 'content_resolver.dart';
import 'scheduler.dart';

class ScheduleWorker {
  ScheduleWorker(this.media, this.playlists);

  final List<PlexMediaItem> media;
  final List<PlexPlaylist> playlists;
  final Map<int, Completer<ScheduleIndex>> _pending = {};
  Future<SendPort>? _starting;
  Isolate? _isolate;
  ReceivePort? _responses;
  int _nextRequest = 0;
  bool _disposed = false;

  Future<ScheduleIndex> build(Channel channel) async {
    if (_disposed) throw StateError('Schedule worker is disposed');
    final port = await (_starting ??= _start());
    if (_disposed) throw StateError('Schedule worker is disposed');
    final id = ++_nextRequest;
    final completer = Completer<ScheduleIndex>();
    _pending[id] = completer;
    port.send([id, channel]);
    return completer.future;
  }

  Future<SendPort> _start() async {
    final ready = Completer<SendPort>();
    final responses = ReceivePort();
    _responses = responses;
    responses.listen((message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
        return;
      }
      final values = message as List<Object?>;
      final completer = _pending.remove(values[0] as int);
      if (completer == null) return;
      final schedule = values[1] as ScheduleIndex?;
      if (schedule == null) {
        completer.completeError(FormatException(values[2] as String));
      } else {
        completer.complete(schedule);
      }
    });
    final isolate = await Isolate.spawn(_run, [
      responses.sendPort,
      media,
      playlists,
    ], debugName: 'Lineup schedule worker');
    if (_disposed) {
      isolate.kill(priority: Isolate.immediate);
      if (!ready.isCompleted) {
        ready.completeError(StateError('Schedule worker was disposed'));
      }
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
      } catch (error) {
        output.send([id, null, error.toString()]);
      }
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _responses?.close();
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Schedule worker was disposed'));
      }
    }
    _pending.clear();
  }
}
