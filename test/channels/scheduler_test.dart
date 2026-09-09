import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';

void main() {
  final items = [
    const ChannelItem(id: 'a', title: 'A', duration: Duration(minutes: 10)),
    const ChannelItem(id: 'b', title: 'B', duration: Duration(minutes: 20)),
  ];
  final anchor = DateTime.utc(2026, 1, 1, 12);

  test('invalid schedules report stable failure reasons', () {
    Matcher failsWith(ScheduleFailureReason reason) => throwsA(
      isA<ScheduleBuildException>().having(
        (error) => error.reason,
        'reason',
        reason,
      ),
    );

    expect(
      () => buildSchedule(const [], mode: PlaybackMode.sequential, seed: 1),
      failsWith(ScheduleFailureReason.noContent),
    );
    expect(
      () => buildSchedule(
        const [ChannelItem(id: 'zero', title: 'Zero', duration: Duration.zero)],
        mode: PlaybackMode.sequential,
        seed: 1,
      ),
      failsWith(ScheduleFailureReason.invalidProgramDuration),
    );
  });

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

  test('program lookup keeps large loop boundaries exact', () {
    final schedule = buildSchedule(
      const [
        ChannelItem(
          id: 'large-a',
          title: 'Large A',
          duration: Duration(microseconds: 1),
        ),
        ChannelItem(
          id: 'large-b',
          title: 'Large B',
          duration: Duration(microseconds: 1),
        ),
      ],
      mode: PlaybackMode.sequential,
      seed: 1,
    );
    final time = anchor.add(const Duration(microseconds: 9007199254740995));

    final program = programAt(time, anchor, schedule);

    expect(program.item.id, 'large-b');
    expect(program.loop, 4503599627370497);
    expect(program.start, time);
    expect(program.elapsed, Duration.zero);
  });

  test('seeded shuffle is stable and preserves every item', () {
    final first = seededShuffle(items, 90210);
    final second = seededShuffle(items, 90210);
    expect(first.map((item) => item.id), second.map((item) => item.id));
    expect(first.map((item) => item.id).toSet(), {'a', 'b'});
  });

  test('v2 shuffle is reproducible and varies complete cycles', () {
    final content = [
      ...items,
      const ChannelItem(id: 'c', title: 'C', duration: Duration(minutes: 30)),
      const ChannelItem(id: 'd', title: 'D', duration: Duration(minutes: 40)),
    ];
    final channel = Channel(
      id: 'shuffle',
      number: 1,
      name: 'Shuffle',
      source: const ManualSource([]),
      playbackMode: PlaybackMode.shuffle,
      anchor: anchor,
      shuffleSeed: 90210,
    );
    final first = buildChannelSchedule(channel, content);
    final restarted = buildChannelSchedule(
      Channel.fromJson(channel.toJson()),
      content,
    );
    final cycleDuration = content.fold(
      Duration.zero,
      (total, item) => total + item.duration,
    );

    List<String> cycle(ScheduleIndex schedule, int index) => scheduleWindow(
      anchor.add(cycleDuration * index),
      anchor.add(cycleDuration * (index + 1)),
      anchor,
      schedule,
    ).map((program) => program.item.id).toList();

    expect(cycle(first, 0), cycle(restarted, 0));
    expect(cycle(first, 1), cycle(restarted, 1));
    expect(cycle(first, 0), isNot(cycle(first, 1)));
    expect(cycle(first, 50000), cycle(restarted, 50000));
    expect(cycle(first, 0).toSet(), {'a', 'b', 'c', 'd'});
  });

  test(
    'v2 shuffle handles adjacent tiny and duplicate cycles deterministically',
    () {
      List<List<String>> cycles(List<ChannelItem> content, int seed) {
        final schedule = buildSchedule(
          content,
          mode: PlaybackMode.shuffle,
          seed: seed,
          scheduleVersion: currentScheduleVersion,
        );
        final duration = content.fold(
          Duration.zero,
          (total, item) => total + item.duration,
        );
        return [
          for (var cycle = 0; cycle < 8; cycle++)
            scheduleWindow(
              anchor.add(duration * cycle),
              anchor.add(duration * (cycle + 1)),
              anchor,
              schedule,
            ).map((program) => program.item.id).toList(),
        ];
      }

      final two = [
        const ChannelItem(id: 'a', title: 'A', duration: Duration(minutes: 1)),
        const ChannelItem(id: 'b', title: 'B', duration: Duration(minutes: 1)),
      ];
      final duplicates = [
        const ChannelItem(id: 'a', title: 'A1', duration: Duration(minutes: 1)),
        const ChannelItem(id: 'a', title: 'A2', duration: Duration(minutes: 1)),
        const ChannelItem(id: 'b', title: 'B', duration: Duration(minutes: 1)),
      ];

      final twoCycles = cycles(two, 17);
      final duplicateCycles = cycles(duplicates, 17);
      expect(cycles(two, 17), twoCycles);
      expect(cycles(duplicates, 17), duplicateCycles);
      for (final cycle in twoCycles) {
        expect(cycle.toSet(), {'a', 'b'});
      }
      for (final cycle in duplicateCycles) {
        expect(cycle.where((id) => id == 'a'), hasLength(2));
        expect(cycle.where((id) => id == 'b'), hasLength(1));
      }
    },
  );

  test('v2 shuffle repairs adjacent repeats when a bounded swap exists', () {
    final content = [
      const ChannelItem(id: 'a', title: 'A', duration: Duration(minutes: 1)),
      const ChannelItem(id: 'b', title: 'B', duration: Duration(minutes: 1)),
      const ChannelItem(id: 'c', title: 'C', duration: Duration(minutes: 1)),
    ];
    final schedule = buildSchedule(
      content,
      mode: PlaybackMode.shuffle,
      seed: 17,
      scheduleVersion: currentScheduleVersion,
    );
    final duration = const Duration(minutes: 3);
    final cycles = [
      for (var cycle = 0; cycle < 20; cycle++)
        scheduleWindow(
          anchor.add(duration * cycle),
          anchor.add(duration * (cycle + 1)),
          anchor,
          schedule,
        ).map((program) => program.item.id).toList(),
    ];

    for (var cycle = 1; cycle < cycles.length; cycle++) {
      expect(cycles[cycle].first, isNot(cycles[cycle - 1].last));
    }
  });

  test('transition preserves the frozen cycle and changes at its boundary', () {
    final channel = Channel(
      id: 'transition',
      number: 1,
      name: 'Transition',
      source: const ManualSource([]),
      playbackMode: PlaybackMode.shuffle,
      anchor: anchor,
      shuffleSeed: 7,
      scheduleTransition: ScheduleTransition(
        boundary: anchor.add(const Duration(minutes: 30)),
        legacyCycleItems: items,
      ),
    );
    final schedule = buildChannelSchedule(channel, const [
      ChannelItem(id: 'new', title: 'New', duration: Duration(minutes: 5)),
    ]);
    final restarted = buildChannelSchedule(
      Channel.fromJson(channel.toJson()),
      const [
        ChannelItem(id: 'new', title: 'New', duration: Duration(minutes: 5)),
      ],
    );

    expect(
      programAt(
        anchor.add(const Duration(minutes: 29)),
        anchor,
        schedule,
      ).item.id,
      'b',
    );
    expect(
      programAt(
        anchor.add(const Duration(minutes: 30)),
        anchor,
        schedule,
      ).item.id,
      'new',
    );
    expect(
      programAt(
        anchor.add(const Duration(minutes: 29)),
        anchor,
        restarted,
      ).item.id,
      'b',
    );
  });

  test(
    'derived legacy shuffle and block cycles stay stable through restart',
    () {
      final content = [
        const ChannelItem(
          id: 's1e2',
          title: 'S1E2',
          duration: Duration(minutes: 7),
          mediaKind: ChannelMediaKind.episode,
          seriesId: 'show',
          seasonNumber: 1,
          episodeNumber: 2,
        ),
        const ChannelItem(
          id: 'other',
          title: 'Other',
          duration: Duration(minutes: 11),
          mediaKind: ChannelMediaKind.episode,
          seriesId: 'other-show',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
        const ChannelItem(
          id: 's1e1',
          title: 'S1E1',
          duration: Duration(minutes: 13),
          mediaKind: ChannelMediaKind.episode,
          seriesId: 'show',
          seasonNumber: 1,
          episodeNumber: 1,
        ),
      ];

      for (final mode in [PlaybackMode.shuffle, PlaybackMode.block]) {
        final legacyChannel = Channel(
          id: mode.name,
          number: 1,
          name: mode.name,
          source: const ManualSource([]),
          playbackMode: mode,
          anchor: anchor,
          shuffleSeed: 23,
          blockSize: mode == PlaybackMode.block ? 2 : null,
          includeSpecials: true,
          scheduleVersion: 1,
        );
        final legacy = buildChannelSchedule(legacyChannel, content);
        final now = anchor.add(
          legacy.loopDuration + const Duration(minutes: 9),
        );
        final migrated = migrateLegacySchedule(legacyChannel, content, now);
        final boundary = migrated.scheduleTransition!.boundary;
        final revised = buildChannelSchedule(migrated, content);
        final restarted = buildChannelSchedule(
          Channel.fromJson(migrated.toJson()),
          content,
        );

        expect(
          migrated.scheduleTransition!.legacyCycleItems.map((item) => item.id),
          legacy.items.map((item) => item.id),
        );
        expect(boundary, anchor.add(legacy.loopDuration * 2));
        for (final time in [
          now,
          boundary.subtract(const Duration(microseconds: 1)),
        ]) {
          final expected = programAt(time, anchor, legacy);
          final actual = programAt(time, anchor, revised);
          final afterRestart = programAt(time, anchor, restarted);
          expect(actual.item.id, expected.item.id, reason: mode.name);
          expect(actual.start, expected.start, reason: mode.name);
          expect(actual.end, expected.end, reason: mode.name);
          expect(afterRestart.item.id, actual.item.id, reason: mode.name);
          expect(afterRestart.start, actual.start, reason: mode.name);
          expect(afterRestart.end, actual.end, reason: mode.name);
        }
        final atBoundary = programAt(boundary, anchor, revised);
        final restartedAtBoundary = programAt(boundary, anchor, restarted);
        expect(
          restartedAtBoundary.item.id,
          atBoundary.item.id,
          reason: mode.name,
        );
        expect(restartedAtBoundary.start, atBoundary.start, reason: mode.name);
      }
    },
  );

  test('mini-marathons honor chronology, seasons, specials, and movies', () {
    ChannelItem episode(String id, int? season, int? number) => ChannelItem(
      id: id,
      title: id,
      duration: const Duration(minutes: 1),
      mediaKind: ChannelMediaKind.episode,
      seriesId: 'show',
      seasonNumber: season,
      episodeNumber: number,
    );
    final content = [
      episode('s2e1', 2, 1),
      episode('unknown', null, null),
      episode('s1e2', 1, 2),
      episode('special', 0, 1),
      episode('s1e1', 1, 1),
      const ChannelItem(
        id: 'movie',
        title: 'Movie',
        duration: Duration(minutes: 1),
        mediaKind: ChannelMediaKind.movie,
      ),
    ];

    final withoutSpecials = blockOrder(content, 1, 3, includeSpecials: false);
    final withSpecials = blockOrder(content, 1, 3);
    final showWithout = withoutSpecials
        .where((item) => item.seriesId == 'show')
        .map((item) => item.id);
    final showWith = withSpecials
        .where((item) => item.seriesId == 'show')
        .map((item) => item.id);

    expect(showWithout, ['s1e1', 's1e2', 's2e1', 'unknown']);
    expect(showWith, ['s1e1', 's1e2', 's2e1', 'special', 'unknown']);
    expect(withoutSpecials.map((item) => item.id), contains('movie'));
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

  test('window result reports exact completion and bounded truncation', () {
    final minute = buildSchedule(
      const [
        ChannelItem(
          id: 'minute',
          title: 'Minute',
          duration: Duration(minutes: 1),
        ),
      ],
      mode: PlaybackMode.sequential,
      seed: 1,
    );
    final exact = scheduleWindowResult(
      anchor,
      anchor.add(const Duration(minutes: 1000)),
      anchor,
      minute,
    );
    final truncated = scheduleWindowResult(
      anchor,
      anchor.add(const Duration(minutes: 1001)),
      anchor,
      minute,
    );

    expect(exact.programs.length, 1000);
    expect(exact.truncated, isFalse);
    expect(exact.lastProjectedEnd, anchor.add(const Duration(minutes: 1000)));
    expect(truncated.programs.length, 1000);
    expect(truncated.truncated, isTrue);
    expect(
      truncated.lastProjectedEnd,
      anchor.add(const Duration(minutes: 1000)),
    );
    expect(
      scheduleWindow(
        anchor,
        anchor.add(const Duration(minutes: 2)),
        anchor,
        minute,
      ),
      hasLength(2),
    );
  });
}
