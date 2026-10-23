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
      data: data.copyWith(extensions: extensions),
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
  const LineupFocusFrame({
    required this.focused,
    required this.child,
    super.key,
  });

  final bool focused;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final active =
        focused &&
        roles.focusTreatment == LineupFocusTreatment.fill &&
        roles.largeFocusIndicators;
    if (roles.focusTreatment != LineupFocusTreatment.fill ||
        !roles.largeFocusIndicators) {
      return child ?? const SizedBox.shrink();
    }
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
  void paint(Canvas canvas, Size size) {
    const stroke = 3.0;
    final bounds = Offset.zero & size;
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

  @override
  bool shouldRepaint(_LargeFocusPainter oldDelegate) =>
      color != oldDelegate.color ||
      innerColor != oldDelegate.innerColor ||
      radius != oldDelegate.radius;
}
