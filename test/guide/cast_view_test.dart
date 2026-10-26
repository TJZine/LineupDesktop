import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/guide/cast_view.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

void main() {
  for (final type in ['episode', 'movie']) {
    test('$type default fills only portraits when detail is inconsistent', () {
      final catalog = [
        ChannelCastMember(name: 'Actor A', role: 'Original'),
        ChannelCastMember(name: 'Actor B', portrait: Uri.parse('/original')),
        ChannelCastMember(name: 'Actor C'),
      ];
      final cast = mergeCast(catalog, const [
        PlexCastMember(name: ' actor b ', role: 'Changed', thumbPath: '/new'),
        PlexCastMember(name: 'ACTOR A', role: 'Changed', thumbPath: '/filled'),
        PlexCastMember(name: 'Extra', thumbPath: '/extra'),
      ]).cast;
      expect(cast.map((e) => e.name), ['Actor A', 'Actor B', 'Actor C']);
      expect(cast.map((e) => e.role), ['Original', null, null]);
      expect(cast.map((e) => e.portrait?.path), ['/filled', '/original', null]);
      expect(catalog.first.portrait, isNull);
    });
    test(
      '$type complete detail replaces order and roles but catalog portraits win',
      () {
        final cast = mergeCast(
          [
            ChannelCastMember(
              name: 'Actor A',
              role: 'Old',
              portrait: Uri.parse('/original'),
            ),
          ],
          const [
            PlexCastMember(name: 'Extra', role: 'Guest', thumbPath: '/extra'),
            PlexCastMember(name: 'actor a', role: 'New', thumbPath: '/new'),
          ],
        ).cast;
        expect(cast.map((e) => e.name), ['Extra', 'actor a']);
        expect(cast.map((e) => e.role), ['Guest', 'New']);
        expect(cast.map((e) => e.portrait?.path), ['/extra', '/original']);
      },
    );
  }
  test('invalid detail portraits cannot enter the display overlay; replacement is capped', () {
    final cast = mergeCast([], [
      const PlexCastMember(name: 'Unsafe', thumbPath: 'file:///private'),
      for (var i = 0; i < 30; i++) PlexCastMember(name: 'Actor $i'),
    ]).cast;
    expect(cast, hasLength(maxRichCastMembers));
    expect(cast.first.portrait, isNull);
    expect(cast.clear, throwsUnsupportedError);
  });
}
