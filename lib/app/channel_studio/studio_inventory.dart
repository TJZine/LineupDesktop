part of '../channel_studio_view.dart';

class _StudioInventoryStatus extends StatelessWidget {
  const _StudioInventoryStatus({
    required this.status,
    required this.totalItems,
    required this.completedItems,
    required this.hasInventory,
    required this.saving,
    required this.onGenerate,
  });
  final LibraryScanStatus status;
  final int? totalItems;
  final int completedItems;
  final bool hasInventory;
  final bool saving;
  final Future<void> Function() onGenerate;
  @override
  Widget build(BuildContext context) {
    if (status == LibraryScanStatus.scanning) {
      final total = totalItems;
      return Semantics(
        key: const Key('studio-inventory-status'),
        liveRegion: true,
        container: true,
        child: Text(
          total == null
              ? 'Loading programming: $completedItems items loaded.'
              : 'Loading programming: $completedItems of $total items loaded.',
        ),
      );
    }
    if (status == LibraryScanStatus.cancelled ||
        status == LibraryScanStatus.transientFailure) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            key: const Key('studio-inventory-status'),
            liveRegion: true,
            container: true,
            child: Text(
              status == LibraryScanStatus.cancelled
                  ? 'Library loading was cancelled. The last usable programming and this draft were preserved.'
                  : 'Library loading failed. The last usable programming and this draft were preserved.',
            ),
          ),
          LineupInlineLink(
            onPressed: saving ? null : onGenerate,
            child: const Text('Retry in Generate lineup'),
          ),
        ],
      );
    }
    if (!hasInventory) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'No usable programming is loaded. A new channel needs a selected Plex movie/show library or video playlist.',
          ),
          LineupInlineLink(
            onPressed: saving ? null : onGenerate,
            child: const Text('Open Generate lineup'),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}
