import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

void main() {
  test('persists safe state atomically and restores it', () async {
    final directory = await Directory.systemTemp.createTemp(
      'lineup-store-test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = FileAppStore(directory);
    final channel = Channel(
      id: 'stable-id',
      number: 42,
      name: 'Edited generated channel',
      source: const MixedSource(
        interleave: true,
        sources: [
          LibrarySource(
            libraryId: '1',
            libraryType: PlexLibraryType.movie,
            includeWatched: false,
            filters: {'genre': 'Comedy'},
          ),
          PlaylistSource('playlist-1'),
        ],
      ),
      playbackMode: PlaybackMode.block,
      anchor: DateTime.utc(2026, 8, 23, 12),
      shuffleSeed: 8675309,
      blockSize: 7,
      builderKey: 'builder-key',
    );
    await store.save(
      PersistedState(
        settings: const LineupSettings(reduceMotion: true),
        selectedServerByProfile: const {'profile': 'server'},
        selectedLibraryIdsByProfileServer: const {
          'profile': {
            'server': ['1'],
          },
        },
        channelsByProfileServer: {
          'profile': {
            'server': [channel],
          },
        },
        currentChannelByProfileServer: const {
          'profile': {'server': 'stable-id'},
        },
      ),
    );
    final restored = await store.load();
    expect(restored.recoveredCorruptState, isFalse);
    expect(restored.state.settings.reduceMotion, isTrue);
    expect(restored.state.selectedServerByProfile, {'profile': 'server'});
    expect(
      restored.state.selectedLibraryIdsByProfileServer['profile']?['server'],
      ['1'],
    );
    final restoredChannel =
        restored.state.channelsByProfileServer['profile']?['server']?.single;
    expect(restoredChannel?.toJson(), channel.toJson());
    expect(
      restored.state.currentChannelByProfileServer['profile']?['server'],
      'stable-id',
    );
    expect(
      await directory
          .list()
          .where((entry) => entry.path.endsWith('.tmp'))
          .isEmpty,
      isTrue,
    );
  });

  for (final corruptState in <String, String>{
    'malformed JSON': '{broken',
    'schema-invalid JSON': '{"selectedServerByProfile":[]}',
  }.entries) {
    test('${corruptState.key} quarantines once and reports recovery', () async {
      final directory = await Directory.systemTemp.createTemp(
        'lineup-store-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final stateFile = File('${directory.path}/state.json');
      await stateFile.writeAsString(corruptState.value);
      final store = FileAppStore(
        directory,
        clock: () => DateTime.utc(2026, 8, 23),
      );

      final restored = await store.load();

      expect(restored.state.channelsByProfileServer, isEmpty);
      expect(restored.recoveredCorruptState, isTrue);
      expect(
        await directory
            .list()
            .where((entry) => entry.path.contains('state.json.corrupt-'))
            .length,
        1,
      );
      expect(await stateFile.exists(), isFalse);

      final restart = await store.load();
      expect(restart.recoveredCorruptState, isFalse);
      expect(restart.state.toJson(), const PersistedState().toJson());
      expect(
        await directory
            .list()
            .where((entry) => entry.path.contains('state.json.corrupt-'))
            .length,
        1,
      );
    });
  }

  test('missing state is quiet', () async {
    final directory = await Directory.systemTemp.createTemp(
      'lineup-store-test',
    );
    addTearDown(() => directory.delete(recursive: true));

    final restored = await FileAppStore(directory).load();

    expect(restored.recoveredCorruptState, isFalse);
    expect(restored.state.toJson(), const PersistedState().toJson());
    expect(await directory.list().isEmpty, isTrue);
  });

  test(
    'a quarantine collision fails instead of hiding corrupt state',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lineup-store-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final stateFile = File('${directory.path}/state.json');
      await stateFile.writeAsString('{broken');
      final instant = DateTime.utc(2026, 8, 23);
      final quarantinePath =
          '${stateFile.path}.corrupt-${instant.millisecondsSinceEpoch}';
      await Directory(quarantinePath).create();

      await expectLater(
        FileAppStore(directory, clock: () => instant).load(),
        throwsA(isA<FileSystemException>()),
      );

      expect(await stateFile.readAsString(), '{broken');
      expect(await Directory(quarantinePath).exists(), isTrue);
    },
  );

  test(
    'transient directory read failure preserves state without quarantine',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lineup-store-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final stateDirectory = Directory('${directory.path}/state.json');
      await stateDirectory.create();

      await expectLater(
        FileAppStore(directory).load(),
        throwsA(isA<FileSystemException>()),
      );

      expect(await stateDirectory.exists(), isTrue);
      expect(
        await directory
            .list()
            .where((entry) => entry.path.contains('state.json.corrupt-'))
            .isEmpty,
        isTrue,
      );
    },
  );
}
