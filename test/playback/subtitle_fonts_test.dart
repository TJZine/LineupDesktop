import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/playback/subtitle_layer.dart';
import 'package:lineup_desktop/settings/subtitle_style.dart';

const _sample = 'Hello iiii WWW mmmm';

double _width(String family, FontWeight weight) {
  final text = TextPainter(
    textDirection: TextDirection.ltr,
    text: TextSpan(
      text: _sample,
      style: TextStyle(fontFamily: family, fontSize: 40, fontWeight: weight),
    ),
  )..layout();
  final width = text.width;
  text.dispose();
  return width;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final product = SubtitleFonts();
  setUpAll(() async {
    for (final font in SubtitleFont.values.where(
      (f) => f != SubtitleFont.standard,
    )) {
      expect(await product.load(font), isTrue);
      final control = FontLoader('Control-${font.storageKey}');
      for (final weight in ['Regular', 'Bold']) {
        control.addFont(
          rootBundle.load(
            'assets/fonts/subtitles/${font.storageKey}/$weight.ttf',
          ),
        );
      }
      await control.load();
    }
  });
  for (final failedWeight in ['Regular', 'Bold']) {
    test(
      'synchronous $failedWeight failure preserves fallback and cache',
      () async {
        final assets = _BrokenFonts(failedWeight);
        final fonts = SubtitleFonts(assets: assets);
        final first = fonts.load(SubtitleFont.casual);
        expect(identical(first, fonts.load(SubtitleFont.casual)), isTrue);
        expect(await first, isFalse);
        expect(fonts.isReady(SubtitleFont.casual), isFalse);
        expect(assets.paths, hasLength(2));
        expect(await fonts.load(SubtitleFont.casual), isFalse);
        expect(assets.paths, hasLength(2));
        expect(fonts.isReady(SubtitleFont.standard), isTrue);
      },
    );
  }
  test(
    'both delayed weight failures are observed without uncaught errors',
    () async {
      final assets = _DelayedFailures();
      final fonts = SubtitleFonts(assets: assets);
      final loading = fonts.load(SubtitleFont.cursive);
      assets.regular.completeError(StateError('regular fixture failure'));
      assets.bold.completeError(StateError('bold fixture failure'));
      expect(await loading, isFalse);
      expect(fonts.isReady(SubtitleFont.cursive), isFalse);
    },
  );
  testWidgets('cold production families match real glyphs in both weights', (
    tester,
  ) async {
    final observations = <String, Object?>{};
    for (final font in SubtitleFont.values.where(
      (f) => f != SubtitleFont.standard,
    )) {
      for (final weight in [FontWeight.normal, FontWeight.bold]) {
        final actual = _width(font.fontFamily, weight);
        final control = _width('Control-${font.storageKey}', weight);
        final missing = _width('F1-Unregistered-Control', weight);
        observations['${font.storageKey}-${weight.value}'] = {
          'actual': actual,
          'direct': control,
          'missing': missing,
        };
      }
    }
    // Fixture-only dimensions, never cue/media content.
    debugPrint('F1_FONT_GLYPHS ${jsonEncode(observations)}');
    for (final font in SubtitleFont.values.where(
      (f) => f != SubtitleFont.standard,
    )) {
      expect(product.isReady(font), isTrue);
      for (final weight in [FontWeight.normal, FontWeight.bold]) {
        final control = _width('Control-${font.storageKey}', weight);
        expect(control, isNot(_width('F1-Unregistered-Control', weight)));
        expect(
          _width(font.fontFamily, weight),
          closeTo(control, .001),
          reason:
              '${font.storageKey} weight ${weight.value} must register real glyphs',
        );
      }
    }
  });
}

class _BrokenFonts extends CachingAssetBundle {
  _BrokenFonts(this.failedWeight);
  final String failedWeight;
  final paths = <String>[];
  @override
  Future<ByteData> load(String key) {
    paths.add(key);
    if (key.endsWith('/$failedWeight.ttf')) throw StateError('fixture failure');
    return rootBundle.load(key);
  }
}

class _DelayedFailures extends CachingAssetBundle {
  final regular = Completer<ByteData>();
  final bold = Completer<ByteData>();
  @override
  Future<ByteData> load(String key) =>
      key.endsWith('/Regular.ttf') ? regular.future : bold.future;
}
