import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/android/fixtures/e6_transport_contract.dart';

class Bridge implements TransportBridge {
  final statuses = <Map<String, Object?>>[];
  final timeline = <String>[];
  final readyCalled = Completer<void>();
  final cancelled = Completer<void>();
  Future<void> Function()? onReady;
  Future<void> Function(Map<String, Object?>)? onStatus;
  Future<void> Function()? onCancel;
  @override
  Future<void> status(Map<String, Object?> facts) async {
    statuses.add(Map.of(facts));
    timeline.add(facts['phase']! as String);
    await onStatus?.call(facts);
  }

  @override
  Future<void> ready() async {
    timeline.add('ready');
    if (!readyCalled.isCompleted) {
      readyCalled.complete();
    }
    await onReady?.call();
  }

  @override
  Future<void> cancel() async {
    timeline.add('cancel');
    if (!cancelled.isCompleted) {
      cancelled.complete();
    }
    await onCancel?.call();
  }
}

void resume() {
  final binding = WidgetsBinding.instance;
  if (binding.lifecycleState == AppLifecycleState.paused) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (binding.lifecycleState == AppLifecycleState.hidden) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

void pause() {
  final binding = WidgetsBinding.instance;
  if (binding.lifecycleState == AppLifecycleState.resumed) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

Future<({Map<String, Object?> result, String reply, Bridge bridge})> exchange(
  TransportMode mode,
  List<int> bytes, {
  bool halfClose = false,
}) async {
  resume();
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  final bridge = Bridge();
  final task = runTransportFixture(
    mode,
    bridge: bridge,
    bind: () async => server,
    show: (frame) => frame(),
    exchangeTimeout: const Duration(seconds: 2),
  );
  await bridge.readyCalled.future;
  final peer = await Socket.connect(InternetAddress.loopbackIPv4, port);
  final response = peer.cast<List<int>>().transform(utf8.decoder).join();
  peer.add(bytes);
  await peer.flush();
  if (halfClose) {
    await peer.close();
  }
  final reply = await response.timeout(const Duration(seconds: 3));
  final result = await task;
  peer.destroy();
  final rebound = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
  await rebound.close();
  return (result: result, reply: reply, bridge: bridge);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('entrypoint accepts only the exact public debug argument sets', () {
    for (final mode in TransportMode.values) {
      expect(
        transportMode([
          '--case=session-live',
          '--e6-observe',
          '--e6-transport=${mode.name}',
        ]),
        mode,
      );
    }
    for (final args in [
      <String>[],
      ['--case=session-live', '--e6-observe'],
      ['--case=session-live', '--e6-observe', '--e6-transport=other'],
      [
        '--case=session-live',
        '--e6-observe',
        '--e6-transport=eof',
        '--token=private',
      ],
      ['--e6-observe', '--e6-observe', '--e6-transport=line'],
    ]) {
      expect(transportMode(args), isNull);
    }
  });
  test('public probe/reply byte counts and hard caps are fixed', () {
    expect(utf8.encode(transportProbe).length, 11);
    expect(utf8.encode('$transportProbe\n').length, 12);
    expect(utf8.encode(transportReply).length, 30);
    expect(transportReply, '{"probe":1}\n{"complete":true}\n');
    expect(30, lessThanOrEqualTo(transportOutputCap));
    expect(transportInputCap, 32768);
  });
  for (final mode in TransportMode.values) {
    test(
      '${mode.name} reader accepts arbitrary chunk boundaries without retaining input',
      () {
        final bytes = utf8.encode(
          mode == TransportMode.eof ? transportProbe : '$transportProbe\n',
        );
        for (var split = 0; split <= bytes.length; split++) {
          final reader = ProbeInput(mode);
          reader.add(bytes.sublist(0, split));
          reader.add(bytes.sublist(split));
          expect(reader.complete, true);
          expect(reader.receivedBytes, bytes.length);
        }
      },
    );
    test('${mode.name} reader rejects a second message and malformed first bytes', () {
      for (final bytes in [
        utf8.encode(
          '${mode == TransportMode.eof ? transportProbe : '$transportProbe\n'}x',
        ),
        utf8.encode('{"probe":2}'),
      ]) {
        expect(
          () => ProbeInput(mode).add(bytes),
          throwsA(isA<TransportFailure>()),
        );
      }
    });
    test(
      '${mode.name} input byte cap is enforced before buffering an oversized chunk',
      () {
        final reader = ProbeInput(mode);
        expect(
          () => reader.add(List.filled(32769, 32)),
          throwsA(
            isA<TransportFailure>().having((e) => e.code, 'code', 'input_cap'),
          ),
        );
        expect(reader.receivedBytes, 32768);
      },
    );
  }
  test(
    'direct EOF half-close may legitimately receive the complete reply',
    () async {
      final observed = await exchange(
        TransportMode.eof,
        utf8.encode(transportProbe),
        halfClose: true,
      );
      expect(observed.reply, '{"probe":1}\n{"complete":true}\n');
      expect(observed.result, containsPair('phase', 'closed'));
      expect(observed.result, containsPair('failureCode', null));
      expect(observed.result, containsPair('receivedBytes', 11));
      expect(observed.result, containsPair('flushedBytes', 30));
      expect(
        observed.bridge.timeline,
        containsAllInOrder([
          'listening',
          'ready',
          'peer_accepted',
          'input_eof',
          'input_complete',
          'reply_attempt',
          'reply_flushed',
          'closed',
          'cancel',
        ]),
      );
    },
  );
  test(
    'direct LF frame replies while the host write side remains open',
    () async {
      final observed = await exchange(
        TransportMode.line,
        utf8.encode('$transportProbe\n'),
      );
      expect(observed.reply, '{"probe":1}\n{"complete":true}\n');
      expect(observed.result['phase'], 'closed');
      expect(observed.result['failureCode'], isNull);
      expect(observed.result['receivedBytes'], 12);
      expect(observed.result['flushedBytes'], 30);
      expect(observed.bridge.timeline, isNot(contains('input_eof')));
    },
  );
  test(
    'EOF valid prefix preserves uncertainty without reply or forced failure',
    () async {
      for (final text in ['', '{"probe":']) {
        final observed = await exchange(
          TransportMode.eof,
          utf8.encode(text),
          halfClose: true,
        );
        expect(observed.reply, isEmpty);
        expect(observed.result['phase'], 'input_incomplete');
        expect(observed.result['failureCode'], isNull);
        expect(observed.result['responseAttempted'], false);
        expect(observed.result['receivedBytes'], text.length);
      }
    },
  );
  test(
    'LF detects premature host half-close instead of treating it as duplex',
    () async {
      final observed = await exchange(
        TransportMode.line,
        utf8.encode(transportProbe),
        halfClose: true,
      );
      expect(observed.result['failureCode'], 'peer_closed');
      expect(observed.result['phase'], 'failed');
    },
  );
  test(
    'extra bytes in the LF frame are rejected without echoing arbitrary data',
    () async {
      final observed = await exchange(
        TransportMode.line,
        utf8.encode('$transportProbe\nPRIVATE'),
      );
      expect(observed.result['phase'], 'failed');
      expect(observed.result['failureCode'], 'extra_input');
      expect(observed.reply, isEmpty);
      expect(jsonEncode(observed.bridge.statuses), isNot(contains('PRIVATE')));
    },
  );
  test('native status payload is exact, bounded, monotone and finalized before cancel', () async {
    final observed = await exchange(
      TransportMode.line,
      utf8.encode('$transportProbe\n'),
    );
    var received = 0, flushed = 0;
    var attempted = false;
    for (final status in observed.bridge.statuses) {
      expect(status.keys.toSet(), {
        'mode',
        'phase',
        'receivedBytes',
        'responseAttempted',
        'flushedBytes',
        'failureCode',
      });
      expect(status['mode'], 'line');
      expect(status['receivedBytes'], inInclusiveRange(received, 32768));
      expect(status['flushedBytes'], inInclusiveRange(flushed, 1024));
      if (attempted) {
        expect(status['responseAttempted'], true);
      }
      received = status['receivedBytes']! as int;
      flushed = status['flushedBytes']! as int;
      attempted = status['responseAttempted']! as bool;
      expect(utf8.encode(jsonEncode(status)).length, lessThan(512));
    }
    expect(observed.bridge.timeline.last, 'cancel');
    expect(observed.bridge.statuses.last, observed.result);
  });
  test('startup waits for frame and resumed before publishing a real listening socket', () async {
    resume();
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.inactive,
    );
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
        bridge = Bridge();
    final frame = Completer<VoidCallback>();
    final task = runTransportFixture(
      TransportMode.line,
      bridge: bridge,
      bind: () async => server,
      show: frame.complete,
      exchangeTimeout: const Duration(seconds: 1),
    );
    (await frame.future)();
    await Future<void>.delayed(Duration.zero);
    expect(bridge.timeline, isNot(contains('ready')));
    resume();
    await bridge.readyCalled.future;
    final peer = await Socket.connect(
      InternetAddress.loopbackIPv4,
      server.port,
    );
    final response = peer.cast<List<int>>().transform(utf8.decoder).join();
    peer.write('$transportProbe\n');
    await peer.flush();
    expect(await response, transportReply);
    expect((await task)['phase'], 'closed');
    peer.destroy();
  });
  test(
    'pause during initial wait cancels and closes the prebound socket',
    () async {
      resume();
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.inactive,
      );
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
          bridge = Bridge();
      final port = server.port, frame = Completer<VoidCallback>();
      final task = runTransportFixture(
        TransportMode.eof,
        bridge: bridge,
        bind: () async => server,
        show: frame.complete,
      );
      (await frame.future)();
      pause();
      final result = await task;
      expect(result['phase'], 'cancelled');
      expect(bridge.timeline, isNot(contains('ready')));
      final rebound = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      await rebound.close();
      resume();
    },
  );
  test(
    'startup deadline and missing-peer exchange deadline close without retries',
    () async {
      resume();
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.inactive,
      );
      final a = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
          one = Bridge();
      final startup = await runTransportFixture(
        TransportMode.eof,
        bridge: one,
        bind: () async => a,
        show: (f) => f(),
        startupTimeout: const Duration(milliseconds: 15),
      );
      expect(startup['failureCode'], 'startup_deadline');
      expect(one.timeline, isNot(contains('ready')));
      resume();
      final b = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
          two = Bridge();
      final exchange = await runTransportFixture(
        TransportMode.line,
        bridge: two,
        bind: () async => b,
        show: (f) => f(),
        exchangeTimeout: const Duration(milliseconds: 15),
      );
      expect(exchange['failureCode'], 'exchange_deadline');
      expect(two.timeline.where((v) => v == 'ready').length, 1);
    },
  );
  test(
    'late bind after cancellation is closed and cannot advertise readiness',
    () async {
      resume();
      final opening = Completer<ServerSocket>(), bridge = Bridge();
      final task = runTransportFixture(
        TransportMode.line,
        bridge: bridge,
        bind: () => opening.future,
        show: (_) => fail('must not show'),
      );
      await Future<void>.delayed(Duration.zero);
      pause();
      final result = await task;
      expect(result['phase'], 'cancelled');
      final late = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
          port = late.port;
      opening.complete(late);
      await Future<void>.delayed(Duration.zero);
      final rebound = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      await rebound.close();
      expect(bridge.timeline, isNot(contains('ready')));
      resume();
    },
  );
  test('channel adapter uses only status, readiness and cancel with strict replies', () async {
    const channel = MethodChannel('lineup/e6');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return {
            switch (call.method) {
              'transportStatus' => 'stored',
              'markInputReady' => 'ready',
              _ => 'cancelled',
            }: true,
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    const bridge = TransportMethodChannel();
    await bridge.status({
      'mode': 'eof',
      'phase': 'starting',
      'receivedBytes': 0,
      'responseAttempted': false,
      'flushedBytes': 0,
      'failureCode': null,
    });
    await bridge.ready();
    await bridge.cancel();
    expect(calls.map((c) => c.method), [
      'transportStatus',
      'markInputReady',
      'cancel',
    ]);
    expect(calls.skip(1).every((c) => c.arguments == null), true);
  });
  test(
    'LF subscription rejects additional bytes arriving during the reply',
    () async {
      resume();
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
          bridge = Bridge();
      final attempt = Completer<void>(), release = Completer<void>();
      bridge.onStatus = (facts) async {
        if (facts['phase'] == 'reply_attempt') {
          attempt.complete();
          await release.future;
        }
      };
      final task = runTransportFixture(
        TransportMode.line,
        bridge: bridge,
        bind: () async => server,
        show: (f) => f(),
        exchangeTimeout: const Duration(seconds: 1),
      );
      await bridge.readyCalled.future;
      final peer = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      final response = peer.cast<List<int>>().transform(utf8.decoder).join();
      peer.write('$transportProbe\n');
      await peer.flush();
      await attempt.future;
      peer.write('x');
      await peer.flush();
      final output = await response;
      final result = await task;
      release.complete();
      peer.destroy();
      expect(result['failureCode'], 'extra_input');
      expect(result['phase'], 'failed');
      expect(result['receivedBytes'], 13);
      expect(result['flushedBytes'], 0);
      expect(transportReply.startsWith(output), true);
      expect(output.length, lessThanOrEqualTo(30));
    },
  );
  test(
    'pause and detach cancel an accepted peer without waiting for EOF',
    () async {
      resume();
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
          bridge = Bridge();
      final accepted = Completer<void>();
      bridge.onStatus = (facts) async {
        if (facts['phase'] == 'peer_accepted') {
          accepted.complete();
        }
      };
      final task = runTransportFixture(
        TransportMode.line,
        bridge: bridge,
        bind: () async => server,
        show: (f) => f(),
      );
      await bridge.readyCalled.future;
      final peer = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      final response = peer
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join()
          .then<String?>(
            (value) => value,
            onError: (Object error) {
              if (error is SocketException) return null;
              throw StateError('Unexpected test socket error');
            },
          );
      await accepted.future;
      peer.write('{');
      await peer.flush();
      pause();
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.detached,
      );
      final result = await task;
      final observed = await response;
      expect(observed == null || observed.isEmpty, true);
      peer.destroy();
      expect(result['phase'], 'cancelled');
      expect(result['failureCode'], 'cancelled');
      expect(bridge.timeline.last, 'cancel');
      resume();
    },
  );
  test('detach before resumed never advertises readiness', () async {
    resume();
    pause();
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
        bridge = Bridge(),
        frame = Completer<VoidCallback>();
    final task = runTransportFixture(
      TransportMode.eof,
      bridge: bridge,
      bind: () async => server,
      show: frame.complete,
    );
    (await frame.future)();
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.detached,
    );
    expect((await task)['phase'], 'cancelled');
    expect(bridge.timeline, isNot(contains('ready')));
    resume();
  });
  test(
    'case deadline interrupts a blocked status operation without retry',
    () async {
      resume();
      final bridge = Bridge(), held = Completer<void>();
      var binds = 0;
      bridge.onStatus = (facts) async {
        if (facts['phase'] == 'starting') {
          await held.future;
        }
      };
      final result = await runTransportFixture(
        TransportMode.eof,
        bridge: bridge,
        bind: () async {
          binds++;
          return ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        },
        show: (_) {},
        caseTimeout: const Duration(milliseconds: 15),
      );
      held.complete();
      expect(result['phase'], 'failed');
      expect(result['failureCode'], 'exchange_deadline');
      expect(binds, 0);
      expect(bridge.timeline, ['starting', 'failed', 'cancel']);
    },
  );
  test('teardown deadline bounds a nonreturning cancel operation', () async {
    resume();
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.inactive,
    );
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
        bridge = Bridge(),
        held = Completer<void>();
    bridge.onCancel = () => held.future;
    final result = await runTransportFixture(
      TransportMode.eof,
      bridge: bridge,
      bind: () async => server,
      show: (f) => f(),
      startupTimeout: const Duration(milliseconds: 10),
      teardownTimeout: const Duration(milliseconds: 15),
    );
    held.complete();
    expect(result['phase'], 'failed');
    expect(result['failureCode'], 'startup_deadline');
    expect(bridge.timeline.last, 'cancel');
    resume();
  });
  test(
    'channel adapter refuses extra or wrongly typed response fields',
    () async {
      const channel = MethodChannel('lineup/e6');
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      for (final result in [
        <String, Object?>{'ready': true, 'private': 'x'},
        {'ready': 1},
        <String, Object?>{},
      ]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async => result);
        await expectLater(
          const TransportMethodChannel().ready(),
          throwsA(isA<TransportFailure>()),
        );
      }
    },
  );
  test(
    'cancel and bind completion in the same turn cannot leak a listener',
    () async {
      resume();
      final late = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
          port = late.port,
          opening = Completer<ServerSocket>(),
          entered = Completer<void>(),
          bridge = Bridge();
      final task = runTransportFixture(
        TransportMode.eof,
        bridge: bridge,
        bind: () {
          entered.complete();
          return opening.future;
        },
        show: (_) {
          throw StateError('cancelled startup must not show');
        },
      );
      await entered.future;
      pause();
      opening.complete(late);
      final result = await task;
      await Future<void>.delayed(Duration.zero);
      expect(result['phase'], 'cancelled');
      expect(bridge.timeline, isNot(contains('ready')));
      final rebound = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      await rebound.close();
      resume();
    },
  );
}
