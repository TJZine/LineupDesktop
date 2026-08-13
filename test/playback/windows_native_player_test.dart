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
      await player.initialize();
      final load = player.load(Uri.file(r'C:\media\sample.mp4'));
      await Future<void>.delayed(Duration.zero);
      final loadId = calls.last.arguments!['loadId']! as int;

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
      await player.dispose();
    },
  );

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
      await player.dispose();
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
      await player.dispose();
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
    await player.initialize();
    await expectLater(
      player.load(Uri.parse('file:///broken.mp4')),
      throwsA(isA<PlatformException>()),
    );
    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': loadId,
      'state': 'playing',
    });
    expect(player.status.state, PlayerState.error);
    await player.dispose();
  });

  test('load timeout retires its load id', () async {
    var loadId = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'load') loadId = call.arguments!['loadId']! as int;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final player = WindowsNativePlayer(loadTimeout: Duration.zero);
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
    await player.dispose();
  });

  test('rejects a second platform-channel owner', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final first = WindowsNativePlayer();
    final second = WindowsNativePlayer();
    await first.initialize();
    await expectLater(second.initialize(), throwsA(isA<PlayerUnavailable>()));
    await first.dispose();
    await second.initialize();
    await second.dispose();
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
