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

part 'library_scan_state.dart';
part 'lineup_scenario.dart';

enum SetupStage { welcome, linking, profiles, servers, channelSetup, ready }

enum ChannelPlanApplyResult { applied, stale }

@immutable
class _PickerOrigin {
  const _PickerOrigin({
    required this.stage,
    this.restoring = false,
    this.canCancelSetup = false,
  });

  final SetupStage stage;
  final bool restoring;
  final bool canCancelSetup;
}

@immutable
class _ServerSelection {
  const _ServerSelection({
    required this.state,
    required this.access,
    required this.connection,
    required this.libraries,
    required this.lineup,
  });
  final PersistedState state;
  final PlexServerAccess access;
  final PlexConnection connection;
  final List<PlexLibrary> libraries;
  final ScopedLineup lineup;
}

@immutable
class _ProfileSelection {
  const _ProfileSelection({
    required this.state,
    required this.profile,
    required this.token,
  });
  final PersistedState state;
  final PlexHomeUser profile;
  final String token;
}

final class LineupScopeSuperseded implements Exception {
  const LineupScopeSuperseded();
}

class ChannelStateConflictException extends FormatException {
  const ChannelStateConflictException()
    : super('The lineup changed. Review the current channels and try again.');
}

Iterable<String> _playlistIds(ContentSource source) sync* {
  if (source case PlaylistSource(:final playlistId)) {
    yield playlistId;
  } else if (source case MixedSource(:final sources)) {
    for (final nested in sources) {
      yield* _playlistIds(nested);
    }
  }
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
    DateTime Function()? scheduleClock,
    LineupScenario? scenario,
  }) : diagnostics = diagnostics ?? Diagnostics(),
       _scheduleWorkerFactory = scheduleWorkerFactory ?? ScheduleWorker.new,
       _scheduleClock = scheduleClock ?? DateTime.now,
       _ownsDiagnostics = diagnostics == null {
    if (scenario != null) installScenario(scenario);
  }

  bool _scenarioInstalled = false;
  bool _scenarioOpen = true;

  @visibleForTesting
  LineupFixtureActor get fixtureActor => LineupFixtureActor._(this);

  /// Installs a credential-free starting scenario before this controller runs.
  /// Later changes must use commands; this boundary cannot reset live lifetimes.
  @visibleForTesting
  void installScenario(LineupScenario scenario) {
    if (!_scenarioOpen ||
        _scenarioInstalled ||
        _epoch != 0 ||
        _mutationScope != 0 ||
        _disposed ||
        _nextChannelRevision != 0) {
      throw StateError('A scenario requires a fresh inactive controller');
    }
    final channelValues = scenario.channels ?? const <Channel>[];
    final libraryValues = scenario.libraries ?? const <PlexLibrary>[];
    if (scenario.currentChannelId != null &&
        !channelValues.any(
          (channel) => channel.id == scenario.currentChannelId,
        )) {
      throw ArgumentError('Current channel must belong to the lineup');
    }
    if (!libraryValues
        .map((library) => library.id)
        .toSet()
        .containsAll(scenario.selectedLibraryIds ?? const {})) {
      throw ArgumentError('Selected libraries must belong to the inventory');
    }
    if (scenario.profileSelectionOrigin != null &&
            scenario.stage != SetupStage.profiles ||
        scenario.serverSelectionOrigin != null &&
            scenario.stage != SetupStage.servers) {
      throw ArgumentError('Picker origin requires its picker');
    }
    if (!libraryValues
        .map((library) => library.id)
        .toSet()
        .containsAll(
          (scenario.scanFacts ?? const <String, LibraryScanFact>{}).keys,
        )) {
      throw ArgumentError('Scan rows must belong to the inventory');
    }
    _scenarioInstalled = true;
    _settings = scenario.settings ?? const LineupSettings();
    diagnostics.enabled = settings.diagnosticsEnabled;
    _publishLineup(
      ScopedLineup(
        libraryIds: scenario.selectedLibraryIds ?? const {},
        channels: scenario.channels ?? const [],
        currentChannelId: scenario.currentChannelId,
      ),
    );
    _account = scenario.account;
    _profile = scenario.profile;
    _publishProfiles = scenario.profiles ?? const [];
    _publishServers = scenario.servers ?? const [];
    _publishServer = scenario.server;
    _connection = scenario.connection;
    _publishLibraries = scenario.libraries ?? const [];
    _publishAvailableMedia = scenario.availableMedia ?? const [];
    _publishAvailablePlaylists = scenario.availablePlaylists ?? const [];
    _activePin = scenario.activePin;
    _stage = scenario.stage ?? SetupStage.welcome;
    _busy = scenario.busy ?? false;
    _channelSetupCanCancel = scenario.channelSetupCanCancel ?? false;
    _profileSelectionCanCancel = scenario.profileSelectionOrigin != null;
    _serverSelectionCanCancel = scenario.serverSelectionOrigin != null;
    _profilePickerOrigin = scenario.profileSelectionOrigin == null
        ? null
        : _PickerOrigin(stage: scenario.profileSelectionOrigin!);
    _serverPickerOrigin = scenario.serverSelectionOrigin == null
        ? null
        : _PickerOrigin(stage: scenario.serverSelectionOrigin!);
    _restoringSavedLineup = scenario.restoringSavedLineup ?? false;
    _secureCancellationRequired = scenario.secureCancellationRequired ?? false;
    _error = scenario.error;
    _startupRecoveryNotice = scenario.startupRecoveryNotice;
    if (scenario.server != null ||
        availableMedia.isNotEmpty ||
        availablePlaylists.isNotEmpty) {
      _contentGeneration = 1;
    }
    _scan.installScenario(
      scenario.scanFacts ?? const {},
      scenario.libraryScanStatus ?? LibraryScanStatus.idle,
      _mutationScope,
      profile?.id,
      server?.id,
    );
  }

  final AppStore store;
  final CredentialStore credentials;
  final PlexClient plex;
  final Diagnostics diagnostics;
  final bool _ownsDiagnostics;
  @visibleForTesting
  final Duration pinPollInterval;

  LineupSettings _settings = const LineupSettings();
  LineupSettings get settings => _settings;
  ScopedLineup _lineup = ScopedLineup.empty;
  List<Channel> get channels => _lineup.channels;
  String? get currentChannelId => _lineup.currentChannelId;
  PlexAccount? _account;
  PlexAccount? get account => _account;
  PlexHomeUser? _profile;
  PlexHomeUser? get profile => _profile;
  List<PlexHomeUser> _profiles = const [];
  List<PlexHomeUser> get profiles => _profiles;
  set _publishProfiles(List<PlexHomeUser> value) =>
      _profiles = List.unmodifiable(value);
  List<PlexServer> _servers = const [];
  List<PlexServer> get servers => _servers;
  set _publishServers(List<PlexServer> value) => _servers = List.unmodifiable(
    value.map((server) => server.immutableCopy()),
  );
  PlexServer? _server;
  PlexServer? get server => _server;
  set _publishServer(PlexServer? value) => _server = value?.immutableCopy();
  PlexConnection? _connection;
  PlexConnection? get connection => _connection;
  List<PlexLibrary> _libraries = const [];
  List<PlexLibrary> get libraries => _libraries;
  set _publishLibraries(List<PlexLibrary> value) =>
      _libraries = List.unmodifiable(value);
  Set<String> get selectedLibraryIds => _lineup.libraryIds;
  List<PlexMediaItem> _availableMedia = const [];
  List<PlexMediaItem> get availableMedia => _availableMedia;
  set _publishAvailableMedia(List<PlexMediaItem> value) => _availableMedia =
      List.unmodifiable(value.map((item) => item.immutableCopy()));
  List<PlexPlaylist> _availablePlaylists = const [];
  List<PlexPlaylist> get availablePlaylists => _availablePlaylists;
  set _publishAvailablePlaylists(List<PlexPlaylist> value) =>
      _availablePlaylists = List.unmodifiable(
        value.map((playlist) => playlist.immutableCopy()),
      );
  PlexPin? _activePin;
  PlexPin? get activePin => _activePin;
  SetupStage _stage = SetupStage.welcome;
  SetupStage get stage => _stage;
  bool _busy = false;
  bool get busy => _busy;
  bool _channelSetupCanCancel = false;
  bool get channelSetupCanCancel => _channelSetupCanCancel;
  bool _profileSelectionCanCancel = false;
  bool get profileSelectionCanCancel => _profileSelectionCanCancel;
  bool _serverSelectionCanCancel = false;
  bool get serverSelectionCanCancel => _serverSelectionCanCancel;
  bool _setupStateCommitInProgress = false;

  /// Discovery and scans can be cancelled; a started state commit cannot.
  bool get canSwitchServer => !_setupStateCommitInProgress;

  /// The immediate stage to which a cancellable profile picker returns.
  SetupStage? get profileSelectionOriginStage => _profilePickerOrigin?.stage;

  bool _restoringSavedLineup = false;
  bool get restoringSavedLineup => _restoringSavedLineup;
  _PickerOrigin? _profilePickerOrigin;
  _PickerOrigin? _serverPickerOrigin;
  bool _secureCancellationRequired = false;
  bool get secureCancellationRequired => _secureCancellationRequired;
  final _LibraryScanState _scan = _LibraryScanState();
  LibraryScanStatus get libraryScanStatus => _scan.currentStatus;
  int get libraryScanCompletedPages => _scan.completedPages;
  int get libraryScanCompletedItems => _scan.completedItems;
  int? get libraryScanTotalItems => _scan.totalItems;
  PlexPlaylistProgress? get playlistScanProgress => _scan.playlistProgress;
  String? _error;
  String? get error => _error;
  int _epoch = 0;
  int _authorizationScope = 0;
  int _mutationScope = 0;
  int _mutationEligibility = 0;
  Future<PlexConnection>? _playbackRefresh;
  int? _playbackRefreshScope;
  Set<String> get _unavailableCollectionLibraryIds =>
      _scan.collectionDiscoveryFailures.keys.toSet();
  bool get playlistCatalogUnavailable => _scan.catalogUnavailable;
  Set<String> get failedPlaylistIds => _scan.failedPlaylistIds;

  /// Absence is meaningful only after every dependency was scanned completely.
  bool isGeneratedSourceConfirmedGone(Channel channel) {
    if (channel.builderKey == null ||
        _scan.discoveryObsolete ||
        _scan.currentStatus == LibraryScanStatus.scanning ||
        _scan.currentStatus == LibraryScanStatus.cancelled ||
        !_sourceDiscoveryComplete(channel.source)) {
      return false;
    }
    final pending = _scan.readiness;
    if (pending != null &&
        resolveContent(
          channel.source,
          pending.media,
          pending.playlists,
        ).isNotEmpty) {
      return false;
    }
    final inventory = playableInventory;
    return resolveContent(
      channel.source,
      inventory.media,
      inventory.playlists,
    ).isEmpty;
  }

  bool _sourceDiscoveryComplete(ContentSource source) => switch (source) {
    LibrarySource(:final libraryId, :final filters) =>
      selectedLibraryIds.contains(libraryId) &&
          const {
            LibraryScanStatus.complete,
            LibraryScanStatus.empty,
            LibraryScanStatus.unsupported,
          }.contains(libraryScanFacts[libraryId]?.status) &&
          !(filters[LibraryFilter.collection]?.isNotEmpty == true &&
              (unavailableCollectionLibraryIds.contains(libraryId) ||
                  filters[LibraryFilter.collection]!.any(
                    (title) =>
                        failedCollectionTitles[libraryId]?.contains(title) ??
                        false,
                  ))),
    PlaylistSource(:final playlistId) =>
      !playlistCatalogUnavailable &&
          !failedPlaylistIds.contains(playlistId) &&
          libraryScanStatus != LibraryScanStatus.scanning &&
          libraryScanStatus != LibraryScanStatus.cancelled,
    MixedSource(:final sources) =>
      sources.isNotEmpty && sources.every(_sourceDiscoveryComplete),
    ManualSource() => false,
  };

  Map<String, Set<String>> get failedCollectionTitles =>
      _scan.failedCollectionTitles;
  Set<String> get unavailableCollectionLibraryIds =>
      Set.unmodifiable(collectionDiscoveryFailures.keys);
  Map<String, PlexCollectionFailure> get collectionDiscoveryFailures =>
      _scan.collectionDiscoveryFailures;

  /// Scale exhaustion requires a changed inventory before another scan helps.
  String? collectionScaleRecovery(Set<String> libraryIds) =>
      _collectionScaleRecovery(
        collectionDiscoveryFailures,
        libraryIds
            .where(
              (id) => !const {
                LibraryScanStatus.scanning,
                LibraryScanStatus.idle,
              }.contains(libraryScanFacts[id]?.status),
            )
            .toSet(),
      );

  String? _collectionScaleRecovery(
    Map<String, PlexCollectionFailure> failures,
    Set<String> libraryIds,
  ) {
    final reasons = libraryIds.map((id) => failures[id]).toSet();
    final limits = [
      if (reasons.contains(PlexCollectionFailure.listingLimitExceeded))
        '${PlexClient.maximumLibraryCollections} collection listing records per listing',
      if (reasons.contains(PlexCollectionFailure.memberLimitExceeded))
        '${PlexClient.maximumLibraryCollectionMembers} collection member occurrences per library scan (including repeats and replacement reads)',
      if (reasons.contains(PlexCollectionFailure.pagingLimitExceeded))
        '${PlexClient.maximumLibraryMetadataPages} pages per collection listing or member stream',
    ];
    if (limits.isEmpty) return null;
    return 'Collection discovery exceeds the supported limit of ${limits.join(' or ')}. '
        'Reduce the collection inventory in Plex before rescanning. Saved channels are preserved.';
  }

  /// Items take precedence while any library is paging (or waiting to page).
  PlexLibraryScanPhase get libraryScanPhase => _scan.phase;

  Set<String> get libraryScanReadyIds => _scan.readyIds(_mutationScope);

  /// Item readiness is retained independently of required-source availability.
  /// Use the same facts as the commit guards when offering a ready subset.
  Set<String> get libraryScanCommittableIds {
    if (libraryScanStatus == LibraryScanStatus.scanning ||
        _requiredPlaylistIds().any(failedPlaylistIds.contains) ||
        (playlistCatalogUnavailable && _requiredPlaylistIds().isNotEmpty)) {
      return const {};
    }
    final blocked = _unavailableRequiredCollectionIds(
      failedCollectionTitles,
      unavailableCollectionLibraryIds,
    );
    return Set.unmodifiable(libraryScanReadyIds.difference(blocked));
  }

  Set<String> get libraryScanRetryIds => _scan.retryIds;
  String? get savedServerId =>
      _persisted.selectedServerByProfile[profile?.id ?? account?.id];
  String? _accountToken;
  String? _profileToken;
  Map<String, PlexServerAccess> _serverAccess = const {};
  String? _pmsToken;
  String? _serverTargetId;
  Future<PlexConnection>? _pmsRefresh;
  int? _pmsRefreshOperation;
  String? _pmsRefreshServerId;
  PersistedState _persisted = PersistedState.empty;
  Timer? _pinTimer;
  int? _busyOperation;
  List<PlexMediaItem>? _scheduleWorkerMedia;
  List<PlexPlaylist>? _scheduleWorkerPlaylists;
  ScheduleWorker? _scheduleWorker;
  Uri? _playableEndpoint;
  List<PlexMediaItem>? _playableSourceMedia;
  List<PlexPlaylist>? _playableSourcePlaylists;
  List<PlexMediaItem> _playableMedia = const [];
  List<PlexPlaylist> _playablePlaylists = const [];
  Map<String, PlexMediaItem> _playableById = const {};
  final ScheduleWorkerFactory _scheduleWorkerFactory;
  final DateTime Function() _scheduleClock;
  Future<void> _credentialOperations = Future.value();
  Future<void> _stateOperations = Future.value();
  Future<bool>? _logoutFuture;
  int _contentGeneration = 0;
  int _nextChannelRevision = 0;
  final Map<String, int> _channelRevisions = {};
  bool _disposed = false;

  String? _startupRecoveryNotice;
  String? get startupRecoveryNotice => _startupRecoveryNotice;

  int get contentGeneration => _contentGeneration;

  int channelRevision(String id) => _channelRevisions[id] ?? 0;

  ({
    List<PlexMediaItem> media,
    List<PlexPlaylist> playlists,
    Map<String, PlexMediaItem> byId,
  })
  get playableInventory {
    _ensurePlayableInventory();
    return (
      media: _playableMedia,
      playlists: _playablePlaylists,
      byId: _playableById,
    );
  }

  Map<String, LibraryScanFact> get libraryScanFacts => _scan.facts;

  Future<void> initialize() async {
    _scenarioOpen = false;
    _retireScope();
    final operation = _invalidateOperation();
    final loadResult = await store.load();
    if (!_isCurrent(operation)) return;
    _persisted = loadResult.state;
    _startupRecoveryNotice = loadResult.recoveredCorruptState
        ? 'Saved app data was corrupt and has been reset.'
        : null;
    _settings = _persisted.settings;
    diagnostics.enabled = settings.diagnosticsEnabled;
    _publishEmptyLineup();
    _resetSetupDiscovery();
    final token = await credentials.readAccountToken();
    if (!_isCurrent(operation)) return;
    if (token == null) {
      _stage = SetupStage.welcome;
      notifyListeners();
      return;
    }
    await _run(
      () async {
        final restoredAccount = await plex.account(token);
        if (operation != _epoch) return;
        _account = restoredAccount;
        _accountToken = token;
        final homeUsers = await plex.homeUsers(token);
        if (!_isCurrent(operation)) return;
        _publishProfiles = homeUsers;
        if (settings.profilePickerOnStartup && profiles.length > 1) {
          _stage = SetupStage.profiles;
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
              _stage = SetupStage.profiles;
              return;
            }
            _profile = restoredProfile;
            _profileToken = profileToken;
          }
        }
        if (profile == null && profiles.length > 1) {
          _stage = SetupStage.profiles;
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
    _startupRecoveryNotice = null;
    notifyListeners();
  }

  Future<void> startLinking() async {
    if (secureCancellationRequired) {
      await cancelLinking();
      return;
    }
    _retireScope();
    final operation = _invalidateOperation();
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
        _activePin = pin;
        _stage = SetupStage.linking;
        notifyListeners();
        _schedulePinPoll(operation, pin);
      },
      operation: operation,
      fallbackStage: SetupStage.welcome,
    );
  }

  Future<bool> cancelLinking() async {
    final pin = activePin;
    final operation = _invalidateOperation();
    _pinTimer?.cancel();
    _busyOperation = null;
    _busy = true;
    _error = null;
    notifyListeners();
    Object? cleanupFailure;
    Object? pinFailure;
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
        if (exception is! PlexException ||
            exception.code != 'resource-not-found') {
          pinFailure = exception;
          diagnostics.add('plex-auth', 'PIN cancellation failed', {
            'code': _linkFailureCode(exception),
          });
        }
      }
    }
    if (!_isCurrent(operation)) return false;
    _busy = false;
    if (cleanupFailure != null || pinFailure != null) {
      _secureCancellationRequired = true;
      _error = cleanupFailure != null
          ? 'Lineup could not securely cancel sign-in. Check system credential storage and try again.'
          : 'Lineup could not cancel sign-in with Plex. Try again.';
      notifyListeners();
      return false;
    }
    _activePin = null;
    _secureCancellationRequired = false;
    _stage = SetupStage.welcome;
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
      _activePin = null;
      _error = 'The Plex link code expired. Request a new code.';
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
        _secureCancellationRequired = true;
        _error = 'Lineup could not confirm secure credential storage. Retry secure cancellation before signing in again.';
        diagnostics.add('plex-auth', 'Credential write failed', {
          'code': 'credential-write-failed',
        });
        notifyListeners();
        return;
      }
      _account = validated;
      _accountToken = token;
      _publishProfiles = homeUsers;
      _activePin = null;
      if (profiles.length > 1) {
        _stage = SetupStage.profiles;
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
      _activePin = null;
      final code = _linkFailureCode(exception);
      _error = _linkFailureMessage(code);
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

  /// Returns whether the profile was durably accepted, independently of any
  /// subsequent server discovery or saved-server reconnect outcome.
  Future<bool> selectProfile(PlexHomeUser selected, {String? pin}) async {
    final operation = _invalidateOperation();
    _invalidatePmsRefresh();
    _serverTargetId = null;
    _pinTimer?.cancel();
    var accepted = false;
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
        await _queueStateOperation(operation, () async {
          final oldCanCancel = profileSelectionCanCancel;
          final oldProfileOrigin = _profilePickerOrigin;
          _profileSelectionCanCancel = false;
          _profilePickerOrigin = null;
          notifyListeners();
          final selection = _ProfileSelection(
            state: _persisted.withSettings(settings).withProfile(selected.id),
            profile: selected,
            token: token,
          );
          try {
            await _persistState(selection.state);
          } catch (_) {
            _profileSelectionCanCancel = oldCanCancel;
            _profilePickerOrigin = oldProfileOrigin;
            rethrow;
          }
          if (_disposed) return;
          _publishProfileSelection(selection);
          accepted = true;
          _stage = SetupStage.servers;
          notifyListeners();
        });
      },
      operation: operation,
      fallbackStage: SetupStage.profiles,
    );
    if (accepted && _isCurrent(operation)) {
      await _run(
        () => _discover(operation),
        operation: operation,
        fallbackStage: SetupStage.servers,
      );
    }
    return accepted;
  }

  void _publishProfileSelection(_ProfileSelection selection) {
    _persisted = selection.state;
    _retireScope();
    _profile = selection.profile;
    _profileToken = selection.token;
    _serverAccess = const {};
    _pmsToken = null;
    _invalidatePmsRefresh();
    _publishServer = null;
    _publishServers = const [];
    _connection = null;
    _serverSelectionCanCancel = false;
    _serverPickerOrigin = null;
    _publishLibraries = const [];
    _publishEmptyLineup();
    _publishAvailableMedia = const [];
    _publishAvailablePlaylists = const [];
    _resetSetupDiscovery();
    _contentGeneration++;
  }

  Future<void> _discover(int operation, {bool reconnectSaved = true}) async {
    final token = _profileToken ?? _accountToken;
    if (token == null) return;
    final discovered = await plex.discoverServers(token);
    if (!_isCurrent(operation)) return;
    final activeAccess = reconnectSaved ? null : _serverAccess[server?.id];
    _serverAccess = {for (final access in discovered) access.server.id: access};
    if (activeAccess != null) {
      _serverAccess.putIfAbsent(activeAccess.server.id, () => activeAccess);
    }
    _publishServers = List.unmodifiable(
      discovered.map((access) => access.server),
    );
    _stage = SetupStage.servers;
    if (!reconnectSaved) return;
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
      _error = 'Plex server authorization is unavailable.';
    } else if (server != null) {
      _clearServerRuntime();
      _serverSelectionCanCancel = false;
    }
  }

  Future<void> refreshServers() async {
    final operation = _invalidateOperation();
    _invalidatePmsRefresh();
    _serverTargetId = null;
    await _run(
      () => _discover(operation, reconnectSaved: false),
      operation: operation,
      fallbackStage: SetupStage.servers,
    );
  }

  Future<void> selectServer(PlexServer selected) async {
    final operation = _invalidateOperation();
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
          final access = _serverAccess[selected.id]!;
          final profileKey = profile?.id ?? account?.id;
          final scope = profileKey == null
              ? null
              : LineupScope(profileKey: profileKey, serverId: selected.id);
          final saved = scope == null
              ? ScopedLineup.empty
              : _persisted.lineupFor(scope);
          final availableIds = loadedLibraries
              .map((library) => library.id)
              .toSet();
          final lineup = ScopedLineup(
            libraryIds: saved.libraryIds.intersection(availableIds),
            channels: saved.channels,
            currentChannelId: saved.currentChannelId,
          );
          final base = _persisted
              .withProfile(profile?.id)
              .withSettings(settings);
          final selection = _ServerSelection(
            state: scope == null ? base : base.withLineup(scope, lineup),
            access: access,
            connection: workingConnection,
            libraries: loadedLibraries,
            lineup: lineup,
          );
          final oldCanCancel = serverSelectionCanCancel;
          _serverSelectionCanCancel = false;
          notifyListeners();
          try {
            await _persistState(selection.state);
          } catch (_) {
            _serverSelectionCanCancel = oldCanCancel;
            rethrow;
          }
          if (_disposed) return;
          _publishServerSelection(selection, operation);
          notifyListeners();
        });
        if (!_isCurrent(operation)) return;
        if (selectedLibraryIds.isNotEmpty && channels.isNotEmpty) {
          final loaded = await _loadLibraries(operation, selectedLibraryIds);
          if (operation != _epoch) return;
          _scan.restoreStatus(loaded.status);
          _requireAvailablePlaylists(loaded.failedPlaylistIds);
          _requireAvailableCollections(loaded);
          _publishAvailableMedia = loaded.media;
          _publishAvailablePlaylists = loaded.playlists;
          await _migrateLegacySchedules(operation);
          if (!_isCurrent(operation)) return;
          _scan.stage(loaded, _mutationScope);
          _restoringSavedLineup = false;
          _stage = libraryScanStatus == LibraryScanStatus.complete
              ? SetupStage.ready
              : SetupStage.channelSetup;
        }
        _serverSelectionCanCancel = false;
      },
      operation: operation,
      fallbackStage: SetupStage.servers,
    );
    if (_isCurrent(operation)) _restoringSavedLineup = false;
    if (_serverTargetId == selected.id) _serverTargetId = null;
  }

  void _publishServerSelection(_ServerSelection selection, int operation) {
    final access = selection.access;
    final committedAccess = _serverAccess[access.server.id] ?? access;
    _serverAccess = {..._serverAccess, access.server.id: committedAccess};
    _persisted = selection.state;
    _retireScope();
    _serverPickerOrigin = null;
    _publishServer = access.server;
    _connection = selection.connection;
    _pmsToken = committedAccess.token;
    _publishLibraries = selection.libraries;
    _publishAvailableMedia = const [];
    _publishAvailablePlaylists = const [];
    _publishLineup(selection.lineup);
    _stage = SetupStage.channelSetup;
    _channelSetupCanCancel = false;
    _resetSetupDiscovery();
    // A started successful save still publishes, but obsolete requests cannot
    // create restore work they will never execute.
    _restoringSavedLineup =
        _isCurrent(operation) &&
        selection.lineup.libraryIds.isNotEmpty &&
        selection.lineup.channels.isNotEmpty;
    _contentGeneration++;
  }

  Future<bool> scanLibraries(Set<String> ids, {bool retryFailedOnly = false}) =>
      _scanLibraries(ids, retryFailedOnly: retryFailedOnly);

  /// Retry failed rows within the complete selected inventory. Completed
  /// results and unrequested failures remain staged for the same scan scope.
  Future<bool> retryLibraryScan(Set<String> ids, Set<String> retryIds) =>
      _scanLibraries(ids, retryLibraryIds: retryIds);

  Future<bool> _scanLibraries(
    Set<String> ids, {
    bool retryFailedOnly = false,
    Set<String>? retryLibraryIds,
  }) async {
    if (libraryScanStatus == LibraryScanStatus.scanning) cancelLibraryScan();
    final operation = _invalidateOperation();
    _scan.beginRefresh(retry: retryFailedOnly || retryLibraryIds != null);
    return _run(
      () async {
        final allowed = libraries.map((library) => library.id).toSet();
        if (ids.isEmpty ||
            !allowed.containsAll(ids) ||
            (retryLibraryIds != null &&
                (retryLibraryIds.isEmpty ||
                    !ids.containsAll(retryLibraryIds)))) {
          _scan.finishRefresh(_mutationScope, failed: true);
          throw const PlexException(
            'invalid-library',
            'Select one or more libraries from the current server.',
          );
        }
        _LibraryScanResult result;
        try {
          result = await _loadLibraries(
            operation,
            ids,
            retryFailedOnly: retryFailedOnly,
            retryLibraryIds: retryLibraryIds,
            settleFailures: true,
          );
        } catch (_) {
          if (_isCurrent(operation)) {
            _scan.interruptRefresh(_mutationScope);
          }
          rethrow;
        }
        if (!_isCurrent(operation)) return;
        _scan.stage(result, _mutationScope);
        _scan.finishRefresh(
          _mutationScope,
          failed: result.status == LibraryScanStatus.transientFailure,
        );
        if (_scan.failure case final failure?) {
          _error = failure is PlexException
              ? failure.message
              : 'Lineup could not complete that request.';
          diagnostics.add('application', 'Operation failed', {
            'code': failure is PlexException ? failure.code : 'unexpected',
          });
        }
      },
      operation: operation,
      fallbackStage: SetupStage.channelSetup,
    );
  }

  Future<bool> commitLibraryScan(Set<String> readyIds) =>
      _commitScannedLibraries(readyIds);

  Future<bool> _commitScannedLibraries(Set<String> ids) async {
    final operation = _epoch;
    final scope = _mutationScope;
    final candidate = _scan.candidateFor(
      ids,
      scope,
      libraries.map((library) => library.id),
    );
    if (candidate == null || !libraryScanReadyIds.containsAll(ids)) {
      return false;
    }
    var committed = false;
    await _run(
      () => _queueStateOperation(operation, () async {
        if (!_scan.isCurrent(candidate, _mutationScope)) return;
        _requireAvailablePlaylists(candidate.evidence.failedPlaylistIds);
        _requireAvailableCollections(
          candidate.evidence,
          libraryIds: candidate.libraryIds,
        );
        final media = candidate.media;
        final inventory = _buildPlayableInventory(media, candidate.playlists);
        final previous = channels;
        final migrated = _migratedLegacyChannels(
          _scheduleClock().toUtc(),
          inventory: inventory,
        );
        await _commitLineup(
          ScopedLineup(
            libraryIds: candidate.libraryIds,
            channels: migrated,
            currentChannelId: currentChannelId,
          ),
        );
        if (!_isCurrentMutationScope(scope)) return;
        _publishAvailableMedia = media;
        _publishAvailablePlaylists = candidate.playlists;
        _publishLineup(
          ScopedLineup(
            libraryIds: candidate.libraryIds,
            channels: migrated,
            currentChannelId: currentChannelId,
          ),
        );
        _recordChannelChanges(previous);
        _scan.didCommit(candidate);
        committed = true;
        _contentGeneration++;
        notifyListeners();
      }),
      operation: operation,
      fallbackStage: SetupStage.channelSetup,
    );
    return committed && _isCurrent(operation);
  }

  Future<_LibraryScanResult> _loadLibraries(
    int operation,
    Set<String> ids, {
    bool retryFailedOnly = false,
    Set<String>? retryLibraryIds,
    bool settleFailures = false,
  }) async {
    final selectedServer = server;
    if (selectedServer == null || connection == null) {
      throw const PlexException('server-unreachable', 'Select a server first.');
    }
    final cancelled = _scan.startIo();
    final retainedIds = _scan.prepare(
      ids,
      (profileId: profile?.id ?? account?.id, serverId: selectedServer.id),
      _mutationScope,
      retryFailedOnly: retryFailedOnly,
      retryLibraryIds: retryLibraryIds,
    );
    notifyListeners();
    try {
      final selected = libraries
          .where((library) => ids.contains(library.id))
          .toList(growable: false);
      var nextLibrary = 0;
      Object? firstFailure;
      StackTrace? firstFailureStack;
      Future<void> loadNext() async {
        while (_isCurrent(operation)) {
          final index = nextLibrary++;
          if (index >= selected.length) return;
          final library = selected[index];
          if (retainedIds.contains(library.id)) {
            continue;
          }
          _scan.startLibrary(library.id);
          notifyListeners();
          try {
            final scanned = await _withPmsAuthorization(
              operation,
              selectedServer.id,
              (token, refreshedConnection) => plex.scanLibrary(
                (refreshedConnection ?? connection!).uri,
                token,
                library.id,
                library.type,
                isCurrent: () => _isCurrent(operation),
                cancelled: cancelled.future,
                onPhase: (phase) {
                  if (!_isCurrent(operation)) return;
                  _scan.setPhase(library.id, phase);
                  notifyListeners();
                },
                onProgress: (progress) {
                  if (!_isCurrent(operation)) return;
                  _scan.reportProgress(library.id, progress);
                  notifyListeners();
                },
              ),
            );
            if (!_isCurrent(operation)) return;
            final items = scanned.items;
            if (scanned.timing case final timing?) {
              diagnostics.add('plex-library', 'Library scan timing', {
                'scanPath': settleFailures ? 'setup' : 'launch',
                'libraryType': library.type.name,
                'itemsMs': timing.items.inMilliseconds,
                'collectionsMs': timing.collections.inMilliseconds,
                'showGenresMs': timing.showGenres.inMilliseconds,
                'items': items.length,
                'collections': timing.collectionTitles,
                'members': timing.collectionMembers,
                'shows': timing.shows,
              });
            }
            _scan.completeLibrary(library.id, scanned);
            notifyListeners();
          } catch (exception, stack) {
            if (!_isCurrent(operation)) return;
            _scan.failLibrary(library.id);
            firstFailure ??= exception;
            firstFailureStack ??= stack;
            notifyListeners();
          }
        }
      }

      await Future.wait(
        List.generate(selected.length.clamp(0, 4), (_) => loadNext()),
      );
      if (_isCurrent(operation)) _scan.failure = firstFailure;
      if (firstFailure != null && !settleFailures) {
        Error.throwWithStackTrace(firstFailure!, firstFailureStack!);
      }
      if (!_isCurrent(operation)) {
        return (
          failedCollectionTitles: const <String, Set<String>>{},
          collectionDiscoveryFailures: const <String, PlexCollectionFailure>{},
          failedPlaylistIds: const <String>{},
          media: const <PlexMediaItem>[],
          playlists: const <PlexPlaylist>[],
          status: LibraryScanStatus.cancelled,
        );
      }
      final items = _scan.inventoryFor(selected.map((library) => library.id));
      _scan.playlistProgress = const PlexPlaylistProgress();
      notifyListeners();
      PlexPlaylistCatalog catalog;
      var catalogUnavailable = false;
      try {
        catalog = await _withPmsAuthorization(
          operation,
          selectedServer.id,
          (token, refreshedConnection) => plex.playlists(
            (refreshedConnection ?? connection!).uri,
            token,
            isCurrent: () => _isCurrent(operation),
            cancelled: cancelled.future,
            onProgress: (progress) {
              if (!_isCurrent(operation)) return;
              _scan.playlistProgress = progress;
              notifyListeners();
            },
          ),
        );
      } on PlexException catch (exception) {
        if (!_isCurrent(operation) ||
            exception.code == 'cancelled' ||
            _isPmsAuthorizationError(exception)) {
          rethrow;
        }
        catalogUnavailable = true;
        diagnostics.add('plex-library', 'Playlist discovery unavailable', {
          'code': exception.code,
        });
        if (_requiredPlaylistIds().isNotEmpty) {
          throw const PlexException(
            'playlist-unavailable',
            'A playlist used by this lineup could not be loaded. Retry setup.',
          );
        }
        catalog = const PlexPlaylistCatalog(playlists: [], failedIds: {});
      }
      if (!_isCurrent(operation)) {
        return (
          failedCollectionTitles: const <String, Set<String>>{},
          collectionDiscoveryFailures: const <String, PlexCollectionFailure>{},
          failedPlaylistIds: const <String>{},
          media: const <PlexMediaItem>[],
          playlists: const <PlexPlaylist>[],
          status: LibraryScanStatus.cancelled,
        );
      }
      _scan.playlistProgress = null;
      _scan.completeCatalog(catalog, unavailable: catalogUnavailable);
      if (catalog.failedIds.isNotEmpty) {
        diagnostics.add('plex-library', 'Some playlists could not be loaded', {
          'count': catalog.failedIds.length,
        });
      }
      final failedTitleCount = ids.fold<int>(
        0,
        (count, id) => count + (_scan.failedCollectionTitles[id]?.length ?? 0),
      );
      final unavailableCount = _unavailableCollectionLibraryIds
          .intersection(ids)
          .length;
      if (failedTitleCount > 0) {
        diagnostics.add(
          'plex-library',
          'Some collections could not be loaded',
          {'count': failedTitleCount},
        );
      }
      if (unavailableCount > 0) {
        diagnostics.add('plex-library', 'Collection discovery unavailable', {
          'count': unavailableCount,
        });
      }
      final playable = items.where((item) => item.isPlayable).toList();
      return _scan.result(playable, catalog.playlists);
    } catch (_) {
      if (_isCurrent(operation)) {
        _scan.restoreStatus(LibraryScanStatus.transientFailure);
        notifyListeners();
      }
      rethrow;
    } finally {
      _scan.finishIo(cancelled);
    }
  }

  void cancelLibraryScan() {
    if (libraryScanStatus != LibraryScanStatus.scanning) return;
    _invalidateOperation();
    _busyOperation = null;
    _busy = false;
    _error = null;
    _scan.cancel(_mutationScope);
    notifyListeners();
  }

  Set<String> _unavailableRequiredCollectionIds(
    Map<String, Set<String>> failedTitles,
    Set<String> unavailableIds,
  ) {
    Iterable<LibrarySource> librarySources(ContentSource source) sync* {
      if (source is LibrarySource) {
        yield source;
      } else if (source is MixedSource) {
        for (final nested in source.sources) {
          yield* librarySources(nested);
        }
      }
    }

    return {
      for (final source in channels.expand(
        (channel) => librarySources(channel.source),
      ))
        if (source.filters[LibraryFilter.collection] case final titles?)
          if (titles.isNotEmpty &&
              (unavailableIds.contains(source.libraryId) ||
                  titles.any(
                    (title) =>
                        failedTitles[source.libraryId]?.contains(title) ??
                        false,
                  )))
            source.libraryId,
    };
  }

  void _requireAvailableCollections(
    _LibraryScanResult scan, {
    Set<String>? libraryIds,
  }) {
    final blocked = _unavailableRequiredCollectionIds(
      scan.failedCollectionTitles,
      scan.collectionDiscoveryFailures.keys.toSet(),
    );
    if (libraryIds != null) blocked.retainAll(libraryIds);
    if (blocked.isNotEmpty) {
      final recovery = _collectionScaleRecovery(
        scan.collectionDiscoveryFailures,
        blocked,
      );
      throw PlexException(
        recovery == null
            ? 'collection-unavailable'
            : 'collection-scale-exceeded',
        recovery ?? 'A collection used by this lineup could not be loaded. Retry setup.',
      );
    }
  }

  void _requireAvailablePlaylists(Set<String> failedIds) {
    final required = _requiredPlaylistIds();
    if (failedIds.any(required.contains)) {
      throw const PlexException(
        'playlist-unavailable',
        'A playlist used by this lineup could not be loaded. Retry setup.',
      );
    }
  }

  Set<String> _requiredPlaylistIds() =>
      channels.expand((channel) => _playlistIds(channel.source)).toSet();

  Future<void> enterChannelSetup() async {
    _scenarioOpen = false;
    _channelSetupCanCancel = stage == SetupStage.ready;
    _stage = SetupStage.channelSetup;
    notifyListeners();
  }

  void cancelChannelSetup() {
    if (channelSetupCanCancel) {
      cancelLibraryScan();
      _channelSetupCanCancel = false;
      _error = null;
      _stage = SetupStage.ready;
      notifyListeners();
    }
  }

  void showProfiles() {
    _scenarioOpen = false;
    _profilePickerOrigin = switch (stage) {
      SetupStage.ready => const _PickerOrigin(stage: SetupStage.ready),
      SetupStage.servers => const _PickerOrigin(stage: SetupStage.servers),
      _ => null,
    };
    _profileSelectionCanCancel = _profilePickerOrigin != null;
    _stage = SetupStage.profiles;
    _error = null;
    notifyListeners();
  }

  void cancelProfileSelection() => _cancelProfileSelection();

  void _cancelProfileSelection() {
    if (!profileSelectionCanCancel) return;
    if (busy) {
      _invalidateOperation();
      _invalidatePmsRefresh();
      _serverTargetId = null;
      _busyOperation = null;
      _busy = false;
    }
    _profileSelectionCanCancel = false;
    final origin = _profilePickerOrigin;
    _profilePickerOrigin = null;
    _error = null;
    _stage =
        origin?.stage ??
        (stage == SetupStage.servers ? SetupStage.servers : SetupStage.ready);
    notifyListeners();
  }

  /// Opens the server picker while preserving its exact return destination.
  void showServers() {
    _scenarioOpen = false;
    if (!canSwitchServer) return;
    if (stage != SetupStage.servers) {
      _serverPickerOrigin = server == null
          ? null
          : _PickerOrigin(
              stage: stage,
              restoring: restoringSavedLineup,
              canCancelSetup: channelSetupCanCancel,
            );
    }
    cancelLibraryScan();
    _invalidateOperation();
    _busyOperation = null;
    _busy = false;
    _serverSelectionCanCancel = _serverPickerOrigin != null;
    _stage = SetupStage.servers;
    _error = null;
    notifyListeners();
  }

  void cancelServerSelection() {
    if (!canSwitchServer || !serverSelectionCanCancel) return;
    if (busy) {
      _invalidateOperation();
      _invalidatePmsRefresh();
      _serverTargetId = null;
      _busyOperation = null;
      _busy = false;
    }
    _serverSelectionCanCancel = false;
    _error = null;
    final origin = _serverPickerOrigin;
    _serverPickerOrigin = null;
    _channelSetupCanCancel = origin?.canCancelSetup ?? false;
    _stage = origin?.stage ?? SetupStage.ready;
    if (origin?.restoring == true && server != null) {
      unawaited(selectServer(server!));
    } else {
      notifyListeners();
    }
  }

  bool continueCurrentServer() {
    if (stage != SetupStage.servers || busy || server == null) {
      return false;
    }

    if (serverSelectionCanCancel) {
      cancelServerSelection();
      return true;
    }

    _serverSelectionCanCancel = false;
    _channelSetupCanCancel = false;
    _serverTargetId = null;
    _error = null;
    _stage = SetupStage.channelSetup;
    notifyListeners();
    return true;
  }

  Future<void> clearSavedServer() async {
    final operation = _invalidateOperation();
    await _run(
      () => _queueStateOperation(operation, () async {
        final profileId = profile?.id ?? account?.id;
        if (profileId == null) return;
        final next = _persistedFromRuntime().withoutSelectedServer(profileId);
        await _persistState(next);
        if (_disposed) return;
        _persisted = next;
        _clearServerRuntime();
        _serverSelectionCanCancel = false;
        _stage = SetupStage.servers;
      }),
      operation: operation,
      fallbackStage: SetupStage.servers,
    );
  }

  Future<ChannelPlanApplyResult> applyReviewedChannelPlan(
    List<Channel> planned, {
    required ChannelBuildMode mode,
    required List<Channel> expectedBase,
    Set<String> removeChannelIds = const {},
  }) => _applyChannelPlan(
    planned,
    mode: mode,
    expectedBase: expectedBase,
    removeChannelIds: removeChannelIds,
  );

  Future<ChannelPlanApplyResult> _applyChannelPlan(
    List<Channel> planned, {
    required ChannelBuildMode mode,
    List<Channel>? expectedBase,
    Set<String> removeChannelIds = const {},
  }) async {
    final operation = _mutationScope;
    final expected = expectedBase
        ?.map((channel) => channel.immutableCopy().toJson())
        .toList();
    final plan = List<Channel>.unmodifiable(
      planned.map((channel) => channel.immutableCopy()),
    );
    final removals = Set<String>.unmodifiable(removeChannelIds);
    var result = ChannelPlanApplyResult.stale;
    await _queueScopeOperation(operation, () async {
      if (expected != null &&
          !canonicalChannelValueEquals(
            channels.map((channel) => channel.toJson()).toList(),
            expected,
          )) {
        return;
      }
      if (plan.any((channel) => channel.builderKey == null)) {
        throw const FormatException(
          'Generated channel plans require builder ownership',
        );
      }
      if (removals.isNotEmpty) {
        final unmatched = channels.where(
          (channel) =>
              !plan.any((planned) => planned.builderKey == channel.builderKey),
        );
        final eligible = unmatched
            .where(isGeneratedSourceConfirmedGone)
            .map((channel) => channel.id)
            .toSet();
        if (mode != ChannelBuildMode.merge || !eligible.containsAll(removals)) {
          throw const FormatException(
            'Only confirmed missing generated sources can be removed',
          );
        }
      }
      final next = composeChannelPlan(
        existing: channels
            .where((channel) => !removals.contains(channel.id))
            .toList(),
        planned: plan,
        mode: mode,
      );
      validateChannels(next);
      final validatedSources = <String>{};
      for (final channel in plan) {
        _validateResolvedSource(
          channel.source,
          requirePlayableManual: true,
          validatedSources: validatedSources,
        );
        final content = resolveContent(
          channel.source,
          _playableMedia,
          _playablePlaylists,
        );
        if (!content.any(
          (item) => scheduleIncludesItem(
            item,
            mode: channel.playbackMode,
            includeSpecials: channel.includeSpecials,
            scheduleVersion: channel.scheduleVersion,
          ),
        )) {
          throw const FormatException('Channel source has no playable content');
        }
      }
      await _commitChannelList(next, operation);
      if (_isCurrentMutationScope(operation)) {
        result = ChannelPlanApplyResult.applied;
      }
    });
    return result;
  }

  Future<void> deleteChannels({required List<Channel> expectedChannels}) async {
    final operation = _mutationScope;
    final expected = {
      for (final channel in expectedChannels)
        channel.id: channel.immutableCopy().toJson(),
    };
    if (expected.isEmpty || expected.length != expectedChannels.length) {
      throw const FormatException('Select distinct channels to delete');
    }
    await _queueScopeOperation(operation, () async {
      final current = {for (final channel in channels) channel.id: channel};
      for (final entry in expected.entries) {
        if (current[entry.key] == null ||
            !canonicalChannelValueEquals(
              current[entry.key]!.toJson(),
              entry.value,
            )) {
          throw const ChannelStateConflictException();
        }
      }
      await _commitChannelList(
        channels.where((channel) => !expected.containsKey(channel.id)).toList(),
        operation,
      );
    });
  }

  Future<void> reorderChannels({
    required List<Channel> expectedLineup,
    required List<String> orderedChannelIds,
  }) async {
    final operation = _mutationScope;
    final expected = expectedLineup
        .map((channel) => channel.immutableCopy().toJson())
        .toList();
    final order = List<String>.of(orderedChannelIds);
    await _queueScopeOperation(operation, () async {
      if (!canonicalChannelValueEquals(
        channels.map((channel) => channel.toJson()).toList(),
        expected,
      )) {
        throw const ChannelStateConflictException();
      }
      final byId = {for (final channel in channels) channel.id: channel};
      if (order.length != byId.length ||
          order.toSet().length != byId.length ||
          !byId.keys.toSet().containsAll(order)) {
        throw const FormatException(
          'Reorder must contain every channel exactly once',
        );
      }
      final numbers = channels.map((channel) => channel.number).toList()
        ..sort();
      final next = [
        for (var i = 0; i < order.length; i++)
          Channel.fromJson({...byId[order[i]]!.toJson(), 'number': numbers[i]}),
      ];
      validateChannels(next);
      await _commitChannelList(next, operation);
    });
  }

  Future<void> _commitChannelList(
    List<Channel> next,
    int operation, {
    String? initialCurrentId,
  }) async {
    next = List.unmodifiable(next.map((channel) => channel.immutableCopy()));
    final previous = channels;
    final oldCurrent = currentChannelId ?? initialCurrentId;
    final oldIndex = previous.indexWhere((channel) => channel.id == oldCurrent);
    final nextCurrent = next.any((channel) => channel.id == oldCurrent)
        ? oldCurrent
        : next.isEmpty
        ? null
        : next[oldIndex.clamp(0, next.length - 1)].id;
    await _commitLineup(
      ScopedLineup(
        libraryIds: selectedLibraryIds,
        channels: next,
        currentChannelId: nextCurrent,
      ),
    );
    if (!_isCurrentMutationScope(operation)) {
      throw const LineupScopeSuperseded();
    }
    _publishChannelCommit(next, nextCurrent, previous);
  }

  void _publishChannelCommit(
    List<Channel> next,
    String? currentId,
    List<Channel> previous,
  ) {
    _publishLineup(
      ScopedLineup(
        libraryIds: selectedLibraryIds,
        channels: next,
        currentChannelId: currentId,
      ),
    );
    _recordChannelChanges(previous);
    notifyListeners();
  }

  void completeChannelSetup() {
    if (stage != SetupStage.channelSetup) return;
    _scenarioOpen = false;
    _channelSetupCanCancel = false;
    _error = null;
    _stage = SetupStage.ready;
    notifyListeners();
  }

  Future<Channel> saveChannel(
    Channel channel, {
    required Channel? expectedBase,
  }) async {
    channel = channel.immutableCopy();
    final expected = expectedBase?.immutableCopy().toJson();
    final operation = _mutationScope;
    Channel? committed;
    await _queueScopeOperation(operation, () async {
      final current = channels
          .where((candidate) => candidate.id == channel.id)
          .firstOrNull;
      if (expectedBase == null) {
        if (current != null) {
          throw const FormatException('Channel already exists');
        }
      } else if (current == null ||
          !canonicalChannelValueEquals(current.toJson(), expected)) {
        throw const ChannelStateConflictException();
      }
      final savedChannel = _channelForSave(channel, current);
      savedChannel.validate(channels);
      _validateResolvedSource(savedChannel.source);
      final next = [...channels];
      final index = next.indexWhere(
        (candidate) => candidate.id == savedChannel.id,
      );
      if (index < 0) {
        next.add(savedChannel);
      } else {
        next[index] = savedChannel;
      }
      next.sort((a, b) => a.number.compareTo(b.number));
      await _commitChannelList(
        next,
        operation,
        initialCurrentId: savedChannel.id,
      );
      if (_isCurrentMutationScope(operation)) committed = savedChannel;
    });
    if (committed == null) {
      throw const LineupScopeSuperseded();
    }
    return committed!;
  }

  void _validateResolvedSource(
    ContentSource source, {
    bool requirePlayableManual = false,
    Set<String>? validatedSources,
  }) {
    final sourceKey = canonicalSourceIdentity(source);
    if (validatedSources?.contains(sourceKey) ?? false) return;
    _ensurePlayableInventory();
    switch (source) {
      case LibrarySource():
      case PlaylistSource():
        if (resolveContent(
          source,
          _playableMedia,
          _playablePlaylists,
        ).isEmpty) {
          throw const FormatException('Channel source has no playable content');
        }
      case ManualSource():
        if (requirePlayableManual &&
            resolveContent(
              source,
              _playableMedia,
              _playablePlaylists,
            ).isEmpty) {
          throw const FormatException('Channel source has no playable content');
        }
      case MixedSource(:final sources):
        for (final child in sources) {
          _validateResolvedSource(
            child,
            requirePlayableManual: requirePlayableManual,
            validatedSources: validatedSources,
          );
        }
    }
    validatedSources?.add(sourceKey);
  }

  Future<ScheduleIndex> loadScheduleFor(Channel channel) {
    if (_disposed) {
      return Future.error(StateError('Schedule worker is disposed'));
    }
    _scenarioOpen = false;
    _ensurePlayableInventory();
    if (!identical(_scheduleWorkerMedia, _playableMedia) ||
        !identical(_scheduleWorkerPlaylists, _playablePlaylists)) {
      _scheduleWorker?.dispose();
      _scheduleWorkerMedia = _playableMedia;
      _scheduleWorkerPlaylists = _playablePlaylists;
      _scheduleWorker = null;
    }
    final worker = _scheduleWorker ??= _scheduleWorkerFactory(
      _playableMedia,
      _playablePlaylists,
    );
    return worker.build(channel);
  }

  Channel _channelForSave(Channel incoming, Channel? current) {
    if (current == null) return incoming;
    final sameProgramming =
        canonicalSourceEquals(current.source, incoming.source) &&
        current.playbackMode == incoming.playbackMode &&
        (incoming.playbackMode != PlaybackMode.block ||
            (current.blockSize ?? 3) == (incoming.blockSize ?? 3)) &&
        (incoming.playbackMode != PlaybackMode.block ||
            current.includeSpecials == incoming.includeSpecials);
    if (!sameProgramming) {
      return Channel(
        id: incoming.id,
        number: incoming.number,
        name: incoming.name,
        source: incoming.source,
        playbackMode: incoming.playbackMode,
        anchor: incoming.anchor,
        shuffleSeed: incoming.shuffleSeed,
        blockSize: incoming.blockSize,
        builderKey: incoming.builderKey,
        includeSpecials: incoming.includeSpecials,
      );
    }
    return Channel(
      id: incoming.id,
      number: incoming.number,
      name: incoming.name,
      source: incoming.source,
      playbackMode: incoming.playbackMode,
      anchor: current.anchor,
      shuffleSeed: current.shuffleSeed,
      blockSize: incoming.blockSize,
      builderKey: incoming.builderKey,
      includeSpecials: current.includeSpecials,
      scheduleVersion: current.scheduleVersion,
      scheduleTransition: current.scheduleTransition,
    );
  }

  List<Channel> _migratedLegacyChannels(
    DateTime now, {
    ({
      List<PlexMediaItem> media,
      List<PlexPlaylist> playlists,
      Map<String, PlexMediaItem> byId,
    })?
    inventory,
  }) {
    final resolved = inventory ?? playableInventory;
    return List.unmodifiable([
      for (final channel in channels)
        if (channel.scheduleVersion != 1)
          channel
        else
          _tryMigrateLegacySchedule(
            channel,
            now,
            resolved.media,
            resolved.playlists,
          ),
    ]);
  }

  Channel _tryMigrateLegacySchedule(
    Channel channel,
    DateTime now,
    List<PlexMediaItem> media,
    List<PlexPlaylist> playlists,
  ) {
    try {
      final content = resolveContent(channel.source, media, playlists);
      return migrateLegacySchedule(channel, content, now);
    } on ScheduleBuildException {
      return channel;
    } on FormatException {
      return channel;
    }
  }

  Future<void> _migrateLegacySchedules(int operation) async {
    final scope = _mutationScope;
    await _queueStateOperation(operation, () async {
      final old = channels;
      final migrated = _migratedLegacyChannels(_scheduleClock().toUtc());
      if (Iterable<int>.generate(old.length)
          .every((index) => identical(old[index], migrated[index]))) {
        return;
      }
      await _commitLineup(
        ScopedLineup(
          libraryIds: selectedLibraryIds,
          channels: migrated,
          currentChannelId: currentChannelId,
        ),
      );
      if (_isCurrentMutationScope(scope)) {
        _publishLineup(
          ScopedLineup(
            libraryIds: selectedLibraryIds,
            channels: migrated,
            currentChannelId: currentChannelId,
          ),
        );
        _recordChannelChanges(old);
      }
    });
  }

  LineupPlaybackRequest playbackFor(String itemId) {
    final endpoint = connection?.uri;
    final token = _pmsToken;
    final serverId = server?.id;
    final item = _playbackItem(itemId);
    if (endpoint == null || token == null || serverId == null || item == null) {
      throw const PlexException(
        'playback-unavailable',
        'This program is not available from the current Plex session.',
      );
    }
    return _playbackRequest(
      item,
      endpoint,
      token,
      serverId,
      _authorizationScope,
    );
  }

  PlexMediaItem? _playbackItem(String itemId) {
    _ensurePlayableInventory();
    return _playableById[itemId];
  }

  ({
    List<PlexMediaItem> media,
    List<PlexPlaylist> playlists,
    Map<String, PlexMediaItem> byId,
  })
  _buildPlayableInventory(
    List<PlexMediaItem> media,
    List<PlexPlaylist> playlists,
  ) {
    final endpoint = connection?.uri;
    if (endpoint == null) {
      return (media: const [], playlists: const [], byId: const {});
    }
    bool eligible(PlexMediaItem item) {
      if (!item.isPlayable) return false;
      try {
        plex.playbackDescriptor(server: endpoint, item: item);
        return true;
      } on PlexException {
        return false;
      }
    }

    final nextMedia = List<PlexMediaItem>.unmodifiable(media.where(eligible));
    final nextPlaylists = List<PlexPlaylist>.unmodifiable([
      for (final playlist in playlists)
        PlexPlaylist(
          id: playlist.id,
          title: playlist.title,
          items: List.unmodifiable(playlist.items.where(eligible)),
        ),
    ]);
    final nextById = playableMediaById(nextMedia, nextPlaylists);
    return (media: nextMedia, playlists: nextPlaylists, byId: nextById);
  }

  void _ensurePlayableInventory() {
    final endpoint = connection?.uri;
    if (_playableEndpoint == endpoint &&
        identical(_playableSourceMedia, availableMedia) &&
        identical(_playableSourcePlaylists, availablePlaylists)) {
      return;
    }
    if (endpoint == null) {
      const nextMedia = <PlexMediaItem>[];
      const nextPlaylists = <PlexPlaylist>[];
      _playableMedia = nextMedia;
      _playablePlaylists = nextPlaylists;
      _playableById = const {};
      _playableSourceMedia = availableMedia;
      _playableSourcePlaylists = availablePlaylists;
      _playableEndpoint = endpoint;
      return;
    }
    final inventory = _buildPlayableInventory(
      availableMedia,
      availablePlaylists,
    );
    final nextMedia = inventory.media;
    final nextPlaylists = inventory.playlists;
    final nextById = inventory.byId;
    _playableMedia = nextMedia;
    _playablePlaylists = nextPlaylists;
    _playableById = nextById;
    _playableSourceMedia = availableMedia;
    _playableSourcePlaylists = availablePlaylists;
    _playableEndpoint = endpoint;
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
        await _refreshPlaybackAccess(operation, serverId);
        if (!_isCurrentAuthorizationScope(operation) ||
            server?.id != serverId) {
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

  Future<Uint8List?> artworkForPath(Uri path, {int? width, int? height}) async {
    final serverId = server?.id;
    final selectedConnection = connection;
    if (serverId == null ||
        selectedConnection == null ||
        path.toString().isEmpty) {
      return null;
    }
    final portrait = width != null || height != null;
    if (!portrait) {
      return _withPmsAuthorization(
        _epoch,
        serverId,
        (token, refreshedConnection) =>
            plex.artwork((refreshedConnection ?? connection!).uri, token, path),
      );
    }
    final scope = _authorizationScope;
    bool current() =>
        _isCurrentAuthorizationScope(scope) &&
        server?.id == serverId &&
        _logoutFuture == null;
    try {
      final bytes = await _withPmsAuthorization(_epoch, serverId, (
        token,
        refreshedConnection,
      ) {
        if (!current()) {
          return Future<Uint8List>.error(
            const PlexException(
              'authorization-unavailable',
              'Artwork session ended.',
            ),
          );
        }
        final endpoint = (refreshedConnection ?? selectedConnection).uri;
        return plex.castPortraitArtwork(
          endpoint,
          token,
          path,
          width: width ?? 0,
          height: height ?? 0,
        );
      });
      return current() ? bytes : null;
    } catch (error) {
      if (!current()) return null;
      final source = canonicalPlexCastPortrait(path) == null
          ? 'invalid'
          : path.isAbsolute
          ? (path.scheme == 'https' ? 'https' : 'http')
          : 'pms';
      final failure = error is PlexException
          ? switch (error.code) {
              'auth-invalid' ||
              'access-denied' ||
              'authorization-unavailable' => 'authorization',
              'network-timeout' => 'timeout',
              'artwork-too-large' => 'size',
              'artwork-unavailable' => 'unavailable',
              _ => 'transport',
            }
          : 'transport';
      diagnostics.add('plex', 'Cast portrait unavailable', {
        'code': 'portrait_$source',
        'failureCode': failure,
        'count': 1,
      });
      return null;
    }
  }

  Future<void> setCurrentChannel(String? id) async {
    final operation = _mutationScope;
    await _queueScopeOperation(operation, () async {
      if (id == currentChannelId ||
          (id != null && !channels.any((channel) => channel.id == id))) {
        return;
      }
      await _commitLineup(_lineup.withCurrentChannel(id));
      if (!_isCurrentMutationScope(operation)) {
        throw const LineupScopeSuperseded();
      }
      _publishCurrentChannel(id);
    });
  }

  Future<void> updateSettings(
    LineupSettings Function(LineupSettings committed) change,
  ) async {
    await _queueGlobalStateOperation(() async {
      final proposed = change(settings);
      await _commitSettings(proposed);
      if (_disposed) return;
      _publishSettingsCommit(proposed);
    });
  }

  void _publishSettingsCommit(LineupSettings proposed) {
    _settings = proposed;
    diagnostics.enabled = proposed.diagnosticsEnabled;
    notifyListeners();
  }

  void _publishCurrentChannel(String? id) {
    _publishLineup(_lineup.withCurrentChannel(id));
    notifyListeners();
  }

  void _recordChannelChanges(List<Channel> previous) {
    final previousById = {for (final channel in previous) channel.id: channel};
    final liveIds = channels.map((channel) => channel.id).toSet();
    _channelRevisions.removeWhere((id, _) => !liveIds.contains(id));
    for (final channel in channels) {
      final old = previousById[channel.id];
      if (!identical(old, channel) &&
          (old == null ||
              !canonicalChannelValueEquals(old.toJson(), channel.toJson()))) {
        _channelRevisions[channel.id] = ++_nextChannelRevision;
      }
    }
  }

  Future<bool> logout() {
    _scenarioOpen = false;
    final active = _logoutFuture;
    if (active != null) return active;
    final next = Future<bool>.microtask(_performLogout)
        .whenComplete(_finishLogout);
    _logoutFuture = next;
    return next;
  }

  Future<bool> _performLogout() async {
    _retireAuthorizationScope();
    _mutationEligibility++;
    _invalidateOperation();
    final stateBeforeLogout = _stateOperations;
    final releaseStateOperations = Completer<void>();
    _stateOperations = stateBeforeLogout.then(
      (_) => releaseStateOperations.future,
    );
    _invalidatePmsRefresh();
    _serverTargetId = null;
    _pinTimer?.cancel();
    _busyOperation = null;
    _busy = true;
    notifyListeners();
    try {
      try {
        await _clearCredentials();
      } catch (exception) {
        if (_disposed) return false;
        _error = 'Lineup could not securely sign out. Check system credential storage and try again.';
        diagnostics.add('application', 'Credential cleanup failed', {
          'code': exception is PlexException ? exception.code : 'unexpected',
        });
        return false;
      }
      if (_disposed) return false;
      await stateBeforeLogout;
      if (_disposed) return false;
      _invalidateOperation();
      _mutationScope++;
      _account = null;
      _profile = null;
      _publishProfiles = const [];
      _publishServers = const [];
      _publishServer = null;
      _connection = null;
      _publishLibraries = const [];
      _publishAvailableMedia = const [];
      _publishAvailablePlaylists = const [];
      _scheduleWorker?.dispose();
      _scheduleWorker = null;
      _scheduleWorkerMedia = null;
      _scheduleWorkerPlaylists = null;
      _publishEmptyLineup();
      _channelSetupCanCancel = false;
      _profileSelectionCanCancel = false;
      _serverSelectionCanCancel = false;
      _accountToken = null;
      _profileToken = null;
      _serverAccess = const {};
      _pmsToken = null;
      _serverTargetId = null;
      _invalidatePmsRefresh();
      _secureCancellationRequired = false;
      _resetSetupDiscovery();
      _contentGeneration++;
      _stage = SetupStage.welcome;
      _error = null;
      return true;
    } finally {
      releaseStateOperations.complete();
    }
  }

  void _finishLogout() {
    _logoutFuture = null;
    if (_disposed) return;
    _busy = false;
    notifyListeners();
  }

  void _publishEmptyLineup() => _publishLineup(ScopedLineup.empty);

  void _publishLineup(ScopedLineup lineup) => _lineup = lineup;

  PersistedState _persistedFromRuntime({
    ScopedLineup? lineup,
    LineupSettings? settings,
  }) {
    final base = _persisted
        .withProfile(profile?.id)
        .withSettings(settings ?? this.settings);
    final profileKey = profile?.id ?? account?.id;
    final serverId = server?.id;
    if (profileKey == null || serverId == null) return base;
    return base.withLineup(
      LineupScope(profileKey: profileKey, serverId: serverId),
      lineup ?? _lineup,
    );
  }

  Future<void> _commitLineup(ScopedLineup lineup) =>
      _commitPersistedState(_persistedFromRuntime(lineup: lineup));

  Future<void> _commitSettings(LineupSettings settings) =>
      _commitPersistedState(_persistedFromRuntime(settings: settings));

  Future<void> _commitPersistedState(PersistedState next) async {
    await _persistState(next);
    if (!_disposed) _persisted = next;
  }

  Future<void> _persistState(PersistedState state) async {
    try {
      await store.save(state);
    } catch (_) {
      diagnostics.add('application', 'State save failed', {
        'code': 'write-failed',
      });
      rethrow;
    }
  }

  Future<void> _queueStateOperation(
    int operation,
    Future<void> Function() body,
  ) {
    final queued = _stateOperations.then((_) async {
      if (!_isCurrent(operation)) return;
      _setupStateCommitInProgress = true;
      notifyListeners();
      try {
        await body();
      } finally {
        _setupStateCommitInProgress = false;
        notifyListeners();
      }
    });
    _stateOperations = queued.then<void>((_) {}, onError: (_, _) {});
    return queued;
  }

  Future<void> _queueScopeOperation(int scope, Future<void> Function() body) {
    final eligibility = _mutationEligibility;
    return _queueGlobalStateOperation(() async {
      if (!_isCurrentMutationScope(scope) ||
          eligibility != _mutationEligibility ||
          _logoutFuture != null) {
        throw const LineupScopeSuperseded();
      }
      await body();
    });
  }

  void _beginFixtureIdentityChange() {
    if (_disposed ||
        _busyOperation != null ||
        _scan._cancelled != null ||
        _setupStateCommitInProgress ||
        _logoutFuture != null ||
        (_pinTimer?.isActive ?? false)) {
      throw StateError(
        'Use real session commands while controller work is active',
      );
    }
    _invalidateOperation();
    _invalidatePmsRefresh();
    _serverTargetId = null;
    _scan.reset();
  }

  void _retireScope() {
    _scenarioOpen = false;
    _mutationScope++;
    _mutationEligibility++;
    _retireAuthorizationScope();
  }

  void _retireAuthorizationScope() {
    _authorizationScope++;
    _playbackRefresh = null;
    _playbackRefreshScope = null;
  }

  bool _isCurrentMutationScope(int scope) =>
      !_disposed && scope == _mutationScope;

  bool _isCurrentAuthorizationScope(int scope) =>
      !_disposed && scope == _authorizationScope;

  Future<void> _queueGlobalStateOperation(Future<void> Function() body) {
    _scenarioOpen = false;
    final queued = _stateOperations.then((_) async {
      if (_disposed) throw StateError('Controller was disposed');
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
    _retireScope();
    _publishServer = null;
    _connection = null;
    _pmsToken = null;
    _serverTargetId = null;
    _invalidatePmsRefresh();
    _publishLibraries = const [];
    _publishEmptyLineup();
    _publishAvailableMedia = const [];
    _publishAvailablePlaylists = const [];
    _resetSetupDiscovery();
    _scheduleWorker?.dispose();
    _scheduleWorker = null;
    _scheduleWorkerMedia = null;
    _scheduleWorkerPlaylists = null;
    _contentGeneration++;
  }

  void _resetSetupDiscovery() {
    _restoringSavedLineup = false;
    _profilePickerOrigin = null;
    _serverPickerOrigin = null;
    _scan.reset();
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

  Future<PlexConnection> _refreshPlaybackAccess(int scope, String serverId) {
    bool current() =>
        _isCurrentAuthorizationScope(scope) &&
        server?.id == serverId &&
        _logoutFuture == null;
    if (!current()) {
      throw const PlexException(
        'authorization-unavailable',
        'Plex server authorization is unavailable.',
      );
    }
    final active = _playbackRefresh;
    if (active != null && _playbackRefreshScope == scope) return active;
    final refresh = _performPmsRefresh(
      _epoch,
      serverId,
      isCurrent: current,
      forPlayback: true,
    );
    _playbackRefresh = refresh;
    _playbackRefreshScope = scope;
    return refresh.whenComplete(() {
      if (identical(_playbackRefresh, refresh)) {
        _playbackRefresh = null;
        _playbackRefreshScope = null;
      }
    });
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
    String serverId, {
    bool Function()? isCurrent,
    bool forPlayback = false,
  }) async {
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
    if (!(isCurrent?.call() ?? _isCurrentPmsTarget(operation, serverId)) ||
        (_profileToken ?? _accountToken) != profileToken) {
      throw const PlexException(
        'authorization-unavailable',
        'Plex server authorization is unavailable.',
      );
    }
    final selectedConnection = await plex.selectConnection(
      refreshed.server,
      refreshed.token,
    );
    if (!(isCurrent?.call() ?? _isCurrentPmsTarget(operation, serverId)) ||
        (_profileToken ?? _accountToken) != profileToken) {
      throw const PlexException(
        'authorization-unavailable',
        'Plex server authorization is unavailable.',
      );
    }
    _serverAccess = {for (final access in discovered) access.server.id: access};
    _publishServers = List.unmodifiable(
      discovered.map((access) => access.server),
    );
    if (forPlayback || _serverTargetId != serverId) {
      _pmsToken = refreshed.token;
      _connection = selectedConnection;
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
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await body();
      return _isCurrent(operation);
    } catch (exception) {
      if (!_isCurrent(operation)) return false;
      _error = exception is PlexException
          ? exception.message
          : 'Lineup could not complete that request.';
      _restoringSavedLineup = false;
      _stage = fallbackStage;
      diagnostics.add('application', 'Operation failed', {
        'code': exception is PlexException ? exception.code : 'unexpected',
      });
      return false;
    } finally {
      if (!_disposed && _busyOperation == operation) {
        _busyOperation = null;
        _busy = false;
        notifyListeners();
      }
    }
  }

  int _invalidateOperation() {
    _scenarioOpen = false;
    _restoringSavedLineup = false;
    _scan.cancelIo();
    return ++_epoch;
  }

  bool _isCurrent(int operation) => !_disposed && operation == _epoch;

  bool _isCurrentPmsTarget(int operation, String serverId) =>
      _isCurrent(operation) &&
      (_serverTargetId == null
          ? server?.id == serverId
          : _serverTargetId == serverId);

  static bool _isPmsAuthorizationError(PlexException exception) =>
      exception.isAuthorizationFailure;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _invalidateOperation();
    _pinTimer?.cancel();
    _busyOperation = null;
    _busy = false;
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
    if (_ownsDiagnostics) diagnostics.dispose();
    super.dispose();
  }
}
