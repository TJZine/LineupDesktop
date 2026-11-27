import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:lineup_desktop/platform/device_profile.dart';

import '../app_version.dart';
import '../diagnostics/diagnostics.dart';
import '../playback/native_player.dart';
import '../ui/app_theme.dart';
import '../ui/app_ui.dart';
import 'lineup_controller.dart';

class DiagnosticsView extends StatefulWidget {
  const DiagnosticsView({
    required this.controller,
    required this.playback,
    required this.onRecordingSettings,
    this.onOpenMenu,
    this.menuFocusNode,
    this.focusNode,
    this.onBack,
    this.backLabel = '‹ Settings · Support',
    super.key,
  });

  final LineupController controller;
  final PlaybackDiagnosticSnapshot playback;
  final VoidCallback onRecordingSettings;
  final LineupMenuCallback? onOpenMenu;
  final FocusNode? menuFocusNode;
  final FocusNode? focusNode;
  final VoidCallback? onBack;
  final String backLabel;

  @override
  State<DiagnosticsView> createState() => _DiagnosticsViewState();
}

class _DiagnosticsViewState extends State<DiagnosticsView> {
  final _scroll = ScrollController();
  final _technicalExpansion = ExpansibleController();
  final _technicalStates = WidgetStatesController();
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
    _technicalStates.dispose();
    _technicalExpansion.dispose();
    _scroll.dispose();
    super.dispose();
  }

  KeyEventResult _readTechnicalDetails(FocusNode _, KeyEvent event) {
    if (!DeviceProfile.of(context).isTv ||
        !_technicalExpansion.isExpanded ||
        !_scroll.hasClients ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final amount = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => 48.0,
      LogicalKeyboardKey.arrowUp => -48.0,
      _ => null,
    };
    if (amount == null) return KeyEventResult.ignored;
    final position = _scroll.position;
    final target = (position.pixels + amount).clamp(
      0.0,
      position.maxScrollExtent,
    );
    if (target == position.pixels) return KeyEventResult.ignored;
    // The expanded toggle remains the reading owner. Moving its viewport also
    // builds lazy controls below the long readonly panel. At either edge the
    // ordinary focus traversal resumes; Select and Back retain their actions.
    position.jumpTo(target);
    return KeyEventResult.handled;
  }

  DiagnosticSupportSnapshot _snapshot() {
    final now = DateTime.now();
    return widget.controller.diagnostics.snapshot(
      reportTime: now,
      timeZone: now.timeZoneName,
      appVersion: lineupVersionDefined ? lineupVersion : 'Unavailable',
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
    final noticeStyle = TextStyle(
      color: LineupTheme.of(context).secondaryText,
      fontSize: DeviceProfile.of(context).isTv
          ? LineupTypography.tvTextFloor
          : 14,
    );
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
                          ConstrainedBox(
                            key: const Key('diagnostics-recording-off'),
                            constraints: const BoxConstraints(minHeight: 180),
                            child: LineupEmptyState(
                              title: 'Diagnostic recording is off',
                              message: 'Turn on recording, then reproduce the issue.',
                              action: TextButton(
                                key: const Key(
                                  'diagnostics-recording-settings-message',
                                ),
                                onPressed: widget.onRecordingSettings,
                                child: Text(
                                  'Recording settings',
                                  style: LineupTypography.tvLabelStyle(context),
                                ),
                              ),
                            ),
                          )
                        else if (_visibleEvents.isEmpty)
                          SizedBox(
                            height: 180,
                            child: LineupEmptyState(
                              title: 'No events recorded yet',
                              message: 'Reproduce the issue to collect support events.',
                            ),
                          )
                        else
                          for (final event in _visibleEvents) _eventTile(event),
                        SizedBox(height: 12),
                        Text(
                          'This session only · Up to 250 recent events retained',
                          style: noticeStyle,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Reports exclude credentials, URLs and private paths. Review before sharing.',
                          style: noticeStyle,
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
          child: Text(
            'Copy redacted report',
            style: TextStyle(
              fontSize: DeviceProfile.of(context).isTv
                  ? LineupTypography.tvTextFloor
                  : 18,
            ),
          ),
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
            child: Text(widget.backLabel),
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
    final idle = switch (snapshot.playback.state) {
      PlayerState.idle || PlayerState.stopped || PlayerState.ended => true,
      _ => false,
    };
    final connection = widget.controller.connection;
    final picture = telemetry?.gamma == null || telemetry!.gamma!.isEmpty
        ? 'Unknown'
        : telemetry.isHdr
        ? 'HDR'
        : 'SDR';
    final facts = [
      (
        'Playback',
        _playbackLabel(snapshot.playback.state),
        snapshot.playback.method == DiagnosticPlaybackMethod.unknown
            ? null
            : _methodLabel(snapshot.playback.method),
      ),
      (
        'Video',
        (telemetry?.width ?? 0) > 0 && (telemetry?.height ?? 0) > 0
            ? '${telemetry!.width} × ${telemetry.height}'
            : 'Unavailable',
        [
          if (telemetry?.videoCodec != null)
            telemetry!.videoCodec!.toUpperCase(),
          if (telemetry?.hardwareDecoder != null) telemetry!.hardwareDecoder!,
        ].join(' · '),
      ),
      (
        'Picture',
        picture,
        [
          telemetry?.gamma,
          telemetry?.primaries,
          if (telemetry?.videoFormat?.toLowerCase().contains('dolby') == true)
            telemetry?.videoFormat,
        ].whereType<String>().map(_signalValue).join(' · '),
      ),
      (
        'Plex',
        snapshot.plexServerSelected
            ? (snapshot.plexConnectionVerified
                  ? 'Connection verified'
                  : 'Connection unverified')
            : 'No server selected',
        connection == null
            ? null
            : LineupConnectionStatus.description(connection),
      ),
    ];
    return Material(
      color: roles.primarySurface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: roles.subtleBorder),
        borderRadius: BorderRadius.circular(roles.panelRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (idle)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
              child: Text(
                'Nothing is playing. Start a channel to see playback details.',
                style: TextStyle(color: roles.secondaryText, fontSize: 18),
              ),
            )
          else
            Padding(
              padding: EdgeInsets.fromLTRB(28, 24, 28, 0),
              child: LayoutBuilder(
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
                  final cards = [
                    for (final fact in facts)
                      _fact(context, fact.$1, fact.$2, fact.$3, width),
                  ];
                  return columns == 4
                      ? IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var i = 0; i < cards.length; i++) ...[
                                if (i > 0) SizedBox(width: gap),
                                cards[i],
                              ],
                            ],
                          ),
                        )
                      : Wrap(spacing: gap, runSpacing: 20, children: cards);
                },
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(28, 16, 28, 0),
            child: Divider(height: 1, color: roles.subtleBorder),
          ),
          Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _readTechnicalDetails,
            child: ListenableBuilder(
              listenable: _technicalStates,
              builder: (context, _) {
                final fill =
                    DeviceProfile.of(context).isTv &&
                    roles.focusTreatment == LineupFocusTreatment.fill &&
                    LineupFocusScope.visible(
                      context,
                      _technicalStates.value.contains(WidgetState.focused),
                    );
                final tileTheme = ListTileTheme.of(context);
                return ListTileTheme(
                  data: tileTheme.copyWith(
                    tileColor: fill
                        ? roles.focusedSurface
                        : tileTheme.tileColor,
                    shape:
                        LineupFocusFrame.shape(context, focused: fill) ??
                        tileTheme.shape,
                  ),
                  child: ExpansionTile(
                    controller: _technicalExpansion,
                    statesController: _technicalStates,
                    key: const PageStorageKey('diagnostic-technical-details'),
                    tilePadding: EdgeInsets.only(left: 28),
                    minTileHeight: 48,
                    iconColor: fill ? roles.onFocus : null,
                    collapsedIconColor: fill ? roles.onFocus : null,
                    title: LineupFocusInk(
                      focused: fill,
                      child: Builder(
                        builder: (context) => Text(
                          'Technical details',
                          style: TextStyle(
                            color: LineupTheme.of(context).primaryText,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    childrenPadding: EdgeInsets.fromLTRB(28, 0, 28, 28),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [_technicalDetails(context, snapshot, telemetry)],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _technicalDetails(
    BuildContext context,
    DiagnosticSupportSnapshot snapshot,
    PlayerTelemetry? telemetry,
  ) {
    final isMacOS = Diagnostics.isMacOSPlatform(snapshot.platform);
    final isWindows = snapshot.platform == TargetPlatform.windows.name;
    final isAndroid = snapshot.platform == TargetPlatform.android.name;
    final hasDesktopOutput = isMacOS || isWindows;
    return LayoutBuilder(
      builder: (context, constraints) {
        final roles = LineupTheme.of(context);
        final effectiveTextScale = _effectiveTextScale(context);
        final gap = 28.0;
        final columns = constraints.maxWidth >= 1100 * effectiveTextScale
            ? 4
            : constraints.maxWidth >= 600 * effectiveTextScale
            ? 2
            : 1;
        final columnWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - gap * (columns - 1)) / columns;
        Widget group(String name, List<Widget> facts) => SizedBox(
          key: ValueKey('diagnostics-technical-$name'),
          width: columnWidth,
          child: _technicalGroup(context, name, facts),
        );
        final build = snapshot.appBuild;
        final commit = RegExp(r'[0-9a-fA-F]{7,40}').firstMatch(build)?.group(0);
        return Wrap(
          spacing: gap,
          runSpacing: 24,
          children: [
            group('Application', [
              _technicalFact('Lineup version', snapshot.appVersion),
              _technicalFact(
                'Commit',
                commit == null
                    ? build
                    : commit.substring(0, math.min(8, commit.length)),
              ),
              _technicalFact('Platform', snapshot.platform),
              _technicalFact(
                'Plex connection',
                LineupConnectionStatus.description(
                  widget.controller.connection,
                ),
              ),
            ]),
            group('Video output', [
              _technicalFact(
                isAndroid ? 'Video decoder' : 'Hardware decoder',
                telemetry?.hardwareDecoder ?? 'Unavailable',
              ),
              if (!isAndroid)
                _technicalFact(
                  'Video output',
                  telemetry?.videoOutput ?? 'Unavailable',
                ),
            ]),
            group('Media signal', [
              _technicalFact('Transfer', _signalValue(telemetry?.gamma)),
              if (!isAndroid)
                _technicalFact(
                  'Pixel format',
                  telemetry?.pixelFormat ?? 'Unavailable',
                ),
              _technicalFact('Primaries', _signalValue(telemetry?.primaries)),
              if (!isAndroid)
                _technicalFact(
                  'Color matrix',
                  _signalValue(telemetry?.colorMatrix),
                ),
              if (!isAndroid)
                _technicalFact(
                  'Reported signal peak',
                  telemetry?.signalPeak?.toStringAsFixed(2) ?? 'Unavailable',
                ),
            ]),
            if (hasDesktopOutput)
              group('Display', [
                if (isMacOS)
                  _technicalFact('HDR output', Diagnostics.macOSHdrOutputFact),
                if (isWindows) ...[
                  _technicalFact(
                    'Windows display',
                    Diagnostics.windowsDisplayFact(
                      snapshot.playback.displayReport,
                    ),
                  ),
                  _technicalFact(
                    'HDR matching',
                    Diagnostics.hdrMatchingFact(
                      snapshot.playback.displayReport,
                    ),
                  ),
                ],
                _technicalFact(
                  'Renderer output',
                  Diagnostics.rendererOutputFact(telemetry),
                ),
                _technicalFact('Per-stream handling', 'Unavailable'),
                Text(
                  isMacOS
                      ? Diagnostics.macOSDisplayStateNote
                      : Diagnostics.windowsDisplayStateNote,
                  style: TextStyle(color: roles.secondaryText, fontSize: 14),
                ),
              ]),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(
            color: roles.primaryText,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        for (final fact in facts)
          Padding(padding: const EdgeInsets.only(bottom: 16), child: fact),
      ],
    );
  }

  Widget _technicalFact(String label, String value) => KeyedSubtree(
    key: ValueKey('diagnostics-technical-fact-$label'),
    child: Column(
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
    ),
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

    final newEvents = SizedBox(
      key: const ValueKey('diagnostics-new-events-slot'),
      width: 170,
      height: 44,
      child: Visibility(
        visible: unseen > 0,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: Align(
          alignment: Alignment.centerRight,
          child: LineupCompactControls(
            child: TextButton(
              style: ButtonStyle(
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
              onPressed: () => setState(
                () => _visibleEvents = currentEvents.reversed.toList(),
              ),
              child: Text(
                '$unseen new ${unseen == 1 ? 'event' : 'events'}',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
    final recording = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: snapshot.recordingEnabled
                ? roles.progressFill
                : roles.mutedText,
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(width: 8),
        Text(
          'Recording ${snapshot.recordingEnabled ? 'on' : 'off'}',
          style: TextStyle(
            color: roles.secondaryText,
            fontSize: DeviceProfile.of(context).isTv
                ? LineupTypography.tvTextFloor
                : 14,
          ),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        newEvents,
        recording,
        TextButton(
          key: const Key('diagnostics-recording-settings-header'),
          onPressed: widget.onRecordingSettings,
          child: const Text('Recording settings'),
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

  String _eventTime(DateTime time) {
    final local = time.toLocal();
    return [
      local.hour,
      local.minute,
      local.second,
    ].map((part) => part.toString().padLeft(2, '0')).join(':');
  }

  Widget _eventTile(DiagnosticEntry event) {
    final area = _eventAreaLabel(event.area);
    return Semantics(
      label:
          '${MaterialLocalizations.of(context).formatFullDate(event.time.toLocal())}, ${_eventTime(event.time)}. $area: ${event.message}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: LineupTheme.of(context).subtleBorder),
          ),
        ),
        child: ExpansionTile(
          key: ObjectKey(event),
          tilePadding: EdgeInsets.zero,
          minTileHeight: 64,
          title: ExcludeSemantics(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isTv = DeviceProfile.of(context).isTv;
                final eventScale = 1.0 * _effectiveTextScale(context);
                final double gap = 16 * eventScale;
                final time = Text(
                  _eventTime(event.time),
                  style: TextStyle(
                    color: LineupTheme.of(context).secondaryText,
                    fontSize: isTv ? LineupTypography.tvTextFloor : 14,
                  ),
                );
                final area = Text(
                  _eventAreaLabel(event.area),
                  style: TextStyle(
                    color: LineupTheme.of(context).secondaryText,
                    fontSize: isTv ? LineupTypography.tvTextFloor : 14,
                  ),
                );
                final message = Text(
                  event.message,
                  style: TextStyle(
                    fontSize: isTv ? LineupTypography.tvTextFloor : 18,
                  ),
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
  }

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

  String _eventAreaLabel(String area) {
    final words = area.split('-').where((word) => word.isNotEmpty).toList();
    if (words.isEmpty) return area;
    final formatted = <String>[];
    for (var index = 0; index < words.length; index++) {
      final word = words[index].toLowerCase();
      formatted.add(
        index == 0 ? '${word[0].toUpperCase()}${word.substring(1)}' : word,
      );
    }
    return formatted.join(' ');
  }

  Widget _fact(
    BuildContext context,
    String title,
    String value,
    String? supporting,
    double width,
  ) => Container(
    key: ValueKey('diagnostics-summary-$title'),
    width: width,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: LineupTheme.of(context).elevatedSurface,
      border: Border.all(color: LineupTheme.of(context).subtleBorder),
      borderRadius: BorderRadius.circular(LineupTheme.of(context).panelRadius),
    ),
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
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            color: LineupTheme.of(context).primaryText,
            fontSize: 24,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
        if (supporting != null && supporting.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            supporting,
            style: TextStyle(
              color: LineupTheme.of(context).secondaryText,
              fontSize: 16,
            ),
          ),
        ],
      ],
    ),
  );

  String _signalValue(String? value) => switch (value?.toLowerCase()) {
    null || '' => 'Unavailable',
    'pq' => 'PQ',
    'hlg' => 'HLG',
    'bt.2020' || 'bt2020' => 'BT.2020',
    _ => value!,
  };

  String _methodLabel(DiagnosticPlaybackMethod method) => switch (method) {
    DiagnosticPlaybackMethod.unknown => '',
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
}
