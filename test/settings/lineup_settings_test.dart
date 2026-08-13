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
  });

  test('round trips meaningful preferences', () {
    const original = LineupSettings(
      guideDensity: GuideDensity.compact,
      audioPassthrough: true,
      reduceMotion: true,
    );
    final restored = LineupSettings.fromJson(original.toJson());
    expect(restored.guideDensity, GuideDensity.compact);
    expect(restored.audioPassthrough, isTrue);
    expect(restored.reduceMotion, isTrue);
  });
}
