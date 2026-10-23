import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _platformChannel = MethodChannel('lineup/platform');
const _plexLinkUrl = 'https://plex.tv/link';

/// Opens only the public linking page; the viewer enters the displayed code.
Future<void> openPlexLink() async {
  if (defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.android) {
    return _openPlexLinkNative();
  }
  final (executable, arguments) = switch (Platform.operatingSystem) {
    'windows' => (
      'rundll32.exe',
      const ['url.dll,FileProtocolHandler', _plexLinkUrl],
    ),
    _ => throw UnsupportedError('Browser linking is unavailable.'),
  };
  final result = await Process.run(executable, arguments).timeout(
    const Duration(seconds: 5),
    onTimeout: () =>
        throw const ProcessException('browser', [], 'Could not open browser.'),
  );
  if (result.exitCode != 0) {
    throw const ProcessException('browser', [], 'Could not open browser.');
  }
}

/// Native code owns the fixed URL on macOS and Android; Dart supplies no URL.
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
