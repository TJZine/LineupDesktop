import 'package:flutter/material.dart';

import '../channels/channel.dart';
import '../channels/channel_builder.dart';
import '../plex/plex_models.dart';
import '../ui/app_theme.dart';
import 'lineup_controller.dart';

enum _SetupCategory {
  contentSources,
  advancedSources,
  buildOptions,
  seriesOrdering,
  limits,
  guideOrder,
}

class UpstreamChannelSetupView extends StatefulWidget {
  const UpstreamChannelSetupView({required this.controller, super.key});

  final LineupController controller;

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
  bool _building = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedLibraries.addAll(
      widget.controller.selectedLibraryIds.isEmpty
          ? widget.controller.libraries.map((library) => library.id)
          : widget.controller.selectedLibraryIds,
    );
  }

  List<PlexLibrary> get _libraries => widget.controller.libraries
      .where((library) => _selectedLibraries.contains(library.id))
      .toList();

  List<ChannelProposal> get _proposals => buildChannelProposals(
    libraries: _libraries,
    items: widget.controller.availableMedia,
    playlists: widget.controller.availablePlaylists,
    strategies: _strategies,
    strategyOrder: _strategyOrder,
    crossLibraryStrategies: _crossLibraryStrategies,
    minimumItems: _minimumItems,
    maximumChannels: _maximumChannels,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.65, -0.75),
          radius: 1.35,
          colors: [Color(0x1228C8A0), LineupTheme.obsidian],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(),
                  if (_error != null) _errorBanner(),
                  const SizedBox(height: 16),
                  Expanded(child: _body()),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _header() => Row(
    children: [
      Image.asset('assets/branding/lineup-logo-mark.png', height: 58),
      const SizedBox(width: 20),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Channel Setup',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const Text(
              'Build a clean, remote-first channel lineup for this server.',
              style: TextStyle(color: Colors.white60),
            ),
          ],
        ),
      ),
      _StepPill(step: _step),
    ],
  );

  Widget _errorBanner() => Semantics(
    liveRegion: true,
    child: Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(_error!),
    ),
  );

  Widget _body() => switch (_step) {
    1 => _libraryStep(),
    2 => _strategyStep(),
    _ => _reviewStep(),
  };

  Widget _libraryStep() => _SetupSurface(
    title: 'Select Plex libraries',
    subtitle: 'Lineup will scan the selected movie and show libraries for channel ideas.',
    footer: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Wrap(
          spacing: 10,
          children: [
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
        ),
        FilledButton.icon(
          onPressed: _selectedLibraries.isEmpty || widget.controller.busy
              ? null
              : _continueFromLibraries,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Configure channels'),
        ),
      ],
    ),
    child: GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 340,
        mainAxisExtent: 120,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: widget.controller.libraries.length,
      itemBuilder: (_, index) {
        final library = widget.controller.libraries[index];
        final selected = _selectedLibraries.contains(library.id);
        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: selected ? LineupTheme.brass : Colors.white12,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            autofocus: index == 0,
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(
              () => selected
                  ? _selectedLibraries.remove(library.id)
                  : _selectedLibraries.add(library.id),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
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
                          style: const TextStyle(color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    selected ? Icons.check_circle : Icons.circle_outlined,
                    color: selected ? LineupTheme.brass : Colors.white30,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  Future<void> _continueFromLibraries() async {
    setState(() => _error = null);
    try {
      await widget.controller.setLibraries(_selectedLibraries);
      if (mounted) setState(() => _step = 2);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    }
  }

  Widget _strategyStep() => _SetupSurface(
    title: 'Configure the lineup',
    subtitle: 'Choose source families, ordering and limits. Estimates update from loaded Plex metadata.',
    footer: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        OutlinedButton(
          onPressed: () => setState(() => _step = 1),
          child: const Text('Back'),
        ),
        FilledButton.icon(
          onPressed: _proposals.isEmpty
              ? null
              : () => setState(() => _step = 3),
          icon: const Icon(Icons.preview_outlined),
          label: Text(
            widget.controller.channels.isEmpty ? 'Build Channels' : 'Review',
          ),
        ),
      ],
    ),
    child: LayoutBuilder(
      builder: (_, constraints) {
        final compact = constraints.maxWidth < 900;
        final rail = _categoryRail(compact);
        final details = _categoryDetails();
        return Column(
          children: [
            Expanded(
              child: compact
                  ? Column(
                      children: [
                        rail,
                        const SizedBox(height: 12),
                        Expanded(child: details),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 280, child: rail),
                        const SizedBox(width: 18),
                        Expanded(child: details),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            _previewStrip(),
          ],
        );
      },
    ),
  );

  Widget _categoryRail(bool compact) {
    final children = [
      for (final category in _SetupCategory.values)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _RailButton(
            label: _categoryLabel(category),
            selected: category == _category,
            autofocus: category == _SetupCategory.contentSources,
            onPressed: () => setState(() => _category = category),
          ),
        ),
    ];
    return compact
        ? Wrap(spacing: 8, runSpacing: 8, children: children)
        : ListView(children: children);
  }

  Widget _categoryDetails() => Card(
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
        Text(subtitle, style: const TextStyle(color: Colors.white54)),
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

  Widget _previewStrip() {
    final proposals = _proposals;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: LineupTheme.brass.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: LineupTheme.brass.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, color: LineupTheme.brass),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                proposals.isEmpty
                    ? 'No channel ideas meet the current minimum. Adjust sources or limits.'
                    : '${proposals.length} channels estimated from ${widget.controller.availableMedia.length} loaded programs.',
              ),
            ),
            if (proposals.length >= _maximumChannels)
              const Chip(label: Text('Limit reached')),
          ],
        ),
      ),
    );
  }

  Widget _reviewStep() {
    final planned = materializeChannelPlan(
      proposals: _proposals,
      existing: widget.controller.channels,
      mode: _mode,
      seriesMode: _seriesOrdering,
      seriesBlockSize: _seriesBlockSize,
      alternateCopies: _alternateLineups ? _alternateCopies : 0,
      variantMode: _alternateLineups ? _variantMode : null,
      variantBlockSize: _variantBlockSize,
    );
    final removed = _mode == ChannelBuildMode.replace
        ? widget.controller.channels.length
        : 0;
    return _SetupSurface(
      title: _building ? 'Building your lineup' : 'Review expected changes',
      subtitle: _building
          ? 'Lineup is applying channels and preparing the Guide.'
          : '${_modeLabel(_mode)} • ${_strategies.length} enabled source families',
      footer: _building
          ? const SizedBox.shrink()
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton(
                  onPressed: () => setState(() => _step = 2),
                  child: const Text('Back'),
                ),
                FilledButton.icon(
                  onPressed:
                      planned.isEmpty ||
                          (_mode == ChannelBuildMode.replace &&
                              !_replaceConfirmed)
                      ? null
                      : () => _build(planned),
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(
                    _mode == ChannelBuildMode.replace
                        ? 'Confirm & Replace'
                        : 'Confirm & Build',
                  ),
                ),
              ],
            ),
      child: _building
          ? const _BuildProgress()
          : ListView(
              children: [
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    _ImpactCard(
                      label: 'Create or update',
                      value: planned.length,
                      icon: Icons.add_circle_outline,
                    ),
                    _ImpactCard(
                      label: 'Remove',
                      value: removed,
                      icon: Icons.remove_circle_outline,
                    ),
                    _ImpactCard(
                      label: 'Final lineup',
                      value: switch (_mode) {
                        ChannelBuildMode.replace => planned.length,
                        ChannelBuildMode.append =>
                          widget.controller.channels.length + planned.length,
                        ChannelBuildMode.merge =>
                          widget.controller.channels.length +
                              planned
                                  .where(
                                    (candidate) =>
                                        !widget.controller.channels.any(
                                          (existing) =>
                                              existing.name == candidate.name,
                                        ),
                                  )
                                  .length,
                      },
                      icon: Icons.live_tv_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                if (_mode == ChannelBuildMode.replace)
                  CheckboxListTile(
                    value: _replaceConfirmed,
                    title: const Text('This will replace your current lineup'),
                    subtitle: const Text(
                      'Existing channels are removed only after this confirmation.',
                    ),
                    onChanged: (value) =>
                        setState(() => _replaceConfirmed = value == true),
                  ),
                const SizedBox(height: 14),
                Text(
                  'Sample channels',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                for (final channel in planned.take(12))
                  ListTile(
                    leading: CircleAvatar(child: Text('${channel.number}')),
                    title: Text(channel.name),
                    subtitle: Text(channel.playbackMode.name),
                  ),
              ],
            ),
    );
  }

  Future<void> _build(List<Channel> planned) async {
    setState(() {
      _building = true;
      _error = null;
    });
    try {
      await widget.controller.applyChannelPlan(planned, mode: _mode);
    } catch (error) {
      if (mounted) {
        setState(() {
          _building = false;
          _error = _message(error);
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
    ChannelBuildMode.replace => 'Replace lineup',
    ChannelBuildMode.append => 'Append channels',
    ChannelBuildMode.merge => 'Merge with lineup',
  };

  static String _modeDescription(ChannelBuildMode mode) => switch (mode) {
    ChannelBuildMode.replace => 'Build only the newly planned channels.',
    ChannelBuildMode.append => 'Keep existing channels and use free numbers.',
    ChannelBuildMode.merge =>
      'Update matching generated channels and keep the rest.',
  };

  static String _message(Object error) =>
      error.toString().replaceFirst('FormatException: ', '');
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(26),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.035),
      borderRadius: BorderRadius.circular(16),
      border: Border(
        bottom: BorderSide(color: LineupTheme.brass.withValues(alpha: 0.12)),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 5),
        Text(subtitle, style: const TextStyle(color: Colors.white60)),
        const SizedBox(height: 20),
        Expanded(child: child),
        const SizedBox(height: 18),
        footer,
      ],
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
            ? LineupTheme.brass.withValues(alpha: 0.15)
            : null,
        side: BorderSide(color: selected ? LineupTheme.brass : Colors.white12),
      ),
      onPressed: onPressed,
      child: Text(label),
    ),
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
  Widget build(BuildContext context) => SizedBox(
    width: 240,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, size: 32),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(label, style: const TextStyle(color: Colors.white60)),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _BuildProgress extends StatelessWidget {
  const _BuildProgress();
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(),
            SizedBox(height: 24),
            Text(
              'Applying channels…',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text(
              'The lineup is committed atomically. The Guide will open when it is ready.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}
