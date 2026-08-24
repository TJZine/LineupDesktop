import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

void main() {
  test('uses the upstream two-hour Guide default and desktop options', () {
    const settings = LineupSettings();

    expect(settings.guideHours, 2);
    expect(LineupSettings.guideHoursOptions, [2, 3, 4, 6, 8, 12]);
    expect(settings.guideDensity, GuideDensity.comfortable);
  });

  test('round trips every canonical preference', () {
    const original = LineupSettings(
      theme: LineupThemeName.slatePine,
      guideHours: 6,
      pastMinutes: 60,
      guideDensity: GuideDensity.compact,
      guideLayoutMode: GuideLayoutMode.overlay,
      guideInfoBackgroundMode: GuideInfoBackgroundMode.artwork,
      preferClearLogos: false,
      audioSetupComplete: true,
      reduceMotion: true,
      libraryTabsEnabled: false,
      nowWatchingBanner: false,
      osdAutoHideSeconds: 8,
      largeFocusIndicators: true,
      profilePickerOnStartup: true,
      diagnosticsEnabled: true,
    );
    final restored = LineupSettings.fromJson(original.toJson());
    expect(restored.toJson(), original.toJson());
  });

  test('rejects missing, unknown, and wrong-type fields', () {
    final canonical = const LineupSettings().toJson();
    for (final invalid in [
      {...canonical}..remove('theme'),
      {...canonical, 'future': true},
      {...canonical, 'reduceMotion': 1},
      {...canonical, 'guideHours': 2.0},
    ]) {
      expect(() => LineupSettings.fromJson(invalid), throwsFormatException);
    }
  });

  test('rejects unsupported options and invalid enum values', () {
    final canonical = const LineupSettings().toJson();
    for (final invalid in [
      {...canonical, 'guideHours': 5},
      {...canonical, 'pastMinutes': 45},
      {...canonical, 'osdAutoHideSeconds': 5},
      {...canonical, 'theme': 'future-theme'},
      {...canonical, 'guideDensity': 'future-density'},
      {...canonical, 'guideLayoutMode': 'future-layout'},
      {...canonical, 'guideInfoBackgroundMode': 'future-background'},
    ]) {
      expect(() => LineupSettings.fromJson(invalid), throwsFormatException);
    }
  });
}
