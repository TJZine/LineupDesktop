import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kReleaseMode;
import 'package:flutter/material.dart';

import 'app/lineup_app.dart';
import 'app/lineup_controller.dart';
import 'persistence/app_store.dart';
import 'platform/device_profile.dart';
import 'playback/native_player_factory.dart';
import 'plex/plex_client.dart';

@pragma('vm:entry-point')
void nativeRunnerLifecycleTestMain() {
  runApp(const SizedBox.shrink());
}

void main(List<String> arguments) {
  WidgetsFlutterBinding.ensureInitialized();
  final profile = DeviceProfile.fallbackFor(defaultTargetPlatform);
  configureImageCache(PaintingBinding.instance.imageCache, isTv: profile.isTv);

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
  for (final argument
      in Platform.isAndroid && kReleaseMode ? const <String>[] : arguments) {
    if (argument.startsWith('--media=')) {
      mediaArgument = argument.substring('--media='.length);
      break;
    }
  }
  runApp(
    LineupStartup(
      profile: profile,
      createBootstrap: () async {
        final store = await FileAppStore.create();
        final clientIdentifier = await store.clientIdentifier();
        return LineupBootstrap(
          controller: LineupController(
            store: store,
            credentials: const KeychainCredentialStore(),
            plex: PlexClient(clientIdentifier: clientIdentifier),
          ),
          player: createPlatformNativePlayer(
            isWindows: Platform.isWindows,
            isMacOS: Platform.isMacOS,
            isAndroid: Platform.isAndroid,
          ),
          initialMediaPath: mediaArgument,
        );
      },
    ),
  );
}
