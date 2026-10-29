import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:http/testing.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/playback/native_player.dart';

const _defaultClientIdentifier = 'lineup-desktop-test-abcdefghijklmnopqrst';

MockClient testPlexHttpClient() =>
    MockClient((_) async => throw StateError('unexpected HTTP'));

class MemoryAppStore implements AppStore {
  MemoryAppStore({
    PersistedState? initial,
    this.clientId = _defaultClientIdentifier,
  }) : state = initial ?? const PersistedState();

  PersistedState state;
  final String clientId;
  final savedStates = <PersistedState>[];

  @override
  Future<String> clientIdentifier() async => clientId;

  @override
  Future<AppStoreLoadResult> load() async => AppStoreLoadResult(state);

  @override
  Future<void> save(PersistedState value) async {
    state = value;
    savedStates.add(value);
  }
}

class MemoryCredentialStore implements CredentialStore {
  MemoryCredentialStore({
    this.accountToken,
    Map<String, String> profileTokens = const {},
  }) : profileTokens = Map<String, String>.from(profileTokens);

  String? accountToken;
  final Map<String, String> profileTokens;

  @override
  Future<String?> readAccountToken() async => accountToken;

  @override
  Future<String?> readProfileToken(String profileId) async =>
      profileTokens[profileId];

  @override
  Future<void> writeAccountToken(String token) async => accountToken = token;

  @override
  Future<void> writeProfileToken(String profileId, String token) async =>
      profileTokens[profileId] = token;

  @override
  Future<void> clear() async {
    accountToken = null;
    profileTokens.clear();
  }
}

class FakeNativePlayer implements NativePlayer {
  @override
  final ValueNotifier<SubtitleCues> subtitleCues = ValueNotifier<SubtitleCues>(
    const SubtitleCues.empty(),
  );
  final subtitlePresentations =
      <({double scale, double imageRaise, bool lineupDrawsStyled})>[];
  final subtitleCommandOrder = <String>[];
  void emitSubtitleCues(SubtitleCues cues) => subtitleCues.value = cues;
  @override
  Future<void> setSubtitlePresentation({
    required double scale,
    required double imageRaise,
    required bool lineupDrawsStyled,
  }) async {
    subtitleCommandOrder.add("presentation");
    subtitlePresentations.add((
      scale: scale,
      imageRaise: imageRaise,
      lineupDrawsStyled: lineupDrawsStyled,
    ));
  }

  FakeNativePlayer({
    PlayerStatus? initialStatus,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.telemetry = const PlayerTelemetry(),
    List<PlayerTrack> initialTracks = const [],
    DisplayMatchingReport? initialDisplayReport,
    this.emitLoadingOnLoad = false,
    int? initialGeneration = 0,
  }) : status =
           initialStatus ??
           const PlayerStatus(
             state: PlayerState.idle,
             message: 'Playback test backend ready',
           ),
       tracks = List.unmodifiable(initialTracks),
       displayReport =
           initialDisplayReport ?? const DisplayMatchingReport.initial(),
       _eventGeneration = initialGeneration;

  final bool emitLoadingOnLoad;
  int? _eventGeneration;

  @override
  PlayerStatus status;
  @override
  Duration position;
  @override
  Duration duration;
  @override
  PlayerTelemetry telemetry;
  @override
  List<PlayerTrack> tracks;
  @override
  DisplayMatchingReport displayReport;

  final loads = <Uri>[];
  final loadPlexTokens = <String?>[];
  final loadGenerations = <int?>[];
  final loadStartPaused = <bool>[];
  final seeks = <Duration>[];
  final seekModes = <SeekMode>[];
  final loadStartPositions = <Duration?>[];
  @override
  bool fullscreen = false;
  final _fullscreenChanges = StreamController<bool>.broadcast(sync: true);
  @override
  Stream<bool> get fullscreenChanges => _fullscreenChanges.stream;
  void emitFullscreen(bool observed) {
    fullscreen = observed;
    if (!_fullscreenChanges.isClosed) _fullscreenChanges.add(observed);
  }

  final fullscreenValues = <bool>[];
  final selectedTracks = <(PlayerTrackType, int?)>[];
  final volumeValues = <double>[];
  final videoRects = <PlayerVideoRect>[];
  final displayMatchingRequests = <DisplayMatchingRequest>[];
  int stops = 0;
  int plays = 0;
  int pauseCalls = 0;
  bool disposed = false;

  final _events = StreamController<PlayerEvent>.broadcast();
  final _displayReports = StreamController<DisplayMatchingReport>.broadcast();

  int get generation => _eventGeneration ?? 0;

  @override
  Stream<PlayerEvent> get events => _events.stream;

  @override
  Stream<DisplayMatchingReport> get displayReports => _displayReports.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> load(
    Uri media, {
    String? plexToken,
    int? generation,
    bool startPaused = false,
    Duration? startPosition,
  }) async {
    subtitleCommandOrder.add("load");
    subtitleCues.value = const SubtitleCues.empty();
    loads.add(media);
    loadPlexTokens.add(plexToken);
    final nextGeneration = generation ?? this.generation + 1;
    _eventGeneration = nextGeneration;
    loadGenerations.add(generation);
    loadStartPaused.add(startPaused);
    loadStartPositions.add(startPosition);
    if (emitLoadingOnLoad) {
      _emitSnapshot(
        const PlayerStatus(state: PlayerState.loading, message: 'Loading'),
        eventGeneration: nextGeneration,
      );
    }
  }

  @override
  Future<void> setDisplayMatching(DisplayMatchingRequest request) async =>
      displayMatchingRequests.add(request);

  @override
  Future<void> play() async => plays++;

  @override
  Future<void> pause() async => pauseCalls++;

  @override
  Future<void> seek(Duration value, {SeekMode mode = SeekMode.exact}) async {
    seeks.add(value);
    seekModes.add(mode);
  }

  @override
  Future<void> setVideoRect(PlayerVideoRect rect) async => videoRects.add(rect);

  @override
  Future<void> setFullscreen(bool fullscreen) async {
    fullscreenValues.add(fullscreen);
    emitFullscreen(fullscreen);
  }

  @override
  Future<void> selectTrack(PlayerTrackType type, int? id) async =>
      selectedTracks.add((type, id));

  @override
  Future<void> setVolume(double volume) async => volumeValues.add(volume);

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
    await _displayReports.close();
    await _fullscreenChanges.close();
  }

  void emit(
    PlayerStatus nextStatus, {
    Duration? position,
    Duration? duration,
    PlayerTelemetry? telemetry,
    List<PlayerTrack>? tracks,
    int? eventGeneration,
    bool tracksUpdated = false,
  }) => _emitSnapshot(
    nextStatus,
    position: position,
    duration: duration,
    telemetry: telemetry,
    tracks: tracks,
    eventGeneration: eventGeneration,
    tracksUpdated: tracksUpdated,
  );

  void _emitSnapshot(
    PlayerStatus nextStatus, {
    Duration? position,
    Duration? duration,
    PlayerTelemetry? telemetry,
    List<PlayerTrack>? tracks,
    int? eventGeneration,
    bool tracksUpdated = false,
  }) {
    if (_events.isClosed) return;
    status = nextStatus;
    this.position = position ?? this.position;
    this.duration = duration ?? this.duration;
    this.telemetry = telemetry ?? this.telemetry;
    this.tracks = List.unmodifiable(tracks ?? this.tracks);
    _events.add(
      PlayerEvent(
        status: status,
        position: this.position,
        duration: this.duration,
        telemetry: this.telemetry,
        tracks: this.tracks,
        tracksUpdated: tracksUpdated,
        generation: eventGeneration ?? _eventGeneration,
      ),
    );
  }

  void emitDisplayReport(DisplayMatchingReport report) {
    if (_displayReports.isClosed) return;
    displayReport = report;
    _displayReports.add(report);
  }
}
