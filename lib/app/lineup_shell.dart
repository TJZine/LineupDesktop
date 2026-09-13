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
import '../plex/plex_models.dart';
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
  Rect? _appMenuAnchor;
  FocusNode? _appMenuInvokerFocus;
  SettingsCategory _settingsCategory = SettingsCategory.appearance;
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
    _channelsMenuFocus.dispose();
    _settingsMenuFocus.dispose();
    _diagnosticsMenuFocus.dispose();
    _appMenuScope.dispose();
    super.dispose();
  }

  Future<void> _select(int index) async {
    if (_selectionPending) return;
    if (index == 4 && !_hasPlaybackSurface) {
      if (_appMenuOpen) _closeAppMenu();
      return;
    }
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
      _appMenuAnchor =
          renderObject.localToGlobal(Offset.zero) & renderObject.size;
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
    setState(() {
      _appMenuOpen = false;
      _appMenuAnchor = null;
      _appMenuInvokerFocus = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (restoreInvoker && invoker?.context != null) {
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

  KeyEventResult _globalKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        FocusManager.instance.primaryFocus?.context
                ?.findAncestorStateOfType<EditableTextState>() !=
            null) {
      return KeyEventResult.ignored;
    }
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
              FilledButton(
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
    final scale = LineupLayout.scaleFor(MediaQuery.sizeOf(context));
    final textTheme = Theme.of(context).textTheme;
    final titleStyle = textTheme.titleLarge?.copyWith(
      fontSize: (textTheme.titleLarge?.fontSize ?? 22) * scale,
    );
    final labelStyle = textTheme.labelLarge?.copyWith(fontSize: 16 * scale);
    final detailStyle = textTheme.bodySmall?.copyWith(fontSize: 14 * scale);
    final menuShape = scale > 1
        ? RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(roles.panelRadius * scale),
            side: BorderSide(color: roles.subtleBorder, width: scale),
          )
        : null;
    final profileName = widget.controller.profile?.name;
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
          delegate: _AnchoredMenuLayout(anchor, scale),
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
                margin: EdgeInsets.zero,
                shape: menuShape,
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(12 * scale),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          12 * scale,
                          4 * scale,
                          4 * scale,
                          8 * scale,
                        ),
                        child: Row(
                          children: [
                            Expanded(child: Text('Lineup', style: titleStyle)),
                            IconButton(
                              constraints: BoxConstraints(
                                minWidth: 48 * scale,
                                minHeight: 48 * scale,
                              ),
                              padding: EdgeInsets.all(8 * scale),
                              iconSize: 24 * scale,
                              tooltip: 'Close Lineup menu',
                              onPressed: _closeAppMenu,
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      _menuDestination(
                        index: 0,
                        label: 'Guide',
                        autofocus: true,
                        labelStyle: labelStyle,
                        detailStyle: detailStyle,
                        scale: scale,
                      ),
                      _menuDestination(
                        index: 4,
                        label: 'Player',
                        enabled: hasPlaybackSurface,
                        helper: hasPlaybackSurface
                            ? null
                            : 'Choose a channel in Guide',
                        labelStyle: labelStyle,
                        detailStyle: detailStyle,
                        scale: scale,
                      ),
                      _menuDestination(
                        index: 1,
                        label: 'Channels',
                        labelStyle: labelStyle,
                        detailStyle: detailStyle,
                        scale: scale,
                      ),
                      _menuDestination(
                        index: 2,
                        label: 'Settings',
                        labelStyle: labelStyle,
                        detailStyle: detailStyle,
                        scale: scale,
                      ),
                      Divider(height: 24 * scale, thickness: scale),
                      Semantics(
                        selected:
                            _selectedIndex == 2 &&
                            _settingsCategory == SettingsCategory.account,
                        button: true,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            padding: EdgeInsets.all(12 * scale),
                            foregroundColor:
                                _selectedIndex == 2 &&
                                    _settingsCategory ==
                                        SettingsCategory.account
                                ? roles.primaryText
                                : roles.secondaryText,
                            textStyle: labelStyle,
                          ),
                          onPressed: () => unawaited(_openAccount()),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Account'),
                              SizedBox(height: 4 * scale),
                              Text(
                                profileName == null
                                    ? accountName
                                    : '$profileName · $accountName',
                                softWrap: true,
                                style: detailStyle,
                              ),
                              SizedBox(height: 3 * scale),
                              Text(
                                serverName,
                                softWrap: true,
                                style: detailStyle?.copyWith(
                                  color: roles.secondaryText,
                                ),
                              ),
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
    required TextStyle? labelStyle,
    required TextStyle? detailStyle,
    required double scale,
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
      child: TextButton(
        autofocus: autofocus,
        style: TextButton.styleFrom(
          alignment: Alignment.centerLeft,
          minimumSize: Size(0, 48 * scale),
          padding: EdgeInsets.all(12 * scale),
          foregroundColor: selected
              ? LineupTheme.of(context).primaryText
              : LineupTheme.of(context).secondaryText,
          backgroundColor: selected
              ? LineupTheme.of(context).selectedSurface
              : null,
          textStyle: labelStyle,
        ),
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
    );
    final settingsView = SettingsView(
      controller: controller,
      focusNode: _settingsFocus,
      menuFocusNode: _settingsMenuFocus,
      onOpenMenu: _openAppMenu,
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
        onBack: () => unawaited(_select(2)),
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
  const _AnchoredMenuLayout(this.anchor, this.scale);

  final Rect anchor;
  final double scale;

  double get _margin => 16 * scale;
  double get _gap => 8 * scale;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: (constraints.maxWidth - _margin * 2).clamp(0.0, 320 * scale),
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
      oldDelegate.anchor != anchor || oldDelegate.scale != scale;
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
    this.onSignOut,
    this.onOpenDiagnostics,
    this.focusNode,
    this.menuFocusNode,
    this.onOpenMenu,
    this.onBack,
    super.key,
  });
  final LineupController controller;
  final SettingsCategory category;
  final ValueChanged<SettingsCategory>? onCategoryChanged;
  final Future<void> Function()? onSignOut;
  final VoidCallback? onOpenDiagnostics;
  final FocusNode? focusNode;
  final FocusNode? menuFocusNode;
  final LineupMenuCallback? onOpenMenu;
  final VoidCallback? onBack;

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
  Future<void> _saveTail = Future.value();

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
      refreshed = _mergeSetting(keyName, refreshed, _displaySettings);
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
    return Theme(
      data: settingsTheme,
      child: Material(
        type: MaterialType.transparency,
        child: FocusTraversalGroup(
          child: ColoredBox(
            key: const Key('settings-immersive-scrim'),
            color: roles.deepBackground.withValues(alpha: 0.94),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                final layoutScale = LineupLayout.scaleFor(size);
                final scale =
                    layoutScale *
                    (size.height / 1080).clamp(0.82, 1.0).toDouble();
                final compact =
                    LineupLayout.isCompactWidth(constraints.maxWidth) ||
                    MediaQuery.textScalerOf(context).scale(1) >= 2;
                final scaledTheme = Theme.of(context).copyWith(
                  textTheme: Theme.of(context).textTheme
                      .apply(fontSizeFactor: layoutScale),
                );
                return Theme(
                  data: scaledTheme,
                  child: DefaultTextStyle(
                    style: scaledTheme.textTheme.bodyMedium!,
                    child: Builder(
                      builder: (context) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _settingsHeader(context, scale),
                          Expanded(
                            child: compact
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _categoryRail(context, true, scale),
                                      Expanded(
                                        child: _detailPane(
                                          context,
                                          true,
                                          scale,
                                        ),
                                      ),
                                    ],
                                  )
                                : Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      48 * scale,
                                      32 * scale,
                                      48 * scale,
                                      0,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _categoryRail(context, false, scale),
                                        Expanded(
                                          child: _detailPane(
                                            context,
                                            false,
                                            scale,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                        ],
                      ),
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

  Widget _settingsHeader(BuildContext context, double scale) => Container(
    height: 96 * scale,
    margin: EdgeInsets.symmetric(horizontal: 48 * scale),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: LineupTheme.of(context).subtleBorder),
      ),
    ),
    child: Row(
      children: [
        TextButton.icon(
          onPressed: widget.onBack,
          icon: Icon(Icons.arrow_back, size: 18 * scale),
          label: const Text('Back'),
          style: TextButton.styleFrom(
            foregroundColor: LineupTheme.of(context).secondaryText,
            minimumSize: Size(0, 48 * scale),
            padding: EdgeInsets.symmetric(
              horizontal: 4 * scale,
              vertical: 8 * scale,
            ),
            textStyle: Theme.of(context).textTheme.labelLarge
                ?.copyWith(fontSize: 18 * scale),
          ),
        ),
        SizedBox(width: 12 * scale),
        Text(
          'Settings',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: LineupTheme.of(context).primaryText,
            fontSize: 26 * scale,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        if (widget.onOpenMenu != null && widget.menuFocusNode != null)
          Builder(
            builder: (buttonContext) => TextButton(
              key: const Key('settings-app-menu'),
              focusNode: widget.menuFocusNode,
              onPressed: () =>
                  widget.onOpenMenu!(buttonContext, widget.menuFocusNode!),
              style: TextButton.styleFrom(
                foregroundColor: LineupTheme.of(context).primaryText,
                minimumSize: Size(0, 48 * scale),
                padding: EdgeInsets.symmetric(
                  horizontal: 4 * scale,
                  vertical: 8 * scale,
                ),
                textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontSize: 20 * scale,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.5 * scale,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('LINEUP'),
                  SizedBox(width: 12 * scale),
                  Icon(Icons.menu, size: 18 * scale),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  Widget _categoryRail(BuildContext context, bool compact, double scale) {
    final roles = LineupTheme.of(context);
    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 20 * scale : 0,
        compact ? 14 * scale : 8 * scale,
        compact ? 20 * scale : 32 * scale,
        compact ? 12 * scale : 0,
      ),
      child: compact
          ? _categorySelector(context, true, scale)
          : _categorySelector(context, false, scale),
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
      child: compact ? content : SizedBox(width: 312 * scale, child: content),
    );
  }

  Widget _detailPane(BuildContext context, bool compact, double scale) =>
      Padding(
        key: const Key('settings-detail-pane'),
        padding: EdgeInsets.fromLTRB(
          (compact ? 20 : 48) * scale,
          (compact ? 20 : 8) * scale,
          (compact ? 20 : 24) * scale,
          (compact ? 20 : 24) * scale,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [Expanded(child: _categoryDetail(context))],
        ),
      );

  Widget _categorySelector(BuildContext context, bool compact, double scale) {
    final roles = LineupTheme.of(context);
    final controls = [
      for (final category in SettingsCategory.values)
        Padding(
          padding: EdgeInsets.only(right: 10 * scale, bottom: 10 * scale),
          child: Semantics(
            selected: category == _category,
            button: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: category == _category
                    ? roles.selectedSurface
                    : Colors.transparent,
                border: Border(
                  left: BorderSide(
                    width: 2 * scale,
                    color: category == _category
                        ? roles.progressFill
                        : Colors.transparent,
                  ),
                ),
              ),
              child: TextButton(
                focusNode: category == _category ? widget.focusNode : null,
                autofocus: category == _category && !_categoryFocusPlaced,
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  foregroundColor: category == _category
                      ? roles.primaryText
                      : roles.secondaryText,
                  padding: EdgeInsets.symmetric(
                    horizontal: 16 * scale,
                    vertical: 18 * scale,
                  ),
                  minimumSize: Size(0, 0),
                  textStyle: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(fontSize: 18 * scale),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5 * scale),
                  ),
                ),
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
    final size = MediaQuery.sizeOf(context);
    final roles = LineupTheme.of(context);
    final scale =
        LineupLayout.scaleFor(size) *
        (size.height / 1080).clamp(0.82, 1.0).toDouble();
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
                    : (item) => _update('theme', value.copyWith(theme: item)),
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
                        value.copyWith(guideInfoBackgroundMode: item),
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
                        value.copyWith(preferClearLogos: item),
                      ),
              ),
              _settingFeedback('preferClearLogos'),
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
                _pendingSettingKeys.contains('guideHours')
                    ? null
                    : (item) => _update(
                        'guideHours',
                        value.copyWith(guideHours: item),
                      ),
                first: true,
              ),
              _settingFeedback('guideHours'),
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
                        value.copyWith(nowWatchingBanner: item),
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
                        value.copyWith(osdAutoHideSeconds: item),
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
                        value.copyWith(dvrControlsEnabled: item),
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
                        value.copyWith(reduceMotion: item),
                      ),
                first: true,
              ),
              _settingFeedback('reduceMotion'),
              _SettingsSwitchTile(
                title: const Text('Large focus indicators'),
                subtitle: const Text(
                  'Use thicker outlines for keyboard and controller focus.',
                ),
                value: value.largeFocusIndicators,
                onChanged: _pendingSettingKeys.contains('largeFocusIndicators')
                    ? null
                    : (item) => _update(
                        'largeFocusIndicators',
                        value.copyWith(largeFocusIndicators: item),
                      ),
              ),
              _settingFeedback('largeFocusIndicators'),
            ],
            SettingsCategory.account => [
              _SettingsRow(
                label: const Text('Plex Home profile'),
                helper: Text(
                  widget.controller.profile?.name ??
                      widget.controller.account?.name ??
                      'Plex account',
                ),
                control: OutlinedButton(
                  onPressed: widget.controller.profiles.isEmpty
                      ? null
                      : widget.controller.showProfiles,
                  style: OutlinedButton.styleFrom(
                    minimumSize: Size(0, 48 * scale),
                    padding: EdgeInsets.symmetric(
                      horizontal: 16 * scale,
                      vertical: 10 * scale,
                    ),
                    textStyle: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(fontSize: 16 * scale),
                  ),
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
                        value.copyWith(profilePickerOnStartup: item),
                      ),
              ),
              _settingFeedback('profilePickerOnStartup'),
              _SettingsRow(
                label: const Text('Plex Media Server'),
                helper: Text(
                  widget.controller.server == null
                      ? 'No server selected'
                      : widget.controller.connection == null
                      ? widget.controller.server!.name
                      : '${widget.controller.server!.name} • ${plexConnectionDescription(widget.controller.connection!)}',
                ),
                control: OutlinedButton(
                  onPressed: widget.controller.showServers,
                  style: OutlinedButton.styleFrom(
                    minimumSize: Size(0, 48 * scale),
                    padding: EdgeInsets.symmetric(
                      horizontal: 16 * scale,
                      vertical: 10 * scale,
                    ),
                    textStyle: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(fontSize: 16 * scale),
                  ),
                  child: const Text('Switch server'),
                ),
              ),
              SizedBox(height: 24 * scale),
              _SettingsRow(
                label: const Text('Signed-in Plex account'),
                helper: Text(widget.controller.account?.name ?? 'Plex account'),
                control: OutlinedButton(
                  onPressed: widget.onSignOut == null
                      ? null
                      : () => unawaited(widget.onSignOut!()),
                  style: ButtonStyle(
                    foregroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.disabled)
                          ? roles.mutedText
                          : roles.secondaryText,
                    ),
                    side: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.focused)
                          ? null
                          : BorderSide(
                              color: states.contains(WidgetState.disabled)
                                  ? roles.subtleBorder.withValues(alpha: 0.6)
                                  : roles.subtleBorder,
                            ),
                    ),
                    minimumSize: WidgetStatePropertyAll(Size(0, 48 * scale)),
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(
                        horizontal: 16 * scale,
                        vertical: 10 * scale,
                      ),
                    ),
                    textStyle: WidgetStatePropertyAll(
                      Theme.of(context).textTheme.labelLarge
                          ?.copyWith(fontSize: 16 * scale),
                    ),
                  ),
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
                        value.copyWith(diagnosticsEnabled: item),
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
                  style: OutlinedButton.styleFrom(
                    minimumSize: Size(0, 48 * scale),
                    padding: EdgeInsets.symmetric(
                      horizontal: 16 * scale,
                      vertical: 10 * scale,
                    ),
                    textStyle: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(fontSize: 16 * scale),
                  ),
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
    final size = MediaQuery.sizeOf(context);
    final scale =
        LineupLayout.scaleFor(size) *
        (size.height / 1080).clamp(0.82, 1.0).toDouble();
    final error = _errors[keyName];
    if (error != null) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16 * scale, 0, 16 * scale, 8 * scale),
        child: Text(
          error,
          key: ValueKey('setting-error-$keyName'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }
    if (_showSaving.contains(keyName)) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16 * scale, 0, 16 * scale, 8 * scale),
        child: Text('Saving…'),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _update(String keyName, LineupSettings next) async {
    if (_pendingSettingKeys.contains(keyName)) return;
    setState(() {
      _pendingSettingKeys.add(keyName);
      _errors.remove(keyName);
      _displaySettings = _mergeSetting(keyName, _displaySettings, next);
    });
    _savingTimers[keyName] = Timer(const Duration(milliseconds: 300), () {
      if (mounted && _pendingSettingKeys.contains(keyName)) {
        setState(() => _showSaving.add(keyName));
      }
    });
    String? error;
    try {
      final operation = _saveTail.then(
        (_) => widget.controller.updateSettings(
          _mergeSetting(keyName, widget.controller.settings, next),
        ),
      );
      _saveTail = operation.then<void>((_) {}, onError: (_, _) {});
      await operation;
    } catch (_) {
      error = 'Could not save. The previous value was restored.';
    } finally {
      _savingTimers.remove(keyName)?.cancel();
      if (mounted) {
        setState(() {
          _pendingSettingKeys.remove(keyName);
          _showSaving.remove(keyName);
          if (error != null) {
            _displaySettings = _mergeSetting(
              keyName,
              _displaySettings,
              widget.controller.settings,
            );
            _errors[keyName] = error;
          }
        });
      }
    }
  }

  static LineupSettings _mergeSetting(
    String keyName,
    LineupSettings current,
    LineupSettings requested,
  ) => switch (keyName) {
    'theme' => current.copyWith(theme: requested.theme),
    'guideHours' => current.copyWith(guideHours: requested.guideHours),
    'guideInfoBackgroundMode' => current.copyWith(
      guideInfoBackgroundMode: requested.guideInfoBackgroundMode,
    ),
    'preferClearLogos' => current.copyWith(
      preferClearLogos: requested.preferClearLogos,
    ),
    'nowWatchingBanner' => current.copyWith(
      nowWatchingBanner: requested.nowWatchingBanner,
    ),
    'osdAutoHideSeconds' => current.copyWith(
      osdAutoHideSeconds: requested.osdAutoHideSeconds,
    ),
    'dvrControlsEnabled' => current.copyWith(
      dvrControlsEnabled: requested.dvrControlsEnabled,
    ),
    'reduceMotion' => current.copyWith(reduceMotion: requested.reduceMotion),
    'largeFocusIndicators' => current.copyWith(
      largeFocusIndicators: requested.largeFocusIndicators,
    ),
    'profilePickerOnStartup' => current.copyWith(
      profilePickerOnStartup: requested.profilePickerOnStartup,
    ),
    'diagnosticsEnabled' => current.copyWith(
      diagnosticsEnabled: requested.diagnosticsEnabled,
    ),
    _ => throw ArgumentError.value(keyName, 'keyName'),
  };

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
    final size = MediaQuery.sizeOf(context);
    final scale =
        LineupLayout.scaleFor(size) *
        (size.height / 1080).clamp(0.82, 1.0).toDouble();
    final theme = Theme.of(context);
    final roles = LineupTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: roles.primaryText,
              fontSize: 32 * scale,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
        ),
        SizedBox(height: 6 * scale),
        Text(
          description,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: roles.secondaryText,
            fontSize: 16 * scale,
            height: 1.5,
          ),
        ),
        SizedBox(height: 32 * scale),
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
      final size = MediaQuery.sizeOf(context);
      final scale =
          LineupLayout.scaleFor(size) *
          (size.height / 1080).clamp(0.82, 1.0).toDouble();
      final reflow =
          constraints.maxWidth < 600 * scale ||
          MediaQuery.textScalerOf(context).scale(1) >= 2;
      final theme = Theme.of(context);
      final roles = LineupTheme.of(context);
      final description = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefaultTextStyle.merge(
            style: theme.textTheme.titleMedium?.copyWith(
              color: roles.primaryText,
              fontSize: 20 * scale,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
            child: label,
          ),
          SizedBox(height: 6 * scale),
          DefaultTextStyle.merge(
            style: theme.textTheme.bodyLarge?.copyWith(
              color: roles.secondaryText,
              fontSize: 16 * scale,
              height: 1.5,
            ),
            child: helper,
          ),
        ],
      );
      return Container(
        constraints: BoxConstraints(minHeight: 132 * scale),
        padding: EdgeInsets.fromLTRB(
          0,
          (first ? 16 : 28) * scale,
          0,
          28 * scale,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: roles.subtleBorder)),
        ),
        child: reflow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  description,
                  SizedBox(height: 16 * scale),
                  Align(alignment: Alignment.centerLeft, child: control),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: description),
                  SizedBox(width: 32 * scale),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * 0.45,
                    ),
                    child: control,
                  ),
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
          final size = MediaQuery.sizeOf(context);
          final scale =
              LineupLayout.scaleFor(size) *
              (size.height / 1080).clamp(0.82, 1.0).toDouble();
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final controlScale = math.max(1.0, scale * math.max(1.0, textScale));
          return SizedBox(
            width: 60 * controlScale,
            height: 48 * controlScale,
            child: Center(
              child: Transform.scale(
                scale: controlScale,
                child: Switch(value: value, onChanged: onChanged),
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
    this.first = false,
  });
  final String label;
  final String description;
  final T value;
  final List<T> values;
  final String Function(T) display;
  final ValueChanged<T>? changed;
  final bool first;
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final scale =
        LineupLayout.scaleFor(size) *
        (size.height / 1080).clamp(0.82, 1.0).toDouble();
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final controlScale = math.max(1.0, scale * math.max(1.0, textScale));
    final theme = Theme.of(context);
    return MergeSemantics(
      child: _SettingsRow(
        label: Text(label),
        helper: Text(description),
        control: SizedBox(
          width: 248 * controlScale,
          child: DropdownButtonFormField<T>(
            key: ValueKey(value),
            initialValue: value,
            isExpanded: true,
            itemHeight: 48 * controlScale,
            icon: Icon(Icons.arrow_drop_down, size: 20 * controlScale),
            style: theme.textTheme.bodyLarge?.copyWith(fontSize: 16 * scale),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14 * controlScale,
                vertical: 11 * controlScale,
              ),
            ),
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
        ),
        first: first,
      ),
    );
  }
}
