import 'package:flutter/material.dart';

import '../playback/native_player.dart';

class EmptyFeatureView extends StatelessWidget {
  const EmptyFeatureView({
    required this.section,
    required this.title,
    required this.description,
    required this.icon,
    required this.status,
    super.key,
  });

  final String section;
  final String title;
  final String description;
  final IconData icon;
  final PlayerStatus status;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(section, style: Theme.of(context).textTheme.headlineMedium),
            const Spacer(),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(36),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 46,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 22),
                        Text(
                          title,
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(description, textAlign: TextAlign.center),
                        const SizedBox(height: 28),
                        Semantics(
                          label: 'Playback backend status: ${status.message}',
                          child: Chip(
                            avatar: const Icon(Icons.info_outline, size: 18),
                            label: Text(status.message),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(),
            Text(
              'Pre-MVP development build',
              style: Theme.of(context).textTheme.labelMedium,
              textAlign: TextAlign.end,
            ),
          ],
        ),
      ),
    );
  }
}
