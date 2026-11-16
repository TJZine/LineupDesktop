import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../guide/guide_controller.dart';
import '../licenses/licenses_view.dart';
import '../guide/guide_playback_placeholder.dart';
import '../guide/guide_view.dart';
import '../playback/native_player.dart';
import '../playback/player_coordinator.dart';
import '../playback/player_view.dart';
import '../platform/device_profile.dart';
import '../ui/app_ui.dart';
import '../ui/channel_identity.dart';
import '../ui/app_theme.dart';
import '../ui/lineup_canvas.dart';
import 'channel_setup_view.dart';
import 'channels_view.dart';
import 'diagnostics_view.dart';
import 'lineup_controller.dart';
import 'lineup_restore_view.dart';
import 'navigation_shortcuts.dart';
import 'settings_view.dart';
import 'onboarding_view.dart';

class LineupShell extends StatefulWidget {
  const LineupShell({
    required this.player,
    required this.controller,
    this.initialMediaPath,
    this.guideClock,
    required this.profile,
    super.key,
  });
  final NativePlayer player;
  final LineupController controller;
  final String? initialMediaPath;
  final DateTime Function()? guideClock;
  final DeviceProfile profile;
  @override
  State<LineupShell> createState() => _LineupShellState();
}

class _LineupShellState extends State<LineupShell> {
  late ShellDestination _destination = widget.initialMediaPath == null
      ? ShellDestination.guide
      : ShellDestination.player;
  ShellDestination? _settingsReturnDestination;
  bool _desktopDiagnosticsFromPlayer = false;
  bool get _diagnosticsFromPlayer => widget.profile.isTv
      ? switch (_tvLocation) {
          _TvDiagnostics(origin: _TvPlayer()) => true,
          _ => false,
        }
      : _desktopDiagnosticsFromPlayer;
  late final GuideController _guide;
  late final PlayerCoordinator _player;
  final _playerKey = GlobalKey<PlayerViewState>();
  final _onboardingKey = GlobalKey<UpstreamOnboardingViewState>();
  GlobalKey<UpstreamChannelSetupViewState> _setupKey =
      GlobalKey<UpstreamChannelSetupViewState>();
  bool _retainSetup = false;
  (String?, String?, String?, int)? _suspendedSetupScope;
  late _TvLocation _tvLocation = widget.initialMediaPath == null
      ? const _TvHome()
      : const _TvPlayer();
  int _routeIntent = 0;

  (String?, String?, String?, int) get _scopeStamp => (
    widget.controller.account?.id,
    widget.controller.profile?.id,
    widget.controller.server?.id,
    widget.controller.contentGeneration,
  );
  final _channelsKey = GlobalKey<ChannelsViewState>();
  final _guideFocus = FocusNode(debugLabel: 'Guide');
  final _guideSetupFocus = FocusNode(debugLabel: 'Guide set up channels');
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
  final _licensesKey = GlobalKey<LicensesViewState>();
  final _licensesMenuFocus = FocusNode(debugLabel: 'Licenses Lineup menu');
  final _openLicensesFocus = FocusNode(debugLabel: 'Open Licenses');
  bool _licensesOpen = false;
  bool _onboardingSupport = false;
  bool _selectionPending = false;
  bool _keyboardInput = false;
  ({Object id, Rect anchor, FocusNode invokerFocus})? _appMenu;
  static const _appMenuChannel = MethodChannel('lineup/app_menu');
  bool _onboardingFromAccount = false;
  SettingsCategory _settingsCategory = SettingsCategory.appearance;
  Object? _lastPlayerFacts;
  late SetupStage _lastStage;
  @override
  void initState() {
    super.initState();
    _lastStage = widget.controller.stage;
    _retainSetup =
        _lastStage == SetupStage.channelSetup &&
        !widget.controller.restoringSavedLineup;
    HardwareKeyboard.instance.addHandler(_trackKeyboardInput);
    FocusManager.instance.addEarlyKeyEventHandler(_handleTvMenuKey);
    if (defaultTargetPlatform != TargetPlatform.android) {
      _appMenuChannel.setMethodCallHandler(_handleAppMenuCall);
    }
    _guide = GuideController(
      lineup: widget.controller,
      clock: widget.guideClock,
    );
    _player = PlayerCoordinator(
      player: widget.player,
      lineup: widget.controller,
      guide: _guide,
      clock: widget.guideClock,
      suspendInBackground: widget.profile.isTv,
    );
    _player.setPlayerDestinationVisible(
      _destination == ShellDestination.player,
    );
    final initialMediaPath = widget.initialMediaPath;
    if (initialMediaPath != null) {
      unawaited(_player.loadInitialMedia(_mediaUri(initialMediaPath)));
    }
    _lastPlayerFacts = _shellPlayerFacts;
    _player.addListener(_playerChanged);
    if (_destination == ShellDestination.guide) _player.showFullGuide();
    widget.controller.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreRouteFocus());
  }

  Object get _shellPlayerFacts => (
    _player.hasPlaybackIntent,
    _player.tuning,
    _player.authorizationTransitionPending,
    _player.authorizationStopPending,
    _player.authorizationTransitionError,
    _player.error,
    _player.failureCause,
    _player.failedChannelId,
    _player.canRetry,
    _player.status.state,
    _player.status.message,
    _player.currentChannel?.id,
    _player.currentProgram?.scheduled.item.title,
    _destination == ShellDestination.diagnostics ? _player.telemetry : null,
    _destination == ShellDestination.diagnostics ? _player.displayReport : null,
  );

  void _playerChanged() {
    final facts = _shellPlayerFacts;
    if (_lastPlayerFacts == facts) return;
    _lastPlayerFacts = facts;
    if (mounted) setState(() {});
  }

  void _changed() {
    if (!mounted) return;
    final stage = widget.controller.stage;
    final returnedToApp =
        _lastStage != SetupStage.ready && stage == SetupStage.ready;
    if (widget.profile.isTv) {
      if (_lastStage != stage) _routeIntent++;
      if (_lastStage == SetupStage.channelSetup &&
          (stage == SetupStage.servers || stage == SetupStage.profiles) &&
          _setupKey.currentState != null) {
        _suspendedSetupScope = _scopeStamp;
      }
      if (_suspendedSetupScope case final stamp?) {
        if (stamp != _scopeStamp ||
            (stage != SetupStage.channelSetup &&
                stage != SetupStage.servers &&
                stage != SetupStage.profiles)) {
          // Retire before a successful scope publication can bind an old draft.
          _retireSetup();
          _tvLocation = const _TvHome();
          _destination = ShellDestination.guide;
        } else if (stage == SetupStage.channelSetup) {
          _suspendedSetupScope = null;
          _restoreResumedSetupFocus();
        }
      }
      if (stage == SetupStage.channelSetup &&
          !widget.controller.restoringSavedLineup) {
        _retainSetup = true;
      }
      if (stage == SetupStage.ready || stage == SetupStage.welcome) {
        _retireSetup();
      }
      if (stage == SetupStage.welcome) {
        _tvLocation = const _TvHome();
        _destination = ShellDestination.guide;
      }
    }
    _lastStage = stage;
    if (returnedToApp && _onboardingSupport) {
      _onboardingSupport = false;
      _destination = ShellDestination.settings;
      if (widget.profile.isTv) {
        _tvLocation = _tvSettings;
      } else {
        _settingsReturnDestination ??= ShellDestination.guide;
      }
    }
    if (stage == SetupStage.welcome) _onboardingFromAccount = false;
    if (_appMenu != null &&
        stage != SetupStage.ready &&
        !_onboardingMenuAvailable) {
      _appMenu = null;
    }
    setState(() {});
    if (returnedToApp) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreRouteFocus());
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_trackKeyboardInput);
    FocusManager.instance.removeEarlyKeyEventHandler(_handleTvMenuKey);
    if (defaultTargetPlatform != TargetPlatform.android) {
      _appMenuChannel.setMethodCallHandler(null);
    }
    widget.controller.removeListener(_changed);
    _player.removeListener(_playerChanged);
    _player.dispose();
    _guide.dispose();
    _guideFocus.dispose();
    _guideSetupFocus.dispose();
    _channelsFocus.dispose();
    _settingsFocus.dispose();
    _diagnosticsFocus.dispose();
    _playerFocus.dispose();
    _channelsMenuFocus.dispose();
    _settingsMenuFocus.dispose();
    _diagnosticsMenuFocus.dispose();
    _appMenuScope.dispose();
    _licensesMenuFocus.dispose();
    _openLicensesFocus.dispose();
    super.dispose();
  }

  bool get _setupVisible =>
      widget.controller.stage == SetupStage.channelSetup &&
      !widget.controller.restoringSavedLineup &&
      !_onboardingSupport;

  void _restoreResumedSetupFocus() {
    final key = _setupKey;
    final state = key.currentState;
    // A synchronous picker round trip that never hid Setup needs no recovery.
    if (state == null ||
        state.context.findAncestorWidgetOfExactType<Offstage>()?.offstage !=
            true) {
      return;
    }
    final scope = _scopeStamp;
    final intent = _routeIntent;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_retainSetup ||
          !_setupVisible ||
          _appMenu != null ||
          _licensesOpen ||
          intent != _routeIntent ||
          scope != _scopeStamp ||
          key != _setupKey ||
          !identical(key.currentState, state)) {
        return;
      }
      state.restoreNavigationFocus();
    });
  }

  void _retireSetup() {
    if (_retainSetup) _setupKey = GlobalKey<UpstreamChannelSetupViewState>();
    _retainSetup = false;
    _suspendedSetupScope = null;
  }

  _TvWatch get _tvWatch => _tvLocation.watch;
  _TvSettings get _tvSettings => switch (_tvLocation) {
    final _TvSettings location => location,
    _TvDiagnostics(:final origin) =>
      origin is _TvSettings ? origin : _TvSettings(origin),
    final _TvChannels location => _TvSettings(location),
    final _TvWatch location => _TvSettings(location),
  };

  _TvLocation _tvOpen(ShellDestination destination) => switch (destination) {
    ShellDestination.guide =>
      _hasPlaybackSurface ? const _TvBrowse() : const _TvHome(),
    ShellDestination.player => const _TvPlayer(),
    ShellDestination.channels => _TvChannels(_tvWatch),
    ShellDestination.settings => _tvSettings,
    ShellDestination.diagnostics => switch (_tvLocation) {
      final _TvDiagnostics location => location,
      _ => _TvDiagnostics(_tvSettings),
    },
  };

  _TvLocation _validTvLocation(_TvLocation location) {
    if (_hasPlaybackSurface) return location;
    return switch (location) {
      _TvPlayer() || _TvBrowse() => const _TvHome(),
      _TvChannels(:final origin) => _TvChannels(
        _validTvLocation(origin) as _TvWatch,
      ),
      _TvSettings(:final origin) => _TvSettings(_validTvLocation(origin)),
      _TvDiagnostics(origin: final _TvSettings origin) => _TvDiagnostics(
        _validTvLocation(origin),
      ),
      _TvDiagnostics() => location,
      _TvHome() => location,
    };
  }

  bool _handleTvBack() {
    if (_appMenu != null) {
      _closeAppMenu();
      return true;
    }
    if (_licensesOpen) {
      _licensesKey.currentState?.back();
      return true;
    }
    if (_onboardingSupport) {
      setState(() => _onboardingSupport = false);
      return true;
    }
    if (_selectionPending) return true;
    final controller = widget.controller;
    if (controller.stage != SetupStage.ready) {
      if (controller.restoringSavedLineup) return !controller.canSwitchServer;
      if (controller.stage == SetupStage.channelSetup) {
        return _setupKey.currentState?.handleBack() ?? true;
      }
      return _onboardingKey.currentState?.handleBack() ?? true;
    }
    switch (_tvLocation) {
      case _TvHome():
        return false;
      case _TvPlayer():
        if (_playerKey.currentState case final state?) {
          return state.handleBack();
        }
      case _TvBrowse():
        _returnTv(const _TvPlayer());
        return true;
      case _TvChannels(:final origin):
        final state = _channelsKey.currentState;
        if (state == null) break;
        if (!state.handleBack()) _returnTv(origin);
        return true;
      case _TvSettings(:final origin):
        _returnTv(origin);
        return true;
      case _TvDiagnostics():
        _returnFromDiagnostics();
        return true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreRouteFocus());
    return true;
  }

  void _returnTv(_TvLocation location) {
    final valid = _validTvLocation(location);
    unawaited(_select(valid.destination, tvLocation: valid));
  }

  Future<void> _select(
    ShellDestination destination, {
    _TvLocation? tvLocation,
    bool diagnosticsFromPlayer = false,
    ({Object menuId, String channelId})? tunedRow,
  }) async {
    bool tunedRowIsCurrent() =>
        tunedRow == null ||
        (_appMenu?.id == tunedRow.menuId &&
            _canShowNowPlaying &&
            _player.currentChannel?.id == tunedRow.channelId);

    if (_selectionPending || !tunedRowIsCurrent()) return;
    final proposed = widget.profile.isTv
        ? tvLocation ?? _tvOpen(destination)
        : null;
    if (widget.controller.stage != SetupStage.ready &&
        !await _leaveOnboardingForRoute()) {
      return;
    }
    if (destination == ShellDestination.player && !_hasPlaybackSurface) {
      if (_appMenu != null) _closeAppMenu();
      return;
    }
    if (destination == ShellDestination.settings && _licensesOpen) {
      _closeLicenses();
    }
    if (tunedRow == null &&
        destination == _destination &&
        (proposed == null || proposed == _tvLocation) &&
        !(destination == ShellDestination.channels &&
            (_channelsKey.currentState?.studioOpen ?? false))) {
      if (_appMenu != null) _closeAppMenu();
      return;
    }
    final intent = ++_routeIntent;
    final stage = widget.controller.stage;
    final scope = _scopeStamp;
    _selectionPending = true;
    try {
      if (_destination == ShellDestination.channels &&
          !(await (_channelsKey.currentState?.requestLeave() ??
              Future.value(true)))) {
        return;
      }
      if (!mounted ||
          !tunedRowIsCurrent() ||
          ((widget.profile.isTv || tunedRow != null) &&
              (intent != _routeIntent ||
                  stage != widget.controller.stage ||
                  scope != _scopeStamp))) {
        return;
      }
      if (!widget.profile.isTv && widget.controller.stage == SetupStage.ready) {
        if (destination == ShellDestination.settings &&
            _destination != ShellDestination.settings &&
            _destination != ShellDestination.diagnostics) {
          _settingsReturnDestination = _destination;
        } else if (destination != ShellDestination.settings &&
            destination != ShellDestination.diagnostics) {
          _settingsReturnDestination = null;
        }
        if (destination == ShellDestination.diagnostics &&
            _settingsReturnDestination == null) {
          _settingsReturnDestination = _destination == ShellDestination.player
              ? ShellDestination.player
              : _destination == ShellDestination.channels
              ? ShellDestination.channels
              : ShellDestination.guide;
        }
      }
      final committed = proposed == null ? null : _validTvLocation(proposed);
      final routeDestination = committed?.destination ?? destination;
      if (tunedRow != null && routeDestination == ShellDestination.player) {
        _player.returnToPicture();
      } else if (routeDestination == ShellDestination.guide) {
        _player.showFullGuide();
      } else if (_player.overlay == PlayerOverlay.fullGuide) {
        _player.closeOverlay();
      }
      setState(() {
        _licensesOpen = false;
        if (committed != null) _tvLocation = committed;
        _destination = routeDestination;
        _desktopDiagnosticsFromPlayer =
            routeDestination == ShellDestination.diagnostics &&
            diagnosticsFromPlayer;
        _player.setPlayerDestinationVisible(
          routeDestination == ShellDestination.player,
        );
        _appMenu = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreRouteFocus());
    } finally {
      _selectionPending = false;
    }
  }

  bool get _hasPlaybackSurface =>
      _player.hasPlaybackIntent || _player.error != null;

  ShellDestination? get _settingsBackDestination => widget.profile.isTv
      ? _validTvLocation(_tvSettings.origin).destination
      : _settingsReturnDestination == ShellDestination.player &&
            !_hasPlaybackSurface
      ? ShellDestination.guide
      : _settingsReturnDestination;

  void _openPlayerDiagnostics() => unawaited(
    _select(
      ShellDestination.diagnostics,
      tvLocation: const _TvDiagnostics(_TvPlayer()),
      diagnosticsFromPlayer: true,
    ),
  );

  void _openSupportSettings() {
    _settingsCategory = SettingsCategory.support;
    if (widget.profile.isTv) {
      _returnTv(_tvSettings);
    } else {
      unawaited(_select(ShellDestination.settings));
    }
  }

  ShellDestination get _diagnosticsBackDestination {
    if (!_diagnosticsFromPlayer) return ShellDestination.settings;
    return _hasPlaybackSurface
        ? ShellDestination.player
        : ShellDestination.guide;
  }

  void _returnFromDiagnostics() {
    final destination = _diagnosticsBackDestination;
    if (destination == ShellDestination.settings) {
      _openSupportSettings();
    } else if (widget.profile.isTv) {
      _returnTv(
        destination == ShellDestination.player
            ? const _TvPlayer()
            : const _TvHome(),
      );
    } else {
      unawaited(_select(destination));
    }
  }

  void _returnFromSettings() {
    if (widget.profile.isTv) {
      _returnTv(_tvSettings.origin);
      return;
    }
    final destination = _settingsBackDestination;
    if (destination != null) unawaited(_select(destination));
  }

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
      _player.currentChannel != null &&
      _player.currentProgram != null;

  void _restoreRouteFocus() {
    if (!mounted ||
        widget.controller.stage != SetupStage.ready ||
        _appMenu != null ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    if (widget.profile.isTv && _destination == ShellDestination.channels) {
      _channelsKey.currentState?.restoreNavigationFocus();
      return;
    }
    final target = switch (_destination) {
      ShellDestination.guide =>
        widget.profile.isTv && _guideSetupFocus.parent != null
            ? _guideSetupFocus
            : _guideFocus,
      ShellDestination.channels => _channelsFocus,
      ShellDestination.settings => _settingsFocus,
      ShellDestination.diagnostics => _diagnosticsFocus,
      ShellDestination.player => _playerFocus,
    };
    if (_licensesOpen) return;
    target.requestFocus();
  }

  void _openAppMenu(BuildContext invokerContext, FocusNode invokerFocus) {
    final anchor = _menuAnchor(invokerContext);
    if (anchor != null) _showAppMenu(anchor, invokerFocus);
  }

  Rect? _menuAnchor(BuildContext? anchorContext) {
    if (anchorContext?.mounted != true) return null;
    final box = anchorContext!.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return MatrixUtils.transformRect(
      box.getTransformTo(context.findRenderObject()),
      Offset.zero & box.size,
    );
  }

  void _showAppMenu(Rect anchor, FocusNode invoker) {
    setState(
      () => _appMenu = (id: Object(), anchor: anchor, invokerFocus: invoker),
    );
  }

  KeyEventResult _handleTvMenuKey(KeyEvent event) {
    if (!widget.profile.isTv ||
        event.logicalKey != LogicalKeyboardKey.contextMenu ||
        ModalRoute.of(context)?.isCurrent != true ||
        _onboardingSupport) {
      return KeyEventResult.ignored;
    }
    final ready = widget.controller.stage == SetupStage.ready;
    if (!ready &&
        (!_onboardingMenuAvailable || widget.controller.restoringSavedLineup)) {
      return KeyEventResult.ignored;
    }
    // Guide and Player open the menu with their own overlay anchors.
    final anchorNode = !ready
        ? _settingsMenuFocus
        : switch ((_licensesOpen, _destination)) {
            (true, _) => _licensesMenuFocus,
            (_, ShellDestination.settings) => _settingsMenuFocus,
            (_, ShellDestination.diagnostics) => _diagnosticsMenuFocus,
            (_, ShellDestination.channels) => _channelsMenuFocus,
            _ => null,
          };
    Rect? anchor;
    if (anchorNode != null) {
      if (anchorNode.parent == null) return KeyEventResult.ignored;
      anchor = _menuAnchor(anchorNode.context);
      if (anchor == null) return KeyEventResult.ignored;
    }
    // A held key cannot toggle repeatedly while focus moves between surfaces.
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    _keyboardInput = true;
    if (_appMenu != null) {
      _closeAppMenu();
      return KeyEventResult.handled;
    }
    if (anchor == null || anchorNode == null) return KeyEventResult.ignored;
    _showAppMenu(anchor, FocusManager.instance.primaryFocus ?? anchorNode);
    return KeyEventResult.handled;
  }

  void _closeGuide(BuildContext invokerContext, FocusNode invokerFocus) {
    // A menu can already be opening while focus still belongs to Guide.
    if (_appMenu != null) {
      _closeAppMenu();
    } else if (_hasPlaybackSurface) {
      unawaited(_select(ShellDestination.player));
    } else {
      _openAppMenu(invokerContext, invokerFocus);
    }
  }

  Future<void> _tuneFromGuide(String channelId) async {
    final tuning = widget.profile.isTv
        ? _player.activateFromGuide(channelId)
        : _player.tune(channelId);
    await _select(ShellDestination.player);
    await tuning;
  }

  String? get _nextGuideChannelId => switch (_player.failedChannelId) {
    final failed? => _guide.successorOf(failed)?.id,
    null => null,
  };

  void _tuneNextFromGuide() {
    final next = _nextGuideChannelId;
    if (next != null) unawaited(_tuneFromGuide(next));
  }

  void _closeAppMenu({bool restoreInvoker = true}) {
    final invoker = _appMenu?.invokerFocus;
    final restoreControl =
        _destination != ShellDestination.player || _keyboardInput;
    setState(() {
      _appMenu = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Detached nodes can retain a context after their control is removed.
      if (restoreInvoker &&
          restoreControl &&
          invoker != null &&
          invoker.parent != null &&
          invoker.context?.mounted == true &&
          invoker.canRequestFocus &&
          invoker.ancestors.every((node) => node.descendantsAreFocusable)) {
        invoker.requestFocus();
      } else {
        _restoreRouteFocus();
      }
    });
  }

  /// Native application-menu commands (macOS Settings…, Command-comma).
  Future<void> _handleAppMenuCall(MethodCall call) async {
    if (call.method != 'openSettings') throw MissingPluginException();
    if (!mounted) return;
    // A dialog route above the shell owns input, as it does for the chord.
    // The in-app Lineup menu is a widget in this tree, so it does not count;
    // _select closes it.
    if (ModalRoute.of(context)?.isCurrent != true) return;
    if (widget.controller.stage != SetupStage.ready) {
      _showOnboardingSupport();
    } else {
      await _select(ShellDestination.settings);
    }
  }

  void _showOnboardingSupport() {
    setState(() {
      _appMenu = null;
      _licensesOpen = false;
      _onboardingSupport = true;
      _settingsCategory = SettingsCategory.support;
    });
  }

  void _closeLicenses() {
    setState(() {
      _licensesOpen = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _openLicensesFocus.context != null) {
        _openLicensesFocus.requestFocus();
      }
    });
  }

  Widget _settingsWithLicenses(Widget settings, {bool onboarding = false}) =>
      Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: _licensesOpen,
            child: ExcludeFocus(excluding: _licensesOpen, child: settings),
          ),
          if (_licensesOpen)
            ColoredBox(
              color: LineupTheme.of(context).deepBackground,
              child: SafeArea(
                left: DeviceProfile.of(context).isTv,
                top: DeviceProfile.of(context).isTv,
                right: DeviceProfile.of(context).isTv,
                bottom: DeviceProfile.of(context).isTv,
                child: LicensesView(
                  key: _licensesKey,
                  onBack: _closeLicenses,
                  onOpenMenu: onboarding ? null : _openAppMenu,
                  menuFocusNode: onboarding ? null : _licensesMenuFocus,
                ),
              ),
            ),
        ],
      );

  Future<void> _openAccount() async {
    _settingsCategory = SettingsCategory.account;
    await _select(ShellDestination.settings);
  }

  void _openProfilePickerFromAccount() {
    if (_selectionPending ||
        widget.controller.busy ||
        _player.authorizationTransitionPending) {
      return;
    }
    _onboardingFromAccount = true;
    widget.controller.showProfiles();
  }

  void _openServerPickerFromAccount() {
    if (_selectionPending ||
        widget.controller.busy ||
        _player.authorizationTransitionPending) {
      return;
    }
    _onboardingFromAccount = true;
    widget.controller.showServers();
  }

  Future<bool> _leaveOnboardingForRoute() async {
    final controller = widget.controller;
    if (controller.busy || _player.authorizationTransitionPending) return false;
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
    final backKey = {
      LogicalKeyboardKey.escape,
      LogicalKeyboardKey.backspace,
      LogicalKeyboardKey.goBack,
    }.contains(event.logicalKey);
    if (widget.profile.isTv && backKey) {
      final editing = FocusManager.instance.primaryFocus?.context;
      if (event.logicalKey == LogicalKeyboardKey.backspace &&
          (editing?.widget is EditableText ||
              editing?.findAncestorWidgetOfExactType<EditableText>() != null)) {
        return KeyEventResult.ignored;
      }
      if (defaultTargetPlatform == TargetPlatform.android) {
        return KeyEventResult.ignored;
      }
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      return _handleTvBack() ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        FocusManager.instance.primaryFocus?.context
                ?.findAncestorStateOfType<EditableTextState>() !=
            null) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final back =
        event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.goBack;
    if (_licensesOpen && _appMenu == null && back) {
      _licensesKey.currentState?.back();
      return KeyEventResult.handled;
    }
    if (_onboardingSupport && _appMenu == null && back) {
      setState(() => _onboardingSupport = false);
      return KeyEventResult.handled;
    }
    if (_destination == ShellDestination.diagnostics &&
        _appMenu == null &&
        (event.logicalKey == LogicalKeyboardKey.escape ||
            event.logicalKey == LogicalKeyboardKey.backspace ||
            event.logicalKey == LogicalKeyboardKey.goBack)) {
      _returnFromDiagnostics();
      return KeyEventResult.handled;
    }
    if (_destination == ShellDestination.settings &&
        _settingsReturnDestination != null &&
        _appMenu == null &&
        (event.logicalKey == LogicalKeyboardKey.escape ||
            event.logicalKey == LogicalKeyboardKey.backspace ||
            event.logicalKey == LogicalKeyboardKey.goBack)) {
      _returnFromSettings();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.f3 &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed) {
      unawaited(_select(ShellDestination.settings));
      return KeyEventResult.handled;
    }
    final destination = navigationShortcutDestination(event.logicalKey);
    if (destination == null) return KeyEventResult.ignored;
    if (destination == ShellDestination.settings &&
        widget.controller.stage != SetupStage.ready) {
      _showOnboardingSupport();
      return KeyEventResult.handled;
    }
    unawaited(_select(destination));
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
    await _select(
      widget.profile.isTv ? ShellDestination.guide : ShellDestination.channels,
      tvLocation: widget.profile.isTv ? const _TvHome() : null,
    );
  }

  Future<void> _completeSetupAndAdd() async {
    widget.controller.completeChannelSetup();
    _onboardingFromAccount = false;
    await _select(
      ShellDestination.channels,
      tvLocation: widget.profile.isTv ? const _TvChannels(_TvHome()) : null,
    );
    final intent = _routeIntent;
    final scope = _scopeStamp;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.controller.stage != SetupStage.ready ||
          _destination != ShellDestination.channels ||
          (widget.profile.isTv &&
              (intent != _routeIntent || scope != _scopeStamp))) {
        return;
      }
      _channelsKey.currentState?.openNew();
    });
  }

  bool _setupActionsBlocked() => !_setupVisible;

  bool _authorizationTransitionPending() =>
      _player.authorizationTransitionPending;

  void _backFromFirstLibraries() {
    final controller = widget.controller;
    if (_player.authorizationTransitionPending ||
        controller.busy ||
        !controller.canSwitchServer) {
      return;
    }
    switch (controller.firstLibrariesOrigin) {
      case FirstLibrariesOrigin.profiles:
        unawaited(controller.backToFirstRunProfiles());
      case FirstLibrariesOrigin.signIn:
        unawaited(_logout());
      case null:
        break;
    }
  }

  Future<void> _requestLogout() async {
    if (_player.authorizationTransitionPending) return;
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
    if (_player.authorizationTransitionPending) return;
    final channels = _channelsKey.currentState;
    if (_destination == ShellDestination.channels &&
        channels != null &&
        !await channels.requestLeave()) {
      return;
    }
    if (await _player.logout() || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: _player,
        builder: (context, _) => AlertDialog(
          title: const Text('Could not sign out'),
          content: Semantics(
            liveRegion: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _player.authorizationTransitionPending
                      ? 'Stopping playback…'
                      : _player.authorizationTransitionError ??
                            widget.controller.error ??
                            'Sign out did not complete.',
                ),
                if (!_player.authorizationTransitionPending &&
                    _player.authorizationTransitionError != null)
                  const Text('You are still signed in.'),
                if (widget.controller.profileCredentialRecoveryNotice
                    case final notice?) ...[
                  const SizedBox(height: 12),
                  Text(notice),
                ],
              ],
            ),
          ),
          actions: [
            if (_player.authorizationTransitionError != null ||
                _player.authorizationTransitionPending)
              TextButton(
                onPressed: _player.authorizationTransitionPending
                    ? null
                    : () async {
                        await _player.retry();
                        if (context.mounted &&
                            _player.authorizationTransitionError == null) {
                          Navigator.pop(context);
                        }
                      },
                child: const Text('Retry stopping playback'),
              ),
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || !widget.profile.isTv || !_setupVisible) return;
    final setup = _setupKey.currentState;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _setupVisible &&
          identical(setup, _setupKey.currentState)) {
        setup?.restoreNavigationFocus();
      }
    });
  }

  Widget _immersiveAppMenu() {
    final menu = _appMenu;
    if (menu == null) return const SizedBox.shrink();
    final anchor = menu.anchor;
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
          delegate: _AnchoredMenuLayout(
            anchor,
            insets: DeviceProfile.of(context).isTv
                ? LineupCanvas.contentInsets(
                    context,
                    minimum: const EdgeInsets.all(16),
                  )
                : const EdgeInsets.all(16),
          ),
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
                      if (_canShowNowPlaying)
                        _nowPlayingMenuRow(menu.id, detailStyle),
                      _menuDestination(
                        destination: ShellDestination.guide,
                        label: 'Guide',
                        autofocus: true,
                      ),
                      _menuDestination(
                        destination: ShellDestination.channels,
                        label: 'Manage channels',
                      ),
                      _menuDestination(
                        destination: ShellDestination.settings,
                        label: 'Settings',
                      ),
                      Divider(height: 24, thickness: 1.0),
                      Semantics(
                        label: 'Account',
                        child: LineupNavigationRow(
                          key: const Key('app-menu-account'),
                          selected:
                              _destination == ShellDestination.settings &&
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
                                    _menuDetail(serverName, detailStyle),
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

  Widget _nowPlayingMenuRow(Object menuId, TextStyle? detailStyle) {
    final program = _player.currentProgram!.scheduled.item.title;
    final channel = _player.currentChannel!;
    final tag = ChannelIdentity.libraryTagFor(
      channel,
      widget.controller.channels,
    );
    final selected = _destination == ShellDestination.player;
    return LineupNavigationRow(
      key: const Key('app-menu-now-playing'),
      selected: selected,
      onPressed: () => unawaited(
        _select(
          ShellDestination.player,
          tunedRow: (menuId: menuId, channelId: channel.id),
        ),
      ),
      child: Semantics(
        label:
            'Now Playing, ${ChannelIdentity.label(channel, libraryTag: tag)}, $program'
            '${selected ? ', current page' : ''}',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ChannelIdentity(
              channel: channel,
              libraryTag: tag,
              showSemantics: false,
            ),
            _menuDetail(program, detailStyle, maxLines: 1),
          ],
        ),
      ),
    );
  }

  Widget _menuDetail(String text, TextStyle? style, {int? maxLines}) => Builder(
    builder: (context) => Text(
      text,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      style: DeviceProfile.of(context).isTv
          ? style?.copyWith(color: LineupTheme.of(context).secondaryText)
          : style,
    ),
  );

  Widget _menuDestination({
    required ShellDestination destination,
    required String label,
    bool autofocus = false,
  }) {
    final selected = _destination == destination;
    void select() => unawaited(_select(destination));
    return Semantics(
      excludeSemantics: true,
      selected: selected,
      button: true,
      enabled: true,
      label: selected ? '$label, current page' : label,
      onTap: select,
      child: LineupNavigationRow(
        selected: selected,
        autofocus: autofocus,
        onPressed: select,
        child: Text(label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget child = _buildShell(context);
    if (widget.profile.isTv) {
      final visibleSetup = _setupVisible;
      child = Stack(
        fit: StackFit.expand,
        children: [
          if (_retainSetup)
            Offstage(
              offstage: !visibleSetup,
              child: ExcludeFocus(
                excluding: !visibleSetup,
                child: ExcludeSemantics(
                  excluding: !visibleSetup,
                  child: TickerMode(
                    enabled: visibleSetup,
                    child: UpstreamChannelSetupView(
                      key: _setupKey,
                      controller: widget.controller,
                      onRequestLogout: _requestLogout,
                      onFirstLibrariesBack: _backFromFirstLibraries,
                      setupActionsBlocked: _setupActionsBlocked,
                      authorizationTransitionPending:
                          _authorizationTransitionPending,
                      onViewLineup: _completeSetup,
                      onAddCustomChannel: _completeSetupAndAdd,
                    ),
                  ),
                ),
              ),
            ),
          if (!visibleSetup) child,
        ],
      );
    }
    final rooted = defaultTargetPlatform == TargetPlatform.android
        ? AndroidBackScope(
            onUnhandledBack: widget.profile.isTv ? _handleTvBack : null,
            child: child,
          )
        : child;
    return DeviceProfileScope(profile: widget.profile, child: rooted);
  }

  Widget _buildShell(BuildContext context) {
    _lastPlayerFacts = _shellPlayerFacts;
    final controller = widget.controller;
    if (controller.stage != SetupStage.ready) {
      if (_onboardingSupport) {
        return _withGlobalKeys(
          Scaffold(
            body: SafeArea(
              left: !DeviceProfile.of(context).isTv,
              top: !DeviceProfile.of(context).isTv,
              right: !DeviceProfile.of(context).isTv,
              bottom: !DeviceProfile.of(context).isTv,
              child: _settingsWithLicenses(
                SettingsView(
                  controller: controller,
                  category: SettingsCategory.support,
                  onCategoryChanged: (_) {},
                  supportOnly: true,
                  backLabel: '‹ Back to setup',
                  onBack: () => setState(() => _onboardingSupport = false),
                  openLicensesFocus: _openLicensesFocus,
                  onOpenLicenses: () => setState(() => _licensesOpen = true),
                ),
                onboarding: true,
              ),
            ),
          ),
        );
      }
      final onboardingMenuAvailable = _onboardingMenuAvailable;
      final onboarding = controller.restoringSavedLineup
          ? LineupRestoreView(controller: controller)
          : controller.stage == SetupStage.channelSetup
          ? widget.profile.isTv
                ? const SizedBox.shrink()
                : UpstreamChannelSetupView(
                    key: _setupKey,
                    controller: controller,
                    onRequestLogout: _requestLogout,
                    onFirstLibrariesBack: _backFromFirstLibraries,
                    setupActionsBlocked: _setupActionsBlocked,
                    authorizationTransitionPending:
                        _authorizationTransitionPending,
                    onViewLineup: _completeSetup,
                    onAddCustomChannel: _completeSetupAndAdd,
                  )
          : UpstreamOnboardingView(
              key: _onboardingKey,
              controller: controller,
              onLogout: _logout,
              onSelectProfile: _player.selectProfile,
              onSelectServer: _player.selectServer,
              authorizationTransitionPending:
                  _player.authorizationTransitionPending,
              authorizationStopPending: _player.authorizationStopPending,
              authorizationTransitionError: () =>
                  _player.authorizationTransitionError,
              onRequestLogout: _requestLogout,
              accountOrigin: _onboardingFromAccount,
              onOpenSettings:
                  (defaultTargetPlatform == TargetPlatform.macOS ||
                      DeviceProfile.of(context).isTv)
                  ? _showOnboardingSupport
                  : null,
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
                excluding: _appMenu != null,
                child: TooltipVisibility(
                  visible: TooltipVisibility.of(context) && _appMenu == null,
                  child: ExcludeFocus(
                    excluding: _appMenu != null,
                    child: onboarding,
                  ),
                ),
              ),
              if (_appMenu != null) _immersiveAppMenu(),
            ],
          ),
        ),
      );
    }
    final playerView = PlayerView(
      key: _playerKey,
      controller: _player,
      focusNode: _playerFocus,
      openGuide: () => unawaited(_select(ShellDestination.guide)),
      onBackToGuide: widget.profile.isTv
          ? () => _returnTv(const _TvHome())
          : null,
      openMenu: _openAppMenu,
      onOpenDiagnostics: _openPlayerDiagnostics,
    );
    final hasPlaybackSurface = _hasPlaybackSurface;
    final guidePlaybackUnavailable =
        _player.status.state == PlayerState.unsupported ||
        _player.error != null;
    final failureCause = _player.failureCause;
    final guideHasPicture = hasPlaybackSurface && !guidePlaybackUnavailable;
    final guideView = GuideView(
      controller: _guide,
      watchingChannelId: _player.watchingChannelId,
      focusNode: _guideFocus,
      setupFocusNode: _guideSetupFocus,
      onClose: _closeGuide,
      onBack: widget.profile.isTv ? _handleTvBack : null,
      onOpenMenu: _openAppMenu,
      pictureInPicture: guideHasPicture
          ? PlayerSurface(controller: _player, showErrors: true)
          : ListenableBuilder(
              listenable: _guide,
              builder: (context, _) => GuidePlaybackPlaceholder(
                unavailable: guidePlaybackUnavailable,
                reduceMotion: controller.settings.reduceMotion,
                failureCause: failureCause,
                message: guidePlaybackUnavailable && failureCause == null
                    ? _player.error ?? _player.status.message
                    : null,
                onRetry: _player.canRetry ? _player.retry : null,
                onNextChannel: _nextGuideChannelId == null
                    ? null
                    : _tuneNextFromGuide,
              ),
            ),
      onOpenPlayer: guideHasPicture
          ? () => unawaited(_select(ShellDestination.player))
          : null,
      onTune: _tuneFromGuide,
      onSetUpChannels: () => unawaited(controller.enterChannelSetup()),
      showIdleArtwork:
          _player.status.state == PlayerState.idle &&
          !hasPlaybackSurface &&
          !guidePlaybackUnavailable,
    );
    final settingsView = SettingsView(
      controller: controller,
      subtitleAppearance: _player.subtitleAppearance,
      focusNode: _settingsFocus,
      menuFocusNode: _settingsMenuFocus,
      onOpenMenu: _openAppMenu,
      backLabel:
          '‹ Back to ${switch (_settingsBackDestination) {
            ShellDestination.player => "Player",
            ShellDestination.channels => "Channels",
            _ => "Guide",
          }}',
      onBack: _settingsBackDestination == null ? null : _returnFromSettings,
      category: _settingsCategory,
      onCategoryChanged: (category) => setState(() {
        _settingsCategory = category;
      }),
      authorizationTransitionPending: _player.authorizationTransitionPending,
      onSwitchProfile: _openProfilePickerFromAccount,
      onSwitchServer: _openServerPickerFromAccount,
      onSignOut: _requestLogout,
      onOpenDiagnostics: () => unawaited(_select(ShellDestination.diagnostics)),
      openLicensesFocus: _openLicensesFocus,
      onOpenLicenses: () => setState(() => _licensesOpen = true),
    );
    final routeConsumesSafeArea =
        !(DeviceProfile.of(context).isTv &&
            (_destination == ShellDestination.player ||
                _destination == ShellDestination.settings));
    final routeView = switch (_destination) {
      ShellDestination.guide => guideView,
      ShellDestination.channels => ChannelsView(
        key: _channelsKey,
        controller: controller,
        player: _player,
        clock: widget.guideClock,
        focusNode: _channelsFocus,
        menuFocusNode: _channelsMenuFocus,
        onOpenMenu: _openAppMenu,
        onOpenPlayer: () => unawaited(_select(ShellDestination.player)),
      ),
      ShellDestination.settings => Stack(
        fit: StackFit.expand,
        children: [
          if (hasPlaybackSurface)
            PlayerSurface(controller: _player, showSubtitles: false),
          _settingsWithLicenses(settingsView),
        ],
      ),
      ShellDestination.diagnostics => DiagnosticsView(
        controller: controller,
        playback: _player.diagnosticPlaybackSnapshot,
        onRecordingSettings: _openSupportSettings,
        focusNode: _diagnosticsFocus,
        menuFocusNode: _diagnosticsMenuFocus,
        onOpenMenu: _openAppMenu,
        onBack: _returnFromDiagnostics,
        backLabel: switch (_diagnosticsBackDestination) {
          ShellDestination.player => '‹ Back to Player',
          ShellDestination.guide => '‹ Back to Guide',
          _ => '‹ Settings · Support',
        },
      ),
      ShellDestination.player => playerView,
    };
    final roles = LineupTheme.of(context);
    final routeColor =
        _destination == ShellDestination.settings ||
            _destination == ShellDestination.player ||
            (_destination == ShellDestination.guide && hasPlaybackSurface)
        ? Colors.transparent
        : Theme.of(context).scaffoldBackgroundColor;
    final insets = MediaQuery.paddingOf(context);
    final safeRoute = SafeArea(
      left: routeConsumesSafeArea,
      top: routeConsumesSafeArea,
      right: routeConsumesSafeArea,
      bottom: routeConsumesSafeArea,
      child: routeView,
    );
    final paintedRoute = DeviceProfile.of(context).isTv
        ? ColoredBox(
            color: routeColor,
            // Paint only the margin around the Guide's transparent native PiP
            // aperture. Filling the whole route would cover the video.
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: _destination == ShellDestination.guide
                    ? Border(
                        left: BorderSide(
                          color: roles.deepBackground,
                          width: insets.left,
                        ),
                        top: BorderSide(
                          color: roles.deepBackground,
                          width: insets.top,
                        ),
                        right: BorderSide(
                          color: roles.deepBackground,
                          width: insets.right,
                        ),
                        bottom: BorderSide(
                          color: roles.deepBackground,
                          width: insets.bottom,
                        ),
                      )
                    : null,
              ),
              child: safeRoute,
            ),
          )
        : SafeArea(
            child: ColoredBox(color: routeColor, child: routeView),
          );
    return _withGlobalKeys(
      Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(
              key: const Key('immersive-route-semantics'),
              excluding: _appMenu != null,
              // A live tooltip overlay can outlast its excluded origin and
              // send unreachable node updates to Flutter's desktop AX bridge.
              child: TooltipVisibility(
                visible: TooltipVisibility.of(context) && _appMenu == null,
                child: ExcludeFocus(
                  excluding: _appMenu != null,
                  child: paintedRoute,
                ),
              ),
            ),
            if (_appMenu != null) _immersiveAppMenu(),
          ],
        ),
      ),
    );
  }
}

// Finite TV parents: only watch locations may sit beneath Channels; Settings
// may additionally retain Channels. Returning consumes this parent, never pushes.
sealed class _TvLocation {
  const _TvLocation();
  ShellDestination get destination;
  _TvWatch get watch;
}

sealed class _TvWatch extends _TvLocation {
  const _TvWatch();
  @override
  _TvWatch get watch => this;
}

final class _TvHome extends _TvWatch {
  const _TvHome();
  @override
  ShellDestination get destination => ShellDestination.guide;
}

final class _TvPlayer extends _TvWatch {
  const _TvPlayer();
  @override
  ShellDestination get destination => ShellDestination.player;
}

final class _TvBrowse extends _TvWatch {
  const _TvBrowse();
  @override
  ShellDestination get destination => ShellDestination.guide;
}

final class _TvChannels extends _TvLocation {
  const _TvChannels(this.origin);
  final _TvWatch origin;
  @override
  ShellDestination get destination => ShellDestination.channels;
  @override
  _TvWatch get watch => origin;
}

final class _TvSettings extends _TvLocation {
  const _TvSettings(this.origin)
    : assert(origin is _TvWatch || origin is _TvChannels);
  final _TvLocation origin;
  @override
  ShellDestination get destination => ShellDestination.settings;
  @override
  _TvWatch get watch => origin.watch;
}

final class _TvDiagnostics extends _TvLocation {
  const _TvDiagnostics(this.origin)
    : assert(origin is _TvSettings || origin is _TvPlayer);
  final _TvLocation origin;
  @override
  ShellDestination get destination => ShellDestination.diagnostics;
  @override
  _TvWatch get watch => origin.watch;
}

class _AnchoredMenuLayout extends SingleChildLayoutDelegate {
  const _AnchoredMenuLayout(this.anchor, {required this.insets});

  final Rect anchor;
  final EdgeInsets insets;

  double get _gap => 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: (constraints.maxWidth - insets.horizontal).clamp(0.0, 320),
        maxHeight: (constraints.maxHeight - insets.vertical).clamp(
          0.0,
          double.infinity,
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final horizontalMargin = math.min(insets.left, size.width / 2);
    final leftLimit =
        size.width - childSize.width - math.min(insets.right, size.width / 2);
    final left = (anchor.right - childSize.width).clamp(
      math.min(horizontalMargin, leftLimit),
      math.max(horizontalMargin, leftLimit),
    );
    final verticalMargin = math.min(insets.top, size.height / 2);
    final bottomMargin = math.min(insets.bottom, size.height / 2);
    final bottomLimit = size.height - childSize.height - bottomMargin;
    final below = anchor.bottom + _gap;
    final above = anchor.top - childSize.height - _gap;
    final top = below + childSize.height <= size.height - bottomMargin
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
      oldDelegate.anchor != anchor || oldDelegate.insets != insets;
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
