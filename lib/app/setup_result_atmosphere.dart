import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Presentation-only motion; completion never waits for the light to settle.
class SetupResultAtmosphere extends StatefulWidget {
  const SetupResultAtmosphere({
    required this.applying,
    required this.failed,
    required this.child,
    super.key,
  });

  final bool applying;
  final bool failed;
  final Widget child;

  @override
  State<SetupResultAtmosphere> createState() => _SetupResultAtmosphereState();
}

class _SetupResultAtmosphereState extends State<SetupResultAtmosphere>
    with SingleTickerProviderStateMixin {
  final _frame = ValueNotifier<(double, double)>((0, 0));
  late final Ticker _ticker = createTicker(_tick);
  Duration? _lastTick;
  bool _reduceMotion = false;
  double _time = 0;
  double _settled = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncMotion();
  }

  @override
  void didUpdateWidget(SetupResultAtmosphere oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.applying != widget.applying) _settled = 0;
    _syncMotion();
  }

  void _syncMotion() {
    if (_reduceMotion) {
      _settled = widget.applying ? 0 : 1;
      _ticker.stop();
      _lastTick = null;
    } else if ((widget.applying || _settled < 1) && !_ticker.isActive) {
      _lastTick = null;
      _ticker.start();
    }
    _frame.value = (_time, _settled);
  }

  void _tick(Duration elapsed) {
    final previous = _lastTick;
    _lastTick = elapsed;
    if (previous == null) return;
    // Hidden or suspended windows resume without jumping across the backdrop.
    final delta = math.min((elapsed - previous).inMicroseconds / 1e6, .05);
    if (widget.applying) {
      _time += delta;
    } else {
      final before = _settled;
      _settled = math.min(1, _settled + delta / 1.3);
      // Integrate the declining speed so position and velocity remain continuous.
      _time += 1.3 / 3 * (math.pow(1 - before, 3) - math.pow(1 - _settled, 3));
    }
    _frame.value = (_time, _settled);
    if (!widget.applying && _settled == 1) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Positioned.fill(
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _LightPainter(_frame, failed: widget.failed),
              ),
            ),
          ),
        ),
      ),
      widget.child,
    ],
  );
}

class _LightPainter extends CustomPainter {
  _LightPainter(this.frame, {required this.failed}) : super(repaint: frame);

  final ValueNotifier<(double, double)> frame;
  final bool failed;

  double _sweep(double time, double duration, double offset) =>
      (1 - math.cos(math.pi * (time + offset) / duration)) / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final (time, settled) = frame.value;
    final fade = Curves.easeOutCubic.transform(settled);
    final opacity = 1 - fade * (failed ? 1 : .62);
    if (opacity == 0) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(0, -size.height * .05);
    final first = _sweep(time, 7.5, 3);
    final second = _sweep(time, 10, 5);
    final third = _sweep(time, 6.7, 2);
    _layer(
      canvas,
      size,
      opacity,
      travel: Offset(-.12 + .24 * first, .08 - .16 * first),
      angle: -14 + 26 * first,
      scale: .92 + .2 * first,
      center: const Offset(.35, .64),
      radii: const Offset(.48, .22),
      colors: const [Color(0xBDBC813C), Color(0x70956032), Color(0x00956032)],
      stops: const [0, .35, .74],
    );
    _layer(
      canvas,
      size,
      opacity,
      travel: Offset(.12 - .24 * second, -.07 + .15 * second),
      angle: 12 - 24 * second,
      scale: 1 + .08 * second,
      center: const Offset(.68, .57),
      radii: const Offset(.35, .24),
      colors: const [Color(0x94EBC786), Color(0x5CBA8757), Color(0x00BA8757)],
      stops: const [0, .35, .74],
    );
    _layer(
      canvas,
      size,
      opacity,
      travel: Offset(-.12 + .24 * third, .08 - .16 * third),
      angle: -14 + 26 * third,
      scale: .92 + .2 * third,
      center: const Offset(.49, .39),
      radii: const Offset(.52, .28),
      colors: const [
        Color(0x00BA8B43),
        Color(0x20BA8B43),
        Color(0x68F5D79A),
        Color(0x38BA8B43),
        Color(0x00BA8B43),
      ],
      stops: const [.45, .53, .60, .69, .84],
    );
    canvas.restore();
    // Keep the header and text legible while light flows through the canvas.
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -.06),
          radius: .72,
          colors: [Color(0x18090806), Color(0x00090806), Color(0xAD090806)],
          stops: [.2, .4, .95],
        ).createShader(bounds),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x80090806), Color(0x00090806), Color(0x40090806)],
          stops: [0, .45, 1],
        ).createShader(bounds),
    );
  }

  void _layer(
    Canvas canvas,
    Size size,
    double opacity, {
    required Offset travel,
    required double angle,
    required double scale,
    required Offset center,
    required Offset radii,
    required List<Color> colors,
    required List<double> stops,
  }) {
    final width = size.width * 1.6;
    final height = size.height * 1.6;
    canvas.save();
    canvas.translate(
      size.width / 2 + travel.dx * width,
      size.height / 2 + travel.dy * height,
    );
    canvas.rotate(angle * math.pi / 180);
    canvas.scale(scale);
    canvas.translate((center.dx - .5) * width, (center.dy - .5) * height);
    canvas.scale(radii.dx * width, radii.dy * height);
    final shader = RadialGradient(
      radius: .5,
      colors: colors
          .map((color) => color.withValues(alpha: color.a * opacity))
          .toList(),
      stops: stops,
    ).createShader(const Rect.fromLTWH(-1, -1, 2, 2));
    canvas.drawCircle(Offset.zero, 1, Paint()..shader = shader);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LightPainter oldDelegate) =>
      oldDelegate.failed != failed || oldDelegate.frame != frame;
}
