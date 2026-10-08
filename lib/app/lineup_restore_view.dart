import 'package:flutter/material.dart';

import '../plex/plex_models.dart';
import '../ui/app_theme.dart';
import '../ui/app_ui.dart';
import 'lineup_controller.dart';
import 'setup_result_atmosphere.dart';

/// Saved-lineup restoration is a loading moment, separate from setup choices.
class LineupRestoreView extends StatelessWidget {
  const LineupRestoreView({required this.controller, super.key});

  final LineupController controller;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    return Scaffold(
      body: Material(
        color: roles.deepBackground,
        child: SetupResultAtmosphere(
          applying: true,
          failed: false,
          child: SafeArea(
            child: Column(
              children: [
                const LineupTopBar(divider: false),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Loading your lineup…',
                                  textAlign: TextAlign.center,
                                  style: LineupTypography.pageTitle.copyWith(
                                    color: roles.primaryText,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                LibraryScanPhaseStatus(controller: controller),
                                const SizedBox(height: 32),
                                TextButton(
                                  key: const ValueKey('restore-switch-server'),
                                  onPressed: controller.canSwitchServer
                                      ? controller.showServers
                                      : null,
                                  child: const Text('Switch server'),
                                ),
                              ],
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
    );
  }
}

/// Counts remain visible; the stable live-region label changes only with phase.
class LibraryScanPhaseStatus extends StatelessWidget {
  const LibraryScanPhaseStatus({
    required this.controller,
    this.centered = true,
    super.key,
  });

  final LineupController controller;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final phase = controller.libraryScanPhase;
    final playlist = controller.playlistScanProgress;
    final label = playlist != null
        ? playlist.totalPlaylists == null
              ? 'Finding playlists'
              : 'Loading playlists'
        : switch (phase) {
            PlexLibraryScanPhase.items => 'Checking items',
            PlexLibraryScanPhase.collections => 'Loading collections',
            PlexLibraryScanPhase.showGenres => 'Loading show details',
          };
    final count = _formatCount(controller.libraryScanCompletedItems);
    final total = controller.libraryScanTotalItems;
    final text = playlist != null
        ? '$label${playlist.totalPlaylists == null ? '' : ' · ${_formatCount(playlist.completedPlaylists)} of ${_formatCount(playlist.totalPlaylists!)}'}'
        : phase == PlexLibraryScanPhase.items
        ? '$label · $count${total == null ? '' : ' of ${_formatCount(total)}'}'
        : label;
    return Semantics(
      key: const ValueKey('library-scan-phase'),
      liveRegion: true,
      label: label,
      excludeSemantics: true,
      child: Text(
        text,
        textAlign: centered ? TextAlign.center : TextAlign.start,
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
          color: LineupTheme.of(context).secondaryText,
          fontSize: 18,
          height: 1.4,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

String _formatCount(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (match) => '${match[1]},',
);
