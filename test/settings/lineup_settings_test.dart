import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

void main() {
  test('uses the upstream two-hour Guide default and desktop options', () {
    const settings = LineupSettings();

    expect(settings.guideHours, 2);
    expect(LineupSettings.guideHoursOptions, [2, 3, 4, 6, 8, 12]);
    expect(settings.guideDensity, GuideDensity.comfortable);
  });

  test('restores defaults and snaps unsafe ranges', () {
    final settings = LineupSettings.fromJson({
      'guideHours': 99,
      'pastMinutes': -5,
      'osdAutoHideSeconds': 99,
    });
    expect(settings.guideHours, 12);
    expect(settings.pastMinutes, 0);
    expect(settings.osdAutoHideSeconds, 15);
    expect(settings.theme, LineupThemeName.emberSteel);
    expect(settings.guideLayoutMode, GuideLayoutMode.pictureInPicture);
  });

  test('snaps OSD auto-hide below its documented minimum', () {
    final settings = LineupSettings.fromJson({'osdAutoHideSeconds': 1});

    expect(settings.osdAutoHideSeconds, 2);
  });

  test('snaps restored numeric settings to selectable options', () {
    final settings = LineupSettings.fromJson({
      'guideHours': 3,
      'pastMinutes': 45,
      'osdAutoHideSeconds': 5,
    });

    expect(settings.guideHours, 3);
    expect(settings.pastMinutes, 60);
    expect(settings.osdAutoHideSeconds, 6);
  });

  test('round trips meaningful preferences', () {
    const original = LineupSettings(
      theme: LineupThemeName.slatePine,
      guideDensity: GuideDensity.compact,
      guideLayoutMode: GuideLayoutMode.overlay,
      guideInfoBackgroundMode: GuideInfoBackgroundMode.artwork,
      preferClearLogos: false,
      audioSetupComplete: true,
      reduceMotion: true,
      libraryTabsEnabled: false,
      nowWatchingBanner: false,
      osdAutoHideSeconds: 8,
    );
    final restored = LineupSettings.fromJson(original.toJson());
    expect(restored.guideDensity, GuideDensity.compact);
    expect(restored.theme, LineupThemeName.slatePine);
    expect(restored.guideLayoutMode, GuideLayoutMode.overlay);
    expect(restored.guideInfoBackgroundMode, GuideInfoBackgroundMode.artwork);
    expect(restored.preferClearLogos, isFalse);
    expect(restored.audioSetupComplete, isTrue);
    expect(restored.reduceMotion, isTrue);
    expect(restored.libraryTabsEnabled, isFalse);
    expect(restored.nowWatchingBanner, isFalse);
    expect(restored.osdAutoHideSeconds, 8);
  });

  test('invalid theme and Guide layout values fall back safely', () {
    final restored = LineupSettings.fromJson({
      'theme': 'future-theme',
      'guideLayoutMode': 'future-layout',
    });
    expect(restored.theme, LineupThemeName.emberSteel);
    expect(restored.guideLayoutMode, GuideLayoutMode.pictureInPicture);
  });

  test('invalid Guide info background values fall back safely', () {
    final restored = LineupSettings.fromJson({
      'guideInfoBackgroundMode': 'future-background',
    });

    expect(restored.guideInfoBackgroundMode, GuideInfoBackgroundMode.bleed);
    expect(restored.preferClearLogos, isTrue);
  });

  test('invalid numeric settings fall back without rejecting other state', () {
    final restored = LineupSettings.fromJson({
      'guideHours': 'many',
      'pastMinutes': false,
      'osdAutoHideSeconds': double.nan,
      'nowWatchingBanner': false,
    });

    expect(restored.guideHours, 2);
    expect(restored.pastMinutes, 30);
    expect(restored.osdAutoHideSeconds, 4);
    expect(restored.nowWatchingBanner, isFalse);
  });
}
