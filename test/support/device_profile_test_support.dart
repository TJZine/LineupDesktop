import 'package:flutter/material.dart';
import 'package:lineup_desktop/platform/device_profile.dart';

export 'package:lineup_desktop/platform/device_profile.dart';

const tvProfile = DeviceProfile(
  host: TargetPlatform.android,
  formFactor: FormFactor.tv,
);

const desktopProfile = DeviceProfile(
  host: TargetPlatform.macOS,
  formFactor: FormFactor.desktop,
);

DeviceProfile profileFor(bool isTv) => isTv ? tvProfile : desktopProfile;

Widget withDeviceProfile({
  required DeviceProfile profile,
  required Widget child,
}) => DeviceProfileScope(profile: profile, child: child);
