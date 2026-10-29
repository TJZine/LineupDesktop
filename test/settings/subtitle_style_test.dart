import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/settings/subtitle_style.dart';

void main() {
  test('strict canonical style object and backward compatible settings', () {
    const standard = SubtitleStyle();
    final old = const LineupSettings().toJson()..remove('subtitleStyle');
    expect(LineupSettings.fromJson(old).subtitleStyle, standard);
    final changed = standard
        .copyWith(
          size: SubtitleSize.p300,
          bold: true,
          font: SubtitleFont.cursive,
          useDeviceStyle: true,
          styleStyledSubtitles: true,
        )
        .applying(SubtitlePreset.light);
    expect(SubtitleStyle.fromJson(changed.toJson()), changed);
    expect(SubtitleStyle.fromJson(changed.toJson()).hashCode, changed.hashCode);
    expect(
      LineupSettings.fromJson(LineupSettings(subtitleStyle: changed).toJson())
          .subtitleStyle,
      changed,
    );
    for (final key in standard.toJson().keys) {
      final missing = standard.toJson()..remove(key);
      expect(
        () => SubtitleStyle.fromJson(missing),
        throwsFormatException,
        reason: key,
      );
      for (final bad in [
        null,
        4,
        <Object?>[],
        <String, Object?>{},
        'future',
        true,
        false,
      ]) {
        if (bad is bool && standard.toJson()[key] is bool) continue;
        expect(
          () => SubtitleStyle.fromJson({...standard.toJson(), key: bad}),
          throwsFormatException,
          reason: key,
        );
      }
    }
    expect(
      () => SubtitleStyle.fromJson({...standard.toJson(), 'future': true}),
      throwsFormatException,
    );
    for (final bad in [null, <Object?>[], true, 'style']) {
      expect(
        () => LineupSettings.fromJson({...old, 'subtitleStyle': bad}),
        throwsFormatException,
      );
    }
  });

  test('presets change only look fields and detect Custom', () {
    const retained = SubtitleStyle(
      size: SubtitleSize.p200,
      position: SubtitlePosition.highest,
      font: SubtitleFont.monoSerif,
      bold: true,
      useDeviceStyle: true,
      styleStyledSubtitles: true,
    );
    for (final preset in SubtitlePreset.values) {
      final applied = retained.applying(preset);
      expect(applied.preset, preset);
      expect(applied.size, retained.size);
      expect(applied.position, retained.position);
      expect(applied.font, retained.font);
      expect(applied.bold, isTrue);
      expect(applied.useDeviceStyle, isTrue);
      expect(applied.styleStyledSubtitles, isTrue);
      expect(
        applied.copyWith(textOpacity: SubtitleTextOpacity.half).preset,
        isNull,
      );
    }
    final standard = retained.applying(SubtitlePreset.standard);
    expect(standard.resolve().textColor, 0xffffffff);
    expect(standard.resolve().edgeColor, 0xff000000);
    expect(standard.resolve().backgroundColor, 0);
    expect(standard.resolve().windowColor, 0);
    expect(standard.edge, SubtitleEdge.outline);
    expect(
      retained.applying(SubtitlePreset.dropShadow).edge,
      SubtitleEdge.dropShadow,
    );
    expect(
      retained.applying(SubtitlePreset.classicBox).resolve().backgroundColor,
      0xbf000000,
    );
    expect(
      retained.applying(SubtitlePreset.highContrast).resolve().textColor,
      0xffffff00,
    );
    expect(
      retained.applying(SubtitlePreset.highContrast).resolve().backgroundColor,
      0xff000000,
    );
    expect(
      retained.applying(SubtitlePreset.light).resolve().textColor,
      0xff000000,
    );
    expect(
      retained.applying(SubtitlePreset.light).resolve().backgroundColor,
      0xffffffff,
    );
  });

  test('every enum resolves to concrete rendering values and round trips', () {
    const standard = SubtitleStyle();
    for (final (i, size) in SubtitleSize.values.indexed) {
      final style = standard.copyWith(size: size);
      expect(style.resolve().scale, [.5, .75, 1, 1.25, 1.5, 2, 3][i]);
      expect(SubtitleStyle.fromJson(style.toJson()), style);
    }
    for (final (i, position) in SubtitlePosition.values.indexed) {
      final style = standard.copyWith(position: position);
      expect(style.resolve().raise, [0, .05, .10, .15][i]);
      expect(SubtitleStyle.fromJson(style.toJson()), style);
    }
    for (final (i, color) in SubtitleColor.values.indexed) {
      final style = standard.copyWith(
        textColor: color,
        edgeColor: color,
        backgroundColor: color,
        windowColor: color,
        backgroundOpacity: SubtitleBoxOpacity.full,
        windowOpacity: SubtitleBoxOpacity.full,
      );
      final appearance = style.resolve();
      final expected = [
        0xffffffff,
        0xffffff00,
        0xff00ffff,
        0xff00ff00,
        0xffff00ff,
        0xffff0000,
        0xff0000ff,
        0xff000000,
      ][i];
      expect([
        appearance.textColor,
        appearance.edgeColor,
        appearance.backgroundColor,
        appearance.windowColor,
      ], everyElement(expected));
      expect(SubtitleStyle.fromJson(style.toJson()), style);
    }
    for (final (i, opacity) in SubtitleTextOpacity.values.indexed) {
      final style = standard.copyWith(textOpacity: opacity);
      expect(style.resolve().textColor >> 24, [255, 191, 128, 64][i]);
      expect(style.resolve().edgeColor >> 24, [255, 191, 128, 64][i]);
      expect(SubtitleStyle.fromJson(style.toJson()), style);
    }
    for (final (i, opacity) in SubtitleBoxOpacity.values.indexed) {
      final style = standard.copyWith(
        backgroundOpacity: opacity,
        windowOpacity: opacity,
      );
      expect(style.resolve().backgroundColor >> 24, [0, 64, 128, 191, 255][i]);
      expect(style.resolve().windowColor >> 24, [0, 64, 128, 191, 255][i]);
      expect(SubtitleStyle.fromJson(style.toJson()), style);
    }
    for (final (i, font) in SubtitleFont.values.indexed) {
      final style = standard.copyWith(font: font);
      expect(
        style.resolve().fontFamily,
        [
          'Inter',
          'JetBrains Mono',
          'Source Serif 4',
          'Courier Prime',
          'Comic Neue',
          'Dancing Script',
          'Alegreya Sans SC',
        ][i],
      );
      expect(SubtitleStyle.fromJson(style.toJson()), style);
    }
    for (final edge in SubtitleEdge.values) {
      final style = standard.copyWith(edge: edge);
      expect(style.resolve().edge, edge);
      expect(SubtitleStyle.fromJson(style.toJson()), style);
    }
    expect(standard.copyWith(bold: true).resolve().bold, isTrue);
  });
}
