import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../channels/channel.dart';
import '../guide/guide_controller.dart';
import '../guide/guide_view.dart';
import '../playback/native_player.dart';
import '../playback/player_coordinator.dart';
import '../playback/player_view.dart';
import '../plex/plex_models.dart';
import '../settings/lineup_settings.dart';
import '../ui/app_ui.dart';
import '../ui/app_theme.dart';
import 'channel_setup_view.dart';
import 'channel_studio_view.dart';
import 'lineup_controller.dart';
import 'onboarding_view.dart';

class LineupShell extends StatefulWidget {
  const LineupShell({
    required this.player,
    required this.controller,
    this.initialMediaPath,
    this.guideClock,
    super.key,
  });
  final NativePlayer player;
  final LineupController controller;
  final String? initialMediaPath;
  final DateTime Function()? guideClock;
  @override
  State<LineupShell> createState() => _LineupShellState();
}

class _LineupShellState extends State<LineupShell> {
  late int _selectedIndex = widget.initialMediaPath == null ? 0 : 4;
  int? _settingsReturnIndex;
  late final GuideController _guide;
  late final PlayerCoordinator _player;
  final _playerKey = GlobalKey();
  final _channelsKey = GlobalKey<_ChannelsViewState>();
  final _guideFocus = FocusNode(debugLabel: 'Guide');
  final _channelsFocus = FocusNode(debugLabel: 'Channels');
  final _settingsFocus = FocusNode(debugLabel: 'Settings');
  final _diagnosticsFocus = FocusNode(debugLabel: 'Diagnostics');
  final _playerFocus = FocusNode(debugLabel: 'Player');
  bool _selectionPending = false;
  bool _appMenuOpen = false;
  bool _guideOpenedFromPlayer = false;
  late SetupStage _lastStage = widget.controller.stage;
  @override
  void initState() {
    super.initState();
    _guide = GuideController(
      lineup: widget.controller,
      clock: widget.guideClock,
    );
    _player = PlayerCoordinator(
      player: widget.player,
      lineup: widget.controller,
      guide: _guide,
    );
    final initialMediaPath = widget.initialMediaPath;
    if (initialMediaPath != null) {
      unawaited(_player.loadInitialMedia(_mediaUri(initialMediaPath)));
    }
    _player.addListener(_changed);
    if (_selectedIndex == 0) _player.showFullGuide();
    widget.controller.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreRouteFocus());
  }

  void _changed() {
    if (!mounted) return;
    final stage = widget.controller.stage;
    final returnedToApp =
        _lastStage != SetupStage.ready && stage == SetupStage.ready;
    _lastStage = stage;
    setState(() {});
    if (returnedToApp) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreRouteFocus());
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _player.removeListener(_changed);
    _player.dispose();
    _guide.dispose();
    _guideFocus.dispose();
    _channelsFocus.dispose();
    _settingsFocus.dispose();
    _diagnosticsFocus.dispose();
    _playerFocus.dispose();
    super.dispose();
  }

  Future<void> _select(int index) async {
    if (_selectionPending) return;
    if (index == _selectedIndex) {
      if (_appMenuOpen) _closeAppMenu();
      return;
    }
    _selectionPending = true;
    try {
      if (_selectedIndex == 1 &&
          !(await (_channelsKey.currentState?.requestLeave() ??
              Future.value(true)))) {
        return;
      }
      if (!mounted) return;
      if (widget.controller.stage == SetupStage.ready) {
        if (index == 2 && _selectedIndex != 2) {
          _settingsReturnIndex = _selectedIndex;
        } else if (index != 2 && _selectedIndex == 2) {
          _settingsReturnIndex = null;
        }
      }
      if (index == 0) {
        _guideOpenedFromPlayer = _selectedIndex == 4;
        _player.showFullGuide();
      } else if (_player.overlay == PlayerOverlay.fullGuide) {
        _player.closeOverlay();
      }
      setState(() {
        _selectedIndex = index;
        _appMenuOpen = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreRouteFocus());
    } finally {
      _selectionPending = false;
    }
  }

  void _restoreRouteFocus() {
    if (!mounted) return;
    final target = switch (_selectedIndex) {
      0 => _guideFocus,
      1 => _channelsFocus,
      2 => _settingsFocus,
      3 => _diagnosticsFocus,
      4 => _playerFocus,
      _ => _guideFocus,
    };
    target.requestFocus();
  }

  void _openAppMenu() => setState(() => _appMenuOpen = true);

  void _closeGuide(bool hasPlaybackSurface) {
    final returnToPlayer = hasPlaybackSurface || _guideOpenedFromPlayer;
    _guideOpenedFromPlayer = false;
    returnToPlayer ? unawaited(_select(4)) : _openAppMenu();
  }

  Future<void> _tuneFromGuide(String channelId) async {
    await _select(4);
    await _player.tune(channelId);
  }

  void _closeAppMenu() {
    setState(() => _appMenuOpen = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreRouteFocus());
  }

  KeyEventResult _globalKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (_selectedIndex == 2 &&
        _settingsReturnIndex != null &&
        !_appMenuOpen &&
        (event.logicalKey == LogicalKeyboardKey.escape ||
            event.logicalKey == LogicalKeyboardKey.backspace ||
            event.logicalKey == LogicalKeyboardKey.goBack)) {
      final returnIndex = _settingsReturnIndex!;
      _settingsReturnIndex = null;
      unawaited(_select(returnIndex));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.f3 &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed) {
      unawaited(_select(2));
      return KeyEventResult.handled;
    }
    if (!keyboard.isControlPressed) {
      return KeyEventResult.ignored;
    }
    final index = switch (event.logicalKey) {
      LogicalKeyboardKey.digit1 || LogicalKeyboardKey.keyG => 0,
      LogicalKeyboardKey.digit2 => 1,
      LogicalKeyboardKey.digit3 || LogicalKeyboardKey.comma => 2,
      LogicalKeyboardKey.digit4 => 3,
      LogicalKeyboardKey.digit5 || LogicalKeyboardKey.keyP => 4,
      _ => null,
    };
    if (index == null) return KeyEventResult.ignored;
    unawaited(_select(index));
    return KeyEventResult.handled;
  }

  Widget _withGlobalKeys(Widget child) =>
      Focus(canRequestFocus: false, onKeyEvent: _globalKey, child: child);

  Future<void> _completeSetup() async {
    widget.controller.completeChannelSetup();
    await _select(1);
  }

  Future<void> _completeSetupAndAdd() async {
    widget.controller.completeChannelSetup();
    await _select(1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _channelsKey.currentState?.openNew();
    });
  }

  Future<void> _logout() async {
    if (_selectedIndex == 1 &&
        !(await (_channelsKey.currentState?.requestLeave() ??
            Future.value(true)))) {
      return;
    }
    if (await _player.logout() || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Could not sign out'),
        content: Text(widget.controller.error ?? 'Sign out did not complete.'),
        actions: [
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _immersiveAppMenu() => Stack(
    fit: StackFit.expand,
    children: [
      ModalBarrier(
        dismissible: true,
        onDismiss: _closeAppMenu,
        color: LineupTheme.of(context).scrim.withValues(alpha: 0.45),
      ),
      Align(
        alignment: Alignment.topRight,
        child: SafeArea(
          minimum: const EdgeInsets.all(16),
          child: FocusScope(
            autofocus: true,
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  (event.logicalKey == LogicalKeyboardKey.escape ||
                      event.logicalKey == LogicalKeyboardKey.backspace ||
                      event.logicalKey == LogicalKeyboardKey.goBack)) {
                _closeAppMenu();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: FocusTraversalGroup(
              policy: WidgetOrderTraversalPolicy(),
              child: Card(
                key: const Key('immersive-app-menu'),
                child: SizedBox(
                  width: 280,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'Lineup',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        for (final destination in const [
                          (0, Icons.live_tv_outlined, 'Guide'),
                          (1, Icons.view_list_outlined, 'Channels'),
                          (2, Icons.settings_outlined, 'Settings'),
                          (3, Icons.monitor_heart_outlined, 'Diagnostics'),
                          (4, Icons.play_circle_outline, 'Player'),
                        ])
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              alignment: Alignment.centerLeft,
                              backgroundColor: _selectedIndex == destination.$1
                                  ? LineupTheme.of(context).selectedSurface
                                  : null,
                            ),
                            onPressed: () => unawaited(_select(destination.$1)),
                            icon: Icon(destination.$2),
                            label: Text(destination.$3),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller.stage != SetupStage.ready) {
      return controller.stage == SetupStage.channelSetup
          ? UpstreamChannelSetupView(
              controller: controller,
              onViewLineup: _completeSetup,
              onAddCustomChannel: _completeSetupAndAdd,
            )
          : UpstreamOnboardingView(controller: controller, onLogout: _logout);
    }
    final playerView = PlayerView(
      key: _playerKey,
      controller: _player,
      focusNode: _playerFocus,
      openGuide: () => unawaited(_select(0)),
      openMenu: _openAppMenu,
    );
    final hasPlaybackSurface =
        _player.hasPlaybackIntent || _player.error != null;
    final overlayGuide =
        controller.settings.guideLayoutMode == GuideLayoutMode.overlay &&
        hasPlaybackSurface;
    final guideView = GuideView(
      controller: _guide,
      focusNode: _guideFocus,
      onClose: () => _closeGuide(hasPlaybackSurface),
      onOpenMenu: _openAppMenu,
      overlayMode: overlayGuide,
      pictureInPicture: hasPlaybackSurface && !overlayGuide
          ? PlayerSurface(controller: _player, showErrors: true)
          : null,
      playbackMessage: _player.tuning
          ? 'Preparing playback…'
          : _player.error ?? _player.status.message,
      onOpenPlayer: () => unawaited(_select(4)),
      onTune: _tuneFromGuide,
    );
    final settingsView = SettingsView(
      controller: controller,
      focusNode: _settingsFocus,
      onOpenMenu: _openAppMenu,
    );
    final views = <Widget>[
      overlayGuide
          ? Stack(
              fit: StackFit.expand,
              children: [
                PlayerSurface(controller: _player),
                guideView,
              ],
            )
          : guideView,
      ChannelsView(
        key: _channelsKey,
        controller: controller,
        player: _player,
        clock: widget.guideClock,
        focusNode: _channelsFocus,
        onOpenPlayer: () => unawaited(_select(4)),
      ),
      settingsView,
      DiagnosticsView(
        controller: controller,
        status: _player.status,
        focusNode: _diagnosticsFocus,
      ),
      playerView,
    ];
    if (_selectedIndex == 0 || _selectedIndex == 2 || _selectedIndex == 4) {
      final immersiveView = _selectedIndex == 2
          ? Stack(
              fit: StackFit.expand,
              children: [
                if (hasPlaybackSurface) PlayerSurface(controller: _player),
                settingsView,
              ],
            )
          : views[_selectedIndex];
      return _withGlobalKeys(
        Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            fit: StackFit.expand,
            children: [
              ExcludeSemantics(
                key: const Key('immersive-route-semantics'),
                excluding: _appMenuOpen,
                child: ExcludeFocus(
                  excluding: _appMenuOpen,
                  child: SafeArea(child: immersiveView),
                ),
              ),
              if (_appMenuOpen) _immersiveAppMenu(),
            ],
          ),
        ),
      );
    }
    return _withGlobalKeys(
      Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Row(
            children: [
              ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) => unawaited(_select(index)),
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
                          onPressed: controller.busy ? null : _logout,
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
      ),
    );
  }
}

Uri _mediaUri(String value) {
  if (Platform.isWindows &&
      (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value) || value.startsWith(r'\\'))) {
    return Uri.file(value, windows: true);
  }
  final parsed = Uri.tryParse(value);
  return parsed != null && parsed.hasScheme
      ? parsed
      : Uri.file(value, windows: Platform.isWindows);
}

class ChannelsView extends StatefulWidget {
  const ChannelsView({
    required this.controller,
    required this.player,
    required this.onOpenPlayer,
    this.focusNode,
    this.clock,
    super.key,
  });

  final LineupController controller;
  final PlayerCoordinator player;
  final VoidCallback onOpenPlayer;
  final FocusNode? focusNode;
  final DateTime Function()? clock;

  @override
  State<ChannelsView> createState() => _ChannelsViewState();
}

class _ChannelsViewState extends State<ChannelsView> {
  static const _maximumHealthLoads = 2;
  static const _maximumPendingHealth = 12;
  static const _maximumCachedHealth = 1000;
  Future<void>? _generateLineupEntry;
  String? _error;
  ChannelStudioMode? _studioMode;
  Channel? _studioChannel;
  String? _returnFocusId;
  final _openFocus = <String, FocusNode>{};
  final _deleteFocus = <String, FocusNode>{};
  Future<bool>? _leaveRequest;
  bool _focusPruneScheduled = false;
  bool _focusPruneNeedsRestore = false;
  final LinkedHashMap<String, _ChannelHealth> _health = LinkedHashMap();
  final Queue<({Channel channel, String signature})> _pendingHealth = Queue();
  final Map<String, String> _activeHealth = {};
  int _activeHealthLoads = 0;
  int _healthEpoch = 0;
  int? _healthContentGeneration;
  GlobalKey<ChannelStudioViewState> _studioKey =
      GlobalKey<ChannelStudioViewState>();

  bool get _studioOpen => _studioMode != null;
  ChannelStudioViewState? get _studio => _studioKey.currentState;

  void openNew() => setState(() {
    _studioKey = GlobalKey<ChannelStudioViewState>();
    _studioMode = ChannelStudioMode.createCustom;
    _studioChannel = null;
    _returnFocusId = null;
    _error = null;
  });

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
      _generateLineupEntry ??= _enterGenerateLineupFromStudio();

  Future<void> _enterGenerateLineupFromStudio() async {
    try {
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
    } finally {
      _generateLineupEntry = null;
    }
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
    for (final node in {..._openFocus.values, ..._deleteFocus.values}) {
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
    if (_healthContentGeneration != widget.controller.contentGeneration) {
      _healthContentGeneration = widget.controller.contentGeneration;
      _healthEpoch++;
      _health.clear();
      _pendingHealth.clear();
    }
    _scheduleFocusPrune(channels.map((channel) => channel.id).toSet());
    return LineupPage(
      title: 'Channels',
      actions: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            focusNode: widget.focusNode,
            onPressed: widget.controller.enterChannelSetup,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Generate lineup'),
          ),
          FilledButton.icon(
            onPressed: openNew,
            icon: const Icon(Icons.add),
            label: const Text('New channel'),
          ),
        ],
      ),
      child: Column(
        children: [
          if (_error != null) ...[
            LineupNotice(message: _error!),
            const SizedBox(height: 12),
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
                          onPressed: widget.controller.enterChannelSetup,
                          icon: const Icon(Icons.auto_awesome_outlined),
                          label: const Text('Generate lineup'),
                        ),
                        OutlinedButton.icon(
                          onPressed: openNew,
                          icon: const Icon(Icons.add),
                          label: const Text('Create a custom channel'),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: channels.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final channel = channels[index];
                      _requestHealth(channel);
                      final ownership = channel.builderKey == null
                          ? 'Custom'
                          : 'Generated';
                      return Card(
                        key: ValueKey('channel-row-${channel.id}'),
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text('${channel.number}'),
                          ),
                          title: Text(channel.name),
                          subtitle: Text(
                            [
                              '$ownership • ${channelSourceLabel(channel.source, widget.controller)} • ${channelRhythmLabel(channel.playbackMode, channel.blockSize)}',
                              if (_health[channel.id]?.issue == true)
                                'Schedule issue — open this channel to recover',
                            ].join('\n'),
                          ),
                          trailing: Wrap(
                            children: [
                              IconButton(
                                tooltip: 'Open ${channel.name}',
                                focusNode: _openFocus.putIfAbsent(
                                  channel.id,
                                  () => FocusNode(
                                    debugLabel: 'Open ${channel.name}',
                                  ),
                                ),
                                onPressed: () => _open(channel),
                                icon: const Icon(Icons.open_in_new),
                              ),
                              IconButton(
                                tooltip: 'Delete ${channel.name}',
                                focusNode: _deleteFocus.putIfAbsent(
                                  channel.id,
                                  () => FocusNode(
                                    debugLabel: 'Delete ${channel.name}',
                                  ),
                                ),
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

  void _finishHealth(String id, String signature, bool issue, int epoch) {
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

  String _healthSignature(Channel channel) =>
      '${widget.controller.contentGeneration}|${channel.toJson()}';

  void _scheduleFocusPrune(Set<String> liveIds) {
    final staleIds = {
      ..._openFocus.keys,
      ..._deleteFocus.keys,
    }.where((id) => !liveIds.contains(id)).toList();
    if (staleIds.isEmpty) return;
    _focusPruneNeedsRestore |= staleIds.any(
      (id) =>
          (_openFocus[id]?.hasFocus ?? false) ||
          (_deleteFocus[id]?.hasFocus ?? false),
    );
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
        ..._deleteFocus.keys,
      }.where((id) => !currentIds.contains(id)).toList();
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
        _deleteFocus.remove(id)?.dispose();
      }
    });
  }

  Future<void> _delete(Channel channel) async {
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
      _deleteFocus[channel.id]?.requestFocus();
      return;
    }
    try {
      await widget.controller.deleteChannel(channel.id);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error =
            'The channel could not be deleted. No lineup changes were saved.',
      );
      _deleteFocus[channel.id]?.requestFocus();
      return;
    }
    if (!mounted) return;
    final deletedFocus = _deleteFocus.remove(channel.id);
    _openFocus.remove(channel.id)?.dispose();
    setState(() => _error = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      deletedFocus?.dispose();
      widget.focusNode?.requestFocus();
    });
  }
}

class _ChannelHealth {
  const _ChannelHealth(this.signature, this.issue);

  final String signature;
  final bool issue;
}

enum _SettingsCategory { appearance, guide, accessibility, account, support }

class SettingsView extends StatefulWidget {
  const SettingsView({
    required this.controller,
    this.focusNode,
    this.onOpenMenu,
    super.key,
  });
  final LineupController controller;
  final FocusNode? focusNode;
  final VoidCallback? onOpenMenu;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  _SettingsCategory _category = _SettingsCategory.appearance;
  bool _categoryFocusPlaced = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _categoryFocusPlaced = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: FocusTraversalGroup(
        child: DecoratedBox(
          key: const Key('settings-immersive-scrim'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                roles.scrim.withValues(alpha: 0.68),
                roles.scrim.withValues(alpha: 0.46),
              ],
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < LineupLayout.compact;
              final categories = _categoryRail(compact, constraints.maxWidth);
              final detail = _detailPane(compact);
              return compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        categories,
                        Expanded(child: detail),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        categories,
                        Expanded(child: detail),
                      ],
                    );
            },
          ),
        ),
      ),
    );
  }

  Widget _categoryRail(bool compact, double width) {
    final roles = LineupTheme.of(context);
    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 20 : 24,
        compact ? 16 : 24,
        compact ? 20 : 18,
        compact ? 14 : 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Settings',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
              ),
              if (widget.onOpenMenu != null)
                IconButton(
                  tooltip: 'Open Lineup menu',
                  onPressed: widget.onOpenMenu,
                  icon: const Icon(Icons.menu),
                ),
            ],
          ),
          Text(
            'Press Back to return',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: roles.mutedText),
          ),
          SizedBox(height: compact ? 14 : 24),
          if (compact)
            _categorySelector(true)
          else
            Expanded(child: _categorySelector(false)),
        ],
      ),
    );
    return DecoratedBox(
      key: const Key('settings-category-rail'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            roles.overlaySurface.withValues(alpha: 0.82),
            roles.deepBackground.withValues(alpha: 0.9),
          ],
        ),
        border: Border(
          right: compact
              ? BorderSide.none
              : BorderSide(color: roles.subtleBorder),
          bottom: compact
              ? BorderSide(color: roles.subtleBorder)
              : BorderSide.none,
        ),
        borderRadius: compact
            ? BorderRadius.only(
                bottomLeft: Radius.circular(roles.panelRadius),
                bottomRight: Radius.circular(roles.panelRadius),
              )
            : BorderRadius.only(
                topRight: Radius.circular(roles.panelRadius),
                bottomRight: Radius.circular(roles.panelRadius),
              ),
      ),
      child: compact
          ? content
          : SizedBox(
              width: width * 0.24 > 320 ? 320 : width * 0.24,
              child: content,
            ),
    );
  }

  Widget _detailPane(bool compact) => Padding(
    key: const Key('settings-detail-pane'),
    padding: EdgeInsets.fromLTRB(
      compact ? 20 : 40,
      compact ? 20 : 32,
      compact ? 20 : 40,
      compact ? 20 : 32,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_saving)
          const LinearProgressIndicator(semanticsLabel: 'Saving settings'),
        if (_error != null) ...[
          LineupNotice(message: _error!),
          const SizedBox(height: 12),
        ],
        Expanded(child: _categoryDetail()),
      ],
    ),
  );

  Widget _categorySelector(bool compact) {
    final roles = LineupTheme.of(context);
    final controls = [
      for (final category in _SettingsCategory.values)
        Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 8),
          child: Semantics(
            selected: category == _category,
            button: true,
            child: OutlinedButton(
              focusNode: category == _SettingsCategory.appearance
                  ? widget.focusNode
                  : null,
              autofocus: category == _category && !_categoryFocusPlaced,
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                backgroundColor: category == _category
                    ? roles.selectedSurface
                    : null,
                side: BorderSide(
                  color: category == _category
                      ? roles.focusBorder
                      : roles.subtleBorder,
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
        _SettingsSection(
          title: _categoryLabel(_category),
          children: switch (_category) {
            _SettingsCategory.appearance => [
              _Dropdown<LineupThemeName>(
                'Theme',
                'Change the application color system immediately.',
                value.theme,
                LineupThemeName.values,
                (item) => item.label,
                _saving
                    ? null
                    : (item) => _update(
                        widget.controller.settings.copyWith(theme: item),
                      ),
              ),
            ],
            _SettingsCategory.guide => [
              _Dropdown<GuideLayoutMode>(
                'Guide presentation',
                'Choose classic Guide with PiP or Guide over full video.',
                value.guideLayoutMode,
                GuideLayoutMode.values,
                (item) => switch (item) {
                  GuideLayoutMode.pictureInPicture => 'Classic with PiP',
                  GuideLayoutMode.overlay => 'Overlay',
                },
                _saving
                    ? null
                    : (item) => _update(
                        widget.controller.settings.copyWith(
                          guideLayoutMode: item,
                        ),
                      ),
              ),
              _Dropdown<int>(
                'Visible time range',
                'Use the upstream-scale view or a wider desktop schedule.',
                value.guideHours,
                LineupSettings.guideHoursOptions,
                (item) => switch (item) {
                  2 => 'Detailed (2 hours)',
                  3 => 'Wide (3 hours)',
                  _ => 'Desktop extended ($item hours)',
                },
                _saving
                    ? null
                    : (item) => _update(
                        widget.controller.settings.copyWith(guideHours: item),
                      ),
              ),
              _Dropdown<int>(
                'Past window',
                'Keep recently ended programs available in the Guide.',
                value.pastMinutes,
                LineupSettings.pastMinutesOptions,
                (item) => '$item minutes',
                _saving
                    ? null
                    : (item) => _update(
                        widget.controller.settings.copyWith(pastMinutes: item),
                      ),
              ),
              _Dropdown<GuideDensity>(
                'Row density',
                'Keep the upstream-scale rows or fit more on desktop.',
                value.guideDensity,
                GuideDensity.values,
                (item) => _enumLabel(item.name),
                _saving
                    ? null
                    : (item) => _update(
                        widget.controller.settings.copyWith(guideDensity: item),
                      ),
              ),
              _Dropdown<GuideInfoBackgroundMode>(
                'Info box background',
                'Choose dynamic color, the theme surface, or Plex artwork.',
                value.guideInfoBackgroundMode,
                GuideInfoBackgroundMode.values,
                (item) => switch (item) {
                  GuideInfoBackgroundMode.bleed => 'Artwork color bleed',
                  GuideInfoBackgroundMode.themeDefault => 'Theme default',
                  GuideInfoBackgroundMode.artwork => 'Artwork backdrop',
                },
                _saving
                    ? null
                    : (item) => _update(
                        widget.controller.settings.copyWith(
                          guideInfoBackgroundMode: item,
                        ),
                      ),
              ),
              SwitchListTile(
                title: const Text('Prefer official title artwork'),
                subtitle: const Text(
                  'Use official Plex title artwork in Guide and Player surfaces when available.',
                ),
                value: value.preferClearLogos,
                onChanged: _saving
                    ? null
                    : (item) => _update(
                        widget.controller.settings.copyWith(
                          preferClearLogos: item,
                        ),
                      ),
              ),
              SwitchListTile(
                title: const Text('Library filters'),
                subtitle: const Text(
                  'Show a source-library filter in the Guide toolbar.',
                ),
                value: value.libraryTabsEnabled,
                onChanged: _saving
                    ? null
                    : (item) => _update(
                        widget.controller.settings.copyWith(
                          libraryTabsEnabled: item,
                        ),
                      ),
              ),
              SwitchListTile(
                title: const Text('Now Playing context'),
                subtitle: const Text(
                  'Keep the tuned channel and program visible in the Guide.',
                ),
                value: value.nowWatchingBanner,
                onChanged: _saving
                    ? null
                    : (item) => _update(
                        widget.controller.settings.copyWith(
                          nowWatchingBanner: item,
                        ),
                      ),
              ),
              _Dropdown<int>(
                'Player controls auto-hide',
                'Set how long controls remain visible while playing.',
                value.osdAutoHideSeconds,
                LineupSettings.osdAutoHideSecondsOptions,
                (item) => '$item seconds',
                _saving
                    ? null
                    : (item) => _update(
                        widget.controller.settings.copyWith(
                          osdAutoHideSeconds: item,
                        ),
                      ),
              ),
              SwitchListTile(
                title: const Text('DVR playback controls'),
                subtitle: const Text(
                  'Show transport controls and enable pause, seek, stop, and media-key shortcuts in Player.',
                ),
                value: value.dvrControlsEnabled,
                onChanged: _saving
                    ? null
                    : (item) => _update(
                        widget.controller.settings.copyWith(
                          dvrControlsEnabled: item,
                        ),
                      ),
              ),
            ],
            _SettingsCategory.accessibility => [
              SwitchListTile(
                title: const Text('Reduce motion'),
                subtitle: const Text(
                  'Disable nonessential application transitions.',
                ),
                value: value.reduceMotion,
                onChanged: _saving
                    ? null
                    : (item) => _update(
                        widget.controller.settings.copyWith(reduceMotion: item),
                      ),
              ),
              SwitchListTile(
                title: const Text('Large focus indicators'),
                subtitle: const Text(
                  'Use thicker outlines for keyboard and controller focus.',
                ),
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
              ListTile(
                title: const Text('Plex Home profile'),
                subtitle: Text(
                  widget.controller.profile?.name ??
                      widget.controller.account?.name ??
                      'Plex account',
                ),
                trailing: OutlinedButton.icon(
                  onPressed: _saving || widget.controller.profiles.isEmpty
                      ? null
                      : widget.controller.showProfiles,
                  icon: const Icon(Icons.switch_account),
                  label: const Text('Switch profile'),
                ),
              ),
              ListTile(
                title: const Text('Plex Media Server'),
                subtitle: Text(
                  widget.controller.server == null
                      ? 'No server selected'
                      : widget.controller.connection == null
                      ? widget.controller.server!.name
                      : '${widget.controller.server!.name} • ${plexConnectionDescription(widget.controller.connection!)}',
                ),
                trailing: OutlinedButton.icon(
                  onPressed: _saving ? null : widget.controller.showServers,
                  icon: const Icon(Icons.dns_outlined),
                  label: const Text('Switch server'),
                ),
              ),
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
    String? error;
    try {
      await widget.controller.updateSettings(next);
    } catch (_) {
      error = 'This setting could not be saved. Your previous value remains.';
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error;
        });
      }
    }
  }

  static String _categoryLabel(_SettingsCategory category) =>
      switch (category) {
        _SettingsCategory.appearance => 'Appearance',
        _SettingsCategory.guide => 'Guide',
        _SettingsCategory.accessibility => 'Accessibility',
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
    child: ListView(
      children: [
        _DiagnosticsSummary(
          focusNode: focusNode,
          status: status,
          serverName: controller.server?.name,
          entryCount: controller.diagnostics.entries.length,
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

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        header: true,
        child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
      ),
      const SizedBox(height: 24),
      ...children,
    ],
  );
}

class _DiagnosticsSummary extends StatefulWidget {
  const _DiagnosticsSummary({
    required this.status,
    required this.entryCount,
    this.serverName,
    this.focusNode,
  });
  final PlayerStatus status;
  final int entryCount;
  final String? serverName;
  final FocusNode? focusNode;

  @override
  State<_DiagnosticsSummary> createState() => _DiagnosticsSummaryState();
}

class _DiagnosticsSummaryState extends State<_DiagnosticsSummary> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(roles.panelRadius),
          side: BorderSide(
            color: _focused ? roles.focusBorder : roles.subtleBorder,
            width: _focused ? roles.focusBorderWidth : 1,
          ),
        ),
        child: ListTile(
          leading: const Icon(Icons.shield_outlined),
          title: const Text('Credential-safe diagnostics'),
          subtitle: Text(
            'Playback: ${widget.status.message}\nPlex: ${widget.serverName ?? 'not connected'}\nEntries: ${widget.entryCount}',
          ),
        ),
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown(
    this.label,
    this.description,
    this.value,
    this.values,
    this.display,
    this.changed,
  );
  final String label;
  final String description;
  final T value;
  final List<T> values;
  final String Function(T) display;
  final ValueChanged<T>? changed;
  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(label),
    subtitle: Text(description),
    trailing: DropdownButton<T>(
      value: value,
      items: [
        for (final item in values)
          DropdownMenuItem(value: item, child: Text(display(item))),
      ],
      onChanged: changed == null
          ? null
          : (item) {
              if (item != null) changed!(item);
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
        if (MediaQuery.sizeOf(context).width >=
            LineupLayout.expandedNavigation) ...[
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
