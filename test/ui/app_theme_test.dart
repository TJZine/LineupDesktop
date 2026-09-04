import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/ui/app_theme.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';

void main() {
  test('theme inventory starts with the approved Lineup identity', () {
    expect(LineupThemeName.values.map((theme) => theme.label), [
      'Ember & Steel',
      'Slate & Pine',
      'Swiss Minimal',
      'DirecTV Classic',
      'Glassmorphism',
    ]);
  });

  test('Ember & Steel exposes the approved semantic palette', () {
    final roles = LineupTheme.forName(LineupThemeName.emberSteel)
        .extension<LineupThemeRoles>()!;

    expect(roles.deepBackground, const Color(0xFF090806));
    expect(roles.primarySurface, const Color(0xFF12100D));
    expect(roles.elevatedSurface, const Color(0xFF1A1712));
    expect(roles.overlaySurface, const Color(0xF20A0907));
    expect(roles.selectedSurface, const Color(0xFF2B2419));
    expect(roles.tunedSurface, const Color(0xFF3B3020));
    expect(roles.progressFill, const Color(0xFFCC9F5B));
    expect(roles.focusBorder, const Color(0xFFF0D39A));
    expect(roles.liveAccent, const Color(0xFFFF7768));
    expect(roles.primaryText, const Color(0xFFF3E8D2));
    expect(roles.secondaryText, const Color(0xFFC7B99F));
    expect(roles.mutedText, const Color(0xFF978B76));
    expect(roles.subtleBorder, const Color(0xFF2B261E));
    expect(roles.defaultBorder, const Color(0xFF494031));
    expect(roles.panelRadius, 8);
  });

  test('every theme supplies usable semantic text and focus contrast', () {
    for (final name in LineupThemeName.values) {
      final theme = LineupTheme.forName(name);
      final roles = theme.extension<LineupThemeRoles>()!;
      final base = _paint(roles.deepBackground, Colors.black);
      for (final surface in [
        roles.deepBackground,
        roles.primarySurface,
        roles.elevatedSurface,
        roles.overlaySurface,
      ]) {
        final paintedSurface = _paint(surface, base);
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
      final primarySurface = _paint(roles.primarySurface, base);
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
      expect(roles.focusedSurface, isNot(roles.selectedSurface));
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

  test('navigation selection preserves the application label typography', () {
    for (final name in LineupThemeName.values) {
      final theme = LineupTheme.forName(name);
      final selected = theme.navigationRailTheme.selectedLabelTextStyle!;

      expect(selected.fontFamily, theme.textTheme.labelMedium!.fontFamily);
      expect(selected.color, theme.extension<LineupThemeRoles>()!.progressFill);
      expect(selected.fontWeight, FontWeight.w700);
    }
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
