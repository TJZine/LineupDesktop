import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channels/channel.dart';
import '../playback/player_coordinator.dart';
import '../ui/app_theme.dart';
import '../ui/app_ui.dart';
import 'channel_health_monitor.dart';
import 'channel_studio_view.dart';
import 'lineup_controller.dart';
import 'navigation_shortcuts.dart';

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
  List<String> _lastChannelOrder = const [];
  final _addFocus = FocusNode(debugLabel: 'Add a custom channel');
  final _selectionFocus = FocusNode(debugLabel: 'Select channels');
  final _reorderFocus = FocusNode(debugLabel: 'Reorder channels');
  Future<bool>? _leaveRequest;
  bool _focusPruneScheduled = false;
  bool _focusPruneNeedsRestore = false;
  String? _focusPruneAnchorId;
  int? _focusPruneAnchorIndex;
  bool _returnToAdd = false;
  late ChannelHealthMonitor _healthMonitor;
  final _visibleHealthIds = <String>{};
  bool _visibleHealthPostFrameScheduled = false;
  GlobalKey<ChannelStudioViewState> _studioKey =
      GlobalKey<ChannelStudioViewState>();

  bool get studioOpen => _studioOpen;

  bool get _studioOpen => _studioMode != null;
  ChannelStudioViewState? get _studio => _studioKey.currentState;

  @override
  void initState() {
    super.initState();
    _healthMonitor = ChannelHealthMonitor(controller: widget.controller)
      ..addListener(_healthChanged);
  }

  @override
  void didUpdateWidget(covariant ChannelsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    _healthMonitor
      ..removeListener(_healthChanged)
      ..dispose();
    _healthMonitor = ChannelHealthMonitor(controller: widget.controller)
      ..addListener(_healthChanged);
    _visibleHealthIds.clear();
  }

  void _healthChanged() {
    if (mounted) setState(() {});
  }

  void openNew() {
    if (_saving) return;
    setState(() {
      _studioKey = GlobalKey<ChannelStudioViewState>();
      _studioMode = ChannelStudioMode.createCustom;
      _studioChannel = null;
      _returnFocusId = null;
      _returnToAdd = true;
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
    _returnToAdd = false;
    _error = null;
  });

  void _openDuplicate(Channel source) => setState(() {
    _studioKey = GlobalKey<ChannelStudioViewState>();
    _studioMode = ChannelStudioMode.duplicateCustom;
    _studioChannel = source;
    _returnFocusId = source.id;
    _returnToAdd = false;
    _error = null;
  });

  /// Claims one local management Back action, if the current leaf has one.
  ///
  /// A false result is deliberately side-effect-free: the shell may then
  /// resolve the Channels route's captured parent. Directory transactions and
  /// Studio leave guards claim the press while they are pending.
  bool handleBack() {
    if (_saving || _leaveRequest != null) return true;
    if (_studioOpen) {
      final studio = _studio;
      if (studio == null || studio.saving) return true;
      if (studio.cancelPendingChoice()) return true;
      unawaited(closeStudio());
      return true;
    }
    if (_showSelected) {
      final selectedFocusId = _selectedIds.firstOrNull;
      setState(() => _showSelected = false);
      _restoreNavigationFocus(preferredId: selectedFocusId);
      return true;
    }
    switch (_mode) {
      case _DirectoryMode.normal:
        return false;
      case _DirectoryMode.selection:
        _cancelSelection();
        return true;
      case _DirectoryMode.reorder:
        _cancelReorder();
        return true;
    }
  }

  /// Restores focus to an attached control in the current directory
  /// projection. The shell may call this after Channels is mounted.
  void restoreNavigationFocus() => _restoreNavigationFocus();

  bool _isTvBackEvent(BuildContext context, KeyEvent event) {
    if (!LineupTheme.of(context).androidTv || event is! KeyDownEvent) {
      return false;
    }
    return event.logicalKey == LogicalKeyboardKey.goBack ||
        event.logicalKey == LogicalKeyboardKey.escape;
  }

  Future<bool> requestLeave([String? focusId]) =>
      _leaveRequest ??= _requestLeave(focusId)
          .whenComplete(() => _leaveRequest = null);

  Future<bool> _requestLeave(String? focusId) async {
    if (_saving) return false;
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
    _restoreNavigationFocus(preferredId: focusId);
  }

  @override
  void dispose() {
    _visibleHealthIds.clear();
    _healthMonitor
      ..removeListener(_healthChanged)
      ..dispose();
    _search.dispose();
    _searchFocus.dispose();
    _addFocus.dispose();
    _selectionFocus.dispose();
    _reorderFocus.dispose();
    for (final node in _openFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_studioMode case final mode?) {
      return PopScope(
        canPop: AndroidBackScope.claims(context),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !AndroidBackScope.claims(context)) {
            unawaited(closeStudio());
          }
        },
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: (_, event) {
            if (_isTvBackEvent(context, event) && handleBack()) {
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: ChannelStudioView(
            key: _studioKey,
            controller: widget.controller,
            mode: mode,
            channel: _studioChannel,
            onBack: closeStudio,
            onOpenMenu: widget.onOpenMenu,
            menuFocusNode: widget.menuFocusNode,
            onSaved: (id) {
              _returnFocusId = id;
              _returnToAdd = false;
            },
            onDuplicate: _openDuplicate,
            onOpenChannel: (channel) async {
              if (await requestLeave(channel.id) && mounted) _open(channel);
            },
            onOpenGenerateLineup: _openGenerateLineupFromStudio,
            clock: widget.clock,
            onTune: (id) async {
              final originatingStudio = _studioKey;
              final success = await widget.player.tune(id);
              if (success &&
                  mounted &&
                  _studioOpen &&
                  identical(_studioKey, originatingStudio)) {
                widget.onOpenPlayer();
              }
              return success;
            },
          ),
        ),
      );
    }

    final channels = _sortedChannels();
    final liveIds = channels.map((channel) => channel.id).toSet();
    _selectedIds.removeWhere((id) => !liveIds.contains(id));
    final matching = _matchingChannels(channels);
    final visible = _showSelected
        ? channels
              .where((channel) => _selectedIds.contains(channel.id))
              .toList(growable: false)
        : matching;
    _scheduleFocusPrune(liveIds);
    _lastChannelOrder = channels
        .map((channel) => channel.id)
        .toList(growable: false);
    final headingStyle = LineupTypography.pageTitle.copyWith(
      color: LineupTheme.of(context).primaryText,
    );
    final countStyle = LineupTypography.body.copyWith(
      fontSize: _directorySize(28, 24),
      color: LineupTheme.of(context).secondaryText,
    );
    final bodyStyle = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(fontSize: 18);

    final page = LineupPage(
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
                            focusNode: _addFocus,
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
                          focusNode: _addFocus,
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
                      _noteVisibleHealth(channel.id);
                      final menuTheme = LineupTheme.of(context).androidTv
                          ? Theme.of(context)
                          : null;
                      // The selection-mode checkbox alone shows checked
                      // state; the row surface carries focus and hover only.
                      return LineupRowSurface(
                        selected: false,
                        child: Builder(
                          builder: (context) {
                            final focusedTv =
                                LineupTheme.of(context).androidTv &&
                                LineupFocusScope.visible(
                                  context,
                                  Focus.of(context).hasFocus,
                                );
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
                              () =>
                                  FocusNode(debugLabel: 'Open ${channel.name}'),
                            );
                            rowFocus.debugLabel = 'Open ${channel.name}';
                            return Material(
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
                                            semanticLabel:
                                                'Select ${channel.name}',
                                            value: _selectedIds.contains(
                                              channel.id,
                                            ),
                                            onChanged: _saving
                                                ? null
                                                : (_) => _toggleSelected(
                                                    channel.id,
                                                  ),
                                          )
                                        : null,
                                    number: Text(
                                      '${channel.number}',
                                      style: rowSupportStyle,
                                    ),
                                    name: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(channel.name, style: rowNameStyle),
                                        if (_healthMonitor.issueFor(
                                              channel.id,
                                            ) ==
                                            true)
                                          Text(
                                            'Schedule issue — open this channel to recover',
                                            style: rowSupportStyle?.copyWith(
                                              color: focusedTv
                                                  ? LineupTheme.of(context)
                                                        .primaryText
                                                  : Theme.of(context)
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
                                    type: Text(
                                      ownership,
                                      style: rowSupportStyle,
                                    ),
                                    action: _mode == _DirectoryMode.selection
                                        ? const SizedBox.shrink()
                                        : PopupMenuButton<_RowAction>(
                                            enabled: !_saving,
                                            tooltip:
                                                'Actions for ${channel.name}',
                                            padding: EdgeInsets.all(8),
                                            iconSize: 24,
                                            icon: Icon(
                                              Icons.adaptive.more,
                                              semanticLabel:
                                                  'Actions for ${channel.name}',
                                            ),
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
                                                    menuTheme: menuTheme,
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
                                                child: LineupDropdownMenuRow(
                                                  menuTheme: menuTheme,
                                                  selected: false,
                                                  child: Text('Delete…'),
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) {
        if (_isTvBackEvent(context, event) && handleBack()) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: page,
    );
  }

  List<Channel> _sortedChannels() =>
      [...widget.controller.channels]
        ..sort((left, right) => left.number.compareTo(right.number));

  List<Channel> _matchingChannels(List<Channel> channels) {
    final query = _search.text.trim().toLowerCase();
    return channels
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
  }

  List<Channel> _visibleChannels() {
    final channels = _sortedChannels();
    final matching = _matchingChannels(channels);
    return _showSelected
        ? channels
              .where((channel) => _selectedIds.contains(channel.id))
              .toList(growable: false)
        : matching;
  }

  bool _usableFocus(FocusNode? node) {
    final nodeContext = node?.context;
    return node != null &&
        node.canRequestFocus &&
        node.parent != null &&
        nodeContext != null &&
        nodeContext.mounted &&
        ModalRoute.of(nodeContext)?.isCurrent != false;
  }

  FocusNode? _focusForVisibleRow(
    List<Channel> visible, {
    String? preferredId,
    int? preferredIndex,
  }) {
    final visibleIds = visible.map((channel) => channel.id).toSet();
    final preferred = preferredId == null ? null : _openFocus[preferredId];
    if (visibleIds.contains(preferredId) && _usableFocus(preferred)) {
      return preferred;
    }
    final attached = [
      for (var index = 0; index < visible.length; index++)
        if (_usableFocus(_openFocus[visible[index].id])) index,
    ];
    if (attached.isEmpty) return null;
    final all = _sortedChannels();
    final anchorId =
        preferredId ??
        _openFocus.entries
            .where(
              (entry) => entry.value.hasFocus && visibleIds.contains(entry.key),
            )
            .map((entry) => entry.key)
            .firstOrNull;
    final anchor =
        preferredIndex ??
        (anchorId == null
            ? 0
            : all.indexWhere((channel) => channel.id == anchorId));
    attached.sort((left, right) {
      final leftDistance =
          (all.indexWhere((channel) => channel.id == visible[left].id) - anchor)
              .abs();
      final rightDistance =
          (all.indexWhere((channel) => channel.id == visible[right].id) -
                  anchor)
              .abs();
      return leftDistance.compareTo(rightDistance);
    });
    return _openFocus[visible[attached.first].id];
  }

  void _restoreNavigationFocus({
    String? preferredId,
    FocusNode? preferredNode,
    int? preferredIndex,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _studioOpen) return;
      final pruneAnchorIndex =
          preferredId != null && _focusPruneAnchorId == preferredId
          ? _focusPruneAnchorIndex
          : null;
      final visible = _visibleChannels();
      final visibleIds = visible.map((channel) => channel.id).toSet();
      final hasFocusedVisibleRow = _openFocus.entries.any(
        (entry) => entry.value.hasFocus && visibleIds.contains(entry.key),
      );
      final addOrigin =
          _returnToAdd && preferredId == null && preferredNode == null;
      final target = _usableFocus(preferredNode)
          ? preferredNode
          : addOrigin && _usableFocus(_addFocus)
          ? _addFocus
          : preferredId == null &&
                preferredNode == null &&
                !hasFocusedVisibleRow &&
                _usableFocus(widget.focusNode)
          ? widget.focusNode
          : _focusForVisibleRow(
                  visible,
                  preferredId: preferredId,
                  preferredIndex: preferredIndex ?? pruneAnchorIndex,
                ) ??
                (_mode == _DirectoryMode.selection &&
                        !_showSelected &&
                        _usableFocus(_searchFocus)
                    ? _searchFocus
                    : null) ??
                (_usableFocus(widget.focusNode) ? widget.focusNode : null);
      target?.requestFocus();
      if (target != null) FocusManager.instance.applyFocusChangesIfNeeded();
      if (addOrigin && identical(target, _addFocus)) _returnToAdd = false;
    });
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
    final moveToTextWidth = TextPainter.computeWidth(
      text: TextSpan(
        text: 'Move to…',
        style: LineupTypography.button.copyWith(fontSize: 16),
      ),
      textDirection: Directionality.of(context),
      textScaler: textScaler,
    );
    final actionWidth = (88 + moveToTextWidth + 40 + 16)
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
        focusNode: _selectionFocus,
        onPressed: _saving
            ? null
            : () => setState(() {
                _mode = _DirectoryMode.selection;
                _selectedIds.clear();
              }),
        child: const Text('Select'),
      ),
      OutlinedButton(
        focusNode: _reorderFocus,
        onPressed: _saving ? null : _beginReorder,
        child: const Text('Reorder channels'),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final search = Semantics(
          container: true,
          label: 'Search channels',
          child: LineupTextFieldActivation(
            focusNode: _searchFocus,
            enabled: !_saving,
            builder: (fieldContext, fieldFocus, finishEditing) => TextField(
              onEditingComplete: finishEditing,
              key: const Key('channels-search'),
              enabled: !_saving,
              controller: _search,
              focusNode: fieldFocus,
              style: _channelBodyStyle(fieldContext),
              decoration: InputDecoration(hintText: 'Search by name or number'),
              onChanged: (_) => setState(() {}),
            ),
          ),
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
                            : () {
                                final selectedFocusId =
                                    _selectedIds.firstOrNull;
                                setState(() => _showSelected = false);
                                _restoreNavigationFocus(
                                  preferredId: selectedFocusId,
                                );
                              },
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

  void _cancelSelection() {
    setState(() {
      _mode = _DirectoryMode.normal;
      _selectedIds.clear();
      _showSelected = false;
    });
    _restoreNavigationFocus(preferredNode: _selectionFocus);
  }

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
    final orderedBeforeDelete = _sortedChannels();
    var selected = widget.controller.channels
        .where((channel) => _selectedIds.contains(channel.id))
        .toList(growable: false);
    final deletionAnchorIndex = orderedBeforeDelete.indexWhere(
      (channel) => _selectedIds.contains(channel.id),
    );
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
      _focusAfterDeletion(
        selected.firstOrNull?.id,
        preferredIndex: deletionAnchorIndex,
      );
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

  void _cancelReorder() {
    setState(() {
      _mode = _DirectoryMode.normal;
      _reorderBase = const [];
      _reorderIds = const [];
    });
    _restoreNavigationFocus(preferredNode: _reorderFocus);
  }

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

  void _noteVisibleHealth(String id) {
    _visibleHealthIds.add(id);
    if (_visibleHealthPostFrameScheduled) return;
    _visibleHealthPostFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibleHealthPostFrameScheduled = false;
      if (!mounted) {
        _visibleHealthIds.clear();
        return;
      }
      final ids = _visibleHealthIds.toList(growable: false);
      _visibleHealthIds.clear();
      for (final id in ids) {
        final channel = widget.controller.channels
            .where((item) => item.id == id)
            .firstOrNull;
        if (channel != null) _healthMonitor.request(channel);
      }
    });
  }

  void _scheduleFocusPrune(Set<String> liveIds) {
    final staleIds = _openFocus.keys
        .where((id) => !liveIds.contains(id))
        .toList();
    if (staleIds.isEmpty) return;
    final focusedStaleId = staleIds
        .where((id) => _openFocus[id]?.hasFocus ?? false)
        .firstOrNull;
    if (focusedStaleId != null) {
      _focusPruneNeedsRestore = true;
      _focusPruneAnchorId ??= focusedStaleId;
      final previousIndex = _lastChannelOrder.indexOf(focusedStaleId);
      if (previousIndex >= 0) _focusPruneAnchorIndex ??= previousIndex;
    }
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
      final anchorId = _focusPruneAnchorId;
      final anchorIndex = _focusPruneAnchorIndex;
      _focusPruneNeedsRestore = false;
      _focusPruneAnchorId = null;
      _focusPruneAnchorIndex = null;
      for (final id in staleIds) {
        _openFocus.remove(id)?.dispose();
      }
      if (restoreFocus) {
        _restoreNavigationFocus(
          preferredId: anchorId,
          preferredIndex: anchorIndex,
        );
      }
    });
  }

  void _focusAfterDeletion(String? deletedId, {int? preferredIndex}) =>
      _restoreNavigationFocus(
        preferredId: deletedId,
        preferredIndex: preferredIndex,
      );

  Future<void> _delete(Channel channel) async {
    if (_saving) return;
    final confirmed = await _confirmChannelDeletion([
      channel,
    ], 'Delete channel');
    if (!mounted) return;
    if (!confirmed) {
      _restoreNavigationFocus(preferredId: channel.id);
      return;
    }
    final deletionAnchorIndex = _sortedChannels().indexWhere(
      (item) => item.id == channel.id,
    );
    setState(() => _saving = true);
    try {
      await widget.controller.deleteChannels(expectedChannels: [channel]);
      if (!mounted) return;
      setState(() => _error = null);
      _focusAfterDeletion(channel.id, preferredIndex: deletionAnchorIndex);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error =
            'The channel could not be deleted. No lineup changes were saved.',
      );
      _restoreNavigationFocus(preferredId: channel.id);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _MoveChannelDialog extends StatefulWidget {
  const _MoveChannelDialog({required this.channels});

  final List<Channel> channels;

  @override
  State<_MoveChannelDialog> createState() => _MoveChannelDialogState();
}

class _MoveChannelDialogState extends State<_MoveChannelDialog> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'Move channel search');
  bool _autofocusRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_autofocusRequested && LineupTheme.of(context).androidTv) {
      _autofocusRequested = true;
      FocusScope.of(context).autofocus(_searchFocus);
    }
  }

  @override
  void dispose() {
    _searchFocus.dispose();
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
            LineupTextFieldActivation(
              focusNode: _searchFocus,
              builder: (fieldContext, fieldFocus, finishEditing) => TextField(
                controller: _search,
                focusNode: fieldFocus,
                autofocus: !LineupTheme.of(fieldContext).androidTv,
                onEditingComplete: finishEditing,
                decoration: searchDecoration,
                onChanged: (_) => setState(() {}),
              ),
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
  final _readerFocus = FocusNode(debugLabel: 'Selected channels to delete');

  @override
  void dispose() {
    _readerFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  KeyEventResult _readSelectedNames(FocusNode _, KeyEvent event) {
    if (!LineupTheme.of(context).androidTv ||
        !_scrollController.hasClients ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final amount = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => 48.0,
      LogicalKeyboardKey.arrowUp => -48.0,
      _ => null,
    };
    if (amount == null) return KeyEventResult.ignored;
    final position = _scrollController.position;
    final target = (position.pixels + amount).clamp(
      0.0,
      position.maxScrollExtent,
    );
    if (target == position.pixels) return KeyEventResult.ignored;
    position.jumpTo(target);
    return KeyEventResult.handled;
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
      fontSize: compact ? 14 : 18,
      color: roles.secondaryText,
    );
    final nameStyle = theme.textTheme.titleMedium?.copyWith(
      fontSize: compact ? 16 : 20,
      fontWeight: FontWeight.w500,
    );
    final numberStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: compact ? 14 : 18,
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
                child: Focus(
                  focusNode: _readerFocus,
                  canRequestFocus: roles.androidTv,
                  skipTraversal: !roles.androidTv,
                  onKeyEvent: _readSelectedNames,
                  child: ListenableBuilder(
                    listenable: _readerFocus,
                    builder: (context, _) {
                      final fill =
                          roles.androidTv &&
                          roles.focusTreatment == LineupFocusTreatment.fill &&
                          LineupFocusScope.visible(
                            context,
                            _readerFocus.hasFocus,
                          );
                      return LineupFocusFrame(
                        focused: fill,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: fill
                                ? roles.focusedSurface
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(
                              roles.panelRadius,
                            ),
                          ),
                          child: LineupFocusInk(
                            focused: fill,
                            child: Semantics(
                              label: roles.androidTv
                                  ? 'Selected channels for deletion'
                                  : null,
                              readOnly: roles.androidTv ? true : null,
                              child: Padding(
                                padding: EdgeInsets.all(
                                  roles.androidTv &&
                                          roles.focusTreatment ==
                                              LineupFocusTreatment.fill &&
                                          roles.largeFocusIndicators
                                      ? LineupFocusFrame.contentClearance
                                      : 0,
                                ),
                                child: Scrollbar(
                                  controller: _scrollController,
                                  thumbVisibility: true,
                                  child: ListView.separated(
                                    controller: _scrollController,
                                    shrinkWrap: true,
                                    padding: EdgeInsets.only(right: 12),
                                    itemCount: channels.length,
                                    separatorBuilder: (_, _) => Divider(
                                      height: 1,
                                      color: roles.subtleBorder,
                                    ),
                                    itemBuilder: (context, index) {
                                      final channel = channels[index];
                                      return ConstrainedBox(
                                        constraints: BoxConstraints(
                                          minHeight: 52,
                                        ),
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          child: Row(
                                            key: ValueKey(
                                              'delete-dialog-row-${channel.id}',
                                            ),
                                            crossAxisAlignment:
                                                CrossAxisAlignment.baseline,
                                            textBaseline:
                                                TextBaseline.alphabetic,
                                            children: [
                                              SizedBox(
                                                width: 56,
                                                child: Text(
                                                  '${channel.number}',
                                                  style: fill
                                                      ? numberStyle?.copyWith(
                                                          color: LineupTheme.of(
                                                            context,
                                                          ).secondaryText,
                                                        )
                                                      : numberStyle,
                                                ),
                                              ),
                                              SizedBox(width: 16),
                                              Expanded(
                                                child: Text(
                                                  channel.name,
                                                  softWrap: true,
                                                  style: fill
                                                      ? nameStyle?.copyWith(
                                                          color: LineupTheme.of(
                                                            context,
                                                          ).primaryText,
                                                        )
                                                      : nameStyle,
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
                            ),
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
