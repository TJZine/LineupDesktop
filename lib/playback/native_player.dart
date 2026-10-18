import 'dart:async';

abstract interface class NativePlayer {
  PlayerStatus get status;
  Duration get position;
  Duration get duration;
  PlayerTelemetry get telemetry;
  List<PlayerTrack> get tracks;
  DisplayMatchingReport get displayReport;

  /// Latest observed window state; false before native initialization.
  bool get fullscreen;

  /// A hot broadcast stream of player state snapshots.
  ///
  /// Implementations must allow multiple simultaneous listeners. Events
  /// emitted without listeners are not buffered for later delivery.
  Stream<PlayerEvent> get events;

  /// A hot broadcast stream of player-scoped display matching reports.
  ///
  /// Reports are not associated with a media load. Implementations must keep
  /// them independent from [events] and allow multiple listeners.
  Stream<DisplayMatchingReport> get displayReports;

  /// Hot broadcast observations of native fullscreen, independent of media.
  /// Native initialization publishes a snapshot, including an already-fullscreen
  /// window. Command completion must not overwrite a newer observation.
  Stream<bool> get fullscreenChanges;

  Future<void> initialize();

  /// Loads [media] for the caller's optional [generation].
  ///
  /// [generation] identifies the current load and may be projected on emitted
  /// events so callers can reject stale work.
  ///
  /// [plexToken] is sensitive authentication material. Implementations that
  /// perform network media loads must require HTTPS and send it only as an
  /// `X-Plex-Token` request header. They must not follow redirects while the
  /// header is attached unless every target is proven to retain the original
  /// HTTPS origin. They must never log it, include it in diagnostics, or append
  /// it to [media]. Backends must also prevent media from implicitly loading
  /// nested or external references unless the target and its credential scope
  /// have been explicitly validated by the owning playback policy.
  Future<void> load(
    Uri media, {
    String? plexToken,
    int? generation,
    bool startPaused = false,
  });
  Future<void> setDisplayMatching(DisplayMatchingRequest request);
  Future<void> play();
  Future<void> pause();

  /// Completes on command acceptance, not on an observed playback landing.
  Future<void> seek(Duration position, {SeekMode mode = SeekMode.exact});
  Future<void> setVideoRect(PlayerVideoRect rect);

  /// Requests a transition. A user change may supersede its target; follow
  /// [fullscreenChanges] for the actual state rather than reasserting intent.
  Future<void> setFullscreen(bool fullscreen);

  /// Requests a track change and completes after native command execution.
  ///
  /// Completion does not confirm the selected track. Callers must wait for the
  /// matching state projected through [events].
  Future<void> selectTrack(PlayerTrackType type, int? id);
  Future<void> setVolume(double volume);

  /// Immediately invalidates any active load before awaiting native cleanup.
  ///
  /// A pending [load] must settle with [PlayerUnavailable], and events from
  /// that retired load must be ignored even while native cleanup is pending.
  /// Completes only after native playback has stopped, not on queue acceptance.
  /// Failure does not establish that playback stopped; callers retain cleanup
  /// responsibility and may retry. Replacement loads wait for pending cleanup.
  Future<void> stop();
  Future<void> dispose();
}

/// Keyframe seeks use mpv's backward preference, including its beginning-of-file
/// fallback when no preceding keyframe exists. Exact is for explicit user seeks.
enum SeekMode { exact, keyframes }

enum DisplayMatchingState { hdr, sdr, unknown }

enum DisplayMatchingSessionState { inactive, active, suspended, unavailable }

enum DisplayMatchingOutcome { idle, pending, matched, failed }

enum DisplayMatchingReason {
  unsupportedApi,
  notHdrCapable,
  ambiguousTarget,
  stateUnknown,
  guardianUnavailable,
  setRejected,
  notObserved,
  externalChange,
  restoreFailed,
  targetLost,
}

enum DisplayMatchingRoute { hdrState, advancedColor, none }

enum DisplayActiveColorMode { sdr, wcg, hdr, unknown }

class DisplayMatchingRequest {
  const DisplayMatchingRequest({
    required this.revision,
    required this.session,
    required this.desired,
  });

  final int revision;
  final bool session;
  final DisplayMatchingState desired;

  Map<String, Object?> toJson() => {
    'revision': revision,
    'session': session,
    'desired': desired.name,
  };

  @override
  bool operator ==(Object other) =>
      other is DisplayMatchingRequest &&
      revision == other.revision &&
      session == other.session &&
      desired == other.desired;

  @override
  int get hashCode => Object.hash(revision, session, desired);
}

class DisplayMatchingReport {
  const DisplayMatchingReport({
    required this.revision,
    required this.session,
    required this.observed,
    required this.outcome,
    required this.wrote,
    required this.owned,
    required this.reason,
    required this.route,
    required this.activeColorMode,
  });

  const DisplayMatchingReport.initial()
    : this(
        revision: 0,
        session: DisplayMatchingSessionState.inactive,
        observed: DisplayMatchingState.unknown,
        outcome: DisplayMatchingOutcome.idle,
        wrote: false,
        owned: false,
        reason: null,
        route: DisplayMatchingRoute.none,
        activeColorMode: null,
      );

  const DisplayMatchingReport.unavailable({
    this.revision = 0,
    this.reason = DisplayMatchingReason.unsupportedApi,
  }) : session = DisplayMatchingSessionState.unavailable,
       observed = DisplayMatchingState.unknown,
       outcome = DisplayMatchingOutcome.failed,
       wrote = false,
       owned = false,
       route = DisplayMatchingRoute.none,
       activeColorMode = null;

  final int revision;
  final DisplayMatchingSessionState session;
  final DisplayMatchingState observed;
  final DisplayMatchingOutcome outcome;
  final bool wrote;
  final bool owned;
  final DisplayMatchingReason? reason;
  final DisplayMatchingRoute route;
  final DisplayActiveColorMode? activeColorMode;

  static DisplayMatchingReport? tryParse(Object? value) {
    if (value is! Map) return null;
    final map = Map<Object?, Object?>.from(value);
    const requiredKeys = {
      'revision',
      'session',
      'observed',
      'outcome',
      'wrote',
      'owned',
      'reason',
      'route',
      'activeColorMode',
    };
    if (!map.keys.toSet().containsAll(requiredKeys)) return null;
    final revision = map['revision'];
    final session = _sessionState(map['session']);
    final observed = _matchingState(map['observed']);
    final outcome = _outcome(map['outcome']);
    final wrote = map['wrote'];
    final owned = map['owned'];
    final reasonValue = map['reason'];
    final route = _route(map['route']);
    final activeColorModeValue = map['activeColorMode'];
    if (revision is! int ||
        revision < 0 ||
        session == null ||
        observed == null ||
        outcome == null ||
        wrote is! bool ||
        owned is! bool ||
        route == null) {
      return null;
    }
    final reason = _reason(reasonValue);
    if (reasonValue != null && reason == null) return null;
    final activeColorMode = _activeColorMode(activeColorModeValue);
    if (activeColorModeValue != null && activeColorMode == null) return null;
    return DisplayMatchingReport(
      revision: revision,
      session: session,
      observed: observed,
      outcome: outcome,
      wrote: wrote,
      owned: owned,
      reason: reason,
      route: route,
      activeColorMode: activeColorMode,
    );
  }

  static DisplayMatchingState? _matchingState(Object? value) => switch (value) {
    'hdr' => DisplayMatchingState.hdr,
    'sdr' => DisplayMatchingState.sdr,
    'unknown' => DisplayMatchingState.unknown,
    _ => null,
  };

  static DisplayMatchingSessionState? _sessionState(Object? value) =>
      switch (value) {
        'inactive' => DisplayMatchingSessionState.inactive,
        'active' => DisplayMatchingSessionState.active,
        'suspended' => DisplayMatchingSessionState.suspended,
        'unavailable' => DisplayMatchingSessionState.unavailable,
        _ => null,
      };

  static DisplayMatchingOutcome? _outcome(Object? value) => switch (value) {
    'idle' => DisplayMatchingOutcome.idle,
    'pending' => DisplayMatchingOutcome.pending,
    'matched' => DisplayMatchingOutcome.matched,
    'failed' => DisplayMatchingOutcome.failed,
    _ => null,
  };

  static DisplayMatchingReason? _reason(Object? value) => switch (value) {
    'unsupported_api' => DisplayMatchingReason.unsupportedApi,
    'not_hdr_capable' => DisplayMatchingReason.notHdrCapable,
    'ambiguous_target' => DisplayMatchingReason.ambiguousTarget,
    'state_unknown' => DisplayMatchingReason.stateUnknown,
    'guardian_unavailable' => DisplayMatchingReason.guardianUnavailable,
    'set_rejected' => DisplayMatchingReason.setRejected,
    'not_observed' => DisplayMatchingReason.notObserved,
    'external_change' => DisplayMatchingReason.externalChange,
    'restore_failed' => DisplayMatchingReason.restoreFailed,
    'target_lost' => DisplayMatchingReason.targetLost,
    _ => null,
  };

  static DisplayMatchingRoute? _route(Object? value) => switch (value) {
    'hdr_state' => DisplayMatchingRoute.hdrState,
    'advanced_color' => DisplayMatchingRoute.advancedColor,
    'none' => DisplayMatchingRoute.none,
    _ => null,
  };

  static DisplayActiveColorMode? _activeColorMode(Object? value) =>
      switch (value) {
        'sdr' => DisplayActiveColorMode.sdr,
        'wcg' => DisplayActiveColorMode.wcg,
        'hdr' => DisplayActiveColorMode.hdr,
        'unknown' => DisplayActiveColorMode.unknown,
        _ => null,
      };

  @override
  bool operator ==(Object other) =>
      other is DisplayMatchingReport &&
      revision == other.revision &&
      session == other.session &&
      observed == other.observed &&
      outcome == other.outcome &&
      wrote == other.wrote &&
      owned == other.owned &&
      reason == other.reason &&
      route == other.route &&
      activeColorMode == other.activeColorMode;

  @override
  int get hashCode => Object.hash(
    revision,
    session,
    observed,
    outcome,
    wrote,
    owned,
    reason,
    route,
    activeColorMode,
  );
}

enum PlayerState {
  idle,
  loading,
  ready,
  playing,
  paused,
  buffering,
  seeking,
  ended,
  stopped,
  error,
  unsupported,
}

class PlayerStatus {
  const PlayerStatus({
    required this.state,
    required this.message,
    this.recoverable = false,
    this.failureCode,
    this.httpStatus,
  });

  final PlayerState state;
  final String message;
  final bool recoverable;
  final String? failureCode;
  final int? httpStatus;
}

class PlayerEvent {
  const PlayerEvent({
    required this.status,
    required this.position,
    required this.duration,
    required this.telemetry,
    required this.tracks,
    this.tracksUpdated = false,
    this.generation,
  });

  final PlayerStatus status;
  final Duration position;
  final Duration duration;
  final PlayerTelemetry telemetry;
  final List<PlayerTrack> tracks;

  /// A track-list property update arrived for this load, including an empty list.
  /// Other events may carry the reset snapshot without establishing no video.
  final bool tracksUpdated;

  /// Identifies the media load associated with this event.
  ///
  /// Production native players project the active generation onto emitted
  /// events so `PlayerCoordinator` can ignore events from superseded loads.
  final int? generation;
}

class PlayerVideoRect {
  const PlayerVideoRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.scale,
  });

  final double left;
  final double top;
  final double width;
  final double height;
  final double scale;

  @override
  bool operator ==(Object other) =>
      other is PlayerVideoRect &&
      left == other.left &&
      top == other.top &&
      width == other.width &&
      height == other.height &&
      scale == other.scale;

  @override
  int get hashCode => Object.hash(left, top, width, height, scale);
}

enum PlayerTrackType { video, audio, subtitle }

class PlayerTrack {
  const PlayerTrack({
    required this.id,
    required this.type,
    required this.selected,
    this.title,
    this.language,
    this.codec,
    this.channelCount,
    this.channelLayout,
    this.forced,
    this.external,
    this.hearingImpaired,
    this.visualImpaired,
    this.commentary,
  });

  final int id;
  final PlayerTrackType type;
  final bool selected;
  final String? title;
  final String? language;
  final String? codec;
  final int? channelCount;
  final String? channelLayout;
  final bool? forced;
  final bool? external;
  final bool? hearingImpaired;
  final bool? visualImpaired;
  final bool? commentary;
}

class PlayerTelemetry {
  const PlayerTelemetry({
    this.videoOutput,
    this.hardwareDecoder,
    this.videoCodec,
    this.videoFormat,
    this.width,
    this.height,
    this.pixelFormat,
    this.hardwarePixelFormat,
    this.primaries,
    this.gamma,
    this.targetGamma,
    this.targetPrimaries,
    this.targetPixelFormat,
    this.colorMatrix,
    this.signalPeak,
  });

  final String? videoOutput;
  final String? hardwareDecoder;
  final String? videoCodec;
  final String? videoFormat;
  final int? width;
  final int? height;
  final String? pixelFormat;
  final String? hardwarePixelFormat;
  final String? primaries;
  final String? gamma;
  final String? targetGamma;
  final String? targetPrimaries;
  final String? targetPixelFormat;
  final String? colorMatrix;
  final double? signalPeak;

  bool get isHdr {
    final transfer = gamma?.toLowerCase();
    return transfer == 'pq' || transfer == 'hlg' || transfer == 'smpte-st-2084';
  }

  @override
  bool operator ==(Object other) =>
      other is PlayerTelemetry &&
      videoOutput == other.videoOutput &&
      hardwareDecoder == other.hardwareDecoder &&
      videoCodec == other.videoCodec &&
      videoFormat == other.videoFormat &&
      width == other.width &&
      height == other.height &&
      pixelFormat == other.pixelFormat &&
      hardwarePixelFormat == other.hardwarePixelFormat &&
      primaries == other.primaries &&
      gamma == other.gamma &&
      targetGamma == other.targetGamma &&
      targetPrimaries == other.targetPrimaries &&
      targetPixelFormat == other.targetPixelFormat &&
      colorMatrix == other.colorMatrix &&
      signalPeak == other.signalPeak;

  @override
  int get hashCode => Object.hash(
    videoOutput,
    hardwareDecoder,
    videoCodec,
    videoFormat,
    width,
    height,
    pixelFormat,
    hardwarePixelFormat,
    primaries,
    gamma,
    targetGamma,
    targetPrimaries,
    targetPixelFormat,
    colorMatrix,
    signalPeak,
  );
}

class PlayerUnavailable implements Exception {
  const PlayerUnavailable(
    this.message, {
    this.failureCode = 'player_unavailable',
  });

  final String message;
  final String failureCode;

  @override
  String toString() => message;
}
