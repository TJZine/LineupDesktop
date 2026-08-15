import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';

void main() {
  final items = [
    const ChannelItem(id: 'a', title: 'A', duration: Duration(minutes: 10)),
    const ChannelItem(id: 'b', title: 'B', duration: Duration(minutes: 20)),
  ];
  final anchor = DateTime.utc(2026, 1, 1, 12);

  test('program lookup is exact at boundaries and before anchor', () {
    final schedule = buildSchedule(
      items,
      mode: PlaybackMode.sequential,
      seed: 1,
    );
    expect(programAt(anchor, anchor, schedule).item.id, 'a');
    expect(
      programAt(
        anchor.add(const Duration(minutes: 10)),
        anchor,
        schedule,
      ).item.id,
      'b',
    );
    final before = programAt(
      anchor.subtract(const Duration(minutes: 1)),
      anchor,
      schedule,
    );
    expect(before.item.id, 'b');
    expect(before.loop, -1);
    expect(before.elapsed, const Duration(minutes: 19));
  });

  test('program lookup preserves sub-millisecond durations', () {
    final schedule = buildSchedule(
      const [
        ChannelItem(
          id: 'tiny-a',
          title: 'Tiny A',
          duration: Duration(microseconds: 1),
        ),
        ChannelItem(
          id: 'tiny-b',
          title: 'Tiny B',
          duration: Duration(microseconds: 2),
        ),
      ],
      mode: PlaybackMode.sequential,
      seed: 1,
    );

    final program = programAt(
      anchor.add(const Duration(microseconds: 2)),
      anchor,
      schedule,
    );

    expect(program.item.id, 'tiny-b');
    expect(program.elapsed, const Duration(microseconds: 1));
  });

  test('seeded shuffle is stable and preserves every item', () {
    final first = seededShuffle(items, 90210);
    final second = seededShuffle(items, 90210);
    expect(first.map((item) => item.id), second.map((item) => item.id));
    expect(first.map((item) => item.id).toSet(), {'a', 'b'});
  });

  test('block ordering preserves episode order inside a series', () {
    final episodes = [
      const ChannelItem(
        id: 'a1',
        title: 'A1',
        showThumb: '/a',
        duration: Duration(minutes: 1),
      ),
      const ChannelItem(
        id: 'b1',
        title: 'B1',
        showThumb: '/b',
        duration: Duration(minutes: 1),
      ),
      const ChannelItem(
        id: 'a2',
        title: 'A2',
        showThumb: '/a',
        duration: Duration(minutes: 1),
      ),
      const ChannelItem(
        id: 'b2',
        title: 'B2',
        showThumb: '/b',
        duration: Duration(minutes: 1),
      ),
    ];
    final ordered = blockOrder(episodes, 4, 1);
    expect(
      ordered.indexWhere((item) => item.id == 'a1'),
      lessThan(ordered.indexWhere((item) => item.id == 'a2')),
    );
    expect(
      ordered.indexWhere((item) => item.id == 'b1'),
      lessThan(ordered.indexWhere((item) => item.id == 'b2')),
    );
  });
}
