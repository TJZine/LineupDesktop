import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/windows_native_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('lineup/native_player');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test(
    'projects bounded native playback facts and completes a loaded file',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'initialize'
            ? <String, Object?>{'clientApiVersion': 131072}
            : null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final player = WindowsNativePlayer();
      addTearDown(player.dispose);
      await player.initialize();
      final load = player.load(
        Uri.parse('https://plex.example/media/sample.mp4'),
        plexToken: 'test-token',
      );
      await Future<void>.delayed(Duration.zero);
      final loadId = calls.last.arguments!['loadId']! as int;
      expect(calls.last.arguments!['plexToken'], 'test-token');

      await _sendNativeEvent(messenger, {
        'type': 'property',
        'loadId': loadId,
        'name': 'current-vo',
        'value': 'gpu-next',
      });
      await _sendNativeEvent(messenger, {
        'type': 'property',
        'loadId': loadId,
        'name': 'hwdec-current',
        'value': 'd3d11va',
      });
      await _sendNativeEvent(messenger, {
        'type': 'property',
        'loadId': loadId,
        'name': 'video-params',
        'value': {
          'w': 1920,
          'h': 1080,
          'pixelformat': 'nv12',
          'hw-pixelformat': 'd3d11',
          'primaries': 'bt.2020',
          'gamma': 'pq',
          'colormatrix': 'bt.2020-ncl',
          'sig-peak': 10.0,
        },
      });
      await _sendNativeEvent(messenger, {
        'type': 'property',
        'loadId': loadId,
        'name': 'track-list',
        'value': [
          {
            'id': 1,
            'type': 'video',
            'title': null,
            'lang': null,
            'codec': 'h264',
            'selected': true,
          },
        ],
      });
      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': loadId,
        'state': 'playing',
        'message': 'Playing',
      });
      await load;

      expect(
        calls.map((call) => call.method),
        containsAll(['initialize', 'load']),
      );
      expect(player.status.state, PlayerState.playing);
      expect(player.telemetry.videoOutput, 'gpu-next');
      expect(player.telemetry.hardwareDecoder, 'd3d11va');
      expect(player.telemetry.isHdr, isTrue);
      expect(player.tracks.single.codec, 'h264');
      expect(player.tracks.single.selected, isTrue);

      await player.dispose();
      await player.initialize();
      expect(calls.where((call) => call.method == 'initialize'), hasLength(2));
    },
  );

  test('dispatches the complete bounded outgoing command contract', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = WindowsNativePlayer();
    addTearDown(player.dispose);
    await player.initialize();
    await player.play();
    await player.pause();
    await player.seek(const Duration(milliseconds: 1250));
    await player.setVideoRect(
      const PlayerVideoRect(
        left: 12,
        top: 34,
        width: 640,
        height: 360,
        scale: 2,
      ),
    );
    await player.setFullscreen(true);
    await player.selectTrack(PlayerTrackType.audio, 7);
    await player.selectTrack(PlayerTrackType.subtitle, null);
    await player.setVolume(42.5);
    await player.stop();

    expect(calls.map((call) => call.method), [
      'initialize',
      'play',
      'pause',
      'seek',
      'setVideoRect',
      'setFullscreen',
      'selectTrack',
      'selectTrack',
      'setVolume',
      'stop',
    ]);
    expect(calls[3].arguments, {'seconds': 1.25});
    expect(calls[4].arguments, {
      'left': 12.0,
      'top': 34.0,
      'width': 640.0,
      'height': 360.0,
      'scale': 2.0,
    });
    expect(calls[5].arguments, {'fullscreen': true});
    expect(calls[6].arguments, {'type': 'audio', 'id': 7});
    expect(calls[7].arguments, {'type': 'subtitle', 'id': null});
    expect(calls[8].arguments, {'volume': 42.5});
  });

  test(
    'normalizes allowlisted native command failures without raw prose',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'play') {
          throw PlatformException(
            code: 'command_queue_full',
            message: 'opaque native queue detail',
          );
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final player = WindowsNativePlayer();
      addTearDown(player.dispose);
      await player.initialize();

      await expectLater(
        player.play(),
        throwsA(
          isA<PlayerUnavailable>()
              .having(
                (error) => error.failureCode,
                'failureCode',
                'command_queue_full',
              )
              .having(
                (error) => error.message,
                'message',
                'The native player is busy. Try again.',
              ),
        ),
      );
    },
  );

  test('authenticated loads require an HTTPS authority in Dart', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = WindowsNativePlayer();
    addTearDown(player.dispose);
    await player.initialize();

    for (final insecure in [
      Uri.parse('http://dev-media.test/video.mp4'),
      Uri.parse('https:opaque-media-path'),
    ]) {
      await expectLater(
        player.load(insecure, plexToken: 'secret-token'),
        throwsA(
          isA<PlayerUnavailable>().having(
            (error) => error.failureCode,
            'failureCode',
            'insecure_media_uri',
          ),
        ),
      );
    }
    expect(calls.where((call) => call.method == 'load'), isEmpty);

    final load = player.load(Uri.parse('http://dev-media.test/video.mp4'));
    await Future<void>.delayed(Duration.zero);
    final loadCall = calls.singleWhere((call) => call.method == 'load');
    final loadId = loadCall.arguments!['loadId']! as int;
    expect(loadCall.arguments!['plexToken'], isNull);
    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': loadId,
      'state': 'playing',
    });
    await load;
  });

  test('projects bounded native failure codes behaviorally', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = WindowsNativePlayer();
    addTearDown(player.dispose);
    await player.initialize();
    const messages = {
      'correlation_error': 'Media load tracking failed',
      'command_error': 'Media player command failed',
      'event_queue_overflow': 'Media player event queue overflowed',
    };

    for (final entry in messages.entries) {
      final load = player.load(Uri.parse('file:///${entry.key}.mp4'));
      await Future<void>.delayed(Duration.zero);
      final loadCall = calls.lastWhere((call) => call.method == 'load');
      final loadId = loadCall.arguments!['loadId']! as int;
      final expectation = expectLater(
        load,
        throwsA(
          isA<PlayerUnavailable>()
              .having((error) => error.failureCode, 'failureCode', entry.key)
              .having((error) => error.message, 'message', entry.value),
        ),
      );

      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': loadId,
        'state': 'error',
        'message': 'raw native detail',
        'failureCode': entry.key,
      });

      await expectation;
      expect(player.status.failureCode, entry.key);
      expect(player.status.message, entry.value);
    }
  });

  test(
    'native load errors preserve retry and coordinator generation',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final player = WindowsNativePlayer();
      addTearDown(player.dispose);
      final events = <PlayerEvent>[];
      final subscription = player.events.listen(events.add);
      addTearDown(subscription.cancel);
      await player.initialize();
      final load = player.load(
        Uri.parse('file:///retryable.mp4'),
        generation: 42,
      );
      await Future<void>.delayed(Duration.zero);
      final loadId = calls.last.arguments!['loadId']! as int;
      final loadExpectation = expectLater(
        load,
        throwsA(isA<PlayerUnavailable>()),
      );
      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': loadId,
        'state': 'error',
        'message': 'Temporary media failure',
      });

      await loadExpectation;
      expect(player.status.recoverable, isTrue);
      expect(
        events.where((event) => event.status.state == PlayerState.error),
        isNotEmpty,
      );
      expect(
        events
            .where((event) => event.status.state == PlayerState.error)
            .every(
              (event) => event.status.recoverable && event.generation == 42,
            ),
        isTrue,
      );
    },
  );

  test(
    'maps structured native failures without exposing native prose',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final player = WindowsNativePlayer();
      addTearDown(player.dispose);
      await player.initialize();
      final load = player.load(Uri.parse('https://plex.example/media'));
      await Future<void>.delayed(Duration.zero);
      final loadId = calls.last.arguments!['loadId']! as int;
      final expectation = expectLater(
        load,
        throwsA(
          isA<PlayerUnavailable>().having(
            (error) => error.message,
            'message',
            'Media server returned HTTP 503',
          ),
        ),
      );

      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': loadId,
        'state': 'error',
        'message': 'raw native detail that must not reach Dart UI',
        'failureCode': 'http_error',
        'httpStatus': 503,
      });

      await expectation;
      expect(player.status.message, 'Media server returned HTTP 503');
      expect(player.status.failureCode, 'http_error');
      expect(player.status.httpStatus, 503);
    },
  );

  test('preserves the bounded libmpv fallback description', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = WindowsNativePlayer();
    addTearDown(player.dispose);
    await player.initialize();
    final load = player.load(Uri.parse('file:///broken.mp4'));
    await Future<void>.delayed(Duration.zero);
    final loadId = calls.last.arguments!['loadId']! as int;
    final expectation = expectLater(load, throwsA(isA<PlayerUnavailable>()));

    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': loadId,
      'state': 'error',
      'message': 'loading failed',
      'failureCode': 'mpv_error',
    });

    await expectation;
    expect(player.status.message, 'loading failed');
    expect(player.status.failureCode, 'mpv_error');
    expect(player.status.httpStatus, isNull);
  });

  test('normalizes unknown native failure codes before projection', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = WindowsNativePlayer();
    addTearDown(player.dispose);
    await player.initialize();
    final load = player.load(Uri.parse('file:///broken.mp4'));
    await Future<void>.delayed(Duration.zero);
    final loadId = calls.last.arguments!['loadId']! as int;
    final expectation = expectLater(
      load,
      throwsA(
        isA<PlayerUnavailable>()
            .having((error) => error.failureCode, 'failureCode', 'native_error')
            .having(
              (error) => error.message,
              'message',
              'Media playback failed',
            ),
      ),
    );

    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': loadId,
      'state': 'error',
      'message': 'opaque native detail',
      'failureCode': 'unbounded_native_extension',
    });

    await expectation;
    expect(player.status.failureCode, 'native_error');
    expect(player.status.message, 'Media playback failed');
  });

  test(
    'ignores stale or unscoped events and clears facts for replacement',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final player = WindowsNativePlayer();
      addTearDown(player.dispose);
      await player.initialize();
      final first = player.load(Uri.parse('file:///one.mp4'));
      await Future<void>.delayed(Duration.zero);
      final firstId = calls.last.arguments!['loadId']! as int;
      await _sendNativeEvent(messenger, {
        'type': 'property',
        'loadId': firstId,
        'name': 'video-codec',
        'value': 'h264',
      });
      final second = player.load(Uri.parse('file:///two.mp4'));
      await expectLater(first, throwsA(isA<PlayerUnavailable>()));
      await Future<void>.delayed(Duration.zero);
      final secondId = calls.last.arguments!['loadId']! as int;

      expect(player.telemetry.videoCodec, isNull);
      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': firstId,
        'state': 'playing',
      });
      await _sendNativeEvent(messenger, {'type': 'state', 'state': 'playing'});
      expect(player.status.state, PlayerState.loading);

      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': secondId,
        'state': 'playing',
      });
      await second;
    },
  );

  test(
    'ignores duplicate terminal events and clears nullable telemetry',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final player = WindowsNativePlayer();
      addTearDown(player.dispose);
      await player.initialize();
      final video = player.load(Uri.parse('file:///video.mp4'));
      await Future<void>.delayed(Duration.zero);
      final videoId = calls.last.arguments!['loadId']! as int;
      await _sendNativeEvent(messenger, {
        'type': 'property',
        'loadId': videoId,
        'name': 'video-codec',
        'value': 'h264',
      });
      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': videoId,
        'state': 'playing',
      });
      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': videoId,
        'state': 'playing',
      });
      await video;

      final audio = player.load(Uri.parse('file:///audio.mp3'));
      final audioFailure = expectLater(
        audio,
        throwsA(isA<PlayerUnavailable>()),
      );
      await Future<void>.delayed(Duration.zero);
      final audioId = calls.last.arguments!['loadId']! as int;
      expect(player.telemetry.videoCodec, isNull);
      await _sendNativeEvent(messenger, {
        'type': 'property',
        'loadId': audioId,
        'name': 'video-codec',
        'value': null,
      });
      expect(player.telemetry.videoCodec, isNull);
      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': audioId,
        'state': 'error',
      });
      await audioFailure;
      await _sendNativeEvent(messenger, {
        'type': 'state',
        'loadId': audioId,
        'state': 'error',
      });
    },
  );

  test(
    'serializes initialize and dispose while initialization is pending',
    () async {
      final initializeResponse = Completer<void>();
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        return call.method == 'initialize' ? initializeResponse.future : null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final player = WindowsNativePlayer();
      addTearDown(player.dispose);
      final initialize = player.initialize();
      final dispose = player.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(calls.map((call) => call.method), ['initialize']);
      initializeResponse.complete();
      await initialize;
      await dispose;
      expect(calls.map((call) => call.method), ['initialize', 'dispose']);
    },
  );

  test(
    'dispose rejects a pending load and late events cannot mutate it',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final player = WindowsNativePlayer();
      addTearDown(player.dispose);
      await player.initialize();
      final load = player.load(Uri.parse('file:///pending.mp4'));
      final loadFailure = expectLater(load, throwsA(isA<PlayerUnavailable>()));
      await Future<void>.delayed(Duration.zero);
      final loadId = calls.last.arguments!['loadId']! as int;
      await player.dispose();
      await loadFailure;
      await _sendNativeEvent(messenger, {
        'type': 'property',
        'loadId': loadId,
        'name': 'video-codec',
        'value': 'late',
      });
      expect(player.telemetry.videoCodec, isNull);
    },
  );

  test('stop retires a pending load before its native reply and ignores late events', () async {
    final calls = <MethodCall>[];
    final stopReply = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return call.method == 'stop' ? stopReply.future : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = WindowsNativePlayer();
    addTearDown(player.dispose);
    await player.initialize();
    var loadSettled = false;
    final load = player
        .load(Uri.parse('file:///pending.mp4'), generation: 7)
        .whenComplete(() => loadSettled = true);
    final loadFailure = expectLater(load, throwsA(isA<PlayerUnavailable>()));
    await Future<void>.delayed(Duration.zero);
    final loadId = calls.last.arguments!['loadId']! as int;
    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': loadId,
      'name': 'video-codec',
      'value': 'h264',
    });
    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': loadId,
      'name': 'time-pos',
      'value': 12,
    });
    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': loadId,
      'name': 'duration',
      'value': 30,
    });
    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': loadId,
      'name': 'track-list',
      'value': [
        {'id': 1, 'type': 'video', 'selected': true},
      ],
    });

    var stopSettled = false;
    final stop = player.stop().whenComplete(() => stopSettled = true);
    await Future<void>.delayed(Duration.zero);

    expect(loadSettled, isTrue);
    expect(stopSettled, isFalse);
    expect(player.status.state, PlayerState.loading);
    expect(player.telemetry.videoCodec, 'h264');
    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': loadId,
      'name': 'video-codec',
      'value': 'late',
    });
    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': loadId,
      'state': 'playing',
    });
    expect(player.telemetry.videoCodec, 'h264');

    stopReply.complete();
    await stop;
    await loadFailure;
    expect(player.status.state, PlayerState.stopped);
    expect(player.status.message, 'Stopped');
    expect(player.position, Duration.zero);
    expect(player.duration, Duration.zero);
    expect(player.telemetry.videoCodec, isNull);
    expect(player.tracks, isEmpty);
  });

  test('late stop reply cannot reset a replacement load', () async {
    final calls = <MethodCall>[];
    final stopReply = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return call.method == 'stop' ? stopReply.future : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = WindowsNativePlayer();
    addTearDown(player.dispose);
    await player.initialize();
    final first = player.load(Uri.parse('file:///first.mp4'), generation: 1);
    await Future<void>.delayed(Duration.zero);
    final firstId = calls.last.arguments!['loadId']! as int;
    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': firstId,
      'state': 'playing',
    });
    await first;

    final stop = player.stop();
    await Future<void>.delayed(Duration.zero);
    final replacement = player.load(
      Uri.parse('file:///replacement.mp4'),
      generation: 2,
    );
    await Future<void>.delayed(Duration.zero);
    final replacementId = calls.last.arguments!['loadId']! as int;
    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': replacementId,
      'name': 'video-codec',
      'value': 'hevc',
    });
    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': replacementId,
      'state': 'playing',
    });
    await replacement;

    stopReply.complete();
    await stop;

    expect(player.status.state, PlayerState.playing);
    expect(player.telemetry.videoCodec, 'hevc');
  });

  test('load invocation failure retires its load id', () async {
    var loadId = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'load') {
        loadId = call.arguments!['loadId']! as int;
        throw PlatformException(code: 'load_failed');
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = WindowsNativePlayer();
    addTearDown(player.dispose);
    await player.initialize();
    await expectLater(
      player.load(Uri.parse('file:///broken.mp4')),
      throwsA(
        isA<PlayerUnavailable>()
            .having(
              (error) => error.failureCode,
              'failureCode',
              'native_command_error',
            )
            .having(
              (error) => error.message,
              'message',
              'The native player command failed.',
            ),
      ),
    );
    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': loadId,
      'state': 'playing',
    });
    expect(player.status.state, PlayerState.error);
  });

  test('load timeout retires its load id', () async {
    var loadId = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'load') loadId = call.arguments!['loadId']! as int;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = WindowsNativePlayer(loadTimeout: Duration.zero);
    addTearDown(player.dispose);
    await player.initialize();
    await expectLater(
      player.load(Uri.parse('file:///timeout.mp4')),
      throwsA(isA<TimeoutException>()),
    );
    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': loadId,
      'name': 'video-codec',
      'value': 'late',
    });
    expect(player.telemetry.videoCodec, isNull);
    expect(player.status.state, PlayerState.error);
  });

  test(
    'replacement observes pending failure before delayed load reply',
    () async {
      final calls = <MethodCall>[];
      final firstReply = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        if (call.method == 'load' &&
            calls.where((item) => item.method == 'load').length == 1) {
          return firstReply.future;
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final uncaught = <Object>[];
      await runZonedGuarded(() async {
        final player = WindowsNativePlayer();
        addTearDown(player.dispose);
        await player.initialize();
        final first = player.load(Uri.parse('file:///first.mp4'));
        final firstFailure = expectLater(
          first,
          throwsA(isA<PlayerUnavailable>()),
        );
        await Future<void>.delayed(Duration.zero);

        final second = player.load(Uri.parse('file:///second.mp4'));
        await Future<void>.delayed(Duration.zero);
        final secondCall = calls.where((call) => call.method == 'load').last;
        await _sendNativeEvent(messenger, {
          'type': 'state',
          'loadId': secondCall.arguments!['loadId']! as int,
          'state': 'playing',
        });
        await second;
        firstReply.complete();
        await firstFailure;
      }, (error, _) => uncaught.add(error));

      expect(uncaught, isEmpty);
    },
  );

  test('null video parameters clear grouped telemetry and HDR', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = WindowsNativePlayer();
    addTearDown(player.dispose);
    await player.initialize();
    final load = player.load(Uri.parse('file:///hdr.mp4'));
    await Future<void>.delayed(Duration.zero);
    final loadId = calls.last.arguments!['loadId']! as int;
    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': loadId,
      'name': 'video-params',
      'value': {
        'w': 3840,
        'h': 2160,
        'pixelformat': 'p010',
        'hw-pixelformat': 'd3d11',
        'primaries': 'bt.2020',
        'gamma': 'pq',
        'colormatrix': 'bt.2020-ncl',
        'sig-peak': 10.0,
      },
    });
    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': loadId,
      'name': 'video-params',
      'value': {'w': 'invalid'},
    });
    expect(player.telemetry.width, 3840);
    expect(player.telemetry.isHdr, isTrue);

    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': loadId,
      'name': 'video-params',
      'value': null,
    });
    expect(player.telemetry.width, isNull);
    expect(player.telemetry.height, isNull);
    expect(player.telemetry.pixelFormat, isNull);
    expect(player.telemetry.hardwarePixelFormat, isNull);
    expect(player.telemetry.primaries, isNull);
    expect(player.telemetry.gamma, isNull);
    expect(player.telemetry.colorMatrix, isNull);
    expect(player.telemetry.signalPeak, isNull);
    expect(player.telemetry.isHdr, isFalse);

    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': loadId,
      'state': 'playing',
    });
    await load;
  });

  test('pause events remain scoped across replacement autoplay', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = WindowsNativePlayer();
    addTearDown(player.dispose);
    await player.initialize();
    final first = player.load(Uri.parse('file:///first.mp4'));
    await Future<void>.delayed(Duration.zero);
    final firstId = calls.last.arguments!['loadId']! as int;
    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': firstId,
      'state': 'playing',
    });
    await first;
    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': firstId,
      'name': 'pause',
      'value': true,
    });
    expect(player.status.state, PlayerState.paused);

    final second = player.load(Uri.parse('file:///second.mp4'));
    await Future<void>.delayed(Duration.zero);
    final secondId = calls.last.arguments!['loadId']! as int;
    expect(player.status.state, PlayerState.loading);
    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': firstId,
      'name': 'pause',
      'value': false,
    });
    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': secondId,
      'name': 'pause',
      'value': true,
    });
    expect(player.status.state, PlayerState.loading);
    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': secondId,
      'state': 'playing',
    });
    await second;
    await _sendNativeEvent(messenger, {
      'type': 'property',
      'loadId': secondId,
      'name': 'pause',
      'value': true,
    });
    expect(player.status.state, PlayerState.paused);
  });

  test('rejects a second platform-channel owner', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final first = WindowsNativePlayer();
    addTearDown(first.dispose);
    final second = WindowsNativePlayer();
    addTearDown(second.dispose);
    await first.initialize();
    await expectLater(second.initialize(), throwsA(isA<PlayerUnavailable>()));
    await first.dispose();
    await second.initialize();
  });
}

Future<void> _sendNativeEvent(
  TestDefaultBinaryMessenger messenger,
  Map<String, Object?> event,
) {
  return messenger.handlePlatformMessage(
    'lineup/native_player',
    const StandardMethodCodec().encodeMethodCall(MethodCall('event', event)),
    null,
  );
}
