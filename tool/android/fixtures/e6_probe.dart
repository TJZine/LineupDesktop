// Debug-only E6 observation. Capability input is retained only in memory.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lineup_desktop/playback/native_player.dart';

import 'e6_schema.dart';

const e6InputLimit = 32768;
const e6OutputLimit = 1024 * 1024;
const e6FactLimit = 300;

class E6Failure implements Exception {
  const E6Failure(this.code);
  final String code;
  @override
  String toString() => 'E6Failure($code)';
}

class E6Request {
  E6Request._(this.fields, this.variant);
  final Map<String, Object?> fields;
  final Uri variant;
  bool get seek => fields['mode'] == 'seek_after_ready';
  int get offsetSeconds => fields['offsetSeconds'] as int;
  bool get public => variant.host == 'localhost' && variant.port == 21443;
  @override
  String toString() => 'E6Request';
}

E6Request parseE6Request(Object? raw, {required bool baseline}) {
  const keys = {
    'variant',
    'offsetSeconds',
    'observeSeconds',
    'mode',
    'sourceDurationMs',
    'expectedVideoCodec',
    'expectedAudioCodec',
    'expectedTargetDurationSeconds',
    'expectedMediaSequence',
    'expectedDurationsSeconds',
  };
  Never invalid([String code = 'invalid_input']) => throw E6Failure(code);
  if (raw is! Map<String, dynamic> ||
      raw.length != keys.length ||
      !raw.keys.every(keys.contains) ||
      utf8.encode(jsonEncode(raw)).length > e6InputLimit) {
    invalid();
  }
  final text = raw['variant'];
  if (text is! String ||
      text.length > 4096 ||
      text.codeUnits.any((c) => c <= 32) ||
      text.contains(RegExp(r'[\\%?#]')) ||
      text.split('/').any((v) => v == '.' || v == '..')) {
    invalid();
  }
  final uri = Uri.tryParse(text);
  if (uri == null ||
      uri.scheme != 'https' ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    invalid();
  }
  final local =
      uri.host == 'localhost' &&
      uri.port == 21443 &&
      {'/e6-clock/index.m3u8', '/e6-hevc/index.m3u8'}.contains(uri.path);
  final privatePath = RegExp(
    r'^/video/:/transcode/universal/session/[A-Za-z0-9_-]{1,256}/base/index\.m3u8$',
  ).hasMatch(uri.path);
  if (!local && !privatePath) {
    invalid();
  }
  if (!{'default', 'seek_after_ready'}.contains(raw['mode'])) {
    invalid();
  }
  if (baseline &&
      (text != 'https://localhost:21443/e6-clock/index.m3u8' ||
          raw['mode'] != 'default')) {
    invalid('baseline_private_refused');
  }
  final offset = raw['offsetSeconds'];
  final duration = raw['sourceDurationMs'];
  final target = raw['expectedTargetDurationSeconds'];
  if (offset is! int ||
      !{0, 9, 10, 19, 21, 605}.contains(offset) ||
      raw['observeSeconds'] != 10 ||
      raw['observeSeconds'] is! int ||
      raw['expectedMediaSequence'] != 0 ||
      raw['expectedMediaSequence'] is! int ||
      duration is! int ||
      duration < 1 ||
      duration > 43200000 ||
      target is! int ||
      target < 1 ||
      target > 120 ||
      !{'h264', 'hevc'}.contains(raw['expectedVideoCodec']) ||
      raw['expectedAudioCodec'] != 'aac') {
    invalid();
  }
  final durations = raw['expectedDurationsSeconds'];
  if (durations is! List || durations.isEmpty || durations.length > 10000) {
    invalid();
  }
  var sum = 0;
  for (final value in durations) {
    if (value is! num || !value.isFinite || value <= 0 || value > 120) {
      invalid();
    }
    // Numeric JSON values are accepted only when exactly representable in microseconds.
    final match = RegExp(r'^(\d+)(?:\.(\d{1,6}))?$')
        .firstMatch(value.toString());
    if (match == null) {
      invalid();
    }
    sum +=
        int.parse(match[1]!) * 1000000 +
        int.parse((match[2] ?? '').padRight(6, '0'));
  }
  if ((sum - duration * 1000).abs() > 1000000) {
    invalid();
  }
  return E6Request._(Map<String, Object?>.unmodifiable(raw), uri);
}

void _validateFields(
  Map<String, dynamic> value,
  Map<String, dynamic> fields,
  Iterable<dynamic> required,
) {
  if (!required.every(value.containsKey)) {
    throw const E6Failure('fact_schema');
  }
  for (final entry in value.entries) {
    final spec = fields[entry.key];
    final item = entry.value;
    if (spec is! Map) {
      throw const E6Failure('fact_schema');
    }
    if (item == null) {
      if (spec['nullable'] != true) {
        throw const E6Failure('fact_schema');
      }
      continue;
    }
    final valid = switch (spec['type']) {
      'boolean' => item is bool,
      'number' => item is num && item.isFinite,
      'integer' => item is int,
      'string' => item is String && (spec['enum'] as List).contains(item),
      _ => false,
    };
    if (!valid ||
        (spec['min'] is num && (item as num) < (spec['min'] as num)) ||
        (spec['max'] is num && (item as num) > (spec['max'] as num))) {
      throw const E6Failure('fact_schema');
    }
  }
}

Map<String, dynamic> validateE6Fact(Object? raw) {
  if (raw is! Map || raw.keys.any((k) => k is! String)) {
    throw const E6Failure('fact_schema');
  }
  final value = Map<String, dynamic>.from(raw);
  final event = (e6Schema['events'] as Map)[value['event']];
  if (event is! Map) {
    throw const E6Failure('fact_schema');
  }
  _validateFields(
    value,
    e6Schema['fields'] as Map<String, dynamic>,
    event['required'] as List,
  );
  if (value['sourceOriginProven'] == true ||
      (value['sampleIndex'] != null &&
          (value['sampleIndex'] is! int ||
              (value['sampleIndex'] as int) < 0 ||
              (value['sampleIndex'] as int) > 40))) {
    throw const E6Failure('fact_schema');
  }
  return value;
}

abstract interface class E6Bridge {
  Future<Object?> call(String method, [Map<String, Object?>? arguments]);
}

class MethodChannelE6Bridge implements E6Bridge {
  const MethodChannelE6Bridge();
  static const _channel = MethodChannel('lineup/e6');
  @override
  Future<Object?> call(String method, [Map<String, Object?>? arguments]) =>
      _channel.invokeMethod<Object?>(method, arguments);
}

class _Drain {
  _Drain(Object? raw) {
    if (raw is! Map ||
        raw.length != 5 ||
        !raw.keys.toSet().containsAll({
          'events',
          'hasReady',
          'terminal',
          'result',
          'failureCode',
        }) ||
        raw['events'] is! List ||
        raw['hasReady'] is! bool ||
        raw['terminal'] is! bool ||
        !{
          'running',
          'complete',
          'failed',
          'unsupported',
        }.contains(raw['result'])) {
      throw const E6Failure('fact_schema');
    }
    final code = raw['failureCode'];
    final fields = e6Schema['fields'] as Map;
    final failureSpec = fields['failureCode'] as Map;
    if (code != null && !(failureSpec['enum'] as List).contains(code)) {
      throw const E6Failure('fact_schema');
    }
    events = List<Object?>.from(raw['events'] as List);
    ready = raw['hasReady'] as bool;
    terminal = raw['terminal'] as bool;
    result = raw['result'] as String;
    failure = code as String?;
  }
  late final List<Object?> events;
  late final bool ready, terminal;
  late final String result;
  late final String? failure;
}

/// Runs one already-decoded load. Every operation is awaited or has an error handler.
/// Native owns the frame clock; Dart owns the one explicitly planned seek.
Future<Map<String, Object?>> observeE6(
  NativePlayer player,
  E6Bridge bridge,
  E6Request request, {
  required Future<void> cancelled,
  required bool Function() active,
  required Future<void> Function(Map<String, dynamic>) record,
  Duration pollInterval = const Duration(milliseconds: 20),
  Duration activeTimeout = const Duration(seconds: 90),
  Duration teardownTimeout = const Duration(seconds: 15),
  Future<void> Function(Duration) wait = Future<void>.delayed,
  String? initialFailure,
}) async {
  String? failure;
  var result = 'failed';
  var gate = false, stopped = false, disposed = false, released = false;
  var count = 0;
  final counters = <String, Object?>{
    'variantAttempts': null,
    'initAttempts': null,
    'mediaAttempts': null,
    'totalBytes': null,
    'activeCalls': null,
  };
  final expired = Completer<void>();
  final timer = Timer(activeTimeout, expired.complete);
  void guard() {
    if (!active()) {
      throw const E6Failure('cancelled');
    }
  }

  Future<T> during<T>(Future<T> operation) => Future.any<T>([
    operation,
    cancelled.then<T>((_) => throw const E6Failure('cancelled')),
    expired.future.then<T>((_) => throw const E6Failure('observation_timeout')),
  ]);
  Future<Object?> call(String name, [Map<String, Object?>? args]) async {
    try {
      return await bridge.call(name, args).timeout(const Duration(seconds: 10));
    } on E6Failure {
      rethrow;
    } catch (_) {
      throw const E6Failure('channel_failed');
    }
  }

  Future<void> emit(Map<String, dynamic> event, {bool teardown = false}) async {
    validateE6Fact(event);
    if (count >= e6FactLimit) {
      throw const E6Failure('event_overflow');
    }
    count++;
    await (teardown ? record(event) : during(record(event)));
    if (event['event'] == 'release') {
      for (final key in counters.keys) {
        counters[key] = event[key];
      }
      released =
          event['released'] == true &&
          event['playbackThreadAlive'] == false &&
          event['activeCalls'] == 0 &&
          event['networkDrained'] == true;
    }
  }

  Future<_Drain> drain({bool teardown = false}) async {
    final value = _Drain(
      await (teardown ? call('drain') : during(call('drain'))),
    );
    for (final event in value.events) {
      await emit(validateE6Fact(event), teardown: teardown);
    }
    return value;
  }

  Future<void>? load;
  String? loadFailure;
  try {
    if (!kDebugMode) {
      throw const E6Failure('debug_required');
    }
    if (initialFailure != null) {
      throw E6Failure(initialFailure);
    }
    guard();
    final caps = await during(call('capabilities'));
    const capKeys = {
      'debugEnabled',
      'apiLevel',
      'arm64',
      'h2641080',
      'aac',
      'hevcMain10',
      'hevc3840x1600',
    };
    if (caps is! Map ||
        caps.length != capKeys.length ||
        !caps.keys.every(capKeys.contains)) {
      throw const E6Failure('fact_schema');
    }
    await emit({'event': 'capabilities', ...Map<String, dynamic>.from(caps)});
    final configured = await during(call('configure', request.fields));
    if (configured is! Map ||
        configured.length != 1 ||
        configured['configured'] != true) {
      throw const E6Failure('fact_schema');
    }
    guard();
    await during(player.initialize().timeout(const Duration(seconds: 10)));
    await during(
      player
          .setVideoRect(
            const PlayerVideoRect(
              left: 0,
              top: 0,
              width: 960,
              height: 540,
              scale: 2,
            ),
          )
          .timeout(const Duration(seconds: 10)),
    );
    guard();
    // Attach error handling immediately: the load acknowledgment can require first frame.
    load = player
        .load(request.variant, kind: LoadKind.plexSession)
        .then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {
            loadFailure = 'load_failed';
          },
        );
    var sought = false;
    while (true) {
      guard();
      final value = await drain();
      if (!value.terminal && loadFailure != null) {
        throw E6Failure(loadFailure!);
      }
      if (value.ready && request.seek && !sought && !value.terminal) {
        sought = true;
        try {
          await during(
            player
                .seek(
                  Duration(seconds: request.offsetSeconds),
                  mode: SeekMode.exact,
                )
                .timeout(const Duration(seconds: 10)),
          );
        } on E6Failure {
          rethrow;
        } catch (_) {
          throw const E6Failure('seek_failed');
        }
      }
      if (value.terminal) {
        result = value.result == 'running' ? 'failed' : value.result;
        failure = value.failure;
        if (result == 'complete') {
          if (!value.ready) throw const E6Failure('fact_schema');
          if (request.seek && !sought) throw const E6Failure('seek_contract');
          await during(load);
          if (loadFailure != null) throw E6Failure(loadFailure!);
        }
        break;
      }
      await during(wait(pollInterval));
    }
  } on E6Failure catch (e) {
    failure = e.code;
  } catch (_) {
    failure = 'load_failed';
  } finally {
    timer.cancel();
    // A single deadline bounds all cleanup; each step still runs after a prior failure.
    final cleanupClock = Stopwatch()..start();
    Future<T> cleanup<T>(Future<T> Function() operation) {
      final remaining = teardownTimeout - cleanupClock.elapsed;
      if (remaining <= Duration.zero) {
        throw const E6Failure('release_failed');
      }
      return operation().timeout(remaining);
    }

    try {
      final value = await cleanup(() => call('cancel'));
      gate = value is Map && value.length == 1 && value['cancelled'] == true;
    } catch (_) {
      failure ??= 'release_failed';
    }
    try {
      await cleanup(player.stop);
      stopped = true;
    } catch (_) {
      failure ??= 'release_failed';
    }
    try {
      await cleanup(player.dispose);
      disposed = true;
    } catch (_) {
      failure ??= 'release_failed';
    }
    try {
      await cleanup(() => drain(teardown: true));
    } catch (_) {
      failure ??= 'release_failed';
    }
    if (!gate ||
        !stopped ||
        !disposed ||
        !released ||
        counters.values.any((value) => value == null)) {
      failure ??= 'release_failed';
      result = 'failed';
    }
  }
  if (failure != null && result != 'unsupported') {
    result = 'failed';
  }
  final terminal = <String, Object?>{
    'type': 'terminal',
    'result': result,
    'failureCode': failure,
    'nativeReleased': released,
    'stopCompleted': stopped,
    'disposeCompleted': disposed,
    'nativeGateClosed': gate,
    'factCount': count,
    ...counters,
  };
  final spec = e6Schema['terminal'] as Map;
  _validateFields(
    terminal,
    Map<String, dynamic>.from(spec['fields'] as Map),
    spec['required'] as List,
  );
  return terminal;
}

/// Prebinding before Flutter's first frame gives the host a causal one-connect gate.
Future<ServerSocket> bindE6Input({
  Future<void>? cancelled,
  Future<ServerSocket> Function()? bind,
  Duration timeout = const Duration(seconds: 10),
}) async {
  if (!kDebugMode) throw const E6Failure('debug_required');
  var abandoned = false;
  final binding =
      bind?.call() ?? ServerSocket.bind(InternetAddress.loopbackIPv4, 18445);
  unawaited(
    binding.then((socket) async {
      if (abandoned) await socket.close();
    }, onError: (Object _) {}),
  );
  try {
    return await Future.any<ServerSocket>([
      binding,
      if (cancelled != null)
        cancelled.then<ServerSocket>((_) => throw const E6Failure('cancelled')),
    ]).timeout(
      timeout,
      onTimeout: () => throw const E6Failure('input_timeout'),
    );
  } catch (_) {
    abandoned = true;
    rethrow;
  }
}

/// One LF frame, with a persistent completed state to reject any later bytes.
class E6LineInput {
  final _bytes = <int>[];
  int receivedBytes = 0;
  bool complete = false;
  bool add(List<int> chunk) {
    if (receivedBytes + chunk.length > e6InputLimit) {
      receivedBytes = e6InputLimit;
      throw const E6Failure('input_cap');
    }
    receivedBytes += chunk.length;
    for (final byte in chunk) {
      if (complete) throw const E6Failure('extra_input');
      if (byte == 10) {
        complete = true;
      } else {
        _bytes.add(byte);
      }
    }
    return complete;
  }

  List<int> takeFrame() {
    if (!complete) throw const E6Failure('invalid_input');
    final frame = List<int>.of(_bytes);
    _bytes.clear();
    return frame;
  }

  void discard() => _bytes.clear();
}

class E6PlaybackStatus {
  E6PlaybackStatus(this.bridge);
  final E6Bridge bridge;
  var phase = 'starting';
  var receivedBytes = 0, flushedBytes = 0;
  var responseAttempted = false, started = false;
  bool _sealed = false;
  String? failureCode;
  void fail(String code) {
    failureCode ??= code;
  }

  Future<void> publish(String next, {bool finalStatus = false}) async {
    if (_sealed) {
      throw const E6Failure('channel_failed');
    }
    if (finalStatus) {
      _sealed = true;
    }
    phase = next;
    started = true;
    try {
      final reply = await bridge
          .call('transportStatus', {
            'mode': 'playback',
            'phase': phase,
            'receivedBytes': receivedBytes,
            'responseAttempted': responseAttempted,
            'flushedBytes': flushedBytes,
            'failureCode': failureCode,
          })
          .timeout(const Duration(seconds: 10));
      if (reply is! Map || reply.length != 1 || reply['stored'] != true) {
        throw const E6Failure('channel_failed');
      }
    } catch (_) {
      throw const E6Failure('channel_failed');
    }
  }
}

/// Owns lifecycle before binding, then advertises only a resumed, listening receiver.
/// [show] installs the fixture and invokes its callback after the first Flutter frame.
Future<void> startE6Fixture(
  NativePlayer player,
  E6Bridge bridge, {
  required bool baseline,
  required void Function(VoidCallback firstFrame) show,
  Future<ServerSocket> Function()? bind,
  Duration startupTimeout = const Duration(seconds: 30),
  Duration teardownTimeout = const Duration(seconds: 15),
}) async {
  if (!kDebugMode) {
    throw const E6Failure('debug_required');
  }
  final cancelled = Completer<void>();
  final resumed = Completer<void>();
  final firstFrame = Completer<void>();
  final expired = Completer<void>();
  void cancel() {
    if (!cancelled.isCompleted) {
      cancelled.complete();
    }
  }

  void lifecycleChanged(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      cancel();
    }
    if (state == AppLifecycleState.resumed && !resumed.isCompleted) {
      resumed.complete();
    }
  }

  final binding = WidgetsBinding.instance;
  // Register before any await: startup can receive pause/detach while binding.
  final lifecycle = AppLifecycleListener(onStateChange: lifecycleChanged);
  if (binding.lifecycleState == AppLifecycleState.resumed) {
    resumed.complete();
  }
  final timer = Timer(startupTimeout, expired.complete);
  bool active() =>
      !cancelled.isCompleted &&
      binding.lifecycleState == AppLifecycleState.resumed;
  Future<T> startup<T>(Future<T> operation) => Future.any<T>([
    operation,
    cancelled.future.then<T>((_) => throw const E6Failure('cancelled')),
    expired.future.then<T>((_) => throw const E6Failure('input_timeout')),
  ]);
  void guard() {
    if (expired.isCompleted) {
      throw const E6Failure('input_timeout');
    }
    if (!active()) {
      throw const E6Failure('cancelled');
    }
  }

  final transport = E6PlaybackStatus(bridge);
  ServerSocket? server;
  var delegated = false;
  try {
    await startup(transport.publish('starting'));
    server = await startup(
      bindE6Input(cancelled: cancelled.future, bind: bind),
    );
    if (cancelled.isCompleted) {
      throw const E6Failure('cancelled');
    }
    show(() {
      if (!firstFrame.isCompleted) {
        firstFrame.complete();
      }
    });
    await startup(transport.publish('waiting_resumed'));
    await startup(Future.wait([firstFrame.future, resumed.future]));
    guard();
    delegated = true;
    await receiveAndObserveE6(
      player,
      bridge,
      baseline: baseline,
      transportStatus: transport,
      prebound: server,
      cancelled: cancelled.future,
      active: active,
      teardownTimeout: teardownTimeout,
      onListening: () async {
        guard();
        final ready = await startup(
          bridge.call('markInputReady').timeout(const Duration(seconds: 10)),
        );
        if (ready is! Map || ready.length != 1 || ready['ready'] != true) {
          throw const E6Failure('channel_failed');
        }
        guard();
        timer.cancel();
      },
    );
  } catch (error) {
    transport.fail(
      error is E6Failure && error.code == 'input_timeout'
          ? 'startup_deadline'
          : error is E6Failure && error.code == 'cancelled'
          ? 'cancelled'
          : 'io_failure',
    );
    // No capability is read before receiver ownership; never report raw startup errors.
    cancel();
  } finally {
    timer.cancel();
    if (!delegated) {
      cancel();
      await receiveAndObserveE6(
        player,
        bridge,
        baseline: baseline,
        transportStatus: transport,
        prebound: server,
        cancelled: cancelled.future,
        active: () => false,
        teardownTimeout: teardownTimeout,
      );
    }
    cancel();
    lifecycle.dispose();
  }
}

/// Keeps the peer's input subscribed through observation: LF ends the sole frame,
/// not the receive side. EOF/extra input before output completion cancels the load.
Future<void> receiveAndObserveE6(
  NativePlayer player,
  E6Bridge bridge, {
  required bool baseline,
  required Future<void> cancelled,
  required bool Function() active,
  Future<ServerSocket> Function()? bind,
  ServerSocket? prebound,
  Future<void> Function()? onListening,
  Duration inputTimeout = const Duration(seconds: 60),
  Duration activeTimeout = const Duration(seconds: 90),
  Duration teardownTimeout = const Duration(seconds: 15),
  E6PlaybackStatus? transportStatus,
}) async {
  if (!kDebugMode) {
    throw const E6Failure('debug_required');
  }
  final transport = transportStatus ?? E6PlaybackStatus(bridge);
  final input = E6LineInput();
  ServerSocket? server = prebound;
  Socket? peer;
  StreamSubscription<Socket>? incoming;
  StreamSubscription<Uint8List>? reader;
  final chosen = Completer<Socket>(), framed = Completer<List<int>>();
  var closed = false, closing = false, observed = false;
  var outputBytes = 0;
  final localCancel = Completer<void>();
  void cancel([String code = 'cancelled']) {
    transport.fail(code);
    if (!localCancel.isCompleted) {
      localCancel.complete();
    }
  }

  unawaited(cancelled.then((_) => cancel()));
  Future<T> receiving<T>(Future<T> work) => Future.any<T>([
    work,
    localCancel.future.then<T>((_) => throw const E6Failure('cancelled')),
  ]);
  Future<void> send(String text, {bool announce = false}) async {
    final size = utf8.encode(text).length;
    if (size > 16384 || outputBytes + size > e6OutputLimit) {
      transport.fail('output_cap');
      throw const E6Failure('event_overflow');
    }
    outputBytes += size;
    transport.responseAttempted = true;
    try {
      peer!.write(text);
    } catch (_) {
      cancel('peer_closed');
      throw const E6Failure('peer_lost');
    }
    if (announce) {
      await transport.publish('reply_attempt');
    }
    try {
      await peer!.flush().timeout(const Duration(seconds: 5));
    } on TimeoutException {
      cancel('exchange_deadline');
      throw const E6Failure('peer_lost');
    } catch (_) {
      cancel('peer_closed');
      throw const E6Failure('peer_lost');
    }
    transport.flushedBytes += size;
    if (announce) {
      await transport.publish('reply_flushed');
    }
  }

  Future<void> write(Object value) => send('${jsonEncode(value)}\n');
  try {
    if (!transport.started) {
      await transport.publish('starting');
    }
    if (!active()) {
      throw const E6Failure('cancelled');
    }
    final binding = prebound == null
        ? bindE6Input(cancelled: localCancel.future, bind: bind)
        : Future.value(prebound);
    unawaited(
      binding.then((value) async {
        if (closed) {
          await value.close();
        }
      }, onError: (Object _) {}),
    );
    server = await binding;
    if (!active() || localCancel.isCompleted) {
      throw const E6Failure('cancelled');
    }
    incoming = server.listen(
      (socket) {
        if (closed || chosen.isCompleted) {
          socket.destroy();
          return;
        }
        peer = socket;
        reader = socket.listen(
          (chunk) {
            try {
              final complete = input.add(chunk);
              transport.receivedBytes = input.receivedBytes;
              if (complete && !framed.isCompleted) {
                framed.complete(input.takeFrame());
              }
            } on E6Failure catch (error) {
              transport.receivedBytes = input.receivedBytes;
              cancel(error.code == 'input_cap' ? 'input_cap' : 'extra_input');
            }
          },
          onError: (Object error) {
            cancel(error is SocketException ? 'peer_closed' : 'io_failure');
          },
          onDone: () {
            if (!closing) {
              cancel('peer_closed');
            }
          },
        );
        chosen.complete(socket);
      },
      onError: (Object _) {
        cancel('io_failure');
      },
    );
    await transport.publish('listening');
    if (onListening != null) {
      await receiving(onListening());
    }
    if (!active() || localCancel.isCompleted) {
      throw const E6Failure('cancelled');
    }
    Future<E6Request> readFrame() async {
      await chosen.future;
      if (!active() || localCancel.isCompleted) {
        throw const E6Failure('cancelled');
      }
      await transport.publish('peer_accepted');
      final bytes = await framed.future;
      if (!active() || localCancel.isCompleted) {
        throw const E6Failure('cancelled');
      }
      try {
        return parseE6Request(
          jsonDecode(utf8.decode(bytes)),
          baseline: baseline,
        );
      } on E6Failure {
        transport.fail('invalid_probe');
        rethrow;
      } catch (_) {
        transport.fail('invalid_probe');
        throw const E6Failure('invalid_input');
      }
    }

    final request = await receiving(readFrame()).timeout(
      inputTimeout,
      onTimeout: () {
        transport.fail('exchange_deadline');
        throw const E6Failure('input_timeout');
      },
    );
    if (!active() || localCancel.isCompleted) {
      throw const E6Failure('cancelled');
    }
    await transport.publish('input_complete');
    await incoming.cancel();
    incoming = null;
    await server.close();
    server = null;
    if (!active() || localCancel.isCompleted) {
      throw const E6Failure('cancelled');
    }
    await send('accepted\n', announce: true);
    observed = true;
    final terminal = await observeE6(
      player,
      bridge,
      request,
      cancelled: localCancel.future,
      active: () => active() && !localCancel.isCompleted,
      record: (fact) => write({'type': 'fact', 'fact': fact}),
      activeTimeout:
          request.public && activeTimeout > const Duration(seconds: 60)
          ? const Duration(seconds: 60)
          : activeTimeout,
      teardownTimeout: teardownTimeout,
    );
    closing = true;
    await write(terminal);
  } catch (error) {
    if (transport.failureCode == null) {
      transport.fail(
        error is E6Failure && error.code == 'cancelled'
            ? 'cancelled'
            : 'io_failure',
      );
    }
    closed = true;
    await incoming?.cancel();
    incoming = null;
    await server?.close();
    server = null;
    if (!observed) {
      final terminal = await observeE6(
        player,
        bridge,
        _inactiveRequest(),
        cancelled: Future.value(),
        active: () => false,
        record: (fact) async {
          if (peer != null) {
            await write({'type': 'fact', 'fact': fact});
          }
        },
        teardownTimeout: teardownTimeout,
        initialFailure:
            error is E6Failure &&
                {
                  'invalid_input',
                  'input_timeout',
                  'cancelled',
                  'channel_failed',
                  'baseline_private_refused',
                  'peer_lost',
                  'event_overflow',
                }.contains(error.code)
            ? error.code
            : 'input_failed',
      );
      closing = true;
      if (peer != null) {
        try {
          await write(terminal);
        } catch (_) {}
      }
    }
  } finally {
    closed = true;
    closing = true;
    final clock = Stopwatch()..start();
    Future<void> finish(Future<void> Function() operation) async {
      final left = teardownTimeout - clock.elapsed;
      if (left <= Duration.zero) {
        throw const E6Failure('peer_lost');
      }
      await operation().timeout(left);
    }

    try {
      if (peer != null) {
        await finish(() => peer!.close().timeout(const Duration(seconds: 5)));
      }
    } catch (_) {
      transport.fail('peer_closed');
    }
    peer?.destroy();
    try {
      await finish(() async {
        await reader?.cancel();
        await incoming?.cancel();
        await server?.close();
      });
    } catch (_) {
      transport.fail('io_failure');
    }
    input.discard();
    // Native observation cancel already closed the player gate. Playback status
    // stays writable afterward so this records the actual final flush count.
    try {
      await finish(
        () => transport.publish(
          transport.failureCode == null
              ? 'closed'
              : transport.failureCode == 'cancelled'
              ? 'cancelled'
              : 'failed',
          finalStatus: true,
        ),
      );
    } catch (_) {
      /* The host retains the earlier partial public status and stops. */
    }
  }
}

// Never loaded; lets the same teardown owner handle pre-input cancellation.
E6Request _inactiveRequest() => E6Request._(const {}, Uri());
