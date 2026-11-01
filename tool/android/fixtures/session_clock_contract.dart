// Fixed public-only native clock integration target. No app/account state access.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const sessionClockCases = {'zero', 'offset21', 'discontinuity'};
const sessionClockStatusName = 'session-hls-clock-public-v1.json';
const _channel = MethodChannel('lineup/native_player');

class PublicClockFailure implements Exception {
  const PublicClockFailure(this.code);
  final String code;
}

Map<String, Object> publicClockValue(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const PublicClockFailure('clock_schema');
  }
  final state = value['state'];
  if (state == 'pending' && value.length == 1) return {'state': 'pending'};
  if (state == 'ready' &&
      (value.length == 2 ||
          value.length == 3 && value['diagnosticCode'] == 'clock_rebased') &&
      value['adjustmentUs'] is int) {
    final adjustment = value['adjustmentUs'] as int;
    if (adjustment >= -1000000000000 && adjustment <= 1000000000000) {
      return {
        'state': 'ready',
        'adjustmentUs': adjustment,
        if (value.length == 3) 'diagnosticCode': 'clock_rebased',
      };
    }
  }
  const reasons = {
    'discontinuity',
    'period_mismatch',
    'ambiguous_adjuster',
    'invalid_timestamp',
  };
  if (state == 'unavailable' &&
      value.length == 3 &&
      reasons.contains(value['reason']) &&
      value['diagnosticCode'] == 'clock_unavailable') {
    return {
      'state': 'unavailable',
      'reason': value['reason'] as String,
      'diagnosticCode': 'clock_unavailable',
    };
  }
  throw const PublicClockFailure('clock_schema');
}

String publicClockCase(List<String> args) {
  final cases = args.where((arg) => arg.startsWith('--case=')).toList();
  if (cases.length != 1 ||
      !sessionClockCases.contains(cases.single.substring(7))) {
    throw const PublicClockFailure('case_invalid');
  }
  return cases.single.substring(7);
}

String publicClockNonce(List<String> args) {
  final values = args.where((arg) => arg.startsWith('--nonce=')).toList();
  if (values.length != 1 ||
      !RegExp(r'^[0-9a-f]{16}$').hasMatch(values.single.substring(8))) {
    throw const PublicClockFailure('nonce_invalid');
  }
  return values.single.substring(8);
}

class PublicClockRecorder {
  PublicClockRecorder(this.caseName, this.nonce);
  final String caseName;
  final String nonce;
  final elapsed = Stopwatch()..start();
  final List<Map<String, Object>> clocks = [];
  final List<Map<String, Object>> samples = [];
  Map<String, Object>? clock;
  double? position;
  double? duration;
  int? width;
  int? height;
  int eventCount = 0;
  bool playing = false;
  bool stopSeen = false;
  bool stopConfirmed = false;
  bool disposed = false;
  bool seekIssued = false;
  bool seekPendingObserved = false;
  bool seekReadyObserved = false;
  bool clockRebasedObserved = false;
  int? a0Us;
  int? a1Us;
  final List<int> readyAdjustmentsUs = [];
  String? failure;

  void receive(Object? value) {
    // Cleanup acknowledgements remain observable after a measurement failure.
    if (value is Map && value['type'] == 'stopResult' && value['stopId'] == 1) {
      stopSeen = true;
      stopConfirmed = value['success'] == true;
      if (!stopConfirmed) failure ??= 'stop_failed';
      return;
    }
    if (failure != null) return;
    try {
      if (eventCount == 200) throw const PublicClockFailure('event_bound');
      eventCount++;
      if (value is! Map) throw const PublicClockFailure('event_schema');
      final type = value['type'];
      if (value['loadId'] != 1) return;
      if (type == 'state') {
        if (value['state'] == 'error' || value['state'] == 'ended') {
          throw const PublicClockFailure('player_failed');
        }
        if (value['state'] == 'playing') playing = true;
        return;
      }
      if (type != 'property') return;
      switch (value['name']) {
        case 'session-clock':
          final next = publicClockValue(value['value']);
          if (clock?['state'] == 'unavailable' &&
              jsonEncode(next) != jsonEncode(clock)) {
            throw const PublicClockFailure('terminal_clock_reversed');
          }
          if (clock?['state'] == 'ready' &&
              next['state'] == 'ready' &&
              next['adjustmentUs'] != clock?['adjustmentUs']) {
            throw const PublicClockFailure('ready_adjustment_changed');
          }
          if (seekIssued && next['state'] == 'pending') {
            seekPendingObserved = true;
          }
          if (next['state'] == 'ready' && clock?['state'] != 'ready') {
            readyAdjustmentsUs.add(next['adjustmentUs']! as int);
            if (seekIssued && seekPendingObserved) {
              a1Us = next['adjustmentUs']! as int;
              seekReadyObserved = true;
            }
          }
          if (next['diagnosticCode'] == 'clock_rebased') {
            clockRebasedObserved = true;
          }
          if (jsonEncode(next) != jsonEncode(clock)) {
            clocks.add({'elapsedMs': elapsed.elapsedMilliseconds, ...next});
          }
          clock = next;
        case 'time-pos':
          position = _number(value['value']);
        case 'duration':
          duration = value['value'] == null ? null : _number(value['value']);
        case 'video-params':
          final params = value['value'];
          if (params is Map && params['w'] is int && params['h'] is int) {
            width = params['w'] as int;
            height = params['h'] as int;
          }
      }
    } on PublicClockFailure catch (error) {
      failure = error.code;
    } catch (_) {
      failure = 'event_schema';
    }
  }

  double _number(Object? value) {
    if (value is! num || !value.isFinite || value < 0 || value > 86400) {
      throw const PublicClockFailure('numeric_property');
    }
    return value.toDouble();
  }

  bool get qualified {
    final current = clock;
    if (!playing ||
        width != 1920 ||
        height != 1080 ||
        position == null ||
        current == null) {
      return false;
    }
    if (caseName == 'zero' && seekIssued) {
      return seekPendingObserved &&
          seekReadyObserved &&
          current['state'] == 'ready' &&
          current['adjustmentUs'] == a1Us;
    }
    if (caseName == 'discontinuity') {
      return current['state'] == 'unavailable' &&
          current['reason'] == 'discontinuity';
    }
    return current['state'] == 'ready' &&
        current['adjustmentUs'] == (caseName == 'zero' ? -10500000 : -11250000);
  }

  void beginSeek() {
    if (caseName != 'zero' || seekIssued || !qualified) {
      throw const PublicClockFailure('seek_clock_unqualified');
    }
    a0Us = clock!['adjustmentUs']! as int;
    seekIssued = true;
  }

  void sample() {
    if (!qualified || samples.length >= 40) {
      throw const PublicClockFailure('sample_unqualified');
    }
    samples.add({
      'elapsedMs': elapsed.elapsedMilliseconds,
      'positionSeconds': position!,
      'clockState': clock!['state']!,
      if (clock!['state'] == 'ready') 'adjustmentUs': clock!['adjustmentUs']!,
    });
  }

  Map<String, Object?> status(String state) => {
    'version': 1,
    'case': caseName,
    'nonce': nonce,
    'status': state,
    'failure': failure,
    'eventCount': eventCount,
    'playingObserved': playing,
    'videoWidth': width,
    'videoHeight': height,
    'durationSeconds': duration,
    'clocks': clocks,
    'samples': samples,
    'seekIssued': seekIssued,
    'seekClock': seekIssued
        ? {
            'a0Us': a0Us,
            'a1Us': a1Us,
            'deltaUs': a1Us == null ? null : a1Us! - a0Us!,
            'pendingObserved': seekPendingObserved,
            'readyObserved': seekReadyObserved,
            'readyAdjustmentsUs': readyAdjustmentsUs,
            'clockRebasedObserved': clockRebasedObserved,
          }
        : null,
    'stopConfirmed': stopConfirmed,
    'disposed': disposed,
    'renderedDisplayClaimed': false,
    'accountOrPlexAccess': false,
  };
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: _PublicOverlay()));
  WidgetsBinding.instance.addPostFrameCallback((_) => _run(args));
}

class _PublicOverlay extends StatelessWidget {
  const _PublicOverlay();
  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Colors.transparent,
    body: Align(
      alignment: Alignment.topRight,
      child: Text('Public native session clock contract'),
    ),
  );
}

Future<void> writePublicClockStatus(
  PublicClockRecorder recorder,
  String state,
) async {
  final data = jsonEncode(recorder.status(state));
  if (utf8.encode(data).length > 64 * 1024) {
    throw const PublicClockFailure('status_bound');
  }
  // path_provider uses Context.cacheDir on Android. Flutter's systemTemp is
  // engine-managed code_cache, while the fixed host collector reads cache/.
  final cache = await getTemporaryDirectory();
  final file = File('${cache.path}/$sessionClockStatusName');
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(data, flush: true);
  await temporary.rename(file.path);
}

Future<void> _wait(
  PublicClockRecorder recorder,
  bool Function() condition, {
  bool cleanup = false,
  int seconds = 30,
}) async {
  final until = DateTime.now().add(Duration(seconds: seconds));
  while (!condition()) {
    if (!cleanup && recorder.failure != null) {
      throw PublicClockFailure(recorder.failure!);
    }
    if (DateTime.now().isAfter(until)) {
      throw const PublicClockFailure('readiness_timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<void> _run(List<String> args) async {
  if (!kDebugMode) return;
  final recorder = PublicClockRecorder(
    publicClockCase(args),
    publicClockNonce(args),
  );
  var initialized = false;
  var loadIssued = false;
  Future<Object?> call(String method, [Object? arguments]) => _channel
      .invokeMethod<Object?>(method, arguments)
      .timeout(const Duration(seconds: 12));
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'event') recorder.receive(call.arguments);
  });
  await writePublicClockStatus(recorder, 'running');
  try {
    await call('initialize');
    initialized = true;
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    await call('setVideoRect', {
      'left': 0.0,
      'top': 0.0,
      'width': view.physicalSize.width / view.devicePixelRatio,
      'height': view.physicalSize.height / view.devicePixelRatio,
      'scale': view.devicePixelRatio,
    });
    loadIssued = true;
    await call('load', {
      'uri': 'https://localhost:18443/session/clock-${recorder.caseName}.m3u8',
      'kind': 'plexSession',
      'loadId': 1,
      'startPaused': false,
    });
    await _wait(recorder, () => recorder.qualified);
    final first = recorder.position!;
    for (var i = 0; i < 17; i++) {
      recorder.sample();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (recorder.position! - first < 2) {
      throw const PublicClockFailure('no_progress');
    }
    if (recorder.caseName == 'zero') {
      recorder.beginSeek();
      await call('seek', {'seconds': 6.0, 'mode': 'exact'});
      await _wait(
        recorder,
        () => recorder.qualified && recorder.position! >= 5.5,
      );
      final afterSeek = recorder.position!;
      for (var i = 0; i < 9; i++) {
        recorder.sample();
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (recorder.position! - afterSeek < 1) {
        throw const PublicClockFailure('seek_no_progress');
      }
    }
    if (recorder.failure != null) throw PublicClockFailure(recorder.failure!);
  } on PublicClockFailure catch (error) {
    recorder.failure ??= error.code;
  } catch (_) {
    recorder.failure ??= 'native_command_failed';
  } finally {
    if (loadIssued) {
      try {
        await call('stop', {'stopId': 1});
        await _wait(
          recorder,
          () => recorder.stopSeen,
          cleanup: true,
          seconds: 5,
        );
      } catch (_) {
        recorder.failure ??= 'stop_unconfirmed';
      }
    } else {
      recorder.stopConfirmed = true;
    }
    if (initialized) {
      try {
        await call('dispose');
        recorder.disposed = true;
      } catch (_) {
        recorder.failure ??= 'dispose_unconfirmed';
      }
    } else {
      recorder.disposed = true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await writePublicClockStatus(
      recorder,
      recorder.failure == null ? 'complete' : 'failed',
    );
    _channel.setMethodCallHandler(null);
  }
}
