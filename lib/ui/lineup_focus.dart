import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';

export 'focus_ink.dart';

/// D14 aliases belong to Android TV. Keep the platform policy shared by
/// command routing and focus modality so desktop Application/Menu and remote
/// keys retain their existing behavior.
LogicalKeyboardKey? androidTvKeyAlias(LogicalKeyboardKey key) {
  if (defaultTargetPlatform != TargetPlatform.android) return null;
  return switch (key) {
    LogicalKeyboardKey.channelUp => LogicalKeyboardKey.pageUp,
    LogicalKeyboardKey.channelDown => LogicalKeyboardKey.pageDown,
    LogicalKeyboardKey.guide => LogicalKeyboardKey.f2,
    LogicalKeyboardKey.info ||
    LogicalKeyboardKey.contextMenu => LogicalKeyboardKey.keyI,
    _ => null,
  };
}

/// Paint modality is separate from focus ownership. Pointer input never unfocuses.
///
/// This scope shows rings for navigation keys only. Player and shell separately
/// observe every key-down/repeat for focus restoration and overlay timeout policy.
/// Their resets are intentional (b86693d9): Player hover returns to pointer mode
/// and calls handlePointerActivity independently; shell pointer-down returns to
/// pointer mode. Do not substitute ring visibility for actual input modality.
class LineupFocusScope extends StatefulWidget {
  const LineupFocusScope({required this.child, super.key});
  final Widget child;

  static bool visible(BuildContext context, [bool focused = true]) =>
      focused && (_FocusVisibility.maybeOf(context)?.visible ?? true);

  @override
  State<LineupFocusScope> createState() => _LineupFocusScopeState();
}

class _LineupFocusScopeState extends State<LineupFocusScope> {
  bool _visible = false;
  bool _initialized = false;
  static final _navigationKeys = {
    LogicalKeyboardKey.tab,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.home,
    LogicalKeyboardKey.end,
    LogicalKeyboardKey.pageUp,
    LogicalKeyboardKey.pageDown,
    LogicalKeyboardKey.select,
  };

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _visible = LineupTheme.of(context).androidTv;
      _initialized = true;
    }
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyUpEvent &&
        (_navigationKeys.contains(event.logicalKey) ||
            androidTvKeyAlias(event.logicalKey) != null)) {
      _setVisible(true);
    }
    return false;
  }

  void _setVisible(bool value) {
    if (mounted && _visible != value) setState(() => _visible = value);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _setVisible(false),
    onPointerMove: (_) => _setVisible(false),
    child: MouseRegion(
      onHover: (_) => _setVisible(false),
      child: _FocusVisibility(
        visible: _visible,
        child: LineupFocusTheme(data: Theme.of(context), child: widget.child),
      ),
    ),
  );
}

/// Applies the current modality to a palette without introducing another
/// keyboard handler or resetting focus when a preview palette changes.
class LineupFocusTheme extends StatelessWidget {
  const LineupFocusTheme({required this.data, required this.child, super.key});
  final ThemeData data;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final visible = LineupFocusScope.visible(context);
    final roles = data.extension<LineupThemeRoles>() ?? LineupTheme.of(context);
    ButtonStyle style(LineupButtonTier tier) =>
        LineupTheme.buttonStyle(roles, tier, focusVisible: visible);
    final segmented = data.segmentedButtonTheme.style?.copyWith(
      side: WidgetStateProperty.resolveWith((states) {
        final focused = visible && states.contains(WidgetState.focused);
        if (!focused) return BorderSide(color: roles.defaultBorder, width: 1);
        if (roles.focusTreatment == LineupFocusTreatment.fill) {
          return roles.largeFocusIndicators
              ? BorderSide(color: roles.focusBorder, width: 3)
              : BorderSide.none;
        }
        return BorderSide(
          color: roles.focusBorder,
          width: roles.focusBorderWidth,
        );
      }),
    );
    return Theme(
      data: data.copyWith(
        focusColor: visible
            ? roles.focusTreatment == LineupFocusTreatment.fill
                  ? Colors.transparent
                  : roles.focusBorder.withValues(alpha: .08)
            : Colors.transparent,
        filledButtonTheme: FilledButtonThemeData(
          style: style(LineupButtonTier.primary),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: style(LineupButtonTier.secondary),
        ),
        textButtonTheme: TextButtonThemeData(
          style: style(LineupButtonTier.text),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: LineupTheme.iconStyle(roles, focusVisible: visible),
        ),
        inputDecorationTheme: LineupTheme.fieldDecoration(
          roles,
          focusVisible: visible,
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(style: segmented),
        menuButtonTheme: MenuButtonThemeData(
          style:
              LineupTheme.buttonStyle(
                roles,
                LineupButtonTier.text,
                compact: true,
                focusVisible: visible,
              ).copyWith(
                shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
                alignment: Alignment.centerLeft,
              ),
        ),
      ),
      child: child,
    );
  }
}

class _FocusVisibility extends InheritedWidget {
  const _FocusVisibility({required this.visible, required super.child});
  final bool visible;
  static _FocusVisibility? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_FocusVisibility>();
  @override
  bool updateShouldNotify(_FocusVisibility oldWidget) =>
      visible != oldWidget.visible;
}
