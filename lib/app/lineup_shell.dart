import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../guide/guide_controller.dart';
import '../guide/guide_playback_placeholder.dart';
import '../guide/guide_view.dart';
import '../playback/native_player.dart';
import '../playback/player_coordinator.dart';
import '../playback/player_view.dart';
import '../settings/lineup_settings.dart';
import '../ui/app_ui.dart';
import '../ui/app_theme.dart';
import 'channel_setup_view.dart';
import 'channels_view.dart';
import 'diagnostics_view.dart';
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
  final _channelsKey = GlobalKey<ChannelsViewState>();
  final _guideFocus = FocusNode(debugLabel: 'Guide');
  final _channelsFocus = FocusNode(debugLabel: 'Channels');
  final _settingsFocus = FocusNode(debugLabel: 'Settings');
  final _diagnosticsFocus = FocusNode(debugLabel: 'Diagnostics');
  final _playerFocus = FocusNode(debugLabel: 'Player');
  final _channelsMenuFocus = FocusNode(debugLabel: 'Channels Lineup menu');
  final _settingsMenuFocus = FocusNode(debugLabel: 'Settings Lineup menu');
  final _diagnosticsMenuFocus = FocusNode(
    debugLabel: 'Diagnostics Lineup menu',
  );
  final _appMenuScope = FocusScopeNode(
    debugLabel: 'Lineup menu',
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );
  bool _selectionPending = false;
  bool _appMenuOpen = false;
  bool _keyboardInput = false;
  Rect? _appMenuAnchor;
  FocusNode? _appMenuInvokerFocus;
  bool _onboardingFromAccount = false;
  SettingsCategory _settingsCategory = SettingsCategory.appearance;
  bool _guideOpenedFromPlayer = false;
  late SetupStage _lastStage = widget.controller.stage;
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_trackKeyboardInput);
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
    if (stage == SetupStage.welcome) _onboardingFromAccount = false;
    if (_appMenuOpen &&
        stage != SetupStage.ready &&
        !_onboardingMenuAvailable) {
      _appMenuOpen = false;
      _appMenuAnchor = null;
      _appMenuInvokerFocus = null;
    }
    setState(() {});
    if (returnedToApp) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreRouteFocus());
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_trackKeyboardInput);
    widget.controller.removeListener(_changed);
    _player.removeListener(_changed);
    _player.dispose();
    _guide.dispose();
    _guideFocus.dispose();
    _channelsFocus.dispose();
    _settingsFocus.dispose();
    _diagnosticsFocus.dispose();
    _playerFocus.dispose();
    _channelsMenuFocus.dispose();
    _settingsMenuFocus.dispose();
    _diagnosticsMenuFocus.dispose();
    _appMenuScope.dispose();
    super.dispose();
  }

  Future<void> _select(int index) async {
    if (_selectionPending) return;
    if (widget.controller.stage != SetupStage.ready &&
        !await _leaveOnboardingForRoute()) {
      return;
    }
    if (index == 4 && !_hasPlaybackSurface) {
      if (_appMenuOpen) _closeAppMenu();
      return;
    }
    if (index == _selectedIndex &&
        !(index == 1 && (_channelsKey.currentState?.studioOpen ?? false))) {
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
        if (index == 2 && _selectedIndex != 2 && _selectedIndex != 3) {
          _settingsReturnIndex = _selectedIndex;
        } else if (index != 2 && index != 3) {
          _settingsReturnIndex = null;
        }
        // Direct Diagnostics entry still has a real Settings origin.
        if (index == 3 && _settingsReturnIndex == null) {
          _settingsReturnIndex = _selectedIndex == 4
              ? 4
              : _selectedIndex == 1
              ? 1
              : 0;
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
        _appMenuAnchor = null;
        _appMenuInvokerFocus = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreRouteFocus());
    } finally {
      _selectionPending = false;
    }
  }

  bool get _hasPlaybackSurface =>
      _player.hasPlaybackIntent || _player.error != null;

  bool get _onboardingMenuAvailable {
    final controller = widget.controller;
    if (!_onboardingFromAccount || controller.busy) return false;
    return switch (controller.stage) {
      SetupStage.profiles => controller.profileSelectionCanCancel,
      SetupStage.servers => controller.serverSelectionCanCancel,
      _ => false,
    };
  }

  bool get _canShowNowPlaying =>
      _player.hasPlaybackIntent &&
      !_player.tuning &&
      _player.error == null &&
      _player.currentProgram != null;

  Future<void> _openNowPlaying() async {
    if (_selectionPending || !_canShowNowPlaying) return;
    await _select(4);
    if (!mounted ||
        widget.controller.stage != SetupStage.ready ||
        _selectedIndex != 4 ||
        _appMenuOpen ||
        !_canShowNowPlaying) {
      return;
    }
    _player.showNowPlaying();
    // Same-route menu dismissal restores its invoker on the next frame.
    // Transfer focus to Player afterwards, not to the now-hidden OSD button.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.controller.stage == SetupStage.ready &&
          _selectedIndex == 4 &&
          !_appMenuOpen &&
          _player.overlay == PlayerOverlay.nowPlaying) {
        _playerFocus.requestFocus();
      }
    });
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

  void _openAppMenu(BuildContext invokerContext, FocusNode invokerFocus) {
    final renderObject = invokerContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    setState(() {
      _appMenuAnchor = MatrixUtils.transformRect(
        renderObject.getTransformTo(context.findRenderObject()),
        Offset.zero & renderObject.size,
      );
      _appMenuInvokerFocus = invokerFocus;
      _appMenuOpen = true;
    });
  }

  void _openAppMenuFromCurrentFocus() {
    final focus = FocusManager.instance.primaryFocus;
    final focusContext = focus?.context;
    if (focus != null && focusContext != null) {
      _openAppMenu(focusContext, focus);
    }
  }

  void _closeGuide(bool hasPlaybackSurface) {
    final returnToPlayer = hasPlaybackSurface || _guideOpenedFromPlayer;
    _guideOpenedFromPlayer = false;
    returnToPlayer ? unawaited(_select(4)) : _openAppMenuFromCurrentFocus();
  }

  Future<void> _tuneFromGuide(String channelId) async {
    final tuning = _player.tune(channelId);
    await _select(4);
    await tuning;
  }

  void _closeAppMenu({bool restoreInvoker = true}) {
    final invoker = _appMenuInvokerFocus;
    final restoreControl = _selectedIndex != 4 || _keyboardInput;
    setState(() {
      _appMenuOpen = false;
      _appMenuAnchor = null;
      _appMenuInvokerFocus = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (restoreInvoker && restoreControl && invoker?.context != null) {
        invoker!.requestFocus();
      } else {
        _restoreRouteFocus();
      }
    });
  }

  Future<void> _openAccount() async {
    _settingsCategory = SettingsCategory.account;
    await _select(2);
  }

  void _openProfilePickerFromAccount() {
    if (_selectionPending || widget.controller.busy) return;
    _onboardingFromAccount = true;
    widget.controller.showProfiles();
  }

  void _openServerPickerFromAccount() {
    if (_selectionPending || widget.controller.busy) return;
    _onboardingFromAccount = true;
    widget.controller.showServers();
  }

  Future<bool> _leaveOnboardingForRoute() async {
    final controller = widget.controller;
    if (controller.busy) return false;
    if (controller.stage == SetupStage.profiles &&
        controller.profileSelectionCanCancel) {
      controller.cancelProfileSelection();
    } else if (controller.stage == SetupStage.servers &&
        controller.serverSelectionCanCancel) {
      controller.cancelServerSelection();
    }
    if (controller.stage != SetupStage.ready) return false;
    _onboardingFromAccount = false;
    return true;
  }

  KeyEventResult _globalKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        FocusManager.instance.primaryFocus?.context
                ?.findAncestorStateOfType<EditableTextState>() !=
            null) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (_selectedIndex == 3 &&
        !_appMenuOpen &&
        (event.logicalKey == LogicalKeyboardKey.escape ||
            event.logicalKey == LogicalKeyboardKey.backspace ||
            event.logicalKey == LogicalKeyboardKey.goBack)) {
      _settingsCategory = SettingsCategory.support;
      unawaited(_select(2));
      return KeyEventResult.handled;
    }
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

  bool _trackKeyboardInput(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _keyboardInput = true;
    }
    return false;
  }

  Widget _withGlobalKeys(Widget child) => Listener(
    onPointerDown: (_) => _keyboardInput = false,
    child: Focus(canRequestFocus: false, onKeyEvent: _globalKey, child: child),
  );

  Future<void> _completeSetup() async {
    widget.controller.completeChannelSetup();
    _onboardingFromAccount = false;
    await _select(1);
  }

  Future<void> _completeSetupAndAdd() async {
    widget.controller.completeChannelSetup();
    _onboardingFromAccount = false;
    await _select(1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _channelsKey.currentState?.openNew();
    });
  }

  Future<void> _requestLogout() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Sign out of Plex?'),
            content: const Text(
              "Playback will stop. You'll need to link Plex again to continue.",
            ),
            actions: [
              TextButton(
                autofocus: true,
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              LineupDestructiveButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    await _logout();
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

  Widget _immersiveAppMenu(bool hasPlaybackSurface) {
    final anchor = _appMenuAnchor;
    if (anchor == null) return const SizedBox.shrink();
    final roles = LineupTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final detailStyle = textTheme.bodyMedium?.copyWith(
      color: roles.secondaryText,
    );
    final profile = widget.controller.profile;
    final profileName = profile?.name;
    final accountName = widget.controller.account?.name ?? 'Plex account';
    final serverName = widget.controller.server?.name ?? 'No server selected';
    return Stack(
      fit: StackFit.expand,
      children: [
        ModalBarrier(
          dismissible: true,
          onDismiss: _closeAppMenu,
          color: roles.scrim.withValues(alpha: 0.45),
        ),
        CustomSingleChildLayout(
          delegate: _AnchoredMenuLayout(anchor),
          child: FocusScope(
            node: _appMenuScope,
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
                color: roles.elevatedSurface,
                margin: EdgeInsets.zero,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _menuDestination(
                        index: 0,
                        label: 'Guide',
                        autofocus: true,
                        detailStyle: detailStyle,
                      ),
                      _menuDestination(
                        index: 4,
                        label: 'Player',
                        enabled: hasPlaybackSurface,
                        helper: hasPlaybackSurface
                            ? null
                            : 'Choose a channel in Guide',
                        detailStyle: detailStyle,
                      ),
                      if (_canShowNowPlaying)
                        LineupNavigationRow(
                          key: const Key('app-menu-now-playing'),
                          selected: false,
                          onPressed: () => unawaited(_openNowPlaying()),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Now Playing'),
                              Text(
                                _player.currentProgram!.scheduled.item.title,
                                style: detailStyle,
                              ),
                            ],
                          ),
                        ),
                      _menuDestination(
                        index: 1,
                        label: 'Channels',
                        detailStyle: detailStyle,
                      ),
                      _menuDestination(
                        index: 2,
                        label: 'Settings',
                        detailStyle: detailStyle,
                      ),
                      Divider(height: 24, thickness: 1.0),
                      Semantics(
                        label: 'Account',
                        child: LineupNavigationRow(
                          key: const Key('app-menu-account'),
                          selected:
                              _selectedIndex == 2 &&
                              _settingsCategory == SettingsCategory.account,
                          onPressed: () => unawaited(_openAccount()),
                          child: Row(
                            children: [
                              LineupProfileAvatar(
                                name: profileName ?? accountName,
                                identity: profile?.id ?? 'account',
                                size: 40,
                                photo: profile?.thumb?.isAbsolute == true
                                    ? NetworkImage(profile!.thumb.toString())
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(profileName ?? accountName),
                                    Text(serverName, style: detailStyle),
                                    LineupConnectionStatus(
                                      connection: widget.controller.connection,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right, size: 22),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _menuDestination({
    required int index,
    required String label,
    bool enabled = true,
    bool autofocus = false,
    String? helper,
    required TextStyle? detailStyle,
  }) {
    final selected = _selectedIndex == index;
    final semanticLabel = [
      label,
      ?helper,
      if (selected) 'current page',
    ].join(', ');
    return Semantics(
      excludeSemantics: true,
      selected: selected,
      button: true,
      enabled: enabled,
      label: semanticLabel,
      onTap: enabled ? () => unawaited(_select(index)) : null,
      child: LineupNavigationRow(
        selected: selected,
        autofocus: autofocus,
        onPressed: enabled ? () => unawaited(_select(index)) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            if (helper != null) Text(helper, style: detailStyle),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller.stage != SetupStage.ready) {
      final onboardingMenuAvailable = _onboardingMenuAvailable;
      final onboarding = controller.stage == SetupStage.channelSetup
          ? UpstreamChannelSetupView(
              controller: controller,
              onViewLineup: _completeSetup,
              onAddCustomChannel: _completeSetupAndAdd,
            )
          : UpstreamOnboardingView(
              controller: controller,
              onLogout: _logout,
              accountOrigin: _onboardingFromAccount,
              onOpenMenu: onboardingMenuAvailable ? _openAppMenu : null,
              menuFocusNode: onboardingMenuAvailable
                  ? _settingsMenuFocus
                  : null,
            );
      if (!_onboardingFromAccount ||
          controller.stage == SetupStage.channelSetup) {
        return onboarding;
      }
      return _withGlobalKeys(
        Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            fit: StackFit.expand,
            children: [
              ExcludeSemantics(
                excluding: _appMenuOpen,
                child: ExcludeFocus(excluding: _appMenuOpen, child: onboarding),
              ),
              if (_appMenuOpen) _immersiveAppMenu(_hasPlaybackSurface),
            ],
          ),
        ),
      );
    }
    final playerView = PlayerView(
      key: _playerKey,
      controller: _player,
      focusNode: _playerFocus,
      openGuide: () => unawaited(_select(0)),
      openMenu: _openAppMenu,
    );
    final hasPlaybackSurface = _hasPlaybackSurface;
    final guidePlaybackUnavailable =
        _player.status.state == PlayerState.unsupported ||
        _player.error != null;
    final guideHasPicture = hasPlaybackSurface && !guidePlaybackUnavailable;
    final guideView = GuideView(
      controller: _guide,
      watchingChannelId:
          !guidePlaybackUnavailable &&
              !_player.tuning &&
              const {
                PlayerState.playing,
                PlayerState.paused,
                PlayerState.buffering,
                PlayerState.seeking,
              }.contains(_player.status.state)
          ? _player.currentChannel?.id
          : null,
      focusNode: _guideFocus,
      onClose: () => _closeGuide(hasPlaybackSurface),
      onOpenMenu: _openAppMenu,
      pictureInPicture: guideHasPicture
          ? PlayerSurface(controller: _player, showErrors: true)
          : GuidePlaybackPlaceholder(
              unavailable: guidePlaybackUnavailable,
              reduceMotion: controller.settings.reduceMotion,
              message:
                  _player.error ??
                  (guidePlaybackUnavailable ? _player.status.message : null),
              onRetry: _player.canRetry ? _player.retry : null,
            ),
      onOpenPlayer: guideHasPicture ? () => unawaited(_select(4)) : null,
      onTune: _tuneFromGuide,
      onSetUpChannels: () => unawaited(controller.enterChannelSetup()),
      showIdleArtwork:
          _player.status.state == PlayerState.idle &&
          !hasPlaybackSurface &&
          !guidePlaybackUnavailable,
    );
    final settingsView = SettingsView(
      controller: controller,
      focusNode: _settingsFocus,
      menuFocusNode: _settingsMenuFocus,
      onOpenMenu: _openAppMenu,
      backLabel:
          '‹ Back to ${switch (_settingsReturnIndex) {
            4 => "Player",
            1 => "Channels",
            _ => "Guide",
          }}',
      onBack: _settingsReturnIndex == null
          ? null
          : () {
              final returnIndex = _settingsReturnIndex!;
              _settingsReturnIndex = null;
              unawaited(_select(returnIndex));
            },
      category: _settingsCategory,
      onCategoryChanged: (category) => setState(() {
        _settingsCategory = category;
      }),
      onSwitchProfile: _openProfilePickerFromAccount,
      onSwitchServer: _openServerPickerFromAccount,
      onSignOut: _requestLogout,
      onOpenDiagnostics: () => unawaited(_select(3)),
    );
    final views = <Widget>[
      guideView,
      ChannelsView(
        key: _channelsKey,
        controller: controller,
        player: _player,
        clock: widget.guideClock,
        focusNode: _channelsFocus,
        menuFocusNode: _channelsMenuFocus,
        onOpenMenu: _openAppMenu,
        onOpenPlayer: () => unawaited(_select(4)),
      ),
      settingsView,
      DiagnosticsView(
        controller: controller,
        playback: _player.diagnosticPlaybackSnapshot,
        onRecordingSettings: () {
          _settingsCategory = SettingsCategory.support;
          unawaited(_select(2));
        },
        focusNode: _diagnosticsFocus,
        menuFocusNode: _diagnosticsMenuFocus,
        onOpenMenu: _openAppMenu,
        onBack: () {
          _settingsCategory = SettingsCategory.support;
          unawaited(_select(2));
        },
      ),
      playerView,
    ];
    final routeView = _selectedIndex == 2
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
                child: SafeArea(
                  child: ColoredBox(
                    color:
                        _selectedIndex == 2 ||
                            _selectedIndex == 4 ||
                            (_selectedIndex == 0 && hasPlaybackSurface)
                        ? Colors.transparent
                        : Theme.of(context).scaffoldBackgroundColor,
                    child: routeView,
                  ),
                ),
              ),
            ),
            if (_appMenuOpen) _immersiveAppMenu(hasPlaybackSurface),
          ],
        ),
      ),
    );
  }
}

class _AnchoredMenuLayout extends SingleChildLayoutDelegate {
  const _AnchoredMenuLayout(this.anchor);

  final Rect anchor;

  double get _margin => 16;
  double get _gap => 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: (constraints.maxWidth - _margin * 2).clamp(0.0, 320),
        maxHeight: (constraints.maxHeight - _margin * 2).clamp(
          0.0,
          double.infinity,
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final horizontalMargin = math.min(_margin, size.width / 2);
    final leftLimit = size.width - childSize.width - horizontalMargin;
    final left = (anchor.right - childSize.width).clamp(
      math.min(horizontalMargin, leftLimit),
      math.max(horizontalMargin, leftLimit),
    );
    final verticalMargin = math.min(_margin, size.height / 2);
    final bottomLimit = size.height - childSize.height - verticalMargin;
    final below = anchor.bottom + _gap;
    final above = anchor.top - childSize.height - _gap;
    final top = below + childSize.height <= size.height - verticalMargin
        ? below
        : above >= verticalMargin
        ? above
        : (anchor.center.dy - childSize.height / 2).clamp(
            math.min(verticalMargin, bottomLimit),
            math.max(verticalMargin, bottomLimit),
          );
    return Offset(left.toDouble(), top.toDouble());
  }

  @override
  bool shouldRelayout(_AnchoredMenuLayout oldDelegate) =>
      oldDelegate.anchor != anchor;
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

enum SettingsCategory {
  appearance,
  guide,
  playback,
  accessibility,
  account,
  support,
}

class SettingsView extends StatefulWidget {
  const SettingsView({
    required this.controller,
    this.category = SettingsCategory.appearance,
    this.onCategoryChanged,
    this.onSwitchProfile,
    this.onSwitchServer,
    this.onSignOut,
    this.onOpenDiagnostics,
    this.focusNode,
    this.menuFocusNode,
    this.onOpenMenu,
    this.onBack,
    this.backLabel = '‹ Back to Guide',
    super.key,
  });
  final LineupController controller;
  final SettingsCategory category;
  final ValueChanged<SettingsCategory>? onCategoryChanged;
  final VoidCallback? onSwitchProfile;
  final VoidCallback? onSwitchServer;
  final Future<void> Function()? onSignOut;
  final VoidCallback? onOpenDiagnostics;
  final FocusNode? focusNode;
  final FocusNode? menuFocusNode;
  final LineupMenuCallback? onOpenMenu;
  final VoidCallback? onBack;
  final String backLabel;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late SettingsCategory _localCategory;
  late LineupSettings _displaySettings;
  late LineupSettings _lastControllerSettings;
  bool _categoryFocusPlaced = false;
  final Map<String, Timer> _savingTimers = {};
  final Set<String> _pendingSettingKeys = {};
  final Set<String> _showSaving = {};
  final Map<String, String> _errors = {};
  final Map<String, LineupSettings Function(LineupSettings)> _pendingChanges =
      {};

  SettingsCategory get _category =>
      widget.onCategoryChanged == null ? _localCategory : widget.category;

  @override
  void initState() {
    super.initState();
    _localCategory = widget.category;
    _lastControllerSettings = widget.controller.settings;
    _displaySettings = _lastControllerSettings;
    widget.controller.addListener(_controllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _categoryFocusPlaced = true;
    });
  }

  @override
  void didUpdateWidget(covariant SettingsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_controllerChanged);
    widget.controller.addListener(_controllerChanged);
    _lastControllerSettings = widget.controller.settings;
    _displaySettings = _lastControllerSettings;
  }

  void _controllerChanged() {
    final settings = widget.controller.settings;
    if (identical(settings, _lastControllerSettings)) return;
    _lastControllerSettings = settings;
    var refreshed = settings;
    for (final keyName in _pendingSettingKeys) {
      refreshed = _pendingChanges[keyName]!(refreshed);
    }
    if (!mounted) return;
    setState(() => _displaySettings = refreshed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    for (final timer in _savingTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsTheme = LineupTheme.forName(
      _displaySettings.theme,
      largeFocusIndicators: _displaySettings.largeFocusIndicators,
    );
    final roles = settingsTheme.extension<LineupThemeRoles>()!;
    return LineupFocusTheme(
      data: settingsTheme,
      child: Material(
        type: MaterialType.transparency,
        child: FocusTraversalGroup(
          child: ColoredBox(
            key: const Key('settings-immersive-scrim'),
            color: roles.deepBackground.withValues(alpha: 0.94),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact =
                    LineupLayout.isCompactWidth(constraints.maxWidth) ||
                    MediaQuery.textScalerOf(context).scale(1) >= 2;
                final theme = Theme.of(context);
                return DefaultTextStyle(
                  style: theme.textTheme.bodyMedium!,
                  child: Builder(
                    builder: (context) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LineupTopBar(
                          menuKey: const Key('settings-app-menu'),
                          onOpenMenu: widget.onOpenMenu,
                          menuFocusNode: widget.menuFocusNode,
                        ),
                        Expanded(
                          child: LineupContentWidth(
                            vertical: 24,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _settingsHeader(context),
                                const SizedBox(height: 24),
                                Expanded(
                                  child: compact
                                      ? Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            _categoryRail(context, true),
                                            Expanded(
                                              child: _detailPane(context, true),
                                            ),
                                          ],
                                        )
                                      : Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            _categoryRail(context, false),
                                            Expanded(
                                              child: _detailPane(
                                                context,
                                                false,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ],
                            ),
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
    );
  }

  Widget _settingsHeader(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (widget.onBack != null)
        LineupInlineLink(
          onPressed: widget.onBack,
          child: Text(widget.backLabel),
        ),
      Text(
        'Settings',
        style: LineupTypography.pageTitle.copyWith(
          color: LineupTheme.of(context).primaryText,
        ),
      ),
    ],
  );

  Widget _categoryRail(BuildContext context, bool compact) {
    final roles = LineupTheme.of(context);
    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 20 : 0,
        compact ? 14 : 8,
        compact ? 20 : 32,
        compact ? 12 : 0,
      ),
      child: compact
          ? _categorySelector(context, true)
          : _categorySelector(context, false),
    );
    return DecoratedBox(
      key: const Key('settings-category-rail'),
      decoration: BoxDecoration(
        border: Border(
          right: compact
              ? BorderSide.none
              : BorderSide(color: roles.subtleBorder),
          bottom: compact
              ? BorderSide(color: roles.subtleBorder)
              : BorderSide.none,
        ),
      ),
      child: compact ? content : SizedBox(width: 312, child: content),
    );
  }

  Widget _detailPane(BuildContext context, bool compact) => Padding(
    key: const Key('settings-detail-pane'),
    padding: EdgeInsets.fromLTRB(
      (compact ? 20 : 48),
      (compact ? 20 : 8),
      (compact ? 20 : 24),
      (compact ? 20 : 24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [Expanded(child: _categoryDetail(context))],
    ),
  );

  Widget _categorySelector(BuildContext context, bool compact) {
    final controls = [
      for (final category in SettingsCategory.values)
        Padding(
          padding: EdgeInsets.only(right: 10, bottom: 10),
          child: LineupNavigationRow(
            selected: category == _category,
            focusNode: category == _category ? widget.focusNode : null,
            autofocus: category == _category && !_categoryFocusPlaced,
            onPressed: () {
              setState(() => _localCategory = category);
              widget.onCategoryChanged?.call(category);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && category == _category) {
                  widget.focusNode?.requestFocus();
                }
              });
            },
            child: Text(_categoryLabel(category)),
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

  Widget _categoryDetail(BuildContext context) {
    final value = _displaySettings;

    return ListView(
      children: [
        _SettingsSection(
          title: _categoryLabel(_category),
          description: _categoryDescription(_category),
          children: switch (_category) {
            SettingsCategory.appearance => [
              _Dropdown<LineupThemeName>(
                'Theme',
                'Color and surface treatment throughout Lineup.',
                value.theme,
                LineupThemeName.values,
                (item) => item.label,
                _pendingSettingKeys.contains('theme')
                    ? null
                    : (item) => _update(
                        'theme',
                        (current) => current.copyWith(theme: item),
                      ),
                first: true,
              ),
              _settingFeedback('theme'),
              _Dropdown<GuideInfoBackgroundMode>(
                'Guide information background',
                'Choose artwork colors, the theme, or an artwork backdrop.',
                value.guideInfoBackgroundMode,
                GuideInfoBackgroundMode.values,
                (item) => switch (item) {
                  GuideInfoBackgroundMode.bleed => 'Artwork colors',
                  GuideInfoBackgroundMode.themeDefault => 'Theme background',
                  GuideInfoBackgroundMode.artwork => 'Artwork backdrop',
                },
                _pendingSettingKeys.contains('guideInfoBackgroundMode')
                    ? null
                    : (item) => _update(
                        'guideInfoBackgroundMode',
                        (current) =>
                            current.copyWith(guideInfoBackgroundMode: item),
                      ),
              ),
              _settingFeedback('guideInfoBackgroundMode'),
              _SettingsSwitchTile(
                title: const Text('Use title artwork'),
                subtitle: const Text(
                  'Use available Plex title artwork with a readable text fallback.',
                ),
                value: value.preferClearLogos,
                onChanged: _pendingSettingKeys.contains('preferClearLogos')
                    ? null
                    : (item) => _update(
                        'preferClearLogos',
                        (current) => current.copyWith(preferClearLogos: item),
                      ),
              ),
              _settingFeedback('preferClearLogos'),
              _Dropdown<OverlayTransparency>(
                'Player overlays',
                'How much of the picture shows through Player controls and panels. More transparent can be harder to read on bright scenes.',
                value.overlayTransparency,
                OverlayTransparency.values,
                (item) => item.label,
                _pendingSettingKeys.contains('overlayTransparency')
                    ? null
                    : (item) => _update(
                        'overlayTransparency',
                        (current) =>
                            current.copyWith(overlayTransparency: item),
                      ),
                choiceDescription: (item) => switch (item) {
                  OverlayTransparency.moreTransparent => 'Lightest',
                  OverlayTransparency.standard => 'Default',
                  OverlayTransparency.reduced => 'Most solid, easiest to read',
                },
              ),
              _settingFeedback('overlayTransparency'),
            ],
            SettingsCategory.guide => [
              _Dropdown<int>(
                'Visible hours',
                'Choose how much of the schedule appears at once.',
                value.guideHours,
                LineupSettings.guideHoursOptions,
                (item) => switch (item) {
                  2 => 'Detailed (2 hours)',
                  3 => 'Wide (3 hours)',
                  _ => 'Extended ($item hours)',
                },
                choiceDescription: (item) => switch (item) {
                  2 => 'Less schedule at once',
                  3 => 'Balanced schedule at once',
                  _ => 'More schedule at once',
                },
                _pendingSettingKeys.contains('guideHours')
                    ? null
                    : (item) => _update(
                        'guideHours',
                        (current) => current.copyWith(guideHours: item),
                      ),
                first: true,
              ),
              _settingFeedback('guideHours'),
              _SettingsSwitchTile(
                title: const Text('Show channel sources'),
                subtitle: const Text(
                  "Show where each channel's programs come from under its name in the Guide.",
                ),
                value: value.guideShowChannelSources,
                onChanged:
                    _pendingSettingKeys.contains('guideShowChannelSources')
                    ? null
                    : (item) => _update(
                        'guideShowChannelSources',
                        (current) =>
                            current.copyWith(guideShowChannelSources: item),
                      ),
              ),
              _settingFeedback('guideShowChannelSources'),
              _SettingsSwitchTile(
                title: const Text('Show now playing in Guide'),
                subtitle: const Text(
                  'Identify the playing channel and program while browsing other listings.',
                ),
                value: value.nowWatchingBanner,
                onChanged: _pendingSettingKeys.contains('nowWatchingBanner')
                    ? null
                    : (item) => _update(
                        'nowWatchingBanner',
                        (current) => current.copyWith(nowWatchingBanner: item),
                      ),
              ),
              _settingFeedback('nowWatchingBanner'),
            ],
            SettingsCategory.playback => [
              _Dropdown<int>(
                'Player controls auto-hide',
                'Set how long controls remain visible while playing.',
                value.osdAutoHideSeconds,
                LineupSettings.osdAutoHideSecondsOptions,
                (item) => '$item seconds',
                _pendingSettingKeys.contains('osdAutoHideSeconds')
                    ? null
                    : (item) => _update(
                        'osdAutoHideSeconds',
                        (current) => current.copyWith(osdAutoHideSeconds: item),
                      ),
                first: true,
              ),
              _settingFeedback('osdAutoHideSeconds'),
              _SettingsSwitchTile(
                title: const Text('DVR playback controls'),
                subtitle: const Text(
                  'Show transport controls and enable pause, seek, stop, and media-key shortcuts in Player.',
                ),
                value: value.dvrControlsEnabled,
                onChanged: _pendingSettingKeys.contains('dvrControlsEnabled')
                    ? null
                    : (item) => _update(
                        'dvrControlsEnabled',
                        (current) => current.copyWith(dvrControlsEnabled: item),
                      ),
              ),
              _settingFeedback('dvrControlsEnabled'),
            ],
            SettingsCategory.accessibility => [
              _SettingsSwitchTile(
                title: const Text('Reduce motion'),
                subtitle: const Text(
                  'Disable nonessential application transitions.',
                ),
                value: value.reduceMotion,
                onChanged: _pendingSettingKeys.contains('reduceMotion')
                    ? null
                    : (item) => _update(
                        'reduceMotion',
                        (current) => current.copyWith(reduceMotion: item),
                      ),
                first: true,
              ),
              _settingFeedback('reduceMotion'),
              _SettingsSwitchTile(
                title: const Text('Large focus indicators'),
                subtitle: const Text(
                  'Use thicker outlines when navigating with a keyboard or remote.',
                ),
                value: value.largeFocusIndicators,
                onChanged: _pendingSettingKeys.contains('largeFocusIndicators')
                    ? null
                    : (item) => _update(
                        'largeFocusIndicators',
                        (current) =>
                            current.copyWith(largeFocusIndicators: item),
                      ),
              ),
              _settingFeedback('largeFocusIndicators'),
            ],
            SettingsCategory.account => [
              _SettingsRow(
                label: const Text('Plex Home profile'),
                helper: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    LineupProfileAvatar(
                      name:
                          widget.controller.profile?.name ??
                          widget.controller.account?.name ??
                          'Plex account',
                      identity:
                          widget.controller.profile?.id ??
                          widget.controller.account?.id ??
                          'account',
                      photo:
                          widget.controller.profile?.thumb?.isAbsolute == true
                          ? NetworkImage(
                              widget.controller.profile!.thumb.toString(),
                            )
                          : null,
                      size: 48,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.controller.profile?.name ??
                            widget.controller.account?.name ??
                            'Plex account',
                      ),
                    ),
                  ],
                ),
                control: OutlinedButton(
                  onPressed: widget.controller.profiles.isEmpty
                      ? null
                      : widget.onSwitchProfile ??
                            widget.controller.showProfiles,
                  child: const Text('Switch profile'),
                ),
                first: true,
              ),
              _SettingsSwitchTile(
                title: const Text('Show profile picker on startup'),
                subtitle: const Text(
                  'Ask who is watching when this Plex Home has multiple profiles.',
                ),
                value: value.profilePickerOnStartup,
                onChanged:
                    _pendingSettingKeys.contains('profilePickerOnStartup')
                    ? null
                    : (item) => _update(
                        'profilePickerOnStartup',
                        (current) =>
                            current.copyWith(profilePickerOnStartup: item),
                      ),
              ),
              _settingFeedback('profilePickerOnStartup'),
              _SettingsRow(
                label: const Text('Plex Media Server'),
                helper: widget.controller.server == null
                    ? const Text('No server selected')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.controller.server!.name),
                          LineupConnectionStatus(
                            connection: widget.controller.connection,
                          ),
                        ],
                      ),
                control: OutlinedButton(
                  onPressed:
                      widget.onSwitchServer ?? widget.controller.showServers,
                  child: const Text('Switch server'),
                ),
              ),
              SizedBox(height: 24),
              _SettingsRow(
                label: const Text('Signed-in Plex account'),
                helper: Text(widget.controller.account?.name ?? 'Plex account'),
                control: OutlinedButton(
                  onPressed: widget.onSignOut == null
                      ? null
                      : () => unawaited(widget.onSignOut!()),
                  child: const Text('Sign out of Plex'),
                ),
              ),
            ],
            SettingsCategory.support => [
              _SettingsSwitchTile(
                title: const Text('Record redacted diagnostics'),
                subtitle: const Text(
                  'Tokens, URLs, paths, headers and credentials are excluded. Turning this off clears recorded events.',
                ),
                value: value.diagnosticsEnabled,
                onChanged: _pendingSettingKeys.contains('diagnosticsEnabled')
                    ? null
                    : (item) => _update(
                        'diagnosticsEnabled',
                        (current) => current.copyWith(diagnosticsEnabled: item),
                      ),
                first: true,
              ),
              _settingFeedback('diagnosticsEnabled'),
              _SettingsRow(
                label: const Text('Diagnostics'),
                helper: const Text(
                  'Review redacted support events from this session.',
                ),
                control: OutlinedButton(
                  onPressed: widget.onOpenDiagnostics,
                  child: const Text('Open Diagnostics'),
                ),
              ),
            ],
          },
        ),
      ],
    );
  }

  Widget _settingFeedback(String keyName) {
    final error = _errors[keyName];
    if (error != null) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          error,
          key: ValueKey('setting-error-$keyName'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }
    if (_showSaving.contains(keyName)) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text('Saving…'),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _update(
    String keyName,
    LineupSettings Function(LineupSettings) change,
  ) async {
    if (_pendingSettingKeys.contains(keyName)) return;
    setState(() {
      _pendingSettingKeys.add(keyName);
      _errors.remove(keyName);
      _pendingChanges[keyName] = change;
      _displaySettings = change(_displaySettings);
    });
    _savingTimers[keyName] = Timer(const Duration(milliseconds: 300), () {
      if (mounted && _pendingSettingKeys.contains(keyName)) {
        setState(() => _showSaving.add(keyName));
      }
    });
    String? error;
    try {
      await widget.controller.updateSettings(change);
    } catch (_) {
      error = 'Could not save. The previous value was restored.';
    } finally {
      _savingTimers.remove(keyName)?.cancel();
      if (mounted) {
        setState(() {
          _pendingSettingKeys.remove(keyName);
          _showSaving.remove(keyName);
          _pendingChanges.remove(keyName);
          var refreshed = widget.controller.settings;
          for (final pending in _pendingChanges.values) {
            refreshed = pending(refreshed);
          }
          _displaySettings = refreshed;
          if (error != null) _errors[keyName] = error;
        });
      }
    }
  }

  static String _categoryLabel(SettingsCategory category) => switch (category) {
    SettingsCategory.appearance => 'Appearance',
    SettingsCategory.guide => 'Guide',
    SettingsCategory.playback => 'Playback',
    SettingsCategory.accessibility => 'Accessibility',
    SettingsCategory.account => 'Account',
    SettingsCategory.support => 'Support',
  };

  static String _categoryDescription(SettingsCategory category) =>
      switch (category) {
        SettingsCategory.appearance => 'Choose the atmosphere of your lineup.',
        SettingsCategory.guide => 'Browse the schedule your way.',
        SettingsCategory.playback => 'Control how playback controls behave.',
        SettingsCategory.accessibility =>
          'Make navigation easier to see and follow.',
        SettingsCategory.account =>
          'Manage who is watching and where your media comes from.',
        SettingsCategory.support =>
          'Collect useful information when something goes wrong.',
      };
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.description,
    required this.children,
  });

  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: roles.primaryText,
              fontSize: 44,
              fontWeight: FontWeight.w600,
              height: 1.08,
            ),
          ),
        ),
        SizedBox(height: 6),
        Text(
          description,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: roles.secondaryText,
            fontSize: 18,
            height: 1.5,
          ),
        ),
        SizedBox(height: 32),
        ...children,
      ],
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.label,
    required this.helper,
    required this.control,
    this.first = false,
  });

  final Widget label;
  final Widget helper;
  final Widget control;
  final bool first;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final reflow =
          constraints.maxWidth < 900 ||
          MediaQuery.textScalerOf(context).scale(1) >= 1.5;
      final controlWidth = math.min(280.0, constraints.maxWidth);
      final theme = Theme.of(context);
      final roles = LineupTheme.of(context);
      final description = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefaultTextStyle.merge(
            style: theme.textTheme.titleMedium?.copyWith(
              color: roles.primaryText,
              fontSize: 18,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
            child: label,
          ),
          SizedBox(height: 6),
          DefaultTextStyle.merge(
            style: theme.textTheme.bodyLarge?.copyWith(
              color: roles.secondaryText,
              fontSize: 18,
              height: 1.5,
            ),
            child: helper,
          ),
        ],
      );
      return Container(
        constraints: BoxConstraints(minHeight: 132),
        padding: EdgeInsets.fromLTRB(0, (first ? 16 : 28), 0, 28),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: roles.subtleBorder)),
        ),
        child: reflow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  description,
                  SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(width: controlWidth, child: control),
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: description),
                  SizedBox(width: 32),
                  SizedBox(width: controlWidth, child: control),
                ],
              ),
      );
    },
  );
}

class _SettingsSwitchTile extends StatelessWidget {
  const _SettingsSwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.first = false,
  });

  final Widget title;
  final Widget subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool first;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: _SettingsRow(
      label: title,
      helper: subtitle,
      control: Builder(
        builder: (context) {
          return SizedBox(
            height: 48,
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: 56,
                child: Switch(
                  value: value,
                  onChanged: onChanged,
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          );
        },
      ),
      first: first,
    ),
  );
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown(
    this.label,
    this.description,
    this.value,
    this.values,
    this.display,
    this.changed, {
    this.choiceDescription,
    this.first = false,
  });
  final String label;
  final String description;
  final T value;
  final List<T> values;
  final String Function(T) display;
  final ValueChanged<T>? changed;
  final String Function(T)? choiceDescription;
  final bool first;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <DropdownMenuItem<T>>[];
    final selectedItems = <Widget>[];
    for (final item in values) {
      final label = display(item);
      items.add(
        DropdownMenuItem(
          value: item,
          child: choiceDescription == null
              ? Text(label)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label),
                    Text(
                      choiceDescription!(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: LineupTheme.of(context).secondaryText,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
        ),
      );
      selectedItems.add(Text(label));
    }
    return MergeSemantics(
      child: _SettingsRow(
        label: Text(label),
        helper: Text(description),
        control: SizedBox(
          width: double.infinity,
          child: lineupDropdownField<T>(
            context: context,
            key: ValueKey('settings-field-$label'),
            initialValue: value,
            isExpanded: true,
            itemHeight: null,
            icon: const Icon(Icons.arrow_drop_down, size: 20),
            style: theme.textTheme.bodyLarge?.copyWith(fontSize: 18),
            decoration: InputDecoration(),
            items: items,
            selectedItemChildren: choiceDescription == null
                ? null
                : selectedItems,
            onChanged: changed == null
                ? null
                : (item) {
                    if (item != null) changed!(item);
                  },
          ),
        ),
        first: first,
      ),
    );
  }
}
