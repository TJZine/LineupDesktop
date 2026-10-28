import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/platform/device_profile.dart';

void main() {
  testWidgets('scope absence keeps Android widget composition desktop', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      DeviceProfile? observed;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              observed = DeviceProfile.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(
        observed,
        const DeviceProfile(
          host: TargetPlatform.android,
          formFactor: FormFactor.desktop,
        ),
      );
      expect(DeviceProfile.fallbackFor(TargetPlatform.android).isTv, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('equal profiles do not notify inherited dependents', (
    tester,
  ) async {
    var builds = 0;
    final child = Builder(
      builder: (context) {
        DeviceProfile.of(context);
        builds++;
        return const SizedBox.shrink();
      },
    );

    await tester.pumpWidget(
      const DeviceProfileScope(
        profile: DeviceProfile(
          host: TargetPlatform.macOS,
          formFactor: FormFactor.desktop,
        ),
        child: SizedBox.shrink(),
      ),
    );
    await tester.pumpWidget(
      DeviceProfileScope(
        profile: const DeviceProfile(
          host: TargetPlatform.macOS,
          formFactor: FormFactor.desktop,
        ),
        child: child,
      ),
    );
    expect(builds, 1);

    await tester.pumpWidget(
      DeviceProfileScope(
        profile: const DeviceProfile(
          host: TargetPlatform.android,
          formFactor: FormFactor.tv,
        ),
        child: child,
      ),
    );
    expect(builds, 2);
  });
}
