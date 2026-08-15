import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../playback/native_player.dart';
import '../ui/app_theme.dart';
import 'lineup_controller.dart';
import 'lineup_shell.dart';

const _requiredEngineFailureMessage =
    'The required Lineup DirectComposition Flutter engine is not active.';

class LineupBootstrap extends StatefulWidget {
  const LineupBootstrap({
    required this.player,
    required this.controller,
    this.initialMediaPath,
    this.guideClock,
    super.key,
  });

  final NativePlayer player;
  final LineupController controller;
  final String? initialMediaPath;
  final DateTime Function()? guideClock;

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

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _startup = Future.wait([
      widget.player.initialize(),
      widget.controller.initialize(),
    ]);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.player.dispose();
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.controller.settings;
    return MaterialApp(
      title: 'Lineup Desktop',
      debugShowCheckedModeBanner: false,
      theme: LineupTheme.forName(
        settings.theme,
        largeFocusIndicators: settings.largeFocusIndicators,
      ),
      themeAnimationDuration: settings.reduceMotion
          ? Duration.zero
          : kThemeAnimationDuration,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations:
              MediaQuery.disableAnimationsOf(context) || settings.reduceMotion,
        ),
        child: child!,
      ),
      home: FutureBuilder<void>(
        future: _startup,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final error = snapshot.error;
            return _StartupFailureBody(
              requiredEngineFailure:
                  error is PlatformException &&
                  error.code == 'required_engine_unavailable',
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const _StartupProgress();
          }
          return LineupShell(
            player: widget.player,
            controller: widget.controller,
            initialMediaPath: widget.initialMediaPath,
            guideClock: widget.guideClock,
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
  const _StartupFailureBody({required this.requiredEngineFailure});

  final bool requiredEngineFailure;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 20),
                Text(
                  'Lineup Desktop could not start',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  requiredEngineFailure ? _requiredEngineFailureMessage : 'Restart the app, and check diagnostics if the problem continues.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
