import 'package:flutter/material.dart';

import '../ui/app_theme.dart';
import '../ui/app_ui.dart';

/// Keeps the Guide's video region stable when there is no usable picture.
class GuidePlaybackPlaceholder extends StatefulWidget {
  const GuidePlaybackPlaceholder({
    required this.unavailable,
    required this.reduceMotion,
    this.message,
    this.onRetry,
    super.key,
  });

  final bool unavailable;
  final bool reduceMotion;
  final String? message;
  final VoidCallback? onRetry;

  @override
  State<GuidePlaybackPlaceholder> createState() =>
      _GuidePlaybackPlaceholderState();
}

class _GuidePlaybackPlaceholderState extends State<GuidePlaybackPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  @override
  void initState() {
    super.initState();
    _syncMotion();
  }

  @override
  void didUpdateWidget(GuidePlaybackPlaceholder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  void _syncMotion() {
    if (widget.unavailable && !widget.reduceMotion) {
      if (!_motion.isAnimating) _motion.repeat();
    } else {
      _motion.stop();
      _motion.value = 0;
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final size = MediaQuery.sizeOf(context);
    final scale = LineupLayout.scaleFor(size);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final retryStyle = scale > 1 || textScale > 1
        ? TextButton.styleFrom(
            minimumSize: Size(0, 48 * scale),
            padding: EdgeInsets.symmetric(
              horizontal: 12 * scale,
              vertical: 8 * scale,
            ),
          )
        : null;
    return ColoredBox(
      color: roles.deepBackground,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.unavailable)
            ExcludeSemantics(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _motion,
                  builder: (context, child) => CustomPaint(
                    painter: _StaticPainter(
                      frame: (_motion.value * 16).floor(),
                      color: roles.secondaryText,
                    ),
                  ),
                ),
              ),
            ),
          Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16 * scale),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.unavailable
                        ? 'Playback unavailable'
                        : 'Choose a channel to watch',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (widget.unavailable && widget.message != null) ...[
                    SizedBox(height: 8 * scale),
                    Text(
                      widget.message!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: roles.secondaryText),
                    ),
                  ],
                  if (widget.onRetry != null) ...[
                    SizedBox(height: 8 * scale),
                    TextButton(
                      style: retryStyle,
                      onPressed: widget.onRetry,
                      child: const Text('Retry'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaticPainter extends CustomPainter {
  const _StaticPainter({required this.frame, required this.color});

  final int frame;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final cellWidth = size.width / 96;
    final cellHeight = size.height / 54;
    for (var row = 0; row < 54; row++) {
      for (var column = 0; column < 96; column++) {
        var noise = column * 1973 + row * 9277 + frame * 26699;
        noise = (noise ^ (noise >> 13)) * 1274126177;
        noise = (noise ^ (noise >> 16)) & 255;
        paint.color = color.withValues(alpha: 0.025 + noise / 255 * 0.065);
        canvas.drawRect(
          Rect.fromLTWH(
            column * cellWidth,
            row * cellHeight,
            cellWidth + 0.5,
            cellHeight + 0.5,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_StaticPainter oldDelegate) =>
      frame != oldDelegate.frame || color != oldDelegate.color;
}
