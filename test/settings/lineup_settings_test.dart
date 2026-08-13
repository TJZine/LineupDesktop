import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

void main() {
  test('restores defaults and clamps unsafe ranges', () {
    final settings = LineupSettings.fromJson({
      'guideHours': 99,
      'pastMinutes': -5,
      'subtitleMode': 'unknown',
    });
    expect(settings.guideHours, 12);
    expect(settings.pastMinutes, 0);
    expect(settings.subtitleMode, SubtitleMode.full);
    expect(settings.theme, LineupThemeName.emberSteel);
    expect(settings.guideLayoutMode, GuideLayoutMode.pictureInPicture);
  });

  test('round trips meaningful preferences', () {
    const original = LineupSettings(
      theme: LineupThemeName.slatePine,
      guideDensity: GuideDensity.compact,
      guideLayoutMode: GuideLayoutMode.overlay,
      audioPassthrough: true,
      audioSetupComplete: true,
      reduceMotion: true,
    );
    final restored = LineupSettings.fromJson(original.toJson());
    expect(restored.guideDensity, GuideDensity.compact);
    expect(restored.theme, LineupThemeName.slatePine);
    expect(restored.guideLayoutMode, GuideLayoutMode.overlay);
    expect(restored.audioPassthrough, isTrue);
    expect(restored.audioSetupComplete, isTrue);
    expect(restored.reduceMotion, isTrue);
  });

  test('invalid theme and Guide layout values fall back safely', () {
    final restored = LineupSettings.fromJson({
      'theme': 'future-theme',
      'guideLayoutMode': 'future-layout',
    });
    expect(restored.theme, LineupThemeName.emberSteel);
    expect(restored.guideLayoutMode, GuideLayoutMode.pictureInPicture);
  });
}
