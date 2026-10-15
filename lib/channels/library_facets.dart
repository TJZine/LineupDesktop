import '../plex/plex_models.dart';
import 'channel.dart';

String? channelDecadeForYear(int? year) {
  if (year == null || year < 1000 || year > 9999) return null;
  return '${year ~/ 10 * 10}s';
}

/// OR within each facet, AND across facets. Empty selections do not constrain
/// inventory. Source validation and inventory/order policy stay with callers.
bool matchesLibraryFacets(
  PlexMediaItem item,
  Map<LibraryFilter, List<String>> filters,
) {
  for (final entry in filters.entries) {
    if (entry.value.isEmpty) continue;
    final values = entry.value;
    final matches = switch (entry.key) {
      LibraryFilter.genre => item.genres.any(values.contains),
      LibraryFilter.collection => item.collections.any(values.contains),
      LibraryFilter.studio => values.contains(item.studio),
      LibraryFilter.actor => _matchesPeople(item.actors, values, entry.key),
      LibraryFilter.director => _matchesPeople(
        item.directors,
        values,
        entry.key,
      ),
      LibraryFilter.decade => values.contains(channelDecadeForYear(item.year)),
    };
    if (!matches) return false;
  }
  return true;
}

bool _matchesPeople(
  List<String> people,
  List<String> selected,
  LibraryFilter filter,
) => people.any(
  (person) => selected.any(
    (value) =>
        canonicalFilterIdentity(filter, person) ==
        canonicalFilterIdentity(filter, value),
  ),
);
