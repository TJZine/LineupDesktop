import 'package:flutter/foundation.dart';

import 'device_profile.dart';

/// Reads the native startup fact before building widgets, without platform IO.
/// Missing or malformed Android arguments retain TV behavior and report an error.
DeviceProfile resolveDeviceProfile({
  required TargetPlatform host,
  required List<String> arguments,
}) {
  if (host != TargetPlatform.android) return DeviceProfile.fallbackFor(host);

  final formArguments = arguments
      .where(
        (argument) =>
            argument == '--form-factor' ||
            argument.startsWith('--form-factor='),
      )
      .toList(growable: false);
  final formFactor = switch (formArguments) {
    ['--form-factor=tv'] => FormFactor.tv,
    ['--form-factor=handheld'] => FormFactor.handheld,
    _ => null,
  };
  if (formFactor != null) {
    return DeviceProfile(host: host, formFactor: formFactor);
  }

  // Never include entrypoint arguments: other flags may carry private media.
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: const FormatException(
        'Missing or invalid Android form-factor argument.',
      ),
      stack: StackTrace.current,
      library: 'Lineup device profile',
      context: ErrorDescription('while reading the Android form factor'),
    ),
  );
  return DeviceProfile.fallbackFor(host);
}
