import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../diagnostics/diagnostics.dart';
import '../ui/app_theme.dart';
import '../ui/app_ui.dart';
import 'lineup_controller.dart';

/// Session-only support information. Event reading is deliberately decoupled
/// from the live summary so new events cannot move an expanded event or focus.
class DiagnosticsView extends StatefulWidget {
  const DiagnosticsView({
    required this.controller,
    required this.playback,
    required this.onRecordingSettings,
    this.onOpenMenu,
    this.menuFocusNode,
    this.focusNode,
    super.key,
  });

  final LineupController controller;
  final PlaybackDiagnosticSnapshot playback;
  final VoidCallback onRecordingSettings;
  final LineupMenuCallback? onOpenMenu;
  final FocusNode? menuFocusNode;
  final FocusNode? focusNode;

  @override
  State<DiagnosticsView> createState() => _DiagnosticsViewState();
}

class _DiagnosticsViewState extends State<DiagnosticsView> {
  final _scroll = ScrollController();
  List<DiagnosticEntry> _visibleEvents = const [];
  bool _copying = false;
  String? _copyFeedback;

  @override
  void initState() {
    super.initState();
    _visibleEvents = widget.controller.diagnostics.entries.reversed.toList();
    widget.controller.diagnostics.addListener(_eventsChanged);
  }

  @override
  void didUpdateWidget(DiagnosticsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller.diagnostics != widget.controller.diagnostics) {
      oldWidget.controller.diagnostics.removeListener(_eventsChanged);
      widget.controller.diagnostics.addListener(_eventsChanged);
      _visibleEvents = widget.controller.diagnostics.entries.reversed.toList();
    }
  }

  void _eventsChanged() {
    if (!mounted) return;
    setState(() {
      if (!widget.controller.diagnostics.enabled) _visibleEvents = const [];
    });
  }

  @override
  void dispose() {
    widget.controller.diagnostics.removeListener(_eventsChanged);
    _scroll.dispose();
    super.dispose();
  }

  DiagnosticSupportSnapshot _snapshot() {
    final now = DateTime.now();
    return widget.controller.diagnostics.snapshot(
      reportTime: now,
      timeZone: now.timeZoneName,
      appVersion: const String.fromEnvironment(
        'LINEUP_VERSION',
        defaultValue: 'Unavailable',
      ),
      appBuild: const String.fromEnvironment(
        'LINEUP_BUILD',
        defaultValue: 'Unavailable',
      ),
      platform: defaultTargetPlatform.name,
      plexServerSelected: widget.controller.server != null,
      plexConnectionVerified: widget.controller.connection != null,
      playback: widget.playback,
    );
  }

  Future<void> _copy() async {
    if (_copying) return;
    final report = widget.controller.diagnostics.buildSupportReport(
      _snapshot(),
    );
    setState(() {
      _copying = true;
      _copyFeedback = null;
    });
    String feedback;
    try {
      await Clipboard.setData(ClipboardData(text: report));
      feedback = 'Report copied';
    } catch (_) {
      feedback = 'Couldn’t copy the report. Try again.';
    }
    if (!mounted) return;
    setState(() {
      _copying = false;
      _copyFeedback = feedback;
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot();
    final telemetry = snapshot.playback.receivedTelemetry;
    final currentEvents = widget.controller.diagnostics.entries;
    final unseen = currentEvents
        .where((event) => !_visibleEvents.contains(event))
        .length;
    final method = switch (snapshot.playback.method) {
      DiagnosticPlaybackMethod.unknown => 'Unknown',
      DiagnosticPlaybackMethod.directPlay => 'Direct Play',
      DiagnosticPlaybackMethod.directStream => 'Direct Stream',
      DiagnosticPlaybackMethod.transcode => 'Transcode',
    };
    return LineupPage(
      title: 'Diagnostics',
      actions: widget.onOpenMenu == null || widget.menuFocusNode == null
          ? null
          : Builder(
              builder: (buttonContext) => IconButton.outlined(
                key: const Key('diagnostics-app-menu'),
                focusNode: widget.menuFocusNode,
                tooltip: 'Open Lineup menu',
                onPressed: () =>
                    widget.onOpenMenu!(buttonContext, widget.menuFocusNode!),
                icon: const Icon(Icons.menu),
              ),
            ),
      child: Material(
        color: Colors.transparent,
        child: ListView(
          controller: _scroll,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  focusNode: widget.focusNode,
                  onPressed: _copying ? null : _copy,
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy redacted report'),
                ),
                if (_copyFeedback != null)
                  Semantics(liveRegion: true, child: Text(_copyFeedback!)),
                const Text('Review the report before sharing it with support.'),
              ],
            ),
            const SizedBox(height: 32),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns =
                    constraints.maxWidth < 850 ||
                        MediaQuery.textScalerOf(context).scale(1) >= 1.6
                    ? 2
                    : 4;
                final width =
                    (constraints.maxWidth - 24 * (columns - 1)) / columns;
                return Wrap(
                  spacing: 24,
                  runSpacing: 24,
                  children: [
                    _fact(
                      context,
                      'Playback',
                      '${snapshot.playback.state.name}\n$method',
                      width,
                    ),
                    _fact(
                      context,
                      'Video',
                      telemetry?.width != null && telemetry?.height != null
                          ? '${telemetry!.width} × ${telemetry.height}\n${telemetry.videoCodec ?? 'Codec unavailable'}'
                          : 'Unavailable',
                      width,
                    ),
                    _fact(
                      context,
                      'Media signal',
                      telemetry?.gamma == null
                          ? 'Unavailable'
                          : '${telemetry!.gamma}\nReported media information',
                      width,
                    ),
                    _fact(
                      context,
                      'Plex',
                      snapshot.plexServerSelected
                          ? 'Server selected\n${snapshot.plexConnectionVerified ? 'Connection verified' : 'Connection unverified'}'
                          : 'No server selected',
                      width,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            ExpansionTile(
              key: const PageStorageKey('diagnostic-technical-details'),
              title: const Text('Technical details'),
              childrenPadding: const EdgeInsets.all(16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'App ${snapshot.appVersion} · Build ${snapshot.appBuild} · ${snapshot.platform}',
                ),
                Text('Decoder: ${telemetry?.hardwareDecoder ?? 'Unavailable'}'),
                Text(
                  'Video output: ${telemetry?.videoOutput ?? 'Unavailable'}',
                ),
                Text(
                  'Pixel format: ${telemetry?.pixelFormat ?? 'Unavailable'}',
                ),
                Text('Primaries: ${telemetry?.primaries ?? 'Unavailable'}'),
                Text(
                  'Color matrix: ${telemetry?.colorMatrix ?? 'Unavailable'}',
                ),
                Text(
                  'Reported signal peak: ${telemetry?.signalPeak ?? 'Unavailable'}',
                ),
                const Text(
                  'Media signal values do not verify display HDR output.\nPer-stream handling: Unavailable',
                ),
              ],
            ),
            const SizedBox(height: 32),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Recent events',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text('Recording ${snapshot.recordingEnabled ? 'On' : 'Off'}'),
                TextButton(
                  onPressed: widget.onRecordingSettings,
                  child: const Text('Recording settings'),
                ),
                SizedBox(
                  width: 170 * MediaQuery.textScalerOf(context).scale(1),
                  child: Visibility(
                    visible: unseen > 0,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: TextButton(
                      onPressed: () => setState(
                        () => _visibleEvents = currentEvents.reversed.toList(),
                      ),
                      child: Text(
                        '$unseen new ${unseen == 1 ? 'event' : 'events'}',
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const Text(
              'Enable recording before reproducing a problem. Events are session-only; the latest 250 are retained.',
            ),
            const SizedBox(height: 16),
            if (!snapshot.recordingEnabled)
              const Text(
                'Recording is off. Enable it in Settings > Support to record events.',
              )
            else if (_visibleEvents.isEmpty)
              const Text('No events recorded in this session.')
            else
              for (final event in _visibleEvents)
                ExpansionTile(
                  key: ObjectKey(event),
                  title: Text('${event.area}: ${event.message}'),
                  subtitle: Text(
                    MaterialLocalizations.of(context).formatTimeOfDay(
                      TimeOfDay.fromDateTime(event.time.toLocal()),
                    ),
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (event.context.isEmpty)
                      const Text('No additional details'),
                    for (final fact in event.context.entries)
                      Text('${fact.key}: ${fact.value}'),
                  ],
                ),
          ],
        ),
      ),
    );
  }

  Widget _fact(
    BuildContext context,
    String title,
    String value,
    double width,
  ) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(color: LineupTheme.of(context).secondaryText),
        ),
        const SizedBox(height: 12),
        Text(value, style: Theme.of(context).textTheme.titleLarge),
      ],
    ),
  );
}
