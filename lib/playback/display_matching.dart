import 'dart:async';

import 'native_player.dart';

bool displayMatchingSession({
  required bool active,
  required bool enabled,
  required bool fullscreen,
  required bool intent,
  required bool playerVisible,
  required bool fullGuide,
  required bool error,
}) =>
    enabled &&
    fullscreen &&
    intent &&
    !error &&
    (active || (playerVisible && !fullGuide));

DisplayMatchingState decodedDisplayState(PlayerTelemetry telemetry) =>
    telemetry.gamma == null
    ? DisplayMatchingState.unknown
    : telemetry.isHdr
    ? DisplayMatchingState.hdr
    : DisplayMatchingState.sdr;

class DisplayMatching {
  DisplayMatching({
    required this.player,
    required this.clock,
    required this.changed,
  }) : report = player.displayReport;
  final NativePlayer player;
  final DateTime Function() clock;
  final void Function() changed;
  DisplayMatchingReport report;
  bool session = false;
  DisplayMatchingState desired = DisplayMatchingState.unknown;
  int revision = 0;
  int _sessionRevision = 0;
  int _operationEpoch = 0;
  bool _targetRetired = false;
  int? _load;
  Duration? _target;
  DateTime? _ready;
  bool? _noVideo;
  DateTime? _positionReached;
  bool _decided = false;
  bool _transferKnown = false;
  bool _userPaused = false;
  bool _suppressTransition = false;
  _DisplayHold? _hold;
  Timer? _timer;
  bool get holdActive => _hold != null;
  bool get startPaused =>
      session &&
      (report.revision < _sessionRevision ||
          !{
            DisplayMatchingSessionState.unavailable,
            DisplayMatchingSessionState.suspended,
          }.contains(report.session));

  void updateSession(bool next, {required bool paused}) {
    if (next == session) return;
    ++_operationEpoch;
    session = next;
    _targetRetired = false;
    _send();
    if (next) _sessionRevision = revision;
    if (next && _load != null) {
      _userPaused = paused && !_suppressTransition;
      _hold = _DisplayHold(false);
      _requestDecision();
      _schedule();
    } else if (!next) {
      _finish(resume: true);
    }
  }

  void _send() {
    final sentRevision = ++revision;
    final sentLoad = _load;
    final sentEpoch = _operationEpoch;
    unawaited(
      player
          .setDisplayMatching(
            DisplayMatchingRequest(
              revision: revision,
              session: session,
              desired: desired,
            ),
          )
          .catchError((Object _) {
            if (revision == sentRevision &&
                _load == sentLoad &&
                _operationEpoch == sentEpoch) {
              _finish(resume: true);
            }
          }),
    );
  }

  bool beginLoad(int generation, Duration? target) {
    cancelLoad();
    _load = generation;
    _target = target;
    _ready = null;
    _noVideo = null;
    _positionReached = null;
    _decided = false;
    _transferKnown = false;
    _userPaused = false;
    if (desired != DisplayMatchingState.unknown) {
      desired = DisplayMatchingState.unknown;
      if (session) _send();
    }
    final paused = startPaused;
    if (paused) {
      _hold = _DisplayHold(true);
      _suppressTransition = true;
    }
    return paused;
  }

  void ready(int generation) {
    if (_load != generation) return;
    _ready ??= clock();
    if (_noVideo == true && !_decided) _decide(DisplayMatchingState.unknown);
    _schedule();
  }

  void tracksUpdated(int generation, {required bool noVideo}) {
    if (_load != generation) return;
    _noVideo = noVideo;
    if (_ready != null && noVideo && !_decided) {
      _decide(DisplayMatchingState.unknown);
    }
  }

  void observe(int generation, PlayerTelemetry telemetry, Duration position) {
    if (_load != generation) return;
    if (_target != null && position >= _target!) _positionReached ??= clock();
    if (!_transferKnown && telemetry.gamma != null) {
      _transferKnown = true;
      _decide(decodedDisplayState(telemetry));
    }
    _schedule();
  }

  void _decide(DisplayMatchingState value) {
    _decided = true;
    if (desired != value) {
      desired = value;
      if (session) _send();
    }
    _requestDecision();
  }

  void _requestDecision() {
    final hold = _hold;
    if (hold == null || !_decided) return;
    if (desired == DisplayMatchingState.unknown) {
      _finish(resume: true);
      return;
    }
    hold.revision ??= revision;
    hold.requested ??= clock();
    if (report.revision >= hold.revision!) _applyReport();
    _schedule();
  }

  void receive(DisplayMatchingReport value) {
    if (value.revision < report.revision || value == report) return;
    report = value;
    if (value.revision >= _sessionRevision &&
        value.session != DisplayMatchingSessionState.active) {
      ++_operationEpoch;
      _targetRetired = true;
    }
    if (session &&
        _load != null &&
        _hold == null &&
        _targetRetired &&
        value.session == DisplayMatchingSessionState.active &&
        value.revision >= _sessionRevision) {
      _hold = _DisplayHold(false);
      _requestDecision();
    }
    if (value.session == DisplayMatchingSessionState.active) {
      _targetRetired = false;
    }
    _applyReport();
    changed();
  }

  void _applyReport() {
    final hold = _hold;
    if (hold == null || report.revision < (hold.revision ?? revision)) return;
    if (report.session != DisplayMatchingSessionState.active ||
        report.outcome == DisplayMatchingOutcome.failed) {
      _finish(resume: true);
      return;
    }
    if (!_decided) return;
    if (!hold.prepaused && !hold.checkedObserved) {
      hold.checkedObserved = true;
      if (desired == report.observed) {
        _finish(resume: true);
        return;
      }
      if (!_userPaused) {
        hold.paused = true;
        _suppressTransition = true;
        unawaited(
          player.pause().catchError((Object _) {
            if (identical(_hold, hold)) _finish(resume: true);
          }),
        );
      }
    }
    if (report.outcome == DisplayMatchingOutcome.matched) {
      if (!report.wrote) {
        _finish(resume: true);
      } else {
        hold.settle ??= clock().add(const Duration(milliseconds: 1500));
      }
    } else if (hold.prepaused && desired == report.observed && !report.wrote) {
      _finish(resume: true);
    }
    _schedule();
  }

  bool suppressTransition(PlayerState state) {
    final suppress = _suppressTransition || holdActive;
    if (state == PlayerState.playing && !holdActive) {
      _suppressTransition = false;
    }
    return suppress &&
        (state == PlayerState.paused || state == PlayerState.playing);
  }

  void userPlay() {
    _finish(resume: false);
    _userPaused = false;
    _suppressTransition = false;
  }

  void userPause() {
    _userPaused = true;
    _suppressTransition = false;
    _finish(resume: false);
  }

  void cancelLoad() {
    ++_operationEpoch;
    _finish(resume: false);
    _load = null;
    _suppressTransition = false;
  }

  void _finish({required bool resume}) {
    final hold = _hold;
    if (hold == null) return;
    _hold = null;
    _timer?.cancel();
    if (resume && !_userPaused && (hold.prepaused || hold.paused)) {
      _suppressTransition = true;
      unawaited(player.play().catchError((Object _) {}));
    }
    changed();
  }

  void _schedule() {
    _timer?.cancel();
    final hold = _hold;
    if (hold == null) return;
    final deadlines = <DateTime>[
      if (!_decided && _ready != null) _ready!.add(const Duration(seconds: 6)),
      if (!_decided && (_target == null ? _ready : _positionReached) != null)
        (_target == null ? _ready! : _positionReached!).add(
          const Duration(seconds: 2),
        ),
      if (hold.requested != null)
        hold.requested!.add(const Duration(seconds: 4)),
      if (hold.settle != null) hold.settle!,
    ]..sort();
    if (deadlines.isEmpty) return;
    final delay = deadlines.first.difference(clock());
    _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (!identical(_hold, hold)) return;
      if (!_decided) {
        _decide(DisplayMatchingState.unknown);
      } else {
        _finish(resume: true);
      }
    });
  }

  void dispose() {
    cancelLoad();
    if (session) {
      session = false;
      _send();
    }
    _timer?.cancel();
  }
}

class _DisplayHold {
  _DisplayHold(this.prepaused);
  final bool prepaused;
  bool paused = false;
  bool checkedObserved = false;
  int? revision;
  DateTime? requested;
  DateTime? settle;
}
