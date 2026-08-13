import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'app/lineup_app.dart';
import 'playback/unsupported_native_player.dart';
import 'playback/windows_native_player.dart';

void main(List<String> arguments) {
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

  String? mediaArgument;
  for (final argument in arguments) {
    if (argument.startsWith('--media=')) {
      mediaArgument = argument.substring('--media='.length);
      break;
    }
  }
  runApp(
    LineupBootstrap(
      player: Platform.isWindows
          ? WindowsNativePlayer()
          : UnsupportedNativePlayer.macos(),
      initialMediaPath: mediaArgument,
    ),
  );
}
