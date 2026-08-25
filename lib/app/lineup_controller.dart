import 'dart:async';

import 'package:flutter/foundation.dart';

import '../channels/channel.dart';
import '../channels/channel_builder.dart';
import '../channels/content_resolver.dart';
import '../channels/scheduler.dart';
import '../channels/schedule_worker.dart';
import '../diagnostics/diagnostics.dart';
import '../persistence/app_store.dart';
import '../plex/plex_client.dart';
import '../plex/plex_models.dart';
import '../settings/lineup_settings.dart';

enum SetupStage {
  welcome,
  linking,
  profiles,
  servers,
  audio,
  channelSetup,
  ready,
}

enum LibraryScanStatus {
  idle,
  scanning,
  complete,
  empty,
  unsupported,
  transientFailure,
  cancelled,
}

@immutable
class LibraryScanFact {
  const LibraryScanFact({
    required this.status,
    this.completedPages = 0,
    this.completedItems = 0,
    this.totalItems,
  });

  final LibraryScanStatus status;
  final int completedPages;
  final int completedItems;
  final int? totalItems;
}

class LineupPlaybackRequest {
  LineupPlaybackRequest.parts(
    List<LineupPlaybackPart> parts, {
    this.plexToken,
    this.authorizationRecovery,
  }) : assert(parts.isNotEmpty),
       parts = List.unmodifiable(parts);

  final List<LineupPlaybackPart> parts;
  final String? plexToken;
  final Future<LineupPlaybackRequest> Function()? authorizationRecovery;

  static Uri _withoutPlexToken(Uri uri) {
    final query = Map<String, List<String>>.fromEntries(
      uri.queryParametersAll.entries.where(
        (entry) => entry.key.toLowerCase() != 'x-plex-token',
      ),
    );
    if (query.length == uri.queryParametersAll.length) return uri;
    return query.isEmpty
        ? Uri(
            scheme: uri.scheme,
            userInfo: uri.userInfo,
            host: uri.hasAuthority ? uri.host : null,
            port: uri.hasPort ? uri.port : null,
            path: uri.path,
            fragment: uri.hasFragment ? uri.fragment : null,
          )
        : uri.replace(queryParameters: query);
  }
}

class LineupPlaybackPart {
  LineupPlaybackPart({required Uri uri, this.duration})
    : assert(duration == null || duration > Duration.zero),
      uri = LineupPlaybackRequest._withoutPlexToken(uri);

  final Uri uri;
  final Duration? duration;
}

class LineupController extends ChangeNotifier {
  LineupController({
    required this.store,
    required this.credentials,
    required this.plex,
    Diagnostics? diagnostics,
    this.pinPollInterval = const Duration(seconds: 1),
    ScheduleWorkerFactory? scheduleWorkerFactory,
  }) : diagnostics = diagnostics ?? Diagnostics(),
       _scheduleWorkerFactory = scheduleWorkerFactory ?? ScheduleWorker.new;

  final AppStore store;
  final CredentialStore credentials;
  final PlexClient plex;
  final Diagnostics diagnostics;
  @visibleForTesting
  final Duration pinPollInterval;

  LineupSettings settings = const LineupSettings();
  List<Channel> channels = const [];
  String? currentChannelId;
  PlexAccount? account;
  PlexHomeUser? profile;
  List<PlexHomeUser> profiles = const [];
  List<PlexServer> servers = const [];
  PlexServer? server;
  PlexConnection? connection;
  List<PlexLibrary> libraries = const [];
  Set<String> selectedLibraryIds = const {};
  List<PlexMediaItem> availableMedia = const [];
  List<PlexPlaylist> availablePlaylists = const [];
  PlexPin? activePin;
  SetupStage stage = SetupStage.welcome;
  bool busy = false;
  bool channelSetupCanCancel = false;
  bool profileSelectionCanCancel = false;
  bool serverSelectionCanCancel = false;
  bool secureCancellationRequired = false;
  LibraryScanStatus libraryScanStatus = LibraryScanStatus.idle;
  int libraryScanCompletedPages = 0;
  int libraryScanCompletedItems = 0;
  int? libraryScanTotalItems;
  Map<String, LibraryScanFact> _libraryScanFacts = const {};
  String? error;
  int _epoch = 0;
  String? _accountToken;
  String? _profileToken;
  Map<String, PlexServerAccess> _serverAccess = const {};
  String? _pmsToken;
  String? _serverTargetId;
  Future<PlexConnection>? _pmsRefresh;
  int? _pmsRefreshOperation;
  String? _pmsRefreshServerId;
  PersistedState _persisted = const PersistedState();
  Timer? _pinTimer;
  int? _busyOperation;
  List<PlexMediaItem>? _scheduleWorkerMedia;
  List<PlexPlaylist>? _scheduleWorkerPlaylists;
  ScheduleWorker? _scheduleWorker;
  final ScheduleWorkerFactory _scheduleWorkerFactory;
  Future<void> _credentialOperations = Future.value();
  Future<void> _stateOperations = Future.value();
  Future<bool>? _logoutFuture;
  int _contentGeneration = 0;
  bool _disposed = false;

  String? startupRecoveryNotice;

  int get contentGeneration => _contentGeneration;
  Map<String, LibraryScanFact> get libraryScanFacts => _libraryScanFacts;

  Future<void> initialize() async {
    final operation = ++_epoch;
    final loadResult = await store.load();
    if (!_isCurrent(operation)) return;
    _persisted = loadResult.state;
    startupRecoveryNotice = loadResult.recoveredCorruptState
        ? 'Saved app data was corrupt and has been reset.'
        : null;
    settings = _persisted.settings;
    diagnostics.enabled = settings.diagnosticsEnabled;
    channels = const [];
    currentChannelId = null;
    selectedLibraryIds = const {};
    _resetLibraryScan();
    final token = await credentials.readAccountToken();
    if (!_isCurrent(operation)) return;
    if (token == null) {
      stage = SetupStage.welcome;
      notifyListeners();
      return;
    }
    await _run(
      () async {
        final restoredAccount = await plex.account(token);
        if (operation != _epoch) return;
        account = restoredAccount;
        _accountToken = token;
        profiles = await plex.homeUsers(token);
        if (operation != _epoch) return;
        if (settings.profilePickerOnStartup && profiles.length > 1) {
          stage = SetupStage.profiles;
          return;
        }
        final profileId = _persisted.profileId;
        if (profileId != null) {
          final restoredProfile = profiles
              .where((candidate) => candidate.id == profileId)
              .firstOrNull;
          if (restoredProfile != null) {
            final profileToken = restoredProfile.id == restoredAccount.id
                ? token
                : await credentials.readProfileToken(profileId);
            if (operation != _epoch) return;
            if (profileToken == null) {
              stage = SetupStage.profiles;
              return;
            }
            profile = restoredProfile;
            _profileToken = profileToken;
          }
        }
        if (profile == null && profiles.length > 1) {
          stage = SetupStage.profiles;
          return;
        }
        await _discover(operation);
      },
      operation: operation,
      fallbackStage: SetupStage.welcome,
    );
  }

  void dismissStartupRecoveryNotice() {
    if (startupRecoveryNotice == null) return;
    startupRecoveryNotice = null;
    notifyListeners();
  }

  Future<void> startLinking() async {
    if (secureCancellationRequired) {
      await cancelLinking();
      return;
    }
    final operation = ++_epoch;
    _pinTimer?.cancel();
    await _run(
      () async {
        late final PlexPin pin;
        try {
          pin = await plex.createPin();
        } catch (exception) {
          final code = _linkFailureCode(exception);
          throw PlexException(code, _linkFailureMessage(code));
        }
        if (operation != _epoch) return;
        activePin = pin;
        stage = SetupStage.linking;
        notifyListeners();
        _schedulePinPoll(operation, pin);
      },
      operation: operation,
      fallbackStage: SetupStage.welcome,
    );
  }

  Future<bool> cancelLinking() async {
    final pin = activePin;
    ++_epoch;
    _pinTimer?.cancel();
    _busyOperation = null;
    busy = true;
    error = null;
    notifyListeners();
    Object? cleanupFailure;
    try {
      await _clearCredentials();
    } catch (exception) {
      cleanupFailure = exception;
      diagnostics.add('application', 'Credential cleanup failed', {
        'code': 'credential-cleanup-failed',
      });
    }
    if (pin != null) {
      try {
        await plex.cancelPin(pin);
      } catch (exception) {
        diagnostics.add('plex-auth', 'PIN cancellation failed', {
          'code': _linkFailureCode(exception),
        });
      }
    }
    if (_disposed) return false;
    busy = false;
    if (cleanupFailure != null) {
      secureCancellationRequired = true;
      error = 'Lineup could not securely cancel sign-in. Check system credential storage and try again.';
      notifyListeners();
      return false;
    }
    activePin = null;
    secureCancellationRequired = false;
    stage = SetupStage.welcome;
    notifyListeners();
    return true;
  }

  void _schedulePinPoll(int operation, PlexPin pin) {
    _pinTimer?.cancel();
    _pinTimer = Timer(pinPollInterval, () async {
      await _pollPin(operation, pin);
      if (operation == _epoch &&
          activePin?.id == pin.id &&
          !secureCancellationRequired) {
        _schedulePinPoll(operation, pin);
      }
    });
  }

  Future<void> _pollPin(int operation, PlexPin pin) async {
    if (busy || operation != _epoch) return;
    if (DateTime.now().isAfter(pin.expiresAt)) {
      _pinTimer?.cancel();
      activePin = null;
      error = 'The Plex link code expired. Request a new code.';
      notifyListeners();
      return;
    }
    try {
      final token = await plex.pollPin(pin);
      if (token == null || operation != _epoch) return;
      _pinTimer?.cancel();
      final validated = await plex.account(token);
      if (operation != _epoch) return;
      final homeUsers = await plex.homeUsers(token);
      if (operation != _epoch) return;
      try {
        if (!await _writeCredential(
          operation,
          () => credentials.writeAccountToken(token),
        )) {
          return;
        }
      } catch (_) {
        if (operation != _epoch) return;
        secureCancellationRequired = true;
        error = 'Lineup could not confirm secure credential storage. Retry secure cancellation before signing in again.';
        diagnostics.add('plex-auth', 'Credential write failed', {
          'code': 'credential-write-failed',
        });
        notifyListeners();
        return;
      }
      account = validated;
      _accountToken = token;
      profiles = homeUsers;
      activePin = null;
      if (profiles.length > 1) {
        stage = SetupStage.profiles;
      } else if (profiles.length == 1) {
        await selectProfile(profiles.single);
      } else {
        _profileToken = token;
        await _run(
          () => _discover(operation),
          operation: operation,
          fallbackStage: SetupStage.servers,
        );
      }
      notifyListeners();
    } catch (exception) {
      if (operation != _epoch) return;
      _pinTimer?.cancel();
      activePin = null;
      final code = _linkFailureCode(exception);
      error = _linkFailureMessage(code);
      diagnostics.add('plex-auth', 'PIN poll failed', {'code': code});
      notifyListeners();
      try {
        await plex.cancelPin(pin);
      } catch (cancelException) {
        if (operation != _epoch) return;
        diagnostics.add('plex-auth', 'PIN cancellation failed', {
          'code': _linkFailureCode(cancelException),
        });
      }
    }
  }

  static String _linkFailureCode(Object exception) {
    final code = exception is PlexException ? exception.code : 'unexpected';
    if (code == 'network-timeout') return 'network-timeout';
    if (const {
      'network-unavailable',
      'server-unreachable',
      'offline',
    }.contains(code)) {
      return 'network-unavailable';
    }
    if (code == 'rate-limited') return 'rate-limited';
    if (const {'auth-invalid', 'access-denied'}.contains(code)) {
      return 'auth-denied';
    }
    if (const {'parse-error', 'resource-not-found'}.contains(code)) {
      return 'response-unavailable';
    }
    return 'unexpected';
  }

  static String _linkFailureMessage(String code) => switch (code) {
    'network-timeout' => 'Plex did not respond in time. Check your connection and request a new code.',
    'network-unavailable' => 'Lineup could not connect to Plex. Check your connection and request a new code.',
    'rate-limited' => 'Plex is receiving too many requests. Wait a moment, then request a new code.',
    'auth-denied' =>
      'Plex did not accept this sign-in. Request a new code and try again.',
    'response-unavailable' => 'Plex returned an unavailable or malformed response. Request a new code and try again.',
    _ => 'Lineup could not complete Plex sign-in. Request a new code and try again.',
  };

  Future<bool> selectProfile(PlexHomeUser selected, {String? pin}) {
    final operation = ++_epoch;
    _invalidatePmsRefresh();
    _serverTargetId = null;
    _pinTimer?.cancel();
    return _run(
      () async {
        final accountToken = _accountToken;
        if (accountToken == null) {
          throw const PlexException('auth-required', 'Link Plex first.');
        }
        final token = profiles.length == 1 && selected.id == account?.id
            ? accountToken
            : await plex.switchHomeUser(accountToken, selected.id, pin);
        if (operation != _epoch) return;
        if (!await _writeCredential(
          operation,
          () => credentials.writeProfileToken(selected.id, token),
        )) {
          return;
        }
        await _queueStateOperation(operation, () async {
          final oldProfile = profile;
          final oldProfileToken = _profileToken;
          final oldServerAccess = _serverAccess;
          final oldPmsToken = _pmsToken;
          final oldServer = server;
          final oldConnection = connection;
          final oldLibraries = libraries;
          final oldSelectedLibraries = selectedLibraryIds;
          final oldMedia = availableMedia;
          final oldPlaylists = availablePlaylists;
          final oldChannels = channels;
          final oldCurrent = currentChannelId;
          final oldCanCancel = profileSelectionCanCancel;
          profileSelectionCanCancel = false;
          notifyListeners();
          profile = selected;
          _profileToken = token;
          _serverAccess = const {};
          _pmsToken = null;
          _invalidatePmsRefresh();
          server = null;
          connection = null;
          libraries = const [];
          selectedLibraryIds = const {};
          availableMedia = const [];
          availablePlaylists = const [];
          channels = const [];
          currentChannelId = null;
          try {
            await _save();
          } catch (_) {
            profile = oldProfile;
            _profileToken = oldProfileToken;
            _serverAccess = oldServerAccess;
            _pmsToken = oldPmsToken;
            server = oldServer;
            connection = oldConnection;
            libraries = oldLibraries;
            selectedLibraryIds = oldSelectedLibraries;
            availableMedia = oldMedia;
            availablePlaylists = oldPlaylists;
            channels = oldChannels;
            currentChannelId = oldCurrent;
            profileSelectionCanCancel = oldCanCancel;
            rethrow;
          }
          if (_disposed) return;
          _resetLibraryScan();
          _contentGeneration++;
          notifyListeners();
        });
        if (!_isCurrent(operation)) return;
        await _discover(operation);
        if (operation == _epoch) profileSelectionCanCancel = false;
      },
      operation: operation,
      fallbackStage: SetupStage.profiles,
    );
  }

  Future<void> _discover(int operation) async {
    final token = _profileToken ?? _accountToken;
    if (token == null) return;
    final discovered = await plex.discoverServers(token);
    if (!_isCurrent(operation)) return;
    _serverAccess = {for (final access in discovered) access.server.id: access};
    servers = List.unmodifiable(discovered.map((access) => access.server));
    stage = SetupStage.servers;
    final profileId = profile?.id ?? account?.id;
    final savedId = profileId == null
        ? null
        : _persisted.selectedServerByProfile[profileId];
    final saved = servers
        .where((candidate) => candidate.id == savedId)
        .firstOrNull;
    if (saved != null) {
      await selectServer(saved);
    } else if (savedId != null) {
      if (server != null) _clearServerRuntime();
      error = 'Plex server authorization is unavailable.';
    } else if (server != null) {
      _clearServerRuntime();
      serverSelectionCanCancel = false;
    }
  }

  Future<void> refreshServers() async {
    final operation = ++_epoch;
    _invalidatePmsRefresh();
    _serverTargetId = null;
    await _run(
      () => _discover(operation),
      operation: operation,
      fallbackStage: SetupStage.servers,
    );
  }

  Future<void> selectServer(PlexServer selected) async {
    final operation = ++_epoch;
    _invalidatePmsRefresh();
    _serverTargetId = selected.id;
    await _run(
      () async {
        final selectedConnection = await _withPmsAuthorization(
          operation,
          selected.id,
          (token, refreshedConnection) => refreshedConnection != null
              ? Future.value(refreshedConnection)
              : plex.selectConnection(
                  _serverAccess[selected.id]!.server,
                  token,
                ),
        );
        if (!_isCurrent(operation)) return;
        var workingConnection = selectedConnection;
        final loadedLibraries = await _withPmsAuthorization(
          operation,
          selected.id,
          (token, refreshedConnection) {
            workingConnection = refreshedConnection ?? workingConnection;
            return plex.libraries(workingConnection.uri, token);
          },
          connectionOverride: selectedConnection,
        );
        if (!_isCurrent(operation)) return;
        await _queueStateOperation(operation, () async {
          final oldServer = server;
          final oldConnection = connection;
          final oldPmsToken = _pmsToken;
          final oldLibraries = libraries;
          final oldSelectedLibraries = selectedLibraryIds;
          final oldMedia = availableMedia;
          final oldPlaylists = availablePlaylists;
          final oldChannels = channels;
          final oldCurrent = currentChannelId;
          final oldCanCancel = serverSelectionCanCancel;
          serverSelectionCanCancel = false;
          notifyListeners();
          server = _serverAccess[selected.id]!.server;
          connection = workingConnection;
          _pmsToken = _serverAccess[selected.id]!.token;
          libraries = loadedLibraries;
          final profileId = profile?.id ?? account?.id;
          final savedLibraries = profileId == null
              ? const <String>[]
              : _persisted
                        .selectedLibraryIdsByProfileServer[profileId]?[selected
                        .id] ??
                    const <String>[];
          final availableIds = loadedLibraries
              .map((library) => library.id)
              .toSet();
          selectedLibraryIds = Set.unmodifiable(
            savedLibraries.where(availableIds.contains),
          );
          availableMedia = const [];
          availablePlaylists = const [];
          channels = List.unmodifiable(
            profileId == null
                ? const <Channel>[]
                : _persisted.channelsByProfileServer[profileId]?[selected.id] ??
                      const <Channel>[],
          );
          currentChannelId = profileId == null
              ? null
              : _persisted.currentChannelByProfileServer[profileId]?[selected
                    .id];
          stage = SetupStage.channelSetup;
          channelSetupCanCancel = false;
          try {
            await _save();
          } catch (_) {
            server = oldServer;
            connection = oldConnection;
            _pmsToken = oldPmsToken;
            libraries = oldLibraries;
            selectedLibraryIds = oldSelectedLibraries;
            availableMedia = oldMedia;
            availablePlaylists = oldPlaylists;
            channels = oldChannels;
            currentChannelId = oldCurrent;
            serverSelectionCanCancel = oldCanCancel;
            rethrow;
          }
          if (_disposed) return;
          _resetLibraryScan();
          _contentGeneration++;
          notifyListeners();
        });
        if (!_isCurrent(operation)) return;
        if (selectedLibraryIds.isNotEmpty && channels.isNotEmpty) {
          final loaded = await _loadLibraries(operation, selectedLibraryIds);
          if (operation != _epoch) return;
          libraryScanStatus = loaded.status;
          _requireAvailablePlaylists(loaded.failedPlaylistIds);
          availableMedia = loaded.media;
          availablePlaylists = loaded.playlists;
          stage = libraryScanStatus == LibraryScanStatus.complete
              ? SetupStage.ready
              : SetupStage.channelSetup;
        } else if (!settings.audioSetupComplete) {
          stage = SetupStage.audio;
        }
        serverSelectionCanCancel = false;
      },
      operation: operation,
      fallbackStage: SetupStage.servers,
    );
    if (_serverTargetId == selected.id) _serverTargetId = null;
  }

  Future<bool> setLibraries(Set<String> ids) async {
    final operation = ++_epoch;
    final loaded = await _run(
      () async {
        final allowed = libraries.map((library) => library.id).toSet();
        if (ids.isEmpty || !allowed.containsAll(ids)) {
          throw const PlexException(
            'invalid-library',
            'Select one or more libraries from the current server.',
          );
        }
        final loaded = await _loadLibraries(operation, ids);
        if (operation != _epoch) return;
        await _queueStateOperation(operation, () async {
          libraryScanStatus = loaded.status;
          _requireAvailablePlaylists(loaded.failedPlaylistIds);
          final oldSelectedLibraries = selectedLibraryIds;
          final oldMedia = availableMedia;
          final oldPlaylists = availablePlaylists;
          selectedLibraryIds = Set.unmodifiable(ids);
          availableMedia = loaded.media;
          availablePlaylists = loaded.playlists;
          try {
            await _save();
          } catch (_) {
            selectedLibraryIds = oldSelectedLibraries;
            availableMedia = oldMedia;
            availablePlaylists = oldPlaylists;
            rethrow;
          }
          if (_disposed) return;
          _contentGeneration++;
          notifyListeners();
        });
      },
      operation: operation,
      fallbackStage: SetupStage.channelSetup,
    );
    return loaded;
  }

  Future<
    ({
      Set<String> failedPlaylistIds,
      List<PlexMediaItem> media,
      List<PlexPlaylist> playlists,
      LibraryScanStatus status,
    })
  >
  _loadLibraries(int operation, Set<String> ids) async {
    final selectedServer = server;
    if (selectedServer == null || connection == null) {
      throw const PlexException('server-unreachable', 'Select a server first.');
    }
    _libraryScanFacts = Map.unmodifiable({
      for (final id in ids)
        id: const LibraryScanFact(status: LibraryScanStatus.idle),
    });
    libraryScanStatus = LibraryScanStatus.scanning;
    _updateLibraryScanAggregates();
    notifyListeners();
    try {
      final selected = libraries
          .where((library) => ids.contains(library.id))
          .toList(growable: false);
      final results = List<List<PlexMediaItem>?>.filled(selected.length, null);
      var nextLibrary = 0;
      Object? firstFailure;
      StackTrace? firstFailureStack;
      Future<void> loadNext() async {
        while (_isCurrent(operation) && firstFailure == null) {
          final index = nextLibrary++;
          if (index >= selected.length) return;
          final library = selected[index];
          _setLibraryScanFact(
            library.id,
            const LibraryScanFact(status: LibraryScanStatus.scanning),
          );
          notifyListeners();
          try {
            final items = await _withPmsAuthorization(
              operation,
              selectedServer.id,
              (token, refreshedConnection) => plex.libraryItems(
                (refreshedConnection ?? connection!).uri,
                token,
                library.id,
                library.type,
                isCurrent: () => _isCurrent(operation),
                onProgress: (progress) {
                  if (!_isCurrent(operation) || firstFailure != null) return;
                  final current = _libraryScanFacts[library.id]!;
                  _setLibraryScanFact(
                    library.id,
                    LibraryScanFact(
                      status: LibraryScanStatus.scanning,
                      completedPages:
                          progress.completedPages > current.completedPages
                          ? progress.completedPages
                          : current.completedPages,
                      completedItems:
                          progress.completedItems > current.completedItems
                          ? progress.completedItems
                          : current.completedItems,
                      totalItems:
                          progress.totalItems != null &&
                              (current.totalItems == null ||
                                  progress.totalItems! > current.totalItems!)
                          ? progress.totalItems
                          : current.totalItems,
                    ),
                  );
                  notifyListeners();
                },
              ),
            );
            if (!_isCurrent(operation)) return;
            results[index] = items;
            final current = _libraryScanFacts[library.id]!;
            final playable = items.where((item) => item.isPlayable).length;
            _setLibraryScanFact(
              library.id,
              LibraryScanFact(
                status: items.isEmpty
                    ? LibraryScanStatus.empty
                    : playable == 0
                    ? LibraryScanStatus.unsupported
                    : LibraryScanStatus.complete,
                completedPages: current.completedPages,
                completedItems:
                    firstFailure == null &&
                        items.length > current.completedItems
                    ? items.length
                    : current.completedItems,
                totalItems: current.totalItems,
              ),
            );
            notifyListeners();
          } catch (exception, stack) {
            if (!_isCurrent(operation)) return;
            final current = _libraryScanFacts[library.id]!;
            _setLibraryScanFact(
              library.id,
              LibraryScanFact(
                status: LibraryScanStatus.transientFailure,
                completedPages: current.completedPages,
                completedItems: current.completedItems,
                totalItems: current.totalItems,
              ),
            );
            firstFailure ??= exception;
            firstFailureStack ??= stack;
            notifyListeners();
          }
        }
      }

      await Future.wait(
        List.generate(selected.length.clamp(0, 4), (_) => loadNext()),
      );
      if (firstFailure != null) {
        Error.throwWithStackTrace(firstFailure!, firstFailureStack!);
      }
      if (!_isCurrent(operation)) {
        return (
          failedPlaylistIds: const <String>{},
          media: const <PlexMediaItem>[],
          playlists: const <PlexPlaylist>[],
          status: LibraryScanStatus.cancelled,
        );
      }
      final items = results
          .whereType<List<PlexMediaItem>>()
          .expand((items) => items)
          .toList();
      PlexPlaylistCatalog catalog;
      try {
        catalog = await _withPmsAuthorization(
          operation,
          selectedServer.id,
          (token, refreshedConnection) =>
              plex.playlists((refreshedConnection ?? connection!).uri, token),
        );
      } on PlexException catch (exception) {
        if (_isPmsAuthorizationError(exception)) rethrow;
        diagnostics.add('plex-library', 'Playlist discovery unavailable', {
          'code': exception.code,
        });
        catalog = const PlexPlaylistCatalog(playlists: [], failedIds: {});
      }
      if (operation != _epoch) {
        return (
          failedPlaylistIds: const <String>{},
          media: const <PlexMediaItem>[],
          playlists: const <PlexPlaylist>[],
          status: LibraryScanStatus.cancelled,
        );
      }
      if (catalog.failedIds.isNotEmpty) {
        diagnostics.add('plex-library', 'Some playlists could not be loaded', {
          'count': catalog.failedIds.length,
        });
      }
      final playable = items.where((item) => item.isPlayable).toList();
      final status = items.isEmpty
          ? LibraryScanStatus.empty
          : playable.isEmpty
          ? LibraryScanStatus.unsupported
          : LibraryScanStatus.complete;
      return (
        failedPlaylistIds: Set<String>.unmodifiable(catalog.failedIds),
        media: List<PlexMediaItem>.unmodifiable(playable),
        playlists: List<PlexPlaylist>.unmodifiable(catalog.playlists),
        status: status,
      );
    } catch (_) {
      if (_isCurrent(operation)) {
        libraryScanStatus = LibraryScanStatus.transientFailure;
        notifyListeners();
      }
      rethrow;
    }
  }

  void cancelLibraryScan() {
    if (libraryScanStatus != LibraryScanStatus.scanning) return;
    ++_epoch;
    _busyOperation = null;
    busy = false;
    error = null;
    libraryScanStatus = LibraryScanStatus.cancelled;
    _libraryScanFacts = Map.unmodifiable({
      for (final entry in _libraryScanFacts.entries)
        entry.key: entry.value.status == LibraryScanStatus.scanning
            ? LibraryScanFact(
                status: LibraryScanStatus.cancelled,
                completedPages: entry.value.completedPages,
                completedItems: entry.value.completedItems,
                totalItems: entry.value.totalItems,
              )
            : entry.value,
    });
    _updateLibraryScanAggregates();
    notifyListeners();
  }

  void _requireAvailablePlaylists(Set<String> failedIds) {
    final required = channels
        .map((channel) => channel.source)
        .whereType<PlaylistSource>()
        .map((source) => source.playlistId)
        .toSet();
    if (failedIds.any(required.contains)) {
      throw const PlexException(
        'playlist-unavailable',
        'A playlist used by this lineup could not be loaded. Retry setup.',
      );
    }
  }

  Future<void> completeAudioSetup() async {
    try {
      await updateSettings(settings.copyWith(audioSetupComplete: true));
      if (_disposed) return;
      stage = SetupStage.channelSetup;
      notifyListeners();
    } catch (exception) {
      error =
          'Could not save audio settings. Check device storage and try again.';
      diagnostics.add('application', 'Audio setup persistence failed', {
        'code': exception is PlexException ? exception.code : 'unexpected',
      });
      notifyListeners();
    }
  }

  Future<void> enterChannelSetup() async {
    channelSetupCanCancel = stage == SetupStage.ready;
    stage = SetupStage.channelSetup;
    notifyListeners();
  }

  void cancelChannelSetup() {
    if (channelSetupCanCancel) {
      cancelLibraryScan();
      channelSetupCanCancel = false;
      error = null;
      stage = SetupStage.ready;
      notifyListeners();
    }
  }

  void showProfiles() {
    profileSelectionCanCancel = stage == SetupStage.ready;
    stage = SetupStage.profiles;
    error = null;
    notifyListeners();
  }

  void cancelProfileSelection() {
    if (!profileSelectionCanCancel || server == null) return;
    if (busy) {
      ++_epoch;
      _invalidatePmsRefresh();
      _serverTargetId = null;
      _busyOperation = null;
      busy = false;
    }
    profileSelectionCanCancel = false;
    error = null;
    stage = SetupStage.ready;
    notifyListeners();
  }

  void showServers() {
    serverSelectionCanCancel = stage == SetupStage.ready;
    stage = SetupStage.servers;
    error = null;
    notifyListeners();
  }

  void cancelServerSelection() {
    if (!serverSelectionCanCancel || server == null) return;
    if (busy) {
      ++_epoch;
      _invalidatePmsRefresh();
      _serverTargetId = null;
      _busyOperation = null;
      busy = false;
    }
    serverSelectionCanCancel = false;
    error = null;
    stage = SetupStage.ready;
    notifyListeners();
  }

  Future<void> clearSavedServer() async {
    final operation = ++_epoch;
    await _run(
      () => _queueStateOperation(operation, () async {
        final profileId = profile?.id ?? account?.id;
        if (profileId == null) return;
        final selections = Map<String, String>.of(
          _persisted.selectedServerByProfile,
        )..remove(profileId);
        final next = PersistedState(
          settings: _persisted.settings,
          profileId: _persisted.profileId,
          selectedServerByProfile: selections,
          selectedLibraryIdsByProfileServer:
              _persisted.selectedLibraryIdsByProfileServer,
          channelsByProfileServer: _persisted.channelsByProfileServer,
          currentChannelByProfileServer:
              _persisted.currentChannelByProfileServer,
        );
        await store.save(next);
        _persisted = next;
        _clearServerRuntime();
        serverSelectionCanCancel = false;
        stage = SetupStage.servers;
      }),
      operation: operation,
      fallbackStage: SetupStage.servers,
    );
  }

  Future<void> applyChannelPlan(
    List<Channel> planned, {
    required ChannelBuildMode mode,
  }) async {
    final operation = _epoch;
    await _queueStateOperation(operation, () async {
      final oldChannels = channels;
      final oldCurrent = currentChannelId;
      final oldCurrentIndex = oldChannels.indexWhere(
        (channel) => channel.id == oldCurrent,
      );
      final next = switch (mode) {
        ChannelBuildMode.replace => [...planned],
        ChannelBuildMode.append => [...channels, ...planned],
        ChannelBuildMode.merge => [
          ...channels.where(
            (existing) => !planned.any(
              (candidate) =>
                  candidate.builderKey != null &&
                  candidate.builderKey == existing.builderKey,
            ),
          ),
          ...planned,
        ],
      }..sort((a, b) => a.number.compareTo(b.number));
      for (final channel in next) {
        channel.validate(next);
      }
      channels = List.unmodifiable(next);
      currentChannelId = channels.any((channel) => channel.id == oldCurrent)
          ? oldCurrent
          : channels.isEmpty
          ? null
          : channels[oldCurrentIndex.clamp(0, channels.length - 1)].id;
      try {
        await _save();
        if (_disposed) return;
        notifyListeners();
      } catch (_) {
        channels = oldChannels;
        currentChannelId = oldCurrent;
        rethrow;
      }
    });
  }

  void completeChannelSetup() {
    if (stage != SetupStage.channelSetup) return;
    channelSetupCanCancel = false;
    error = null;
    stage = SetupStage.ready;
    notifyListeners();
  }

  Future<void> saveChannel(Channel channel) async {
    final operation = _epoch;
    await _queueStateOperation(operation, () async {
      channel.validate(channels);
      final next = [...channels];
      final index = next.indexWhere((candidate) => candidate.id == channel.id);
      if (index < 0) {
        next.add(channel);
      } else {
        next[index] = channel;
      }
      final old = channels;
      final oldCurrent = currentChannelId;
      channels = List.unmodifiable(
        next..sort((a, b) => a.number.compareTo(b.number)),
      );
      currentChannelId ??= channel.id;
      try {
        await _save();
        if (_disposed) return;
        notifyListeners();
      } catch (_) {
        channels = old;
        currentChannelId = oldCurrent;
        rethrow;
      }
    });
  }

  ScheduleIndex scheduleFor(Channel channel) => buildSchedule(
    resolveContent(channel.source, availableMedia, availablePlaylists),
    mode: channel.playbackMode,
    seed: channel.shuffleSeed,
    blockSize: channel.blockSize ?? 3,
  );

  Future<ScheduleIndex> loadScheduleFor(Channel channel) {
    if (_disposed) {
      return Future.error(StateError('Schedule worker is disposed'));
    }
    if (!identical(_scheduleWorkerMedia, availableMedia) ||
        !identical(_scheduleWorkerPlaylists, availablePlaylists)) {
      _scheduleWorker?.dispose();
      _scheduleWorkerMedia = availableMedia;
      _scheduleWorkerPlaylists = availablePlaylists;
      _scheduleWorker = null;
    }
    final worker = _scheduleWorker ??= _scheduleWorkerFactory(
      availableMedia,
      availablePlaylists,
    );
    return worker.build(channel);
  }

  LineupPlaybackRequest playbackFor(String itemId) {
    final endpoint = connection?.uri;
    final token = _pmsToken;
    final serverId = server?.id;
    final item = availableMedia
        .where((value) => value.id == itemId)
        .firstOrNull;
    if (endpoint == null || token == null || serverId == null || item == null) {
      throw const PlexException(
        'playback-unavailable',
        'This program is not available from the current Plex session.',
      );
    }
    return _playbackRequest(item, endpoint, token, serverId, _epoch);
  }

  LineupPlaybackRequest _playbackRequest(
    PlexMediaItem item,
    Uri endpoint,
    String token,
    String serverId,
    int operation,
  ) {
    final descriptor = plex.playbackDescriptor(server: endpoint, item: item);
    diagnostics.add('playback', 'Plex playback selected', {
      'container': item.container,
      'videoCodec': item.videoCodec,
      'audioCodec': item.audioCodec,
      'dynamicRange': item.dynamicRange.name,
    });
    return LineupPlaybackRequest.parts(
      [
        for (final part in descriptor)
          LineupPlaybackPart(uri: part.uri, duration: part.duration),
      ],
      plexToken: token,
      authorizationRecovery: () async {
        await _refreshPmsAccess(operation, serverId);
        if (!_isCurrent(operation) || server?.id != serverId) {
          throw const PlexException(
            'playback-unavailable',
            'This program is not available from the current Plex session.',
          );
        }
        final refreshedEndpoint = connection?.uri;
        final refreshedToken = _pmsToken;
        if (refreshedEndpoint == null || refreshedToken == null) {
          throw const PlexException(
            'authorization-unavailable',
            'Plex server authorization is unavailable.',
          );
        }
        return _playbackRequest(
          item,
          refreshedEndpoint,
          refreshedToken,
          serverId,
          operation,
        );
      },
    );
  }

  Future<Uint8List?> artworkFor(ChannelItem item) async {
    final poster = item.poster;
    return poster == null ? null : artworkForPath(poster);
  }

  Future<Uint8List?> artworkForPath(Uri path) async {
    final serverId = server?.id;
    if (serverId == null || connection == null || path.toString().isEmpty) {
      return null;
    }
    return _withPmsAuthorization(
      _epoch,
      serverId,
      (token, refreshedConnection) =>
          plex.artwork((refreshedConnection ?? connection!).uri, token, path),
    );
  }

  Future<void> setCurrentChannel(String? id) async {
    final operation = _epoch;
    await _queueStateOperation(operation, () async {
      if (id == currentChannelId ||
          (id != null && !channels.any((channel) => channel.id == id))) {
        return;
      }
      final old = currentChannelId;
      currentChannelId = id;
      try {
        await _save();
        if (_disposed) return;
        notifyListeners();
      } catch (_) {
        currentChannelId = old;
        rethrow;
      }
    });
  }

  Future<void> deleteChannel(String id) async {
    final operation = _epoch;
    await _queueStateOperation(operation, () async {
      final old = channels;
      final oldCurrent = currentChannelId;
      final removedIndex = channels.indexWhere((channel) => channel.id == id);
      channels = List.unmodifiable(
        channels.where((channel) => channel.id != id),
      );
      if (currentChannelId == id) {
        currentChannelId = channels.isEmpty
            ? null
            : channels[removedIndex.clamp(0, channels.length - 1)].id;
      }
      try {
        await _save();
        if (_disposed) return;
        notifyListeners();
      } catch (_) {
        channels = old;
        currentChannelId = oldCurrent;
        rethrow;
      }
    });
  }

  Future<void> updateSettings(LineupSettings value) async {
    final operation = _epoch;
    await _queueStateOperation(operation, () async {
      final old = settings;
      settings = value;
      try {
        await _save();
        if (_disposed) return;
        diagnostics.enabled = value.diagnosticsEnabled;
        notifyListeners();
      } catch (_) {
        settings = old;
        rethrow;
      }
    });
  }

  Future<bool> logout() {
    final active = _logoutFuture;
    if (active != null) return active;
    final next = Future<bool>.microtask(_performLogout)
        .whenComplete(_finishLogout);
    _logoutFuture = next;
    return next;
  }

  Future<bool> _performLogout() async {
    ++_epoch;
    final stateBeforeLogout = _stateOperations;
    final releaseStateOperations = Completer<void>();
    _stateOperations = stateBeforeLogout.then(
      (_) => releaseStateOperations.future,
    );
    _invalidatePmsRefresh();
    _serverTargetId = null;
    _pinTimer?.cancel();
    _busyOperation = null;
    busy = true;
    notifyListeners();
    try {
      try {
        await _clearCredentials();
      } catch (exception) {
        if (_disposed) return false;
        error = 'Lineup could not securely sign out. Check system credential storage and try again.';
        diagnostics.add('application', 'Credential cleanup failed', {
          'code': exception is PlexException ? exception.code : 'unexpected',
        });
        return false;
      }
      if (_disposed) return false;
      await stateBeforeLogout;
      if (_disposed) return false;
      ++_epoch;
      account = null;
      profile = null;
      profiles = const [];
      servers = const [];
      server = null;
      connection = null;
      libraries = const [];
      availableMedia = const [];
      availablePlaylists = const [];
      _scheduleWorker?.dispose();
      _scheduleWorker = null;
      _scheduleWorkerMedia = null;
      _scheduleWorkerPlaylists = null;
      selectedLibraryIds = const {};
      channels = const [];
      currentChannelId = null;
      channelSetupCanCancel = false;
      profileSelectionCanCancel = false;
      serverSelectionCanCancel = false;
      _accountToken = null;
      _profileToken = null;
      _serverAccess = const {};
      _pmsToken = null;
      _serverTargetId = null;
      _invalidatePmsRefresh();
      secureCancellationRequired = false;
      _resetLibraryScan();
      _contentGeneration++;
      stage = SetupStage.welcome;
      error = null;
      return true;
    } finally {
      releaseStateOperations.complete();
    }
  }

  void _finishLogout() {
    _logoutFuture = null;
    if (_disposed) return;
    busy = false;
    notifyListeners();
  }

  Future<void> _save() async {
    final profileId = profile?.id ?? account?.id;
    final selectedServers = Map<String, String>.of(
      _persisted.selectedServerByProfile,
    );
    final librarySelections = {
      for (final entry in _persisted.selectedLibraryIdsByProfileServer.entries)
        entry.key: {
          for (final selection in entry.value.entries)
            selection.key: List<String>.of(selection.value),
        },
    };
    final channelSelections = {
      for (final entry in _persisted.channelsByProfileServer.entries)
        entry.key: {
          for (final selection in entry.value.entries)
            selection.key: List<Channel>.of(selection.value),
        },
    };
    final currentSelections = {
      for (final entry in _persisted.currentChannelByProfileServer.entries)
        entry.key: Map<String, String>.of(entry.value),
    };
    if (profileId != null && server != null) {
      selectedServers[profileId] = server!.id;
      librarySelections.putIfAbsent(profileId, () => {})[server!.id] =
          selectedLibraryIds.toList();
      channelSelections.putIfAbsent(profileId, () => {})[server!.id] = channels
          .toList();
      final current = currentChannelId;
      if (current == null) {
        currentSelections[profileId]?.remove(server!.id);
      } else {
        currentSelections.putIfAbsent(profileId, () => {})[server!.id] =
            current;
      }
    }
    final next = PersistedState(
      settings: settings,
      profileId: profile?.id,
      selectedServerByProfile: selectedServers,
      selectedLibraryIdsByProfileServer: librarySelections,
      channelsByProfileServer: channelSelections,
      currentChannelByProfileServer: currentSelections,
    );
    await store.save(next);
    if (!_disposed) _persisted = next;
  }

  Future<void> _queueStateOperation(
    int operation,
    Future<void> Function() body,
  ) {
    final queued = _stateOperations.then((_) async {
      if (!_isCurrent(operation)) return;
      await body();
    });
    _stateOperations = queued.then<void>((_) {}, onError: (_, _) {});
    return queued;
  }

  Future<bool> _writeCredential(
    int operation,
    Future<void> Function() write,
  ) async {
    var current = false;
    final next = _credentialOperations.then((_) async {
      if (operation != _epoch) return;
      await write();
      current = operation == _epoch;
    });
    _credentialOperations = next.catchError((_) {});
    await next;
    return current;
  }

  Future<void> _clearCredentials() {
    final next = _credentialOperations.then((_) => credentials.clear());
    _credentialOperations = next.catchError((_) {});
    return next;
  }

  void _clearServerRuntime() {
    server = null;
    connection = null;
    _pmsToken = null;
    _serverTargetId = null;
    _invalidatePmsRefresh();
    libraries = const [];
    selectedLibraryIds = const {};
    availableMedia = const [];
    availablePlaylists = const [];
    _resetLibraryScan();
    channels = const [];
    currentChannelId = null;
    _scheduleWorker?.dispose();
    _scheduleWorker = null;
    _scheduleWorkerMedia = null;
    _scheduleWorkerPlaylists = null;
    _contentGeneration++;
  }

  void _resetLibraryScan() {
    libraryScanStatus = LibraryScanStatus.idle;
    libraryScanCompletedPages = 0;
    libraryScanCompletedItems = 0;
    libraryScanTotalItems = null;
    _libraryScanFacts = const {};
  }

  void _setLibraryScanFact(String id, LibraryScanFact fact) {
    _libraryScanFacts = Map.unmodifiable({..._libraryScanFacts, id: fact});
    _updateLibraryScanAggregates();
  }

  void _updateLibraryScanAggregates() {
    libraryScanCompletedPages = _libraryScanFacts.values.fold(
      0,
      (total, fact) => total + fact.completedPages,
    );
    libraryScanCompletedItems = _libraryScanFacts.values.fold(
      0,
      (total, fact) => total + fact.completedItems,
    );
    libraryScanTotalItems =
        _libraryScanFacts.isNotEmpty &&
            _libraryScanFacts.values.every((fact) => fact.totalItems != null)
        ? _libraryScanFacts.values.fold<int>(
            0,
            (total, fact) => total + fact.totalItems!,
          )
        : null;
  }

  Future<T> _withPmsAuthorization<T>(
    int operation,
    String serverId,
    Future<T> Function(String token, PlexConnection? connection) request, {
    PlexConnection? connectionOverride,
  }) async {
    final access = _serverAccess[serverId];
    if (access == null || access.token.isEmpty) {
      throw const PlexException(
        'authorization-unavailable',
        'Plex server authorization is unavailable.',
      );
    }
    PlexServerAccess retryAccess;
    PlexConnection retryConnection;
    try {
      return await request(access.token, connectionOverride);
    } on PlexException catch (exception) {
      if (!_isPmsAuthorizationError(exception)) rethrow;
      final currentAccess = _serverAccess[serverId];
      final currentConnection = server?.id == serverId ? connection : null;
      if (!identical(currentAccess, access) &&
          currentAccess != null &&
          currentConnection != null) {
        retryAccess = currentAccess;
        retryConnection = currentConnection;
      } else {
        retryConnection = await _refreshPmsAccess(operation, serverId);
        final refreshed = _serverAccess[serverId];
        if (refreshed == null) {
          throw const PlexException(
            'authorization-unavailable',
            'Plex server authorization is unavailable.',
          );
        }
        retryAccess = refreshed;
      }
      if (!_isCurrentPmsTarget(operation, serverId)) {
        throw const PlexException(
          'authorization-unavailable',
          'Plex server authorization is unavailable.',
        );
      }
    }
    return request(retryAccess.token, retryConnection);
  }

  void _invalidatePmsRefresh() {
    _pmsRefresh = null;
    _pmsRefreshOperation = null;
    _pmsRefreshServerId = null;
  }

  Future<PlexConnection> _refreshPmsAccess(int operation, String serverId) {
    final active = _pmsRefresh;
    if (active != null &&
        _pmsRefreshOperation == operation &&
        _pmsRefreshServerId == serverId) {
      return active;
    }
    final refresh = _performPmsRefresh(operation, serverId);
    _pmsRefresh = refresh;
    _pmsRefreshOperation = operation;
    _pmsRefreshServerId = serverId;
    return refresh.whenComplete(() {
      if (identical(_pmsRefresh, refresh)) {
        _invalidatePmsRefresh();
      }
    });
  }

  Future<PlexConnection> _performPmsRefresh(
    int operation,
    String serverId,
  ) async {
    final profileToken = _profileToken ?? _accountToken;
    if (profileToken == null) {
      throw const PlexException('auth-required', 'Link Plex first.');
    }
    final discovered = await plex.discoverServers(profileToken);
    final refreshed = discovered
        .where((access) => access.server.id == serverId)
        .firstOrNull;
    if (refreshed == null) {
      throw const PlexException(
        'authorization-unavailable',
        'Plex server authorization is unavailable.',
      );
    }
    final selectedConnection = await plex.selectConnection(
      refreshed.server,
      refreshed.token,
    );
    if (!_isCurrentPmsTarget(operation, serverId) ||
        (_profileToken ?? _accountToken) != profileToken) {
      throw const PlexException(
        'authorization-unavailable',
        'Plex server authorization is unavailable.',
      );
    }
    _serverAccess = {for (final access in discovered) access.server.id: access};
    servers = List.unmodifiable(discovered.map((access) => access.server));
    if (_serverTargetId != serverId) {
      _pmsToken = refreshed.token;
      connection = selectedConnection;
    }
    return selectedConnection;
  }

  Future<bool> _run(
    Future<void> Function() body, {
    required int operation,
    required SetupStage fallbackStage,
  }) async {
    if (!_isCurrent(operation)) return false;
    _busyOperation = operation;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await body();
      return _isCurrent(operation);
    } catch (exception) {
      if (!_isCurrent(operation)) return false;
      error = exception is PlexException
          ? exception.message
          : 'Lineup could not complete that request.';
      stage = fallbackStage;
      diagnostics.add('application', 'Operation failed', {
        'code': exception is PlexException ? exception.code : 'unexpected',
      });
      return false;
    } finally {
      if (!_disposed && _busyOperation == operation) {
        _busyOperation = null;
        busy = false;
        notifyListeners();
      }
    }
  }

  bool _isCurrent(int operation) => !_disposed && operation == _epoch;

  bool _isCurrentPmsTarget(int operation, String serverId) =>
      _isCurrent(operation) &&
      (_serverTargetId == null
          ? server?.id == serverId
          : _serverTargetId == serverId);

  static bool _isPmsAuthorizationError(PlexException exception) => const {
    'auth-invalid',
    'auth-required',
    'access-denied',
  }.contains(exception.code);

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_epoch;
    _pinTimer?.cancel();
    _busyOperation = null;
    busy = false;
    _scheduleWorker?.dispose();
    _serverAccess = const {};
    _pmsToken = null;
    _serverTargetId = null;
    _invalidatePmsRefresh();
    final pin = activePin;
    if (pin == null) {
      plex.close();
    } else {
      unawaited(
        plex.cancelPin(pin).onError((_, _) {}).whenComplete(plex.close),
      );
    }
    super.dispose();
  }
}
