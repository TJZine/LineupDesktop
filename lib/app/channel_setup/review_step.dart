import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../channels/channel.dart';
import '../../channels/channel_builder.dart';
import '../../ui/app_theme.dart';
import '../../ui/app_ui.dart';
import '../setup_review.dart';
import 'step_scaffold.dart';

enum SetupReviewFilter { all, unchanged, updated, added, removed }

class SetupReviewStep extends StatefulWidget {
  const SetupReviewStep({
    required this.review,
    required this.notice,
    required this.removalConfirmed,
    required this.sourceOrder,
    required this.sourceLabel,
    required this.initialFilter,
    required this.initialSearch,
    required this.onFilterChanged,
    required this.onSearchChanged,
    required this.isGeneratedSourceConfirmedGone,
    required this.onBack,
    required this.onModeChanged,
    required this.onRemovalChanged,
    required this.onRemovalConfirmationChanged,
    required this.onApply,
    required this.onViewLineup,
    super.key,
  });

  final SetupReview review;
  final String? notice;
  final bool removalConfirmed;
  final List<BuilderStrategy> sourceOrder;
  final String Function(ContentSource source) sourceLabel;
  final SetupReviewFilter initialFilter;
  final String initialSearch;
  final ValueChanged<SetupReviewFilter> onFilterChanged;
  final ValueChanged<String> onSearchChanged;
  final bool Function(Channel channel) isGeneratedSourceConfirmedGone;
  final VoidCallback onBack;
  final ValueChanged<ChannelBuildMode> onModeChanged;
  final void Function(String id, bool remove) onRemovalChanged;
  final ValueChanged<bool> onRemovalConfirmationChanged;
  final VoidCallback onApply;
  final VoidCallback onViewLineup;

  @override
  State<SetupReviewStep> createState() => _SetupReviewStepState();
}

class _SetupReviewStepState extends State<SetupReviewStep> {
  late SetupReviewFilter _filter = widget.initialFilter;
  late final _search = TextEditingController(text: widget.initialSearch);
  final _searchFocus = FocusNode(debugLabel: 'Setup review search');

  final _rosterScroll = ScrollController();
  final _backFocus = FocusNode(debugLabel: 'Review Back to configure');
  final _primaryFocus = FocusNode(debugLabel: 'Review primary');
  final _rowScopes = <String, FocusNode>{};
  List<String> _returnOrder = const [];
  String? _returnId;
  double _returnOffset = 0;
  bool _rosterFocused = false;
  int _revealGeneration = 0;

  List<SetupReviewEntry> get _visibleEntries {
    final query = _search.text.trim().toLowerCase();
    return widget.review.entries.where((entry) {
      final channel = entry.channel;
      return (query.isEmpty ||
              channel.name.toLowerCase().contains(query) ||
              '${channel.number}'.contains(query)) &&
          (_filter == SetupReviewFilter.all || entry.kind.name == _filter.name);
    }).toList();
  }

  bool get _primaryEnabled =>
      !widget.review.counts.hasChanges ||
      (widget.notice != 'Updating review…' &&
          (widget.review.counts.removed == 0 || widget.removalConfirmed));

  void _rememberRow(String id) {
    _returnId = id;
    _returnOrder = widget.review.entries
        .map((entry) => entry.channel.id)
        .toList();
    _returnOffset = _rosterScroll.offset;
  }

  KeyEventResult _rowKey(String id, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.arrowRight ||
        event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    _revealGeneration++;
    _rememberRow(id);
    (_primaryEnabled ? _primaryFocus : _backFocus).requestFocus();
    return KeyEventResult.handled;
  }

  String? _returnTarget(List<SetupReviewEntry> entries) {
    final ids = entries.map((entry) => entry.channel.id).toSet();
    if (ids.contains(_returnId)) return _returnId;
    final origin = _returnOrder.indexOf(_returnId ?? '');
    // Equal-distance ties choose the preceding entry in the original order.
    for (var distance = 1; distance < _returnOrder.length; distance++) {
      for (final index in [origin - distance, origin + distance]) {
        if (index >= 0 &&
            index < _returnOrder.length &&
            ids.contains(_returnOrder[index])) {
          return _returnOrder[index];
        }
      }
    }
    return entries.isEmpty ? null : entries.first.channel.id;
  }

  Future<void> _returnToRoster() async {
    final generation = ++_revealGeneration;
    final entries = _visibleEntries;
    final id = _returnTarget(entries);
    if (id == null) {
      _searchFocus.requestFocus();
      await Scrollable.ensureVisible(_searchFocus.context!);
      return;
    }
    final targetIndex = entries.indexWhere((entry) => entry.channel.id == id);
    final positions = {
      for (var i = 0; i < entries.length; i++) entries[i].channel.id: i,
    };
    _rosterScroll.jumpTo(
      _returnOffset.clamp(0, _rosterScroll.position.maxScrollExtent),
    );
    // A sliver may have disposed the return row while focus was in the footer.
    // Walk viewport-sized chunks until it is built; row heights can vary with
    // disclosure expansion and text scaling, so an estimated row extent is unsafe.
    for (var attempt = 0; attempt <= entries.length; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          generation != _revealGeneration ||
          (!_primaryFocus.hasFocus && !_backFocus.hasFocus)) {
        return;
      }
      final scope = _rowScopes[id];
      final target = scope?.traversalDescendants.firstOrNull;
      if (target?.context?.mounted == true) {
        target!.requestFocus();
        await Scrollable.ensureVisible(target.context!, alignment: .5);
        return;
      }
      final built =
          _rowScopes.entries
              .where(
                (entry) =>
                    entry.value.context?.mounted == true &&
                    positions.containsKey(entry.key),
              )
              .map((entry) => positions[entry.key]!)
              .toList()
            ..sort();
      final forward = built.isEmpty || targetIndex > built.last;
      final position = _rosterScroll.position;
      final next =
          (position.pixels +
                  (forward ? 1 : -1) * position.viewportDimension * .8)
              .clamp(0.0, position.maxScrollExtent);
      if (next == position.pixels) return;
      _rosterScroll.jumpTo(next);
    }
  }

  KeyEventResult _footerKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.arrowUp || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    unawaited(_returnToRoster());
    return KeyEventResult.handled;
  }

  bool get _firstSetup => widget.review.base.isEmpty;

  bool get _entryFocusIsEligible {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;
    if (!_searchFocus.canRequestFocus ||
        _searchFocus.context?.mounted != true) {
      return false;
    }
    if (_searchFocus.enclosingScope?.canRequestFocus == false) return false;
    if (context.findAncestorWidgetOfExactType<Offstage>()?.offstage == true) {
      return false;
    }
    if (context.findAncestorWidgetOfExactType<ExcludeFocus>()?.excluding ==
        true) {
      return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_entryFocusIsEligible && LineupTheme.of(context).androidTv) {
        _searchFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _revealGeneration++;
    _rosterScroll.dispose();
    _backFocus.dispose();
    _primaryFocus.dispose();
    for (final node in _rowScopes.values) {
      node.dispose();
    }
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SetupReviewStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFilter != widget.initialFilter) {
      _filter = widget.initialFilter;
    }
    if (oldWidget.initialSearch != widget.initialSearch &&
        _search.text != widget.initialSearch) {
      _search.value = TextEditingValue(
        text: widget.initialSearch,
        selection: TextSelection.collapsed(offset: widget.initialSearch.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final review = widget.review;
    final noChanges = !review.counts.hasChanges;
    final body = SetupStage(
      footer: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: LineupTheme.of(context).androidTv ? _footerKey : null,
        child: SetupFooter(
          configuration: true,
          leading: [
            TextButton(
              key: const ValueKey('back-to-configure'),
              focusNode: _backFocus,
              onPressed: widget.onBack,
              child: const Text('Back to configure'),
            ),
          ],
          summary: LineupTheme.of(context).androidTv && _rosterFocused
              ? Text(
                  'Press right on any channel to jump here',
                  key: const ValueKey('review-footer-hint'),
                  style: Theme.of(context).textTheme.bodyMedium!
                      .copyWith(color: LineupTheme.of(context).mutedText),
                )
              : const SizedBox.shrink(),
          trailing: noChanges
              ? FilledButton(
                  focusNode: _primaryFocus,
                  onPressed: widget.onViewLineup,
                  child: Text(
                    LineupTheme.of(context).androidTv
                        ? 'Open guide'
                        : 'View lineup',
                  ),
                )
              : FilledButton(
                  key: const ValueKey('apply-reviewed-lineup'),
                  focusNode: _primaryFocus,
                  onPressed: _primaryEnabled ? widget.onApply : null,
                  child: Text(_applyLabel(review.mode, _firstSetup)),
                ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final intro = <Widget>[
            if (widget.notice != null &&
                widget.notice != 'Updating review…') ...[
              LineupNotice(message: widget.notice!),
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
            _reviewOverview(),
            if (_missingSources.isNotEmpty &&
                !LineupTheme.of(context).androidTv) ...[
              const SizedBox(height: 16),
              _missingSourceReview(),
            ],
            const SizedBox(height: 24),
          ];
          final orderedIntro = [
            for (final child in intro)
              FocusTraversalOrder(
                order: const NumericFocusOrder(-1),
                child: child,
              ),
          ];
          if (LineupTheme.of(context).androidTv) {
            return _roster(leading: orderedIntro, includeRemoval: true);
          }
          if (constraints.maxHeight < 650 ||
              MediaQuery.textScalerOf(context).scale(1) >= 1.5) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _roster(leading: orderedIntro)),
                if (review.counts.removed > 0)
                  _removalNotice(review.counts.removed),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...orderedIntro,
              Expanded(child: _roster()),
              if (review.counts.removed > 0)
                _removalNotice(review.counts.removed),
            ],
          );
        },
      ),
    );
    return LineupTheme.of(context).androidTv
        ? FocusTraversalGroup(
            policy: SetupVerticalTraversalPolicy(),
            child: body,
          )
        : body;
  }

  List<Channel> get _missingSources =>
      widget.review.mode == ChannelBuildMode.merge
      ? widget.review.plan.unmatchedGenerated
            .where(widget.isGeneratedSourceConfirmedGone)
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
                      selected: {
                        widget.review.removeSourceIds.contains(channel.id),
                      },
                      onSelectionChanged: (selected) =>
                          widget.onRemovalChanged(channel.id, selected.single),
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
                child: LineupToggleSurface(
                  child: CheckboxListTile(
                    key: const ValueKey('channel-setup-replace-confirmation'),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    value: widget.removalConfirmed,
                    title: const Text('I understand'),
                    onChanged: (value) =>
                        widget.onRemovalConfirmationChanged(value == true),
                  ),
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
              selected: {widget.review.mode},
              onSelectionChanged: (selection) =>
                  widget.onModeChanged(selection.single),
            ),
      ),
      const SizedBox(height: 8),
      Text(
        widget.notice == 'Updating review…'
            ? widget.notice!
            : _modeDescription(widget.review.mode),
        style: TextStyle(
          color: LineupTheme.of(context).secondaryText,
          fontSize: 18,
          height: 1.4,
        ),
      ),
    ],
  );

  Widget _reviewOverview() {
    final review = widget.review;
    final roles = LineupTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final finalCount = review.finalChannels.length;
    final generated = _finalGeneratedCounts(review.finalChannels);
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
    final supportingStyle = currentStyle;
    final total = _firstSetup
        ? Text('$finalCount channels ready to create', style: totalStyle)
        : Semantics(
            label: '${review.base.length} current to $finalCount final',
            child: ExcludeSemantics(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 14,
                children: [
                  Text('${review.base.length} current', style: currentStyle),
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
        _filterChip(SetupReviewFilter.unchanged, review.counts.unchanged),
        _filterChip(SetupReviewFilter.updated, review.counts.updated),
        _filterChip(SetupReviewFilter.added, review.counts.added),
        _filterChip(SetupReviewFilter.removed, review.counts.removed),
      ],
    );
    final sourceCounts = [
      for (final strategy in widget.sourceOrder)
        if ((generated.byStrategy[strategy] ?? 0) > 0)
          '${builderStrategyLabels[strategy]} ${generated.byStrategy[strategy]}',
      if (generated.other > 0) 'Other generated ${generated.other}',
    ];
    return DecoratedBox(
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
                    if (!_firstSetup) ...[const SizedBox(height: 12), filters],
                  ],
                );
              },
            ),
            if (!_firstSetup) ...[
              const SizedBox(height: 24),
              Text(
                'Changes in this review${review.counts.removed > 0 ? ' · Includes channels being removed' : ''}',
                style: supportingStyle,
              ),
              const SizedBox(height: 12),
              if (review.entries.isNotEmpty)
                Semantics(
                  label:
                      '${review.counts.unchanged} unchanged, ${review.counts.updated} updated, ${review.counts.added} added, ${review.counts.removed} removed. ${review.entries.length} review entries including outgoing channels.',
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        _segment(
                          review.counts.unchanged,
                          roles.mutedText,
                          height: 14,
                        ),
                        _segment(
                          review.counts.updated,
                          roles.secondaryText,
                          height: 14,
                        ),
                        _segment(
                          review.counts.added,
                          roles.progressFill,
                          height: 14,
                        ),
                        _segment(
                          review.counts.removed,
                          Theme.of(context).colorScheme.error,
                          height: 14,
                        ),
                      ],
                    ),
                  ),
                ),
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
            const SizedBox(height: 24),
            Divider(height: 1, color: roles.subtleBorder),
            const SizedBox(height: 16),
            Text(
              'By source: ${sourceCounts.join(' · ')}',
              style: supportingStyle,
            ),
            if (review.mode == ChannelBuildMode.append &&
                review.plan.existingSkipped > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${review.plan.existingSkipped} already in your lineup',
                  key: const ValueKey('existing-sources-skipped'),
                  style: supportingStyle,
                ),
              ),
            if (review.base.any((channel) => channel.builderKey == null))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${review.base.where((channel) => channel.builderKey == null).length} custom channels will be kept.',
                  style: supportingStyle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _segment(int count, Color color, {required double height}) =>
      count == 0
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
      final strategy = widget
          .review
          .strategyBySource[canonicalSourceIdentity(channel.source)];
      if (strategy == null) {
        other++;
      } else {
        byStrategy.update(strategy, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    return (byStrategy: byStrategy, other: other);
  }

  Widget _filterChip(SetupReviewFilter filter, int count) {
    final roles = LineupTheme.of(context);
    final selected = _filter == filter;
    final swatchColor = count == 0
        ? roles.subtleBorder
        : switch (filter) {
            SetupReviewFilter.unchanged => roles.mutedText,
            SetupReviewFilter.updated => roles.secondaryText,
            SetupReviewFilter.added => roles.progressFill,
            SetupReviewFilter.removed => Theme.of(context).colorScheme.error,
            SetupReviewFilter.all => roles.mutedText,
          };
    return Semantics(
      selected: selected,
      child: TextButton(
        onPressed: () {
          setState(() => _filter = filter);
          widget.onFilterChanged(filter);
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 10, height: 10, color: swatchColor),
            const SizedBox(width: 10),
            Text('$count ${_capitalized(filter.name)}'),
          ],
        ),
      ),
    );
  }

  Widget _roster({
    List<Widget> leading = const [],
    bool includeRemoval = false,
  }) {
    final review = widget.review;
    final roles = LineupTheme.of(context);
    final textStyle = Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: roles.secondaryText, fontSize: 18, height: 1.4);
    final searchStyle = Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: roles.primaryText, fontSize: 18, height: 1.4);
    final query = _search.text.trim().toLowerCase();
    final entries = _visibleEntries;
    final filtered = _filter != SetupReviewFilter.all;
    return LineupCompactControls(
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) {
          if (_rosterFocused != focused) {
            setState(() => _rosterFocused = focused);
          }
        },
        child: CustomScrollView(
          controller: _rosterScroll,
          key: const ValueKey('channel-setup-review-roster'),
          slivers: [
            if (leading.isNotEmpty) SliverList.list(children: leading),
            SliverList.list(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: FocusTraversalOrder(
                        order: const NumericFocusOrder(0),
                        child: LineupTextFieldActivation(
                          focusNode: _searchFocus,
                          builder: (fieldContext, fieldFocus, finishEditing) =>
                              TextField(
                                onEditingComplete: finishEditing,
                                focusNode: fieldFocus,
                                key: const ValueKey(
                                  'channel-setup-review-search',
                                ),
                                controller: _search,
                                style: searchStyle.copyWith(
                                  color: LineupTheme.of(fieldContext)
                                      .primaryText,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Search channels by name or number',
                                  hintStyle: searchStyle.copyWith(
                                    color: LineupTheme.of(fieldContext)
                                        .primaryText,
                                  ),
                                ),
                                onChanged: (value) {
                                  setState(() {});
                                  widget.onSearchChanged(value);
                                },
                              ),
                        ),
                      ),
                    ),
                    if (!_firstSetup) ...[
                      const SizedBox(width: 12),
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(0),
                        child: TextButton(
                          key: const ValueKey('review-show-all'),
                          onPressed: () {
                            setState(() => _filter = SetupReviewFilter.all);
                            widget.onFilterChanged(SetupReviewFilter.all);
                          },
                          child: const Text('Show all'),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  filtered
                      ? '${_capitalized(_filter.name)} · ${entries.length} matching ${entries.length == 1 ? 'channel' : 'channels'}'
                      : '${entries.length} of ${review.entries.length} review entries',
                  style: textStyle,
                ),
                const SizedBox(height: 12),
                _rosterHeader(),
              ],
            ),
            if (entries.isEmpty)
              SliverToBoxAdapter(child: _emptyRoster(query, filtered))
            else
              SliverList.builder(
                itemCount: entries.length,
                itemBuilder: (_, index) => KeyedSubtree(
                  key: ValueKey(entries[index].channel.id),
                  child: _reviewRow(entries[index], index),
                ),
                findChildIndexCallback: (key) {
                  final index = entries.indexWhere(
                    (entry) => ValueKey(entry.channel.id) == key,
                  );
                  return index < 0 ? null : index;
                },
              ),
            if (includeRemoval && _missingSources.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: FocusTraversalOrder(
                    order: NumericFocusOrder(review.entries.length + .5),
                    child: _missingSourceReview(),
                  ),
                ),
              ),
            if (includeRemoval && review.counts.removed > 0)
              SliverToBoxAdapter(
                child: FocusTraversalOrder(
                  order: NumericFocusOrder(review.entries.length + 1),
                  child: _removalNotice(review.counts.removed),
                ),
              ),
          ],
        ),
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
    final changeWidth = _reviewChangeWidth();
    return DecoratedBox(
      key: const ValueKey('review-roster-header'),
      decoration: BoxDecoration(color: roles.primarySurface),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 52, 8),
        child: Row(
          children: [
            SizedBox(width: 80, child: Text('No.', style: headerStyle)),
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
            if (filtered) {
              _filter = SetupReviewFilter.all;
              widget.onFilterChanged(SetupReviewFilter.all);
            }
            if (query.isNotEmpty) widget.onSearchChanged('');
          }),
          child: Text(query.isNotEmpty ? 'Clear search' : 'Show all'),
        ),
      ],
    ),
  );

  Widget _reviewRow(SetupReviewEntry entry, int index) {
    if (!LineupTheme.of(context).androidTv) {
      return _reviewRowContent(context, entry);
    }
    return FocusTraversalOrder(
      order: NumericFocusOrder(index + 1),
      child: Focus(
        focusNode: _rowScopes.putIfAbsent(
          entry.channel.id,
          () => FocusNode(debugLabel: 'Review row ${entry.channel.id}'),
        ),
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, event) => _rowKey(entry.channel.id, event),
        onFocusChange: (focused) {
          if (focused) _rememberRow(entry.channel.id);
        },
        child: LineupRowSurface(
          selected: false,
          child: Builder(
            builder: (context) => _reviewRowContent(context, entry),
          ),
        ),
      ),
    );
  }

  Widget _reviewRowContent(BuildContext context, SetupReviewEntry entry) {
    final roles = LineupTheme.of(context);
    final focusedTv =
        roles.androidTv &&
        LineupFocusScope.visible(context, Focus.of(context).hasFocus);
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
        SetupReviewKind.unchanged => roles.mutedText,
        SetupReviewKind.updated => roles.secondaryText,
        SetupReviewKind.added => roles.secondaryText,
        SetupReviewKind.removed =>
          focusedTv ? roles.primaryText : Theme.of(context).colorScheme.error,
      },
    );
    final changeWidth = _reviewChangeWidth();
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text('${entry.channel.number}', style: metaStyle),
        ),
        Expanded(flex: 60, child: Text(entry.channel.name, style: nameStyle)),
        Expanded(
          flex: 16,
          child: Text(
            widget.sourceLabel(entry.channel.source),
            style: metaStyle,
          ),
        ),
        Expanded(
          flex: 16,
          child: Text(_playbackLabel(entry.channel), style: metaStyle),
        ),
        SizedBox(
          width: changeWidth,
          child: Text(
            switch (entry.kind) {
              SetupReviewKind.added => '+ Added',
              SetupReviewKind.updated => '• Updated',
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
        border: Border(bottom: BorderSide(color: roles.subtleBorder)),
      ),
      child: entry.kind == SetupReviewKind.updated && changes.isNotEmpty
          ? ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
              title: content,
              childrenPadding: const EdgeInsets.fromLTRB(92, 0, 12, 16),
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
          : Focus(
              canRequestFocus: roles.androidTv,
              skipTraversal: !roles.androidTv,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 52, 16),
                child: content,
              ),
            ),
    );
  }

  List<String> _changedFields(Channel? before, Channel after) {
    if (before == null) return const [];
    return [
      if (before.name != after.name) 'Name: ${before.name} → ${after.name}',
      if (before.number != after.number)
        'Number: ${before.number} → ${after.number}',
      if (!canonicalSourceEquals(before.source, after.source))
        'Source: ${widget.sourceLabel(before.source)} → ${widget.sourceLabel(after.source)}',
      if (before.playbackMode != after.playbackMode ||
          before.blockSize != after.blockSize ||
          before.includeSpecials != after.includeSpecials)
        'Playback: ${_playbackLabel(before)} → ${_playbackLabel(after)}',
    ];
  }
}

String _applyLabel(ChannelBuildMode mode, bool firstSetup) => switch (mode) {
  ChannelBuildMode.replace =>
    firstSetup ? 'Create lineup' : 'Replace generated channels',
  ChannelBuildMode.append => 'Add channels',
  ChannelBuildMode.merge => 'Apply changes',
};

String _modeDescription(ChannelBuildMode mode) => switch (mode) {
  ChannelBuildMode.merge =>
    'Update matching generated channels, add new ones, and keep the rest.',
  ChannelBuildMode.replace => 'Replace all generated channels with this selection. Custom channels will be kept.',
  ChannelBuildMode.append => 'Keep your existing lineup and add channels whose sources are not already in it.',
};

String _playbackLabel(Channel channel) => switch (channel.playbackMode) {
  PlaybackMode.shuffle => 'Shuffle',
  PlaybackMode.sequential => 'In order',
  PlaybackMode.block =>
    'Mini-marathons · ${channel.blockSize ?? 3}${channel.includeSpecials ? ' · specials' : ''}',
};

String _capitalized(String value) =>
    '${value[0].toUpperCase()}${value.substring(1)}';
