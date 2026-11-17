import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lineup_desktop/platform/device_profile.dart';

import '../channels/channel.dart';
import '../channels/channel_builder.dart';
import '../channels/channel_filter.dart';
import '../playback/player_coordinator.dart';
import '../ui/app_theme.dart';
import '../ui/app_ui.dart';
import '../ui/channel_identity.dart';
import 'channel_health_monitor.dart';
import 'channel_studio_view.dart';
import 'lineup_controller.dart';
import 'navigation_shortcuts.dart';

enum _DirectoryMode { normal, selection, reorder }

enum _DirectoryView { channelOrder, groupedBySource }

typedef _DirectoryGroupHeader = ({String key, String label, int count});

enum _RowAction { watch, favourite, edit, duplicate, delete }

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
  ChannelFilterKey _filter = ChannelFilter.all;
  List<Channel>? _filterLineup;
  late ChannelFilter _channelFilter;
  final _personLabels = StudioPersonLabels();
  _DirectoryMode _mode = _DirectoryMode.normal;
  _DirectoryView _view = _DirectoryView.channelOrder;
  bool _restoredView = false;
  final _openGroups = <String>{'custom'};
  final _groupFocus = <String, FocusNode>{};
  final _scheduleRequests = <String, Channel>{};
  bool _scheduleRequestPending = false;
  Timer? _clockTick;
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
    widget.player.guide.addListener(_guideChanged);
    _clockTick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _view == _DirectoryView.groupedBySource && !_studioOpen) {
        setState(() {});
      }
    });
    _healthMonitor = ChannelHealthMonitor(controller: widget.controller)
      ..addListener(_healthChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restoredView) return;
    _restoredView = true;
    final stored = PageStorage.maybeOf(context)
        ?.readState(context, identifier: 'channels-directory-view');
    if (stored is _DirectoryView) _view = stored;
  }

  void _setView(_DirectoryView view) {
    setState(() => _view = view);
    PageStorage.maybeOf(context)
        ?.writeState(context, view, identifier: 'channels-directory-view');
  }

  void _guideChanged() {
    if (mounted && _view == _DirectoryView.groupedBySource && !_studioOpen) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant ChannelsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.player.guide, widget.player.guide)) {
      oldWidget.player.guide.removeListener(_guideChanged);
      widget.player.guide.addListener(_guideChanged);
    }
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
              title: const Text('Open Update lineup?'),
              content: const Text(
                'Your unsaved Studio draft cannot be carried into Update lineup. Existing custom channels remain protected while you review the proposed roster.',
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
    _clockTick?.cancel();
    widget.player.guide.removeListener(_guideChanged);
    for (final node in _groupFocus.values) {
      node.dispose();
    }
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
    final filter = _filterFor(channels);
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
    final actionLabelStyle = LineupTypography.tvLabelStyle(context);
    final bodyStyle = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(fontSize: 18);

    final page = LineupPage(
      title: 'Manage channels',
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
                                : 'Manage channels',
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
                            child: Text(
                              'Update lineup…',
                              style: actionLabelStyle,
                            ),
                          ),
                          FilledButton(
                            focusNode: _addFocus,
                            onPressed: _saving ? null : openNew,
                            child: Text(
                              'Add a custom channel',
                              style: actionLabelStyle,
                            ),
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
            _directoryControls(matching, filter),
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
                      source: Text(
                        _view == _DirectoryView.groupedBySource
                            ? 'On now'
                            : 'Source',
                      ),
                      playback: const Text('Playback'),
                      action: const SizedBox.shrink(),
                      heading: true,
                    ),
            ),
            const Divider(height: 1),
          ],
          Expanded(
            child: channels.isEmpty
                ? LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            LineupEmptyState(
                              icon: Icons.view_list,
                              title: 'Build your first channel',
                              message: 'Generate a lineup from Plex or create one custom channel.',
                              action: FilledButton.icon(
                                focusNode: widget.focusNode,
                                onPressed: _saving
                                    ? null
                                    : widget.controller.enterChannelSetup,
                                icon: const Icon(Icons.auto_awesome_outlined),
                                label: Text(
                                  'Generate lineup…',
                                  style: actionLabelStyle,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              focusNode: _addFocus,
                              onPressed: _saving ? null : openNew,
                              icon: const Icon(Icons.add),
                              label: Text(
                                'Add a custom channel',
                                style: actionLabelStyle,
                              ),
                            ),
                          ],
                        ),
                      ),
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
                        : 'Adjust the search or channel filter.',
                  )
                : _directoryList(visible),
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

  Widget _directoryList(List<Channel> visible) {
    if (_view == _DirectoryView.channelOrder) {
      return ListView.separated(
        key: const PageStorageKey('channels-directory'),
        itemCount: visible.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) => _channelRow(context, visible[index]),
      );
    }
    final entries = _groupedEntries(visible);
    return ListView.builder(
      key: const PageStorageKey('channels-directory-grouped'),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        if (entry is Channel) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [_channelRow(context, entry), const Divider(height: 1)],
          );
        }
        final group = entry as _DirectoryGroupHeader;
        final expanded = _openGroups.contains(group.key);
        return LineupRowSurface(
          selected: false,
          child: TextButton(
            key: ValueKey('channel-group-${group.key}'),
            focusNode: _groupFocus.putIfAbsent(
              group.key,
              () => FocusNode(debugLabel: '${group.label} group'),
            ),
            onPressed: _saving
                ? null
                : () => setState(() {
                    if (!_openGroups.remove(group.key)) {
                      _openGroups.add(group.key);
                    }
                  }),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(expanded ? Icons.expand_more : Icons.chevron_right),
                  const SizedBox(width: 12),
                  Text(group.label, style: LineupTypography.title(24, 88)),
                  const SizedBox(width: 16),
                  Text(
                    '${group.count} channels',
                    style: TextStyle(
                      color: LineupTheme.of(context).secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Object> _groupedEntries(List<Channel> visible) {
    final groups = <String, List<Channel>>{};
    String keyFor(Channel channel) => channel.builderKey == null
        ? 'custom'
        : channelSourceType(channel)?.name ?? 'custom';
    for (final channel in visible) {
      final key = keyFor(channel);
      (groups[key] ??= []).add(channel);
    }
    const labels = {
      'custom': 'Custom',
      'collections': 'Collections',
      'recentlyAdded': 'Recently added',
      'genres': 'Genres',
      'decades': 'Decades',
      'studios': 'Studios',
      'actors': 'Actors',
      'directors': 'Directors',
      'playlists': 'Playlists',
    };
    final keys = [
      if (groups.containsKey('custom')) 'custom',
      ..._sortedChannels()
          .map(keyFor)
          .where((key) => key != 'custom' && groups.containsKey(key))
          .toSet(),
    ];
    return [
      for (final key in keys) ...[
        (key: key, label: labels[key]!, count: groups[key]!.length),
        if (_openGroups.contains(key)) ...groups[key]!,
      ],
    ];
  }

  void _requestSchedule(Channel channel) {
    _scheduleRequests[channel.id] = channel;
    if (_scheduleRequestPending) return;
    _scheduleRequestPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleRequestPending = false;
      final channels = _scheduleRequests.values.toList();
      _scheduleRequests.clear();
      if (mounted && _view == _DirectoryView.groupedBySource && !_studioOpen) {
        widget.player.guide.requestChannels(channels);
      }
    });
  }

  Widget _onNow(Channel channel, TextStyle? style) {
    final now = widget.clock?.call() ?? DateTime.now();
    final program = widget.player.guide.currentProgram(channel.id, now);
    if (program == null) return Text('—', style: style);
    final minutes = (program.scheduled.end.difference(now).inSeconds / 60)
        .ceil()
        .clamp(0, 999999);
    return Text(
      '${program.scheduled.item.title} · ${minutes}m left',
      key: ValueKey('channel-on-now-${channel.id}'),
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _channelRow(BuildContext menuContext, Channel channel) {
    _noteVisibleHealth(channel.id);
    if (_view == _DirectoryView.groupedBySource) _requestSchedule(channel);
    // The selection-mode checkbox alone shows checked
    // state; the row surface carries focus and hover only.
    return LineupRowSurface(
      selected: false,
      child: Builder(
        builder: (context) {
          final focusedTv =
              DeviceProfile.of(context).isTv &&
              LineupFocusScope.visible(context, Focus.of(context).hasFocus);
          final rowNameStyle = Theme.of(context).textTheme.titleMedium
              ?.copyWith(
                fontSize: _directorySize(22, 16),
                fontWeight: FontWeight.w500,
              );
          final rowSupportStyle = Theme.of(context).textTheme.bodyMedium
              ?.copyWith(
                fontSize: 18,
                color: LineupTheme.of(context).secondaryText,
              );
          final rowFocus = _openFocus.putIfAbsent(
            channel.id,
            () => FocusNode(debugLabel: 'Open ${channel.name}'),
          );
          rowFocus.debugLabel = 'Open ${channel.name}';
          return Material(
            key: ValueKey('channel-row-${channel.id}'),
            color: Colors.transparent,
            child: Tooltip(
              message: _mode == _DirectoryMode.selection
                  ? '${_selectedIds.contains(channel.id) ? 'Deselect' : 'Select'} ${channel.name}'
                  : 'Open ${channel.name}',
              child: _DirectoryRow(
                menuContext: menuContext,
                focusNode: rowFocus,
                channel: channel,
                enabled: !_saving,
                showActions: _mode == _DirectoryMode.normal,
                onActivate: _mode == _DirectoryMode.selection
                    ? () => _toggleSelected(channel.id)
                    : () => _open(channel),
                onLineupMenu: DeviceProfile.of(menuContext).isTv
                    ? () {
                        final anchor = widget.menuFocusNode.context;
                        if (anchor != null) {
                          widget.onOpenMenu(anchor, rowFocus);
                        }
                      }
                    : null,
                onAction: (action) => _applyRowAction(action, channel),
                builder: (action) => _directoryColumns(
                  leading: _mode == _DirectoryMode.selection
                      ? Checkbox(
                          semanticLabel: 'Select ${channel.name}',
                          value: _selectedIds.contains(channel.id),
                          onChanged: _saving
                              ? null
                              : (_) => _toggleSelected(channel.id),
                        )
                      : null,
                  identity: ChannelIdentity(
                    maxLines: null,
                    channel: channel,
                    semanticsContainer: false,
                    libraryTag: ChannelIdentity.libraryTagFor(
                      channel,
                      widget.controller.channels,
                    ),
                    numberWidth: 52 * MediaQuery.textScalerOf(context).scale(1),
                    numberStyle: rowSupportStyle,
                    nameStyle: rowNameStyle,
                    supportStyle: rowSupportStyle,
                  ),
                  name: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_healthMonitor.issueFor(channel.id) == true)
                        Text(
                          'Schedule issue — open this channel to recover',
                          style: rowSupportStyle?.copyWith(
                            color: focusedTv
                                ? LineupTheme.of(context).primaryText
                                : Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                  custom:
                      _view == _DirectoryView.channelOrder &&
                      channel.builderKey == null,
                  favourite: channel.favorite,
                  scheduleIssue: _healthMonitor.issueFor(channel.id) == true,
                  source: _view == _DirectoryView.groupedBySource
                      ? _onNow(channel, rowSupportStyle)
                      : _directorySource(channel, rowSupportStyle),
                  playback: Text(
                    channelRhythmLabel(channel.playbackMode, channel.blockSize),
                    style: rowSupportStyle,
                  ),
                  action: action,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Channel> _sortedChannels() =>
      [...widget.controller.channels]
        ..sort((left, right) => left.number.compareTo(right.number));

  ChannelFilter _filterFor(List<Channel> channels) {
    final lineup = widget.controller.channels;
    if (!identical(_filterLineup, lineup)) {
      _filterLineup = lineup;
      _channelFilter = ChannelFilter(channels);
      if (!_channelFilter.entries.any((entry) => entry.key == _filter)) {
        _filter = ChannelFilter.all;
      }
    }
    return _channelFilter;
  }

  List<Channel> _matchingChannels(List<Channel> channels) {
    final query = _search.text.trim().toLowerCase();
    return _filterFor(channels)
        .channelsFor(_filter)
        .where(
          (channel) =>
              query.isEmpty ||
              channel.name.toLowerCase().contains(query) ||
              channel.number.toString().contains(query),
        )
        .toList(growable: false);
  }

  Future<void> _applyRowAction(_RowAction action, Channel channel) async {
    switch (action) {
      case _RowAction.watch:
        unawaited(widget.player.tune(channel.id));
        widget.onOpenPlayer();
      case _RowAction.favourite:
        final row = _openFocus[channel.id];
        final rowScope = row?.enclosingScope;
        final index = _visibleChannels().indexWhere(
          (row) => row.id == channel.id,
        );
        try {
          await widget.controller.setFavorite(channel.id, !channel.favorite);
          if (!mounted) return;
          setState(() => _error = null);
          if (channel.favorite) {
            _restoreNavigationFocus(
              preferredId: channel.id,
              preferredIndex: index,
              visibleIndex: true,
              canRestore: () {
                // setFavorite publishes at the end of its queued operation, so
                // the departing row may have left primary focus null by now.
                final primary = FocusManager.instance.primaryFocus;
                return primary == null ||
                    identical(primary, rowScope) ||
                    identical(primary, FocusManager.instance.rootScope) ||
                    (row?.hasFocus ?? false);
              },
            );
          }
        } catch (_) {
          if (mounted) {
            setState(() => _error = 'The favourite could not be saved.');
          }
        }
      case _RowAction.edit:
        _open(channel);
      case _RowAction.duplicate:
        _openDuplicate(channel);
      case _RowAction.delete:
        await _delete(channel);
    }
  }

  Widget _directorySource(Channel channel, TextStyle? style) {
    final source = channel.source;
    final type = switch (channelSourceType(channel)) {
      BuilderStrategy.collections => 'Collection',
      BuilderStrategy.recentlyAdded => 'Recently added',
      BuilderStrategy.genres => 'Genre',
      BuilderStrategy.studios => 'Studio',
      BuilderStrategy.actors => 'Actor',
      BuilderStrategy.decades => 'Decade',
      BuilderStrategy.directors => 'Director',
      BuilderStrategy.playlists => 'Playlist',
      null => _directorySourceType(source),
    };
    final savedLibraries = channel.sourceLibraries.values;
    final sourceLibraryIds = channelSourceLibraryIds(source);
    final libraryTitles = savedLibraries.isNotEmpty
        ? savedLibraries
        : widget.controller.libraries
              .where((library) => sourceLibraryIds.contains(library.id))
              .map((library) => library.title);
    final libraries = libraryTitles.toSet().join(', ');
    final text = Text(
      libraries.isEmpty ? type : '$type · $libraries',
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    final people = _directorySourcePeople(source).toSet();
    return people.isEmpty
        ? text
        : Tooltip(message: people.join(', '), child: text);
  }

  Iterable<String> _directorySourcePeople(ContentSource source) sync* {
    if (source case MixedSource(:final sources)) {
      for (final child in sources) {
        yield* _directorySourcePeople(child);
      }
    } else if (source case LibrarySource(:final libraryId, :final filters)) {
      for (final filter in [LibraryFilter.actor, LibraryFilter.director]) {
        for (final value in filters[filter] ?? const <String>[]) {
          yield _personLabels.label(
            widget.controller,
            libraryId,
            filter,
            value,
          );
        }
      }
    }
  }

  String _directorySourceType(ContentSource source) => switch (source) {
    LibrarySource(:final filters, :final order) =>
      order == LibraryOrder.addedDescending && filters.isEmpty
          ? 'Recently added'
          : switch (filters.keys.singleOrNull) {
              LibraryFilter.collection => 'Collection',
              LibraryFilter.genre => 'Genre',
              LibraryFilter.studio => 'Studio',
              LibraryFilter.actor => 'Actor',
              LibraryFilter.director => 'Director',
              LibraryFilter.decade => 'Decade',
              null => filters.isEmpty ? 'Library' : 'Filtered library',
            },
    PlaylistSource() => 'Playlist',
    ManualSource() => 'Hand-picked',
    MixedSource() => 'Mixed sources',
  };

  List<Channel> _visibleChannels() {
    final channels = _sortedChannels();
    final matching = _matchingChannels(channels);
    final visible = _showSelected
        ? channels
              .where((channel) => _selectedIds.contains(channel.id))
              .toList(growable: false)
        : matching;
    if (_view == _DirectoryView.channelOrder) return visible;
    return _groupedEntries(visible).whereType<Channel>().toList();
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
    bool visibleIndex = false,
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
    if (visibleIndex && preferredIndex != null) {
      final nearest = attached.reduce(
        (best, candidate) =>
            (candidate - preferredIndex).abs() < (best - preferredIndex).abs()
            ? candidate
            : best,
      );
      return _openFocus[visible[nearest].id];
    }
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
    bool visibleIndex = false,
    bool Function()? canRestore,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _studioOpen || canRestore?.call() == false) return;
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
                  visibleIndex: visibleIndex,
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
    Widget? number,
    required Widget name,
    ChannelIdentity? identity,
    required Widget source,
    required Widget playback,
    bool custom = false,
    bool favourite = false,
    bool scheduleIssue = false,
    required Widget action,
    Widget? leading,
    bool heading = false,
  }) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final numberWidth = 52 * textScale;
    final tv = DeviceProfile.of(context).isTv;
    final rowHeight = tv ? 72.0 : _directorySize(80, 68);
    return ConstrainedBox(
      constraints: heading
          ? const BoxConstraints()
          : BoxConstraints(
              minHeight: rowHeight,
              maxHeight: scheduleIssue ? double.infinity : rowHeight,
            ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: heading || tv ? 8 : 10,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final lead = leading == null ? 0 : (36 + 16);
            final flexSpace =
                constraints.maxWidth - lead - numberWidth - 16 - 16 * 4 - 44;
            final identityWidth =
                numberWidth +
                16 +
                4 * (flexSpace.clamp(0.0, double.infinity) / 9);
            return Row(
              children: [
                if (leading != null) ...[
                  SizedBox(width: 36, child: leading),
                  SizedBox(width: 16),
                ],
                if (identity == null) ...[
                  SizedBox(width: numberWidth, child: number),
                  SizedBox(width: 16),
                  SizedBox(
                    width: identityWidth - numberWidth - 16,
                    child: name,
                  ),
                ] else
                  SizedBox(
                    width: identityWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (scheduleIssue)
                          _DirectoryChannelIdentity(
                            identity: identity,
                            custom: custom,
                            favourite: favourite,
                          )
                        else
                          Flexible(
                            child: _DirectoryChannelIdentity(
                              identity: identity,
                              custom: custom,
                              favourite: favourite,
                            ),
                          ),
                        Padding(
                          padding: EdgeInsetsDirectional.only(
                            start: identity.nameIndent(context),
                          ),
                          child: name,
                        ),
                      ],
                    ),
                  ),
                SizedBox(width: 16),
                Expanded(flex: 3, child: source),
                SizedBox(width: 16),
                Expanded(flex: 2, child: playback),
                SizedBox(width: 16),
                SizedBox(width: 44, child: action),
              ],
            );
          },
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

  Widget _directoryToolbar(ChannelFilter filter) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final entries = filter.entries;
    final tv = DeviceProfile.of(context).isTv;
    final roles = LineupTheme.of(context);
    final menuTheme = tv ? Theme.of(context) : null;
    final filters = SizedBox(
      width: 180 * textScale.clamp(1, 1.5),
      child: LineupDropdownBox(
        compact: true,
        enabled: !_saving,
        child: Builder(
          builder: (context) => DropdownButton<ChannelFilterKey>(
            key: const Key('channels-filter'),
            value: _filter,
            isExpanded: true,
            style: tv
                ? _channelBodyStyle(context)
                      .copyWith(color: LineupTheme.of(context).primaryText)
                : null,
            iconEnabledColor: tv ? LineupTheme.of(context).secondaryText : null,
            selectedItemBuilder: (_) => [
              for (final entry in entries)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    entry.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            underline: const SizedBox.shrink(),
            dropdownColor: roles.elevatedSurface,
            borderRadius: BorderRadius.circular(roles.panelRadius),
            items: lineupMenuItems(
              [
                for (final entry in entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(
                      entry.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              _filter,
              menuTheme: menuTheme,
            ),
            onChanged: _saving
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _filter = value;
                      _showSelected = false;
                    });
                  },
          ),
        ),
      ),
    );
    final viewStyle = tv
        ? _channelBodyStyle(context).copyWith(color: roles.primaryText)
        : Theme.of(context).textTheme.titleMedium!;
    const viewLabels = ['Channel order', 'Grouped by source'];
    final viewLabelWidth = viewLabels
        .map(
          (label) => TextPainter.computeWidth(
            text: TextSpan(text: label, style: viewStyle),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            locale: Localizations.maybeLocaleOf(context),
          ),
        )
        .reduce((a, b) => a > b ? a : b);
    // Include the trigger's box/icon and the popup row's normal insets. The
    // decorated menu row is not also the closed selector's value widget.
    final viewWidth =
        viewLabelWidth +
        LineupDropdownBox.contentPadding(compact: true).horizontal +
        LineupDropdownBox.borderWidth * 2 +
        24 +
        LineupDropdownMenuRow.contentPadding.horizontal +
        32;
    final viewLine = TextPainter(
      text: TextSpan(text: 'M', style: viewStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final viewItemHeight =
        (viewLine.height + LineupDropdownMenuRow.contentPadding.vertical).clamp(
          kMinInteractiveDimension,
          double.infinity,
        );
    viewLine.dispose();
    final view = SizedBox(
      width: viewWidth,
      child: LineupDropdownBox(
        compact: true,
        enabled: !_saving,
        child: Builder(
          builder: (context) => DropdownButton<_DirectoryView>(
            key: const Key('channels-view'),
            value: _view,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            dropdownColor: roles.elevatedSurface,
            style: tv
                ? _channelBodyStyle(context)
                      .copyWith(color: LineupTheme.of(context).primaryText)
                : viewStyle,
            iconEnabledColor: tv ? LineupTheme.of(context).secondaryText : null,
            // A finite item height keeps DropdownButton's selected row and
            // arrow centered inside the outer box, including scaled text.
            itemHeight: viewItemHeight,
            selectedItemBuilder: (_) => [
              for (final label in viewLabels)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            borderRadius: BorderRadius.circular(roles.panelRadius),
            items: lineupMenuItems(
              const [
                DropdownMenuItem(
                  value: _DirectoryView.channelOrder,
                  child: Text(
                    'Channel order',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(
                  value: _DirectoryView.groupedBySource,
                  child: Text(
                    'Grouped by source',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              _view,
              menuTheme: menuTheme,
            ),
            onChanged: _saving
                ? null
                : (value) {
                    if (value != null) _setView(value);
                  },
          ),
        ),
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
              view,
              SizedBox(width: 8),
              if (_mode == _DirectoryMode.normal) ...[
                const SizedBox(height: 28, child: VerticalDivider(width: 16)),
                ...actions,
              ],
            ],
          );
        }
        final desiredWidth =
            constraints.maxWidth - 530 * textScale - viewWidth - 8;
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
            view,
            if (_mode == _DirectoryMode.normal) ...[
              const SizedBox(height: 28, child: VerticalDivider(width: 16)),
              ...actions,
            ],
          ],
        );
      },
    );
  }

  Widget _directoryControls(List<Channel> matching, ChannelFilter filter) {
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
            _directoryToolbar(filter),
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

  void _beginReorder() {
    _setView(_DirectoryView.channelOrder);
    setState(() {
      _mode = _DirectoryMode.reorder;
      _reorderBase = [...widget.controller.channels]
        ..sort((a, b) => a.number.compareTo(b.number));
      _reorderIds = _reorderBase.map((channel) => channel.id).toList();
    });
  }

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
            name: channel.builderKey == null
                ? _DirectoryCustomIdentity(
                    name: channel.name,
                    nameStyle: rowNameStyle,
                    supportStyle: rowSupportStyle,
                  )
                : Text(channel.name, style: rowNameStyle, softWrap: true),
            source: _directorySource(channel, rowSupportStyle),
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
                    title: ChannelIdentity(
                      maxLines: null,
                      channel: channel,
                      libraryTag: ChannelIdentity.libraryTagFor(
                        channel,
                        widget.channels,
                      ),
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
          child: Text('Cancel', style: LineupTypography.tvLabelStyle(context)),
        ),
      ],
    );
    return dialog;
  }
}

/// Reserves the row markers before fitting the name to the existing row height.
class _DirectoryChannelIdentity extends StatelessWidget {
  const _DirectoryChannelIdentity({
    required this.identity,
    required this.custom,
    required this.favourite,
  });

  final ChannelIdentity identity;
  final bool custom;
  final bool favourite;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final support = identity.supportStyle;
    return Semantics(
      label: [
        ChannelIdentity.label(
          identity.channel,
          libraryTag: identity.libraryTag,
        ),
        if (custom) 'Custom',
        if (favourite) 'Favourite',
      ].join(', '),
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final text = TextPainter(
            text: TextSpan(
              text: 'M',
              style: DefaultTextStyle.of(context).style
                  .merge(identity.nameStyle),
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          int lines;
          if (constraints.hasBoundedHeight) {
            lines = (constraints.maxHeight / text.preferredLineHeight)
                .floor()
                .clamp(1, 2);
          } else {
            // Recovery rows already reserve space for a health line. Markers may
            // truncate the name, but must not add lines to that existing state.
            final room = (constraints.maxWidth - identity.nameIndent(context))
                .clamp(0.0, double.infinity);
            final style = DefaultTextStyle.of(context).style
                .merge(identity.nameStyle);
            final longestWord = identity.channel.name
                .split(RegExp(r'\s+'))
                .map(
                  (word) => TextPainter.computeWidth(
                    text: TextSpan(text: word, style: style),
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                  ),
                )
                .fold(0.0, (a, b) => a > b ? a : b);
            if (longestWord > room) {
              lines = 1;
            } else {
              final baseline = TextPainter(
                text: TextSpan(text: identity.channel.name, style: style),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout(maxWidth: room);
              lines = baseline.computeLineMetrics().length.clamp(1, 1000);
              baseline.dispose();
            }
          }
          text.dispose();
          return Row(
            children: [
              Flexible(
                child: ChannelIdentity(
                  channel: identity.channel,
                  numberWidth: identity.numberWidth,
                  nameStyle: identity.nameStyle,
                  numberStyle: identity.numberStyle,
                  supportStyle: support,
                  maxLines: lines,
                  showSemantics: false,
                ),
              ),
              if (identity.libraryTag case final library?) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * .3,
                  ),
                  child: Text(
                    library,
                    style: support,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              if (custom) ...[
                const SizedBox(width: 8),
                Container(
                  key: ValueKey('channel-custom-${identity.channel.id}'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: roles.defaultBorder),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Custom',
                    style: support?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              if (favourite) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.star,
                  key: ValueKey('channel-favourite-${identity.channel.id}'),
                  size: 18,
                  color: roles.progressFill,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DirectoryCustomIdentity extends StatelessWidget {
  const _DirectoryCustomIdentity({
    required this.name,
    required this.nameStyle,
    required this.supportStyle,
  });

  final String name;
  final TextStyle? nameStyle;
  final TextStyle? supportStyle;

  @override
  Widget build(BuildContext context) {
    const gap = 8.0;
    final baseStyle = DefaultTextStyle.of(context).style;
    final support = baseStyle.merge(supportStyle);
    final tagStyle = support.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );
    final labelStyle = baseStyle.merge(nameStyle);
    final textScaler = MediaQuery.textScalerOf(context);
    double measure(String value, TextStyle style) => TextPainter.computeWidth(
      text: TextSpan(text: value, style: style),
      textDirection: Directionality.of(context),
      textScaler: textScaler,
      locale: Localizations.maybeLocaleOf(context),
    );
    final label = Text(name, style: nameStyle, softWrap: true);
    return LayoutBuilder(
      builder: (context, constraints) {
        final requiredWidth =
            measure(name, labelStyle) + gap + measure('Custom', tagStyle);
        if (requiredWidth > constraints.maxWidth) return label;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(child: label),
            const SizedBox(width: gap),
            Text('Custom', style: tagStyle),
          ],
        );
      },
    );
  }
}

class _DirectoryRow extends StatefulWidget {
  const _DirectoryRow({
    required this.menuContext,
    required this.focusNode,
    required this.channel,
    required this.enabled,
    required this.showActions,
    required this.onActivate,
    required this.onAction,
    required this.onLineupMenu,
    required this.builder,
  });

  final BuildContext menuContext;
  final FocusNode focusNode;
  final Channel channel;
  final bool enabled;
  final bool showActions;
  final VoidCallback onActivate;
  final Future<void> Function(_RowAction) onAction;
  final VoidCallback? onLineupMenu;
  final Widget Function(Widget action) builder;

  @override
  State<_DirectoryRow> createState() => _DirectoryRowState();
}

class _DirectoryRowState extends State<_DirectoryRow> {
  final _actionKey = GlobalKey();
  final _actionFocus = FocusNode(debugLabel: 'Channel actions');
  Timer? _selectHold;
  LogicalKeyboardKey? _heldKey;
  bool _menuOpen = false;

  @override
  void dispose() {
    _selectHold?.cancel();
    _actionFocus.dispose();
    super.dispose();
  }

  void _rowFocusChanged(bool focused) {
    if (focused) return;
    _selectHold?.cancel();
    _selectHold = null;
    _heldKey = null;
  }

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    if (!widget.enabled || !widget.showActions) {
      return KeyEventResult.ignored;
    }
    final tv = DeviceProfile.of(context).isTv;
    final key = event.logicalKey;
    final select =
        key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter;
    if (tv && _actionFocus.hasPrimaryFocus) {
      if (select) {
        if (event is KeyDownEvent) unawaited(_openMenu());
        return KeyEventResult.handled;
      }
      if (event is KeyDownEvent && key == LogicalKeyboardKey.arrowLeft) {
        widget.focusNode.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (!widget.focusNode.hasPrimaryFocus) return KeyEventResult.ignored;
    if (!tv) {
      if (event is KeyDownEvent &&
          (key == LogicalKeyboardKey.contextMenu ||
              (key == LogicalKeyboardKey.f10 &&
                  HardwareKeyboard.instance.isShiftPressed))) {
        unawaited(_openMenu());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent && key == LogicalKeyboardKey.arrowRight) {
      _actionFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (!select) return KeyEventResult.ignored;
    if (event is KeyDownEvent && _heldKey == null) {
      _heldKey = key;
      _selectHold = Timer(kLongPressTimeout, () {
        _selectHold = null;
        if (widget.focusNode.hasPrimaryFocus) unawaited(_openMenu());
      });
    } else if (event is KeyUpEvent && key == _heldKey) {
      final shortPress = _selectHold?.isActive == true;
      _selectHold?.cancel();
      _selectHold = null;
      _heldKey = null;
      if (shortPress) widget.onActivate();
    }
    return KeyEventResult.handled;
  }

  Future<void> _openMenu() async {
    if (!widget.enabled || !widget.showActions || _menuOpen) return;
    final anchor = _actionKey.currentContext?.findRenderObject() as RenderBox?;
    final navigator = Navigator.of(context);
    final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
    if (anchor == null || !anchor.attached) return;
    final topLeft = anchor.localToGlobal(Offset.zero, ancestor: overlay);
    final channel = widget.channel;
    final onAction = widget.onAction;
    _menuOpen = true;
    var openLineupMenu = false;
    void requestLineupMenu() => openLineupMenu = true;
    final onMenu = widget.onLineupMenu == null ? null : requestLineupMenu;
    final action = await showMenu<_RowAction>(
      // Capture the list theme above the row's temporary TV focus ink.
      context: widget.menuContext,
      requestFocus: true,
      position: RelativeRect.fromSize(topLeft & anchor.size, overlay.size),
      menuPadding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 224, maxWidth: 320),
      items: [
        _DirectoryMenuItem(
          _RowAction.watch,
          'Watch',
          autofocus: true,
          onMenu: onMenu,
        ),
        _DirectoryMenuItem(
          _RowAction.favourite,
          channel.favorite ? 'Remove from favourites' : 'Favourite',
          onMenu: onMenu,
        ),
        if (channel.builderKey == null)
          _DirectoryMenuItem(_RowAction.edit, 'Edit', onMenu: onMenu)
        else
          _DirectoryMenuItem(
            _RowAction.duplicate,
            'Duplicate as custom',
            onMenu: onMenu,
          ),
        _DirectoryMenuItem(_RowAction.delete, 'Delete…', onMenu: onMenu),
      ],
    );
    _menuOpen = false;
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
    widget.focusNode.requestFocus();
    if (openLineupMenu) {
      widget.onLineupMenu?.call();
      return;
    }
    if (action != null && widget.enabled && widget.showActions) {
      await onAction(action);
    }
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: _key,
    child: InkWell(
      focusNode: widget.focusNode,
      onFocusChange: _rowFocusChanged,
      onTap: widget.enabled ? widget.onActivate : null,
      onSecondaryTap:
          widget.enabled &&
              widget.showActions &&
              !DeviceProfile.of(context).isTv
          ? _openMenu
          : null,
      child: widget.builder(
        widget.showActions
            ? IconButton(
                key: _actionKey,
                focusNode: _actionFocus,
                tooltip: 'Actions for ${widget.channel.name}',
                onPressed: widget.enabled ? _openMenu : null,
                padding: const EdgeInsets.all(8),
                icon: Icon(
                  Icons.more_vert,
                  size: 24,
                  semanticLabel: 'Actions for ${widget.channel.name}',
                ),
              )
            : const SizedBox.shrink(),
      ),
    ),
  );
}

class _DirectoryMenuItem extends PopupMenuItem<_RowAction> {
  const _DirectoryMenuItem(
    _RowAction action,
    this.label, {
    this.autofocus = false,
    this.onMenu,
  }) : super(value: action, height: 48, child: null);

  final String label;
  final bool autofocus;
  final VoidCallback? onMenu;

  @override
  PopupMenuItemState<_RowAction, _DirectoryMenuItem> createState() =>
      _DirectoryMenuItemState();
}

class _DirectoryMenuItemState
    extends PopupMenuItemState<_RowAction, _DirectoryMenuItem> {
  KeyEventResult _key(FocusNode _, KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.contextMenu &&
        widget.onMenu != null &&
        ModalRoute.of(context)?.isCurrent == true) {
      if (event is KeyDownEvent) {
        widget.onMenu!();
        Navigator.pop(context);
      }
      return KeyEventResult.handled;
    }
    final select =
        key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter;
    if (key != LogicalKeyboardKey.goBack &&
        key != LogicalKeyboardKey.escape &&
        !select) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      if (select) {
        if (widget.enabled) handleTap();
      } else {
        Navigator.pop(context);
      }
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: _key,
    child: MergeSemantics(
      child: buildSemantics(
        child: InkWell(
          autofocus: widget.enabled && widget.autofocus,
          canRequestFocus: widget.enabled,
          onTap: widget.enabled ? handleTap : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: widget.height),
            child: Center(
              child: LineupDropdownMenuRow(
                selected: false,
                child: SizedBox(
                  width: double.infinity,
                  child: Builder(
                    builder: (context) => Text(
                      widget.label,
                      style: LineupTypography.control.copyWith(
                        color: LineupTheme.of(context).primaryText,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
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
