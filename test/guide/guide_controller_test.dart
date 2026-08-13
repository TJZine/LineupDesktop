import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/channel_builder.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

void main() {
  test(
    'Channel Builder result becomes the authoritative 1000-channel lineup',
    () async {
      final original = _channels(10);
      final lineup = _TestLineup(original)..currentChannelId = original[5].id;
      final replacement = _channels(1000);

      await lineup.applyChannelPlan(
        replacement,
        mode: ChannelBuildMode.replace,
      );

      expect(lineup.channels, hasLength(1000));
      expect(lineup.currentChannelId, original[5].id);

      await lineup.applyChannelPlan(
        _channels(3, idPrefix: 'small'),
        mode: ChannelBuildMode.replace,
      );
      expect(lineup.channels, hasLength(3));
      expect(lineup.currentChannelId, 'small-2');
      lineup.dispose();
    },
  );

  test('cardinality does not determine loaded or retained row count', () async {
    for (final count in [0, 1, 10, 200, 500, 1000]) {
      final lineup = _TestLineup(_channels(count));
      var loads = 0;
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async {
          loads++;
          return _schedule(channel);
        },
        clock: () => DateTime(2026, 8, 13, 12),
      );

      guide.requestViewport((count - 5).clamp(0, count), 5);
      await _settle();

      expect(loads, lessThanOrEqualTo(14), reason: '$count channels');
      expect(guide.cachedRowCount, lessThanOrEqualTo(14));
      expect(guide.channels, hasLength(count));
      guide.dispose();
      lineup.dispose();
    }
  });

  test(
    'stable identity survives reorder and falls back near deletion',
    () async {
      final lineup = _TestLineup(_channels(10, nonContiguous: true));
      final guide = GuideController(
        lineup: lineup,
        loadSchedule: (channel) async => _schedule(channel),
        clock: () => DateTime(2026, 8, 13, 12),
      );
      guide.moveVertical(5);
      final selected = guide.selectedChannelId;

      lineup.setChannels(lineup.channels.reversed.toList());
      expect(guide.selectedChannelId, selected);

      final selectedIndex = lineup.channels.indexWhere(
        (channel) => channel.id == selected,
      );
      final expectedFallback = lineup.channels[selectedIndex + 1].id;
      lineup.setChannels(
        lineup.channels.where((channel) => channel.id != selected).toList(),
      );
      expect(guide.selectedChannelId, expectedFallback);

      guide.dispose();
      lineup.dispose();
    },
  );

  test('stale schedule result cannot repopulate a replaced lineup', () async {
    final old = _channels(1).single;
    final next = _channels(1, idPrefix: 'new').single;
    final lineup = _TestLineup([old]);
    final oldLoad = Completer<ScheduleIndex>();
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) => channel.id == old.id
          ? oldLoad.future
          : Future.value(_schedule(channel)),
      clock: () => DateTime(2026, 8, 13, 12),
    );
    guide.requestViewport(0, 1);
    lineup.setChannels([next]);
    guide.requestViewport(0, 1);
    oldLoad.complete(_schedule(old));
    await _settle();

    expect(guide.channels.single.id, next.id);
    expect(guide.row(old.id).state, GuideLoadState.loading);
    expect(guide.row(next.id).state, GuideLoadState.ready);

    guide.dispose();
    lineup.dispose();
  });

  test('time navigation reuses the bounded schedule index cache', () async {
    final lineup = _TestLineup(_channels(1));
    var loads = 0;
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async {
        loads++;
        return _schedule(channel);
      },
      clock: () => DateTime(2026, 8, 13, 12),
    );
    guide.requestViewport(0, 1);
    await _settle();
    for (var index = 0; index < 20; index++) {
      guide.moveHorizontal(1);
    }
    guide.requestViewport(0, 1);
    await _settle();

    expect(loads, 1);
    expect(guide.row(lineup.channels.single.id).state, GuideLoadState.ready);

    guide.dispose();
    lineup.dispose();
  });

  test('tuning resolves now after the Guide browses another window', () async {
    final lineup = _TestLineup(_channels(1));
    final now = DateTime(2026, 8, 13, 12);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
      clock: () => now,
    );
    guide.requestViewport(0, 1);
    await _settle();
    for (var index = 0; index < 12; index++) {
      guide.moveHorizontal(1);
    }

    final current = await guide.ensureCurrentProgram(lineup.channels.single.id);

    expect(current, isNotNull);
    expect(current!.isCurrentAt(now), isTrue);
    guide.dispose();
    lineup.dispose();
  });

  test('tuning after disposal returns null without loading', () async {
    final lineup = _TestLineup(_channels(1));
    var loads = 0;
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async {
        loads++;
        return _schedule(channel);
      },
    );
    guide.dispose();

    expect(await guide.ensureCurrentProgram(lineup.channels.single.id), isNull);
    expect(loads, 0);
    lineup.dispose();
  });

  test('artwork work stays bounded during rapid selection', () async {
    final lineup = _ArtworkLineup(_channels(1));
    final guide = GuideController(lineup: lineup);
    final futures = <Future<Uint8List?>>[];
    for (var index = 0; index < 20; index++) {
      final start = DateTime(2026, 8, 13, 12).add(Duration(hours: index));
      futures.add(
        guide.artworkFor(
          GuideProgram(
            channelId: 'channel-0',
            scheduled: ScheduledProgram(
              item: ChannelItem(
                id: 'art-$index',
                title: 'Artwork $index',
                duration: const Duration(hours: 1),
                artwork: Uri.parse('/art/$index'),
              ),
              start: start,
              end: start.add(const Duration(hours: 1)),
              elapsed: Duration.zero,
              index: index,
              loop: 0,
            ),
          ),
        ),
      );
    }
    await _settle();

    expect(lineup.artworkLoads, GuideController.maximumConcurrentArtworkLoads);
    final evictedQueuedLoads =
        futures.length -
        GuideController.maximumCachedArtworkEntries -
        GuideController.maximumConcurrentArtworkLoads;
    expect(
      await Future.wait(
        futures
            .skip(GuideController.maximumConcurrentArtworkLoads)
            .take(evictedQueuedLoads),
      ),
      everyElement(isNull),
    );

    guide.dispose();
    lineup.completeArtwork();
    await _settle();
    expect(lineup.artworkLoads, GuideController.maximumConcurrentArtworkLoads);
    lineup.dispose();
  });

  test('production schedules use the persistent catalog worker', () async {
    final channel = Channel(
      id: 'library-channel',
      number: 1,
      name: 'Library',
      source: const LibrarySource(
        libraryId: 'library',
        libraryType: PlexLibraryType.movie,
      ),
      playbackMode: PlaybackMode.sequential,
      anchor: DateTime(2026, 8, 13),
      shuffleSeed: 1,
    );
    final lineup = _TestLineup([channel])
      ..availableMedia = List.unmodifiable(
        List.generate(
          2000,
          (index) => PlexMediaItem(
            id: 'item-$index',
            key: '/library/metadata/$index',
            title: 'Item $index',
            type: 'movie',
            duration: const Duration(minutes: 30),
            libraryId: 'library',
          ),
        ),
      );

    final first = await lineup.loadScheduleFor(channel);
    final second = await lineup.loadScheduleFor(channel);

    expect(first.items, hasLength(2000));
    expect(second.items, hasLength(2000));
    lineup.dispose();
  });

  test('disposing Guide prevents queued schedule work from starting', () async {
    final lineup = _TestLineup(_channels(10));
    final loads = <Completer<ScheduleIndex>>[];
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) {
        final completer = Completer<ScheduleIndex>();
        loads.add(completer);
        return completer.future;
      },
    );
    guide.requestViewport(0, 5);
    expect(loads, hasLength(4));

    guide.dispose();
    for (var index = 0; index < 4; index++) {
      loads[index].complete(_schedule(lineup.channels[index]));
    }
    await _settle();

    expect(loads, hasLength(4));
    lineup.dispose();
  });

  test('clock transitions and Guide settings preserve logical focus', () async {
    var now = DateTime(2026, 8, 13, 12, 10);
    final channel = Channel(
      id: 'stable',
      number: 42,
      name: 'Clock',
      source: const ManualSource([
        ChannelItem(
          id: 'first',
          title: 'First',
          duration: Duration(minutes: 30),
        ),
        ChannelItem(
          id: 'second',
          title: 'Second',
          duration: Duration(minutes: 30),
        ),
      ]),
      playbackMode: PlaybackMode.sequential,
      anchor: DateTime(2026, 8, 13, 12),
      shuffleSeed: 1,
    );
    final lineup = _TestLineup([channel]);
    final guide = GuideController(
      lineup: lineup,
      loadSchedule: (channel) async => _schedule(channel),
      clock: () => now,
    );
    guide.requestViewport(0, 1);
    await _settle();
    expect(guide.currentProgram('stable')?.scheduled.item.id, 'first');

    now = DateTime(2026, 8, 13, 12, 40);
    expect(guide.currentProgram('stable')?.scheduled.item.id, 'second');
    lineup.setSettings(
      const LineupSettings(guideHours: 8, guideDensity: GuideDensity.compact),
    );

    expect(guide.selectedChannelId, 'stable');
    expect(guide.guideHours, 8);
    expect(guide.density, GuideDensity.compact);

    guide.dispose();
    lineup.dispose();
  });

  test(
    'library filters include mixed sources without confusing channel number',
    () {
      final channels = _channels(2, nonContiguous: true);
      final mixed = Channel(
        id: 'mixed',
        number: 900,
        name: 'Mixed custom',
        source: MixedSource(
          sources: [
            channels[0].source,
            const LibrarySource(
              libraryId: 'library-1',
              libraryType: PlexLibraryType.movie,
            ),
          ],
          interleave: true,
        ),
        playbackMode: PlaybackMode.sequential,
        anchor: DateTime.utc(2026),
        shuffleSeed: 1,
      );
      final lineup = _TestLineup([...channels, mixed]);
      final guide = GuideController(lineup: lineup);

      guide.setLibraryFilter('library-1');
      expect(guide.channels.map((channel) => channel.id), contains('mixed'));
      expect(guide.channels.map((channel) => channel.number), contains(900));

      guide.dispose();
      lineup.dispose();
    },
  );
}

List<Channel> _channels(
  int count, {
  bool nonContiguous = false,
  String idPrefix = 'channel',
}) => List.generate(count, (index) {
  final items = List.generate(
    8,
    (program) => ChannelItem(
      id: '$idPrefix-$index-program-$program',
      title: 'Program $program',
      duration: Duration(minutes: 17 + program * 3),
      showTitle: program.isEven ? 'Series $index' : null,
    ),
  );
  return Channel(
    id: '$idPrefix-$index',
    number: nonContiguous ? index * 7 + 3 : index + 1,
    name: index == count - 1 ? 'Custom $index' : 'Channel $index',
    source: index == count - 1
        ? ManualSource(items)
        : LibrarySource(
            libraryId: 'library-${index % 3}',
            libraryType: PlexLibraryType.movie,
          ),
    playbackMode: PlaybackMode.sequential,
    anchor: DateTime(2026, 8, 13),
    shuffleSeed: index,
  );
});

ScheduleIndex _schedule(Channel channel) {
  final items = channel.source is ManualSource
      ? (channel.source as ManualSource).items
      : List.generate(
          8,
          (index) => ChannelItem(
            id: '${channel.id}-$index',
            title: 'Program $index',
            duration: Duration(minutes: 17 + index * 3),
          ),
        );
  return buildSchedule(
    items,
    mode: channel.playbackMode,
    seed: channel.shuffleSeed,
  );
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

class _TestLineup extends LineupController {
  _TestLineup(List<Channel> value)
    : super(
        store: _MemoryStore(),
        credentials: _MemoryCredentials(),
        plex: PlexClient(
          clientIdentifier: 'lineup-desktop-test-abcdefghijklmnopqrst',
        ),
      ) {
    channels = value;
    stage = SetupStage.ready;
    settings = const LineupSettings(guideHours: 4, pastMinutes: 30);
  }

  void setChannels(List<Channel> value) {
    channels = List.unmodifiable(value);
    notifyListeners();
  }

  void setSettings(LineupSettings value) {
    settings = value;
    notifyListeners();
  }
}

class _ArtworkLineup extends _TestLineup {
  _ArtworkLineup(super.value);

  final _artwork = <Completer<Uint8List?>>[];
  int artworkLoads = 0;

  @override
  Future<Uint8List?> artworkFor(ChannelItem item) {
    artworkLoads++;
    final completer = Completer<Uint8List?>();
    _artwork.add(completer);
    return completer.future;
  }

  void completeArtwork() {
    for (final completer in _artwork) {
      if (!completer.isCompleted) completer.complete(Uint8List(0));
    }
  }
}

class _MemoryStore implements AppStore {
  @override
  Future<String> clientIdentifier() async => 'test';
  @override
  Future<PersistedState> load() async => const PersistedState();
  @override
  Future<void> save(PersistedState state) async {}
}

class _MemoryCredentials implements CredentialStore {
  @override
  Future<void> clear() async {}
  @override
  Future<String?> readAccountToken() async => null;
  @override
  Future<String?> readProfileToken(String profileId) async => null;
  @override
  Future<void> writeAccountToken(String token) async {}
  @override
  Future<void> writeProfileToken(String profileId, String token) async {}
}
