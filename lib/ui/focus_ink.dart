import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Keeps the focus-ink scope in the same place for both focus states.
///
/// The scope is intentionally data-driven: focused widgets keep their element
/// identity while the semantic roles and inherited text/icon defaults change.
class LineupFocusInk extends StatelessWidget {
  const LineupFocusInk({required this.focused, required this.child, super.key});

  final bool focused;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final data = Theme.of(context);
    final roles = LineupTheme.of(context);
    final active = focused && roles.focusTreatment == LineupFocusTreatment.fill;
    if (roles.focusTreatment != LineupFocusTreatment.fill) {
      return child ?? const SizedBox.shrink();
    }
    final inkRoles = active
        ? roles.copyWith(
            deepBackground: roles.focusedInsetSurface,
            primarySurface: roles.focusedInsetSurface,
            elevatedSurface: roles.focusedInsetSurface,
            overlaySurface: roles.focusedInsetSurface,
            selectedSurface: roles.focusedInsetSurface,
            tunedSurface: roles.focusedInsetSurface,
            primaryText: roles.onFocus,
            secondaryText: roles.focusSecondaryText,
            mutedText: roles.focusMutedText,
            focusedText: roles.onFocus,
            focusedSurface: roles.focusedInsetSurface,
          )
        : roles;
    final extensions = [
      for (final extension in data.extensions.values)
        if (extension is! LineupThemeRoles) extension,
      inkRoles,
    ];
    return Theme(
      data: data.copyWith(
        extensions: extensions,
        // Material and ListTile install their own text defaults below this
        // scope. Carry the same ink through those owners, not just Text's
        // inherited DefaultTextStyle. Unfocused and desktop themes stay exact.
        textTheme: active
            ? data.textTheme.apply(
                bodyColor: inkRoles.primaryText,
                displayColor: inkRoles.primaryText,
              )
            : data.textTheme,
        listTileTheme: active
            ? data.listTileTheme.copyWith(
                textColor: inkRoles.primaryText,
                iconColor: inkRoles.secondaryText,
                titleTextStyle: data.listTileTheme.titleTextStyle?.copyWith(
                  color: inkRoles.primaryText,
                ),
                subtitleTextStyle: data.listTileTheme.subtitleTextStyle
                    ?.copyWith(color: inkRoles.secondaryText),
              )
            : data.listTileTheme,
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: inkRoles.primaryText),
        child: IconTheme.merge(
          data: IconThemeData(color: inkRoles.primaryText),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// Paints the accessibility exception for large TV focus indicators without
/// changing layout. Ordinary TV focus has no outline.
class LineupFocusFrame extends StatelessWidget {
  static const strokeWidth = 3.0;
  /// Edge-to-edge clipped content reserves the two inward paint strokes.
  static const contentClearance = strokeWidth * 2;

  const LineupFocusFrame({
    required this.focused,
    required this.child,
    super.key,
  });

  final bool focused;
  final Widget? child;

  /// Header-only counterpart for controls whose Material owns a ShapeBorder
  /// but exposes no header builder. Zero insets preserve the existing layout.
  /// A null result leaves the caller's ordinary shape untouched.
  static ShapeBorder? shape(BuildContext context, {required bool focused}) {
    final roles = LineupTheme.of(context);
    if (!focused ||
        roles.focusTreatment != LineupFocusTreatment.fill ||
        !roles.largeFocusIndicators) {
      return null;
    }
    return _LargeFocusShape(
      color: roles.focusBorder,
      innerColor: roles.onFocus,
      radius: roles.panelRadius,
    );
  }

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final active =
        focused &&
        roles.focusTreatment == LineupFocusTreatment.fill &&
        roles.largeFocusIndicators;
    if (roles.focusTreatment != LineupFocusTreatment.fill) {
      return child ?? const SizedBox.shrink();
    }
    // Keep the TV subtree stable when the accessibility setting changes. Its
    // stateful child can own focus even while the frame has no painter.
    return CustomPaint(
      foregroundPainter: active
          ? _LargeFocusPainter(
              color: roles.focusBorder,
              innerColor: roles.onFocus,
              radius: roles.panelRadius,
            )
          : null,
      child: child,
    );
  }
}

class _LargeFocusPainter extends CustomPainter {
  const _LargeFocusPainter({
    required this.color,
    required this.innerColor,
    required this.radius,
  });

  final Color color;
  final Color innerColor;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) => _paintLargeFocus(
    canvas,
    Offset.zero & size,
    color: color,
    innerColor: innerColor,
    radius: radius,
  );

  @override
  bool shouldRepaint(_LargeFocusPainter oldDelegate) =>
      color != oldDelegate.color ||
      innerColor != oldDelegate.innerColor ||
      radius != oldDelegate.radius;
}

class _LargeFocusShape extends ShapeBorder {
  const _LargeFocusShape({
    required this.color,
    required this.innerColor,
    required this.radius,
    this.strokeWidth = LineupFocusFrame.strokeWidth,
  });
  final Color color;
  final Color innerColor;
  final double radius;
  final double strokeWidth;
  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);
  @override
  ShapeBorder scale(double t) => _LargeFocusShape(
    color: color,
    innerColor: innerColor,
    radius: radius * t.clamp(0.0, double.infinity),
    strokeWidth: strokeWidth * t.clamp(0.0, double.infinity),
  );
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) =>
      _paintLargeFocus(
        canvas,
        rect,
        color: color,
        innerColor: innerColor,
        radius: radius,
        strokeWidth: strokeWidth,
      );
}

void _paintLargeFocus(
  Canvas canvas,
  Rect bounds, {
  required Color color,
  required Color innerColor,
  required double radius,
  double strokeWidth = LineupFocusFrame.strokeWidth,
}) {
  if (strokeWidth <= 0) return;
  final stroke = strokeWidth;
  final outer = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = stroke;
  final inner = Paint()
    ..color = innerColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = stroke;
  final outerRadius = Radius.circular((radius + stroke).clamp(0, 999));
  final innerRadius = Radius.circular((radius - stroke).clamp(0, 999));
  canvas.drawRRect(
    RRect.fromRectAndRadius(bounds.deflate(stroke / 2), outerRadius),
    outer,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(bounds.deflate(stroke * 1.5), innerRadius),
    inner,
  );
}
