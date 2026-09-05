import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

void main() {
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
        // Observe the peer closing before client.close(): timeout alone is not proof.
        await disconnected.future.timeout(const Duration(seconds: 2));
      },
    );
  }
}

Matcher _plexError(String code) => throwsA(
  isA<PlexException>().having((exception) => exception.code, 'code', code),
);
