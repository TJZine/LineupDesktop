import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lineup_desktop/plex/plex_transcode.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

void main() {
  test(
    'session stop deadline aborts pending transport and never throws',
    () async {
      final transport = _PendingSessionTransport();
      final failures = <String>[];
      final client = PlexClient(
        clientIdentifier: 'synthetic',
        httpClient: transport,
        requestTimeout: const Duration(seconds: 30),
        onTranscodeStopFailure: failures.add,
      );
      addTearDown(client.close);
      final stopped = client.stopTranscodeSession(
        Uri.parse('https://synthetic.invalid'),
        '00000000-0000-4000-8000-000000000001',
        'synthetic-token',
      );
      await stopped.timeout(const Duration(seconds: 3));
      expect(transport.calls, 1);
      expect(transport.request!.url.path, '/video/:/transcode/universal/stop');
      expect(transport.request!.followRedirects, isFalse);
      expect(
        transport.request!.url.toString(),
        isNot(contains('synthetic-token')),
      );
      expect(transport.request!.headers['X-Plex-Token'], 'synthetic-token');
      await transport.aborted.future.timeout(const Duration(seconds: 1));
      expect(failures, ['network-timeout']);
    },
  );

  test(
    'streamed master size limit cancels before buffering unbounded body',
    () async {
      var cancelled = false;
      final stream = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      final transport = _StreamingMasterTransport(stream.stream);
      final client = PlexClient(
        clientIdentifier: 'synthetic',
        httpClient: transport,
      );
      addTearDown(client.close);
      final result = client.startTranscodeSession(
        Uri.parse('https://synthetic.invalid'),
        PlexSessionRequest(
          ratingKey: '42',
          sessionId: '00000000-0000-4000-8000-000000000001',
          profile: buildProfile(MediaCapabilities.desktop, desktop: true),
        ),
        'synthetic-token',
      );
      final assertion = expectLater(result, _plexError('session-invalid'));
      stream.add(List.filled(maximumPlexMasterBytes, 32));
      stream.add([32]);
      await assertion;
      expect(cancelled, isTrue);
      expect(transport.calls, 1);
      await stream.close();
    },
  );

  for (final cancelScan in [false, true]) {
    test(
      'IOClient closes a connection awaiting headers on ${cancelScan ? 'scan cancellation' : 'deadline'}',
      () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final received = Completer<void>();
        final disconnected = Completer<void>();
        final sockets = <Socket>[];
        final connections = server.listen((socket) {
          sockets.add(socket);
          socket.listen(
            (_) {
              if (!received.isCompleted) received.complete();
            },
            onDone: () {
              if (!disconnected.isCompleted) disconnected.complete();
            },
          );
        });
        addTearDown(() async {
          for (final socket in sockets) {
            socket.destroy();
          }
          await connections.cancel();
          await server.close();
        });
        final cancelled = Completer<void>();
        final client = PlexClient(
          clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
          requestTimeout: cancelScan
              ? const Duration(seconds: 10)
              : const Duration(milliseconds: 250),
        );
        addTearDown(client.close);
        final result = client.libraryItems(
          Uri.parse('http://127.0.0.1:${server.port}'),
          'test-token',
          'movies',
          PlexLibraryType.movie,
          isCurrent: () => !cancelled.isCompleted,
          onProgress: (_) {},
          cancelled: cancelled.future,
        );
        final assertion = expectLater(
          result,
          _plexError(cancelScan ? 'cancelled' : 'network-timeout'),
        );
        await received.future.timeout(const Duration(seconds: 2));
        if (cancelScan) cancelled.complete();
        await assertion;
        await disconnected.future.timeout(const Duration(seconds: 2));
      },
    );
  }

  test(
    'normalizes invalid credential header failures without leaking it',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      final connections = server.listen((socket) {
        sockets.add(socket);
        socket.listen((_) {}, onDone: () {});
      });
      addTearDown(() async {
        for (final socket in sockets) {
          socket.destroy();
        }
        await connections.cancel();
        await server.close();
      });
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      );
      addTearDown(client.close);

      final error = await getPlexError(
        client.libraries(
          Uri.parse('http://127.0.0.1:${server.port}'),
          'SECRETHEAD\r\nSECRETTAIL',
        ),
      );
      expect(error, isA<PlexException>());
      final plexError = error as PlexException;
      expect(plexError.code, 'auth-invalid');
      expect(plexError.message, isNot(contains('SECRETHEAD')));
      expect(plexError.message, isNot(contains('SECRETTAIL')));
      expect(plexError.toString(), isNot(contains('SECRETHEAD')));
      expect(plexError.toString(), isNot(contains('SECRETTAIL')));
      expect(sockets, isEmpty);
    },
  );
}

Future<Object?> getPlexError(Future<Object?> operation) async {
  try {
    await operation;
    fail('Expected a Plex error.');
  } catch (error) {
    return error;
  }
}

Matcher _plexError(String code) => throwsA(
  isA<PlexException>().having((exception) => exception.code, 'code', code),
);

class _PendingSessionTransport extends http.BaseClient {
  int calls = 0;
  http.BaseRequest? request;
  final aborted = Completer<void>();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    expect(++calls, 1, reason: 'Unexpected session request');
    this.request = request;
    if (request is! http.AbortableRequest) fail('Expected abortable request');
    unawaited(
      request.abortTrigger!.then((_) {
        aborted.complete();
      }),
    );
    return Completer<http.StreamedResponse>().future;
  }
}

class _StreamingMasterTransport extends http.BaseClient {
  _StreamingMasterTransport(this.stream);
  final Stream<List<int>> stream;
  int calls = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    expect(++calls, 1, reason: 'Unexpected session request');
    expect(request.url.path, '/video/:/transcode/universal/start.m3u8');
    return http.StreamedResponse(stream, 200);
  }
}
