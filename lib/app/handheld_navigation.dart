import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../playback/player_coordinator.dart';
import '../playback/player_view.dart';
import '../ui/app_theme.dart';
import '../ui/app_ui.dart';
import '../ui/lineup_canvas.dart';
import 'navigation_shortcuts.dart';

/// Portrait-composition navigation. A selection is a destination, never a
/// pushed route, so changing tabs adds no Back history.
class HandheldTabBar extends StatelessWidget {
  const HandheldTabBar({
    required this.destination,
    required this.onSelect,
    super.key,
  });

  final ShellDestination destination;
  final ValueChanged<ShellDestination> onSelect;

  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(
    maxScaleFactor: 1.3,
    child: Builder(
      builder: (context) {
        final roles = LineupTheme.of(context);
        final selectedDestination = destination == ShellDestination.diagnostics
            ? ShellDestination.settings
            : destination;
        final growth = math.max(
          1.0,
          MediaQuery.textScalerOf(context).scale(14) / 14,
        );
        return ColoredBox(
          color: roles.primarySurface,
          child: SafeArea(
            top: false,
            child: SizedBox(
              key: const Key('handheld-tab-bar'),
              height: 78 * growth,
              child: Row(
                children: [
                  for (final tab in const [
                    (ShellDestination.guide, Icons.grid_view_rounded, 'Guide'),
                    (
                      ShellDestination.channels,
                      Icons.view_list_rounded,
                      'Channels',
                    ),
                    (
                      ShellDestination.settings,
                      Icons.settings_outlined,
                      'Settings',
                    ),
                  ])
                    Expanded(
                      child: Semantics(
                        selected: selectedDestination == tab.$1,
                        button: true,
                        label: tab.$3,
                        onTap: () => onSelect(tab.$1),
                        excludeSemantics: true,
                        child: TextButton(
                          key: ValueKey('handheld-tab-${tab.$1.name}'),
                          onPressed: () => onSelect(tab.$1),
                          style: TextButton.styleFrom(
                            minimumSize: Size(
                              0,
                              LineupCanvas.minimumTouchExtentOf(context),
                            ),
                            padding: EdgeInsets.zero,
                            foregroundColor: selectedDestination == tab.$1
                                ? roles.primaryText
                                : roles.mutedText,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 64,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: selectedDestination == tab.$1
                                      ? roles.selectedSurface
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(tab.$2, size: 24),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                tab.$3,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
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
  );
}

/// The existing coordinator and native output are shared with Guide and Player.
/// Mount only on Channels/Settings, replacing their background output. The
/// transparent thumbnail is the sole aperture; no Flutter fill covers it.
class HandheldMiniPlayer extends StatelessWidget {
  const HandheldMiniPlayer({
    required this.controller,
    required this.onOpenPlayer,
    super.key,
  });

  final PlayerCoordinator controller;
  final VoidCallback onOpenPlayer;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Builder(
        builder: (context) {
          final roles = LineupTheme.of(context);
          final growth = math.max(
            1.0,
            MediaQuery.textScalerOf(context).scale(17) / 17,
          );
          final channel = controller.currentChannel;
          final title =
              controller.currentProgram?.scheduled.item.title ?? 'Player';
          final channelLabel = channel == null
              ? ''
              : '${channel.number} · ${channel.name}';
          final pause = controller.playbackToggleWillPause;
          return SafeArea(
            top: false,
            bottom: false,
            child: SizedBox(
              key: const Key('handheld-mini-player'),
              height: 76 * growth,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: 'Open Player, $title, $channelLabel',
                      onTap: onOpenPlayer,
                      excludeSemantics: true,
                      child: InkWell(
                        key: const Key('handheld-mini-open'),
                        onTap: onOpenPlayer,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AspectRatio(
                              aspectRatio: 16 / 9,
                              child: PlayerSurface(controller: controller),
                            ),
                            Expanded(
                              child: ColoredBox(
                                color: roles.primarySurface,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w500,
                                          color: roles.primaryText,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        channelLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: roles.secondaryText,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  ColoredBox(
                    color: roles.primarySurface,
                    child: LineupTouchTarget(
                      onPressed: () => unawaited(controller.togglePlayback()),
                      child: IconButton(
                        key: const Key('handheld-mini-playback'),
                        tooltip: pause ? 'Pause' : 'Play',
                        onPressed: () => unawaited(controller.togglePlayback()),
                        icon: Icon(
                          pause
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
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
  );
}
