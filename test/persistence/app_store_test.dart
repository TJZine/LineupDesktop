import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

void main() {
  test(
    'pre-source-setting file loads saves and reloads without quarantine',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lineup-guide-sources',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/state.json');
      final old = _canonicalJson();
      // Literal settings from the pre-change schema, independent of new serialization.
      old['settings'] = {
        'theme': 'slate-pine',
        'guideHours': 3,
        'guideInfoBackgroundMode': 'bleed',
        'preferClearLogos': false,
        'dvrControlsEnabled': true,
        'nowWatchingBanner': false,
        'osdAutoHideSeconds': 8,
        'audioSetupComplete': true,
        'reduceMotion': true,
        'largeFocusIndicators': true,
        'profilePickerOnStartup': true,
        'diagnosticsEnabled': true,
      };
      final original = _encodedState(old);
      await file.writeAsString(original);
      final store = FileAppStore(directory);
      final loaded = await store.load();
      expect(loaded.recoveredCorruptState, isFalse);
      expect(loaded.state.settings.guideShowChannelSources, isFalse);
      final expected = Map<String, Object?>.from(old)
        ..['settings'] = {
          ...old['settings'] as Map,
          'guideShowChannelSources': false,
          'overlayTransparency': 'standard',
        };
      expect(loaded.state.toJson(), expected);
      await store.save(loaded.state);
      expect(jsonDecode(await file.readAsString()), expected);
      final reloaded = await FileAppStore(directory).load();
      expect(reloaded.recoveredCorruptState, isFalse);
      expect(reloaded.state.toJson(), expected);
      expect(
        await directory
            .list()
            .where((file) => file.path.contains('.corrupt-'))
            .isEmpty,
        isTrue,
      );
      expect(
        await File('${file.path}.pre-desktop-ui').readAsString(),
        original,
      );
    },
  );

  test(
    'pre-overlay-setting file loads saves and reloads without quarantine',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lineup-guide-sources',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/state.json');
      final old = _canonicalJson();
      // Literal settings from the pre-change schema, independent of new serialization.
      old['settings'] = {
        'theme': 'slate-pine',
        'guideHours': 3,
        'guideShowChannelSources': true,
        'guideInfoBackgroundMode': 'bleed',
        'preferClearLogos': false,
        'dvrControlsEnabled': true,
        'nowWatchingBanner': false,
        'osdAutoHideSeconds': 8,
        'audioSetupComplete': true,
        'reduceMotion': true,
        'largeFocusIndicators': true,
        'profilePickerOnStartup': true,
        'diagnosticsEnabled': true,
      };
      final original = _encodedState(old);
      await file.writeAsString(original);
      final store = FileAppStore(directory);
      final loaded = await store.load();
      expect(loaded.recoveredCorruptState, isFalse);
      expect(loaded.state.settings.guideShowChannelSources, isTrue);
      expect(
        loaded.state.settings.overlayTransparency,
        OverlayTransparency.standard,
      );
      final expected = Map<String, Object?>.from(old)
        ..['settings'] = {
          ...old['settings'] as Map,
          'overlayTransparency': 'standard',
        };
      expect(loaded.state.toJson(), expected);
      await store.save(loaded.state);
      expect(jsonDecode(await file.readAsString()), expected);
      final reloaded = await FileAppStore(directory).load();
      expect(reloaded.recoveredCorruptState, isFalse);
      expect(reloaded.state.toJson(), expected);
      expect(
        await directory
            .list()
            .where((file) => file.path.contains('.corrupt-'))
            .isEmpty,
        isTrue,
      );
      expect(
        await File('${file.path}.pre-desktop-ui').readAsString(),
        original,
      );
    },
  );

  test(
    'pre-change Glass state loads and saves as Ember without quarantine',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lineup-retired-theme',
      );
      addTearDown(() => directory.delete(recursive: true));
      final stateFile = File('${directory.path}/state.json');
      final oldState = _canonicalJson();
      oldState['settings'] = {
        ...const LineupSettings(
          guideHours: 3,
          reduceMotion: true,
          dvrControlsEnabled: true,
        ).toJson(),
        'theme': 'glass',
      };
      final original = _encodedState(oldState);
      await stateFile.writeAsString(original);
      final store = FileAppStore(directory);
      final loaded = await store.load();
      expect(loaded.recoveredCorruptState, isFalse);
      expect(loaded.state.settings.theme, LineupThemeName.emberSteel);
      expect(loaded.state.settings.guideHours, 3);
      expect(loaded.state.settings.reduceMotion, isTrue);
      expect(loaded.state.settings.dvrControlsEnabled, isTrue);
      expect(loaded.state.profileId, 'profile');
      await store.save(loaded.state);
      final written = jsonDecode(await stateFile.readAsString()) as Map;
      expect((written['settings'] as Map)['theme'], 'ember-steel');
      expect((written['settings'] as Map)['guideHours'], 3);
      expect(
        (await FileAppStore(directory).load()).state.toJson(),
        loaded.state.toJson(),
      );
      expect(
        await directory
            .list()
            .where((file) => file.path.contains('.corrupt-'))
            .isEmpty,
        isTrue,
      );
      expect(
        await File('${stateFile.path}.pre-desktop-ui').readAsString(),
        original,
      );
    },
  );

  test(
    'first overwrite preserves exact bytes across queued saves and restart',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lineup-backup-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final stateFile = File('${directory.path}/state.json');
      final original = utf8.encode('  ${_encodedState(_canonicalJson())}\n\n');
      await stateFile.writeAsBytes(original);
      final store = FileAppStore(directory);
      await store.load();
      await Future.wait([
        store.save(const PersistedState(profileId: 'first')),
        store.save(const PersistedState(profileId: 'second')),
      ]);
      final backup = File('${stateFile.path}.pre-desktop-ui');
      expect(await backup.readAsBytes(), original);
      final restarted = FileAppStore(directory);
      expect((await restarted.load()).state.profileId, 'second');
      await restarted.save(const PersistedState(profileId: 'third'));
      expect(await backup.readAsBytes(), original);
      expect((await restarted.load()).state.profileId, 'third');
    },
  );

  test(
    'backup failure blocks overwrite and the write queue remains usable',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lineup-backup-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final stateFile = File('${directory.path}/state.json');
      final original = _encodedState(_canonicalJson());
      await stateFile.writeAsString(original);
      final obstruction = Directory('${stateFile.path}.pre-desktop-ui');
      await obstruction.create();
      final store = FileAppStore(directory);
      await expectLater(
        store.save(const PersistedState(profileId: 'replacement')),
        throwsA(isA<FileSystemException>()),
      );
      expect(await stateFile.readAsString(), original);
      expect(
        await directory.list().where((f) => f.path.endsWith('.tmp')).isEmpty,
        isTrue,
      );
      await obstruction.delete();
      await store.save(const PersistedState(profileId: 'replacement'));
      expect(await File(obstruction.path).readAsString(), original);
      expect((await store.load()).state.profileId, 'replacement');
    },
  );

  test(
    'load backs up before artwork migration and never quarantines IO failure',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lineup-backup-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final stateFile = File('${directory.path}/state.json');
      final original = _encodedState(
        _canonicalJson()
          ..['channelsByProfileServer'] = {
            'profile': {
              'server': [
                _channelJson(
                  artworkValue: '/library/metadata/1/thumb?secret=x',
                ),
              ],
            },
          },
      );
      await stateFile.writeAsString(original);
      final obstruction = Directory('${stateFile.path}.pre-desktop-ui');
      await obstruction.create();
      await expectLater(
        FileAppStore(directory).load(),
        throwsA(isA<FileSystemException>()),
      );
      expect(await stateFile.readAsString(), original);
      expect(
        await directory
            .list()
            .where((f) => f.path.contains('.corrupt-'))
            .isEmpty,
        isTrue,
      );
      await obstruction.delete();
      expect(
        (await FileAppStore(directory).load()).recoveredCorruptState,
        isFalse,
      );
      expect(await File(obstruction.path).readAsString(), original);
      expect(await stateFile.readAsString(), isNot(contains('?secret=x')));
    },
  );

  test(
    'a rewrite FormatException is not mistaken for invalid saved data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lineup-backup-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final stateFile = File('${directory.path}/state.json');
      final original = _encodedState(
        _canonicalJson()
          ..['channelsByProfileServer'] = {
            'profile': {
              'server': [
                _channelJson(
                  artworkValue: '/library/metadata/1/thumb?secret=x',
                ),
              ],
            },
          },
      );
      await stateFile.writeAsString(original);
      await expectLater(
        _InvalidRewriteStore(directory).load(),
        throwsA(isA<FormatException>()),
      );
      expect(await stateFile.readAsString(), original);
      expect(
        await directory
            .list()
            .where((f) => f.path.contains('.corrupt-'))
            .isEmpty,
        isTrue,
      );
    },
  );

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
          ContentSource.fromJson({
            'type': 'library',
            'libraryId': '1',
            'libraryType': 'movie',
            'includeWatched': false,
            'filters': {'genre': 'Comedy'},
          }),
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
                    'https://user@plex.invalid/library/metadata/2/thumb',
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
                  portrait: Uri.parse('file:///Users/private/cast.png'),
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
      'https://user@plex.invalid/library/metadata/2/thumb',
      '/library/metadata/3/thumb?X-Plex-Token=secret',
      '/library/metadata/4/thumb#private',
      '/photo/:/transcode?url=private',
      'file:///Users/private/cast.png',
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

  test(
    'new portrait source shapes persist without changing the state schema',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lineup-portrait-state-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final sources = [
        '/library/metadata/1/thumb',
        '/photo/people/2',
        'https://metadata-static.plex.tv/people/3.jpg',
        'https://images.example/4.jpg?size=large',
        'http://images.example/5.jpg',
      ];
      final item = ChannelItem(
        id: 'portrait-item',
        title: 'Synthetic',
        duration: const Duration(minutes: 1),
        cast: [
          for (final source in sources)
            ChannelCastMember(name: 'Actor', portrait: Uri.parse(source)),
        ],
      );
      final json = _canonicalJson()
        ..['channelsByProfileServer'] = {
          'profile': {
            'server': [
              _channelJson()
                ..['source'] = {
                  'type': 'manual',
                  'items': [item.toJson()],
                },
            ],
          },
        };
      final store = FileAppStore(directory);
      await store.save(PersistedState.fromJson(json));
      final loaded = await store.load();
      expect(loaded.recoveredCorruptState, isFalse);
      final restored =
          (loaded
                      .state
                      .channelsByProfileServer['profile']!['server']!
                      .single
                      .source
                  as ManualSource)
              .items
              .single;
      expect(
        restored.cast.map((member) => member.portrait.toString()),
        sources,
      );
      expect(loaded.state.toJson().keys.toSet(), _canonicalJson().keys.toSet());
    },
  );

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

  test(
    'rejects malformed persisted state structure but allows null profile',
    () {
      final invalidStates = <String, Map<String, Object?>>{
        'missing profile': _canonicalJson()..remove('profileId'),
        'mistyped profile': _canonicalJson()..['profileId'] = 7,
        'unknown field': _canonicalJson()..['legacy'] = true,
        'null settings': _canonicalJson()..['settings'] = null,
        'wrong selected server shape': _canonicalJson()
          ..['selectedServerByProfile'] = {'profile': 1},
        'mixed library IDs': _canonicalJson()
          ..['selectedLibraryIdsByProfileServer'] = {
            'profile': {
              'server': ['library', 2],
            },
          },
        'wrong channel list shape': _canonicalJson()
          ..['channelsByProfileServer'] = {
            'profile': {'server': <String, Object?>{}},
          },
      };
      for (final invalid in invalidStates.entries) {
        expect(
          () => PersistedState.fromJson(invalid.value),
          throwsFormatException,
          reason: invalid.key,
        );
      }
      expect(
        PersistedState.fromJson(_canonicalJson()..['profileId'] = null)
            .profileId,
        isNull,
      );
    },
  );

  for (final corruptState in <String, String>{
    'malformed JSON': '{broken',
    'schema-invalid JSON': '{"selectedServerByProfile":[]}',
    'invalid settings JSON': _encodedState(
      _canonicalJson()
        ..['settings'] = {
          ...const LineupSettings().toJson(),
          'theme': 'future-theme',
        },
    ),
    'null manual items JSON': _encodedState(
      _canonicalJson()
        ..['channelsByProfileServer'] = {
          'profile': {
            'server': [
              _channelJson()..['source'] = {'type': 'manual', 'items': null},
            ],
          },
        },
    ),
    'null mixed source items JSON': _encodedState(
      _canonicalJson()
        ..['channelsByProfileServer'] = {
          'profile': {
            'server': [
              _channelJson()
                ..['source'] = {
                  'type': 'mixed',
                  'interleave': false,
                  'sources': [
                    {'type': 'manual', 'items': null},
                  ],
                },
            ],
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
  }.entries) {
    test('${corruptState.key} quarantines once and reports recovery', () async {
      final directory = await Directory.systemTemp.createTemp(
        'lineup-store-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final stateFile = File('${directory.path}/state.json');
      final originalBytes = utf8.encode(corruptState.value);
      await stateFile.writeAsBytes(originalBytes);
      final store = FileAppStore(
        directory,
        clock: () => DateTime.utc(2026, 8, 23),
      );

      final restored = await store.load();

      expect(restored.state.channelsByProfileServer, isEmpty);
      expect(restored.recoveredCorruptState, isTrue);
      expect(await _quarantineContainers(directory), hasLength(1));
      expect(await stateFile.exists(), isFalse);
      final quarantine = (await _quarantineContainers(directory)).single;
      expect(
        await File('${quarantine.path}/state.json').readAsBytes(),
        originalBytes,
      );

      final restart = await store.load();
      expect(restart.recoveredCorruptState, isFalse);
      expect(restart.state.toJson(), const PersistedState().toJson());
      expect(await _quarantineContainers(directory), hasLength(1));
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
      final quarantine = (await _quarantineContainers(directory)).single;
      final quarantinedState = File('${quarantine.path}/state.json');
      expect(await quarantinedState.readAsBytes(), invalidBytes);

      const replacement = PersistedState(
        settings: LineupSettings(reduceMotion: true),
        profileId: 'profile',
      );
      await store.save(replacement);
      final reloaded = await FileAppStore(directory).load();

      expect(reloaded.recoveredCorruptState, isFalse);
      expect(reloaded.state.toJson(), replacement.toJson());
      expect(await quarantinedState.readAsBytes(), invalidBytes);
    },
  );

  test(
    'a pre-existing flat quarantine artifact survives corrupt-state recovery',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lineup-store-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final stateFile = File('${directory.path}/state.json');
      await stateFile.writeAsString('{broken');
      final instant = DateTime.utc(2026, 8, 23);
      final existing = File(
        '${stateFile.path}.corrupt-${instant.millisecondsSinceEpoch}',
      );
      final existingBytes = [0x66, 0x6c, 0x61, 0x74];
      await existing.writeAsBytes(existingBytes);

      final restored = await FileAppStore(
        directory,
        clock: () => instant,
      ).load();

      expect(restored.recoveredCorruptState, isTrue);
      expect(await existing.readAsBytes(), existingBytes);
      expect(await stateFile.exists(), isFalse);
      final containers = await _quarantineContainers(directory);
      expect(containers, hasLength(1));
      expect(
        await File('${containers.single.path}/state.json').readAsString(),
        '{broken',
      );
    },
  );

  test('a pre-existing directory quarantine artifact survives corrupt-state recovery', () async {
    final directory = await Directory.systemTemp.createTemp(
      'lineup-store-test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final stateFile = File(
      '${directory.path}${Platform.pathSeparator}state.json',
    );
    await stateFile.writeAsString('{broken');
    final instant = DateTime.utc(2026, 8, 23);
    final existing = Directory(
      '${stateFile.path}.corrupt-${instant.millisecondsSinceEpoch}',
    );
    await existing.create();
    final marker = File('${existing.path}/marker');
    final markerBytes = [0x64, 0x69, 0x72];
    await marker.writeAsBytes(markerBytes);

    final restored = await FileAppStore(directory, clock: () => instant).load();

    expect(restored.recoveredCorruptState, isTrue);
    expect(await existing.exists(), isTrue);
    expect(await marker.readAsBytes(), markerBytes);
    expect(await stateFile.exists(), isFalse);
    final containers = (await _quarantineContainers(directory))
        .where((container) => container.path != existing.path)
        .toList();
    expect(containers, hasLength(1));
    expect(
      await File('${containers.single.path}/state.json').readAsString(),
      '{broken',
    );
  });

  test(
    'repeated fixed-clock recovery preserves both original byte sequences',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lineup-store-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final stateFile = File('${directory.path}/state.json');
      final instant = DateTime.utc(2026, 8, 23);
      final store = FileAppStore(directory, clock: () => instant);
      final firstBytes = [0x7b, 0x22, 0x66, 0x69, 0x72, 0x73, 0x74, 0x7d];
      final secondBytes = [
        0x7b,
        0x22,
        0x73,
        0x65,
        0x63,
        0x6f,
        0x6e,
        0x64,
        0x7d,
      ];

      await stateFile.writeAsBytes(firstBytes);
      expect((await store.load()).recoveredCorruptState, isTrue);
      await stateFile.writeAsBytes(secondBytes);
      expect((await store.load()).recoveredCorruptState, isTrue);

      final containers = await _quarantineContainers(directory);
      expect(containers, hasLength(2));
      final quarantinedBytes = [
        for (final container in containers)
          await File('${container.path}/state.json').readAsBytes(),
      ];
      expect(
        quarantinedBytes.any((bytes) => _sameBytes(bytes, firstBytes)),
        isTrue,
      );
      expect(
        quarantinedBytes.any((bytes) => _sameBytes(bytes, secondBytes)),
        isTrue,
      );
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
      expect(await _quarantineContainers(directory), isEmpty);
    },
  );
}

Future<List<Directory>> _quarantineContainers(Directory directory) async {
  final prefix =
      '${directory.path}${Platform.pathSeparator}state.json.corrupt-';
  return [
    for (final entry in await directory.list().toList())
      if (entry is Directory && entry.path.startsWith(prefix)) entry,
  ];
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
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

class _InvalidRewriteStore extends FileAppStore {
  _InvalidRewriteStore(super.directory);

  @override
  Future<void> save(PersistedState state) =>
      Future.error(const FormatException('Synthetic canonical write failure'));
}
