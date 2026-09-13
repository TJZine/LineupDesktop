import 'dart:async';

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
    this.openBrowser = openPlexLink,
    super.key,
  });

  final LineupController controller;
  final Future<void> Function() onLogout;
  final Future<void> Function() openBrowser;

  @override
  State<UpstreamOnboardingView> createState() => _UpstreamOnboardingViewState();
}

class _UpstreamOnboardingViewState extends State<UpstreamOnboardingView> {
  Timer? _clock;
  final _linkActionFocus = FocusNode(debugLabel: 'Retry secure cancellation');
  final _profileCancelFocus = FocusNode(debugLabel: 'Cancel profile selection');
  late bool _linkingStopped;
  late bool _busy;
  String? _linkFeedback;
  int? _feedbackPinId;
  int? _browserPinId;
  bool get _openingBrowser =>
      _browserPinId != null && _browserPinId == widget.controller.activePin?.id;
  String? _connectingServerId;
  String? _failedServerId;
  String? _serverError;
  int _serverAttempt = 0;

  @override
  void initState() {
    super.initState();
    _linkingStopped = _isLinkingStopped(widget.controller);
    _busy = widget.controller.busy;
    widget.controller.addListener(_controllerChanged);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.controller.stage == SetupStage.linking) {
        setState(() {});
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
    _linkActionFocus.dispose();
    _profileCancelFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final scale = LineupLayout.scaleFor(MediaQuery.sizeOf(context));
    final refinedStage = switch (widget.controller.stage) {
      SetupStage.linking || SetupStage.profiles || SetupStage.servers => true,
      _ => false,
    };
    return Scaffold(
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
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(32 * scale),
              child: ConstrainedBox(
                key: const ValueKey('onboarding-content'),
                constraints: const BoxConstraints(maxWidth: double.infinity),
                child: FocusTraversalGroup(
                  policy: ReadingOrderTraversalPolicy(),
                  child: AnimatedSwitcher(
                    duration: widget.controller.settings.reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    child: _screen(key: ValueKey(widget.controller.stage)),
                  ),
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
    final content = switch (controller.stage) {
      SetupStage.welcome => _welcome(),
      SetupStage.linking => Builder(builder: _linking),
      SetupStage.profiles => _profiles(),
      SetupStage.servers => _servers(),
      SetupStage.channelSetup || SetupStage.ready => const SizedBox.shrink(),
    };
    final compactWidth = switch (controller.stage) {
      SetupStage.linking => 736.0,
      SetupStage.profiles => 1080.0,
      SetupStage.servers => 880.0,
      _ => null,
    };
    if (compactWidth != null) {
      return Theme(
        key: key,
        data: _onboardingButtonTheme(context),
        child: _OnboardingCompactPanel(
          maxWidth: compactWidth,
          busy: controller.busy,
          error: controller.stage == SetupStage.servers && _serverError != null
              ? null
              : controller.error,
          child: content,
        ),
      );
    }
    return Theme(
      key: key,
      data: _onboardingButtonTheme(context),
      child: _OnboardingPanel(
        busy: controller.busy,
        error: controller.stage == SetupStage.servers && _serverError != null
            ? null
            : controller.error,
        refinedSurface:
            controller.stage == SetupStage.linking ||
            controller.stage == SetupStage.profiles ||
            controller.stage == SetupStage.servers,
        child: content,
      ),
    );
  }

  Widget _welcome() {
    final enabled = !widget.controller.busy;
    return _HeroContent(
      title: 'Your Plex library, scheduled like television',
      subtitle: 'Link Plex once, choose who is watching, then tune Lineup to your server.',
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        },
        child: FilledButton.icon(
          autofocus: true,
          onPressed: enabled ? widget.controller.startLinking : null,
          icon: const Icon(Icons.link),
          label: const Text('Sign in to Plex'),
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
      _linkFeedback = null;
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
      if (widget.controller.activePin?.id == pinId) {
        _feedbackPinId = pinId;
        _linkFeedback = feedback;
      }
    });
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
    setState(() {
      _feedbackPinId = pin.id;
      _linkFeedback = feedback;
    });
  }

  Widget _linking(BuildContext context) {
    final controller = widget.controller;
    final pin = controller.activePin;
    final usable = _usableLink;
    final expired =
        pin != null &&
        !pin.expiresAt.isAfter(DateTime.now()) &&
        !controller.secureCancellationRequired;
    final remaining =
        pin?.expiresAt.difference(DateTime.now()) ?? Duration.zero;
    final seconds = remaining.inSeconds.clamp(0, 3599);
    final time =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    final feedback = _feedbackPinId == pin?.id ? _linkFeedback : null;
    final roles = LineupTheme.of(context);
    final size = MediaQuery.sizeOf(context);
    final scale = LineupLayout.scaleFor(size);
    final narrow =
        size.width <= 720 * scale ||
        MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    final theme = Theme.of(context);
    final bodyFontSize = (narrow ? 14.0 : 18.0) * scale;
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: bodyFontSize,
      height: 1.45,
    );
    final actionStyle = theme.textTheme.labelLarge?.copyWith(
      fontSize: bodyFontSize,
    );
    final instructions = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Sign in to Plex',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontSize: (narrow ? 26.0 : 36.0) * scale,
            height: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 12 * scale),
        Text(
          pin == null || expired
              ? 'Request a fresh code to finish signing in.'
              : 'Open plex.tv/link and enter this code.',
          style: bodyStyle,
        ),
        SizedBox(height: 20 * scale),
        if (pin != null)
          Wrap(
            spacing: 16 * scale,
            runSpacing: 12 * scale,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Semantics(
                label: 'Plex link code ${pin.code.split('').join(' ')}',
                excludeSemantics: true,
                child: SelectableText(
                  pin.code,
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontSize: (narrow ? 32.0 : 40.0) * scale,
                    letterSpacing: 6 * scale,
                    fontWeight: FontWeight.w500,
                    color: usable ? roles.primaryText : roles.mutedText,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: usable ? _copyCode : null,
                style: OutlinedButton.styleFrom(textStyle: actionStyle),
                icon: const Icon(Icons.copy),
                label: const Text('Copy code'),
              ),
            ],
          ),
        SizedBox(height: 16 * scale),
        Wrap(
          spacing: 12 * scale,
          runSpacing: 12 * scale,
          children: [
            if (usable)
              FilledButton.icon(
                onPressed: _openingBrowser ? null : _openBrowser,
                style: FilledButton.styleFrom(textStyle: actionStyle),
                icon: const Icon(Icons.open_in_browser),
                label: const Text('Open browser'),
              )
            else
              FilledButton(
                focusNode: _linkActionFocus,
                autofocus: true,
                onPressed: controller.busy
                    ? null
                    : controller.secureCancellationRequired
                    ? controller.cancelLinking
                    : controller.startLinking,
                style: FilledButton.styleFrom(textStyle: actionStyle),
                child: Text(
                  controller.secureCancellationRequired
                      ? 'Retry secure cancellation'
                      : 'Get a new code',
                ),
              ),
          ],
        ),
        if (feedback != null) ...[
          SizedBox(height: 12 * scale),
          Semantics(liveRegion: true, child: Text(feedback, style: bodyStyle)),
        ],
      ],
    );
    final hasQr = usable || expired;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 736 * scale),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 736 * scale),
                  child: LayoutBuilder(
                    builder: (context, bodyConstraints) {
                      final qrSize = (narrow ? 172.0 : 200.0) * scale;
                      final qr = hasQr
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  width: qrSize,
                                  height: qrSize,
                                  padding: EdgeInsets.all(12 * scale),
                                  decoration: BoxDecoration(
                                    color: usable
                                        ? Colors.white
                                        : roles.primarySurface,
                                    borderRadius: BorderRadius.circular(8),
                                    border: expired
                                        ? Border.all(color: roles.subtleBorder)
                                        : null,
                                  ),
                                  alignment: Alignment.center,
                                  child: usable
                                      ? QrImageView(
                                          data: 'https://plex.tv/link',
                                          size: qrSize - 24 * scale,
                                          padding: EdgeInsets.zero,
                                          semanticsLabel:
                                              'QR code for plex.tv/link',
                                        )
                                      : Semantics(
                                          label: 'Code expired',
                                          image: true,
                                          child: Text(
                                            'Code expired',
                                            textAlign: TextAlign.center,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  fontSize:
                                                      (theme
                                                              .textTheme
                                                              .bodyMedium
                                                              ?.fontSize ??
                                                          14) *
                                                      scale,
                                                  color: roles.secondaryText,
                                                ),
                                          ),
                                        ),
                                ),
                                SizedBox(height: 8 * scale),
                                Text(
                                  expired
                                      ? 'Request a new code'
                                      : 'Or scan with your phone',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize:
                                        (theme.textTheme.bodySmall?.fontSize ??
                                            12) *
                                        scale,
                                    color: roles.secondaryText,
                                  ),
                                ),
                              ],
                            )
                          : const SizedBox.shrink();
                      return narrow
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                instructions,
                                if (hasQr) ...[
                                  SizedBox(height: 24 * scale),
                                  Align(alignment: Alignment.center, child: qr),
                                ],
                              ],
                            )
                          : hasQr
                          ? Row(
                              children: [
                                Expanded(child: instructions),
                                if (hasQr) ...[SizedBox(width: 40 * scale), qr],
                              ],
                            )
                          : SizedBox(
                              width: double.infinity,
                              child: instructions,
                            );
                    },
                  ),
                ),
              ),
              SizedBox(height: 20 * scale),
              const Divider(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      usable
                          ? 'Waiting for sign-in · Expires in $time'
                          : expired
                          ? 'This code has expired'
                          : 'This code is no longer active.',
                      style: bodyStyle?.copyWith(
                        fontSize: (narrow ? 14.0 : 16.0) * scale,
                        color: roles.secondaryText,
                      ),
                    ),
                  ),
                  if (!controller.secureCancellationRequired)
                    Padding(
                      padding: EdgeInsets.only(left: 12 * scale),
                      child: TextButton(
                        onPressed: controller.busy
                            ? null
                            : controller.cancelLinking,
                        style: TextButton.styleFrom(
                          foregroundColor: roles.secondaryText,
                          textStyle: actionStyle,
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profiles() => _HeroContent(
    title: "Who's watching?",
    subtitle: 'Choose a Plex Home profile to continue.',
    compact: true,
    titleFontSize: 36,
    subtitleFontSize: 18,
    titleWeight: FontWeight.w600,
    child: Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = LineupLayout.scaleFor(MediaQuery.sizeOf(context));
            final textScale = MediaQuery.textScalerOf(context)
                .scale(1)
                .clamp(1.0, 1.75);
            final availableWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 1080 * scale;
            final gap = 16 * scale;
            final itemWidth = 200 * scale * textScale;
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
              final rowWidth = ((rowCount * itemWidth) + ((rowCount - 1) * gap))
                  .clamp(0.0, availableWidth);
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
        SizedBox(
          height: 28 * LineupLayout.scaleFor(MediaQuery.sizeOf(context)),
        ),
        OutlinedButton.icon(
          onPressed: widget.controller.busy ? null : widget.onLogout,
          style: OutlinedButton.styleFrom(
            textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontSize: 18 * LineupLayout.scaleFor(MediaQuery.sizeOf(context)),
            ),
          ),
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
        if (widget.controller.profileSelectionCanCancel) ...[
          SizedBox(
            height: 12 * LineupLayout.scaleFor(MediaQuery.sizeOf(context)),
          ),
          TextButton(
            focusNode: _profileCancelFocus,
            onPressed: widget.controller.cancelProfileSelection,
            style: TextButton.styleFrom(
              textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontSize:
                    18 * LineupLayout.scaleFor(MediaQuery.sizeOf(context)),
              ),
            ),
            child: const Text('Back'),
          ),
        ],
      ],
    ),
  );

  Widget _servers() => _HeroContent(
    title: 'Choose a server',
    subtitle: 'Select the Plex server you want to watch from.',
    centered: false,
    maxWidth: 880,
    titleFontSize: 36,
    subtitleFontSize: 18,
    titleWeight: FontWeight.w600,
    child: Column(
      children: [
        if (widget.controller.servers.isEmpty && !widget.controller.busy)
          Builder(
            builder: (context) {
              final scale = LineupLayout.scaleFor(MediaQuery.sizeOf(context));
              final theme = Theme.of(context);
              return Theme(
                data: theme.copyWith(
                  textTheme: theme.textTheme.apply(fontSizeFactor: scale),
                ),
                child: DefaultTextStyle.merge(
                  style: DefaultTextStyle.of(context).style
                      .apply(fontSizeFactor: scale),
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
            padding: EdgeInsets.only(
              bottom: 12 * LineupLayout.scaleFor(MediaQuery.sizeOf(context)),
            ),
            child: _ServerCard(
              server: server,
              connection: widget.controller.server?.id == server.id
                  ? widget.controller.connection
                  : null,
              onPressed: widget.controller.busy
                  ? null
                  : () => _connectServer(server),
              previouslyUsed: widget.controller.savedServerId == server.id,
              pending: _connectingServerId == server.id,
              error: _failedServerId == server.id ? _serverError : null,
            ),
          ),
        SizedBox(
          height: 12 * LineupLayout.scaleFor(MediaQuery.sizeOf(context)),
        ),
        Wrap(
          spacing: 12 * LineupLayout.scaleFor(MediaQuery.sizeOf(context)),
          runSpacing: 12 * LineupLayout.scaleFor(MediaQuery.sizeOf(context)),
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton.icon(
              autofocus: widget.controller.servers.isEmpty,
              onPressed: widget.controller.busy ? null : _refreshServers,
              style: OutlinedButton.styleFrom(
                textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontSize:
                      18 * LineupLayout.scaleFor(MediaQuery.sizeOf(context)),
                ),
              ),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh servers'),
            ),
            if (widget.controller.profiles.length > 1)
              OutlinedButton.icon(
                onPressed: widget.controller.busy ? null : _showProfiles,
                style: OutlinedButton.styleFrom(
                  textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontSize:
                        18 * LineupLayout.scaleFor(MediaQuery.sizeOf(context)),
                  ),
                ),
                icon: const Icon(Icons.switch_account),
                label: const Text('Switch profile'),
              ),
            if (widget.controller.serverSelectionCanCancel)
              TextButton(
                onPressed: widget.controller.cancelServerSelection,
                style: TextButton.styleFrom(
                  textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontSize:
                        18 * LineupLayout.scaleFor(MediaQuery.sizeOf(context)),
                  ),
                ),
                child: const Text('Back'),
              ),
          ],
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

  Future<void> _selectProfile(PlexHomeUser user) async {
    if (!user.protected) {
      await widget.controller.selectProfile(user);
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProfilePinDialog(
        user: user,
        onSubmit: (pin) => widget.controller.selectProfile(user, pin: pin),
        error: () => widget.controller.error,
      ),
    );
  }
}

ThemeData _onboardingButtonTheme(BuildContext context) {
  final scale = LineupLayout.scaleFor(MediaQuery.sizeOf(context));
  final theme = Theme.of(context);
  return theme.copyWith(
    filledButtonTheme: FilledButtonThemeData(
      style: _scaledOnboardingButtonStyle(
        theme.filledButtonTheme.style,
        scale: scale,
        minimumSize: const Size(148, 54),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        iconSize: 18,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _scaledOnboardingButtonStyle(
        theme.outlinedButtonTheme.style,
        scale: scale,
        minimumSize: const Size(148, 54),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        iconSize: 18,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: _scaledOnboardingButtonStyle(
        theme.textButtonTheme.style,
        scale: scale,
        minimumSize: const Size(64, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        iconSize: 18,
      ),
    ),
  );
}

ButtonStyle _scaledOnboardingButtonStyle(
  ButtonStyle? source, {
  required double scale,
  required Size minimumSize,
  required EdgeInsets padding,
  required double iconSize,
}) {
  final base = source ?? const ButtonStyle();
  var scaled = base.copyWith(
    minimumSize: WidgetStatePropertyAll(
      Size(minimumSize.width * scale, minimumSize.height * scale),
    ),
    padding: WidgetStatePropertyAll(
      EdgeInsets.fromLTRB(
        padding.left * scale,
        padding.top * scale,
        padding.right * scale,
        padding.bottom * scale,
      ),
    ),
    iconSize: WidgetStatePropertyAll(iconSize * scale),
  );
  final textStyle = base.textStyle;
  if (textStyle == null) return scaled;
  scaled = scaled.copyWith(
    textStyle: WidgetStateProperty.resolveWith((states) {
      final resolved = textStyle.resolve(states);
      final fontSize = resolved?.fontSize;
      return resolved == null || fontSize == null
          ? resolved
          : resolved.copyWith(fontSize: fontSize * scale);
    }),
  );
  return scaled;
}

class _OnboardingCompactPanel extends StatelessWidget {
  const _OnboardingCompactPanel({
    required this.busy,
    required this.error,
    required this.child,
    this.maxWidth = 736,
  });

  final bool busy;
  final String? error;
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final scale = LineupLayout.scaleFor(size);
    final narrow =
        size.width <= 720 * scale ||
        MediaQuery.textScalerOf(context).scale(1) >= 1.6;
    final roles = LineupTheme.of(context);
    final bodyFontSize = (narrow ? 14.0 : 18.0) * scale;
    final content = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth * scale),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/branding/lineup-logo-mark.png',
                  height: 24 * scale,
                  width: 24 * scale,
                ),
                SizedBox(width: 8 * scale),
                Text(
                  'LINEUP',
                  style: TextStyle(
                    color: roles.progressFill,
                    fontFamily: 'Arial',
                    fontSize: 18 * scale,
                    letterSpacing: 1.5 * scale,
                  ),
                ),
              ],
            ),
            SizedBox(height: 20 * scale),
            if (busy) ...[
              LinearProgressIndicator(semanticsLabel: 'Working'),
              SizedBox(height: 16 * scale),
            ],
            if (error != null) ...[
              DefaultTextStyle(
                style: Theme.of(context).textTheme.bodyMedium!
                    .copyWith(fontSize: bodyFontSize, height: 1.45),
                child: LineupNotice(message: error!),
              ),
              SizedBox(height: 16 * scale),
            ],
            child,
          ],
        ),
      ),
    );
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth * scale),
        child: content,
      ),
    );
  }
}

class _OnboardingPanel extends StatelessWidget {
  const _OnboardingPanel({
    required this.busy,
    required this.error,
    required this.refinedSurface,
    required this.child,
  });
  final bool busy;
  final String? error;
  final bool refinedSurface;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scale = LineupLayout.scaleFor(MediaQuery.sizeOf(context));
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(fontSizeFactor: scale),
      ),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: 48 * scale,
          vertical: 38 * scale,
        ),
        decoration: BoxDecoration(
          color: refinedSurface
              ? LineupTheme.of(context).deepBackground
              : LineupTheme.of(context).primarySurface,
          borderRadius: BorderRadius.circular(
            LineupTheme.of(context).panelRadius,
          ),
          border: refinedSurface
              ? Border.all(color: LineupTheme.of(context).subtleBorder)
              : Border(
                  bottom: BorderSide(
                    color: LineupTheme.of(context).defaultBorder,
                  ),
                ),
        ),
        child: Column(
          children: [
            Image.asset(
              'assets/branding/lineup-logo-mark.png',
              height: 62 * scale,
            ),
            if (busy) ...[
              SizedBox(height: 16 * scale),
              const LinearProgressIndicator(semanticsLabel: 'Working'),
            ],
            if (error != null) ...[
              SizedBox(height: 16 * scale),
              LineupNotice(message: error!),
            ],
            SizedBox(height: 18 * scale),
            DefaultTextStyle(
              style: theme.textTheme.bodyMedium!.apply(fontSizeFactor: scale),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroContent extends StatelessWidget {
  const _HeroContent({
    required this.title,
    required this.subtitle,
    required this.child,
    this.compact = false,
    this.centered = true,
    this.maxWidth,
    this.titleFontSize,
    this.subtitleFontSize,
    this.titleWeight,
  });
  final String title;
  final String subtitle;
  final bool compact;
  final bool centered;
  final double? maxWidth;
  final double? titleFontSize;
  final double? subtitleFontSize;
  final FontWeight? titleWeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scale = LineupLayout.scaleFor(MediaQuery.sizeOf(context));
    final content = Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            textAlign: centered ? TextAlign.center : TextAlign.left,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontSize: titleFontSize == null ? null : titleFontSize! * scale,
              fontWeight: titleWeight ?? FontWeight.w800,
            ),
          ),
        ),
        SizedBox(height: 10 * scale),
        Text(
          subtitle,
          textAlign: centered ? TextAlign.center : TextAlign.left,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: subtitleFontSize == null
                ? null
                : subtitleFontSize! * scale,
            color: LineupTheme.of(context).secondaryText,
          ),
        ),
        SizedBox(height: (compact ? 16 : 30) * scale),
        child,
      ],
    );
    if (maxWidth == null) return content;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth! * scale),
        child: SizedBox(width: double.infinity, child: content),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.user,
    required this.active,
    required this.autofocus,
    required this.onPressed,
  });
  final PlexHomeUser user;
  final bool active;
  final bool autofocus;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final scale = LineupLayout.scaleFor(size);
    final roles = LineupTheme.of(context);
    final buttonStyle = ButtonStyle(
      alignment: Alignment.topCenter,
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      minimumSize: const WidgetStatePropertyAll(Size.zero),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(roles.panelRadius),
        ),
      ),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return roles.progressFill.withValues(alpha: 0.14);
        }
        if (active) return roles.selectedSurface;
        if (states.contains(WidgetState.focused)) {
          return roles.focusedSurface;
        }
        if (states.contains(WidgetState.hovered)) {
          return roles.primarySurface.withValues(alpha: 0.7);
        }
        return Colors.transparent;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return roles.mutedText;
        if (states.contains(WidgetState.focused)) return roles.focusedText;
        return roles.primaryText;
      }),
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.focused)) {
          return BorderSide(
            color: roles.focusBorder,
            width: _onboardingFocusWidth(roles) * scale,
          );
        }
        if (states.contains(WidgetState.hovered)) {
          return BorderSide(color: roles.defaultBorder);
        }
        return BorderSide.none;
      }),
      overlayColor: WidgetStatePropertyAll(
        roles.progressFill.withValues(alpha: 0.12),
      ),
    );
    return SizedBox(
      width: double.infinity,
      child: MergeSemantics(
        child: Semantics(
          button: true,
          selected: active,
          enabled: onPressed != null,
          child: TextButton(
            autofocus: autofocus,
            onPressed: onPressed,
            style: buttonStyle,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                12 * scale,
                16 * scale,
                12 * scale,
                16 * scale,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 48 * scale,
                    backgroundColor: roles.elevatedSurface,
                    foregroundColor: roles.secondaryText,
                    backgroundImage: user.thumb?.isAbsolute == true
                        ? NetworkImage(user.thumb.toString())
                        : null,
                    child: user.thumb?.isAbsolute == true
                        ? null
                        : Text(
                            user.name.characters.first.toUpperCase(),
                            style: TextStyle(fontSize: 32 * scale),
                          ),
                  ),
                  SizedBox(height: 12 * scale),
                  Text(
                    user.name,
                    textAlign: TextAlign.center,
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 18 * scale,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (user.protected ||
                      user.admin ||
                      user.restricted == true ||
                      active)
                    Padding(
                      padding: EdgeInsets.only(top: 4 * scale),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 4 * scale,
                        runSpacing: 4 * scale,
                        children: [
                          if (user.protected) const _ProfileBadge('PIN'),
                          if (user.admin) const _ProfileBadge('Admin'),
                          if (user.restricted == true)
                            const _ProfileBadge('Restricted'),
                          if (active) const _ProfileBadge('Active'),
                        ],
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

class _ProfileBadge extends StatelessWidget {
  const _ProfileBadge(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: ExcludeSemantics(
      child: Text(
        label,
        style: TextStyle(
          color: LineupTheme.of(context).secondaryText,
          fontSize: 12 * LineupLayout.scaleFor(MediaQuery.sizeOf(context)),
        ),
      ),
    ),
  );
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.server,
    required this.connection,
    required this.onPressed,
    this.pending = false,
    this.previouslyUsed = false,
    this.error,
  });
  final PlexServer server;
  final PlexConnection? connection;
  final VoidCallback? onPressed;
  final bool pending;
  final bool previouslyUsed;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scale = LineupLayout.scaleFor(MediaQuery.sizeOf(context));
    final supportStyle = TextStyle(
      color: LineupTheme.of(context).secondaryText,
      fontSize: 16 * scale,
    );
    final actionStyle = Theme.of(context).textTheme.labelLarge
        ?.copyWith(fontSize: 18 * scale);
    final actionLabel = pending
        ? 'Connecting…'
        : error != null
        ? 'Retry'
        : 'Connect to ${server.name}';
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12 * scale,
          runSpacing: 8 * scale,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              server.name,
              softWrap: true,
              style: TextStyle(
                fontSize: 22 * scale,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (connection != null)
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 8 * scale,
                  vertical: 4 * scale,
                ),
                decoration: BoxDecoration(
                  color: LineupTheme.of(context).progressFill
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6 * scale),
                ),
                child: Text(
                  'Current',
                  style: TextStyle(
                    color: LineupTheme.of(context).progressFill,
                    fontSize: 12 * scale,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: 4 * scale),
        Text(
          server.owned ? 'Owned server' : 'Shared server',
          style: supportStyle,
        ),
        if (previouslyUsed && connection == null)
          Text('Previously used', style: supportStyle),
        if (connection != null) ...[
          SizedBox(height: 8 * scale),
          Text(
            'Current connection: ${plexConnectionDescription(connection!)}',
            softWrap: true,
            style: supportStyle,
          ),
        ],
      ],
    );
    final trailing = connection == null
        ? MergeSemantics(
            child: Semantics(
              label: actionLabel,
              child: FilledButton(
                onPressed: onPressed,
                style: FilledButton.styleFrom(textStyle: actionStyle),
                child: ExcludeSemantics(
                  child: Text(
                    pending
                        ? 'Connecting…'
                        : error != null
                        ? 'Retry'
                        : 'Connect',
                  ),
                ),
              ),
            ),
          )
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 520 * scale ||
            MediaQuery.textScalerOf(context).scale(1) >= 1.6;
        final content = stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  details,
                  if (trailing != null) ...[
                    SizedBox(height: 12 * scale),
                    Align(alignment: Alignment.centerLeft, child: trailing),
                  ],
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: details),
                  if (trailing != null) ...[
                    SizedBox(width: 24 * scale),
                    trailing,
                  ],
                ],
              );
        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: 20 * scale),
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
                SizedBox(height: 12 * scale),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 16 * scale,
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

class _ProfilePinDialog extends StatefulWidget {
  const _ProfilePinDialog({
    required this.user,
    required this.onSubmit,
    required this.error,
  });
  final PlexHomeUser user;
  final Future<bool> Function(String pin) onSubmit;
  final String? Function() error;
  @override
  State<_ProfilePinDialog> createState() => _ProfilePinDialogState();
}

class _ProfilePinDialogState extends State<_ProfilePinDialog> {
  String _pin = '';
  String? _error;
  bool _submitting = false;
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
    setState(() => _submitting = true);
    final accepted = await widget.onSubmit(_pin);
    if (!mounted) return;
    if (accepted) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _pin = '';
      _submitting = false;
      _error = widget.error();
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
    if (!_submitting && event.logicalKey == LogicalKeyboardKey.backspace) {
      setState(() {
        _error = null;
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_submitting,
    child: Focus(
      key: const Key('profile-pin-keyboard-owner'),
      focusNode: _keyboardFocus,
      autofocus: true,
      onKeyEvent: _key,
      child: Dialog(
        key: const Key('profile-pin-sheet'),
        backgroundColor: LineupTheme.of(context).primarySurface,
        alignment: Alignment.center,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            LineupTheme.of(context).panelRadius,
          ),
          side: BorderSide(color: LineupTheme.of(context).defaultBorder),
        ),
        child: ConstrainedBox(
          key: const Key('profile-pin-surface'),
          constraints: const BoxConstraints(maxWidth: 384),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Enter PIN',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: LineupTheme.of(context)
                              .elevatedSurface,
                          foregroundColor: LineupTheme.of(context)
                              .secondaryText,
                          backgroundImage: widget.user.thumb?.isAbsolute == true
                              ? NetworkImage(widget.user.thumb.toString())
                              : null,
                          child: widget.user.thumb?.isAbsolute == true
                              ? null
                              : Text(
                                  widget.user.name.characters.first
                                      .toUpperCase(),
                                  style: const TextStyle(fontSize: 18),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            widget.user.name,
                            softWrap: true,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: LineupTheme.of(context).secondaryText,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
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
                              width: 16,
                              height: 16,
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: index < _pin.length
                                    ? LineupTheme.of(context).progressFill
                                    : Colors.transparent,
                                border: Border.all(
                                  color: index < _pin.length
                                      ? LineupTheme.of(context).progressFill
                                      : LineupTheme.of(context).defaultBorder,
                                  width: 1,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 38),
                    child: _submitting
                        ? Semantics(
                            label: 'Checking PIN',
                            child: const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : _error == null
                        ? const Align(
                            alignment: Alignment.center,
                            child: Text('Type or use the number pad.'),
                          )
                        : Semantics(
                            key: const Key('profile-pin-error'),
                            container: true,
                            liveRegion: true,
                            label: _error,
                            child: ExcludeSemantics(
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
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 224,
                    child: GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 3,
                      childAspectRatio: 1.33,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      children: [
                        for (var digit = 1; digit <= 9; digit++)
                          _PinKey(
                            digit: digit,
                            focusNode: digit == 1 ? _firstDigitFocus : null,
                            autofocus: digit == 1,
                            onPressed: _submitting ? null : () => _digit(digit),
                          ),
                        _PinControlKey(
                          tooltip: 'Delete',
                          onPressed: _submitting || _pin.isEmpty
                              ? null
                              : () => setState(() {
                                  _error = null;
                                  _pin = _pin.substring(0, _pin.length - 1);
                                }),
                          child: const Text(
                            'Delete',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        _PinKey(
                          digit: 0,
                          onPressed: _submitting ? null : () => _digit(0),
                        ),
                        const SizedBox.shrink(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: LineupTheme.of(context).secondaryText,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    child: const Text('Cancel'),
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
    child: FilledButton(
      focusNode: focusNode,
      autofocus: autofocus,
      onPressed: onPressed,
      style: _pinKeyStyle(context),
      child: ExcludeSemantics(
        child: Text(
          '$digit',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
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
      child: FilledButton(
        onPressed: onPressed,
        style: _pinKeyStyle(context, secondary: true),
        child: child,
      ),
    ),
  );
}

ButtonStyle _pinKeyStyle(BuildContext context, {bool secondary = false}) {
  final roles = LineupTheme.of(context);
  return ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size.zero),
    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return roles.elevatedSurface.withValues(alpha: 0.45);
      }
      if (states.contains(WidgetState.pressed)) {
        return roles.progressFill.withValues(alpha: secondary ? 0.14 : 0.28);
      }
      if (states.contains(WidgetState.focused)) return roles.focusedSurface;
      return roles.elevatedSurface.withValues(alpha: secondary ? 0.55 : 0.82);
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return roles.mutedText;
      if (states.contains(WidgetState.focused)) return roles.focusedText;
      return secondary ? roles.secondaryText : roles.primaryText;
    }),
    side: WidgetStateProperty.resolveWith(
      (states) => BorderSide(
        color: states.contains(WidgetState.focused)
            ? roles.focusBorder
            : roles.subtleBorder,
        width: states.contains(WidgetState.focused)
            ? _onboardingFocusWidth(roles)
            : 1,
      ),
    ),
    overlayColor: WidgetStatePropertyAll(
      roles.progressFill.withValues(alpha: 0.12),
    ),
  );
}

double _onboardingFocusWidth(LineupThemeRoles roles) =>
    roles.focusBorderWidth >= 5 ? roles.focusBorderWidth : 2;
