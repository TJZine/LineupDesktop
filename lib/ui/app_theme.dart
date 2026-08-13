import 'package:flutter/material.dart';

abstract final class LineupTheme {
  static const brass = Color(0xFFC8A064);
  static const obsidian = Color(0xFF0E1017);
  static const smoke = Color(0xFF171A22);

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: brass,
      brightness: Brightness.dark,
      surface: smoke,
    );

    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: obsidian,
      useMaterial3: true,
      focusColor: brass.withValues(alpha: 0.28),
      visualDensity: VisualDensity.standard,
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: obsidian,
        indicatorColor: brass.withValues(alpha: 0.18),
        selectedIconTheme: const IconThemeData(color: brass),
        selectedLabelTextStyle: const TextStyle(
          color: brass,
          fontWeight: FontWeight.w700,
        ),
        useIndicator: true,
      ),
      cardTheme: CardThemeData(
        color: smoke,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brass,
          foregroundColor: obsidian,
          minimumSize: const Size(148, 54),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(148, 54),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          side: BorderSide(color: brass.withValues(alpha: 0.35)),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
