import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/playback/device_captions.dart';
import 'package:lineup_desktop/settings/subtitle_style.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lineup/device_captions');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Map<String, Object?> device({bool enabled = false}) => {
    'enabled': enabled,
    'fontScale': 1.5,
    'foreground': null,
    'background': null,
    'window': null,
    'edgeColor': null,
    'edgeType': null,
    'typeface': null,
  };

  test('unset fields use Standard, enabled does not override explicit style choice', () {
    final captions = DeviceCaptions.tryParse(device())!;
    final appearance = captions.resolve(
      const SubtitleStyle(
        position: SubtitlePosition.higher,
        bold: true,
        textColor: SubtitleColor.red,
      ),
    );
    expect(captions.enabled, isFalse);
    expect(appearance.textColor, 0xffffffff);
    expect(appearance.edgeColor, 0xff000000);
    expect(appearance.backgroundColor, 0);
    expect(appearance.windowColor, 0);
    expect(appearance.edge, SubtitleEdge.outline);
    expect(appearance.font, SubtitleFont.standard);
    expect(appearance.scale, 1.5);
    expect(appearance.raise, .1);
    expect(appearance.bold, isTrue);
  });
  test('all fields map including signed 32-bit and 64-bit ARGB', () {
    for (final edge in SubtitleEdge.values) {
      for (final font in SubtitleFont.values) {
        final appearance = DeviceCaptions.tryParse({
          ...device(),
          'foreground': -65536,
          'background': 0x80123456,
          'window': 0x100ffffff,
          'edgeColor': 0xffabcdef,
          'edgeType': edge.storageKey,
          'typeface': font.storageKey,
        })!.resolve(const SubtitleStyle());
        expect(appearance.textColor, 0xffff0000);
        expect(appearance.backgroundColor, 0x80123456);
        expect(appearance.windowColor, 0x00ffffff);
        expect(appearance.edgeColor, 0xffabcdef);
        expect(appearance.edge, edge);
        expect(appearance.font, font);
      }
    }
    expect(
      DeviceCaptions.tryParse({...device(), 'typeface': 'unknown'})!
          .resolve(const SubtitleStyle())
          .font,
      SubtitleFont.standard,
    );
    for (final invalid in [
      null,
      <String, Object?>{},
      {...device(), 'enabled': 1},
      {...device(), 'fontScale': double.nan},
      {...device(), 'fontScale': 0},
      {...device(), 'foreground': 'red'},
    ]) {
      expect(DeviceCaptions.tryParse(invalid), isNull);
    }
  });
  test('Android read/listen/changed/cancel and late read cannot replace newer change', () async {
    final calls = <String>[];
    final response = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'read' ? response.future : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final client = DeviceCaptionsClient(platform: TargetPlatform.android);
    addTearDown(client.dispose);
    final listening = client.listen();
    await pumpEventQueue(times: 2);
    await _changed(messenger, channel, {
      ...device(enabled: true),
      'fontScale': 2,
    });
    response.complete(device());
    await listening;
    expect(client.value!.enabled, isTrue);
    expect(client.value!.fontScale, 2);
    await client.cancel();
    expect(calls, ['listen', 'read', 'cancel']);
    await _changed(messenger, channel, {...device(), 'fontScale': 3});
    expect(client.value!.fontScale, 2);
  });
  test(
    'desktop never invokes the Android channel; disposed client sends nothing',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return device();
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final client = DeviceCaptionsClient(platform: TargetPlatform.macOS);
      await client.listen();
      expect(await client.read(), isNull);
      await client.cancel();
      client.dispose();
      await client.listen();
      await client.read();
      expect(calls, isEmpty);
    },
  );
}

Future<void> _changed(
  TestDefaultBinaryMessenger messenger,
  MethodChannel channel,
  Object? value,
) async {
  await messenger.handlePlatformMessage(
    channel.name,
    const StandardMethodCodec().encodeMethodCall(MethodCall('changed', value)),
    (_) {},
  );
}
