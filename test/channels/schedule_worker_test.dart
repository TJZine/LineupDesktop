import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/content_resolver.dart';
import 'package:lineup_desktop/channels/schedule_worker.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

void main() {
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
