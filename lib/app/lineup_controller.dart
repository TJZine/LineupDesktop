import 'dart:async';

import 'package:flutter/foundation.dart';

import '../channels/channel.dart';
import '../channels/content_resolver.dart';
import '../channels/scheduler.dart';
import '../diagnostics/diagnostics.dart';
import '../persistence/app_store.dart';
import '../plex/plex_client.dart';
import '../plex/plex_models.dart';
import '../settings/lineup_settings.dart';

enum SetupStage { welcome, linking, profiles, servers, libraries, ready }

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
  PlexPin? activePin;
  SetupStage stage = SetupStage.welcome;
  bool busy = false;
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
    channels = List.unmodifiable(_persisted.channels);
    currentChannelId = _persisted.currentChannelId;
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
      if (operation != _epoch) return;
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
        if (operation != _epoch) return;
        final oldProfile = profile;
        final oldProfileToken = _profileToken;
        final oldServer = server;
        final oldConnection = connection;
        final oldLibraries = libraries;
        final oldSelectedLibraries = selectedLibraryIds;
        final oldMedia = availableMedia;
        profile = selected;
        _profileToken = token;
        server = null;
        connection = null;
        libraries = const [];
        selectedLibraryIds = const {};
        availableMedia = const [];
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
        stage = SetupStage.libraries;
        try {
          await _save();
        } catch (_) {
          server = oldServer;
          connection = oldConnection;
          libraries = oldLibraries;
          selectedLibraryIds = oldSelectedLibraries;
          availableMedia = oldMedia;
          rethrow;
        }
      },
      operation: operation,
      fallbackStage: SetupStage.servers,
    );
  }

  Future<void> setLibraries(Set<String> ids) async {
    final operation = ++_epoch;
    await _run(
      () async {
        final token = _profileToken ?? _accountToken;
        final endpoint = connection?.uri;
        if (token == null || endpoint == null) {
          throw const PlexException(
            'server-unreachable',
            'Select a server first.',
          );
        }
        final allowed = libraries.map((library) => library.id).toSet();
        if (ids.isEmpty || !allowed.containsAll(ids)) {
          throw const PlexException(
            'invalid-library',
            'Select one or more libraries from the current server.',
          );
        }
        final items = <PlexMediaItem>[];
        for (final id in ids) {
          items.addAll(await plex.libraryItems(endpoint, token, id));
          if (operation != _epoch) return;
        }
        final nextMedia = List<PlexMediaItem>.unmodifiable(
          items.where((item) => item.duration > Duration.zero),
        );
        final oldSelectedLibraries = selectedLibraryIds;
        final oldMedia = availableMedia;
        selectedLibraryIds = Set.unmodifiable(ids);
        availableMedia = nextMedia;
        try {
          await _save();
          stage = SetupStage.ready;
        } catch (_) {
          selectedLibraryIds = oldSelectedLibraries;
          availableMedia = oldMedia;
          rethrow;
        }
      },
      operation: operation,
      fallbackStage: SetupStage.libraries,
    );
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
    resolveContent(channel.source, availableMedia),
    mode: channel.playbackMode,
    seed: channel.shuffleSeed,
    blockSize: channel.blockSize ?? 3,
  );

  Future<void> deleteChannel(String id) async {
    final old = channels;
    final oldCurrent = currentChannelId;
    channels = List.unmodifiable(channels.where((channel) => channel.id != id));
    if (currentChannelId == id) currentChannelId = channels.firstOrNull?.id;
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
    if (profileId != null && server != null) {
      selectedServers[profileId] = server!.id;
      librarySelections.putIfAbsent(profileId, () => {})[server!.id] =
          selectedLibraryIds.toList();
    }
    final next = PersistedState(
      settings: settings,
      channels: channels,
      currentChannelId: currentChannelId,
      profileId: profile?.id,
      selectedServerByProfile: selectedServers,
      selectedLibraryIdsByProfileServer: librarySelections,
    );
    await store.save(next);
    _persisted = next;
  }

  Future<void> _run(
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
    } catch (exception) {
      if (operation != _epoch) return;
      error = exception is PlexException
          ? exception.message
          : 'Lineup could not complete that request.';
      stage = fallbackStage;
      diagnostics.add('application', 'Operation failed', {
        'error': exception.toString(),
      });
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
