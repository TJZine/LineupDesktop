import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/android/fixtures/session_clock_contract.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String, Object?> property(String name, Object? value, {int loadId = 1}) =>
      {'type': 'property', 'loadId': loadId, 'name': name, 'value': value};
  PublicClockRecorder ready(String name) {
    final recorder = PublicClockRecorder(name, '0123456789abcdef');
    recorder.receive({'type': 'state', 'state': 'playing', 'loadId': 1});
    recorder.receive(property('video-params', {'w': 1920, 'h': 1080}));
    recorder.receive(property('time-pos', 0.0));
    recorder.receive(
      property('session-clock', {
        'state': 'ready',
        'adjustmentUs': name == 'zero' ? -10500000 : -11250000,
      }),
    );
    return recorder;
  }

  test(
    'all statuses use the provider cache path and atomic fixed file',
    () async {
      final root = await Directory.systemTemp.createTemp('session-clock-path-');
      final cache = await Directory('${root.path}/cache').create();
      const provider = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var lookups = 0;
      messenger.setMockMethodCallHandler(provider, (call) async {
        expect(call.method, 'getTemporaryDirectory');
        lookups++;
        return cache.path;
      });
      try {
        final recorder = ready('zero');
        for (final state in ['running', 'complete', 'failed']) {
          await writePublicClockStatus(recorder, state);
          final file = File('${cache.path}/$sessionClockStatusName');
          final bytes = await file.readAsBytes();
          expect(bytes.length, lessThanOrEqualTo(64 * 1024));
          final value = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
          expect(value['status'], state);
          expect(value['nonce'], '0123456789abcdef');
          expect(await File('${file.path}.tmp').exists(), isFalse);
          expect(await root.list().length, 1);
        }
        expect(lookups, 3);
        expect(await cache.list().length, 1);
      } finally {
        messenger.setMockMethodCallHandler(provider, null);
        await root.delete(recursive: true);
      }
    },
  );

  test('closed clock values accept initialized zero and fixed diagnostics', () {
    expect(publicClockValue({'state': 'ready', 'adjustmentUs': 0}), {
      'state': 'ready',
      'adjustmentUs': 0,
    });
    expect(
      publicClockValue({
        'state': 'ready',
        'adjustmentUs': 0,
        'diagnosticCode': 'clock_rebased',
      })['diagnosticCode'],
      'clock_rebased',
    );
    expect(
      publicClockValue({
        'state': 'unavailable',
        'reason': 'discontinuity',
        'diagnosticCode': 'clock_unavailable',
      })['state'],
      'unavailable',
    );
    for (final value in [
      {'state': 'ready', 'adjustmentUs': double.nan},
      {'state': 'ready', 'adjustmentUs': -9223372036854775808},
      {'state': 'ready', 'adjustmentUs': 1, 'positionUs': 0},
      {'state': 'ready', 'adjustmentUs': 1, 'diagnosticCode': 'other'},
      {'state': 'pending', 'revision': 1},
      {
        'state': 'unavailable',
        'reason': 'arbitrary',
        'diagnosticCode': 'clock_unavailable',
      },
      for (final reason in ['unsupported_scope', 'adjustment_changed'])
        {
          'state': 'unavailable',
          'reason': reason,
          'diagnosticCode': 'clock_unavailable',
        },
    ]) {
      expect(() => publicClockValue(value), throwsA(isA<PublicClockFailure>()));
    }
  });

  test('case and nonce inputs cannot become URI or capability arguments', () {
    expect(publicClockCase(['--case=zero']), 'zero');
    expect(publicClockNonce(['--nonce=0123456789abcdef']), '0123456789abcdef');
    expect(
      () => publicClockCase(['--case=https://example.test']),
      throwsA(isA<PublicClockFailure>()),
    );
    expect(
      () => publicClockNonce(['--nonce=secret']),
      throwsA(isA<PublicClockFailure>()),
    );
  });

  test(
    'raw position stays raw and readiness requires actual video metadata',
    () {
      final recorder = ready('offset21');
      recorder.receive(property('time-pos', 20.25));
      expect(recorder.qualified, isTrue);
      recorder.sample();
      expect(recorder.samples.single['positionSeconds'], 20.25);
      recorder.width = 0;
      expect(recorder.qualified, isFalse);
      expect(recorder.sample, throwsA(isA<PublicClockFailure>()));
    },
  );

  test(
    'stale load facts do not initialize clock and terminal cannot reverse',
    () {
      final recorder = PublicClockRecorder('zero', '0123456789abcdef');
      recorder.receive(
        property('session-clock', {
          'state': 'ready',
          'adjustmentUs': -10500000,
        }, loadId: 2),
      );
      expect(recorder.clock, isNull);
      recorder.receive(
        property('session-clock', {
          'state': 'unavailable',
          'reason': 'discontinuity',
          'diagnosticCode': 'clock_unavailable',
        }),
      );
      recorder.receive(
        property('session-clock', {
          'state': 'ready',
          'adjustmentUs': -10500000,
        }),
      );
      expect(recorder.failure, 'terminal_clock_reversed');
      expect(recorder.clock?['state'], 'unavailable');
    },
  );

  test('discontinuity is a diagnostic observation, not a player error', () {
    final recorder = ready('discontinuity');
    recorder.receive(
      property('session-clock', {
        'state': 'unavailable',
        'reason': 'discontinuity',
        'diagnosticCode': 'clock_unavailable',
      }),
    );
    expect(recorder.qualified, isTrue);
    expect(recorder.failure, isNull);
    expect(recorder.playing, isTrue);
  });

  test('cleanup acknowledgement survives prior measurement failure', () {
    final recorder = ready('zero');
    recorder.receive({'type': 'state', 'state': 'error', 'loadId': 1});
    expect(recorder.failure, 'player_failed');
    recorder.receive({'type': 'stopResult', 'stopId': 1, 'success': true});
    expect(recorder.stopSeen, isTrue);
    expect(recorder.stopConfirmed, isTrue);
    expect(recorder.failure, 'player_failed');
  });

  test('ready adjustment cannot change without a pending transition', () {
    final recorder = ready('zero');
    recorder.receive(
      property('session-clock', {'state': 'ready', 'adjustmentUs': 0}),
    );
    expect(recorder.failure, 'ready_adjustment_changed');
  });

  test('seek qualifies only fresh pending then ready, with measured A1', () {
    for (final a1 in [-10500000, -11250000]) {
      final recorder = ready('zero');
      recorder.beginSeek();
      recorder.receive(property('time-pos', 6.0));
      recorder.receive(
        property('session-clock', {
          'state': 'ready',
          'adjustmentUs': -10500000,
        }),
      );
      expect(recorder.qualified, isFalse);
      expect(recorder.seekReadyObserved, isFalse);
      recorder.receive(property('session-clock', {'state': 'pending'}));
      expect(recorder.qualified, isFalse);
      recorder.receive(
        property('session-clock', {
          'state': 'ready',
          'adjustmentUs': a1,
        }, loadId: 2),
      );
      expect(recorder.seekReadyObserved, isFalse);
      recorder.receive(
        property('session-clock', {
          'state': 'ready',
          'adjustmentUs': a1,
          if (a1 != -10500000) 'diagnosticCode': 'clock_rebased',
        }),
      );
      expect(recorder.qualified, isTrue);
      expect(recorder.failure, isNull);
      expect(recorder.status('complete')['seekClock'], {
        'a0Us': -10500000,
        'a1Us': a1,
        'deltaUs': a1 + 10500000,
        'pendingObserved': true,
        'readyObserved': true,
        'readyAdjustmentsUs': [-10500000, a1],
        'clockRebasedObserved': a1 != -10500000,
      });
      recorder.sample();
      expect(recorder.samples.single['positionSeconds'], 6.0);
      expect(recorder.samples.single['adjustmentUs'], a1);
      recorder.receive(
        property('session-clock', {'state': 'ready', 'adjustmentUs': a1}),
      );
      expect(recorder.readyAdjustmentsUs, [-10500000, a1]);
    }
  });

  test('event/sample bounds are enforced without raw diagnostic retention', () {
    final recorder = ready('zero');
    for (var i = 0; i < 201; i++) {
      recorder.receive(property('ignored', 'not retained'));
    }
    expect(recorder.failure, 'event_bound');
    expect(recorder.eventCount, 200);
    expect(
      recorder.status('failed').toString(),
      isNot(contains('not retained')),
    );
  });
}
