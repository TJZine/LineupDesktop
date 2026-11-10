import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lineup_desktop/plex/plex_transcode.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/plex/plex_scan_budget.dart';

void main() {
  test(
    'aggregate bytes stop and drain every active response before completion',
    () async {
      final streams = <StreamController<List<int>>>[];
      final drained = Completer<void>();
      var cancellations = 0;
      final started = Completer<void>();
      final client = PlexClient(
        clientIdentifier: 'synthetic',
        scanLimits: const PlexScanLimits(receivedBytes: 10),
        httpClient: _ScanStreamTransport((request) async {
          final stream = StreamController<List<int>>(
            onCancel: () async {
              cancellations++;
              await drained.future;
            },
          );
          streams.add(stream);
          if (streams.length == 2) started.complete();
          return http.StreamedResponse(stream.stream, 200);
        }),
      );
      addTearDown(client.close);
      var finished = false;
      final attempt = client
          .runScan(
            (_) => Future.wait([
              for (final id in ['a', 'b'])
                client.libraryItems(
                  Uri.parse('https://synthetic.invalid'),
                  'token',
                  id,
                  PlexLibraryType.movie,
                  isCurrent: () => true,
                  onProgress: (_) {},
                ),
            ]),
          )
          .whenComplete(() => finished = true);
      final assertion = expectLater(
        attempt,
        throwsA(
          isA<PlexScanLimitException>().having(
            (e) => e.limit,
            'limit',
            'received-bytes',
          ),
        ),
      );
      await started.future;
      // Individually valid chunks exceed only the aggregate ceiling.
      streams[0].add(List.filled(6, 32));
      streams[1].add(List.filled(6, 32));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(cancellations, 2);
      expect(finished, isFalse);
      drained.complete();
      await assertion;
      for (final stream in streams) {
        await stream.close();
      }
    },
  );

  test(
    'one pool bounds headers and bodies across independent scan calls',
    () async {
      final release = Completer<void>();
      final full = Completer<void>();
      var active = 0;
      var peak = 0;
      var requests = 0;
      final client = PlexClient(
        clientIdentifier: 'synthetic',
        scanLimits: const PlexScanLimits(concurrentRequests: 2),
        httpClient: _ScanStreamTransport((request) async {
          active++;
          requests++;
          if (active > peak) peak = active;
          if (active == 2 && !full.isCompleted) full.complete();
          final stream = StreamController<List<int>>(onCancel: () => active--);
          unawaited(
            release.future.then((_) async {
              stream.add(
                utf8.encode('{"MediaContainer":{"Metadata":[],"size":0}}'),
              );
              await stream.close();
            }),
          );
          return http.StreamedResponse(stream.stream, 200);
        }),
      );
      addTearDown(client.close);
      final attempt = client.runScan(
        (_) => Future.wait([
          for (var i = 0; i < 9; i++)
            client.libraryItems(
              Uri.parse('https://synthetic.invalid'),
              'token',
              '$i',
              PlexLibraryType.movie,
              isCurrent: () => true,
              onProgress: (_) {},
            ),
        ]),
      );
      await full.future;
      expect(requests, 2);
      release.complete();
      await attempt;
      expect(peak, 2);
      expect(active, 0);
      expect(requests, 9);
    },
  );

  test(
    'attempt elapsed limit also bounds a transport ignoring abortion',
    () async {
      final client = PlexClient(
        clientIdentifier: 'synthetic',
        scanLimits: const PlexScanLimits(elapsed: Duration(milliseconds: 50)),
        requestTimeout: const Duration(seconds: 10),
        httpClient: _ScanStreamTransport(
          (_) => Completer<http.StreamedResponse>().future,
        ),
      );
      addTearDown(client.close);
      await expectLater(
        client
            .playlists(
              Uri.parse('https://synthetic.invalid'),
              'token',
              isCurrent: () => true,
            )
            .timeout(const Duration(seconds: 1)),
        throwsA(
          isA<PlexScanLimitException>().having(
            (e) => e.limit,
            'limit',
            'elapsed',
          ),
        ),
      );
    },
  );

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

  test('maps corrupt gzip response bodies to parse errors', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <String>[];
    final connections = server.listen((request) {
      requests.add(request.uri.path);
      unawaited(_sendCorruptGzip(request.response));
    });
    addTearDown(() async {
      await connections.cancel();
      await server.close();
    });
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
    );
    addTearDown(client.close);

    final error = await getPlexError(
      client.libraryItems(
        Uri.parse('http://127.0.0.1:${server.port}'),
        'synthetic-token',
        'movies',
        PlexLibraryType.movie,
        isCurrent: () => true,
        onProgress: (_) {},
      ),
    );

    expect(requests, ['/library/sections/movies/all']);
    expect(error, isA<PlexException>());
    final plexError = error as PlexException;
    expect(plexError.code, 'parse-error');
    expect(plexError.code, isNot('auth-invalid'));
  });

  test('a corrupt playlist body fails only that playlist', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <String>[];
    final connections = server.listen((request) {
      requests.add(request.uri.path);
      unawaited(_sendPlaylistResponse(request));
    });
    addTearDown(() async {
      await connections.cancel();
      await server.close();
    });
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
    );
    addTearDown(client.close);

    final catalog = await client.playlists(
      Uri.parse('http://127.0.0.1:${server.port}'),
      'synthetic-token',
      isCurrent: () => true,
    );

    expect(
      requests,
      containsAllInOrder([
        '/playlists/all',
        '/playlists/corrupt/items',
        '/playlists/valid/items',
      ]),
    );
    expect(catalog.failedIds, {'corrupt'});
    expect(catalog.playlists.map((playlist) => playlist.id), ['valid']);
    expect(catalog.playlists.single.items.single.id, 'valid-item');
  });

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
      // Linux may accept the TCP connection before dart:io rejects the
      // invalid header value. Any accepted sockets are destroyed by teardown.
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

Future<void> _sendCorruptGzip(HttpResponse response) async {
  response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
  response.add(_corruptGzipBytes());
  await response.close();
}

Future<void> _sendPlaylistResponse(HttpRequest request) async {
  if (request.uri.path == '/playlists/corrupt/items') {
    await _sendCorruptGzip(request.response);
    return;
  }
  final body = request.uri.path == '/playlists/all'
      ? {
          'MediaContainer': {
            'totalSize': 2,
            'Metadata': [
              {'ratingKey': 'corrupt', 'title': 'Corrupt'},
              {'ratingKey': 'valid', 'title': 'Valid'},
            ],
          },
        }
      : {
          'MediaContainer': {
            'totalSize': 1,
            'Metadata': [
              {
                'ratingKey': 'valid-item',
                'key': '/library/metadata/valid-item',
                'title': 'Valid item',
                'type': 'movie',
                'duration': 1000,
                'Media': [
                  {
                    'Part': [
                      {'key': '/library/parts/valid-item'},
                    ],
                  },
                ],
              },
            ],
          },
        };
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}

List<int> _corruptGzipBytes() {
  final bytes = gzip.encode(utf8.encode('{"MediaContainer":{}}'));
  bytes[bytes.length - 1] ^= 0xff;
  return bytes;
}

class _ScanStreamTransport extends http.BaseClient {
  _ScanStreamTransport(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}
