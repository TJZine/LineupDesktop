import 'package:flutter/material.dart';

import '../channels/channel.dart';
import '../channels/content_resolver.dart';
import '../guide/guide_controller.dart';
import '../guide/guide_view.dart';
import '../playback/native_player.dart';
import '../playback/player_coordinator.dart';
import '../playback/player_view.dart';
import '../settings/lineup_settings.dart';
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
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _player.dispose();
    _guide.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index == 0) {
      _player.showFullGuide();
    } else if (_player.overlay == PlayerOverlay.fullGuide) {
      _player.closeOverlay();
    }
    setState(() => _selectedIndex = index);
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
      openGuide: () => _select(0),
    );
    final views = <Widget>[
      Stack(
        fit: StackFit.expand,
        children: [
          playerView,
          GuideView(
            controller: _guide,
            onClose: () => _select(4),
            onTune: (channelId) async {
              await _player.tune(channelId);
              if (_player.error == null) _select(4);
            },
          ),
        ],
      ),
      ChannelsView(controller: controller),
      SettingsView(controller: controller),
      DiagnosticsView(controller: controller, status: widget.player.status),
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
                extended: MediaQuery.sizeOf(context).width >= 1100,
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

class ChannelsView extends StatelessWidget {
  const ChannelsView({required this.controller, super.key});
  final LineupController controller;
  @override
  Widget build(BuildContext context) => _Page(
    title: 'Channels',
    trailing: Wrap(
      spacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: controller.enterChannelSetup,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('Channel builder'),
        ),
        FilledButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => ChannelEditor(controller: controller),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Create channel'),
        ),
      ],
    ),
    child: controller.channels.isEmpty
        ? const Center(
            child: _Panel(
              icon: Icons.view_list,
              title: 'Build your first channel',
              body: 'Choose library content, ordering, and a stable channel number.',
              action: SizedBox.shrink(),
            ),
          )
        : ListView.separated(
            itemCount: controller.channels.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final channel = controller.channels[index];
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
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => ChannelEditor(
                            controller: controller,
                            channel: channel,
                          ),
                        ),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Delete ${channel.name}',
                        onPressed: () => controller.deleteChannel(channel.id),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
  );
}

class ChannelEditor extends StatefulWidget {
  const ChannelEditor({required this.controller, this.channel, super.key});
  final LineupController controller;
  final Channel? channel;
  @override
  State<ChannelEditor> createState() => _ChannelEditorState();
}

class _ChannelEditorState extends State<ChannelEditor> {
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
  bool _includeWatched = true;
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Channel name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _number,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Channel number (1–1000)',
              ),
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
                  (library) =>
                      widget.controller.selectedLibraryIds.contains(library.id),
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
                ButtonSegment(value: PlaybackMode.block, label: Text('Blocks')),
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
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save channel')),
    ],
  );
  Future<void> _save() async {
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
          name: _name.text,
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
      setState(
        () => _error = error.toString().replaceFirst('FormatException: ', ''),
      );
    }
  }
}

class SettingsView extends StatelessWidget {
  const SettingsView({required this.controller, super.key});
  final LineupController controller;
  @override
  Widget build(BuildContext context) {
    final value = controller.settings;
    return _Page(
      title: 'Settings',
      child: ListView(
        children: [
          _Section('Guide', [
            _Dropdown<int>(
              'Visible time range',
              value.guideHours,
              const [2, 4, 6, 8, 12],
              (item) => '$item hours',
              (item) =>
                  controller.updateSettings(value.copyWith(guideHours: item)),
            ),
            _Dropdown<int>(
              'Past window',
              value.pastMinutes,
              const [0, 15, 30, 60, 120, 180],
              (item) => '$item minutes',
              (item) =>
                  controller.updateSettings(value.copyWith(pastMinutes: item)),
            ),
            _Dropdown<GuideDensity>(
              'Row density',
              value.guideDensity,
              GuideDensity.values,
              (item) => item.name,
              (item) =>
                  controller.updateSettings(value.copyWith(guideDensity: item)),
            ),
          ]),
          _Section('Playback', [
            _Dropdown<VideoQuality>(
              'Remote quality',
              value.videoQuality,
              VideoQuality.values,
              (item) => item.name,
              (item) =>
                  controller.updateSettings(value.copyWith(videoQuality: item)),
            ),
            _Dropdown<ToneMapPolicy>(
              'HDR tone mapping',
              value.toneMapPolicy,
              ToneMapPolicy.values,
              (item) => item.name,
              (item) => controller.updateSettings(
                value.copyWith(toneMapPolicy: item),
              ),
            ),
            SwitchListTile(
              title: const Text('Audio passthrough intent'),
              subtitle: const Text(
                'Applied only where the native player proves support.',
              ),
              value: value.audioPassthrough,
              onChanged: (item) => controller.updateSettings(
                value.copyWith(audioPassthrough: item),
              ),
            ),
            SwitchListTile(
              title: const Text('Allow compatible audio fallback'),
              value: value.directPlayAudioFallback,
              onChanged: (item) => controller.updateSettings(
                value.copyWith(directPlayAudioFallback: item),
              ),
            ),
          ]),
          _Section('Subtitles and access', [
            _Dropdown<SubtitleMode>(
              'Subtitle mode',
              value.subtitleMode,
              SubtitleMode.values,
              (item) => item.name,
              (item) =>
                  controller.updateSettings(value.copyWith(subtitleMode: item)),
            ),
            SwitchListTile(
              title: const Text('Prefer forced subtitles'),
              value: value.preferForcedSubtitles,
              onChanged: (item) => controller.updateSettings(
                value.copyWith(preferForcedSubtitles: item),
              ),
            ),
            SwitchListTile(
              title: const Text('Reduce motion'),
              value: value.reduceMotion,
              onChanged: (item) =>
                  controller.updateSettings(value.copyWith(reduceMotion: item)),
            ),
            SwitchListTile(
              title: const Text('Large focus indicators'),
              value: value.largeFocusIndicators,
              onChanged: (item) => controller.updateSettings(
                value.copyWith(largeFocusIndicators: item),
              ),
            ),
          ]),
          _Section('Support', [
            SwitchListTile(
              title: const Text('Record redacted diagnostics'),
              subtitle: const Text(
                'Tokens, URLs, paths, headers and credentials are excluded.',
              ),
              value: value.diagnosticsEnabled,
              onChanged: (item) => controller.updateSettings(
                value.copyWith(diagnosticsEnabled: item),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class DiagnosticsView extends StatelessWidget {
  const DiagnosticsView({
    required this.controller,
    required this.status,
    super.key,
  });
  final LineupController controller;
  final PlayerStatus status;
  @override
  Widget build(BuildContext context) => _Page(
    title: 'Diagnostics',
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
        for (final entry in controller.diagnostics.entries.reversed)
          ListTile(
            title: Text('${entry.area}: ${entry.message}'),
            subtitle: Text(entry.time.toLocal().toString()),
            trailing: Text(
              entry.context.entries
                  .map((item) => '${item.key}=${item.value}')
                  .join(' '),
            ),
          ),
      ],
    ),
  );
}

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 24),
          Expanded(child: child),
        ],
      ),
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
  });
  final IconData icon;
  final String title;
  final String body;
  final Widget action;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 28),
          action,
        ],
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const Divider(height: 24),
          ...children,
        ],
      ),
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
