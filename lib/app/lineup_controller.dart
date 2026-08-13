import 'dart:async';

import 'package:flutter/foundation.dart';

import '../channels/channel.dart';
import '../channels/channel_builder.dart';
import '../channels/content_resolver.dart';
import '../channels/scheduler.dart';
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
  LineupPlaybackRequest(this.uri, this._release);

  final Uri uri;
  final Future<void> Function() _release;
  bool _released = false;

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
  }) : diagnostics = diagnostics ?? Diagnostics();

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
  String? error;
  int _epoch = 0;
  String? _accountToken;
  String? _profileToken;
  PersistedState _persisted = const PersistedState();
  Timer? _pinTimer;
  int? _busyOperation;

  Future<void> initialize() async {
    _persisted = await store.load();
    settings = _persisted.settings;
    diagnostics.enabled = settings.diagnosticsEnabled;
    channels = const [];
    currentChannelId = null;
    selectedLibraryIds = const {};
    final token = await credentials.readAccountToken();
    if (token == null) {
      stage = SetupStage.welcome;
      notifyListeners();
      return;
    }
    final operation = ++_epoch;
    await _run(
      () async {
        final restoredAccount = await plex.account(token);
        if (operation != _epoch) return;
        account = restoredAccount;
        _accountToken = token;
        profiles = await plex.homeUsers(token);
        if (operation != _epoch) return;
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
        await _discover(operation);
      },
      operation: operation,
      fallbackStage: SetupStage.welcome,
    );
  }

  Future<void> startLinking() async {
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

  Future<void> cancelLinking() async {
    final pin = activePin;
    ++_epoch;
    _pinTimer?.cancel();
    activePin = null;
    busy = false;
    error = null;
    stage = SetupStage.welcome;
    notifyListeners();
    if (pin != null) await plex.cancelPin(pin);
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
      await credentials.writeAccountToken(token);
      if (operation != _epoch) {
        await credentials.clear();
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
        await credentials.writeProfileToken(selected.id, token);
        if (operation != _epoch) {
          await credentials.clear();
          return;
        }
        final oldProfile = profile;
        final oldProfileToken = _profileToken;
        final oldServer = server;
        final oldConnection = connection;
        final oldLibraries = libraries;
        final oldSelectedLibraries = selectedLibraryIds;
        final oldMedia = availableMedia;
        final oldPlaylists = availablePlaylists;
        final oldChannels = channels;
        final oldCurrent = currentChannelId;
        profile = selected;
        _profileToken = token;
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
          server = oldServer;
          connection = oldConnection;
          libraries = oldLibraries;
          selectedLibraryIds = oldSelectedLibraries;
          availableMedia = oldMedia;
          availablePlaylists = oldPlaylists;
          channels = oldChannels;
          currentChannelId = oldCurrent;
          rethrow;
        }
        await _discover(operation);
      },
      operation: operation,
      fallbackStage: SetupStage.profiles,
    );
  }

  Future<void> _discover(int operation) async {
    final token = _profileToken ?? _accountToken;
    if (token == null) return;
    servers = await plex.discoverServers(token);
    if (operation != _epoch) return;
    stage = SetupStage.servers;
    final profileId = profile?.id ?? account?.id;
    final savedId = profileId == null
        ? null
        : _persisted.selectedServerByProfile[profileId];
    final saved = servers
        .where((candidate) => candidate.id == savedId)
        .firstOrNull;
    if (saved != null) await selectServer(saved);
  }

  Future<void> refreshServers() async {
    final operation = ++_epoch;
    await _run(
      () => _discover(operation),
      operation: operation,
      fallbackStage: SetupStage.servers,
    );
  }

  Future<void> selectServer(PlexServer selected) async {
    final operation = ++_epoch;
    await _run(
      () async {
        final token = _profileToken ?? _accountToken;
        if (token == null) {
          throw const PlexException('auth-required', 'Link Plex first.');
        }
        final selectedConnection = await plex.selectConnection(selected, token);
        final loadedLibraries = await plex.libraries(
          selectedConnection.uri,
          token,
        );
        if (operation != _epoch) return;
        final oldServer = server;
        final oldConnection = connection;
        final oldLibraries = libraries;
        final oldSelectedLibraries = selectedLibraryIds;
        final oldMedia = availableMedia;
        final oldPlaylists = availablePlaylists;
        final oldChannels = channels;
        final oldCurrent = currentChannelId;
        server = selected;
        connection = selectedConnection;
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
          libraries = oldLibraries;
          selectedLibraryIds = oldSelectedLibraries;
          availableMedia = oldMedia;
          availablePlaylists = oldPlaylists;
          channels = oldChannels;
          currentChannelId = oldCurrent;
          rethrow;
        }
        if (selectedLibraryIds.isNotEmpty && channels.isNotEmpty) {
          await _loadLibraries(operation, selectedLibraryIds);
          if (operation != _epoch) return;
          stage = SetupStage.ready;
        } else if (!settings.audioSetupComplete) {
          stage = SetupStage.audio;
        }
      },
      operation: operation,
      fallbackStage: SetupStage.servers,
    );
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
      },
      operation: operation,
      fallbackStage: SetupStage.channelSetup,
    );
  }

  Future<void> _loadLibraries(int operation, Set<String> ids) async {
    final token = _profileToken ?? _accountToken;
    final endpoint = connection?.uri;
    if (token == null || endpoint == null) {
      throw const PlexException('server-unreachable', 'Select a server first.');
    }
    final items = <PlexMediaItem>[];
    for (final id in ids) {
      final library = libraries.firstWhere((library) => library.id == id);
      items.addAll(await plex.libraryItems(endpoint, token, id, library.type));
      if (operation != _epoch) return;
    }
    PlexPlaylistCatalog catalog;
    try {
      catalog = await plex.playlists(endpoint, token);
    } on PlexException catch (exception) {
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

  Future<void> completeAudioSetup({
    required bool externalAudio,
    required bool directPlayFallback,
  }) async {
    try {
      await updateSettings(
        settings.copyWith(
          audioPassthrough: externalAudio,
          directPlayAudioFallback: directPlayFallback,
          audioSetupComplete: true,
        ),
      );
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
    stage = SetupStage.profiles;
    error = null;
    notifyListeners();
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
      ChannelBuildMode.replace => planned,
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

  LineupPlaybackRequest playbackFor(String itemId) {
    final endpoint = connection?.uri;
    final token = _profileToken ?? _accountToken;
    final item = availableMedia
        .where((value) => value.id == itemId)
        .firstOrNull;
    if (endpoint == null || token == null || item == null) {
      throw const PlexException(
        'playback-unavailable',
        'This program is not available from the current Plex session.',
      );
    }
    final descriptor = plex.playbackDescriptor(
      server: endpoint,
      token: token,
      item: item,
      capabilities: const StreamCapabilities(
        containers: {'mkv', 'mp4', 'mpegts', 'avi', 'webm'},
        videoCodecs: {'h264', 'hevc', 'mpeg2video', 'vp9', 'av1'},
        audioCodecs: {'aac', 'ac3', 'eac3', 'dca', 'opus', 'mp3', 'flac'},
        hdr10: true,
        hlg: true,
        dolbyVision: true,
      ),
    );
    final uri = descriptor.uri.replace(
      queryParameters: {
        ...descriptor.uri.queryParameters,
        'X-Plex-Token': token,
      },
    );
    return LineupPlaybackRequest(
      uri,
      () => plex.releasePlaybackSession(
        server: endpoint,
        token: token,
        sessionId: descriptor.sessionId,
      ),
    );
  }

  Future<Uint8List?> artworkFor(ChannelItem item) async {
    final endpoint = connection?.uri;
    final token = _profileToken ?? _accountToken;
    final artwork = item.artwork;
    if (endpoint == null ||
        token == null ||
        artwork == null ||
        artwork.toString().isEmpty) {
      return null;
    }
    return plex.artwork(endpoint, token, artwork);
  }

  Future<void> setCurrentChannel(String id) async {
    if (id == currentChannelId ||
        !channels.any((channel) => channel.id == id)) {
      return;
    }
    final old = currentChannelId;
    currentChannelId = id;
    try {
      await _save();
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
      notifyListeners();
    } catch (_) {
      channels = old;
      currentChannelId = oldCurrent;
      rethrow;
    }
  }

  Future<void> updateSettings(LineupSettings value) async {
    final old = settings;
    settings = value;
    try {
      await _save();
      diagnostics.enabled = value.diagnosticsEnabled;
      notifyListeners();
    } catch (_) {
      settings = old;
      rethrow;
    }
  }

  Future<void> logout() async {
    ++_epoch;
    _pinTimer?.cancel();
    _busyOperation = null;
    busy = false;
    await credentials.clear();
    account = null;
    profile = null;
    profiles = const [];
    servers = const [];
    server = null;
    connection = null;
    libraries = const [];
    availableMedia = const [];
    availablePlaylists = const [];
    selectedLibraryIds = const {};
    channels = const [];
    currentChannelId = null;
    channelSetupCanCancel = false;
    _accountToken = null;
    _profileToken = null;
    stage = SetupStage.welcome;
    error = null;
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
    _persisted = next;
  }

  Future<bool> _run(
    Future<void> Function() body, {
    required int operation,
    required SetupStage fallbackStage,
  }) async {
    _busyOperation = operation;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await body();
      return operation == _epoch;
    } catch (exception) {
      if (operation != _epoch) return false;
      error = exception is PlexException
          ? exception.message
          : 'Lineup could not complete that request.';
      stage = fallbackStage;
      diagnostics.add('application', 'Operation failed', {
        'error': exception.toString(),
      });
      return false;
    } finally {
      if (_busyOperation == operation) {
        _busyOperation = null;
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    ++_epoch;
    _pinTimer?.cancel();
    final pin = activePin;
    if (pin == null) {
      plex.close();
    } else {
      unawaited(plex.cancelPin(pin).whenComplete(plex.close));
    }
    super.dispose();
  }
}
