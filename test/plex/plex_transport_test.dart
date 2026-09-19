import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

void main() {
  test('transport timeouts surface a stable Plex error', () async {
    final response = Completer<http.Response>();
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      requestTimeout: const Duration(milliseconds: 5),
      httpClient: MockClient((_) => response.future),
    );
    await expectLater(
      client.createPin(),
      throwsA(
        isA<PlexException>().having(
          (exception) => exception.code,
          'code',
          'network-timeout',
        ),
      ),
    );
  });

  test(
    'header deadline triggers request abortion and consumes a late response',
    () async {
      final aborted = Completer<void>();
      final lateBodyCancelled = Completer<void>();
      final pending = Completer<http.StreamedResponse>();
      final lateBody = StreamController<List<int>>(
        onCancel: lateBodyCancelled.complete,
      );
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        requestTimeout: const Duration(milliseconds: 5),
        httpClient: MockClient.streaming((request, _) {
          expect(request, isA<http.AbortableRequest>());
          (request as http.AbortableRequest).abortTrigger!.then((_) {
            aborted.complete();
          });
          return pending.future;
        }),
      );
      addTearDown(client.close);
      await expectLater(client.createPin(), _plexError('network-timeout'));
      await aborted.future.timeout(const Duration(seconds: 1));
      pending.complete(http.StreamedResponse(lateBody.stream, 201));
      await lateBodyCancelled.future.timeout(const Duration(seconds: 1));
      await lateBody.close();
    },
  );

  for (final milliseconds in [9, 10, 11]) {
    testWidgets(
      'rejected headers arriving at ${milliseconds}ms around a 10ms deadline complete once',
      (tester) async {
        final pending = Completer<http.StreamedResponse>();
        var aborts = 0;
        var bodyCancelled = 0;
        final body = StreamController<List<int>>(
          onCancel: () {
            bodyCancelled++;
          },
        );
        final client = PlexClient(
          clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
          requestTimeout: const Duration(milliseconds: 10),
          httpClient: MockClient.streaming((request, _) {
            (request as http.AbortableRequest).abortTrigger!.then((_) {
              aborts++;
            });
            return pending.future;
          }),
        );
        var completions = 0;
        Object? failure;
        client.createPin().then(
          (_) {
            completions++;
          },
          onError: (Object error) {
            failure = error;
            completions++;
          },
        );
        await tester.pump(Duration(milliseconds: milliseconds));
        // A rejected response isolates the header deadline from body timing,
        // whose remaining budget uses a real Stopwatch rather than fake time.
        pending.complete(http.StreamedResponse(body.stream, 401));
        unawaited(body.close());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        expect(completions, 1);
        expect(bodyCancelled, 1);
        expect(
          failure,
          isA<PlexException>().having(
            (error) => error.code,
            'code',
            milliseconds < 10 ? 'auth-invalid' : 'network-timeout',
          ),
        );
        expect(aborts, milliseconds < 10 ? 0 : 1);
        client.close();
      },
    );
  }

  for (final failure in <Object>[
    const SocketException('opaque socket detail'),
    http.ClientException('opaque client detail'),
  ]) {
    test('${failure.runtimeType} maps to a finite transport code', () async {
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((_) async => throw failure),
      );
      await expectLater(
        client.createPin(),
        throwsA(
          isA<PlexException>()
              .having(
                (exception) => exception.code,
                'code',
                'network-unavailable',
              )
              .having(
                (exception) => exception.message,
                'message',
                isNot(contains('opaque')),
              ),
        ),
      );
    });
  }

  test('PIN requests send stable identity without a credential', () async {
    late http.Request request;
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((value) async {
        request = value;
        return http.Response(
          jsonEncode({
            'id': 5,
            'code': 'ABCD',
            'expiresAt': '2026-01-01T01:00:00Z',
          }),
          201,
        );
      }),
    );
    final pin = await client.createPin();
    expect(pin.code, 'ABCD');
    expect(
      request.headers['X-Plex-Client-Identifier'],
      'lineup-desktop-test-abcdefghijklmnopqrst',
    );
    expect(request.headers, isNot(contains('X-Plex-Token')));
  });

  test(
    'control requests reject redirects without forwarding headers',
    () async {
      late http.BaseRequest request;
      final canceled = Completer<void>();
      final stream = StreamController<List<int>>(onCancel: canceled.complete);
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient.streaming((value, _) async {
          request = value;
          return http.StreamedResponse(
            stream.stream,
            302,
            headers: const {'location': 'https://attacker.invalid/collect'},
          );
        }),
      );

      await expectLater(
        client.account('private-token'),
        throwsA(
          isA<PlexException>().having(
            (exception) => exception.code,
            'code',
            'server-unreachable',
          ),
        ),
      );
      await canceled.future.timeout(const Duration(seconds: 1));
      expect(request.followRedirects, isFalse);
    },
  );

  test('control requests reject declared oversized bodies', () async {
    final canceled = Completer<void>();
    final stream = StreamController<List<int>>(onCancel: canceled.complete);
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          stream.stream,
          200,
          contentLength: PlexClient.maximumControlResponseBytes + 1,
        ),
      ),
    );

    await expectLater(
      client.createPin(),
      throwsA(
        isA<PlexException>().having(
          (exception) => exception.code,
          'code',
          'response-too-large',
        ),
      ),
    );
    await canceled.future.timeout(const Duration(seconds: 1));
  });

  test('control requests reject actual streamed overflow', () async {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream.fromIterable([
            Uint8List(PlexClient.maximumControlResponseBytes),
            Uint8List(1),
          ]),
          200,
        ),
      ),
    );

    await expectLater(
      client.createPin(),
      throwsA(
        isA<PlexException>().having(
          (exception) => exception.code,
          'code',
          'response-too-large',
        ),
      ),
    );
  });

  test('control response deadline includes body streaming', () async {
    final canceled = Completer<void>();
    final aborted = Completer<void>();
    final stream = StreamController<List<int>>(onCancel: canceled.complete);
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      requestTimeout: const Duration(milliseconds: 5),
      httpClient: MockClient.streaming((request, _) async {
        (request as http.AbortableRequest).abortTrigger!.then(
          (_) => aborted.complete(),
        );
        return http.StreamedResponse(stream.stream, 200);
      }),
    );

    await expectLater(
      client.createPin(),
      throwsA(
        isA<PlexException>().having(
          (exception) => exception.code,
          'code',
          'network-timeout',
        ),
      ),
    );
    await canceled.future.timeout(const Duration(seconds: 1));
    await aborted.future.timeout(const Duration(seconds: 1));
  });

  test('cancel PIN propagates a normalized HTTP failure', () async {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((_) async => http.Response('', 503)),
    );

    await expectLater(
      client.cancelPin(
        PlexPin(id: 7, code: 'ABCD', expiresAt: DateTime.utc(2026)),
      ),
      throwsA(
        isA<PlexException>().having(
          (exception) => exception.code,
          'code',
          'server-unreachable',
        ),
      ),
    );
  });

  test(
    'discovery rejects credential-bearing and unsupported connections',
    () async {
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode([
              {
                'clientIdentifier': 'safe',
                'name': 'Server',
                'provides': 'server',
                'accessToken': 'pms-token-sentinel',
                'connections': [
                  {
                    'uri': 'https://plex.example:32400',
                    'local': true,
                    'relay': false,
                  },
                  {
                    'uri': 'https://user:pass@bad.example',
                    'local': true,
                    'relay': false,
                  },
                  {'uri': 'ftp://bad.example', 'local': true, 'relay': false},
                  {
                    'uri': 'http://plaintext.example',
                    'local': true,
                    'relay': false,
                  },
                ],
              },
            ]),
            200,
          ),
        ),
      );
      final servers = await client.discoverServers('private-token');
      expect(servers.single.server.connections, hasLength(1));
      expect(
        servers.single.server.connections.single.uri.toString(),
        'https://plex.example:32400',
      );
      expect(servers.single.token, 'pms-token-sentinel');
      expect(servers.single.toString(), isNot(contains('pms-token-sentinel')));
    },
  );

  test('discovery omits resources without a non-empty PMS token', () async {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode([
            for (final token in [null, '', '   '])
              {
                'clientIdentifier': 'server-${token ?? 'missing'}',
                'name': 'Server',
                'provides': 'server',
                'accessToken': ?token,
                'connections': [
                  {
                    'uri': 'https://plex.example:32400',
                    'local': true,
                    'relay': false,
                  },
                ],
              },
          ]),
          200,
        ),
      ),
    );

    expect(await client.discoverServers('cloud-token'), isEmpty);
  });

  test(
    'connection probing binds the identity to the selected server',
    () async {
      final probed = <String>[];
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          probed.add(request.url.host);
          final id = request.url.host == 'wrong.example' ? 'other' : 'expected';
          return http.Response(
            '<MediaContainer machineIdentifier="$id"/>',
            200,
          );
        }),
      );
      final selected = await client.selectConnection(
        PlexServer(
          id: 'expected',
          name: 'Server',
          connections: [
            PlexConnection(
              uri: Uri.parse('https://wrong.example:32400'),
              local: true,
              relay: false,
            ),
            PlexConnection(
              uri: Uri.parse('https://right.example:32400'),
              local: true,
              relay: false,
            ),
          ],
        ),
        'secret',
      );
      expect(selected.uri.host, 'right.example');
      expect(selected.latency, isNotNull);
      expect(probed, containsAll(['wrong.example', 'right.example']));
    },
  );

  test('connection probing ignores a timed-out candidate', () async {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        if (request.url.host == 'slow.example') throw TimeoutException('slow');
        return http.Response(
          '<MediaContainer machineIdentifier="expected"/>',
          200,
        );
      }),
    );

    final selected = await client.selectConnection(
      PlexServer(
        id: 'expected',
        name: 'Server',
        connections: [
          PlexConnection(
            uri: Uri.parse('https://slow.example:32400'),
            local: true,
            relay: false,
          ),
          PlexConnection(
            uri: Uri.parse('https://ready.example:32400'),
            local: true,
            relay: false,
          ),
        ],
      ),
      'secret',
    );

    expect(selected.uri.host, 'ready.example');
  });

  for (final (status, code) in [
    (401, 'auth-required'),
    (403, 'access-denied'),
  ]) {
    test('connection probing preserves HTTP $status failures', () async {
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((_) async => http.Response('', status)),
      );

      await expectLater(
        client.selectConnection(
          PlexServer(
            id: 'expected',
            name: 'Server',
            connections: [
              PlexConnection(
                uri: Uri.parse('https://server.example:32400'),
                local: true,
                relay: false,
              ),
            ],
          ),
          'secret',
        ),
        throwsA(
          isA<PlexException>().having(
            (exception) => exception.code,
            'code',
            code,
          ),
        ),
      );
    });
  }

  test(
    'authorization failure does not hide a reachable same-tier endpoint',
    () async {
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          if (request.url.host == 'unauthorized.example') {
            return http.Response('', 401);
          }
          return http.Response(
            '<MediaContainer machineIdentifier="expected"/>',
            200,
          );
        }),
      );

      final selected = await client.selectConnection(
        PlexServer(
          id: 'expected',
          name: 'Server',
          connections: [
            PlexConnection(
              uri: Uri.parse('https://unauthorized.example:32400'),
              local: true,
              relay: false,
            ),
            PlexConnection(
              uri: Uri.parse('https://reachable.example:32400'),
              local: true,
              relay: false,
            ),
          ],
        ),
        'secret',
      );

      expect(selected.uri.host, 'reachable.example');
    },
  );

  test(
    'authorization failure does not prevent a reachable fallback tier',
    () async {
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          if (request.url.host == 'local.example') {
            return http.Response('', 403);
          }
          return http.Response(
            '<MediaContainer machineIdentifier="expected"/>',
            200,
          );
        }),
      );

      final selected = await client.selectConnection(
        PlexServer(
          id: 'expected',
          name: 'Server',
          connections: [
            PlexConnection(
              uri: Uri.parse('https://local.example:32400'),
              local: true,
              relay: false,
            ),
            PlexConnection(
              uri: Uri.parse('https://relay.example:32400'),
              local: false,
              relay: true,
            ),
          ],
        ),
        'secret',
      );

      expect(selected.uri.host, 'relay.example');
    },
  );

  test(
    'connection probing is bounded to eight advertised candidates',
    () async {
      var probes = 0;
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((_) async {
          probes++;
          return http.Response(
            '<MediaContainer machineIdentifier="other"/>',
            200,
          );
        }),
      );
      await expectLater(
        client.selectConnection(
          PlexServer(
            id: 'expected',
            name: 'Server',
            connections: List.generate(
              20,
              (index) => PlexConnection(
                uri: Uri.parse('https://server-$index.example:32400'),
                local: true,
                relay: false,
              ),
            ),
          ),
          'secret',
        ),
        throwsA(isA<PlexException>()),
      );
      expect(probes, 8);
    },
  );

  test('connection priority is applied before the probe bound', () async {
    final probed = <String>[];
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        probed.add(request.url.host);
        return http.Response(
          '<MediaContainer machineIdentifier="expected"/>',
          200,
        );
      }),
    );
    final selected = await client.selectConnection(
      PlexServer(
        id: 'expected',
        name: 'Server',
        connections: [
          for (var index = 0; index < 8; index++)
            PlexConnection(
              uri: Uri.parse('https://relay-$index.example:32400'),
              local: false,
              relay: true,
            ),
          PlexConnection(
            uri: Uri.parse('https://local.example:32400'),
            local: true,
            relay: false,
          ),
        ],
      ),
      'secret',
    );

    expect(selected.uri.host, 'local.example');
    expect(probed, contains('local.example'));
    expect(probed.length, lessThanOrEqualTo(8));
  });

  test('the probe bound reserves a reachable fallback tier', () async {
    final probed = <String>[];
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        probed.add(request.url.host);
        final id = request.url.host == 'relay.example' ? 'expected' : 'other';
        return http.Response('<MediaContainer machineIdentifier="$id"/>', 200);
      }),
    );
    final selected = await client.selectConnection(
      PlexServer(
        id: 'expected',
        name: 'Server',
        connections: [
          for (var index = 0; index < 8; index++)
            PlexConnection(
              uri: Uri.parse('https://local-$index.example:32400'),
              local: true,
              relay: false,
            ),
          PlexConnection(
            uri: Uri.parse('https://relay.example:32400'),
            local: false,
            relay: true,
          ),
        ],
      ),
      'secret',
    );

    expect(selected.uri.host, 'relay.example');
    expect(probed, contains('relay.example'));
    expect(probed.length, 8);
  });

  test('an empty ordered part list is unsupported media', () {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
    );
    expect(
      () => client.playbackDescriptor(
        server: Uri.parse('https://plex.example:32400'),
        item: PlexMediaItem(
          id: 'empty',
          title: 'Empty',
          type: 'movie',
          duration: Duration.zero,
        ),
      ),
      throwsA(
        isA<PlexException>().having(
          (exception) => exception.code,
          'code',
          'unsupported',
        ),
      ),
    );
  });

  test('direct play retains the selected Plex server origin', () {
    final descriptor = _directPlaybackDescriptor('/library/parts/1/file.mkv');

    expect(
      descriptor.single.uri,
      Uri.parse('https://plex.example:32400/library/parts/1/file.mkv'),
    );
  });

  test('multipart descriptors preserve order and origin', () {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
    );
    final descriptor = client.playbackDescriptor(
      server: Uri.parse('https://plex.example:32400'),
      item: PlexMediaItem(
        id: '1',
        title: 'Movie',
        type: 'movie',
        duration: Duration(minutes: 2),
        parts: [
          PlexMediaPart(
            path: '/library/parts/one.mkv',
            duration: Duration(minutes: 1),
          ),
          PlexMediaPart(path: '/library/parts/two.mkv'),
        ],
        container: 'mkv',
        videoCodec: 'h264',
        audioCodec: 'aac',
        dynamicRange: DynamicRange.sdr,
      ),
    );

    expect(descriptor.map((part) => part.uri), [
      Uri.parse('https://plex.example:32400/library/parts/one.mkv'),
      Uri.parse('https://plex.example:32400/library/parts/two.mkv'),
    ]);
    expect(descriptor.first.duration, const Duration(minutes: 1));
    expect(descriptor.last.duration, isNull);
    expect(
      descriptor.expand((part) => part.uri.queryParameters.keys),
      isNot(contains('X-Plex-Token')),
    );
    expect(
      () => descriptor.add((
        uri: Uri.parse('https://plex.example/new'),
        duration: null,
      )),
      throwsUnsupportedError,
    );
  });

  test('multipart descriptors reject a cross-origin part', () {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
    );
    expect(
      () => client.playbackDescriptor(
        server: Uri.parse('https://plex.example:32400'),
        item: PlexMediaItem(
          id: '1',
          title: 'Movie',
          type: 'movie',
          duration: Duration(minutes: 2),
          parts: [
            PlexMediaPart(path: '/library/parts/one.mkv'),
            PlexMediaPart(path: 'https://attacker.example/two.mkv'),
          ],
          container: 'mkv',
          videoCodec: 'h264',
          audioCodec: 'aac',
          dynamicRange: DynamicRange.sdr,
        ),
      ),
      throwsA(isA<PlexException>()),
    );
  });

  for (final mismatch in {
    'host': 'https://attacker.example/file.mkv',
    'network path': '//attacker.example/file.mkv',
    'scheme': 'http://plex.example:32400/file.mkv',
    'port': 'https://plex.example:32401/file.mkv',
    'userinfo': 'https://user@plex.example:32400/file.mkv',
  }.entries) {
    test('direct play rejects ${mismatch.key} mismatch', () {
      expect(
        () => _directPlaybackDescriptor(mismatch.value),
        throwsA(
          isA<PlexException>().having(
            (exception) => exception.code,
            'code',
            'unsupported',
          ),
        ),
      );
    });
  }

  group('artwork transport', () {
    Matcher plexError(String code) => throwsA(
      isA<PlexException>().having((exception) => exception.code, 'code', code),
    );

    PlexClient client(
      Future<http.StreamedResponse> Function(http.BaseRequest, http.ByteStream)
      handler,
    ) => PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient.streaming(handler),
    );

    test('scopes credentials to the selected server', () async {
      late http.BaseRequest request;
      final plex = client((value, _) async {
        request = value;
        return http.StreamedResponse(Stream.value([1, 2, 3, 4]), 200);
      });

      final bytes = await plex.artwork(
        Uri.parse('https://plex.example:32400'),
        'secret',
        Uri.parse('/library/metadata/1/art'),
        maximumBytes: 4,
      );

      expect(bytes, [1, 2, 3, 4]);
      expect(request.url.host, 'plex.example');
      expect(request.headers['X-Plex-Token'], 'secret');
    });

    for (final mismatch in {
      'host': 'https://attacker.example/art',
      'scheme': 'http://plex.example:32400/art',
      'port': 'https://plex.example:32401/art',
      'userinfo': 'https://user@plex.example:32400/art',
    }.entries) {
      test('rejects ${mismatch.key} mismatch before sending', () async {
        final plex = client((_, _) async => throw StateError('sent request'));

        await expectLater(
          plex.artwork(
            Uri.parse('https://plex.example:32400'),
            'secret',
            Uri.parse(mismatch.value),
          ),
          plexError('artwork-unavailable'),
        );
      });
    }

    test('rejects redirects and cancels the response stream', () async {
      late http.BaseRequest request;
      final canceled = Completer<void>();
      final stream = StreamController<List<int>>(onCancel: canceled.complete);
      final plex = client((value, _) async {
        request = value;
        return http.StreamedResponse(
          stream.stream,
          302,
          headers: {'location': '/other'},
        );
      });

      await expectLater(
        plex.artwork(
          Uri.parse('https://plex.example:32400'),
          'secret',
          Uri.parse('/library/metadata/1/redirect'),
        ),
        plexError('artwork-unavailable'),
      );
      await canceled.future.timeout(const Duration(seconds: 1));

      expect(request.followRedirects, isFalse);
      expect(canceled.isCompleted, isTrue);
    });

    for (final failure in {401: 'auth-invalid', 403: 'access-denied'}.entries) {
      test('preserves ${failure.key} authorization classification', () async {
        final plex = client(
          (_, _) async =>
              http.StreamedResponse(const Stream.empty(), failure.key),
        );

        await expectLater(
          plex.artwork(
            Uri.parse('https://plex.example:32400'),
            'resource-token',
            Uri.parse('/library/metadata/1/art'),
          ),
          plexError(failure.value),
        );
      });
    }

    test('rejects declared-length overflow and cancels the stream', () async {
      final canceled = Completer<void>();
      final stream = StreamController<List<int>>(onCancel: canceled.complete);
      final plex = client(
        (_, _) async =>
            http.StreamedResponse(stream.stream, 200, contentLength: 4),
      );

      await expectLater(
        plex.artwork(
          Uri.parse('https://plex.example:32400'),
          'secret',
          Uri.parse('/library/metadata/1/art'),
          maximumBytes: 3,
        ),
        plexError('artwork-too-large'),
      );
      await canceled.future.timeout(const Duration(seconds: 1));

      expect(canceled.isCompleted, isTrue);
    });

    test('rejects streamed overflow', () async {
      final plex = client(
        (_, _) async => http.StreamedResponse(Stream.value([1, 2, 3, 4]), 200),
      );

      await expectLater(
        plex.artwork(
          Uri.parse('https://plex.example:32400'),
          'secret',
          Uri.parse('/library/metadata/1/art'),
          maximumBytes: 3,
        ),
        plexError('artwork-too-large'),
      );
    });

    test('fetches trusted metadata artwork without Plex credentials', () async {
      late http.BaseRequest request;
      final plex = client((value, _) async {
        request = value;
        return http.StreamedResponse(Stream.value([1, 2, 3, 4]), 200);
      });
      final uri = Uri.parse(
        'https://metadata-static.plex.tv/f/people/avery-vale.jpg',
      );

      final bytes = await plex.metadataArtwork(uri, maximumBytes: 4);

      expect(bytes, [1, 2, 3, 4]);
      expect(request.url, uri);
      expect(request.followRedirects, isFalse);
      expect(request.headers.keys, everyElement(isNot(startsWith('X-Plex-'))));
    });

    test('rejects untrusted metadata artwork before sending', () async {
      final plex = client((_, _) async => throw StateError('sent request'));

      await expectLater(
        plex.metadataArtwork(
          Uri.parse(
            'https://metadata-static.plex.tv.evil.example/f/people/a.jpg',
          ),
        ),
        plexError('artwork-unavailable'),
      );
    });

    test('rejects metadata artwork redirects and cancels the stream', () async {
      late http.BaseRequest request;
      final canceled = Completer<void>();
      final stream = StreamController<List<int>>(onCancel: canceled.complete);
      final plex = client((value, _) async {
        request = value;
        return http.StreamedResponse(
          stream.stream,
          302,
          headers: {'location': 'https://attacker.example/portrait.jpg'},
        );
      });

      await expectLater(
        plex.metadataArtwork(
          Uri.parse('https://metadata-static.plex.tv/f/people/redirect.jpg'),
        ),
        plexError('artwork-unavailable'),
      );
      await canceled.future.timeout(const Duration(seconds: 1));

      expect(request.followRedirects, isFalse);
      expect(canceled.isCompleted, isTrue);
    });

    test('bounds streamed metadata artwork', () async {
      final plex = client(
        (_, _) async => http.StreamedResponse(Stream.value([1, 2, 3, 4]), 200),
      );

      await expectLater(
        plex.metadataArtwork(
          Uri.parse('https://metadata-static.plex.tv/f/people/large.jpg'),
          maximumBytes: 3,
        ),
        plexError('artwork-too-large'),
      );
    });
  });

  test(
    'show libraries load episode rows and playlists load their items',
    () async {
      final requests = <Uri>[];
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          requests.add(request.url);
          if (request.url.path == '/library/sections/7/all') {
            return http.Response(
              jsonEncode({
                'MediaContainer': {
                  'totalSize': 1,
                  'Metadata': [
                    {
                      'ratingKey': 'e1',
                      'key': '/library/metadata/e1',
                      'title': 'Pilot',
                      'type': 'episode',
                      'duration': '1000',
                      'year': '2026',
                    },
                  ],
                },
              }),
              200,
            );
          }
          if (request.url.path == '/playlists/all') {
            return http.Response(
              jsonEncode({
                'MediaContainer': {
                  'totalSize': 1,
                  'Metadata': [
                    {
                      'ratingKey': 'p1',
                      'key': 'https://attacker.example/steal',
                      'title': 'Favorites',
                    },
                  ],
                },
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'totalSize': 1,
                'Metadata': [
                  {
                    'ratingKey': 'm1',
                    'key': '/library/metadata/m1',
                    'title': 'Movie',
                    'type': 'movie',
                    'duration': 1000,
                    'Media': [
                      {
                        'Part': [
                          {'key': '/library/parts/m1'},
                        ],
                      },
                    ],
                  },
                ],
              },
            }),
            200,
          );
        }),
      );
      final episodes = await client.libraryItems(
        Uri.parse('https://plex.example:32400'),
        'secret',
        '7',
        PlexLibraryType.show,
        isCurrent: () => true,
        onProgress: (_) {},
      );
      final playlists = await client.playlists(
        Uri.parse('https://plex.example:32400'),
        'secret',
        isCurrent: () => true,
      );
      expect(episodes.single.type, 'episode');
      expect(episodes.single.duration, const Duration(seconds: 1));
      expect(episodes.single.year, 2026);
      expect(requests.first.queryParameters['type'], '4');
      expect(playlists.playlists.single.title, 'Favorites');
      expect(playlists.playlists.single.items.single.id, 'm1');
      expect(requests.last.host, 'plex.example');
      expect(requests.last.path, '/playlists/p1/items');
      expect(playlists.failedIds, isEmpty);
    },
  );

  test('stale playlist discovery sends no catalog request', () async {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((_) async => fail('No request should be sent')),
    );
    await expectLater(
      client.playlists(
        Uri.parse('https://plex.example'),
        'test-token',
        isCurrent: () => false,
      ),
      _plexError('cancelled'),
    );
  });

  test('playlist cancellation during catalog sends no item requests', () async {
    var current = true;
    var requests = 0;
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((_) async {
        requests++;
        current = false;
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'Metadata': [
                {'ratingKey': 'p1', 'title': 'Playlist'},
              ],
            },
          }),
          200,
        );
      }),
    );
    await expectLater(
      client.playlists(
        Uri.parse('https://plex.example'),
        'test-token',
        isCurrent: () => current,
      ),
      _plexError('cancelled'),
    );
    expect(requests, 1);
  });

  test(
    'cancelled playlist batch launches no later requests while retry completes',
    () async {
      var current = true;
      var scan = 0;
      final firstBatchStarted = Completer<void>();
      final releaseFirstBatch = Completer<void>();
      final itemRequests = <int>[];
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          if (request.url.path == '/playlists/all') {
            scan++;
            return http.Response(
              jsonEncode({
                'MediaContainer': {
                  'totalSize': 8,
                  'Metadata': [
                    for (var i = 0; i < 8; i++)
                      {'ratingKey': 'p$i', 'title': 'Playlist $i'},
                  ],
                },
              }),
              200,
            );
          }
          final requestScan = scan;
          itemRequests.add(requestScan);
          if (requestScan == 1) {
            if (itemRequests.length == 4) firstBatchStarted.complete();
            await releaseFirstBatch.future;
          }
          return http.Response('{"MediaContainer":{"Metadata":[]}}', 200);
        }),
      );
      final abandoned = client.playlists(
        Uri.parse('https://plex.example'),
        'test-token',
        isCurrent: () => current,
      );
      final abandonedAssertion = expectLater(
        abandoned,
        _plexError('cancelled'),
      );
      await firstBatchStarted.future;
      current = false;
      final retry = client.playlists(
        Uri.parse('https://plex.example'),
        'test-token',
        isCurrent: () => true,
      );
      await retry;
      releaseFirstBatch.complete();
      await abandonedAssertion;
      expect(itemRequests.where((scan) => scan == 1), hasLength(4));
      expect(itemRequests.where((scan) => scan == 2), hasLength(8));
    },
  );

  test('playlist catalog loads every page in order', () async {
    Map<String, Object?> catalogPage(int start, List<String> ids, int total) =>
        {
          'MediaContainer': {
            'offset': start,
            'totalSize': total,
            'Metadata': [
              for (final id in ids) {'ratingKey': id, 'title': 'Playlist $id'},
            ],
          },
        };
    Map<String, Object?> itemsPage(List<String> ids, [int? total]) => {
      'MediaContainer': {
        'totalSize': ?total,
        'Metadata': [for (final id in ids) _playablePlaylistItem(id)],
      },
    };
    final catalogStarts = <int>[];
    final catalogSizes = <String?>[];
    final playlistTypes = <String?>[];
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        if (request.url.path == '/playlists/all') {
          final params = request.url.queryParameters;
          catalogStarts.add(int.parse(params['X-Plex-Container-Start']!));
          catalogSizes.add(params['X-Plex-Container-Size']);
          playlistTypes.add(params['playlistType']);
          return switch (catalogStarts.last) {
            0 => http.Response(
              jsonEncode(catalogPage(0, ['p0', 'p1'], 5)),
              200,
            ),
            2 => http.Response(
              jsonEncode(catalogPage(2, ['p2', 'p3'], 5)),
              200,
            ),
            _ => http.Response(jsonEncode(catalogPage(4, ['p4'], 5)), 200),
          };
        }
        final id = request.url.pathSegments[1];
        return http.Response(jsonEncode(itemsPage(['$id-item'], 1)), 200);
      }),
    );
    addTearDown(client.close);

    final catalog = await client.playlists(
      Uri.parse('https://plex.example:32400'),
      'secret',
      isCurrent: () => true,
    );

    expect(catalogStarts, [0, 2, 4]);
    expect(catalogSizes, ['100', '100', '100']);
    expect(playlistTypes, ['video', 'video', 'video']);
    expect(catalog.playlists.map((playlist) => playlist.id), [
      'p0',
      'p1',
      'p2',
      'p3',
      'p4',
    ]);
    expect(catalog.failedIds, isEmpty);
  });

  test(
    'playlist catalog without a total terminates on an empty page',
    () async {
      final catalogStarts = <int>[];
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          if (request.url.path == '/playlists/all') {
            final start = int.parse(
              request.url.queryParameters['X-Plex-Container-Start']!,
            );
            catalogStarts.add(start);
            Map<String, Object?> page(List<String> ids) => {
              'MediaContainer': {
                'Metadata': [
                  for (final id in ids)
                    {'ratingKey': id, 'title': 'Playlist $id'},
                ],
              },
            };
            return switch (start) {
              0 => http.Response(jsonEncode(page(['p0', 'p1'])), 200),
              _ => http.Response(jsonEncode(page(const [])), 200),
            };
          }
          final id = request.url.pathSegments[1];
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'totalSize': 1,
                'Metadata': [_playablePlaylistItem('$id-item')],
              },
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);

      final catalog = await client.playlists(
        Uri.parse('https://plex.example:32400'),
        'secret',
        isCurrent: () => true,
      );

      expect(catalogStarts, [0, 2]);
      expect(catalog.playlists.map((playlist) => playlist.id), ['p0', 'p1']);
      expect(catalog.failedIds, isEmpty);
    },
  );

  test(
    'playlist contents page through a known total preserving order',
    () async {
      Map<String, Object?> page(int start, int count) => {
        'MediaContainer': {
          'offset': start,
          'totalSize': 120,
          'Metadata': [
            for (var index = 0; index < count; index++)
              _playablePlaylistItem('m${start + index}'),
          ],
        },
      };
      final itemStarts = <int>[];
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          if (request.url.path == '/playlists/all') {
            return http.Response(
              jsonEncode({
                'MediaContainer': {
                  'totalSize': 1,
                  'Metadata': [
                    {'ratingKey': 'p1', 'title': 'Playlist'},
                  ],
                },
              }),
              200,
            );
          }
          final start = int.parse(
            request.url.queryParameters['X-Plex-Container-Start']!,
          );
          itemStarts.add(start);
          expect(request.url.queryParameters['X-Plex-Container-Size'], '100');
          return switch (start) {
            0 => http.Response(jsonEncode(page(0, 50)), 200),
            50 => http.Response(jsonEncode(page(50, 50)), 200),
            100 => http.Response(jsonEncode(page(100, 20)), 200),
            _ => http.Response(jsonEncode(page(start, 0)), 200),
          };
        }),
      );
      addTearDown(client.close);

      final catalog = await client.playlists(
        Uri.parse('https://plex.example:32400'),
        'secret',
        isCurrent: () => true,
      );

      expect(itemStarts, [0, 50, 100]);
      expect(catalog.failedIds, isEmpty);
      expect(catalog.playlists.single.items.map((item) => item.id), [
        for (var index = 0; index < 120; index++) 'm$index',
      ]);
    },
  );

  test(
    'playlist pages without a total terminate on a valid empty page',
    () async {
      final itemStarts = <int>[];
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          if (request.url.path == '/playlists/all') {
            return http.Response(
              jsonEncode({
                'MediaContainer': {
                  'totalSize': 1,
                  'Metadata': [
                    {'ratingKey': 'p1', 'title': 'Playlist'},
                  ],
                },
              }),
              200,
            );
          }
          final start = int.parse(
            request.url.queryParameters['X-Plex-Container-Start']!,
          );
          itemStarts.add(start);
          Map<String, Object?> page(List<String> ids) => {
            'MediaContainer': {
              'Metadata': [for (final id in ids) _playablePlaylistItem(id)],
            },
          };
          return switch (start) {
            0 => http.Response(jsonEncode(page(['a', 'b'])), 200),
            2 => http.Response(jsonEncode(page(['c'])), 200),
            _ => http.Response(jsonEncode(page(const [])), 200),
          };
        }),
      );
      addTearDown(client.close);

      final catalog = await client.playlists(
        Uri.parse('https://plex.example:32400'),
        'secret',
        isCurrent: () => true,
      );

      expect(itemStarts, [0, 2, 3]);
      expect(catalog.playlists.single.items.map((item) => item.id), [
        'a',
        'b',
        'c',
      ]);
    },
  );

  test('playlist catalog rejects a mismatched offset', () async {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        final start = int.parse(
          request.url.queryParameters['X-Plex-Container-Start']!,
        );
        final ids = start == 0 ? ['p0', 'p1'] : ['p2', 'p3'];
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'offset': 0,
              'totalSize': 4,
              'Metadata': [
                for (final id in ids)
                  {'ratingKey': id, 'title': 'Playlist $id'},
              ],
            },
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);

    await expectLater(
      client.playlists(
        Uri.parse('https://plex.example:32400'),
        'secret',
        isCurrent: () => true,
      ),
      _plexError('playlist-page-invalid'),
    );
  });

  test(
    'playlist contents reject a mismatched offset as a failed playlist',
    () async {
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          if (request.url.path == '/playlists/all') {
            return http.Response(
              jsonEncode({
                'MediaContainer': {
                  'totalSize': 1,
                  'Metadata': [
                    {'ratingKey': 'p1', 'title': 'Playlist'},
                  ],
                },
              }),
              200,
            );
          }
          final start = int.parse(
            request.url.queryParameters['X-Plex-Container-Start']!,
          );
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'offset': 0,
                'totalSize': 4,
                'Metadata': [
                  for (var index = 0; index < 2; index++)
                    _playablePlaylistItem('m${start + index}'),
                ],
              },
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);

      final catalog = await client.playlists(
        Uri.parse('https://plex.example:32400'),
        'secret',
        isCurrent: () => true,
      );

      expect(catalog.playlists, isEmpty);
      expect(catalog.failedIds, {'p1'});
    },
  );

  test('playlist later-page failure marks the playlist failed without partial success', () async {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        if (request.url.path == '/playlists/all') {
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'totalSize': 1,
                'Metadata': [
                  {'ratingKey': 'p1', 'title': 'Playlist'},
                ],
              },
            }),
            200,
          );
        }
        final start = int.parse(
          request.url.queryParameters['X-Plex-Container-Start']!,
        );
        if (start == 0) {
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'totalSize': 4,
                'Metadata': [
                  _playablePlaylistItem('m0'),
                  _playablePlaylistItem('m1'),
                ],
              },
            }),
            200,
          );
        }
        return http.Response('', 500);
      }),
    );
    addTearDown(client.close);

    final catalog = await client.playlists(
      Uri.parse('https://plex.example:32400'),
      'secret',
      isCurrent: () => true,
    );

    expect(catalog.playlists, isEmpty);
    expect(catalog.failedIds, {'p1'});
  });

  test('playlist catalog failure throws instead of an empty catalog', () async {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((_) async => http.Response('', 500)),
    );
    addTearDown(client.close);

    await expectLater(
      client.playlists(
        Uri.parse('https://plex.example:32400'),
        'secret',
        isCurrent: () => true,
      ),
      _plexError('server-unreachable'),
    );
  });

  test(
    'playlist repeated items across a page boundary are preserved',
    () async {
      final itemStarts = <int>[];
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          if (request.url.path == '/playlists/all') {
            return http.Response(
              jsonEncode({
                'MediaContainer': {
                  'totalSize': 1,
                  'Metadata': [
                    {'ratingKey': 'p1', 'title': 'Playlist'},
                  ],
                },
              }),
              200,
            );
          }
          final start = int.parse(
            request.url.queryParameters['X-Plex-Container-Start']!,
          );
          itemStarts.add(start);
          final ids = start == 0 ? ['m1', 'm2'] : ['m2', 'm3'];
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'offset': start,
                'totalSize': 4,
                'Metadata': [for (final id in ids) _playablePlaylistItem(id)],
              },
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);

      final catalog = await client.playlists(
        Uri.parse('https://plex.example:32400'),
        'secret',
        isCurrent: () => true,
      );

      expect(itemStarts, [0, 2]);
      expect(catalog.failedIds, isEmpty);
      expect(catalog.playlists.single.items.map((item) => item.id), [
        'm1',
        'm2',
        'm2',
        'm3',
      ]);
    },
  );

  test('playlist identical repeated blocks are not a repeated page', () async {
    final itemStarts = <int>[];
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        if (request.url.path == '/playlists/all') {
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'totalSize': 1,
                'Metadata': [
                  {'ratingKey': 'p1', 'title': 'Playlist'},
                ],
              },
            }),
            200,
          );
        }
        final start = int.parse(
          request.url.queryParameters['X-Plex-Container-Start']!,
        );
        itemStarts.add(start);
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'offset': start,
              'totalSize': 6,
              'Metadata': [
                for (final id in ['a', 'b', 'c']) _playablePlaylistItem(id),
              ],
            },
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);

    final catalog = await client.playlists(
      Uri.parse('https://plex.example:32400'),
      'secret',
      isCurrent: () => true,
    );

    expect(itemStarts, [0, 3]);
    expect(catalog.failedIds, isEmpty);
    expect(catalog.playlists.single.items.map((item) => item.id), [
      'a',
      'b',
      'c',
      'a',
      'b',
      'c',
    ]);
  });

  test(
    'playlist repeated media with distinct occurrence ids are preserved',
    () async {
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          if (request.url.path == '/playlists/all') {
            return http.Response(
              jsonEncode({
                'MediaContainer': {
                  'totalSize': 1,
                  'Metadata': [
                    {'ratingKey': 'p1', 'title': 'Playlist'},
                  ],
                },
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'totalSize': 4,
                'Metadata': [
                  {..._playablePlaylistItem('a'), 'playlistItemID': 101},
                  {..._playablePlaylistItem('b'), 'playlistItemID': 102},
                  {..._playablePlaylistItem('b'), 'playlistItemID': 103},
                  {..._playablePlaylistItem('d'), 'playlistItemID': 104},
                ],
              },
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);

      final catalog = await client.playlists(
        Uri.parse('https://plex.example:32400'),
        'secret',
        isCurrent: () => true,
      );

      expect(catalog.failedIds, isEmpty);
      expect(catalog.playlists.single.items.map((item) => item.id), [
        'a',
        'b',
        'b',
        'd',
      ]);
    },
  );

  test(
    'playlist repeated blocks with distinct occurrence ids are preserved',
    () async {
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          if (request.url.path == '/playlists/all') {
            return http.Response(
              jsonEncode({
                'MediaContainer': {
                  'totalSize': 1,
                  'Metadata': [
                    {'ratingKey': 'p1', 'title': 'Playlist'},
                  ],
                },
              }),
              200,
            );
          }
          final start = int.parse(
            request.url.queryParameters['X-Plex-Container-Start']!,
          );
          final base = start == 0 ? 101 : 103;
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'offset': start,
                'totalSize': 4,
                'Metadata': [
                  {..._playablePlaylistItem('a'), 'playlistItemID': base},
                  {..._playablePlaylistItem('b'), 'playlistItemID': base + 1},
                ],
              },
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);

      final catalog = await client.playlists(
        Uri.parse('https://plex.example:32400'),
        'secret',
        isCurrent: () => true,
      );

      expect(catalog.failedIds, isEmpty);
      expect(catalog.playlists.single.items.map((item) => item.id), [
        'a',
        'b',
        'a',
        'b',
      ]);
    },
  );

  test(
    'playlist repeated occurrence ids across pages fail that playlist',
    () async {
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          if (request.url.path == '/playlists/all') {
            return http.Response(
              jsonEncode({
                'MediaContainer': {
                  'totalSize': 1,
                  'Metadata': [
                    {'ratingKey': 'p1', 'title': 'Playlist'},
                  ],
                },
              }),
              200,
            );
          }
          final start = int.parse(
            request.url.queryParameters['X-Plex-Container-Start']!,
          );
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'offset': start,
                'totalSize': 4,
                'Metadata': start == 0
                    ? [
                        {..._playablePlaylistItem('a'), 'playlistItemID': 101},
                        {..._playablePlaylistItem('b'), 'playlistItemID': 102},
                      ]
                    : [
                        {..._playablePlaylistItem('b'), 'playlistItemID': 102},
                        {..._playablePlaylistItem('d'), 'playlistItemID': 104},
                      ],
              },
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);

      final catalog = await client.playlists(
        Uri.parse('https://plex.example:32400'),
        'secret',
        isCurrent: () => true,
      );

      expect(catalog.playlists, isEmpty);
      expect(catalog.failedIds, {'p1'});
    },
  );

  test(
    'playlist repeated occurrence ids within one page fail that playlist',
    () async {
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          if (request.url.path == '/playlists/all') {
            return http.Response(
              jsonEncode({
                'MediaContainer': {
                  'totalSize': 1,
                  'Metadata': [
                    {'ratingKey': 'p1', 'title': 'Playlist'},
                  ],
                },
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'totalSize': 2,
                'Metadata': [
                  {..._playablePlaylistItem('a'), 'playlistItemID': 101},
                  {..._playablePlaylistItem('b'), 'playlistItemID': 101},
                ],
              },
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);

      final catalog = await client.playlists(
        Uri.parse('https://plex.example:32400'),
        'secret',
        isCurrent: () => true,
      );

      expect(catalog.playlists, isEmpty);
      expect(catalog.failedIds, {'p1'});
    },
  );

  test('playlist numeric and decimal-string occurrence ids collide', () async {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        if (request.url.path == '/playlists/all') {
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'totalSize': 1,
                'Metadata': [
                  {'ratingKey': 'p1', 'title': 'Playlist'},
                ],
              },
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'totalSize': 2,
              'Metadata': [
                {..._playablePlaylistItem('a'), 'playlistItemID': 102},
                {..._playablePlaylistItem('b'), 'playlistItemID': '102'},
              ],
            },
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);

    final catalog = await client.playlists(
      Uri.parse('https://plex.example:32400'),
      'secret',
      isCurrent: () => true,
    );

    expect(catalog.playlists, isEmpty);
    expect(catalog.failedIds, {'p1'});
  });

  test('playlist invalid occurrence ids fail that playlist', () async {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        if (request.url.path == '/playlists/all') {
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'totalSize': 1,
                'Metadata': [
                  {'ratingKey': 'p1', 'title': 'Playlist'},
                ],
              },
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'totalSize': 2,
              'Metadata': [
                {..._playablePlaylistItem('a'), 'playlistItemID': 'not-an-id'},
                {..._playablePlaylistItem('b'), 'playlistItemID': 102},
              ],
            },
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);

    final catalog = await client.playlists(
      Uri.parse('https://plex.example:32400'),
      'secret',
      isCurrent: () => true,
    );

    expect(catalog.playlists, isEmpty);
    expect(catalog.failedIds, {'p1'});
  });

  test('playlist occurrence ids do not collide across playlists', () async {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        if (request.url.path == '/playlists/all') {
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'totalSize': 2,
                'Metadata': [
                  {'ratingKey': 'p1', 'title': 'First'},
                  {'ratingKey': 'p2', 'title': 'Second'},
                ],
              },
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'totalSize': 1,
              'Metadata': [
                {..._playablePlaylistItem('m'), 'playlistItemID': 101},
              ],
            },
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);

    final catalog = await client.playlists(
      Uri.parse('https://plex.example:32400'),
      'secret',
      isCurrent: () => true,
    );

    expect(catalog.failedIds, isEmpty);
    expect(catalog.playlists.map((playlist) => playlist.id), ['p1', 'p2']);
  });

  test(
    'playlist exact repeated terminal page with occurrence ids fails',
    () async {
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          if (request.url.path == '/playlists/all') {
            return http.Response(
              jsonEncode({
                'MediaContainer': {
                  'totalSize': 1,
                  'Metadata': [
                    {'ratingKey': 'p1', 'title': 'Playlist'},
                  ],
                },
              }),
              200,
            );
          }
          final start = int.parse(
            request.url.queryParameters['X-Plex-Container-Start']!,
          );
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'offset': start,
                'totalSize': 4,
                'Metadata': [
                  {..._playablePlaylistItem('a'), 'playlistItemID': 101},
                  {..._playablePlaylistItem('b'), 'playlistItemID': 102},
                ],
              },
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);

      final catalog = await client.playlists(
        Uri.parse('https://plex.example:32400'),
        'secret',
        isCurrent: () => true,
      );

      expect(catalog.playlists, isEmpty);
      expect(catalog.failedIds, {'p1'});
    },
  );

  for (final entry in [(401, 'auth-invalid'), (403, 'access-denied')]) {
    test(
      'fatal playlist authorization ${entry.$1} aborts sibling IO with the original error',
      timeout: const Timeout(Duration(seconds: 10)),
      () async {
        final status = entry.$1;
        final code = entry.$2;
        var mode = 'fatal';
        final itemRequests = <String>[];
        final allStarted = Completer<void>();
        final releaseFatal = Completer<void>();
        final abortObserved = Completer<void>();
        var aborts = 0;
        final client = PlexClient(
          clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
          httpClient: MockClient.streaming((request, _) async {
            if (request.url.path == '/playlists/all') {
              return http.StreamedResponse(
                Stream.value(
                  utf8.encode(
                    jsonEncode({
                      'MediaContainer': {
                        'totalSize': 5,
                        'Metadata': [
                          for (var i = 0; i < 5; i++)
                            {'ratingKey': 'p$i', 'title': 'Playlist $i'},
                        ],
                      },
                    }),
                  ),
                ),
                200,
              );
            }
            if (mode == 'valid') {
              return http.StreamedResponse(
                Stream.value(
                  utf8.encode(
                    jsonEncode({
                      'MediaContainer': {
                        'totalSize': 1,
                        'Metadata': [_playablePlaylistItem('m')],
                      },
                    }),
                  ),
                ),
                200,
              );
            }
            final path = request.url.path;
            itemRequests.add(
              '$path?start=${request.url.queryParameters['X-Plex-Container-Start']}',
            );
            if (itemRequests.length >= 4 && !allStarted.isCompleted) {
              allStarted.complete();
            }
            if (path == '/playlists/p0/items') {
              await allStarted.future;
              await releaseFatal.future;
              return http.StreamedResponse(Stream.empty(), status);
            }
            if (path == '/playlists/p1/items') {
              // The first page stays available until the fatal abort fires,
              // so any second page would prove sibling work was not stopped.
              await releaseFatal.future;
              await abortObserved.future;
              return http.StreamedResponse(
                Stream.value(
                  utf8.encode(
                    jsonEncode({
                      'MediaContainer': {
                        'offset': 0,
                        'totalSize': 4,
                        'Metadata': [
                          {..._playablePlaylistItem('a'), 'playlistItemID': 1},
                          {..._playablePlaylistItem('b'), 'playlistItemID': 2},
                        ],
                      },
                    }),
                  ),
                ),
                200,
              );
            }
            await (request as http.AbortableRequest).abortTrigger!;
            aborts++;
            if (!abortObserved.isCompleted) abortObserved.complete();
            throw http.RequestAbortedException(request.url);
          }),
        );
        addTearDown(client.close);

        final attempt = client.playlists(
          Uri.parse('https://plex.example:32400'),
          'secret',
          isCurrent: () => true,
        );
        await allStarted.future;
        releaseFatal.complete();
        await expectLater(attempt, _plexError(code));

        expect(aborts, 2);
        expect(
          itemRequests.where((item) => item.startsWith('/playlists/p4/')),
          isEmpty,
        );
        expect(itemRequests.where((item) => item.contains('start=2')), isEmpty);
        expect(itemRequests, hasLength(4));

        mode = 'valid';
        final retry = await client.playlists(
          Uri.parse('https://plex.example:32400'),
          'secret',
          isCurrent: () => true,
        );
        expect(retry.playlists.map((playlist) => playlist.id), [
          'p0',
          'p1',
          'p2',
          'p3',
          'p4',
        ]);
        expect(retry.failedIds, isEmpty);
      },
    );
  }

  test(
    'first fatal playlist authorization error wins the attempt',
    timeout: const Timeout(Duration(seconds: 10)),
    () async {
      // p1 fails first with 403 while p0's 401 is held back until the abort
      // signal proves p1's failure was already recorded. A simultaneous abort
      // converging on p0 must not replace it.
      final releaseSecond = Completer<void>();
      final abortObserved = Completer<void>();
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient.streaming((request, _) async {
          if (request.url.path == '/playlists/all') {
            return http.StreamedResponse(
              Stream.value(
                utf8.encode(
                  jsonEncode({
                    'MediaContainer': {
                      'totalSize': 3,
                      'Metadata': [
                        {'ratingKey': 'p0', 'title': 'First'},
                        {'ratingKey': 'p1', 'title': 'Second'},
                        {'ratingKey': 'p2', 'title': 'Third'},
                      ],
                    },
                  }),
                ),
              ),
              200,
            );
          }
          if (request.url.path == '/playlists/p1/items') {
            return http.StreamedResponse(Stream.empty(), 403);
          }
          if (request.url.path == '/playlists/p0/items') {
            await releaseSecond.future;
            return http.StreamedResponse(Stream.empty(), 401);
          }
          await (request as http.AbortableRequest).abortTrigger!;
          if (!abortObserved.isCompleted) abortObserved.complete();
          throw http.RequestAbortedException(request.url);
        }),
      );
      addTearDown(client.close);

      final attempt = client.playlists(
        Uri.parse('https://plex.example:32400'),
        'secret',
        isCurrent: () => true,
      );
      await abortObserved.future;
      releaseSecond.complete();
      await expectLater(attempt, _plexError('access-denied'));
    },
  );

  test('external playlist cancellation still throws instead of per-playlist failure', () async {
    final cancel = Completer<void>();
    var itemRequests = 0;
    final allStarted = Completer<void>();
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient.streaming((request, _) async {
        if (request.url.path == '/playlists/all') {
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                jsonEncode({
                  'MediaContainer': {
                    'totalSize': 2,
                    'Metadata': [
                      {'ratingKey': 'p0', 'title': 'First'},
                      {'ratingKey': 'p1', 'title': 'Second'},
                    ],
                  },
                }),
              ),
            ),
            200,
          );
        }
        itemRequests++;
        if (itemRequests == 2 && !allStarted.isCompleted) {
          allStarted.complete();
        }
        await (request as http.AbortableRequest).abortTrigger!;
        throw http.RequestAbortedException(request.url);
      }),
    );
    addTearDown(client.close);

    final attempt = client.playlists(
      Uri.parse('https://plex.example:32400'),
      'secret',
      isCurrent: () => true,
      cancelled: cancel.future,
    );
    await allStarted.future;
    cancel.complete();
    await expectLater(attempt, _plexError('cancelled'));
    expect(itemRequests, 2);
  });

  test(
    'individual playlist failure does not abort sibling playlists',
    () async {
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          if (request.url.path == '/playlists/all') {
            return http.Response(
              jsonEncode({
                'MediaContainer': {
                  'totalSize': 2,
                  'Metadata': [
                    {'ratingKey': 'p0', 'title': 'Failing'},
                    {'ratingKey': 'p1', 'title': 'Working'},
                  ],
                },
              }),
              200,
            );
          }
          if (request.url.path == '/playlists/p0/items') {
            return http.Response('', 500);
          }
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'totalSize': 1,
                'Metadata': [_playablePlaylistItem('m')],
              },
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);

      final catalog = await client.playlists(
        Uri.parse('https://plex.example:32400'),
        'secret',
        isCurrent: () => true,
      );

      expect(catalog.playlists.map((playlist) => playlist.id), ['p1']);
      expect(catalog.failedIds, {'p0'});
    },
  );

  test('playlist playable filtering applies after raw paging', () async {
    Map<String, Object?> unplayableItem(String id) => {
      'ratingKey': id,
      'key': '/library/metadata/$id',
      'title': 'Item $id',
      'type': 'movie',
      'duration': 1000,
    };
    final itemStarts = <int>[];
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        if (request.url.path == '/playlists/all') {
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'totalSize': 1,
                'Metadata': [
                  {'ratingKey': 'p1', 'title': 'Playlist'},
                ],
              },
            }),
            200,
          );
        }
        final start = int.parse(
          request.url.queryParameters['X-Plex-Container-Start']!,
        );
        itemStarts.add(start);
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'offset': start,
              'totalSize': 4,
              'Metadata': start == 0
                  ? [_playablePlaylistItem('m1'), unplayableItem('m2')]
                  : [_playablePlaylistItem('m1'), _playablePlaylistItem('m3')],
            },
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);

    final catalog = await client.playlists(
      Uri.parse('https://plex.example:32400'),
      'secret',
      isCurrent: () => true,
    );

    expect(itemStarts, [0, 2]);
    expect(catalog.failedIds, isEmpty);
    expect(catalog.playlists.single.items.map((item) => item.id), [
      'm1',
      'm1',
      'm3',
    ]);
  });

  test('playlist catalog rejects duplicate playlist identities', () async {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        final start = int.parse(
          request.url.queryParameters['X-Plex-Container-Start']!,
        );
        final ids = start == 0 ? ['p0', 'p1'] : ['p1', 'p2'];
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'offset': start,
              'totalSize': 4,
              'Metadata': [
                for (final id in ids)
                  {'ratingKey': id, 'title': 'Playlist $id'},
              ],
            },
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);

    await expectLater(
      client.playlists(
        Uri.parse('https://plex.example:32400'),
        'secret',
        isCurrent: () => true,
      ),
      _plexError('playlist-page-not-progressing'),
    );
  });

  for (final entry in <(String, List<Object?>)>[
    (
      'missing catalog id',
      [
        {'title': 'Synthetic broken playlist'},
      ],
    ),
    (
      'null catalog id',
      [
        {'ratingKey': null, 'title': 'Synthetic broken playlist'},
      ],
    ),
    (
      'empty catalog id',
      [
        {'ratingKey': '', 'title': 'Synthetic broken playlist'},
      ],
    ),
    (
      'whitespace catalog id',
      [
        {'ratingKey': '   ', 'title': 'Synthetic broken playlist'},
      ],
    ),
    ('null catalog row', [null]),
    ('scalar catalog row', ['oops']),
  ]) {
    test(
      'playlist catalog with ${entry.$1} fails instead of an empty success',
      () async {
        var itemRequests = 0;
        final client = PlexClient(
          clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith('/items')) itemRequests++;
            return http.Response(
              jsonEncode({
                'MediaContainer': {
                  'offset': 0,
                  'size': 1,
                  'totalSize': 1,
                  'Metadata': entry.$2,
                },
              }),
              200,
            );
          }),
        );
        addTearDown(client.close);

        await expectLater(
          client.playlists(
            Uri.parse('https://plex.example:32400'),
            'secret',
            isCurrent: () => true,
          ),
          _plexError('playlist-page-invalid'),
        );
        expect(itemRequests, 0);
      },
    );
  }

  test(
    'playlist catalog with an unidentifiable second page returns no prefix',
    () async {
      var itemRequests = 0;
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/items')) itemRequests++;
          final start = int.parse(
            request.url.queryParameters['X-Plex-Container-Start']!,
          );
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'offset': start,
                'totalSize': 3,
                'Metadata': start == 0
                    ? [
                        {'ratingKey': 'p0', 'title': 'Playlist p0'},
                        {'ratingKey': 'p1', 'title': 'Playlist p1'},
                      ]
                    : [
                        {'title': 'Synthetic broken playlist'},
                      ],
              },
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);

      await expectLater(
        client.playlists(
          Uri.parse('https://plex.example:32400'),
          'secret',
          isCurrent: () => true,
        ),
        _plexError('playlist-page-invalid'),
      );
      expect(itemRequests, 0);
    },
  );

  for (final entry in <(String, Map<String, Object?>)>[
    ('missing', {'ratingKey': 'p1'}),
    ('blank-empty', {'ratingKey': 'p1', 'title': ''}),
    ('blank-spaces', {'ratingKey': 'p1', 'title': '   '}),
  ]) {
    test(
      'playlist catalog entry with a ${entry.$1} title fails that playlist canonically',
      () async {
        var itemRequests = 0;
        final client = PlexClient(
          clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith('/items')) itemRequests++;
            return http.Response(
              jsonEncode({
                'MediaContainer': {
                  'totalSize': 1,
                  'Metadata': [entry.$2],
                },
              }),
              200,
            );
          }),
        );
        addTearDown(client.close);

        final catalog = await client.playlists(
          Uri.parse('https://plex.example:32400'),
          'secret',
          isCurrent: () => true,
        );

        expect(catalog.playlists, isEmpty);
        expect(catalog.failedIds, {'p1'});
        expect(itemRequests, 0);
      },
    );
  }

  test(
    'playlist failure uses the canonical id for padded catalog identities',
    () async {
      final itemPaths = <String>[];
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          if (request.url.path == '/playlists/all') {
            return http.Response(
              jsonEncode({
                'MediaContainer': {
                  'totalSize': 1,
                  'Metadata': [
                    {'ratingKey': ' p1 ', 'title': 'Padded'},
                  ],
                },
              }),
              200,
            );
          }
          itemPaths.add(request.url.path);
          return http.Response('', 500);
        }),
      );
      addTearDown(client.close);

      final catalog = await client.playlists(
        Uri.parse('https://plex.example:32400'),
        'secret',
        isCurrent: () => true,
      );

      expect(itemPaths, ['/playlists/p1/items']);
      expect(catalog.playlists, isEmpty);
      expect(catalog.failedIds, {'p1'});
    },
  );

  test('playlist catalog rejects padded duplicate identities', () async {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'offset': 0,
              'totalSize': 2,
              'Metadata': [
                {'ratingKey': 'p1', 'title': 'Playlist p1'},
                {'ratingKey': ' p1 ', 'title': 'Playlist padded'},
              ],
            },
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);

    await expectLater(
      client.playlists(
        Uri.parse('https://plex.example:32400'),
        'secret',
        isCurrent: () => true,
      ),
      _plexError('playlist-page-not-progressing'),
    );
  });

  test(
    'playlist numeric identities use one normalized representation',
    () async {
      final itemPaths = <String>[];
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          if (request.url.path == '/playlists/all') {
            return http.Response(
              jsonEncode({
                'MediaContainer': {
                  'totalSize': 2,
                  'Metadata': [
                    {'ratingKey': 7, 'title': 'Seven'},
                    {'ratingKey': '8', 'title': 'Eight'},
                  ],
                },
              }),
              200,
            );
          }
          itemPaths.add(request.url.path);
          if (request.url.path == '/playlists/7/items') {
            return http.Response('', 500);
          }
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'totalSize': 1,
                'Metadata': [_playablePlaylistItem('m8')],
              },
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);

      final catalog = await client.playlists(
        Uri.parse('https://plex.example:32400'),
        'secret',
        isCurrent: () => true,
      );

      expect(itemPaths, ['/playlists/7/items', '/playlists/8/items']);
      expect(catalog.playlists.map((playlist) => playlist.id), ['8']);
      expect(catalog.failedIds, {'7'});
    },
  );

  test('playlist explicit empty catalog remains a successful empty', () async {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'MediaContainer': {'totalSize': 0, 'Metadata': <Object?>[]},
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);

    final catalog = await client.playlists(
      Uri.parse('https://plex.example:32400'),
      'secret',
      isCurrent: () => true,
    );

    expect(catalog.playlists, isEmpty);
    expect(catalog.failedIds, isEmpty);
  });

  test('playlist catalog exceeding the work bound fails visibly', () async {
    var requests = 0;
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        requests++;
        final start = int.parse(
          request.url.queryParameters['X-Plex-Container-Start']!,
        );
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'totalSize': 100001,
              'Metadata': [
                for (var index = 0; index < 100; index++)
                  {
                    'ratingKey': '${start + index}',
                    'title': 'Playlist ${start + index}',
                  },
              ],
            },
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);

    await expectLater(
      client.playlists(
        Uri.parse('https://plex.example:32400'),
        'secret',
        isCurrent: () => true,
      ),
      _plexError('playlist-scale-exceeded'),
    );
    expect(requests, 1000);
  });

  test(
    'playlist contents exceeding the work bound fail only that playlist',
    () async {
      var itemRequests = 0;
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          if (request.url.path == '/playlists/all') {
            return http.Response(
              jsonEncode({
                'MediaContainer': {
                  'totalSize': 1,
                  'Metadata': [
                    {'ratingKey': 'p1', 'title': 'Playlist'},
                  ],
                },
              }),
              200,
            );
          }
          itemRequests++;
          final start = int.parse(
            request.url.queryParameters['X-Plex-Container-Start']!,
          );
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'totalSize': 100001,
                'Metadata': [
                  for (var index = 0; index < 100; index++)
                    _playablePlaylistItem('m${start + index}'),
                ],
              },
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);

      final catalog = await client.playlists(
        Uri.parse('https://plex.example:32400'),
        'secret',
        isCurrent: () => true,
      );

      expect(itemRequests, 1000);
      expect(catalog.playlists, isEmpty);
      expect(catalog.failedIds, {'p1'});
    },
  );

  test('playlist contents check cancellation before the next page', () async {
    var current = true;
    var itemRequests = 0;
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        if (request.url.path == '/playlists/all') {
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'totalSize': 1,
                'Metadata': [
                  {'ratingKey': 'p1', 'title': 'Playlist'},
                ],
              },
            }),
            200,
          );
        }
        itemRequests++;
        current = false;
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'totalSize': 4,
              'Metadata': [
                _playablePlaylistItem('m0'),
                _playablePlaylistItem('m1'),
              ],
            },
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);

    await expectLater(
      client.playlists(
        Uri.parse('https://plex.example:32400'),
        'secret',
        isCurrent: () => current,
      ),
      _plexError('cancelled'),
    );
    expect(itemRequests, 1);
  });

  test(
    'library pagination reports exact progress without page snapshots',
    () async {
      var requests = 0;
      final requestedStarts = <int>[];
      final progress = <PlexLibraryPageProgress>[];
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          requests++;
          final start = int.parse(
            request.url.queryParameters['X-Plex-Container-Start']!,
          );
          requestedStarts.add(start);
          const total = 2505;
          final count = (total - start).clamp(0, 100);
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'totalSize': total,
                'Metadata': [
                  for (var index = 0; index < count; index++)
                    {
                      'ratingKey': '${start + index}',
                      'key': '/library/metadata/${start + index}',
                      'title': 'Item ${start + index}',
                      'type': 'movie',
                      'duration': 1000,
                    },
                ],
              },
            }),
            200,
          );
        }),
      );

      final items = await client.libraryItems(
        Uri.parse('https://plex.example:32400'),
        'secret',
        '7',
        PlexLibraryType.movie,
        isCurrent: () => true,
        onProgress: progress.add,
      );

      expect(items, hasLength(2505));
      expect(requests, 26);
      expect(requestedStarts, [
        for (var start = 0; start <= 2500; start += 100) start,
      ]);
      expect(items.first.id, '0');
      expect(items.last.id, '2504');
      expect(
        progress.map((value) => value.completedItems),
        orderedEquals([
          for (var count = 100; count <= 2500; count += 100) count,
          2505,
        ]),
      );
      expect(progress.last.completedPages, 26);
      expect(progress.last.totalItems, 2505);
    },
  );

  test(
    'library short pages continue until the known total is reached',
    () async {
      final requestedStarts = <int>[];
      final progress = <PlexLibraryPageProgress>[];
      Map<String, Object?> page(int start, int count) => {
        'MediaContainer': {
          'offset': start,
          'totalSize': 120,
          'Metadata': [
            for (var index = 0; index < count; index++)
              {
                'ratingKey': '${start + index}',
                'key': '/library/metadata/${start + index}',
                'title': 'Item ${start + index}',
                'type': 'movie',
                'duration': 1000,
              },
          ],
        },
      };
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          final start = int.parse(
            request.url.queryParameters['X-Plex-Container-Start']!,
          );
          requestedStarts.add(start);
          return switch (start) {
            0 => http.Response(jsonEncode(page(0, 50)), 200),
            50 => http.Response(jsonEncode(page(50, 50)), 200),
            100 => http.Response(jsonEncode(page(100, 20)), 200),
            _ => http.Response(jsonEncode(page(start, 0)), 200),
          };
        }),
      );
      addTearDown(client.close);

      final items = await client.libraryItems(
        Uri.parse('https://plex.example:32400'),
        'secret',
        '7',
        PlexLibraryType.movie,
        isCurrent: () => true,
        onProgress: progress.add,
      );

      expect(items, hasLength(120));
      expect(requestedStarts, [0, 50, 100]);
      expect(items.map((item) => item.id), [
        for (var index = 0; index < 120; index++) '$index',
      ]);
      expect(progress.last.totalItems, 120);
    },
  );

  test('library exact full pages advance by raw records consumed', () async {
    final requestedStarts = <int>[];
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        final start = int.parse(
          request.url.queryParameters['X-Plex-Container-Start']!,
        );
        requestedStarts.add(start);
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'totalSize': 200,
              'Metadata': [
                for (var index = 0; index < 100; index++)
                  {
                    'ratingKey': '${start + index}',
                    'key': '/library/metadata/${start + index}',
                    'title': 'Item ${start + index}',
                    'type': 'movie',
                    'duration': 1000,
                  },
              ],
            },
          }),
          200,
        );
      }),
    );

    final items = await client.libraryItems(
      Uri.parse('https://plex.example:32400'),
      'secret',
      '7',
      PlexLibraryType.movie,
      isCurrent: () => true,
      onProgress: (_) {},
    );

    expect(items, hasLength(200));
    expect(requestedStarts, [0, 100]);
    expect(items.first.id, '0');
    expect(items.last.id, '199');
  });

  test('library total zero returns an empty complete result', () async {
    final requestedStarts = <int>[];
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        requestedStarts.add(
          int.parse(request.url.queryParameters['X-Plex-Container-Start']!),
        );
        return http.Response(
          jsonEncode({
            'MediaContainer': {'totalSize': 0, 'Metadata': []},
          }),
          200,
        );
      }),
    );

    final items = await client.libraryItems(
      Uri.parse('https://plex.example:32400'),
      'secret',
      '7',
      PlexLibraryType.movie,
      isCurrent: () => true,
      onProgress: (_) {},
    );

    expect(items, isEmpty);
    expect(requestedStarts, [0]);
  });

  test(
    'library pages without a total terminate on a valid empty page',
    () async {
      final requestedStarts = <int>[];
      Map<String, Object?> page(List<int> ids) => {
        'MediaContainer': {
          'Metadata': [
            for (final id in ids)
              {
                'ratingKey': '$id',
                'key': '/library/metadata/$id',
                'title': 'Item $id',
                'type': 'movie',
                'duration': 1000,
              },
          ],
        },
      };
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          final start = int.parse(
            request.url.queryParameters['X-Plex-Container-Start']!,
          );
          requestedStarts.add(start);
          return switch (start) {
            0 => http.Response(jsonEncode(page([0, 1])), 200),
            2 => http.Response(jsonEncode(page([2])), 200),
            _ => http.Response(jsonEncode(page(const [])), 200),
          };
        }),
      );

      final items = await client.libraryItems(
        Uri.parse('https://plex.example:32400'),
        'secret',
        '7',
        PlexLibraryType.movie,
        isCurrent: () => true,
        onProgress: (_) {},
      );

      expect(items.map((item) => item.id), ['0', '1', '2']);
      expect(requestedStarts, [0, 2, 3]);
    },
  );

  test('library retains an earlier total when later pages omit it', () async {
    final requestedStarts = <int>[];
    final progress = <PlexLibraryPageProgress>[];
    http.Response page(int start, List<int> ids, [int? total]) => http.Response(
      jsonEncode({
        'MediaContainer': {
          'totalSize': ?total,
          'Metadata': [
            for (final id in ids)
              {
                'ratingKey': '$id',
                'key': '/library/metadata/$id',
                'title': 'Item $id',
                'type': 'movie',
                'duration': 1000,
              },
          ],
        },
      }),
      200,
    );
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        final start = int.parse(
          request.url.queryParameters['X-Plex-Container-Start']!,
        );
        requestedStarts.add(start);
        return switch (start) {
          0 => page(0, [0, 1], 5),
          2 => page(2, [2, 3]),
          _ => page(4, [4]),
        };
      }),
    );

    final items = await client.libraryItems(
      Uri.parse('https://plex.example:32400'),
      'secret',
      '7',
      PlexLibraryType.movie,
      isCurrent: () => true,
      onProgress: progress.add,
    );

    expect(items.map((item) => item.id), ['0', '1', '2', '3', '4']);
    expect(requestedStarts, [0, 2, 4]);
    expect(progress.last.totalItems, 5);
  });

  test('library rejects a changed total', () async {
    final requestedStarts = <int>[];
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        final start = int.parse(
          request.url.queryParameters['X-Plex-Container-Start']!,
        );
        requestedStarts.add(start);
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'totalSize': start == 0 ? 5 : 6,
              'Metadata': [
                for (var index = 0; index < 2; index++)
                  {
                    'ratingKey': '${start + index}',
                    'key': '/library/metadata/${start + index}',
                    'title': 'Item ${start + index}',
                    'type': 'movie',
                    'duration': 1000,
                  },
              ],
            },
          }),
          200,
        );
      }),
    );

    await expectLater(
      client.libraryItems(
        Uri.parse('https://plex.example:32400'),
        'secret',
        '7',
        PlexLibraryType.movie,
        isCurrent: () => true,
        onProgress: (_) {},
      ),
      _plexError('library-page-invalid'),
    );
    expect(requestedStarts, [0, 2]);
  });

  test('library rejects a mismatched offset', () async {
    final requestedStarts = <int>[];
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        final start = int.parse(
          request.url.queryParameters['X-Plex-Container-Start']!,
        );
        requestedStarts.add(start);
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'offset': 0,
              'totalSize': 4,
              'Metadata': [
                for (var index = 0; index < 2; index++)
                  {
                    'ratingKey': '${start + index}',
                    'key': '/library/metadata/${start + index}',
                    'title': 'Item ${start + index}',
                    'type': 'movie',
                    'duration': 1000,
                  },
              ],
            },
          }),
          200,
        );
      }),
    );

    await expectLater(
      client.libraryItems(
        Uri.parse('https://plex.example:32400'),
        'secret',
        '7',
        PlexLibraryType.movie,
        isCurrent: () => true,
        onProgress: (_) {},
      ),
      _plexError('library-page-invalid'),
    );
    expect(requestedStarts, [0, 2]);
  });

  test('library rejects malformed container counts', () async {
    Map<String, Object?> record(String id) => {
      'ratingKey': id,
      'key': '/library/metadata/$id',
      'title': 'Item $id',
      'type': 'movie',
      'duration': 1000,
    };
    final badBodies = <String, Object?>{
      'missing container': {'Other': []},
      'non-map container': {'MediaContainer': []},
      'non-list metadata': {
        'MediaContainer': {'Metadata': 'soon'},
      },
      'missing metadata without empty size': {
        'MediaContainer': {'totalSize': 2},
      },
      'negative total': {
        'MediaContainer': {
          'totalSize': -1,
          'Metadata': [record('0')],
        },
      },
      'nonintegral total': {
        'MediaContainer': {
          'totalSize': 'many',
          'Metadata': [record('0')],
        },
      },
      'fractional total': {
        'MediaContainer': {
          'totalSize': 2.5,
          'Metadata': [record('0')],
        },
      },
      'negative offset': {
        'MediaContainer': {
          'offset': -3,
          'totalSize': 2,
          'Metadata': [record('0')],
        },
      },
      'nonintegral offset': {
        'MediaContainer': {
          'offset': 'start',
          'totalSize': 2,
          'Metadata': [record('0')],
        },
      },
      'contradictory size': {
        'MediaContainer': {
          'size': 2,
          'totalSize': 2,
          'Metadata': [record('0')],
        },
      },
    };
    for (final entry in badBodies.entries) {
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode(entry.value), 200),
        ),
      );
      await expectLater(
        client.libraryItems(
          Uri.parse('https://plex.example:32400'),
          'secret',
          '7',
          PlexLibraryType.movie,
          isCurrent: () => true,
          onProgress: (_) {},
        ),
        _plexError('library-page-invalid'),
        reason: entry.key,
      );
    }
  });

  test('library rejects a repeated page without progress', () async {
    final requestedStarts = <int>[];
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        final start = int.parse(
          request.url.queryParameters['X-Plex-Container-Start']!,
        );
        requestedStarts.add(start);
        const ids = [0, 1];
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'totalSize': 4,
              'Metadata': [
                for (final id in ids)
                  {
                    'ratingKey': '$id',
                    'key': '/library/metadata/$id',
                    'title': 'Item $id',
                    'type': 'movie',
                    'duration': 1000,
                  },
              ],
            },
          }),
          200,
        );
      }),
    );

    await expectLater(
      client.libraryItems(
        Uri.parse('https://plex.example:32400'),
        'secret',
        '7',
        PlexLibraryType.movie,
        isCurrent: () => true,
        onProgress: (_) {},
      ),
      _plexError('library-page-not-progressing'),
    );
    expect(requestedStarts, [0, 2]);
  });

  test('library rejects duplicate identities across pages', () async {
    final requestedStarts = <int>[];
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        final start = int.parse(
          request.url.queryParameters['X-Plex-Container-Start']!,
        );
        requestedStarts.add(start);
        final ids = start == 0 ? [0, 1] : [1, 2];
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'totalSize': 4,
              'Metadata': [
                for (final id in ids)
                  {
                    'ratingKey': '$id',
                    'key': '/library/metadata/$id',
                    'title': 'Item $id',
                    'type': 'movie',
                    'duration': 1000,
                  },
              ],
            },
          }),
          200,
        );
      }),
    );

    await expectLater(
      client.libraryItems(
        Uri.parse('https://plex.example:32400'),
        'secret',
        '7',
        PlexLibraryType.movie,
        isCurrent: () => true,
        onProgress: (_) {},
      ),
      _plexError('library-page-not-progressing'),
    );
    expect(requestedStarts, [0, 2]);
  });

  test('library rejects duplicate identities within one page', () async {
    final requestedStarts = <int>[];
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        requestedStarts.add(
          int.parse(request.url.queryParameters['X-Plex-Container-Start']!),
        );
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'totalSize': 2,
              'Metadata': [
                for (final id in ['7', '7'])
                  {
                    'ratingKey': id,
                    'key': '/library/metadata/$id',
                    'title': 'Item $id',
                    'type': 'movie',
                    'duration': 1000,
                  },
              ],
            },
          }),
          200,
        );
      }),
    );

    await expectLater(
      client.libraryItems(
        Uri.parse('https://plex.example:32400'),
        'secret',
        '7',
        PlexLibraryType.movie,
        isCurrent: () => true,
        onProgress: (_) {},
      ),
      _plexError('library-page-not-progressing'),
    );
    expect(requestedStarts, [0]);
  });

  test('library accepts a total that appears on a later page', () async {
    final requestedStarts = <int>[];
    final progress = <PlexLibraryPageProgress>[];
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        final start = int.parse(
          request.url.queryParameters['X-Plex-Container-Start']!,
        );
        requestedStarts.add(start);
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              if (start != 0) 'totalSize': 4,
              'Metadata': [
                for (var index = 0; index < 2; index++)
                  {
                    'ratingKey': '${start + index}',
                    'key': '/library/metadata/${start + index}',
                    'title': 'Item ${start + index}',
                    'type': 'movie',
                    'duration': 1000,
                  },
              ],
            },
          }),
          200,
        );
      }),
    );

    final items = await client.libraryItems(
      Uri.parse('https://plex.example:32400'),
      'secret',
      '7',
      PlexLibraryType.movie,
      isCurrent: () => true,
      onProgress: progress.add,
    );

    expect(items.map((item) => item.id), ['0', '1', '2', '3']);
    expect(requestedStarts, [0, 2]);
    expect(progress.last.totalItems, 4);
  });

  test('library treats an explicit empty container as complete', () async {
    final requestedStarts = <int>[];
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        requestedStarts.add(
          int.parse(request.url.queryParameters['X-Plex-Container-Start']!),
        );
        return http.Response(
          jsonEncode({
            'MediaContainer': {'size': 0, 'totalSize': 0},
          }),
          200,
        );
      }),
    );

    final items = await client.libraryItems(
      Uri.parse('https://plex.example:32400'),
      'secret',
      '7',
      PlexLibraryType.movie,
      isCurrent: () => true,
      onProgress: (_) {},
    );

    expect(items, isEmpty);
    expect(requestedStarts, [0]);
  });

  test('library rejects an empty page before the total is reached', () async {
    final requestedStarts = <int>[];
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        final start = int.parse(
          request.url.queryParameters['X-Plex-Container-Start']!,
        );
        requestedStarts.add(start);
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'totalSize': 3,
              'Metadata': [
                if (start == 0)
                  for (final id in [0, 1])
                    {
                      'ratingKey': '$id',
                      'key': '/library/metadata/$id',
                      'title': 'Item $id',
                      'type': 'movie',
                      'duration': 1000,
                    },
              ],
            },
          }),
          200,
        );
      }),
    );

    await expectLater(
      client.libraryItems(
        Uri.parse('https://plex.example:32400'),
        'secret',
        '7',
        PlexLibraryType.movie,
        isCurrent: () => true,
        onProgress: (_) {},
      ),
      _plexError('library-page-invalid'),
    );
    expect(requestedStarts, [0, 2]);
  });

  test('library rejects records beyond the reported total', () async {
    final requestedStarts = <int>[];
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        final start = int.parse(
          request.url.queryParameters['X-Plex-Container-Start']!,
        );
        requestedStarts.add(start);
        final ids = start == 0 ? [0, 1] : [2, 3];
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'totalSize': 3,
              'Metadata': [
                for (final id in ids)
                  {
                    'ratingKey': '$id',
                    'key': '/library/metadata/$id',
                    'title': 'Item $id',
                    'type': 'movie',
                    'duration': 1000,
                  },
              ],
            },
          }),
          200,
        );
      }),
    );

    await expectLater(
      client.libraryItems(
        Uri.parse('https://plex.example:32400'),
        'secret',
        '7',
        PlexLibraryType.movie,
        isCurrent: () => true,
        onProgress: (_) {},
      ),
      _plexError('library-page-invalid'),
    );
    expect(requestedStarts, [0, 2]);
  });

  test('library final-page failure invalidates the staged result', () async {
    final requestedStarts = <int>[];
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        final start = int.parse(
          request.url.queryParameters['X-Plex-Container-Start']!,
        );
        requestedStarts.add(start);
        if (start != 0) return http.Response('', 500);
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'totalSize': 4,
              'Metadata': [
                for (final id in [0, 1])
                  {
                    'ratingKey': '$id',
                    'key': '/library/metadata/$id',
                    'title': 'Item $id',
                    'type': 'movie',
                    'duration': 1000,
                  },
              ],
            },
          }),
          200,
        );
      }),
    );

    await expectLater(
      client.libraryItems(
        Uri.parse('https://plex.example:32400'),
        'secret',
        '7',
        PlexLibraryType.movie,
        isCurrent: () => true,
        onProgress: (_) {},
      ),
      _plexError('server-unreachable'),
    );
    expect(requestedStarts, [0, 2]);
  });

  test('library cancellation aborts the active HTTP request', () async {
    final cancelled = Completer<void>();
    var requests = 0;
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient.streaming((request, _) async {
        requests++;
        // Hang like an unresponsive server until the scan is cancelled, then
        // abort the way a real transport observes the abort trigger.
        await (request as http.AbortableRequest).abortTrigger!;
        throw http.RequestAbortedException(request.url);
      }),
    );
    addTearDown(client.close);

    final pending = client.libraryItems(
      Uri.parse('https://plex.example:32400'),
      'secret',
      '7',
      PlexLibraryType.movie,
      isCurrent: () => true,
      onProgress: (_) {},
      cancelled: cancelled.future,
    );
    final assertion = expectLater(pending, _plexError('cancelled'));
    await Future<void>.delayed(Duration.zero);
    cancelled.complete();
    await assertion;
    expect(requests, 1);
  });

  test('library sends no request when the scope is already stale', () async {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((_) async => fail('No request should be sent')),
    );

    await expectLater(
      client.libraryItems(
        Uri.parse('https://plex.example:32400'),
        'secret',
        '7',
        PlexLibraryType.movie,
        isCurrent: () => false,
        onProgress: (_) {},
      ),
      _plexError('cancelled'),
    );
  });

  test('library rejects stale results before progress callbacks', () async {
    var requests = 0;
    var currentCalls = 0;
    var progressCalls = 0;
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((_) async {
        requests++;
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'totalSize': 1,
              'Metadata': [
                {
                  'ratingKey': '0',
                  'key': '/library/metadata/0',
                  'title': 'Item 0',
                  'type': 'movie',
                  'duration': 1000,
                },
              ],
            },
          }),
          200,
        );
      }),
    );

    await expectLater(
      client.libraryItems(
        Uri.parse('https://plex.example:32400'),
        'secret',
        '7',
        PlexLibraryType.movie,
        isCurrent: () => ++currentCalls == 1,
        onProgress: (_) => progressCalls++,
      ),
      _plexError('cancelled'),
    );
    expect(requests, 1);
    expect(progressCalls, 0);
  });

  test('library advances raw offsets past unplayable records', () async {
    // libraryItems retains every parsed record (playable filtering happens
    // later in the controller), so this locks in that the next request offset
    // counts raw records including the unplayable one.
    final requestedStarts = <int>[];
    Map<String, Object?> playable(String id) => {
      'ratingKey': id,
      'key': '/library/metadata/$id',
      'title': 'Item $id',
      'type': 'movie',
      'duration': 1000,
      'Media': [
        {
          'Part': [
            {'key': '/library/parts/$id'},
          ],
        },
      ],
    };
    Map<String, Object?> unplayable(String id) => {
      'ratingKey': id,
      'key': '/library/metadata/$id',
      'title': 'Item $id',
      'type': 'movie',
      'duration': 0,
    };
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        final start = int.parse(
          request.url.queryParameters['X-Plex-Container-Start']!,
        );
        requestedStarts.add(start);
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'totalSize': 5,
              'Metadata': start == 0
                  ? [playable('0'), unplayable('1'), playable('2')]
                  : [playable('3'), playable('4')],
            },
          }),
          200,
        );
      }),
    );

    final items = await client.libraryItems(
      Uri.parse('https://plex.example:32400'),
      'secret',
      '7',
      PlexLibraryType.movie,
      isCurrent: () => true,
      onProgress: (_) {},
    );

    expect(items.map((item) => item.id), ['0', '1', '2', '3', '4']);
    expect(requestedStarts, [0, 3]);
  });

  test('library pagination checks cancellation before the next page', () async {
    var current = true;
    var requests = 0;
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((_) async {
        requests++;
        current = false;
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'totalSize': 200,
              'Metadata': [
                for (var index = 0; index < 100; index++)
                  {
                    'ratingKey': '$index',
                    'key': '/library/metadata/$index',
                    'title': 'Item $index',
                    'type': 'movie',
                    'duration': 1000,
                  },
              ],
            },
          }),
          200,
        );
      }),
    );

    await expectLater(
      client.libraryItems(
        Uri.parse('https://plex.example:32400'),
        'secret',
        '7',
        PlexLibraryType.movie,
        isCurrent: () => current,
        onProgress: (_) {},
      ),
      throwsA(
        isA<PlexException>().having((error) => error.code, 'code', 'cancelled'),
      ),
    );
    expect(requests, 1);
  });

  test('library pagination rejects a page larger than requested', () async {
    final requestedStarts = <int>[];
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        requestedStarts.add(
          int.parse(request.url.queryParameters['X-Plex-Container-Start']!),
        );
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'Metadata': [
                for (var index = 0; index < 101; index++)
                  {
                    'ratingKey': '$index',
                    'title': 'Item $index',
                    'type': 'movie',
                    'duration': 1000,
                  },
              ],
            },
          }),
          200,
        );
      }),
    );

    await expectLater(
      client.libraryItems(
        Uri.parse('https://plex.example:32400'),
        'secret',
        '7',
        PlexLibraryType.movie,
        isCurrent: () => true,
        onProgress: (_) {},
      ),
      throwsA(
        isA<PlexException>().having(
          (error) => error.code,
          'code',
          'library-page-too-large',
        ),
      ),
    );
    expect(requestedStarts, [0]);
  });

  test(
    'one thousand full pages return when the reported total is reached',
    () async {
      var requests = 0;
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          requests++;
          final start = int.parse(
            request.url.queryParameters['X-Plex-Container-Start']!,
          );
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'totalSize': 100000,
                'Metadata': [
                  for (var index = 0; index < 100; index++)
                    {
                      'ratingKey': '${start + index}',
                      'key': '/library/metadata/${start + index}',
                      'title': 'Item ${start + index}',
                      'type': 'movie',
                      'duration': 1000,
                    },
                ],
              },
            }),
            200,
          );
        }),
      );

      final items = await client.libraryItems(
        Uri.parse('https://plex.example:32400'),
        'secret',
        '7',
        PlexLibraryType.movie,
        isCurrent: () => true,
        onProgress: (_) {},
      );

      expect(items, hasLength(100000));
      expect(requests, 1000);
    },
  );

  test(
    'one thousand full library pages fail visibly instead of truncating',
    () async {
      var requests = 0;
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          requests++;
          final start = int.parse(
            request.url.queryParameters['X-Plex-Container-Start']!,
          );
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'totalSize': 100001,
                'Metadata': [
                  for (var index = 0; index < 100; index++)
                    {
                      'ratingKey': '${start + index}',
                      'key': '/library/metadata/${start + index}',
                      'title': 'Item ${start + index}',
                      'type': 'movie',
                      'duration': 1000,
                    },
                ],
              },
            }),
            200,
          );
        }),
      );

      await expectLater(
        client.libraryItems(
          Uri.parse('https://plex.example:32400'),
          'secret',
          '7',
          PlexLibraryType.movie,
          isCurrent: () => true,
          onProgress: (_) {},
        ),
        throwsA(
          isA<PlexException>().having(
            (error) => error.code,
            'code',
            'library-scale-exceeded',
          ),
        ),
      );
      expect(requests, 1000);
    },
  );

  test(
    'Plex Home falls back from empty v2 users and missing v2 switch',
    () async {
      final paths = <String>[];
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          return switch (request.url.path) {
            '/api/v2/home/users' => http.Response(
              jsonEncode({'users': []}),
              200,
            ),
            '/api/home/users' => http.Response(
              '<MediaContainer><User id="7" title="Home &amp; Away" protected="0"/></MediaContainer>',
              200,
            ),
            '/api/v2/home/users/7/switch' => http.Response('', 404),
            '/api/home/users/7/switch' => http.Response(
              '<user authenticationToken="profile-secret"/>',
              200,
            ),
            _ => http.Response('', 500),
          };
        }),
      );
      final users = await client.homeUsers('account-secret');
      expect(users.single.name, 'Home & Away');
      expect(
        await client.switchHomeUser('account-secret', '7', null),
        'profile-secret',
      );
      expect(paths, [
        '/api/v2/home/users',
        '/api/home/users',
        '/api/v2/home/users/7/switch',
        '/api/home/users/7/switch',
      ]);
    },
  );

  test('Plex Home JSON preserves explicit role facts', () async {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'User': [
              {
                'id': 'admin',
                'title': 'Admin profile',
                'ADMIN': 'yes',
                'restricted': false,
              },
              {
                'id': 'restricted',
                'title': 'Restricted profile',
                'IsAdMiN': 0,
                'ReStRiCtEd': 'true',
              },
              {'id': 'standard', 'title': 'Standard profile'},
            ],
          }),
          200,
        ),
      ),
    );

    final users = await client.homeUsers('account-secret');
    expect(users[0].admin, isTrue);
    expect(users[0].restricted, isFalse);
    expect(users[1].admin, isFalse);
    expect(users[1].restricted, isTrue);
    expect(users[2].admin, isFalse);
    expect(users[2].restricted, isNull);
  });

  test('Plex Home XML preserves explicit role facts', () async {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient(
        (_) async => http.Response(
          '<MediaContainer>'
          '<User id="admin" title="Admin profile" admin="1" restricted="false"/>'
          '<User id="restricted" title="Restricted profile" isAdmin="false" restricted="yes"/>'
          '<User id="standard" title="Standard profile"/>'
          '</MediaContainer>',
          200,
        ),
      ),
    );

    final users = await client.homeUsers('account-secret');
    expect(users[0].admin, isTrue);
    expect(users[0].restricted, isFalse);
    expect(users[1].admin, isFalse);
    expect(users[1].restricted, isTrue);
    expect(users[2].admin, isFalse);
    expect(users[2].restricted, isNull);
  });

  test('Plex Home v2 server failure falls back to legacy', () async {
    final paths = <String>[];
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient((request) async {
        paths.add(request.url.path);
        return request.url.path.contains('/v2/')
            ? http.Response('', 503)
            : http.Response(
                '<MediaContainer><User id="7" title="Home" protected="0"/></MediaContainer>',
                200,
              );
      }),
    );

    expect((await client.homeUsers('account-secret')).single.id, '7');
    expect(paths, ['/api/v2/home/users', '/api/home/users']);
  });

  test('Plex Home legacy server failure is terminal', () async {
    final client = PlexClient(
      clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
      httpClient: MockClient(
        (request) async => request.url.path.contains('/v2/')
            ? http.Response('', 404)
            : http.Response('', 503),
      ),
    );

    await expectLater(
      client.homeUsers('account-secret'),
      throwsA(
        isA<PlexException>().having(
          (exception) => exception.code,
          'code',
          'server-unreachable',
        ),
      ),
    );
  });

  for (final status in [404, 405]) {
    test('missing legacy Plex Home inventory is empty ($status)', () async {
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((_) async => http.Response('', status)),
      );

      expect(await client.homeUsers('account-secret'), isEmpty);
    });
  }

  for (final (format, payload) in [
    ('JSON', '{"users":'),
    ('XML', '<MediaContainer>'),
  ]) {
    test(
      'malformed successful Plex Home payload is a parse error ($format)',
      () async {
        final client = PlexClient(
          clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
          httpClient: MockClient((_) async => http.Response(payload, 200)),
        );

        await expectLater(
          client.homeUsers('account-secret'),
          throwsA(
            isA<PlexException>().having(
              (exception) => exception.code,
              'code',
              'parse-error',
            ),
          ),
        );
      },
    );
  }

  for (final (format, payload) in [
    ('JSON', jsonEncode({'users': []})),
    ('XML', '<MediaContainer/>'),
  ]) {
    test('valid empty Plex Home inventory remains empty ($format)', () async {
      var calls = 0;
      final client = PlexClient(
        clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        httpClient: MockClient((_) async {
          calls++;
          return http.Response(payload, 200);
        }),
      );

      expect(await client.homeUsers('account-secret'), isEmpty);
      expect(calls, 2);
    });
  }
}

List<PlexPlaybackPartDescriptor> _directPlaybackDescriptor(String partPath) =>
    PlexClient(clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst')
        .playbackDescriptor(
          server: Uri.parse('https://plex.example:32400'),
          item: PlexMediaItem(
            id: '1',
            title: 'Movie',
            type: 'movie',
            duration: const Duration(minutes: 1),
            parts: [PlexMediaPart(path: partPath)],
            container: 'mkv',
            videoCodec: 'h264',
            audioCodec: 'aac',
            dynamicRange: DynamicRange.sdr,
          ),
        );

Matcher _plexError(String code) => throwsA(
  isA<PlexException>().having((exception) => exception.code, 'code', code),
);

Map<String, Object?> _playablePlaylistItem(String id) => {
  'ratingKey': id,
  'key': '/library/metadata/$id',
  'title': 'Item $id',
  'type': 'movie',
  'duration': 1000,
  'Media': [
    {
      'Part': [
        {'key': '/library/parts/$id'},
      ],
    },
  ],
};
