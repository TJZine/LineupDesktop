import 'dart:async';

import 'package:flutter/foundation.dart';

import '../channels/channel.dart';
import '../channels/channel_builder.dart';
import '../channels/content_resolver.dart';
import '../channels/scheduler.dart';
import '../channels/schedule_worker.dart';
import '../diagnostics/diagnostics.dart';
import '../persistence/app_store.dart';
import '../playback/stream_policy.dart';
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

class LineupPlaybackRequest {
  LineupPlaybackRequest(
    Uri uri,
    this._release, {
    this.plexToken,
    this.authorizationRecovery,
  }) : uri = _withoutPlexToken(uri);

  final Uri uri;
  final String? plexToken;
  final Future<void> Function() _release;
  final Future<LineupPlaybackRequest> Function()? authorizationRecovery;
  bool _released = false;

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

  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _release();
  }
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
  String? error;
  int _epoch = 0;
  String? _accountToken;
  String? _profileToken;
  Map<String, PlexServerAccess> _serverAccess = const {};
  String? _pmsToken;
  String? _serverTargetId;
  Future<void>? _pmsRefresh;
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
  Future<bool>? _logoutFuture;
  int _settingsGeneration = 0;
  int _contentGeneration = 0;
  bool _disposed = false;

  int get contentGeneration => _contentGeneration;

  Future<void> initialize() async {
    final operation = ++_epoch;
    final persisted = await store.load();
    if (!_isCurrent(operation)) return;
    _persisted = persisted;
    settings = _persisted.settings;
    diagnostics.enabled = settings.diagnosticsEnabled;
    channels = const [];
    currentChannelId = null;
    selectedLibraryIds = const {};
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

  Future<void> startLinking() async {
    if (secureCancellationRequired) {
      await cancelLinking();
      return;
    }
    final operation = ++_epoch;
    _pinTimer?.cancel();
    await _run(
      () async {
        final pin = await plex.createPin();
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
        'error': exception.toString(),
      });
    }
    if (pin != null) {
      try {
        await plex.cancelPin(pin);
      } catch (exception) {
        diagnostics.add('plex-auth', 'PIN cancellation failed', {
          'error': exception.toString(),
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
      if (operation == _epoch && activePin?.id == pin.id) {
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
      if (!await _writeCredential(
        operation,
        () => credentials.writeAccountToken(token),
      )) {
        return;
      }
      account = validated;
      _accountToken = token;
      profiles = await plex.homeUsers(token);
      if (operation != _epoch) return;
      activePin = null;
      if (profiles.length > 1) {
        stage = SetupStage.profiles;
      } else if (profiles.length == 1) {
        await selectProfile(profiles.single);
      } else {
        _profileToken = token;
        await _discover(operation);
      }
      notifyListeners();
    } catch (exception) {
      diagnostics.add('plex-auth', 'PIN poll failed', {
        'error': exception.toString(),
      });
    }
  }

  Future<void> selectProfile(PlexHomeUser selected, {String? pin}) async {
    final operation = ++_epoch;
    _pmsRefresh = null;
    _pmsRefreshOperation = null;
    _pmsRefreshServerId = null;
    _serverTargetId = null;
    _pinTimer?.cancel();
    await _run(
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
        _pmsRefresh = null;
        _pmsRefreshOperation = null;
        _pmsRefreshServerId = null;
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
        if (!_isCurrent(operation)) return;
        _contentGeneration++;
        notifyListeners();
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
    _pmsRefresh = null;
    _pmsRefreshOperation = null;
    _pmsRefreshServerId = null;
    _serverTargetId = null;
    await _run(
      () => _discover(operation),
      operation: operation,
      fallbackStage: SetupStage.servers,
    );
  }

  Future<void> selectServer(PlexServer selected) async {
    final operation = ++_epoch;
    _pmsRefresh = null;
    _pmsRefreshOperation = null;
    _pmsRefreshServerId = null;
    _serverTargetId = selected.id;
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
    final succeeded = await _run(
      () async {
        final selectedConnection = await _withPmsAuthorization(
          operation,
          selected.id,
          (token, _) => plex.selectConnection(
            _serverAccess[selected.id]?.server ?? selected,
            token,
          ),
          connectionIsResult: true,
        );
        if (!_isCurrent(operation)) return;
        _pmsToken = _serverAccess[selected.id]!.token;
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
        serverSelectionCanCancel = false;
        notifyListeners();
        server = _serverAccess[selected.id]?.server ?? selected;
        connection = workingConnection;
        libraries = loadedLibraries;
        final profileId = profile?.id ?? account?.id;
        final savedLibraries = profileId == null
            ? const <String>[]
            : _persisted.selectedLibraryIdsByProfileServer[profileId]?[selected
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
            : _persisted.currentChannelByProfileServer[profileId]?[selected.id];
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
        if (!_isCurrent(operation)) return;
        _contentGeneration++;
        notifyListeners();
        if (selectedLibraryIds.isNotEmpty && channels.isNotEmpty) {
          await _loadLibraries(operation, selectedLibraryIds);
          if (operation != _epoch) return;
          stage = SetupStage.ready;
        } else if (!settings.audioSetupComplete) {
          stage = SetupStage.audio;
        }
        serverSelectionCanCancel = false;
      },
      operation: operation,
      fallbackStage: SetupStage.servers,
    );
    if (!succeeded && _isCurrent(operation)) {
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
    }
    if (_serverTargetId == selected.id) _serverTargetId = null;
  }

  Future<bool> setLibraries(Set<String> ids) async {
    final operation = ++_epoch;
    return _run(
      () async {
        final allowed = libraries.map((library) => library.id).toSet();
        if (ids.isEmpty || !allowed.containsAll(ids)) {
          throw const PlexException(
            'invalid-library',
            'Select one or more libraries from the current server.',
          );
        }
        final oldSelectedLibraries = selectedLibraryIds;
        final oldMedia = availableMedia;
        final oldPlaylists = availablePlaylists;
        await _loadLibraries(operation, ids);
        if (operation != _epoch) return;
        selectedLibraryIds = Set.unmodifiable(ids);
        try {
          await _save();
        } catch (_) {
          selectedLibraryIds = oldSelectedLibraries;
          availableMedia = oldMedia;
          availablePlaylists = oldPlaylists;
          rethrow;
        }
        if (!_isCurrent(operation)) return;
        _contentGeneration++;
        notifyListeners();
      },
      operation: operation,
      fallbackStage: SetupStage.channelSetup,
    );
  }

  Future<void> _loadLibraries(int operation, Set<String> ids) async {
    final selectedServer = server;
    if (selectedServer == null || connection == null) {
      throw const PlexException('server-unreachable', 'Select a server first.');
    }
    final items = <PlexMediaItem>[];
    for (final id in ids) {
      final library = libraries.firstWhere((library) => library.id == id);
      items.addAll(
        await _withPmsAuthorization(
          operation,
          selectedServer.id,
          (token, refreshedConnection) => plex.libraryItems(
            (refreshedConnection ?? connection!).uri,
            token,
            id,
            library.type,
          ),
        ),
      );
      if (operation != _epoch) return;
    }
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
        'error': exception.toString(),
      });
      catalog = const PlexPlaylistCatalog(playlists: [], failedIds: {});
    }
    if (operation != _epoch) return;
    final required = channels
        .map((channel) => channel.source)
        .whereType<PlaylistSource>()
        .map((source) => source.playlistId)
        .toSet();
    if (catalog.failedIds.any(required.contains)) {
      throw const PlexException(
        'playlist-unavailable',
        'A playlist used by this lineup could not be loaded. Retry setup.',
      );
    }
    if (catalog.failedIds.isNotEmpty) {
      diagnostics.add('plex-library', 'Some playlists could not be loaded', {
        'count': catalog.failedIds.length,
      });
    }
    availableMedia = List.unmodifiable(
      items.where((item) => item.duration > Duration.zero),
    );
    availablePlaylists = catalog.playlists;
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
        'error': exception.toString(),
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
      _pmsRefresh = null;
      _pmsRefreshOperation = null;
      _pmsRefreshServerId = null;
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
      _pmsRefresh = null;
      _pmsRefreshOperation = null;
      _pmsRefreshServerId = null;
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
    final profileId = profile?.id ?? account?.id;
    if (profileId == null) return;
    final operation = ++_epoch;
    await _run(
      () async {
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
        if (operation != _epoch) return;
        _persisted = next;
        _clearServerRuntime();
        serverSelectionCanCancel = false;
        stage = SetupStage.servers;
      },
      operation: operation,
      fallbackStage: SetupStage.servers,
    );
  }

  Future<void> applyChannelPlan(
    List<Channel> planned, {
    required ChannelBuildMode mode,
  }) async {
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
      stage = SetupStage.ready;
      notifyListeners();
    } catch (_) {
      channels = oldChannels;
      currentChannelId = oldCurrent;
      rethrow;
    }
  }

  Future<void> saveChannel(Channel channel) async {
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
    final descriptor = plex.playbackDescriptor(
      server: endpoint,
      item: item,
      capabilities: const StreamCapabilities.unrestricted(),
    );
    diagnostics.add('playback', 'Plex playback selected', {
      'mode': descriptor.decision.kind.name,
      'container': item.container,
      'videoCodec': item.videoCodec,
      'audioCodec': item.audioCodec,
      'dynamicRange': item.dynamicRange.name,
      'reason': descriptor.decision.reasons.join(','),
    });
    return LineupPlaybackRequest(
      descriptor.uri,
      () => plex.releasePlaybackSession(
        server: endpoint,
        token: token,
        sessionId: descriptor.sessionId,
      ),
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
    final artwork = item.artwork;
    return artwork == null ? null : artworkForPath(artwork);
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
  }

  Future<void> deleteChannel(String id) async {
    final old = channels;
    final oldCurrent = currentChannelId;
    final removedIndex = channels.indexWhere((channel) => channel.id == id);
    channels = List.unmodifiable(channels.where((channel) => channel.id != id));
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
  }

  Future<void> updateSettings(LineupSettings value) async {
    final generation = ++_settingsGeneration;
    final old = settings;
    settings = value;
    try {
      await _save();
      if (generation != _settingsGeneration) return;
      diagnostics.enabled = value.diagnosticsEnabled;
      notifyListeners();
    } catch (_) {
      if (generation == _settingsGeneration) settings = old;
      rethrow;
    }
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
    _pmsRefresh = null;
    _pmsRefreshOperation = null;
    _pmsRefreshServerId = null;
    _serverTargetId = null;
    _pinTimer?.cancel();
    _busyOperation = null;
    busy = true;
    notifyListeners();
    try {
      await _clearCredentials();
    } catch (exception) {
      if (_disposed) return false;
      error = 'Lineup could not securely sign out. Check system credential storage and try again.';
      diagnostics.add('application', 'Credential cleanup failed', {
        'error': exception.toString(),
      });
      return false;
    }
    if (_disposed) return false;
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
    _pmsRefresh = null;
    _pmsRefreshOperation = null;
    _pmsRefreshServerId = null;
    secureCancellationRequired = false;
    _contentGeneration++;
    stage = SetupStage.welcome;
    error = null;
    return true;
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
    _pmsRefresh = null;
    _pmsRefreshOperation = null;
    _pmsRefreshServerId = null;
    libraries = const [];
    selectedLibraryIds = const {};
    availableMedia = const [];
    availablePlaylists = const [];
    channels = const [];
    currentChannelId = null;
    _scheduleWorker?.dispose();
    _scheduleWorker = null;
    _scheduleWorkerMedia = null;
    _scheduleWorkerPlaylists = null;
    _contentGeneration++;
  }

  Future<T> _withPmsAuthorization<T>(
    int operation,
    String serverId,
    Future<T> Function(String token, PlexConnection? connection) request, {
    PlexConnection? connectionOverride,
    bool connectionIsResult = false,
  }) async {
    final access = _serverAccess[serverId];
    if (access == null || access.token.isEmpty) {
      throw const PlexException(
        'authorization-unavailable',
        'Plex server authorization is unavailable.',
      );
    }
    try {
      return await request(access.token, connectionOverride);
    } on PlexException catch (exception) {
      if (!_isPmsAuthorizationError(exception)) rethrow;
      await _refreshPmsAccess(operation, serverId);
      if (!_isCurrentPmsTarget(operation, serverId)) {
        throw const PlexException(
          'authorization-unavailable',
          'Plex server authorization is unavailable.',
        );
      }
      final refreshed = _serverAccess[serverId];
      final refreshedConnection = connection;
      if (refreshed == null || refreshedConnection == null) {
        throw const PlexException(
          'authorization-unavailable',
          'Plex server authorization is unavailable.',
        );
      }
      if (connectionIsResult) return refreshedConnection as T;
      return request(refreshed.token, refreshedConnection);
    }
  }

  Future<void> _refreshPmsAccess(int operation, String serverId) {
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
        _pmsRefresh = null;
        _pmsRefreshOperation = null;
        _pmsRefreshServerId = null;
      }
    });
  }

  Future<void> _performPmsRefresh(int operation, String serverId) async {
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
    _pmsToken = refreshed.token;
    connection = selectedConnection;
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
        'error': exception.toString(),
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
    ++_settingsGeneration;
    _pinTimer?.cancel();
    _busyOperation = null;
    busy = false;
    _scheduleWorker?.dispose();
    _serverAccess = const {};
    _pmsToken = null;
    _serverTargetId = null;
    _pmsRefresh = null;
    _pmsRefreshOperation = null;
    _pmsRefreshServerId = null;
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
