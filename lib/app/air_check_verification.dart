import 'dart:async';

import 'package:flutter/foundation.dart';

import '../channels/channel.dart';
import '../channels/scheduler.dart';
import '../guide/guide_controller.dart';

const channelAirCheckDebounce = Duration(milliseconds: 80);

enum ChannelAirCheckValidity { unknown, valid, retainedOffAir }

sealed class AirCheckBaseline {
  const AirCheckBaseline(this.key);
  final String? key;
}

final class BaselineLoading extends AirCheckBaseline {
  const BaselineLoading(super.key);
}

final class BaselineAvailable extends AirCheckBaseline {
  const BaselineAvailable(super.key, this.schedule);
  final ScheduleIndex schedule;
}

final class BaselineOffAir extends AirCheckBaseline {
  const BaselineOffAir(super.key);
}

final class BaselineFailed extends AirCheckBaseline {
  const BaselineFailed(super.key, this.error);
  final Object error;
}

final class AirCheckResult {
  const AirCheckResult({
    required this.revisionKey,
    required this.validity,
    this.preview,
    this.error,
  });
  final String revisionKey;
  final ChannelAirCheckValidity validity;
  final AirCheckPreview? preview;
  final Object? error;
  ScheduleWindowResult? get projectedWindow => preview?.window;
}

/// Studio owns this revision-bound schedule verification and projection lifetime.
class AirCheckVerification extends ChangeNotifier {
  AirCheckVerification({required this.loadSchedule, required this.clock}) {
    _clockTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _advanceClock(),
    );
  }
  final Future<ScheduleIndex> Function(Channel) loadSchedule;
  final DateTime Function() clock;
  Timer? _debounce;
  Timer? _clockTimer;
  _AirCheckRequest? _active;
  _AirCheckRequest? _pending;
  AirCheckPreview? _preview;
  AirCheckBaseline _baseline = const BaselineLoading(null);
  Object? _error;
  bool _disposed = false;
  int _futureHours = 6;
  int _requestVersion = 0;
  String _targetKey = '';
  String? _wantedOriginalKey;
  late Channel _channel;
  Channel? _original;
  String? _sourceIssue;
  String _sourceLabel = '';
  ChannelAirCheckValidity _validity = ChannelAirCheckValidity.unknown;
  bool changesOnNow = false;

  AirCheckResult get result => AirCheckResult(
    revisionKey: _targetKey,
    validity: _validity,
    preview: _preview,
    error: _error,
  );
  AirCheckBaseline get baseline => _baseline;
  int get futureHours => _futureHours;
  bool get comparisonFailed =>
      _baseline is BaselineFailed && _baseline.key == _wantedOriginalKey;
  bool get stale =>
      _preview != null &&
      (_active != null ||
          _pending != null ||
          _error != null ||
          _preview!.key != _targetKey);
  bool get _comparisonReady =>
      _original == null ||
      (_baseline.key == _wantedOriginalKey &&
          (_baseline is BaselineAvailable || _baseline is BaselineOffAir));

  void update(
    Channel preview,
    Channel? original,
    int generation,
    String? sourceIssue, {
    String sourceLabel = '',
  }) {
    final nextKey = channelAirCheckSnapshotKey(preview, generation);
    final originalKey = original == null
        ? null
        : channelAirCheckSnapshotKey(original, generation);
    final initial = _targetKey.isEmpty;
    final changed =
        nextKey != _targetKey ||
        originalKey != _wantedOriginalKey ||
        sourceIssue != _sourceIssue;
    _channel = preview;
    _original = original;
    _sourceLabel = sourceLabel;
    _sourceIssue = sourceIssue;
    _targetKey = nextKey;
    _wantedOriginalKey = originalKey;
    if (changed) {
      _scheduleLoad(initial: initial);
    } else if (_preview case final current? when current.key == nextKey) {
      _preview = current.withChannel(preview);
      _publish();
    }
  }

  bool _canRetainOffAir(Object error) =>
      hasNonemptyRetainedManualContent(_channel.source) &&
      _isNoContentFailure(error);

  void _setValidity(ChannelAirCheckValidity validity) {
    _validity = validity;
    _publish();
  }

  void _publish() {
    if (_disposed) return;
    _compareNow();
    notifyListeners();
  }

  void _compareNow() {
    changesOnNow = false;
    final preview = _preview;
    final original = _original;
    if (preview == null ||
        original == null ||
        canonicalScheduleIdentity(original) ==
            canonicalScheduleIdentity(_channel)) {
      return;
    }
    if (_baseline case BaselineOffAir(:final key)
        when key == _wantedOriginalKey) {
      changesOnNow = true;
    } else if (_baseline case BaselineAvailable(:final key, :final schedule)
        when key == _wantedOriginalKey) {
      try {
        final now = clock();
        changesOnNow =
            programAt(now, original.anchor, schedule).item.id !=
            programAt(now, preview.channel.anchor, preview.schedule).item.id;
      } on ScheduleBuildException catch (error) {
        _preview = null;
        _baseline = BaselineLoading(_wantedOriginalKey);
        _error = error;
        _validity = ChannelAirCheckValidity.unknown;
      }
    }
  }

  void extendHorizon() {
    final preview = _preview;
    if (preview == null || stale) return;
    final nextHours = (_futureHours + 6).clamp(6, 24);
    try {
      _preview = _project(
        preview.schedule,
        preview.key,
        preview.channel,
        futureHours: nextHours,
        sourceLabel: preview.sourceLabel,
      );
      _futureHours = nextHours;
      _error = null;
    } on ScheduleBuildException catch (error) {
      _projectionFailed(error);
    } catch (error) {
      _validity = ChannelAirCheckValidity.unknown;
      _error = error;
    }
    _publish();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  void _scheduleLoad({bool initial = false}) {
    _debounce?.cancel();
    final version = ++_requestVersion;
    _pending = null;
    final issue = _sourceIssue;
    if (issue != null) {
      _error = AirCheckSourceIssue(issue);
      _setValidity(
        _canRetainOffAir(_error!)
            ? ChannelAirCheckValidity.retainedOffAir
            : ChannelAirCheckValidity.unknown,
      );
      _publish();
      return;
    }
    _setValidity(ChannelAirCheckValidity.unknown);
    if (initial) {
      _enqueueRequired(version);
    } else {
      _debounce = Timer(
        channelAirCheckDebounce,
        () => _enqueueRequired(version),
      );
    }
  }

  void _enqueueRequired(int version) {
    if (_disposed || version != _requestVersion) return;
    final target = _AirCheckRequest(
      key: _targetKey,
      channel: _channel,
      sourceLabel: _sourceLabel,
      baseline: false,
      publishes: true,
      version: version,
    );
    final original = _original;
    final originalKey = _wantedOriginalKey;
    if (original != null &&
        originalKey != null &&
        !(_baseline is BaselineAvailable && _baseline.key == originalKey)) {
      _enqueue(
        _AirCheckRequest(
          key: originalKey,
          channel: original,
          sourceLabel: _sourceLabel,
          baseline: true,
          publishes: originalKey == _targetKey,
          version: version,
          followUp: originalKey == _targetKey ? null : target,
        ),
      );
      return;
    }
    _enqueue(target);
  }

  void retry() {
    _error = null;
    _scheduleLoad();
    _publish();
  }

  void _enqueue(_AirCheckRequest request) {
    if (_disposed) return;
    if (_active != null) {
      _pending = request;
      _publish();
      return;
    }
    _start(request);
  }

  void _start(_AirCheckRequest request) {
    _active = request;
    _error = null;
    if (request.baseline && request.key == _wantedOriginalKey) {
      _baseline = BaselineLoading(request.key);
    }
    _publish();
    unawaited(_load(request));
  }

  Future<void> _load(_AirCheckRequest request) async {
    try {
      final schedule = await loadSchedule(request.channel);
      if (_disposed) return;
      if (request.baseline && request.key == _wantedOriginalKey) {
        programAt(clock(), request.channel.anchor, schedule);
        _baseline = BaselineAvailable(request.key, schedule);
      }
      if (request.publishes &&
          request.key == _targetKey &&
          request.version == _requestVersion) {
        // Name/number edits do not reload schedules. Publish their latest text
        // with this request's verified schedule and captured source label.
        final preview = _project(
          schedule,
          request.key,
          _channel,
          sourceLabel: request.sourceLabel,
        );
        _preview = preview;
        _error = null;
        _compareNow();
        final validity = _preview != null && _comparisonReady
            ? ChannelAirCheckValidity.valid
            : ChannelAirCheckValidity.unknown;
        _setValidity(validity);
      }
    } catch (error) {
      if (_disposed || request.version != _requestVersion) return;
      if (request.baseline && request.key == _wantedOriginalKey) {
        _baseline = _isNoContentFailure(error)
            ? BaselineOffAir(request.key)
            : BaselineFailed(request.key, error);
      }
      if (request.key != _targetKey) return;
      _error = error;
      _setValidity(
        _canRetainOffAir(error)
            ? ChannelAirCheckValidity.retainedOffAir
            : ChannelAirCheckValidity.unknown,
      );
    } finally {
      if (!_disposed) {
        if (identical(_active, request)) _active = null;
        final pending =
            _pending ??
            (request.version == _requestVersion ? request.followUp : null);
        _pending = null;
        if (pending != null) {
          _start(pending);
        } else if (!_disposed) {
          _publish();
        }
      }
    }
  }

  AirCheckPreview _project(
    ScheduleIndex schedule,
    String key,
    Channel channel, {
    int? futureHours,
    required String sourceLabel,
  }) {
    final now = clock().toUtc();
    final current = programAt(now, channel.anchor, schedule);
    final start = current.start;
    final requestedEnd = now.add(Duration(hours: futureHours ?? _futureHours));
    final projected = scheduleWindowResult(
      start,
      requestedEnd,
      channel.anchor,
      schedule,
    );
    final programs = projected.programs
        .where(
          (program) =>
              program.start == current.start ||
              !program.end.isAfter(requestedEnd),
        )
        .toList(growable: false);
    final result = ScheduleWindowResult(
      programs: programs,
      truncated: projected.truncated,
      lastProjectedEnd: programs.lastOrNull?.end,
    );
    return AirCheckPreview(
      schedule: schedule,
      sourceLabel: sourceLabel,
      channel: channel,
      window: result,
      key: key,
      windowStart: start,
      windowEnd: requestedEnd,
      ribbonStart: now,
      ribbonEnd: now.add(const Duration(hours: 2)),
    );
  }

  void _advanceClock() {
    if (_disposed || _preview == null || _error != null) return;
    try {
      _refreshClockProjection();
    } on ScheduleBuildException catch (error) {
      _projectionFailed(error);
      _publish();
    }
  }

  void _projectionFailed(ScheduleBuildException error) {
    _preview = null;
    _baseline = BaselineLoading(_wantedOriginalKey);
    _error = error;
    _setValidity(ChannelAirCheckValidity.unknown);
  }

  void _refreshClockProjection() {
    final previous = _preview!;
    final now = clock();
    final previousCurrentIndex = previous.programs.indexWhere(
      (item) => item.isCurrentAt(now),
    );
    final needsRollover =
        previousCurrentIndex < 0 ||
        previousCurrentIndex + 1 >= previous.programs.length ||
        now.isBefore(previous.ribbonStart) ||
        !now.isBefore(previous.ribbonEnd);
    final next = needsRollover
        ? _project(
            previous.schedule,
            previous.key,
            previous.channel,
            sourceLabel: previous.sourceLabel,
          )
        : previous;
    _preview = next;
    _publish();
  }
}

class _AirCheckRequest {
  const _AirCheckRequest({
    required this.key,
    required this.channel,
    required this.baseline,
    required this.publishes,
    required this.version,
    required this.sourceLabel,
    this.followUp,
  });

  final String key;
  final Channel channel;
  final bool baseline;
  final bool publishes;
  final int version;
  final String sourceLabel;
  final _AirCheckRequest? followUp;
}

class AirCheckPreview {
  const AirCheckPreview({
    required this.schedule,
    required this.sourceLabel,
    required this.channel,
    required this.window,
    required this.key,
    required this.windowStart,
    required this.windowEnd,
    required this.ribbonStart,
    required this.ribbonEnd,
  });

  final ScheduleIndex schedule;
  final String sourceLabel;
  final Channel channel;
  final ScheduleWindowResult window;
  final String key;
  final DateTime windowStart;
  final DateTime windowEnd;
  final DateTime ribbonStart;
  final DateTime ribbonEnd;

  AirCheckPreview withChannel(Channel value) => AirCheckPreview(
    schedule: schedule,
    sourceLabel: sourceLabel,
    channel: value,
    window: window,
    key: key,
    windowStart: windowStart,
    windowEnd: windowEnd,
    ribbonStart: ribbonStart,
    ribbonEnd: ribbonEnd,
  );
  List<GuideProgram> get programs => window.programs
      .map(
        (scheduled) =>
            GuideProgram(channelId: 'air-check', scheduled: scheduled),
      )
      .toList(growable: false);
}

class AirCheckSourceIssue {
  const AirCheckSourceIssue(this.message);
  final String message;
}

bool _isNoContentFailure(Object error) =>
    error is ScheduleBuildException &&
    error.reason == ScheduleFailureReason.noContent;
String channelAirCheckSnapshotKey(Channel channel, int generation) =>
    '${canonicalScheduleIdentity(channel)}|$generation';
