import 'package:lineup_desktop/app/lineup_controller.dart';

import 'dart:async';
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
          final lineup = FixtureController(
            scenario: LineupScenario(
              channels: [Channel.fromJson(channel.toJson())],
              availableMedia: reorder(media),
              availablePlaylists: [
                PlexPlaylist(
                  id: 'playlist',
                  title: 'Playlist',
                  items: reorder(occurrences),
                ),
              ],
            ),
          );
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

  test('simultaneous builds share startup readiness', () async {
    final worker = ScheduleWorker([_mediaItem], const []);
    addTearDown(worker.dispose);

    final schedules = await Future.wait([
      worker.build(_channel),
      worker.build(_channel),
    ]);

    expect(schedules, hasLength(2));
    expect(schedules[0].items.single.id, _mediaItem.id);
    expect(schedules[1].items.single.id, _mediaItem.id);
  });

  test('dispose before spawn completion settles all waiters and kills late isolate', () async {
    final exited = ReceivePort();
    addTearDown(exited.close);
    final spawnRelease = Completer<Isolate>();
    SendPort? responses;
    final worker = ScheduleWorker(
      [_mediaItem],
      const [],
      spawn: (responsePort, _, _) {
        responses = responsePort;
        return spawnRelease.future;
      },
    );
    addTearDown(worker.dispose);

    final first = worker.build(_channel);
    final second = worker.build(_channel);
    worker.dispose();
    worker.dispose();

    await expectLater(first, throwsA(isA<StateError>()));
    await expectLater(second, throwsA(isA<StateError>()));
    expect(responses, isNotNull);
    final responsePort = responses!;

    final lateIsolate = await Isolate.spawn(
      _idleWorker,
      [responsePort],
      onExit: exited.sendPort,
      onError: responsePort,
      errorsAreFatal: true,
    );
    addTearDown(() => lateIsolate.kill(priority: Isolate.immediate));
    spawnRelease.complete(lateIsolate);

    expect(await exited.first.timeout(const Duration(seconds: 1)), isNull);
  });

  test(
    'dispose after spawn before handshake settles readiness and kills isolate',
    () async {
      final exited = ReceivePort();
      addTearDown(exited.close);
      final handshakeControl = ReceivePort();
      addTearDown(handshakeControl.close);
      final handshakeGate = handshakeControl.first.then((message) {
        expect(message, isA<SendPort>());
        return message as SendPort;
      });
      final spawned = Completer<void>();
      final worker = ScheduleWorker(
        [_mediaItem],
        const [],
        spawn: (responses, _, _) async {
          final isolate = await Isolate.spawn(
            _heldHandshakeWorker,
            [responses, handshakeControl.sendPort],
            onExit: exited.sendPort,
            onError: responses,
            errorsAreFatal: true,
          );
          spawned.complete();
          return isolate;
        },
      );
      addTearDown(worker.dispose);

      final build = worker.build(_channel);
      await spawned.future;
      await handshakeGate.timeout(const Duration(seconds: 1));
      await Future<void>.delayed(Duration.zero);
      worker.dispose();
      worker.dispose();

      await expectLater(build, throwsA(isA<StateError>()));
      expect(await exited.first.timeout(const Duration(seconds: 1)), isNull);
    },
  );

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

  test('correlated malformed responses settle their pending build', () async {
    final worker = ScheduleWorker(
      [_mediaItem],
      const [],
      spawn: (responses, _, _) =>
          Isolate.spawn(_correlatedMalformedWorker, responses),
    );
    addTearDown(worker.dispose);

    await expectLater(worker.build(_channel), throwsA(isA<FormatException>()));
  });

  test('uncorrelatable malformed responses retire the generation', () async {
    var spawnCount = 0;
    final secondSpawned = Completer<void>();
    final worker = ScheduleWorker(
      [_mediaItem],
      const [],
      spawn: (responses, _, _) {
        spawnCount++;
        if (spawnCount == 1) {
          return Isolate.spawn(_uncorrelatableWorker, responses);
        }
        secondSpawned.complete();
        return Isolate.spawn(_idleResponseWorker, responses);
      },
    );
    addTearDown(worker.dispose);

    await expectLater(worker.build(_channel), throwsA(isA<FormatException>()));

    final restarted = worker.build(_channel);
    await secondSpawned.future;
    worker.dispose();
    await expectLater(restarted, throwsA(isA<StateError>()));
    expect(spawnCount, 2);
  });

  test(
    'unexpected worker failures preserve remote message and stack',
    () async {
      final worker = ScheduleWorker([_ThrowingMediaItem()], const []);
      addTearDown(worker.dispose);

      await expectLater(
        worker.build(_channel),
        throwsA(
          isA<RemoteError>()
              .having(
                (error) => error.toString(),
                'message',
                contains('worker boom'),
              )
              .having(
                (error) => error.stackTrace.toString(),
                'stack trace',
                isNotEmpty,
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

class _ThrowingMediaItem extends PlexMediaItem {
  _ThrowingMediaItem()
    : super(
        id: 'throwing',
        title: 'Throwing',
        type: 'movie',
        duration: const Duration(minutes: 30),
      );

  @override
  String get libraryId => throw StateError('worker boom');
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

void _idleWorker(List<Object?> bootstrap) {
  final requests = ReceivePort();
  requests.listen((_) {});
}

void _heldHandshakeWorker(List<Object?> bootstrap) {
  final output = bootstrap[0] as SendPort;
  final control = bootstrap[1] as SendPort;
  final requests = ReceivePort();
  final gate = ReceivePort();
  control.send(gate.sendPort);
  gate.listen((_) {
    output.send(requests.sendPort);
  });
  requests.listen((_) {});
}

void _correlatedMalformedWorker(SendPort output) {
  final requests = ReceivePort();
  output.send(requests.sendPort);
  requests.listen((message) {
    final request = message as dynamic;
    output.send([request.id, 'malformed']);
  });
}

void _uncorrelatableWorker(SendPort output) {
  final requests = ReceivePort();
  output.send(requests.sendPort);
  requests.listen((_) => output.send('malformed'));
}

void _idleResponseWorker(SendPort _) {
  final requests = ReceivePort();
  requests.listen((_) {});
}

Object _scheduledIdentity(ScheduledProgram program) => (
  program.item.id,
  program.start,
  program.end,
  program.elapsed,
  program.index,
  program.loop,
);
