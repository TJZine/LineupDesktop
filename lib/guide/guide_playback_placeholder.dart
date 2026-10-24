import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/app_theme.dart';

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

  static const _contentPadding = 16.0;
  static const _gap = 8.0;
  static const _messageLines = 3;

  static TextStyle? _titleStyle(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge;
  static TextStyle? _messageStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: LineupTheme.of(context).secondaryText);

  /// A state-independent 16:9 aperture for the complete existing placeholder
  /// contract: either title, three message lines, Retry, and its normal padding.
  /// The 16cu inset also contains the existing 6cu Large Focus clearance.
  static Size minimumSize(BuildContext context) {
    final theme = Theme.of(context);
    final inherited = theme.textTheme.bodyMedium!;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    Size text(String value, TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: inherited.merge(style)),
        textScaler: scaler,
        textDirection: direction,
        maxLines: 1,
      )..layout();
      final size = painter.size;
      painter.dispose();
      return size;
    }

    final idle = text('Choose a channel to watch', _titleStyle(context));
    final unavailable = text('Playback unavailable', _titleStyle(context));
    final messageLine = text(
      'Ag',
      _messageStyle(context),
    ).height.ceilToDouble();
    final button = theme.textButtonTheme.style!;
    final retry = text('Retry', button.textStyle!.resolve({}));
    final minimum = button.minimumSize!.resolve({})!;
    final padding = button.padding!.resolve({})!.resolve(direction);
    final retryHeight = math.max(
      minimum.height,
      retry.height + padding.vertical,
    );
    final height =
        2 * _contentPadding +
        math.max(
          idle.height,
          unavailable.height +
              _gap * 2 +
              _messageLines * messageLine +
              retryHeight,
        );
    final width = math
        .max(
          height * 16 / 9,
          2 * _contentPadding +
              math.max(
                math.max(idle.width, unavailable.width),
                math.max(minimum.width, retry.width + padding.horizontal),
              ),
        )
        .ceilToDouble();
    return Size(width, width * 9 / 16);
  }

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
              padding: const EdgeInsets.all(
                GuidePlaybackPlaceholder._contentPadding,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.unavailable
                        ? 'Playback unavailable'
                        : 'Choose a channel to watch',
                    textAlign: TextAlign.center,
                    style: GuidePlaybackPlaceholder._titleStyle(context),
                  ),
                  if (widget.unavailable && widget.message != null) ...[
                    const SizedBox(height: GuidePlaybackPlaceholder._gap),
                    Text(
                      widget.message!,
                      maxLines: GuidePlaybackPlaceholder._messageLines,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: GuidePlaybackPlaceholder._messageStyle(context),
                    ),
                  ],
                  if (widget.onRetry != null) ...[
                    const SizedBox(height: GuidePlaybackPlaceholder._gap),
                    TextButton(
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
