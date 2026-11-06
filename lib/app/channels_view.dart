import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:lineup_desktop/platform/device_profile.dart';

import '../channels/channel.dart';
import '../playback/player_coordinator.dart';
import '../ui/app_theme.dart';
import '../ui/app_ui.dart';
import '../ui/handheld_management.dart';
import '../ui/lineup_canvas.dart';
import 'channel_health_monitor.dart';
import 'channel_setup/review_step.dart' show HandheldRosterAnchor;
import 'channel_studio_view.dart';
import 'lineup_controller.dart';
import 'navigation_shortcuts.dart';

enum _DirectoryFilter { all, custom, generated }

enum _DirectoryMode { normal, selection, reorder }

enum _RowAction { duplicate, delete }

enum _DirectoryAction { generate, select, reorder }

enum _MoveAction { up, down, to }

typedef _MoveDestination = ({String id, bool after});

double _channelTouchExtent(BuildContext context) =>
    math.max(56, LineupCanvas.minimumTouchExtentOf(context) + .001);

ButtonStyle? _channelMoveButtonStyle(BuildContext context) =>
    DeviceProfile.of(context).isHandheld
    ? TextButton.styleFrom(
        minimumSize: Size.square(_channelTouchExtent(context)),
      )
    : null;

double _moveKeyboardInset(BuildContext context) {
  // Observe inset changes and use the raw view value because a parent can
  // already have consumed the inset in its MediaQuery.
  MediaQuery.viewInsetsOf(context);
  return View.of(context).viewInsets.bottom /
      LineupCanvas.physicalPixelRatioOf(context);
}

class ChannelsView extends StatefulWidget {
  const ChannelsView({
    required this.controller,
    required this.player,
    required this.onOpenPlayer,
    required this.onOpenMenu,
    required this.menuFocusNode,
    this.onBack,
    this.showNavigationMenu = true,
    this.backLabel = '‹ Back to Guide',
    this.focusNode,
    this.clock,
    super.key,
  });

  final LineupController controller;
  final PlayerCoordinator player;
  final VoidCallback onOpenPlayer;
  final LineupMenuCallback onOpenMenu;
  final FocusNode menuFocusNode;
  final VoidCallback? onBack;
  final bool showNavigationMenu;
  final String backLabel;
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
  final _handheldScroll = ScrollController();
  late final _anchor = HandheldRosterAnchor(
    _handheldScroll,
    () => _directoryRows,
  );
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
  final _stackedActionsFocus = <String, FocusNode>{};
  FocusNode? _popupActionsInvoker;
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
      unawaited(_handleStudioBack());
      return true;
    }
    if (_showSelected && !handheldStacked(context)) {
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
        if (_reorderDirty) {
          unawaited(requestLeave());
        } else {
          _cancelReorder();
        }
        return true;
    }
  }

  /// Restores focus to an attached control in the current directory
  /// projection. The shell may call this after Channels is mounted.
  void restoreNavigationFocus() => _restoreNavigationFocus();

  bool _isTvBackEvent(BuildContext context, KeyEvent event) {
    if (!DeviceProfile.of(context).isTv || event is! KeyDownEvent) {
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
    if (_reorderDirty) {
      if (!await _confirmDiscard('Your unsaved channel order will be lost.') ||
          !mounted) {
        return false;
      }
      _cancelReorder();
      return true;
    }
    if (!_studioOpen) return true;
    final studio = _studio;
    if (studio == null || studio.saving) return false;
    if (studio.dirty) {
      if (!await _confirmDiscard(
            'Your unsaved Channel Studio changes will be lost.',
          ) ||
          !mounted) {
        return false;
      }
    }
    _showList(focusId ?? _returnFocusId);
    return true;
  }

  Future<bool> _confirmDiscard(String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard changes?'),
          content: Text(message),
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

  Future<void> closeStudio([String? focusId]) async {
    await requestLeave(focusId);
  }

  Future<void> _handleStudioBack([String? focusId]) async {
    final studio = _studio;
    if (_saving || _leaveRequest != null || studio == null || studio.saving) {
      return;
    }
    if (!studio.cancelPendingChoice()) await closeStudio(focusId);
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
    _handheldScroll.dispose();
    _search.dispose();
    _searchFocus.dispose();
    _addFocus.dispose();
    _selectionFocus.dispose();
    _reorderFocus.dispose();
    for (final node in [..._openFocus.values, ..._stackedActionsFocus.values]) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = DeviceProfile.of(context);
    if (_studioMode case final mode?) {
      if (profile.isHandheld) _anchor.captureBeforeDetach();
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
            onBack: profile.isHandheld ? _handleStudioBack : closeStudio,
            onOpenMenu: widget.showNavigationMenu ? widget.onOpenMenu : null,
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
    final handheld = profile.isHandheld;
    final stacked = handheldStacked(context);
    if (handheld) {
      final reordering = _mode == _DirectoryMode.reorder;
      _anchor.update(
        context,
        stacked,
        reordering
            ? List.of(_reorderIds)
            : [for (final channel in visible) channel.id],
        separated: !stacked && !reordering,
      );
    }
    if (stacked) {
      final directory = _stackedDirectory(channels, matching, visible);
      return NotificationListener<ScrollNotification>(
        onNotification: _anchor.cancelOnDrag,
        child: _mode == _DirectoryMode.reorder
            ? _layoutReorderPage(directory)
            : directory,
      );
    }
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
        onOpenMenu: widget.showNavigationMenu ? widget.onOpenMenu : null,
        trailing: widget.onBack == null
            ? null
            : Align(
                alignment: Alignment.centerRight,
                child: LineupTouchTarget(
                  onPressed: widget.onBack,
                  child: TextButton(
                    onPressed: widget.onBack,
                    child: Text(widget.backLabel),
                  ),
                ),
              ),
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
                    controller: handheld ? _handheldScroll : null,
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final channel = visible[index];
                      _noteVisibleHealth(channel.id);
                      final menuTheme = DeviceProfile.of(context).isTv
                          ? Theme.of(context)
                          : null;
                      // The selection-mode checkbox alone shows checked
                      // state; the row surface carries focus and hover only.
                      return LineupRowSurface(
                        selected: false,
                        child: Builder(
                          builder: (context) {
                            final focusedTv =
                                DeviceProfile.of(context).isTv &&
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
                            BuildContext? actionsIconContext;
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
                                            icon: Builder(
                                              builder: (context) {
                                                actionsIconContext = context;
                                                return Icon(
                                                  Icons.adaptive.more,
                                                  semanticLabel:
                                                      'Actions for ${channel.name}',
                                                );
                                              },
                                            ),
                                            onOpened: () {
                                              final iconContext =
                                                  actionsIconContext;
                                              _popupActionsInvoker =
                                                  iconContext == null
                                                  ? null
                                                  : Focus.maybeOf(iconContext);
                                            },
                                            onCanceled: () =>
                                                _popupActionsInvoker = null,
                                            menuPadding: EdgeInsets.zero,
                                            style: handheld
                                                ? IconButton.styleFrom(
                                                    minimumSize: Size.square(
                                                      _channelTouchExtent(
                                                        context,
                                                      ),
                                                    ),
                                                  )
                                                : null,
                                            onSelected: (action) {
                                              final invoker =
                                                  _popupActionsInvoker;
                                              _popupActionsInvoker = null;
                                              switch (action) {
                                                case _RowAction.duplicate:
                                                  _openDuplicate(channel);
                                                case _RowAction.delete:
                                                  unawaited(
                                                    _delete(
                                                      channel,
                                                      invoker: invoker,
                                                    ),
                                                  );
                                              }
                                            },
                                            itemBuilder: (_) => [
                                              if (channel.builderKey != null)
                                                PopupMenuItem(
                                                  value: _RowAction.duplicate,
                                                  height: handheld
                                                      ? _channelTouchExtent(
                                                          context,
                                                        )
                                                      : 48,
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
                                                height: handheld
                                                    ? _channelTouchExtent(
                                                        context,
                                                      )
                                                    : 48,
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
      child: handheld
          ? NotificationListener<ScrollNotification>(
              onNotification: _anchor.cancelOnDrag,
              child: page,
            )
          : page,
    );
  }

  // Reorder has no text fields. The Move sheet handles keyboard clearance
  // while the covered reorder page keeps its normal layout.
  Widget _layoutReorderPage(Widget directory) => LayoutBuilder(
    builder: (context, constraints) {
      final keyboard = _moveKeyboardInset(context);
      final height = constraints.maxHeight + keyboard;
      return ClipRect(
        clipBehavior: keyboard > 0 ? Clip.hardEdge : Clip.none,
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: height,
          maxHeight: height,
          child: directory,
        ),
      );
    },
  );

  Widget _stackedDirectory(
    List<Channel> channels,
    List<Channel> matching,
    List<Channel> visible,
  ) {
    final selecting = _mode == _DirectoryMode.selection;
    final reordering = _mode == _DirectoryMode.reorder;
    final bar = switch (_mode) {
      _DirectoryMode.normal => HandheldPageBar(
        title: 'Channels',
        subtitle:
            '${channels.length} ${channels.length == 1 ? 'channel' : 'channels'}',
        tabRoot: true,
        actions: [
          _channelIcon(
            'Add a custom channel',
            Icons.add,
            _saving ? null : openNew,
            focusNode: channels.isEmpty ? null : _addFocus,
          ),
          if (channels.isNotEmpty)
            _channelIcon(
              'More channel actions',
              Icons.adaptive.more,
              _saving ? null : _stackedMoreActions,
              focusNode: widget.focusNode,
            ),
        ],
      ),
      _DirectoryMode.selection => HandheldPageBar(
        title: '${_selectedIds.length} selected',
        onBack: _saving ? null : _cancelSelection,
        backIcon: Icons.close,
        backTooltip: 'Cancel selection',
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: _saving || matching.isEmpty
                ? null
                : () => setState(
                    () => _selectedIds.addAll(
                      matching.map((channel) => channel.id),
                    ),
                  ),
            child: const Text('Select all'),
          ),
          _channelIcon(
            'Delete selected',
            Icons.delete_outline,
            _selectedIds.isEmpty || _saving ? null : _deleteSelected,
          ),
        ],
      ),
      _DirectoryMode.reorder => HandheldPageBar(
        title: 'Reorder channels',
        onBack: _saving ? null : handleBack,
        backIcon: Icons.close,
        backTooltip: 'Cancel reorder',
        actions: [
          FilledButton(
            onPressed: _saving || !_reorderDirty ? null : _saveOrder,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    };

    return SafeArea(
      child: Column(
        children: [
          if (widget.showNavigationMenu)
            LineupTopBar(
              menuKey: const Key('channels-app-menu'),
              menuFocusNode: widget.menuFocusNode,
              onOpenMenu: widget.onOpenMenu,
              trailing: widget.onBack == null
                  ? null
                  : Align(
                      alignment: Alignment.centerRight,
                      child: LineupTouchTarget(
                        onPressed: widget.onBack,
                        child: TextButton(
                          onPressed: widget.onBack,
                          child: Text(widget.backLabel),
                        ),
                      ),
                    ),
            ),
          Expanded(
            child: HandheldColumnWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  bar,
                  if (channels.isNotEmpty && !reordering) ...[
                    _stackedSearch(),
                    const SizedBox(height: 10),
                    _stackedFilters(channels),
                    const Divider(height: 8),
                  ],
                  Expanded(
                    child: channels.isEmpty
                        ? _stackedEmptyDirectory()
                        : reordering
                        ? _reorderList(channels, stacked: true)
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
                        : ListView.builder(
                            key: const PageStorageKey('channels-directory'),
                            controller: _handheldScroll,
                            itemCount: visible.length,
                            itemBuilder: (context, index) =>
                                _stackedChannelRow(visible[index], selecting),
                          ),
                  ),
                  if (_error != null) LineupNotice(message: _error!),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stackedEmptyDirectory() => LineupEmptyState(
    icon: Icons.view_list,
    title: 'Build your first channel',
    message: 'Generate a lineup from Plex or create one custom channel.',
    action: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          focusNode: widget.focusNode,
          onPressed: _saving ? null : widget.controller.enterChannelSetup,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('Generate lineup'),
          style: FilledButton.styleFrom(
            minimumSize: Size.square(_channelTouchExtent(context)),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          focusNode: _addFocus,
          onPressed: _saving ? null : openNew,
          icon: const Icon(Icons.add),
          label: const Text('Create a custom channel'),
          style: OutlinedButton.styleFrom(
            minimumSize: Size.square(_channelTouchExtent(context)),
          ),
        ),
      ],
    ),
  );

  Widget _channelIcon(
    String tooltip,
    IconData icon,
    VoidCallback? onPressed, {
    FocusNode? focusNode,
  }) {
    final extent = _channelTouchExtent(context);
    return IconButton(
      focusNode: focusNode,
      tooltip: tooltip,
      onPressed: onPressed,
      constraints: BoxConstraints.tightFor(width: extent, height: extent),
      icon: Icon(icon),
    );
  }

  Widget _stackedSearch() {
    final extent = _channelTouchExtent(context);
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: extent),
      child: TextField(
        key: const Key('channels-search'),
        controller: _search,
        focusNode: _searchFocus,
        enabled: !_saving,
        scrollPadding: const EdgeInsets.all(96),
        decoration: InputDecoration(
          hintText: 'Search by name or number',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _search.text.isEmpty
              ? null
              : _channelIcon(
                  'Clear search',
                  Icons.close,
                  _saving ? null : () => setState(_search.clear),
                ),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _stackedFilters(List<Channel> channels) {
    final custom = channels
        .where((channel) => channel.builderKey == null)
        .length;
    return HandheldChipRow(
      children: [
        for (final (filter, label, count) in [
          (_DirectoryFilter.all, 'All', channels.length),
          (_DirectoryFilter.custom, 'Custom', custom),
          (_DirectoryFilter.generated, 'Generated', channels.length - custom),
        ])
          HandheldFilterChip(
            label: label,
            count: count,
            selected: _filter == filter && !_showSelected,
            onSelected: _saving
                ? null
                : () => setState(() {
                    _filter = filter;
                    _showSelected = false;
                  }),
          ),
        if (_mode == _DirectoryMode.selection)
          HandheldFilterChip(
            label: 'Selected ${_selectedIds.length}',
            selected: _showSelected,
            onSelected: _saving || _selectedIds.isEmpty
                ? null
                : () => setState(() => _showSelected = !_showSelected),
          ),
      ],
    );
  }

  void _beginSelection([String? id]) => setState(() {
    _mode = _DirectoryMode.selection;
    _selectedIds.clear();
    if (id != null) _selectedIds.add(id);
  });

  Widget _stackedChannelRow(Channel channel, bool selecting) {
    _noteVisibleHealth(channel.id);
    final source = channelSourceLabel(channel.source, widget.controller);
    final playback = channelRhythmLabel(
      channel.playbackMode,
      channel.blockSize,
    );
    final ownership = channel.builderKey == null ? 'Custom' : 'Generated';
    final extent = _channelTouchExtent(context);
    final actionsFocus = selecting
        ? null
        : _stackedActionsFocus.putIfAbsent(
            channel.id,
            () => FocusNode(debugLabel: 'Actions for ${channel.name}'),
          );
    return KeyedSubtree(
      key: ValueKey('channel-row-${channel.id}'),
      child: HandheldStackedRow(
        number: channel.number,
        name: channel.name,
        facts: '$source · $playback · $ownership',
        warning: _healthMonitor.issueFor(channel.id) == true
            ? 'Schedule issue — open this channel to recover'
            : null,
        onTap: _saving
            ? null
            : selecting
            ? () => _toggleSelected(channel.id)
            : () => _open(channel),
        onLongPress: _saving || selecting
            ? null
            : () => _beginSelection(channel.id),
        checked: selecting ? _selectedIds.contains(channel.id) : null,
        leading: selecting
            ? ExcludeSemantics(
                child: SizedBox.square(
                  dimension: extent,
                  child: Checkbox(
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    value: _selectedIds.contains(channel.id),
                    onChanged: _saving
                        ? null
                        : (_) => _toggleSelected(channel.id),
                  ),
                ),
              )
            : null,
        trailing: selecting
            ? null
            : _channelIcon(
                'Actions for ${channel.name}',
                Icons.adaptive.more,
                _saving
                    ? null
                    : () => _stackedRowActions(channel, actionsFocus!),
                focusNode: actionsFocus,
              ),
      ),
    );
  }

  Widget _stackedReorderRow(
    Channel channel,
    int index,
    int nextNumber,
    Map<String, Channel> byId,
  ) => HandheldStackedRow(
    key: ValueKey('reorder-${channel.id}'),
    number: channel.number,
    next: nextNumber,
    name: channel.name,
    facts: '',
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _channelIcon(
          'Move ${channel.name}',
          Icons.adaptive.more,
          _saving ? null : () => _stackedMoveActions(index, byId),
        ),
        ReorderableDragStartListener(
          key: ValueKey('reorder-drag-${channel.id}'),
          enabled: !_saving,
          index: index,
          child: Semantics(
            label: 'Drag to reorder ${channel.name}',
            child: SizedBox.square(
              dimension: _channelTouchExtent(context),
              child: Icon(
                Icons.drag_handle,
                color: LineupTheme.of(context).secondaryText,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _stackedMoreActions() async {
    final action = await showHandheldChoiceSheet(
      context,
      title: 'Channels',
      showSelection: false,
      choices: const [
        HandheldChoice(
          value: _DirectoryAction.generate,
          label: 'Generate lineup',
          detail: 'Build or update channels from your Plex libraries',
        ),
        HandheldChoice(
          value: _DirectoryAction.select,
          label: 'Select channels',
          detail: 'Choose channels to delete',
        ),
        HandheldChoice(
          value: _DirectoryAction.reorder,
          label: 'Reorder channels',
          detail: 'Change channel order and numbers',
        ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case _DirectoryAction.generate:
        await widget.controller.enterChannelSetup();
      case _DirectoryAction.select:
        _beginSelection();
      case _DirectoryAction.reorder:
        _beginReorder();
      case null:
    }
  }

  Future<void> _stackedRowActions(Channel channel, FocusNode invoker) async {
    final action = await showHandheldChoiceSheet(
      context,
      title: '${channel.number} · ${channel.name}',
      showSelection: false,
      choices: [
        if (channel.builderKey != null)
          const HandheldChoice(
            value: _RowAction.duplicate,
            label: 'Duplicate as custom',
            detail: 'Copy this channel so you can edit it',
          ),
        const HandheldChoice(
          value: _RowAction.delete,
          label: 'Delete…',
          destructive: true,
        ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case _RowAction.duplicate:
        _openDuplicate(channel);
      case _RowAction.delete:
        await _delete(channel, invoker: invoker);
      case null:
    }
  }

  Future<void> _stackedMoveActions(int index, Map<String, Channel> byId) async {
    final action = await showHandheldChoiceSheet(
      context,
      title: 'Move channel',
      showSelection: false,
      choices: [
        if (index > 0)
          const HandheldChoice(value: _MoveAction.up, label: 'Move up'),
        if (index < _reorderIds.length - 1)
          const HandheldChoice(value: _MoveAction.down, label: 'Move down'),
        const HandheldChoice(
          value: _MoveAction.to,
          label: 'Move to…',
          detail: 'Choose a position by channel',
        ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case _MoveAction.up:
        _moveReorder(index, index - 1);
      case _MoveAction.down:
        _moveReorder(index, index + 1);
      case _MoveAction.to:
        await _moveTo(index, byId, stacked: true);
      case null:
    }
  }

  RenderSliverMultiBoxAdaptor? get _directoryRows {
    if (!_handheldScroll.hasClients) return null;
    // The directory and reorder scrollables both use a lazy sliver. Resolve
    // it from the active position so the anchor works in either presentation.
    RenderSliverMultiBoxAdaptor? rows;
    void visit(RenderObject node) {
      if (rows != null) return;
      if (node is RenderSliverMultiBoxAdaptor) {
        rows = node;
      } else {
        node.visitChildren(visit);
      }
    }

    final root = _handheldScroll.position.context.notificationContext
        ?.findRenderObject();
    if (root != null) visit(root);
    return rows;
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
            SizedBox(
              width: DeviceProfile.of(context).isHandheld
                  ? _channelTouchExtent(context)
                  : 44,
              child: action,
            ),
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
        onPressed: _saving ? null : _beginSelection,
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
                    onPressed: _reorderDirty && !_saving ? _saveOrder : null,
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
  ) async {
    final expandActions = DeviceProfile.of(context).isHandheld;
    return await showDialog<bool>(
          context: context,
          builder: (context) => _ChannelDeletionDialog(
            channels: channels,
            confirmLabel: confirmLabel,
            expandActions: expandActions,
          ),
        ) ??
        false;
  }

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

  bool get _reorderDirty =>
      _mode == _DirectoryMode.reorder &&
      !_sameOrder(_reorderBase.map((channel) => channel.id), _reorderIds);

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

  Widget _reorderList(List<Channel> current, {bool stacked = false}) {
    final byId = {for (final channel in current) channel.id: channel};
    final positions = _reorderBase.map((channel) => channel.number).toList()
      ..sort();
    return ReorderableListView.builder(
      key: const Key('channels-reorder-list'),
      buildDefaultDragHandles: false,
      scrollController: DeviceProfile.of(context).isHandheld
          ? _handheldScroll
          : null,
      header: stacked
          ? Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Drag a handle, or use a row menu, to move a channel. Saving renumbers channels in this order.',
                style: TextStyle(
                  color: LineupTheme.of(context).secondaryText,
                  fontSize: 16,
                ),
              ),
            )
          : null,
      itemCount: _reorderIds.length,
      onReorderItem: _saving ? (_, _) {} : _moveReorder,
      itemBuilder: (context, index) {
        final channel =
            byId[_reorderIds[index]] ??
            _reorderBase.firstWhere((item) => item.id == _reorderIds[index]);
        final nextNumber = positions[index];
        if (stacked) {
          return _stackedReorderRow(channel, index, nextNumber, byId);
        }
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
              style: _channelMoveButtonStyle(context),
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

  Future<void> _moveTo(
    int from,
    Map<String, Channel> byId, {
    bool stacked = false,
  }) async {
    final movedId = _reorderIds[from];
    final destinations = [
      for (final id in _reorderIds)
        if (id != movedId) ?byId[id],
    ];
    final target = stacked
        ? await showModalBottomSheet<_MoveDestination>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: false,
            backgroundColor: Colors.transparent,
            builder: (context) => _MoveChannelDialog(
              channels: destinations,
              movingName:
                  (byId[movedId] ??
                          _reorderBase.firstWhere(
                            (channel) => channel.id == movedId,
                          ))
                      .name,
            ),
          )
        : await showDialog<_MoveDestination>(
            context: context,
            builder: (context) => _MoveChannelDialog(channels: destinations),
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
    final staleIds = {
      ..._openFocus.keys,
      ..._stackedActionsFocus.keys,
    }.where((id) => !liveIds.contains(id)).toList();
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
      final staleIds = {
        ..._openFocus.keys,
        ..._stackedActionsFocus.keys,
      }.where((id) => !currentIds.contains(id)).toList();
      final restoreFocus = _focusPruneNeedsRestore;
      final anchorId = _focusPruneAnchorId;
      final anchorIndex = _focusPruneAnchorIndex;
      _focusPruneNeedsRestore = false;
      _focusPruneAnchorId = null;
      _focusPruneAnchorIndex = null;
      for (final id in staleIds) {
        _openFocus.remove(id)?.dispose();
        _stackedActionsFocus.remove(id)?.dispose();
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

  Future<void> _delete(Channel channel, {required FocusNode? invoker}) async {
    if (_saving) return;
    final confirmed = await _confirmChannelDeletion([
      channel,
    ], 'Delete channel');
    if (!mounted) return;
    if (!confirmed) {
      _restoreNavigationFocus(preferredNode: invoker, preferredId: channel.id);
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
  const _MoveChannelDialog({required this.channels, this.movingName});

  final List<Channel> channels;
  final String? movingName;

  @override
  State<_MoveChannelDialog> createState() => _MoveChannelDialogState();
}

class _MoveChannelDialogState extends State<_MoveChannelDialog> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'Move channel search');
  final _sheetSearch = GlobalKey();
  bool _autofocusRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_autofocusRequested && DeviceProfile.of(context).isTv) {
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
    if (widget.movingName case final name?) {
      return _buildSheet(context, name, channels);
    }
    final size = MediaQuery.sizeOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);

    final contentWidth = (size.width - 128).clamp(0.0, 520).toDouble();
    final contentHeight = (size.height - viewInsets.vertical - 200)
        .clamp(0.0, 440)
        .toDouble();

    final searchDecoration = InputDecoration(hintText: 'Search channels');
    final buttonStyle = _channelMoveButtonStyle(context);
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
                autofocus: !DeviceProfile.of(fieldContext).isTv,
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
                          style: buttonStyle,
                          onPressed: () => Navigator.pop(context, (
                            id: channel.id,
                            after: false,
                          )),
                          child: const Text('Before'),
                        ),
                        TextButton(
                          style: buttonStyle,
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
          style: buttonStyle,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
    return dialog;
  }

  Widget _buildSheet(
    BuildContext context,
    String name,
    List<Channel> channels,
  ) {
    final size = MediaQuery.sizeOf(context);
    final keyboard = _moveKeyboardInset(context);
    final height = math.max(0.0, size.height - keyboard) * .9;
    final roles = LineupTheme.of(context);
    final handleHeight = 43 / LineupCanvas.scaleOf(context);
    final touchExtent = _channelTouchExtent(context);
    final textScaler = MediaQuery.textScalerOf(context);
    // Budget the tall header, field and one destination (label and buttons)
    // using the same canvas units as the sheet.
    final searchHeight = math.max(touchExtent, textScaler.scale(16) + 32);
    final resultHeight = math.max(touchExtent, textScaler.scale(18) * 1.4 + 24);
    final compact =
        height - MediaQuery.paddingOf(context).bottom <
        handleHeight + 72 + searchHeight + 8 + resultHeight + touchExtent + 16;
    // The IME can switch header layouts while this field is editing.
    final search = ConstrainedBox(
      key: _sheetSearch,
      constraints: BoxConstraints(minHeight: touchExtent),
      child: TextField(
        key: const Key('channels-move-search'),
        controller: _search,
        focusNode: _searchFocus,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: 'Search channels',
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
    final cancel = TextButton(
      style: compact ? _channelMoveButtonStyle(context) : null,
      onPressed: () => Navigator.pop(context),
      child: const Text('Cancel'),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Material(
        color: roles.elevatedSurface,
        clipBehavior: Clip.antiAlias,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: SizedBox(
          height: height,
          child: SafeArea(
            top: false,
            child: HandheldColumnWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (compact)
                    Row(
                      children: [
                        Expanded(child: search),
                        const SizedBox(width: 8),
                        cancel,
                      ],
                    )
                  else ...[
                    SizedBox(
                      height: handleHeight,
                      child: Center(
                        child: DecoratedBox(
                          decoration: ShapeDecoration(
                            color: roles.mutedText,
                            shape: const StadiumBorder(),
                          ),
                          child: const SizedBox(width: 36, height: 4),
                        ),
                      ),
                    ),
                    HandheldPageBar(title: 'Move $name', actions: [cancel]),
                    search,
                    const SizedBox(height: 8),
                  ],
                  Expanded(
                    child: ListView.builder(
                      itemCount: channels.length,
                      itemBuilder: (context, index) {
                        final channel = channels[index];
                        return Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: compact ? 0 : 8,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              HandheldStackedRow(
                                number: channel.number,
                                name: channel.name,
                                facts: '',
                              ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final after in [false, true])
                                    OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: Size.square(
                                          _channelTouchExtent(context),
                                        ),
                                      ),
                                      onPressed: () => Navigator.pop(context, (
                                        id: channel.id,
                                        after: after,
                                      )),
                                      child: Text(
                                        after ? 'Move after' : 'Move before',
                                        semanticsLabel: after
                                            ? 'Move after ${channel.name}'
                                            : 'Move before ${channel.name}',
                                      ),
                                    ),
                                ],
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
          ),
        ),
      ),
    );
  }
}

class _ChannelDeletionDialog extends StatefulWidget {
  const _ChannelDeletionDialog({
    required this.channels,
    required this.confirmLabel,
    required this.expandActions,
  });

  final List<Channel> channels;
  final String confirmLabel;
  final bool expandActions;

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
    if (!DeviceProfile.of(context).isTv ||
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

    final cancel = TextButton(
      autofocus: true,
      onPressed: () => Navigator.pop(context, false),
      child: const Text('Cancel'),
    );
    final confirm = LineupDestructiveButton(
      onPressed: () => Navigator.pop(context, true),
      child: Text(widget.confirmLabel),
    );

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
                  canRequestFocus: DeviceProfile.of(context).isTv,
                  skipTraversal: !DeviceProfile.of(context).isTv,
                  onKeyEvent: _readSelectedNames,
                  child: ListenableBuilder(
                    listenable: _readerFocus,
                    builder: (context, _) {
                      final fill =
                          DeviceProfile.of(context).isTv &&
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
                              label: DeviceProfile.of(context).isTv
                                  ? 'Selected channels for deletion'
                                  : null,
                              readOnly: DeviceProfile.of(context).isTv
                                  ? true
                                  : null,
                              child: Padding(
                                padding: EdgeInsets.all(
                                  DeviceProfile.of(context).isTv &&
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
                  if (widget.expandActions) ...[
                    LineupTouchTarget(
                      onPressed: cancel.onPressed,
                      child: cancel,
                    ),
                    LineupTouchTarget(
                      onPressed: confirm.onPressed,
                      child: confirm,
                    ),
                  ] else ...[
                    cancel,
                    confirm,
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
