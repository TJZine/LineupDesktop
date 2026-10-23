import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, ValueListenable, defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../playback/native_player.dart';
import '../persistence/app_store.dart';
import '../settings/lineup_settings.dart';
import '../ui/app_theme.dart';
import '../ui/lineup_canvas.dart';
import '../ui/keyboard_visibility.dart';
import 'lineup_controller.dart';
import 'lineup_shell.dart';

// Only the Windows backend reports required_engine_unavailable (its
// DirectComposition engine variant); the macOS backend never does.
const _requiredEngineFailureMessage =
    'The required Lineup DirectComposition Flutter engine is not active.';

class LineupStartup extends StatefulWidget {
  const LineupStartup({required this.createBootstrap, super.key});

  final Future<LineupBootstrap> Function() createBootstrap;

  @override
  State<LineupStartup> createState() => _LineupStartupState();
}

class _LineupStartupState extends State<LineupStartup> {
  late final Future<LineupBootstrap> _composition;

  @override
  void initState() {
    super.initState();
    _composition = Future.sync(widget.createBootstrap);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LineupBootstrap>(
      future: _composition,
      builder: (context, snapshot) {
        if (snapshot.hasData) return snapshot.requireData;
        return MaterialApp(
          title: 'Lineup Desktop',
          debugShowCheckedModeBanner: false,
          theme: LineupTheme.forName(
            LineupThemeName.emberSteel,
            largeFocusIndicators: false,
            androidTv: defaultTargetPlatform == TargetPlatform.android,
          ),
          builder: LineupCanvas.builder,
          home: snapshot.hasError
              ? const _StartupFailureBody(
                  requiredEngineFailure: false,
                  unsupportedStateFormatFailure: false,
                )
              : const _StartupProgress(),
        );
      },
    );
  }
}

class LineupBootstrap extends StatefulWidget {
  const LineupBootstrap({
    required this.player,
    required this.controller,
    this.initialMediaPath,
    this.guideClock,
    this.androidTv,
    this.keyboardVisibility,
    super.key,
  });

  final NativePlayer player;
  final LineupController controller;
  final String? initialMediaPath;
  final DateTime Function()? guideClock;

  /// Null follows the host platform for the production composition root.
  /// Tests and alternate compositions can inject the form factor explicitly.
  final bool? androidTv;

  /// An injected observation source remains owned by its caller.
  final ValueListenable<bool?>? keyboardVisibility;

  @override
  State<LineupBootstrap> createState() => _LineupBootstrapState();
}

class LineupRuntimeFailure extends StatelessWidget {
  const LineupRuntimeFailure({super.key});

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    return ColoredBox(
      color: roles.primarySurface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Semantics(
            liveRegion: true,
            label: 'This part of Lineup Desktop could not be displayed',
            child: Text(
              'Something went wrong while displaying this view.',
              style: TextStyle(color: roles.primaryText),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class _LineupBootstrapState extends State<LineupBootstrap> {
  late final Future<void> _startup;
  late LineupSettings _settings;
  String? _startupRecoveryNotice;
  bool _nativeInitialized = false;
  bool _restoreStarted = false;

  PlatformKeyboardVisibility? _ownedKeyboardVisibility;
  bool get _androidTv =>
      widget.androidTv ?? defaultTargetPlatform == TargetPlatform.android;

  void _configureKeyboardVisibility() {
    if (_androidTv && widget.keyboardVisibility == null) {
      _ownedKeyboardVisibility ??= PlatformKeyboardVisibility();
    } else {
      _ownedKeyboardVisibility?.dispose();
      _ownedKeyboardVisibility = null;
    }
  }

  @override
  void didUpdateWidget(LineupBootstrap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configureKeyboardVisibility();
  }

  @override
  void initState() {
    super.initState();
    _configureKeyboardVisibility();
    _settings = widget.controller.settings;
    _startupRecoveryNotice = widget.controller.startupRecoveryNotice;
    _restoreStarted = widget.controller.restoringSavedLineup;
    widget.controller.addListener(_changed);
    _startup = Future.wait([
      _initializePlayer(),
      widget.controller.initialize(),
    ], eagerError: true);
  }

  Future<void> _initializePlayer() async {
    await widget.player.initialize();
    if (mounted) setState(() => _nativeInitialized = true);
  }

  void _changed() {
    final settings = widget.controller.settings;
    final startupRecoveryNotice = widget.controller.startupRecoveryNotice;
    final restoreStarted =
        _restoreStarted || widget.controller.restoringSavedLineup;
    if (settings.theme == _settings.theme &&
        settings.largeFocusIndicators == _settings.largeFocusIndicators &&
        settings.reduceMotion == _settings.reduceMotion &&
        startupRecoveryNotice == _startupRecoveryNotice &&
        restoreStarted == _restoreStarted) {
      return;
    }
    if (mounted) {
      setState(() {
        _settings = settings;
        _startupRecoveryNotice = startupRecoveryNotice;
        _restoreStarted = restoreStarted;
      });
    }
  }

  @override
  void dispose() {
    _ownedKeyboardVisibility?.dispose();
    widget.controller.removeListener(_changed);
    unawaited(_disposePlayer());
    widget.controller.dispose();
    super.dispose();
  }

  Future<void> _disposePlayer() async {
    try {
      await widget.player.dispose();
    } catch (_) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: StateError('Native player shutdown failed.'),
          library: 'Lineup Desktop',
          context: ErrorDescription('while disposing the native player'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final androidTv = _androidTv;
    return MaterialApp(
      title: 'Lineup Desktop',
      debugShowCheckedModeBanner: false,
      theme: LineupTheme.forName(
        settings.theme,
        largeFocusIndicators: settings.largeFocusIndicators,
        androidTv: androidTv,
      ),
      themeAnimationDuration: settings.reduceMotion
          ? Duration.zero
          : kThemeAnimationDuration,
      builder: (context, child) {
        final canvas = LineupCanvas(
          reduceMotion: settings.reduceMotion,
          child: child!,
        );
        return androidTv
            ? KeyboardVisibilityScope(
                visibility:
                    widget.keyboardVisibility ?? _ownedKeyboardVisibility!,
                child: canvas,
              )
            : canvas;
      },
      home: FutureBuilder<void>(
        future: _startup,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final error = snapshot.error;
            return _StartupFailureBody(
              requiredEngineFailure:
                  error is PlayerUnavailable &&
                  error.failureCode == 'required_engine_unavailable',
              unsupportedStateFormatFailure:
                  error is UnsupportedStateFormatException,
            );
          }
          if (snapshot.connectionState != ConnectionState.done &&
              !(_nativeInitialized && _restoreStarted)) {
            return const _StartupProgress();
          }
          return Stack(
            children: [
              LineupShell(
                player: widget.player,
                controller: widget.controller,
                initialMediaPath: widget.initialMediaPath,
                guideClock: widget.guideClock,
              ),
              if (_startupRecoveryNotice case final notice?)
                SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Semantics(
                      container: true,
                      liveRegion: true,
                      label: notice,
                      child: Material(
                        child: MaterialBanner(
                          content: ExcludeSemantics(child: Text(notice)),
                          actions: [
                            TextButton(
                              onPressed: widget
                                  .controller
                                  .dismissStartupRecoveryNotice,
                              child: const Text('Dismiss'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StartupProgress extends StatelessWidget {
  const _StartupProgress();

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.5, -0.6),
            radius: 1.2,
            colors: [
              roles.progressFill.withValues(alpha: 0.10),
              roles.deepBackground,
            ],
          ),
        ),
        child: Center(
          child: Semantics(
            label: 'Starting Lineup Desktop',
            liveRegion: true,
            container: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/branding/lineup-logo-mark.png', height: 92),
                const SizedBox(height: 26),
                const SizedBox(width: 220, child: LinearProgressIndicator()),
                const SizedBox(height: 14),
                const Text('TUNING LINEUP'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupFailureBody extends StatelessWidget {
  const _StartupFailureBody({
    required this.requiredEngineFailure,
    required this.unsupportedStateFormatFailure,
  });

  final bool requiredEngineFailure;
  final bool unsupportedStateFormatFailure;

  @override
  Widget build(BuildContext context) {
    const failureLabel = 'Lineup Desktop could not start';
    return Scaffold(
      body: Center(
        child: Semantics(
          container: true,
          liveRegion: true,
          label: failureLabel,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 20),
                  ExcludeSemantics(
                    child: Text(
                      failureLabel,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    requiredEngineFailure
                        ? _requiredEngineFailureMessage
                        : unsupportedStateFormatFailure
                        ? 'This build is too old to open your saved data. '
                              'Your saved data was left intact. Update '
                              'Lineup Desktop and try again.'
                        : 'Restart the app. If the problem continues, report '
                              'the startup failure.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
