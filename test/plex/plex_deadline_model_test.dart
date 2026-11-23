import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/plex/plex_scan_budget.dart';

enum _Deadlines {
  scanFirst(1, 2),
  requestFirst(2, 1),
  equal(1, 1);

  const _Deadlines(this.scanMinutes, this.requestMinutes);
  final int scanMinutes;
  final int requestMinutes;
}

enum _Phase { awaitingHeaders, readingBody }

void main() {
  for (final deadlines in _Deadlines.values) {
    for (final phase in _Phase.values) {
      for (final nativeTimeoutFirst in [false, true]) {
        testWidgets(
          '${deadlines.name}, ${phase.name}, '
          '${nativeTimeoutFirst ? "transport times out first" : "transport stalls"}',
          (tester) =>
              _checkSchedule(tester, deadlines, phase, nativeTimeoutFirst),
        );
      }
    }
  }
}

Future<void> _checkSchedule(
  WidgetTester tester,
  _Deadlines deadlines,
  _Phase phase,
  bool nativeTimeoutFirst,
) async {
  final headers = Completer<http.StreamedResponse>();
  var bodyCancelled = false;
  final body = StreamController<List<int>>(
    onCancel: () => Future<void>.microtask(() => bodyCancelled = true),
  );
  var aborted = false;
  final client = PlexClient(
    clientIdentifier: 'synthetic',
    scanLimits: PlexScanLimits(
      elapsed: Duration(minutes: deadlines.scanMinutes),
    ),
    requestTimeout: Duration(minutes: deadlines.requestMinutes),
    httpClient: MockClient.streaming((request, _) {
      final trigger = (request as http.AbortableRequest).abortTrigger!;
      unawaited(trigger.then((_) => aborted = true));
      return headers.future;
    }),
  );
  addTearDown(client.close);
  Object? failure;
  bool? budgetActive;
  final attempt = client.runScan((budget) async {
    try {
      await client.playlists(
        Uri.parse('https://synthetic.invalid'),
        'token',
        isCurrent: () => true,
      );
    } finally {
      budgetActive = budget.isActive;
    }
  });
  unawaited(
    attempt.then<void>(
      (_) {},
      onError: (Object e) {
        failure = e;
      },
    ),
  );
  if (phase == _Phase.readingBody) {
    headers.complete(http.StreamedResponse(body.stream, 200));
  }

  await tester.pump();
  await tester.pump(const Duration(seconds: 59));
  expect(aborted, isFalse);
  expect(failure, isNull);
  if (nativeTimeoutFirst) {
    final error = TimeoutException('transport');
    if (phase == _Phase.readingBody) {
      body.addError(error);
    } else {
      headers.completeError(error);
    }
    await tester.pump();
  } else {
    await tester.pump(const Duration(seconds: 1));
  }

  final scanExpired =
      !nativeTimeoutFirst && deadlines != _Deadlines.requestFirst;
  if (scanExpired) {
    expect(
      failure,
      isA<PlexScanLimitException>().having((e) => e.limit, 'limit', 'elapsed'),
    );
  } else {
    expect(
      failure,
      isA<PlexException>().having((e) => e.code, 'code', 'network-timeout'),
    );
  }
  expect(budgetActive, !scanExpired);
  expect(aborted, isTrue);

  if (phase == _Phase.awaitingHeaders && !nativeTimeoutFirst) {
    headers.complete(http.StreamedResponse(body.stream, 200));
    await tester.pump();
  }
  expect(bodyCancelled, phase == _Phase.readingBody || !nativeTimeoutFirst);
  unawaited(body.close());
  await tester.pump();
}
