import 'package:flutter/material.dart';

import '../channels/channel.dart';
import '../channels/channel_builder.dart';
import '../plex/plex_models.dart';
import '../ui/app_theme.dart';
import '../ui/app_ui.dart';
import 'form_error.dart';
import 'lineup_controller.dart';

enum _SetupCategory {
  contentSources,
  advancedSources,
  buildOptions,
  seriesOrdering,
  limits,
  guideOrder,
}

enum _BuildPhase { review, applying, failed, complete }

enum _ReviewKind { protected, added, updated, retained, removed }

enum _ReviewFilter { all, protected, changed, removed }

typedef _PlanImpact = ({
  int create,
  int update,
  int unchanged,
  int remove,
  int finalCount,
  int customKept,
});

class UpstreamChannelSetupView extends StatefulWidget {
  const UpstreamChannelSetupView({
    required this.controller,
    this.onViewLineup,
    this.onAddCustomChannel,
    super.key,
  });

  static const maxContentWidth = 1440.0;

  final LineupController controller;
  final VoidCallback? onViewLineup;
  final VoidCallback? onAddCustomChannel;

  @override
  State<UpstreamChannelSetupView> createState() =>
      _UpstreamChannelSetupViewState();
}

class _UpstreamChannelSetupViewState extends State<UpstreamChannelSetupView> {
  int _step = 1;
  final _selectedLibraries = <String>{};
  final _strategies = <BuilderStrategy>{...BuilderStrategy.values};
  final _crossLibraryStrategies = <BuilderStrategy>{};
  final _strategyOrder = <BuilderStrategy>[...BuilderStrategy.values];
  _SetupCategory _category = _SetupCategory.contentSources;
  ChannelBuildMode _mode = ChannelBuildMode.replace;
  PlaybackMode _seriesOrdering = PlaybackMode.shuffle;
  int _seriesBlockSize = 3;
  int _maximumChannels = 200;
  int _minimumItems = 5;
  bool _alternateLineups = false;
  int _alternateCopies = 1;
  PlaybackMode? _variantMode;
  int _variantBlockSize = 3;
  bool _replaceConfirmed = false;
  _BuildPhase _buildPhase = _BuildPhase.review;
  bool _libraryFocusPlaced = false;
  bool _strategyFocusPlaced = false;
  final _phaseActionFocus = FocusNode(debugLabel: 'Channel Setup phase action');
  final _reviewSearch = TextEditingController();
  _ReviewFilter _reviewFilter = _ReviewFilter.all;
  String? _error;
  ({List<Channel> channels, bool truncated})? _planned;
  _PlanImpact? _appliedImpact;

  @override
  void initState() {
    super.initState();
    _selectedLibraries.addAll(
      widget.controller.selectedLibraryIds.isEmpty
          ? widget.controller.libraries.map((library) => library.id)
          : widget.controller.selectedLibraryIds,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _libraryFocusPlaced = true;
    });
  }

  @override
  void dispose() {
    _phaseActionFocus.dispose();
    _reviewSearch.dispose();
    super.dispose();
  }

  List<PlexLibrary> get _libraries => widget.controller.libraries
      .where((library) => _selectedLibraries.contains(library.id))
      .toList();

  ({List<ChannelProposal> proposals, int itemCount}) get _proposalSnapshot {
    final inventory = widget.controller.playableInventory;
    return (
      proposals: buildChannelProposals(
        libraries: _libraries,
        items: inventory.media,
        playlists: inventory.playlists,
        strategies: _strategies,
        strategyOrder: _strategyOrder,
        crossLibraryStrategies: _crossLibraryStrategies,
        minimumItems: _minimumItems,
        maximumChannels: _maximumChannels + 1,
      ),
      itemCount: inventory.byId.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 900 || size.height < 700;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.65, -0.75),
            radius: 1.35,
            colors: [
              LineupTheme.of(context).progressFill.withValues(alpha: 0.07),
              LineupTheme.of(context).deepBackground,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              key: const ValueKey('channel-setup-content'),
              constraints: const BoxConstraints(
                maxWidth: UpstreamChannelSetupView.maxContentWidth,
              ),
              child: Padding(
                padding: EdgeInsets.all(compact ? 16 : 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(),
                    const SizedBox(height: 18),
                    Expanded(
                      child: Material(
                        key: const ValueKey('channel-setup-shell'),
                        color: LineupTheme.of(context).primarySurface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            LineupTheme.of(context).panelRadius,
                          ),
                          side: BorderSide(
                            color: LineupTheme.of(context).defaultBorder,
                          ),
                        ),
                        child: Padding(
                          key: const ValueKey('channel-setup-stage'),
                          padding: EdgeInsets.all(compact ? 18 : 26),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_error != null &&
                                  _buildPhase != _BuildPhase.failed)
                                _errorBanner(),
                              if (_error != null &&
                                  _buildPhase != _BuildPhase.failed)
                                const SizedBox(height: 18),
                              Expanded(child: _body()),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => LayoutBuilder(
    key: const ValueKey('channel-setup-header'),
    builder: (context, constraints) {
      final title = Row(
        children: [
          Image.asset('assets/branding/lineup-logo-mark.png', height: 50),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Channel Setup',
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  'Build a clean, remote-first channel lineup for this server.',
                  style: TextStyle(
                    color: LineupTheme.of(context).secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
      if (LineupLayout.isCompactWidth(constraints.maxWidth)) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: _StepPill(step: _step),
            ),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: title),
          _StepPill(step: _step),
        ],
      );
    },
  );

  Widget _errorBanner() => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: LineupNotice(message: _error!),
  );

  Widget _body() => switch (_step) {
    1 => _libraryStep(),
    2 => _strategyStep(),
    _ => _reviewStep(),
  };

  Widget _libraryStep() => _SetupSurface(
    title: 'Select Plex libraries',
    subtitle: 'Lineup will scan the selected movie and show libraries for channel ideas.',
    footer: _SetupFooter(
      secondary: [
        if (widget.controller.libraryScanStatus == LibraryScanStatus.scanning)
          OutlinedButton.icon(
            onPressed: widget.controller.cancelLibraryScan,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Cancel scan'),
          ),
        if (widget.controller.channelSetupCanCancel)
          OutlinedButton(
            onPressed: widget.controller.cancelChannelSetup,
            child: const Text('Cancel'),
          ),
        if (widget.controller.libraries.isEmpty &&
            !widget.controller.channelSetupCanCancel)
          OutlinedButton.icon(
            onPressed: widget.controller.busy
                ? null
                : widget.controller.showServers,
            icon: const Icon(Icons.dns_outlined),
            label: const Text('Choose another server'),
          ),
        OutlinedButton(
          onPressed: () => setState(
            () => _selectedLibraries.addAll(
              widget.controller.libraries.map((library) => library.id),
            ),
          ),
          child: const Text('Select All'),
        ),
        OutlinedButton(
          onPressed: () => setState(_selectedLibraries.clear),
          child: const Text('Clear All'),
        ),
      ],
      primary: FilledButton.icon(
        onPressed: _selectedLibraries.isEmpty || widget.controller.busy
            ? null
            : _continueFromLibraries,
        icon: const Icon(Icons.arrow_forward),
        label: const Text('Configure channels'),
      ),
    ),
    child: widget.controller.libraries.isEmpty
        ? const SingleChildScrollView(
            child: LineupEmptyState(
              icon: Icons.video_library_outlined,
              title: 'No movie or show libraries found',
              message: 'Choose another Plex server with accessible movie or show libraries.',
            ),
          )
        : LayoutBuilder(
            builder: (context, constraints) => CustomScrollView(
              slivers: [
                if (widget.controller.libraryScanStatus !=
                    LibraryScanStatus.idle)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _scanStatus(),
                    ),
                  ),
                SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: constraints.maxWidth >= 680 ? 2 : 1,
                    mainAxisExtent: 132,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  delegate: SliverChildBuilderDelegate((_, index) {
                    final library = widget.controller.libraries[index];
                    final selected = _selectedLibraries.contains(library.id);
                    final scanFact =
                        widget.controller.libraryScanFacts[library.id];
                    return LineupSelectionCard(
                      selected: selected,
                      autofocus: index == 0 && !_libraryFocusPlaced,
                      onPressed: () => setState(
                        () => selected
                            ? _selectedLibraries.remove(library.id)
                            : _selectedLibraries.add(library.id),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Icon(
                              library.type == PlexLibraryType.show
                                  ? Icons.tv
                                  : Icons.movie_outlined,
                              size: 38,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    library.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    library.type == PlexLibraryType.show
                                        ? 'TV Shows'
                                        : 'Movies',
                                    style: TextStyle(
                                      color: LineupTheme.of(context).mutedText,
                                    ),
                                  ),
                                  Text(
                                    _libraryScanStatusLabel(scanFact),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: LineupTheme.of(context).mutedText,
                                    ),
                                  ),
                                  if (scanFact != null &&
                                      scanFact.status != LibraryScanStatus.idle)
                                    Text(
                                      _libraryScanProgressLabel(scanFact),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: LineupTheme.of(context)
                                            .mutedText,
                                        fontSize: 13,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Icon(
                              selected
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              color: selected
                                  ? LineupTheme.of(context).progressFill
                                  : LineupTheme.of(context).mutedText,
                            ),
                          ],
                        ),
                      ),
                    );
                  }, childCount: widget.controller.libraries.length),
                ),
              ],
            ),
          ),
  );

  String _libraryScanStatusLabel(LibraryScanFact? fact) {
    if (fact == null) return 'Count available after scan';
    return switch (fact.status) {
      LibraryScanStatus.idle => 'Not scanned',
      LibraryScanStatus.scanning => 'Scanning',
      LibraryScanStatus.complete => 'Complete',
      LibraryScanStatus.empty => 'Empty',
      LibraryScanStatus.unsupported => 'Unsupported',
      LibraryScanStatus.transientFailure => 'Scan failed',
      LibraryScanStatus.cancelled => 'Cancelled',
    };
  }

  String _libraryScanProgressLabel(LibraryScanFact fact) => [
    fact.totalItems == null
        ? '${fact.completedItems} ${fact.completedItems == 1 ? 'item' : 'items'}'
        : '${fact.completedItems}/${fact.totalItems} ${fact.totalItems == 1 ? 'item' : 'items'}',
    '${fact.completedPages} ${fact.completedPages == 1 ? 'page' : 'pages'}',
  ].join(' · ');

  Widget _scanStatus() {
    final controller = widget.controller;
    final status = controller.libraryScanStatus;
    final (label, message) = switch (status) {
      LibraryScanStatus.scanning => (
        'Scanning selected libraries',
        'Pages scanned: ${controller.libraryScanCompletedPages} · Items scanned: ${controller.libraryScanCompletedItems}',
      ),
      LibraryScanStatus.complete => (
        'Library scan complete',
        'Pages scanned: ${controller.libraryScanCompletedPages} · Items scanned: ${controller.libraryScanCompletedItems}',
      ),
      LibraryScanStatus.empty => (
        'Selected libraries are empty',
        'Plex returned no media metadata for the selected libraries.',
      ),
      LibraryScanStatus.unsupported => (
        'No playable media found',
        'Plex returned media, but none has a positive duration and usable media part.',
      ),
      LibraryScanStatus.transientFailure => (
        'Library scan failed',
        controller.error ?? 'Plex could not complete the library scan.',
      ),
      LibraryScanStatus.cancelled => (
        'Library scan cancelled',
        'Your previous library selection and media remain unchanged.',
      ),
      LibraryScanStatus.idle => ('', ''),
    };
    final total = controller.libraryScanTotalItems;
    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExcludeSemantics(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 4),
              Text(message),
              if (status == LibraryScanStatus.scanning) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: total != null && total > 0
                      ? (controller.libraryScanCompletedItems / total).clamp(
                          0.0,
                          1.0,
                        )
                      : null,
                ),
              ],
              if ({
                LibraryScanStatus.empty,
                LibraryScanStatus.unsupported,
                LibraryScanStatus.transientFailure,
                LibraryScanStatus.cancelled,
              }.contains(status))
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: controller.busy ? null : _continueFromLibraries,
                    child: const Text('Retry scan'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _continueFromLibraries() async {
    setState(() => _error = null);
    try {
      final loaded = await widget.controller.setLibraries(_selectedLibraries);
      if (!mounted) return;
      setState(() {
        if (loaded &&
            widget.controller.libraryScanStatus == LibraryScanStatus.complete) {
          _step = 2;
        } else if (!loaded &&
            widget.controller.libraryScanStatus !=
                LibraryScanStatus.cancelled) {
          _error = widget.controller.error ?? 'Library loading failed.';
        }
      });
      if (loaded &&
          widget.controller.libraryScanStatus == LibraryScanStatus.complete) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _strategyFocusPlaced = true;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = safeFormError(
            error,
            'Channel Setup could not complete that request.',
          ),
        );
      }
    }
  }

  Widget _strategyStep() => _strategyStepFor(_proposalSnapshot);

  Widget _strategyStepFor(
    ({List<ChannelProposal> proposals, int itemCount}) proposalSnapshot,
  ) => _SetupSurface(
    title: 'Configure the lineup',
    subtitle: 'Choose source families, ordering and limits. Estimates update from loaded Plex metadata.',
    footer: _SetupFooter(
      secondary: [
        OutlinedButton(
          onPressed: () => setState(() => _step = 1),
          child: const Text('Back'),
        ),
      ],
      primary: FilledButton.icon(
        onPressed: proposalSnapshot.proposals.isEmpty ? null : _prepareReview,
        icon: const Icon(Icons.preview_outlined),
        label: Text(
          widget.controller.channels.isEmpty ? 'Build Channels' : 'Review',
        ),
      ),
    ),
    child: LayoutBuilder(
      builder: (_, constraints) {
        final compact = LineupLayout.isCompactWidth(constraints.maxWidth);
        final rail = _categoryRail(compact);
        final details = _categoryDetails();
        if (compact) {
          return ListView(
            children: [
              rail,
              const SizedBox(height: 12),
              SizedBox(
                height: constraints.maxHeight.clamp(280, 520).toDouble(),
                child: details,
              ),
              const SizedBox(height: 12),
              _previewStrip(proposalSnapshot),
            ],
          );
        }
        return Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 280, child: rail),
                  const SizedBox(width: 18),
                  Expanded(child: details),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _previewStrip(proposalSnapshot),
          ],
        );
      },
    ),
  );

  Widget _categoryRail(bool compact) {
    final children = [
      for (final category in _SetupCategory.values)
        Padding(
          padding: EdgeInsets.only(right: compact ? 8 : 0, bottom: 8),
          child: _RailButton(
            label: _categoryLabel(category),
            selected: category == _category,
            autofocus: category == _category && !_strategyFocusPlaced,
            onPressed: () => setState(() => _category = category),
          ),
        ),
    ];
    return KeyedSubtree(
      key: const ValueKey('channel-setup-strategy-rail'),
      child: compact
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: children),
            )
          : ListView(children: children),
    );
  }

  Widget _categoryDetails() => Card(
    key: const ValueKey('channel-setup-strategy-details'),
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: ListView(children: _detailControls()),
    ),
  );

  List<Widget> _detailControls() => switch (_category) {
    _SetupCategory.contentSources => [
      _sectionTitle('Content Sources', 'Core library-driven channel families.'),
      _strategyToggle(BuilderStrategy.playlists),
      _strategyToggle(BuilderStrategy.collections),
      _strategyToggle(BuilderStrategy.recentlyAdded),
      _strategyToggle(BuilderStrategy.genres, allowCrossLibrary: true),
      _strategyToggle(BuilderStrategy.decades),
    ],
    _SetupCategory.advancedSources => [
      _sectionTitle(
        'Advanced Sources',
        'People and studio channels from Plex metadata.',
      ),
      _strategyToggle(BuilderStrategy.studios, allowCrossLibrary: true),
      _strategyToggle(BuilderStrategy.actors, allowCrossLibrary: true),
      _strategyToggle(BuilderStrategy.directors, allowCrossLibrary: true),
    ],
    _SetupCategory.buildOptions => [
      _sectionTitle(
        'Build Options',
        'Choose how this plan changes the lineup.',
      ),
      RadioGroup<ChannelBuildMode>(
        groupValue: _mode,
        onChanged: (value) => setState(() => _mode = value!),
        child: Column(
          children: [
            for (final mode in ChannelBuildMode.values)
              RadioListTile<ChannelBuildMode>(
                value: mode,
                title: Text(_modeLabel(mode)),
                subtitle: Text(_modeDescription(mode)),
              ),
          ],
        ),
      ),
    ],
    _SetupCategory.seriesOrdering => [
      _sectionTitle(
        'Series Ordering',
        'Base playback order for generated channels.',
      ),
      SegmentedButton<PlaybackMode>(
        segments: const [
          ButtonSegment(value: PlaybackMode.shuffle, label: Text('Shuffle')),
          ButtonSegment(
            value: PlaybackMode.sequential,
            label: Text('Sequential'),
          ),
          ButtonSegment(value: PlaybackMode.block, label: Text('Blocks')),
        ],
        selected: {_seriesOrdering},
        onSelectionChanged: (value) =>
            setState(() => _seriesOrdering = value.single),
      ),
      if (_seriesOrdering == PlaybackMode.block) ...[
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          initialValue: _seriesBlockSize,
          decoration: const InputDecoration(labelText: 'Episodes per block'),
          items: const [2, 3, 4, 5]
              .map(
                (value) =>
                    DropdownMenuItem(value: value, child: Text('$value')),
              )
              .toList(),
          onChanged: (value) => setState(() => _seriesBlockSize = value!),
        ),
      ],
      const SizedBox(height: 18),
      SwitchListTile(
        value: _alternateLineups,
        onChanged: (value) => setState(() => _alternateLineups = value),
        title: Text('Alternate lineups and variants'),
        subtitle: const Text(
          'Create deterministic alternatives for series channels.',
        ),
      ),
      if (_alternateLineups) ...[
        DropdownButtonFormField<int>(
          initialValue: _alternateCopies,
          decoration: const InputDecoration(labelText: 'Alternate copies'),
          items: const [1, 2, 3]
              .map(
                (value) =>
                    DropdownMenuItem(value: value, child: Text('$value')),
              )
              .toList(),
          onChanged: (value) => setState(() => _alternateCopies = value!),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<PlaybackMode?>(
          initialValue: _variantMode,
          decoration: const InputDecoration(labelText: 'Additional variant'),
          items: const [
            DropdownMenuItem(value: null, child: Text('None')),
            DropdownMenuItem(
              value: PlaybackMode.shuffle,
              child: Text('Shuffle'),
            ),
            DropdownMenuItem(
              value: PlaybackMode.sequential,
              child: Text('Sequential'),
            ),
            DropdownMenuItem(value: PlaybackMode.block, child: Text('Blocks')),
          ],
          onChanged: (value) => setState(() => _variantMode = value),
        ),
        if (_variantMode == PlaybackMode.block) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _variantBlockSize,
            decoration: const InputDecoration(labelText: 'Variant block size'),
            items: const [2, 3, 4, 5]
                .map(
                  (value) =>
                      DropdownMenuItem(value: value, child: Text('$value')),
                )
                .toList(),
            onChanged: (value) => setState(() => _variantBlockSize = value!),
          ),
        ],
      ],
    ],
    _SetupCategory.limits => [
      _sectionTitle(
        'Limits',
        'Bound the lineup while keeping large channel collections practical.',
      ),
      DropdownButtonFormField<int>(
        initialValue: _maximumChannels,
        decoration: const InputDecoration(labelText: 'Maximum channels'),
        items: const [50, 100, 200, 300, 500, 750, 1000]
            .map(
              (value) => DropdownMenuItem(value: value, child: Text('$value')),
            )
            .toList(),
        onChanged: (value) => setState(() => _maximumChannels = value!),
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<int>(
        initialValue: _minimumItems,
        decoration: const InputDecoration(
          labelText: 'Minimum programs per channel',
        ),
        items: const [1, 5, 10, 20, 50]
            .map(
              (value) => DropdownMenuItem(value: value, child: Text('$value')),
            )
            .toList(),
        onChanged: (value) => setState(() => _minimumItems = value!),
      ),
    ],
    _SetupCategory.guideOrder => [
      _sectionTitle(
        'Guide Order',
        'Enabled source families are evaluated in this deterministic order.',
      ),
      for (var index = 0; index < _strategyOrder.length; index++)
        ListTile(
          leading: CircleAvatar(child: Text('${index + 1}')),
          title: Text(builderStrategyLabels[_strategyOrder[index]]!),
          trailing: _strategies.contains(_strategyOrder[index])
              ? Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Move earlier',
                      onPressed: index == 0
                          ? null
                          : () => _moveStrategy(index, -1),
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    IconButton(
                      tooltip: 'Move later',
                      onPressed: index == _strategyOrder.length - 1
                          ? null
                          : () => _moveStrategy(index, 1),
                      icon: const Icon(Icons.arrow_downward),
                    ),
                  ],
                )
              : const Text('Off'),
        ),
    ],
  };

  Widget _sectionTitle(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(color: LineupTheme.of(context).mutedText),
        ),
      ],
    ),
  );

  Widget _strategyToggle(
    BuilderStrategy strategy, {
    bool allowCrossLibrary = false,
  }) => Column(
    children: [
      SwitchListTile(
        value: _strategies.contains(strategy),
        title: Text(builderStrategyLabels[strategy]!),
        subtitle: Text(
          allowCrossLibrary && _crossLibraryStrategies.contains(strategy)
              ? 'Combined across selected libraries'
              : 'Per-library channels',
        ),
        onChanged: (enabled) => setState(
          () => enabled
              ? _strategies.add(strategy)
              : _strategies.remove(strategy),
        ),
      ),
      if (allowCrossLibrary && _strategies.contains(strategy))
        Padding(
          padding: const EdgeInsets.only(left: 56),
          child: SwitchListTile(
            dense: true,
            value: _crossLibraryStrategies.contains(strategy),
            title: const Text('Combine matching tags across libraries'),
            onChanged: (enabled) => setState(
              () => enabled
                  ? _crossLibraryStrategies.add(strategy)
                  : _crossLibraryStrategies.remove(strategy),
            ),
          ),
        ),
    ],
  );

  void _moveStrategy(int index, int delta) => setState(() {
    final strategy = _strategyOrder.removeAt(index);
    _strategyOrder.insert(index + delta, strategy);
  });

  Widget _previewStrip(
    ({List<ChannelProposal> proposals, int itemCount}) proposalSnapshot,
  ) {
    final proposals = proposalSnapshot.proposals;
    final displayed = proposals.take(_maximumChannels).toList();
    final summary = displayed.isEmpty
        ? 'No channel ideas meet the current minimum. Adjust sources or limits.'
        : '${displayed.length} channel ideas from ${proposalSnapshot.itemCount} playable programs.';
    final statuses = [
      for (final strategy in _strategyOrder)
        '${builderStrategyLabels[strategy]}: ${_strategyStatus(strategy, displayed)}',
    ];
    return Semantics(
      container: true,
      liveRegion: true,
      label:
          '$summary ${statuses.join('. ')}${proposals.length > _maximumChannels ? '. More ideas omitted' : ''}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: LineupTheme.of(context).selectedSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: LineupTheme.of(context).defaultBorder),
          ),
          child: Row(
            children: [
              Icon(
                Icons.auto_awesome,
                color: LineupTheme.of(context).progressFill,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Text(summary),
                      const SizedBox(width: 12),
                      for (final status in statuses)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(status),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (proposals.length > _maximumChannels)
                const Chip(label: Text('More ideas omitted')),
            ],
          ),
        ),
      ),
    );
  }

  String _strategyStatus(
    BuilderStrategy strategy,
    List<ChannelProposal> proposals,
  ) {
    if (!_strategies.contains(strategy)) return 'Off';
    final count = proposals
        .where((proposal) => proposal.strategy == strategy)
        .length;
    return count == 0 ? 'No matches' : '$count';
  }

  Widget _reviewStep() {
    final result = _planned;
    final planned = result?.channels ?? const <Channel>[];
    final impact = _planImpact(planned);
    final phase = _buildPhase;
    return _SetupSurface(
      title: switch (phase) {
        _BuildPhase.review => 'Review expected changes',
        _BuildPhase.applying => 'Applying your lineup',
        _BuildPhase.failed => 'Lineup update failed',
        _BuildPhase.complete => 'Your lineup is ready',
      },
      subtitle: switch (phase) {
        _BuildPhase.review =>
          '${_modeLabel(_mode)} • ${_strategies.length} enabled source families',
        _BuildPhase.applying =>
          'Lineup is committing the accepted plan as one atomic update.',
        _BuildPhase.failed =>
          'The previous lineup is unchanged. Return to Review to try again.',
        _BuildPhase.complete => 'The accepted plan was saved. Continue when you are ready to review Channels.',
      },
      footer: switch (phase) {
        _BuildPhase.applying => const SizedBox.shrink(),
        _BuildPhase.failed => _SetupFooter(
          secondary: [
            OutlinedButton(
              focusNode: _phaseActionFocus,
              onPressed: () {
                setState(() {
                  _buildPhase = _BuildPhase.review;
                  _error = null;
                });
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _phaseActionFocus.requestFocus();
                });
              },
              child: const Text('Back to Review'),
            ),
          ],
          primary: const SizedBox.shrink(),
        ),
        _BuildPhase.complete => _SetupFooter(
          secondary: [
            OutlinedButton.icon(
              onPressed:
                  widget.onAddCustomChannel ??
                  widget.controller.completeChannelSetup,
              icon: const Icon(Icons.add),
              label: const Text('Add a custom channel'),
            ),
          ],
          primary: FilledButton.icon(
            focusNode: _phaseActionFocus,
            onPressed:
                widget.onViewLineup ?? widget.controller.completeChannelSetup,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('View lineup'),
          ),
        ),
        _BuildPhase.review => _SetupFooter(
          secondary: [
            OutlinedButton(
              focusNode: _phaseActionFocus,
              onPressed: () => setState(() => _step = 2),
              child: const Text('Back'),
            ),
          ],
          primary: FilledButton.icon(
            onPressed:
                planned.isEmpty ||
                    (_mode == ChannelBuildMode.replace && !_replaceConfirmed)
                ? null
                : () => _build(planned, impact),
            icon: const Icon(Icons.auto_awesome),
            label: Text(
              _mode == ChannelBuildMode.replace
                  ? 'Confirm & Replace'
                  : 'Confirm & Build',
            ),
          ),
        ),
      },
      child: phase == _BuildPhase.review
          ? _reviewRoster(
              planned,
              impact,
              truncated: result?.truncated ?? false,
            )
          : _BuildProgress(
              phase: phase,
              error: _error,
              impact: _appliedImpact ?? impact,
            ),
    );
  }

  Widget _reviewRoster(
    List<Channel> planned,
    _PlanImpact impact, {
    required bool truncated,
  }) {
    final allEntries = _reviewEntries(planned);
    final query = _reviewSearch.text.trim().toLowerCase();
    final entries = allEntries
        .where((entry) {
          final matchesQuery =
              query.isEmpty ||
              entry.channel.name.toLowerCase().contains(query) ||
              '${entry.channel.number}'.contains(query);
          final matchesFilter = switch (_reviewFilter) {
            _ReviewFilter.all => true,
            _ReviewFilter.protected => entry.kind == _ReviewKind.protected,
            _ReviewFilter.changed =>
              entry.kind == _ReviewKind.added ||
                  entry.kind == _ReviewKind.updated,
            _ReviewFilter.removed => entry.kind == _ReviewKind.removed,
          };
          return matchesQuery && matchesFilter;
        })
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: CustomScrollView(
            key: const Key('channel-setup-review-roster'),
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (truncated) ...[
                      const LineupNotice(
                        message: 'The channel limit or available channel numbers omitted some ideas.',
                      ),
                      const SizedBox(height: 12),
                    ],
                    _reviewSummary(impact),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) =>
                          _reviewSearchAndFilter(constraints),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${entries.length} of ${allEntries.length} review entries',
                      style: TextStyle(
                        color: LineupTheme.of(context).secondaryText,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
              if (entries.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text('No channels match this review.')),
                )
              else
                SliverList.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) => Column(
                    children: [_reviewRow(entries[index]), const Divider()],
                  ),
                ),
            ],
          ),
        ),
        if (_mode == ChannelBuildMode.replace) ...[
          const SizedBox(height: 10),
          Material(
            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.06),
            shape: RoundedRectangleBorder(
              side: BorderSide(
                color: Theme.of(context).colorScheme.error
                    .withValues(alpha: 0.35),
              ),
              borderRadius: BorderRadius.circular(
                LineupTheme.of(context).panelRadius,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: CheckboxListTile(
              key: const Key('channel-setup-replace-confirmation'),
              value: _replaceConfirmed,
              title: Text('Remove ${impact.remove} generated channels'),
              subtitle: Text(
                '${impact.customKept} custom ${impact.customKept == 1 ? 'channel is' : 'channels are'} protected and will remain unchanged.',
              ),
              onChanged: (value) =>
                  setState(() => _replaceConfirmed = value == true),
            ),
          ),
        ],
      ],
    );
  }

  Widget _reviewSearchAndFilter(BoxConstraints constraints) {
    final search = TextField(
      key: const Key('channel-setup-review-search'),
      controller: _reviewSearch,
      decoration: const InputDecoration(
        labelText: 'Search proposed lineup',
        prefixIcon: Icon(Icons.search),
      ),
      onChanged: (_) => setState(() {}),
    );
    final filter = DropdownButtonFormField<_ReviewFilter>(
      key: const Key('channel-setup-review-filter'),
      isExpanded: true,
      initialValue: _reviewFilter,
      decoration: const InputDecoration(labelText: 'Show'),
      items: const [
        DropdownMenuItem(
          value: _ReviewFilter.all,
          child: Text('Entire review'),
        ),
        DropdownMenuItem(
          value: _ReviewFilter.protected,
          child: Text('Protected custom'),
        ),
        DropdownMenuItem(
          value: _ReviewFilter.changed,
          child: Text('Added or updated'),
        ),
        DropdownMenuItem(value: _ReviewFilter.removed, child: Text('Removed')),
      ],
      onChanged: (value) => setState(() => _reviewFilter = value!),
    );
    if (constraints.maxWidth < 680 ||
        MediaQuery.textScalerOf(context).scale(14) > 21) {
      return Column(children: [search, const SizedBox(height: 8), filter]);
    }
    return Row(
      children: [
        Expanded(child: search),
        const SizedBox(width: 10),
        SizedBox(width: 210, child: filter),
      ],
    );
  }

  List<({Channel channel, _ReviewKind kind})> _reviewEntries(
    List<Channel> planned,
  ) {
    final existing = widget.controller.channels;
    final existingById = {for (final channel in existing) channel.id: channel};
    final plannedIds = planned.map((channel) => channel.id).toSet();
    final finalChannels = composeChannelPlan(
      existing: existing,
      planned: planned,
      mode: _mode,
    );
    final entries = <({Channel channel, _ReviewKind kind})>[
      for (final channel in finalChannels)
        (
          channel: channel,
          kind: channel.builderKey == null
              ? _ReviewKind.protected
              : plannedIds.contains(channel.id)
              ? existingById[channel.id] == null
                    ? _ReviewKind.added
                    : identical(existingById[channel.id], channel)
                    ? _ReviewKind.retained
                    : _ReviewKind.updated
              : _ReviewKind.retained,
        ),
      for (final channel in existing.where(
        (channel) => !finalChannels.any((next) => next.id == channel.id),
      ))
        (channel: channel, kind: _ReviewKind.removed),
    ];
    entries.sort((left, right) {
      final byNumber = left.channel.number.compareTo(right.channel.number);
      return byNumber != 0
          ? byNumber
          : left.kind.index.compareTo(right.kind.index);
    });
    return entries;
  }

  Widget _reviewSummary(_PlanImpact impact) {
    final roles = LineupTheme.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label:
          'Channel composition. Create: ${impact.create}, Update: ${impact.update}, Unchanged: ${impact.unchanged}, Generated removed: ${impact.remove}.',
      child: Container(
        key: const ValueKey('channel-setup-impact-hero'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: roles.selectedSurface.withValues(alpha: 0.28),
          border: Border.all(color: roles.defaultBorder),
          borderRadius: BorderRadius.circular(roles.panelRadius),
        ),
        child: Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              label: 'Final: ${impact.finalCount}',
              child: ExcludeSemantics(
                child: Text(
                  '${widget.controller.channels.length} CURRENT  ·  ${impact.finalCount} FINAL',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            _summaryFact('Create', impact.create, '${impact.create} added'),
            _summaryFact('Update', impact.update, '${impact.update} updated'),
            _summaryFact(
              'Unchanged',
              impact.unchanged,
              '${impact.unchanged} retained',
            ),
            _summaryFact(
              'Generated removed',
              impact.remove,
              '${impact.remove} removed',
            ),
            _summaryFact(
              'Custom kept',
              impact.customKept,
              '${impact.customKept} protected',
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryFact(String label, int value, String text) => Semantics(
    label: '$label: $value',
    child: ExcludeSemantics(child: Text(text)),
  );

  Widget _reviewRow(({Channel channel, _ReviewKind kind}) entry) {
    final roles = LineupTheme.of(context);
    final (label, icon, color) = switch (entry.kind) {
      _ReviewKind.protected => (
        'PROTECTED CUSTOM',
        Icons.lock_outline,
        roles.secondaryText,
      ),
      _ReviewKind.added => (
        'ADDED',
        Icons.add_circle_outline,
        roles.progressFill,
      ),
      _ReviewKind.updated => (
        'UPDATED',
        Icons.edit_outlined,
        roles.focusBorder,
      ),
      _ReviewKind.retained => (
        'RETAINED',
        Icons.check_circle_outline,
        roles.tunedSurface,
      ),
      _ReviewKind.removed => (
        'REMOVED',
        Icons.remove_circle_outline,
        Theme.of(context).colorScheme.error,
      ),
    };
    return Semantics(
      container: true,
      label:
          '$label, channel ${entry.channel.number}, ${entry.channel.name}, ${_reviewRhythm(entry.channel)}',
      child: ExcludeSemantics(
        child: ListTile(
          leading: Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: roles.elevatedSurface,
              border: Border.all(color: roles.subtleBorder),
              borderRadius: BorderRadius.circular(roles.panelRadius),
            ),
            child: Text(
              '${entry.channel.number}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          title: Text(
            entry.channel.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '$label · ${_reviewRhythm(entry.channel)}',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
          trailing: Icon(icon, color: color),
        ),
      ),
    );
  }

  void _prepareReview() {
    final proposalSnapshot = _proposalSnapshot;
    setState(() {
      _planned = materializeChannelPlan(
        proposals: proposalSnapshot.proposals,
        existing: widget.controller.channels,
        mode: _mode,
        seriesMode: _seriesOrdering,
        seriesBlockSize: _seriesBlockSize,
        alternateCopies: _alternateLineups ? _alternateCopies : 0,
        variantMode: _alternateLineups ? _variantMode : null,
        variantBlockSize: _variantBlockSize,
        maximumChannels: _maximumChannels,
        anchor: DateTime.now().toUtc(),
      );
      _step = 3;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _phaseActionFocus.requestFocus();
    });
  }

  _PlanImpact _planImpact(List<Channel> planned) {
    final existing = widget.controller.channels;
    final customCount = existing
        .where((channel) => channel.builderKey == null)
        .length;
    return switch (_mode) {
      ChannelBuildMode.replace => (
        create: planned.length,
        update: 0,
        unchanged: customCount,
        remove: existing.length - customCount,
        finalCount: customCount + planned.length,
        customKept: customCount,
      ),
      ChannelBuildMode.append => (
        create: planned.length,
        update: 0,
        unchanged: existing.length,
        remove: 0,
        finalCount: existing.length + planned.length,
        customKept: customCount,
      ),
      ChannelBuildMode.merge => () {
        var create = 0;
        var update = 0;
        var unchanged = 0;
        for (final candidate in planned) {
          final matched = existing
              .where(
                (channel) =>
                    candidate.builderKey != null &&
                    channel.builderKey == candidate.builderKey,
              )
              .firstOrNull;
          if (matched == null) {
            create++;
          } else if (identical(candidate, matched)) {
            unchanged++;
          } else {
            update++;
          }
        }
        unchanged += existing
            .where(
              (channel) => !planned.any(
                (candidate) =>
                    candidate.builderKey != null &&
                    candidate.builderKey == channel.builderKey,
              ),
            )
            .length;
        return (
          create: create,
          update: update,
          unchanged: unchanged,
          remove: 0,
          finalCount: existing.length + create,
          customKept: customCount,
        );
      }(),
    };
  }

  Future<void> _build(List<Channel> planned, _PlanImpact impact) async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _buildPhase = _BuildPhase.applying;
      _appliedImpact = impact;
      _error = null;
    });
    try {
      await widget.controller.applyChannelPlan(planned, mode: _mode);
      if (mounted) {
        setState(() => _buildPhase = _BuildPhase.complete);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _phaseActionFocus.requestFocus();
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _buildPhase = _BuildPhase.failed;
          _error = safeFormError(
            error,
            'The channel plan could not be applied.',
          );
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _phaseActionFocus.requestFocus();
        });
      }
    }
  }

  static String _categoryLabel(_SetupCategory category) => switch (category) {
    _SetupCategory.contentSources => 'Content Sources',
    _SetupCategory.advancedSources => 'Advanced Sources',
    _SetupCategory.buildOptions => 'Build Options',
    _SetupCategory.seriesOrdering => 'Series Ordering',
    _SetupCategory.limits => 'Limits',
    _SetupCategory.guideOrder => 'Guide Order',
  };

  static String _modeLabel(ChannelBuildMode mode) => switch (mode) {
    ChannelBuildMode.replace => 'Replace generated channels',
    ChannelBuildMode.append => 'Add generated channels',
    ChannelBuildMode.merge => 'Refresh generated channels',
  };

  static String _modeDescription(ChannelBuildMode mode) => switch (mode) {
    ChannelBuildMode.replace =>
      'Keep custom channels and replace only generated channels.',
    ChannelBuildMode.append =>
      'Keep all channels and add generated channels at free numbers.',
    ChannelBuildMode.merge =>
      'Refresh matching generated channels and keep all others.',
  };

  static String _reviewRhythm(Channel channel) =>
      switch (channel.playbackMode) {
        PlaybackMode.sequential => 'In order',
        PlaybackMode.shuffle => 'Mix it up',
        PlaybackMode.block => 'Mini-marathons of ${channel.blockSize ?? 3}',
      };
}

class _SetupSurface extends StatelessWidget {
  const _SetupSurface({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.footer,
  });
  final String title;
  final String subtitle;
  final Widget child;
  final Widget footer;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 5),
      Text(
        subtitle,
        style: TextStyle(color: LineupTheme.of(context).secondaryText),
      ),
      const SizedBox(height: 18),
      Expanded(child: child),
      const SizedBox(height: 14),
      footer,
    ],
  );
}

class _SetupFooter extends StatelessWidget {
  const _SetupFooter({required this.secondary, required this.primary});
  final List<Widget> secondary;
  final Widget primary;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: LineupTheme.of(context).subtleBorder),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.only(top: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final secondaryActions = Wrap(
            spacing: 10,
            runSpacing: 10,
            children: secondary,
          );
          if (LineupLayout.isCompactWidth(constraints.maxWidth)) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                secondaryActions,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: primary),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: secondaryActions),
              const SizedBox(width: 16),
              primary,
            ],
          );
        },
      ),
    ),
  );
}

class _StepPill extends StatelessWidget {
  const _StepPill({required this.step});
  final int step;
  @override
  Widget build(BuildContext context) => Chip(
    avatar: const Icon(Icons.tune, size: 18),
    label: Text('Step $step of 3'),
  );
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.autofocus = false,
  });
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final bool autofocus;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 260,
    child: OutlinedButton(
      autofocus: autofocus,
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        backgroundColor: selected
            ? LineupTheme.of(context).selectedSurface
            : null,
        side: BorderSide(
          color: selected
              ? LineupTheme.of(context).focusBorder
              : LineupTheme.of(context).subtleBorder,
        ),
      ),
      onPressed: onPressed,
      child: Text(label),
    ),
  );
}

class _ImpactCount extends StatelessWidget {
  const _ImpactCount({
    required this.value,
    required this.label,
    this.emphasized = false,
  });

  final int value;
  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(
        '$value',
        style: Theme.of(context).textTheme.displaySmall?.copyWith(
          color: emphasized ? LineupTheme.of(context).progressFill : null,
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
          height: 1,
        ),
      ),
      const SizedBox(width: 8),
      Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Text(
          label,
          style: TextStyle(color: LineupTheme.of(context).secondaryText),
        ),
      ),
    ],
  );
}

class _ImpactCard extends StatelessWidget {
  const _ImpactCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '$label: $value',
    child: ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: LineupTheme.of(context).selectedSurface.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: LineupTheme.of(context).subtleBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: LineupTheme.of(context).secondaryText),
            const SizedBox(width: 7),
            Text(
              '$value',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(color: LineupTheme.of(context).secondaryText),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BuildProgress extends StatelessWidget {
  const _BuildProgress({
    required this.phase,
    required this.error,
    required this.impact,
  });

  final _BuildPhase phase;
  final String? error;
  final _PlanImpact impact;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: switch (phase) {
      _BuildPhase.applying => 'Applying channels',
      _BuildPhase.failed => 'Channel update failed',
      _BuildPhase.complete => 'Channel update complete',
      _BuildPhase.review => null,
    },
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    switch (phase) {
                      _BuildPhase.applying => Icons.auto_awesome,
                      _BuildPhase.failed => Icons.error_outline,
                      _BuildPhase.complete => Icons.check_circle_outline,
                      _BuildPhase.review => Icons.live_tv_outlined,
                    },
                    size: 42,
                    color: phase == _BuildPhase.failed
                        ? Theme.of(context).colorScheme.error
                        : LineupTheme.of(context).progressFill,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 420,
                    child: LinearProgressIndicator(
                      value: switch (phase) {
                        _BuildPhase.applying => null,
                        _BuildPhase.failed => 0,
                        _BuildPhase.complete => 1,
                        _BuildPhase.review => 0,
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    switch (phase) {
                      _BuildPhase.applying => 'Applying channels…',
                      _BuildPhase.failed => 'No changes were saved',
                      _BuildPhase.complete => 'Channel setup complete',
                      _BuildPhase.review => '',
                    },
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    switch (phase) {
                      _BuildPhase.applying => 'The lineup is being committed atomically. This step cannot be cancelled.',
                      _BuildPhase.failed =>
                        error ?? 'The channel plan could not be applied.',
                      _BuildPhase.complete =>
                        'The atomic lineup update completed successfully.',
                      _BuildPhase.review => '',
                    },
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: LineupTheme.of(context).secondaryText,
                    ),
                  ),
                  if (phase == _BuildPhase.complete) ...[
                    const SizedBox(height: 18),
                    Semantics(
                      container: true,
                      label: 'Final: ${impact.finalCount}',
                      child: ExcludeSemantics(
                        child: _ImpactCount(
                          value: impact.finalCount,
                          label: 'channels ready',
                          emphasized: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _ImpactCard(
                          label: 'Create',
                          value: impact.create,
                          icon: Icons.add_circle_outline,
                        ),
                        _ImpactCard(
                          label: 'Update',
                          value: impact.update,
                          icon: Icons.edit_outlined,
                        ),
                        _ImpactCard(
                          label: 'Unchanged',
                          value: impact.unchanged,
                          icon: Icons.check_circle_outline,
                        ),
                        _ImpactCard(
                          label: 'Generated removed',
                          value: impact.remove,
                          icon: Icons.remove_circle_outline,
                        ),
                        _ImpactCard(
                          label: 'Custom kept',
                          value: impact.customKept,
                          icon: Icons.lock_outline,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
