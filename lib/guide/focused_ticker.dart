import 'dart:async';

import 'package:flutter/material.dart';

/// Shows a single line of text and gently reveals focused overflow.
class FocusedTicker extends StatefulWidget {
  const FocusedTicker({
    required this.text,
    required this.focused,
    this.reduceMotion = false,
    this.style,
    super.key,
  });

  final String text;
  final bool focused;
  final bool reduceMotion;
  final TextStyle? style;

  @override
  State<FocusedTicker> createState() => _FocusedTickerState();
}

class _FocusedTickerState extends State<FocusedTicker>
    with SingleTickerProviderStateMixin {
  static const _startDelay = Duration(milliseconds: 900);
  static const _endPause = Duration(milliseconds: 600);
  static const _pixelsPerSecond = 34.0;

  late final AnimationController _animationController = AnimationController(
    vsync: this,
  );
  Timer? _phaseTimer;
  _TickerConfiguration? _requestedConfiguration;
  _TickerConfiguration? _activeConfiguration;
  int _generation = 0;

  @override
  void dispose() {
    _phaseTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final style = widget.style ?? DefaultTextStyle.of(context).style;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth ? constraints.maxWidth : null;
        final textSize = _measureText(textDirection, textScaler, style);
        final textWidth = textSize.width;
        final overflow = width != null && textWidth > width;
        final configuration = (
          text: widget.text,
          width: width,
          textWidth: textWidth,
          textDirection: textDirection,
          textScaler: textScaler,
          style: style,
          canAnimate: widget.focused && !widget.reduceMotion && overflow,
        );
        _synchronize(configuration);

        final text = Text(
          widget.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: widget.style,
        );
        if (width == null || width <= 0) return text;
        if (_activeConfiguration != configuration) {
          return SizedBox(width: width, child: text);
        }

        final scrollingText = SizedBox(
          width: textWidth,
          height: textSize.height,
          child: Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.clip,
            softWrap: false,
            style: widget.style,
          ),
        );
        return ClipRect(
          child: SizedBox(
            width: width,
            height: textSize.height,
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: width,
              maxWidth: double.infinity,
              minHeight: textSize.height,
              maxHeight: textSize.height,
              child: AnimatedBuilder(
                animation: _animationController,
                child: scrollingText,
                builder: (context, child) {
                  final distance = configuration.textWidth - width;
                  return Transform.translate(
                    offset: Offset(-_offset(distance), 0),
                    child: child,
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Size _measureText(
    TextDirection textDirection,
    TextScaler textScaler,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 1,
    );
    try {
      painter.layout();
      return painter.size;
    } finally {
      painter.dispose();
    }
  }

  double _offset(double distance) => distance * _animationController.value;

  void _synchronize(_TickerConfiguration configuration) {
    if (_requestedConfiguration == configuration) return;
    _requestedConfiguration = configuration;
    _generation++;
    _phaseTimer?.cancel();
    _animationController.stop(canceled: true);
    _animationController.value = 0;
    _activeConfiguration = null;
    if (!configuration.canAnimate) return;

    final generation = _generation;
    final scrollDuration = Duration(
      milliseconds:
          ((configuration.textWidth - configuration.width!) /
                  _pixelsPerSecond *
                  1000)
              .ceil(),
    );
    _animationController.duration = scrollDuration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      _activeConfiguration = configuration;
      setState(() {});
      _scheduleScroll(generation);
    });
  }

  void _scheduleScroll(int generation) {
    _phaseTimer = Timer(_startDelay, () {
      if (!mounted || generation != _generation) return;
      unawaited(_runScroll(generation));
    });
  }

  Future<void> _runScroll(int generation) async {
    try {
      await _animationController.forward(from: 0).orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted || generation != _generation) return;
    _phaseTimer = Timer(_endPause, () {
      if (!mounted || generation != _generation) return;
      _animationController.value = 0;
      _scheduleScroll(generation);
    });
  }
}

typedef _TickerConfiguration = ({
  String text,
  double? width,
  double textWidth,
  TextDirection textDirection,
  TextScaler textScaler,
  TextStyle style,
  bool canAnimate,
});
