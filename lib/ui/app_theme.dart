import 'package:flutter/material.dart';

abstract final class LineupTheme {
  static const _gold = Color(0xFFF5B84B);
  static const _surface = Color(0xFF17191D);
  static const _background = Color(0xFF0E0F12);

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: _gold,
      brightness: Brightness.dark,
      surface: _surface,
    );

    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: _background,
      useMaterial3: true,
      focusColor: _gold.withValues(alpha: 0.28),
      visualDensity: VisualDensity.standard,
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: _background,
        indicatorColor: _gold.withValues(alpha: 0.18),
        selectedIconTheme: const IconThemeData(color: _gold),
        selectedLabelTextStyle: const TextStyle(
          color: _gold,
          fontWeight: FontWeight.w700,
        ),
        useIndicator: true,
      ),
      cardTheme: CardThemeData(
        color: _surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );
  }
}
