import 'package:flutter/material.dart';

import '../playback/native_player.dart';
import '../ui/empty_feature_view.dart';

class LineupShell extends StatefulWidget {
  const LineupShell({required this.player, super.key});

  final NativePlayer player;

  @override
  State<LineupShell> createState() => _LineupShellState();
}

class _LineupShellState extends State<LineupShell> {
  int _selectedIndex = 0;

  static const _destinations = <_Destination>[
    _Destination(
      'Guide',
      Icons.live_tv_outlined,
      Icons.live_tv,
      'Your guide is ready for setup',
      'Connect a Plex server and create a channel to build your schedule.',
    ),
    _Destination(
      'Channels',
      Icons.view_list_outlined,
      Icons.view_list,
      'No channels yet',
      'Channel creation will arrive after Plex connection and scheduling are implemented.',
    ),
    _Destination(
      'Settings',
      Icons.settings_outlined,
      Icons.settings,
      'Settings are not available yet',
      'Secure Plex connection and playback preferences are the next application foundations.',
    ),
    _Destination(
      'Diagnostics',
      Icons.monitor_heart_outlined,
      Icons.monitor_heart,
      'Diagnostics foundation',
      'Runtime diagnostics will be added with redaction before network and native playback work.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final destination = _destinations[_selectedIndex];
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) =>
                  setState(() => _selectedIndex = index),
              extended: MediaQuery.sizeOf(context).width >= 1040,
              leading: const Padding(
                padding: EdgeInsets.fromLTRB(12, 16, 12, 28),
                child: _Brand(),
              ),
              destinations: [
                for (final item in _destinations)
                  NavigationRailDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selectedIcon),
                    label: Text(item.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: EmptyFeatureView(
                key: ValueKey(destination.label),
                section: destination.label,
                title: destination.title,
                description: destination.description,
                icon: destination.selectedIcon,
                status: widget.player.status,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Semantics(
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
          if (MediaQuery.sizeOf(context).width >= 1040) ...[
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
}

class _Destination {
  const _Destination(
    this.label,
    this.icon,
    this.selectedIcon,
    this.title,
    this.description,
  );

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String title;
  final String description;
}
