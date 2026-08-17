import 'package:flutter/material.dart';

import '../settings/lineup_settings.dart';

@immutable
class LineupThemeRoles extends ThemeExtension<LineupThemeRoles> {
  const LineupThemeRoles({
    required this.deepBackground,
    required this.primarySurface,
    required this.elevatedSurface,
    required this.overlaySurface,
    required this.focusedSurface,
    required this.selectedSurface,
    required this.tunedSurface,
    required this.liveAccent,
    required this.primaryText,
    required this.secondaryText,
    required this.mutedText,
    required this.onFocus,
    required this.focusedText,
    required this.subtleBorder,
    required this.defaultBorder,
    required this.focusBorder,
    required this.focusBorderWidth,
    required this.progressTrack,
    required this.progressFill,
    required this.scrim,
    required this.panelRadius,
    required this.overlaySafeArea,
  });

  final Color deepBackground;
  final Color primarySurface;
  final Color elevatedSurface;
  final Color overlaySurface;
  final Color focusedSurface;
  final Color selectedSurface;
  final Color tunedSurface;
  final Color liveAccent;
  final Color primaryText;
  final Color secondaryText;
  final Color mutedText;
  final Color onFocus;
  final Color focusedText;
  final Color subtleBorder;
  final Color defaultBorder;
  final Color focusBorder;
  final double focusBorderWidth;
  final Color progressTrack;
  final Color progressFill;
  final Color scrim;
  final double panelRadius;
  final double overlaySafeArea;

  @override
  LineupThemeRoles copyWith({
    Color? deepBackground,
    Color? primarySurface,
    Color? elevatedSurface,
    Color? overlaySurface,
    Color? focusedSurface,
    Color? selectedSurface,
    Color? tunedSurface,
    Color? liveAccent,
    Color? primaryText,
    Color? secondaryText,
    Color? mutedText,
    Color? onFocus,
    Color? focusedText,
    Color? subtleBorder,
    Color? defaultBorder,
    Color? focusBorder,
    double? focusBorderWidth,
    Color? progressTrack,
    Color? progressFill,
    Color? scrim,
    double? panelRadius,
    double? overlaySafeArea,
  }) => LineupThemeRoles(
    deepBackground: deepBackground ?? this.deepBackground,
    primarySurface: primarySurface ?? this.primarySurface,
    elevatedSurface: elevatedSurface ?? this.elevatedSurface,
    overlaySurface: overlaySurface ?? this.overlaySurface,
    focusedSurface: focusedSurface ?? this.focusedSurface,
    selectedSurface: selectedSurface ?? this.selectedSurface,
    tunedSurface: tunedSurface ?? this.tunedSurface,
    liveAccent: liveAccent ?? this.liveAccent,
    primaryText: primaryText ?? this.primaryText,
    secondaryText: secondaryText ?? this.secondaryText,
    mutedText: mutedText ?? this.mutedText,
    onFocus: onFocus ?? this.onFocus,
    focusedText: focusedText ?? this.focusedText,
    subtleBorder: subtleBorder ?? this.subtleBorder,
    defaultBorder: defaultBorder ?? this.defaultBorder,
    focusBorder: focusBorder ?? this.focusBorder,
    focusBorderWidth: focusBorderWidth ?? this.focusBorderWidth,
    progressTrack: progressTrack ?? this.progressTrack,
    progressFill: progressFill ?? this.progressFill,
    scrim: scrim ?? this.scrim,
    panelRadius: panelRadius ?? this.panelRadius,
    overlaySafeArea: overlaySafeArea ?? this.overlaySafeArea,
  );

  @override
  LineupThemeRoles lerp(LineupThemeRoles? other, double t) {
    if (other == null) return this;
    return LineupThemeRoles(
      deepBackground: Color.lerp(deepBackground, other.deepBackground, t)!,
      primarySurface: Color.lerp(primarySurface, other.primarySurface, t)!,
      elevatedSurface: Color.lerp(elevatedSurface, other.elevatedSurface, t)!,
      overlaySurface: Color.lerp(overlaySurface, other.overlaySurface, t)!,
      focusedSurface: Color.lerp(focusedSurface, other.focusedSurface, t)!,
      selectedSurface: Color.lerp(selectedSurface, other.selectedSurface, t)!,
      tunedSurface: Color.lerp(tunedSurface, other.tunedSurface, t)!,
      liveAccent: Color.lerp(liveAccent, other.liveAccent, t)!,
      primaryText: Color.lerp(primaryText, other.primaryText, t)!,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      onFocus: Color.lerp(onFocus, other.onFocus, t)!,
      focusedText: Color.lerp(focusedText, other.focusedText, t)!,
      subtleBorder: Color.lerp(subtleBorder, other.subtleBorder, t)!,
      defaultBorder: Color.lerp(defaultBorder, other.defaultBorder, t)!,
      focusBorder: Color.lerp(focusBorder, other.focusBorder, t)!,
      focusBorderWidth:
          focusBorderWidth + (other.focusBorderWidth - focusBorderWidth) * t,
      progressTrack: Color.lerp(progressTrack, other.progressTrack, t)!,
      progressFill: Color.lerp(progressFill, other.progressFill, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      panelRadius: panelRadius + (other.panelRadius - panelRadius) * t,
      overlaySafeArea:
          overlaySafeArea + (other.overlaySafeArea - overlaySafeArea) * t,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LineupThemeRoles &&
          deepBackground == other.deepBackground &&
          primarySurface == other.primarySurface &&
          elevatedSurface == other.elevatedSurface &&
          overlaySurface == other.overlaySurface &&
          focusedSurface == other.focusedSurface &&
          selectedSurface == other.selectedSurface &&
          tunedSurface == other.tunedSurface &&
          liveAccent == other.liveAccent &&
          primaryText == other.primaryText &&
          secondaryText == other.secondaryText &&
          mutedText == other.mutedText &&
          onFocus == other.onFocus &&
          focusedText == other.focusedText &&
          subtleBorder == other.subtleBorder &&
          defaultBorder == other.defaultBorder &&
          focusBorder == other.focusBorder &&
          focusBorderWidth == other.focusBorderWidth &&
          progressTrack == other.progressTrack &&
          progressFill == other.progressFill &&
          scrim == other.scrim &&
          panelRadius == other.panelRadius &&
          overlaySafeArea == other.overlaySafeArea;

  @override
  int get hashCode => Object.hashAll([
    deepBackground,
    primarySurface,
    elevatedSurface,
    overlaySurface,
    focusedSurface,
    selectedSurface,
    tunedSurface,
    liveAccent,
    primaryText,
    secondaryText,
    mutedText,
    onFocus,
    focusedText,
    subtleBorder,
    defaultBorder,
    focusBorder,
    focusBorderWidth,
    progressTrack,
    progressFill,
    scrim,
    panelRadius,
    overlaySafeArea,
  ]);
}

abstract final class LineupTheme {
  static const fast = Duration(milliseconds: 100);

  static LineupThemeRoles of(BuildContext context) =>
      Theme.of(context).extension<LineupThemeRoles>() ??
      _palette(LineupThemeName.emberSteel);

  static ThemeData forName(
    LineupThemeName name, {
    bool largeFocusIndicators = false,
  }) {
    final palette = _palette(name)
        .copyWith(focusBorderWidth: largeFocusIndicators ? 5 : 3);
    final scheme = ColorScheme.dark(
      primary: palette.progressFill,
      onPrimary: palette.onFocus,
      secondary: palette.secondaryText,
      surface: palette.primarySurface,
      surfaceContainer: palette.elevatedSurface,
      error: const Color(0xFFEF4444),
      onError: Colors.black,
      outline: palette.defaultBorder,
      outlineVariant: palette.subtleBorder,
    );
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(palette.panelRadius),
    );
    final textTheme = ThemeData.dark().textTheme.apply(
      bodyColor: palette.primaryText,
      displayColor: palette.primaryText,
    );

    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.deepBackground,
      textTheme: textTheme,
      useMaterial3: true,
      extensions: [palette],
      focusColor: palette.focusedSurface,
      hoverColor: palette.primaryText.withValues(alpha: 0.08),
      splashColor: palette.progressFill.withValues(alpha: 0.12),
      visualDensity: VisualDensity.standard,
      dividerTheme: DividerThemeData(
        color: palette.subtleBorder,
        thickness: 1,
        space: 1,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: palette.deepBackground,
        indicatorColor: palette.selectedSurface,
        selectedIconTheme: IconThemeData(color: palette.progressFill),
        selectedLabelTextStyle: TextStyle(
          color: palette.progressFill,
          fontWeight: FontWeight.w700,
        ),
        useIndicator: true,
      ),
      cardTheme: CardThemeData(
        color: palette.primarySurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(palette.panelRadius),
          side: BorderSide(color: palette.subtleBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.elevatedSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(palette.panelRadius),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(palette.panelRadius),
          borderSide: BorderSide(
            color: palette.focusBorder,
            width: palette.focusBorderWidth,
          ),
        ),
        errorMaxLines: 2,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.overlaySurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(palette.panelRadius),
          side: BorderSide(color: palette.defaultBorder),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.elevatedSurface,
        side: BorderSide(color: palette.defaultBorder),
        shape: const StadiumBorder(),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: palette.secondaryText,
        textColor: palette.primaryText,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(controlShape),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? palette.mutedText
                : states.contains(WidgetState.focused)
                ? palette.focusBorder
                : states.contains(WidgetState.hovered)
                ? palette.progressFill
                : palette.secondaryText,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.progressFill,
          foregroundColor: palette.onFocus,
          minimumSize: const Size(148, 54),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: textTheme.labelLarge?.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
          shape: controlShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(148, 54),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          side: BorderSide(color: palette.defaultBorder),
          textStyle: textTheme.labelLarge?.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
          shape: controlShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: controlShape),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.progressFill,
        linearTrackColor: palette.progressTrack,
      ),
    );
  }

  static LineupThemeRoles _palette(LineupThemeName name) => switch (name) {
    LineupThemeName.emberSteel => _roles(
      deep: const Color(0xFF141414),
      surface: const Color(0xEB181818),
      elevated: const Color(0xF0202020),
      overlay: const Color(0xDB101010),
      primary: const Color(0xFFE0782A),
      tuned: const Color(0xFF7C4930),
      live: const Color(0xFFE85D4A),
      radius: 4,
      scrim: const Color(0xD9141414),
    ),
    LineupThemeName.slatePine => _roles(
      deep: const Color(0xFF161917),
      surface: const Color(0xEB1A1D1B),
      elevated: const Color(0xF0222623),
      overlay: const Color(0xDB121413),
      primary: const Color(0xFF809A79),
      tuned: const Color(0xFF405B46),
      live: const Color(0xFFFF4444),
      radius: 8,
      scrim: const Color(0xDB161816),
    ),
    LineupThemeName.swiss => _roles(
      deep: const Color(0xFF020202),
      surface: const Color(0xF20A0A0A),
      elevated: const Color(0xFA121212),
      overlay: const Color(0xE6000000),
      primary: const Color(0xFF34D399),
      tuned: const Color(0xFF164E3C),
      live: const Color(0xFFFF4444),
      radius: 0,
      scrim: const Color(0xE6000000),
    ),
    LineupThemeName.directv => _roles(
      deep: const Color(0xFF001020),
      surface: const Color(0xF0002040),
      elevated: const Color(0xF5002A52),
      overlay: const Color(0xE6001224),
      primary: const Color(0xFF00A6D6),
      tuned: const Color(0xFF00437F),
      live: const Color(0xFFFF4444),
      radius: 2,
      scrim: const Color(0xE3001830),
      focus: const Color(0xFFFFCC00),
      focusBorder: const Color(0xFFE5A00D),
      onFocus: Colors.black,
    ),
    LineupThemeName.glass => _roles(
      deep: const Color(0xFF05080B),
      surface: const Color(0xB8090C10),
      elevated: const Color(0xD10C1015),
      overlay: const Color(0xC7040609),
      primary: const Color(0xFF00E5FF),
      tuned: const Color(0xFF123D46),
      live: const Color(0xFFFF4444),
      radius: 16,
      scrim: const Color(0xE3080B0F),
    ),
  };

  static LineupThemeRoles _roles({
    required Color deep,
    required Color surface,
    required Color elevated,
    required Color overlay,
    required Color primary,
    required Color tuned,
    required Color live,
    required double radius,
    required Color scrim,
    Color? focus,
    Color? focusBorder,
    Color onFocus = const Color(0xFF0A0D12),
  }) {
    final focusColor = focus ?? primary.withValues(alpha: 0.20);
    return LineupThemeRoles(
      deepBackground: deep,
      primarySurface: surface,
      elevatedSurface: elevated,
      overlaySurface: overlay,
      focusedSurface: focusColor,
      selectedSurface: primary.withValues(alpha: 0.20),
      tunedSurface: tuned,
      liveAccent: live,
      primaryText: Colors.white,
      secondaryText: Colors.white.withValues(alpha: 0.70),
      mutedText: Colors.white.withValues(alpha: 0.50),
      onFocus: onFocus,
      focusedText: focus == null ? Colors.white : onFocus,
      subtleBorder: Colors.white.withValues(alpha: 0.08),
      defaultBorder: Colors.white.withValues(alpha: 0.12),
      focusBorder: focusBorder ?? primary,
      focusBorderWidth: 3,
      progressTrack: Colors.white.withValues(alpha: 0.12),
      progressFill: primary,
      scrim: scrim,
      panelRadius: radius,
      overlaySafeArea: 16,
    );
  }
}
