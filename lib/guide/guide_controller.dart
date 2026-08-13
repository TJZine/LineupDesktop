import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../app/lineup_controller.dart';
import '../channels/channel.dart';
import '../channels/scheduler.dart';
import '../settings/lineup_settings.dart';

typedef GuideScheduleLoader = Future<ScheduleIndex> Function(Channel channel);

abstract final class GuideGeometry {
  static ({double left, double width}) programRect({
    required DateTime windowStart,
    required DateTime windowEnd,
    required DateTime programStart,
    required DateTime programEnd,
    required double viewportWidth,
  }) {
    final total = windowEnd.difference(windowStart).inMicroseconds;
    if (total <= 0 || viewportWidth <= 0) return (left: 0, width: 0);
    final left =
        (viewportWidth *
                programStart.difference(windowStart).inMicroseconds /
                total)
            .clamp(0.0, viewportWidth)
            .toDouble();
    final right =
        (viewportWidth *
                programEnd.difference(windowStart).inMicroseconds /
                total)
            .clamp(0.0, viewportWidth)
            .toDouble();
    return (left: left, width: (right - left).clamp(0.0, viewportWidth));
  }

  static ({int first, int count}) visibleRows({
    required double scrollOffset,
    required double viewportHeight,
    required double rowHeight,
    required int totalRows,
  }) {
    if (totalRows <= 0 || rowHeight <= 0 || viewportHeight <= 0) {
      return (first: 0, count: 0);
    }
    final first = (scrollOffset / rowHeight).floor().clamp(0, totalRows - 1);
    final count = (viewportHeight / rowHeight).ceil().clamp(
      1,
      totalRows - first,
    );
    return (first: first, count: count);
  }
}

enum GuideLoadState { loading, ready, error }

@immutable
class GuideProgram {
  const GuideProgram({required this.channelId, required this.scheduled});

  final String channelId;
  final ScheduledProgram scheduled;

  String get id =>
      '$channelId:${scheduled.item.id}:${scheduled.start.microsecondsSinceEpoch}';
  bool isCurrentAt(DateTime now) =>
      !now.isBefore(scheduled.start) && now.isBefore(scheduled.end);
}

@immutable
class GuideRowData {
  const GuideRowData({
    required this.state,
    this.programs = const [],
    this.error,
  });

  final GuideLoadState state;
  final List<GuideProgram> programs;
  final Object? error;
}

class GuideController extends ChangeNotifier {
  static const maximumCachedArtworkEntries = 12;
  static const maximumConcurrentArtworkLoads = 4;

  GuideController({
    required this.lineup,
    GuideScheduleLoader? loadSchedule,
    DateTime Function()? clock,
    this.maximumCachedRows = 64,
    this.maximumConcurrentLoads = 4,
  }) : _loadSchedule = loadSchedule ?? lineup.loadScheduleFor,
       _clock = clock ?? DateTime.now {
    _channels = lineup.channels;
    _contentGeneration = lineup.contentGeneration;
    _updateVisibleChannels();
    _settings = lineup.settings;
    _windowStart = _initialWindowStart;
    _focusTime = _clock();
    _focusedChannelId = _channels.firstOrNull?.id;
    lineup.addListener(_reconcileLineup);
  }

  final LineupController lineup;
  final GuideScheduleLoader _loadSchedule;
  final DateTime Function() _clock;
  final int maximumCachedRows;
  final int maximumConcurrentLoads;
  final LinkedHashMap<String, GuideRowData> _rows = LinkedHashMap();
  final LinkedHashMap<String, ScheduleIndex> _schedules = LinkedHashMap();
  final LinkedHashMap<String, Future<Uint8List?>> _artwork = LinkedHashMap();
  final Queue<Channel> _pending = Queue();
  final Set<String> _queuedIds = {};
  final Queue<_ArtworkRequest> _pendingArtwork = Queue();
  final Set<Completer<void>> _rowWaiters = {};
  List<Channel> _channels = const [];
  Map<String, Channel> _channelById = const {};
  List<Channel> _visibleChannels = const [];
  Map<String, int> _visibleIndexById = const {};
  Set<String> _availableLibraryIds = const {};
  LineupSettings _settings = const LineupSettings();
  late DateTime _windowStart;
  late DateTime _focusTime;
  String? _focusedChannelId;
  String? _focusedProgramId;
  String? _selectedChannelId;
  String? _selectedProgramId;
  String? _libraryFilterId;
  int _generation = 0;
  late int _contentGeneration;
  int _activeLoads = 0;
  int _activeArtworkLoads = 0;
  bool _disposed = false;
  double _verticalOffset = 0;

  List<Channel> get channels => _visibleChannels;

  DateTime get windowStart => _windowStart;
  DateTime get windowEnd =>
      _windowStart.add(Duration(hours: _settings.guideHours));
  DateTime get focusTime => _focusTime;
  DateTime get now => _clock();
  String? get focusedChannelId => _focusedChannelId;
  String? get focusedProgramId => _focusedProgramId;
  String? get selectedChannelId => _selectedChannelId;
  String? get selectedProgramId => _selectedProgramId;
  String? get libraryFilterId => _libraryFilterId;
  GuideDensity get density => _settings.guideDensity;
  int get guideHours => _settings.guideHours;
  int get cachedRowCount => _rows.length;
  int get activeLoadCount => _activeLoads;
  double get verticalOffset => _verticalOffset;
  int get focusedChannelIndex =>
      _visibleIndexById[_focusedChannelId] ??
      (_visibleChannels.isEmpty ? -1 : 0);

  GuideRowData row(String channelId) =>
      _rows[channelId] ?? const GuideRowData(state: GuideLoadState.loading);

  GuideProgram? get selectedProgram {
    final id = _selectedProgramId;
    final channelId = _selectedChannelId;
    if (id == null || channelId == null) return null;
    return row(channelId).programs
        .where((program) => program.id == id)
        .firstOrNull;
  }

  GuideProgram? get focusedProgram {
    final id = _focusedProgramId;
    final channelId = _focusedChannelId;
    if (id == null || channelId == null) return null;
    return row(channelId).programs
        .where((program) => program.id == id)
        .firstOrNull;
  }

  GuideProgram? currentProgram(String channelId, [DateTime? at]) {
    final now = at ?? _clock();
    final schedule = _schedules[channelId];
    final channel = _channelById[channelId];
    if (schedule != null && channel != null) {
      final scheduled = programAt(now, channel.anchor, schedule);
      return GuideProgram(channelId: channelId, scheduled: scheduled);
    }
    return row(channelId).programs
        .where((program) => program.isCurrentAt(now))
        .firstOrNull;
  }

  GuideProgram? nextProgram(String channelId, [DateTime? at]) {
    final current = currentProgram(channelId, at);
    final schedule = _schedules[channelId];
    final channel = _channelById[channelId];
    if (current == null || schedule == null || channel == null) return null;
    final scheduled = programAt(
      current.scheduled.end,
      channel.anchor,
      schedule,
    );
    return GuideProgram(channelId: channelId, scheduled: scheduled);
  }

  Future<GuideProgram?> ensureCurrentProgram(String channelId) async {
    if (_disposed) return null;
    final channel = _channelById[channelId];
    if (channel == null) return null;
    if (_schedules.containsKey(channelId)) return currentProgram(channelId);
    final existing = _rows[channelId];
    if (existing?.state == GuideLoadState.error) _rows.remove(channelId);
    _request(channel);
    final completer = Completer<void>();
    _rowWaiters.add(completer);
    void changed() {
      final value = _rows[channelId];
      if (value != null && value.state != GuideLoadState.loading) {
        if (!completer.isCompleted) completer.complete();
      } else if (!_channelById.containsKey(channelId)) {
        if (!completer.isCompleted) completer.complete();
      }
    }

    addListener(changed);
    changed();
    try {
      await completer.future.timeout(const Duration(seconds: 15));
    } finally {
      _rowWaiters.remove(completer);
      removeListener(changed);
    }
    return currentProgram(channelId);
  }

  Set<String> get availableLibraryIds => _availableLibraryIds;

  Future<Uint8List?> artworkFor(GuideProgram program) {
    if (_disposed) return Future.value();
    final path = program.scheduled.item.artwork;
    if (path == null || path.toString().isEmpty) return Future.value();
    final key = '${program.scheduled.item.id}|$path';
    final existing = _artwork.remove(key);
    if (existing != null) {
      _artwork[key] = existing;
      return existing;
    }
    final completer = Completer<Uint8List?>();
    final loading = completer.future;
    _artwork[key] = loading;
    _pendingArtwork.add(
      _ArtworkRequest(key, program.scheduled.item, completer, _generation),
    );
    while (_artwork.length > maximumCachedArtworkEntries) {
      final evicted = _artwork.keys.first;
      _artwork.remove(evicted);
      _pendingArtwork.removeWhere((request) {
        if (request.key != evicted) return false;
        if (!request.completer.isCompleted) request.completer.complete(null);
        return true;
      });
    }
    _pumpArtwork();
    return loading;
  }

  void _pumpArtwork() {
    if (_disposed) return;
    while (_activeArtworkLoads < maximumConcurrentArtworkLoads &&
        _pendingArtwork.isNotEmpty) {
      final request = _pendingArtwork.removeFirst();
      if (!identical(_artwork[request.key], request.completer.future)) {
        if (!request.completer.isCompleted) request.completer.complete(null);
        continue;
      }
      _activeArtworkLoads++;
      lineup
          .artworkFor(request.item)
          .then((value) {
            final current =
                request.generation == _generation &&
                identical(_artwork[request.key], request.completer.future);
            request.completer.complete(current ? value : null);
          }, onError: (_) => request.completer.complete(null))
          .whenComplete(() {
            _activeArtworkLoads--;
            if (!_disposed) _pumpArtwork();
          });
    }
  }

  void requestViewport(int firstIndex, int visibleCount) {
    final visible = channels;
    if (visible.isEmpty) return;
    final start = (firstIndex - 3).clamp(0, visible.length);
    final end = (firstIndex + visibleCount + 6).clamp(0, visible.length);
    for (var index = start; index < end; index++) {
      _request(visible[index]);
    }
  }

  void requestChannels(Iterable<Channel> channels) {
    for (final channel in channels) {
      _request(channel);
    }
  }

  Future<void> retry(String channelId) async {
    _rows.remove(channelId);
    final channel = _channelById[channelId];
    if (channel != null) _request(channel);
  }

  void focusProgram(GuideProgram program) {
    _focusedChannelId = program.channelId;
    _focusedProgramId = program.id;
    _focusTime = _programFocusTime(program);
    notifyListeners();
  }

  void selectProgram(GuideProgram program) {
    _focusedChannelId = program.channelId;
    _focusedProgramId = program.id;
    _selectedChannelId = program.channelId;
    _selectedProgramId = program.id;
    _focusTime = _programFocusTime(program);
    notifyListeners();
  }

  GuideProgram? selectFocusedProgram() {
    final program = focusedProgram;
    if (program != null) selectProgram(program);
    return program;
  }

  void rememberVerticalOffset(double value) {
    if (value.isFinite && value >= 0) _verticalOffset = value;
  }

  void moveVertical(int offset) {
    final visible = channels;
    if (visible.isEmpty) return;
    final current = focusedChannelIndex;
    final target = ((current < 0 ? 0 : current) + offset).clamp(
      0,
      visible.length - 1,
    );
    _focusedChannelId = visible[target].id;
    _selectAtFocusTime();
    notifyListeners();
  }

  void page(int offset, int visibleRows) =>
      moveVertical(offset * visibleRows.clamp(1, channels.length));

  void moveHorizontal(int offset) {
    final programs = _focusedChannelId == null
        ? const <GuideProgram>[]
        : row(_focusedChannelId!).programs;
    final current = programs.indexWhere(
      (program) => program.id == _focusedProgramId,
    );
    if (current >= 0 &&
        current + offset >= 0 &&
        current + offset < programs.length) {
      final selected = programs[current + offset];
      _focusedProgramId = selected.id;
      _focusTime = _programFocusTime(selected);
      if (_focusTime.isBefore(_windowStart) ||
          !_focusTime.isBefore(windowEnd)) {
        _shiftWindow(offset);
      }
    } else {
      _focusTime = _focusTime.add(Duration(minutes: 30 * offset));
      _shiftWindow(offset);
    }
    notifyListeners();
  }

  void playToNow() {
    final now = _clock();
    _focusTime = now;
    _windowStart = _floorHalfHour(
      now.subtract(Duration(minutes: _settings.pastMinutes)),
    );
    _reloadRows();
  }

  void setLibraryFilter(String? libraryId) {
    if (_libraryFilterId == libraryId) return;
    _libraryFilterId = libraryId;
    _updateVisibleChannels();
    final visible = _visibleChannels;
    if (!visible.any((channel) => channel.id == _focusedChannelId)) {
      _focusedChannelId = visible.firstOrNull?.id;
      _focusedProgramId = null;
    }
    if (!visible.any((channel) => channel.id == _selectedChannelId)) {
      _selectedChannelId = null;
      _selectedProgramId = null;
    }
    notifyListeners();
  }

  void _shiftWindow(int direction) {
    final minimum = _floorHalfHour(
      _clock().subtract(Duration(minutes: _settings.pastMinutes)),
    );
    final next = _windowStart.add(Duration(minutes: 30 * direction));
    _windowStart = next.isBefore(minimum) ? minimum : next;
    _reloadRows();
  }

  void _selectAtFocusTime() {
    final channelId = _focusedChannelId;
    if (channelId == null) return;
    final programs = row(channelId).programs;
    final match = programs
        .where(
          (program) =>
              !_focusTime.isBefore(program.scheduled.start) &&
              _focusTime.isBefore(program.scheduled.end),
        )
        .firstOrNull;
    _focusedProgramId = match?.id;
  }

  DateTime _programFocusTime(GuideProgram program) {
    if (!_focusTime.isBefore(program.scheduled.start) &&
        _focusTime.isBefore(program.scheduled.end)) {
      return _focusTime;
    }
    final current = _clock();
    if (!current.isBefore(program.scheduled.start) &&
        current.isBefore(program.scheduled.end)) {
      return current;
    }
    return program.scheduled.start.add(
      Duration(
        microseconds:
            program.scheduled.end
                .difference(program.scheduled.start)
                .inMicroseconds ~/
            2,
      ),
    );
  }

  void _request(Channel channel) {
    if (_disposed) return;
    if (_rows.containsKey(channel.id) || !_queuedIds.add(channel.id)) return;
    _pending.add(channel);
    _pump();
  }

  void _pump() {
    if (_disposed) return;
    while (_activeLoads < maximumConcurrentLoads && _pending.isNotEmpty) {
      final channel = _pending.removeFirst();
      _queuedIds.remove(channel.id);
      final generation = _generation;
      _activeLoads++;
      _rows[channel.id] = const GuideRowData(state: GuideLoadState.loading);
      final cachedSchedule = _schedules.remove(channel.id);
      final loading = cachedSchedule == null
          ? _loadSchedule(channel)
          : Future<ScheduleIndex>.value(cachedSchedule);
      if (cachedSchedule != null) _schedules[channel.id] = cachedSchedule;
      loading
          .then(
            (schedule) {
              if (_disposed ||
                  generation != _generation ||
                  !_channelById.containsKey(channel.id)) {
                return;
              }
              _putSchedule(channel.id, schedule);
              final projected =
                  scheduleWindow(
                        _windowStart,
                        windowEnd,
                        channel.anchor,
                        schedule,
                      )
                      .map((scheduled) {
                        return GuideProgram(
                          channelId: channel.id,
                          scheduled: scheduled,
                        );
                      })
                      .toList(growable: false);
              _putRow(
                channel.id,
                GuideRowData(state: GuideLoadState.ready, programs: projected),
              );
              if (_focusedChannelId == channel.id) _selectAtFocusTime();
              if (_selectedChannelId == channel.id &&
                  !projected.any(
                    (program) => program.id == _selectedProgramId,
                  )) {
                _selectedChannelId = null;
                _selectedProgramId = null;
              }
              notifyListeners();
            },
            onError: (Object error) {
              if (_disposed || generation != _generation) return;
              _putRow(
                channel.id,
                GuideRowData(state: GuideLoadState.error, error: error),
              );
              notifyListeners();
            },
          )
          .whenComplete(() {
            _activeLoads--;
            if (!_disposed) _pump();
          });
    }
  }

  void _putRow(String id, GuideRowData value) {
    _rows.remove(id);
    _rows[id] = value;
    while (_rows.length > maximumCachedRows) {
      _rows.remove(_rows.keys.first);
    }
  }

  void _putSchedule(String id, ScheduleIndex value) {
    _schedules.remove(id);
    _schedules[id] = value;
    while (_schedules.length > maximumCachedRows) {
      _schedules.remove(_schedules.keys.first);
    }
  }

  void _reloadRows({bool clearSchedules = false}) {
    _generation++;
    _pending.clear();
    _queuedIds.clear();
    _rows.clear();
    if (clearSchedules) _schedules.clear();
    if (clearSchedules) _artwork.clear();
    if (clearSchedules) {
      for (final request in _pendingArtwork) {
        if (!request.completer.isCompleted) request.completer.complete(null);
      }
      _pendingArtwork.clear();
    }
    notifyListeners();
  }

  void _reconcileLineup() {
    final old = _channels;
    final focusedIndex = focusedChannelIndex;
    final next = lineup.channels;
    final contentChanged = _contentGeneration != lineup.contentGeneration;
    _contentGeneration = lineup.contentGeneration;
    final lineupChanged =
        contentChanged ||
        (!identical(old, next) &&
            !listEquals(
              old.map(_channelFingerprint).toList(),
              next.map(_channelFingerprint).toList(),
            ));
    final settingsChanged =
        _settings.guideHours != lineup.settings.guideHours ||
        _settings.pastMinutes != lineup.settings.pastMinutes ||
        _settings.guideDensity != lineup.settings.guideDensity ||
        _settings.libraryTabsEnabled != lineup.settings.libraryTabsEnabled;
    _channels = next;
    _settings = lineup.settings;
    if (contentChanged) {
      _libraryFilterId = null;
      _focusedProgramId = null;
      _selectedChannelId = null;
      _selectedProgramId = null;
    }
    if (!_settings.libraryTabsEnabled && _libraryFilterId != null) {
      _libraryFilterId = null;
      _updateVisibleChannels();
    }
    if (lineupChanged) {
      _updateVisibleChannels();
      if (_libraryFilterId != null &&
          !availableLibraryIds.contains(_libraryFilterId)) {
        _libraryFilterId = null;
        _updateVisibleChannels();
      }
      if (!_visibleIndexById.containsKey(_focusedChannelId)) {
        if (_visibleChannels.isEmpty) {
          _focusedChannelId = null;
        } else {
          final fallback = focusedIndex < 0
              ? 0
              : focusedIndex.clamp(0, _visibleChannels.length - 1);
          _focusedChannelId = _visibleChannels[fallback].id;
        }
        _focusedProgramId = null;
      }
      if (!_visibleIndexById.containsKey(_selectedChannelId)) {
        _selectedChannelId = null;
        _selectedProgramId = null;
      }
      _reloadRows(clearSchedules: true);
    } else if (settingsChanged) {
      playToNow();
    } else {
      notifyListeners();
    }
  }

  void _updateVisibleChannels() {
    _channelById = {for (final channel in _channels) channel.id: channel};
    _availableLibraryIds = {
      for (final channel in _channels) ..._sourceLibraryIds(channel.source),
    };
    final filter = _libraryFilterId;
    _visibleChannels = filter == null
        ? _channels
        : _channels
              .where(
                (channel) => _sourceLibraryIds(channel.source).contains(filter),
              )
              .toList(growable: false);
    _visibleIndexById = {
      for (var index = 0; index < _visibleChannels.length; index++)
        _visibleChannels[index].id: index,
    };
  }

  DateTime get _initialWindowStart => _floorHalfHour(
    _clock().subtract(Duration(minutes: _settings.pastMinutes)),
  );

  @override
  void dispose() {
    _disposed = true;
    lineup.removeListener(_reconcileLineup);
    _generation++;
    _pending.clear();
    _queuedIds.clear();
    for (final request in _pendingArtwork) {
      if (!request.completer.isCompleted) request.completer.complete(null);
    }
    _pendingArtwork.clear();
    _artwork.clear();
    for (final waiter in _rowWaiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _rowWaiters.clear();
    super.dispose();
  }
}

class _ArtworkRequest {
  const _ArtworkRequest(this.key, this.item, this.completer, this.generation);

  final String key;
  final ChannelItem item;
  final Completer<Uint8List?> completer;
  final int generation;
}

String _channelFingerprint(Channel channel) =>
    '${channel.id}|${channel.number}|${channel.name}|${channel.anchor.microsecondsSinceEpoch}|${channel.shuffleSeed}|${channel.blockSize}|${channel.playbackMode}|${channel.source.toJson()}';

DateTime _floorHalfHour(DateTime value) => DateTime(
  value.year,
  value.month,
  value.day,
  value.hour,
  value.minute < 30 ? 0 : 30,
);

Set<String> _sourceLibraryIds(ContentSource source) => switch (source) {
  LibrarySource(:final libraryId) => {libraryId},
  MixedSource(:final sources) => {
    for (final source in sources) ..._sourceLibraryIds(source),
  },
  ManualSource() || PlaylistSource() => const {},
};
