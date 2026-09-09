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
import 'setup_result_atmosphere.dart';

enum _BuildPhase { review, applying, failed, complete }

enum _ReviewKind { unchanged, updated, added, removed }

enum _ReviewFilter { all, unchanged, updated, added, removed }

typedef _ReviewEntry = ({Channel channel, Channel? before, _ReviewKind kind});

// Interpolate the approved 720p and 1080p configuration dimensions.
double _configurationExpansion(Size size) =>
    math.max(0, (math.min(size.width / 1280, size.height / 720) - 1) * 2);

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
    final size = MediaQuery.sizeOf(context);
    final expansion = _configurationExpansion(size);
    final resultState = _step == 3 && _phase != _BuildPhase.review;
    final refined = _step == 1 || _step == 2 || _step == 3;
    final scale = refined
        ? (14 + 4 * expansion) / 14
        : LineupLayout.scaleFor(size);
    final page = SafeArea(
      child: Theme(
        data: Theme.of(context).copyWith(
          textTheme: Theme.of(context).textTheme.apply(fontSizeFactor: scale),
        ),
        child: Padding(
          key: const ValueKey('channel-setup-content'),
          padding: refined
              ? EdgeInsets.symmetric(
                  horizontal: 32 + 16 * expansion,
                  vertical: 24 + 12 * expansion,
                )
              : LineupLayout.pageInsets(size),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_step != 1) ...[
                _header(),
                SizedBox(height: refined ? 20 + 12 * expansion : 20 * scale),
              ],
              if (_error != null &&
                  _phase != _BuildPhase.failed &&
                  _step != 1) ...[
                LineupNotice(message: _error!),
                SizedBox(height: 12 * scale),
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
        subtitleText: _librarySummary(),
        activeStep: 1,
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
        activeStep: 3,
      );
    }
    return _configurationHeader(showTitle: false, activeStep: 3);
  }

  Widget _configurationHeader({
    String titleText = 'Shape your lineup',
    String? subtitleText,
    int activeStep = 2,
    bool showTitle = true,
  }) => LayoutBuilder(
    key: const ValueKey('channel-setup-header'),
    builder: (context, constraints) {
      final expansion = _configurationExpansion(MediaQuery.sizeOf(context));
      final roles = LineupTheme.of(context);
      final textStyle = TextStyle(
        fontSize: 14 + 4 * expansion,
        height: 1.4,
        color: roles.secondaryText,
      );
      final steps = Text.rich(
        TextSpan(
          style: textStyle,
          children: [
            TextSpan(
              text: '1 Libraries  /  ',
              style: activeStep == 1
                  ? TextStyle(
                      color: roles.primaryText,
                      fontWeight: FontWeight.w600,
                    )
                  : null,
            ),
            TextSpan(
              text: '2 Configure',
              style: activeStep == 2
                  ? TextStyle(
                      color: roles.primaryText,
                      fontWeight: FontWeight.w600,
                    )
                  : null,
            ),
            TextSpan(
              text: '  /  3 Review',
              style: activeStep == 3
                  ? TextStyle(
                      color: roles.primaryText,
                      fontWeight: FontWeight.w600,
                    )
                  : null,
            ),
          ],
        ),
        key: const ValueKey('channel-setup-steps'),
      );
      final brand = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            'assets/branding/lineup-logo-mark.png',
            height: 18 + 6 * expansion,
            excludeFromSemantics: true,
          ),
          SizedBox(width: 10 + 2 * expansion),
          Text(
            'LINEUP',
            style: TextStyle(
              color: roles.progressFill,
              fontFamily: 'Arial',
              fontSize: 14 + 4 * expansion,
              fontWeight: FontWeight.normal,
              letterSpacing: 1.5,
              height: 1.4,
            ),
          ),
        ],
      );
      final title = showTitle
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                brand,
                SizedBox(height: 6 + 4 * expansion),
                Semantics(
                  header: true,
                  child: Text(
                    titleText,
                    style: TextStyle(
                      color: roles.primaryText,
                      fontSize: 28 + 10 * expansion,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ),
                SizedBox(height: 6 + 4 * expansion),
                Text(
                  subtitleText ??
                      switch (_configurationSection) {
                        0 =>
                          'Choose the channels you want from your libraries.',
                        1 => 'Choose how your generated channels will play.',
                        _ => 'Choose the size and balance of your generated lineup.',
                      },
                  style: textStyle.copyWith(height: 1.4),
                ),
              ],
            )
          : brand;
      if (constraints.maxWidth < 900 ||
          MediaQuery.textScalerOf(context).scale(14) >= 21) {
        return Column(
          key: const ValueKey('channel-setup-header-stack'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: steps),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: title),
          const SizedBox(width: 32),
          steps,
        ],
      );
    },
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
    final scanning = controller.libraryScanStatus == LibraryScanStatus.scanning;
    final canContinue = _libraryScanSettled && ready.isNotEmpty;
    final canRetry =
        !scanning &&
        controller.libraryScanStatus != LibraryScanStatus.cancelled &&
        (retry.isNotEmpty || controller.error != null);
    final expansion = _configurationExpansion(MediaQuery.sizeOf(context));
    final roles = LineupTheme.of(context);
    final bodyStyle = Theme.of(context).textTheme.bodyMedium!.copyWith(
      color: roles.secondaryText,
      fontSize: 14 + 4 * expansion,
      height: 1.4,
    );
    final actionStyle = Theme.of(context).textTheme.labelLarge!
        .copyWith(fontSize: 14 + 4 * expansion);
    final retryLabel = retry.isEmpty ? 'Retry scan' : 'Retry failed scans';
    final scanError = _error ?? controller.error;
    final excluded = _selectedLibraries.length - ready.length;
    final footer = _Footer(
      configuration: true,
      summary: !scanning && controller.channelSetupCanCancel
          ? Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: controller.cancelChannelSetup,
                child: Text('Cancel', style: actionStyle),
              ),
            )
          : const SizedBox.shrink(),
      leading: [
        if (canRetry && canContinue)
          OutlinedButton(
            key: const ValueKey('retry-failed-libraries'),
            style: OutlinedButton.styleFrom(textStyle: actionStyle),
            onPressed: controller.busy
                ? null
                : () => _scan(retryFailedOnly: true),
            child: Text(retryLabel),
          ),
      ],
      trailing: scanning
          ? TextButton(
              onPressed: controller.cancelLibraryScan,
              child: Text('Cancel scan', style: actionStyle),
            )
          : canContinue
          ? FilledButton(
              key: const ValueKey('continue-ready-libraries'),
              style: FilledButton.styleFrom(textStyle: actionStyle),
              onPressed: controller.busy ? null : () => _commitLibraries(ready),
              child: Text(
                'Continue with ${ready.length} ${ready.length == 1 ? 'library' : 'libraries'}',
              ),
            )
          : canRetry
          ? FilledButton(
              key: const ValueKey('retry-failed-libraries'),
              style: FilledButton.styleFrom(textStyle: actionStyle),
              onPressed: _selectedLibraries.isEmpty || controller.busy
                  ? null
                  : () => _scan(retryFailedOnly: true),
              child: Text(retryLabel),
            )
          : FilledButton(
              key: const ValueKey('scan-selected-libraries'),
              style: FilledButton.styleFrom(textStyle: actionStyle),
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
            constraints.maxHeight < 640 ||
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
            SizedBox(height: 20 + 12 * expansion),
            if (controller.libraries.isEmpty)
              const Padding(
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
            if (!scanning && scanError != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    scanError,
                    style: bodyStyle.copyWith(color: roles.liveAccent),
                  ),
                ),
              ),
            if (canContinue && excluded > 0)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  '${ready.length} ${ready.length == 1 ? 'library is' : 'libraries are'} ready. Continuing uses only the ready libraries; the other $excluded selected ${excluded == 1 ? 'library will' : 'libraries will'} be excluded.',
                  style: bodyStyle,
                ),
              ),
            SizedBox(height: 16 + 8 * expansion),
            footer,
          ],
        );
        return Align(
          alignment: singleScroll ? Alignment.topCenter : Alignment.center,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(constraints.maxWidth, 880 + 160 * expansion),
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
    final expansion = _configurationExpansion(MediaQuery.sizeOf(context));
    final roles = LineupTheme.of(context);
    final summaryStyle = Theme.of(context).textTheme.bodyMedium!.copyWith(
      color: roles.secondaryText,
      fontSize: 13 + 3 * expansion,
      height: 1.4,
    );
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
      padding: EdgeInsets.only(bottom: 12 + 4 * expansion),
      child: Row(
        children: [
          if (libraries.length > 1) ...[
            Checkbox(
              key: const ValueKey('select-all-libraries'),
              tristate: true,
              value: value,
              onChanged: editable ? (_) => _toggleAllLibraries() : null,
            ),
            TextButton(
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
    final expansion = _configurationExpansion(MediaQuery.sizeOf(context));
    final roles = LineupTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final selected = _selectedLibraries.contains(library.id);
    final fact = widget.controller.libraryScanFacts[library.id];
    final titleStyle = textTheme.bodyMedium!.copyWith(
      color: roles.primaryText,
      fontSize: 16 + 4 * expansion,
      fontWeight: FontWeight.w600,
      height: 1.3,
    );
    final statusStyle = textTheme.bodyMedium!.copyWith(
      fontSize: 14 + 4 * expansion,
      height: 1.4,
    );
    final typeStyle = textTheme.bodyMedium!.copyWith(
      color: roles.mutedText,
      fontSize: 13 + 3 * expansion,
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
            Text(library.title, style: titleStyle),
            if (fact != null) ...[
              const SizedBox(height: 8),
              Text(
                _scanDetail(fact),
                style: statusStyle.copyWith(color: _scanColor(fact.status)),
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
                  Checkbox(
                    value: selected,
                    onChanged: widget.controller.busy ? null : (_) => toggle(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        details,
                        const SizedBox(height: 8),
                        Align(alignment: Alignment.centerRight, child: type),
                      ],
                    ),
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: selected,
                    onChanged: widget.controller.busy ? null : (_) => toggle(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: details),
                  const SizedBox(width: 16),
                  type,
                ],
              );
        return MergeSemantics(
          child: InkWell(
            canRequestFocus: false,
            excludeFromSemantics: true,
            onTap: widget.controller.busy ? null : toggle,
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: 12 + 6 * expansion,
                horizontal: 8,
              ),
              child: content,
            ),
          ),
        );
      },
    );
  }

  Future<void> _scan({bool retryFailedOnly = false}) async {
    setState(() {
      _error = null;
      _notice = null;
    });
    try {
      final settled = await widget.controller.scanLibraries(
        Set.of(_selectedLibraries),
        retryFailedOnly: retryFailedOnly,
      );
      if (!mounted) return;
      if (!settled) {
        setState(() {});
        return;
      }
      final ready = widget.controller.libraryScanReadyIds.intersection(
        _selectedLibraries,
      );
      if (ready.length == _selectedLibraries.length) {
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
    final size = MediaQuery.sizeOf(context);
    final expansion = _configurationExpansion(size);
    final roles = LineupTheme.of(context);
    final actionHeight = 44 + 12 * expansion;
    final actionPadding = EdgeInsets.symmetric(
      horizontal: 12 + 4 * expansion,
      vertical: 8 + 4 * expansion,
    );
    final actionTextStyle = Theme.of(context).textTheme.labelLarge!.copyWith(
      fontSize: 14 + 4 * expansion,
      height: 1.4,
      fontWeight: FontWeight.normal,
    );
    return _Stage(
      footerGap: 0,
      footer: _Footer(
        configuration: true,
        leading: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: roles.secondaryText,
              minimumSize: Size(0, actionHeight),
              padding: actionPadding,
              textStyle: actionTextStyle,
            ),
            onPressed: () => setState(() => _step = 1),
            child: const Text('Back to libraries'),
          ),
        ],
        summary: _configurationSummary(allocation),
        trailing: FilledButton(
          key: const ValueKey('review-channels'),
          style: FilledButton.styleFrom(
            minimumSize: Size(0, actionHeight),
            padding: actionPadding,
            textStyle: actionTextStyle.copyWith(fontWeight: FontWeight.w600),
          ),
          onPressed: allocation.channels.isEmpty ? null : _prepareReview,
          child: const Text('Review channels'),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const labels = ['Channel sources', 'Playback order', 'Lineup rules'];
          final compact =
              constraints.maxWidth < 900 ||
              MediaQuery.textScalerOf(context).scale(1) >= 1.6;
          final navigationHeight = 44 + 12 * expansion;
          final navigationPadding = EdgeInsets.symmetric(
            horizontal: 12 + 4 * expansion,
            vertical: 8 + 4 * expansion,
          );
          final navigation = [
            for (var index = 0; index < labels.length; index++)
              Semantics(
                selected: _configurationSection == index,
                child: TextButton(
                  key: ValueKey('configure-section-$index'),
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    foregroundColor: roles.primaryText,
                    backgroundColor: _configurationSection == index
                        ? roles.selectedSurface
                        : Colors.transparent,
                    minimumSize: Size(0, navigationHeight),
                    padding: navigationPadding,
                    textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(
                      fontSize: 14 + 4 * expansion,
                      fontWeight: FontWeight.normal,
                      height: 1.4,
                    ),
                  ),
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
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Combine matching values to create shared channels across your selected libraries.',
                      style: TextStyle(
                        color: roles.secondaryText,
                        fontSize: 13 + 3 * expansion,
                        height: 1.4,
                      ),
                    ),
                  ),
                if (_configurationSection == 0)
                  LayoutBuilder(
                    builder: (_, constraints) {
                      final expansion = _configurationExpansion(
                        MediaQuery.sizeOf(context),
                      );
                      final gap = 28 + 12 * expansion;
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
                              const SizedBox(height: 12),
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
                      final rulesGap = 40 + 24 * expansion;
                      if (effectiveWidth < 840) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _limitControls(allocation),
                            const SizedBox(height: 20),
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
                    const SizedBox(height: 16),
                    Expanded(child: content),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 176 + 60 * expansion,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final item in navigation) ...[
                            item,
                            SizedBox(height: 8 + 4 * expansion),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(width: 28 + 12 * expansion),
                    Expanded(child: content),
                  ],
                );
        },
      ),
    );
  }

  Widget _heading(String title, String description) {
    final expansion = _configurationExpansion(MediaQuery.sizeOf(context));
    final roles = LineupTheme.of(context);
    final titleStyle = TextStyle(
      color: roles.primaryText,
      fontSize: 18 + 6 * expansion,
      fontWeight: FontWeight.w600,
      height: 1.3,
    );
    final descriptionStyle = TextStyle(
      color: roles.secondaryText,
      fontSize: 14 + 4 * expansion,
      height: 1.4,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final inline =
            constraints.maxWidth >= 640 &&
            MediaQuery.textScalerOf(context).scale(1) < 1.4;
        return Padding(
          padding: EdgeInsets.only(bottom: 8 + 4 * expansion),
          child: inline
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(title, style: titleStyle),
                    SizedBox(width: 16 + 16 * expansion),
                    Expanded(child: Text(description, style: descriptionStyle)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: titleStyle),
                    const SizedBox(height: 8),
                    Text(description, style: descriptionStyle),
                  ],
                ),
        );
      },
    );
  }

  Widget _configurationSummary(ChannelPlanAllocation result) {
    final expansion = _configurationExpansion(MediaQuery.sizeOf(context));
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
      fontSize: 14 + 4 * expansion,
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
                  fontSize: 22 + 8 * expansion,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(width: 8),
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
    final expansion = _configurationExpansion(MediaQuery.sizeOf(context));
    final canGroup =
        _supportsGrouping(strategy) && _selectedLibraries.length > 1;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12 + 4 * expansion),
      child: ListTileTheme.merge(
        titleAlignment: ListTileTitleAlignment.top,
        child: Column(
          children: [
            _sourceSelectionControl(strategy, allocation),
            if (canGroup)
              Padding(
                padding: const EdgeInsets.only(top: 8),
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
    final expansion = _configurationExpansion(MediaQuery.sizeOf(context));
    final roles = LineupTheme.of(context);
    final rowPadding = 12 + 4 * expansion;
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
    final expansion = _configurationExpansion(MediaQuery.sizeOf(context));
    final roles = LineupTheme.of(context);
    final enabled = _strategies.contains(strategy);
    final eligible = allocation.eligibleOriginalsByStrategy[strategy] ?? 0;
    final included = allocation.allocatedOriginalsByStrategy[strategy] ?? 0;
    final nameStyle = TextStyle(
      color: roles.primaryText,
      fontSize: 16 + 6 * expansion,
      fontWeight: FontWeight.w600,
      height: 1.4,
    );
    final countStyle = TextStyle(
      color: roles.secondaryText,
      fontSize: 13 + 3 * expansion,
      height: 1.4,
    );
    final detailStyle = TextStyle(
      color: roles.secondaryText,
      fontSize: 13 + 5 * expansion,
      height: 1.4,
    );
    return CheckboxListTile(
      value: enabled,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(builderStrategyLabels[strategy]!, style: nameStyle),
          ),
          const SizedBox(width: 12),
          Flexible(
            fit: FlexFit.tight,
            child: Text(
              '$eligible qualifying · $included included',
              textAlign: TextAlign.end,
              style: countStyle,
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: EdgeInsets.only(top: 8 + 4 * expansion),
        child: Text(_strategyDescription(strategy), style: detailStyle),
      ),
      onChanged: (value) => setState(() {
        if (value == true) {
          _strategies.add(strategy);
        } else {
          _strategies.remove(strategy);
        }
      }),
    );
  }

  Widget _sourceGroupingControl(BuilderStrategy strategy) {
    final expansion = _configurationExpansion(MediaQuery.sizeOf(context));
    final roles = LineupTheme.of(context);
    final enabled = _strategies.contains(strategy);
    final countStyle = TextStyle(
      color: roles.secondaryText,
      fontSize: 13 + 3 * expansion,
      height: 1.4,
    );
    return Padding(
      padding: const EdgeInsets.only(left: 56),
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
          final dropdown = SizedBox(
            width: math.min(300, constraints.maxWidth),
            height: 40 + 4 * expansion,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: roles.primarySurface,
                border: Border.all(color: roles.defaultBorder),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<bool>(
                  key: ValueKey('source-grouping-${strategy.name}'),
                  isExpanded: true,
                  isDense: true,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  value: _grouped.contains(strategy),
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    fontSize: 13 + 3 * expansion,
                    height: 1.4,
                    color: enabled ? roles.primaryText : roles.mutedText,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: false,
                      child: Text('Separate by library'),
                    ),
                    DropdownMenuItem(value: true, child: Text(groupingLabel)),
                  ],
                  onChanged: enabled
                      ? (value) => setState(() {
                          if (value == true) {
                            _grouped.add(strategy);
                          } else {
                            _grouped.remove(strategy);
                          }
                        })
                      : null,
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
                      const SizedBox(width: 8),
                      dropdown,
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [label, const SizedBox(height: 8), dropdown],
                  ),
          );
        },
      ),
    );
  }

  Widget _playbackControls() {
    final expansion = _configurationExpansion(MediaQuery.sizeOf(context));
    final sectionGap = 16 + 8 * expansion;
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
            final gap = 12 + 8 * expansion;
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
        SizedBox(height: sectionGap),
        _episodeStrip(),
        if (_playback == PlaybackMode.block) ...[
          SizedBox(height: 12 + 4 * expansion),
          Wrap(
            spacing: 20,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [SizedBox(width: 220, child: _blockField(main: true))],
          ),
        ],
        SizedBox(height: 20 + 8 * expansion),
        ListTileTheme.merge(
          titleAlignment: ListTileTitleAlignment.top,
          child: SwitchListTile(
            value: _extras,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Additional channel versions',
              style: TextStyle(
                fontSize: 16 + 6 * expansion,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            subtitle: Padding(
              padding: EdgeInsets.only(top: 8 + 4 * expansion),
              child: Text(
                _playback == PlaybackMode.sequential
                    ? 'Alternate schedules are not available with In order. A different playback mode can still be added.'
                    : 'Create extra channels with alternate schedules or another playback mode.',
                style: TextStyle(
                  color: LineupTheme.of(context).secondaryText,
                  fontSize: 13 + 5 * expansion,
                  height: 1.4,
                ),
              ),
            ),
            onChanged: (value) => setState(() {
              _extras = value;
              _clearIncludeSpecialsIfUnused();
            }),
          ),
        ),
        if (_extras)
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<PlaybackMode?>(
                  isExpanded: true,
                  initialValue: _variantMode,
                  decoration: const InputDecoration(
                    labelText: 'Different playback mode',
                  ),
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
              if (_variantMode == PlaybackMode.block)
                SizedBox(width: 210, child: _blockField(main: false)),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<int>(
                  initialValue: _alternateCopies,
                  decoration: const InputDecoration(
                    labelText: 'Alternate schedules',
                  ),
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
            ],
          ),
        if (_playback == PlaybackMode.block ||
            (_extras && _variantMode == PlaybackMode.block))
          CheckboxMenuButton(
            value: _includeSpecials,
            onChanged: (value) =>
                setState(() => _includeSpecials = value ?? false),
            child: const Text('Include specials'),
          ),
        if (_notice != null)
          Text(
            _notice!,
            style: TextStyle(color: LineupTheme.of(context).secondaryText),
          ),
      ],
    );
  }

  Widget _playbackChoice(
    PlaybackMode mode,
    String title,
    String description, {
    required double width,
  }) {
    final expansion = _configurationExpansion(MediaQuery.sizeOf(context));
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
              final focused = state.states.contains(WidgetState.focused);
              final hovered = state.states.contains(WidgetState.hovered);
              final radius = BorderRadius.circular(roles.panelRadius);
              final surface = selected
                  ? roles.selectedSurface
                  : roles.primarySurface;
              return Container(
                constraints: BoxConstraints(minHeight: 104 + 48 * expansion),
                padding: EdgeInsets.all(16 + 8 * expansion),
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
                        fontSize: 16 + 6 * expansion,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                        letterSpacing: 0,
                      ),
                    ),
                    SizedBox(height: 8 + 4 * expansion),
                    Text(
                      description,
                      style: TextStyle(
                        color: roles.secondaryText,
                        fontSize: 13 + 5 * expansion,
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
    final expansion = _configurationExpansion(MediaQuery.sizeOf(context));
    final roles = LineupTheme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(vertical: 16 + 12 * expansion),
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
          final gap = 8 + 4 * expansion;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Illustrative schedule · Each tile is one episode',
                style: TextStyle(
                  color: roles.secondaryText,
                  fontSize: 14 + 4 * expansion,
                  height: 1.4,
                ),
              ),
              SizedBox(height: 12 + 8 * expansion),
              Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final episode in episodes)
                    SizedBox(
                      width: width,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: roles.primarySurface,
                          border: Border(
                            left: BorderSide(
                              color: roles.defaultBorder,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: 12 + 10 * expansion,
                            horizontal: 12 + 8 * expansion,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                episode.$1,
                                style: TextStyle(
                                  fontSize: 14 + 6 * expansion,
                                  height: 1.4,
                                ),
                              ),
                              SizedBox(height: 4 + 4 * expansion),
                              Text(
                                'Episode ${episode.$2}',
                                style: TextStyle(
                                  color: roles.secondaryText,
                                  fontSize: 12 + 5 * expansion,
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
              const SizedBox(height: 12),
              Text(
                switch (_playback) {
                  PlaybackMode.shuffle => 'The example mixes episodes across shows. Tuning in joins the channel’s ongoing schedule.',
                  PlaybackMode.sequential => 'This example source is already episode-ordered. In order preserves source order; it does not re-sort episodes.',
                  PlaybackMode.block =>
                    'Up to $_blockSize episodes from one show play before the next show. Episodes follow season and episode order within each show.',
                },
                style: TextStyle(
                  color: roles.secondaryText,
                  fontSize: 13 + 5 * expansion,
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

  Widget _blockField({required bool main}) => DropdownButtonFormField<int>(
    initialValue: main ? _blockSize : _variantBlockSize,
    decoration: InputDecoration(
      labelText: main ? 'Episodes per block' : 'Extra block size',
    ),
    items: const [2, 3, 4, 5]
        .map((value) => DropdownMenuItem(value: value, child: Text('$value')))
        .toList(),
    onChanged: (value) => setState(() {
      if (main) {
        _blockSize = value!;
      } else {
        _variantBlockSize = value!;
      }
      _clearDuplicateVariant();
    }),
  );

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
    final expansion = _configurationExpansion(MediaQuery.sizeOf(context));
    final roles = LineupTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final headingStyle = textTheme.titleMedium!.copyWith(
      color: roles.primaryText,
      fontSize: 18 + 6 * expansion,
      fontWeight: FontWeight.w600,
      height: 1.3,
    );
    final subtitleStyle = textTheme.bodyMedium!.copyWith(
      color: roles.secondaryText,
      fontSize: 14 + 4 * expansion,
      height: 1.4,
    );
    final labelStyle = textTheme.bodyMedium!.copyWith(
      color: roles.primaryText,
      fontSize: 16 + 6 * expansion,
      fontWeight: FontWeight.normal,
      height: 1.4,
    );
    final descriptionStyle = textTheme.bodyMedium!.copyWith(
      color: roles.secondaryText,
      fontSize: 13 + 5 * expansion,
      height: 1.4,
    );
    final dropdownStyle = textTheme.bodyMedium!.copyWith(
      color: roles.primaryText,
      fontSize: 14 + 4 * expansion,
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
          padding: EdgeInsets.symmetric(vertical: 24 + 12 * expansion),
          child: LayoutBuilder(
            builder: (_, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              final desiredWidth = 90 + 20 * expansion;
              final dropdownWidth = math.min(
                desiredWidth,
                constraints.maxWidth,
              );
              final inline =
                  constraints.maxWidth / textScale >= 320 &&
                  constraints.maxWidth >= dropdownWidth + 16;
              final dropdown = Semantics(
                label: label,
                container: true,
                child: SizedBox(
                  width: dropdownWidth,
                  height: 36 + 12 * expansion,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: roles.primarySurface,
                      border: Border.all(color: roles.defaultBorder),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        key: key,
                        isExpanded: true,
                        isDense: true,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        value: value,
                        style: dropdownStyle,
                        items: [
                          for (final choice in choices)
                            DropdownMenuItem(
                              value: choice,
                              child: Text('$choice'),
                            ),
                        ],
                        onChanged: (next) {
                          if (next != null) onChanged(next);
                        },
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
                        const SizedBox(width: 16),
                        dropdown,
                      ],
                    )
                  else ...[
                    Text(label, style: labelStyle),
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerLeft, child: dropdown),
                  ],
                  SizedBox(height: 10 + 6 * expansion),
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
        const SizedBox(height: 8),
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
    final expansion = _configurationExpansion(MediaQuery.sizeOf(context));
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
        margin: EdgeInsets.only(top: 24 + 12 * expansion),
        padding: EdgeInsets.only(left: 14 + 6 * expansion),
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
            fontSize: 13 + 5 * expansion,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _orderControls() {
    final expansion = _configurationExpansion(MediaQuery.sizeOf(context));
    final roles = LineupTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final headingStyle = textTheme.titleMedium!.copyWith(
      color: roles.primaryText,
      fontSize: 18 + 6 * expansion,
      fontWeight: FontWeight.w600,
      height: 1.3,
    );
    final subtitleStyle = textTheme.bodyMedium!.copyWith(
      color: roles.secondaryText,
      fontSize: 14 + 4 * expansion,
      height: 1.4,
    );
    final nameStyle = textTheme.bodyMedium!.copyWith(
      color: roles.primaryText,
      fontSize: 15 + 6 * expansion,
      height: 1.4,
    );
    final rankStyle = textTheme.bodyMedium!.copyWith(
      color: roles.secondaryText,
      fontSize: 13 + 5 * expansion,
      height: 1.4,
    );
    final rowHeight = 42 + 18 * expansion;
    final buttonSize = 32 + 12 * expansion;
    final buttonIconSize = 20 + 4 * expansion;
    final rowGap = 12 + 4 * expansion;

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
                color: hovered || focused
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
                      width: 20 + 8 * expansion,
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
                    const SizedBox(width: 8),
                    Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          focusNode: _orderFocus[strategy]!.earlier,
                          constraints: BoxConstraints.tightFor(
                            width: buttonSize,
                            height: buttonSize,
                          ),
                          padding: EdgeInsets.zero,
                          iconSize: buttonIconSize,
                          tooltip: 'Move earlier',
                          onPressed: index == 0
                              ? null
                              : () => _moveSource(index, -1),
                          icon: const Icon(Icons.arrow_upward),
                        ),
                        IconButton(
                          focusNode: _orderFocus[strategy]!.later,
                          constraints: BoxConstraints.tightFor(
                            width: buttonSize,
                            height: buttonSize,
                          ),
                          padding: EdgeInsets.zero,
                          iconSize: buttonIconSize,
                          tooltip: 'Move later',
                          onPressed: index == _sourceOrder.length - 1
                              ? null
                              : () => _moveSource(index, 1),
                          icon: const Icon(Icons.arrow_downward),
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
        const SizedBox(height: 8),
        Text(
          'Take one channel from each source, then repeat.',
          style: subtitleStyle,
        ),
        SizedBox(height: 16 + 8 * expansion),
        for (var index = 0; index < _sourceOrder.length; index++)
          rowFor(index, _sourceOrder[index]),
        SizedBox(height: 16 + 8 * expansion),
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
      existing: _reviewBase,
      planned: _plan!.channels,
      mode: _mode,
    );
    final noChanges =
        counts.added == 0 && counts.updated == 0 && counts.removed == 0;
    final expansion = _configurationExpansion(MediaQuery.sizeOf(context));
    final roles = LineupTheme.of(context);
    final actionStyle = FilledButton.styleFrom(
      textStyle: Theme.of(context).textTheme.labelLarge!
          .copyWith(fontSize: 14 + 4 * expansion, fontWeight: FontWeight.w600),
    );
    return _Stage(
      footer: _Footer(
        configuration: true,
        leading: [
          TextButton(
            onPressed: () => setState(() => _step = 2),
            child: const Text('Back to configure'),
          ),
        ],
        summary: _firstSetup ? const SizedBox.shrink() : _methodDecision(),
        trailing: noChanges
            ? FilledButton(
                style: actionStyle,
                onPressed: _viewLineup,
                child: const Text('View lineup'),
              )
            : FilledButton(
                style: actionStyle,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_notice != null && _notice != 'Updating review…') ...[
            LineupNotice(message: _notice!),
            const SizedBox(height: 8),
          ],
          if (noChanges) ...[
            Text(
              'Your lineup is already up to date',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const Text('No changes needed.'),
            const SizedBox(height: 8),
          ],
          _reviewOverview(entries, finalChannels, counts),
          SizedBox(height: 16 + 8 * expansion),
          Expanded(child: _roster(entries)),
          if (counts.removed > 0)
            Padding(
              padding: EdgeInsets.only(top: 12 + 4 * expansion),
              child: CheckboxListTile(
                key: const ValueKey('channel-setup-replace-confirmation'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                value: _removalConfirmed,
                title: Text(
                  'I understand that ${counts.removed} existing generated ${counts.removed == 1 ? 'channel' : 'channels'} will be removed.',
                  style: TextStyle(color: roles.liveAccent),
                ),
                onChanged: (value) =>
                    setState(() => _removalConfirmed = value == true),
              ),
            ),
        ],
      ),
    );
  }

  Widget _methodDecision() {
    if (_firstSetup) return const SizedBox.shrink();
    final expansion = _configurationExpansion(MediaQuery.sizeOf(context));
    final roles = LineupTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final methodStyle = textTheme.bodyMedium!.copyWith(
      color: roles.primaryText,
      fontSize: 14 + 4 * expansion,
      height: 1.4,
    );
    final helpStyle = textTheme.bodyMedium!.copyWith(
      color: roles.secondaryText,
      fontSize: 13 + 5 * expansion,
      height: 1.4,
    );
    final dropdown = SizedBox(
      width: 240 + 90 * expansion,
      child: DropdownButtonFormField<ChannelBuildMode>(
        key: const ValueKey('review-build-method'),
        initialValue: _mode,
        isExpanded: true,
        style: methodStyle,
        decoration: const InputDecoration(labelText: 'Build method'),
        items: const [
          DropdownMenuItem(
            value: ChannelBuildMode.merge,
            child: Text('Update and add'),
          ),
          DropdownMenuItem(
            value: ChannelBuildMode.replace,
            child: Text('Replace generated channels'),
          ),
          DropdownMenuItem(
            value: ChannelBuildMode.append,
            child: Text('Add as new channels'),
          ),
        ],
        onChanged: (mode) {
          setState(() {
            _mode = mode!;
            _removalConfirmed = false;
            _notice = 'Updating review…';
            _plan = _allocateReview(_reviewBase);
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _notice = null);
          });
        },
      ),
    );
    final explanation = Text(
      _notice == 'Updating review…' ? _notice! : _modeDescription(_mode),
      style: helpStyle,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final effectiveWidth =
            constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1);
        final inline = effectiveWidth >= 700;
        if (inline) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              dropdown,
              SizedBox(width: 20 + 8 * expansion),
              Expanded(child: explanation),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [dropdown, const SizedBox(height: 8), explanation],
        );
      },
    );
  }

  Widget _reviewOverview(
    List<_ReviewEntry> entries,
    List<Channel> finalChannels,
    ({int unchanged, int updated, int added, int removed}) counts,
  ) {
    final expansion = _configurationExpansion(MediaQuery.sizeOf(context));
    final roles = LineupTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final finalCount = finalChannels.length;
    final generated = _finalGeneratedCounts(finalChannels);
    final totalStyle = textTheme.titleLarge!.copyWith(
      color: roles.primaryText,
      fontSize: 24 + 12 * expansion,
      fontWeight: FontWeight.w600,
      height: 1.2,
    );
    final currentStyle = textTheme.bodyMedium!.copyWith(
      color: roles.secondaryText,
      fontSize: 14 + 4 * expansion,
      height: 1.4,
    );
    final supportingStyle = textTheme.bodyMedium!.copyWith(
      color: roles.secondaryText,
      fontSize: 13 + 5 * expansion,
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
                    size: 24 + 8 * expansion,
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
    final sourceBreakdown = Wrap(
      spacing: 18 + 6 * expansion,
      runSpacing: 4,
      children: [
        Text('Final generated channels', style: supportingStyle),
        for (final strategy in _sourceOrder)
          if ((generated.byStrategy[strategy] ?? 0) > 0)
            Text.rich(
              TextSpan(
                text: '${builderStrategyLabels[strategy]} ',
                style: supportingStyle,
                children: [
                  TextSpan(
                    text: '${generated.byStrategy[strategy]}',
                    style: supportingStyle.copyWith(
                      color: roles.primaryText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        if (generated.other > 0)
          Text.rich(
            TextSpan(
              text: 'Other generated ',
              style: supportingStyle,
              children: [
                TextSpan(
                  text: '${generated.other}',
                  style: supportingStyle.copyWith(
                    color: roles.primaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: roles.primarySurface,
        border: Border.all(color: roles.subtleBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: EdgeInsets.all(20 + 8 * expansion),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                    if (!_firstSetup) ...[const SizedBox(height: 12), filters],
                  ],
                );
              },
            ),
            if (!_firstSetup) ...[
              SizedBox(height: 16 + 8 * expansion),
              Text(
                'Changes in this review${counts.removed > 0 ? ' · Includes channels being removed' : ''}',
                style: supportingStyle,
              ),
              SizedBox(height: 8 + 4 * expansion),
              if (entries.isNotEmpty)
                Semantics(
                  label:
                      '${counts.unchanged} unchanged, ${counts.updated} updated, ${counts.added} added, ${counts.removed} removed. ${entries.length} review entries including outgoing channels.',
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        _segment(
                          counts.unchanged,
                          roles.mutedText,
                          height: 10 + 4 * expansion,
                        ),
                        _segment(
                          counts.updated,
                          roles.focusBorder,
                          height: 10 + 4 * expansion,
                        ),
                        _segment(
                          counts.added,
                          roles.progressFill,
                          height: 10 + 4 * expansion,
                        ),
                        _segment(
                          counts.removed,
                          Theme.of(context).colorScheme.error,
                          height: 10 + 4 * expansion,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            SizedBox(height: 16 + 8 * expansion),
            Divider(height: 1, color: roles.subtleBorder),
            SizedBox(height: 12 + 4 * expansion),
            sourceBreakdown,
            if (_reviewBase.any((channel) => channel.builderKey == null))
              Padding(
                padding: const EdgeInsets.only(top: 8),
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
    final expansion = _configurationExpansion(MediaQuery.sizeOf(context));
    final roles = LineupTheme.of(context);
    final selected = _filter == filter;
    final swatchColor = count == 0
        ? roles.subtleBorder
        : switch (filter) {
            _ReviewFilter.unchanged => roles.mutedText,
            _ReviewFilter.updated => roles.focusBorder,
            _ReviewFilter.added => roles.progressFill,
            _ReviewFilter.removed => Theme.of(context).colorScheme.error,
            _ReviewFilter.all => roles.mutedText,
          };
    final textStyle = Theme.of(context).textTheme.bodyMedium!.copyWith(
      color: roles.primaryText,
      fontSize: 13 + 5 * expansion,
      height: 1.4,
    );
    return Semantics(
      selected: selected,
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: roles.primaryText,
          backgroundColor: selected
              ? roles.selectedSurface
              : Colors.transparent,
          side: selected
              ? BorderSide(color: roles.defaultBorder)
              : BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          minimumSize: Size(0, 32 + 12 * expansion),
          padding: EdgeInsets.symmetric(
            horizontal: 8 + 4 * expansion,
            vertical: 4 + 4 * expansion,
          ),
          textStyle: textStyle,
        ),
        onPressed: () => setState(() => _filter = filter),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8 + 2 * expansion,
              height: 8 + 2 * expansion,
              color: swatchColor,
            ),
            SizedBox(width: 8 + 2 * expansion),
            Text('$count ${_capitalized(filter.name)}'),
          ],
        ),
      ),
    );
  }

  Widget _roster(List<_ReviewEntry> all) {
    final expansion = _configurationExpansion(MediaQuery.sizeOf(context));
    final roles = LineupTheme.of(context);
    final textStyle = Theme.of(context).textTheme.bodyMedium!.copyWith(
      color: roles.secondaryText,
      fontSize: 13 + 5 * expansion,
      height: 1.4,
    );
    final searchStyle = Theme.of(context).textTheme.bodyMedium!.copyWith(
      color: roles.primaryText,
      fontSize: 14 + 4 * expansion,
      height: 1.4,
    );
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (!_firstSetup) ...[
              const SizedBox(width: 12),
              TextButton(
                key: const ValueKey('review-show-all'),
                style: TextButton.styleFrom(
                  foregroundColor: roles.secondaryText,
                  textStyle: searchStyle,
                  minimumSize: Size(0, 44 + 4 * expansion),
                  padding: EdgeInsets.symmetric(horizontal: 8 + 4 * expansion),
                ),
                onPressed: () => setState(() => _filter = _ReviewFilter.all),
                child: const Text('Show all'),
              ),
            ],
          ],
        ),
        SizedBox(height: 6 + 2 * expansion),
        Text(
          filtered
              ? '${_capitalized(_filter.name)} · ${entries.length} matching ${entries.length == 1 ? 'channel' : 'channels'}'
              : '${entries.length} of ${all.length} review entries',
          style: textStyle,
        ),
        SizedBox(height: 8 + 4 * expansion),
        _rosterHeader(),
        Expanded(
          child: entries.isEmpty
              ? _emptyRoster(query, filtered)
              : ListView.builder(
                  key: const ValueKey('channel-setup-review-roster'),
                  itemCount: entries.length,
                  itemBuilder: (_, index) => _reviewRow(entries[index]),
                ),
        ),
      ],
    );
  }

  Widget _rosterHeader() {
    final expansion = _configurationExpansion(MediaQuery.sizeOf(context));
    final roles = LineupTheme.of(context);
    final headerStyle = Theme.of(context).textTheme.bodyMedium!.copyWith(
      color: roles.secondaryText,
      fontSize: 14 + 4 * expansion,
      height: 1.4,
    );
    final numberWidth = 58 + 22 * expansion;
    final changeWidth = 92 + 28 * expansion;
    return DecoratedBox(
      key: const ValueKey('review-roster-header'),
      decoration: BoxDecoration(color: roles.primarySurface),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          6 + 2 * expansion,
          52,
          6 + 2 * expansion,
        ),
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
        TextButton(
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
    final expansion = _configurationExpansion(MediaQuery.sizeOf(context));
    final roles = LineupTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final nameStyle = textTheme.bodyMedium!.copyWith(
      color: roles.primaryText,
      fontSize: 15 + 5 * expansion,
      height: 1.4,
    );
    final metaStyle = textTheme.bodyMedium!.copyWith(
      color: roles.secondaryText,
      fontSize: 14 + 4 * expansion,
      height: 1.4,
    );
    final changeStyle = metaStyle.copyWith(
      color: switch (entry.kind) {
        _ReviewKind.unchanged => roles.mutedText,
        _ReviewKind.updated => roles.focusBorder,
        _ReviewKind.added => roles.progressFill,
        _ReviewKind.removed => Theme.of(context).colorScheme.error,
      },
    );
    final numberWidth = 58 + 22 * expansion;
    final changeWidth = 92 + 28 * expansion;
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
            _capitalized(entry.kind.name),
            textAlign: TextAlign.end,
            style: changeStyle,
          ),
        ),
      ],
    );
    final changes = _changedFields(entry.before, entry.channel);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: LineupTheme.of(context).subtleBorder),
        ),
      ),
      child: entry.kind == _ReviewKind.updated && changes.isNotEmpty
          ? ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
              title: content,
              childrenPadding: EdgeInsets.fromLTRB(
                numberWidth + 12,
                0,
                12,
                12 + 4 * expansion,
              ),
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
              padding: EdgeInsets.fromLTRB(
                12,
                13 + 3 * expansion,
                52,
                13 + 3 * expansion,
              ),
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
    final expansion = _configurationExpansion(MediaQuery.sizeOf(context));
    final roles = LineupTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final headingStyle = textTheme.headlineMedium!.copyWith(
      color: roles.primaryText,
      fontSize: 36 + 12 * expansion,
      fontWeight: FontWeight.w600,
      height: 1.18,
      letterSpacing: -1.2,
    );
    final infoStyle = textTheme.bodyMedium!.copyWith(
      color: roles.secondaryText,
      fontSize: 20 + 4 * expansion,
      height: 1.4,
    );
    final detailStyle = textTheme.bodyMedium!.copyWith(
      color: roles.secondaryText,
      fontSize: 14 + 4 * expansion,
      height: 1.4,
    );
    final actionStyle = textTheme.labelLarge!.copyWith(
      fontSize: 14 + 4 * expansion,
      height: 1.4,
      fontWeight: FontWeight.w600,
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
        constraints: BoxConstraints(
          minHeight: _firstSetup ? 96 + 20 * expansion : 120 + 24 * expansion,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(headline, textAlign: TextAlign.center, style: headingStyle),
            SizedBox(height: 16 + 8 * expansion),
            if (_phase == _BuildPhase.complete) ...[
              Text(
                '$total ${total == 1 ? 'channel' : 'channels'} in your lineup',
                textAlign: TextAlign.center,
                style: infoStyle,
              ),
              if (!_firstSetup && changeSummary.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  changeSummary,
                  textAlign: TextAlign.center,
                  style: detailStyle,
                ),
              ],
            ] else if (_phase == _BuildPhase.failed) ...[
              Text(
                _firstSetup
                    ? 'Your lineup wasn’t saved.'
                    : 'Your existing lineup hasn’t changed.',
                textAlign: TextAlign.center,
                style: detailStyle,
              ),
              const SizedBox(height: 4),
              Text(
                'Your setup choices are still here.',
                textAlign: TextAlign.center,
                style: detailStyle,
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
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
    final actionHeight = 48 + 8 * expansion;
    final actions = ConstrainedBox(
      constraints: BoxConstraints(minHeight: 108 + 12 * expansion),
      child: applying
          ? SizedBox(height: 108 + 12 * expansion)
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(minWidth: 170 + 20 * expansion),
                  child: FilledButton(
                    focusNode: _resultFocus,
                    style: FilledButton.styleFrom(
                      minimumSize: Size(0, actionHeight),
                      textStyle: actionStyle,
                    ),
                    onPressed: failure
                        ? () => setState(() => _phase = _BuildPhase.review)
                        : _viewLineup,
                    child: Text(failure ? 'Back to review' : 'View lineup'),
                  ),
                ),
                if (!failure) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: roles.secondaryText,
                      minimumSize: Size(0, 44 + 4 * expansion),
                      textStyle: actionStyle,
                    ),
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
        SizedBox(height: 20 + 4 * expansion),
        _revealResult(copy, slot: 'copy'),
        SizedBox(height: 24 + 8 * expansion),
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
                constraints: BoxConstraints(maxWidth: 800 + 200 * expansion),
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
      existing: _reviewBase,
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
    LibraryScanStatus.scanning =>
      'Scanning · ${fact.completedItems} items checked',
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
    ChannelBuildMode.append => 'Keep your existing lineup and add every channel in this selection as a new channel.',
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
      return SingleChildScrollView(
        key: const ValueKey('channel-setup-single-scroll'),
        child: SizedBox(
          height: math.max(760, media.size.height - 120),
          child: Column(
            children: [
              Expanded(child: child),
              SizedBox(height: footerGap),
              footer,
            ],
          ),
        ),
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
      final expansion = _configurationExpansion(MediaQuery.sizeOf(context));
      final footerTop = 16 + 8 * expansion;
      final actionGroup = Wrap(
        spacing: 12 + 8 * expansion,
        runSpacing: 12,
        alignment: WrapAlignment.end,
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
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerRight, child: actionGroup),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (summary != null) Expanded(child: summary!),
                  if (summary != null) const SizedBox(width: 24),
                  actionGroup,
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
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (leading.isNotEmpty) Wrap(spacing: 8, children: leading),
            if (summary != null) ...[
              const SizedBox(width: 16),
              Expanded(child: summary!),
            ] else
              const Spacer(),
            const SizedBox(width: 16),
            trailing,
          ],
        ),
      ),
    );
  }
}
