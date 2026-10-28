import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/platform/device_profile.dart';
import 'package:lineup_desktop/platform/device_profile_resolver.dart';

void main() {
  late List<FlutterErrorDetails> errors;
  FlutterExceptionHandler? originalHandler;

  setUp(() {
    errors = [];
    originalHandler = FlutterError.onError;
    FlutterError.onError = errors.add;
  });
  tearDown(() {
    FlutterError.onError = originalHandler;
  });

  for (final form in [FormFactor.tv, FormFactor.handheld]) {
    test('reads Android ${form.name} synchronously', () {
      final profile = resolveDeviceProfile(
        host: TargetPlatform.android,
        arguments: ['--form-factor=${form.name}'],
      );
      expect(profile.host, TargetPlatform.android);
      expect(profile.formFactor, form);
      expect(errors, isEmpty);
    });
  }

  test('other entrypoint arguments do not affect the native fact', () {
    final profile = resolveDeviceProfile(
      host: TargetPlatform.android,
      arguments: [
        '--media=lineup-test://synthetic',
        '--form-factor=handheld',
        '--case=product',
      ],
    );
    expect(profile.isHandheld, isTrue);
    expect(errors, isEmpty);
  });

  test(
    'non-Android hosts retain desktop without requiring native arguments',
    () {
      for (final host in TargetPlatform.values.where(
        (host) => host != TargetPlatform.android,
      )) {
        for (final arguments in [
          <String>[],
          ['--form-factor=invalid'],
          ['--form-factor=tv'],
        ]) {
          expect(
            resolveDeviceProfile(host: host, arguments: arguments),
            DeviceProfile.fallbackFor(host),
          );
        }
      }
      expect(errors, isEmpty);
    },
  );

  final malformed = [
    <String>[],
    ['--form-factor'],
    ['--form-factor='],
    ['--form-factor=desktop'],
    ['--form-factor=TV'],
    ['--form-factor=handheld '],
    ['--form-factor=tv', '--form-factor=handheld'],
    ['--form-factor=handheld', '--form-factor=handheld'],
    ['--form-factor=handheld', '--form-factor'],
  ];
  for (var index = 0; index < malformed.length; index++) {
    test(
      'missing or malformed arguments $index report and fall back to TV',
      () {
        expect(
          resolveDeviceProfile(
            host: TargetPlatform.android,
            arguments: malformed[index],
          ).isTv,
          isTrue,
        );
        expect(errors.single.exception, isA<FormatException>());
      },
    );
  }

  test('failure reporting does not expose entrypoint arguments', () {
    const privateSentinel = 'private-argument-sentinel';
    resolveDeviceProfile(
      host: TargetPlatform.android,
      arguments: [
        '--form-factor=$privateSentinel',
        '--media=lineup-test://$privateSentinel',
      ],
    );
    expect(errors, hasLength(1));
    expect(errors.single.toString(), isNot(contains(privateSentinel)));
  });
}
