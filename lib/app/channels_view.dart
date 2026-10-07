import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../channels/channel.dart';
import '../playback/player_coordinator.dart';
import '../ui/app_theme.dart';
import '../ui/app_ui.dart';
import 'channel_studio_view.dart';
import 'lineup_controller.dart';

enum _DirectoryFilter { all, custom, generated }

enum _DirectoryMode { normal, selection, reorder }

enum _RowAction { duplicate, delete }

class ChannelsView extends StatefulWidget {
  const ChannelsView({
    required this.controller,
    required this.player,
    required this.onOpenPlayer,
    required this.onOpenMenu,
    required this.menuFocusNode,
    this.focusNode,
    this.clock,
    super.key,
  });

  final LineupController controller;
  final PlayerCoordinator player;
  final VoidCallback onOpenPlayer;
  final LineupMenuCallback onOpenMenu;
  final FocusNode menuFocusNode;
  final FocusNode? focusNode;
  final DateTime Function()? clock;

  @override
  State<ChannelsView> createState() => ChannelsViewState();
}

class ChannelsViewState extends State<ChannelsView> {
  static const _maximumHealthLoads = 2;
  static const _maximumPendingHealth = 12;
  static const _maximumCachedHealth = 1000;
  Future<void>? _generateLineupEntry;
  String? _error;
  ChannelStudioMode? _studioMode;
  Channel? _studioChannel;
  String? _returnFocusId;
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'Search channels');
  _DirectoryFilter _filter = _DirectoryFilter.all;
  _DirectoryMode _mode = _DirectoryMode.normal;
  final Set<String> _selectedIds = {};
  bool _showSelected = false;
  bool _saving = false;
  List<Channel> _reorderBase = const [];
  List<String> _reorderIds = const [];
  final _openFocus = <String, FocusNode>{};
  Future<bool>? _leaveRequest;
  bool _focusPruneScheduled = false;
  bool _focusPruneNeedsRestore = false;
  final LinkedHashMap<String, _ChannelHealth> _health = LinkedHashMap();
  final Queue<({Channel channel, _ChannelHealthSignature signature})>
  _pendingHealth = Queue();
  final Map<String, _ChannelHealthSignature> _activeHealth = {};
  int _activeHealthLoads = 0;
  int _healthEpoch = 0;
  int? _healthContentGeneration;
  GlobalKey<ChannelStudioViewState> _studioKey =
      GlobalKey<ChannelStudioViewState>();

  bool get studioOpen => _studioOpen;

  bool get _studioOpen => _studioMode != null;
  ChannelStudioViewState? get _studio => _studioKey.currentState;

  void openNew() {
    if (_saving) return;
    setState(() {
      _studioKey = GlobalKey<ChannelStudioViewState>();
      _studioMode = ChannelStudioMode.createCustom;
      _studioChannel = null;
      _returnFocusId = null;
      _error = null;
    });
  }

  void _open(Channel channel) => setState(() {
    _studioKey = GlobalKey<ChannelStudioViewState>();
    _studioMode = channel.builderKey == null
        ? ChannelStudioMode.editCustom
        : ChannelStudioMode.inspectGenerated;
    _studioChannel = channel;
    _returnFocusId = channel.id;
    _error = null;
  });

  void _openDuplicate(Channel source) => setState(() {
    _studioKey = GlobalKey<ChannelStudioViewState>();
    _studioMode = ChannelStudioMode.duplicateCustom;
    _studioChannel = source;
    _returnFocusId = source.id;
    _error = null;
  });

  Future<bool> requestLeave([String? focusId]) =>
      _leaveRequest ??= _requestLeave(focusId)
          .whenComplete(() => _leaveRequest = null);

  Future<bool> _requestLeave(String? focusId) async {
    if (!_studioOpen) return true;
    final studio = _studio;
    if (studio == null || studio.saving) return false;
    if (studio.dirty) {
      final discard =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Discard changes?'),
              content: const Text(
                'Your unsaved Channel Studio changes will be lost.',
              ),
              actions: [
                TextButton(
                  autofocus: true,
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Keep editing'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Discard changes'),
                ),
              ],
            ),
          ) ??
          false;
      if (!discard || !mounted) return false;
    }
    _showList(focusId ?? _returnFocusId);
    return true;
  }

  Future<void> closeStudio([String? focusId]) async {
    await requestLeave(focusId);
  }

  Future<void> _openGenerateLineupFromStudio() =>
      _generateLineupEntry ??= _enterGenerateLineupFromStudio().whenComplete(
        () => _generateLineupEntry = null,
      );

  Future<void> _enterGenerateLineupFromStudio() async {
    if (!_studioOpen) return;
    final studio = _studio;
    if (studio == null || studio.saving) return;
    if (studio.dirty) {
      final discard =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Open Generate lineup?'),
              content: const Text(
                'Your unsaved Studio draft cannot be carried into Generate lineup. Existing custom channels remain protected while you review the proposed roster.',
              ),
              actions: [
                TextButton(
                  autofocus: true,
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Keep editing'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Discard draft and continue'),
                ),
              ],
            ),
          ) ??
          false;
      if (!discard || !mounted) return;
    }
    _showList(_returnFocusId);
    await widget.controller.enterChannelSetup();
  }

  void _showList(String? focusId) {
    setState(() {
      _studioMode = null;
      _studioChannel = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (_openFocus[focusId] ?? widget.focusNode)?.requestFocus();
    });
  }

  @override
  void dispose() {
    _healthEpoch++;
    _search.dispose();
    _searchFocus.dispose();
    for (final node in _openFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_studioMode case final mode?) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(closeStudio());
        },
        child: ChannelStudioView(
          key: _studioKey,
          controller: widget.controller,
          mode: mode,
          channel: _studioChannel,
          onBack: closeStudio,
          onOpenMenu: widget.onOpenMenu,
          menuFocusNode: widget.menuFocusNode,
          onSaved: (id) => _returnFocusId = id,
          onDuplicate: _openDuplicate,
          onOpenChannel: (channel) async {
            if (await requestLeave(channel.id) && mounted) _open(channel);
          },
          onOpenGenerateLineup: _openGenerateLineupFromStudio,
          clock: widget.clock,
          onTune: (id) async {
            final success = await widget.player.tune(id);
            if (success) widget.onOpenPlayer();
            return success;
          },
        ),
      );
    }

    final channels = [...widget.controller.channels]
      ..sort((left, right) => left.number.compareTo(right.number));
    final liveIds = channels.map((channel) => channel.id).toSet();
    _selectedIds.removeWhere((id) => !liveIds.contains(id));
    final query = _search.text.trim().toLowerCase();
    final matching = channels
        .where((channel) {
          final ownershipMatches = switch (_filter) {
            _DirectoryFilter.all => true,
            _DirectoryFilter.custom => channel.builderKey == null,
            _DirectoryFilter.generated => channel.builderKey != null,
          };
          return ownershipMatches &&
              (query.isEmpty ||
                  channel.name.toLowerCase().contains(query) ||
                  channel.number.toString().contains(query));
        })
        .toList(growable: false);
    final visible = _showSelected
        ? channels
              .where((channel) => _selectedIds.contains(channel.id))
              .toList(growable: false)
        : matching;
    if (_healthContentGeneration != widget.controller.contentGeneration) {
      _healthContentGeneration = widget.controller.contentGeneration;
      _healthEpoch++;
      _health.clear();
      _pendingHealth.clear();
    }
    _pruneHealth(liveIds);
    _scheduleFocusPrune(liveIds);
    final headingStyle = LineupTypography.pageTitle.copyWith(
      color: LineupTheme.of(context).primaryText,
    );
    final countStyle = LineupTypography.body.copyWith(
      fontSize: _directorySize(28, 24),
      color: LineupTheme.of(context).secondaryText,
    );
    final bodyStyle = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(fontSize: 18);

    return LineupPage(
      title: 'Channels',
      showTitle: false,
      topBar: LineupTopBar(
        menuKey: const Key('channels-app-menu'),
        menuFocusNode: widget.menuFocusNode,
        onOpenMenu: widget.onOpenMenu,
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: _directorySize(24, 16)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            _mode == _DirectoryMode.reorder
                                ? 'Reorder channels'
                                : 'Channels',
                            style: headingStyle,
                          ),
                          SizedBox(width: 12),
                          Text('${channels.length}', style: countStyle),
                        ],
                      ),
                      SizedBox(height: 6),
                      Text(
                        _mode == _DirectoryMode.reorder
                            ? 'Channels appear in number order. Reordering changes channel numbers.'
                            : 'Your lineup, in channel order.',
                        style: bodyStyle?.copyWith(
                          color: LineupTheme.of(context).secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_mode == _DirectoryMode.normal && channels.isNotEmpty)
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: [
                          OutlinedButton(
                            focusNode: widget.focusNode,
                            onPressed: _saving
                                ? null
                                : widget.controller.enterChannelSetup,
                            child: const Text('Generate lineup'),
                          ),
                          FilledButton(
                            onPressed: _saving ? null : openNew,
                            child: const Text('Add a custom channel'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_error != null) ...[
            LineupNotice(message: _error!),
            SizedBox(height: 12),
          ],
          if (channels.isNotEmpty) ...[
            _directoryControls(matching),
            SizedBox(height: 20),
            DefaultTextStyle.merge(
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 18,
                color: LineupTheme.of(context).secondaryText,
              ),
              child: _mode == _DirectoryMode.reorder
                  ? _reorderColumns(
                      drag: const SizedBox.shrink(),
                      number: const Text('No.'),
                      name: const Text('Channel'),
                      source: const Text('Source'),
                      playback: const Text('Playback'),
                      action: const Text('Move'),
                      heading: true,
                    )
                  : _directoryColumns(
                      leading: _mode == _DirectoryMode.selection
                          ? const SizedBox.shrink()
                          : null,
                      number: const Text('No.'),
                      name: const Text('Channel'),
                      source: const Text('Source'),
                      playback: const Text('Playback'),
                      type: const Text('Type'),
                      action: const SizedBox.shrink(),
                      heading: true,
                    ),
            ),
            const Divider(height: 1),
          ],
          Expanded(
            child: channels.isEmpty
                ? LineupEmptyState(
                    icon: Icons.view_list,
                    title: 'Build your first channel',
                    message: 'Generate a lineup from Plex or create one custom channel.',
                    action: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        FilledButton.icon(
                          focusNode: widget.focusNode,
                          onPressed: _saving
                              ? null
                              : widget.controller.enterChannelSetup,
                          icon: const Icon(Icons.auto_awesome_outlined),
                          label: const Text('Generate lineup'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _saving ? null : openNew,
                          icon: const Icon(Icons.add),
                          label: const Text('Create a custom channel'),
                        ),
                      ],
                    ),
                  )
                : _mode == _DirectoryMode.reorder
                ? _reorderList(channels)
                : visible.isEmpty
                ? LineupEmptyState(
                    icon: Icons.search_off,
                    title: _showSelected
                        ? 'No channels selected'
                        : 'No matching channels',
                    message: _showSelected
                        ? 'Return to results and select channels to inspect.'
                        : 'Adjust the search or channel type.',
                  )
                : ListView.separated(
                    key: const PageStorageKey('channels-directory'),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final channel = visible[index];
                      _requestHealth(channel);
                      final rowNameStyle = Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                            fontSize: _directorySize(22, 16),
                            fontWeight: FontWeight.w500,
                          );
                      final rowSupportStyle = Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                            fontSize: 18,
                            color: LineupTheme.of(context).secondaryText,
                          );
                      final ownership = channel.builderKey == null
                          ? 'Custom'
                          : 'Generated';
                      final rowFocus = _openFocus.putIfAbsent(
                        channel.id,
                        () => FocusNode(debugLabel: 'Open ${channel.name}'),
                      );
                      rowFocus.debugLabel = 'Open ${channel.name}';
                      return LineupRowSurface(
                        selected: _selectedIds.contains(channel.id),
                        child: Material(
                          key: ValueKey('channel-row-${channel.id}'),
                          color: Colors.transparent,
                          child: Tooltip(
                            message: _mode == _DirectoryMode.selection
                                ? '${_selectedIds.contains(channel.id) ? 'Deselect' : 'Select'} ${channel.name}'
                                : 'Open ${channel.name}',
                            child: InkWell(
                              focusNode: rowFocus,
                              onTap: _saving
                                  ? null
                                  : _mode == _DirectoryMode.selection
                                  ? () => _toggleSelected(channel.id)
                                  : () => _open(channel),
                              child: _directoryColumns(
                                leading: _mode == _DirectoryMode.selection
                                    ? Checkbox(
                                        semanticLabel: 'Select ${channel.name}',
                                        value: _selectedIds.contains(
                                          channel.id,
                                        ),
                                        onChanged: _saving
                                            ? null
                                            : (_) =>
                                                  _toggleSelected(channel.id),
                                      )
                                    : null,
                                number: Text(
                                  '${channel.number}',
                                  style: rowSupportStyle,
                                ),
                                name: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(channel.name, style: rowNameStyle),
                                    if (_health[channel.id]?.issue == true)
                                      Text(
                                        'Schedule issue — open this channel to recover',
                                        style: rowSupportStyle?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                      ),
                                  ],
                                ),
                                source: Text(
                                  channelSourceLabel(
                                    channel.source,
                                    widget.controller,
                                  ),
                                  style: rowSupportStyle,
                                ),
                                playback: Text(
                                  channelRhythmLabel(
                                    channel.playbackMode,
                                    channel.blockSize,
                                  ),
                                  style: rowSupportStyle,
                                ),
                                type: Text(ownership, style: rowSupportStyle),
                                action: _mode == _DirectoryMode.selection
                                    ? const SizedBox.shrink()
                                    : PopupMenuButton<_RowAction>(
                                        enabled: !_saving,
                                        tooltip: 'Actions for ${channel.name}',
                                        padding: EdgeInsets.all(8),
                                        iconSize: 24,
                                        menuPadding: EdgeInsets.zero,
                                        onSelected: (action) =>
                                            switch (action) {
                                              _RowAction.duplicate =>
                                                _openDuplicate(channel),
                                              _RowAction.delete => _delete(
                                                channel,
                                              ),
                                            },
                                        itemBuilder: (_) => [
                                          if (channel.builderKey != null)
                                            PopupMenuItem(
                                              value: _RowAction.duplicate,
                                              height: 48,
                                              padding: EdgeInsets.zero,
                                              child: LineupDropdownMenuRow(
                                                selected: false,
                                                child: const Text(
                                                  'Duplicate as custom',
                                                ),
                                              ),
                                            ),
                                          PopupMenuItem(
                                            value: _RowAction.delete,
                                            height: 48,
                                            padding: EdgeInsets.zero,
                                            child: const LineupDropdownMenuRow(
                                              selected: false,
                                              child: Text('Delete…'),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _directoryColumns({
    required Widget number,
    required Widget name,
    required Widget source,
    required Widget playback,
    required Widget type,
    required Widget action,
    Widget? leading,
    bool heading = false,
  }) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final numberWidth = 52 * textScale;
    return ConstrainedBox(
      constraints: heading
          ? const BoxConstraints()
          : BoxConstraints(minHeight: _directorySize(80, 68)),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: (heading ? 8 : 10),
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              SizedBox(width: 36, child: leading),
              SizedBox(width: 16),
            ],
            SizedBox(width: numberWidth, child: number),
            SizedBox(width: 16),
            Expanded(flex: 4, child: name),
            SizedBox(width: 16),
            Expanded(flex: 2, child: source),
            SizedBox(width: 16),
            Expanded(flex: 2, child: playback),
            SizedBox(width: 16),
            Expanded(child: type),
            SizedBox(width: 16),
            SizedBox(width: 44, child: action),
          ],
        ),
      ),
    );
  }

  Widget _reorderColumns({
    required Widget drag,
    required Widget number,
    required Widget name,
    required Widget source,
    required Widget playback,
    required Widget action,
    bool heading = false,
  }) {
    final textScaler = MediaQuery.textScalerOf(context);
    final textScale = textScaler.scale(1);
    final numberWidth = 76 * textScale;
    final moveToText = TextPainter(
      text: TextSpan(
        text: 'Move to…',
        style: LineupTypography.button.copyWith(fontSize: 16),
      ),
      textDirection: Directionality.of(context),
      textScaler: textScaler,
    )..layout();
    // Keep two 44px arrows and the compact label on one line while allowing
    // the active font and accessibility text scale to determine its width.
    final actionWidth = (88 + moveToText.width + 40 + 16)
        .clamp(216, 336)
        .toDouble();
    return DecoratedBox(
      decoration: heading
          ? const BoxDecoration()
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(color: LineupTheme.of(context).subtleBorder),
              ),
            ),
      child: ConstrainedBox(
        constraints: heading
            ? const BoxConstraints()
            : BoxConstraints(minHeight: _directorySize(80, 68)),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: (heading ? 8 : 10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(width: 36, child: drag),
              SizedBox(width: 16),
              SizedBox(width: numberWidth, child: number),
              SizedBox(width: 16),
              Expanded(flex: 4, child: name),
              SizedBox(width: 16),
              Expanded(flex: 2, child: source),
              SizedBox(width: 16),
              Expanded(flex: 2, child: playback),
              SizedBox(width: 16),
              SizedBox(
                width: actionWidth,
                child: LineupCompactControls(child: action),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _directorySize(double expanded, double compact) =>
      LineupLayout.isCompactWidth(MediaQuery.sizeOf(context).width)
      ? compact
      : expanded;

  TextStyle _channelBodyStyle(BuildContext context) {
    return Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 18) ??
        TextStyle(fontSize: 18);
  }

  Widget _directoryToolbar() {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final filters = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: LineupLayout.isCompactWidth(MediaQuery.sizeOf(context).width)
            ? 0
            : 48,
      ),
      child: LineupSegmentedControl<_DirectoryFilter>(
        segments: const [
          ButtonSegment(value: _DirectoryFilter.all, label: Text('All')),
          ButtonSegment(value: _DirectoryFilter.custom, label: Text('Custom')),
          ButtonSegment(
            value: _DirectoryFilter.generated,
            label: Text('Generated'),
          ),
        ],
        selected: {_filter},
        showSelectedIcon: false,
        onSelectionChanged: _saving
            ? null
            : (value) => setState(() {
                _filter = value.single;
                _showSelected = false;
              }),
      ),
    );
    final actions = [
      OutlinedButton(
        onPressed: _saving
            ? null
            : () => setState(() {
                _mode = _DirectoryMode.selection;
                _selectedIds.clear();
              }),
        child: const Text('Select'),
      ),
      OutlinedButton(
        onPressed: _saving ? null : _beginReorder,
        child: const Text('Reorder channels'),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final search = TextField(
          key: const Key('channels-search'),
          enabled: !_saving,
          controller: _search,
          focusNode: _searchFocus,
          style: _channelBodyStyle(context),
          decoration: InputDecoration(hintText: 'Search by name or number'),
          onChanged: (_) => setState(() {}),
        );
        final wide = constraints.maxWidth >= 1200 && textScale < 1.4;
        if (wide) {
          return Row(
            children: [
              Expanded(child: search),
              SizedBox(width: 8),
              filters,
              SizedBox(width: 8),
              if (_mode == _DirectoryMode.normal) ...[
                const SizedBox(height: 28, child: VerticalDivider(width: 16)),
                ...actions,
              ],
            ],
          );
        }
        final desiredWidth = constraints.maxWidth - 530 * textScale;
        final minimumSearchWidth = 280;
        final searchWidth = constraints.maxWidth < minimumSearchWidth
            ? constraints.maxWidth
            : desiredWidth
                  .clamp(minimumSearchWidth, constraints.maxWidth)
                  .toDouble();
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(width: searchWidth, child: search),
            filters,
            if (_mode == _DirectoryMode.normal) ...[
              const SizedBox(height: 28, child: VerticalDivider(width: 16)),
              ...actions,
            ],
          ],
        );
      },
    );
  }

  Widget _directoryControls(List<Channel> matching) {
    if (_mode == _DirectoryMode.reorder) {
      final changed = !_sameOrder(
        _reorderBase.map((channel) => channel.id),
        _reorderIds,
      );
      return LineupCompactControls(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton(
                    onPressed: _saving ? null : _cancelReorder,
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: changed && !_saving ? _saveOrder : null,
                    child: Text(_saving ? 'Saving…' : 'Save order'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return LineupCompactControls(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_showSelected)
            Text('Selected channels', style: _channelBodyStyle(context))
          else
            _directoryToolbar(),
          if (_mode == _DirectoryMode.selection) ...[
            SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final leading = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton(
                      onPressed: _saving || _selectedIds.isEmpty
                          ? null
                          : () => setState(() => _showSelected = true),
                      child: Text(
                        _showSelected
                            ? '${_selectedIds.length} selected'
                            : _selectionSummary(matching),
                      ),
                    ),
                    if (_showSelected)
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => setState(() => _showSelected = false),
                        child: const Text('Back to results'),
                      ),
                    if (!_showSelected)
                      TextButton(
                        onPressed: _saving || matching.isEmpty
                            ? null
                            : () => setState(
                                () => _selectedIds.addAll(
                                  matching.map((channel) => channel.id),
                                ),
                              ),
                        child: const Text('Select all matching'),
                      ),
                    TextButton(
                      onPressed: _saving || _selectedIds.isEmpty
                          ? null
                          : () => setState(_selectedIds.clear),
                      child: const Text('Clear selection'),
                    ),
                  ],
                );
                final trailing = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton(
                      onPressed: _saving ? null : _cancelSelection,
                      child: const Text('Cancel'),
                    ),
                    OutlinedButton(
                      onPressed: _selectedIds.isEmpty || _saving
                          ? null
                          : _deleteSelected,
                      child: Text(_saving ? 'Deleting…' : 'Delete selected'),
                    ),
                  ],
                );
                if (constraints.maxWidth < 760) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      leading,
                      SizedBox(height: 8),
                      Align(alignment: Alignment.centerRight, child: trailing),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: leading),
                    SizedBox(width: 12),
                    trailing,
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  String _selectionSummary(List<Channel> matching) {
    final matchingIds = matching.map((channel) => channel.id).toSet();
    final outside = _selectedIds.difference(matchingIds).length;
    return '${_selectedIds.length} selected${outside == 0 ? '' : ' · $outside outside this view'}';
  }

  void _toggleSelected(String id) => setState(() {
    _selectedIds.contains(id) ? _selectedIds.remove(id) : _selectedIds.add(id);
  });

  void _cancelSelection() => setState(() {
    _mode = _DirectoryMode.normal;
    _selectedIds.clear();
    _showSelected = false;
  });

  Future<bool> _confirmChannelDeletion(
    List<Channel> channels,
    String confirmLabel,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => _ChannelDeletionDialog(
          channels: channels,
          confirmLabel: confirmLabel,
        ),
      ) ??
      false;

  Future<void> _deleteSelected() async {
    if (_saving || _selectedIds.isEmpty) return;
    var selected = widget.controller.channels
        .where((channel) => _selectedIds.contains(channel.id))
        .toList(growable: false);
    final confirmed = await _confirmChannelDeletion(
      selected,
      'Delete ${selected.length} ${selected.length == 1 ? 'channel' : 'channels'}',
    );
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.controller.deleteChannels(expectedChannels: selected);
      if (!mounted) return;
      _cancelSelection();
      setState(() => _error = null);
      _focusAfterDeletion(selected.first.number);
    } on ChannelStateConflictException {
      if (!mounted) return;
      selected = widget.controller.channels
          .where((channel) => _selectedIds.contains(channel.id))
          .toList(growable: false);
      setState(
        () => _error = selected.isEmpty
            ? 'The selected channels already changed or were removed.'
            : 'The selected channels changed. Review them and confirm deletion again.',
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'The channels could not be deleted. No lineup changes were saved.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _beginReorder() => setState(() {
    _mode = _DirectoryMode.reorder;
    _reorderBase = [...widget.controller.channels]
      ..sort((a, b) => a.number.compareTo(b.number));
    _reorderIds = _reorderBase.map((channel) => channel.id).toList();
  });

  void _cancelReorder() => setState(() {
    _mode = _DirectoryMode.normal;
    _reorderBase = const [];
    _reorderIds = const [];
  });

  Widget _reorderList(List<Channel> current) {
    final byId = {for (final channel in current) channel.id: channel};
    final positions = _reorderBase.map((channel) => channel.number).toList()
      ..sort();
    return ReorderableListView.builder(
      key: const Key('channels-reorder-list'),
      buildDefaultDragHandles: false,
      itemCount: _reorderIds.length,
      onReorderItem: _saving
          ? (_, _) {}
          : (from, to) => setState(() {
              final id = _reorderIds.removeAt(from);
              _reorderIds.insert(to, id);
            }),
      itemBuilder: (context, index) {
        final channel =
            byId[_reorderIds[index]] ??
            _reorderBase.firstWhere((item) => item.id == _reorderIds[index]);
        final nextNumber = positions[index];
        final rowNameStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontSize: _directorySize(22, 16),
          fontWeight: FontWeight.w500,
        );
        final rowSupportStyle = Theme.of(context).textTheme.bodyMedium
            ?.copyWith(
              fontSize: 18,
              color: LineupTheme.of(context).secondaryText,
            );
        final moves = Wrap(
          alignment: WrapAlignment.end,
          children: [
            lineupArrowButton(
              tooltip: 'Move ${channel.name} up',
              onPressed: _saving || index == 0
                  ? null
                  : () => _moveReorder(index, index - 1),
              icon: Icons.arrow_upward,
            ),
            lineupArrowButton(
              tooltip: 'Move ${channel.name} down',
              onPressed: _saving || index == _reorderIds.length - 1
                  ? null
                  : () => _moveReorder(index, index + 1),
              icon: Icons.arrow_downward,
            ),
            TextButton(
              onPressed: _saving ? null : () => _moveTo(index, byId),
              child: const Text('Move to…'),
            ),
          ],
        );
        return KeyedSubtree(
          key: ValueKey('reorder-${channel.id}'),
          child: _reorderColumns(
            drag: ReorderableDragStartListener(
              enabled: !_saving,
              index: index,
              child: Icon(Icons.drag_handle, size: 24),
            ),
            number: Text(
              channel.number == nextNumber
                  ? '${channel.number}'
                  : '${channel.number} → $nextNumber',
              style: rowSupportStyle?.copyWith(
                fontFamilyFallback: const ['Arial'],
              ),
            ),
            name: Text(channel.name, style: rowNameStyle, softWrap: true),
            source: Text(
              channelSourceLabel(channel.source, widget.controller),
              style: rowSupportStyle,
            ),
            playback: Text(
              channelRhythmLabel(channel.playbackMode, channel.blockSize),
              style: rowSupportStyle,
            ),
            action: moves,
          ),
        );
      },
    );
  }

  void _moveReorder(int from, int to) => setState(() {
    final id = _reorderIds.removeAt(from);
    _reorderIds.insert(to, id);
  });

  Future<void> _moveTo(int from, Map<String, Channel> byId) async {
    final movedId = _reorderIds[from];
    final target = await showDialog<({String id, bool after})>(
      context: context,
      builder: (context) => _MoveChannelDialog(
        channels: [
          for (final id in _reorderIds)
            if (id != movedId) ?byId[id],
        ],
      ),
    );
    if (target == null || !mounted) return;
    setState(() {
      final id = _reorderIds.removeAt(from);
      var index = _reorderIds.indexOf(target.id);
      if (target.after) index++;
      _reorderIds.insert(index, id);
    });
  }

  Future<void> _saveOrder() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.controller.reorderChannels(
        expectedLineup: _reorderBase,
        orderedChannelIds: _reorderIds,
      );
      if (!mounted) return;
      _cancelReorder();
      setState(() => _error = null);
    } on ChannelStateConflictException {
      if (mounted) {
        final current = [...widget.controller.channels]
          ..sort((a, b) => a.number.compareTo(b.number));
        final liveIds = current.map((channel) => channel.id).toSet();
        setState(() {
          _reorderBase = current;
          _reorderIds = [
            ..._reorderIds.where(liveIds.contains),
            ...current
                .map((channel) => channel.id)
                .where((id) => !_reorderIds.contains(id)),
          ];
          _error = 'The lineup changed. Review the refreshed order before saving again.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The order could not be saved. No channel numbers were changed.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _sameOrder(Iterable<String> left, Iterable<String> right) {
    final leftValues = left.toList();
    final rightValues = right.toList();
    if (leftValues.length != rightValues.length) return false;
    for (var index = 0; index < leftValues.length; index++) {
      if (leftValues[index] != rightValues[index]) return false;
    }
    return true;
  }

  void _requestHealth(Channel channel) {
    final signature = _healthSignature(channel);
    final cached = _health[channel.id];
    if (cached?.signature == signature ||
        _activeHealth[channel.id] == signature ||
        _pendingHealth.any(
          (pending) =>
              pending.channel.id == channel.id &&
              pending.signature == signature,
        )) {
      return;
    }
    _pendingHealth.removeWhere((pending) => pending.channel.id == channel.id);
    if (_pendingHealth.length >= _maximumPendingHealth) {
      _pendingHealth.removeFirst();
    }
    _pendingHealth.add((channel: channel, signature: signature));
    WidgetsBinding.instance.addPostFrameCallback((_) => _pumpHealth());
  }

  void _pumpHealth() {
    if (!mounted) return;
    var blocked = 0;
    while (_activeHealthLoads < _maximumHealthLoads &&
        _pendingHealth.isNotEmpty) {
      final pending = _pendingHealth.removeFirst();
      final channel = pending.channel;
      if (_activeHealth.containsKey(channel.id)) {
        _pendingHealth.add(pending);
        blocked++;
        if (blocked >= _pendingHealth.length) break;
        continue;
      }
      blocked = 0;
      final epoch = _healthEpoch;
      final signature = pending.signature;
      final current = widget.controller.channels
          .where((item) => item.id == channel.id)
          .firstOrNull;
      if (current == null || _healthSignature(current) != signature) {
        if (current != null) _requestHealth(current);
        continue;
      }
      _activeHealthLoads++;
      _activeHealth[channel.id] = signature;
      widget.controller
          .loadScheduleFor(channel)
          .then(
            (_) => _finishHealth(channel.id, signature, false, epoch),
            onError: (_) => _finishHealth(channel.id, signature, true, epoch),
          );
    }
  }

  void _finishHealth(
    String id,
    _ChannelHealthSignature signature,
    bool issue,
    int epoch,
  ) {
    _activeHealthLoads--;
    if (_activeHealth[id] == signature) _activeHealth.remove(id);
    if (!mounted) return;
    final current = widget.controller.channels
        .where((channel) => channel.id == id)
        .firstOrNull;
    if (epoch == _healthEpoch &&
        current != null &&
        _healthSignature(current) == signature) {
      _health.remove(id);
      _health[id] = _ChannelHealth(signature, issue);
      while (_health.length > _maximumCachedHealth) {
        _health.remove(_health.keys.first);
      }
      setState(() {});
    } else if (current != null) {
      _requestHealth(current);
    }
    _pumpHealth();
  }

  _ChannelHealthSignature _healthSignature(Channel channel) => (
    contentGeneration: widget.controller.contentGeneration,
    channelRevision: widget.controller.channelRevision(channel.id),
  );

  void _pruneHealth(Set<String> liveIds) {
    _health.removeWhere((id, _) => !liveIds.contains(id));
    _pendingHealth.removeWhere(
      (pending) => !liveIds.contains(pending.channel.id),
    );
  }

  void _scheduleFocusPrune(Set<String> liveIds) {
    final staleIds = _openFocus.keys
        .where((id) => !liveIds.contains(id))
        .toList();
    if (staleIds.isEmpty) return;
    _focusPruneNeedsRestore |= staleIds.any(
      (id) => _openFocus[id]?.hasFocus ?? false,
    );
    if (_focusPruneScheduled) return;
    _focusPruneScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusPruneScheduled = false;
      if (!mounted) return;
      final currentIds = widget.controller.channels
          .map((channel) => channel.id)
          .toSet();
      final staleIds = _openFocus.keys
          .where((id) => !currentIds.contains(id))
          .toList();
      final restoreFocus = _focusPruneNeedsRestore;
      _focusPruneNeedsRestore = false;
      if (restoreFocus) {
        final survivingId = widget.controller.channels
            .map((channel) => channel.id)
            .where((id) => !staleIds.contains(id))
            .firstOrNull;
        (_openFocus[survivingId] ?? widget.focusNode)?.requestFocus();
        FocusManager.instance.applyFocusChangesIfNeeded();
      }
      for (final id in staleIds) {
        _openFocus.remove(id)?.dispose();
      }
    });
  }

  void _focusAfterDeletion(int number) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final remaining = [...widget.controller.channels]
        ..sort((a, b) => a.number.compareTo(b.number));
      final next =
          remaining.where((channel) => channel.number >= number).firstOrNull ??
          remaining.lastOrNull;
      (_openFocus[next?.id] ?? widget.focusNode)?.requestFocus();
    });
  }

  Future<void> _delete(Channel channel) async {
    if (_saving) return;
    final confirmed = await _confirmChannelDeletion([
      channel,
    ], 'Delete channel');
    if (!mounted) return;
    if (!confirmed) {
      _openFocus[channel.id]?.requestFocus();
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.controller.deleteChannels(expectedChannels: [channel]);
      if (!mounted) return;
      setState(() => _error = null);
      _focusAfterDeletion(channel.number);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error =
            'The channel could not be deleted. No lineup changes were saved.',
      );
      _openFocus[channel.id]?.requestFocus();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

typedef _ChannelHealthSignature = ({
  int contentGeneration,
  int channelRevision,
});

class _ChannelHealth {
  const _ChannelHealth(this.signature, this.issue);

  final _ChannelHealthSignature signature;
  final bool issue;
}

class _MoveChannelDialog extends StatefulWidget {
  const _MoveChannelDialog({required this.channels});

  final List<Channel> channels;

  @override
  State<_MoveChannelDialog> createState() => _MoveChannelDialogState();
}

class _MoveChannelDialogState extends State<_MoveChannelDialog> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final channels = widget.channels
        .where(
          (channel) =>
              query.isEmpty ||
              channel.name.toLowerCase().contains(query) ||
              channel.number.toString().contains(query),
        )
        .toList(growable: false);
    final size = MediaQuery.sizeOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);

    final contentWidth = (size.width - 128).clamp(0.0, 520).toDouble();
    final contentHeight = (size.height - viewInsets.vertical - 200)
        .clamp(0.0, 440)
        .toDouble();

    final searchDecoration = InputDecoration(hintText: 'Search channels');
    final dialog = AlertDialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      titlePadding: EdgeInsets.only(left: 24, top: 24, right: 24),
      contentPadding: EdgeInsets.fromLTRB(24, 16, 24, 24),
      actionsPadding: EdgeInsets.only(left: 24, right: 24, bottom: 24),
      buttonPadding: EdgeInsets.symmetric(horizontal: 8),
      actionsOverflowButtonSpacing: 8,
      title: const Text('Move channel'),
      content: SizedBox(
        width: contentWidth,
        height: contentHeight,
        child: Column(
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              decoration: searchDecoration,
              onChanged: (_) => setState(() {}),
            ),
            SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: channels.length,
                itemBuilder: (context, index) {
                  final channel = channels[index];
                  return ListTile(
                    minTileHeight: 56,
                    horizontalTitleGap: 16,
                    title: Text(
                      '${channel.number} · ${channel.name}',
                      softWrap: true,
                    ),
                    trailing: Wrap(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, (
                            id: channel.id,
                            after: false,
                          )),
                          child: const Text('Before'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, (
                            id: channel.id,
                            after: true,
                          )),
                          child: const Text('After'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
    return dialog;
  }
}

class _ChannelDeletionDialog extends StatefulWidget {
  const _ChannelDeletionDialog({
    required this.channels,
    required this.confirmLabel,
  });

  final List<Channel> channels;
  final String confirmLabel;

  @override
  State<_ChannelDeletionDialog> createState() => _ChannelDeletionDialogState();
}

class _ChannelDeletionDialogState extends State<_ChannelDeletionDialog> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channels = widget.channels;
    final size = MediaQuery.sizeOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final compact = LineupLayout.isCompactWidth(size.width);
    final roles = LineupTheme.of(context);
    final theme = Theme.of(context);
    final count = channels.length;
    final headingStyle = theme.textTheme.headlineSmall?.copyWith(
      fontSize: (compact ? 24 : 32),
      fontWeight: FontWeight.w600,
    );
    final supportStyle = theme.textTheme.bodyLarge?.copyWith(
      fontSize: (compact ? 14 : 18),
      color: roles.secondaryText,
    );
    final nameStyle = theme.textTheme.titleMedium?.copyWith(
      fontSize: (compact ? 16 : 20),
      fontWeight: FontWeight.w500,
    );
    final numberStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: (compact ? 14 : 18),
      color: roles.secondaryText,
    );

    final availableWidth = (size.width - (48)).clamp(0.0, 680).toDouble();
    final availableHeight = (size.height - viewInsets.vertical - (48))
        .clamp(0.0, 720)
        .toDouble();

    return Dialog(
      backgroundColor: roles.primarySurface,
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(roles.panelRadius),
        side: BorderSide(color: roles.subtleBorder),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: availableWidth,
          maxHeight: availableHeight,
        ),
        child: Padding(
          padding: EdgeInsets.all((compact ? 24 : 32)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                namesRoute: true,
                container: true,
                child: Text(
                  'Delete $count ${count == 1 ? 'channel' : 'channels'}?',
                  style: headingStyle,
                ),
              ),
              SizedBox(height: 8),
              Text(
                count == 1
                    ? 'This removes this channel from your lineup. This action cannot be undone.'
                    : 'This removes these channels from your lineup. This action cannot be undone.',
                style: supportStyle,
              ),
              SizedBox(height: 16),
              Divider(height: 1, color: roles.subtleBorder),
              SizedBox(height: 8),
              Flexible(
                fit: FlexFit.loose,
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: ListView.separated(
                    controller: _scrollController,
                    shrinkWrap: true,
                    padding: EdgeInsets.only(right: 12),
                    itemCount: channels.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: roles.subtleBorder),
                    itemBuilder: (context, index) {
                      final channel = channels[index];
                      return ConstrainedBox(
                        constraints: BoxConstraints(minHeight: 52),
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            key: ValueKey('delete-dialog-row-${channel.id}'),
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              SizedBox(
                                width: 56,
                                child: Text(
                                  '${channel.number}',
                                  style: numberStyle,
                                ),
                              ),
                              SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  channel.name,
                                  softWrap: true,
                                  style: nameStyle,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton(
                    autofocus: true,
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  LineupDestructiveButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(widget.confirmLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
