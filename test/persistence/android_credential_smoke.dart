// Real-backend check for a disposable Android installation or Windows user/VM.
// Never run against signed-in data. See the platform runtime documents.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:lineup_desktop/persistence/app_store.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isAndroid && !Platform.isWindows) {
    throw UnsupportedError(
      'Disposable Android or Windows installation required.',
    );
  }
  const credentials = KeychainCredentialStore();
  const account = 'lineup-u1-synthetic-account';
  const profileId = 'u1-smoke';
  const profile = 'lineup-u1-synthetic-profile';
  const otherId = 'u1-smoke-other';
  const other = 'lineup-u1-synthetic-other';
  final store = await FileAppStore.create();
  final support = await getApplicationSupportDirectory();
  final marker = File('${support.path}/u1-smoke-client-id');

  Future<void> verify({required bool profilePresent}) async {
    if (await credentials.readAccountToken() != account ||
        await credentials.readProfileToken(profileId) !=
            (profilePresent ? profile : null) ||
        await credentials.readProfileToken(otherId) != other ||
        (await store.load()).state.profileId != profileId ||
        await marker.readAsString() != await store.clientIdentifier()) {
      throw StateError('Synthetic storage verification failed.');
    }
  }

  String status;
  try {
    switch (arguments.single) {
      case 'write':
        if (await credentials.readAccountToken() != null ||
            await credentials.readProfileToken(profileId) != null ||
            await credentials.readProfileToken(otherId) != null ||
            await marker.exists() ||
            jsonEncode((await store.load()).state.toJson()) !=
                jsonEncode(PersistedState.empty.toJson())) {
          throw StateError('Use a fresh disposable installation.');
        }
        await credentials.writeAccountToken(account);
        await credentials.writeProfileToken(profileId, profile);
        await credentials.writeProfileToken(otherId, other);
        final previous = await credentials.readProfileToken(profileId);
        if (previous != profile) throw StateError('Synthetic read failed.');
        await credentials.writeProfileToken(profileId, 'synthetic-candidate');
        if (await credentials.readProfileToken(profileId) !=
            'synthetic-candidate') {
          throw StateError('Synthetic replacement readback failed.');
        }
        await credentials.writeProfileToken(profileId, previous!);
        await store.save(const PersistedState(profileId: profileId));
        await marker.writeAsString(await store.clientIdentifier());
        await verify(profilePresent: true);
        status = 'U1_STORAGE_WRITE_PASS';
      case 'verify-and-delete':
        await verify(profilePresent: true);
        await credentials.deleteProfileToken(profileId);
        await verify(profilePresent: false);
        status = 'U1_STORAGE_RESTART_EXACT_DELETE_PASS';
      case 'verify-and-clear':
        await verify(profilePresent: false);
        await credentials.clear();
        if (await credentials.readAccountToken() != null ||
            await credentials.readProfileToken(profileId) != null ||
            await credentials.readProfileToken(otherId) != null) {
          throw StateError('Synthetic credential cleanup failed.');
        }
        await store.save(PersistedState.empty);
        await marker.delete();
        status = 'U1_STORAGE_RESTART_UPGRADE_DELETE_PASS';
      default:
        throw ArgumentError(
          'Use write, verify-and-delete or verify-and-clear.',
        );
    }
  } catch (_) {
    status = 'U1_STORAGE_FAIL';
  }
  // Fixed status only. Never log stored values or plugin exceptions.
  debugPrint(status);
  runApp(
    MaterialApp(
      home: Scaffold(body: Center(child: Text(status))),
    ),
  );
}
