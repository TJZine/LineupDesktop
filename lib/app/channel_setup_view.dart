import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channels/channel.dart';
import '../channels/channel_builder.dart';
import '../ui/app_theme.dart';
import '../ui/app_ui.dart';
import 'channel_setup_projection.dart';
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
  State<UpstreamChannelSetupView> createState() =>
      UpstreamChannelSetupViewState();
}

class UpstreamChannelSetupViewState extends State<UpstreamChannelSetupView> {
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
  bool _androidTv = false;
  bool _committingLibraries = false;
  int _libraryCommitRevision = 0;
  bool _completionActionStarted = false;
  final _libraryEntryFocus = FocusNode(debugLabel: 'Setup libraries entry');
  bool _libraryFocusCallbackScheduled = false;
  bool _libraryFocusClearScheduled = false;
  bool _libraryEntryWasEnabled = false;

  SetupReview? get _review => _phase?.review;

  bool get _firstSetup => _review?.base.isEmpty ?? true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _androidTv = LineupTheme.of(context).androidTv;
  }

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
    _libraryEntryFocus.dispose();
    super.dispose();
  }

  bool get _libraryEntryFocusIsEligible {
    if (!mounted || _step != _SetupStep.libraries) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    if (!_libraryEntryFocus.canRequestFocus ||
        _libraryEntryFocus.context?.mounted != true) {
      return false;
    }
    if (_libraryEntryFocus.enclosingScope?.canRequestFocus == false) {
      return false;
    }
    if (context.findAncestorWidgetOfExactType<Offstage>()?.offstage == true) {
      return false;
    }
    if (context.findAncestorWidgetOfExactType<ExcludeFocus>()?.excluding ==
        true) {
      return false;
    }
    return true;
  }

  void _scheduleLibraryEntryFocus() {
    if (!_androidTv ||
        _step != _SetupStep.libraries ||
        _libraryFocusCallbackScheduled) {
      return;
    }
    _libraryFocusCallbackScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _libraryFocusCallbackScheduled = false;
      restoreNavigationFocus();
    });
  }

  /// Restores the existing Libraries entry after a retained navigation return.
  /// The shell calls this only once its subtree is visible again.
  void restoreNavigationFocus() {
    if (_libraryEntryTargetIsEnabled && _libraryEntryFocusIsEligible) {
      _libraryEntryFocus.requestFocus();
    }
  }

  bool get _libraryEntryTargetIsEnabled {
    if (!mounted ||
        !_androidTv ||
        _committingLibraries ||
        _step != _SetupStep.libraries) {
      return false;
    }
    final controller = widget.controller;
    if (controller.libraryScanStatus == LibraryScanStatus.scanning) {
      return false;
    }
    if (controller.libraries.isEmpty) {
      return !controller.busy && controller.canSwitchServer;
    }
    return !controller.busy;
  }

  void _clearLibraryEntryFocusIfUnavailable() {
    if (_libraryEntryTargetIsEnabled ||
        !_libraryEntryFocus.hasFocus ||
        _libraryFocusClearScheduled) {
      return;
    }
    _libraryFocusClearScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _libraryFocusClearScheduled = false;
      if (mounted && !_libraryEntryTargetIsEnabled) {
        _libraryEntryFocus.unfocus(disposition: UnfocusDisposition.scope);
      }
    });
  }

  /// Claims one contextual Back press for the active setup owner.
  bool handleBack() {
    if (_step == _SetupStep.libraries) {
      if (_committingLibraries || !widget.controller.canSwitchServer) {
        return true;
      }
      if (widget.controller.libraryScanStatus == LibraryScanStatus.scanning) {
        widget.controller.cancelLibraryScan();
        return true;
      }
      if (widget.controller.channelSetupCanCancel) {
        widget.controller.cancelChannelSetup();
        return true;
      }
      return widget.controller.busy;
    }

    if (_step == _SetupStep.configure) {
      _backToLibraries();
      return true;
    }
    if (_step == _SetupStep.review) {
      _backToConfigure();
      return true;
    }

    final phase = _phase;
    if (phase is Applying || phase == null) return true;
    if (phase is Failed) {
      _backToReview(phase);
      return true;
    }
    if (phase is Completed) {
      _viewLineupFromBack();
      return true;
    }
    return true;
  }

  bool _editableTextOwnsBackspace() {
    final context = FocusManager.instance.primaryFocus?.context;
    return context?.widget is EditableText ||
        context?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _navigationKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace && _editableTextOwnsBackspace()) {
      return KeyEventResult.ignored;
    }
    if (!_androidTv ||
        ![
          LogicalKeyboardKey.escape,
          LogicalKeyboardKey.goBack,
          LogicalKeyboardKey.backspace,
        ].contains(key)) {
      return KeyEventResult.ignored;
    }
    return handleBack() ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  void _backToLibraries() {
    if (!mounted) return;
    setState(() => _step = _SetupStep.libraries);
    _scheduleLibraryEntryFocus();
  }

  void _backToConfigure() {
    if (!mounted) return;
    setState(() => _step = _SetupStep.configure);
  }

  void _backToReview(SetupPhase phase) {
    if (!mounted) return;
    setState(() {
      _step = _SetupStep.review;
      _phase = Reviewing(
        phase.review,
        confirmed: phase is Failed && phase.confirmed,
      );
    });
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
    final entryEnabled = _libraryEntryTargetIsEnabled;
    if (entryEnabled && !_libraryEntryWasEnabled) {
      _scheduleLibraryEntryFocus();
    }
    _libraryEntryWasEnabled = entryEnabled;
    _clearLibraryEntryFocusIfUnavailable();
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
    return Focus(
      // Route descendant Back keys without becoming a directional focus target.
      canRequestFocus: false,
      onKeyEvent: _navigationKey,
      child: Scaffold(
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
    final visibleStep = _step == _SetupStep.result ? _SetupStep.review : _step;
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
            '${complete || index.index < visibleStep.index ? "✓" : index.index + 1} $label',
            style: LineupTypography.body.copyWith(
              color: complete || index == visibleStep
                  ? roles.primaryText
                  : roles.secondaryText,
              fontWeight: complete || index == visibleStep
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
    data: SetupLibraryData(
      libraries: widget.controller.libraries,
      libraryScanFacts: widget.controller.libraryScanFacts,
      libraryScanReadyIds: widget.controller.libraryScanReadyIds,
      libraryScanRetryIds: widget.controller.libraryScanRetryIds,
      libraryScanCommittableIds: widget.controller.libraryScanCommittableIds,
      unavailableCollectionLibraryIds:
          widget.controller.unavailableCollectionLibraryIds,
      failedPlaylistIds: widget.controller.failedPlaylistIds,
      libraryScanStatus: widget.controller.libraryScanStatus,
      playlistCatalogUnavailable: widget.controller.playlistCatalogUnavailable,
      busy: widget.controller.busy,
      canSwitchServer: widget.controller.canSwitchServer,
      channelSetupCanCancel: widget.controller.channelSetupCanCancel,
      error: widget.controller.error,
      collectionRecoveryByLibrary: Map.unmodifiable({
        for (final library in widget.controller.libraries)
          library.id: ?widget.controller.collectionScaleRecovery({library.id}),
      }),
      selectionCollectionRecovery: widget.controller.collectionScaleRecovery(
        _selectedLibraries,
      ),
      progress: LibraryScanProgress.fromController(widget.controller),
    ),
    onSwitchServer: widget.controller.showServers,
    onCancelSetup: widget.controller.cancelChannelSetup,
    onCancelScan: widget.controller.cancelLibraryScan,
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
    entryFocusNode: _libraryEntryFocus,
    onRequestLogout: widget.onRequestLogout,
  );

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
      if (advanceWhenReady &&
          ready.length == _selectedLibraries.length &&
          widget.controller.libraryScanStatus == LibraryScanStatus.complete &&
          widget.controller.error == null) {
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
    if (_committingLibraries) return;
    final revision = ++_libraryCommitRevision;
    _committingLibraries = true;
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
    } finally {
      if (mounted && revision == _libraryCommitRevision) {
        _committingLibraries = false;
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
      allocation: freezeSetupAllocation(allocation),
      section: _configurationSection,
      onSectionChanged: (section) =>
          setState(() => _configurationSection = section),
      onBack: _backToLibraries,
      onReview: _prepareReview,
      hasConfirmedMissingSources:
          _mode == ChannelBuildMode.merge &&
          allocation.unmatchedGenerated.any(
            widget.controller.isGeneratedSourceConfirmedGone,
          ),
      configuration: SetupConfiguration(
        strategies: _strategies,
        grouped: _grouped,
        sourceOrder: _sourceOrder,
        playback: _playback,
        blockSize: _blockSize,
        includeSpecials: _includeSpecials,
        extras: _extras,
        alternateCopies: _alternateCopies,
        variantMode: _variantMode,
        variantBlockSize: _variantBlockSize,
        maximum: _maximum,
        minimum: _minimum,
      ),
      selectedLibraryCount: _selectedLibraries.length,
      disabledEligibility: Map.unmodifiable({
        for (final strategy in BuilderStrategy.values)
          if (_configurationSection == 0 && !_strategies.contains(strategy))
            strategy: _projection.disabledEligibility(strategy),
      }),
      discoveryFailures: Map.unmodifiable({
        for (final strategy in BuilderStrategy.values)
          strategy: ?_discoveryFailure(strategy),
      }),
      collectionRecovery: widget.controller.collectionScaleRecovery(
        _selectedLibraries,
      ),
      retryingDiscovery: _discoveryRetry,
      busy: widget.controller.busy,
      notice: _notice,
      onSourceEnabledChanged: (strategy, enabled) => setState(() {
        enabled ? _strategies.add(strategy) : _strategies.remove(strategy);
      }),
      onGroupingChanged: (strategy, grouped) => setState(() {
        grouped ? _grouped.add(strategy) : _grouped.remove(strategy);
      }),
      onRetryDiscovery: _retryDiscovery,
      onPlaybackChanged: _setPlaybackMode,
      onExtrasChanged: (value) => setState(() {
        _extras = value;
        _clearIncludeSpecialsIfUnused();
      }),
      onVariantModeChanged: (value) => setState(() {
        _variantMode = value;
        _clearDuplicateVariant();
        _clearIncludeSpecialsIfUnused();
      }),
      onAlternateCopiesChanged: (value) =>
          setState(() => _alternateCopies = value),
      onIncludeSpecialsChanged: (value) =>
          setState(() => _includeSpecials = value),
      onBlockSizeChanged: (main, value) => setState(() {
        if (main) {
          _blockSize = value;
        } else {
          _variantBlockSize = value;
        }
        _clearDuplicateVariant();
      }),
      onMaximumChanged: (value) => setState(() => _maximum = value),
      onMinimumChanged: (value) => setState(() => _minimum = value),
      onSourceOrderChanged: (order) => setState(() {
        _sourceOrder
          ..clear()
          ..addAll(order);
      }),
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
      onBack: _backToConfigure,
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
    final phase = _phase;
    final confirmed = phase is Reviewing && phase.confirmed;
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
        _error = safeFormError(error, 'The lineup could not be saved.');
        _phase = Failed(review, _error!, confirmed: confirmed);
      });
    }
  }

  Widget _resultStep() {
    final phase = _phase;
    if (phase == null) return const SizedBox.shrink();
    return SetupResultStep(
      phase: phase,
      totalChannels: widget.controller.channels.length,
      onBackToReview: () => _backToReview(phase),
      onViewLineup: _viewLineup,
      onAddCustom: _addCustom,
    );
  }

  void _viewLineup() {
    (widget.onViewLineup ?? widget.controller.completeChannelSetup)();
  }

  void _viewLineupFromBack() {
    if (_completionActionStarted) return;
    _completionActionStarted = true;
    _viewLineup();
  }

  void _addCustom() =>
      (widget.onAddCustomChannel ?? widget.controller.completeChannelSetup)();
}
