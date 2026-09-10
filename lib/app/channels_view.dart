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
    final scale = LineupLayout.scaleFor(MediaQuery.sizeOf(context));
    if (_healthContentGeneration != widget.controller.contentGeneration) {
      _healthContentGeneration = widget.controller.contentGeneration;
      _healthEpoch++;
      _health.clear();
      _pendingHealth.clear();
    }
    _pruneHealth(liveIds);
    _scheduleFocusPrune(liveIds);
    final headingStyle = Theme.of(context).textTheme.headlineMedium?.copyWith(
      fontSize: _directorySize(36, 28) * scale,
      fontWeight: FontWeight.w600,
    );
    final countStyle = Theme.of(context).textTheme.headlineMedium?.copyWith(
      fontSize: _directorySize(28, 24) * scale,
      fontWeight: FontWeight.w400,
      color: LineupTheme.of(context).secondaryText,
    );
    final bodyStyle = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(fontSize: _directorySize(18, 14) * scale);
    final labelStyle = Theme.of(context).textTheme.labelLarge
        ?.copyWith(fontSize: _directorySize(18, 14) * scale);
    return LineupPage(
      title: 'Channels',
      titleWidget: Row(
        children: [
          Builder(
            builder: (buttonContext) => Tooltip(
              message: 'Open Lineup menu',
              child: TextButton.icon(
                key: const Key('channels-app-menu'),
                focusNode: widget.menuFocusNode,
                onPressed: () =>
                    widget.onOpenMenu(buttonContext, widget.menuFocusNode),
                icon: const Icon(Icons.menu),
                label: const Text('LINEUP'),
              ),
            ),
          ),
          const SizedBox(width: 16),
          const SizedBox(height: 24, child: VerticalDivider(width: 1)),
          const SizedBox(width: 16),
          Text('Channels', style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
      child: Column(
        children: [
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.symmetric(
              vertical: _directorySize(24, 16) * scale,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            _mode == _DirectoryMode.reorder
                                ? 'Reorder channels'
                                : 'Channels',
                            style: headingStyle,
                          ),
                          const SizedBox(width: 12),
                          Text('${channels.length}', style: countStyle),
                        ],
                      ),
                      const SizedBox(height: 6),
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
                            style: OutlinedButton.styleFrom(
                              minimumSize: Size(0, 48 * scale),
                              textStyle: labelStyle,
                            ),
                            child: const Text('Generate lineup'),
                          ),
                          FilledButton(
                            onPressed: _saving ? null : openNew,
                            style: FilledButton.styleFrom(
                              minimumSize: Size(0, 48 * scale),
                              textStyle: labelStyle,
                            ),
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
            const SizedBox(height: 12),
          ],
          if (channels.isNotEmpty) ...[
            _directoryControls(matching),
            const SizedBox(height: 20),
            DefaultTextStyle.merge(
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: _directorySize(18, 14) * scale,
                color: LineupTheme.of(context).secondaryText,
              ),
              child: _mode == _DirectoryMode.reorder
                  ? _reorderColumns(
                      scale: scale,
                      drag: const SizedBox.shrink(),
                      number: const Text('Number'),
                      name: const Text('Channel'),
                      source: const Text('Source'),
                      playback: const Text('Playback'),
                      action: const Text('Move'),
                      heading: true,
                    )
                  : _directoryColumns(
                      scale: scale,
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
                ? _reorderList(channels, scale)
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
                            fontSize: _directorySize(22, 16) * scale,
                            fontWeight: FontWeight.w500,
                          );
                      final rowSupportStyle = Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                            fontSize: _directorySize(18, 14) * scale,
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
                      return Material(
                        key: ValueKey('channel-row-${channel.id}'),
                        color: _selectedIds.contains(channel.id)
                            ? Theme.of(context).colorScheme.primary
                                  .withValues(alpha: 0.08)
                            : Colors.transparent,
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
                              scale: scale,
                              leading: _mode == _DirectoryMode.selection
                                  ? Checkbox(
                                      semanticLabel: 'Select ${channel.name}',
                                      value: _selectedIds.contains(channel.id),
                                      onChanged: _saving
                                          ? null
                                          : (_) => _toggleSelected(channel.id),
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
                                      onSelected: (action) => switch (action) {
                                        _RowAction.duplicate => _openDuplicate(
                                          channel,
                                        ),
                                        _RowAction.delete => _delete(channel),
                                      },
                                      itemBuilder: (_) => [
                                        if (channel.builderKey != null)
                                          const PopupMenuItem(
                                            value: _RowAction.duplicate,
                                            child: Text('Duplicate as custom'),
                                          ),
                                        const PopupMenuItem(
                                          value: _RowAction.delete,
                                          child: Text('Delete'),
                                        ),
                                      ],
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
    required double scale,
    required Widget number,
    required Widget name,
    required Widget source,
    required Widget playback,
    required Widget type,
    required Widget action,
    Widget? leading,
    bool heading = false,
  }) => ConstrainedBox(
    constraints: heading
        ? const BoxConstraints()
        : BoxConstraints(minHeight: _directorySize(80, 68) * scale),
    child: Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 12 * scale,
        vertical: (heading ? 8 : 10) * scale,
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            SizedBox(width: 36 * scale, child: leading),
            SizedBox(width: 16 * scale),
          ],
          SizedBox(width: 52 * scale, child: number),
          SizedBox(width: 16 * scale),
          Expanded(flex: 4, child: name),
          SizedBox(width: 16 * scale),
          Expanded(flex: 2, child: source),
          SizedBox(width: 16 * scale),
          Expanded(flex: 2, child: playback),
          SizedBox(width: 16 * scale),
          Expanded(child: type),
          SizedBox(width: 16 * scale),
          SizedBox(width: 44 * scale, child: action),
        ],
      ),
    ),
  );

  Widget _reorderColumns({
    required double scale,
    required Widget drag,
    required Widget number,
    required Widget name,
    required Widget source,
    required Widget playback,
    required Widget action,
    bool heading = false,
  }) => DecoratedBox(
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
          : BoxConstraints(minHeight: _directorySize(80, 68) * scale),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 12 * scale,
          vertical: (heading ? 8 : 10) * scale,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: 36 * scale, child: drag),
            SizedBox(width: 16 * scale),
            SizedBox(width: 76 * scale, child: number),
            SizedBox(width: 16 * scale),
            Expanded(flex: 4, child: name),
            SizedBox(width: 16 * scale),
            Expanded(flex: 2, child: source),
            SizedBox(width: 16 * scale),
            Expanded(flex: 2, child: playback),
            SizedBox(width: 16 * scale),
            SizedBox(width: 144 * scale, child: action),
          ],
        ),
      ),
    ),
  );

  double _directorySize(double expanded, double compact) =>
      LineupLayout.isCompactWidth(MediaQuery.sizeOf(context).width)
      ? compact
      : expanded;

  TextStyle _channelBodyStyle(BuildContext context) {
    final scale = LineupLayout.scaleFor(MediaQuery.sizeOf(context));
    return Theme.of(context).textTheme.bodyMedium
            ?.copyWith(fontSize: _directorySize(18, 14) * scale) ??
        TextStyle(fontSize: _directorySize(18, 14) * scale);
  }

  TextStyle _channelControlStyle(BuildContext context) {
    final scale = LineupLayout.scaleFor(MediaQuery.sizeOf(context));
    return Theme.of(context).textTheme.labelLarge
            ?.copyWith(fontSize: _directorySize(18, 14) * scale) ??
        TextStyle(fontSize: _directorySize(18, 14) * scale);
  }

  ButtonStyle _channelQuietButtonStyle(BuildContext context) {
    final scale = LineupLayout.scaleFor(MediaQuery.sizeOf(context));
    return TextButton.styleFrom(
      minimumSize: Size(0, 48 * scale),
      padding: EdgeInsets.symmetric(
        horizontal: 16 * scale,
        vertical: 10 * scale,
      ),
      visualDensity: VisualDensity.standard,
      foregroundColor: LineupTheme.of(context).secondaryText,
      textStyle: _channelControlStyle(context),
    );
  }

  ButtonStyle _channelFilterStyle(BuildContext context) {
    final scale = LineupLayout.scaleFor(MediaQuery.sizeOf(context));
    final roles = LineupTheme.of(context);
    return ButtonStyle(
      padding: LineupLayout.isCompactWidth(MediaQuery.sizeOf(context).width)
          ? null
          : WidgetStatePropertyAll(
              EdgeInsets.symmetric(
                horizontal: 16 * scale,
                vertical: 11 * scale,
              ),
            ),
      visualDensity: VisualDensity.standard,
      tapTargetSize:
          LineupLayout.isCompactWidth(MediaQuery.sizeOf(context).width)
          ? null
          : MaterialTapTargetSize.shrinkWrap,
      textStyle: WidgetStatePropertyAll(_channelControlStyle(context)),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? roles.mutedText
            : states.contains(WidgetState.selected)
            ? roles.primaryText
            : roles.secondaryText,
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? roles.selectedSurface
            : Colors.transparent,
      ),
      side: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? BorderSide(
                color: roles.focusBorder,
                width: roles.focusBorderWidth,
              )
            : BorderSide.none,
      ),
    );
  }

  Widget _directoryToolbar() {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final filters = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: LineupLayout.isCompactWidth(MediaQuery.sizeOf(context).width)
            ? 0
            : 48 * LineupLayout.scaleFor(MediaQuery.sizeOf(context)),
      ),
      child: SegmentedButton<_DirectoryFilter>(
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
        style: _channelFilterStyle(context),
        onSelectionChanged: _saving
            ? null
            : (value) => setState(() {
                _filter = value.single;
                _showSelected = false;
              }),
      ),
    );
    final actions = [
      TextButton(
        onPressed: _saving
            ? null
            : () => setState(() {
                _mode = _DirectoryMode.selection;
                _selectedIds.clear();
              }),
        style: _channelQuietButtonStyle(context),
        child: const Text('Select'),
      ),
      TextButton(
        onPressed: _saving ? null : _beginReorder,
        style: _channelQuietButtonStyle(context),
        child: const Text('Reorder channels'),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = LineupLayout.scaleFor(MediaQuery.sizeOf(context));
        final search = TextField(
          key: const Key('channels-search'),
          enabled: !_saving,
          controller: _search,
          focusNode: _searchFocus,
          style: _channelBodyStyle(context),
          decoration: InputDecoration(
            hintText: 'Search by name or number',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 16 * scale,
              vertical: 11 * scale,
            ),
            constraints: BoxConstraints(minHeight: 48 * scale),
          ),
          onChanged: (_) => setState(() {}),
        );
        final wide = constraints.maxWidth >= 1200 * scale && textScale < 1.4;
        if (wide) {
          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 8),
              filters,
              const SizedBox(width: 8),
              if (_mode == _DirectoryMode.normal) ...actions,
            ],
          );
        }
        final desiredWidth = constraints.maxWidth - 530 * textScale;
        final searchWidth = constraints.maxWidth < 280
            ? constraints.maxWidth
            : desiredWidth.clamp(280.0, constraints.maxWidth).toDouble();
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(width: searchWidth, child: search),
            filters,
            if (_mode == _DirectoryMode.normal) ...actions,
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
      final scale = LineupLayout.scaleFor(MediaQuery.sizeOf(context));
      return Column(
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
                  style: _channelQuietButtonStyle(context).copyWith(
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(
                        horizontal: 16 * scale,
                        vertical: 16 * scale,
                      ),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: changed && !_saving ? _saveOrder : null,
                  style: FilledButton.styleFrom(
                    minimumSize: Size(
                      0,
                      48 * LineupLayout.scaleFor(MediaQuery.sizeOf(context)),
                    ),
                    textStyle: _channelControlStyle(context),
                  ),
                  child: Text(_saving ? 'Saving…' : 'Save order'),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_showSelected)
          Text('Selected channels', style: _channelBodyStyle(context))
        else
          _directoryToolbar(),
        if (_mode == _DirectoryMode.selection) ...[
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = LineupLayout.scaleFor(MediaQuery.sizeOf(context));
              final leading = Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton(
                    onPressed: _saving || _selectedIds.isEmpty
                        ? null
                        : () => setState(() => _showSelected = true),
                    style: _channelQuietButtonStyle(context),
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
                      style: _channelQuietButtonStyle(context),
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
                      style: _channelQuietButtonStyle(context),
                      child: const Text('Select all matching'),
                    ),
                  TextButton(
                    onPressed: _saving || _selectedIds.isEmpty
                        ? null
                        : () => setState(_selectedIds.clear),
                    style: _channelQuietButtonStyle(context),
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
                    style: _channelQuietButtonStyle(context).copyWith(
                      padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(
                          horizontal: 16 * scale,
                          vertical: 16 * scale,
                        ),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                  OutlinedButton(
                    onPressed: _selectedIds.isEmpty || _saving
                        ? null
                        : _deleteSelected,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                      minimumSize: Size(
                        0,
                        48 * LineupLayout.scaleFor(MediaQuery.sizeOf(context)),
                      ),
                      textStyle: _channelControlStyle(context),
                    ),
                    child: Text(_saving ? 'Deleting…' : 'Delete selected'),
                  ),
                ],
              );
              if (constraints.maxWidth < 760) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    leading,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: trailing),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: leading),
                  const SizedBox(width: 12),
                  trailing,
                ],
              );
            },
          ),
        ],
      ],
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

  Future<void> _deleteSelected() async {
    if (_saving || _selectedIds.isEmpty) return;
    var selected = widget.controller.channels
        .where((channel) => _selectedIds.contains(channel.id))
        .toList(growable: false);
    final custom = selected
        .where((channel) => channel.builderKey == null)
        .length;
    final generated = selected.length - custom;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              'Delete ${selected.length} ${selected.length == 1 ? 'channel' : 'channels'}?',
            ),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('$custom custom · $generated generated'),
                  const Text('Your Plex media won’t be deleted.'),
                  if (generated > 0)
                    const Text(
                      'Generated channels may be proposed again by Generate lineup.',
                    ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final channel in selected)
                          Text('${channel.number} · ${channel.name}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                autofocus: true,
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  'Delete ${selected.length} ${selected.length == 1 ? 'channel' : 'channels'}',
                ),
              ),
            ],
          ),
        ) ??
        false;
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

  Widget _reorderList(List<Channel> current, double scale) {
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
          fontSize: _directorySize(22, 16) * scale,
          fontWeight: FontWeight.w500,
        );
        final rowSupportStyle = Theme.of(context).textTheme.bodyMedium
            ?.copyWith(
              fontSize: _directorySize(18, 14) * scale,
              color: LineupTheme.of(context).secondaryText,
            );
        final moves = Wrap(
          alignment: WrapAlignment.end,
          children: [
            IconButton(
              tooltip: 'Move ${channel.name} up',
              onPressed: _saving || index == 0
                  ? null
                  : () => _moveReorder(index, index - 1),
              icon: const Icon(Icons.arrow_upward),
            ),
            IconButton(
              tooltip: 'Move ${channel.name} down',
              onPressed: _saving || index == _reorderIds.length - 1
                  ? null
                  : () => _moveReorder(index, index + 1),
              icon: const Icon(Icons.arrow_downward),
            ),
            IconButton(
              tooltip: 'Move ${channel.name} before or after another channel',
              onPressed: _saving ? null : () => _moveTo(index, byId),
              icon: const Icon(Icons.low_priority),
            ),
          ],
        );
        return KeyedSubtree(
          key: ValueKey('reorder-${channel.id}'),
          child: _reorderColumns(
            scale: scale,
            drag: ReorderableDragStartListener(
              enabled: !_saving,
              index: index,
              child: const Icon(Icons.drag_handle),
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
    final generated = channel.builderKey != null;
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Delete ${channel.name}?',
      message: generated
          ? 'This removes channel ${channel.number}. A future Generate lineup refresh may propose it again.'
          : 'This removes channel ${channel.number} from the lineup. This action cannot be undone.',
      confirmLabel: 'Delete channel',
    );
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
    return AlertDialog(
      title: const Text('Move channel'),
      content: SizedBox(
        width: 520,
        height: 440,
        child: Column(
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Search channels',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: channels.length,
                itemBuilder: (context, index) {
                  final channel = channels[index];
                  return ListTile(
                    title: Text('${channel.number} · ${channel.name}'),
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
  }
}
