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
      error: palette.liveAccent,
      onError: palette.onFocus,
      outline: palette.defaultBorder,
      outlineVariant: palette.subtleBorder,
    );
    final textTheme = LineupTypography.textTheme(palette);
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
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
        selectedLabelTextStyle: textTheme.labelMedium!.copyWith(
          color: palette.progressFill,
          fontWeight: FontWeight.w600,
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
      inputDecorationTheme: fieldDecoration(palette),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? palette.selectedSurface
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? palette.mutedText
                : states.contains(WidgetState.selected)
                ? palette.primaryText
                : palette.secondaryText,
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.focused)
                  ? palette.focusBorder
                  : palette.subtleBorder,
              width: states.contains(WidgetState.focused)
                  ? (largeFocusIndicators ? palette.focusBorderWidth : 2)
                  : 1,
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(palette.panelRadius),
            ),
          ),
        ),
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
        selectedColor: palette.selectedSurface,
        secondarySelectedColor: palette.selectedSurface,
        checkmarkColor: palette.primaryText,
        labelStyle: textTheme.labelLarge!.copyWith(color: palette.primaryText),
        secondaryLabelStyle: textTheme.labelLarge!.copyWith(
          color: palette.primaryText,
        ),
        side: BorderSide(color: palette.defaultBorder),
        shape: const StadiumBorder(),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: LineupTypography.control.copyWith(
          color: palette.primaryText,
        ),
        subtitleTextStyle: LineupTypography.body.copyWith(
          color: palette.secondaryText,
        ),
        iconColor: palette.secondaryText,
        textColor: palette.primaryText,
      ),
      iconButtonTheme: IconButtonThemeData(style: iconStyle(palette)),
      filledButtonTheme: FilledButtonThemeData(
        style: buttonStyle(palette, LineupButtonTier.primary),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: buttonStyle(palette, LineupButtonTier.secondary),
      ),
      textButtonTheme: TextButtonThemeData(
        style: buttonStyle(palette, LineupButtonTier.text),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: palette.progressFill,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: palette.subtleBorder,
        labelColor: palette.primaryText,
        unselectedLabelColor: palette.secondaryText,
        labelStyle: LineupTypography.control,
        unselectedLabelStyle: LineupTypography.control,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.elevatedSurface,
        surfaceTintColor: Colors.transparent,
        textStyle: LineupTypography.control.copyWith(
          color: palette.primaryText,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: palette.defaultBorder),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(palette.elevatedSurface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStatePropertyAll(
            BorderSide(color: palette.defaultBorder),
          ),
          shape: WidgetStatePropertyAll(controlShape),
        ),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: buttonStyle(palette, LineupButtonTier.text, compact: true)
            .copyWith(
              shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
              alignment: Alignment.centerLeft,
            ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: LineupTypography.body,
        inputDecorationTheme: fieldDecoration(palette),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(palette.elevatedSurface),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        side: BorderSide(color: palette.defaultBorder, width: 2),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.progressFill
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(palette.onFocus),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : palette.defaultBorder,
        ),
        trackOutlineWidth: const WidgetStatePropertyAll(2),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.progressFill,
        linearTrackColor: palette.progressTrack,
      ),
    );
  }

  static InputDecorationTheme fieldDecoration(
    LineupThemeRoles roles, {
    bool focusVisible = true,
    bool compact = false,
  }) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecorationTheme(
      filled: true,
      fillColor: roles.onFocus,
      floatingLabelBehavior: FloatingLabelBehavior.never,
      constraints: BoxConstraints(minHeight: compact ? 44 : 56),
      contentPadding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 18,
        vertical: compact ? 10 : 16,
      ),
      hintStyle: LineupTypography.body.copyWith(color: roles.mutedText),
      labelStyle: LineupTypography.fieldLabel.copyWith(
        color: roles.secondaryText,
      ),
      border: border(roles.defaultBorder),
      enabledBorder: border(roles.defaultBorder),
      disabledBorder: border(roles.defaultBorder.withValues(alpha: .5)),
      focusedBorder: border(
        focusVisible ? roles.focusBorder : roles.defaultBorder,
        focusVisible ? roles.focusBorderWidth : 1,
      ),
      errorBorder: border(roles.liveAccent),
      focusedErrorBorder: border(
        roles.liveAccent,
        focusVisible ? roles.focusBorderWidth : 1,
      ),
      errorStyle: LineupTypography.small.copyWith(color: roles.liveAccent),
      errorMaxLines: 3,
    );
  }

  static ButtonStyle buttonStyle(
    LineupThemeRoles roles,
    LineupButtonTier tier, {
    bool compact = false,
    bool focusVisible = true,
  }) {
    final filled =
        tier == LineupButtonTier.primary ||
        tier == LineupButtonTier.destructive;
    final accent = tier == LineupButtonTier.destructive
        ? roles.liveAccent
        : roles.progressFill;
    return ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, compact ? 44 : 56)),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: compact ? 20 : 28),
      ),
      textStyle: WidgetStatePropertyAll(
        LineupTypography.button.copyWith(fontSize: compact ? 16 : 18),
      ),
      iconSize: const WidgetStatePropertyAll(20),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(compact ? 6 : 8),
        ),
      ),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        final disabled = states.contains(WidgetState.disabled);
        if (filled) {
          return disabled
              ? accent.withValues(alpha: .22)
              : states.contains(WidgetState.hovered)
              ? Color.lerp(accent, roles.primaryText, .18)
              : accent;
        }
        return states.contains(WidgetState.hovered)
            ? roles.primaryText.withValues(alpha: .08)
            : Colors.transparent;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return (filled ? accent : roles.secondaryText).withValues(alpha: .45);
        }
        if (filled) return roles.onFocus;
        if (tier == LineupButtonTier.link) return roles.progressFill;
        return tier == LineupButtonTier.secondary ||
                states.contains(WidgetState.hovered)
            ? roles.primaryText
            : roles.secondaryText;
      }),
      side: WidgetStateProperty.resolveWith((states) {
        if (focusVisible && states.contains(WidgetState.focused)) {
          return BorderSide(
            color: roles.focusBorder,
            width: roles.focusBorderWidth,
          );
        }
        if (tier == LineupButtonTier.secondary) {
          return BorderSide(
            color: roles.defaultBorder.withValues(
              alpha: states.contains(WidgetState.disabled) ? .5 : 1,
            ),
          );
        }
        return BorderSide.none;
      }),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    );
  }

  static ButtonStyle iconStyle(
    LineupThemeRoles roles, {
    bool focusVisible = true,
  }) =>
      buttonStyle(
        roles,
        LineupButtonTier.text,
        compact: true,
        focusVisible: focusVisible,
      ).copyWith(
        minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(10)),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? roles.secondaryText.withValues(alpha: .3)
              : roles.secondaryText,
        ),
      );

  static LineupThemeRoles _palette(LineupThemeName name) => switch (name) {
    LineupThemeName.emberSteel => const LineupThemeRoles(
      deepBackground: Color(0xFF090806),
      primarySurface: Color(0xFF12100D),
      elevatedSurface: Color(0xFF1A1712),
      overlaySurface: Color(0xF20A0907),
      focusedSurface: Color(0x33F0D39A),
      selectedSurface: Color(0xFF2B2419),
      tunedSurface: Color(0xFF3B3020),
      liveAccent: Color(0xFFFF7768),
      primaryText: Color(0xFFF3E8D2),
      secondaryText: Color(0xFFC7B99F),
      mutedText: Color(0xFF978B76),
      onFocus: Color(0xFF060504),
      focusedText: Color(0xFFF3E8D2),
      subtleBorder: Color(0xFF2B261E),
      defaultBorder: Color(0xFF494031),
      focusBorder: Color(0xFFF0D39A),
      focusBorderWidth: 3,
      progressTrack: Color(0xFF2B261E),
      progressFill: Color(0xFFCC9F5B),
      scrim: Color(0xF20A0907),
      panelRadius: 8,
      overlaySafeArea: 16,
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
      focusBorder: const Color(0xFFA8C49E),
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
      focusBorder: const Color(0xFFFFCC00),
      onFocus: Colors.black,
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
    final focusColor = focus ?? primary.withValues(alpha: 0.32);
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
      focusBorder: focusBorder ?? const Color(0xFFF0D39A),
      focusBorderWidth: 3,
      progressTrack: Colors.white.withValues(alpha: 0.12),
      progressFill: primary,
      scrim: scrim,
      panelRadius: radius,
      overlaySafeArea: 16,
    );
  }
}

enum LineupButtonTier { primary, secondary, text, link, destructive }

/// Canvas-pixel roles. Width variation applies only to Instrument Sans titles.
abstract final class LineupTypography {
  static const body = TextStyle(
    fontFamily: 'Inter',
    fontFeatures: [FontFeature.tabularFigures()],
    fontSize: 18,
    fontWeight: FontWeight.w400,
  );
  static const control = TextStyle(
    fontFamily: 'Inter',
    fontFeatures: [FontFeature.tabularFigures()],
    fontSize: 18,
    fontWeight: FontWeight.w500,
  );
  static const button = TextStyle(
    fontFamily: 'Inter',
    fontFeatures: [FontFeature.tabularFigures()],
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );
  static const small = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: .5,
  );
  static const fieldLabel = TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    fontWeight: FontWeight.w500,
  );
  static const time = TextStyle(
    fontFamily: 'Inter',
    fontSize: 18,
    fontWeight: FontWeight.w400,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static TextStyle title(double size, double width, {double? height}) =>
      TextStyle(
        fontFamily: 'Instrument Sans',
        fontFamilyFallback: const ['Inter'],
        fontSize: size,
        fontWeight: FontWeight.w600,
        fontVariations: [FontVariation('wdth', width)],
        letterSpacing: -size * .01,
        height: height,
      );
  static final programTitle = title(54, 88, height: 1.04);
  static final pageTitle = title(44, 92, height: 1.08);
  static final guideTitle = title(22, 90, height: 1.1);
  static final osdTitle = title(38, 90);
  static TextTheme textTheme(LineupThemeRoles roles) => TextTheme(
    displayLarge: programTitle,
    displayMedium: programTitle,
    displaySmall: osdTitle,
    headlineLarge: pageTitle,
    headlineMedium: pageTitle,
    headlineSmall: pageTitle,
    titleLarge: title(24, 92),
    titleMedium: control,
    titleSmall: fieldLabel,
    bodyLarge: body,
    bodyMedium: body,
    bodySmall: body.copyWith(color: roles.secondaryText),
    labelLarge: button,
    labelMedium: control,
    labelSmall: small,
  ).apply(bodyColor: roles.primaryText, displayColor: roles.primaryText);
}
