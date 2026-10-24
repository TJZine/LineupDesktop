import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'lineup_focus.dart';
import 'app_theme.dart';

/// The single design-canvas owner, above the Navigator and all its overlays.
/// Layout and MediaQuery use canvas pixels; painting and input use window pixels.
class LineupCanvas extends StatelessWidget {
  const LineupCanvas({
    required this.child,
    this.reduceMotion = false,
    super.key,
  });

  final Widget child;
  final bool reduceMotion;

  static double scaleFor(Size window, {bool androidTv = false}) => androidTv
      ? math.min(window.width / 1440, window.height / 810)
      : math.max(0.8, math.min(window.width / 1920, window.height / 1080));

  static EdgeInsets contentInsets(
    BuildContext context, {
    EdgeInsets minimum = EdgeInsets.zero,
  }) => _maximumInsets(MediaQuery.paddingOf(context), minimum);

  static EdgeInsets _maximumInsets(EdgeInsets a, EdgeInsets b) =>
      EdgeInsets.fromLTRB(
        math.max(a.left, b.left),
        math.max(a.top, b.top),
        math.max(a.right, b.right),
        math.max(a.bottom, b.bottom),
      );

  /// Original canvas safe margin for background paint that extends beyond a
  /// SafeArea. Content still uses MediaQuery.padding, which SafeArea consumes.
  static EdgeInsets fullSafeInsetsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CanvasSafeInsets>()?.insets ??
      MediaQuery.paddingOf(context);

  static Widget builder(BuildContext context, Widget? child) =>
      LineupCanvas(child: child ?? const SizedBox.shrink());

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final androidTv = LineupTheme.of(context).androidTv;
    return LayoutBuilder(
      builder: (context, constraints) {
        final window = constraints.biggest;
        if (window.isEmpty || !window.isFinite) return const SizedBox.shrink();
        final scale = scaleFor(window, androidTv: androidTv);
        final canvas = window / scale;
        final padding = androidTv
            ? _maximumInsets(
                media.padding,
                EdgeInsets.symmetric(
                  horizontal: window.width * .05,
                  vertical: window.height * .05,
                ),
              )
            : media.padding;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: canvas.width,
            maxWidth: canvas.width,
            minHeight: canvas.height,
            maxHeight: canvas.height,
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topLeft,
              child: MediaQuery(
                data: media.copyWith(
                  size: canvas,
                  padding: padding / scale,
                  viewPadding: media.viewPadding / scale,
                  viewInsets: media.viewInsets / scale,
                  systemGestureInsets: media.systemGestureInsets / scale,
                  disableAnimations: media.disableAnimations || reduceMotion,
                ),
                child: _CanvasSafeInsets(
                  insets: padding / scale,
                  child: LineupFocusScope(child: child),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CanvasSafeInsets extends InheritedWidget {
  const _CanvasSafeInsets({required this.insets, required super.child});
  final EdgeInsets insets;

  @override
  bool updateShouldNotify(_CanvasSafeInsets oldWidget) =>
      insets != oldWidget.insets;
}
