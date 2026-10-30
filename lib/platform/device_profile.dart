import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

enum FormFactor { desktop, tv, handheld }

@immutable
final class DeviceProfile {
  const DeviceProfile({required this.host, required this.formFactor});

  final TargetPlatform host;
  final FormFactor formFactor;

  bool get isTv => formFactor == FormFactor.tv;
  bool get isHandheld => formFactor == FormFactor.handheld;

  static DeviceProfile fallbackFor(TargetPlatform host) => DeviceProfile(
    host: host,
    formFactor: host == TargetPlatform.android
        ? FormFactor.tv
        : FormFactor.desktop,
  );

  static DeviceProfile desktopFallbackFor(TargetPlatform host) =>
      DeviceProfile(host: host, formFactor: FormFactor.desktop);

  static DeviceProfile of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DeviceProfileScope>()
          ?.profile ??
      desktopFallbackFor(defaultTargetPlatform);

  @override
  bool operator ==(Object other) =>
      other is DeviceProfile &&
      other.host == host &&
      other.formFactor == formFactor;

  @override
  int get hashCode => Object.hash(host, formFactor);
}

class DeviceProfileScope extends InheritedWidget {
  const DeviceProfileScope({
    required this.profile,
    required super.child,
    super.key,
  });

  final DeviceProfile profile;

  @override
  bool updateShouldNotify(DeviceProfileScope oldWidget) =>
      profile != oldWidget.profile;
}
