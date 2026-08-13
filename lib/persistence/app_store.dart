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
    this.selectedServerByProfile = const {},
    this.selectedLibraryIdsByProfileServer = const {},
  });

  final LineupSettings settings;
  final List<Channel> channels;
  final String? currentChannelId;
  final String? profileId;
  final Map<String, String> selectedServerByProfile;
  final Map<String, Map<String, List<String>>>
  selectedLibraryIdsByProfileServer;

  Map<String, Object?> toJson() => {
    'settings': settings.toJson(),
    'channels': channels.map((channel) => channel.toJson()).toList(),
    'currentChannelId': currentChannelId,
    'profileId': profileId,
    'selectedServerByProfile': selectedServerByProfile,
    'selectedLibraryIdsByProfileServer': selectedLibraryIdsByProfileServer,
  };

  factory PersistedState.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('State must be an object.');
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
        selectedServerByProfile: Map<String, String>.from(
          json['selectedServerByProfile'] as Map? ?? const {},
        ),
        selectedLibraryIdsByProfileServer: _librarySelections(
          json['selectedLibraryIdsByProfileServer'],
        ),
      );
    } catch (error) {
      throw FormatException('State contains invalid values.', error);
    }
  }
}

Map<String, Map<String, List<String>>> _librarySelections(Object? value) {
  if (value == null) return const {};
  if (value is! Map) throw const FormatException('Invalid library selections.');
  return {
    for (final profileEntry in value.entries)
      if (profileEntry.key is String && profileEntry.value is Map)
        profileEntry.key as String: {
          for (final serverEntry in (profileEntry.value as Map).entries)
            if (serverEntry.key is String && serverEntry.value is List)
              serverEntry.key as String: (serverEntry.value as List)
                  .whereType<String>()
                  .toList(),
        },
  };
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
    } on PathNotFoundException {
      return const PersistedState();
    } catch (_) {
      await _quarantineState();
      return const PersistedState();
    }
  }

  Future<void> _quarantineState() async {
    if (!await _stateFile.exists()) return;
    final quarantine = File(
      '${_stateFile.path}.corrupt-${DateTime.now().toUtc().millisecondsSinceEpoch}',
    );
    try {
      await _stateFile.rename(quarantine.path);
    } catch (_) {
      // Startup recovery must not fail only because preservation failed.
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
  static const _macosOptions = MacOsOptions(usesDataProtectionKeychain: false);

  @override
  Future<String?> readAccountToken() =>
      storage.read(key: 'plex.account-token', mOptions: _macosOptions);

  @override
  Future<String?> readProfileToken(String profileId) => storage.read(
    key: 'plex.profile-token.$profileId',
    mOptions: _macosOptions,
  );

  @override
  Future<void> writeAccountToken(String token) => storage.write(
    key: 'plex.account-token',
    value: token,
    mOptions: _macosOptions,
  );

  @override
  Future<void> writeProfileToken(String profileId, String token) =>
      storage.write(
        key: 'plex.profile-token.$profileId',
        value: token,
        mOptions: _macosOptions,
      );

  @override
  Future<void> clear() => storage.deleteAll(mOptions: _macosOptions);
}
