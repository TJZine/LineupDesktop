import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _platformChannel = MethodChannel('lineup/platform');

/// Opens only the public linking page; the viewer enters the displayed code.
Future<void> openPlexLink() async {
  if (defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.android) {
    return _openPlexLinkNative();
  }
  throw UnsupportedError('Browser linking is unavailable.');
}

/// Native code owns the fixed URL on Windows, macOS and Android; Dart supplies no URL.
Future<void> _openPlexLinkNative() async {
  final bool opened;
  try {
    opened =
        await _platformChannel
            .invokeMethod<bool>('openPlexLink')
            .timeout(const Duration(seconds: 5)) ??
        false;
  } on Object {
    throw const ProcessException('browser', [], 'Could not open browser.');
  }
  if (!opened) {
    throw const ProcessException('browser', [], 'Could not open browser.');
  }
}
