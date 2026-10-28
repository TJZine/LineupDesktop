import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'device_profile.dart';

/// Called once by the process composition root, before building any widgets.
/// Failure retains the shipped TV behavior and reports through Flutter's handler.
Future<DeviceProfile> resolveDeviceProfile({
  required TargetPlatform host,
  MethodChannel channel = const MethodChannel('lineup/platform'),
  Duration timeout = const Duration(seconds: 2),
}) async {
  if (host != TargetPlatform.android) return DeviceProfile.fallbackFor(host);

  try {
    final reply = await channel
        .invokeMethod<Object?>('deviceProfile')
        .timeout(timeout);
    final formFactor = switch (reply) {
      {'formFactor': 'tv'} => FormFactor.tv,
      {'formFactor': 'handheld'} => FormFactor.handheld,
      _ => throw const FormatException('Invalid Android device profile reply.'),
    };
    return DeviceProfile(host: host, formFactor: formFactor);
  } catch (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'Lineup device profile',
        context: ErrorDescription('while resolving the Android form factor'),
      ),
    );
    return DeviceProfile.fallbackFor(host);
  }
}
