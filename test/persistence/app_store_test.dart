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
      number: 7,
      name: 'Comedy',
      source: const LibrarySource(
        libraryId: '1',
        libraryType: PlexLibraryType.movie,
      ),
      playbackMode: PlaybackMode.shuffle,
      anchor: DateTime.utc(2026),
      shuffleSeed: 4,
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
    expect(restored.settings.reduceMotion, isTrue);
    expect(restored.selectedServerByProfile, {'profile': 'server'});
    expect(restored.selectedLibraryIdsByProfileServer['profile']?['server'], [
      '1',
    ]);
    expect(
      restored.channelsByProfileServer['profile']?['server']?.single.id,
      'stable-id',
    );
    expect(
      restored.currentChannelByProfileServer['profile']?['server'],
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

  test(
    'corrupt state fails closed and preserves a recovery artifact',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lineup-store-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      await directory.create(recursive: true);
      await File('${directory.path}/state.json').writeAsString('{broken');
      final restored = await FileAppStore(directory).load();
      expect(restored.channelsByProfileServer, isEmpty);
      expect(
        await directory
            .list()
            .where((entry) => entry.path.contains('state.json.corrupt-'))
            .length,
        1,
      );
      expect(await File('${directory.path}/state.json').exists(), isFalse);
    },
  );
}
