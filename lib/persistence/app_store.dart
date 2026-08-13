import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../channels/channel.dart';
import '../settings/lineup_settings.dart';

class PersistedState {
  const PersistedState({
    this.settings = const LineupSettings(),
    this.channels = const [],
    this.currentChannelId,
    this.profileId,
    this.profileName,
    this.selectedServerByProfile = const {},
    this.selectedLibraryIds = const [],
  });

  final LineupSettings settings;
  final List<Channel> channels;
  final String? currentChannelId;
  final String? profileId;
  final String? profileName;
  final Map<String, String> selectedServerByProfile;
  final List<String> selectedLibraryIds;

  Map<String, Object?> toJson() => {
    'settings': settings.toJson(),
    'channels': channels.map((channel) => channel.toJson()).toList(),
    'currentChannelId': currentChannelId,
    'profileId': profileId,
    'profileName': profileName,
    'selectedServerByProfile': selectedServerByProfile,
    'selectedLibraryIds': selectedLibraryIds,
  };

  factory PersistedState.fromJson(Object? value) {
    if (value is! Map) return const PersistedState();
    final json = Map<String, Object?>.from(value);
    try {
      final channels = (json['channels'] as List? ?? const [])
          .map(Channel.fromJson)
          .toList();
      for (final channel in channels) {
        channel.validate(channels);
      }
      return PersistedState(
        settings: LineupSettings.fromJson(json['settings']),
        channels: channels,
        currentChannelId: json['currentChannelId'] as String?,
        profileId: json['profileId'] as String?,
        profileName: json['profileName'] as String?,
        selectedServerByProfile: Map<String, String>.from(
          json['selectedServerByProfile'] as Map? ?? const {},
        ),
        selectedLibraryIds: (json['selectedLibraryIds'] as List? ?? const [])
            .whereType<String>()
            .toList(),
      );
    } catch (_) {
      return const PersistedState();
    }
  }
}

abstract interface class AppStore {
  Future<PersistedState> load();
  Future<void> save(PersistedState state);
  Future<String> clientIdentifier();
}

class FileAppStore implements AppStore {
  FileAppStore(this.directory);

  final Directory directory;
  Future<void> _writes = Future.value();

  static Future<FileAppStore> create() async => FileAppStore(
    Directory(
      '${(await getApplicationSupportDirectory()).path}/Lineup Desktop',
    ),
  );

  File get _stateFile => File('${directory.path}/state.json');
  File get _identityFile => File('${directory.path}/plex-client-identity');

  @override
  Future<PersistedState> load() async {
    try {
      return PersistedState.fromJson(
        jsonDecode(await _stateFile.readAsString()),
      );
    } catch (_) {
      return const PersistedState();
    }
  }

  @override
  Future<void> save(PersistedState state) {
    final next = _writes.then(
      (_) => _atomicWrite(_stateFile, '${jsonEncode(state.toJson())}\n'),
    );
    _writes = next.catchError((_) {});
    return next;
  }

  @override
  Future<String> clientIdentifier() async {
    try {
      final existing = (await _identityFile.readAsString()).trim();
      if (RegExp(r'^lineup-desktop-[a-z]+-[A-Za-z0-9_-]{20,}$')
          .hasMatch(existing)) {
        return existing;
      }
    } catch (_) {}
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    final id =
        'lineup-desktop-${Platform.operatingSystem}-${base64Url.encode(bytes).replaceAll('=', '')}';
    await _atomicWrite(_identityFile, '$id\n');
    return id;
  }

  Future<void> _atomicWrite(File target, String contents) async {
    await directory.create(recursive: true);
    final temporary = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporary.writeAsString(contents, flush: true);
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}

abstract interface class CredentialStore {
  Future<String?> readAccountToken();
  Future<String?> readProfileToken(String profileId);
  Future<void> writeAccountToken(String token);
  Future<void> writeProfileToken(String profileId, String token);
  Future<void> clear();
}

class KeychainCredentialStore implements CredentialStore {
  const KeychainCredentialStore([this.storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage storage;

  @override
  Future<String?> readAccountToken() => storage.read(key: 'plex.account-token');

  @override
  Future<String?> readProfileToken(String profileId) =>
      storage.read(key: 'plex.profile-token.$profileId');

  @override
  Future<void> writeAccountToken(String token) =>
      storage.write(key: 'plex.account-token', value: token);

  @override
  Future<void> writeProfileToken(String profileId, String token) =>
      storage.write(key: 'plex.profile-token.$profileId', value: token);

  @override
  Future<void> clear() => storage.deleteAll();
}
