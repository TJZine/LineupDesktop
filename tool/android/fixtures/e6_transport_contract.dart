// Public-only transport diagnostic. No player, media, URI, or HTTP dependency.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const transportProbe = '{"probe":1}';
const transportReply = '{"probe":1}\n{"complete":true}\n';
const transportInputCap = 32768;
const transportOutputCap = 1024;

enum TransportMode { eof, line }

class TransportFailure implements Exception {
  const TransportFailure(this.code);
  final String code;
  @override
  String toString() => 'TransportFailure($code)';
}

TransportMode? transportMode(List<String> args) {
  if (!kDebugMode ||
      args.length != 3 ||
      !args.contains('--case=session-live') ||
      !args.contains('--e6-observe')) {
    return null;
  }
  if (args.contains('--e6-transport=eof')) {
    return TransportMode.eof;
  }
  if (args.contains('--e6-transport=line')) {
    return TransportMode.line;
  }
  return null;
}

/// Stores only prefix position and a bounded count, never arbitrary input bytes.
class ProbeInput {
  ProbeInput(TransportMode mode)
    : expected =
          (mode == TransportMode.eof ? transportProbe : '$transportProbe\n')
              .codeUnits;
  final List<int> expected;
  int receivedBytes = 0;
  int matchedBytes = 0;
  bool get complete => matchedBytes == expected.length;
  void add(List<int> bytes) {
    if (receivedBytes + bytes.length > transportInputCap) {
      receivedBytes = transportInputCap; // input_cap explicitly records overflow beyond this bound.
      throw const TransportFailure('input_cap');
    }
    receivedBytes += bytes.length;
    for (final byte in bytes) {
      if (complete) {
        throw const TransportFailure('extra_input');
      }
      if (byte != expected[matchedBytes]) {
        throw const TransportFailure('invalid_probe');
      }
      matchedBytes++;
    }
  }
}

abstract interface class TransportBridge {
  Future<void> status(Map<String, Object?> facts);
  Future<void> ready();
  Future<void> cancel();
}

class TransportMethodChannel implements TransportBridge {
  const TransportMethodChannel();
  static const _channel = MethodChannel('lineup/e6');
  Future<void> _call(
    String method,
    String key, [
    Map<String, Object?>? arguments,
  ]) async {
    final value = await _channel.invokeMethod<Object?>(method, arguments);
    if (value is! Map || value.length != 1 || value[key] != true) {
      throw const TransportFailure('io_failure');
    }
  }

  @override
  Future<void> status(Map<String, Object?> facts) =>
      _call('transportStatus', 'stored', facts);
  @override
  Future<void> ready() => _call('markInputReady', 'ready');
  @override
  Future<void> cancel() => _call('cancel', 'cancelled');
}

/// One process, one peer, fixed public input/output. The native file is the evidence
/// channel when the transport under test cannot carry a reply.
Future<Map<String, Object?>> runTransportFixture(
  TransportMode mode, {
  required TransportBridge bridge,
  required void Function(VoidCallback firstFrame) show,
  Future<ServerSocket> Function()? bind,
  Duration startupTimeout = const Duration(seconds: 30),
  Duration exchangeTimeout = const Duration(seconds: 10),
  Duration caseTimeout = const Duration(seconds: 60),
  Duration teardownTimeout = const Duration(seconds: 15),
}) async {
  if (!kDebugMode) {
    throw const TransportFailure('cancelled');
  }
  final binding = WidgetsBinding.instance;
  final resumed = Completer<void>(), frame = Completer<void>();
  final failed = Completer<TransportFailure>();
  TransportFailure? signalled;
  void fail(String code) {
    if (!failed.isCompleted) {
      signalled = TransportFailure(code);
      failed.complete(signalled!);
    }
  }

  final lifecycle = AppLifecycleListener(
    onStateChange: (state) {
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached) {
        fail('cancelled');
      }
      if (state == AppLifecycleState.resumed && !resumed.isCompleted) {
        resumed.complete();
      }
    },
  );
  if (binding.lifecycleState == AppLifecycleState.resumed) {
    resumed.complete();
  }
  final startupTimer = Timer(startupTimeout, () => fail('startup_deadline'));
  final caseTimer = Timer(caseTimeout, () => fail('exchange_deadline'));
  Timer? exchangeTimer;
  Future<T> race<T>(Future<T> work) =>
      Future.any<T>([work, failed.future.then<T>((error) => throw error)]);
  void guard() {
    if (signalled != null) {
      throw signalled!;
    }
    if (binding.lifecycleState != AppLifecycleState.resumed) {
      throw const TransportFailure('cancelled');
    }
  }

  final input = ProbeInput(mode);
  var phase = 'starting';
  String? failureCode;
  var responseAttempted = false, closing = false, bindingAbandoned = false;
  var readyPublished = false;
  var flushedBytes = 0;
  ServerSocket? server;
  Socket? peer;
  StreamSubscription<Socket>? acceptor;
  StreamSubscription<Uint8List>? reader;
  final accepted = Completer<Socket>(), inputEnded = Completer<void>();
  final framed = Completer<void>();
  Map<String, Object?> facts() => {
    'mode': mode.name,
    'phase': phase,
    'receivedBytes': input.receivedBytes,
    'responseAttempted': responseAttempted,
    'flushedBytes': flushedBytes,
    'failureCode': failureCode,
  };
  Future<void> status(String value) async {
    phase = value;
    await race(bridge.status(facts()).timeout(const Duration(seconds: 10)));
  }

  try {
    await status('starting');
    final opening =
        bind?.call() ?? ServerSocket.bind(InternetAddress.loopbackIPv4, 18445);
    unawaited(
      opening.then((socket) async {
        if (bindingAbandoned) {
          await socket.close();
        }
      }, onError: (Object _) {}),
    );
    final listener = await race(opening.timeout(const Duration(seconds: 10)));
    server = listener;
    show(() {
      if (!frame.isCompleted) {
        frame.complete();
      }
    });
    await status('waiting_resumed');
    await race(Future.wait([resumed.future, frame.future]));
    guard();
    acceptor = listener.listen(
      (socket) {
        if (accepted.isCompleted || closing || failed.isCompleted) {
          socket.destroy();
          return;
        }
        peer = socket;
        exchangeTimer = Timer(exchangeTimeout, () => fail('exchange_deadline'));
        accepted.complete(socket);
      },
      onError: (Object _) {
        fail('io_failure');
      },
    );
    await status('listening');
    guard();
    await race(bridge.ready().timeout(const Duration(seconds: 10)));
    guard();
    readyPublished = true;
    startupTimer.cancel();
    // Also bound an absent host after readiness, without reconnecting or rebinding.
    peer = await race(
      accepted.future.timeout(
        exchangeTimeout,
        onTimeout: () => throw const TransportFailure('exchange_deadline'),
      ),
    );
    await status('peer_accepted');
    await acceptor.cancel();
    acceptor = null;
    await listener.close();
    server = null;
    reader = peer!.listen(
      (bytes) {
        try {
          input.add(bytes);
          if (mode == TransportMode.line &&
              input.complete &&
              !framed.isCompleted) {
            framed.complete();
          }
        } on TransportFailure catch (error) {
          fail(error.code);
        }
      },
      onError: (Object error) {
        fail(error is SocketException ? 'peer_closed' : 'io_failure');
      },
      onDone: () {
        if (!inputEnded.isCompleted) {
          inputEnded.complete();
        }
        if (mode == TransportMode.line && !closing) {
          fail('peer_closed');
        }
      },
    );
    if (mode == TransportMode.eof) {
      await race(inputEnded.future);
      await status('input_eof');
      if (!input.complete) {
        phase = 'input_incomplete';
      } else {
        await status('input_complete');
      }
    } else {
      await race(framed.future);
      await status('input_complete');
    }
    if (input.complete) {
      guard();
      final reply = transportReply.codeUnits;
      if (reply.length > transportOutputCap) {
        throw const TransportFailure('output_cap');
      }
      responseAttempted = true;
      peer!.add(reply);
      await status('reply_attempt');
      await race(peer!.flush());
      flushedBytes = reply.length;
      await status('reply_flushed');
      guard();
      closing = true;
      await race(peer!.close());
      phase = 'closed';
    }
  } on TransportFailure catch (error) {
    failureCode = error.code;
    phase = error.code == 'cancelled'
        ? 'cancelled'
        : mode == TransportMode.eof &&
              input.complete &&
              responseAttempted &&
              error.code == 'peer_closed'
        ? 'closed'
        : 'failed';
  } on SocketException {
    failureCode = peer == null ? 'io_failure' : 'peer_closed';
    phase = mode == TransportMode.eof && input.complete && responseAttempted
        ? 'closed'
        : 'failed';
  } on TimeoutException {
    failureCode = readyPublished ? 'exchange_deadline' : 'startup_deadline';
    phase = 'failed';
  } catch (_) {
    failureCode = 'io_failure';
    phase = 'failed';
  } finally {
    bindingAbandoned = true;
    closing = true;
    startupTimer.cancel();
    caseTimer.cancel();
    exchangeTimer?.cancel();
    final cleanup = Stopwatch()..start();
    Future<void> finish(Future<void> Function() work) async {
      final remaining = teardownTimeout - cleanup.elapsed;
      if (remaining <= Duration.zero) {
        throw const TransportFailure('io_failure');
      }
      await work().timeout(remaining);
    }

    try {
      peer?.destroy();
      await finish(() async {
        await reader?.cancel();
        await acceptor?.cancel();
        await server?.close();
      });
    } catch (_) {
      phase = 'failed';
      failureCode ??= 'io_failure';
    }
    // The final public status is written before cancel freezes it/removes readiness.
    try {
      await finish(() => bridge.status(facts()));
    } catch (_) {
      phase = 'failed';
      failureCode ??= 'io_failure';
    }
    try {
      await finish(bridge.cancel);
    } catch (_) {
      phase = 'failed';
      failureCode ??= 'io_failure';
    }
    lifecycle.dispose();
  }
  return facts();
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final mode = transportMode(args);
  if (mode == null) {
    return;
  }
  await runTransportFixture(
    mode,
    bridge: const TransportMethodChannel(),
    show: (firstFrame) {
      WidgetsBinding.instance.addPostFrameCallback((_) => firstFrame());
      runApp(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: Text('Public transport diagnostic')),
          ),
        ),
      );
    },
  );
}
