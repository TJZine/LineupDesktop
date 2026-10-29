import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../channels/channel.dart';
import '../../channels/channel_builder.dart';
import '../../ui/app_theme.dart';
import '../../ui/app_ui.dart';
import 'step_scaffold.dart';

/// Configuration is owned by the flow; steps receive a frozen presentation value.
class SetupConfiguration {
  SetupConfiguration({
    required Set<BuilderStrategy> strategies,
    required Set<BuilderStrategy> grouped,
    required List<BuilderStrategy> sourceOrder,
    required this.playback,
    required this.blockSize,
    required this.includeSpecials,
    required this.extras,
    required this.alternateCopies,
    required this.variantMode,
    required this.variantBlockSize,
    required this.maximum,
    required this.minimum,
  }) : strategies = Set.unmodifiable(strategies),
       grouped = Set.unmodifiable(grouped),
       sourceOrder = List.unmodifiable(sourceOrder);

  final Set<BuilderStrategy> strategies;
  final Set<BuilderStrategy> grouped;
  final List<BuilderStrategy> sourceOrder;
  final PlaybackMode playback;
  final int blockSize;
  final bool includeSpecials;
  final bool extras;
  final int alternateCopies;
  final PlaybackMode? variantMode;
  final int variantBlockSize;
  final int maximum;
  final int minimum;
}

class _ConfigureFocus {
  _ConfigureFocus()
    : playback = {
        for (final mode in PlaybackMode.values)
          mode: FocusNode(debugLabel: 'Setup playback ${mode.name}'),
      },
      order = {
        for (final strategy in BuilderStrategy.values)
          strategy: (earlier: FocusNode(), later: FocusNode()),
      };

  final Map<PlaybackMode, FocusNode> playback;
  final Map<BuilderStrategy, ({FocusNode earlier, FocusNode later})> order;

  void dispose() {
    for (final node in playback.values) {
      node.dispose();
    }
    for (final nodes in order.values) {
      nodes.earlier.dispose();
      nodes.later.dispose();
    }
  }
}

class SetupConfigureStep extends StatefulWidget {
  const SetupConfigureStep({
    required this.allocation,
    required this.section,
    required this.onSectionChanged,
    required this.onBack,
    required this.onReview,
    required this.hasConfirmedMissingSources,
    required this.configuration,
    required this.selectedLibraryCount,
    required this.disabledEligibility,
    required this.discoveryFailures,
    required this.collectionRecovery,
    required this.retryingDiscovery,
    required this.busy,
    required this.notice,
    required this.onSourceEnabledChanged,
    required this.onGroupingChanged,
    required this.onRetryDiscovery,
    required this.onPlaybackChanged,
    required this.onExtrasChanged,
    required this.onVariantModeChanged,
    required this.onAlternateCopiesChanged,
    required this.onIncludeSpecialsChanged,
    required this.onBlockSizeChanged,
    required this.onMaximumChanged,
    required this.onMinimumChanged,
    required this.onSourceOrderChanged,
    super.key,
  });

  final ChannelPlanAllocation allocation;
  final int section;
  final ValueChanged<int> onSectionChanged;
  final VoidCallback onBack;
  final VoidCallback onReview;
  final bool hasConfirmedMissingSources;
  final SetupConfiguration configuration;
  final int selectedLibraryCount;
  final Map<BuilderStrategy, int> disabledEligibility;
  final Map<BuilderStrategy, String> discoveryFailures;
  final String? collectionRecovery;
  final bool retryingDiscovery;
  final bool busy;
  final String? notice;
  final void Function(BuilderStrategy strategy, bool enabled)
  onSourceEnabledChanged;
  final void Function(BuilderStrategy strategy, bool grouped) onGroupingChanged;
  final ValueChanged<BuilderStrategy> onRetryDiscovery;
  final ValueChanged<PlaybackMode> onPlaybackChanged;
  final ValueChanged<bool> onExtrasChanged;
  final ValueChanged<PlaybackMode?> onVariantModeChanged;
  final ValueChanged<int> onAlternateCopiesChanged;
  final ValueChanged<bool> onIncludeSpecialsChanged;
  final void Function(bool main, int size) onBlockSizeChanged;
  final ValueChanged<int> onMaximumChanged;
  final ValueChanged<int> onMinimumChanged;
  final ValueChanged<List<BuilderStrategy>> onSourceOrderChanged;

  @override
  State<SetupConfigureStep> createState() => _SetupConfigureStepState();
}

class _SetupConfigureStepState extends State<SetupConfigureStep> {
  final _focus = _ConfigureFocus();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SetupStage(
      footerGap: 0,
      footer: SetupFooter(
        configuration: true,
        leading: [
          TextButton(
            onPressed: widget.onBack,
            child: const Text('Back to libraries'),
          ),
        ],
        summary: _configurationSummary(widget.allocation),
        trailing: FilledButton(
          key: const ValueKey('review-channels'),
          onPressed:
              widget.allocation.channels.isNotEmpty ||
                  widget.allocation.existingSkipped > 0 ||
                  widget.hasConfirmedMissingSources
              ? widget.onReview
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
                selected: widget.section == index,
                child: LineupNavigationRow(
                  selected: widget.section == index,
                  key: ValueKey('configure-section-$index'),
                  autofocus: LineupTheme.of(context).androidTv && index == 0,
                  onPressed: () => widget.onSectionChanged(index),
                  child: Text(labels[index]),
                ),
              ),
          ];
          final selectedContent = switch (widget.section) {
            0 => _configureSectionContent(widget.allocation, 0, _focus),
            1 => _configureSectionContent(widget.allocation, 1, _focus),
            _ => _configureSectionContent(widget.allocation, 2, _focus),
          };
          final content = KeyedSubtree(
            key: const ValueKey('channel-configuration'),
            child: ListView(
              key: ValueKey(widget.section),
              children: [
                if (widget.section != 2)
                  _heading(
                    labels[widget.section],
                    widget.section == 0
                        ? 'Choose which kinds of generated channels to include.'
                        : 'For generated channels containing TV episodes',
                  ),
                selectedContent,
              ],
            ),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(spacing: 8, runSpacing: 4, children: navigation),
                const SizedBox(height: 16),
                Expanded(child: content),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 236,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final item in navigation) ...[
                      item,
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 40),
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
          padding: const EdgeInsets.only(bottom: 12),
          child: inline
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(title, style: titleStyle),
                    const SizedBox(width: 32),
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

  Set<BuilderStrategy> get _strategies => widget.configuration.strategies;
  Set<BuilderStrategy> get _grouped => widget.configuration.grouped;
  List<BuilderStrategy> get _sourceOrder => widget.configuration.sourceOrder;
  PlaybackMode get _playback => widget.configuration.playback;
  int get _blockSize => widget.configuration.blockSize;
  bool get _includeSpecials => widget.configuration.includeSpecials;
  bool get _extras => widget.configuration.extras;
  int get _alternateCopies => widget.configuration.alternateCopies;
  PlaybackMode? get _variantMode => widget.configuration.variantMode;
  int get _variantBlockSize => widget.configuration.variantBlockSize;
  int get _maximum => widget.configuration.maximum;
  int get _minimum => widget.configuration.minimum;
  String? get _notice => widget.notice;

  ({double width, double closedHeight, double itemHeight}) _dropdownMetrics({
    required double desiredWidth,
    required double baseHeight,
    required double maxWidth,
    required Iterable<String> labels,
    required TextStyle style,
    double outerHorizontalChrome = 0,
    double menuVerticalPadding = 8,
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
        intrinsicWidth +
            2 * horizontalPadding +
            arrowWidth +
            outerHorizontalChrome,
      ),
    );
    final textWidth = math.max(
      1.0,
      width - 2 * horizontalPadding - arrowWidth - outerHorizontalChrome,
    );
    var textHeight = 0.0;
    for (final label in labels) {
      textHeight = math.max(textHeight, measure(label, maxWidth: textWidth));
    }
    return (
      width: width,
      closedHeight: math.max(baseHeight, textHeight + 8),
      itemHeight: math.max(48, textHeight + menuVerticalPadding),
    );
  }

  Widget _configureSectionContent(
    ChannelPlanAllocation allocation,
    int section,
    _ConfigureFocus focus,
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
          if (widget.selectedLibraryCount > 1)
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
        _supportsGrouping(strategy) && widget.selectedLibraryCount > 1;
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
        _supportsGrouping(first) && widget.selectedLibraryCount > 1;
    final secondCanGroup =
        _supportsGrouping(second) && widget.selectedLibraryCount > 1;

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
  ) => LineupTheme.of(context).androidTv
      ? LineupRowSurface(
          selected: false,
          child: Builder(
            builder: (context) =>
                _sourceSelectionContent(context, strategy, allocation),
          ),
        )
      : _sourceSelectionContent(context, strategy, allocation);

  Widget _sourceSelectionContent(
    BuildContext context,
    BuilderStrategy strategy,
    ChannelPlanAllocation allocation,
  ) {
    final roles = LineupTheme.of(context);
    final enabled = _strategies.contains(strategy);
    final discoveryFailure = widget.discoveryFailures[strategy];
    final eligible = enabled
        ? allocation.eligibleOriginalsByStrategy[strategy] ?? 0
        : (widget.disabledEligibility[strategy] ?? 0);
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
        ? widget.collectionRecovery
        : null;
    final subtitle = Padding(
      padding: EdgeInsets.only(top: 12),
      child: Text(_strategyDescription(strategy), style: detailStyle),
    );
    void changed(bool? value) =>
        widget.onSourceEnabledChanged(strategy, value == true);

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
                  padding: LineupTheme.of(context).androidTv
                      ? const EdgeInsets.symmetric(horizontal: 20)
                      : EdgeInsets.zero,
                  minimumSize: const Size(0, 48),
                  alignment: Alignment.centerLeft,
                ),
                key: ValueKey('retry-discovery-${strategy.name}'),
                onPressed: widget.retryingDiscovery || widget.busy
                    ? null
                    : () => widget.onRetryDiscovery(strategy),
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

  Widget _sourceGroupingControl(BuilderStrategy strategy) {
    final roles = LineupTheme.of(context);
    final menuTheme = roles.androidTv ? Theme.of(context) : null;
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
            outerHorizontalChrome: roles.androidTv
                ? LineupDropdownBox.contentPadding(compact: true).horizontal +
                      2 * LineupDropdownBox.borderWidth
                : 0,
            menuVerticalPadding: roles.androidTv
                ? LineupDropdownMenuRow.contentPadding.vertical
                : 8,
          );
          final dropdown = SizedBox(
            width: metrics.width,
            height: math.max(44, metrics.closedHeight),
            child: DropdownButtonHideUnderline(
              child: LineupDropdownBox(
                compact: true,
                enabled: enabled,
                child: Builder(
                  builder: (context) => DropdownButton<bool>(
                    key: ValueKey('source-grouping-${strategy.name}'),
                    isExpanded: true,
                    isDense: true,
                    iconSize: 24,
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    itemHeight: metrics.itemHeight,
                    value: _grouped.contains(strategy),
                    style: roles.androidTv
                        ? groupingStyle.copyWith(
                            color: enabled
                                ? LineupTheme.of(context).primaryText
                                : LineupTheme.of(context).mutedText,
                          )
                        : groupingStyle,
                    iconEnabledColor: roles.androidTv
                        ? LineupTheme.of(context).secondaryText
                        : null,
                    iconDisabledColor: roles.androidTv
                        ? LineupTheme.of(context).mutedText
                        : null,
                    items: lineupMenuItems(
                      [
                        const DropdownMenuItem(
                          value: false,
                          child: Text('Separate by library'),
                        ),
                        DropdownMenuItem(
                          value: true,
                          child: Text(groupingLabel),
                        ),
                      ],
                      _grouped.contains(strategy),
                      menuTheme: menuTheme,
                    ),
                    onChanged: enabled
                        ? (value) =>
                              widget.onGroupingChanged(strategy, value == true)
                        : null,
                    dropdownColor: roles.elevatedSurface,
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

  Widget _playbackControls(_ConfigureFocus focus) {
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
    final additionalVersionsSubtitle = Builder(
      builder: (context) => Padding(
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
      ),
    );
    void changeAdditionalVersions(bool value) => widget.onExtrasChanged(value);
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
              onChanged: (mode) => widget.onPlaybackChanged(mode!),
              child: Shortcuts(
                // RadioGroup owns all four arrows by default. TV uses vertical
                // arrows to leave the choices through normal spatial traversal.
                shortcuts: LineupTheme.of(context).androidTv
                    ? const {
                        SingleActivator(LogicalKeyboardKey.arrowUp):
                            DirectionalFocusIntent(TraversalDirection.up),
                        SingleActivator(LogicalKeyboardKey.arrowDown):
                            DirectionalFocusIntent(TraversalDirection.down),
                      }
                    : const {},
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
        LineupToggleSurface(
          child: ListTileTheme.merge(
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
                    onChanged: (value) => widget.onVariantModeChanged(value),
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
                        : (value) => widget.onAlternateCopiesChanged(value!),
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
      onChanged: (value) => widget.onIncludeSpecialsChanged(value ?? false),
      child: const Text('Include specials'),
    ),
  );

  Widget _playbackChoice(
    PlaybackMode mode,
    String title,
    String description, {
    required _ConfigureFocus focus,
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
            builder: (context, state) => ListenableBuilder(
              listenable: focus.playback[mode]!,
              builder: (context, _) {
                final roles = LineupTheme.of(context);
                final selected = state.states.contains(WidgetState.selected);
                final focused = LineupFocusScope.visible(
                  context,
                  // Toggleable's focused state follows Flutter's platform
                  // highlight mode, which can remain touch for native TV keys.
                  roles.androidTv
                      ? focus.playback[mode]!.hasFocus
                      : state.states.contains(WidgetState.focused),
                );
                final hovered = state.states.contains(WidgetState.hovered);
                final radius = BorderRadius.circular(roles.panelRadius);
                final focusFill =
                    focused &&
                    roles.focusTreatment == LineupFocusTreatment.fill;
                final focusRing =
                    focused &&
                    roles.focusTreatment == LineupFocusTreatment.ring;
                final surface = selected
                    ? roles.elevatedSurface
                    : roles.primarySurface;
                return LineupFocusFrame(
                  focused: focusFill,
                  child: Container(
                    constraints: BoxConstraints(minHeight: 152),
                    padding: EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: focusFill
                          ? roles.focusedSurface
                          : hovered
                          ? Color.alphaBlend(
                              roles.primaryText.withValues(alpha: 0.04),
                              surface,
                            )
                          : surface,
                      borderRadius: radius,
                      border: Border.all(
                        color: selected
                            ? roles.progressFill
                            : roles.defaultBorder,
                      ),
                    ),
                    foregroundDecoration: focusRing
                        ? BoxDecoration(
                            borderRadius: radius,
                            border: Border.all(
                              color: roles.focusBorder,
                              width: roles.focusBorderWidth,
                            ),
                          )
                        : null,
                    child: LineupFocusInk(
                      focused: focusFill,
                      child: Builder(
                        builder: (context) {
                          final ink = LineupTheme.of(context);
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  color: ink.primaryText,
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
                                  color: ink.secondaryText,
                                  fontSize: 18,
                                  height: 1.4,
                                  letterSpacing: 0,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
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
        onChanged: (value) => widget.onBlockSizeChanged(main, value!),
      ),
    );
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
    Widget choiceLabel(int choice) => roles.androidTv
        ? Builder(
            builder: (context) => Text(
              '$choice',
              maxLines: 1,
              softWrap: false,
              style: dropdownStyle.copyWith(
                color: LineupTheme.of(context).primaryText,
              ),
            ),
          )
        : Text('$choice');

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
                outerHorizontalChrome: roles.androidTv
                    ? LineupDropdownBox.contentPadding().horizontal +
                          2 * LineupDropdownBox.borderWidth
                    : 0,
                menuVerticalPadding: roles.androidTv
                    ? LineupDropdownMenuRow.contentPadding.vertical
                    : 8,
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
                        icon: roles.androidTv
                            ? Builder(
                                builder: (context) => Icon(
                                  Icons.arrow_drop_down,
                                  color: LineupTheme.of(context).secondaryText,
                                ),
                              )
                            : null,
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        itemHeight: metrics.itemHeight,
                        value: value,
                        style: dropdownStyle,
                        items: lineupMenuItems(
                          [
                            for (final choice in choices)
                              DropdownMenuItem(
                                value: choice,
                                child: choiceLabel(choice),
                              ),
                          ],
                          value,
                          menuTheme: roles.androidTv ? Theme.of(context) : null,
                        ),
                        onChanged: (next) {
                          if (next != null) onChanged(next);
                        },
                        dropdownColor: LineupTheme.of(context).elevatedSurface,
                        menuWidth: roles.androidTv ? dropdownWidth : null,
                        selectedItemBuilder: (_) => [
                          for (final choice in choices) choiceLabel(choice),
                        ],
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
          onChanged: widget.onMaximumChanged,
        ),
        field(
          key: const ValueKey('rules-minimum'),
          label: 'Minimum programs per channel',
          value: _minimum,
          choices: const [1, 5, 10, 20, 50],
          description: 'Movies and individual episodes count as programs. Higher values exclude smaller channel candidates.',
          onChanged: widget.onMinimumChanged,
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

  Widget _orderControls(_ConfigureFocus focus) {
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
            child: Builder(
              builder: (context) {
                final visible = LineupFocusScope.visible(context, focused);
                final fillFocus =
                    visible &&
                    roles.focusTreatment == LineupFocusTreatment.fill;
                return DecoratedBox(
                  key: ValueKey('source-order-${strategy.name}'),
                  decoration: BoxDecoration(
                    color: fillFocus
                        ? roles.focusedSurface
                        : hovered || visible
                        ? roles.primarySurface
                        : Colors.transparent,
                    border: Border(
                      bottom: BorderSide(color: roles.subtleBorder),
                    ),
                  ),
                  child: LineupFocusFrame(
                    focused: fillFocus,
                    child: LineupFocusInk(
                      focused: fillFocus,
                      child: Builder(
                        builder: (context) {
                          final ink = LineupTheme.of(context);
                          final inkNameStyle = nameStyle.copyWith(
                            color: ink.primaryText,
                          );
                          final inkRankStyle = rankStyle.copyWith(
                            color: ink.secondaryText,
                          );
                          return ConstrainedBox(
                            constraints: BoxConstraints(minHeight: rowHeight),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 28,
                                  child: Text(
                                    '${index + 1}',
                                    style: inkRankStyle,
                                  ),
                                ),
                                SizedBox(width: rowGap),
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text:
                                              builderStrategyLabels[strategy]!,
                                        ),
                                        if (!enabled)
                                          TextSpan(
                                            text: '  Off',
                                            style: inkRankStyle,
                                          ),
                                      ],
                                    ),
                                    style: inkNameStyle,
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
                                      onPressed:
                                          index == _sourceOrder.length - 1
                                          ? null
                                          : () => _moveSource(index, 1, focus),
                                      icon: Icons.arrow_downward,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
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

  void _moveSource(int index, int delta, _ConfigureFocus focus) {
    final strategy = _sourceOrder[index];
    final target = index + delta;
    final order = List<BuilderStrategy>.of(_sourceOrder)
      ..removeAt(index)
      ..insert(target, strategy);
    widget.onSourceOrderChanged(List.unmodifiable(order));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nodes = focus.order[strategy]!;
      final earlier =
          target == _sourceOrder.length - 1 || (target > 0 && delta < 0);
      (earlier ? nodes.earlier : nodes.later).requestFocus();
    });
  }

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
