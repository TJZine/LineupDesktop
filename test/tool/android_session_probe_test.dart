import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/playback/native_player.dart';

import '../../tool/android/fixtures/session_probe.dart';
import '../support/test_doubles.dart';

class _Player extends FakeNativePlayer {
  int loadCount = 0;
  LoadKind? kind;
  String? token;
  Duration? start;

  @override
  Future<void> load(
    Uri media, {
    String? plexToken,
    int? generation,
    bool startPaused = false,
    Duration? startPosition,
    LoadKind kind = LoadKind.direct,
  }) async {
    loadCount++;
    this.kind = kind;
    token = plexToken;
    start = startPosition;
    position = const Duration(seconds: 42);
    duration = const Duration(seconds: 1200);
    status = const PlayerStatus(state: PlayerState.playing, message: 'Ready');
  }
}

class _Socket extends Stream<Uint8List> implements Socket {
  final bytes = StreamController<Uint8List>();
  bool destroyed = false;
  final written = StringBuffer();
  @override
  void write(Object? value) => written.write(value);
  @override
  Future<void> flush() async {}
  @override
  void destroy() {
    destroyed = true;
    unawaited(bytes.close());
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => bytes.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Server extends Stream<Socket> implements ServerSocket {
  final peers = StreamController<Socket>();
  bool closed = false;
  @override
  Future<ServerSocket> close() async {
    closed = true;
    await peers.close();
    return this;
  }

  @override
  StreamSubscription<Socket> listen(
    void Function(Socket)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => peers.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  List<int> payload([Map<String, Object?> fields = const {}]) => utf8.encode(
    jsonEncode({
      'variant': 'https://synthetic.invalid/session/private-capability',
      'offsetSeconds': 600,
      'observeSeconds': 1,
      ...fields,
    }),
  );

  test(
    'bounded input accepts chunking without exposing capability in description',
    () async {
      final bytes = payload();
      final request = await decodeSessionProbe(
        Stream.fromIterable([bytes.sublist(0, 15), bytes.sublist(15)]),
      );
      expect(request.offsetSeconds, 600);
      expect(request.observeSeconds, 1);
      expect(request.toString(), 'SessionProbeRequest');
      expect(
        const SessionProbeFailure('invalid_input').toString(),
        'SessionProbeFailure(invalid_input)',
      );
    },
  );

  test(
    'input refuses credentials, explicit starts, unsafe URIs and excess bytes',
    () async {
      final bad = [
        payload({'plexToken': 'synthetic'}),
        payload({'startSeconds': 0}),
        payload({'offsetSeconds': true}),
        payload({'observeSeconds': 31}),
        utf8.encode('{'),
        List<int>.filled(sessionProbeMaxBytes + 1, 32),
        for (final uri in [
          'http://synthetic.invalid/a',
          'https://u:p@synthetic.invalid/a',
          'https://synthetic.invalid/a?%58-pLeX-tOkEn=synthetic',
          'https://synthetic.invalid/a#fragment',
        ])
          payload({'variant': uri}),
      ];
      for (final bytes in bad) {
        await expectLater(
          decodeSessionProbe(Stream.value(bytes)),
          throwsA(
            isA<SessionProbeFailure>().having(
              (e) => e.code,
              'code',
              'invalid_input',
            ),
          ),
        );
      }
    },
  );

  test('offset600 stays evidence metadata; player gets session kind with no token/start', () async {
    final player = _Player();
    final request = await decodeSessionProbe(Stream.value(payload()));
    final facts = <Map<String, Object?>>[];
    await measureSessionProbe(
      player,
      request,
      record: (phase, value) => facts.add({'phase': phase, ...value}),
      wait: (duration) async {
        player.position += duration;
      },
    );
    expect(player.kind, LoadKind.plexSession);
    expect(player.token, isNull);
    expect(player.start, isNull);
    expect(facts, hasLength(5));
    expect(facts.first['positionMs'], 42000);
    expect(facts.first['durationMs'], 1200000);
    expect(facts.every((fact) => fact['offsetSeconds'] == 600), isTrue);
    expect(jsonEncode(facts), isNot(contains('private-capability')));
    expect(jsonEncode(facts), isNot(contains('synthetic.invalid')));
    await player.dispose();
  });

  test('measurement fails on no progress and stopped playback without recording URI', () async {
    final request = await decodeSessionProbe(Stream.value(payload()));
    final player = _Player();
    await expectLater(
      measureSessionProbe(
        player,
        request,
        record: (_, _) {},
        wait: (_) async {},
      ),
      throwsA(
        isA<SessionProbeFailure>().having((e) => e.code, 'code', 'no_progress'),
      ),
    );
    await expectLater(
      measureSessionProbe(
        player,
        request,
        record: (_, _) {},
        wait: (_) async {
          player.status = const PlayerStatus(
            state: PlayerState.stopped,
            message: 'Stopped',
          );
        },
      ),
      throwsA(
        isA<SessionProbeFailure>().having(
          (e) => e.code,
          'code',
          'playback_failed',
        ),
      ),
    );
    await player.dispose();
  });
  test(
    'input lifetime closes listener and every accepted peer without network',
    () async {
      final server = _Server();
      final first = _Socket();
      final extra = _Socket();
      final cancelled = Completer<void>();
      final result = receiveSessionProbe(
        cancelled: cancelled.future,
        bind: () async => server,
      );
      await Future<void>.delayed(Duration.zero);
      server.peers.add(first);
      server.peers.add(extra);
      first.bytes.add(Uint8List.fromList(payload()));
      await first.bytes.close();
      expect((await result).offsetSeconds, 600);
      expect(first.written.toString(), 'accepted\n');
      expect(first.destroyed, isTrue);
      expect(extra.destroyed, isTrue);
      expect(server.closed, isTrue);
    },
  );

  test(
    'cancelled partial input and input deadline release owned sockets/listener',
    () async {
      final server = _Server();
      final peer = _Socket();
      final cancelled = Completer<void>();
      final result = receiveSessionProbe(
        cancelled: cancelled.future,
        bind: () async => server,
      );
      final expectation = expectLater(
        result,
        throwsA(
          isA<SessionProbeFailure>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      server.peers.add(peer);
      peer.bytes.add(Uint8List.fromList(utf8.encode('{')));
      await Future<void>.delayed(Duration.zero);
      cancelled.complete();
      await expectation;
      expect(peer.destroyed, isTrue);
      expect(peer.written.toString(), isEmpty);
      expect(server.closed, isTrue);
      final waiting = _Server();
      await expectLater(
        receiveSessionProbe(
          cancelled: Completer<void>().future,
          timeout: const Duration(milliseconds: 1),
          bind: () async => waiting,
        ),
        throwsA(
          isA<SessionProbeFailure>().having(
            (e) => e.code,
            'code',
            'input_timeout',
          ),
        ),
      );
      expect(waiting.closed, isTrue);
    },
  );
  test(
    'already-inactive and active cancellation prevent stale measurement work',
    () async {
      final request = await decodeSessionProbe(Stream.value(payload()));
      final player = _Player();
      await expectLater(
        measureSessionProbe(
          player,
          request,
          record: (_, _) {},
          active: () => false,
        ),
        throwsA(
          isA<SessionProbeFailure>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );
      expect(player.loadCount, 0);
      final cancelled = Completer<void>();
      final sampling = Completer<void>();
      final result = measureSessionProbe(
        player,
        request,
        record: (_, _) {},
        cancelled: cancelled.future,
        wait: (_) {
          sampling.complete();
          return Completer<void>().future;
        },
      );
      final expectation = expectLater(
        result,
        throwsA(
          isA<SessionProbeFailure>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );
      await sampling.future;
      cancelled.complete();
      await expectation;
      expect(player.loadCount, 1);
      await player.dispose();
    },
  );
  test(
    'real loopback input closes listener/peer and allows same-port rebind',
    () async {
      final bound = Completer<int>();
      final input = receiveSessionProbe(
        cancelled: Completer<void>().future,
        bind: () async {
          final server = await ServerSocket.bind(
            InternetAddress.loopbackIPv4,
            0,
          );
          bound.complete(server.port);
          return server;
        },
      );
      final port = await bound.future;
      final peer = await Socket.connect(InternetAddress.loopbackIPv4, port);
      try {
        peer.add(payload());
        await peer.flush();
        await peer.close();
        expect(await utf8.decoder.bind(peer).join(), 'accepted\n');
        expect((await input).offsetSeconds, 600);
        final rebound = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          port,
        );
        await rebound.close();
      } finally {
        peer.destroy();
      }
    },
  );

  test(
    'real loopback timeout/oversize/cancel close input and reject late peers',
    () async {
      for (final scenario in ['timeout', 'oversize', 'cancel']) {
        final bound = Completer<int>();
        final cancelled = Completer<void>();
        final input = receiveSessionProbe(
          cancelled: cancelled.future,
          timeout: Duration(milliseconds: scenario == 'timeout' ? 20 : 1000),
          bind: () async {
            final server = await ServerSocket.bind(
              InternetAddress.loopbackIPv4,
              0,
            );
            bound.complete(server.port);
            return server;
          },
        );
        final expected = scenario == 'oversize'
            ? 'invalid_input'
            : scenario == 'cancel'
            ? 'cancelled'
            : 'input_timeout';
        final expectation = expectLater(
          input,
          throwsA(
            isA<SessionProbeFailure>().having((e) => e.code, 'code', expected),
          ),
        );
        final port = await bound.future;
        Socket? peer;
        try {
          if (scenario != 'timeout') {
            peer = await Socket.connect(InternetAddress.loopbackIPv4, port);
            peer.add(
              scenario == 'oversize'
                  ? List<int>.filled(sessionProbeMaxBytes + 1, 32)
                  : [123],
            );
            await peer.flush();
            await Future<void>.delayed(Duration.zero);
            if (scenario == 'cancel') cancelled.complete();
          }
          await expectation;
          await expectLater(
            Socket.connect(
              InternetAddress.loopbackIPv4,
              port,
              timeout: const Duration(milliseconds: 100),
            ),
            throwsA(isA<SocketException>()),
          );
          final rebound = await ServerSocket.bind(
            InternetAddress.loopbackIPv4,
            port,
          );
          await rebound.close();
        } finally {
          peer?.destroy();
        }
      }
    },
  );
}
