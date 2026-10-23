// Emulator-only runtime check. This writes synthetic credentials to the app's
// real storage; never run against a signed-in device. See android-runtime.md.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:lineup_desktop/persistence/app_store.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isAndroid) throw UnsupportedError('Android emulator required.');
  const credentials = KeychainCredentialStore();
  const account = 'lineup-u1-synthetic-account';
  const profile = 'lineup-u1-synthetic-profile';
  final store = await FileAppStore.create();
  final support = await getApplicationSupportDirectory();
  final marker = File('${support.path}/u1-smoke-client-id');
  String status;
  try {
    switch (arguments.single) {
      case 'write':
        // Refuse to overwrite credentials or saved user state.
        if (await credentials.readAccountToken() != null ||
            (await store.load()).state.profileId != null) {
          throw StateError('Use a fresh emulator installation.');
        }
        await credentials.writeAccountToken(account);
        await credentials.writeProfileToken('u1-smoke', profile);
        if (await credentials.readAccountToken() != account ||
            await credentials.readProfileToken('u1-smoke') != profile) {
          throw StateError('Synthetic credential readback failed.');
        }
        await store.save(const PersistedState(profileId: 'u1-smoke'));
        await marker.writeAsString(await store.clientIdentifier());
        status = 'U1_STORAGE_WRITE_PASS';
      case 'verify-and-clear':
        if (await credentials.readAccountToken() != account ||
            await credentials.readProfileToken('u1-smoke') != profile ||
            (await store.load()).state.profileId != 'u1-smoke' ||
            await marker.readAsString() != await store.clientIdentifier()) {
          throw StateError('Persistence across restart/upgrade failed.');
        }
        await credentials.clear();
        if (await credentials.readAccountToken() != null ||
            await credentials.readProfileToken('u1-smoke') != null) {
          throw StateError('Synthetic credential deletion failed.');
        }
        await store.save(PersistedState.empty);
        await marker.delete();
        status = 'U1_STORAGE_RESTART_UPGRADE_DELETE_PASS';
      default:
        throw ArgumentError('Use write or verify-and-clear.');
    }
  } catch (_) {
    status = 'U1_STORAGE_FAIL';
  }
  // Fixed status only: never log stored values or plugin exceptions.
  debugPrint(status);
  runApp(
    MaterialApp(
      home: Scaffold(body: Center(child: Text(status))),
    ),
  );
}
