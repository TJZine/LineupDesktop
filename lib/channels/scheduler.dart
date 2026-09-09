import 'dart:collection';

import 'channel.dart';

enum ScheduleFailureReason {
  noContent,
  invalidProgramDuration,
  unsupportedSource,
}

final class ScheduleBuildException implements Exception {
  const ScheduleBuildException(this.reason);

  final ScheduleFailureReason reason;
}

class ScheduleIndex {
  ScheduleIndex({
    required this.items,
    required this.offsets,
    required this.loopDuration,
    required this.mode,
    required this.seed,
    required this.scheduleVersion,
    this.transition,
  });

  final List<ChannelItem> items;
  final List<Duration> offsets;
  final Duration loopDuration;
  final PlaybackMode mode;
  final int seed;
  final int scheduleVersion;
  final ScheduleTransition? transition;
  late final _CycleIndex? _transitionCycle = transition == null
      ? null
      : _cycleIndex(transition!.legacyCycleItems);
  late final Duration? _transitionDuration = transition == null
      ? null
      : _durationOf(transition!.legacyCycleItems);
  final LinkedHashMap<int, _CycleIndex> _cycles = LinkedHashMap();
}

class _CycleIndex {
  const _CycleIndex(this.items, this.offsets);
  final List<ChannelItem> items;
  final List<Duration> offsets;
}

class ScheduledProgram {
  const ScheduledProgram({
    required this.item,
    required this.start,
    required this.end,
    required this.elapsed,
    required this.index,
    required this.loop,
  });

  final ChannelItem item;
  final DateTime start;
  final DateTime end;
  final Duration elapsed;
  final int index;
  final int loop;
}

class ScheduleWindowResult {
  const ScheduleWindowResult({
    required this.programs,
    required this.truncated,
    required this.lastProjectedEnd,
  });

  final List<ScheduledProgram> programs;
  final bool truncated;
  final DateTime? lastProjectedEnd;
}

ScheduleIndex buildSchedule(
  List<ChannelItem> content, {
  required PlaybackMode mode,
  required int seed,
  int blockSize = 3,
  bool includeSpecials = true,
  int scheduleVersion = 1,
  ScheduleTransition? transition,
}) {
  if (content.isEmpty) {
    throw const ScheduleBuildException(ScheduleFailureReason.noContent);
  }
  if (content.any((item) => item.duration <= Duration.zero)) {
    throw const ScheduleBuildException(
      ScheduleFailureReason.invalidProgramDuration,
    );
  }
  final items = switch (mode) {
    PlaybackMode.sequential => List<ChannelItem>.of(content),
    PlaybackMode.shuffle when scheduleVersion >= 2 => List<ChannelItem>.of(
      content,
    ),
    PlaybackMode.shuffle => seededShuffle(content, seed),
    PlaybackMode.block when scheduleVersion >= 2 => blockOrder(
      content,
      seed,
      blockSize,
      includeSpecials: includeSpecials,
    ),
    PlaybackMode.block => legacyBlockOrder(content, seed, blockSize),
  };
  if (items.isEmpty) {
    throw const ScheduleBuildException(ScheduleFailureReason.noContent);
  }
  final offsets = <Duration>[];
  var total = Duration.zero;
  for (final item in items) {
    offsets.add(total);
    total += item.duration;
  }
  return ScheduleIndex(
    items: List.unmodifiable(items),
    offsets: List.unmodifiable(offsets),
    loopDuration: total,
    mode: mode,
    seed: seed,
    scheduleVersion: scheduleVersion,
    transition: transition,
  );
}

ScheduleIndex buildChannelSchedule(
  Channel channel,
  List<ChannelItem> content,
) => buildSchedule(
  content,
  mode: channel.playbackMode,
  seed: channel.shuffleSeed,
  blockSize: channel.blockSize ?? 3,
  includeSpecials: channel.includeSpecials,
  scheduleVersion: channel.scheduleVersion,
  transition: channel.scheduleTransition,
);

Channel migrateLegacySchedule(
  Channel channel,
  List<ChannelItem> content,
  DateTime now,
) {
  if (channel.scheduleVersion != 1) return channel;
  final legacy = buildSchedule(
    content,
    mode: channel.playbackMode,
    seed: channel.shuffleSeed,
    blockSize: channel.blockSize ?? 3,
    includeSpecials: true,
  );
  final at = programAt(now, channel.anchor, legacy);
  final boundary = channel.anchor.toUtc().add(
    Duration(microseconds: (at.loop + 1) * legacy.loopDuration.inMicroseconds),
  );
  return Channel(
    id: channel.id,
    number: channel.number,
    name: channel.name,
    source: channel.source,
    playbackMode: channel.playbackMode,
    anchor: channel.anchor,
    shuffleSeed: channel.shuffleSeed,
    blockSize: channel.blockSize,
    builderKey: channel.builderKey,
    includeSpecials: channel.includeSpecials,
    scheduleVersion: currentScheduleVersion,
    scheduleTransition: ScheduleTransition(
      boundary: boundary,
      legacyCycleItems: legacy.items,
    ),
  );
}

ScheduledProgram programAt(
  DateTime time,
  DateTime anchor,
  ScheduleIndex schedule,
) {
  final transition = schedule.transition;
  if (transition != null && time.toUtc().isBefore(transition.boundary)) {
    return _programInCycle(
      time,
      transition.boundary,
      schedule._transitionCycle!,
      schedule._transitionDuration!,
    );
  }
  if (schedule.scheduleVersion >= 2 && schedule.mode == PlaybackMode.shuffle) {
    final origin = transition?.boundary ?? anchor.toUtc();
    final elapsed = time.toUtc().difference(origin).inMicroseconds;
    final loopUs = schedule.loopDuration.inMicroseconds;
    final cycle = _floorDivision(elapsed, loopUs);
    final index = _shuffleCycle(schedule, cycle);
    return _programInCycle(
      time,
      origin.add(Duration(microseconds: cycle * loopUs)),
      index,
      schedule.loopDuration,
      loop: cycle,
    );
  }
  return _programInCycle(
    time,
    transition?.boundary ?? anchor.toUtc(),
    _CycleIndex(schedule.items, schedule.offsets),
    schedule.loopDuration,
  );
}

ScheduledProgram _programInCycle(
  DateTime time,
  DateTime anchor,
  _CycleIndex cycle,
  Duration loopDuration, {
  int? loop,
}) {
  final elapsed = time.toUtc().difference(anchor.toUtc()).inMicroseconds;
  final loopUs = loopDuration.inMicroseconds;
  final position = ((elapsed % loopUs) + loopUs) % loopUs;
  final resolvedLoop = loop ?? (elapsed - position) ~/ loopUs;
  var low = 0;
  var high = cycle.offsets.length - 1;
  while (low < high) {
    final middle = ((low + high + 1) / 2).floor();
    if (cycle.offsets[middle].inMicroseconds <= position) {
      low = middle;
    } else {
      high = middle - 1;
    }
  }
  final start = anchor.toUtc().add(
    Duration(
      microseconds:
          (loop == null ? resolvedLoop * loopUs : 0) +
          cycle.offsets[low].inMicroseconds,
    ),
  );
  final item = cycle.items[low];
  return ScheduledProgram(
    item: item,
    start: start,
    end: start.add(item.duration),
    elapsed: Duration(
      microseconds: position - cycle.offsets[low].inMicroseconds,
    ),
    index: low,
    loop: resolvedLoop,
  );
}

int _floorDivision(int value, int divisor) {
  final remainder = ((value % divisor) + divisor) % divisor;
  return (value - remainder) ~/ divisor;
}

Duration _durationOf(List<ChannelItem> items) =>
    items.fold(Duration.zero, (duration, item) => duration + item.duration);

_CycleIndex _cycleIndex(List<ChannelItem> items) {
  final offsets = <Duration>[];
  var total = Duration.zero;
  for (final item in items) {
    offsets.add(total);
    total += item.duration;
  }
  return _CycleIndex(items, List.unmodifiable(offsets));
}

_CycleIndex _shuffleCycle(ScheduleIndex schedule, int cycle) {
  final cached = schedule._cycles.remove(cycle);
  if (cached != null) {
    schedule._cycles[cycle] = cached;
    return cached;
  }
  final items = seededShuffle(
    schedule.items,
    _cycleSeed(schedule.seed, schedule.scheduleVersion, cycle),
  );
  if (items.length > 2) {
    final previous = seededShuffle(
      schedule.items,
      _cycleSeed(schedule.seed, schedule.scheduleVersion, cycle - 1),
    );
    if (items.first.id == previous.last.id) {
      final swap = Iterable<int>.generate(
        items.length - 2,
        (index) => index + 1,
      ).where((index) => items[index].id != previous.last.id).firstOrNull;
      if (swap != null) {
        final first = items.first;
        items[0] = items[swap];
        items[swap] = first;
      }
    }
  }
  final built = _cycleIndex(List.unmodifiable(items));
  schedule._cycles[cycle] = built;
  while (schedule._cycles.length > 4) {
    schedule._cycles.remove(schedule._cycles.keys.first);
  }
  return built;
}

int _cycleSeed(int seed, int version, int cycle) {
  var value = seed & 0xffffffff;
  value = _imul(value ^ (version * 0x9e3779b9), 0x85ebca6b);
  value = _imul(value ^ (cycle & 0xffffffff), 0xc2b2ae35);
  return (value ^ (value >>> 16)) & 0xffffffff;
}

List<ScheduledProgram> scheduleWindow(
  DateTime start,
  DateTime end,
  DateTime anchor,
  ScheduleIndex schedule,
) => scheduleWindowResult(start, end, anchor, schedule).programs;

ScheduleWindowResult scheduleWindowResult(
  DateTime start,
  DateTime end,
  DateTime anchor,
  ScheduleIndex schedule,
) {
  if (!end.isAfter(start)) {
    return const ScheduleWindowResult(
      programs: [],
      truncated: false,
      lastProjectedEnd: null,
    );
  }
  final programs = <ScheduledProgram>[programAt(start, anchor, schedule)];
  while (programs.last.end.isBefore(end) && programs.length < 1000) {
    programs.add(programAt(programs.last.end, anchor, schedule));
  }
  return ScheduleWindowResult(
    programs: List.unmodifiable(programs),
    truncated: programs.last.end.isBefore(end),
    lastProjectedEnd: programs.last.end,
  );
}

List<T> seededShuffle<T>(List<T> input, int seed) {
  final output = List<T>.of(input);
  var state = seed & 0xffffffff;
  double next() {
    state = (state + 0x6d2b79f5) & 0xffffffff;
    var value = state;
    value = _imul(value ^ (value >>> 15), value | 1);
    value ^= value + _imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) & 0xffffffff) / 4294967296;
  }

  for (var index = output.length - 1; index > 0; index--) {
    final swap = (next() * (index + 1)).floor();
    final value = output[index];
    output[index] = output[swap];
    output[swap] = value;
  }
  return output;
}

List<ChannelItem> blockOrder(
  List<ChannelItem> items,
  int seed,
  int blockSize, {
  bool includeSpecials = true,
}) {
  final groups = <String, List<_MarathonRun>>{};
  var occurrence = 0;
  for (final item in items) {
    final isEpisode =
        item.mediaKind == ChannelMediaKind.episode ||
        (item.mediaKind == ChannelMediaKind.unknown &&
            (item.showTitle != null || item.showThumb != null));
    final seriesId = item.seriesId ?? item.showThumb ?? item.showTitle;
    if (!isEpisode || seriesId == null) {
      groups['item:$occurrence'] = [
        _MarathonRun([(item: item, occurrence: occurrence)], season: null),
      ];
      occurrence++;
      continue;
    }
    if (item.seasonNumber == 0 && !includeSpecials) {
      occurrence++;
      continue;
    }
    final runs = groups.putIfAbsent(seriesId, () => []);
    final season = item.seasonNumber;
    final numbered = season != null && item.episodeNumber != null;
    final key = numbered ? season : null;
    final run = runs.where((run) => run.season == key).firstOrNull;
    if (run == null) {
      runs.add(
        _MarathonRun([(item: item, occurrence: occurrence)], season: key),
      );
    } else {
      run.items.add((item: item, occurrence: occurrence));
    }
    occurrence++;
  }
  for (final runs in groups.values) {
    runs.sort((left, right) {
      if (left.season == null) return right.season == null ? 0 : 1;
      if (right.season == null) return -1;
      if (left.season == 0) return right.season == 0 ? 0 : 1;
      if (right.season == 0) return -1;
      return left.season!.compareTo(right.season!);
    });
    for (final run in runs) {
      if (run.season != null) {
        run.items.sort((left, right) {
          final compared = left.item.episodeNumber!.compareTo(
            right.item.episodeNumber!,
          );
          return compared != 0
              ? compared
              : left.occurrence.compareTo(right.occurrence);
        });
      }
    }
  }
  final keys = seededShuffle(groups.keys.toList(), seed);
  final runPositions = {for (final key in keys) key: 0};
  final itemPositions = {for (final key in keys) key: 0};
  final output = <ChannelItem>[];
  final size = blockSize < 1 ? 3 : blockSize;
  final retained = groups.values
      .expand((runs) => runs)
      .fold<int>(0, (count, run) => count + run.items.length);
  while (output.length < retained) {
    for (final key in keys) {
      final runs = groups[key]!;
      var runIndex = runPositions[key]!;
      if (runIndex >= runs.length) continue;
      final run = runs[runIndex];
      final start = itemPositions[key]!;
      final end = (start + size).clamp(0, run.items.length);
      output.addAll(run.items.sublist(start, end).map((entry) => entry.item));
      if (end == run.items.length) {
        runPositions[key] = ++runIndex;
        itemPositions[key] = 0;
      } else {
        itemPositions[key] = end;
      }
    }
  }
  return output;
}

List<ChannelItem> legacyBlockOrder(
  List<ChannelItem> items,
  int seed,
  int blockSize,
) {
  final groups = <String, List<ChannelItem>>{};
  for (final item in items) {
    final key = item.showThumb ?? item.showTitle ?? item.id;
    groups.putIfAbsent(key, () => []).add(item);
  }
  final keys = seededShuffle(groups.keys.toList(), seed);
  final positions = {for (final key in keys) key: 0};
  final output = <ChannelItem>[];
  final size = blockSize < 1 ? 3 : blockSize;
  while (output.length < items.length) {
    for (final key in keys) {
      final group = groups[key]!;
      final start = positions[key]!;
      final end = (start + size).clamp(0, group.length);
      output.addAll(group.sublist(start, end));
      positions[key] = end;
    }
  }
  return output;
}

class _MarathonRun {
  _MarathonRun(this.items, {required this.season});
  final List<({ChannelItem item, int occurrence})> items;
  final int? season;
}

int _imul(int left, int right) {
  final leftLow = left & 0xffff;
  final leftHigh = (left >>> 16) & 0xffff;
  return (leftLow * right + ((leftHigh * right & 0xffff) << 16)) & 0xffffffff;
}
