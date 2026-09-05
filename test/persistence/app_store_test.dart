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
              showThumb: '/library/metadata/show/thumb',
              poster: Uri(path: '/library/metadata/item/thumb'),
              backdrop: Uri(path: '/library/metadata/item/art'),
              clearLogo: Uri(path: '/library/metadata/show/clearlogo'),
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
    expect(item.showThumb, '/library/metadata/show/thumb');
    expect(item.poster, Uri(path: '/library/metadata/item/thumb'));
    expect(item.backdrop, Uri(path: '/library/metadata/item/art'));
    expect(item.clearLogo, Uri(path: '/library/metadata/show/clearlogo'));
    expect(
      item.toJson(),
      containsPair('poster', '/library/metadata/item/thumb'),
    );
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
    expect(savedJson, contains('"poster":"/library/metadata/item/thumb"'));
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

  test('trusted Plex metadata cast portraits round-trip', () {
    const trusted = 'https://metadata-static.plex.tv/f/people/avery-vale.jpg';
    final item = ChannelItem.fromJson(const {
      'id': 'item',
      'title': 'Item',
      'durationMs': 60000,
      'cast': [
        {'name': 'Actor', 'portrait': trusted},
      ],
    });

    expect(item.cast.single.portrait, Uri.parse(trusted));
    expect(item.toJson()['cast'], [
      {'name': 'Actor', 'portrait': trusted},
    ]);
  });

  test(
    'load atomically removes preexisting unsafe artwork from state',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lineup-store-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      const unsafe = '/library/metadata/1/thumb?X-Plex-Token=secret';
      final stateFile = File('${directory.path}/state.json');
      await stateFile.writeAsString(
        _encodedState(
          _canonicalJson()
            ..['channelsByProfileServer'] = {
              'profile': {
                'server': [
                  _channelJson()
                    ..['source'] = {
                      'type': 'manual',
                      'items': [
                        {
                          'id': 'item',
                          'title': 'Item',
                          'durationMs': 60000,
                          'showThumb': unsafe,
                          'poster': unsafe,
                          'backdrop': unsafe,
                          'clearLogo': unsafe,
                          'cast': [
                            {'name': 'Actor', 'portrait': unsafe},
                          ],
                        },
                      ],
                    },
                ],
              },
            },
        ),
      );
      final store = FileAppStore(directory);

      final restored = await store.load();
      expect(restored.recoveredCorruptState, isFalse);
      final item =
          (restored
                      .state
                      .channelsByProfileServer['profile']!['server']!
                      .single
                      .source
                  as ManualSource)
              .items
              .single;
      expect(item.showThumb, isNull);
      expect(item.poster, isNull);
      expect(item.backdrop, isNull);
      expect(item.clearLogo, isNull);
      expect(item.cast.single.portrait, isNull);

      expect(await stateFile.readAsString(), isNot(contains('X-Plex-Token')));
    },
  );

  test('load does not rewrite a healthy canonical state file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'lineup-store-test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final stateFile = File('${directory.path}/state.json');
    const trusted = 'https://metadata-static.plex.tv/f/people/avery-vale.jpg';
    final contents = _encodedState(
      _stateJsonWithCast(const [
        {'name': 'Actor', 'portrait': trusted},
      ]),
    );
    await stateFile.writeAsString(contents);

    final restored = await FileAppStore(directory).load();

    expect(restored.recoveredCorruptState, isFalse);
    expect(await stateFile.readAsString(), contents);
  });

  test(
    'failed unsafe-artwork migration does not report a successful load',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lineup-store-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      const unsafe = '/library/metadata/1/thumb?X-Plex-Token=secret';
      final stateFile = File('${directory.path}/state.json');
      final contents = _encodedState(
        _canonicalJson()
          ..['channelsByProfileServer'] = {
            'profile': {
              'server': [_channelJson(artworkValue: unsafe)],
            },
          },
      );
      await stateFile.writeAsString(contents);

      await expectLater(
        _FailingMigrationStore(directory).load(),
        throwsA(isA<FileSystemException>()),
      );

      expect(await stateFile.readAsString(), contents);
    },
  );

  test('bounds oversized persisted cast across round trips', () {
    final cast = [
      for (var index = 0; index < maxRichCastMembers + 5; index++)
        {'name': 'Actor $index', 'role': 'Role $index'},
    ];
    final json = _stateJsonWithCast(cast);

    ChannelItem persistedItem(PersistedState state) =>
        (state.channelsByProfileServer['profile']!['server']!.single.source
                as ManualSource)
            .items
            .single;

    final restored = PersistedState.fromJson(json);
    final item = persistedItem(restored);
    expect(item.cast, hasLength(maxRichCastMembers));
    expect(item.cast.map((member) => member.name), [
      for (var index = 0; index < maxRichCastMembers; index++) 'Actor $index',
    ]);

    final roundTripped = persistedItem(
      PersistedState.fromJson(restored.toJson()),
    );
    expect(roundTripped.cast, hasLength(maxRichCastMembers));
    expect(roundTripped.toJson(), item.toJson());

    expect(
      () => PersistedState.fromJson(
        _stateJsonWithCast([
          ...cast,
          {'name': 'Malformed tail', 'future': true},
        ]),
      ),
      throwsFormatException,
    );
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
    'noncanonical oversized cast tail JSON': _encodedState(
      _stateJsonWithCast([
        for (var index = 0; index < maxRichCastMembers + 5; index++)
          {'name': 'Actor $index'},
        {'name': 'Malformed tail', 'future': true},
      ]),
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

  test(
    'invalid UTF-8 preserves bytes in quarantine and allows saving',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lineup-store-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final stateFile = File('${directory.path}/state.json');
      final invalidBytes = [0x7b, 0x22, 0xc3, 0x28, 0x22, 0x7d];
      await stateFile.writeAsBytes(invalidBytes);
      final instant = DateTime.utc(2026, 8, 23);
      final store = FileAppStore(directory, clock: () => instant);

      final restored = await store.load();

      expect(restored.recoveredCorruptState, isTrue);
      expect(restored.state.toJson(), const PersistedState().toJson());
      expect(await stateFile.exists(), isFalse);
      final quarantine = File(
        '${stateFile.path}.corrupt-${instant.millisecondsSinceEpoch}',
      );
      expect(await quarantine.readAsBytes(), invalidBytes);

      const replacement = PersistedState(
        settings: LineupSettings(reduceMotion: true),
        profileId: 'profile',
      );
      await store.save(replacement);
      final reloaded = await FileAppStore(directory).load();

      expect(reloaded.recoveredCorruptState, isFalse);
      expect(reloaded.state.toJson(), replacement.toJson());
      expect(await quarantine.readAsBytes(), invalidBytes);
    },
  );

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

Map<String, Object?> _stateJsonWithCast(List<Object?> cast) => _canonicalJson()
  ..['channelsByProfileServer'] = {
    'profile': {
      'server': [
        _channelJson()
          ..['source'] = {
            'type': 'manual',
            'items': [
              {
                'id': 'item',
                'title': 'Item',
                'durationMs': 60000,
                'cast': cast,
              },
            ],
          },
      ],
    },
  };

Map<String, Object?> _channelJson({
  String artworkKey = 'poster',
  Object? artworkValue = '/library/metadata/item/thumb',
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

class _FailingMigrationStore extends FileAppStore {
  _FailingMigrationStore(super.directory);

  @override
  Future<void> save(PersistedState state) => Future.error(
    const FileSystemException('Synthetic migration rewrite failure'),
  );
}
