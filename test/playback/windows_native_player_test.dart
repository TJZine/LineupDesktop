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

      await _sendNativeEvent(messenger, const {
        'type': 'property',
        'name': 'current-vo',
        'value': 'gpu-next',
      });
      await _sendNativeEvent(messenger, const {
        'type': 'property',
        'name': 'hwdec-current',
        'value': 'd3d11va',
      });
      await _sendNativeEvent(messenger, const {
        'type': 'property',
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
      await _sendNativeEvent(messenger, const {
        'type': 'property',
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
      await _sendNativeEvent(messenger, const {
        'type': 'state',
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
