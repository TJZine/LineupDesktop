// Debug-only E6 measurement support. Capability URLs stay in memory.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:lineup_desktop/playback/native_player.dart';

const sessionProbePort = 18445;
const sessionProbeMaxBytes = 32768;

class SessionProbeFailure implements Exception {
  const SessionProbeFailure(this.code);
  final String code;
  @override
  String toString() => 'SessionProbeFailure($code)';
}

class SessionProbeRequest {
  const SessionProbeRequest(
    this.variant,
    this.offsetSeconds,
    this.observeSeconds,
  );
  final Uri variant;
  // Evidence label only; never passed as a player start position.
  final int offsetSeconds;
  final int observeSeconds;
  @override
  String toString() => 'SessionProbeRequest';
}

Future<SessionProbeRequest> decodeSessionProbe(Stream<List<int>> input) async {
  final bytes = <int>[];
  await for (final chunk in input) {
    if (bytes.length + chunk.length > sessionProbeMaxBytes) {
      throw const SessionProbeFailure('invalid_input');
    }
    bytes.addAll(chunk);
  }
  try {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic> ||
        value.keys.any(
          (key) =>
              !{'variant', 'offsetSeconds', 'observeSeconds'}.contains(key),
        )) {
      throw const SessionProbeFailure('invalid_input');
    }
    final text = value['variant'];
    final offset = value['offsetSeconds'];
    final seconds = value['observeSeconds'] ?? 8;
    if (text is! String ||
        offset is! int ||
        offset < 0 ||
        offset > 86400 ||
        seconds is! int ||
        seconds < 1 ||
        seconds > 30) {
      throw const SessionProbeFailure('invalid_input');
    }
    final uri = Uri.tryParse(text);
    if (uri == null ||
        uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.queryParameters.keys.any(
          (key) => key.toLowerCase() == 'x-plex-token',
        )) {
      throw const SessionProbeFailure('invalid_input');
    }
    return SessionProbeRequest(uri, offset, seconds);
  } on SessionProbeFailure {
    rethrow;
  } catch (_) {
    throw const SessionProbeFailure('invalid_input');
  }
}

Future<SessionProbeRequest> receiveSessionProbe({
  required Future<void> cancelled,
  Duration timeout = const Duration(seconds: 60),
  Future<ServerSocket> Function()? bind,
}) async {
  if (!kDebugMode) throw const SessionProbeFailure('debug_required');
  final server =
      await (bind?.call() ??
          ServerSocket.bind(InternetAddress.loopbackIPv4, sessionProbePort));
  Socket? peer;
  final accepted = Completer<Socket>();
  final subscription = server.listen(
    (socket) {
      if (accepted.isCompleted) {
        socket.destroy();
      } else {
        peer = socket;
        accepted.complete(socket);
      }
    },
    onError: (Object _) {
      if (!accepted.isCompleted) {
        accepted.completeError(const SessionProbeFailure('input_failed'));
      }
    },
  );
  Future<SessionProbeRequest> receive() async {
    final socket = await accepted.future;
    final request = await decodeSessionProbe(socket);
    socket.write('accepted\n');
    await socket.flush();
    return request;
  }

  try {
    return await Future.any([
      receive(),
      cancelled.then<SessionProbeRequest>(
        (_) => throw const SessionProbeFailure('cancelled'),
      ),
    ]).timeout(
      timeout,
      onTimeout: () => throw const SessionProbeFailure('input_timeout'),
    );
  } on SessionProbeFailure {
    rethrow;
  } catch (_) {
    throw const SessionProbeFailure('input_failed');
  } finally {
    peer?.destroy();
    await subscription.cancel();
    await server.close();
  }
}

Future<void> measureSessionProbe(
  NativePlayer player,
  SessionProbeRequest request, {
  required void Function(String phase, Map<String, Object?> facts) record,
  Future<void> Function(Duration) wait = Future<void>.delayed,
  Future<void>? cancelled,
  bool Function()? active,
}) async {
  if (!kDebugMode) throw const SessionProbeFailure('debug_required');
  void guard() {
    if (active?.call() == false) throw const SessionProbeFailure('cancelled');
  }

  Future<void> untilCancelled(Future<void> operation) => cancelled == null
      ? operation
      : Future.any([
          operation,
          cancelled.then<void>(
            (_) => throw const SessionProbeFailure('cancelled'),
          ),
        ]);
  guard();
  final clock = Stopwatch()..start();
  await untilCancelled(
    player.load(request.variant, kind: LoadKind.plexSession),
  );
  guard();
  void sample(String phase) => record(phase, {
    'offsetSeconds': request.offsetSeconds,
    'elapsedMs': clock.elapsedMilliseconds,
    'positionMs': player.position.inMilliseconds,
    'durationMs': player.duration.inMilliseconds,
    'state': player.status.state.name,
  });
  sample('session-ready');
  final initial = player.position;
  for (var i = 0; i < request.observeSeconds * 4; i++) {
    await untilCancelled(wait(const Duration(milliseconds: 250)));
    guard();
    if (player.status.state != PlayerState.playing) {
      throw const SessionProbeFailure('playback_failed');
    }
    sample('session-sample');
  }
  if (player.position < initial + const Duration(milliseconds: 400)) {
    throw const SessionProbeFailure('no_progress');
  }
}
