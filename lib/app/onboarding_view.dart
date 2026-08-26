import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../plex/plex_models.dart';
import '../ui/app_theme.dart';
import '../ui/app_ui.dart';
import 'lineup_controller.dart';

class UpstreamOnboardingView extends StatefulWidget {
  const UpstreamOnboardingView({
    required this.controller,
    required this.onLogout,
    super.key,
  });

  static const maxContentWidth = 1180.0;

  final LineupController controller;
  final Future<void> Function() onLogout;

  @override
  State<UpstreamOnboardingView> createState() => _UpstreamOnboardingViewState();
}

class _UpstreamOnboardingViewState extends State<UpstreamOnboardingView> {
  Timer? _clock;
  final _linkActionFocus = FocusNode(debugLabel: 'Retry secure cancellation');
  final _profileCancelFocus = FocusNode(debugLabel: 'Cancel profile selection');
  late bool _linkingStopped;
  late bool _busy;

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
  Widget build(BuildContext context) => Scaffold(
    body: DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.6, -0.65),
          radius: 1.25,
          colors: [
            LineupTheme.of(context).progressFill.withValues(alpha: 0.08),
            LineupTheme.of(context).deepBackground,
          ],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              key: const ValueKey('onboarding-content'),
              constraints: const BoxConstraints(
                maxWidth: UpstreamOnboardingView.maxContentWidth,
              ),
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

  Widget _screen({required Key key}) {
    final controller = widget.controller;
    final content = switch (controller.stage) {
      SetupStage.welcome => _welcome(),
      SetupStage.linking => _linking(),
      SetupStage.profiles => _profiles(),
      SetupStage.servers => _servers(),
      SetupStage.audio => _audio(),
      SetupStage.channelSetup || SetupStage.ready => const SizedBox.shrink(),
    };
    return _OnboardingPanel(
      key: key,
      busy: controller.busy,
      error: controller.error,
      child: content,
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

  Widget _linking() {
    final pin = widget.controller.activePin;
    final stopped = _isLinkingStopped(widget.controller);
    final remaining = pin == null
        ? Duration.zero
        : pin.expiresAt.difference(DateTime.now());
    final seconds = remaining.inSeconds.clamp(0, 3599);
    final time =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    final code = (pin?.code ?? '----').padRight(4, '-').substring(0, 4);
    return _HeroContent(
      title: 'Sign in to Plex',
      subtitle: stopped
          ? 'Sign-in stopped. Request a new code to try again.'
          : 'Scan the QR code or visit plex.tv/link',
      child: Column(
        children: [
          const SizedBox(height: 16),
          if (!stopped)
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 42,
              runSpacing: 28,
              children: [
                if (pin != null)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: QrImageView(
                      data: 'https://plex.tv/link',
                      size: 190,
                      padding: EdgeInsets.zero,
                      semanticsLabel: 'QR code for plex.tv/link',
                    ),
                  ),
                Column(
                  children: [
                    Semantics(
                      liveRegion: true,
                      label: 'Plex link code ${code.split('').join(' ')}',
                      excludeSemantics: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final character in code.characters)
                            _PinCell(character),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      pin == null ? 'Requesting PIN…' : 'Waiting for sign-in…',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (pin != null) ...[
                      const SizedBox(height: 10),
                      Chip(
                        avatar: const Icon(Icons.schedule, size: 18),
                        label: Text(
                          'Expires in $time',
                          style: const TextStyle(
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          if (stopped)
            Icon(
              Icons.link_off,
              size: 72,
              color: Theme.of(context).colorScheme.error,
              semanticLabel: 'Plex sign-in stopped',
            ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton(
                focusNode: _linkActionFocus,
                autofocus: pin == null,
                onPressed: widget.controller.busy
                    ? null
                    : widget.controller.secureCancellationRequired
                    ? widget.controller.cancelLinking
                    : widget.controller.startLinking,
                child: Text(
                  widget.controller.secureCancellationRequired
                      ? 'Retry secure cancellation'
                      : stopped
                      ? 'Request a new code'
                      : pin == null
                      ? 'Request PIN'
                      : 'Request a new code',
                ),
              ),
              if (pin != null && !widget.controller.secureCancellationRequired)
                TextButton(
                  onPressed: widget.controller.busy
                      ? null
                      : widget.controller.cancelLinking,
                  child: const Text('Cancel'),
                ),
            ],
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
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final user in widget.controller.profiles)
              _ProfileCard(
                user: user,
                active: user.id == widget.controller.profile?.id,
                autofocus: user == widget.controller.profiles.first,
                onPressed: widget.controller.busy
                    ? null
                    : () => _selectProfile(user),
              ),
          ],
        ),
        const SizedBox(height: 28),
        OutlinedButton.icon(
          onPressed: widget.controller.busy ? null : widget.onLogout,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
        if (widget.controller.profileSelectionCanCancel) ...[
          const SizedBox(height: 12),
          TextButton(
            focusNode: _profileCancelFocus,
            onPressed: widget.controller.cancelProfileSelection,
            child: const Text('Cancel'),
          ),
        ],
      ],
    ),
  );

  Widget _servers() => _HeroContent(
    title: 'Select Plex Server',
    subtitle: 'Choose a server to continue startup.',
    child: Column(
      children: [
        if (widget.controller.servers.isEmpty && !widget.controller.busy)
          const LineupEmptyState(
            icon: Icons.dns_outlined,
            title: 'No servers found',
            message: 'Make sure Plex Media Server is online and reachable, then retry discovery.',
          ),
        for (final server in widget.controller.servers)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ServerCard(
              server: server,
              connection: widget.controller.server?.id == server.id
                  ? widget.controller.connection
                  : null,
              onPressed: widget.controller.busy
                  ? null
                  : () => widget.controller.selectServer(server),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            OutlinedButton.icon(
              autofocus: widget.controller.servers.isEmpty,
              onPressed: widget.controller.busy
                  ? null
                  : widget.controller.refreshServers,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry discovery'),
            ),
            if (widget.controller.profiles.isNotEmpty)
              OutlinedButton.icon(
                onPressed: widget.controller.busy
                    ? null
                    : widget.controller.showProfiles,
                icon: const Icon(Icons.switch_account),
                label: const Text('Switch profile'),
              ),
            if (widget.controller.server != null)
              OutlinedButton.icon(
                onPressed: widget.controller.busy
                    ? null
                    : widget.controller.clearSavedServer,
                icon: const Icon(Icons.link_off),
                label: const Text('Clear saved server'),
              ),
            if (widget.controller.serverSelectionCanCancel)
              TextButton(
                onPressed: widget.controller.cancelServerSelection,
                child: const Text('Cancel'),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _audio() => _HeroContent(
    title: 'Audio Setup',
    step: 'Step 2 of 3',
    subtitle: 'Lineup uses the system-selected audio output on Desktop.',
    child: Column(
      children: [
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: LineupTheme.of(context).elevatedSurface,
            border: Border.all(color: LineupTheme.of(context).defaultBorder),
          ),
          child: const Icon(Icons.volume_up_outlined, size: 54),
        ),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: const Text(
            'Output devices, passthrough, and native capability controls remain hidden until the Windows player can report and consume them accurately.',
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 28),
        FilledButton(
          autofocus: true,
          onPressed: widget.controller.busy
              ? null
              : widget.controller.completeAudioSetup,
          child: const Text('Continue'),
        ),
      ],
    ),
  );

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

class _OnboardingPanel extends StatelessWidget {
  const _OnboardingPanel({
    required this.busy,
    required this.error,
    required this.child,
    super.key,
  });
  final bool busy;
  final String? error;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 38),
    decoration: BoxDecoration(
      color: LineupTheme.of(context).primarySurface,
      borderRadius: BorderRadius.circular(LineupTheme.of(context).panelRadius),
      border: Border(
        bottom: BorderSide(color: LineupTheme.of(context).defaultBorder),
      ),
    ),
    child: Column(
      children: [
        Image.asset('assets/branding/lineup-logo-mark.png', height: 62),
        if (busy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(semanticsLabel: 'Working'),
        ],
        if (error != null) ...[
          const SizedBox(height: 16),
          LineupNotice(message: error!),
        ],
        const SizedBox(height: 18),
        child,
      ],
    ),
  );
}

class _HeroContent extends StatelessWidget {
  const _HeroContent({
    required this.title,
    required this.subtitle,
    required this.child,
    this.step,
    this.compact = false,
  });
  final String title;
  final String subtitle;
  final String? step;
  final bool compact;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Semantics(
        header: true,
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      if (step != null) ...[
        const SizedBox(height: 8),
        Text(
          step!,
          style: TextStyle(color: LineupTheme.of(context).progressFill),
        ),
      ],
      const SizedBox(height: 10),
      Text(
        subtitle,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(color: LineupTheme.of(context).secondaryText),
      ),
      SizedBox(height: compact ? 16 : 30),
      child,
    ],
  );
}

class _PinCell extends StatelessWidget {
  const _PinCell(this.character);
  final String character;
  @override
  Widget build(BuildContext context) => Container(
    width: 76,
    height: 84,
    margin: const EdgeInsets.symmetric(horizontal: 7),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: LineupTheme.of(context).elevatedSurface,
      borderRadius: BorderRadius.circular(40),
      border: Border.all(color: LineupTheme.of(context).focusBorder, width: 2),
    ),
    child: Text(
      character,
      style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800),
    ),
  );
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
  int get _badgeCount => [
    user.protected,
    user.admin,
    user.restricted == true,
    active,
  ].where((visible) => visible).length;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 140,
    height: switch (_badgeCount) {
      > 3 => 250,
      > 2 => 222,
      _ => 184,
    },
    child: LineupSelectionCard(
      selected: false,
      autofocus: autofocus,
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 42,
              backgroundImage: user.thumb?.isAbsolute == true
                  ? NetworkImage(user.thumb.toString())
                  : null,
              child: user.thumb?.isAbsolute == true
                  ? null
                  : Text(
                      user.name.characters.first.toUpperCase(),
                      style: const TextStyle(fontSize: 30),
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              user.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            if (user.protected ||
                user.admin ||
                user.restricted == true ||
                active)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 3,
                  runSpacing: 3,
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
  );
}

class _ProfileBadge extends StatelessWidget {
  const _ProfileBadge(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: LineupTheme.of(context).elevatedSurface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: LineupTheme.of(context).subtleBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: LineupTheme.of(context).secondaryText,
            fontSize: 10,
          ),
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
  });
  final PlexServer server;
  final PlexConnection? connection;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    final availableKinds = server.connections.map(plexConnectionKind).toSet();
    final availability = [
      for (final kind in PlexConnectionKind.values)
        if (availableKinds.contains(kind))
          '${plexConnectionKindLabel(kind)} available',
    ];
    final action = connection == null ? 'Connect' : 'Reconnect';
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.dns_outlined, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(server.owned ? 'Owned server' : 'Shared server'),
                  if (availability.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final label in availability)
                          Chip(
                            visualDensity: const VisualDensity(
                              horizontal: -4,
                              vertical: -4,
                            ),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            label: Text(label),
                          ),
                      ],
                    ),
                  ],
                  if (connection != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Selected connection: ${plexConnectionDescription(connection!)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            MergeSemantics(
              child: Semantics(
                label: '$action to ${server.name}',
                child: FilledButton(
                  onPressed: onPressed,
                  child: ExcludeSemantics(child: Text(action)),
                ),
              ),
            ),
          ],
        ),
      ),
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
    if (!_submitting &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _pin.isNotEmpty) {
      setState(() {
        _error = null;
        _pin = _pin.substring(0, _pin.length - 1);
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
        alignment: Alignment.bottomCenter,
        insetPadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          side: BorderSide(color: LineupTheme.of(context).defaultBorder),
        ),
        child: ConstrainedBox(
          key: const Key('profile-pin-surface'),
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: LineupTheme.of(context).focusBorder
                          .withValues(alpha: 0.45),
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 28,
                    backgroundImage: widget.user.thumb?.isAbsolute == true
                        ? NetworkImage(widget.user.thumb.toString())
                        : null,
                    child: widget.user.thumb?.isAbsolute == true
                        ? null
                        : Text(
                            widget.user.name.characters.first.toUpperCase(),
                            style: const TextStyle(fontSize: 22),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Enter PIN for ${widget.user.name}',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
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
                            width: 22,
                            height: 22,
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: index < _pin.length
                                  ? LineupTheme.of(context).progressFill
                                  : Colors.transparent,
                              border: Border.all(
                                color: LineupTheme.of(context).focusBorder,
                                width: 2,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 236,
                  child: GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 3,
                    childAspectRatio: 1,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    children: [
                      for (var digit = 1; digit <= 9; digit++)
                        _PinKey(
                          digit: digit,
                          focusNode: digit == 1 ? _firstDigitFocus : null,
                          autofocus: digit == 1,
                          onPressed: _submitting ? null : () => _digit(digit),
                        ),
                      _PinControlKey(
                        tooltip: 'Backspace',
                        onPressed: _submitting || _pin.isEmpty
                            ? null
                            : () => setState(() {
                                _error = null;
                                _pin = _pin.substring(0, _pin.length - 1);
                              }),
                        child: const Icon(Icons.backspace_outlined),
                      ),
                      _PinKey(
                        digit: 0,
                        onPressed: _submitting ? null : () => _digit(0),
                      ),
                      _PinControlKey(
                        tooltip: 'Cancel',
                        onPressed: _submitting
                            ? null
                            : () => Navigator.pop(context),
                        child: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 22,
                  child: _submitting
                      ? Semantics(
                          label: 'Checking PIN',
                          child: const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _error == null
                      ? null
                      : Semantics(
                          key: const Key('profile-pin-error'),
                          container: true,
                          liveRegion: true,
                          label: _error,
                          child: ExcludeSemantics(
                            child: Text(
                              _error!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
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
    shape: const WidgetStatePropertyAll(CircleBorder()),
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
            ? roles.focusBorderWidth
            : 1,
      ),
    ),
    overlayColor: WidgetStatePropertyAll(
      roles.progressFill.withValues(alpha: 0.12),
    ),
  );
}
