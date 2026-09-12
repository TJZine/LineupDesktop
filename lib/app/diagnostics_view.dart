import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../diagnostics/diagnostics.dart';
import '../playback/native_player.dart';
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

  double _effectiveTextScale(BuildContext context) =>
      math.max(1.0, MediaQuery.textScalerOf(context).scale(1));

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final layoutScale = LineupLayout.scaleFor(size);
    final scale =
        layoutScale * (size.height / 1080).clamp(0.82, 1.0).toDouble();
    final snapshot = _snapshot();
    final telemetry = snapshot.playback.receivedTelemetry;
    final currentEvents = widget.controller.diagnostics.entries;
    final unseen = currentEvents
        .where((event) => !_visibleEvents.contains(event))
        .length;
    return IconTheme.merge(
      data: IconThemeData(size: 24 * scale),
      child: FocusTraversalGroup(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _diagnosticsHeader(context, scale),
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      48 * scale,
                      32 * scale,
                      48 * scale,
                      0,
                    ),
                    child: ListView(
                      controller: _scroll,
                      children: [
                        _diagnosticsIntro(context, scale),
                        SizedBox(height: 28 * scale),
                        _summary(context, snapshot, telemetry, scale),
                        SizedBox(height: 32 * scale),
                        _eventsHeader(
                          context,
                          snapshot,
                          currentEvents,
                          unseen,
                          scale,
                        ),
                        if (!snapshot.recordingEnabled)
                          SizedBox(
                            height: 180 * scale,
                            child: _emptyEvents(
                              'Diagnostic recording is off',
                              'Enable recording in Settings > Support, then reproduce the issue.',
                              scale,
                            ),
                          )
                        else if (_visibleEvents.isEmpty)
                          SizedBox(
                            height: 180 * scale,
                            child: _emptyEvents(
                              'No events recorded yet',
                              'Reproduce the issue to collect support events.',
                              scale,
                            ),
                          )
                        else
                          for (final event in _visibleEvents)
                            _eventTile(event, scale),
                        SizedBox(height: 12 * scale),
                        Text(
                          'This session only · Up to 250 recent events retained',
                          style: TextStyle(
                            color: LineupTheme.of(context).secondaryText,
                            fontSize: 14 * scale,
                          ),
                        ),
                        SizedBox(height: 8 * scale),
                        Text(
                          'Reports exclude credentials, URLs and private paths. Review before sharing.',
                          style: TextStyle(
                            color: LineupTheme.of(context).secondaryText,
                            fontSize: 14 * scale,
                          ),
                        ),
                        SizedBox(height: 16 * scale),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _diagnosticsHeader(BuildContext context, double scale) {
    final roles = LineupTheme.of(context);
    return Container(
      height: 96 * scale,
      margin: EdgeInsets.symmetric(horizontal: 48 * scale),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: roles.subtleBorder)),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: widget.onBack,
            icon: Icon(Icons.arrow_back, size: 18 * scale),
            label: const Text('Back'),
            style: TextButton.styleFrom(
              foregroundColor: roles.secondaryText,
              minimumSize: Size(0, 48 * scale),
              padding: EdgeInsets.symmetric(
                horizontal: 4 * scale,
                vertical: 8 * scale,
              ),
              textStyle: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(fontSize: 18 * scale),
            ),
          ),
          SizedBox(width: 12 * scale),
          Text(
            'Support',
            style: TextStyle(color: roles.secondaryText, fontSize: 16 * scale),
          ),
          const Spacer(),
          if (widget.onOpenMenu != null && widget.menuFocusNode != null)
            Builder(
              builder: (buttonContext) => TextButton(
                key: const Key('diagnostics-app-menu'),
                focusNode: widget.menuFocusNode,
                onPressed: () =>
                    widget.onOpenMenu!(buttonContext, widget.menuFocusNode!),
                style: TextButton.styleFrom(
                  foregroundColor: roles.primaryText,
                  minimumSize: Size(0, 48 * scale),
                  padding: EdgeInsets.symmetric(
                    horizontal: 4 * scale,
                    vertical: 8 * scale,
                  ),
                  textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontSize: 20 * scale,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.5 * scale,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('LINEUP'),
                    SizedBox(width: 12 * scale),
                    Icon(Icons.menu, size: 18 * scale),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _diagnosticsIntro(BuildContext context, double scale) {
    final roles = LineupTheme.of(context);
    final copyAction = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FilledButton(
          focusNode: widget.focusNode,
          onPressed: _copying ? null : _copy,
          style: FilledButton.styleFrom(
            minimumSize: Size(148 * scale, 54 * scale),
            padding: EdgeInsets.symmetric(
              horizontal: 24 * scale,
              vertical: 16 * scale,
            ),
          ),
          child: Text(
            'Copy redacted report',
            style: TextStyle(fontSize: 16 * scale),
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: 40 * scale * _effectiveTextScale(context),
            minWidth: 300 * scale,
            maxWidth: 300 * scale,
          ),
          child: Align(
            alignment: Alignment.topRight,
            child: Semantics(
              liveRegion: true,
              child: Text(
                _copyFeedback ?? '',
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: roles.secondaryText,
                  fontSize: 14 * scale,
                ),
              ),
            ),
          ),
        ),
      ],
    );
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Diagnostics',
          style: TextStyle(
            color: roles.primaryText,
            fontSize: 32 * scale,
            fontWeight: FontWeight.w500,
            height: 1.2,
            letterSpacing: -0.6 * scale,
          ),
        ),
        SizedBox(height: 5 * scale),
        Text(
          'Playback information and recent support events.',
          style: TextStyle(color: roles.secondaryText, fontSize: 16 * scale),
        ),
      ],
    );
    final effectiveTextScale = _effectiveTextScale(context);
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth < 720 * scale * effectiveTextScale
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                SizedBox(height: 20 * scale),
                Align(alignment: Alignment.centerLeft, child: copyAction),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: heading),
                copyAction,
              ],
            ),
    );
  }

  Widget _summary(
    BuildContext context,
    DiagnosticSupportSnapshot snapshot,
    PlayerTelemetry? telemetry,
    double scale,
  ) {
    final roles = LineupTheme.of(context);
    final facts = [
      (
        'Playback',
        '${_playbackLabel(snapshot.playback.state)} · ${_methodLabel(snapshot.playback.method)}',
      ),
      (
        'Video',
        (telemetry?.width ?? 0) > 0 && (telemetry?.height ?? 0) > 0
            ? '${telemetry!.width} × ${telemetry.height} · ${telemetry.videoCodec ?? 'Codec unavailable'}'
            : 'Unavailable',
      ),
      ('Media signal', _mediaSignal(telemetry)),
      (
        'Plex',
        snapshot.plexServerSelected
            ? (snapshot.plexConnectionVerified
                  ? 'Connection verified'
                  : 'Connection unverified')
            : 'No server selected',
      ),
    ];
    return Material(
      color: roles.primarySurface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: roles.subtleBorder),
        borderRadius: BorderRadius.circular(roles.panelRadius),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          28 * scale,
          24 * scale,
          28 * scale,
          8 * scale,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final gap = 28 * scale;
                final effectiveTextScale = _effectiveTextScale(context);
                final columns =
                    constraints.maxWidth >= 1100 * scale * effectiveTextScale
                    ? 4
                    : constraints.maxWidth >= 600 * scale * effectiveTextScale
                    ? 2
                    : 1;
                final width = columns == 1
                    ? constraints.maxWidth
                    : (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: 20 * scale,
                  children: [
                    for (final fact in facts)
                      _fact(context, fact.$1, fact.$2, width, scale),
                  ],
                );
              },
            ),
            SizedBox(height: 16 * scale),
            Divider(height: 1, color: roles.subtleBorder),
            ExpansionTile(
              key: const PageStorageKey('diagnostic-technical-details'),
              tilePadding: EdgeInsets.zero,
              minTileHeight: 48 * scale,
              title: Text(
                'Technical details',
                style: TextStyle(
                  color: roles.primaryText,
                  fontSize: 16 * scale,
                  fontWeight: FontWeight.w500,
                ),
              ),
              childrenPadding: EdgeInsets.only(bottom: 20 * scale),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _technicalDetails(context, snapshot, telemetry, scale),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _technicalDetails(
    BuildContext context,
    DiagnosticSupportSnapshot snapshot,
    PlayerTelemetry? telemetry,
    double scale,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final roles = LineupTheme.of(context);
        final wide =
            constraints.maxWidth >= 1100 * scale * _effectiveTextScale(context);
        final gap = 24 * scale;
        final narrowGroup = wide
            ? (constraints.maxWidth - 2 * gap) / 4
            : constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: gap,
              runSpacing: 20 * scale,
              children: [
                SizedBox(
                  width: narrowGroup,
                  child: _technicalGroup(context, 'Application', [
                    _technicalFact(
                      'Lineup',
                      '${snapshot.appVersion} · build ${snapshot.appBuild}',
                      scale,
                    ),
                    _technicalFact('Platform', snapshot.platform, scale),
                  ], scale),
                ),
                SizedBox(
                  width: narrowGroup,
                  child: _technicalGroup(context, 'Video output', [
                    _technicalFact(
                      'Hardware decoder',
                      telemetry?.hardwareDecoder ?? 'Unavailable',
                      scale,
                    ),
                    _technicalFact(
                      'Video output',
                      telemetry?.videoOutput ?? 'Unavailable',
                      scale,
                    ),
                  ], scale),
                ),
                SizedBox(
                  width: wide ? 2 * narrowGroup : constraints.maxWidth,
                  child: _technicalGroup(context, 'Media signal', [
                    _technicalFact(
                      'Transfer',
                      telemetry?.gamma ?? 'Unavailable',
                      scale,
                    ),
                    _technicalFact(
                      'Pixel format',
                      telemetry?.pixelFormat ?? 'Unavailable',
                      scale,
                    ),
                    _technicalFact(
                      'Primaries',
                      telemetry?.primaries ?? 'Unavailable',
                      scale,
                    ),
                    _technicalFact(
                      'Color matrix',
                      telemetry?.colorMatrix ?? 'Unavailable',
                      scale,
                    ),
                    _technicalFact(
                      'Reported signal peak',
                      telemetry?.signalPeak?.toString() ?? 'Unavailable',
                      scale,
                    ),
                  ], scale),
                ),
              ],
            ),
            SizedBox(height: 20 * scale),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Per-stream handling · ',
                    style: TextStyle(color: roles.secondaryText),
                  ),
                  TextSpan(
                    text: 'Unavailable',
                    style: TextStyle(color: roles.primaryText),
                  ),
                ],
              ),
              style: TextStyle(fontSize: 16 * scale),
            ),
            SizedBox(height: 16 * scale),
            Text(
              'Media signal values do not verify display HDR output.',
              style: TextStyle(
                color: LineupTheme.of(context).secondaryText,
                fontSize: 14 * scale,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _technicalGroup(
    BuildContext context,
    String title,
    List<Widget> facts,
    double scale,
  ) {
    final roles = LineupTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: roles.primaryText,
            fontSize: 16 * scale,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 10 * scale),
        LayoutBuilder(
          builder: (context, constraints) {
            final gap = 24 * scale;
            final effectiveTextScale = _effectiveTextScale(context);
            final columns =
                constraints.maxWidth >= 800 * scale * effectiveTextScale
                ? 3
                : constraints.maxWidth >= 500 * scale * effectiveTextScale
                ? 2
                : 1;
            final width = columns == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: 16 * scale,
              children: [
                for (final fact in facts) SizedBox(width: width, child: fact),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _technicalFact(String label, String value, double scale) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          color: LineupTheme.of(context).secondaryText,
          fontSize: 14 * scale,
        ),
      ),
      SizedBox(height: 4 * scale),
      Text(value, style: TextStyle(fontSize: 16 * scale)),
    ],
  );

  Widget _eventsHeader(
    BuildContext context,
    DiagnosticSupportSnapshot snapshot,
    List<DiagnosticEntry> currentEvents,
    int unseen,
    double scale,
  ) {
    final roles = LineupTheme.of(context);
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent events',
          style: TextStyle(fontSize: 24 * scale, fontWeight: FontWeight.w500),
        ),
        SizedBox(height: 4 * scale),
        Text(
          '${_visibleEvents.length} events · newest first',
          style: TextStyle(color: roles.secondaryText, fontSize: 14 * scale),
        ),
      ],
    );
    final buttonStyle = TextButton.styleFrom(
      foregroundColor: roles.secondaryText,
      minimumSize: Size(0, 48 * scale),
      padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 8 * scale),
      textStyle: Theme.of(context).textTheme.labelLarge
          ?.copyWith(fontSize: 16 * scale),
    );
    final actions = Wrap(
      spacing: 16 * scale,
      runSpacing: 8 * scale,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Recording ${snapshot.recordingEnabled ? 'On' : 'Off'}',
          style: TextStyle(color: roles.secondaryText, fontSize: 14 * scale),
        ),
        TextButton(
          onPressed: widget.onRecordingSettings,
          style: buttonStyle,
          child: const Text('Recording settings'),
        ),
        SizedBox(
          width: 170 * scale,
          child: Visibility(
            visible: unseen > 0,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: TextButton(
              onPressed: () => setState(
                () => _visibleEvents = currentEvents.reversed.toList(),
              ),
              style: buttonStyle,
              child: Text('$unseen new ${unseen == 1 ? 'event' : 'events'}'),
            ),
          ),
        ),
      ],
    );
    final effectiveTextScale = _effectiveTextScale(context);
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth < 1000 * scale * effectiveTextScale
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                title,
                SizedBox(height: 8 * scale),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: title),
                actions,
              ],
            ),
    );
  }

  Widget _emptyEvents(String title, String message, double scale) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 20 * scale, fontWeight: FontWeight.w500),
        ),
        SizedBox(height: 8 * scale),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16 * scale),
        ),
      ],
    ),
  );

  // Use a local 24-hour clock with seconds so closely spaced events remain distinct.
  String _eventTime(DateTime time) {
    final local = time.toLocal();
    return [
      local.hour,
      local.minute,
      local.second,
    ].map((part) => part.toString().padLeft(2, '0')).join(':');
  }

  Widget _eventTile(DiagnosticEntry event, double scale) => Semantics(
    label:
        '${MaterialLocalizations.of(context).formatFullDate(event.time.toLocal())}, ${_eventTime(event.time)}. ${event.area}: ${event.message}',
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: LineupTheme.of(context).subtleBorder),
        ),
      ),
      child: ExpansionTile(
        key: ObjectKey(event),
        tilePadding: EdgeInsets.symmetric(horizontal: 16 * scale),
        minTileHeight: 64 * scale,
        title: ExcludeSemantics(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final eventScale = scale * _effectiveTextScale(context);
              final gap = 16 * eventScale;
              final time = Text(
                _eventTime(event.time),
                style: TextStyle(
                  color: LineupTheme.of(context).secondaryText,
                  fontSize: 14 * scale,
                ),
              );
              final area = Text(
                event.area,
                style: TextStyle(
                  color: LineupTheme.of(context).secondaryText,
                  fontSize: 14 * scale,
                ),
              );
              final message = Text(
                event.message,
                style: TextStyle(fontSize: 16 * scale),
              );
              if (constraints.maxWidth < 520 * eventScale) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: gap,
                      runSpacing: 4 * eventScale,
                      children: [time, area],
                    ),
                    SizedBox(height: 4 * eventScale),
                    message,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  SizedBox(width: 104 * eventScale, child: time),
                  SizedBox(width: gap),
                  SizedBox(width: 120 * eventScale, child: area),
                  SizedBox(width: gap),
                  Expanded(child: message),
                ],
              );
            },
          ),
        ),
        childrenPadding: EdgeInsets.zero,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [_eventDetails(event, scale)],
      ),
    ),
  );

  Widget _eventDetails(DiagnosticEntry event, double scale) => LayoutBuilder(
    builder: (context, constraints) {
      final eventScale = scale * _effectiveTextScale(context);
      final compact = constraints.maxWidth < 720 * eventScale;
      return SizedBox(
        width: constraints.maxWidth,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 16 * scale : 16 * scale + 256 * eventScale,
            0,
            16 * scale,
            16 * scale,
          ),
          child: event.context.isEmpty
              ? Text(
                  'No additional details',
                  style: TextStyle(fontSize: 16 * scale),
                )
              : Wrap(
                  spacing: 24 * scale,
                  runSpacing: 8 * scale,
                  children: [
                    for (final fact in event.context.entries)
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${_eventFactLabel(fact.key)}: ',
                              style: TextStyle(
                                color: LineupTheme.of(context).secondaryText,
                                fontSize: 16 * scale,
                              ),
                            ),
                            TextSpan(
                              text:
                                  fact.key == 'operation' &&
                                      fact.value == 'seek'
                                  ? 'Seek'
                                  : '${fact.value}',
                              style: TextStyle(
                                color: LineupTheme.of(context).primaryText,
                                fontSize: 16 * scale,
                              ),
                            ),
                          ],
                        ),
                        style: TextStyle(fontSize: 16 * scale),
                      ),
                  ],
                ),
        ),
      );
    },
  );

  String _eventFactLabel(String key) => switch (key) {
    'operation' => 'Operation',
    'code' => 'Code',
    'failureCode' => 'Failure code',
    'httpStatus' => 'HTTP status',
    'count' => 'Count',
    'container' => 'Container',
    'videoCodec' => 'Video codec',
    'audioCodec' => 'Audio codec',
    'dynamicRange' => 'Dynamic range',
    'videoOutput' => 'Video output',
    'hardwareDecoder' => 'Hardware decoder',
    _ => key,
  };

  Widget _fact(
    BuildContext context,
    String title,
    String value,
    double width,
    double scale,
  ) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: LineupTheme.of(context).secondaryText,
            fontSize: 16 * scale,
          ),
        ),
        SizedBox(height: 8 * scale),
        Text(
          value,
          style: TextStyle(
            color: LineupTheme.of(context).primaryText,
            fontSize: 22 * scale,
            fontWeight: FontWeight.w500,
            height: 1.2,
          ),
        ),
      ],
    ),
  );

  String _methodLabel(DiagnosticPlaybackMethod method) => switch (method) {
    DiagnosticPlaybackMethod.unknown => 'Method unavailable',
    DiagnosticPlaybackMethod.directPlay => 'Direct Play',
    DiagnosticPlaybackMethod.directStream => 'Direct Stream',
    DiagnosticPlaybackMethod.transcode => 'Transcode',
  };

  String _playbackLabel(PlayerState state) => switch (state) {
    PlayerState.idle => 'Idle',
    PlayerState.loading => 'Loading',
    PlayerState.ready => 'Ready',
    PlayerState.playing => 'Playing',
    PlayerState.paused => 'Paused',
    PlayerState.buffering => 'Buffering',
    PlayerState.seeking => 'Seeking',
    PlayerState.ended => 'Ended',
    PlayerState.stopped => 'Stopped',
    PlayerState.error => 'Error',
    PlayerState.unsupported => 'Unsupported',
  };

  String _mediaSignal(PlayerTelemetry? telemetry) {
    if (telemetry == null) return 'Unavailable';
    final values = [
      telemetry.gamma,
      telemetry.primaries,
    ].whereType<String>().where((value) => value.isNotEmpty).toList();
    return values.isEmpty ? 'Unavailable' : values.join(' · ');
  }
}
