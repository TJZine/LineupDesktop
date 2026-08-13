import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/schedule_worker.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

void main() {
  test('spawn failure does not prevent a later build', () async {
    final unsendable = ReceivePort();
    final media = <PlexMediaItem>[_UnsendableMediaItem(unsendable)];
    final worker = ScheduleWorker(media, const []);
    addTearDown(worker.dispose);

    await expectLater(worker.build(_channel), throwsA(anything));
    unsendable.close();
    media
      ..clear()
      ..add(_mediaItem);

    final schedule = await worker.build(_channel);

    expect(schedule.items.single.id, _mediaItem.id);
  });

  test('send failure does not retain the failed operation', () async {
    final unsendable = ReceivePort();
    final worker = ScheduleWorker(const [], const []);
    addTearDown(worker.dispose);

    await expectLater(
      worker.build(_manualChannel(_UnsendableChannelItem(unsendable))),
      throwsA(anything),
    );
    unsendable.close();

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
}

final _channel = Channel(
  id: 'channel',
  number: 1,
  name: 'Channel',
  source: const LibrarySource(
    libraryId: 'library',
    libraryType: PlexLibraryType.movie,
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

const _mediaItem = PlexMediaItem(
  id: 'item',
  key: '/library/metadata/item',
  title: 'Item',
  type: 'movie',
  duration: Duration(minutes: 30),
  libraryId: 'library',
);

class _UnsendableMediaItem extends PlexMediaItem {
  _UnsendableMediaItem(this.unsendable)
    : super(
        id: 'unsendable',
        key: '/library/metadata/unsendable',
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
        key: '/library/metadata/exiting',
        title: 'Exiting',
        type: 'movie',
        duration: const Duration(minutes: 30),
      );

  @override
  String? get libraryId => Isolate.exit();
}
