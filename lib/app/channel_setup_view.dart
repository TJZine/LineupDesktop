import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channels/channel.dart';
import '../channels/channel_builder.dart';
import '../plex/plex_models.dart';
import '../ui/app_theme.dart';
import '../ui/app_ui.dart';
import 'form_error.dart';
import 'lineup_controller.dart';
import 'lineup_restore_view.dart';
import 'setup_result_atmosphere.dart';

enum _BuildPhase { review, applying, failed, complete }

enum _ReviewKind { unchanged, updated, added, removed }

enum _ReviewFilter { all, unchanged, updated, added, removed }

typedef _ReviewEntry = ({Channel channel, Channel? before, _ReviewKind kind});

class UpstreamChannelSetupView extends StatefulWidget {
  const UpstreamChannelSetupView({
    required this.controller,
    this.onViewLineup,
    this.onAddCustomChannel,
    super.key,
  });

  final LineupController controller;
  final VoidCallback? onViewLineup;
  final VoidCallback? onAddCustomChannel;

  @override
  State<UpstreamChannelSetupView> createState() => _SetupState();
}

class _SetupState extends State<UpstreamChannelSetupView> {
  int _step = 1;
  int _configurationSection = 0;
  final _selectedLibraries = <String>{};
  final _strategies = <BuilderStrategy>{...BuilderStrategy.values};
  final _grouped = <BuilderStrategy>{};
  final _sourceOrder = <BuilderStrategy>[...BuilderStrategy.values];
  final _playbackFocus = {
    for (final mode in PlaybackMode.values)
      mode: FocusNode(debugLabel: 'Setup playback ${mode.name}'),
  };
  final _orderFocus = {
    for (final strategy in BuilderStrategy.values)
      strategy: (earlier: FocusNode(), later: FocusNode()),
  };
  late ChannelBuildMode _mode;
  PlaybackMode _playback = PlaybackMode.shuffle;
  int _blockSize = 3;
  bool _includeSpecials = false;
  bool _extras = false;
  int _alternateCopies = 1;
  PlaybackMode? _variantMode;
  int _variantBlockSize = 3;
  int _maximum = 200;
  int _minimum = 5;
  bool _removalConfirmed = false;
  _BuildPhase _phase = _BuildPhase.review;
  _ReviewFilter _filter = _ReviewFilter.all;
  final _search = TextEditingController();
  final _resultFocus = FocusNode(
    debugLabel: 'Setup result',
    onKeyEvent: (_, event) =>
        event is KeyRepeatEvent &&
            const [
              LogicalKeyboardKey.enter,
              LogicalKeyboardKey.numpadEnter,
              LogicalKeyboardKey.space,
              LogicalKeyboardKey.select,
              LogicalKeyboardKey.gameButtonA,
            ].contains(event.logicalKey)
        ? KeyEventResult.handled
        : KeyEventResult.ignored,
  );
  ChannelPlanAllocation? _plan;
  final _reviewStrategyBySource = <String, BuilderStrategy>{};
  List<Channel> _reviewBase = const [];
  final _removeSourceIds = <String>{};
  bool _discoveryRetry = false;
  List<_ReviewEntry> _appliedEntries = const [];
  String? _notice;
  String? _error;

  bool get _firstSetup => _reviewBase.isEmpty;

  @override
  void initState() {
    super.initState();
    _mode = widget.controller.channels.isEmpty
        ? ChannelBuildMode.replace
        : ChannelBuildMode.merge;
    _selectedLibraries.addAll(
      widget.controller.selectedLibraryIds.isEmpty
          ? widget.controller.libraries.map((library) => library.id)
          : widget.controller.selectedLibraryIds,
    );
  }

  @override
  void dispose() {
    for (final node in _playbackFocus.values) {
      node.dispose();
    }
    for (final nodes in _orderFocus.values) {
      nodes.earlier.dispose();
      nodes.later.dispose();
    }
    _search.dispose();
    _resultFocus.dispose();
    super.dispose();
  }

  List<ChannelProposal> get _proposals {
    final inventory = widget.controller.playableInventory;
    return buildChannelProposals(
      libraries: widget.controller.libraries
          .where((library) => _selectedLibraries.contains(library.id))
          .toList(),
      items: inventory.media,
      playlists: inventory.playlists,
      strategies: _strategies,
      strategyOrder: _sourceOrder,
      crossLibraryStrategies: _grouped,
      minimumItems: _minimum,
      maximumChannels: null,
    );
  }

  ChannelPlanAllocation _allocate(
    List<Channel> existing, {
    List<ChannelProposal>? proposals,
  }) => materializeChannelPlan(
    proposals: proposals ?? _proposals,
    existing: existing,
    mode: _mode,
    seriesMode: _playback,
    seriesBlockSize: _blockSize,
    alternateCopies: _extras ? _alternateCopies : 0,
    variantMode: _extras ? _variantMode : null,
    variantBlockSize: _variantBlockSize,
    includeSpecials: _includeSpecials,
    maximumChannels: _maximum,
    anchor: DateTime.now().toUtc(),
  );

  ChannelPlanAllocation _allocateReview(List<Channel> existing) {
    final proposals = _proposals;
    _removeSourceIds.clear();
    _reviewStrategyBySource.clear();
    for (final proposal in proposals) {
      _reviewStrategyBySource.putIfAbsent(
        canonicalSourceIdentity(proposal.source),
        () => proposal.strategy,
      );
    }
    return _allocate(existing, proposals: proposals);
  }

  @override
  Widget build(BuildContext context) {
    final resultState = _step == 3 && _phase != _BuildPhase.review;
    final page = SafeArea(
      child: IconTheme.merge(
        data: const IconThemeData(size: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LineupTopBar(
              divider:
                  _phase != _BuildPhase.complete &&
                  _phase != _BuildPhase.applying,
              trailing: Align(
                alignment: Alignment.centerRight,
                child: SingleChildScrollView(child: _setupSteps()),
              ),
            ),
            Expanded(
              child: LineupContentWidth(
                key: const ValueKey('channel-setup-content'),
                maxWidth: _step == 1 ? 1040 : 1824,
                vertical: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_step != 1 && !resultState) ...[
                      _header(),
                      const SizedBox(height: 32),
                    ],
                    if (_error != null &&
                        _phase != _BuildPhase.failed &&
                        _step != 1) ...[
                      LineupNotice(message: _error!),
                      const SizedBox(height: 12),
                    ],
                    Expanded(
                      child: KeyedSubtree(
                        key: const ValueKey('channel-setup-stage'),
                        child: switch (_step) {
                          1 => _libraryStep(),
                          2 => _configureStep(),
                          _ =>
                            _phase == _BuildPhase.review
                                ? _reviewStep()
                                : _resultStep(),
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Scaffold(
      body: Material(
        color: LineupTheme.of(context).deepBackground,
        child: resultState
            ? SetupResultAtmosphere(
                applying: _phase == _BuildPhase.applying,
                failed: _phase == _BuildPhase.failed,
                child: page,
              )
            : page,
      ),
    );
  }

  Widget _header() {
    if (_step == 1) {
      return _configurationHeader(
        titleText:
            widget.controller.libraryScanStatus == LibraryScanStatus.scanning
            ? 'Scanning your libraries'
            : _libraryScanSettled
            ? 'Review your libraries'
            : 'Choose libraries',
        subtitleText:
            widget.controller.libraries.isEmpty ||
                _libraryScanSettled ||
                widget.controller.libraryScanStatus ==
                    LibraryScanStatus.scanning
            ? ''
            : _librarySummary(),
      );
    }
    if (_step == 2) return _configurationHeader();
    if (_step == 3 && _phase == _BuildPhase.review) {
      return _configurationHeader(
        titleText: _firstSetup
            ? 'Review your first lineup'
            : 'Review your lineup',
        subtitleText: _firstSetup
            ? 'Check your channels before creating your lineup.'
            : 'Check what changes and what stays.',
      );
    }
    return const SizedBox.shrink();
  }

  Widget _setupSteps() {
    final roles = LineupTheme.of(context);
    final complete = _phase == _BuildPhase.complete;
    return Wrap(
      key: const ValueKey('channel-setup-steps'),
      alignment: WrapAlignment.end,
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final (index, label) in [
          (1, 'Libraries'),
          (2, 'Configure'),
          (3, 'Review'),
        ])
          Text(
            '${complete || index < _step ? "✓" : index} $label',
            style: LineupTypography.body.copyWith(
              color: complete || index == _step
                  ? roles.primaryText
                  : roles.secondaryText,
              fontWeight: complete || index == _step
                  ? FontWeight.w600
                  : FontWeight.w400,
            ),
          ),
      ],
    );
  }

  Widget _configurationHeader({
    String titleText = 'Shape your lineup',
    String? subtitleText,
  }) => Column(
    key: const ValueKey('channel-setup-header'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        header: true,
        child: Text(
          titleText,
          style: LineupTypography.pageTitle.copyWith(
            color: LineupTheme.of(context).primaryText,
          ),
        ),
      ),
      if (subtitleText != '') ...[
        const SizedBox(height: 10),
        Text(
          subtitleText ??
              switch (_configurationSection) {
                0 => 'Choose the channels you want from your libraries.',
                1 => 'Choose how your generated channels will play.',
                _ => 'Choose the size and balance of your generated lineup.',
              },
          style: LineupTypography.body.copyWith(
            height: 1.4,
            color: LineupTheme.of(context).secondaryText,
          ),
        ),
      ],
    ],
  );

  bool get _libraryScanSettled => switch (widget.controller.libraryScanStatus) {
    LibraryScanStatus.complete ||
    LibraryScanStatus.empty ||
    LibraryScanStatus.unsupported ||
    LibraryScanStatus.transientFailure => true,
    _ => false,
  };

  String _librarySummary() {
    final controller = widget.controller;
    final statuses = [
      for (final id in _selectedLibraries)
        controller.libraryScanFacts[id]?.status ?? LibraryScanStatus.idle,
    ];
    int count(LibraryScanStatus status) =>
        statuses.where((value) => value == status).length;
    if (controller.libraryScanStatus == LibraryScanStatus.scanning) {
      final checked = statuses
          .where(
            (status) => const {
              LibraryScanStatus.complete,
              LibraryScanStatus.empty,
              LibraryScanStatus.unsupported,
              LibraryScanStatus.transientFailure,
            }.contains(status),
          )
          .length;
      return '$checked of ${statuses.length} libraries checked';
    }
    if (controller.libraryScanStatus == LibraryScanStatus.cancelled) {
      return 'Your selections are preserved. Scan again when you’re ready.';
    }
    if (!_libraryScanSettled || statuses.isEmpty) {
      return 'Select the Plex libraries to scan for channel ideas.';
    }
    final ready = count(LibraryScanStatus.complete);
    if (ready == 0) {
      return count(LibraryScanStatus.transientFailure) > 0
          ? 'No libraries are ready. Retry failed scans or change your selection.'
          : 'No libraries are ready. Change your selection or scan again.';
    }
    return [
      '$ready ${ready == 1 ? 'library' : 'libraries'} ready',
      if (count(LibraryScanStatus.empty) > 0)
        '${count(LibraryScanStatus.empty)} empty',
      if (count(LibraryScanStatus.unsupported) > 0)
        '${count(LibraryScanStatus.unsupported)} with no playable media',
      if (count(LibraryScanStatus.transientFailure) > 0)
        '${count(LibraryScanStatus.transientFailure)} failed',
      if (count(LibraryScanStatus.idle) > 0)
        '${count(LibraryScanStatus.idle)} not scanned',
    ].join(' · ');
  }

  Widget _libraryStep() {
    final controller = widget.controller;
    final ready = controller.libraryScanReadyIds.intersection(
      _selectedLibraries,
    );
    final retry = controller.libraryScanRetryIds.intersection(
      _selectedLibraries,
    );
    final hasLibraries = controller.libraries.isNotEmpty;
    final scanning = controller.libraryScanStatus == LibraryScanStatus.scanning;
    final canContinue = hasLibraries && !scanning && ready.isNotEmpty;
    final canRetry =
        !scanning &&
        controller.libraryScanStatus != LibraryScanStatus.cancelled &&
        (retry.isNotEmpty || controller.error != null);
    final roles = LineupTheme.of(context);
    final bodyStyle = Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: roles.secondaryText, fontSize: 18, height: 1.4);
    final actionStyle = Theme.of(context).textTheme.labelLarge!
        .copyWith(fontSize: 18);
    final retryLabel = retry.isEmpty ? 'Retry scan' : 'Retry failed scans';
    final scanError = _error ?? controller.error;
    final excluded = _selectedLibraries.length - ready.length;
    final footer = _Footer(
      configuration: true,
      summary: Wrap(
        spacing: 8,
        children: [
          if (hasLibraries)
            TextButton(
              key: const ValueKey('setup-switch-server'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 48),
                alignment: Alignment.centerLeft,
              ),
              onPressed: controller.canSwitchServer
                  ? controller.showServers
                  : null,
              child: Text('Switch server', style: actionStyle),
            ),
          if (!scanning && controller.channelSetupCanCancel)
            TextButton(
              onPressed: controller.cancelChannelSetup,
              child: Text('Cancel', style: actionStyle),
            ),
        ],
      ),
      leading: [
        if (canContinue)
          OutlinedButton(
            key: const ValueKey('scan-again-libraries'),
            onPressed: controller.busy
                ? null
                : () => _scan(advanceWhenReady: false),
            child: const Text('Scan again'),
          ),
        if (canRetry && canContinue)
          OutlinedButton(
            key: const ValueKey('retry-failed-libraries'),
            onPressed: controller.busy
                ? null
                : () => _scan(retryFailedOnly: true),
            child: Text(retryLabel),
          ),
      ],
      trailing: !hasLibraries
          ? FilledButton(
              key: const ValueKey('setup-switch-server'),
              onPressed: controller.canSwitchServer
                  ? controller.showServers
                  : null,
              child: const Text('Switch server'),
            )
          : scanning
          ? TextButton(
              onPressed: controller.cancelLibraryScan,
              child: Text('Cancel scan', style: actionStyle),
            )
          : canContinue
          ? FilledButton(
              key: const ValueKey('continue-ready-libraries'),
              onPressed: controller.busy ? null : () => _commitLibraries(ready),
              child: Text(
                'Continue with ${ready.length} ${ready.length == 1 ? 'library' : 'libraries'}',
              ),
            )
          : canRetry
          ? FilledButton(
              key: const ValueKey('retry-failed-libraries'),
              onPressed: _selectedLibraries.isEmpty || controller.busy
                  ? null
                  : () => _scan(retryFailedOnly: true),
              child: Text(retryLabel),
            )
          : FilledButton(
              key: const ValueKey('scan-selected-libraries'),
              onPressed: _selectedLibraries.isEmpty || controller.busy
                  ? null
                  : _scan,
              child: Text(
                _libraryScanSettled ? 'Scan again' : 'Scan selected libraries',
              ),
            ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final singleScroll =
            constraints.maxHeight < 800 ||
            MediaQuery.textScalerOf(context).scale(1) >= 1.5;
        final list = ListView.separated(
          key: const ValueKey('library-selection-list'),
          shrinkWrap: true,
          physics: singleScroll ? const NeverScrollableScrollPhysics() : null,
          itemCount: controller.libraries.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, index) => _libraryRow(controller.libraries[index]),
        );
        final content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            if (scanning) ...[
              const SizedBox(height: 10),
              LibraryScanPhaseStatus(controller: controller, centered: false),
            ],
            SizedBox(height: 32),
            if (controller.libraries.isEmpty)
              Padding(
                padding: EdgeInsets.only(top: 24),
                child: LineupEmptyState(
                  icon: Icons.video_library_outlined,
                  title: 'No movie or show libraries found',
                  message:
                      'Choose another Plex server with accessible libraries.',
                ),
              )
            else ...[
              _selectionSummary(),
              if (singleScroll)
                list
              else
                Flexible(fit: FlexFit.loose, child: list),
            ],
            if (!scanning &&
                ((hasLibraries && _libraryScanSettled) || scanError != null))
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    scanError != null && (retry.isEmpty || _error != null)
                        ? scanError
                        : ready.isEmpty
                        ? _librarySummary()
                        : '${ready.length} of ${_selectedLibraries.length} ${_selectedLibraries.length == 1 ? 'library' : 'libraries'} ${ready.length == 1 ? 'is' : 'are'} ready. Continuing builds from ${controller.libraries.where((library) => ready.contains(library.id)).map((library) => library.title).join(', ')}${excluded > 0 ? ' only' : ''}.',
                    style: bodyStyle,
                  ),
                ),
              ),
            SizedBox(height: 24),
            footer,
          ],
        );
        return Align(
          alignment: singleScroll ? Alignment.topCenter : Alignment.center,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(constraints.maxWidth, 1040),
            ),
            child: singleScroll
                ? SingleChildScrollView(
                    key: const ValueKey('channel-setup-single-scroll'),
                    child: content,
                  )
                : content,
          ),
        );
      },
    );
  }

  Widget _selectionSummary() {
    final roles = LineupTheme.of(context);
    final summaryStyle = Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: roles.secondaryText, fontSize: 16, height: 1.4);
    final editable =
        !widget.controller.busy &&
        widget.controller.libraryScanStatus != LibraryScanStatus.scanning;
    final libraries = widget.controller.libraries;
    final selected = _selectedLibraries.length;
    final all = selected == libraries.length;
    final value = all
        ? true
        : selected == 0
        ? false
        : null;
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 0, 8, 16),
      child: Row(
        children: [
          if (libraries.length > 1) ...[
            _checkbox(
              key: const ValueKey('select-all-libraries'),
              tristate: true,
              value: value,
              onChanged: editable ? (_) => _toggleAllLibraries() : null,
            ),
            TextButton(
              style: const ButtonStyle(
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
              onPressed: editable ? _toggleAllLibraries : null,
              child: Text(
                'Select all',
                style: summaryStyle.copyWith(
                  color: editable ? roles.secondaryText : roles.mutedText,
                ),
              ),
            ),
          ],
          const Spacer(),
          Text(
            '$selected of ${libraries.length} selected',
            style: summaryStyle,
          ),
        ],
      ),
    );
  }

  Widget _checkbox({
    Key? key,
    required bool? value,
    required ValueChanged<bool?>? onChanged,
    bool tristate = false,
    double width = 48,
    String? semanticLabel,
  }) {
    final checkbox = Checkbox(
      key: key,
      tristate: tristate,
      value: value,
      onChanged: onChanged,
    );
    return SizedBox(
      width: width,
      height: 48,
      child: semanticLabel == null
          ? checkbox
          : Semantics(label: semanticLabel, child: checkbox),
    );
  }

  ({double width, double closedHeight, double itemHeight}) _dropdownMetrics({
    required double desiredWidth,
    required double baseHeight,
    required double maxWidth,
    required Iterable<String> labels,
    required TextStyle style,
  }) {
    final horizontalPadding = 10;
    final arrowWidth = 24;
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);

    double measure(String label, {double maxWidth = double.infinity}) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: textDirection,
        textScaler: textScaler,
      );
      try {
        painter.layout(maxWidth: maxWidth);
        return painter.height;
      } finally {
        painter.dispose();
      }
    }

    var intrinsicWidth = 0.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: textDirection,
        textScaler: textScaler,
      );
      try {
        painter.layout();
        intrinsicWidth = math.max(intrinsicWidth, painter.width);
      } finally {
        painter.dispose();
      }
    }
    final width = math.min(
      maxWidth,
      math.max(
        desiredWidth,
        intrinsicWidth + 2 * horizontalPadding + arrowWidth,
      ),
    );
    final textWidth = math.max(1.0, width - 2 * horizontalPadding - arrowWidth);
    var textHeight = 0.0;
    for (final label in labels) {
      textHeight = math.max(textHeight, measure(label, maxWidth: textWidth));
    }
    return (
      width: width,
      closedHeight: math.max(baseHeight, textHeight + 8),
      itemHeight: math.max(48, textHeight + 8),
    );
  }

  void _toggleAllLibraries() => setState(() {
    final libraries = widget.controller.libraries;
    if (_selectedLibraries.length == libraries.length) {
      _selectedLibraries.clear();
    } else {
      _selectedLibraries
        ..clear()
        ..addAll(libraries.map((library) => library.id));
    }
  });

  Widget _libraryRow(PlexLibrary library) {
    final roles = LineupTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final selected = _selectedLibraries.contains(library.id);
    final fact = widget.controller.libraryScanFacts[library.id];
    final titleStyle = textTheme.bodyMedium!.copyWith(
      color: roles.primaryText,
      fontSize: 20,
      fontWeight: FontWeight.w600,
      height: 1.3,
    );
    final statusStyle = textTheme.bodyMedium!.copyWith(
      fontSize: 18,
      height: 1.4,
    );
    final typeStyle = textTheme.bodyMedium!.copyWith(
      color: roles.mutedText,
      fontSize: 16,
      height: 1.4,
    );
    void toggle() => setState(() {
      if (selected) {
        _selectedLibraries.remove(library.id);
      } else {
        _selectedLibraries.add(library.id);
      }
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final effectiveWidth = constraints.maxWidth / textScale;
        final narrow = effectiveWidth < 620 || textScale >= 1.6;
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(library.title, style: titleStyle),
                if (selected &&
                    _libraryScanSettled &&
                    fact?.status != LibraryScanStatus.complete)
                  Text("Won't be used", style: typeStyle),
              ],
            ),
            if (fact != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _scanDetail(fact),
                    style: statusStyle.copyWith(color: _scanColor(fact.status)),
                  ),
                  if (fact.status == LibraryScanStatus.transientFailure)
                    LineupInlineLink(
                      key: ValueKey('retry-library-${library.id}'),
                      onPressed: widget.controller.busy
                          ? null
                          : () => _scan(retryLibraryIds: {library.id}),
                      child: const Text('Retry'),
                    ),
                ],
              ),
            ],
          ],
        );
        final type = Text(
          _libraryType(library),
          textAlign: TextAlign.end,
          style: typeStyle,
        );
        final content = narrow
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _checkbox(
                    value: selected,
                    semanticLabel: library.title,
                    onChanged: widget.controller.busy ? null : (_) => toggle(),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        details,
                        SizedBox(height: 8),
                        Align(alignment: Alignment.centerRight, child: type),
                      ],
                    ),
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _checkbox(
                    value: selected,
                    semanticLabel: library.title,
                    onChanged: widget.controller.busy ? null : (_) => toggle(),
                  ),
                  SizedBox(width: 8),
                  Expanded(child: details),
                  SizedBox(width: 16),
                  type,
                ],
              );
        return InkWell(
          canRequestFocus: false,
          excludeFromSemantics: true,
          onTap: widget.controller.busy ? null : toggle,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 18, horizontal: 8),
            child: content,
          ),
        );
      },
    );
  }

  Future<void> _scan({
    bool retryFailedOnly = false,
    Set<String>? retryLibraryIds,
    bool advanceWhenReady = true,
  }) async {
    setState(() {
      _error = null;
      _notice = null;
    });
    try {
      // A row may have been unchecked since scanning. Retry its staged scan
      // inventory without changing the person's current selection.
      final ids = {
        ..._selectedLibraries,
        if (retryLibraryIds != null) ...widget.controller.libraryScanFacts.keys,
        ...?retryLibraryIds,
      };
      final settled = retryLibraryIds == null
          ? await widget.controller.scanLibraries(
              ids,
              retryFailedOnly: retryFailedOnly,
            )
          : await widget.controller.retryLibraryScan(ids, retryLibraryIds);
      if (!mounted) return;
      if (!settled) {
        setState(() {});
        return;
      }
      final ready = widget.controller.libraryScanReadyIds.intersection(
        _selectedLibraries,
      );
      if (advanceWhenReady && ready.length == _selectedLibraries.length) {
        await _commitLibraries(ready);
      } else {
        setState(() {});
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = safeFormError(error, 'The library scan failed.'),
        );
      }
    }
  }

  Future<void> _commitLibraries(Set<String> ready) async {
    try {
      final saved = await widget.controller.commitLibraryScan(ready);
      if (!mounted) return;
      if (!saved) {
        setState(() => _error = 'The ready libraries could not be saved.');
        return;
      }
      setState(() {
        _selectedLibraries
          ..clear()
          ..addAll(ready);
        _step = 2;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = safeFormError(
            error,
            'The ready libraries could not be saved.',
          ),
        );
      }
    }
  }

  Widget _configureStep() {
    final allocation = _allocate(widget.controller.channels);

    final roles = LineupTheme.of(context);

    return _Stage(
      footerGap: 0,
      footer: _Footer(
        configuration: true,
        leading: [
          TextButton(
            onPressed: () => setState(() => _step = 1),
            child: const Text('Back to libraries'),
          ),
        ],
        summary: _configurationSummary(allocation),
        trailing: FilledButton(
          key: const ValueKey('review-channels'),
          onPressed:
              allocation.channels.isNotEmpty ||
                  allocation.existingSkipped > 0 ||
                  (_mode == ChannelBuildMode.merge &&
                      allocation.unmatchedGenerated.any(
                        widget.controller.isGeneratedSourceConfirmedGone,
                      ))
              ? _prepareReview
              : null,
          child: const Text('Review channels'),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const labels = ['Channel sources', 'Playback order', 'Lineup rules'];
          final compact =
              constraints.maxWidth < 1100 ||
              MediaQuery.textScalerOf(context).scale(1) >= 1.6;

          final navigation = [
            for (var index = 0; index < labels.length; index++)
              Semantics(
                selected: _configurationSection == index,
                child: LineupNavigationRow(
                  selected: _configurationSection == index,
                  key: ValueKey('configure-section-$index'),
                  onPressed: () =>
                      setState(() => _configurationSection = index),
                  child: Text(labels[index]),
                ),
              ),
          ];
          final content = KeyedSubtree(
            key: const ValueKey('channel-configuration'),
            child: ListView(
              key: ValueKey(_configurationSection),
              children: [
                if (_configurationSection != 2)
                  _heading(
                    labels[_configurationSection],
                    switch (_configurationSection) {
                      0 =>
                        'Choose which kinds of generated channels to include.',
                      _ => 'For generated channels containing TV episodes',
                    },
                  ),
                if (_configurationSection == 0 && _selectedLibraries.length > 1)
                  Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Combine matching values to create shared channels across your selected libraries.',
                      style: TextStyle(
                        color: roles.secondaryText,
                        fontSize: 16,
                        height: 1.4,
                      ),
                    ),
                  ),
                if (_configurationSection == 0)
                  LayoutBuilder(
                    builder: (_, constraints) {
                      final double gap = 40;
                      final effectiveWidth =
                          constraints.maxWidth /
                          MediaQuery.textScalerOf(context).scale(1);
                      const sourcePairs = [
                        (
                          BuilderStrategy.playlists,
                          BuilderStrategy.collections,
                        ),
                        (
                          BuilderStrategy.recentlyAdded,
                          BuilderStrategy.decades,
                        ),
                        (BuilderStrategy.genres, BuilderStrategy.studios),
                        (BuilderStrategy.actors, BuilderStrategy.directors),
                      ];
                      final desktop = effectiveWidth >= 840;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (
                            var index = 0;
                            index < sourcePairs.length;
                            index++
                          ) ...[
                            _sourcePair(
                              sourcePairs[index],
                              allocation,
                              compact: !desktop,
                              columnGap: gap,
                            ),
                            if (index < sourcePairs.length - 1)
                              SizedBox(height: 12),
                          ],
                        ],
                      );
                    },
                  ),
                if (_configurationSection == 1) _playbackControls(),
                if (_configurationSection == 2)
                  LayoutBuilder(
                    builder: (_, constraints) {
                      final effectiveWidth =
                          constraints.maxWidth /
                          MediaQuery.textScalerOf(context).scale(1);
                      final double rulesGap = 64;
                      if (effectiveWidth < 840) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _limitControls(allocation),
                            SizedBox(height: 20),
                            _orderControls(),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 85, child: _limitControls(allocation)),
                          SizedBox(width: rulesGap),
                          Expanded(flex: 115, child: _orderControls()),
                        ],
                      );
                    },
                  ),
              ],
            ),
          );
          return compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(spacing: 8, runSpacing: 4, children: navigation),
                    SizedBox(height: 16),
                    Expanded(child: content),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 236,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final item in navigation) ...[
                            item,
                            SizedBox(height: 12),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(width: 40),
                    Expanded(child: content),
                  ],
                );
        },
      ),
    );
  }

  Widget _heading(String title, String description) {
    final roles = LineupTheme.of(context);
    final titleStyle = TextStyle(
      color: roles.primaryText,
      fontSize: 24,
      fontWeight: FontWeight.w600,
      height: 1.3,
    );
    final descriptionStyle = TextStyle(
      color: roles.secondaryText,
      fontSize: 18,
      height: 1.4,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final inline =
            constraints.maxWidth >= 640 &&
            MediaQuery.textScalerOf(context).scale(1) < 1.4;
        return Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: inline
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(title, style: titleStyle),
                    SizedBox(width: 32),
                    Expanded(child: Text(description, style: descriptionStyle)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: titleStyle),
                    SizedBox(height: 8),
                    Text(description, style: descriptionStyle),
                  ],
                ),
        );
      },
    );
  }

  Widget _configurationSummary(ChannelPlanAllocation result) {
    final roles = LineupTheme.of(context);
    final total = result.channels.length;
    final details = <String>[
      if (result.allocatedExtras == 0)
        'No additional versions'
      else
        '${result.allocatedOriginals} originals + ${result.allocatedExtras} extra versions',
    ];
    final excluded = [
      if (result.excludedOriginals > 0)
        '${result.excludedOriginals} ${result.excludedOriginals == 1 ? 'original' : 'originals'} excluded',
      if (result.excludedExtras > 0)
        '${result.excludedExtras} extra ${result.excludedExtras == 1 ? 'version' : 'versions'} excluded',
    ];
    if (excluded.isNotEmpty) {
      final reason = result.numberLimitExcluded > 0
          ? 'Channel numbers exhausted'
          : 'Channel limit reached';
      details.add('$reason · ${excluded.join(' · ')}');
    }
    final secondaryStyle = TextStyle(
      color: roles.secondaryText,
      fontSize: 18,
      height: 1.4,
    );
    return MergeSemantics(
      key: const ValueKey('configuration-allocation-summary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$total',
                style: TextStyle(
                  color: roles.primaryText,
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'generated ${total == 1 ? 'channel' : 'channels'}',
                  style: secondaryStyle,
                ),
              ),
            ],
          ),
          for (final detail in details) Text(detail, style: secondaryStyle),
        ],
      ),
    );
  }

  Widget _sourceControl(
    BuilderStrategy strategy,
    ChannelPlanAllocation allocation,
  ) {
    final canGroup =
        _supportsGrouping(strategy) && _selectedLibraries.length > 1;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: ListTileTheme.merge(
        titleAlignment: ListTileTitleAlignment.top,
        child: Column(
          children: [
            _sourceSelectionControl(strategy, allocation),
            if (canGroup)
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: _sourceGroupingControl(strategy),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sourcePair(
    (BuilderStrategy, BuilderStrategy) pair,
    ChannelPlanAllocation allocation, {
    required bool compact,
    required double columnGap,
  }) {
    final first = pair.$1;
    final second = pair.$2;
    final roles = LineupTheme.of(context);
    final double rowPadding = 16;
    final firstCanGroup =
        _supportsGrouping(first) && _selectedLibraries.length > 1;
    final secondCanGroup =
        _supportsGrouping(second) && _selectedLibraries.length > 1;

    if (compact) {
      return DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: roles.subtleBorder)),
        ),
        child: Column(
          children: [
            _sourceControl(first, allocation),
            _sourceControl(second, allocation),
          ],
        ),
      );
    }

    Widget separatorCell() => DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: roles.subtleBorder)),
      ),
      child: const SizedBox.shrink(),
    );

    return ListTileTheme.merge(
      titleAlignment: ListTileTitleAlignment.top,
      child: Table(
        columnWidths: {
          0: const FlexColumnWidth(),
          1: FixedColumnWidth(columnGap),
          2: const FlexColumnWidth(),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        children: [
          TableRow(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(vertical: rowPadding),
                child: _sourceSelectionControl(first, allocation),
              ),
              const SizedBox.shrink(),
              Padding(
                padding: EdgeInsets.symmetric(vertical: rowPadding),
                child: _sourceSelectionControl(second, allocation),
              ),
            ],
          ),
          if (firstCanGroup || secondCanGroup)
            TableRow(
              children: [
                firstCanGroup
                    ? Padding(
                        padding: EdgeInsets.only(top: 8, bottom: rowPadding),
                        child: _sourceGroupingControl(first),
                      )
                    : const SizedBox.shrink(),
                const SizedBox.shrink(),
                secondCanGroup
                    ? Padding(
                        padding: EdgeInsets.only(top: 8, bottom: rowPadding),
                        child: _sourceGroupingControl(second),
                      )
                    : const SizedBox.shrink(),
              ],
            ),
          TableRow(
            children: [separatorCell(), separatorCell(), separatorCell()],
          ),
        ],
      ),
    );
  }

  Widget _sourceSelectionControl(
    BuilderStrategy strategy,
    ChannelPlanAllocation allocation,
  ) {
    final roles = LineupTheme.of(context);
    final enabled = _strategies.contains(strategy);
    final discoveryFailure = _discoveryFailure(strategy);
    final eligible = enabled
        ? allocation.eligibleOriginalsByStrategy[strategy] ?? 0
        : buildChannelProposals(
            libraries: widget.controller.libraries
                .where((library) => _selectedLibraries.contains(library.id))
                .toList(),
            items: widget.controller.playableInventory.media,
            playlists: widget.controller.playableInventory.playlists,
            strategies: {strategy},
            crossLibraryStrategies: _grouped,
            minimumItems: _minimum,
            maximumChannels: null,
          ).length;
    final included = allocation.allocatedOriginalsByStrategy[strategy] ?? 0;
    final channels = enabled
        ? allocation.allocatedChannelsByStrategy[strategy] ?? 0
        : eligible;
    final nameStyle = TextStyle(
      color: eligible == 0 ? roles.mutedText : roles.primaryText,
      fontSize: 22,
      fontWeight: FontWeight.w600,
      height: 1.4,
    );
    final countStyle = TextStyle(
      color: eligible == 0 ? roles.mutedText : roles.secondaryText,
      fontSize: 16,
      height: 1.4,
    );
    final detailStyle = TextStyle(
      color: eligible == 0 ? roles.mutedText : roles.secondaryText,
      fontSize: 18,
      height: 1.4,
    );
    final title = Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(builderStrategyLabels[strategy]!, style: nameStyle),
        ),
        SizedBox(width: 12),
        Flexible(
          fit: FlexFit.tight,
          child: Text(
            eligible == 0 && discoveryFailure == null
                ? 'None in your libraries'
                : enabled && included < eligible
                ? '$included of $eligible included'
                : '$channels ${channels == 1 ? 'channel' : 'channels'}',
            textAlign: TextAlign.end,
            style: countStyle,
          ),
        ),
      ],
    );
    final subtitle = Padding(
      padding: EdgeInsets.only(top: 12),
      child: Text(_strategyDescription(strategy), style: detailStyle),
    );
    void changed(bool? value) => setState(() {
      if (value == true) {
        _strategies.add(strategy);
      } else {
        _strategies.remove(strategy);
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          value: enabled,
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: title,
          subtitle: subtitle,
          onChanged: changed,
        ),
        if (discoveryFailure != null)
          Padding(
            padding: const EdgeInsets.only(left: 56, top: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 48),
                  alignment: Alignment.centerLeft,
                ),
                key: ValueKey('retry-discovery-${strategy.name}'),
                onPressed: _discoveryRetry || widget.controller.busy
                    ? null
                    : () => _retryDiscovery(strategy),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text('$discoveryFailure · Retry'),
              ),
            ),
          ),
      ],
    );
  }

  String? _discoveryFailure(BuilderStrategy strategy) {
    final controller = widget.controller;
    if (strategy == BuilderStrategy.playlists) {
      if (controller.playlistCatalogUnavailable) {
        return 'Playlists unavailable';
      }
      final count = controller.failedPlaylistIds.length;
      if (count > 0) {
        return '$count ${count == 1 ? 'playlist' : 'playlists'} unavailable';
      }
    }
    if (strategy == BuilderStrategy.collections) {
      final unavailable = controller.unavailableCollectionLibraryIds
          .intersection(_selectedLibraries)
          .length;
      final failed = _selectedLibraries.fold<int>(
        0,
        (count, id) =>
            count + (controller.failedCollectionTitles[id]?.length ?? 0),
      );
      if (unavailable > 0) {
        return 'Collections unavailable in $unavailable ${unavailable == 1 ? 'library' : 'libraries'}${failed > 0 ? ' · $failed ${failed == 1 ? 'collection' : 'collections'} unavailable' : ''}';
      }
      if (failed > 0) {
        return '$failed ${failed == 1 ? 'collection' : 'collections'} unavailable';
      }
    }
    return null;
  }

  Future<void> _retryDiscovery(BuilderStrategy strategy) async {
    final controller = widget.controller;
    final ids = strategy == BuilderStrategy.collections
        ? _selectedLibraries
              .where(
                (id) =>
                    controller.unavailableCollectionLibraryIds.contains(id) ||
                    (controller.failedCollectionTitles[id]?.isNotEmpty ??
                        false),
              )
              .toSet()
        : Set<String>.of(_selectedLibraries);
    setState(() => _discoveryRetry = true);
    await _scan(retryLibraryIds: ids);
    if (mounted) setState(() => _discoveryRetry = false);
  }

  Widget _sourceGroupingControl(BuilderStrategy strategy) {
    final roles = LineupTheme.of(context);
    final enabled = _strategies.contains(strategy);
    final countStyle = TextStyle(
      color: roles.secondaryText,
      fontSize: 16,
      height: 1.4,
    );
    return Padding(
      padding: EdgeInsets.only(left: 56),
      child: LayoutBuilder(
        builder: (_, constraints) {
          final effectiveWidth =
              constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1);
          final groupingLabel = switch (strategy) {
            BuilderStrategy.genres => 'Combine matching genres',
            BuilderStrategy.studios => 'Combine matching studios',
            BuilderStrategy.actors => 'Combine matching actors',
            BuilderStrategy.directors => 'Combine matching directors',
            _ => 'Combine matching values',
          };
          final groupingStyle = Theme.of(context).textTheme.bodyMedium!
              .copyWith(
                fontSize: 16,
                height: 1.4,
                color: enabled ? roles.primaryText : roles.mutedText,
              );
          final metrics = _dropdownMetrics(
            desiredWidth: 300,
            baseHeight: 44,
            maxWidth: constraints.maxWidth,
            labels: ['Separate by library', groupingLabel],
            style: groupingStyle,
          );
          final dropdown = SizedBox(
            width: metrics.width,
            height: math.max(44, metrics.closedHeight),
            child: DropdownButtonHideUnderline(
              child: LineupDropdownBox(
                compact: true,
                enabled: enabled,
                child: DropdownButton<bool>(
                  key: ValueKey('source-grouping-${strategy.name}'),
                  isExpanded: true,
                  isDense: true,
                  iconSize: 24,
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  itemHeight: metrics.itemHeight,
                  value: _grouped.contains(strategy),
                  style: groupingStyle,
                  items: lineupMenuItems([
                    const DropdownMenuItem(
                      value: false,
                      child: Text('Separate by library'),
                    ),
                    DropdownMenuItem(value: true, child: Text(groupingLabel)),
                  ], _grouped.contains(strategy)),
                  onChanged: enabled
                      ? (value) => setState(() {
                          if (value == true) {
                            _grouped.add(strategy);
                          } else {
                            _grouped.remove(strategy);
                          }
                        })
                      : null,
                  dropdownColor: LineupTheme.of(context).elevatedSurface,
                  selectedItemBuilder: (_) => ([
                    const DropdownMenuItem(
                      value: false,
                      child: Text('Separate by library'),
                    ),
                    DropdownMenuItem(value: true, child: Text(groupingLabel)),
                  ]).map<Widget>((item) => item.child).toList(),
                ),
              ),
            ),
          );
          final label = Text('Library grouping', style: countStyle);
          final inline = effectiveWidth >= 460;
          return Semantics(
            label: '${builderStrategyLabels[strategy]} library grouping',
            container: true,
            child: inline
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: label),
                      SizedBox(width: 8),
                      dropdown,
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [label, SizedBox(height: 8), dropdown],
                  ),
          );
        },
      ),
    );
  }

  Widget _playbackControls() {
    final double sectionGap = 24;
    final dropdownTextStyle = Theme.of(context).textTheme.titleMedium!;
    final variantMetrics = _dropdownMetrics(
      desiredWidth: 240,
      baseHeight: 48,
      maxWidth: double.infinity,
      labels: ['None', 'Shuffle', 'In order', 'Mini-marathons'],
      style: dropdownTextStyle,
    );
    final alternateMetrics = _dropdownMetrics(
      desiredWidth: 220,
      baseHeight: 48,
      maxWidth: double.infinity,
      labels: ['0', '1', '2', '3'],
      style: dropdownTextStyle,
    );
    final additionalVersionsTitle = Text(
      'Additional channel versions',
      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, height: 1.4),
    );
    final additionalVersionsSubtitle = Padding(
      padding: EdgeInsets.only(top: 12),
      child: Text(
        _playback == PlaybackMode.sequential
            ? 'Alternate schedules are not available with In order. A different playback mode can still be added.'
            : 'Create extra channels with alternate schedules or another playback mode.',
        style: TextStyle(
          color: LineupTheme.of(context).secondaryText,
          fontSize: 18,
          height: 1.4,
        ),
      ),
    );
    void changeAdditionalVersions(bool value) => setState(() {
      _extras = value;
      _clearIncludeSpecialsIfUnused();
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: sectionGap),
        LayoutBuilder(
          builder: (context, constraints) {
            final effectiveWidth =
                constraints.maxWidth /
                MediaQuery.textScalerOf(context).scale(1);
            final columns = effectiveWidth >= 780
                ? 3
                : effectiveWidth >= 520
                ? 2
                : 1;
            final double gap = 20;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return RadioGroup<PlaybackMode>(
              groupValue: _playback,
              onChanged: (mode) => _setPlaybackMode(mode!),
              child: Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  _playbackChoice(
                    PlaybackMode.shuffle,
                    'Shuffle',
                    'Mix programs into a shuffled schedule.',
                    width: width,
                  ),
                  _playbackChoice(
                    PlaybackMode.sequential,
                    'In order',
                    'Keep the order supplied by the channel’s source.',
                    width: width,
                  ),
                  _playbackChoice(
                    PlaybackMode.block,
                    'Mini-marathons',
                    'Play a few episodes of one show, then move to another.',
                    width: width,
                  ),
                ],
              ),
            );
          },
        ),
        if (_playback == PlaybackMode.block) ...[
          SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: LineupTheme.of(context).primarySurface,
              border: Border.all(color: LineupTheme.of(context).subtleBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Wrap(
              spacing: 20,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(width: 220, child: _blockField(main: true)),
                _specialsControl(),
              ],
            ),
          ),
        ],
        SizedBox(height: sectionGap),
        _episodeStrip(),
        SizedBox(height: 28),
        ListTileTheme.merge(
          titleAlignment: ListTileTitleAlignment.top,
          child: SwitchListTile(
            value: _extras,
            controlAffinity: ListTileControlAffinity.trailing,
            contentPadding: EdgeInsets.zero,
            title: additionalVersionsTitle,
            subtitle: additionalVersionsSubtitle,
            onChanged: changeAdditionalVersions,
          ),
        ),
        if (_extras)
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              SizedBox(
                width: variantMetrics.width,
                child: LineupField(
                  label: 'Different playback mode',
                  child: lineupDropdownField<PlaybackMode?>(
                    context: context,
                    isExpanded: true,
                    iconSize: 24,
                    itemHeight: variantMetrics.itemHeight,
                    initialValue: _variantMode,
                    decoration: const InputDecoration(),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('None')),
                      DropdownMenuItem(
                        value: PlaybackMode.shuffle,
                        child: Text('Shuffle'),
                      ),
                      DropdownMenuItem(
                        value: PlaybackMode.sequential,
                        child: Text('In order'),
                      ),
                      DropdownMenuItem(
                        value: PlaybackMode.block,
                        child: Text('Mini-marathons'),
                      ),
                    ],
                    onChanged: (value) => setState(() {
                      _variantMode = value;
                      _clearDuplicateVariant();
                      _clearIncludeSpecialsIfUnused();
                    }),
                  ),
                ),
              ),
              if (_variantMode == PlaybackMode.block)
                SizedBox(width: 210, child: _blockField(main: false)),
              SizedBox(
                width: alternateMetrics.width,
                child: LineupField(
                  label: 'Alternate schedules',
                  child: lineupDropdownField<int>(
                    context: context,
                    initialValue: _alternateCopies,
                    decoration: const InputDecoration(),
                    iconSize: 24,
                    itemHeight: alternateMetrics.itemHeight,
                    items: const [0, 1, 2, 3]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text('$value'),
                          ),
                        )
                        .toList(),
                    onChanged: _playback == PlaybackMode.sequential
                        ? null
                        : (value) => setState(() => _alternateCopies = value!),
                  ),
                ),
              ),
            ],
          ),
        if (_playback != PlaybackMode.block &&
            _extras &&
            _variantMode == PlaybackMode.block)
          _specialsControl(),
        if (_notice != null)
          Text(
            _notice!,
            style: TextStyle(color: LineupTheme.of(context).secondaryText),
          ),
      ],
    );
  }

  Widget _specialsControl() => IntrinsicWidth(
    child: CheckboxMenuButton(
      value: _includeSpecials,
      onChanged: (value) => setState(() => _includeSpecials = value ?? false),
      child: const Text('Include specials'),
    ),
  );

  Widget _playbackChoice(
    PlaybackMode mode,
    String title,
    String description, {
    required double width,
  }) {
    return SizedBox(
      width: width,
      child: Builder(
        builder: (context) => MergeSemantics(
          child: RawRadio<PlaybackMode>(
            key: ValueKey('setup-playback-${mode.name}'),
            value: mode,
            mouseCursor: WidgetStateMouseCursor.clickable,
            toggleable: false,
            focusNode: _playbackFocus[mode]!,
            autofocus: false,
            groupRegistry: RadioGroup.maybeOf<PlaybackMode>(context),
            enabled: true,
            builder: (context, state) {
              final roles = LineupTheme.of(context);
              final selected = state.states.contains(WidgetState.selected);
              final focused = LineupFocusScope.visible(
                context,
                state.states.contains(WidgetState.focused),
              );
              final hovered = state.states.contains(WidgetState.hovered);
              final radius = BorderRadius.circular(roles.panelRadius);
              final surface = selected
                  ? roles.elevatedSurface
                  : roles.primarySurface;
              return Container(
                constraints: BoxConstraints(minHeight: 152),
                padding: EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: hovered
                      ? Color.alphaBlend(
                          roles.primaryText.withValues(alpha: 0.04),
                          surface,
                        )
                      : surface,
                  borderRadius: radius,
                  border: Border.all(
                    color: selected ? roles.progressFill : roles.defaultBorder,
                  ),
                ),
                foregroundDecoration: focused
                    ? BoxDecoration(
                        borderRadius: radius,
                        border: Border.all(
                          color: roles.focusBorder,
                          width: roles.focusBorderWidth,
                        ),
                      )
                    : null,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: roles.primaryText,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                        letterSpacing: 0,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      description,
                      style: TextStyle(
                        color: roles.secondaryText,
                        fontSize: 18,
                        height: 1.4,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _episodeStrip() {
    final episodes = switch (_playback) {
      PlaybackMode.shuffle => const [
        ('Summit', '02'),
        ('Harbor', '01'),
        ('Summit', '03'),
        ('Harbor', '02'),
        ('Harbor', '03'),
        ('Summit', '01'),
      ],
      PlaybackMode.sequential => const [
        ('Harbor', '01'),
        ('Harbor', '02'),
        ('Harbor', '03'),
        ('Summit', '01'),
        ('Summit', '02'),
        ('Summit', '03'),
      ],
      PlaybackMode.block => _miniMarathonEpisodes(),
    };
    final roles = LineupTheme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: roles.subtleBorder),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final effectiveWidth =
              constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1);
          final columns = effectiveWidth >= 900
              ? 6
              : effectiveWidth >= 560
              ? 3
              : effectiveWidth >= 320
              ? 2
              : 1;
          final double gap = 12;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Illustrative schedule · Each tile is one episode',
                style: TextStyle(
                  color: roles.secondaryText,
                  fontSize: 18,
                  height: 1.4,
                ),
              ),
              SizedBox(height: 20),
              Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final episode in episodes)
                    SizedBox(
                      width: width,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color.alphaBlend(
                            (episode.$1 == 'Harbor'
                                    ? roles.progressFill
                                    : roles.focusBorder)
                                .withValues(
                                  alpha: episode.$1 == 'Harbor' ? .10 : .04,
                                ),
                            roles.primarySurface,
                          ),
                          border: Border(
                            left: BorderSide(
                              color: roles.defaultBorder,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: 22,
                            horizontal: 20,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                episode.$1,
                                style: TextStyle(fontSize: 20, height: 1.4),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Episode ${episode.$2}',
                                style: TextStyle(
                                  color: roles.secondaryText,
                                  fontSize: 17,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: 12),
              Text(
                switch (_playback) {
                  PlaybackMode.shuffle => 'The example mixes episodes across shows. Tuning in joins the channel’s ongoing schedule.',
                  PlaybackMode.sequential => 'This example source is already episode-ordered. In order preserves source order; it does not re-sort episodes.',
                  PlaybackMode.block =>
                    'Up to $_blockSize episodes from one show play before the next show. Episodes follow season and episode order within each show.',
                },
                style: TextStyle(
                  color: roles.secondaryText,
                  fontSize: 18,
                  height: 1.4,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<(String, String)> _miniMarathonEpisodes() {
    final blockSize = _blockSize.clamp(2, 5).toInt();
    return List.generate(6, (index) {
      final block = index ~/ blockSize;
      final episode = index % blockSize + 1;
      final seasonBlock = block ~/ 2;
      return (
        block.isEven ? 'Harbor' : 'Summit',
        '${seasonBlock * blockSize + episode}'.padLeft(2, '0'),
      );
    });
  }

  Widget _blockField({required bool main}) {
    final metrics = _dropdownMetrics(
      desiredWidth: 220,
      baseHeight: 48,
      maxWidth: 220,
      labels: ['2', '3', '4', '5'],
      style: Theme.of(context).textTheme.titleMedium!,
    );
    return LineupField(
      label: main ? 'Episodes per block' : 'Extra block size',
      child: lineupDropdownField<int>(
        context: context,
        initialValue: main ? _blockSize : _variantBlockSize,
        iconSize: 24,
        itemHeight: metrics.itemHeight,
        decoration: InputDecoration(),
        items: const [2, 3, 4, 5]
            .map(
              (value) => DropdownMenuItem(value: value, child: Text('$value')),
            )
            .toList(),
        onChanged: (value) => setState(() {
          if (main) {
            _blockSize = value!;
          } else {
            _variantBlockSize = value!;
          }
          _clearDuplicateVariant();
        }),
      ),
    );
  }

  void _setPlaybackMode(PlaybackMode mode) {
    if (mode == _playback) return;
    setState(() {
      _playback = mode;
      _notice = null;
      final enteringInOrder = mode == PlaybackMode.sequential;
      final removedAlternateSchedules = enteringInOrder && _alternateCopies > 0;
      if (removedAlternateSchedules) _alternateCopies = 0;
      _clearDuplicateVariant();
      if (removedAlternateSchedules && _notice == null) {
        _notice = 'Alternate schedules aren’t available with In order.';
      }
      _clearIncludeSpecialsIfUnused();
    });
  }

  void _clearIncludeSpecialsIfUnused() {
    final hasBlockOutput =
        _playback == PlaybackMode.block ||
        (_extras && _variantMode == PlaybackMode.block);
    if (!hasBlockOutput) _includeSpecials = false;
  }

  void _clearDuplicateVariant() {
    final duplicate =
        _variantMode == _playback &&
        (_variantMode != PlaybackMode.block || _variantBlockSize == _blockSize);
    if (!duplicate) return;
    final removed = _variantMode;
    _variantMode = null;
    _notice = removed == PlaybackMode.sequential
        ? 'Extra In order version removed—it now matches your main playback order.'
        : 'The duplicate extra version was removed because it matches your main playback order.';
  }

  Widget _limitControls(ChannelPlanAllocation allocation) {
    final roles = LineupTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final headingStyle = textTheme.titleMedium!.copyWith(
      color: roles.primaryText,
      fontSize: 24,
      fontWeight: FontWeight.w600,
      height: 1.3,
    );
    final subtitleStyle = textTheme.bodyMedium!.copyWith(
      color: roles.secondaryText,
      fontSize: 18,
      height: 1.4,
    );
    final labelStyle = textTheme.bodyMedium!.copyWith(
      color: roles.primaryText,
      fontSize: 22,
      fontWeight: FontWeight.normal,
      height: 1.4,
    );
    final descriptionStyle = textTheme.bodyMedium!.copyWith(
      color: roles.secondaryText,
      fontSize: 18,
      height: 1.4,
    );
    final dropdownStyle = textTheme.bodyMedium!.copyWith(
      color: roles.primaryText,
      fontSize: 18,
      height: 1.4,
    );

    Widget field({
      required Key key,
      required String label,
      required int value,
      required List<int> choices,
      required String description,
      required ValueChanged<int> onChanged,
    }) {
      return DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: roles.subtleBorder)),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 36),
          child: LayoutBuilder(
            builder: (_, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              final double desiredWidth = 110;
              final metrics = _dropdownMetrics(
                desiredWidth: desiredWidth,
                baseHeight: 48,
                maxWidth: constraints.maxWidth,
                labels: choices.map((choice) => '$choice'),
                style: dropdownStyle,
              );
              final dropdownWidth = metrics.width;
              final inline =
                  constraints.maxWidth / textScale >= 320 &&
                  constraints.maxWidth >= dropdownWidth + 16;
              final dropdown = Semantics(
                label: label,
                container: true,
                child: SizedBox(
                  width: dropdownWidth,
                  height: math.max(56, metrics.closedHeight),
                  child: DropdownButtonHideUnderline(
                    child: LineupDropdownBox(
                      compact: false,
                      enabled: true,
                      child: DropdownButton<int>(
                        key: key,
                        isExpanded: true,
                        isDense: true,
                        iconSize: 24,
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        itemHeight: metrics.itemHeight,
                        value: value,
                        style: dropdownStyle,
                        items: lineupMenuItems([
                          for (final choice in choices)
                            DropdownMenuItem(
                              value: choice,
                              child: Text('$choice'),
                            ),
                        ], value),
                        onChanged: (next) {
                          if (next != null) onChanged(next);
                        },
                        dropdownColor: LineupTheme.of(context).elevatedSurface,
                        selectedItemBuilder: (_) => ([
                          for (final choice in choices)
                            DropdownMenuItem(
                              value: choice,
                              child: Text('$choice'),
                            ),
                        ]).map<Widget>((item) => item.child).toList(),
                      ),
                    ),
                  ),
                ),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (inline)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: Text(label, style: labelStyle)),
                        SizedBox(width: 16),
                        dropdown,
                      ],
                    )
                  else ...[
                    Text(label, style: labelStyle),
                    SizedBox(height: 8),
                    Align(alignment: Alignment.centerLeft, child: dropdown),
                  ],
                  SizedBox(height: 16),
                  Text(description, style: descriptionStyle),
                ],
              );
            },
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Channel limits', style: headingStyle),
        SizedBox(height: 8),
        Text(
          'Keep enough variety without overcrowding your guide.',
          style: subtitleStyle,
        ),
        field(
          key: const ValueKey('rules-maximum'),
          label: 'Maximum generated channels',
          value: _maximum,
          choices: const [50, 100, 200, 300, 500, 750, 1000],
          description: 'Includes additional versions. Custom and retained channels may bring the final lineup above this limit.',
          onChanged: (value) => setState(() => _maximum = value),
        ),
        field(
          key: const ValueKey('rules-minimum'),
          label: 'Minimum programs per channel',
          value: _minimum,
          choices: const [1, 5, 10, 20, 50],
          description: 'Movies and individual episodes count as programs. Higher values exclude smaller channel candidates.',
          onChanged: (value) => setState(() => _minimum = value),
        ),
        _rulesAllocationFeedback(allocation),
      ],
    );
  }

  Widget _rulesAllocationFeedback(ChannelPlanAllocation allocation) {
    final roles = LineupTheme.of(context);
    final excluded = allocation.excludedOriginals + allocation.excludedExtras;
    if (excluded == 0 && allocation.channels.isNotEmpty) {
      return const SizedBox.shrink();
    }
    final guidance = allocation.numberLimitExcluded > 0
        ? 'Free up channel numbers to make room for more generated channels.'
        : excluded > 0
        ? 'Increase the maximum to include more channels, or adjust source order to change which channels fit.'
        : 'Choose more sources or lower the minimum programs per channel.';
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: EdgeInsets.only(top: 36),
        padding: EdgeInsets.only(left: 20),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: excluded > 0 ? roles.progressFill : roles.subtleBorder,
              width: 2,
            ),
          ),
        ),
        child: Text(
          guidance,
          style: TextStyle(
            color: roles.secondaryText,
            fontSize: 18,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _orderControls() {
    final roles = LineupTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final headingStyle = textTheme.titleMedium!.copyWith(
      color: roles.primaryText,
      fontSize: 24,
      fontWeight: FontWeight.w600,
      height: 1.3,
    );
    final subtitleStyle = textTheme.bodyMedium!.copyWith(
      color: roles.secondaryText,
      fontSize: 18,
      height: 1.4,
    );
    final nameStyle = textTheme.bodyMedium!.copyWith(
      color: roles.primaryText,
      fontSize: 21,
      height: 1.4,
    );
    final rankStyle = textTheme.bodyMedium!.copyWith(
      color: roles.secondaryText,
      fontSize: 18,
      height: 1.4,
    );
    final double rowHeight = 60;

    final double rowGap = 16;

    Widget rowFor(int index, BuilderStrategy strategy) {
      var hovered = false;
      var focused =
          _orderFocus[strategy]!.earlier.hasFocus ||
          _orderFocus[strategy]!.later.hasFocus;
      final enabled = _strategies.contains(strategy);
      return StatefulBuilder(
        key: ValueKey('source-order-state-${strategy.name}'),
        builder: (context, setRowState) => Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (value) {
            if (focused != value) setRowState(() => focused = value);
          },
          child: MouseRegion(
            onEnter: (_) {
              if (!hovered) setRowState(() => hovered = true);
            },
            onExit: (_) {
              if (hovered) setRowState(() => hovered = false);
            },
            child: DecoratedBox(
              key: ValueKey('source-order-${strategy.name}'),
              decoration: BoxDecoration(
                color: hovered || LineupFocusScope.visible(context, focused)
                    ? roles.primarySurface
                    : Colors.transparent,
                border: Border(bottom: BorderSide(color: roles.subtleBorder)),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: rowHeight),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text('${index + 1}', style: rankStyle),
                    ),
                    SizedBox(width: rowGap),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: builderStrategyLabels[strategy]!),
                            if (!enabled)
                              TextSpan(text: '  Off', style: rankStyle),
                          ],
                        ),
                        style: nameStyle,
                      ),
                    ),
                    SizedBox(width: 8),
                    Wrap(
                      spacing: 4,
                      children: [
                        lineupArrowButton(
                          focusNode: _orderFocus[strategy]!.earlier,
                          tooltip: 'Move earlier',
                          onPressed: index == 0
                              ? null
                              : () => _moveSource(index, -1),
                          icon: Icons.arrow_upward,
                        ),
                        lineupArrowButton(
                          focusNode: _orderFocus[strategy]!.later,
                          tooltip: 'Move later',
                          onPressed: index == _sourceOrder.length - 1
                              ? null
                              : () => _moveSource(index, 1),
                          icon: Icons.arrow_downward,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Source order', style: headingStyle),
        SizedBox(height: 8),
        Text(
          'Take one channel from each source, then repeat.',
          style: subtitleStyle,
        ),
        SizedBox(height: 24),
        for (var index = 0; index < _sourceOrder.length; index++)
          rowFor(index, _sourceOrder[index]),
        SizedBox(height: 24),
        Text(
          'Repeat this order until the limit is reached. Skip sources with no remaining channels.',
          style: subtitleStyle,
        ),
      ],
    );
  }

  void _moveSource(int index, int delta) {
    final strategy = _sourceOrder[index];
    final target = index + delta;
    setState(() {
      _sourceOrder.removeAt(index);
      _sourceOrder.insert(target, strategy);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nodes = _orderFocus[strategy]!;
      final earlier =
          target == _sourceOrder.length - 1 || (target > 0 && delta < 0);
      (earlier ? nodes.earlier : nodes.later).requestFocus();
    });
  }

  void _prepareReview() {
    final base = List<Channel>.of(widget.controller.channels);
    setState(() {
      _reviewBase = base;
      _plan = _allocateReview(base);
      _removalConfirmed = false;
      _phase = _BuildPhase.review;
      _error = null;
      _notice = null;
      _step = 3;
    });
  }

  Widget _reviewStep() {
    final entries = _reviewEntries(_plan!.channels);
    final counts = _counts(entries);
    final finalChannels = composeChannelPlan(
      existing: _reviewBase
          .where((channel) => !_removeSourceIds.contains(channel.id))
          .toList(),
      planned: _plan!.channels,
      mode: _mode,
    );
    final noChanges =
        counts.added == 0 && counts.updated == 0 && counts.removed == 0;
    return _Stage(
      footer: _Footer(
        configuration: true,
        leading: [
          TextButton(
            key: const ValueKey('back-to-configure'),
            onPressed: () => setState(() => _step = 2),
            child: const Text('Back to configure'),
          ),
        ],
        summary: const SizedBox.shrink(),
        trailing: noChanges
            ? FilledButton(
                onPressed: _viewLineup,
                child: const Text('View lineup'),
              )
            : FilledButton(
                key: const ValueKey('apply-reviewed-lineup'),
                onPressed:
                    _notice == 'Updating review…' ||
                        (counts.removed > 0 && !_removalConfirmed)
                    ? null
                    : _applyReview,
                child: Text(switch (_mode) {
                  ChannelBuildMode.replace =>
                    _firstSetup
                        ? 'Create lineup'
                        : 'Replace generated channels',
                  ChannelBuildMode.append => 'Add channels',
                  ChannelBuildMode.merge => 'Apply changes',
                }),
              ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final intro = <Widget>[
            if (_notice != null && _notice != 'Updating review…') ...[
              LineupNotice(message: _notice!),
              SizedBox(height: 8),
            ],
            if (noChanges) ...[
              Text(
                'Your lineup is already up to date',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Text('No changes needed.'),
              SizedBox(height: 8),
            ],
            _reviewOverview(entries, finalChannels, counts),
            if (_missingSources.isNotEmpty) ...[
              const SizedBox(height: 16),
              _missingSourceReview(),
            ],
            SizedBox(height: 24),
          ];
          if (constraints.maxHeight < 650 ||
              MediaQuery.textScalerOf(context).scale(1) >= 1.5) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _roster(entries, leading: intro)),
                if (counts.removed > 0) _removalNotice(counts.removed),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...intro,
              Expanded(child: _roster(entries)),
              if (counts.removed > 0) _removalNotice(counts.removed),
            ],
          );
        },
      ),
    );
  }

  List<Channel> get _missingSources => _mode == ChannelBuildMode.merge
      ? _plan!.unmatchedGenerated
            .where(widget.controller.isGeneratedSourceConfirmedGone)
            .toList()
      : const [];

  Widget _missingSourceReview() {
    final roles = LineupTheme.of(context);
    return DecoratedBox(
      key: const ValueKey('source-not-found'),
      decoration: BoxDecoration(
        color: roles.primarySurface,
        border: Border.all(color: roles.subtleBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Source not found',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'These generated channels have no playable items after a complete scan. Keep them or remove them from your lineup.',
              style: TextStyle(
                color: roles.secondaryText,
                fontSize: 18,
                height: 1.4,
              ),
            ),
            for (final channel in _missingSources)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final choice = LineupSegmentedControl<bool>(
                      key: ValueKey('missing-source-choice-${channel.id}'),
                      segments: const [
                        ButtonSegment(value: false, label: Text('Keep')),
                        ButtonSegment(value: true, label: Text('Remove')),
                      ],
                      selected: {_removeSourceIds.contains(channel.id)},
                      onSelectionChanged: (selected) => setState(() {
                        if (selected.single) {
                          _removeSourceIds.add(channel.id);
                        } else {
                          _removeSourceIds.remove(channel.id);
                        }
                        _removalConfirmed = false;
                      }),
                    );
                    final title = Text(
                      '${channel.number} · ${channel.name}',
                      style: TextStyle(color: roles.primaryText, fontSize: 18),
                    );
                    if (constraints.maxWidth /
                            MediaQuery.textScalerOf(context).scale(1) <
                        600) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          title,
                          const SizedBox(height: 8),
                          Align(alignment: Alignment.centerLeft, child: choice),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: title),
                        const SizedBox(width: 16),
                        choice,
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _removalNotice(int count) {
    final roles = LineupTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Material(
        color: roles.primarySurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: roles.subtleBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber_rounded, color: roles.liveAccent),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      '$count existing generated ${count == 1 ? 'channel will' : 'channels will'} be removed.',
                    ),
                  ),
                ],
              ),
              SizedBox(
                width: 220,
                child: CheckboxListTile(
                  key: const ValueKey('channel-setup-replace-confirmation'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  value: _removalConfirmed,
                  title: const Text('I understand'),
                  onChanged: (value) =>
                      setState(() => _removalConfirmed = value == true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _methodDecision() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, constraints) =>
            LineupSegmentedControl<ChannelBuildMode>(
              key: const ValueKey('review-build-method'),
              direction:
                  constraints.maxWidth /
                          MediaQuery.textScalerOf(context).scale(1) <
                      800
                  ? Axis.vertical
                  : Axis.horizontal,
              expanded: true,
              segments: const [
                ButtonSegment(
                  value: ChannelBuildMode.merge,
                  label: Text('Update and add'),
                ),
                ButtonSegment(
                  value: ChannelBuildMode.replace,
                  label: Text('Replace generated channels'),
                ),
                ButtonSegment(
                  value: ChannelBuildMode.append,
                  label: Text('Add as new channels'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) {
                setState(() {
                  _mode = selection.single;
                  _removalConfirmed = false;
                  _notice = 'Updating review…';
                  _plan = _allocateReview(_reviewBase);
                });
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _notice = null);
                });
              },
            ),
      ),
      const SizedBox(height: 8),
      Text(
        _notice == 'Updating review…' ? _notice! : _modeDescription(_mode),
        style: TextStyle(
          color: LineupTheme.of(context).secondaryText,
          fontSize: 18,
          height: 1.4,
        ),
      ),
    ],
  );

  Widget _reviewOverview(
    List<_ReviewEntry> entries,
    List<Channel> finalChannels,
    ({int unchanged, int updated, int added, int removed}) counts,
  ) {
    final roles = LineupTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final finalCount = finalChannels.length;
    final generated = _finalGeneratedCounts(finalChannels);
    final totalStyle = textTheme.titleLarge!.copyWith(
      color: roles.primaryText,
      fontSize: 36,
      fontWeight: FontWeight.w600,
      height: 1.2,
    );
    final currentStyle = textTheme.bodyMedium!.copyWith(
      color: roles.secondaryText,
      fontSize: 18,
      height: 1.4,
    );
    final supportingStyle = textTheme.bodyMedium!.copyWith(
      color: roles.secondaryText,
      fontSize: 18,
      height: 1.4,
    );
    final total = _firstSetup
        ? Text('$finalCount channels ready to create', style: totalStyle)
        : Semantics(
            label: '${_reviewBase.length} current to $finalCount final',
            child: ExcludeSemantics(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 14,
                children: [
                  Text('${_reviewBase.length} current', style: currentStyle),
                  Icon(
                    Icons.arrow_forward,
                    size: 32,
                    color: roles.secondaryText,
                  ),
                  Text('$finalCount final', style: totalStyle),
                ],
              ),
            ),
          );
    final filters = Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        _filterChip(_ReviewFilter.unchanged, counts.unchanged),
        _filterChip(_ReviewFilter.updated, counts.updated),
        _filterChip(_ReviewFilter.added, counts.added),
        _filterChip(_ReviewFilter.removed, counts.removed),
      ],
    );
    final sourceCounts = [
      for (final strategy in _sourceOrder)
        if ((generated.byStrategy[strategy] ?? 0) > 0)
          '${builderStrategyLabels[strategy]} ${generated.byStrategy[strategy]}',
      if (generated.other > 0) 'Other generated ${generated.other}',
    ];
    final sourceBreakdown = Text(
      'By source: ${sourceCounts.join(' · ')}',
      style: supportingStyle,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: roles.primarySurface,
        border: Border.all(color: roles.subtleBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_firstSetup) ...[
              _methodDecision(),
              const SizedBox(height: 16),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final effectiveWidth =
                    constraints.maxWidth /
                    MediaQuery.textScalerOf(context).scale(1);
                final inline = !_firstSetup && effectiveWidth >= 760;
                if (inline) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: total),
                      filters,
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    total,
                    if (!_firstSetup) ...[SizedBox(height: 12), filters],
                  ],
                );
              },
            ),
            if (!_firstSetup) ...[
              SizedBox(height: 24),
              Text(
                'Changes in this review${counts.removed > 0 ? ' · Includes channels being removed' : ''}',
                style: supportingStyle,
              ),
              SizedBox(height: 12),
              if (entries.isNotEmpty)
                Semantics(
                  label:
                      '${counts.unchanged} unchanged, ${counts.updated} updated, ${counts.added} added, ${counts.removed} removed. ${entries.length} review entries including outgoing channels.',
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        _segment(counts.unchanged, roles.mutedText, height: 14),
                        _segment(
                          counts.updated,
                          roles.secondaryText,
                          height: 14,
                        ),
                        _segment(counts.added, roles.progressFill, height: 14),
                        _segment(
                          counts.removed,
                          Theme.of(context).colorScheme.error,
                          height: 14,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            if (!_firstSetup) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 20,
                runSpacing: 4,
                children: [
                  for (final item in [
                    ('Unchanged', roles.mutedText),
                    ('Updated', roles.secondaryText),
                    ('Added', roles.progressFill),
                    ('Removed', roles.liveAccent),
                  ])
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 10, height: 10, color: item.$2),
                        const SizedBox(width: 8),
                        Text(item.$1, style: supportingStyle),
                      ],
                    ),
                ],
              ),
            ],
            SizedBox(height: 24),
            Divider(height: 1, color: roles.subtleBorder),
            SizedBox(height: 16),
            sourceBreakdown,
            if (_mode == ChannelBuildMode.append && _plan!.existingSkipped > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${_plan!.existingSkipped} already in your lineup',
                  key: const ValueKey('existing-sources-skipped'),
                  style: supportingStyle,
                ),
              ),
            if (_reviewBase.any((channel) => channel.builderKey == null))
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '${_reviewBase.where((channel) => channel.builderKey == null).length} custom channels will be kept.',
                  style: supportingStyle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _segment(int count, Color color, {double height = 10}) => count == 0
      ? const SizedBox.shrink()
      : Expanded(
          flex: count,
          child: Container(height: height, color: color),
        );

  ({Map<BuilderStrategy, int> byStrategy, int other}) _finalGeneratedCounts(
    List<Channel> channels,
  ) {
    final byStrategy = <BuilderStrategy, int>{};
    var other = 0;
    for (final channel in channels.where(
      (candidate) => candidate.builderKey != null,
    )) {
      final strategy =
          _reviewStrategyBySource[canonicalSourceIdentity(channel.source)];
      if (strategy == null) {
        other++;
      } else {
        byStrategy.update(strategy, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    return (byStrategy: byStrategy, other: other);
  }

  Widget _filterChip(_ReviewFilter filter, int count) {
    final roles = LineupTheme.of(context);
    final selected = _filter == filter;
    final swatchColor = count == 0
        ? roles.subtleBorder
        : switch (filter) {
            _ReviewFilter.unchanged => roles.mutedText,
            _ReviewFilter.updated => roles.secondaryText,
            _ReviewFilter.added => roles.progressFill,
            _ReviewFilter.removed => Theme.of(context).colorScheme.error,
            _ReviewFilter.all => roles.mutedText,
          };

    return Semantics(
      selected: selected,
      child: TextButton(
        onPressed: () => setState(() => _filter = filter),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 10, height: 10, color: swatchColor),
            SizedBox(width: 10),
            Text('$count ${_capitalized(filter.name)}'),
          ],
        ),
      ),
    );
  }

  Widget _roster(List<_ReviewEntry> all, {List<Widget> leading = const []}) {
    final roles = LineupTheme.of(context);
    final textStyle = Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: roles.secondaryText, fontSize: 18, height: 1.4);
    final searchStyle = Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: roles.primaryText, fontSize: 18, height: 1.4);
    final query = _search.text.trim().toLowerCase();
    final entries = all.where((entry) {
      final found =
          query.isEmpty ||
          entry.channel.name.toLowerCase().contains(query) ||
          '${entry.channel.number}'.contains(query);
      return found &&
          (_filter == _ReviewFilter.all || entry.kind.name == _filter.name);
    }).toList();
    final filtered = _filter != _ReviewFilter.all;
    return LineupCompactControls(
      child: CustomScrollView(
        key: const ValueKey('channel-setup-review-roster'),
        slivers: [
          if (leading.isNotEmpty) SliverList.list(children: leading),
          SliverList.list(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('channel-setup-review-search'),
                      controller: _search,
                      style: searchStyle,
                      decoration: InputDecoration(
                        hintText: 'Search channels by name or number',
                        hintStyle: searchStyle,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (!_firstSetup) ...[
                    SizedBox(width: 12),
                    TextButton(
                      key: const ValueKey('review-show-all'),
                      onPressed: () =>
                          setState(() => _filter = _ReviewFilter.all),
                      child: const Text('Show all'),
                    ),
                  ],
                ],
              ),
              SizedBox(height: 8),
              Text(
                filtered
                    ? '${_capitalized(_filter.name)} · ${entries.length} matching ${entries.length == 1 ? 'channel' : 'channels'}'
                    : '${entries.length} of ${all.length} review entries',
                style: textStyle,
              ),
              SizedBox(height: 12),
              _rosterHeader(),
            ],
          ),
          if (entries.isEmpty)
            SliverToBoxAdapter(child: _emptyRoster(query, filtered))
          else
            SliverList.builder(
              itemCount: entries.length,
              itemBuilder: (_, index) => _reviewRow(entries[index]),
            ),
        ],
      ),
    );
  }

  double _reviewChangeWidth() {
    final style = Theme.of(context).textTheme.bodyMedium!
        .copyWith(fontSize: 18, height: 1.4);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    var width = 120.0;
    for (final label in [
      'Change',
      'Unchanged',
      '• Updated',
      '+ Added',
      'Removed',
    ]) {
      width = math.max(
        width,
        TextPainter.computeWidth(
              text: TextSpan(text: label, style: style),
              textDirection: direction,
              textScaler: scaler,
              maxLines: 1,
            ) +
            8,
      );
    }
    return width;
  }

  Widget _rosterHeader() {
    final roles = LineupTheme.of(context);
    final headerStyle = Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: roles.secondaryText, fontSize: 18, height: 1.4);
    final double numberWidth = 80;
    final changeWidth = _reviewChangeWidth();
    return DecoratedBox(
      key: const ValueKey('review-roster-header'),
      decoration: BoxDecoration(color: roles.primarySurface),
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 8, 52, 8),
        child: Row(
          children: [
            SizedBox(
              width: numberWidth,
              child: Text('No.', style: headerStyle),
            ),
            Expanded(flex: 60, child: Text('Channel', style: headerStyle)),
            Expanded(flex: 16, child: Text('Source', style: headerStyle)),
            Expanded(flex: 16, child: Text('Playback', style: headerStyle)),
            SizedBox(
              width: changeWidth,
              child: Text(
                'Change',
                textAlign: TextAlign.end,
                style: headerStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyRoster(String query, bool filtered) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          query.isNotEmpty
              ? 'No matching channels'
              : 'No channels in this filter',
        ),
        LineupInlineLink(
          onPressed: () => setState(() {
            if (query.isNotEmpty) _search.clear();
            if (filtered) _filter = _ReviewFilter.all;
          }),
          child: Text(query.isNotEmpty ? 'Clear search' : 'Show all'),
        ),
      ],
    ),
  );

  Widget _reviewRow(_ReviewEntry entry) {
    final roles = LineupTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final nameStyle = textTheme.bodyMedium!.copyWith(
      color: roles.primaryText,
      fontSize: 20,
      height: 1.4,
    );
    final metaStyle = textTheme.bodyMedium!.copyWith(
      color: roles.secondaryText,
      fontSize: 18,
      height: 1.4,
    );
    final changeStyle = metaStyle.copyWith(
      color: switch (entry.kind) {
        _ReviewKind.unchanged => roles.mutedText,
        _ReviewKind.updated => roles.secondaryText,
        _ReviewKind.added => roles.secondaryText,
        _ReviewKind.removed => Theme.of(context).colorScheme.error,
      },
    );
    final double numberWidth = 80;
    final changeWidth = _reviewChangeWidth();
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: numberWidth,
          child: Text('${entry.channel.number}', style: metaStyle),
        ),
        Expanded(flex: 60, child: Text(entry.channel.name, style: nameStyle)),
        Expanded(
          flex: 16,
          child: Text(_sourceLabel(entry.channel.source), style: metaStyle),
        ),
        Expanded(
          flex: 16,
          child: Text(_playbackLabel(entry.channel), style: metaStyle),
        ),
        SizedBox(
          width: changeWidth,
          child: Text(
            switch (entry.kind) {
              _ReviewKind.added => '+ Added',
              _ReviewKind.updated => '• Updated',
              _ => _capitalized(entry.kind.name),
            },
            textAlign: TextAlign.end,
            style: changeStyle,
          ),
        ),
      ],
    );
    final changes = _changedFields(entry.before, entry.channel);
    return DecoratedBox(
      key: ValueKey('review-channel-${entry.channel.id}'),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: LineupTheme.of(context).subtleBorder),
        ),
      ),
      child: entry.kind == _ReviewKind.updated && changes.isNotEmpty
          ? ExpansionTile(
              tilePadding: EdgeInsets.symmetric(horizontal: 12),
              title: content,
              childrenPadding: EdgeInsets.fromLTRB(numberWidth + 12, 0, 12, 16),
              children: [
                for (final change in changes)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      change,
                      style: metaStyle.copyWith(
                        fontFamilyFallback: const ['Arial'],
                      ),
                    ),
                  ),
              ],
            )
          : Padding(
              padding: EdgeInsets.fromLTRB(12, 16, 52, 16),
              child: content,
            ),
    );
  }

  Future<void> _applyReview() async {
    final planned = _plan!;
    setState(() {
      _phase = _BuildPhase.applying;
      _appliedEntries = _reviewEntries(planned.channels);
      _error = null;
    });
    try {
      final result = await widget.controller.applyReviewedChannelPlan(
        planned.channels,
        mode: _mode,
        expectedBase: _reviewBase,
        removeChannelIds: _removeSourceIds,
      );
      if (!mounted) return;
      if (result == ChannelPlanApplyResult.stale) {
        final base = List<Channel>.of(widget.controller.channels);
        setState(() {
          _reviewBase = base;
          _plan = _allocateReview(base);
          _removalConfirmed = false;
          _notice = 'Your lineup changed. Review the updated changes before applying.';
          _phase = _BuildPhase.review;
        });
        return;
      }
      setState(() => _phase = _BuildPhase.complete);
      _focusResult();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _BuildPhase.failed;
        _error = safeFormError(error, 'The lineup could not be saved.');
      });
      _focusResult();
    }
  }

  Widget _resultStep() {
    final counts = _counts(_appliedEntries);
    final total = widget.controller.channels.length;
    final roles = LineupTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final headingStyle = LineupTypography.pageTitle.copyWith(
      color: roles.primaryText,
    );
    final infoStyle = textTheme.bodyMedium!.copyWith(
      color: roles.secondaryText,
      fontSize: 24,
      height: 1.4,
    );
    final detailStyle = textTheme.bodyMedium!.copyWith(
      color: roles.secondaryText,
      fontSize: 18,
      height: 1.4,
    );

    final failure = _phase == _BuildPhase.failed;
    final applying = _phase == _BuildPhase.applying;
    final changeSummary = _changeSummary(counts);
    final headline = switch (_phase) {
      _BuildPhase.applying =>
        _firstSetup ? 'Creating your lineup…' : 'Updating your lineup…',
      _BuildPhase.failed =>
        _firstSetup
            ? 'We couldn’t create your lineup'
            : 'We couldn’t update your lineup',
      _BuildPhase.complete =>
        _firstSetup ? 'Your lineup is ready' : 'Your lineup is updated',
      _ => '',
    };
    final copy = Semantics(
      liveRegion: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: _firstSetup ? 116 : 144),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(headline, textAlign: TextAlign.center, style: headingStyle),
            SizedBox(height: 24),
            if (_phase == _BuildPhase.complete) ...[
              Text(
                '$total ${total == 1 ? 'channel' : 'channels'} in your lineup',
                textAlign: TextAlign.center,
                style: infoStyle,
              ),
              if (!_firstSetup && changeSummary.isNotEmpty) ...[
                SizedBox(height: 4),
                Text(
                  changeSummary,
                  textAlign: TextAlign.center,
                  style: detailStyle,
                ),
              ],
            ] else if (applying) ...[
              Text(
                '${_firstSetup ? 'Creating' : 'Updating'} ${_plan!.channels.length} ${_plan!.channels.length == 1 ? 'channel' : 'channels'}',
                textAlign: TextAlign.center,
                style: detailStyle,
              ),
            ] else if (_phase == _BuildPhase.failed) ...[
              Text(
                _firstSetup
                    ? 'Your lineup wasn’t saved.'
                    : 'Your existing lineup hasn’t changed.',
                textAlign: TextAlign.center,
                style: detailStyle,
              ),
              SizedBox(height: 4),
              Text(
                'Your setup choices are still here.',
                textAlign: TextAlign.center,
                style: detailStyle,
              ),
              if (_error != null) ...[
                SizedBox(height: 14),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: detailStyle.copyWith(color: roles.liveAccent),
                ),
              ],
            ],
          ],
        ),
      ),
    );

    final actions = ConstrainedBox(
      constraints: BoxConstraints(minHeight: 120),
      child: applying
          ? SizedBox(height: 120)
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(minWidth: 190),
                  child: FilledButton(
                    focusNode: _resultFocus,
                    onPressed: failure
                        ? () => setState(() => _phase = _BuildPhase.review)
                        : _viewLineup,
                    child: Text(failure ? 'Back to review' : 'View lineup'),
                  ),
                ),
                if (!failure) ...[
                  SizedBox(height: 12),
                  TextButton(
                    onPressed: _addCustom,
                    child: const Text('Add a custom channel'),
                  ),
                ],
              ],
            ),
    );
    final group = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 42,
          height: failure ? 42 : 0,
          child: failure
              ? Icon(
                  Icons.error_outline,
                  size: 42,
                  color: Theme.of(context).colorScheme.error,
                )
              : null,
        ),
        SizedBox(height: 24),
        _revealResult(copy, slot: 'copy'),
        SizedBox(height: 32),
        _revealResult(actions, slot: 'actions'),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 0.0;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 1000),
                child: SizedBox(width: double.infinity, child: group),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _revealResult(Widget child, {required String slot}) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      key: ValueKey('result-$slot-${_phase.name}'),
      tween: Tween(begin: reduced ? 1 : .25, end: 1),
      duration: reduced ? Duration.zero : const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 4),
          child: child,
        ),
      ),
    );
  }

  void _focusResult() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _resultFocus.requestFocus();
  });

  void _viewLineup() =>
      (widget.onViewLineup ?? widget.controller.completeChannelSetup)();
  void _addCustom() =>
      (widget.onAddCustomChannel ?? widget.controller.completeChannelSetup)();

  List<_ReviewEntry> _reviewEntries(List<Channel> planned) {
    final finalChannels = composeChannelPlan(
      existing: _reviewBase
          .where((channel) => !_removeSourceIds.contains(channel.id))
          .toList(),
      planned: planned,
      mode: _mode,
    );
    final before = {for (final channel in _reviewBase) channel.id: channel};
    final finalIds = finalChannels.map((channel) => channel.id).toSet();
    final plannedIds = planned.map((channel) => channel.id).toSet();
    final entries = <_ReviewEntry>[
      for (final channel in finalChannels)
        (
          channel: channel,
          before: before[channel.id],
          kind: before[channel.id] == null
              ? _ReviewKind.added
              : plannedIds.contains(channel.id) &&
                    !canonicalChannelValueEquals(
                      before[channel.id]!.toJson(),
                      channel.toJson(),
                    )
              ? _ReviewKind.updated
              : _ReviewKind.unchanged,
        ),
      for (final channel in _reviewBase.where(
        (channel) => !finalIds.contains(channel.id),
      ))
        (channel: channel, before: channel, kind: _ReviewKind.removed),
    ];
    entries.sort((left, right) {
      final number = left.channel.number.compareTo(right.channel.number);
      return number != 0 ? number : left.kind.index.compareTo(right.kind.index);
    });
    return entries;
  }

  ({int unchanged, int updated, int added, int removed}) _counts(
    List<_ReviewEntry> entries,
  ) => (
    unchanged: entries
        .where((entry) => entry.kind == _ReviewKind.unchanged)
        .length,
    updated: entries.where((entry) => entry.kind == _ReviewKind.updated).length,
    added: entries.where((entry) => entry.kind == _ReviewKind.added).length,
    removed: entries.where((entry) => entry.kind == _ReviewKind.removed).length,
  );

  List<String> _changedFields(Channel? before, Channel after) {
    if (before == null) return const [];
    return [
      if (before.name != after.name) 'Name: ${before.name} → ${after.name}',
      if (before.number != after.number)
        'Number: ${before.number} → ${after.number}',
      if (!canonicalSourceEquals(before.source, after.source))
        'Source: ${_sourceLabel(before.source)} → ${_sourceLabel(after.source)}',
      if (before.playbackMode != after.playbackMode ||
          before.blockSize != after.blockSize ||
          before.includeSpecials != after.includeSpecials)
        'Playback: ${_playbackLabel(before)} → ${_playbackLabel(after)}',
    ];
  }

  Color _scanColor(LibraryScanStatus status) => switch (status) {
    LibraryScanStatus.transientFailure => Theme.of(context).colorScheme.error,
    _ => LineupTheme.of(context).secondaryText,
  };

  String _scanDetail(LibraryScanFact fact) => switch (fact.status) {
    LibraryScanStatus.idle => 'Waiting to scan',
    LibraryScanStatus.scanning => switch (fact.phase) {
      PlexLibraryScanPhase.items =>
        'Scanning · ${fact.completedItems} items checked',
      PlexLibraryScanPhase.collections => 'Loading collections',
      PlexLibraryScanPhase.showGenres => 'Loading show details',
    },
    LibraryScanStatus.complete =>
      'Ready · ${fact.completedItems} ${fact.completedItems == 1 ? 'item' : 'items'} checked',
    LibraryScanStatus.empty => 'No media found',
    LibraryScanStatus.unsupported => 'No playable media found',
    LibraryScanStatus.transientFailure => 'Couldn’t scan · Try again.',
    LibraryScanStatus.cancelled => 'Cancelled · Scan again when you’re ready.',
  };

  String _libraryType(PlexLibrary library) =>
      library.type == PlexLibraryType.show ? 'TV Shows' : 'Movies';

  String _sourceLabel(ContentSource source) => switch (source) {
    PlaylistSource() => 'Playlist',
    LibrarySource(:final libraryId) =>
      widget.controller.libraries
              .where((library) => library.id == libraryId)
              .firstOrNull
              ?.title ??
          'Library',
    MixedSource() => 'Grouped libraries',
    ManualSource() => 'Custom',
  };

  String _playbackLabel(Channel channel) => switch (channel.playbackMode) {
    PlaybackMode.shuffle => 'Shuffle',
    PlaybackMode.sequential => 'In order',
    PlaybackMode.block =>
      'Mini-marathons · ${channel.blockSize ?? 3}${channel.includeSpecials ? ' · specials' : ''}',
  };

  String _changeSummary(
    ({int unchanged, int updated, int added, int removed}) counts,
  ) => [
    if (counts.added > 0) '${counts.added} Added',
    if (counts.updated > 0) '${counts.updated} Updated',
    if (counts.removed > 0) '${counts.removed} Removed',
  ].join(' · ');

  String _modeDescription(ChannelBuildMode mode) => switch (mode) {
    ChannelBuildMode.merge =>
      'Update matching generated channels, add new ones, and keep the rest.',
    ChannelBuildMode.replace => 'Replace all generated channels with this selection. Custom channels will be kept.',
    ChannelBuildMode.append => 'Keep your existing lineup and add channels whose sources are not already in it.',
  };

  bool _supportsGrouping(BuilderStrategy strategy) => const {
    BuilderStrategy.genres,
    BuilderStrategy.studios,
    BuilderStrategy.actors,
    BuilderStrategy.directors,
  }.contains(strategy);

  String _strategyDescription(BuilderStrategy strategy) => switch (strategy) {
    BuilderStrategy.playlists => 'Create channels from your Plex playlists.',
    BuilderStrategy.collections =>
      'Create channels from collections in each selected library.',
    BuilderStrategy.recentlyAdded =>
      'Create channels featuring recent additions from each library.',
    BuilderStrategy.genres =>
      'Channels grouped by genre, such as drama, comedy and science fiction.',
    BuilderStrategy.studios =>
      'Create channels around studios identified in Plex metadata.',
    BuilderStrategy.actors => 'Channels for actors with enough programs.',
    BuilderStrategy.decades => 'Channels grouped by release decade within each library, such as the 1980s and 1990s.',
    BuilderStrategy.directors => 'Channels for directors with enough programs.',
  };

  String _capitalized(String value) =>
      '${value[0].toUpperCase()}${value.substring(1)}';
}

class _Stage extends StatelessWidget {
  const _Stage({
    required this.child,
    required this.footer,
    this.footerGap = 12,
  });

  final Widget child;
  final Widget footer;
  final double footerGap;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final singleScroll =
        media.size.width < 900 ||
        media.size.height < 720 ||
        media.textScaler.scale(14) >= 24;
    if (singleScroll) {
      return Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              key: const ValueKey('channel-setup-single-scroll'),
              child: SizedBox(
                height: math.max(760, media.size.height - 120),
                child: child,
              ),
            ),
          ),
          SizedBox(height: footerGap),
          footer,
        ],
      );
    }
    return Column(
      children: [
        Expanded(child: child),
        SizedBox(height: footerGap),
        footer,
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.leading,
    required this.trailing,
    this.summary,
    this.configuration = false,
  });

  final List<Widget> leading;
  final Widget trailing;
  final Widget? summary;
  final bool configuration;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    if (configuration) {
      final double footerTop = 24;
      final actionGroup = Wrap(
        spacing: 20,
        runSpacing: 12,
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [...leading, trailing],
      );
      return DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: roles.subtleBorder)),
        ),
        child: Padding(
          padding: EdgeInsets.only(top: footerTop),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow =
                  constraints.maxWidth < 800 ||
                  MediaQuery.textScalerOf(context).scale(1) >= 1.5;
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ?summary,
                    SizedBox(height: 12),
                    Align(alignment: Alignment.centerRight, child: actionGroup),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (summary != null) Expanded(child: summary!),
                  if (summary != null) SizedBox(width: 24),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: actionGroup,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: roles.subtleBorder)),
      ),
      child: Padding(
        padding: EdgeInsets.only(top: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (leading.isNotEmpty) Wrap(spacing: 8, children: leading),
            if (summary != null) ...[
              SizedBox(width: 16),
              Expanded(child: summary!),
            ] else
              const Spacer(),
            SizedBox(width: 16),
            trailing,
          ],
        ),
      ),
    );
  }
}
