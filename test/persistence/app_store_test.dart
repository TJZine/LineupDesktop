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
    );
    await store.save(
      PersistedState(
        settings: const LineupSettings(reduceMotion: true),
        channels: [channel],
        currentChannelId: channel.id,
        selectedServerByProfile: const {'profile': 'server'},
      ),
    );
    final restored = await store.load();
    expect(restored.settings.reduceMotion, isTrue);
    expect(restored.channels.single.id, 'stable-id');
    expect(restored.selectedServerByProfile, {'profile': 'server'});
    expect(
      await directory
          .list()
          .where((entry) => entry.path.endsWith('.tmp'))
          .isEmpty,
      isTrue,
    );
  });

  test('corrupt state fails closed to defaults', () async {
    final directory = await Directory.systemTemp.createTemp(
      'lineup-store-test',
    );
    addTearDown(() => directory.delete(recursive: true));
    await directory.create(recursive: true);
    await File('${directory.path}/state.json').writeAsString('{broken');
    final restored = await FileAppStore(directory).load();
    expect(restored.channels, isEmpty);
  });
}
