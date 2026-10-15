part of 'lineup_controller.dart';

/// A starting scenario for synthetic UI and domain fixtures. Tokens and live
/// operation identities belong to real stores/commands and cannot be seeded.
@immutable
class LineupScenario {
  const LineupScenario({
    this.settings,
    this.channels,
    this.currentChannelId,
    this.account,
    this.profile,
    this.profiles,
    this.servers,
    this.server,
    this.connection,
    this.libraries,
    this.selectedLibraryIds,
    this.availableMedia,
    this.availablePlaylists,
    this.activePin,
    this.stage,
    this.busy,
    this.channelSetupCanCancel,
    this.profileSelectionOrigin,
    this.serverSelectionOrigin,
    this.restoringSavedLineup,
    this.secureCancellationRequired,
    this.error,
    this.startupRecoveryNotice,
    this.libraryScanStatus,
    this.scanFacts,
  });

  final LineupSettings? settings;
  final List<Channel>? channels;
  final String? currentChannelId;
  final PlexAccount? account;
  final PlexHomeUser? profile;
  final List<PlexHomeUser>? profiles;
  final List<PlexServer>? servers;
  final PlexServer? server;
  final PlexConnection? connection;
  final List<PlexLibrary>? libraries;
  final Set<String>? selectedLibraryIds;
  final List<PlexMediaItem>? availableMedia;
  final List<PlexPlaylist>? availablePlaylists;
  final PlexPin? activePin;
  final SetupStage? stage;
  final bool? busy;
  final bool? channelSetupCanCancel;
  final SetupStage? profileSelectionOrigin;
  final SetupStage? serverSelectionOrigin;
  final bool? restoringSavedLineup;
  final bool? secureCancellationRequired;
  final String? error;
  final String? startupRecoveryNotice;
  final LibraryScanStatus? libraryScanStatus;
  final Map<String, LibraryScanFact>? scanFacts;

  /// Resolves factory defaults before installation, never against a live controller.
  LineupScenario withDefaults(LineupScenario defaults) => LineupScenario(
    settings: settings ?? defaults.settings,
    channels: channels ?? defaults.channels,
    currentChannelId:
        currentChannelId ??
        (channels != null &&
                !channels!.any(
                  (channel) => channel.id == defaults.currentChannelId,
                )
            ? channels!.firstOrNull?.id
            : defaults.currentChannelId),
    account: account ?? defaults.account,
    profile: profile ?? defaults.profile,
    profiles: profiles ?? defaults.profiles,
    servers: servers ?? defaults.servers,
    server: server ?? defaults.server,
    connection: connection ?? defaults.connection,
    libraries: libraries ?? defaults.libraries,
    selectedLibraryIds: selectedLibraryIds ?? defaults.selectedLibraryIds,
    availableMedia: availableMedia ?? defaults.availableMedia,
    availablePlaylists: availablePlaylists ?? defaults.availablePlaylists,
    activePin: activePin ?? defaults.activePin,
    stage: stage ?? defaults.stage,
    busy: busy ?? defaults.busy,
    channelSetupCanCancel:
        channelSetupCanCancel ?? defaults.channelSetupCanCancel,
    profileSelectionOrigin:
        profileSelectionOrigin ?? defaults.profileSelectionOrigin,
    serverSelectionOrigin:
        serverSelectionOrigin ?? defaults.serverSelectionOrigin,
    restoringSavedLineup: restoringSavedLineup ?? defaults.restoringSavedLineup,
    secureCancellationRequired:
        secureCancellationRequired ?? defaults.secureCancellationRequired,
    error: error ?? defaults.error,
    startupRecoveryNotice:
        startupRecoveryNotice ?? defaults.startupRecoveryNotice,
    libraryScanStatus: libraryScanStatus ?? defaults.libraryScanStatus,
    scanFacts: scanFacts ?? defaults.scanFacts,
  );
}

/// Synthetic UI events and explicit external publication. This actor never
/// resets authorization, mutation, revision or request counters, and cannot
/// install a second scenario. IO/save boundary tests use real controller commands.
@visibleForTesting
class LineupFixtureActor {
  LineupFixtureActor._(this._controller);
  final LineupController _controller;

  void publishInventory({
    List<PlexMediaItem>? media,
    List<PlexPlaylist>? playlists,
    Set<String>? selectedLibraryIds,
  }) {
    _controller._scenarioOpen = false;
    final controller = _controller;
    if (media != null) controller._publishAvailableMedia = media;
    if (playlists != null) controller._publishAvailablePlaylists = playlists;
    if (selectedLibraryIds != null) {
      controller._publishLineup(
        ScopedLineup(
          libraryIds: selectedLibraryIds,
          channels: controller.channels,
          currentChannelId: controller.currentChannelId,
        ),
      );
    }
    controller._contentGeneration++;
    controller.notifyListeners();
  }

  void replaceChannels(List<Channel> channels) {
    _controller._scenarioOpen = false;
    final controller = _controller;
    final currentId =
        channels.any((channel) => channel.id == controller.currentChannelId)
        ? controller.currentChannelId
        : channels.firstOrNull?.id;
    controller._publishChannelCommit(channels, currentId, controller.channels);
  }

  void replaceConnection(PlexConnection? connection) {
    _controller._beginFixtureIdentityChange();
    _controller._retireScope();
    _controller._connection = connection;
    _controller._contentGeneration++;
    _controller.notifyListeners();
  }

  /// Publishes synthetic scan output for UI fixtures with no real scan in flight.
  /// Counts remain row-derived; retained real readiness can never be overwritten.
  void reportScan({
    required LibraryScanStatus status,
    Map<String, LibraryScanFact>? facts,
  }) {
    _controller._scenarioOpen = false;
    final controller = _controller;
    if (controller._scan.readiness != null ||
        controller._scan._cancelled != null) {
      throw StateError('Synthetic scan output cannot replace a real scan');
    }
    controller._scenarioOpen = false;
    if (facts != null) {
      controller._scan.installScenario(
        facts,
        status,
        controller._mutationScope,
        controller.profile?.id,
        controller.server?.id,
      );
    } else {
      controller._scan.status = status;
    }
    controller.notifyListeners();
  }

  void discoverLibraries(
    List<PlexLibrary> libraries, {
    Set<String>? selectedLibraryIds,
  }) {
    _controller._scenarioOpen = false;
    final controller = _controller;
    controller._publishLibraries = libraries;
    controller._publishLineup(
      ScopedLineup(
        libraryIds:
            selectedLibraryIds ??
            controller.selectedLibraryIds.intersection(
              libraries.map((library) => library.id).toSet(),
            ),
        channels: controller.channels,
        currentChannelId: controller.currentChannelId,
      ),
    );
    controller._contentGeneration++;
    controller.notifyListeners();
  }

  void discoverServers(List<PlexServer> servers) {
    _controller._scenarioOpen = false;
    _controller._publishServers = servers;
    _controller.notifyListeners();
  }

  void cancelProfilePicker() {
    _controller._scenarioOpen = false;
    _controller._cancelProfileSelection();
  }

  void publishSettings(LineupSettings settings) {
    _controller._scenarioOpen = false;
    _controller._publishSettingsCommit(settings);
  }

  void selectChannel(String? id) {
    _controller._scenarioOpen = false;
    if (id != null &&
        !_controller.channels.any((channel) => channel.id == id)) {
      throw ArgumentError('Current channel must belong to the lineup');
    }
    _controller._publishCurrentChannel(id);
  }

  void serverSelected(PlexServer? server, {PlexConnection? connection}) {
    _controller._beginFixtureIdentityChange();
    _controller._retireScope();
    _controller._publishServer = server;
    _controller._connection = connection ?? server?.connections.firstOrNull;
    _controller._pmsToken = server == null
        ? null
        : _controller._serverAccess[server.id]?.token;
    _controller._contentGeneration++;
    _controller.notifyListeners();
  }

  void profileSelected(
    PlexHomeUser profile, {
    List<PlexServer> servers = const [],
  }) {
    _controller._beginFixtureIdentityChange();
    _controller._clearServerRuntime();
    _controller._profile = profile;
    _controller._publishServers = servers;
    _controller._profileSelectionCanCancel = false;
    _controller._serverSelectionCanCancel = false;
    _controller._stage = SetupStage.servers;
    _controller.notifyListeners();
  }

  void present(LineupPresentation presentation) {
    _controller._scenarioOpen = false;
    final controller = _controller;
    if (presentation.stage != null) controller._stage = presentation.stage!;
    if (presentation.busy != null) controller._busy = presentation.busy!;
    if (presentation.pin != null) controller._activePin = presentation.pin!.$1;
    if (presentation.error != null) controller._error = presentation.error!.$1;
    if (presentation.restoring != null) {
      controller._restoringSavedLineup = presentation.restoring!;
    }
    if (presentation.secureCancellationRequired != null) {
      controller._secureCancellationRequired =
          presentation.secureCancellationRequired!;
    }
    if (presentation.canCancelSetup != null) {
      controller._channelSetupCanCancel = presentation.canCancelSetup!;
    }
    controller.notifyListeners();
  }
}

@immutable
class LineupPresentation {
  const LineupPresentation({
    this.stage,
    this.busy,
    this.pin,
    this.error,
    this.restoring,
    this.secureCancellationRequired,
    this.canCancelSetup,
  });
  final SetupStage? stage;
  final bool? busy;
  final (PlexPin?,)? pin;
  final (String?,)? error;
  final bool? restoring;
  final bool? secureCancellationRequired;
  final bool? canCancelSetup;
}
