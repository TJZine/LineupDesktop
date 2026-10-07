import 'dart:math' as math;

import 'package:flutter/material.dart';

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

  static double scaleFor(Size window) =>
      math.max(0.8, math.min(window.width / 1920, window.height / 1080));

  static Widget builder(BuildContext context, Widget? child) =>
      LineupCanvas(child: child ?? const SizedBox.shrink());

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final window = constraints.biggest;
        final scale = scaleFor(window);
        final canvas = window / scale;
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
                  padding: media.padding / scale,
                  viewPadding: media.viewPadding / scale,
                  viewInsets: media.viewInsets / scale,
                  systemGestureInsets: media.systemGestureInsets / scale,
                  disableAnimations: media.disableAnimations || reduceMotion,
                ),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
