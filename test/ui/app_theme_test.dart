import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

void main() {
  test(
    'theme inventory and default match the implemented upstream product',
    () {
      expect(LineupThemeName.values.map((theme) => theme.label), [
        'Ember & Steel',
        'Slate & Pine',
        'Swiss Minimal',
        'DirecTV Classic',
        'Glassmorphism',
      ]);
      expect(LineupThemeName.fromStorage(null), LineupThemeName.emberSteel);
    },
  );

  test('every theme supplies usable semantic text and focus contrast', () {
    for (final name in LineupThemeName.values) {
      final theme = LineupTheme.forName(name);
      final roles = theme.extension<LineupThemeRoles>()!;
      expect(
        _contrast(roles.primaryText, roles.deepBackground),
        greaterThanOrEqualTo(4.5),
        reason: '${name.label} primary text',
      );
      expect(
        _contrast(roles.onFocus, roles.progressFill),
        greaterThanOrEqualTo(3),
        reason: '${name.label} focused control',
      );
      expect(roles.focusBorder, isNot(roles.deepBackground));
      expect(roles.progressTrack, isNot(roles.progressFill));
    }
  });
}

double _contrast(Color first, Color second) {
  double luminance(Color color) => color.computeLuminance();
  final lighter = [
    luminance(first),
    luminance(second),
  ].reduce((value, next) => value > next ? value : next);
  final darker = [
    luminance(first),
    luminance(second),
  ].reduce((value, next) => value < next ? value : next);
  return (lighter + 0.05) / (darker + 0.05);
}
