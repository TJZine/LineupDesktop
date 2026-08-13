import 'package:flutter/material.dart';

abstract final class LineupTheme {
  static const brass = Color(0xFFC8A064);
  static const obsidian = Color(0xFF0E1017);
  static const smoke = Color(0xFF171A22);
  static const elevated = Color(0xFF20242E);
  static const error = Color(0xFFEF4444);

  static const fast = Duration(milliseconds: 100);

  static const radiusSmall = 8.0;
  static const radius = 12.0;
  static const radiusLarge = 16.0;

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: brass,
      onPrimary: obsidian,
      secondary: Color(0xFF9AA4B2),
      surface: smoke,
      surfaceContainer: elevated,
      error: error,
    );

    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );

    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: obsidian,
      useMaterial3: true,
      focusColor: brass.withValues(alpha: 0.28),
      hoverColor: Colors.white.withValues(alpha: 0.07),
      splashColor: brass.withValues(alpha: 0.12),
      visualDensity: VisualDensity.standard,
      dividerTheme: const DividerThemeData(
        color: Colors.white12,
        thickness: 1,
        space: 1,
      ),
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
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: elevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: brass, width: 2),
        ),
        errorMaxLines: 2,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: smoke,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          side: const BorderSide(color: Colors.white12),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: elevated,
        side: const BorderSide(color: Colors.white12),
        shape: const StadiumBorder(),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: Colors.white70,
        textColor: Colors.white,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(controlShape),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? Colors.white30
                : states.contains(WidgetState.hovered)
                ? brass
                : Colors.white70,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brass,
          foregroundColor: obsidian,
          minimumSize: const Size(148, 54),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          shape: controlShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(148, 54),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          side: BorderSide(color: brass.withValues(alpha: 0.35)),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          shape: controlShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: controlShape),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: brass,
        linearTrackColor: Colors.white12,
      ),
    );
  }
}
