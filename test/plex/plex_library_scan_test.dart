import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

final _server = Uri.parse('https://synthetic.invalid');
http.Response _page(List<Object?> rows, {int? total, int offset = 0}) =>
    http.Response(
      jsonEncode({
        'MediaContainer': {
          'Metadata': rows,
          'size': rows.length,
          'offset': offset,
          'totalSize': ?total,
        },
      }),
      200,
    );
Map<String, Object?> _collection(String key, String title, {int? count}) => {
  'ratingKey': key,
  'title': title,
  'childCount': ?count,
};
Map<String, Object?> _member(String id) => {'ratingKey': id};
PlexClient _client(Future<http.Response> Function(http.Request) handler) {
  final client = PlexClient(
    clientIdentifier: 'test',
    httpClient: MockClient(handler),
  );
  addTearDown(client.close);
  return client;
}

Future<PlexCollectionMembership> _membership(
  PlexClient client, {
  bool Function()? isCurrent,
  Future<void>? cancelled,
}) => client.libraryCollectionMembership(
  _server,
  'token',
  'movies',
  isCurrent: isCurrent ?? () => true,
  cancelled: cancelled,
);
Matcher _error(String code) =>
    throwsA(isA<PlexException>().having((e) => e.code, 'code', code));

void main() {
  test('playlist progress spans discovery and bounded content batches, including failed rows', () async {
    final catalogGate = Completer<void>();
    final contentsGate = Completer<void>();
    final firstBatchStarted = Completer<void>();
    final secondBatchStarted = Completer<void>();
    final progress = <PlexPlaylistProgress>[];
    var requests = 0;
    final client = _client((request) async {
      if (request.url.path == '/playlists/all') {
        await catalogGate.future;
        return _page([
          for (var i = 0; i < 6; i++)
            {'ratingKey': 'p$i', 'title': 'Playlist $i'},
        ], total: 6);
      }
      requests++;
      if (requests == 4) firstBatchStarted.complete();
      if (requests <= 4) await contentsGate.future;
      if (requests > 4 && !secondBatchStarted.isCompleted) {
        secondBatchStarted.complete();
      }
      if (request.url.path == '/playlists/p1/items') {
        return http.Response('{}', 503);
      }
      return _page([], total: 0);
    });
    final load = client.playlists(
      _server,
      'token',
      isCurrent: () => true,
      onProgress: progress.add,
    );
    expect(progress.single.totalPlaylists, isNull);
    catalogGate.complete();
    await firstBatchStarted.future;
    expect(progress.last.totalPlaylists, 6);
    expect(progress.last.completedPlaylists, 0);
    expect(requests, 4);
    contentsGate.complete();
    await secondBatchStarted.future;
    final catalog = await load;
    expect(catalog.failedIds, {'p1'});
    expect(progress.map((p) => (p.completedPlaylists, p.totalPlaylists)), [
      (0, null),
      (0, 6),
      (4, 6),
      (6, 6),
    ]);
  });

  for (final payload in <String, Object?>{
    'missing envelope': {},
    'invalid envelope': {'MediaContainer': []},
    'missing inventory': {'MediaContainer': {}},
    'nonempty count without inventory': {
      'MediaContainer': {'size': 1},
    },
    'invalid inventory': {
      'MediaContainer': {'Directory': {}},
    },
    'invalid row': {
      'MediaContainer': {
        'Directory': [null],
      },
    },
    'missing row type': {
      'MediaContainer': {
        'Directory': [{}],
      },
    },
    'contradictory size': {
      'MediaContainer': {'size': 1, 'Directory': []},
    },
  }.entries) {
    test('library endpoint rejects ${payload.key}', () async {
      final client = _client((request) async {
        expect(request.url.path, '/library/sections');
        return http.Response(jsonEncode(payload.value), 200);
      });
      await expectLater(
        client.libraries(_server, 'token'),
        _error('parse-error'),
      );
    });
  }

  for (final container in [
    {'size': 0},
    {'size': '0', 'Directory': <Object?>[]},
    {'Directory': <Object?>[]},
  ]) {
    test(
      'library endpoint accepts explicit empty inventory $container',
      () async {
        final client = _client(
          (_) async =>
              http.Response(jsonEncode({'MediaContainer': container}), 200),
        );
        expect(await client.libraries(_server, 'token'), isEmpty);
      },
    );
  }

  test(
    'library endpoint keeps supported directories in response order',
    () async {
      final client = _client(
        (_) async => http.Response(
          jsonEncode({
            'MediaContainer': {
              'size': 3,
              'Directory': [
                {'key': 'tv', 'title': 'TV', 'type': 'show'},
                {'key': 'music', 'title': 'Music', 'type': 'artist'},
                {'key': 1, 'title': 'Movies', 'type': 'movie'},
              ],
            },
          }),
          200,
        ),
      );
      final libraries = await client.libraries(_server, 'token');
      expect(libraries.map((library) => library.id), ['tv', '1']);
      expect(libraries.map((library) => library.type), [
        PlexLibraryType.show,
        PlexLibraryType.movie,
      ]);
    },
  );

  test('collection listing and children paginate independently and normalize names', () async {
    final calls = <String>[];
    final client = _client((request) async {
      final start = int.parse(
        request.url.queryParameters['X-Plex-Container-Start']!,
      );
      calls.add('${request.url.path}:$start');
      if (request.url.path.contains('/sections/')) {
        return _page(
          [_collection('$start', '  Title $start  ')],
          total: 2,
          offset: start,
        );
      }
      return _page([_member('member-$start')], total: 2, offset: start);
    });
    final result = await _membership(client);
    expect(result.titlesByMember, {
      'member-0': {'Title 0', 'Title 1'},
      'member-1': {'Title 0', 'Title 1'},
    });
    expect(
      calls,
      containsAll([
        '/library/sections/movies/all:0',
        '/library/sections/movies/all:1',
        '/library/collections/0/children:1',
      ]),
    );
  });

  test('regular and smart collections ignore smart shape; only explicit zero is skipped', () async {
    final fetched = <String>[];
    final client = _client((request) async {
      if (request.url.path.contains('/sections/')) {
        return _page([
          {..._collection('regular', 'Regular', count: 1), 'smart': 0},
          {
            ..._collection('smart', 'Smart'),
            'smart': {'opaque': true},
          },
          _collection('empty', 'Empty', count: 0),
        ], total: 3);
      }
      fetched.add(request.url.path);
      return _page([_member('movie')], total: 1);
    });
    expect((await _membership(client)).titlesByMember['movie'], {
      'Regular',
      'Smart',
    });
    expect(fetched.length, 2);
    expect(fetched.any((path) => path.contains('/empty/')), isFalse);
  });

  for (final complete in [true, false]) {
    test(
      'oversized children response ${complete ? "complete" : "incomplete"}',
      () async {
        final client = _client(
          (request) async => request.url.path.contains('/sections/')
              ? _page([_collection('1', 'Title')], total: 1)
              : _page(
                  List.generate(101, (i) => _member('$i')),
                  total: complete ? 101 : 102,
                ),
        );
        final result = await _membership(client);
        expect(result.failedTitles, complete ? isEmpty : {'Title'});
        expect(result.titlesByMember.length, complete ? 101 : 0);
      },
    );
  }

  for (final state in ['recreated', 'gone', 'still-listed']) {
    test('children 404 $state re-lists once', () async {
      var listings = 0;
      final paths = <String>[];
      final client = _client((request) async {
        paths.add(request.url.path);
        if (request.url.path.contains('/sections/')) {
          listings++;
          return _page(
            listings == 1
                ? [_collection('old', 'Title')]
                : state == 'gone'
                ? []
                : [_collection(state == 'recreated' ? 'new' : 'old', 'Title')],
            total: state == 'gone' && listings > 1 ? 0 : 1,
          );
        }
        return request.url.path.contains('/new/')
            ? _page([_member('movie')], total: 1)
            : http.Response('', 404);
      });
      final result = await _membership(client);
      expect(listings, 2);
      expect(
        result.failedTitles,
        state == 'still-listed' ? {'Title'} : isEmpty,
      );
      expect(
        result.titlesByMember,
        state == 'recreated'
            ? {
                'movie': {'Title'},
              }
            : isEmpty,
      );
      if (state == 'recreated') {
        expect(paths.last, '/library/collections/new/children');
      }
    });
  }

  for (final failure in [
    '500',
    'timeout',
    'missing-key',
    'duplicate',
    'bad-offset',
  ]) {
    test(
      'per-collection $failure fails title without publishing a prefix',
      () async {
        final client = PlexClient(
          clientIdentifier: 'test',
          requestTimeout: const Duration(milliseconds: 10),
          httpClient: MockClient((request) async {
            if (request.url.path.contains('/sections/')) {
              return _page([_collection('1', 'Title')], total: 1);
            }
            switch (failure) {
              case '500':
                return http.Response('', 500);
              case 'timeout':
                await Future<void>.delayed(const Duration(milliseconds: 30));
                return _page([], total: 0);
              case 'missing-key':
                return _page([{}], total: 1);
              case 'duplicate':
                return _page([_member('1'), _member('1')], total: 2);
              default:
                return _page([_member('1')], total: 1, offset: 1);
            }
          }),
        );
        addTearDown(client.close);
        final result = await _membership(client);
        expect(result.unavailable, isFalse);
        expect(result.failedTitles, {'Title'});
        expect(result.titlesByMember, isEmpty);
      },
    );
  }

  for (final badPage in [
    {'Metadata': [], 'size': 0, 'totalSize': 1},
    {'Metadata': [], 'size': -1},
    {'Metadata': [], 'size': 1},
    {'Metadata': [], 'offset': 1, 'size': 0},
    {'Metadata': {}, 'size': 0},
    {'Metadata': [], 'size': 0, 'totalSize': 100001},
  ]) {
    test('invalid/over-limit listing is unavailable: $badPage', () async {
      final result = await _membership(
        _client(
          (_) async =>
              http.Response(jsonEncode({'MediaContainer': badPage}), 200),
        ),
      );
      expect(result.unavailable, isTrue);
      expect(result.titlesByMember, isEmpty);
    });
  }
  test('listing transport failure is unavailable', () async {
    expect(
      (await _membership(_client((_) async => http.Response('', 500))))
          .unavailable,
      isTrue,
    );
  });

  for (final status in [401, 403]) {
    test('$status aborts active siblings and propagates', () async {
      var childrenStarted = 0;
      var aborted = 0;
      final allStarted = Completer<void>();
      final client = PlexClient(
        clientIdentifier: 'test',
        httpClient: MockClient.streaming((request, _) async {
          if (request.url.path.contains('/sections/')) {
            final response = _page(
              List.generate(5, (i) => _collection('$i', 'Title $i')),
              total: 5,
            );
            return http.StreamedResponse(Stream.value(response.bodyBytes), 200);
          }
          childrenStarted++;
          if (childrenStarted == 4) allStarted.complete();
          if (request.url.path.contains('/0/')) {
            await allStarted.future;
            return http.StreamedResponse(const Stream.empty(), status);
          }
          await (request as http.AbortableRequest).abortTrigger!;
          aborted++;
          throw http.RequestAbortedException(request.url);
        }),
      );
      addTearDown(client.close);
      await expectLater(
        _membership(client),
        _error(status == 401 ? 'auth-invalid' : 'access-denied'),
      );
      expect(childrenStarted, 4);
      expect(aborted, 3);
    });
  }

  test(
    'sliding workers refill while a slow collection holds a permit',
    () async {
      final slow = Completer<void>();
      final fifth = Completer<void>();
      var active = 0;
      var maximum = 0;
      final client = _client((request) async {
        if (request.url.path.contains('/sections/')) {
          return _page(
            List.generate(6, (i) => _collection('$i', 'Title $i')),
            total: 6,
          );
        }
        active++;
        if (active > maximum) maximum = active;
        if (request.url.path.contains('/0/')) await slow.future;
        if (request.url.path.contains('/4/')) fifth.complete();
        await Future<void>.delayed(Duration.zero);
        active--;
        return _page([_member(request.url.path)], total: 1);
      });
      final pending = _membership(client);
      await fifth.future.timeout(const Duration(seconds: 1));
      expect(maximum, lessThanOrEqualTo(4));
      slow.complete();
      expect((await pending).failedTitles, isEmpty);
    },
  );

  test('concurrent libraries share the eight-collection limit', () async {
    var active = 0;
    var maximum = 0;
    final client = _client((request) async {
      if (request.url.path.contains('/sections/')) {
        return _page(
          List.generate(10, (i) => _collection('$i', 'Title $i')),
          total: 10,
        );
      }
      active++;
      if (active > maximum) maximum = active;
      await Future<void>.delayed(const Duration(milliseconds: 2));
      active--;
      return _page([_member('movie')], total: 1);
    });
    await Future.wait(
      List.generate(
        4,
        (i) => client.libraryCollectionMembership(
          _server,
          'token',
          '$i',
          isCurrent: () => true,
        ),
      ),
    );
    expect(maximum, 8);
  });

  test(
    'member scale overflow makes the library membership unavailable',
    () async {
      final client = _client(
        (request) async => request.url.path.contains('/sections/')
            ? _page([_collection('1', 'Title')], total: 1)
            : _page([
                _member('1'),
              ], total: PlexClient.maximumLibraryCollectionMembers + 1),
      );
      expect((await _membership(client)).unavailable, isTrue);
    },
  );

  for (final cancellation in ['currentness', 'future']) {
    test('$cancellation stops IO between listing and children', () async {
      var current = true;
      var requests = 0;
      final cancel = Completer<void>();
      final client = _client((_) async {
        requests++;
        if (cancellation == 'currentness') {
          current = false;
        } else {
          cancel.complete();
        }
        return _page([_collection('1', 'Title')], total: 1);
      });
      await expectLater(
        _membership(client, isCurrent: () => current, cancelled: cancel.future),
        _error('cancelled'),
      );
      expect(requests, 1);
    });
  }

  test(
    'caller cancellation aborts in-flight children and releases shared permits',
    () async {
      final started = Completer<void>();
      final cancel = Completer<void>();
      var blocking = true;
      var active = 0;
      var aborted = 0;
      final client = PlexClient(
        clientIdentifier: 'test',
        httpClient: MockClient.streaming((request, _) async {
          if (request.url.path.contains('/sections/')) {
            final response = _page(
              List.generate(4, (i) => _collection('$i', 'Title $i')),
              total: 4,
            );
            return http.StreamedResponse(Stream.value(response.bodyBytes), 200);
          }
          if (blocking) {
            if (++active == 4) started.complete();
            await (request as http.AbortableRequest).abortTrigger!;
            aborted++;
            throw http.RequestAbortedException(request.url);
          }
          final response = _page([_member('movie')], total: 1);
          return http.StreamedResponse(Stream.value(response.bodyBytes), 200);
        }),
      );
      addTearDown(client.close);
      final pending = _membership(client, cancelled: cancel.future);
      final failure = expectLater(pending, _error('cancelled'));
      await started.future;
      cancel.complete();
      await failure;
      expect(aborted, 4);
      blocking = false;
      expect((await _membership(client)).titlesByMember['movie']!.length, 4);
    },
  );

  test('aggregate member entries across collections are bounded', () async {
    final client = _client(
      (request) async => request.url.path.contains('/sections/')
          ? _page([_collection('1', 'One'), _collection('2', 'Two')], total: 2)
          : _page(List.generate(50001, (i) => _member('$i')), total: 50001),
    );
    final result = await _membership(client);
    expect(result.unavailable, isTrue);
    expect(result.titlesByMember, isEmpty);
  });

  for (final invalid in ['changed-total', 'duplicate-page', 'oversized']) {
    test('listing $invalid is unavailable', () async {
      final client = _client((request) async {
        final start = int.parse(
          request.url.queryParameters['X-Plex-Container-Start']!,
        );
        if (invalid == 'oversized') {
          return _page(
            List.generate(101, (i) => _collection('$i', 'Title')),
            total: 101,
          );
        }
        return _page(
          [
            _collection(
              invalid == 'duplicate-page' ? 'same' : '$start',
              'Title',
            ),
          ],
          total: invalid == 'changed-total' && start > 0 ? 3 : 2,
          offset: start,
        );
      });
      expect((await _membership(client)).unavailable, isTrue);
    });
  }

  test('unknown-total listing stops at the thousand-page guard', () async {
    var requests = 0;
    final client = _client((request) async {
      requests++;
      final start = int.parse(
        request.url.queryParameters['X-Plex-Container-Start']!,
      );
      return _page([_collection('$start', 'Title')], offset: start);
    });
    expect((await _membership(client)).unavailable, isTrue);
    expect(requests, 1000);
  });

  test(
    'failed duplicate title suppresses members from all matching collections',
    () async {
      final client = _client((request) async {
        if (request.url.path.contains('/sections/')) {
          return _page([
            _collection('good', 'Title'),
            _collection('bad', 'Title'),
          ], total: 2);
        }
        return request.url.path.contains('/bad/')
            ? http.Response('', 500)
            : _page([_member('movie')], total: 1);
      });
      final result = await _membership(client);
      expect(result.failedTitles, {'Title'});
      expect(result.titlesByMember, isEmpty);
    },
  );

  test('show genres page with strict offsets and normalized tags', () async {
    final client = _client((request) async {
      expect(request.url.queryParameters['type'], '2');
      final start = int.parse(
        request.url.queryParameters['X-Plex-Container-Start']!,
      );
      return _page(
        [
          {
            'ratingKey': 'show-$start',
            'Genre': [
              {'tag': ' Drama '},
            ],
          },
        ],
        total: 2,
        offset: start,
      );
    });
    expect(
      await client.libraryShowGenres(
        _server,
        'token',
        'tv',
        isCurrent: () => true,
      ),
      {
        'show-0': ['Drama'],
        'show-1': ['Drama'],
      },
    );
  });

  test('scan annotates movie/show/season/episode membership, drops tags, and inherits show genres', () async {
    final phases = <PlexLibraryScanPhase>[];
    final progress = <PlexLibraryPageProgress>[];
    final client = _client((request) async {
      if (request.url.path.contains('/collections/')) {
        final key = request.url.path.split('/')[3];
        return _page([
          _member(switch (key) {
            'movie' => 'movie',
            'show' => 'show',
            _ => 'season',
          }),
        ], total: 1);
      }
      switch (request.url.queryParameters['type']) {
        case '18':
          return _page([
            _collection('movie', '  Shared  '),
            _collection('show', 'Shared'),
            _collection('season', 'Season'),
          ], total: 3);
        case '2':
          return _page([
            {
              'ratingKey': 'show',
              'Genre': [
                {'tag': ' Drama '},
                {'tag': 'Comedy'},
              ],
            },
          ], total: 1);
        default:
          return _page([
            for (final type in [
              'movie',
              'show',
              'season',
              'episode',
              'non-member',
            ])
              {
                'ratingKey': type,
                'title': type,
                'type': type == 'non-member' ? 'movie' : type,
                'Collection': [
                  {'tag': 'Stale'},
                ],
                if (type == 'episode') ...{
                  'parentRatingKey': 'season',
                  'grandparentRatingKey': 'show',
                  'Genre': [
                    {'tag': 'Drama'},
                  ],
                },
                if (type == 'season') 'parentRatingKey': 'show',
              },
          ], total: 5);
      }
    });
    final scanned = await client.scanLibrary(
      _server,
      'token',
      'tv',
      PlexLibraryType.show,
      isCurrent: () => true,
      onProgress: progress.add,
      onPhase: phases.add,
    );
    expect(phases, PlexLibraryScanPhase.values);
    expect(scanned.items.map((i) => i.collections).toList(), [
      ['Shared'],
      ['Shared'],
      ['Season', 'Shared'],
      ['Season', 'Shared'],
      [],
    ]);
    expect(scanned.items[3].genres, ['Drama', 'Comedy']);
    expect(progress.single.completedItems, 5);
    expect(scanned.items[3].parentRatingKey, 'season');
    final timing = scanned.timing!;
    expect(timing.collectionTitles, 2);
    expect(timing.collectionMembers, 3);
    expect(timing.shows, 1);
    for (final phase in [timing.items, timing.collections, timing.showGenres]) {
      expect(phase, greaterThanOrEqualTo(Duration.zero));
    }
  });

  test(
    'show genre failure fails scan while listing failure keeps item inventory',
    () async {
      for (final type in [PlexLibraryType.movie, PlexLibraryType.show]) {
        final client = _client((request) async {
          if (request.url.queryParameters['type'] == '18' ||
              request.url.queryParameters['type'] == '2') {
            return http.Response('', 500);
          }
          return _page([
            {'ratingKey': '1', 'title': 'Item', 'type': 'movie'},
          ], total: 1);
        });
        final scan = client.scanLibrary(
          _server,
          'token',
          'library',
          type,
          isCurrent: () => true,
          onProgress: (_) {},
        );
        if (type == PlexLibraryType.show) {
          await expectLater(scan, _error('server-unreachable'));
        } else {
          final result = await scan;
          expect(result.items.single.id, '1');
          expect(result.collections.unavailable, isTrue);
        }
      }
    },
  );
}
