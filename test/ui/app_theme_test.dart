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
      for (final surface in [
        roles.deepBackground,
        roles.primarySurface,
        roles.elevatedSurface,
        roles.overlaySurface,
      ]) {
        final paintedSurface = _paint(surface, roles.deepBackground);
        for (final text in [
          roles.primaryText,
          roles.secondaryText,
          roles.mutedText,
        ]) {
          expect(
            _contrast(_paint(text, paintedSurface), paintedSurface),
            greaterThanOrEqualTo(4.5),
            reason: '${name.label} semantic text on surface',
          );
        }
      }
      final primarySurface = _paint(roles.primarySurface, roles.deepBackground);
      final progressSurface = _paint(roles.progressFill, primarySurface);
      expect(
        _contrast(_paint(roles.onFocus, progressSurface), progressSurface),
        greaterThanOrEqualTo(4.5),
        reason: '${name.label} focused control',
      );
      final focusedSurface = _paint(roles.focusedSurface, primarySurface);
      expect(
        _contrast(_paint(roles.focusedText, focusedSurface), focusedSurface),
        greaterThanOrEqualTo(4.5),
        reason: '${name.label} focused surface text',
      );
      expect(
        _contrast(_paint(roles.focusBorder, primarySurface), primarySurface),
        greaterThanOrEqualTo(3),
        reason: '${name.label} focus outline',
      );
      expect(roles.focusBorder, isNot(roles.deepBackground));
      expect(roles.progressTrack, isNot(roles.progressFill));
    }
  });

  test('large focus mode enlarges the shared semantic outline', () {
    final normal = LineupTheme.forName(LineupThemeName.emberSteel)
        .extension<LineupThemeRoles>()!;
    final large = LineupTheme.forName(
      LineupThemeName.emberSteel,
      largeFocusIndicators: true,
    ).extension<LineupThemeRoles>()!;
    expect(large.focusBorderWidth, greaterThan(normal.focusBorderWidth));
  });

  test('equivalent semantic role extensions use value equality', () {
    final first = LineupTheme.forName(LineupThemeName.emberSteel)
        .extension<LineupThemeRoles>()!;
    final second = LineupTheme.forName(LineupThemeName.emberSteel)
        .extension<LineupThemeRoles>()!;
    final changed = second.copyWith(panelRadius: second.panelRadius + 1);

    expect(first, equals(second));
    expect(first.hashCode, second.hashCode);
    expect(first, isNot(equals(changed)));
  });
}

Color _paint(Color foreground, Color background) =>
    Color.alphaBlend(foreground, background);

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
