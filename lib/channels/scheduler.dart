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
  const ScheduleIndex({
    required this.items,
    required this.offsets,
    required this.loopDuration,
  });

  final List<ChannelItem> items;
  final List<Duration> offsets;
  final Duration loopDuration;
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
    PlaybackMode.shuffle => seededShuffle(content, seed),
    PlaybackMode.block => blockOrder(content, seed, blockSize),
  };
  final offsets = <Duration>[];
  var total = Duration.zero;
  for (final item in items) {
    offsets.add(total);
    total += item.duration;
  }
  return ScheduleIndex(items: items, offsets: offsets, loopDuration: total);
}

ScheduledProgram programAt(
  DateTime time,
  DateTime anchor,
  ScheduleIndex schedule,
) {
  final elapsed = time.toUtc().difference(anchor.toUtc()).inMicroseconds;
  final loopUs = schedule.loopDuration.inMicroseconds;
  final position = ((elapsed % loopUs) + loopUs) % loopUs;
  final loop = (elapsed - position) ~/ loopUs;
  var low = 0;
  var high = schedule.offsets.length - 1;
  while (low < high) {
    final middle = ((low + high + 1) / 2).floor();
    if (schedule.offsets[middle].inMicroseconds <= position) {
      low = middle;
    } else {
      high = middle - 1;
    }
  }
  final start = anchor.toUtc().add(
    Duration(
      microseconds: loop * loopUs + schedule.offsets[low].inMicroseconds,
    ),
  );
  final item = schedule.items[low];
  return ScheduledProgram(
    item: item,
    start: start,
    end: start.add(item.duration),
    elapsed: Duration(
      microseconds: position - schedule.offsets[low].inMicroseconds,
    ),
    index: low,
    loop: loop,
  );
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

List<ChannelItem> blockOrder(List<ChannelItem> items, int seed, int blockSize) {
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

int _imul(int left, int right) {
  final leftLow = left & 0xffff;
  final leftHigh = (left >>> 16) & 0xffff;
  return (leftLow * right + ((leftHigh * right & 0xffff) << 16)) & 0xffffffff;
}
