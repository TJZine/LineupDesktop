import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../channels/channel.dart';
import '../channels/channel_builder.dart';
import '../ui/app_theme.dart';
import '../ui/app_ui.dart';
import 'channel_setup_projection.dart';
import 'channel_setup/step_scaffold.dart';
import 'channel_setup/review_step.dart';
import 'channel_setup/result_step.dart';
import 'channel_setup/library_step.dart';
import 'channel_setup/configure_step.dart';
import 'form_error.dart';
import 'lineup_controller.dart';
import 'lineup_restore_view.dart';
import 'setup_review.dart';
import 'setup_result_atmosphere.dart';

enum _SetupStep { libraries, configure, review, result }

class UpstreamChannelSetupView extends StatefulWidget {
  const UpstreamChannelSetupView({
    required this.controller,
    this.onRequestLogout,
    this.onViewLineup,
    this.onAddCustomChannel,
    super.key,
  });

  final LineupController controller;
  final Future<void> Function()? onRequestLogout;
  final VoidCallback? onViewLineup;
  final VoidCallback? onAddCustomChannel;

  @override
  State<UpstreamChannelSetupView> createState() => _SetupState();
}

class _SetupState extends State<UpstreamChannelSetupView> {
  _SetupStep _step = _SetupStep.libraries;
  int _configurationSection = 0;
  final _selectedLibraries = <String>{};
  final _strategies = <BuilderStrategy>{...BuilderStrategy.values};
  final _grouped = <BuilderStrategy>{};
  final _sourceOrder = <BuilderStrategy>[...BuilderStrategy.values];
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
  SetupPhase? _phase;
  SetupReviewFilter _reviewFilter = SetupReviewFilter.all;
  String _reviewSearch = '';
  bool _discoveryRetry = false;
  String? _notice;
  String? _error;

  SetupReview? get _review => _phase?.review;

  bool get _firstSetup => _review?.base.isEmpty ?? true;

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
    super.dispose();
  }

  final _projection = ChannelSetupProjection();

  List<ChannelProposal> _buildProposals() {
    final inventory = widget.controller.playableInventory;
    return _projection.proposals(
      libraries: widget.controller.libraries,
      selectedLibraries: _selectedLibraries,
      items: inventory.media,
      playlists: inventory.playlists,
      strategies: _strategies,
      strategyOrder: _sourceOrder,
      crossLibraryStrategies: _grouped,
      minimumItems: _minimum,
    );
  }

  ChannelSetupAllocationOptions _allocationOptions(ChannelBuildMode mode) => (
    mode: mode,
    seriesMode: _playback,
    seriesBlockSize: _blockSize,
    alternateCopies: _extras ? _alternateCopies : 0,
    variantMode: _extras ? _variantMode : null,
    variantBlockSize: _variantBlockSize,
    includeSpecials: _includeSpecials,
    minimumItems: _minimum,
    maximumChannels: _maximum,
  );

  ChannelPlanAllocation _allocate(
    List<Channel> existing, {
    List<ChannelProposal>? proposals,
    required ChannelBuildMode mode,
    required DateTime anchor,
  }) => ChannelSetupProjection.allocate(
    proposals ?? _buildProposals(),
    existing: existing,
    options: _allocationOptions(mode),
    anchor: anchor,
  );

  SetupReview _allocateReview(
    List<Channel> existing, {
    required ChannelBuildMode mode,
    required DateTime anchor,
  }) {
    final proposals = _buildProposals();
    final strategyBySource = <String, BuilderStrategy>{};
    for (final proposal in proposals) {
      strategyBySource.putIfAbsent(
        canonicalSourceIdentity(proposal.source),
        () => proposal.strategy,
      );
    }
    return SetupReview(
      base: existing,
      plan: _allocate(
        existing,
        proposals: proposals,
        mode: mode,
        anchor: anchor,
      ),
      mode: mode,
      strategyBySource: strategyBySource,
      planFactory: (nextMode, nextAnchor) {
        final nextProposals = _buildProposals();
        final nextStrategies = <String, BuilderStrategy>{};
        for (final proposal in nextProposals) {
          nextStrategies.putIfAbsent(
            canonicalSourceIdentity(proposal.source),
            () => proposal.strategy,
          );
        }
        return (
          plan: _allocate(
            existing,
            proposals: nextProposals,
            mode: nextMode,
            anchor: nextAnchor,
          ),
          strategyBySource: nextStrategies,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final resultState = _step == _SetupStep.result;
    final phase = _phase;
    final page = SafeArea(
      child: IconTheme.merge(
        data: const IconThemeData(size: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LineupTopBar(
              divider: phase is! Completed && phase is! Applying,
              trailing: Align(
                alignment: Alignment.centerRight,
                child: SingleChildScrollView(child: _setupSteps()),
              ),
            ),
            Expanded(
              child: LineupContentWidth(
                key: const ValueKey('channel-setup-content'),
                maxWidth: _step == _SetupStep.libraries ? 1040 : 1824,
                vertical: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_step != _SetupStep.libraries && !resultState) ...[
                      _header(),
                      const SizedBox(height: 32),
                    ],
                    if (_error != null &&
                        phase is! Failed &&
                        _step != _SetupStep.libraries) ...[
                      LineupNotice(message: _error!),
                      const SizedBox(height: 12),
                    ],
                    Expanded(
                      child: KeyedSubtree(
                        key: const ValueKey('channel-setup-stage'),
                        child: switch (_step) {
                          _SetupStep.libraries => _libraryStep(),
                          _SetupStep.configure => _configureStep(),
                          _SetupStep.review => _reviewStep(),
                          _SetupStep.result => _resultStep(),
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
                applying: phase is Applying,
                failed: phase is Failed,
                child: page,
              )
            : page,
      ),
    );
  }

  Widget _header() {
    if (_step == _SetupStep.configure) return _configurationHeader();
    if (_step == _SetupStep.review) {
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
    final complete = _phase is Completed;
    return Wrap(
      key: const ValueKey('channel-setup-steps'),
      alignment: WrapAlignment.end,
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final (index, label) in [
          (_SetupStep.libraries, 'Libraries'),
          (_SetupStep.configure, 'Configure'),
          (_SetupStep.review, 'Review'),
        ])
          Text(
            '${complete || index.index < _step.index ? "✓" : index.index + 1} $label',
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

  Widget _libraryStep() => SetupLibraryStep(
    controller: widget.controller,
    selectedLibraryIds: Set.unmodifiable(_selectedLibraries),
    error: _error,
    onScan: _scan,
    onCommit: _commitLibraries,
    onToggleLibrary: (id) => setState(() {
      if (_selectedLibraries.contains(id)) {
        _selectedLibraries.remove(id);
      } else {
        _selectedLibraries.add(id);
      }
    }),
    onToggleAll: () => setState(() {
      if (_selectedLibraries.length == widget.controller.libraries.length) {
        _selectedLibraries.clear();
      } else {
        _selectedLibraries
          ..clear()
          ..addAll(widget.controller.libraries.map((library) => library.id));
      }
    }),
    onRequestLogout: widget.onRequestLogout,
  );

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
      final ready = widget.controller.libraryScanCommittableIds.intersection(
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
        _step = _SetupStep.configure;
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
    _buildProposals();
    final allocation = _projection.configure(
      existing: widget.controller.channels,
      options: _allocationOptions(_mode),
    );
    return SetupConfigureStep(
      allocation: allocation,
      section: _configurationSection,
      onSectionChanged: (section) =>
          setState(() => _configurationSection = section),
      onBack: () => setState(() => _step = _SetupStep.libraries),
      onReview: _prepareReview,
      hasConfirmedMissingSources:
          _mode == ChannelBuildMode.merge &&
          allocation.unmatchedGenerated.any(
            widget.controller.isGeneratedSourceConfirmedGone,
          ),
      summary: _configurationSummary(allocation),
      buildSources: (focus) => _configureSectionContent(allocation, 0, focus),
      buildPlayback: (focus) => _configureSectionContent(allocation, 1, focus),
      buildRules: (focus) => _configureSectionContent(allocation, 2, focus),
    );
  }

  Widget _configureSectionContent(
    ChannelPlanAllocation allocation,
    int section,
    SetupConfigureFocus focus,
  ) {
    final roles = LineupTheme.of(context);
    if (section == 0) {
      const sourcePairs = [
        (BuilderStrategy.playlists, BuilderStrategy.collections),
        (BuilderStrategy.recentlyAdded, BuilderStrategy.decades),
        (BuilderStrategy.genres, BuilderStrategy.studios),
        (BuilderStrategy.actors, BuilderStrategy.directors),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_selectedLibraries.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Combine matching values to create shared channels across your selected libraries.',
                style: TextStyle(
                  color: roles.secondaryText,
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
            ),
          LayoutBuilder(
            builder: (_, constraints) {
              final compact =
                  constraints.maxWidth /
                      MediaQuery.textScalerOf(context).scale(1) <
                  840;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < sourcePairs.length; index++) ...[
                    _sourcePair(
                      sourcePairs[index],
                      allocation,
                      compact: compact,
                      columnGap: 40,
                    ),
                    if (index < sourcePairs.length - 1)
                      const SizedBox(height: 12),
                  ],
                ],
              );
            },
          ),
        ],
      );
    }
    if (section == 1) return _playbackControls(focus);
    return LayoutBuilder(
      builder: (_, constraints) {
        final effectiveWidth =
            constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1);
        if (effectiveWidth < 840) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _limitControls(allocation),
              const SizedBox(height: 20),
              _orderControls(focus),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 85, child: _limitControls(allocation)),
            const SizedBox(width: 64),
            Expanded(flex: 115, child: _orderControls(focus)),
          ],
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
        : _projection.disabledEligibility(strategy);
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
    final collectionRecovery = strategy == BuilderStrategy.collections
        ? widget.controller.collectionScaleRecovery(_selectedLibraries)
        : null;
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
        if (collectionRecovery case final recovery?)
          Padding(
            padding: const EdgeInsets.only(left: 56, top: 4),
            child: Text(recovery, style: detailStyle),
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
                label: Text(
                  '$discoveryFailure · ${collectionRecovery != null ? 'Rescan' : 'Retry'}',
                ),
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
      final scaleCount = _selectedLibraries
          .where((id) => controller.collectionScaleRecovery({id}) != null)
          .length;
      final unavailable = controller.unavailableCollectionLibraryIds
          .intersection(_selectedLibraries)
          .length;
      final failed = _selectedLibraries.fold<int>(
        0,
        (count, id) =>
            count + (controller.failedCollectionTitles[id]?.length ?? 0),
      );
      if (scaleCount > 0) {
        final transient = unavailable - scaleCount;
        return [
          'Collection limit exceeded in $scaleCount ${scaleCount == 1 ? 'library' : 'libraries'}',
          if (transient > 0)
            'collections unavailable in $transient other ${transient == 1 ? 'library' : 'libraries'}',
          if (failed > 0)
            '$failed ${failed == 1 ? 'collection' : 'collections'} unavailable',
        ].join(' · ');
      }
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

  Widget _playbackControls(SetupConfigureFocus focus) {
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
                    focus: focus,
                    width: width,
                  ),
                  _playbackChoice(
                    PlaybackMode.sequential,
                    'In order',
                    'Keep the order supplied by the channel’s source.',
                    focus: focus,
                    width: width,
                  ),
                  _playbackChoice(
                    PlaybackMode.block,
                    'Mini-marathons',
                    'Play a few episodes of one show, then move to another.',
                    focus: focus,
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
    required SetupConfigureFocus focus,
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
            focusNode: focus.playback[mode]!,
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

  Widget _orderControls(SetupConfigureFocus focus) {
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
          focus.order[strategy]!.earlier.hasFocus ||
          focus.order[strategy]!.later.hasFocus;
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
                          focusNode: focus.order[strategy]!.earlier,
                          tooltip: 'Move earlier',
                          onPressed: index == 0
                              ? null
                              : () => _moveSource(index, -1, focus),
                          icon: Icons.arrow_upward,
                        ),
                        lineupArrowButton(
                          focusNode: focus.order[strategy]!.later,
                          tooltip: 'Move later',
                          onPressed: index == _sourceOrder.length - 1
                              ? null
                              : () => _moveSource(index, 1, focus),
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

  void _moveSource(int index, int delta, SetupConfigureFocus focus) {
    final strategy = _sourceOrder[index];
    final target = index + delta;
    setState(() {
      _sourceOrder.removeAt(index);
      _sourceOrder.insert(target, strategy);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nodes = focus.order[strategy]!;
      final earlier =
          target == _sourceOrder.length - 1 || (target > 0 && delta < 0);
      (earlier ? nodes.earlier : nodes.later).requestFocus();
    });
  }

  void _prepareReview() {
    final base = List<Channel>.of(widget.controller.channels);
    setState(() {
      _phase = Reviewing(
        _allocateReview(base, mode: _mode, anchor: DateTime.now().toUtc()),
        confirmed: false,
      );
      _error = null;
      _notice = null;
      _step = _SetupStep.review;
    });
  }

  Widget _reviewStep() {
    final review = _review;
    if (review == null) return const SizedBox.shrink();
    final phase = _phase;
    return SetupReviewStep(
      review: review,
      notice: _notice,
      removalConfirmed: phase is Reviewing && phase.confirmed,
      sourceOrder: List.unmodifiable(_sourceOrder),
      sourceLabel: _reviewSourceLabel,
      initialFilter: _reviewFilter,
      initialSearch: _reviewSearch,
      onFilterChanged: (filter) => setState(() => _reviewFilter = filter),
      onSearchChanged: (search) => setState(() => _reviewSearch = search),
      isGeneratedSourceConfirmedGone:
          widget.controller.isGeneratedSourceConfirmedGone,
      onBack: () => setState(() => _step = _SetupStep.configure),
      onModeChanged: _changeReviewMode,
      onRemovalChanged: _changeReviewRemoval,
      onRemovalConfirmationChanged: (confirmed) => setState(() {
        final current = _review;
        if (current != null) {
          _phase = Reviewing(current, confirmed: confirmed);
        }
      }),
      onApply: _applyReview,
      onViewLineup: _viewLineup,
    );
  }

  void _changeReviewMode(ChannelBuildMode mode) {
    final current = _review;
    if (current == null || current.mode == mode) return;
    setState(() {
      _mode = mode;
      _phase = Reviewing(
        current.withMode(mode, DateTime.now().toUtc()),
        confirmed: false,
      );
      _notice = 'Updating review…';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _notice = null);
    });
  }

  void _changeReviewRemoval(String id, bool remove) {
    final current = _review;
    if (current == null) return;
    setState(() {
      _phase = Reviewing(current.withRemoval(id, remove), confirmed: false);
    });
  }

  String _reviewSourceLabel(ContentSource source) => switch (source) {
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

  Future<void> _applyReview() async {
    final review = _review;
    if (review == null) return;
    setState(() {
      _phase = Applying(review);
      _error = null;
      _step = _SetupStep.result;
    });
    try {
      final result = await widget.controller.applyReviewedChannelPlan(
        review.plan.channels,
        mode: review.mode,
        expectedBase: review.base,
        removeChannelIds: review.removeSourceIds,
      );
      if (!mounted) return;
      if (result == ChannelPlanApplyResult.stale) {
        final base = List<Channel>.of(widget.controller.channels);
        setState(() {
          _phase = Reviewing(
            _allocateReview(
              base,
              mode: review.mode,
              anchor: DateTime.now().toUtc(),
            ),
            confirmed: false,
          );
          _notice = 'Your lineup changed. Review the updated changes before applying.';
          _step = _SetupStep.review;
        });
        return;
      }
      setState(() => _phase = Completed(review));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = Failed(
          review,
          safeFormError(error, 'The lineup could not be saved.'),
        );
      });
    }
  }

  Widget _resultStep() {
    final phase = _phase;
    if (phase == null) return const SizedBox.shrink();
    return SetupResultStep(
      phase: phase,
      totalChannels: widget.controller.channels.length,
      onBackToReview: () => setState(() {
        _step = _SetupStep.review;
        _phase = Reviewing(phase.review, confirmed: false);
      }),
      onViewLineup: _viewLineup,
      onAddCustom: _addCustom,
    );
  }

  void _viewLineup() =>
      (widget.onViewLineup ?? widget.controller.completeChannelSetup)();
  void _addCustom() =>
      (widget.onAddCustomChannel ?? widget.controller.completeChannelSetup)();

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
}
