import '../plex/plex_models.dart';
import 'channel.dart';

List<ChannelItem> resolveContent(
  ContentSource source,
  List<PlexMediaItem> media,
) {
  final resolved = switch (source) {
    LibrarySource source => _library(source, media),
    ManualSource(:final items) => List<ChannelItem>.of(items),
    MixedSource(:final sources, :final interleave) =>
      interleave
          ? _interleave(
              sources.map((source) => resolveContent(source, media)).toList(),
            )
          : [for (final source in sources) ...resolveContent(source, media)],
  };
  return List.unmodifiable(resolved);
}

List<ChannelItem> _library(LibrarySource source, List<PlexMediaItem> media) {
  var items = media.where((item) => item.libraryId == source.libraryId);
  if (!source.includeWatched) items = items.where((item) => !item.viewed);
  for (final filter in source.filters.entries) {
    items = switch (filter.key) {
      'genre' => items.where((item) => item.genres.contains(filter.value)),
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
      .map((item) => item.toChannelItem(null))
      .toList();
}

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
