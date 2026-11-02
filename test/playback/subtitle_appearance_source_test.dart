import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/playback/device_captions.dart';
import 'package:lineup_desktop/playback/subtitle_appearance_source.dart';
import 'package:lineup_desktop/settings/subtitle_style.dart';

import '../support/ui_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lineup/device_captions');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Map<String, Object?> device(double scale, {int? color}) => {
    'enabled': false,
    'fontScale': scale,
    'foreground': color,
  };
  Future<void> changed(Object value) => messenger.handlePlatformMessage(
    channel.name,
    const StandardMethodCodec().encodeMethodCall(MethodCall('changed', value)),
    (_) {},
  );
  test('consumers share subscription; device size ignores enabled and restores saved size', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'read' ? device(2) : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final f = UiFixture();
    final source = SubtitleAppearanceSource(
      lineup: f.controller,
      platform: TargetPlatform.android,
    );
    addTearDown(source.dispose);
    void style(SubtitleStyle value) => f.controller.fixtureActor
        .publishSettings(f.controller.settings.copyWith(subtitleStyle: value));
    style(
      const SubtitleStyle(
        size: SubtitleSize.p150,
        useDeviceStyle: true,
        bold: true,
        position: SubtitlePosition.higher,
      ),
    );
    expect(calls, isEmpty);
    final releaseEngine = source.retain();
    final releasePreview = source.retain();
    expect(source.value.scale, 1.5);
    await pumpEventQueue();
    expect(calls, ['listen', 'read']);
    expect(source.value.scale, 2);
    expect(source.deviceCaptions!.enabled, isFalse);
    expect(source.value.bold, isTrue);
    expect(source.value.raise, .1);
    await changed(device(3, color: 0xff00ffff));
    expect(source.value.scale, 3);
    expect(source.value.textColor, 0xff00ffff);
    releasePreview();
    releasePreview();
    expect(calls, ['listen', 'read']);
    source.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(source.value.scale, 2);
    style(const SubtitleStyle(size: SubtitleSize.p150));
    await pumpEventQueue();
    expect(source.value.scale, 1.5);
    expect(calls, ['listen', 'read', 'read', 'cancel']);
    await changed(device(4));
    expect(source.value.scale, 1.5);
    style(const SubtitleStyle(useDeviceStyle: true));
    await pumpEventQueue();
    releaseEngine();
    await pumpEventQueue();
    expect(calls.where((v) => v == 'listen'), hasLength(2));
    expect(calls.where((v) => v == 'cancel'), hasLength(2));
  });
  test(
    'late initial read cannot publish after toggle off or disposal',
    () async {
      final response = Completer<Object?>();
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'read' ? response.future : null,
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final f = UiFixture();
      f.controller.fixtureActor.publishSettings(
        f.controller.settings.copyWith(
          subtitleStyle: const SubtitleStyle(useDeviceStyle: true),
        ),
      );
      final source = SubtitleAppearanceSource(
        lineup: f.controller,
        platform: TargetPlatform.android,
      );
      source.retain();
      await pumpEventQueue(times: 2);
      var publications = 0;
      source.addListener(() => ++publications);
      source.dispose();
      response.complete(device(3));
      await pumpEventQueue();
      expect(publications, 0);
    },
  );
  test('toggle off rejects an outstanding device read', () async {
    final response = Completer<Object?>();
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'read' ? response.future : null,
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final f = UiFixture();
    f.controller.fixtureActor.publishSettings(
      f.controller.settings.copyWith(
        subtitleStyle: const SubtitleStyle(
          useDeviceStyle: true,
          size: SubtitleSize.p150,
        ),
      ),
    );
    final source = SubtitleAppearanceSource(
      lineup: f.controller,
      platform: TargetPlatform.android,
    );
    addTearDown(source.dispose);
    source.retain();
    await pumpEventQueue(times: 2);
    f.controller.fixtureActor.publishSettings(
      f.controller.settings.copyWith(
        subtitleStyle: const SubtitleStyle(size: SubtitleSize.p150),
      ),
    );
    var latePublications = 0;
    source.addListener(() => ++latePublications);
    response.complete(device(3));
    await pumpEventQueue();
    expect(source.value.scale, 1.5);
    expect(latePublications, 0);
  });
  test('desktop uses saved style and never calls device channel', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return device(2);
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final f = UiFixture();
    f.controller.fixtureActor.publishSettings(
      f.controller.settings.copyWith(
        subtitleStyle: const SubtitleStyle(
          size: SubtitleSize.p300,
          useDeviceStyle: true,
        ),
      ),
    );
    final source = SubtitleAppearanceSource(
      lineup: f.controller,
      platform: TargetPlatform.macOS,
    );
    source.retain();
    source.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(source.value.scale, 3);
    source.dispose();
    expect(calls, isEmpty);
  });
  test('device bounds and invalid direct values share one safe scale', () {
    for (final (input, expected) in [
      (0.01, .25),
      (9.0, 4.0),
      (double.nan, 1.5),
      (-1.0, 1.5),
    ]) {
      expect(
        DeviceCaptions(
          enabled: false,
          fontScale: input,
        ).resolve(const SubtitleStyle(size: SubtitleSize.p150)).scale,
        expected,
      );
    }
  });
}
