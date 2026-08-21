import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'app/lineup_app.dart';
import 'app/lineup_controller.dart';
import 'persistence/app_store.dart';
import 'playback/unsupported_native_player.dart';
import 'playback/windows_native_player.dart';
import 'plex/plex_client.dart';

Future<void> main(List<String> arguments) async {
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
  final store = await FileAppStore.create();
  final controller = LineupController(
    store: store,
    credentials: const KeychainCredentialStore(),
    plex: PlexClient(clientIdentifier: await store.clientIdentifier()),
  );
  runApp(
    LineupBootstrap(
      controller: controller,
      player: Platform.isWindows
          ? WindowsNativePlayer()
          : UnsupportedNativePlayer.macos(),
      initialMediaPath: mediaArgument,
    ),
  );
}
