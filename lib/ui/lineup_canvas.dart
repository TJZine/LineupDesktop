import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'lineup_focus.dart';
import '../platform/device_profile.dart';

enum LineupComposition { wide, handheld }

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

  static LineupComposition compositionFor(
    Size window, {
    FormFactor formFactor = FormFactor.desktop,
  }) =>
      formFactor == FormFactor.handheld &&
          (window.width < 1280 || window.height < 720)
      ? LineupComposition.handheld
      : LineupComposition.wide;

  static LineupComposition compositionOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_CanvasSafeInsets>()
          ?.composition ??
      LineupComposition.wide;

  /// Shared surface rule from UI-A Part 2. This is separate from the
  /// two-class scale policy: short-wide Handheld windows use desktop layouts.
  static bool usesPortraitCompositionFor(
    Size window, {
    FormFactor formFactor = FormFactor.desktop,
  }) =>
      compositionFor(window, formFactor: formFactor) ==
          LineupComposition.handheld &&
      (window.height > window.width ||
          window.width / scaleFor(window, formFactor: formFactor) < 933);

  static bool usesPortraitCompositionOf(BuildContext context) =>
      usesPortraitCompositionFor(
        windowSizeOf(context),
        formFactor: DeviceProfile.of(context).formFactor,
      );

  /// Window dp, before the design-canvas transform. Surface breakpoints must
  /// not accidentally classify a window using its enlarged canvas dimensions.
  static Size windowSizeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CanvasSafeInsets>()?.window ??
      MediaQuery.sizeOf(context);

  /// Minimum canvas extent whose transformed hit region is 48 window dp.
  static double minimumTouchExtentOf(BuildContext context) =>
      DeviceProfile.of(context).isHandheld ? 48 / scaleOf(context) : 0;

  static double scaleFor(
    Size window, {
    FormFactor formFactor = FormFactor.desktop,
  }) =>
      compositionFor(window, formFactor: formFactor) ==
          LineupComposition.handheld
      ? 0.9
      : formFactor == FormFactor.tv
      ? math.min(window.width / 1920, window.height / 1080)
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

  /// Real platform padding for background paint that extends beyond a
  /// SafeArea. Content still uses MediaQuery.padding, which SafeArea consumes.
  static EdgeInsets fullSafeInsetsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CanvasSafeInsets>()?.insets ??
      MediaQuery.paddingOf(context);

  /// Canvas-to-window scale applied by the nearest [LineupCanvas], or 1 when
  /// the subtree is not hosted by one.
  static double scaleOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CanvasSafeInsets>()?.scale ??
      1;

  /// Physical pixels per canvas pixel: the device pixel ratio times the canvas
  /// scale. Decode and transcode sizes use this so artwork matches the pixels
  /// actually painted, not the unscaled canvas.
  static double physicalPixelRatioOf(BuildContext context) =>
      MediaQuery.devicePixelRatioOf(context) * scaleOf(context);

  static Widget builder(BuildContext context, Widget? child) =>
      LineupCanvas(child: child ?? const SizedBox.shrink());

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final formFactor = DeviceProfile.of(context).formFactor;
    return LayoutBuilder(
      builder: (context, constraints) {
        final window = constraints.biggest;
        if (window.isEmpty || !window.isFinite) return const SizedBox.shrink();
        final scale = scaleFor(window, formFactor: formFactor);
        final canvas = window / scale;
        final padding = media.padding;
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
                  scale: scale,
                  window: window,
                  composition: compositionFor(window, formFactor: formFactor),
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
  const _CanvasSafeInsets({
    required this.insets,
    required this.scale,
    required this.window,
    required this.composition,
    required super.child,
  });
  final EdgeInsets insets;
  final double scale;
  final Size window;
  final LineupComposition composition;

  @override
  bool updateShouldNotify(_CanvasSafeInsets oldWidget) =>
      insets != oldWidget.insets ||
      scale != oldWidget.scale ||
      window != oldWidget.window ||
      composition != oldWidget.composition;
}
