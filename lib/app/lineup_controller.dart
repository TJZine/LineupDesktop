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
  }) : diagnostics = diagnostics ?? Diagnostics();

  final AppStore store;
  final CredentialStore credentials;
  final PlexClient plex;
  final Diagnostics diagnostics;

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

  Future<void> initialize() async {
    _persisted = await store.load();
    settings = _persisted.settings;
    channels = List.unmodifiable(_persisted.channels);
    currentChannelId = _persisted.currentChannelId;
    selectedLibraryIds = _persisted.selectedLibraryIds.toSet();
    final token = await credentials.readAccountToken();
    if (token == null) {
      stage = SetupStage.welcome;
      notifyListeners();
      return;
    }
    final operation = ++_epoch;
    await _run(() async {
      final restoredAccount = await plex.account(token);
      if (operation != _epoch) return;
      account = restoredAccount;
      _accountToken = token;
      profiles = await plex.homeUsers(token);
      if (operation != _epoch) return;
      final profileId = _persisted.profileId;
      if (profileId != null) {
        profile = profiles
            .where((candidate) => candidate.id == profileId)
            .firstOrNull;
        _profileToken = await credentials.readProfileToken(profileId) ?? token;
      }
      await _discover(operation);
    }, fallbackStage: SetupStage.welcome);
  }

  Future<void> startLinking() async {
    final operation = ++_epoch;
    _pinTimer?.cancel();
    await _run(() async {
      final pin = await plex.createPin();
      if (operation != _epoch) return;
      activePin = pin;
      stage = SetupStage.linking;
      notifyListeners();
      _pinTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _pollPin(operation, pin),
      );
    }, fallbackStage: SetupStage.welcome);
  }

  Future<void> _pollPin(int operation, PlexPin pin) async {
    if (busy || operation != _epoch) return;
    if (DateTime.now().isAfter(pin.expiresAt)) {
      _pinTimer?.cancel();
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
    await _run(() async {
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
      profile = selected;
      _profileToken = token;
      server = null;
      connection = null;
      libraries = const [];
      availableMedia = const [];
      await _save();
      await _discover(operation);
    }, fallbackStage: SetupStage.profiles);
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
    await _run(() => _discover(operation), fallbackStage: SetupStage.servers);
  }

  Future<void> selectServer(PlexServer selected) async {
    final operation = ++_epoch;
    await _run(() async {
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
      server = selected;
      connection = selectedConnection;
      libraries = loadedLibraries;
      availableMedia = const [];
      stage = SetupStage.libraries;
      await _save();
    }, fallbackStage: SetupStage.servers);
  }

  Future<void> setLibraries(Set<String> ids) async {
    final operation = ++_epoch;
    await _run(() async {
      final token = _profileToken ?? _accountToken;
      final endpoint = connection?.uri;
      if (token == null || endpoint == null) {
        throw const PlexException(
          'server-unreachable',
          'Select a server first.',
        );
      }
      final items = <PlexMediaItem>[];
      for (final id in ids) {
        items.addAll(await plex.libraryItems(endpoint, token, id));
        if (operation != _epoch) return;
      }
      selectedLibraryIds = Set.unmodifiable(ids);
      availableMedia = List.unmodifiable(
        items.where((item) => item.duration > Duration.zero),
      );
      stage = SetupStage.ready;
      await _save();
    }, fallbackStage: SetupStage.libraries);
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
      notifyListeners();
    } catch (_) {
      settings = old;
      rethrow;
    }
  }

  Future<void> logout() async {
    ++_epoch;
    _pinTimer?.cancel();
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
    if (profileId != null && server != null) {
      selectedServers[profileId] = server!.id;
    }
    _persisted = PersistedState(
      settings: settings,
      channels: channels,
      currentChannelId: currentChannelId,
      profileId: profile?.id,
      profileName: profile?.name,
      selectedServerByProfile: selectedServers,
      selectedLibraryIds: selectedLibraryIds.toList(),
    );
    await store.save(_persisted);
  }

  Future<void> _run(
    Future<void> Function() operation, {
    required SetupStage fallbackStage,
  }) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await operation();
    } catch (exception) {
      error = exception is PlexException
          ? exception.message
          : 'Lineup could not complete that request.';
      stage = fallbackStage;
      diagnostics.add('application', 'Operation failed', {
        'error': exception.toString(),
      });
    } finally {
      busy = false;
      notifyListeners();
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
