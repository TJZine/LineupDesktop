import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'platform_events.dart';

/// Application policy uses DISPLAY dimensions for phone detection, the actual
/// Android multi-window fact, and WINDOW orientation for immersive bars.
@immutable
class HandheldSystemUiPolicy {
  const HandheldSystemUiPolicy({
    required this.displaySize,
    required this.windowSize,
    required this.multiWindow,
    required this.playerVisible,
    required this.osdVisible,
    this.fullscreen = false,
  });

  final Size displaySize;
  final Size windowSize;
  final bool? multiWindow;
  final bool playerVisible;
  final bool osdVisible;
  final bool fullscreen;

  List<DeviceOrientation> get orientations {
    if (multiWindow != false ||
        displaySize.isEmpty ||
        !displaySize.isFinite ||
        displaySize.shortestSide >= 600) {
      return const [];
    }
    if (!playerVisible) return const [DeviceOrientation.portraitUp];
    return [
      if (!fullscreen) DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ];
  }

  SystemUiMode get mode =>
      playerVisible && (!osdVisible || windowSize.width > windowSize.height)
      ? SystemUiMode.immersiveSticky
      : SystemUiMode.edgeToEdge;
}

/// Hosted only on Android handheld. It owns and retires one observation and
/// serializes platform updates so an older destination cannot restore stale UI.
class HandheldSystemUi extends StatefulWidget {
  const HandheldSystemUi({
    required this.playerVisible,
    required this.osdVisible,
    required this.child,
    this.fullscreen = false,
    super.key,
  });

  final bool playerVisible;
  final bool osdVisible;
  final bool fullscreen;
  final Widget child;

  @override
  State<HandheldSystemUi> createState() => _HandheldSystemUiState();
}

class _HandheldSystemUiState extends State<HandheldSystemUi>
    with WidgetsBindingObserver {
  // Startup and the ready shell briefly overlap during element replacement.
  // Only the newest host may apply or restore policy for the same app window.
  static _HandheldSystemUiState? _owner;
  bool get _ownsWindow => identical(_owner, this);
  late final VoidCallback _unsubscribe;
  bool? _multiWindow;
  (List<DeviceOrientation>, SystemUiMode)? _pending;
  (List<DeviceOrientation>, SystemUiMode)? _applied;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _owner = this;
    WidgetsBinding.instance.addObserver(this);
    _unsubscribe = PlatformEvents().subscribe(
      event: 'multiWindowChanged',
      watch: 'watchWindowFacts',
      unwatch: 'unwatchWindowFacts',
      accepts: (fact) => fact is bool,
      onEvent: (fact) {
        if (mounted && _multiWindow != fact) {
          setState(() => _multiWindow = fact as bool);
        }
      },
    );
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _applied = null;
      if (mounted) setState(() {});
    }
  }

  void _schedule(HandheldSystemUiPolicy policy) {
    final next = (policy.orientations, policy.mode);
    bool same((List<DeviceOrientation>, SystemUiMode)? other) =>
        other != null &&
        other.$2 == next.$2 &&
        other.$1.length == next.$1.length &&
        Iterable<int>.generate(next.$1.length)
            .every((i) => other.$1[i] == next.$1[i]);
    if (same(_pending) || (_pending == null && !_applying && same(_applied))) {
      return;
    }
    _pending = next;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _ownsWindow && !_applying) unawaited(_applyPending());
    });
  }

  Future<void> _applyPending() async {
    _applying = true;
    try {
      while (mounted && _ownsWindow && _pending != null) {
        final next = _pending!;
        _pending = null;
        await SystemChrome.setPreferredOrientations(next.$1);
        if (!mounted || !_ownsWindow) return;
        if (_pending != null) continue;
        await SystemChrome.setEnabledSystemUIMode(next.$2);
        if (!mounted || !_ownsWindow) return;
        SystemChrome.setSystemUIOverlayStyle(_bars);
        _applied = next;
      }
    } finally {
      _applying = false;
    }
  }

  static const _bars = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    // Android retains the contrast scrim for three-button navigation.
    systemNavigationBarContrastEnforced: true,
  );

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    _schedule(
      HandheldSystemUiPolicy(
        displaySize: view.display.size / view.display.devicePixelRatio,
        windowSize: view.physicalSize / view.devicePixelRatio,
        multiWindow: _multiWindow,
        playerVisible: widget.playerVisible,
        osdVisible: widget.osdVisible,
        fullscreen: widget.fullscreen,
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _bars,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unsubscribe();
    _pending = null;
    if (_ownsWindow) {
      _owner = null;
      unawaited(SystemChrome.setPreferredOrientations(const []));
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
      SystemChrome.setSystemUIOverlayStyle(_bars);
    }
    super.dispose();
  }
}
