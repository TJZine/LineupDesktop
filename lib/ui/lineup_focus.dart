import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';

/// Paint modality is separate from focus ownership. Pointer input never unfocuses.
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

  bool _onKey(KeyEvent event) {
    if (event is! KeyUpEvent && _navigationKeys.contains(event.logicalKey)) {
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
      side: WidgetStateProperty.resolveWith(
        (states) => BorderSide(
          color: visible && states.contains(WidgetState.focused)
              ? roles.focusBorder
              : roles.defaultBorder,
          width: visible && states.contains(WidgetState.focused)
              ? roles.focusBorderWidth
              : 1,
        ),
      ),
    );
    return Theme(
      data: data.copyWith(
        focusColor: visible
            ? roles.focusBorder.withValues(alpha: .08)
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
