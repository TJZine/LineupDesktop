import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

void main() {
  final server = Uri.parse('https://synthetic.invalid');
  Map<String, Object?> detail(Object? rows) => {
    'MediaContainer': {'Metadata': rows},
  };
  final roles = [
    {'tag': ' Actor A ', 'role': ' First '},
    {'tag': 'actor a', 'role': 'Later', 'thumb': '/portrait/a'},
    {'tag': 'Actor A', 'thumb': '/portrait/ignored'},
  ];
  final row = {'ratingKey': '1', 'Role': roles};

  test('detail uses a single encoded item path, header token, and shared cast parser', () async {
    final client = PlexClient(
      clientIdentifier: 'test',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/library/metadata/1');
        expect(request.url.query, isEmpty);
        expect(request.headers['X-Plex-Token'], 'secret');
        expect(request.followRedirects, isFalse);
        return http.Response(jsonEncode(detail([row])), 200);
      }),
    );
    addTearDown(client.close);
    final cast = await client.itemCast(server, 'secret', '1');
    expect(cast.single.name, 'Actor A');
    expect(cast.single.role, 'First');
    expect(cast.single.thumbPath, '/portrait/a');
    final bulk = parseMediaItem({
      ...row,
      'title': 'Fixture',
      'type': 'movie',
      'duration': 1000,
    });
    expect(bulk.cast.single.thumbPath, cast.single.thumbPath);
    expect(bulk.cast.single.role, cast.single.role);
  });

  for (final row in <Map<String, Object?>>[
    {'ratingKey': '1'},
    {'ratingKey': '1', 'Role': null},
    {'ratingKey': '1', 'Role': <Object?>[]},
  ]) {
    test(
      'empty optional detail cast is valid ${row.length}/${row['Role'] == null}',
      () async {
        final client = PlexClient(
          clientIdentifier: 'test',
          httpClient: MockClient(
            (_) async => http.Response(jsonEncode(detail([row])), 200),
          ),
        );
        addTearDown(client.close);
        expect(await client.itemCast(server, 'secret', '1'), isEmpty);
      },
    );
  }
  for (final rows in <Object?>[
    [],
    [row, row],
    [
      {'ratingKey': '2', 'Role': roles},
    ],
    [
      {'ratingKey': '1', 'Role': <String, Object?>{}},
    ],
    null,
  ]) {
    test('rejects invalid detail shape ${jsonEncode(rows)}', () async {
      final client = PlexClient(
        clientIdentifier: 'test',
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode(detail(rows)), 200),
        ),
      );
      addTearDown(client.close);
      await expectLater(
        client.itemCast(server, 'secret', '1'),
        throwsA(
          isA<PlexException>().having(
            (e) => e.code,
            'code',
            'cast-detail-invalid',
          ),
        ),
      );
    });
  }
  for (final status in [401, 500, 302]) {
    test('detail rejects HTTP $status without following redirects', () async {
      var calls = 0;
      final client = PlexClient(
        clientIdentifier: 'test',
        httpClient: MockClient((request) async {
          calls++;
          expect(request.followRedirects, isFalse);
          return http.Response(
            '',
            status,
            headers: {'location': 'https://other.invalid'},
          );
        }),
      );
      addTearDown(client.close);
      await expectLater(
        client.itemCast(server, 'secret', '1'),
        throwsA(isA<PlexException>()),
      );
      expect(calls, 1);
    });
  }
  test('detail body remains bounded', () async {
    final client = PlexClient(
      clientIdentifier: 'test',
      httpClient: MockClient(
        (_) async => http.Response(
          ' ' * (PlexClient.maximumControlResponseBytes + 1),
          200,
        ),
      ),
    );
    addTearDown(client.close);
    await expectLater(
      client.itemCast(server, 'secret', '1'),
      throwsA(
        isA<PlexException>().having(
          (e) => e.code,
          'code',
          'response-too-large',
        ),
      ),
    );
  });
  test('parser fills retained duplicates even after the cast cap', () {
    final item = parseMediaItem({
      'ratingKey': '1',
      'title': 'Fixture',
      'type': 'movie',
      'duration': 1000,
      'Role': [
        for (var i = 0; i < maxRichCastMembers + 1; i++) {'tag': 'Actor $i'},
        {'tag': 'actor 0', 'role': 'Later', 'thumb': '/portrait/a'},
      ],
    });
    expect(item.cast, hasLength(maxRichCastMembers));
    expect(item.cast.first.name, 'Actor 0');
    expect(item.cast.first.role, isNull);
    expect(item.cast.first.thumbPath, '/portrait/a');
  });
}
