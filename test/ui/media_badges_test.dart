import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/ui/media_badges.dart';

ChannelItem _item({String? range, int? channels}) => ChannelItem(
  id: 'synthetic',
  title: 'Program',
  duration: const Duration(minutes: 30),
  contentRating: 'TV-14',
  resolution: '1080p',
  dynamicRange: range,
  videoCodec: 'h264',
  audioCodec: 'aac',
  audioChannels: channels,
);

void main() {
  test('each surface preserves its badge set and order', () {
    final item = _item(range: 'hdr10', channels: 6);
    expect(mediaBadges(item, surface: MediaBadgeSurface.guide), [
      'TV-14',
      '1080P',
      'HDR10',
      'AAC',
      '5.1',
    ]);
    expect(
      mediaBadges(
        item,
        surface: MediaBadgeSurface.nowPlaying,
        effectiveVideoCodec: 'HEVC',
      ),
      ['TV-14', '1080P', 'HDR10', 'HEVC', 'AAC', '5.1'],
    );
    expect(
      mediaBadges(
        item,
        surface: MediaBadgeSurface.guide,
        runtimeHdr: true,
        effectiveVideoCodec: 'HEVC',
      ),
      ['TV-14', '1080P', 'HDR10', 'AAC', '5.1'],
    );
  });

  test('dynamic range table retains surface policy and suppresses unknown', () {
    for (final (catalog, guide, player) in <(String?, String?, String?)>[
      (null, null, null),
      ('', null, null),
      ('unknown', null, null),
      ('UNKNOWN', null, null),
      ('sdr', null, 'SDR'),
      ('hdr', null, 'HDR'),
      ('hdr10', 'HDR10', 'HDR10'),
      ('hlg', 'HLG', 'HLG'),
      ('dolbyVision', 'DOLBY VISION', 'DOLBY VISION'),
      ('dolby vision', null, 'DOLBY VISION'),
      ('custom', null, 'CUSTOM'),
    ]) {
      for (final surface in MediaBadgeSurface.values) {
        final expected = surface == MediaBadgeSurface.guide ? guide : player;
        expect(mediaBadges(_item(range: catalog), surface: surface), [
          'TV-14',
          '1080P',
          ?expected,
          'AAC',
        ], reason: '$catalog / $surface');
      }
    }
  });

  test(
    'runtime HDR overrides SDR or unknown and retains specific HDR formats',
    () {
      for (final (catalog, expected) in <(String?, String)>[
        (null, 'HDR'),
        ('unknown', 'HDR'),
        ('sdr', 'HDR'),
        ('hdr', 'HDR'),
        ('custom', 'HDR'),
        ('hdr10', 'HDR10'),
        ('hlg', 'HLG'),
        ('dolbyVision', 'DOLBY VISION'),
      ]) {
        expect(
          mediaBadges(
            _item(range: catalog),
            surface: MediaBadgeSurface.nowPlaying,
            runtimeHdr: true,
          ),
          ['TV-14', '1080P', expected, 'AAC'],
          reason: '$catalog',
        );
      }
    },
  );

  test(
    'channel labels agree across surfaces, including nonstandard counts',
    () {
      for (final (channels, label) in [
        (1, 'MONO'),
        (2, 'STEREO'),
        (3, '3 CH'),
        (6, '5.1'),
        (8, '7.1'),
      ]) {
        for (final surface in MediaBadgeSurface.values) {
          expect(mediaBadges(_item(channels: channels), surface: surface), [
            'TV-14',
            '1080P',
            'AAC',
            label,
          ]);
        }
      }
      final empty = ChannelItem(
        id: 'empty',
        title: 'Empty',
        duration: const Duration(minutes: 1),
      );
      for (final surface in MediaBadgeSurface.values) {
        expect(mediaBadges(empty, surface: surface), isEmpty);
      }
    },
  );
}
