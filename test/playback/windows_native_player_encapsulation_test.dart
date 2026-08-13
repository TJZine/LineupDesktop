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

  test('exposes decoded track state as read-only', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'initialize'
          ? <String, Object?>{'clientApiVersion': 131072}
          : null;
    });

    final player = WindowsNativePlayer();
    addTearDown(() async {
      await player.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    });

    await player.initialize();
    final load = player.load(Uri.file(r'C:\media\sample.mp4'));
    await Future<void>.delayed(Duration.zero);
    final loadId = calls.last.arguments!['loadId']! as int;

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

    expect(player.tracks, hasLength(1));
    expect(() => player.tracks.clear(), throwsA(isA<UnsupportedError>()));
    expect(player.tracks, hasLength(1));

    await _sendNativeEvent(messenger, {
      'type': 'state',
      'loadId': loadId,
      'state': 'playing',
      'message': 'Playing',
    });
    await load;
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
