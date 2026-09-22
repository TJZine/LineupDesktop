import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/player_track_label.dart';

void main() {
  group('formatPlayerTrackDisplay language resolution', () {
    const cases = <({String input, String? primary})>[
      (input: 'en', primary: 'English'),
      (input: 'ENG', primary: 'English'),
      (input: 'fra', primary: 'Français'),
      (input: 'fre', primary: 'Français'),
      (input: 'dEu', primary: 'Deutsch'),
      (input: 'ger', primary: 'Deutsch'),
      (input: 'es-419', primary: 'español (Latinoamérica)'),
      (input: 'pt-BR', primary: 'Português (Brasil)'),
      (input: 'zh-Hans', primary: '简体中文'),
      (input: 'zh_Hant', primary: '繁體中文'),
      (input: 'en-unknown', primary: 'en-unknown'),
      (input: 'und', primary: 'Audio track 1'),
      (input: 'mul', primary: 'Multiple languages'),
      (input: 'zxx', primary: 'No linguistic content'),
      (input: '   ', primary: 'Audio track 1'),
    ];

    for (final testCase in cases) {
      test(testCase.input, () {
        final display = formatPlayerTrackDisplay(
          _track(language: testCase.input),
        );
        expect(display.primaryText, testCase.primary);
      });
    }
  });

  test('normalizes only lookup casing and separators', () {
    expect(
      formatPlayerTrackDisplay(_track(language: ' En_us ')).primaryText,
      'English (United States of America)',
    );
    expect(
      formatPlayerTrackDisplay(_track(language: 'pt-br')).primaryText,
      'Português (Brasil)',
    );
    expect(
      formatPlayerTrackDisplay(_track(language: 'en-XX')).primaryText,
      'en-XX',
    );
  });

  group('formatPlayerTrackDisplay purposes and facts', () {
    test('keeps explicit audio purposes in order and type-scoped', () {
      final display = formatPlayerTrackDisplay(
        _track(
          language: 'en',
          visualImpaired: true,
          commentary: true,
          channelCount: 2,
          channelLayout: 'stereo',
          codec: 'aac',
        ),
      );
      expect(display.primaryText, 'English — Audio description');
      expect(display.secondaryFacts, ['Commentary', 'Stereo', 'AAC']);
    });

    test('keeps unrelated titles and subtitle purposes', () {
      final display = formatPlayerTrackDisplay(
        _track(
          type: PlayerTrackType.subtitle,
          language: 'en',
          title: 'Festival edition',
          hearingImpaired: true,
          forced: true,
          codec: 'subrip',
        ),
      );
      expect(display.primaryText, 'English — Festival edition');
      expect(display.secondaryFacts, ['SDH', 'Forced', 'SRT (text)']);
      expect(
        display.semanticsText,
        contains('subtitles for deaf and hard-of-hearing viewers'),
        reason: 'The public result reserves the complete semantic wording.',
      );
      expect(
        display.semanticsText,
        contains('marked as forced'),
        reason: 'Forced remains a disposition, not an invented cue meaning.',
      );
    });

    test('expands a primary forced purpose without inventing cue meaning', () {
      final display = formatPlayerTrackDisplay(
        _track(type: PlayerTrackType.subtitle, language: 'en', forced: true),
      );
      expect(display.primaryText, 'English — Forced');
      expect(display.semanticsText, contains('English — marked as forced'));
      expect(display.semanticsText, isNot(contains('foreign-language')));
    });

    test('does not infer purpose from a title or apply it to another type', () {
      final audio = formatPlayerTrackDisplay(
        _track(language: 'en', title: 'Commentary'),
      );
      final subtitle = formatPlayerTrackDisplay(
        _track(
          type: PlayerTrackType.subtitle,
          language: 'en',
          title: 'Audio description',
          visualImpaired: true,
          commentary: true,
        ),
      );
      expect(audio.secondaryFacts, isEmpty);
      expect(subtitle.primaryText, 'English — Audio description');
      expect(subtitle.secondaryFacts, isEmpty);
    });

    test('does not generate purposes from explicit false flags', () {
      final audio = formatPlayerTrackDisplay(
        _track(language: 'en', visualImpaired: false, commentary: false),
      );
      final subtitle = formatPlayerTrackDisplay(
        _track(
          type: PlayerTrackType.subtitle,
          language: 'en',
          hearingImpaired: false,
          forced: false,
        ),
      );
      expect(audio.primaryText, 'English');
      expect(audio.secondaryFacts, isEmpty);
      expect(subtitle.primaryText, 'English');
      expect(subtitle.secondaryFacts, isEmpty);
    });
  });

  group('formatPlayerTrackDisplay channels and codecs', () {
    const channelCases = <({String? layout, int? count, String? fact})>[
      (layout: 'stereo', count: null, fact: 'Stereo'),
      (layout: '5.1', count: 6, fact: '5.1 surround'),
      (layout: '5.1(side)', count: 6, fact: '5.1 surround'),
      (layout: 'unknown', count: 6, fact: '6 channels'),
      (layout: '7.1', count: 6, fact: '6 channels'),
      (layout: null, count: 1, fact: '1 channels'),
      (layout: null, count: 0, fact: null),
      (layout: null, count: -1, fact: null),
      (layout: 'unknown', count: null, fact: null),
    ];

    for (final testCase in channelCases) {
      test('channels ${testCase.layout}/${testCase.count}', () {
        final display = formatPlayerTrackDisplay(
          _track(channelLayout: testCase.layout, channelCount: testCase.count),
        );
        expect(
          display.secondaryFacts,
          testCase.fact == null ? isEmpty : [testCase.fact],
        );
      });
    }

    const codecCases = <({PlayerTrackType type, String codec, String? fact})>[
      (type: PlayerTrackType.audio, codec: 'aac', fact: 'AAC'),
      (type: PlayerTrackType.audio, codec: 'ac3', fact: 'Dolby Digital'),
      (type: PlayerTrackType.audio, codec: 'eac3', fact: 'Dolby Digital Plus'),
      (type: PlayerTrackType.audio, codec: 'truehd', fact: 'Dolby TrueHD'),
      (type: PlayerTrackType.audio, codec: 'dts', fact: 'DTS'),
      (type: PlayerTrackType.audio, codec: 'dts-hd', fact: 'dts-hd'),
      (type: PlayerTrackType.audio, codec: 'flac', fact: 'FLAC'),
      (type: PlayerTrackType.audio, codec: 'opus', fact: 'Opus'),
      (type: PlayerTrackType.subtitle, codec: 'subrip', fact: 'SRT (text)'),
      (type: PlayerTrackType.subtitle, codec: 'ass', fact: 'ASS (styled text)'),
      (type: PlayerTrackType.subtitle, codec: 'ssa', fact: 'SSA (styled text)'),
      (
        type: PlayerTrackType.subtitle,
        codec: 'hdmv_pgs_subtitle',
        fact: 'PGS (image)',
      ),
      (
        type: PlayerTrackType.subtitle,
        codec: 'dvd_subtitle',
        fact: 'VobSub (image)',
      ),
      (
        type: PlayerTrackType.subtitle,
        codec: 'custom_codec',
        fact: 'custom_codec',
      ),
      (type: PlayerTrackType.subtitle, codec: '   ', fact: null),
    ];

    for (final testCase in codecCases) {
      test('codec ${testCase.codec}', () {
        final display = formatPlayerTrackDisplay(
          _track(type: testCase.type, codec: testCase.codec),
        );
        expect(
          display.secondaryFacts,
          testCase.fact == null ? isEmpty : [testCase.fact],
        );
      });
    }
  });

  test('orders purpose, channels, codec, and external facts', () {
    final display = formatPlayerTrackDisplay(
      _track(
        language: 'en',
        commentary: true,
        channelCount: 6,
        channelLayout: '5.1',
        codec: 'eac3',
        external: true,
      ),
    );
    expect(display.secondaryFacts, [
      '5.1 surround',
      'Dolby Digital Plus',
      'External',
    ]);
  });

  test('filters generated facts repeated by editorial title or each other', () {
    final titled = formatPlayerTrackDisplay(
      _track(language: 'en', title: 'Stereo', channelLayout: 'stereo'),
    );
    expect(titled.primaryText, 'English — Stereo');
    expect(titled.secondaryFacts, isEmpty);

    final generated = formatPlayerTrackDisplay(
      _track(channelLayout: 'stereo', codec: 'Stereo'),
    );
    expect(generated.secondaryFacts, ['Stereo']);

    final external = formatPlayerTrackDisplay(
      _track(language: 'en', title: 'External', external: true),
    );
    expect(external.primaryText, 'English — External');
    expect(external.secondaryFacts, isEmpty);
  });

  group('formatPlayerTrackDisplay de-duplication and peers', () {
    test('suppresses language, codec, and exact purpose title duplicates', () {
      final display = formatPlayerTrackDisplay(
        _track(
          language: 'en',
          title: 'English',
          codec: 'aac',
          commentary: true,
        ),
      );
      expect(display.primaryText, 'English — Commentary');
      expect(display.secondaryFacts, ['AAC']);
    });

    test(
      'retains the canonical generated fact after removing a duplicate title',
      () {
        final codec = formatPlayerTrackDisplay(
          _track(title: 'AAC', codec: 'aac'),
        );
        final purpose = formatPlayerTrackDisplay(
          _track(title: 'Commentary', commentary: true),
        );
        expect(codec.primaryText, 'Audio track 1');
        expect(codec.secondaryFacts, ['AAC']);
        expect(purpose.primaryText, 'Audio track 1');
        expect(purpose.secondaryFacts, ['Commentary']);
      },
    );

    test('uses the smallest available visible peer difference', () {
      final peers = [
        _track(id: 1, language: 'en', title: 'Original', codec: 'aac'),
        _track(id: 2, language: 'en', title: 'Original', codec: 'flac'),
      ];
      final first = formatPlayerTrackDisplay(peers[0], peers: peers);
      final second = formatPlayerTrackDisplay(peers[1], peers: peers);
      expect(first.primaryText, second.primaryText);
      expect(first.secondaryFacts, ['AAC']);
      expect(second.secondaryFacts, ['FLAC']);
      expect(first.compactText, 'English');
      expect(second.compactText, 'English');
    });

    test(
      'adds title discriminator to compact text when peers share language',
      () {
        final peers = [
          _track(id: 1, language: 'en', title: 'Theatrical mix'),
          _track(id: 2, language: 'en', title: 'Director mix'),
        ];
        expect(
          formatPlayerTrackDisplay(peers[0], peers: peers).compactText,
          'English — Theatrical mix',
        );
        expect(
          formatPlayerTrackDisplay(peers[1], peers: peers).compactText,
          'English — Director mix',
        );
      },
    );

    test('puts Track N first when visible metadata is identical', () {
      final peers = [
        _track(id: 7, language: 'en', title: 'Original', codec: 'aac'),
        _track(id: 8, language: 'en', title: 'Original', codec: 'aac'),
      ];
      final display = formatPlayerTrackDisplay(peers[1], peers: peers);
      expect(display.secondaryFacts, ['Track 8', 'AAC']);
      expect(
        display.tooltipText,
        'Audio track: English — Original; Track 8; AAC',
      );
      expect(
        display.semanticsText,
        'Select Audio track: English — Original; Track 8; AAC.',
      );
    });

    test(
      'keeps all-absent peers distinguishable by their fallback primaries',
      () {
        final peers = [_track(id: 1), _track(id: 2)];
        expect(
          formatPlayerTrackDisplay(peers[0], peers: peers).primaryText,
          'Audio track 1',
        );
        expect(
          formatPlayerTrackDisplay(peers[1], peers: peers).primaryText,
          'Audio track 2',
        );
        expect(
          formatPlayerTrackDisplay(peers[0], peers: peers).secondaryFacts,
          isEmpty,
        );
        expect(
          formatPlayerTrackDisplay(peers[1], peers: peers).secondaryFacts,
          isEmpty,
        );
      },
    );

    test('keeps titleless same-language peers null-safe and distinct', () {
      final peers = [
        _track(id: 1, language: 'en', title: 'Original'),
        _track(id: 2, language: 'en'),
      ];
      expect(
        formatPlayerTrackDisplay(peers[0], peers: peers).compactText,
        'English — Original',
      );
      expect(
        formatPlayerTrackDisplay(peers[1], peers: peers).compactText,
        'English',
      );
    });

    test('keeps long title tails distinct without changing identity', () {
      final peers = [
        _track(
          id: 1,
          language: 'en',
          title: 'A long shared title prefix that ends with theatrical',
        ),
        _track(
          id: 2,
          language: 'en',
          title: 'A long shared title prefix that ends with commentary',
        ),
      ];
      final first = formatPlayerTrackDisplay(peers[0], peers: peers);
      final second = formatPlayerTrackDisplay(peers[1], peers: peers);
      expect(first.primaryText, isNot(second.primaryText));
      expect(first.compactText, isNot(second.compactText));
    });
  });

  test('returns an immutable display result and complete public fields', () {
    final display = formatPlayerTrackDisplay(
      _track(language: 'en', title: 'Original', codec: 'aac'),
    );
    expect(
      () => display.secondaryFacts.add('unexpected'),
      throwsUnsupportedError,
    );
    expect(display.secondaryText, 'AAC');
    expect(display.tooltipText, 'Audio track: English — Original; AAC');
    expect(
      display.semanticsText,
      'Select Audio track: English — Original; AAC.',
    );
  });
}

PlayerTrack _track({
  int id = 1,
  PlayerTrackType type = PlayerTrackType.audio,
  String? title,
  String? language,
  String? codec,
  int? channelCount,
  String? channelLayout,
  bool? forced,
  bool? external,
  bool? hearingImpaired,
  bool? visualImpaired,
  bool? commentary,
}) => PlayerTrack(
  id: id,
  type: type,
  selected: false,
  title: title,
  language: language,
  codec: codec,
  channelCount: channelCount,
  channelLayout: channelLayout,
  forced: forced,
  external: external,
  hearingImpaired: hearingImpaired,
  visualImpaired: visualImpaired,
  commentary: commentary,
);
