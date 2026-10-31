import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../app/lineup_controller.dart';
import '../settings/subtitle_style.dart';
import 'device_captions.dart';

/// Controller-scoped appearance shared by engine presentation, Player and preview.
/// Consumers retain explicitly; the coordinator retains even without text cues.
class SubtitleAppearanceSource extends ChangeNotifier
    with WidgetsBindingObserver
    implements ValueListenable<SubtitleAppearance> {
  /// Owns the supplied client as well as one created here. Reuse this source
  /// from the coordinator; Player and Settings must not create their own.
  SubtitleAppearanceSource({
    required this.lineup,
    DeviceCaptionsClient? deviceCaptions,
    TargetPlatform? platform,
  }) : _platform = platform ?? defaultTargetPlatform,
       _device = deviceCaptions ?? DeviceCaptionsClient(platform: platform) {
    lineup.addListener(_changed);
    _device.addListener(_changed);
    _value = lineup.settings.subtitleStyle.resolve();
  }

  final LineupController lineup;
  final TargetPlatform _platform;
  final DeviceCaptionsClient _device;
  late SubtitleAppearance _value;
  int _consumers = 0;
  bool _disposed = false;
  bool _usingDevice = false;

  @override
  SubtitleAppearance get value => _value;

  /// Read-only OS switch/style status for Settings helper copy; no extra read.
  DeviceCaptions? get deviceCaptions => _device.value;

  /// Returns an idempotent release callback. No widget owns the shared client.
  VoidCallback retain() {
    assert(!_disposed);
    ++_consumers;
    _changed();
    var released = false;
    return () {
      if (released || _disposed) return;
      released = true;
      --_consumers;
      _changed();
    };
  }

  void _changed() {
    if (_disposed) return;
    final style = lineup.settings.subtitleStyle;
    final useDevice =
        _platform == TargetPlatform.android &&
        _consumers > 0 &&
        style.useDeviceStyle;
    if (useDevice != _usingDevice) {
      _usingDevice = useDevice;
      if (useDevice) {
        WidgetsBinding.instance.addObserver(this);
        unawaited(_device.listen());
      } else {
        WidgetsBinding.instance.removeObserver(this);
        unawaited(_device.cancel());
      }
    }
    // A safe saved-style fallback is shared by painting and native until read.
    _value = useDevice && _device.value != null
        ? _device.value!.resolve(style)
        : style.resolve();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_disposed && _usingDevice && state == AppLifecycleState.resumed) {
      unawaited(_device.read());
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    lineup.removeListener(_changed);
    _device.removeListener(_changed);
    if (_usingDevice) WidgetsBinding.instance.removeObserver(this);
    _device.dispose();
    super.dispose();
  }
}
