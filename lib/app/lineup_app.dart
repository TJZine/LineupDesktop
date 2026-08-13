import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../playback/native_player.dart';
import '../ui/app_theme.dart';
import 'lineup_controller.dart';
import 'lineup_shell.dart';

class LineupBootstrap extends StatefulWidget {
  const LineupBootstrap({
    required this.player,
    required this.controller,
    this.initialMediaPath,
    super.key,
  });

  final NativePlayer player;
  final LineupController controller;
  final String? initialMediaPath;

  @override
  State<LineupBootstrap> createState() => _LineupBootstrapState();
}

class LineupRuntimeFailure extends StatelessWidget {
  const LineupRuntimeFailure({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF17191D),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Semantics(
            liveRegion: true,
            label: 'This part of Lineup Desktop could not be displayed',
            child: const Text(
              'Something went wrong while displaying this view.',
              style: TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class _LineupBootstrapState extends State<LineupBootstrap> {
  late final Future<void> _startup = Future.wait([
    widget.player.initialize(),
    widget.controller.initialize(),
  ]);

  @override
  void dispose() {
    widget.player.dispose();
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lineup Desktop',
      debugShowCheckedModeBanner: false,
      theme: LineupTheme.dark,
      home: FutureBuilder<void>(
        future: _startup,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _StartupFailureBody(error: snapshot.error);
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const _StartupProgress();
          }
          return LineupShell(
            player: widget.player,
            controller: widget.controller,
            initialMediaPath: widget.initialMediaPath,
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
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.5, -0.6),
            radius: 1.2,
            colors: [Color(0x1428C8A0), LineupTheme.obsidian],
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
  const _StartupFailureBody({required this.error});

  final Object? error;

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
                  error is PlatformException &&
                          (error as PlatformException).code ==
                              'initialize_failed'
                      ? (error as PlatformException).message ?? 'The required Windows native player could not initialize.'
                      : 'No settings or media were changed. Restart the app, and check diagnostics if the problem continues.',
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
