import 'dart:ui';

import 'package:flutter/material.dart';

import 'app/lineup_app.dart';
import 'playback/unsupported_native_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  ErrorWidget.builder = (_) => const LineupRuntimeFailure();

  PlatformDispatcher.instance.onError = (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'Lineup Desktop',
      ),
    );
    return true;
  };

  runApp(LineupBootstrap(player: UnsupportedNativePlayer.macos()));
}
