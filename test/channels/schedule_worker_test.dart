import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/content_resolver.dart';
import 'package:lineup_desktop/channels/schedule_worker.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';

import '../support/ui_fixture.dart';

void main() {
  test('fresh reordered inventories preserve production worker and Guide queries', () async {
    final media = [
      for (final (id, minutes) in [('c', 17), ('a', 11), ('b', 13)])
        PlexMediaItem(
          id: id,
          title: id,
          type: 'movie',
          duration: Duration(minutes: minutes),
          libraryId: 'library',
          collections: const ['Collection'],
          parts: [
            PlexMediaPart(path: '/parts/$id/first'),
            PlexMediaPart(path: '/parts/$id/second'),
          ],
        ),
    ];
    final occurrences = [media[0], media[1], media[0], media[2]];
    const library = LibrarySource(
      libraryId: 'library',
      libraryType: PlexLibraryType.movie,
      filters: {
        LibraryFilter.collection: ['Collection'],
      },
    );
    const playlist = PlaylistSource('playlist');
    final sources = <ContentSource>[
      library,
      playlist,
      const MixedSource(sources: [library, playlist], interleave: true),
    ];
    final now = DateTime.utc(2026, 10, 8, 12, 17);
    for (final source in sources) {
      for (final version in [1, currentScheduleVersion]) {
        final channel = Channel(
          id: 'channel',
          number: 1,
          name: 'Channel',
          source: source,
          playbackMode: PlaybackMode.shuffle,
          anchor: DateTime.utc(2026),
          shuffleSeed: 19,
          scheduleVersion: version,
        );
        Object? expected;
        for (var permutation = 0; permutation < 4; permutation++) {
          List<T> reorder<T>(List<T> values) => switch (permutation) {
            0 => List.of(values),
            1 => values.reversed.toList(),
            2 => [...values.skip(1), values.first],
            _ => [...values.skip(2), ...values.take(2)],
          };
          final lineup = FixtureController()
            ..channels = [Channel.fromJson(channel.toJson())]
            ..availableMedia = reorder(media)
            ..availablePlaylists = [
              PlexPlaylist(
                id: 'playlist',
                title: 'Playlist',
                items: reorder(occurrences),
              ),
            ];
          final guide = GuideController(lineup: lineup, clock: () => now);
          try {
            final schedule = await lineup.loadScheduleFor(
              lineup.channels.single,
            );
            final current = await guide.ensureCurrentProgram(channel.id);
            expect(current, isNotNull);
            expect(guide.row(channel.id).state, GuideLoadState.ready);
            final actual = [
              schedule.items.map((item) => item.id).toList(),
              schedule.offsets,
              schedule.loopDuration,
              _scheduledIdentity(programAt(now, channel.anchor, schedule)),
              _scheduledIdentity(current!.scheduled),
              guide
                  .row(channel.id)
                  .programs
                  .map((program) => _scheduledIdentity(program.scheduled))
                  .toList(),
            ];
            if (permutation == 0) {
              expected = actual;
            } else {
              expect(
                actual,
                expected,
                reason:
                    '${source.runtimeType}, version $version, permutation $permutation',
              );
            }
            expect(
              schedule.items,
              hasLength(
                source is LibrarySource
                    ? 3
                    : source is PlaylistSource
                    ? 4
                    : 7,
              ),
            );
          } finally {
            guide.dispose();
            lineup.dispose();
          }
        }
      }
    }
  });

  test('spawn failure does not prevent a later build', () async {
    final unsendable = ReceivePort();
    addTearDown(unsendable.close);
    final media = <PlexMediaItem>[_UnsendableMediaItem(unsendable)];
    final worker = ScheduleWorker(media, const []);
    addTearDown(worker.dispose);

    await expectLater(worker.build(_channel), throwsA(anything));
    media
      ..clear()
      ..add(_mediaItem);

    final schedule = await worker.build(_channel);

    expect(schedule.items.single.id, _mediaItem.id);
  });

  test('send failure does not retain the failed operation', () async {
    final unsendable = ReceivePort();
    addTearDown(unsendable.close);
    final worker = ScheduleWorker([_mediaItem], const []);
    addTearDown(worker.dispose);

    await expectLater(
      worker.build(_manualChannel(_UnsendableChannelItem(unsendable))),
      throwsA(anything),
    );
    final schedule = await worker.build(
      _manualChannel(
        const ChannelItem(
          id: 'item',
          title: 'Item',
          duration: Duration(minutes: 30),
        ),
      ),
    );

    expect(schedule.items.single.id, 'item');
  });

  test(
    'expected build failures retain typed reasons across the isolate',
    () async {
      final worker = ScheduleWorker([_mediaItem], const []);
      addTearDown(worker.dispose);

      await expectLater(
        worker.build(_libraryChannel(libraryId: 'missing')),
        throwsA(
          isA<ScheduleBuildException>().having(
            (error) => error.reason,
            'reason',
            ScheduleFailureReason.noContent,
          ),
        ),
      );
      await expectLater(
        worker.build(
          _libraryChannel(
            filters: const {
              LibraryFilter.decade: ['invalid'],
            },
          ),
        ),
        throwsA(
          isA<ScheduleBuildException>().having(
            (error) => error.reason,
            'reason',
            ScheduleFailureReason.unsupportedSource,
          ),
        ),
      );
    },
  );

  test(
    'unexpected isolate exit fails pending work and permits restart',
    () async {
      final media = <PlexMediaItem>[const _ExitingMediaItem()];
      final worker = ScheduleWorker(media, const []);
      addTearDown(worker.dispose);

      await expectLater(worker.build(_channel), throwsA(isA<StateError>()));
      media
        ..clear()
        ..add(_mediaItem);

      final schedule = await worker.build(_channel);

      expect(schedule.items.single.id, _mediaItem.id);
    },
  );

  test(
    'worker and sync schedules agree around a transition boundary',
    () async {
      final media = [
        _mediaItem,
        PlexMediaItem(
          id: 'second',
          title: 'Second',
          type: 'movie',
          duration: const Duration(minutes: 17),
          libraryId: 'library',
          parts: [PlexMediaPart(path: '/library/parts/second')],
        ),
      ];
      final boundary = DateTime.utc(2026, 1, 1, 1);
      final channel = Channel(
        id: 'transition',
        number: 1,
        name: 'Transition',
        source: const LibrarySource(
          libraryId: 'library',
          libraryType: PlexLibraryType.movie,
          order: LibraryOrder.title,
        ),
        playbackMode: PlaybackMode.shuffle,
        anchor: DateTime.utc(2026),
        shuffleSeed: 19,
        scheduleTransition: ScheduleTransition(
          boundary: boundary,
          legacyCycleItems: const [
            ChannelItem(
              id: 'second',
              title: 'Second',
              duration: Duration(minutes: 17),
            ),
            ChannelItem(
              id: 'item',
              title: 'Item',
              duration: Duration(minutes: 30),
            ),
          ],
        ),
      );
      final worker = ScheduleWorker(media, const []);
      addTearDown(worker.dispose);

      final isolated = await worker.build(channel);
      final sync = buildChannelSchedule(
        channel,
        resolveContent(channel.source, media),
      );

      for (final time in [
        boundary.subtract(const Duration(microseconds: 1)),
        boundary,
        boundary.add(const Duration(minutes: 31)),
      ]) {
        final expected = programAt(time, channel.anchor, sync);
        final actual = programAt(time, channel.anchor, isolated);
        expect(actual.item.id, expected.item.id);
        expect(actual.start, expected.start);
        expect(actual.end, expected.end);
        expect(actual.elapsed, expected.elapsed);
        expect(actual.loop, expected.loop);
      }
    },
  );
}

final _channel = _libraryChannel();

Channel _libraryChannel({
  String libraryId = 'library',
  Map<LibraryFilter, List<String>> filters = const {},
}) => Channel(
  id: 'channel',
  number: 1,
  name: 'Channel',
  source: LibrarySource(
    libraryId: libraryId,
    libraryType: PlexLibraryType.movie,
    filters: filters,
  ),
  playbackMode: PlaybackMode.sequential,
  anchor: DateTime.utc(2026),
  shuffleSeed: 1,
);

Channel _manualChannel(ChannelItem item) => Channel(
  id: 'manual',
  number: 1,
  name: 'Manual',
  source: ManualSource([item]),
  playbackMode: PlaybackMode.sequential,
  anchor: DateTime.utc(2026),
  shuffleSeed: 1,
);

final _mediaItem = PlexMediaItem(
  id: 'item',
  title: 'Item',
  type: 'movie',
  duration: Duration(minutes: 30),
  libraryId: 'library',
  parts: [PlexMediaPart(path: '/library/parts/item')],
);

class _UnsendableMediaItem extends PlexMediaItem {
  _UnsendableMediaItem(this.unsendable)
    : super(
        id: 'unsendable',
        title: 'Unsendable',
        type: 'movie',
        duration: const Duration(minutes: 30),
        libraryId: 'library',
      );

  final ReceivePort unsendable;
}

class _UnsendableChannelItem extends ChannelItem {
  _UnsendableChannelItem(this.unsendable)
    : super(
        id: 'unsendable',
        title: 'Unsendable',
        duration: const Duration(minutes: 30),
      );

  final ReceivePort unsendable;
}

class _ExitingMediaItem extends PlexMediaItem {
  const _ExitingMediaItem()
    : super(
        id: 'exiting',
        title: 'Exiting',
        type: 'movie',
        duration: const Duration(minutes: 30),
      );

  @override
  String? get libraryId => Isolate.exit();
}

Object _scheduledIdentity(ScheduledProgram program) => (
  program.item.id,
  program.start,
  program.end,
  program.elapsed,
  program.index,
  program.loop,
);
