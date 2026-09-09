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
    this.onBack,
    super.key,
  });

  final LineupController controller;
  final PlaybackDiagnosticSnapshot playback;
  final VoidCallback onRecordingSettings;
  final LineupMenuCallback? onOpenMenu;
  final FocusNode? menuFocusNode;
  final FocusNode? focusNode;
  final VoidCallback? onBack;

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
      titleWidget: Row(
        children: [
          TextButton.icon(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back'),
          ),
          const SizedBox(width: 20),
          Text('Diagnostics', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(width: 16),
          Text(
            'Support',
            style: TextStyle(color: LineupTheme.of(context).secondaryText),
          ),
        ],
      ),
      actions: widget.onOpenMenu == null || widget.menuFocusNode == null
          ? null
          : Builder(
              builder: (buttonContext) => TextButton.icon(
                key: const Key('diagnostics-app-menu'),
                focusNode: widget.menuFocusNode,
                onPressed: () =>
                    widget.onOpenMenu!(buttonContext, widget.menuFocusNode!),
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.expand_more),
                label: const Text('LINEUP'),
              ),
            ),
      child: Material(
        color: Colors.transparent,
        child: ListView(
          controller: _scroll,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Diagnostics',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const Text(
                        'Playback information and recent support events.',
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  focusNode: widget.focusNode,
                  onPressed: _copying ? null : _copy,
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy redacted report'),
                ),
              ],
            ),
            if (_copyFeedback != null)
              Align(
                alignment: Alignment.centerRight,
                child: Semantics(liveRegion: true, child: Text(_copyFeedback!)),
              ),
            const SizedBox(height: 20),
            Material(
              color: LineupTheme.of(context).primarySurface,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: LineupTheme.of(context).subtleBorder),
                borderRadius: BorderRadius.circular(
                  LineupTheme.of(context).panelRadius,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) => Wrap(
                        spacing: 28,
                        runSpacing: 18,
                        children: [
                          _fact(
                            context,
                            'Playback',
                            '${snapshot.playback.state.name} · $method',
                            (constraints.maxWidth - 84) / 4,
                          ),
                          _fact(
                            context,
                            'Video',
                            telemetry?.width != null &&
                                    telemetry?.height != null
                                ? '${telemetry!.width} × ${telemetry.height} · ${telemetry.videoCodec ?? 'Codec unavailable'}'
                                : 'Unavailable',
                            (constraints.maxWidth - 84) / 4,
                          ),
                          _fact(
                            context,
                            'Media signal',
                            telemetry?.gamma == null
                                ? 'Unavailable'
                                : '${telemetry!.gamma} · Reported media information',
                            (constraints.maxWidth - 84) / 4,
                          ),
                          _fact(
                            context,
                            'Plex',
                            snapshot.plexServerSelected
                                ? (snapshot.plexConnectionVerified
                                      ? 'Connection verified'
                                      : 'Connection unverified')
                                : 'No server selected',
                            (constraints.maxWidth - 84) / 4,
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    ExpansionTile(
                      key: const PageStorageKey('diagnostic-technical-details'),
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Technical details'),
                      childrenPadding: const EdgeInsets.only(bottom: 12),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 32,
                          runSpacing: 12,
                          children: [
                            _technicalFact(
                              'Lineup',
                              '${snapshot.appVersion} · build ${snapshot.appBuild}',
                            ),
                            _technicalFact('Platform', snapshot.platform),
                            _technicalFact(
                              'Hardware decoder',
                              telemetry?.hardwareDecoder ?? 'Unavailable',
                            ),
                            _technicalFact(
                              'Video output',
                              telemetry?.videoOutput ?? 'Unavailable',
                            ),
                            _technicalFact(
                              'Transfer / pixel format',
                              '${telemetry?.gamma ?? 'Unavailable'} · ${telemetry?.pixelFormat ?? 'Unavailable'}',
                            ),
                            _technicalFact(
                              'Primaries / color matrix',
                              '${telemetry?.primaries ?? 'Unavailable'} · ${telemetry?.colorMatrix ?? 'Unavailable'}',
                            ),
                            _technicalFact(
                              'Reported signal peak',
                              telemetry?.signalPeak?.toString() ??
                                  'Unavailable',
                            ),
                            _technicalFact(
                              'Per-stream handling',
                              'Unavailable',
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Media signal values do not verify display HDR output.',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final title = Wrap(
                  spacing: 16,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Recent events',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${_visibleEvents.length} events · newest first',
                      style: TextStyle(
                        color: LineupTheme.of(context).secondaryText,
                      ),
                    ),
                  ],
                );
                final actions = Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Recording ${snapshot.recordingEnabled ? 'On' : 'Off'}',
                    ),
                    TextButton(
                      onPressed: widget.onRecordingSettings,
                      child: const Text('Recording settings'),
                    ),
                    SizedBox(
                      width: 170,
                      child: Visibility(
                        visible: unseen > 0,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: TextButton(
                          onPressed: () => setState(
                            () => _visibleEvents = currentEvents.reversed
                                .toList(),
                          ),
                          child: Text(
                            '$unseen new ${unseen == 1 ? 'event' : 'events'}',
                          ),
                        ),
                      ),
                    ),
                  ],
                );
                if (constraints.maxWidth < 1000) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      title,
                      Align(alignment: Alignment.centerRight, child: actions),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: title),
                    actions,
                  ],
                );
              },
            ),
            if (!snapshot.recordingEnabled)
              SizedBox(
                height: 180,
                child: _emptyEvents(
                  'Diagnostic recording is off',
                  'Enable recording in Settings > Support, then reproduce the issue.',
                ),
              )
            else if (_visibleEvents.isEmpty)
              SizedBox(
                height: 180,
                child: _emptyEvents(
                  'No events recorded yet',
                  'Reproduce the issue to collect support events.',
                ),
              )
            else
              for (final event in _visibleEvents) _eventTile(event),
            Text(
              'This session only · Up to 250 recent events retained',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: LineupTheme.of(context).secondaryText),
            ),
            const SizedBox(height: 6),
            Text(
              'Reports exclude credentials, URLs and private paths. Review before sharing.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: LineupTheme.of(context).secondaryText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _technicalFact(String label, String value) => SizedBox(
    width: 210,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: LineupTheme.of(context).secondaryText),
        ),
        const SizedBox(height: 3),
        Text(value),
      ],
    ),
  );

  Widget _emptyEvents(String title, String message) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(message),
      ],
    ),
  );

  Widget _eventTile(DiagnosticEntry event) => Semantics(
    label: '${event.area}: ${event.message}',
    child: ExpansionTile(
      key: ObjectKey(event),
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      title: ExcludeSemantics(
        child: Row(
          children: [
            SizedBox(
              width: 105,
              child: Text(
                MaterialLocalizations.of(
                  context,
                ).formatTimeOfDay(TimeOfDay.fromDateTime(event.time.toLocal())),
              ),
            ),
            SizedBox(width: 120, child: Text(event.area)),
            Expanded(child: Text(event.message)),
          ],
        ),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(249, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (event.context.isEmpty) const Text('No additional details'),
        for (final fact in event.context.entries)
          Text('${fact.key}: ${fact.value}'),
      ],
    ),
  );

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
