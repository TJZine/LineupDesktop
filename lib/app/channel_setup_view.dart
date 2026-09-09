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
    final scale = _step == 2
        ? (14 + 4 * expansion) / 14
        : LineupLayout.scaleFor(size);
    return Scaffold(
      body: Material(
        color: LineupTheme.of(context).deepBackground,
        child: SafeArea(
          child: Theme(
            data: Theme.of(context).copyWith(
              textTheme: Theme.of(context).textTheme
                  .apply(fontSizeFactor: scale),
            ),
            child: Padding(
              key: const ValueKey('channel-setup-content'),
              padding: _step == 2
                  ? EdgeInsets.symmetric(
                      horizontal: 32 + 16 * expansion,
                      vertical: 24 + 12 * expansion,
                    )
                  : LineupLayout.pageInsets(size),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(),
                  SizedBox(
                    height: _step == 2 ? 20 + 12 * expansion : 20 * scale,
                  ),
                  if (_error != null && _phase != _BuildPhase.failed) ...[
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
        ),
      ),
    );
  }

  Widget _header() {
    if (_step == 2) return _configurationHeader();
    return LayoutBuilder(
      key: const ValueKey('channel-setup-header'),
      builder: (context, constraints) {
        final title = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.asset('assets/branding/lineup-logo-mark.png', height: 42),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(switch (_step) {
                      1 => 'Choose libraries',
                      _ =>
                        _phase == _BuildPhase.review
                            ? (_firstSetup
                                  ? 'Review your first lineup'
                                  : 'Review your lineup')
                            : 'Channel Setup',
                    }, style: Theme.of(context).textTheme.headlineMedium),
                  ),
                  Text(
                    switch (_step) {
                      1 =>
                        'Select the Plex libraries to scan for channel ideas.',
                      _ =>
                        _phase == _BuildPhase.review
                            ? (_firstSetup
                                  ? 'Check your channels before creating your lineup.'
                                  : 'Check what changes and what stays.')
                            : 'Your setup choices remain available.',
                    },
                    style: TextStyle(
                      color: LineupTheme.of(context).secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
        final steps = Text(
          '1 Libraries  /  2 Configure  /  3 Review',
          key: const ValueKey('channel-setup-steps'),
          style: TextStyle(color: LineupTheme.of(context).secondaryText),
        );
        if (constraints.maxWidth < 900 ||
            MediaQuery.textScalerOf(context).scale(14) >= 21) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [title, const SizedBox(height: 8), steps],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            const SizedBox(width: 20),
            steps,
          ],
        );
      },
    );
  }

  Widget _configurationHeader() => LayoutBuilder(
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
            const TextSpan(text: '1 Libraries  /  '),
            TextSpan(
              text: '2 Configure',
              style: TextStyle(
                color: roles.primaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
            const TextSpan(text: '  /  3 Review'),
          ],
        ),
        key: const ValueKey('channel-setup-steps'),
      );
      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
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
              SizedBox(width: 10 + 2 * expansion),
              Image.asset(
                'assets/branding/lineup-logo-mark.png',
                height: 18 + 6 * expansion,
                excludeFromSemantics: true,
              ),
            ],
          ),
          SizedBox(height: 6 + 4 * expansion),
          Semantics(
            header: true,
            child: Text(
              'Shape your lineup',
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
            'Choose how your generated channels will play.',
            style: textStyle.copyWith(height: 1.4),
          ),
        ],
      );
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

  Widget _libraryStep() {
    final controller = widget.controller;
    final ready = controller.libraryScanReadyIds.intersection(
      _selectedLibraries,
    );
    final retry = controller.libraryScanRetryIds.intersection(
      _selectedLibraries,
    );
    final scanning = controller.libraryScanStatus == LibraryScanStatus.scanning;
    final mixed =
        ready.isNotEmpty &&
        ready.length != _selectedLibraries.length &&
        !scanning;
    final canRetry =
        !scanning &&
        (retry.isNotEmpty || (controller.error != null && ready.isNotEmpty));
    return _Stage(
      footer: _Footer(
        leading: [
          if (scanning)
            TextButton(
              onPressed: controller.cancelLibraryScan,
              child: const Text('Cancel scan'),
            )
          else if (controller.channelSetupCanCancel)
            TextButton(
              onPressed: controller.cancelChannelSetup,
              child: const Text('Cancel'),
            ),
          if (canRetry)
            OutlinedButton(
              onPressed: controller.busy
                  ? null
                  : () => _scan(retryFailedOnly: true),
              child: Text(
                retry.isEmpty ? 'Retry scan' : 'Retry ${retry.length} failed',
              ),
            ),
        ],
        trailing: mixed
            ? FilledButton(
                key: const ValueKey('continue-ready-libraries'),
                onPressed: controller.busy
                    ? null
                    : () => _commitLibraries(ready),
                child: Text('Continue with ${ready.length} ready'),
              )
            : FilledButton(
                key: const ValueKey('scan-selected-libraries'),
                onPressed: _selectedLibraries.isEmpty || controller.busy
                    ? null
                    : _scan,
                child: const Text('Scan selected libraries'),
              ),
      ),
      child: controller.libraries.isEmpty
          ? const Center(
              child: LineupEmptyState(
                icon: Icons.video_library_outlined,
                title: 'No movie or show libraries found',
                message:
                    'Choose another Plex server with accessible libraries.',
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _selectionSummary(),
                if (controller.error != null && !scanning) ...[
                  const SizedBox(height: 8),
                  LineupNotice(message: controller.error!),
                ],
                if (mixed) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: LineupTheme.of(context).secondaryText,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '${ready.length} ${ready.length == 1 ? 'library is' : 'libraries are'} ready. Libraries that are empty, unsupported or failed will be excluded.',
                          style: TextStyle(
                            color: LineupTheme.of(context).secondaryText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.separated(
                    key: const ValueKey('library-selection-list'),
                    itemCount: controller.libraries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) =>
                        _libraryRow(controller.libraries[index]),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _selectionSummary() {
    final libraries = widget.controller.libraries;
    final selected = _selectedLibraries.length;
    final all = selected == libraries.length;
    final value = all
        ? true
        : selected == 0
        ? false
        : null;
    return Row(
      children: [
        if (libraries.length > 1) ...[
          Checkbox(
            key: const ValueKey('select-all-libraries'),
            tristate: true,
            value: value,
            onChanged: (_) => _toggleAllLibraries(),
          ),
          TextButton(
            onPressed: _toggleAllLibraries,
            child: const Text('Select all'),
          ),
        ],
        const Spacer(),
        Text('$selected of ${libraries.length} selected'),
      ],
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
    final selected = _selectedLibraries.contains(library.id);
    final fact = widget.controller.libraryScanFacts[library.id];
    void toggle() => setState(() {
      if (selected) {
        _selectedLibraries.remove(library.id);
      } else {
        _selectedLibraries.add(library.id);
      }
    });

    return Semantics(
      button: true,
      selected: selected,
      label: '${library.title}, ${_libraryType(library)}, ${_scanStatus(fact)}',
      child: InkWell(
        onTap: widget.controller.busy ? null : toggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: selected,
                onChanged: widget.controller.busy ? null : (_) => toggle(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      library.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (fact != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _scanDetail(fact),
                        style: TextStyle(color: _scanColor(fact.status)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Text(
                _libraryType(library),
                style: TextStyle(color: LineupTheme.of(context).mutedText),
              ),
            ],
          ),
        ),
      ),
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
                _heading(
                  labels[_configurationSection],
                  switch (_configurationSection) {
                    0 => 'Choose which kinds of generated channels to include.',
                    1 => 'For generated channels containing TV episodes',
                    _ => 'Set limits and the priority used by balanced source rotation.',
                  },
                ),
                if (_configurationSection == 0)
                  LayoutBuilder(
                    builder: (_, constraints) {
                      final width = constraints.maxWidth >= 840
                          ? (constraints.maxWidth - 16) / 2
                          : constraints.maxWidth;
                      return Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          for (final strategy in BuilderStrategy.values)
                            SizedBox(
                              width: width,
                              child: _sourceControl(strategy, allocation),
                            ),
                        ],
                      );
                    },
                  ),
                if (_configurationSection == 1) _playbackControls(),
                if (_configurationSection == 2)
                  LayoutBuilder(
                    builder: (_, constraints) {
                      if (constraints.maxWidth < 840) {
                        return Column(
                          children: [
                            _limitControls(),
                            const SizedBox(height: 20),
                            _orderControls(),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _limitControls()),
                          const SizedBox(width: 32),
                          Expanded(child: _orderControls()),
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
    final enabled = _strategies.contains(strategy);
    final canGroup =
        _supportsGrouping(strategy) && _selectedLibraries.length > 1;
    final eligible = allocation.eligibleOriginalsByStrategy[strategy] ?? 0;
    final included = allocation.allocatedOriginalsByStrategy[strategy] ?? 0;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: LineupTheme.of(context).subtleBorder),
        ),
      ),
      child: Column(
        children: [
          CheckboxListTile(
            value: enabled,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(builderStrategyLabels[strategy]!)),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    '$eligible qualifying · $included included',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: LineupTheme.of(context).secondaryText,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_strategyDescription(strategy)),
            ),
            onChanged: (value) => setState(() {
              if (value == true) {
                _strategies.add(strategy);
              } else {
                _strategies.remove(strategy);
              }
            }),
          ),
          if (canGroup)
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.only(left: 40, right: 16),
              value: enabled && _grouped.contains(strategy),
              title: const Text('Group matching values across libraries'),
              subtitle: const Text(
                'One channel combines the same value from every selected library.',
              ),
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
        ],
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

  Widget _limitControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Limits', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 10),
      DropdownButtonFormField<int>(
        initialValue: _maximum,
        decoration: const InputDecoration(
          labelText: 'Maximum generated channels',
        ),
        items: const [50, 100, 200, 300, 500, 750, 1000]
            .map(
              (value) => DropdownMenuItem(value: value, child: Text('$value')),
            )
            .toList(),
        onChanged: (value) => setState(() => _maximum = value!),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<int>(
        initialValue: _minimum,
        decoration: const InputDecoration(
          labelText: 'Minimum programs per channel',
        ),
        items: const [1, 5, 10, 20, 50]
            .map(
              (value) => DropdownMenuItem(value: value, child: Text('$value')),
            )
            .toList(),
        onChanged: (value) => setState(() => _minimum = value!),
      ),
      const SizedBox(height: 8),
      Text(
        'Movies and individual episodes count as programs. Extra versions count toward the generated limit.',
        style: TextStyle(color: LineupTheme.of(context).secondaryText),
      ),
    ],
  );

  Widget _orderControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Source order', style: Theme.of(context).textTheme.titleMedium),
      for (var index = 0; index < _sourceOrder.length; index++)
        DecoratedBox(
          key: ValueKey('source-order-${_sourceOrder[index].name}'),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: LineupTheme.of(context).subtleBorder),
            ),
          ),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(builderStrategyLabels[_sourceOrder[index]]!),
            subtitle: _strategies.contains(_sourceOrder[index])
                ? null
                : const Text('Off'),
            trailing: Wrap(
              children: [
                IconButton(
                  focusNode: _orderFocus[_sourceOrder[index]]!.earlier,
                  tooltip: 'Move earlier',
                  onPressed: index == 0 ? null : () => _moveSource(index, -1),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  focusNode: _orderFocus[_sourceOrder[index]]!.later,
                  tooltip: 'Move later',
                  onPressed: index == _sourceOrder.length - 1
                      ? null
                      : () => _moveSource(index, 1),
                  icon: const Icon(Icons.arrow_downward),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 8),
      Text(
        'Lineup takes one eligible original from each source in order, repeats, and skips exhausted sources.',
        style: TextStyle(color: LineupTheme.of(context).secondaryText),
      ),
    ],
  );

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
    return _Stage(
      footer: _Footer(
        leading: [
          TextButton(
            onPressed: () => setState(() => _step = 2),
            child: const Text('Back to configure'),
          ),
        ],
        summary: _methodDecision(),
        trailing: noChanges
            ? FilledButton(
                onPressed: _viewLineup,
                child: const Text('View lineup'),
              )
            : FilledButton(
                key: const ValueKey('apply-reviewed-lineup'),
                onPressed: counts.removed > 0 && !_removalConfirmed
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
          if (_notice != null) ...[
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
          const SizedBox(height: 8),
          Expanded(child: _roster(entries)),
          if (counts.removed > 0)
            CheckboxListTile(
              key: const ValueKey('channel-setup-replace-confirmation'),
              contentPadding: EdgeInsets.zero,
              value: _removalConfirmed,
              title: Text(
                'I understand that ${counts.removed} existing generated ${counts.removed == 1 ? 'channel' : 'channels'} will be removed.',
              ),
              onChanged: (value) =>
                  setState(() => _removalConfirmed = value == true),
            ),
        ],
      ),
    );
  }

  Widget _methodDecision() {
    if (_firstSetup) {
      return Text('${_plan!.channels.length} channels ready to create');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 310,
          child: DropdownButtonFormField<ChannelBuildMode>(
            key: const ValueKey('review-build-method'),
            initialValue: _mode,
            isExpanded: true,
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
        ),
        const SizedBox(height: 5),
        Text(
          _modeDescription(_mode),
          style: TextStyle(color: LineupTheme.of(context).secondaryText),
        ),
      ],
    );
  }

  Widget _reviewOverview(
    List<_ReviewEntry> entries,
    List<Channel> finalChannels,
    ({int unchanged, int updated, int added, int removed}) counts,
  ) {
    final finalCount = finalChannels.length;
    final generated = _finalGeneratedCounts(finalChannels);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_firstSetup)
          Text(
            '$finalCount channels ready to create',
            style: Theme.of(context).textTheme.headlineSmall,
          )
        else
          Semantics(
            label: '${_reviewBase.length} current to $finalCount final',
            child: ExcludeSemantics(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text(
                    '${_reviewBase.length} current',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Icon(
                    Icons.arrow_forward,
                    size: Theme.of(context).textTheme.headlineSmall?.fontSize,
                  ),
                  Text(
                    '$finalCount final',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
            ),
          ),
        if (!_firstSetup) ...[
          Text(
            'Changes in this review${counts.removed > 0 ? ' · Includes channels being removed' : ''}',
            style: TextStyle(color: LineupTheme.of(context).secondaryText),
          ),
          const SizedBox(height: 5),
          if (entries.isNotEmpty)
            Semantics(
              label:
                  '${counts.unchanged} unchanged, ${counts.updated} updated, ${counts.added} added, ${counts.removed} removed. ${entries.length} review entries including outgoing channels.',
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    _segment(
                      counts.unchanged,
                      LineupTheme.of(context).mutedText,
                    ),
                    _segment(
                      counts.updated,
                      LineupTheme.of(context).focusBorder,
                    ),
                    _segment(
                      counts.added,
                      LineupTheme.of(context).progressFill,
                    ),
                    _segment(
                      counts.removed,
                      Theme.of(context).colorScheme.error,
                    ),
                  ],
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              _filterChip(_ReviewFilter.unchanged, counts.unchanged),
              _filterChip(_ReviewFilter.updated, counts.updated),
              _filterChip(_ReviewFilter.added, counts.added),
              _filterChip(_ReviewFilter.removed, counts.removed),
              TextButton(
                onPressed: () => setState(() => _filter = _ReviewFilter.all),
                child: const Text('Show all'),
              ),
            ],
          ),
        ],
        const Divider(),
        Wrap(
          spacing: 18,
          runSpacing: 4,
          children: [
            const Text('Final generated channels'),
            for (final strategy in _sourceOrder)
              if ((generated.byStrategy[strategy] ?? 0) > 0)
                Text(
                  '${builderStrategyLabels[strategy]} ${generated.byStrategy[strategy]}',
                ),
            if (generated.other > 0) Text('Other generated ${generated.other}'),
          ],
        ),
        if (_reviewBase.any((channel) => channel.builderKey == null))
          Text(
            '${_reviewBase.where((channel) => channel.builderKey == null).length} custom channels will be kept.',
            style: TextStyle(color: LineupTheme.of(context).secondaryText),
          ),
      ],
    );
  }

  Widget _segment(int count, Color color) => count == 0
      ? const SizedBox.shrink()
      : Expanded(
          flex: count,
          child: Container(height: 10, color: color),
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

  Widget _filterChip(_ReviewFilter filter, int count) => FilterChip(
    selected: _filter == filter,
    label: Text('$count ${_capitalized(filter.name)}'),
    onSelected: (_) => setState(() => _filter = filter),
  );

  Widget _roster(List<_ReviewEntry> all) {
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
        TextField(
          key: const ValueKey('channel-setup-review-search'),
          controller: _search,
          decoration: const InputDecoration(
            hintText: 'Search channels by name or number',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {}),
        ),
        Text(
          filtered
              ? '${_capitalized(_filter.name)} · ${entries.length} matching ${entries.length == 1 ? 'channel' : 'channels'}'
              : '${entries.length} of ${all.length} review entries',
        ),
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

  Widget _rosterHeader() => Container(
    key: const ValueKey('review-roster-header'),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    color: LineupTheme.of(context).primarySurface,
    child: const Row(
      children: [
        SizedBox(width: 58, child: Text('No.')),
        Expanded(flex: 3, child: Text('Channel')),
        Expanded(flex: 2, child: Text('Source')),
        Expanded(flex: 2, child: Text('Playback')),
        SizedBox(width: 92, child: Text('Change', textAlign: TextAlign.end)),
      ],
    ),
  );

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
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 58, child: Text('${entry.channel.number}')),
        Expanded(flex: 3, child: Text(entry.channel.name)),
        Expanded(flex: 2, child: Text(_sourceLabel(entry.channel.source))),
        Expanded(flex: 2, child: Text(_playbackLabel(entry.channel))),
        SizedBox(
          width: 92,
          child: Text(_capitalized(entry.kind.name), textAlign: TextAlign.end),
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
              childrenPadding: const EdgeInsets.fromLTRB(70, 0, 12, 12),
              children: [
                for (final change in changes)
                  Align(alignment: Alignment.centerLeft, child: Text(change)),
              ],
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
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
    return _Stage(
      footer: _phase == _BuildPhase.applying
          ? const SizedBox.shrink()
          : _Footer(
              leading: [
                if (_phase == _BuildPhase.complete)
                  TextButton(
                    onPressed: _addCustom,
                    child: const Text('Add a custom channel'),
                  ),
              ],
              trailing: FilledButton(
                focusNode: _resultFocus,
                onPressed: _phase == _BuildPhase.failed
                    ? () => setState(() => _phase = _BuildPhase.review)
                    : _viewLineup,
                child: Text(
                  _phase == _BuildPhase.failed
                      ? 'Back to review'
                      : 'View lineup',
                ),
              ),
            ),
      child: Center(
        child: Semantics(
          liveRegion: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_phase == _BuildPhase.applying)
                  MediaQuery.disableAnimationsOf(context)
                      ? const Icon(Icons.hourglass_top, size: 38)
                      : const SizedBox(
                          width: 38,
                          height: 38,
                          child: CircularProgressIndicator(),
                        )
                else
                  Icon(
                    _phase == _BuildPhase.failed
                        ? Icons.error_outline
                        : Icons.check_circle_outline,
                    size: 42,
                    color: _phase == _BuildPhase.failed
                        ? Theme.of(context).colorScheme.error
                        : LineupTheme.of(context).progressFill,
                  ),
                const SizedBox(width: 22),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(switch (_phase) {
                        _BuildPhase.applying =>
                          _firstSetup
                              ? 'Creating your lineup…'
                              : 'Updating your lineup…',
                        _BuildPhase.failed =>
                          _firstSetup
                              ? 'We couldn’t create your lineup'
                              : 'We couldn’t update your lineup',
                        _BuildPhase.complete =>
                          _firstSetup
                              ? 'Your lineup is ready'
                              : 'Your lineup is updated',
                        _ => '',
                      }, style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 14),
                      if (_phase == _BuildPhase.complete) ...[
                        Text(
                          '$total ${total == 1 ? 'channel' : 'channels'} in your lineup',
                        ),
                        if (!_firstSetup) Text(_changeSummary(counts)),
                      ] else if (_phase == _BuildPhase.failed) ...[
                        Text(
                          _firstSetup
                              ? 'Your lineup wasn’t saved.'
                              : 'Your existing lineup hasn’t changed.',
                        ),
                        const Text('Your setup choices are still here.'),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Text(_error!),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
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
    LibraryScanStatus.complete => LineupTheme.of(context).progressFill,
    _ => LineupTheme.of(context).secondaryText,
  };

  String _scanStatus(LibraryScanFact? fact) => fact == null
      ? 'Not scanned'
      : switch (fact.status) {
          LibraryScanStatus.idle => 'Not scanned',
          LibraryScanStatus.scanning => 'Scanning',
          LibraryScanStatus.complete => 'Ready',
          LibraryScanStatus.empty => 'Empty',
          LibraryScanStatus.unsupported => 'No playable media',
          LibraryScanStatus.transientFailure => 'Scan failed',
          LibraryScanStatus.cancelled => 'Cancelled',
        };

  String _scanDetail(LibraryScanFact fact) {
    final status = _scanStatus(fact);
    if (fact.status == LibraryScanStatus.idle) return status;
    final items = fact.totalItems == null
        ? '${fact.completedItems} scanned'
        : '${fact.completedItems}/${fact.totalItems} items';
    return '$status · $items · ${fact.completedPages} ${fact.completedPages == 1 ? 'page' : 'pages'}';
  }

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
    BuilderStrategy.playlists => 'Channels from Plex playlists.',
    BuilderStrategy.collections => 'Channels from collection tags.',
    BuilderStrategy.recentlyAdded => 'One newest-first channel per library.',
    BuilderStrategy.genres =>
      'Examples include drama, comedy and science fiction.',
    BuilderStrategy.studios => 'Channels grouped by studio metadata.',
    BuilderStrategy.actors => 'Channels for actors with enough programs.',
    BuilderStrategy.decades => 'Channels such as 1980s and 1990s.',
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
