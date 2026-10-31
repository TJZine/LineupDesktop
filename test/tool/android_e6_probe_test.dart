import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lineup_desktop/playback/native_player.dart';

import '../../tool/android/fixtures/e6_probe.dart';
import '../../tool/android/fixtures/e6_schema.dart';

Map<String, dynamic> input([Map<String, dynamic> changes = const {}]) => {
  'variant': 'https://localhost:21443/e6-clock/index.m3u8',
  'offsetSeconds': 21,
  'observeSeconds': 10,
  'mode': 'default',
  'sourceDurationMs': 30000,
  'expectedVideoCodec': 'h264',
  'expectedAudioCodec': 'aac',
  'expectedTargetDurationSeconds': 10,
  'expectedMediaSequence': 0,
  'expectedDurationsSeconds': [10, 10, 10],
  ...changes,
};
Map<String, Object?> snapshot({
  bool ready = false,
  bool terminal = false,
  String result = 'running',
  List<Map<String, Object?>> events = const [],
}) => {
  'events': events,
  'hasReady': ready,
  'terminal': terminal,
  'result': result,
  'failureCode': null,
};
const release = <String, Object?>{
  'event': 'release',
  'released': true,
  'playbackThreadAlive': false,
  'activeCalls': 0,
  'networkDrained': true,
  'variantAttempts': 1,
  'initAttempts': 1,
  'mediaAttempts': 2,
  'totalBytes': 44,
};

class Bridge implements E6Bridge {
  final calls = <String>[];
  final drains = <Object?>[];
  bool cancelled = false;
  bool missingRelease = false;
  @override
  Future<Object?> call(String method, [Map<String, Object?>? arguments]) async {
    calls.add(method);
    return switch (method) {
      'capabilities' => {
        'debugEnabled': true,
        'apiLevel': 35,
        'arm64': true,
        'h2641080': true,
        'aac': true,
        'hevcMain10': false,
        'hevc3840x1600': false,
      },
      'configure' => {'configured': true},
      'cancel' => _cancel(),
      'drain' =>
        cancelled
            ? snapshot(
                terminal: true,
                result: 'complete',
                events: missingRelease ? [] : [release],
              )
            : drains.isEmpty
            ? snapshot(ready: true, terminal: true, result: 'complete')
            : drains.removeAt(0),
      _ => throw StateError('private diagnostic should never serialize'),
    };
  }

  Object _cancel() {
    cancelled = true;
    return {'cancelled': true};
  }
}

class Player implements NativePlayer {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  final calls = <String>[];
  Completer<void>? loadGate;
  bool failDispose = false;
  bool failLoad = false;
  Future<void>? disposeGate;
  final loadStarted = Completer<void>();
  LoadKind? loadedKind;
  String? token;
  Duration? start;
  final seeks = <Duration>[];
  SeekMode? lastSeekMode;
  PlayerVideoRect? rectangle;
  @override
  Future<void> initialize() async {
    calls.add('initialize');
  }

  @override
  Future<void> load(
    Uri media, {
    String? plexToken,
    int? generation,
    bool startPaused = false,
    Duration? startPosition,
    LoadKind kind = LoadKind.direct,
  }) async {
    calls.add('load');
    loadStarted.complete();
    if (failLoad) throw StateError('private diagnostics');
    loadedKind = kind;
    token = plexToken;
    start = startPosition;
    await loadGate?.future;
  }

  @override
  Future<void> seek(Duration position, {SeekMode mode = SeekMode.exact}) async {
    lastSeekMode = mode;
    seeks.add(position);
    loadGate?.complete();
  }

  @override
  Future<void> setVideoRect(PlayerVideoRect rect) async {
    calls.add('rectangle');
    rectangle = rect;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    if (loadGate?.isCompleted == false) loadGate!.complete();
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await disposeGate;
    if (failDispose) throw StateError('secret error');
  }
}

// In-memory loopback peer: models one accepted socket and the host's write half-close.
class StartupPeer extends Stream<Uint8List> implements Socket {
  StartupPeer() {
    incoming.add(Uint8List.fromList(utf8.encode(jsonEncode(inputFields()))));
    unawaited(incoming.close());
  }
  static Map<String, dynamic> inputFields() => input();
  final incoming = StreamController<Uint8List>();
  final output = StringBuffer();
  bool destroyed = false;
  @override
  void write(Object? value) => output.write(value);
  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {}
  @override
  void destroy() {
    destroyed = true;
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return incoming.stream.listen(
      onData,
      onError: onError,
      onDone: () {
        onDone?.call();
      },
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class StartupServer extends Stream<Socket> implements ServerSocket {
  final peers = StreamController<Socket>();
  bool listening = false, closed = false;
  int connections = 0;
  bool connectionWasReady = false;
  void connect(StartupPeer peer) {
    connectionWasReady = listening && !closed;
    connections++;
    peers.add(peer);
  }

  @override
  StreamSubscription<Socket> listen(
    void Function(Socket)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    listening = true;
    return peers.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Future<ServerSocket> close() async {
    closed = true;
    unawaited(peers.close());
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class StartupBridge extends Bridge {
  Future<Object?> Function()? ready;
  bool marker = false;
  @override
  Future<Object?> call(String method, [Map<String, Object?>? arguments]) async {
    if (method == 'markInputReady') {
      calls.add(method);
      marker = true;
      if (ready != null) return await ready!();
      return {'ready': true};
    }
    if (method == 'cancel') marker = false;
    return super.call(method, arguments);
  }
}

void resumeBinding(WidgetsBinding binding) {
  if (binding.lifecycleState == AppLifecycleState.paused) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (binding.lifecycleState == AppLifecycleState.hidden) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

void pauseBinding(WidgetsBinding binding) {
  if (binding.lifecycleState == AppLifecycleState.resumed) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

Future<Map<String, Object?>> run(
  Player p,
  Bridge b, {
  bool seek = false,
  Future<void>? cancel,
  bool Function()? active,
  Duration timeout = const Duration(seconds: 1),
  Future<void> Function(Map<String, dynamic>)? record,
}) => observeE6(
  p,
  b,
  parseE6Request(
    input({'mode': seek ? 'seek_after_ready' : 'default'}),
    baseline: false,
  ),
  cancelled: cancel ?? Completer<void>().future,
  active: active ?? () => true,
  record: record ?? (_) async {},
  pollInterval: Duration.zero,
  activeTimeout: timeout,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'schema embedded in APK exactly matches independently readable host schema',
    () {
      expect(
        e6Schema,
        jsonDecode(
          File('tool/android/fixtures/e6_schema.json').readAsStringSync(),
        ),
      );
    },
  );
  test('exact manifest accepted; descriptions hide capability', () {
    final request = parseE6Request(input(), baseline: false);
    expect(request.offsetSeconds, 21);
    expect(request.toString(), 'E6Request');
  });
  for (final bad in [
    {'token': 'private'},
    {'startSeconds': 0},
    {'mode': 'seekBy'},
    {'observeSeconds': 9},
    {'offsetSeconds': 12},
    {'expectedAudioCodec': 'ac3'},
    {'expectedMediaSequence': 1},
    {'expectedTargetDurationSeconds': 121},
    {'sourceDurationMs': 35000},
    {
      'expectedDurationsSeconds': ['10', 10, 10],
    },
    {
      'expectedDurationsSeconds': [0, 10, 20],
    },
    {
      'expectedDurationsSeconds': [0.0000001, 10, 20],
    },
    {'variant': 'https://localhost:21443/e6-clock/index.m3u8?X-Plex-Token='},
    {'variant': 'https://localhost:21443/e6-clock/%2e%2e/index.m3u8'},
    {'variant': 'https://user@localhost:21443/e6-clock/index.m3u8'},
    {'variant': 'https://private.invalid/prefs'},
  ]) {
    test('reject input ${bad.keys.first} ${bad.values.first.runtimeType}', () {
      expect(
        () => parseE6Request(input(bad), baseline: false),
        throwsA(isA<E6Failure>()),
      );
    });
  }
  test('baseline refuses private and seeks before ordinary load', () {
    expect(
      () => parseE6Request(
        input({
          'variant': 'https://private.invalid/video/:/transcode/universal/session/opaque/base/index.m3u8',
        }),
        baseline: true,
      ),
      throwsA(isA<E6Failure>()),
    );
    expect(
      () => parseE6Request(input({'mode': 'seek_after_ready'}), baseline: true),
      throwsA(isA<E6Failure>()),
    );
  });
  for (final bad in [
    {'event': 'position', 'uri': 'private'},
    {
      'event': 'position',
      'positionMs': {'secret': 1},
    },
    {'event': 'position', 'durationMs': double.nan},
    {'event': 'position', 'sampleIndex': 41},
    {'event': 'position', 'sourceOriginProven': true},
    {'event': 'private_title'},
    {'event': 'failure', 'failureCode': 'raw exception'},
  ]) {
    test('closed fact schema refuses ${bad.keys.last}', () {
      expect(() => validateE6Fact(bad), throwsA(isA<E6Failure>()));
    });
  }
  test('unknown clocks remain null', () {
    expect(
      validateE6Fact({
        'event': 'position',
        'durationMs': null,
        'callbackPtsUs': null,
      })['durationMs'],
      isNull,
    );
  });
  test(
    'default load is token-free, no start, no seek and releases before success',
    () async {
      final p = Player(), b = Bridge();
      final facts = <Map<String, dynamic>>[];
      final result = await run(
        p,
        b,
        record: (e) async {
          facts.add(e);
        },
      );
      expect(p.loadedKind, LoadKind.plexSession);
      expect(p.rectangle?.width, 960);
      expect(p.token, isNull);
      expect(p.start, isNull);
      expect(p.seeks, isEmpty);
      expect(p.calls, ['initialize', 'rectangle', 'load', 'stop', 'dispose']);
      expect(b.calls.indexOf('configure'), lessThan(b.calls.indexOf('drain')));
      expect(facts.first['event'], 'capabilities');
      expect(facts.last['event'], 'release');
      expect(result['result'], 'complete');
      expect(result['nativeReleased'], true);
      expect(result['totalBytes'], 44);
    },
  );
  test(
    'READY seek unblocks pending load acknowledgement; exactly one exact seek',
    () async {
      final p = Player()..loadGate = Completer<void>(),
          b = Bridge()
            ..drains.addAll([
              snapshot(ready: true),
              snapshot(ready: true),
              snapshot(ready: true, terminal: true, result: 'complete'),
            ]);
      expect((await run(p, b, seek: true))['result'], 'complete');
      expect(p.seeks, [const Duration(seconds: 21)]);
      expect(p.lastSeekMode, SeekMode.exact);
    },
  );
  test('already inactive never loads but does real cleanup', () async {
    final p = Player(), b = Bridge();
    expect((await run(p, b, active: () => false))['result'], 'failed');
    expect(p.calls, ['stop', 'dispose']);
    expect(b.calls, ['cancel', 'drain']);
  });
  test(
    'active cancel stops pending async load without unhandled errors',
    () async {
      final p = Player()..loadGate = Completer<void>(),
          b = Bridge()..drains.addAll(List.filled(20, snapshot()));
      final c = Completer<void>();
      final task = run(p, b, cancel: c.future);
      await p.loadStarted.future;
      c.complete();
      final result = await task;
      expect(result['failureCode'], 'cancelled');
      expect(p.calls.contains('dispose'), true);
    },
  );
  test('active deadline still closes native gate and releases', () async {
    final p = Player(),
        b = Bridge()..drains.addAll(List.filled(1000, snapshot()));
    final result = await run(p, b, timeout: const Duration(milliseconds: 2));
    expect(result['failureCode'], 'observation_timeout');
    expect(result['nativeReleased'], true);
  });
  test('dispose rejection and absent actual release can never pass', () async {
    for (final missing in [false, true]) {
      final p = Player()..failDispose = !missing,
          b = Bridge()..missingRelease = missing;
      final result = await run(p, b);
      expect(result['failureCode'], 'release_failed');
      expect(result['result'], 'failed');
    }
  });
  test('privacy failure aborts before serialized private value', () async {
    final p = Player(),
        b = Bridge()
          ..drains.add(
            snapshot(
              events: [
                {'event': 'position', 'privateTitle': 'secret'},
              ],
            ),
          );
    final facts = <Map<String, dynamic>>[];
    final result = await run(
      p,
      b,
      record: (e) async {
        facts.add(e);
      },
    );
    expect(result['result'], 'failed');
    expect(jsonEncode(facts), isNot(contains('secret')));
  });
  test('socket half-close retains bidirectional ACK/facts/terminal and closes listener', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    final p = Player(), b = Bridge();
    final task = receiveAndObserveE6(
      p,
      b,
      baseline: false,
      cancelled: Completer<void>().future,
      active: () => true,
      bind: () async => server,
    );
    final peer = await Socket.connect(InternetAddress.loopbackIPv4, port);
    final received = peer.cast<List<int>>().transform(utf8.decoder).join();
    peer.write(jsonEncode(input()));
    await peer.flush();
    await peer.close();
    final text = await received.timeout(const Duration(seconds: 3));
    await task;
    final lines = const LineSplitter().convert(text);
    expect(lines.first, 'accepted');
    final records = lines
        .skip(1)
        .map(jsonDecode)
        .cast<Map<String, dynamic>>()
        .toList();
    expect(records.first['type'], 'fact');
    expect((records.first['fact'] as Map)['event'], 'capabilities');
    expect(records.last['type'], 'terminal');
    expect(records.last['nativeReleased'], true);
    expect(text, isNot(contains('localhost')));
    peer.destroy();
    final rebound = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    await rebound.close();
  });
  test(
    'partial input timeout closes peer and rebinds listener without load',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      final p = Player(), b = Bridge();
      final task = receiveAndObserveE6(
        p,
        b,
        baseline: false,
        cancelled: Completer<void>().future,
        active: () => true,
        bind: () async => server,
        inputTimeout: const Duration(milliseconds: 30),
      );
      final peer = await Socket.connect(InternetAddress.loopbackIPv4, port);
      final received = peer.cast<List<int>>().transform(utf8.decoder).join();
      peer.write('{');
      await peer.flush();
      await task.timeout(const Duration(seconds: 2));
      await received;
      expect(p.calls.contains('load'), false);
      peer.destroy();
      final rebound = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      await rebound.close();
    },
  );
  test('caps reject null/floating API instead of false zeros', () {
    for (final change in [
      {'debugEnabled': null},
      {'apiLevel': 35.5},
    ]) {
      expect(
        () => validateE6Fact({
          'event': 'capabilities',
          'debugEnabled': true,
          'apiLevel': 35,
          'arm64': true,
          'h2641080': true,
          'aac': true,
          'hevcMain10': false,
          'hevc3840x1600': false,
          ...change,
        }),
        throwsA(isA<E6Failure>()),
      );
    }
  });
  test('schema contains complete native vocabulary', () {
    final native = File(
      'android/app/src/main/kotlin/com/tjzine/lineup/player/E6Facts.kt',
    ).readAsStringSync();
    final fields = e6Schema['fields'] as Map;
    for (final match in RegExp(
      r'"([^"]+)" to setOf\((.*?)\)',
      dotAll: true,
    ).allMatches(native)) {
      expect(
        ((fields[match[1]] as Map)['enum'] as List).toSet(),
        RegExp(r'"([^"]+)"').allMatches(match[2]!).map((v) => v[1]).toSet(),
      );
    }
    for (final group in ['booleans', 'numbers']) {
      final block = RegExp(
        'val $group = setOf\\((.*?)\\)\\n',
        dotAll: true,
      ).firstMatch(native)![1]!;
      for (final key in RegExp(
        r'"([^"]+)"',
      ).allMatches(block).map((v) => v[1]!)) {
        expect(fields.containsKey(key), true, reason: key);
        expect(
          (fields[key] as Map)['type'],
          group == 'numbers' ? 'integer' : 'boolean',
        );
      }
    }
  });
  test(
    'fact overflow preserves bounded partial facts without passing',
    () async {
      final b = Bridge()
        ..drains.add(
          snapshot(
            events: List.generate(
              301,
              (i) => {'event': 'position', 'positionMs': i},
            ),
          ),
        );
      final facts = <Map<String, dynamic>>[];
      final result = await run(
        Player(),
        b,
        record: (e) async {
          facts.add(e);
        },
      );
      expect(facts.length, 300);
      expect(result['factCount'], 300);
      expect(result['failureCode'], 'event_overflow');
      expect(result['result'], 'failed');
    },
  );
  test('valid records before bad record in one drain survive', () async {
    final b = Bridge()
      ..drains.add(
        snapshot(
          events: [
            {'event': 'position', 'positionMs': 123},
            {'event': 'position', 'privateUri': 'secret'},
          ],
        ),
      );
    final facts = <Map<String, dynamic>>[];
    await run(
      Player(),
      b,
      record: (e) async {
        facts.add(e);
      },
    );
    expect(facts.any((f) => f['positionMs'] == 123), true);
    expect(jsonEncode(facts), isNot(contains('secret')));
  });
  test('failed terminal cannot issue a late planned seek', () async {
    final b = Bridge()
      ..drains.add(snapshot(ready: true, terminal: true, result: 'failed'));
    final p = Player();
    expect((await run(p, b, seek: true))['result'], 'failed');
    expect(p.seeks, isEmpty);
  });
  test('bind cancellation closes late listener', () async {
    final binding = Completer<ServerSocket>(), cancel = Completer<void>();
    final task = bindE6Input(
      bind: () => binding.future,
      cancelled: cancel.future,
    );
    final rejected = expectLater(task, throwsA(isA<E6Failure>()));
    cancel.complete();
    await rejected;
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    binding.complete(server);
    await Future<void>.delayed(Duration.zero);
    final rebound = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    await rebound.close();
  });
  test('prebound listener closes on already inactive lifecycle', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    final p = Player();
    await receiveAndObserveE6(
      p,
      Bridge(),
      baseline: false,
      cancelled: Completer<void>().future,
      active: () => false,
      prebound: server,
    );
    expect(p.calls, ['stop', 'dispose']);
    final rebound = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    await rebound.close();
  });
  test('oversize input never ACKs or loads', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = Player();
    final task = receiveAndObserveE6(
      p,
      Bridge(),
      baseline: false,
      cancelled: Completer<void>().future,
      active: () => true,
      prebound: server,
    );
    final peer = await Socket.connect(
      InternetAddress.loopbackIPv4,
      server.port,
    );
    final received = peer.cast<List<int>>().transform(utf8.decoder).join();
    peer.add(List.filled(32769, 32));
    await peer.flush();
    await peer.close();
    final text = await received;
    await task;
    expect(text.startsWith('accepted\n'), false);
    expect(p.calls.contains('load'), false);
    peer.destroy();
  });
  test('rejected asynchronous load cannot become complete', () async {
    final result = await run(Player()..failLoad = true, Bridge());
    expect(result['result'], 'failed');
    expect(result['failureCode'], 'load_failed');
  });
  test('teardown deadline cannot claim pending dispose complete', () async {
    final p = Player()..disposeGate = Completer<void>().future;
    final result = await observeE6(
      p,
      Bridge(),
      parseE6Request(input(), baseline: false),
      cancelled: Completer<void>().future,
      active: () => true,
      record: (_) async {},
      teardownTimeout: const Duration(milliseconds: 20),
    );
    expect(result['result'], 'failed');
    expect(result['failureCode'], 'release_failed');
    expect(result['disposeCompleted'], false);
    expect(result['nativeReleased'], false);
  });
  test('real debug channel adapter preserves configure boundary and sanitized drain', () async {
    const channel = MethodChannel('lineup/e6');
    final native = Bridge();
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return native.call(
            call.method,
            call.arguments == null
                ? null
                : Map<String, Object?>.from(call.arguments as Map),
          );
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final result = await observeE6(
      Player(),
      const MethodChannelE6Bridge(),
      parseE6Request(input(), baseline: false),
      cancelled: Completer<void>().future,
      active: () => true,
      record: (_) async {},
    );
    expect(result['result'], 'complete');
    final args =
        calls.singleWhere((c) => c.method == 'configure').arguments as Map;
    expect(args.keys.toSet(), input().keys.toSet());
    expect(args.containsKey('startSeconds'), false);
    expect(calls.first.method, 'capabilities');
    expect(calls.last.method, 'drain');
  });
  test('entrypoint waits for resumed after inactive first frame before one connection', () async {
    final binding = WidgetsBinding.instance;
    resumeBinding(binding);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    final server = StartupServer(),
        peer = StartupPeer(),
        bridge = StartupBridge(),
        player = Player();
    final frame = Completer<VoidCallback>(),
        events = <String>[],
        readyChecks = <bool>[];
    bridge.ready = () async {
      events.add('mark');
      readyChecks.addAll([
        server.listening,
        events.contains('firstFrame'),
        binding.lifecycleState == AppLifecycleState.resumed,
      ]);
      server.connect(peer);
      events.add('connect');
      return {'ready': true};
    };
    final task = startE6Fixture(
      player,
      bridge,
      baseline: true,
      bind: () async {
        events.add('bind');
        return server;
      },
      show: (callback) {
        events.add('show');
        frame.complete(callback);
      },
    );
    final callback = await frame.future;
    events.add('firstFrame');
    callback();
    await Future<void>.delayed(Duration.zero);
    expect(events, ['bind', 'show', 'firstFrame']);
    expect(bridge.marker, false);
    expect(server.listening, false);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await task;
    expect(events, containsAllInOrder(['firstFrame', 'mark', 'connect']));
    expect(readyChecks, [true, true, true]);
    expect(server.connections, 1);
    expect(server.connectionWasReady, true);
    expect(peer.output.toString(), startsWith('accepted\n'));
    expect(
      jsonDecode(const LineSplitter().convert(peer.output.toString()).last),
      containsPair('result', 'complete'),
    );
    expect(bridge.marker, false);
    expect(server.closed, true);
    expect(peer.destroyed, true);
  });
  test(
    'pause during initial resumed wait closes listener without marker or load',
    () async {
      final binding = WidgetsBinding.instance;
      resumeBinding(binding);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      final server = StartupServer(),
          bridge = StartupBridge(),
          player = Player(),
          frame = Completer<VoidCallback>();
      final task = startE6Fixture(
        player,
        bridge,
        baseline: true,
        bind: () async => server,
        show: frame.complete,
      );
      (await frame.future)();
      pauseBinding(binding);
      await task;
      expect(server.closed, true);
      expect(bridge.calls, isNot(contains('markInputReady')));
      expect(player.calls, isNot(contains('load')));
      resumeBinding(binding);
    },
  );
  test(
    'detach during startup wait cannot later resume or publish readiness',
    () async {
      final binding = WidgetsBinding.instance;
      resumeBinding(binding);
      pauseBinding(binding);
      final server = StartupServer(),
          bridge = StartupBridge(),
          player = Player(),
          frame = Completer<VoidCallback>();
      final task = startE6Fixture(
        player,
        bridge,
        baseline: true,
        bind: () async => server,
        show: frame.complete,
      );
      (await frame.future)();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
      await task;
      resumeBinding(binding);
      await Future<void>.delayed(Duration.zero);
      expect(server.closed, true);
      expect(bridge.calls, isNot(contains('markInputReady')));
      expect(player.calls, isNot(contains('load')));
    },
  );
  test('pause after marker publication removes marker and ignores late ready reply', () async {
    final binding = WidgetsBinding.instance;
    resumeBinding(binding);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    final server = StartupServer(),
        bridge = StartupBridge(),
        player = Player(),
        frame = Completer<VoidCallback>();
    final reply = Completer<Object?>(), marked = Completer<void>();
    bridge.ready = () {
      marked.complete();
      return reply.future;
    };
    final task = startE6Fixture(
      player,
      bridge,
      baseline: true,
      bind: () async => server,
      show: frame.complete,
    );
    (await frame.future)();
    resumeBinding(binding);
    await marked.future;
    expect(bridge.marker, true);
    expect(server.listening, true);
    pauseBinding(binding);
    await task;
    expect(bridge.marker, false);
    expect(server.closed, true);
    expect(player.calls, isNot(contains('load')));
    reply.complete({'ready': true});
    resumeBinding(binding);
    await Future<void>.delayed(Duration.zero);
    expect(bridge.calls.where((c) => c == 'markInputReady').length, 1);
    expect(player.calls, isNot(contains('load')));
  });
  test(
    'startup owns pause cancellation before asynchronous bind returns',
    () async {
      final binding = WidgetsBinding.instance;
      resumeBinding(binding);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      final pending = Completer<ServerSocket>(),
          server = StartupServer(),
          bridge = StartupBridge(),
          player = Player();
      var shown = false;
      final task = startE6Fixture(
        player,
        bridge,
        baseline: true,
        bind: () => pending.future,
        show: (_) {
          shown = true;
        },
      );
      pauseBinding(binding);
      await task;
      pending.complete(server);
      await Future<void>.delayed(Duration.zero);
      expect(server.closed, true);
      expect(shown, false);
      expect(bridge.calls, isNot(contains('markInputReady')));
      expect(player.calls, isNot(contains('load')));
      resumeBinding(binding);
    },
  );
  test('initial resumed deadline closes prebound socket without a readiness marker', () async {
    final binding = WidgetsBinding.instance;
    resumeBinding(binding);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    final server = StartupServer(),
        bridge = StartupBridge(),
        player = Player(),
        frame = Completer<VoidCallback>();
    final task = startE6Fixture(
      player,
      bridge,
      baseline: true,
      bind: () async => server,
      show: frame.complete,
      startupTimeout: const Duration(milliseconds: 15),
    );
    (await frame.future)();
    await task;
    expect(server.closed, true);
    expect(bridge.calls, isNot(contains('markInputReady')));
    expect(player.calls, isNot(contains('load')));
    resumeBinding(binding);
  });
  test(
    'listener callback accepts one buffered peer before starting input read',
    () async {
      final server = StartupServer(), peer = StartupPeer();
      await receiveAndObserveE6(
        Player(),
        Bridge(),
        baseline: true,
        prebound: server,
        cancelled: Completer<void>().future,
        active: () => true,
        onListening: () async {
          server.connect(peer);
        },
      ).timeout(const Duration(seconds: 1));
      expect(peer.output.toString(), startsWith('accepted\n'));
    },
  );
}
