import 'dart:async';

import 'package:flutter/material.dart';

import 'native_player.dart';

class NativeVideoSurface extends StatefulWidget {
  const NativeVideoSurface({required this.player, super.key});

  final NativePlayer player;

  @override
  State<NativeVideoSurface> createState() => _NativeVideoSurfaceState();
}

class _NativeVideoSurfaceState extends State<NativeVideoSurface>
    with WidgetsBindingObserver {
  // A player has one native output, even while a route replaces its surface
  // widget. The successor mounts before the predecessor is disposed. Giving it
  // ownership here prevents the old widget's zero rectangle from destroying
  // the live Android SurfaceView between two visible rectangles.
  static final _owners = Expando<_NativeVideoSurfaceState>();

  PlayerVideoRect? _lastRect;

  @override
  void initState() {
    super.initState();
    _owners[widget.player] = this;
    WidgetsBinding.instance.addObserver(this);
    _scheduleBoundsUpdate();
  }

  @override
  void didUpdateWidget(NativeVideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.player, widget.player)) {
      _hideIfOwner(oldWidget.player);
      _owners[widget.player] = this;
      _lastRect = null;
    }
    _scheduleBoundsUpdate();
  }

  @override
  void didChangeMetrics() => _scheduleBoundsUpdate();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideIfOwner(widget.player);
    super.dispose();
  }

  void _hideIfOwner(NativePlayer player) {
    if (!identical(_owners[player], this)) return;
    _owners[player] = null;
    unawaited(
      player
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
  }

  void _scheduleBoundsUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateBounds());
  }

  void _updateBounds() {
    if (!mounted || !identical(_owners[widget.player], this)) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final bounds = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    final rect = PlayerVideoRect(
      left: bounds.left,
      top: bounds.top,
      width: bounds.width,
      height: bounds.height,
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
