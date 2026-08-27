import 'dart:convert';
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
      source: MixedSource(
        interleave: true,
        sources: [
          LibrarySource(
            libraryId: '1',
            libraryType: PlexLibraryType.movie,
            includeWatched: false,
            filters: {'genre': 'Comedy'},
          ),
          PlaylistSource('playlist-1'),
          ManualSource([
            ChannelItem(
              id: 'poster-item',
              title: 'Poster item',
              duration: Duration(minutes: 1),
              poster: Uri(path: '/poster'),
              cast: [
                ChannelCastMember(
                  name: 'Safe Actor',
                  role: 'Lead',
                  portrait: Uri.parse('/library/metadata/1/thumb'),
                ),
                ChannelCastMember(
                  name: 'Unsafe Absolute',
                  role: 'Reporter',
                  portrait: Uri.parse(
                    'https://plex.invalid/library/metadata/2/thumb',
                  ),
                ),
                ChannelCastMember(
                  name: 'Unsafe Token',
                  role: 'Dispatcher',
                  portrait: Uri.parse(
                    '/library/metadata/3/thumb?X-Plex-Token=secret',
                  ),
                ),
                ChannelCastMember(
                  name: 'Unsafe Fragment',
                  role: 'Archivist',
                  portrait: Uri.parse('/library/metadata/4/thumb#private'),
                ),
                ChannelCastMember(
                  name: 'Unsafe Transcode',
                  portrait: Uri.parse('/photo/:/transcode?url=private'),
                ),
                ChannelCastMember(
                  name: 'Unsafe File',
                  portrait: Uri.parse('/Users/private/cast.png'),
                ),
              ],
            ),
          ]),
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
    final item =
        ((restoredChannel!.source as MixedSource).sources.last as ManualSource)
            .items
            .single;
    expect(item.poster, Uri(path: '/poster'));
    expect(item.toJson(), containsPair('poster', '/poster'));
    expect(item.toJson(), isNot(contains('artwork')));
    expect(item.cast.first.portrait, Uri.parse('/library/metadata/1/thumb'));
    expect(
      item.cast.skip(1).map((member) => member.portrait),
      everyElement(isNull),
    );
    final fragment = item.cast.singleWhere(
      (member) => member.name == 'Unsafe Fragment',
    );
    expect(fragment.role, 'Archivist');
    expect(fragment.portrait, isNull);
    final savedJson = await File('${directory.path}/state.json').readAsString();
    expect(savedJson, contains('"poster":"/poster"'));
    expect(savedJson, contains('/library/metadata/1/thumb'));
    expect(savedJson, isNot(contains('plex.invalid')));
    expect(savedJson, isNot(contains('X-Plex-Token')));
    expect(savedJson, contains('Unsafe Fragment'));
    expect(savedJson, contains('Archivist'));
    expect(savedJson, isNot(contains('#private')));
    expect(savedJson, isNot(contains('/photo/:/transcode')));
    expect(savedJson, isNot(contains('/Users/private')));
    expect(savedJson, isNot(contains('"artwork"')));
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

  test('unsafe persisted cast portraits cannot be revived', () {
    for (final unsafe in [
      'https://plex.invalid/library/metadata/2/thumb',
      '/library/metadata/3/thumb?X-Plex-Token=secret',
      '/library/metadata/4/thumb#private',
      '/photo/:/transcode?url=private',
      '/Users/private/cast.png',
    ]) {
      final item = ChannelItem.fromJson({
        'id': 'item',
        'title': 'Item',
        'durationMs': 60000,
        'cast': [
          {'name': 'Actor', 'role': 'Lead', 'portrait': unsafe},
        ],
      });

      expect(item.cast.single.name, 'Actor');
      expect(item.cast.single.role, 'Lead');
      expect(item.cast.single.portrait, isNull);
      expect(item.toJson().toString(), isNot(contains(unsafe)));
    }
  });

  group('canonical persisted schema', () {
    test(
      'requires every structural field and permits only a nullable profile',
      () {
        for (final field in [
          'settings',
          'selectedServerByProfile',
          'selectedLibraryIdsByProfileServer',
          'channelsByProfileServer',
          'currentChannelByProfileServer',
        ]) {
          final missing = _canonicalJson()..remove(field);
          final nullValue = _canonicalJson()..[field] = null;
          expect(() => PersistedState.fromJson(missing), throwsFormatException);
          expect(
            () => PersistedState.fromJson(nullValue),
            throwsFormatException,
          );
        }
        expect(
          PersistedState.fromJson(_canonicalJson()..['profileId'] = null)
              .profileId,
          isNull,
        );
        expect(
          () => PersistedState.fromJson(_canonicalJson()..remove('profileId')),
          throwsFormatException,
        );
        expect(
          () => PersistedState.fromJson(_canonicalJson()..['profileId'] = 7),
          throwsFormatException,
        );
        expect(
          () => PersistedState.fromJson(_canonicalJson()..['legacy'] = true),
          throwsFormatException,
        );
      },
    );

    test('rejects non-string outer and inner keys', () {
      expect(
        () => PersistedState.fromJson(
          _canonicalJson()..['selectedServerByProfile'] = {1: 'server'},
        ),
        throwsFormatException,
      );
      expect(
        () => PersistedState.fromJson(
          _canonicalJson()
            ..['channelsByProfileServer'] = {
              'profile': {1: <Object?>[]},
            },
        ),
        throwsFormatException,
      );
    });

    test('rejects wrong nested leaf shapes and mixed library lists', () {
      for (final invalid in [
        _canonicalJson()..['selectedServerByProfile'] = {'profile': 1},
        _canonicalJson()
          ..['selectedLibraryIdsByProfileServer'] = {
            'profile': {'server': 'library'},
          },
        _canonicalJson()
          ..['channelsByProfileServer'] = {
            'profile': {'server': <String, Object?>{}},
          },
        _canonicalJson()
          ..['currentChannelByProfileServer'] = {
            'profile': {'server': <Object?>[]},
          },
        _canonicalJson()
          ..['selectedLibraryIdsByProfileServer'] = {
            'profile': {
              'server': ['library', 2],
            },
          },
      ]) {
        expect(() => PersistedState.fromJson(invalid), throwsFormatException);
      }
    });

    test('rejects malformed channels and invalid selected/current values', () {
      for (final invalid in [
        _canonicalJson()
          ..['channelsByProfileServer'] = {
            'profile': {
              'server': [null],
            },
          },
        _canonicalJson()
          ..['channelsByProfileServer'] = {
            'profile': {
              'server': [_channelJson(artworkValue: 7)],
            },
          },
        _canonicalJson()..['selectedServerByProfile'] = {'profile': false},
        _canonicalJson()
          ..['currentChannelByProfileServer'] = {
            'profile': {'server': 42},
          },
      ]) {
        expect(() => PersistedState.fromJson(invalid), throwsFormatException);
      }
    });

    test('rejects noncanonical settings values', () {
      expect(
        () => PersistedState.fromJson(
          _canonicalJson()
            ..['settings'] = {
              ...const LineupSettings().toJson(),
              'guideHours': 5,
            },
        ),
        throwsFormatException,
      );
    });
  });

  for (final corruptState in <String, String>{
    'malformed JSON': '{broken',
    'schema-invalid JSON': '{"selectedServerByProfile":[]}',
    'malformed nested JSON': _encodedState(
      _canonicalJson()
        ..['selectedLibraryIdsByProfileServer'] = {
          'profile': {
            'server': ['library', 2],
          },
        },
    ),
    'legacy artwork JSON': _encodedState(
      _canonicalJson()
        ..['channelsByProfileServer'] = {
          'profile': {
            'server': [_channelJson(artworkKey: 'artwork')],
          },
        },
    ),
    'malformed current artwork JSON': _encodedState(
      _canonicalJson()
        ..['channelsByProfileServer'] = {
          'profile': {
            'server': [
              _channelJson(artworkKey: 'clearLogo', artworkValue: 'http://['),
            ],
          },
        },
    ),
    'noncanonical settings JSON': _encodedState(
      _canonicalJson()
        ..['settings'] = {
          ...const LineupSettings().toJson(),
          'guideHours': 2.5,
        },
    ),
    'noncanonical channel JSON': _encodedState(
      _canonicalJson()
        ..['channelsByProfileServer'] = {
          'profile': {
            'server': [_channelJson()..['future'] = true],
          },
        },
    ),
    'noncanonical source JSON': _encodedState(
      _canonicalJson()
        ..['channelsByProfileServer'] = {
          'profile': {
            'server': [
              _channelJson()
                ..['source'] = {
                  'type': 'playlist',
                  'playlistId': 'playlist',
                  'future': true,
                },
            ],
          },
        },
    ),
    'noncanonical item JSON': _encodedState(
      _canonicalJson()
        ..['channelsByProfileServer'] = {
          'profile': {
            'server': [_channelJson(artworkKey: 'future')],
          },
        },
    ),
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

Map<String, Object?> _canonicalJson() => {
  ...const PersistedState().toJson(),
  'profileId': 'profile',
};

Map<String, Object?> _channelJson({
  String artworkKey = 'poster',
  Object? artworkValue = '/poster',
}) => {
  'id': 'channel',
  'number': 1,
  'name': 'Channel',
  'source': {
    'type': 'manual',
    'items': [
      {
        'id': 'item',
        'title': 'Item',
        'durationMs': 60000,
        artworkKey: artworkValue,
      },
    ],
  },
  'playbackMode': 'sequential',
  'anchor': '2026-08-23T00:00:00.000Z',
  'shuffleSeed': 1,
};

String _encodedState(Map<String, Object?> state) => jsonEncode(state);
