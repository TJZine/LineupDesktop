import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/platform/device_profile.dart';
import 'package:lineup_desktop/platform/device_profile_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lineup/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<FlutterErrorDetails> errors;
  FlutterExceptionHandler? originalHandler;

  setUp(() {
    errors = [];
    originalHandler = FlutterError.onError;
    FlutterError.onError = errors.add;
  });
  tearDown(() {
    FlutterError.onError = originalHandler;
    messenger.setMockMethodCallHandler(channel, null);
  });

  for (final form in [FormFactor.tv, FormFactor.handheld]) {
    test('resolves Android ${form.name} with a no-argument call', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'deviceProfile');
        expect(call.arguments, isNull);
        return {'formFactor': form.name};
      });
      final profile = await resolveDeviceProfile(host: TargetPlatform.android);
      expect(profile.host, TargetPlatform.android);
      expect(profile.formFactor, form);
      expect(errors, isEmpty);
    });
  }

  test('desktop hosts never invoke the Android channel', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      fail('Android channel called on desktop');
    });
    for (final host in [
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.iOS,
      TargetPlatform.fuchsia,
    ]) {
      expect(
        await resolveDeviceProfile(host: host),
        DeviceProfile.fallbackFor(host),
      );
    }
    expect(errors, isEmpty);
  });

  final malformed = <Object?>[
    null,
    'tv',
    {},
    {'formFactor': 'desktop'},
    {'formFactor': true},
    {'formFactor': null},
  ];
  for (var index = 0; index < malformed.length; index++) {
    test('malformed reply $index reports and falls back to TV', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => malformed[index],
      );
      expect(
        (await resolveDeviceProfile(host: TargetPlatform.android)).isTv,
        isTrue,
      );
      expect(errors.single.exception, isA<FormatException>());
    });
  }

  test('platform exception reports and falls back to TV', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'unavailable');
    });
    expect(
      (await resolveDeviceProfile(host: TargetPlatform.android)).isTv,
      isTrue,
    );
    expect(errors.single.exception, isA<PlatformException>());
  });

  test('timeout reports and falls back to TV', () async {
    final pending = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (_) => pending.future);
    expect(
      (await resolveDeviceProfile(
        host: TargetPlatform.android,
        timeout: const Duration(milliseconds: 10),
      )).isTv,
      isTrue,
    );
    expect(errors.single.exception, isA<TimeoutException>());
    pending.complete({'formFactor': 'handheld'});
  });
}
