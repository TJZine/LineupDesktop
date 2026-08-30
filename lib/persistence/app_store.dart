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
    this.profileId,
    this.selectedServerByProfile = const {},
    this.selectedLibraryIdsByProfileServer = const {},
    this.channelsByProfileServer = const {},
    this.currentChannelByProfileServer = const {},
  });

  final LineupSettings settings;
  final String? profileId;
  final Map<String, String> selectedServerByProfile;
  final Map<String, Map<String, List<String>>>
  selectedLibraryIdsByProfileServer;
  final Map<String, Map<String, List<Channel>>> channelsByProfileServer;
  final Map<String, Map<String, String>> currentChannelByProfileServer;

  Map<String, Object?> toJson() => {
    'settings': settings.toJson(),
    'profileId': profileId,
    'selectedServerByProfile': selectedServerByProfile,
    'selectedLibraryIdsByProfileServer': selectedLibraryIdsByProfileServer,
    'channelsByProfileServer': {
      for (final profile in channelsByProfileServer.entries)
        profile.key: {
          for (final server in profile.value.entries)
            server.key: server.value
                .map((channel) => channel.toJson())
                .toList(),
        },
    },
    'currentChannelByProfileServer': currentChannelByProfileServer,
  };

  factory PersistedState.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('State must be an object.');
    try {
      final json = _stringKeyedMap(value);
      const fields = {
        'settings',
        'profileId',
        'selectedServerByProfile',
        'selectedLibraryIdsByProfileServer',
        'channelsByProfileServer',
        'currentChannelByProfileServer',
      };
      if (json.keys.toSet().difference(fields).isNotEmpty ||
          !json.keys.toSet().containsAll(fields)) {
        throw const FormatException('State fields are not canonical.');
      }
      final settings = json['settings'];
      final profileId = json['profileId'];
      if (settings is! Map || (profileId != null && profileId is! String)) {
        throw const FormatException('Invalid settings or profile.');
      }
      return PersistedState(
        settings: LineupSettings.fromJson(settings),
        profileId: profileId as String?,
        selectedServerByProfile: _flatStringMap(
          json['selectedServerByProfile'],
        ),
        selectedLibraryIdsByProfileServer: _librarySelections(
          json['selectedLibraryIdsByProfileServer'],
        ),
        channelsByProfileServer: _channelSelections(
          json['channelsByProfileServer'],
        ),
        currentChannelByProfileServer: _stringSelections(
          json['currentChannelByProfileServer'],
        ),
      );
    } catch (error) {
      throw FormatException('State contains invalid values.', error);
    }
  }
}

Map<String, Object?> _stringKeyedMap(Object? value) =>
    Map<String, Object?>.from(value as Map);

Map<String, String> _flatStringMap(Object? value) =>
    Map<String, String>.from(value as Map);

Map<String, Map<String, List<Channel>>> _channelSelections(Object? value) {
  final outer = _stringKeyedMap(value);
  final selections = <String, Map<String, List<Channel>>>{};
  for (final profile in outer.entries) {
    final inner = _stringKeyedMap(profile.value);
    selections[profile.key] = {
      for (final server in inner.entries)
        server.key: server.value is List
            ? (server.value as List).map(Channel.fromJson).toList()
            : throw const FormatException('Invalid channel list.'),
    };
  }
  for (final profile in selections.values) {
    for (final channels in profile.values) {
      validateChannels(channels);
    }
  }
  return selections;
}

Map<String, Map<String, String>> _stringSelections(Object? value) {
  final outer = _stringKeyedMap(value);
  return {
    for (final profile in outer.entries)
      profile.key: _flatStringMap(profile.value),
  };
}

Map<String, Map<String, List<String>>> _librarySelections(Object? value) {
  final outer = _stringKeyedMap(value);
  final selections = <String, Map<String, List<String>>>{};
  for (final profile in outer.entries) {
    final inner = _stringKeyedMap(profile.value);
    selections[profile.key] = {
      for (final server in inner.entries)
        server.key:
            server.value is List &&
                (server.value as List).every((item) => item is String)
            ? List<String>.from(server.value as List)
            : throw const FormatException('Invalid library list.'),
    };
  }
  return selections;
}

abstract interface class AppStore {
  Future<AppStoreLoadResult> load();
  Future<void> save(PersistedState state);
  Future<String> clientIdentifier();
}

class AppStoreLoadResult {
  const AppStoreLoadResult(this.state, {this.recoveredCorruptState = false});

  final PersistedState state;
  final bool recoveredCorruptState;
}

class FileAppStore implements AppStore {
  FileAppStore(this.directory, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Directory directory;
  final DateTime Function() _clock;
  Future<void> _writes = Future.value();

  static Future<FileAppStore> create() async => FileAppStore(
    Directory(
      '${(await getApplicationSupportDirectory()).path}/Lineup Desktop',
    ),
  );

  File get _stateFile => File('${directory.path}/state.json');
  File get _identityFile => File('${directory.path}/plex-client-identity');

  @override
  Future<AppStoreLoadResult> load() async {
    late final String contents;
    try {
      contents = await _stateFile.readAsString();
    } on PathNotFoundException {
      return const AppStoreLoadResult(PersistedState());
    }
    try {
      final decoded = jsonDecode(contents);
      final state = PersistedState.fromJson(decoded);
      if (_hasNoncanonicalArtwork(decoded)) await save(state);
      return AppStoreLoadResult(state);
    } on FormatException {
      await _quarantineState();
      return const AppStoreLoadResult(
        PersistedState(),
        recoveredCorruptState: true,
      );
    }
  }

  Future<void> _quarantineState() async {
    final quarantine = File(
      '${_stateFile.path}.corrupt-${_clock().toUtc().millisecondsSinceEpoch}',
    );
    await _stateFile.rename(quarantine.path);
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

bool _hasNoncanonicalArtwork(Object? decoded) {
  if (decoded is! Map) return false;
  final profiles = decoded['channelsByProfileServer'];
  if (profiles is! Map) return false;
  for (final servers in profiles.values) {
    if (servers is! Map) continue;
    for (final channels in servers.values) {
      if (channels is! List) continue;
      for (final channel in channels) {
        if (channel is Map &&
            _sourceHasNoncanonicalArtwork(channel['source'])) {
          return true;
        }
      }
    }
  }
  return false;
}

bool _sourceHasNoncanonicalArtwork(Object? raw) {
  if (raw is! Map) return false;
  switch (raw['type']) {
    case 'manual':
      final items = raw['items'];
      return items is List && items.any(_itemHasNoncanonicalArtwork);
    case 'mixed':
      final sources = raw['sources'];
      return sources is List && sources.any(_sourceHasNoncanonicalArtwork);
    default:
      return false;
  }
}

bool _itemHasNoncanonicalArtwork(Object? raw) {
  if (raw is! Map) return false;
  for (final field in const ['showThumb', 'poster', 'backdrop', 'clearLogo']) {
    if (raw[field] case final String value) {
      if (canonicalPlexArtworkPathText(value) != value) return true;
    }
  }
  final cast = raw['cast'];
  if (cast is List) {
    for (final member in cast) {
      if (member is Map) {
        if (member['portrait'] case final String value) {
          if (canonicalPlexArtworkPathText(value) != value) return true;
        }
      }
    }
  }
  return false;
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
