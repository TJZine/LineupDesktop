import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../platform/platform_events.dart';

/// Observed OS visibility, independent of keyboard size or text input state.
/// Null means no truthful observation is available (including unsupported OSes).
class PlatformKeyboardVisibility extends ValueNotifier<bool?> {
  PlatformKeyboardVisibility({MethodChannel? channel}) : super(null) {
    _unsubscribe = PlatformEvents(channel: channel).subscribe(
      event: 'keyboardVisibilityChanged',
      watch: 'watchKeyboardVisibility',
      unwatch: 'unwatchKeyboardVisibility',
      accepts: (observed) => observed is bool,
      onEvent: (observed) {
        if (!_disposed && observed is bool) value = observed;
      },
    );
  }

  late final VoidCallback _unsubscribe;
  bool _disposed = false;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _unsubscribe();
    super.dispose();
  }
}

/// One app-owned source above the Navigator, shared by fields and overlays.
/// Injection keeps platform transport out of individual fields and fixtures.
class KeyboardVisibilityScope extends InheritedWidget {
  const KeyboardVisibilityScope({
    required this.visibility,
    required super.child,
    super.key,
  });

  final ValueListenable<bool?> visibility;

  static ValueListenable<bool?>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<KeyboardVisibilityScope>()
      ?.visibility;

  @override
  bool updateShouldNotify(KeyboardVisibilityScope oldWidget) =>
      !identical(visibility, oldWidget.visibility);
}
