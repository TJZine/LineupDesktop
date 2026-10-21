import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../channels/channel.dart';
import '../settings/lineup_settings.dart';

@immutable
class LineupScope {
  const LineupScope({required this.profileKey, required this.serverId});

  final String profileKey;
  final String serverId;
}

@immutable
class ScopedLineup {
  ScopedLineup({
    required Set<String> libraryIds,
    required List<Channel> channels,
    required this.currentChannelId,
  }) : libraryIds = Set.unmodifiable(libraryIds),
       channels = List.unmodifiable(
         channels.map((channel) => channel.immutableCopy()),
       );

  // Only derivations of this value may reuse its already frozen collections.
  const ScopedLineup._owned({
    required this.libraryIds,
    required this.channels,
    required this.currentChannelId,
  });

  static const empty = ScopedLineup._owned(
    libraryIds: {},
    channels: [],
    currentChannelId: null,
  );

  ScopedLineup withLibraryIds(Set<String> value) => ScopedLineup._owned(
    libraryIds: Set.unmodifiable(value),
    channels: channels,
    currentChannelId: currentChannelId,
  );

  ScopedLineup withCurrentChannel(String? value) => ScopedLineup._owned(
    libraryIds: libraryIds,
    channels: channels,
    currentChannelId: value,
  );

  final Set<String> libraryIds;
  final List<Channel> channels;
  final String? currentChannelId;
}

class PersistedState {
  static const empty = PersistedState();

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

  ScopedLineup lineupFor(LineupScope scope) => ScopedLineup(
    libraryIds:
        (selectedLibraryIdsByProfileServer[scope.profileKey]?[scope.serverId] ??
                const <String>[])
            .toSet(),
    channels:
        channelsByProfileServer[scope.profileKey]?[scope.serverId] ?? const [],
    currentChannelId:
        currentChannelByProfileServer[scope.profileKey]?[scope.serverId],
  );

  PersistedState withLineup(LineupScope scope, ScopedLineup lineup) {
    final libraries = {
      for (final profile in selectedLibraryIdsByProfileServer.entries)
        profile.key: {
          for (final server in profile.value.entries)
            server.key: List<String>.of(server.value),
        },
    };
    final channels = {
      for (final profile in channelsByProfileServer.entries)
        profile.key: {
          for (final server in profile.value.entries)
            server.key: List<Channel>.of(server.value),
        },
    };
    final current = {
      for (final profile in currentChannelByProfileServer.entries)
        profile.key: Map<String, String>.of(profile.value),
    };
    libraries.putIfAbsent(scope.profileKey, () => {})[scope.serverId] = lineup
        .libraryIds
        .toList();
    channels.putIfAbsent(scope.profileKey, () => {})[scope.serverId] = lineup
        .channels
        .toList();
    final currentId = lineup.currentChannelId;
    if (currentId == null) {
      current[scope.profileKey]?.remove(scope.serverId);
    } else {
      current.putIfAbsent(scope.profileKey, () => {})[scope.serverId] =
          currentId;
    }
    return PersistedState(
      settings: settings,
      profileId: profileId,
      selectedServerByProfile: {
        ...selectedServerByProfile,
        scope.profileKey: scope.serverId,
      },
      selectedLibraryIdsByProfileServer: libraries,
      channelsByProfileServer: channels,
      currentChannelByProfileServer: current,
    );
  }

  PersistedState withSettings(LineupSettings value) => PersistedState(
    settings: value,
    profileId: profileId,
    selectedServerByProfile: selectedServerByProfile,
    selectedLibraryIdsByProfileServer: selectedLibraryIdsByProfileServer,
    channelsByProfileServer: channelsByProfileServer,
    currentChannelByProfileServer: currentChannelByProfileServer,
  );

  PersistedState withProfile(String? value) => PersistedState(
    settings: settings,
    profileId: value,
    selectedServerByProfile: selectedServerByProfile,
    selectedLibraryIdsByProfileServer: selectedLibraryIdsByProfileServer,
    channelsByProfileServer: channelsByProfileServer,
    currentChannelByProfileServer: currentChannelByProfileServer,
  );

  PersistedState withoutSelectedServer(String profileKey) => PersistedState(
    settings: settings,
    profileId: profileId,
    selectedServerByProfile: Map.of(selectedServerByProfile)
      ..remove(profileKey),
    selectedLibraryIdsByProfileServer: selectedLibraryIdsByProfileServer,
    channelsByProfileServer: channelsByProfileServer,
    currentChannelByProfileServer: currentChannelByProfileServer,
  );

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

class UnsupportedStateFormatException implements Exception {
  const UnsupportedStateFormatException(this.formatVersion);

  final int formatVersion;

  @override
  String toString() => 'Saved state uses unsupported format $formatVersion.';
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
    late final List<int> contents;
    try {
      contents = await _stateFile.readAsBytes();
    } on PathNotFoundException {
      return const AppStoreLoadResult(PersistedState());
    }
    late final Object? decoded;
    late final PersistedState state;
    try {
      decoded = jsonDecode(utf8.decode(contents));
      _rejectUnsupportedFormat(decoded);
      state = PersistedState.fromJson(decoded);
    } on FormatException {
      await _quarantineState();
      return const AppStoreLoadResult(
        PersistedState(),
        recoveredCorruptState: true,
      );
    }
    if (_hasNoncanonicalArtwork(decoded)) await save(state);
    return AppStoreLoadResult(state);
  }

  void _rejectUnsupportedFormat(Object? decoded) {
    if (decoded is! Map) return;
    final formatVersion = decoded['formatVersion'];
    if (formatVersion is int && formatVersion > 1) {
      throw UnsupportedStateFormatException(formatVersion);
    }
  }

  Future<void> _quarantineState() async {
    final quarantine = await directory.createTemp(
      'state.json.corrupt-${_clock().toUtc().millisecondsSinceEpoch}-',
    );
    try {
      await _stateFile.rename('${quarantine.path}/state.json');
    } catch (error, stackTrace) {
      try {
        await quarantine.delete();
      } catch (_) {}
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<void> save(PersistedState state) {
    final next = _writes.then((_) async {
      final contents = '${jsonEncode(state.toJson())}\n';
      await _preservePreRefinementState();
      await _atomicWrite(_stateFile, contents);
    });
    _writes = next.catchError((_) {});
    return next;
  }

  Future<void> _preservePreRefinementState() async {
    final backup = File('${_stateFile.path}.pre-desktop-ui');
    if (await backup.exists()) return;
    late final List<int> original;
    try {
      original = await _stateFile.readAsBytes();
    } on PathNotFoundException {
      return;
    }
    await _atomicWriteBytes(backup, original);
  }

  @override
  Future<String> clientIdentifier() async {
    try {
      final existing = utf8.decode(await _identityFile.readAsBytes()).trim();
      if (RegExp(r'^lineup-desktop-[a-z]+-[A-Za-z0-9_-]{20,}$')
          .hasMatch(existing)) {
        return existing;
      }
    } on PathNotFoundException {
      // A missing identity is a first run.
    } on FormatException {
      // Invalid UTF-8 is malformed identity content, not a filesystem failure.
    }
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    final id =
        'lineup-desktop-${Platform.operatingSystem}-${base64Url.encode(bytes).replaceAll('=', '')}';
    await _atomicWrite(_identityFile, '$id\n');
    return id;
  }

  Future<void> _atomicWrite(File target, String contents) =>
      _atomicWriteBytes(target, utf8.encode(contents));

  Future<void> _atomicWriteBytes(File target, List<int> contents) async {
    await directory.create(recursive: true);
    final temporary = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporary.writeAsBytes(contents, flush: true);
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
          if (canonicalPlexCastPortraitText(value) != value) return true;
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
