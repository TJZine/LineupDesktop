import '../plex/plex_models.dart';
import 'channel.dart';

String? channelDecadeForYear(int? year) {
  if (year == null || year < 1000 || year > 9999) return null;
  return '${year ~/ 10 * 10}s';
}

List<String> libraryFacetValues(PlexMediaItem item, LibraryFilter filter) =>
    switch (filter) {
      LibraryFilter.genre => item.genres,
      LibraryFilter.collection => item.collections,
      LibraryFilter.studio => [if (item.studio != null) item.studio!],
      LibraryFilter.actor => item.actors,
      LibraryFilter.director => item.directors,
      LibraryFilter.decade => [?channelDecadeForYear(item.year)],
    };

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
      LibraryFilter.actor => _matchesPeople(
        libraryFacetValues(item, entry.key),
        values,
        entry.key,
      ),
      LibraryFilter.director => _matchesPeople(
        libraryFacetValues(item, entry.key),
        values,
        entry.key,
      ),
      _ => libraryFacetValues(item, entry.key).any(values.contains),
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
