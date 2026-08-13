import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../plex/plex_models.dart';
import '../ui/app_theme.dart';
import '../ui/app_ui.dart';
import 'lineup_controller.dart';

class UpstreamOnboardingView extends StatefulWidget {
  const UpstreamOnboardingView({required this.controller, super.key});

  final LineupController controller;

  @override
  State<UpstreamOnboardingView> createState() => _UpstreamOnboardingViewState();
}

class _UpstreamOnboardingViewState extends State<UpstreamOnboardingView> {
  Timer? _clock;
  bool? _externalAudio;
  bool _audioFallback = true;

  @override
  void initState() {
    super.initState();
    _externalAudio = widget.controller.settings.audioSetupComplete
        ? widget.controller.settings.audioPassthrough
        : null;
    _audioFallback = widget.controller.settings.directPlayAudioFallback;
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.controller.stage == SetupStage.linking) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.6, -0.65),
          radius: 1.25,
          colors: [Color(0x1428C8A0), LineupTheme.obsidian],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              key: const ValueKey('onboarding-content'),
              constraints: const BoxConstraints(maxWidth: 1180),
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

  Widget _welcome() => _HeroContent(
    title: 'Your Plex library, scheduled like television',
    subtitle: 'Link Plex once, choose who is watching, then tune Lineup to your server.',
    child: FilledButton.icon(
      autofocus: true,
      onPressed: widget.controller.busy ? null : widget.controller.startLinking,
      icon: const Icon(Icons.link),
      label: const Text('Sign in to Plex'),
    ),
  );

  Widget _linking() {
    final pin = widget.controller.activePin;
    final remaining = pin == null
        ? Duration.zero
        : pin.expiresAt.difference(DateTime.now());
    final seconds = remaining.inSeconds.clamp(0, 3599);
    final time =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    final code = (pin?.code ?? '----').padRight(4, '-').substring(0, 4);
    return _HeroContent(
      title: 'Sign in to Plex',
      subtitle: 'Scan the QR code or visit plex.tv/link',
      child: Column(
        children: [
          const SizedBox(height: 16),
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
          const SizedBox(height: 28),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton(
                autofocus: pin == null,
                onPressed: widget.controller.busy
                    ? null
                    : widget.controller.startLinking,
                child: Text(pin == null ? 'Request PIN' : 'Request a new code'),
              ),
              if (pin != null)
                TextButton(
                  onPressed: widget.controller.cancelLinking,
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
    child: Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 24,
          runSpacing: 24,
          children: [
            for (final user in widget.controller.profiles)
              _ProfileCard(
                user: user,
                autofocus: user == widget.controller.profiles.first,
                onPressed: widget.controller.busy
                    ? null
                    : () => _selectProfile(user),
              ),
          ],
        ),
        const SizedBox(height: 28),
        OutlinedButton.icon(
          onPressed: widget.controller.busy ? null : widget.controller.logout,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
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
          ],
        ),
      ],
    ),
  );

  Widget _audio() => _HeroContent(
    title: 'Audio Setup',
    step: 'Step 2 of 3',
    subtitle: 'Do you have an external sound system?',
    child: Column(
      children: [
        Wrap(
          spacing: 24,
          runSpacing: 20,
          alignment: WrapAlignment.center,
          children: [
            _AudioChoice(
              icon: Icons.speaker_group_outlined,
              title: 'Yes, I have a soundbar or receiver',
              subtitle: 'Connected via HDMI eARC',
              selected: _externalAudio == true,
              autofocus: true,
              onPressed: () => setState(() => _externalAudio = true),
            ),
            _AudioChoice(
              icon: Icons.tv,
              title: 'No, using TV speakers',
              subtitle:
                  'Best for built-in speakers. Turns off passthrough intent.',
              selected: _externalAudio == false,
              onPressed: () => setState(() => _externalAudio = false),
            ),
          ],
        ),
        const SizedBox(height: 28),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'ADVANCED',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2),
          ),
        ),
        SwitchListTile(
          value: _audioFallback,
          title: const Text('Direct Play Audio Fallback'),
          subtitle: const Text(
            'Allow a compatible audio track instead of transcoding. Recommended for most users.',
          ),
          onChanged: (value) => setState(() => _audioFallback = value),
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _externalAudio == null || widget.controller.busy
              ? null
              : () async => widget.controller.completeAudioSetup(
                  externalAudio: _externalAudio!,
                  directPlayFallback: _audioFallback,
                ),
          child: const Text('Continue'),
        ),
      ],
    ),
  );

  Future<void> _selectProfile(PlexHomeUser user) async {
    if (!user.protected) return widget.controller.selectProfile(user);
    final pin = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProfilePinDialog(user: user),
    );
    if (pin != null) await widget.controller.selectProfile(user, pin: pin);
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
      color: Colors.white.withValues(alpha: 0.035),
      borderRadius: BorderRadius.circular(16),
      border: Border(
        bottom: BorderSide(color: LineupTheme.brass.withValues(alpha: 0.12)),
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
  });
  final String title;
  final String subtitle;
  final String? step;
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
        Text(step!, style: const TextStyle(color: LineupTheme.brass)),
      ],
      const SizedBox(height: 10),
      Text(
        subtitle,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(color: Colors.white60),
      ),
      const SizedBox(height: 30),
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
      color: Colors.white.withValues(alpha: 0.045),
      borderRadius: BorderRadius.circular(40),
      border: Border.all(
        color: LineupTheme.brass.withValues(alpha: 0.5),
        width: 2,
      ),
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
    required this.autofocus,
    required this.onPressed,
  });
  final PlexHomeUser user;
  final bool autofocus;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 178,
    height: 244,
    child: LineupSelectionCard(
      selected: false,
      autofocus: autofocus,
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 48,
              backgroundImage: user.thumb?.isAbsolute == true
                  ? NetworkImage(user.thumb.toString())
                  : null,
              child: user.thumb?.isAbsolute == true
                  ? null
                  : Text(
                      user.name.characters.first.toUpperCase(),
                      style: const TextStyle(fontSize: 34),
                    ),
            ),
            const SizedBox(height: 14),
            Text(
              user.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (user.protected)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Chip(
                  avatar: Icon(Icons.lock, size: 15),
                  label: Text('PIN'),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({required this.server, required this.onPressed});
  final PlexServer server;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      leading: const Icon(Icons.dns_outlined, size: 34),
      title: Text(
        server.name,
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${server.owned ? 'Owned server' : 'Shared server'} • ${server.connections.length} secure connection${server.connections.length == 1 ? '' : 's'}',
      ),
      trailing: FilledButton(
        onPressed: onPressed,
        child: const Text('Connect'),
      ),
    ),
  );
}

class _AudioChoice extends StatelessWidget {
  const _AudioChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onPressed,
    this.autofocus = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onPressed;
  final bool autofocus;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 360,
    height: 210,
    child: LineupSelectionCard(
      selected: selected,
      autofocus: autofocus,
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}

class _ProfilePinDialog extends StatefulWidget {
  const _ProfilePinDialog({required this.user});
  final PlexHomeUser user;
  @override
  State<_ProfilePinDialog> createState() => _ProfilePinDialogState();
}

class _ProfilePinDialogState extends State<_ProfilePinDialog> {
  String _pin = '';
  void _digit(int digit) {
    if (_pin.length >= 4) return;
    setState(() => _pin += '$digit');
    if (_pin.length == 4) Navigator.pop(context, _pin);
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
    if (event.logicalKey == LogicalKeyboardKey.backspace && _pin.isNotEmpty) {
      setState(() => _pin = _pin.substring(0, _pin.length - 1));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: _key,
    child: AlertDialog(
      title: Text('Enter PIN for ${widget.user.name}'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${List.filled(_pin.length, '●').join()}${List.filled(4 - _pin.length, '○').join()}',
              style: const TextStyle(fontSize: 30, letterSpacing: 12),
            ),
            const SizedBox(height: 18),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 3,
              childAspectRatio: 1.8,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: [
                for (var digit = 1; digit <= 9; digit++)
                  FilledButton(
                    onPressed: () => _digit(digit),
                    child: Text('$digit'),
                  ),
                IconButton(
                  tooltip: 'Backspace',
                  onPressed: _pin.isEmpty
                      ? null
                      : () => setState(
                          () => _pin = _pin.substring(0, _pin.length - 1),
                        ),
                  icon: const Icon(Icons.backspace_outlined),
                ),
                FilledButton(
                  onPressed: () => _digit(0),
                  child: const Text('0'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
