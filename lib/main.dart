import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kDebugMode, kReleaseMode, debugPrint;
import 'package:flutter/material.dart';

import 'app/lineup_app.dart';
import 'app/lineup_controller.dart';
import 'persistence/app_store.dart';
import 'platform/device_profile_resolver.dart';
import 'playback/native_player_factory.dart';
import 'plex/plex_client.dart';

@pragma('vm:entry-point')
void nativeRunnerLifecycleTestMain() {
  runApp(const SizedBox.shrink());
}

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

  final profile = await resolveDeviceProfile(host: defaultTargetPlatform);
  if (kDebugMode) {
    debugPrint('Lineup device profile: ${profile.formFactor.name}');
  }
  configureImageCache(PaintingBinding.instance.imageCache, isTv: profile.isTv);

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
          profile: profile,
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
