import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'native_player.dart';
import 'native_video_surface.dart';

class PlayerFoundationView extends StatefulWidget {
  const PlayerFoundationView({
    required this.player,
    this.initialMediaPath,
    super.key,
  });

  final NativePlayer player;
  final String? initialMediaPath;

  @override
  State<PlayerFoundationView> createState() => _PlayerFoundationViewState();
}

class _PlayerFoundationViewState extends State<PlayerFoundationView> {
  late final TextEditingController _path = TextEditingController(
    text: widget.initialMediaPath ?? '',
  );
  StreamSubscription<PlayerEvent>? _subscription;
  PlayerEvent? _event;
  String? _operation;
  bool _fullscreen = false;
  int _presentationEpoch = 0;

  @override
  void initState() {
    super.initState();
    _subscription = widget.player.events.listen((event) {
      if (mounted) setState(() => _event = event);
    });
    if (_path.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _path.dispose();
    super.dispose();
  }

  Uri? _mediaUri() {
    final value = _path.text.trim();
    if (value.isEmpty) return null;
    if (Platform.isWindows &&
        (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value) ||
            value.startsWith(r'\\'))) {
      return Uri.file(value, windows: true);
    }
    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme) return parsed;
    return Uri.file(value, windows: Platform.isWindows);
  }

  Future<void> _run(String label, Future<void> Function() operation) async {
    if (_operation != null) return;
    setState(() => _operation = label);
    try {
      await operation();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$label failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _operation = null);
    }
  }

  Future<void> _load() async {
    final media = _mediaUri();
    if (media == null) return;
    await _run('Load', () => widget.player.load(media));
  }

  Future<void> _reloadTenTimes() async {
    final media = _mediaUri();
    if (media == null) return;
    await _run('10 replacement loads', () async {
      for (var index = 1; index <= 10; index++) {
        if (mounted) setState(() => _operation = 'Replacement load $index/10');
        await widget.player.load(media);
      }
    });
  }

  Future<void> _recreate() async {
    final media = _mediaUri();
    await _run('Recreate native player', () async {
      await widget.player.dispose();
      await widget.player.initialize();
      if (mounted) {
        setState(() {
          _fullscreen = false;
          _presentationEpoch += 1;
        });
      }
      if (media != null) await widget.player.load(media);
    });
  }

  @override
  Widget build(BuildContext context) {
    final event = _event;
    final status = event?.status ?? widget.player.status;
    final telemetry = event?.telemetry ?? widget.player.telemetry;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (status.state == PlayerState.unsupported)
          ColoredBox(color: Theme.of(context).scaffoldBackgroundColor)
        else
          NativeVideoSurface(
            player: widget.player,
            presentationEpoch: _presentationEpoch,
          ),
        Positioned(
          left: 28,
          top: 24,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.58),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                'Flutter overlay • ${status.message}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xDD17191D),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white24),
              ),
              child: FocusTraversalGroup(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Text(
                      'Native player foundation',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _path,
                      decoration: const InputDecoration(
                        labelText: 'Local media path or URI',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _load(),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: _operation == null ? _load : null,
                          child: const Text('Load'),
                        ),
                        OutlinedButton(
                          onPressed: _operation == null
                              ? () => _run('Play', widget.player.play)
                              : null,
                          child: const Text('Play'),
                        ),
                        OutlinedButton(
                          onPressed: _operation == null
                              ? () => _run('Pause', widget.player.pause)
                              : null,
                          child: const Text('Pause'),
                        ),
                        OutlinedButton(
                          onPressed: _operation == null
                              ? () => _run('Stop', widget.player.stop)
                              : null,
                          child: const Text('Stop'),
                        ),
                        OutlinedButton(
                          onPressed: _operation == null
                              ? () => _run('Fullscreen', () async {
                                  final fullscreen = !_fullscreen;
                                  await widget.player.setFullscreen(fullscreen);
                                  if (mounted) {
                                    setState(() => _fullscreen = fullscreen);
                                  }
                                })
                              : null,
                          child: Text(
                            _fullscreen ? 'Exit fullscreen' : 'Fullscreen',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: _operation == null
                              ? _reloadTenTimes
                              : null,
                          child: const Text('Replace ×10'),
                        ),
                        OutlinedButton(
                          onPressed: _operation == null ? _recreate : null,
                          child: const Text('Dispose + recreate'),
                        ),
                      ],
                    ),
                    if (_operation != null) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(semanticsLabel: _operation),
                      const SizedBox(height: 6),
                      Text(_operation!),
                    ],
                    const Divider(height: 28),
                    _Fact('Video output', telemetry.videoOutput),
                    _Fact('Hardware decoder', telemetry.hardwareDecoder),
                    _Fact('Codec', telemetry.videoCodec),
                    _Fact(
                      'Dimensions',
                      telemetry.width == null
                          ? null
                          : '${telemetry.width} × ${telemetry.height}',
                    ),
                    _Fact(
                      'Pixel formats',
                      [
                        telemetry.pixelFormat,
                        telemetry.hardwarePixelFormat,
                      ].nonNulls.join(' / '),
                    ),
                    _Fact(
                      'Color',
                      [
                        telemetry.primaries,
                        telemetry.gamma,
                        telemetry.colorMatrix,
                      ].nonNulls.join(' / '),
                    ),
                    _Fact(
                      'HDR metadata',
                      telemetry.isHdr ? 'Observed' : 'Not observed',
                    ),
                    _Fact(
                      'Tracks',
                      '${event?.tracks.length ?? widget.player.tracks.length}',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final display = value == null || value!.isEmpty ? 'Not observed' : value!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text('$label: $display'),
    );
  }
}
