import 'dart:async';

import 'package:flutter/material.dart';

import 'native_player.dart';

class NativeVideoSurface extends StatefulWidget {
  const NativeVideoSurface({
    required this.player,
    this.presentationEpoch = 0,
    super.key,
  });

  final NativePlayer player;
  final int presentationEpoch;

  @override
  State<NativeVideoSurface> createState() => _NativeVideoSurfaceState();
}

class _NativeVideoSurfaceState extends State<NativeVideoSurface>
    with WidgetsBindingObserver {
  PlayerVideoRect? _lastRect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleBoundsUpdate();
  }

  @override
  void didUpdateWidget(NativeVideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.player, widget.player) ||
        oldWidget.presentationEpoch != widget.presentationEpoch) {
      _lastRect = null;
    }
    _scheduleBoundsUpdate();
  }

  @override
  void didChangeMetrics() => _scheduleBoundsUpdate();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(
      widget.player
          .setVideoRect(
            const PlayerVideoRect(
              left: 0,
              top: 0,
              width: 0,
              height: 0,
              scale: 1,
            ),
          )
          .catchError((_) {}),
    );
    super.dispose();
  }

  void _scheduleBoundsUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateBounds());
  }

  void _updateBounds() {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);
    final rect = PlayerVideoRect(
      left: origin.dx,
      top: origin.dy,
      width: box.size.width,
      height: box.size.height,
      scale: MediaQuery.devicePixelRatioOf(context),
    );
    if (rect == _lastRect) return;
    _lastRect = rect;
    unawaited(
      widget.player.setVideoRect(rect).catchError((
        Object error,
        StackTrace stack,
      ) {
        if (mounted && _lastRect == rect) _lastRect = null;
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'Lineup native video surface',
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    _scheduleBoundsUpdate();
    return const SizedBox.expand();
  }
}
