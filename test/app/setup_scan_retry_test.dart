import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lineup_desktop/app/channel_setup_view.dart';
import 'package:lineup_desktop/app/channel_setup/library_step.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/app/lineup_shell.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/playback/native_player_factory.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';

import '../support/test_doubles.dart';

void main() {
  testWidgets(
    'failed reentry rescan retries real library reads before advancing',
    (tester) async {
      final fixture = await _ScanFixture.restored();
      addTearDown(fixture.controller.dispose);
      final previous = fixture.store.state;
      await _showSetup(tester, fixture);
      fixture.failedLibraries.addAll(_libraries);
      await tester.tap(find.byKey(const ValueKey('scan-again-libraries')));
      await tester.pumpAndSettle();

      expect(fixture.controller.libraryScanReadyIds, _libraries);
      expect(fixture.store.state, same(previous));
      expect(
        fixture.controller.isGeneratedSourceConfirmedGone(_missing),
        isFalse,
      );
      fixture.itemReads.clear();
      await tester.tap(find.byKey(const ValueKey('retry-failed-libraries')));
      await tester.pumpAndSettle();

      expect(fixture.itemReads.toSet(), _libraries);
      expect(find.byType(UpstreamChannelSetupView), findsOneWidget);
      expect(find.text('Shape your lineup'), findsNothing);
      expect(fixture.controller.error, isNotNull);
      expect(fixture.controller.libraryScanReadyIds, _libraries);
      expect(fixture.controller.libraryScanRetryIds, _libraries);
      expect(
        fixture.controller.isGeneratedSourceConfirmedGone(_missing),
        isFalse,
      );
      expect(fixture.store.state, same(previous));

      fixture.failedLibraries.clear();
      fixture.revision = 'recovered';
      fixture.itemReads.clear();
      await tester.tap(find.byKey(const ValueKey('retry-failed-libraries')));
      await tester.pumpAndSettle();

      expect(fixture.itemReads.toSet(), _libraries);
      expect(find.text('Shape your lineup'), findsOneWidget);
      expect(fixture.controller.error, isNull);
      expect(fixture.controller.libraryScanRetryIds, isEmpty);
      expect(
        fixture.controller.availableMedia.every(
          (item) => item.id.contains('recovered'),
        ),
        isTrue,
      );
      expect(fixture.store.savedStates.length, greaterThan(1));
      expect(
        fixture.controller.isGeneratedSourceConfirmedGone(_missing),
        isTrue,
      );
    },
  );

  test(
    'mixed rescan keeps fresh successes and retries only failed reads',
    () async {
      final fixture = await _ScanFixture.restored();
      addTearDown(fixture.controller.dispose);
      final previous = fixture.store.state;
      fixture.revision = 'fresh';
      fixture.failedLibraries.add('second');
      await fixture.controller.scanLibraries(_libraries);
      expect(fixture.controller.libraryScanReadyIds, _libraries);
      expect(fixture.store.state, same(previous));
      expect(
        fixture.controller.availableMedia.every(
          (item) => item.id.contains('original'),
        ),
        isTrue,
      );

      fixture.itemReads.clear();
      fixture.failedLibraries.clear();
      fixture.revision = 'recovered';
      await fixture.controller.scanLibraries(_libraries, retryFailedOnly: true);
      expect(fixture.itemReads, ['second']);
      expect(await fixture.controller.commitLibraryScan(_libraries), isTrue);
      expect(fixture.controller.availableMedia.map((item) => item.id), [
        for (var index = 0; index < 5; index++) 'first-fresh-$index',
        for (var index = 0; index < 5; index++) 'second-recovered-$index',
      ]);
      expect(fixture.controller.libraryScanRetryIds, isEmpty);
    },
  );

  testWidgets(
    'recovering one row does not auto-advance with another retained failure',
    (tester) async {
      final fixture = await _ScanFixture.restored();
      addTearDown(fixture.controller.dispose);
      await _showSetup(tester, fixture);
      fixture.failedLibraries.addAll(_libraries);
      await tester.tap(find.byKey(const ValueKey('scan-again-libraries')));
      await tester.pumpAndSettle();
      fixture.failedLibraries.remove('first');
      fixture.itemReads.clear();
      // Exercise the row-scan command even though retained ready rows do not
      // render a per-row Retry button. The footer is exercised above.
      final step = tester.widget<SetupLibraryStep>(
        find.byType(SetupLibraryStep),
      );
      unawaited(step.onScan(retryLibraryIds: {'first'}));
      await tester.pumpAndSettle();
      expect(fixture.itemReads, ['first']);
      expect(fixture.controller.error, isNull);
      expect(fixture.controller.libraryScanRetryIds, {'second'});
      expect(find.text('Shape your lineup'), findsNothing);
      expect(
        find.byKey(const ValueKey('continue-ready-libraries')),
        findsOneWidget,
      );
      expect(
        fixture.controller.isGeneratedSourceConfirmedGone(_missing),
        isFalse,
      );

      await tester.tap(find.byKey(const ValueKey('continue-ready-libraries')));
      await tester.pumpAndSettle();
      expect(find.text('Shape your lineup'), findsOneWidget);
      expect(
        fixture.controller.isGeneratedSourceConfirmedGone(_missing),
        isFalse,
      );
    },
  );

  test(
    'cancelled refresh retries unfinished work and preserves completed reads',
    () async {
      final fixture = await _ScanFixture.restored();
      addTearDown(fixture.controller.dispose);
      final started = Completer<void>();
      final release = Completer<void>();
      final firstFinished = Completer<void>();
      var firstStarted = false;
      fixture.controller.addListener(() {
        final status = fixture.controller.libraryScanFacts['first']?.status;
        if (status == LibraryScanStatus.scanning) firstStarted = true;
        if (firstStarted &&
            !firstFinished.isCompleted &&
            status == LibraryScanStatus.complete) {
          firstFinished.complete();
        }
      });
      fixture.revision = 'fresh';
      fixture.beforeRead = (id) async {
        if (id == 'second') {
          started.complete();
          await release.future;
        }
      };
      final refreshing = fixture.controller.scanLibraries(_libraries);
      await started.future;
      await firstFinished.future.timeout(const Duration(seconds: 2));
      fixture.controller.cancelLibraryScan();
      release.complete();
      expect(await refreshing, isFalse);
      expect(fixture.controller.libraryScanReadyIds, _libraries);
      expect(
        fixture.controller.isGeneratedSourceConfirmedGone(_missing),
        isFalse,
      );

      fixture.beforeRead = null;
      fixture.itemReads.clear();
      fixture.revision = 'recovered';
      await fixture.controller.scanLibraries(_libraries, retryFailedOnly: true);
      expect(fixture.itemReads, ['second']);
      expect(await fixture.controller.commitLibraryScan(_libraries), isTrue);
      expect(fixture.controller.availableMedia.first.id, 'first-fresh-0');
      expect(fixture.controller.availableMedia.last.id, 'second-recovered-4');
    },
  );

  test(
    'catalog failure retries only catalog after fresh library reads',
    () async {
      final fixture = await _ScanFixture.restored(requiredPlaylist: true);
      addTearDown(fixture.controller.dispose);
      fixture.revision = 'fresh';
      fixture.catalogUnavailable = true;
      await fixture.controller.scanLibraries(_libraries);
      expect(fixture.controller.error, isNotNull);
      expect(fixture.controller.libraryScanReadyIds, _libraries);
      expect(
        fixture.controller.isGeneratedSourceConfirmedGone(_missing),
        isFalse,
      );

      fixture.itemReads.clear();
      final catalogReads = fixture.catalogReads;
      fixture.catalogUnavailable = false;
      await fixture.controller.scanLibraries(_libraries, retryFailedOnly: true);
      expect(fixture.itemReads, isEmpty);
      expect(fixture.catalogReads, catalogReads + 1);
      expect(await fixture.controller.commitLibraryScan(_libraries), isTrue);
      expect(
        fixture.controller.availableMedia.every(
          (item) => item.id.contains('fresh'),
        ),
        isTrue,
      );
      expect(
        fixture.controller.isGeneratedSourceConfirmedGone(_missing),
        isTrue,
      );
    },
  );

  for (final changeSelection in [true, false]) {
    test(
      'retained retry inventory is retired by ${changeSelection ? 'a different selection' : 'a new server lifetime'}',
      () async {
        final fixture = await _ScanFixture.restored();
        addTearDown(fixture.controller.dispose);
        fixture.revision = 'discarded';
        fixture.failedLibraries.add('second');
        await fixture.controller.scanLibraries(_libraries);
        fixture.failedLibraries.clear();
        fixture.revision = 'current';
        fixture.itemReads.clear();

        if (changeSelection) {
          await fixture.controller.scanLibraries({
            'first',
          }, retryFailedOnly: true);
          expect(fixture.itemReads, ['first']);
          expect(await fixture.controller.commitLibraryScan({'first'}), isTrue);
        } else {
          await fixture.controller.selectServer(fixture.controller.server!);
          expect(fixture.itemReads.toSet(), _libraries);
        }
        expect(
          fixture.controller.availableMedia.every(
            (item) => item.id.contains('current'),
          ),
          isTrue,
        );
      },
    );
  }
}

const _libraries = {'first', 'second'};
final _missing = Channel(
  id: 'missing',
  number: 2,
  name: 'Missing source',
  builderKey: 'generated',
  source: const LibrarySource(
    libraryId: 'first',
    libraryType: PlexLibraryType.movie,
    filters: {
      LibraryFilter.genre: ['missing'],
    },
  ),
  playbackMode: PlaybackMode.sequential,
  anchor: DateTime.utc(2026),
  shuffleSeed: 1,
);

Future<void> _showSetup(WidgetTester tester, _ScanFixture fixture) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await fixture.controller.enterChannelSetup();
  await tester.pumpWidget(
    MaterialApp(
      theme: LineupTheme.forName(LineupThemeName.emberSteel),
      builder: LineupCanvas.builder,
      home: LineupShell(
        controller: fixture.controller,
        player: createPlatformNativePlayer(isWindows: false, isMacOS: true),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// Only the external service response is controlled. The controller, Plex parser,
// scan state, persistence commands and Setup widgets run their production paths.
class _ScanFixture {
  _ScanFixture({required bool requiredPlaylist}) {
    store = MemoryAppStore(
      initial: PersistedState(
        profileId: 'owner',
        selectedServerByProfile: const {'owner': 'server'},
        selectedLibraryIdsByProfileServer: const {
          'owner': {
            'server': ['first', 'second'],
          },
        },
        channelsByProfileServer: {
          'owner': {
            'server': [
              Channel(
                id: 'saved',
                number: 1,
                name: 'Saved',
                source: requiredPlaylist
                    ? const PlaylistSource('saved')
                    : const LibrarySource(
                        libraryId: 'first',
                        libraryType: PlexLibraryType.movie,
                      ),
                playbackMode: PlaybackMode.sequential,
                anchor: DateTime.utc(2026),
                shuffleSeed: 1,
                scheduleVersion: currentScheduleVersion,
              ),
            ],
          },
        },
      ),
    );
    controller = LineupController(
      store: store,
      credentials: MemoryCredentialStore(accountToken: 'synthetic-account'),
      plex: PlexClient(
        clientIdentifier: 'lineup-scan-regression-abcdefghijklmnop',
        httpClient: MockClient(_respond),
      ),
    );
  }
  static Future<_ScanFixture> restored({bool requiredPlaylist = false}) async {
    final fixture = _ScanFixture(requiredPlaylist: requiredPlaylist);
    await fixture.controller.initialize();
    expect(fixture.controller.stage, SetupStage.ready);
    fixture.itemReads.clear();
    return fixture;
  }

  late final MemoryAppStore store;
  late final LineupController controller;
  final failedLibraries = <String>{};
  final itemReads = <String>[];
  String revision = 'original';
  bool catalogUnavailable = false;
  int catalogReads = 0;
  Future<void> Function(String id)? beforeRead;

  Map<String, Object> _page(List<Object> items) => {
    'MediaContainer': {
      'offset': 0,
      'size': items.length,
      'totalSize': items.length,
      'Metadata': items,
    },
  };
  Map<String, Object> _movie(String id) => {
    'ratingKey': id,
    'title': id,
    'type': 'movie',
    'duration': 1800000,
    'Media': [
      {
        'Part': [
          {'key': '/library/parts/$id'},
        ],
      },
    ],
  };
  Future<http.Response> _respond(http.Request request) async {
    final path = request.url.path;
    Object body;
    if (path == '/users/account.json') {
      body = {
        'user': {'id': 'owner', 'username': 'Owner'},
      };
    } else if (path == '/api/v2/home/users') {
      body = {
        'User': [
          {'id': 'owner', 'title': 'Owner', 'protected': false},
        ],
      };
    } else if (path == '/api/v2/resources') {
      body = [
        {
          'name': 'Server',
          'clientIdentifier': 'server',
          'provides': 'server',
          'accessToken': 'synthetic-pms',
          'connections': [
            {'uri': 'https://fixture.invalid:32400', 'local': true},
          ],
        },
      ];
    } else if (path == '/identity') {
      body = {
        'MediaContainer': {'machineIdentifier': 'server'},
      };
    } else if (path == '/library/sections') {
      body = {
        'MediaContainer': {
          'size': 2,
          'Directory': [
            for (final id in _libraries)
              {'key': id, 'title': id, 'type': 'movie'},
          ],
        },
      };
    } else if (path.startsWith('/library/sections/')) {
      final id = request.url.pathSegments[2];
      if (request.url.queryParameters['type'] == '18') {
        body = _page([]);
      } else {
        itemReads.add(id);
        await beforeRead?.call(id);
        if (failedLibraries.contains(id)) return http.Response('{}', 503);
        body = _page([
          for (var index = 0; index < 5; index++)
            _movie('$id-$revision-$index'),
        ]);
      }
    } else if (path == '/playlists/all') {
      catalogReads++;
      if (catalogUnavailable) return http.Response('{}', 503);
      body = _page([
        {
          'ratingKey': 'saved',
          'title': 'Saved playlist',
          'playlistType': 'video',
        },
      ]);
    } else if (path == '/playlists/saved/items') {
      body = _page([_movie('playlist-item')]);
    } else {
      throw StateError('Unexpected fixture request: $path');
    }
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}
