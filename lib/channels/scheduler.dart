import 'channel.dart';

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

ScheduleIndex buildSchedule(
  List<ChannelItem> content, {
  required PlaybackMode mode,
  required int seed,
  int blockSize = 3,
}) {
  if (content.isEmpty) throw const FormatException('A channel needs content');
  if (content.any((item) => item.duration <= Duration.zero)) {
    throw const FormatException('Program durations must be positive');
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
  final elapsed = time.toUtc().difference(anchor.toUtc()).inMilliseconds;
  final loopMs = schedule.loopDuration.inMilliseconds;
  final loop = (elapsed / loopMs).floor();
  final position = ((elapsed % loopMs) + loopMs) % loopMs;
  var low = 0;
  var high = schedule.offsets.length - 1;
  while (low < high) {
    final middle = ((low + high + 1) / 2).floor();
    if (schedule.offsets[middle].inMilliseconds <= position) {
      low = middle;
    } else {
      high = middle - 1;
    }
  }
  final start = anchor.toUtc().add(
    Duration(
      milliseconds: loop * loopMs + schedule.offsets[low].inMilliseconds,
    ),
  );
  final item = schedule.items[low];
  return ScheduledProgram(
    item: item,
    start: start,
    end: start.add(item.duration),
    elapsed: Duration(
      milliseconds: position - schedule.offsets[low].inMilliseconds,
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
) {
  if (!end.isAfter(start)) return const [];
  final programs = <ScheduledProgram>[programAt(start, anchor, schedule)];
  while (programs.last.end.isBefore(end) && programs.length < 1000) {
    programs.add(programAt(programs.last.end, anchor, schedule));
  }
  return programs;
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
