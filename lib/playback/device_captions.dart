import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../settings/subtitle_style.dart';

/// Android's current caption style. This is never persisted in Lineup settings.
@immutable
final class DeviceCaptions {
  const DeviceCaptions({
    required this.enabled,
    required this.fontScale,
    this.foreground,
    this.background,
    this.window,
    this.edgeType,
    this.edgeColor,
    this.typeface,
  });
  final bool enabled;
  final double fontScale;
  final int? foreground;
  final int? background;
  final int? window;
  final SubtitleEdge? edgeType;
  final int? edgeColor;
  final SubtitleFont? typeface;

  static DeviceCaptions? tryParse(Object? value) {
    if (value is! Map || value['enabled'] is! bool) return null;
    final scale = value['fontScale'];
    if (scale is! num || !scale.isFinite || scale <= 0) return null;
    int? color(String key) =>
        value[key] is int ? (value[key] as int) & 0xffffffff : null;
    for (final key in ['foreground', 'background', 'window', 'edgeColor']) {
      if (value[key] != null && value[key] is! int) return null;
    }
    return DeviceCaptions(
      enabled: value['enabled'] as bool,
      fontScale: scale.toDouble(),
      foreground: color('foreground'),
      background: color('background'),
      window: color('window'),
      edgeColor: color('edgeColor'),
      edgeType: SubtitleEdge.values
          .where((v) => v.storageKey == value['edgeType'])
          .firstOrNull,
      typeface: SubtitleFont.values
          .where((v) => v.storageKey == value['typeface'])
          .firstOrNull,
    );
  }

  SubtitleAppearance resolve(SubtitleStyle style) {
    final standard = const SubtitleStyle().resolve();
    return SubtitleAppearance(
      textColor: foreground ?? standard.textColor,
      edgeColor: edgeColor ?? standard.edgeColor,
      backgroundColor: background ?? standard.backgroundColor,
      windowColor: window ?? standard.windowColor,
      edge: edgeType ?? standard.edge,
      font: typeface ?? standard.font,
      bold: style.bold,
      scale: fontScale.isFinite && fontScale > 0
          ? fontScale.clamp(0.25, 4.0)
          : style.size.scale,
      raise: style.position.raise,
    );
  }
}

/// A shared client can be subscribed by the appearance source while in use.
/// Host gating is here as well as in the Settings UI; desktop never calls native.
class DeviceCaptionsClient extends ValueNotifier<DeviceCaptions?> {
  DeviceCaptionsClient({
    TargetPlatform? platform,
    this.channel = const MethodChannel('lineup/device_captions'),
  }) : _platform = platform ?? defaultTargetPlatform,
       super(null);
  final TargetPlatform _platform;
  final MethodChannel channel;
  bool _listening = false;
  bool _disposed = false;
  int _epoch = 0;
  int _revision = 0;

  Future<DeviceCaptions?> read() async {
    if (_disposed || _platform != TargetPlatform.android) return null;
    final epoch = _epoch;
    final revision = _revision;
    try {
      final next = DeviceCaptions.tryParse(
        await channel.invokeMethod<Object?>('read'),
      );
      if (!_disposed &&
          epoch == _epoch &&
          revision == _revision &&
          next != null) {
        value = next;
      }
      return next;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> listen() async {
    if (_disposed || _listening || _platform != TargetPlatform.android) return;
    _listening = true;
    final epoch = ++_epoch;
    channel.setMethodCallHandler((call) async {
      if (_disposed ||
          !_listening ||
          epoch != _epoch ||
          call.method != 'changed') {
        return;
      }
      final next = DeviceCaptions.tryParse(call.arguments);
      if (next != null) {
        ++_revision;
        value = next;
      }
    });
    try {
      await channel.invokeMethod<void>('listen');
      if (!_disposed && _listening && epoch == _epoch) await read();
    } on PlatformException {
      /* Device settings are optional. */
    } on MissingPluginException {
      /* Unsupported host. */
    }
  }

  Future<void> cancel() async {
    if (!_listening) return;
    _listening = false;
    ++_epoch;
    channel.setMethodCallHandler(null);
    if (_platform == TargetPlatform.android) {
      try {
        await channel.invokeMethod<void>('cancel');
      } on PlatformException {
        /* Best effort. */
      } on MissingPluginException {
        /* Unsupported host. */
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(cancel());
    super.dispose();
  }
}
