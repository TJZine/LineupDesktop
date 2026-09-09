import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

void main() {
  test('uses the two-hour Guide default and final desktop options', () {
    const settings = LineupSettings();
    expect(settings.theme, LineupThemeName.emberSteel);
    expect(settings.guideHours, 2);
    expect(LineupSettings.guideHoursOptions, [2, 3, 4]);
    expect(settings.toJson(), containsPair('audioSetupComplete', true));
  });

  test('round trips every retained preference', () {
    const original = LineupSettings(
      theme: LineupThemeName.slatePine,
      guideHours: 4,
      guideInfoBackgroundMode: GuideInfoBackgroundMode.artwork,
      preferClearLogos: false,
      reduceMotion: true,
      nowWatchingBanner: false,
      osdAutoHideSeconds: 8,
      largeFocusIndicators: true,
      profilePickerOnStartup: true,
      diagnosticsEnabled: true,
      dvrControlsEnabled: true,
    );
    expect(
      LineupSettings.fromJson(original.toJson()).toJson(),
      original.toJson(),
    );
  });

  test('accepts, validates, and omits retired preference keys', () {
    final legacy = const LineupSettings().toJson()
      ..addAll({
        'guideLayoutMode': 'overlay',
        'pastMinutes': 180,
        'guideDensity': 'compact',
        'libraryTabsEnabled': false,
      });
    final restored = LineupSettings.fromJson(legacy);
    expect(restored.guideHours, 2);
    for (final key in [
      'guideLayoutMode',
      'pastMinutes',
      'guideDensity',
      'libraryTabsEnabled',
    ]) {
      expect(restored.toJson(), isNot(contains(key)));
    }
  });

  test('maps legacy Guide spans to four hours', () {
    for (final hours in [6, 8, 12]) {
      final json = const LineupSettings().toJson()..['guideHours'] = hours;
      expect(LineupSettings.fromJson(json).guideHours, 4);
    }
    for (final hours in [2, 3, 4]) {
      final json = const LineupSettings().toJson()..['guideHours'] = hours;
      expect(LineupSettings.fromJson(json).guideHours, hours);
    }
  });

  test('retains DVR and audio compatibility contracts', () {
    final old = const LineupSettings().toJson()..remove('dvrControlsEnabled');
    expect(LineupSettings.fromJson(old).dvrControlsEnabled, isFalse);
    final audio = const LineupSettings().toJson()
      ..['audioSetupComplete'] = false;
    expect(
      LineupSettings.fromJson(audio).toJson()['audioSetupComplete'],
      isTrue,
    );
  });

  test('rejects malformed or unknown canonical and retired fields', () {
    final canonical = const LineupSettings().toJson();
    for (final invalid in [
      {...canonical}..remove('theme'),
      {...canonical, 'future': true},
      {...canonical, 'reduceMotion': 1},
      {...canonical, 'guideHours': 2.0},
      {...canonical, 'guideHours': 5},
      {...canonical, 'theme': 'future-theme'},
      {...canonical, 'guideInfoBackgroundMode': 'future-background'},
      {...canonical, 'guideLayoutMode': 'future-layout'},
      {...canonical, 'guideDensity': 'future-density'},
      {...canonical, 'pastMinutes': 45},
      {...canonical, 'libraryTabsEnabled': 'false'},
    ]) {
      expect(() => LineupSettings.fromJson(invalid), throwsFormatException);
    }
  });
}
