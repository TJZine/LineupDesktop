import '../plex/plex_models.dart';
import 'channel.dart';

List<ChannelItem> resolveContent(
  ContentSource source,
  List<PlexMediaItem> media, [
  List<PlexPlaylist> playlists = const [],
]) {
  final resolved = switch (source) {
    LibrarySource source => _library(source, media),
    ManualSource(:final items) => List<ChannelItem>.of(items),
    PlaylistSource(:final playlistId) =>
      playlists
          .where((playlist) => playlist.id == playlistId)
          .expand((playlist) => playlist.items)
          .map(channelItemFor)
          .toList(),
    MixedSource(:final sources, :final interleave) =>
      interleave
          ? _interleave(
              sources
                  .map((source) => resolveContent(source, media, playlists))
                  .toList(),
            )
          : [
              for (final source in sources)
                ...resolveContent(source, media, playlists),
            ],
  };
  return List.unmodifiable(resolved);
}

List<ChannelItem> _library(LibrarySource source, List<PlexMediaItem> media) {
  var items = media.where((item) => item.libraryId == source.libraryId);
  if (!source.includeWatched) items = items.where((item) => !item.viewed);
  for (final filter in source.filters.entries) {
    items = switch (filter.key) {
      'genre' => items.where((item) => item.genres.contains(filter.value)),
      'collection' => items.where(
        (item) => item.collections.contains(filter.value),
      ),
      'studio' => items.where((item) => item.studio == filter.value),
      'actor' => items.where((item) => item.actors.contains(filter.value)),
      'director' => items.where(
        (item) => item.directors.contains(filter.value),
      ),
      'decade' => items.where(
        (item) =>
            item.year != null && '${item.year! ~/ 10 * 10}s' == filter.value,
      ),
      'sort' when filter.value == 'added:desc' =>
        items.toList()..sort(
          (a, b) => (b.addedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(a.addedAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
        ),
      _ => items,
    };
  }
  return items
      .where((item) => item.duration > Duration.zero)
      .map(channelItemFor)
      .toList();
}

ChannelItem channelItemFor(PlexMediaItem item) => ChannelItem(
  id: item.id,
  title: item.title,
  duration: item.duration,
  showTitle: item.grandparentTitle,
  showThumb: item.grandparentThumbPath,
  artwork: _uriPath(item.thumbPath),
  backdrop: _uriPath(item.artPath),
  clearLogo: _uriPath(item.clearLogoPath),
  summary: item.summary,
  contentRating: item.contentRating,
  genres: item.genres,
  year: item.year,
  seasonNumber: item.seasonNumber,
  episodeNumber: item.episodeNumber,
  resolution: item.videoResolution,
  videoCodec: item.videoCodec,
  audioCodec: item.audioCodec,
  audioChannels: item.audioChannels,
  dynamicRange: item.dynamicRange.name,
);

Uri? _uriPath(String? path) =>
    path == null || path.isEmpty ? null : Uri.tryParse(path);

List<ChannelItem> _interleave(List<List<ChannelItem>> sources) {
  final output = <ChannelItem>[];
  final longest = sources.fold(
    0,
    (length, items) => items.length > length ? items.length : length,
  );
  for (var index = 0; index < longest; index++) {
    for (final source in sources) {
      if (index < source.length) output.add(source[index]);
    }
  }
  return output;
}
