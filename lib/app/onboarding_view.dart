import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../plex/plex_models.dart';
import '../ui/app_theme.dart';
import '../ui/app_ui.dart';
import 'lineup_controller.dart';
import 'plex_link_launcher.dart';

class UpstreamOnboardingView extends StatefulWidget {
  const UpstreamOnboardingView({
    required this.controller,
    required this.onLogout,
    this.onRequestLogout,
    this.openBrowser = openPlexLink,
    this.accountOrigin = false,
    this.onOpenMenu,
    this.menuFocusNode,
    super.key,
  });

  final LineupController controller;
  final Future<void> Function() onLogout;
  final Future<void> Function()? onRequestLogout;
  final Future<void> Function() openBrowser;
  final bool accountOrigin;
  final LineupMenuCallback? onOpenMenu;
  final FocusNode? menuFocusNode;

  @override
  State<UpstreamOnboardingView> createState() => _UpstreamOnboardingViewState();
}

class _UpstreamOnboardingViewState extends State<UpstreamOnboardingView> {
  Timer? _clock;
  final _navigationFocus = FocusNode(debugLabel: 'Onboarding navigation');
  final _linkActionFocus = FocusNode(debugLabel: 'Retry secure cancellation');
  final _profileCancelFocus = FocusNode(debugLabel: 'Cancel profile selection');
  final _profileReturnFocus = FocusNode(debugLabel: 'Return to profiles');
  late bool _linkingStopped;
  late bool _busy;
  int? _browserPinId;
  bool get _openingBrowser =>
      _browserPinId != null && _browserPinId == widget.controller.activePin?.id;
  String? _connectingServerId;
  String? _failedServerId;
  String? _serverError;
  int _serverAttempt = 0;
  PlexHomeUser? _pinUser;
  bool _pulse = true;

  @override
  void initState() {
    super.initState();
    _linkingStopped = _isLinkingStopped(widget.controller);
    _busy = widget.controller.busy;
    widget.controller.addListener(_controllerChanged);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.controller.stage == SetupStage.linking) {
        setState(() => _pulse = !_pulse);
      }
    });
  }

  @override
  void didUpdateWidget(UpstreamOnboardingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_controllerChanged);
    _linkingStopped = _isLinkingStopped(widget.controller);
    _busy = widget.controller.busy;
    widget.controller.addListener(_controllerChanged);
  }

  void _controllerChanged() {
    if (!mounted) return;
    final controller = widget.controller;
    final nextBusy = controller.busy;
    final nextLinkingStopped = _isLinkingStopped(controller);
    final retryNeedsFocus = !_linkingStopped && nextLinkingStopped;
    final cancelNeedsFocus =
        !_busy &&
        nextBusy &&
        _pinUser == null &&
        controller.stage == SetupStage.profiles &&
        controller.profileSelectionCanCancel;
    setState(() {
      _linkingStopped = nextLinkingStopped;
      _busy = nextBusy;
    });
    final target = retryNeedsFocus
        ? _linkActionFocus
        : cancelNeedsFocus
        ? _profileCancelFocus
        : null;
    if (target != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && target.canRequestFocus) target.requestFocus();
      });
    }
  }

  static bool _isLinkingStopped(LineupController controller) =>
      controller.stage == SetupStage.linking &&
      controller.error != null &&
      (controller.activePin == null || controller.secureCancellationRequired);

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    _clock?.cancel();
    _navigationFocus.dispose();
    _linkActionFocus.dispose();
    _profileCancelFocus.dispose();
    _profileReturnFocus.dispose();
    super.dispose();
  }

  void _returnFromPin() {
    if (_pinUser == null) return;
    setState(() => _pinUser = null);
    if (widget.accountOrigin &&
        widget.controller.profileSelectionCanCancel &&
        widget.controller.profileSelectionOriginStage == SetupStage.ready) {
      widget.controller.cancelProfileSelection();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _profileReturnFocus.canRequestFocus) {
        _profileReturnFocus.requestFocus();
      }
    });
  }

  void _handleBack() {
    if (_pinUser != null) {
      if (widget.controller.busy) return;
      _returnFromPin();
      return;
    }
    final controller = widget.controller;
    var handled = false;
    if (controller.stage == SetupStage.profiles &&
        controller.profileSelectionCanCancel) {
      controller.cancelProfileSelection();
      handled = true;
    } else if (controller.stage == SetupStage.servers &&
        controller.serverSelectionCanCancel) {
      controller.cancelServerSelection();
      handled = true;
    }
    if (handled) {
      _focusNavigation();
    }
  }

  void _focusNavigation() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _navigationFocus.canRequestFocus) {
        _navigationFocus.requestFocus();
      }
    });
  }

  void _cancelProfileSelection() {
    widget.controller.cancelProfileSelection();
    _focusNavigation();
  }

  void _cancelServerSelection() {
    widget.controller.cancelServerSelection();
    _focusNavigation();
  }

  KeyEventResult _navigationKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent || _pinUser != null) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      final controller = widget.controller;
      if (controller.profileSelectionCanCancel ||
          controller.serverSelectionCanCancel) {
        _handleBack();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final refinedStage = switch (widget.controller.stage) {
      SetupStage.linking || SetupStage.profiles || SetupStage.servers => true,
      _ => false,
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, _) => _handleBack(),
      child: Focus(
        focusNode: _navigationFocus,
        canRequestFocus: true,
        onKeyEvent: _navigationKey,
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): _handleBack,
            const SingleActivator(LogicalKeyboardKey.goBack): _handleBack,
            const SingleActivator(LogicalKeyboardKey.backspace): _handleBack,
          },
          child: Scaffold(
            body: DecoratedBox(
              decoration: refinedStage
                  ? BoxDecoration(color: roles.deepBackground)
                  : BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(-0.6, -0.65),
                        radius: 1.25,
                        colors: [
                          roles.progressFill.withValues(alpha: 0.08),
                          roles.deepBackground,
                        ],
                      ),
                    ),
              child: SafeArea(
                child: Column(
                  children: [
                    if (refinedStage)
                      LineupTopBar(
                        menuKey: const ValueKey('onboarding-app-menu'),
                        onOpenMenu: widget.onOpenMenu,
                        menuFocusNode: widget.menuFocusNode,
                      ),
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 48,
                            vertical: 24,
                          ),
                          child: ConstrainedBox(
                            key: const ValueKey('onboarding-content'),
                            constraints: BoxConstraints(
                              maxWidth: refinedStage ? 1040 : double.infinity,
                            ),
                            child: FocusTraversalGroup(
                              policy: ReadingOrderTraversalPolicy(),
                              child: AnimatedSwitcher(
                                duration:
                                    widget.controller.settings.reduceMotion
                                    ? Duration.zero
                                    : const Duration(milliseconds: 180),
                                child: _screen(
                                  key: ValueKey(widget.controller.stage),
                                ),
                              ),
                            ),
                          ),
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
    );
  }

  Widget _screen({required Key key}) {
    final controller = widget.controller;
    final content = _pinUser != null
        ? _profilePin(key: key)
        : switch (controller.stage) {
            SetupStage.welcome => _welcome(),
            SetupStage.linking => Builder(builder: _linking),
            SetupStage.profiles => _profiles(),
            SetupStage.servers => _servers(),
            SetupStage.channelSetup ||
            SetupStage.ready => const SizedBox.shrink(),
          };
    return Theme(key: key, data: Theme.of(context), child: content);
  }

  Widget _welcome() {
    final enabled = !widget.controller.busy;
    return _HeroContent(
      title: 'Your Plex library, scheduled like television',
      subtitle: 'Link Plex once, choose who is watching, then tune Lineup to your server.',
      leading: Image.asset('assets/branding/lineup-logo-mark.png', height: 120),
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              autofocus: true,
              onPressed: enabled ? widget.controller.startLinking : null,
              icon: const Icon(Icons.link),
              label: const Text('Sign in to Plex'),
            ),
            _onboardingFeedback(const ValueKey('welcome-feedback-slot')),
          ],
        ),
      ),
    );
  }

  bool get _usableLink {
    final pin = widget.controller.activePin;
    return pin != null &&
        pin.expiresAt.isAfter(DateTime.now()) &&
        !widget.controller.secureCancellationRequired;
  }

  Future<void> _openBrowser() async {
    if (!_usableLink || _openingBrowser) return;
    final pinId = widget.controller.activePin!.id;
    setState(() {
      _browserPinId = pinId;
    });
    String? feedback;
    try {
      await widget.openBrowser();
    } catch (_) {
      feedback = 'Couldn’t open your browser. Scan the QR code or visit plex.tv/link and enter the code.';
    }
    if (!mounted || _browserPinId != pinId) return;
    setState(() {
      _browserPinId = null;
    });
    if (feedback != null && widget.controller.activePin?.id == pinId) {
      _showLinkFeedback(feedback);
    }
  }

  Future<void> _copyCode() async {
    if (!_usableLink) return;
    final pin = widget.controller.activePin!;
    String feedback;
    try {
      await Clipboard.setData(ClipboardData(text: pin.code));
      feedback = 'Code copied';
    } catch (_) {
      feedback = 'Couldn’t copy the code. Enter the code shown here.';
    }
    if (!mounted || widget.controller.activePin?.id != pin.id) return;
    _showLinkFeedback(feedback);
  }

  void _showLinkFeedback(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Semantics(liveRegion: true, child: Text(message)),
        ),
      );
  }

  Widget _linking(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _linkingContent(context, constraints.maxWidth),
  );

  Widget _linkingContent(BuildContext context, double contentWidth) {
    final controller = widget.controller;
    final pin = controller.activePin;
    final usable = _usableLink && controller.error == null;
    final expired =
        pin != null &&
        !pin.expiresAt.isAfter(DateTime.now()) &&
        !controller.secureCancellationRequired;
    final remaining =
        pin?.expiresAt.difference(DateTime.now()) ?? Duration.zero;
    final seconds = remaining.inSeconds.clamp(0, 3599);
    final time =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    final roles = LineupTheme.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final narrow = contentWidth <= 720 || textScaler.scale(1) >= 1.6;
    final theme = Theme.of(context);
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 18,
      height: 1.45,
    );
    double textHeight(String text, TextStyle? style, double width) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: textScaler,
      )..layout(maxWidth: math.max(1, width));
      final height = painter.height;
      painter.dispose();
      return height;
    }

    const qrColumnWidth = 232.0;
    final deviceWidth = narrow
        ? contentWidth
        : contentWidth - qrColumnWidth - 40;
    final instructionsHeight = math.max(
      textHeight(
        'Open plex.tv/link and enter this code.',
        bodyStyle,
        deviceWidth,
      ),
      textHeight(
        'Request a fresh code to finish signing in.',
        bodyStyle,
        deviceWidth,
      ),
    );
    final bodyLineHeight = textScaler.scale(18) * 1.45;
    final codeHeight = math.max(
      58.0,
      math.max(
        textScaler.scale(narrow ? 32 : 40) * 1.4,
        bodyLineHeight *
            (narrow
                ? 4
                : textScaler.scale(1) > 1
                ? 3
                : 2),
      ),
    );
    final captionHeight = math.max(
      28.0,
      math.max(
        textHeight(
          'Or scan with your phone',
          theme.textTheme.bodyMedium,
          qrColumnWidth,
        ),
        textHeight(
          'Request a new code',
          theme.textTheme.bodyMedium,
          qrColumnWidth,
        ),
      ),
    );
    final cancelWidth = textScaler.scale(18) * 4 + 56;
    final footerHeight = math.max(
      56.0,
      textHeight(
        'Waiting for sign-in · Expires in 3:59',
        bodyStyle,
        contentWidth - cancelWidth - 18,
      ),
    );
    final safeError = controller.error;
    final message = expired
        ? 'That code expired before sign-in finished.'
        : safeError;
    final codeRow = message == null && pin != null
        ? Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Semantics(
                label: 'Plex link code ${pin.code.split('').join(' ')}',
                excludeSemantics: true,
                child: SelectableText(
                  pin.code,
                  style: LineupTypography.time.copyWith(
                    fontSize: narrow ? 32 : 40,
                    letterSpacing: 6,
                    fontWeight: FontWeight.w500,
                    color: roles.primaryText,
                  ),
                ),
              ),
              LineupCompactControls(
                child: OutlinedButton(
                  onPressed: usable ? _copyCode : null,
                  child: const Text('Copy code'),
                ),
              ),
            ],
          )
        : message == null
        ? const SizedBox.shrink()
        : Semantics(
            key: const ValueKey('linking-message-slot'),
            liveRegion: true,
            child: Text(
              message,
              style: bodyStyle?.copyWith(color: roles.secondaryText),
            ),
          );
    final action = usable
        ? FilledButton.icon(
            onPressed: _openingBrowser ? null : _openBrowser,
            icon: const Icon(Icons.open_in_browser),
            label: const Text('Open browser'),
          )
        : FilledButton(
            focusNode: _linkActionFocus,
            autofocus: true,
            onPressed: controller.busy
                ? null
                : controller.secureCancellationRequired
                ? controller.cancelLinking
                : controller.startLinking,
            child: Text(
              controller.secureCancellationRequired
                  ? 'Retry secure cancellation'
                  : 'Get a new code',
            ),
          );
    final qrSize = narrow ? 172.0 : 200.0;
    final qr = SizedBox(
      width: qrColumnWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Visibility(
            visible: usable,
            maintainState: true,
            maintainAnimation: true,
            maintainSize: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 64, child: Divider(color: roles.subtleBorder)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('or', style: TextStyle(color: roles.mutedText)),
                ),
                SizedBox(width: 64, child: Divider(color: roles.subtleBorder)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            key: const ValueKey('linking-qr-slot'),
            label: usable ? 'QR code for plex.tv/link' : 'QR code unavailable',
            image: true,
            excludeSemantics: true,
            child: Container(
              width: qrSize,
              height: qrSize,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3E8D2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: roles.subtleBorder),
              ),
              alignment: Alignment.center,
              child: usable
                  ? QrImageView(
                      data: 'https://plex.tv/link',
                      size: qrSize - 24,
                      padding: EdgeInsets.zero,
                      semanticsLabel: 'QR code for plex.tv/link',
                    )
                  : Text(
                      expired ? 'Code expired' : 'Unavailable',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF2D241C)),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: captionHeight,
            child: Center(
              child: Text(
                usable ? 'Or scan with your phone' : 'Request a new code',
                textAlign: TextAlign.center,
                style: TextStyle(color: roles.secondaryText),
              ),
            ),
          ),
        ],
      ),
    );
    final deviceColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Sign in to Plex',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontSize: 44,
            height: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: instructionsHeight,
          child: Align(
            alignment: Alignment.topLeft,
            child: RichText(
              textScaler: textScaler,
              text: TextSpan(
                style: bodyStyle,
                children: [
                  TextSpan(
                    text: usable
                        ? 'Open '
                        : 'Request a fresh code to finish signing in. ',
                  ),
                  if (usable)
                    TextSpan(
                      text: 'plex.tv/link',
                      style: bodyStyle?.copyWith(
                        color: roles.progressFill,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (usable) const TextSpan(text: ' and enter this code.'),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          key: const ValueKey('linking-code-slot'),
          height: codeHeight,
          child: Align(alignment: Alignment.centerLeft, child: codeRow),
        ),
        const SizedBox(height: 8),
        SizedBox(
          key: const ValueKey('linking-action-slot'),
          height: 56,
          child: Align(alignment: Alignment.centerLeft, child: action),
        ),
      ],
    );
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [deviceColumn, const SizedBox(height: 24), qr],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: deviceColumn),
                    const SizedBox(width: 40),
                    qr,
                  ],
                ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),
          SizedBox(
            key: const ValueKey('linking-footer'),
            height: footerHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _LinkStatusDot(
                  animated: usable && !controller.settings.reduceMotion,
                  phase: _pulse,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    usable
                        ? 'Waiting for sign-in · Expires in $time'
                        : 'Sign-in unavailable',
                    style: bodyStyle?.copyWith(color: roles.secondaryText),
                  ),
                ),
                if (!controller.secureCancellationRequired)
                  TextButton(
                    onPressed: controller.busy
                        ? null
                        : controller.cancelLinking,
                    child: const Text('Cancel'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profiles() => _HeroContent(
    title: "Who's watching?",
    subtitle: 'Choose a Plex Home profile to continue.',
    compact: true,
    child: Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context)
                .scale(1)
                .clamp(1.0, 1.75);
            final availableWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 1080.0;
            final double gap = 16;
            final itemWidth = 200 * textScale;
            final count = widget.controller.profiles.length;
            final targetColumns = count <= 3
                ? count.clamp(1, 3)
                : ((count + 1) ~/ 2).clamp(1, 5);
            final fittingColumns = ((availableWidth + gap) / (itemWidth + gap))
                .floor()
                .clamp(1, targetColumns);
            final columns = fittingColumns.toInt();
            final rows = <Widget>[];
            for (var start = 0; start < count; start += columns) {
              final rowCount = (count - start).clamp(0, columns).toInt();
              final double rowWidth =
                  ((rowCount * itemWidth) + ((rowCount - 1) * gap)).clamp(
                    0.0,
                    availableWidth,
                  );
              rows.add(
                Padding(
                  padding: EdgeInsets.only(top: start == 0 ? 0 : gap),
                  child: Center(
                    child: SizedBox(
                      width: rowWidth,
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (
                              var column = 0;
                              column < rowCount;
                              column++
                            ) ...[
                              if (column > 0) SizedBox(width: gap),
                              Expanded(
                                child: _ProfileCard(
                                  key: ValueKey(
                                    'profile-card-${widget.controller.profiles[start + column].id}',
                                  ),
                                  user: widget
                                      .controller
                                      .profiles[start + column],
                                  active:
                                      widget
                                          .controller
                                          .profiles[start + column]
                                          .id ==
                                      widget.controller.profile?.id,
                                  autofocus: start + column == 0,
                                  focusNode: start + column == 0
                                      ? _profileReturnFocus
                                      : null,
                                  onPressed: widget.controller.busy
                                      ? null
                                      : () => _selectProfile(
                                          widget.controller.profiles[start +
                                              column],
                                        ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }
            return Center(child: Column(children: rows));
          },
        ),
        SizedBox(height: 28),
        TextButton(
          onPressed: widget.controller.busy ? null : widget.onLogout,
          child: const Text('Sign out'),
        ),
        if (widget.controller.profileSelectionCanCancel) ...[
          SizedBox(height: 12),
          TextButton(
            focusNode: _profileCancelFocus,
            onPressed: _cancelProfileSelection,
            child: Text(
              widget.accountOrigin &&
                      widget.controller.profileSelectionOriginStage ==
                          SetupStage.ready
                  ? '‹ Settings · Account'
                  : 'Back',
            ),
          ),
        ],
        _onboardingFeedback(const ValueKey('profile-feedback-slot')),
      ],
    ),
  );

  Widget _onboardingFeedback(Key key) {
    final controller = widget.controller;
    final message = controller.busy ? 'Working…' : controller.error;
    final roles = LineupTheme.of(context);
    if (message == null) return SizedBox.shrink(key: key);
    return Padding(
      key: key,
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        liveRegion: true,
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: controller.busy
                ? roles.secondaryText
                : Theme.of(context).colorScheme.error,
            fontSize: 18,
          ),
        ),
      ),
    );
  }

  Widget _servers() => _HeroContent(
    title: 'Choose a server',
    subtitle: 'Select the Plex server you want to watch from.',
    centered: false,
    maxWidth: 1040,
    child: Column(
      children: [
        if (widget.controller.servers.isEmpty && !widget.controller.busy)
          Builder(
            builder: (context) {
              final theme = Theme.of(context);
              return Theme(
                data: theme.copyWith(textTheme: theme.textTheme),
                child: DefaultTextStyle.merge(
                  style: DefaultTextStyle.of(context).style,
                  child: const LineupEmptyState(
                    icon: Icons.dns_outlined,
                    title: 'No servers found',
                    message: 'Make sure Plex Media Server is online and reachable, then retry discovery.',
                  ),
                ),
              );
            },
          ),
        for (final server in widget.controller.servers)
          Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: _ServerCard(
              server: server,
              current: widget.controller.server?.id == server.id,
              primary: widget.controller.server == null
                  ? widget.controller.servers.first.id == server.id
                  : widget.controller.server?.id == server.id,
              connection: widget.controller.server?.id == server.id
                  ? widget.controller.connection
                  : null,
              onPressed:
                  widget.controller.busy || _connectingServerId == server.id
                  ? null
                  : widget.controller.server?.id == server.id
                  ? () => _continueServer(server)
                  : () => _connectServer(server),
              previouslyUsed: widget.controller.savedServerId == server.id,
              pending: _connectingServerId == server.id,
              error: _failedServerId == server.id ? _serverError : null,
            ),
          ),
        SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton.icon(
              autofocus: widget.controller.servers.isEmpty,
              onPressed: widget.controller.busy ? null : _refreshServers,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh servers'),
            ),
            if (widget.controller.profiles.length > 1)
              OutlinedButton.icon(
                onPressed: widget.controller.busy ? null : _showProfiles,
                icon: const Icon(Icons.switch_account),
                label: const Text('Switch profile'),
              ),
            if (widget.onRequestLogout != null)
              TextButton(
                onPressed: widget.controller.busy
                    ? null
                    : widget.onRequestLogout,
                child: const Text('Sign out'),
              ),
            if (widget.controller.serverSelectionCanCancel)
              TextButton(
                onPressed: _cancelServerSelection,
                child: Text(
                  widget.accountOrigin ? '‹ Settings · Account' : 'Back',
                ),
              ),
          ],
        ),
        if ((_serverError ?? widget.controller.error) != null &&
            _failedServerId == null)
          Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _serverError ?? widget.controller.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  void _clearServerError() {
    if (!mounted) return;
    setState(() {
      _failedServerId = null;
      _serverError = null;
    });
  }

  Future<void> _refreshServers() async {
    if (!mounted || widget.controller.busy) return;
    _clearServerError();
    await widget.controller.refreshServers();
    if (!mounted || widget.controller.stage != SetupStage.servers) return;
    if (widget.controller.error != null) {
      setState(() => _serverError = widget.controller.error);
    }
  }

  void _showProfiles() {
    if (!mounted || widget.controller.busy) return;
    _clearServerError();
    widget.controller.showProfiles();
  }

  Future<void> _connectServer(PlexServer server) async {
    if (widget.controller.busy) return;
    final attempt = ++_serverAttempt;
    setState(() {
      _connectingServerId = server.id;
      _failedServerId = null;
      _serverError = null;
    });
    await widget.controller.selectServer(server);
    if (!mounted || attempt != _serverAttempt) return;
    setState(() {
      _connectingServerId = null;
      if (widget.controller.stage == SetupStage.servers &&
          widget.controller.error != null) {
        _failedServerId = server.id;
        _serverError = widget.controller.error;
      }
    });
  }

  void _continueServer(PlexServer server) {
    if (widget.controller.busy || widget.controller.server?.id != server.id) {
      return;
    }
    widget.controller.continueCurrentServer();
  }

  Future<void> _selectProfile(PlexHomeUser user) async {
    if (!user.protected) {
      await widget.controller.selectProfile(user);
      return;
    }
    if (!mounted || widget.controller.busy) return;
    setState(() => _pinUser = user);
  }

  Widget _profilePin({required Key key}) => _ProfilePinStep(
    key: key,
    user: _pinUser!,
    accountOrigin: widget.accountOrigin,
    profileOriginIsReady:
        widget.controller.profileSelectionOriginStage == SetupStage.ready,
    onBack: _returnFromPin,
    onAccepted: () {
      if (mounted) setState(() => _pinUser = null);
    },
    onSubmit: (pin) => widget.controller.selectProfile(_pinUser!, pin: pin),
    error: () => widget.controller.error,
  );
}

class _LinkStatusDot extends StatelessWidget {
  const _LinkStatusDot({required this.animated, required this.phase});

  final bool animated;
  final bool phase;

  @override
  Widget build(BuildContext context) {
    final color = LineupTheme.of(context).progressFill;
    return AnimatedOpacity(
      duration: animated ? const Duration(milliseconds: 450) : Duration.zero,
      opacity: animated && !phase ? .35 : 1,
      child: Container(
        key: const ValueKey('linking-status-dot'),
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _HeroContent extends StatelessWidget {
  const _HeroContent({
    required this.title,
    required this.subtitle,
    required this.child,
    this.leading,
    this.compact = false,
    this.centered = true,
    this.maxWidth,
  });
  final String title;
  final String subtitle;
  final Widget? leading;
  final bool compact;
  final bool centered;
  final double? maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        if (leading != null) ...[leading!, SizedBox(height: compact ? 20 : 28)],
        Semantics(
          header: true,
          child: Text(
            title,
            textAlign: centered ? TextAlign.center : TextAlign.left,
            style: LineupTypography.pageTitle,
          ),
        ),
        SizedBox(height: 10),
        Text(
          subtitle,
          textAlign: centered ? TextAlign.center : TextAlign.left,
          style: LineupTypography.body.copyWith(
            color: LineupTheme.of(context).secondaryText,
          ),
        ),
        SizedBox(height: (compact ? 16 : 30)),
        child,
      ],
    );
    if (maxWidth == null) return content;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth!),
        child: SizedBox(width: double.infinity, child: content),
      ),
    );
  }
}

class _ProfileCard extends StatefulWidget {
  const _ProfileCard({
    required this.user,
    required this.active,
    required this.autofocus,
    required this.onPressed,
    this.focusNode,
    super.key,
  });
  final PlexHomeUser user;
  final bool active;
  final bool autofocus;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  FocusNode? _ownedFocusNode;
  bool _focused = false;
  final _nameOverlay = OverlayPortalController();
  final _nameAnchor = LayerLink();

  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownedFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _attachFocusNode(_focusNode);
  }

  @override
  void didUpdateWidget(covariant _ProfileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode == widget.focusNode) return;
    _detachFocusNode(oldWidget.focusNode ?? _ownedFocusNode!);
    _attachFocusNode(_focusNode);
  }

  void _attachFocusNode(FocusNode node) {
    node.addListener(_focusChanged);
    _focused = node.hasFocus;
  }

  void _detachFocusNode(FocusNode node) {
    node.removeListener(_focusChanged);
  }

  void _focusChanged() {
    final next = _focusNode.hasFocus;
    if (next == _focused || !mounted) return;
    setState(() => _focused = next);
    final style = LineupTypography.body.copyWith(fontWeight: FontWeight.w600);
    final painter = TextPainter(
      text: TextSpan(text: widget.user.name, style: style),
      maxLines: 2,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: _nameAnchor.leaderSize?.width ?? 200);
    final clipped = painter.didExceedMaxLines;
    painter.dispose();
    if (next && clipped) {
      _nameOverlay.show();
    } else {
      _nameOverlay.hide();
    }
  }

  @override
  void dispose() {
    _detachFocusNode(_focusNode);
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return SizedBox(
      width: double.infinity,
      child: MergeSemantics(
        child: Semantics(
          button: true,
          selected: widget.active,
          enabled: widget.onPressed != null,
          child: LineupRowSurface(
            selected: widget.active,
            child: TextButton(
              focusNode: _focusNode,
              autofocus: widget.autofocus,
              onPressed: widget.onPressed,
              style: TextButton.styleFrom(alignment: Alignment.topCenter),
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, 16, 12, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LineupProfileAvatar(
                      name: user.name,
                      identity: user.id,
                      size: 120,
                      locked: user.protected,
                      photo: user.thumb?.isAbsolute == true
                          ? NetworkImage(user.thumb.toString())
                          : null,
                    ),
                    SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: Builder(
                        builder: (context) {
                          final roles = LineupTheme.of(context);
                          final nameStyle = LineupTypography.body.copyWith(
                            color: roles.primaryText,
                            fontWeight: FontWeight.w600,
                          );
                          return OverlayPortal(
                            controller: _nameOverlay,
                            overlayChildBuilder: (_) => Positioned(
                              left: 0,
                              top: 0,
                              width:
                                  (_nameAnchor.leaderSize?.width ?? 200) + 16,
                              child: CompositedTransformFollower(
                                link: _nameAnchor,
                                showWhenUnlinked: false,
                                offset: const Offset(-8, -4),
                                child: IgnorePointer(
                                  child: ExcludeSemantics(
                                    child: DecoratedBox(
                                      key: ValueKey(
                                        'profile-name-full-${user.id}',
                                      ),
                                      decoration: BoxDecoration(
                                        color: roles.elevatedSurface,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: roles.subtleBorder,
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        child: Text(
                                          user.name,
                                          textAlign: TextAlign.center,
                                          style: nameStyle,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            child: CompositedTransformTarget(
                              link: _nameAnchor,
                              child: Tooltip(
                                message: user.name,
                                child: Semantics(
                                  label: user.name,
                                  child: Text(
                                    user.name,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: nameStyle,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (user.protected ||
                        user.admin ||
                        user.restricted == true ||
                        widget.active)
                      Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            if (user.admin) const _ProfileBadge('Admin'),
                            if (user.restricted == true)
                              const _ProfileBadge('Restricted'),
                            if (widget.active) const _ProfileBadge('Current'),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileBadge extends StatelessWidget {
  const _ProfileBadge(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: LineupTheme.of(context).elevatedSurface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: LineupTheme.of(context).subtleBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(
            label,
            style: TextStyle(
              color: label == 'Current'
                  ? LineupTheme.of(context).progressFill
                  : LineupTheme.of(context).secondaryText,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    ),
  );
}

PlexConnection? _measuredConnection(PlexServer server) {
  for (final connection in server.connections) {
    if (connection.latency != null) return connection;
  }
  return null;
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.server,
    required this.current,
    required this.connection,
    required this.onPressed,
    required this.primary,
    this.pending = false,
    this.previouslyUsed = false,
    this.error,
  });
  final PlexServer server;
  final bool current;
  final PlexConnection? connection;
  final VoidCallback? onPressed;
  final bool primary;
  final bool pending;
  final bool previouslyUsed;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final measuredConnection = connection ?? _measuredConnection(server);
    final supportStyle = TextStyle(
      color: LineupTheme.of(context).secondaryText,
      fontSize: 18,
    );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              server.name,
              softWrap: true,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            if (current)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: LineupTheme.of(context).progressFill
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Current',
                  style: TextStyle(
                    color: LineupTheme.of(context).progressFill,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: 4),
        Text(
          server.owned ? 'Owned server' : 'Shared server',
          style: supportStyle,
        ),
        if (previouslyUsed && !current)
          Text('Previously used', style: supportStyle),
        const SizedBox(height: 8),
        LineupConnectionStatus(connection: measuredConnection),
      ],
    );
    final buttonLabel = pending
        ? 'Connecting…'
        : current
        ? 'Continue'
        : error != null
        ? 'Retry'
        : 'Connect';
    final actionLabel = buttonLabel == 'Connect'
        ? 'Connect to ${server.name}'
        : buttonLabel;
    final trailing = MergeSemantics(
      child: Semantics(
        label: actionLabel,
        child: primary
            ? FilledButton(
                onPressed: onPressed,
                child: ExcludeSemantics(child: Text(buttonLabel)),
              )
            : LineupCompactControls(
                child: OutlinedButton(
                  onPressed: onPressed,
                  child: ExcludeSemantics(child: Text(buttonLabel)),
                ),
              ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 520 ||
            MediaQuery.textScalerOf(context).scale(1) >= 1.6;
        final content = stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  details,
                  SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: trailing),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: details),
                  SizedBox(width: 24),
                  trailing,
                ],
              );
        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: LineupTheme.of(context).subtleBorder),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              content,
              if (error != null) ...[
                SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ProfilePinStep extends StatefulWidget {
  const _ProfilePinStep({
    required this.user,
    required this.accountOrigin,
    required this.profileOriginIsReady,
    required this.onBack,
    required this.onAccepted,
    required this.onSubmit,
    required this.error,
    super.key,
  });
  final PlexHomeUser user;
  final bool accountOrigin;
  final bool profileOriginIsReady;
  final VoidCallback onBack;
  final VoidCallback onAccepted;
  final Future<bool> Function(String pin) onSubmit;
  final String? Function() error;

  @override
  State<_ProfilePinStep> createState() => _ProfilePinStepState();
}

class _ProfilePinStepState extends State<_ProfilePinStep> {
  String _pin = '';
  String? _error;
  bool _submitting = false;
  int _attempt = 0;
  final _keyboardFocus = FocusNode(debugLabel: 'Profile PIN keyboard owner');
  final _firstDigitFocus = FocusNode(debugLabel: 'Profile PIN digit 1');

  @override
  void dispose() {
    _keyboardFocus.dispose();
    _firstDigitFocus.dispose();
    super.dispose();
  }

  void _digit(int digit) {
    if (_submitting || _pin.length >= 4) return;
    setState(() {
      _error = null;
      _pin += '$digit';
    });
    if (_pin.length == 4) _submit();
  }

  Future<void> _submit() async {
    if (_submitting || _pin.length != 4) return;
    final attempt = ++_attempt;
    final pin = _pin;
    setState(() => _submitting = true);
    final accepted = await widget.onSubmit(pin);
    if (!mounted || attempt != _attempt) return;
    if (accepted) {
      widget.onAccepted();
      return;
    }
    final reportedError = widget.error();
    setState(() {
      _pin = '';
      _submitting = false;
      _error = reportedError == 'That Plex Home PIN was not accepted.'
          ? 'Incorrect PIN. Try again.'
          : reportedError ?? 'Incorrect PIN. Try again.';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _firstDigitFocus.canRequestFocus) {
        _firstDigitFocus.requestFocus();
      }
    });
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final digit = <LogicalKeyboardKey, int>{
      LogicalKeyboardKey.digit0: 0,
      LogicalKeyboardKey.digit1: 1,
      LogicalKeyboardKey.digit2: 2,
      LogicalKeyboardKey.digit3: 3,
      LogicalKeyboardKey.digit4: 4,
      LogicalKeyboardKey.digit5: 5,
      LogicalKeyboardKey.digit6: 6,
      LogicalKeyboardKey.digit7: 7,
      LogicalKeyboardKey.digit8: 8,
      LogicalKeyboardKey.digit9: 9,
      LogicalKeyboardKey.numpad0: 0,
      LogicalKeyboardKey.numpad1: 1,
      LogicalKeyboardKey.numpad2: 2,
      LogicalKeyboardKey.numpad3: 3,
      LogicalKeyboardKey.numpad4: 4,
      LogicalKeyboardKey.numpad5: 5,
      LogicalKeyboardKey.numpad6: 6,
      LogicalKeyboardKey.numpad7: 7,
      LogicalKeyboardKey.numpad8: 8,
      LogicalKeyboardKey.numpad9: 9,
    }[event.logicalKey];
    if (digit != null) {
      _digit(digit);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (!_submitting) {
        setState(() {
          _error = null;
          if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
        });
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      if (!_submitting) widget.onBack();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (_, _) {
      if (!_submitting) widget.onBack();
    },
    child: Focus(
      key: const Key('profile-pin-keyboard-owner'),
      focusNode: _keyboardFocus,
      autofocus: true,
      onKeyEvent: _key,
      child: SizedBox(
        key: const Key('profile-pin-sheet'),
        width: double.infinity,
        child: ConstrainedBox(
          key: const Key('profile-pin-surface'),
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: LineupInlineLink(
                    onPressed: _submitting ? null : widget.onBack,
                    child: Text(
                      widget.accountOrigin && widget.profileOriginIsReady
                          ? '‹ Settings · Account'
                          : '‹ Profiles',
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                LineupProfileAvatar(
                  name: widget.user.name,
                  identity: widget.user.id,
                  size: 120,
                  locked: true,
                  photo: widget.user.thumb?.isAbsolute == true
                      ? NetworkImage(widget.user.thumb.toString())
                      : null,
                ),
                const SizedBox(height: 16),
                Text(
                  widget.user.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: LineupTypography.pageTitle,
                ),
                const SizedBox(height: 28),
                Semantics(
                  key: const Key('profile-pin-progress'),
                  container: true,
                  explicitChildNodes: true,
                  liveRegion: true,
                  label: '${_pin.length} of 4 digits entered',
                  child: ExcludeSemantics(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var index = 0; index < 4; index++)
                          Container(
                            width: 24,
                            height: 24,
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: index < _pin.length
                                  ? LineupTheme.of(context).progressFill
                                  : Colors.transparent,
                              border: Border.all(
                                color: index < _pin.length
                                    ? LineupTheme.of(context).progressFill
                                    : LineupTheme.of(context).defaultBorder,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 44,
                  child: _submitting
                      ? Semantics(
                          label: 'Checking PIN',
                          child: const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _error == null
                      ? const SizedBox.shrink()
                      : Semantics(
                          key: const Key('profile-pin-error'),
                          container: true,
                          liveRegion: true,
                          label: _error,
                          child: ExcludeSemantics(
                            child: Center(
                              child: Text(
                                _error!,
                                softWrap: true,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 16),
                LineupCompactControls(
                  child: SizedBox(
                    width: 3 * 104 + 2 * 8,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var digit = 1; digit <= 9; digit++)
                          _PinKey(
                            digit: digit,
                            focusNode: digit == 1 ? _firstDigitFocus : null,
                            autofocus: digit == 1,
                            onPressed: _submitting ? null : () => _digit(digit),
                          ),
                        const SizedBox(width: 104, height: 76),
                        _PinKey(
                          digit: 0,
                          onPressed: _submitting ? null : () => _digit(0),
                        ),
                        _PinControlKey(
                          tooltip: 'Backspace',
                          onPressed: _submitting || _pin.isEmpty
                              ? null
                              : () => setState(() {
                                  _error = null;
                                  _pin = _pin.substring(0, _pin.length - 1);
                                }),
                          child: const Text(
                            '⌫',
                            style: TextStyle(fontSize: 24),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: _submitting ? null : widget.onBack,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _PinKey extends StatelessWidget {
  const _PinKey({
    required this.digit,
    required this.onPressed,
    this.focusNode,
    this.autofocus = false,
  });

  final int digit;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$digit',
    button: true,
    child: SizedBox(
      width: 104,
      height: 76,
      child: OutlinedButton(
        focusNode: focusNode,
        autofocus: autofocus,
        onPressed: onPressed,
        child: ExcludeSemantics(
          child: Text(
            '$digit',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    ),
  );
}

class _PinControlKey extends StatelessWidget {
  const _PinControlKey({
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    label: tooltip,
    button: true,
    child: Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: SizedBox(
        width: 104,
        height: 76,
        child: OutlinedButton(onPressed: onPressed, child: child),
      ),
    ),
  );
}
