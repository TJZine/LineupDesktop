import 'package:flutter/material.dart';

import '../channels/channel.dart';
import '../channels/content_resolver.dart';
import '../guide/guide_controller.dart';
import '../guide/guide_view.dart';
import '../playback/native_player.dart';
import '../playback/player_coordinator.dart';
import '../playback/player_view.dart';
import '../settings/lineup_settings.dart';
import '../ui/app_ui.dart';
import '../ui/app_theme.dart';
import 'channel_setup_view.dart';
import 'lineup_controller.dart';
import 'onboarding_view.dart';

class LineupShell extends StatefulWidget {
  const LineupShell({
    required this.player,
    required this.controller,
    this.initialMediaPath,
    super.key,
  });
  final NativePlayer player;
  final LineupController controller;
  final String? initialMediaPath;
  @override
  State<LineupShell> createState() => _LineupShellState();
}

class _LineupShellState extends State<LineupShell> {
  late int _selectedIndex = widget.initialMediaPath == null ? 0 : 4;
  late final GuideController _guide;
  late final PlayerCoordinator _player;
  final _playerKey = GlobalKey();
  final _guideFocus = FocusNode(debugLabel: 'Guide');
  final _channelsFocus = FocusNode(debugLabel: 'Channels');
  final _settingsFocus = FocusNode(debugLabel: 'Settings');
  final _diagnosticsFocus = FocusNode(debugLabel: 'Diagnostics');
  final _playerFocus = FocusNode(debugLabel: 'Player');
  @override
  void initState() {
    super.initState();
    _guide = GuideController(lineup: widget.controller);
    _player = PlayerCoordinator(
      player: widget.player,
      lineup: widget.controller,
      guide: _guide,
    );
    if (_selectedIndex == 0) _player.showFullGuide();
    widget.controller.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreRouteFocus());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _player.dispose();
    _guide.dispose();
    _guideFocus.dispose();
    _channelsFocus.dispose();
    _settingsFocus.dispose();
    _diagnosticsFocus.dispose();
    _playerFocus.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index == 0) {
      _player.showFullGuide();
    } else if (_player.overlay == PlayerOverlay.fullGuide) {
      _player.closeOverlay();
    }
    setState(() => _selectedIndex = index);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreRouteFocus());
  }

  void _restoreRouteFocus() {
    if (!mounted) return;
    switch (_selectedIndex) {
      case 0:
        _guideFocus.requestFocus();
      case 1:
        _channelsFocus.requestFocus();
      case 2:
        _settingsFocus.requestFocus();
      case 3:
        _diagnosticsFocus.requestFocus();
      case 4:
        _playerFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller.stage != SetupStage.ready) {
      return controller.stage == SetupStage.channelSetup
          ? UpstreamChannelSetupView(controller: controller)
          : UpstreamOnboardingView(controller: controller);
    }
    final playerView = PlayerView(
      key: _playerKey,
      controller: _player,
      initialMediaPath: widget.initialMediaPath,
      focusNode: _playerFocus,
      openGuide: () => _select(0),
    );
    final views = <Widget>[
      Stack(
        fit: StackFit.expand,
        children: [
          playerView,
          GuideView(
            controller: _guide,
            focusNode: _guideFocus,
            onClose: () => _select(4),
            onTune: (channelId) async {
              await _player.tune(channelId);
              if (_player.error == null) _select(4);
            },
          ),
        ],
      ),
      ChannelsView(controller: controller, focusNode: _channelsFocus),
      SettingsView(controller: controller, focusNode: _settingsFocus),
      DiagnosticsView(
        controller: controller,
        status: widget.player.status,
        focusNode: _diagnosticsFocus,
      ),
      playerView,
    ];
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Row(
          children: [
            ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: NavigationRail(
                selectedIndex: _selectedIndex,
                onDestinationSelected: _select,
                extended:
                    MediaQuery.sizeOf(context).width >=
                    LineupLayout.expandedNavigation,
                leading: const Padding(
                  padding: EdgeInsets.fromLTRB(12, 16, 12, 28),
                  child: _Brand(),
                ),
                trailing: Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: IconButton(
                        tooltip: 'Sign out of Plex',
                        onPressed: controller.busy ? null : controller.logout,
                        icon: const Icon(Icons.logout),
                      ),
                    ),
                  ),
                ),
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.live_tv_outlined),
                    selectedIcon: Icon(Icons.live_tv),
                    label: Text('Guide'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.view_list_outlined),
                    selectedIcon: Icon(Icons.view_list),
                    label: Text('Channels'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings),
                    label: Text('Settings'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.monitor_heart_outlined),
                    selectedIcon: Icon(Icons.monitor_heart),
                    label: Text('Diagnostics'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.play_circle_outline),
                    selectedIcon: Icon(Icons.play_circle),
                    label: Text('Player'),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: views[_selectedIndex],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChannelsView extends StatefulWidget {
  const ChannelsView({required this.controller, this.focusNode, super.key});
  final LineupController controller;
  final FocusNode? focusNode;

  @override
  State<ChannelsView> createState() => _ChannelsViewState();
}

class _ChannelsViewState extends State<ChannelsView> {
  String? _error;

  @override
  Widget build(BuildContext context) => LineupPage(
    title: 'Channels',
    focusNode: widget.focusNode,
    actions: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: widget.controller.enterChannelSetup,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('Channel builder'),
        ),
        FilledButton.icon(
          onPressed: _showEditor,
          icon: const Icon(Icons.add),
          label: const Text('Create channel'),
        ),
      ],
    ),
    child: Column(
      children: [
        if (_error != null) ...[
          LineupNotice(message: _error!, tone: NoticeTone.error),
          const SizedBox(height: 12),
        ],
        Expanded(
          child: widget.controller.channels.isEmpty
              ? LineupEmptyState(
                  icon: Icons.view_list,
                  title: 'Build your first channel',
                  message: 'Choose library content, ordering, and a stable channel number.',
                  action: FilledButton.icon(
                    onPressed: widget.controller.enterChannelSetup,
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text('Open Channel builder'),
                  ),
                )
              : ListView.separated(
                  itemCount: widget.controller.channels.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final channel = widget.controller.channels[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Text('${channel.number}')),
                        title: Text(channel.name),
                        subtitle: Text(
                          '${channel.playbackMode.name} • ${_sourceLabel(channel.source)}',
                        ),
                        trailing: Wrap(
                          children: [
                            IconButton(
                              tooltip: 'Edit ${channel.name}',
                              onPressed: () => _showEditor(channel),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Delete ${channel.name}',
                              onPressed: () => _delete(channel),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );

  Future<void> _showEditor([Channel? channel]) => showDialog<void>(
    context: context,
    builder: (_) =>
        ChannelEditor(controller: widget.controller, channel: channel),
  );

  Future<void> _delete(Channel channel) async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Delete ${channel.name}?',
      message:
          'This removes channel ${channel.number} from the lineup. This action cannot be undone.',
      confirmLabel: 'Delete channel',
    );
    if (!confirmed || !mounted) return;
    try {
      await widget.controller.deleteChannel(channel.id);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The channel could not be deleted. No lineup changes were saved.',
        );
      }
    }
  }
}

class ChannelEditor extends StatefulWidget {
  const ChannelEditor({required this.controller, this.channel, super.key});
  final LineupController controller;
  final Channel? channel;
  @override
  State<ChannelEditor> createState() => _ChannelEditorState();
}

class _ChannelEditorState extends State<ChannelEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.channel?.name ?? '');
  late final _number = TextEditingController(
    text: '${widget.channel?.number ?? _nextNumber()}',
  );
  late PlaybackMode _mode =
      widget.channel?.playbackMode ?? PlaybackMode.shuffle;
  late bool _manual = widget.channel?.source is ManualSource;
  late final Set<String> _manualItemIds = switch (widget.channel?.source) {
    ManualSource(:final items) => items.map((item) => item.id).toSet(),
    _ => <String>{},
  };
  late String? _libraryId = switch (widget.channel?.source) {
    LibrarySource(:final libraryId) => libraryId,
    _ => widget.controller.selectedLibraryIds.firstOrNull,
  };
  late bool _includeWatched = switch (widget.channel?.source) {
    LibrarySource(:final includeWatched) => includeWatched,
    _ => true,
  };
  bool _saving = false;
  String? _error;
  int _nextNumber() {
    for (var value = 1; value <= 1000; value++) {
      if (!widget.controller.channels.any(
        (channel) => channel.number == value,
      )) {
        return value;
      }
    }
    return 1;
  }

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.channel == null ? 'Create custom channel' : 'Edit channel',
    ),
    content: SizedBox(
      width: 560,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) ...[
                LineupNotice(message: _error!, tone: NoticeTone.error),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Channel name',
                  hintText: 'Required',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a channel name.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _number,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Channel number (1–1000)',
                ),
                validator: (value) {
                  final number = int.tryParse(value ?? '');
                  if (number == null || number < 1 || number > 1000) {
                    return 'Enter a number from 1 to 1000.';
                  }
                  if (widget.controller.channels.any(
                    (channel) =>
                        channel.id != widget.channel?.id &&
                        channel.number == number,
                  )) {
                    return 'That channel number is already in use.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Entire library')),
                  ButtonSegment(value: true, label: Text('Hand-picked')),
                ],
                selected: {_manual},
                onSelectionChanged: (value) =>
                    setState(() => _manual = value.single),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _libraryId,
                decoration: const InputDecoration(labelText: 'Content library'),
                items: [
                  for (final library in widget.controller.libraries.where(
                    (library) => widget.controller.selectedLibraryIds.contains(
                      library.id,
                    ),
                  ))
                    DropdownMenuItem(
                      value: library.id,
                      child: Text(library.title),
                    ),
                ],
                onChanged: _manual
                    ? null
                    : (value) => setState(() => _libraryId = value),
              ),
              if (_manual) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 240,
                  child: ListView.builder(
                    itemCount: widget.controller.availableMedia.length,
                    itemBuilder: (context, index) {
                      final item = widget.controller.availableMedia[index];
                      return CheckboxListTile(
                        dense: true,
                        value: _manualItemIds.contains(item.id),
                        title: Text(item.title),
                        subtitle: item.grandparentTitle == null
                            ? null
                            : Text(item.grandparentTitle!),
                        onChanged: (selected) => setState(
                          () => selected == true
                              ? _manualItemIds.add(item.id)
                              : _manualItemIds.remove(item.id),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SegmentedButton<PlaybackMode>(
                segments: const [
                  ButtonSegment(
                    value: PlaybackMode.sequential,
                    label: Text('Sequential'),
                  ),
                  ButtonSegment(
                    value: PlaybackMode.shuffle,
                    label: Text('Shuffle'),
                  ),
                  ButtonSegment(
                    value: PlaybackMode.block,
                    label: Text('Blocks'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (value) =>
                    setState(() => _mode = value.single),
              ),
              SwitchListTile(
                value: _includeWatched,
                title: const Text('Include watched items'),
                onChanged: (value) => setState(() => _includeWatched = value),
              ),
              Text(
                '${widget.controller.availableMedia.length} loaded items are available.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Save channel'),
      ),
    ],
  );
  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = _libraryId;
      if (!_manual && id == null) {
        throw const FormatException('Select a library');
      }
      final library = _manual
          ? null
          : widget.controller.libraries.firstWhere(
              (library) => library.id == id,
            );
      final manualItems = widget.controller.availableMedia
          .where((item) => _manualItemIds.contains(item.id))
          .map(channelItemFor)
          .toList();
      if (_manual && manualItems.isEmpty) {
        throw const FormatException('Select at least one program');
      }
      final channelId = widget.channel?.id ?? createChannelId();
      await widget.controller.saveChannel(
        Channel(
          id: channelId,
          number: int.parse(_number.text),
          name: _name.text.trim(),
          source: _manual
              ? ManualSource(manualItems)
              : LibrarySource(
                  libraryId: id!,
                  libraryType: library!.type,
                  includeWatched: _includeWatched,
                ),
          playbackMode: _mode,
          anchor: widget.channel?.anchor ?? DateTime.now().toUtc(),
          shuffleSeed: widget.channel?.shuffleSeed ?? channelId.hashCode,
          blockSize: _mode == PlaybackMode.block ? 3 : null,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString().replaceFirst('FormatException: ', '');
        });
      }
    }
  }
}

enum _SettingsCategory { guide, playback, accessibility, account, support }

class SettingsView extends StatefulWidget {
  const SettingsView({required this.controller, this.focusNode, super.key});
  final LineupController controller;
  final FocusNode? focusNode;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  _SettingsCategory _category = _SettingsCategory.guide;
  bool _saving = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return LineupPage(
      title: 'Settings',
      focusNode: widget.focusNode,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < LineupLayout.compact;
          final categories = _categorySelector(compact);
          final detail = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_saving)
                const LinearProgressIndicator(
                  semanticsLabel: 'Saving settings',
                ),
              if (_error != null) ...[
                LineupNotice(message: _error!, tone: NoticeTone.error),
                const SizedBox(height: 12),
              ],
              Expanded(child: _categoryDetail()),
            ],
          );
          return compact
              ? Column(
                  children: [
                    categories,
                    const SizedBox(height: 12),
                    Expanded(child: detail),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 250, child: categories),
                    const SizedBox(width: 20),
                    Expanded(child: detail),
                  ],
                );
        },
      ),
    );
  }

  Widget _categorySelector(bool compact) {
    final controls = [
      for (final category in _SettingsCategory.values)
        Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 8),
          child: Semantics(
            selected: category == _category,
            button: true,
            child: OutlinedButton(
              autofocus: category == _category,
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                backgroundColor: category == _category
                    ? LineupTheme.brass.withValues(alpha: 0.14)
                    : null,
                side: BorderSide(
                  color: category == _category
                      ? LineupTheme.brass
                      : Colors.white12,
                ),
              ),
              onPressed: () => setState(() => _category = category),
              child: Text(_categoryLabel(category)),
            ),
          ),
        ),
    ];
    return compact
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: controls),
          )
        : ListView(children: controls);
  }

  Widget _categoryDetail() {
    final value = widget.controller.settings;
    return ListView(
      children: [
        LineupSection(
          title: _categoryLabel(_category),
          children: switch (_category) {
            _SettingsCategory.guide => [
              _Dropdown<int>(
                'Visible time range',
                value.guideHours,
                const [2, 4, 6, 8, 12],
                (item) => '$item hours',
                (item) => _update(
                  widget.controller.settings.copyWith(guideHours: item),
                ),
              ),
              _Dropdown<int>(
                'Past window',
                value.pastMinutes,
                const [0, 15, 30, 60, 120, 180],
                (item) => '$item minutes',
                (item) => _update(
                  widget.controller.settings.copyWith(pastMinutes: item),
                ),
              ),
              _Dropdown<GuideDensity>(
                'Row density',
                value.guideDensity,
                GuideDensity.values,
                (item) => _enumLabel(item.name),
                (item) => _update(
                  widget.controller.settings.copyWith(guideDensity: item),
                ),
              ),
            ],
            _SettingsCategory.playback => [
              _Dropdown<VideoQuality>(
                'Remote quality',
                value.videoQuality,
                VideoQuality.values,
                (item) => _enumLabel(item.name),
                (item) => _update(
                  widget.controller.settings.copyWith(videoQuality: item),
                ),
              ),
              _Dropdown<ToneMapPolicy>(
                'HDR tone mapping',
                value.toneMapPolicy,
                ToneMapPolicy.values,
                (item) => _enumLabel(item.name),
                (item) => _update(
                  widget.controller.settings.copyWith(toneMapPolicy: item),
                ),
              ),
              SwitchListTile(
                title: const Text('Audio passthrough intent'),
                subtitle: const Text(
                  'Applied only where the native player proves support.',
                ),
                value: value.audioPassthrough,
                onChanged: _saving
                    ? null
                    : (item) => _update(
                        widget.controller.settings.copyWith(
                          audioPassthrough: item,
                        ),
                      ),
              ),
              SwitchListTile(
                title: const Text('Allow compatible audio fallback'),
                value: value.directPlayAudioFallback,
                onChanged: _saving
                    ? null
                    : (item) => _update(
                        widget.controller.settings.copyWith(
                          directPlayAudioFallback: item,
                        ),
                      ),
              ),
            ],
            _SettingsCategory.accessibility => [
              _Dropdown<SubtitleMode>(
                'Subtitle mode',
                value.subtitleMode,
                SubtitleMode.values,
                (item) => _enumLabel(item.name),
                (item) => _update(
                  widget.controller.settings.copyWith(subtitleMode: item),
                ),
              ),
              SwitchListTile(
                title: const Text('Prefer forced subtitles'),
                value: value.preferForcedSubtitles,
                onChanged: _saving
                    ? null
                    : (item) => _update(
                        widget.controller.settings.copyWith(
                          preferForcedSubtitles: item,
                        ),
                      ),
              ),
              SwitchListTile(
                title: const Text('Reduce motion'),
                value: value.reduceMotion,
                onChanged: _saving
                    ? null
                    : (item) => _update(
                        widget.controller.settings.copyWith(reduceMotion: item),
                      ),
              ),
              SwitchListTile(
                title: const Text('Large focus indicators'),
                value: value.largeFocusIndicators,
                onChanged: _saving
                    ? null
                    : (item) => _update(
                        widget.controller.settings.copyWith(
                          largeFocusIndicators: item,
                        ),
                      ),
              ),
            ],
            _SettingsCategory.account => [
              SwitchListTile(
                title: const Text('Show profile picker on startup'),
                subtitle: const Text(
                  'Ask who is watching when this Plex Home has multiple profiles.',
                ),
                value: value.profilePickerOnStartup,
                onChanged: _saving
                    ? null
                    : (item) => _update(
                        widget.controller.settings.copyWith(
                          profilePickerOnStartup: item,
                        ),
                      ),
              ),
            ],
            _SettingsCategory.support => [
              SwitchListTile(
                title: const Text('Record redacted diagnostics'),
                subtitle: const Text(
                  'Tokens, URLs, paths, headers and credentials are excluded.',
                ),
                value: value.diagnosticsEnabled,
                onChanged: _saving
                    ? null
                    : (item) => _update(
                        widget.controller.settings.copyWith(
                          diagnosticsEnabled: item,
                        ),
                      ),
              ),
            ],
          },
        ),
      ],
    );
  }

  Future<void> _update(LineupSettings next) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.updateSettings(next);
    } catch (_) {
      _error = 'This setting could not be saved. Your previous value remains.';
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _categoryLabel(_SettingsCategory category) =>
      switch (category) {
        _SettingsCategory.guide => 'Guide',
        _SettingsCategory.playback => 'Playback',
        _SettingsCategory.accessibility => 'Subtitles and access',
        _SettingsCategory.account => 'Account',
        _SettingsCategory.support => 'Support',
      };

  static String _enumLabel(String value) =>
      '${value[0].toUpperCase()}${value.substring(1)}';
}

class DiagnosticsView extends StatelessWidget {
  const DiagnosticsView({
    required this.controller,
    required this.status,
    this.focusNode,
    super.key,
  });
  final LineupController controller;
  final PlayerStatus status;
  final FocusNode? focusNode;
  @override
  Widget build(BuildContext context) => LineupPage(
    title: 'Diagnostics',
    focusNode: focusNode,
    child: ListView(
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Credential-safe diagnostics'),
            subtitle: Text(
              'Playback: ${status.message}\nPlex: ${controller.server?.name ?? 'not connected'}\nEntries: ${controller.diagnostics.entries.length}',
            ),
          ),
        ),
        if (controller.diagnostics.entries.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: LineupEmptyState(
              icon: Icons.fact_check_outlined,
              title: 'No diagnostic events',
              message: controller.settings.diagnosticsEnabled
                  ? 'Lineup has not recorded any support events in this session.'
                  : 'Diagnostic recording is off. You can enable it in Settings under Support.',
            ),
          )
        else
          for (final entry in controller.diagnostics.entries.reversed)
            Card(
              child: ListTile(
                title: Text('${entry.area}: ${entry.message}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.time.toLocal().toString()),
                    if (entry.context.isNotEmpty)
                      Text(
                        entry.context.entries
                            .map((item) => '${item.key}=${item.value}')
                            .join(' • '),
                        softWrap: true,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
      ],
    ),
  );
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown(
    this.label,
    this.value,
    this.values,
    this.display,
    this.changed,
  );
  final String label;
  final T value;
  final List<T> values;
  final String Function(T) display;
  final ValueChanged<T> changed;
  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(label),
    trailing: DropdownButton<T>(
      value: value,
      items: [
        for (final item in values)
          DropdownMenuItem(value: item, child: Text(display(item))),
      ],
      onChanged: (item) {
        if (item != null) changed(item);
      },
    ),
  );
}

class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Lineup Desktop',
    header: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/branding/lineup-logo-mark.png',
          width: 42,
          height: 42,
        ),
        if (MediaQuery.sizeOf(context).width >= 1100) ...[
          const SizedBox(width: 12),
          Text(
            'LINEUP',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(letterSpacing: 3),
          ),
        ],
      ],
    ),
  );
}

String _sourceLabel(ContentSource source) => switch (source) {
  LibrarySource() => 'library',
  ManualSource() => 'manual',
  PlaylistSource() => 'playlist',
  MixedSource() => 'mixed',
};
