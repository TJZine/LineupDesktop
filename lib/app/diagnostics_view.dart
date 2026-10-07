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
    final snapshot = _snapshot();
    final telemetry = snapshot.playback.receivedTelemetry;
    final currentEvents = widget.controller.diagnostics.entries;
    final unseen = currentEvents
        .where((event) => !_visibleEvents.contains(event))
        .length;
    return IconTheme.merge(
      data: IconThemeData(size: 24),
      child: FocusTraversalGroup(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LineupTopBar(
                menuKey: const Key('diagnostics-app-menu'),
                menuFocusNode: widget.menuFocusNode,
                onOpenMenu: widget.onOpenMenu,
              ),
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: LineupContentWidth(
                    vertical: 24,
                    child: ListView(
                      controller: _scroll,
                      children: [
                        _diagnosticsIntro(context),
                        SizedBox(height: 28),
                        _summary(context, snapshot, telemetry),
                        SizedBox(height: 32),
                        _eventsHeader(context, snapshot, currentEvents, unseen),
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
                        SizedBox(height: 12),
                        Text(
                          'This session only · Up to 250 recent events retained',
                          style: TextStyle(
                            color: LineupTheme.of(context).secondaryText,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Reports exclude credentials, URLs and private paths. Review before sharing.',
                          style: TextStyle(
                            color: LineupTheme.of(context).secondaryText,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 16),
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

  Widget _diagnosticsIntro(BuildContext context) {
    final roles = LineupTheme.of(context);
    final copyAction = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FilledButton(
          focusNode: widget.focusNode,
          onPressed: _copying ? null : _copy,
          child: Text('Copy redacted report', style: TextStyle(fontSize: 18)),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: 40 * _effectiveTextScale(context),
            minWidth: 300,
            maxWidth: 300,
          ),
          child: Align(
            alignment: Alignment.topRight,
            child: Semantics(
              liveRegion: true,
              child: Text(
                _copyFeedback ?? '',
                textAlign: TextAlign.end,
                style: TextStyle(color: roles.secondaryText, fontSize: 14),
              ),
            ),
          ),
        ),
      ],
    );
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.onBack != null)
          LineupInlineLink(
            onPressed: widget.onBack,
            child: const Text('‹ Settings · Support'),
          ),
        Text(
          'Diagnostics',
          style: LineupTypography.pageTitle.copyWith(color: roles.primaryText),
        ),
        SizedBox(height: 5),
        Text(
          'Playback information and recent support events.',
          style: TextStyle(color: roles.secondaryText, fontSize: 18),
        ),
      ],
    );
    final effectiveTextScale = _effectiveTextScale(context);
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth < 720 * effectiveTextScale
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                SizedBox(height: 20),
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
        padding: EdgeInsets.fromLTRB(28, 24, 28, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final double gap = 28;
                final effectiveTextScale = _effectiveTextScale(context);
                final columns =
                    constraints.maxWidth >= 1100 * effectiveTextScale
                    ? 4
                    : constraints.maxWidth >= 600 * effectiveTextScale
                    ? 2
                    : 1;
                final width = columns == 1
                    ? constraints.maxWidth
                    : (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: 20,
                  children: [
                    for (final fact in facts)
                      _fact(context, fact.$1, fact.$2, width),
                  ],
                );
              },
            ),
            SizedBox(height: 16),
            Divider(height: 1, color: roles.subtleBorder),
            ExpansionTile(
              key: const PageStorageKey('diagnostic-technical-details'),
              tilePadding: EdgeInsets.zero,
              minTileHeight: 48,
              title: Text(
                'Technical details',
                style: TextStyle(
                  color: roles.primaryText,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              childrenPadding: EdgeInsets.only(bottom: 20),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [_technicalDetails(context, snapshot, telemetry)],
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
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final roles = LineupTheme.of(context);
        final wide =
            constraints.maxWidth >= 1100 * _effectiveTextScale(context);
        final double gap = 24;
        final narrowGroup = wide
            ? (constraints.maxWidth - 2 * gap) / 4
            : constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: gap,
              runSpacing: 20,
              children: [
                SizedBox(
                  width: narrowGroup,
                  child: _technicalGroup(context, 'Application', [
                    _technicalFact(
                      'Lineup',
                      '${snapshot.appVersion} · build ${snapshot.appBuild}',
                    ),
                    _technicalFact('Platform', snapshot.platform),
                  ]),
                ),
                SizedBox(
                  width: narrowGroup,
                  child: _technicalGroup(context, 'Video output', [
                    _technicalFact(
                      'Hardware decoder',
                      telemetry?.hardwareDecoder ?? 'Unavailable',
                    ),
                    _technicalFact(
                      'Video output',
                      telemetry?.videoOutput ?? 'Unavailable',
                    ),
                  ]),
                ),
                SizedBox(
                  width: wide ? 2 * narrowGroup : constraints.maxWidth,
                  child: _technicalGroup(context, 'Media signal', [
                    _technicalFact(
                      'Transfer',
                      telemetry?.gamma ?? 'Unavailable',
                    ),
                    _technicalFact(
                      'Pixel format',
                      telemetry?.pixelFormat ?? 'Unavailable',
                    ),
                    _technicalFact(
                      'Primaries',
                      telemetry?.primaries ?? 'Unavailable',
                    ),
                    _technicalFact(
                      'Color matrix',
                      telemetry?.colorMatrix ?? 'Unavailable',
                    ),
                    _technicalFact(
                      'Reported signal peak',
                      telemetry?.signalPeak?.toString() ?? 'Unavailable',
                    ),
                  ]),
                ),
              ],
            ),
            SizedBox(height: 20),
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
              style: TextStyle(fontSize: 18),
            ),
            SizedBox(height: 16),
            Text(
              'Media signal values do not verify display HDR output.',
              style: TextStyle(
                color: LineupTheme.of(context).secondaryText,
                fontSize: 14,
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
  ) {
    final roles = LineupTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: roles.primaryText,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final double gap = 24;
            final effectiveTextScale = _effectiveTextScale(context);
            final columns = constraints.maxWidth >= 800 * effectiveTextScale
                ? 3
                : constraints.maxWidth >= 500 * effectiveTextScale
                ? 2
                : 1;
            final width = columns == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: 16,
              children: [
                for (final fact in facts) SizedBox(width: width, child: fact),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _technicalFact(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          color: LineupTheme.of(context).secondaryText,
          fontSize: 14,
        ),
      ),
      SizedBox(height: 4),
      Text(value, style: TextStyle(fontSize: 18)),
    ],
  );

  Widget _eventsHeader(
    BuildContext context,
    DiagnosticSupportSnapshot snapshot,
    List<DiagnosticEntry> currentEvents,
    int unseen,
  ) {
    final roles = LineupTheme.of(context);
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent events',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
        ),
        SizedBox(height: 4),
        Text(
          '${_visibleEvents.length} events · newest first',
          style: TextStyle(color: roles.secondaryText, fontSize: 14),
        ),
      ],
    );

    final actions = Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Recording ${snapshot.recordingEnabled ? 'On' : 'Off'}',
          style: TextStyle(color: roles.secondaryText, fontSize: 14),
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
                () => _visibleEvents = currentEvents.reversed.toList(),
              ),
              child: Text('$unseen new ${unseen == 1 ? 'event' : 'events'}'),
            ),
          ),
        ),
      ],
    );
    final effectiveTextScale = _effectiveTextScale(context);
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth < 1000 * effectiveTextScale
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                title,
                SizedBox(height: 8),
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

  Widget _emptyEvents(String title, String message) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
        ),
        SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18),
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

  Widget _eventTile(DiagnosticEntry event) => Semantics(
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
        tilePadding: EdgeInsets.symmetric(horizontal: 16),
        minTileHeight: 64,
        title: ExcludeSemantics(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final eventScale = 1.0 * _effectiveTextScale(context);
              final double gap = 16 * eventScale;
              final time = Text(
                _eventTime(event.time),
                style: TextStyle(
                  color: LineupTheme.of(context).secondaryText,
                  fontSize: 14,
                ),
              );
              final area = Text(
                event.area,
                style: TextStyle(
                  color: LineupTheme.of(context).secondaryText,
                  fontSize: 14,
                ),
              );
              final message = Text(
                event.message,
                style: TextStyle(fontSize: 18),
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
        children: [_eventDetails(event)],
      ),
    ),
  );

  Widget _eventDetails(DiagnosticEntry event) => LayoutBuilder(
    builder: (context, constraints) {
      final eventScale = 1.0 * _effectiveTextScale(context);
      final compact = constraints.maxWidth < 720 * eventScale;
      return SizedBox(
        width: constraints.maxWidth,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : 16 + 256 * eventScale,
            0,
            16,
            16,
          ),
          child: event.context.isEmpty
              ? Text('No additional details', style: TextStyle(fontSize: 18))
              : Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: [
                    for (final fact in event.context.entries)
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${_eventFactLabel(fact.key)}: ',
                              style: TextStyle(
                                color: LineupTheme.of(context).secondaryText,
                                fontSize: 18,
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
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                        style: TextStyle(fontSize: 18),
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
  ) => SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: LineupTheme.of(context).secondaryText,
            fontSize: 18,
          ),
        ),
        SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            color: LineupTheme.of(context).primaryText,
            fontSize: 22,
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
