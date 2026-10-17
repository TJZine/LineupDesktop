part of '../channel_studio_view.dart';

class _StudioPlaylist extends StatelessWidget {
  const _StudioPlaylist({
    required this.playlists,
    required this.selectedId,
    required this.otherUses,
    required this.saving,
    required this.inventoryStatus,
    required this.sourceExplanation,
    required this.onChanged,
    required this.onOpenChannel,
  });
  final List<PlexPlaylist> playlists;
  final String? selectedId;
  final Iterable<Channel> otherUses;
  final bool saving;
  final Widget inventoryStatus;
  final String? sourceExplanation;
  final ValueChanged<String?> onChanged;
  final Future<void> Function(Channel)? onOpenChannel;
  @override
  Widget build(BuildContext context) {
    final available = playlists;
    final selected = available.any((playlist) => playlist.id == selectedId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        inventoryStatus,
        const Text(
          'Uses an existing Plex playlist. Manage its contents in Plex.',
        ),

        LineupField(
          label: 'Video playlist',
          child: lineupDropdownField<String>(
            context: context,
            key: const Key('studio-playlist'),
            isExpanded: true,
            iconSize: 24,
            itemHeight: null,
            initialValue: selected ? selectedId : null,
            decoration: const InputDecoration(),
            items: [
              for (final playlist in available)
                DropdownMenuItem(
                  value: playlist.id,
                  child: Text(playlist.title),
                ),
            ],
            onChanged: saving ? null : onChanged,
          ),
        ),
        _studioSourceExplanation(context, sourceExplanation),
        if (otherUses.isNotEmpty) ...[
          SizedBox(height: 8),
          const Text('Also used by'),
          for (final channel in otherUses)
            ListTile(
              contentPadding: EdgeInsets.zero,
              minTileHeight: null,
              title: Text('${channel.number} · ${channel.name}'),
              trailing: TextButton(
                onPressed: saving || onOpenChannel == null
                    ? null
                    : () => onOpenChannel!(channel),
                child: const Text('Open channel'),
              ),
            ),
        ],
      ],
    );
  }
}
