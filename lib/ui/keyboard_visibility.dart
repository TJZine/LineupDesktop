import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Observed OS visibility, independent of keyboard size or text input state.
/// Null means no truthful observation is available (including unsupported OSes).
class PlatformKeyboardVisibility extends ValueNotifier<bool?> {
  PlatformKeyboardVisibility({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('lineup/platform'),
      super(null) {
    // Native may publish its initial fact before the watch acknowledgement.
    _channel.setMethodCallHandler(_handleCall);
    unawaited(_watch());
  }

  final MethodChannel _channel;
  bool _disposed = false;

  Future<void> _watch() async {
    try {
      await _channel.invokeMethod<Object?>('watchKeyboardVisibility');
      // The acknowledgement describes support, never the observed state. In
      // particular, it cannot overwrite a newer callback with hidden/unknown.
    } on MissingPluginException {
      // A host without the observer leaves visibility unknown.
    } on PlatformException {
      // An unavailable optional platform observation must not fail startup.
    }
  }

  Future<void> _handleCall(MethodCall call) async {
    if (_disposed || call.method != 'keyboardVisibilityChanged') return;
    final observed = call.arguments;
    if (observed is bool) value = observed;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _channel.setMethodCallHandler(null);
    unawaited(_unwatch());
    super.dispose();
  }

  Future<void> _unwatch() async {
    try {
      await _channel.invokeMethod<void>('unwatchKeyboardVisibility');
    } on MissingPluginException {
      // Unwatch is also optional and idempotent on older hosts.
    } on PlatformException {
      // Local callback ownership has already been retired.
    }
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
