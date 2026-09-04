import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'app/lineup_app.dart';
import 'app/lineup_controller.dart';
import 'persistence/app_store.dart';
import 'playback/unsupported_native_player.dart';
import 'playback/windows_native_player.dart';
import 'plex/plex_client.dart';

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
    LineupStartup(
      createBootstrap: () async {
        final store = await FileAppStore.create();
        final clientIdentifier = await store.clientIdentifier();
        return LineupBootstrap(
          controller: LineupController(
            store: store,
            credentials: const KeychainCredentialStore(),
            plex: PlexClient(clientIdentifier: clientIdentifier),
          ),
          player: Platform.isWindows
              ? WindowsNativePlayer()
              : UnsupportedNativePlayer.macos(),
          initialMediaPath: mediaArgument,
        );
      },
    ),
  );
}
