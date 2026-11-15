part of '../channel_studio_view.dart';

_FacetOptions _studioFacetOptions(
  String? libraryId, {
  required Iterable<PlexMediaItem> inventory,
}) {
  final values = {for (final key in _facetKeys) key: <String>{}};
  final labels = {for (final key in _facetKeys) key: <String, String>{}};
  void add(String key, String raw) {
    final filter = _libraryFilter(key);
    final identity = canonicalFilterIdentity(filter, raw);
    if (identity.isEmpty) return;
    final label = raw.trim();
    values[key]!.add(identity);
    labels[key]!.update(
      identity,
      (current) => _preferredFacetLabel(filter, current, label),
      ifAbsent: () => label,
    );
  }

  for (final item in inventory.where(
    (item) => libraryId == null || item.libraryId == libraryId,
  )) {
    if (item.libraryId != null) {
      for (final value in item.collections) {
        add('collection', value);
      }
    }
    for (final value in item.genres) {
      add('genre', value);
    }
    if (item.studio case final studio? when studio.isNotEmpty) {
      add('studio', studio);
    }
    for (final value in item.actors) {
      add('actor', value);
    }
    for (final value in item.directors) {
      add('director', value);
    }
    if (channelDecadeForYear(item.year) case final decade?) {
      add('decade', decade);
    }
  }
  return (
    values: {
      for (final entry in values.entries)
        entry.key: entry.value.toList()..sort(),
    },
    labels: {
      for (final entry in labels.entries)
        entry.key: Map<String, String>.unmodifiable(entry.value),
    },
  );
}

List<PlexMediaItem> _studioFilteredInventory({
  required Iterable<PlexMediaItem> inventory,
  String? libraryId,
  String? mediaType,
  Map<LibraryFilter, List<String>> filters = const {},
  String search = '',
  bool includeWatched = true,
}) {
  final query = search.trim().toLowerCase();
  var items = inventory.where(
    (item) =>
        (libraryId == null || item.libraryId == libraryId) &&
        (includeWatched || !item.viewed) &&
        (mediaType == null || item.type == mediaType) &&
        (query.isEmpty ||
            item.title.toLowerCase().contains(query) ||
            (item.grandparentTitle?.toLowerCase().contains(query) ?? false)),
  );
  items = items.where((item) => matchesLibraryFacets(item, filters));
  return items.toList(growable: false);
}

/// Reattaches inventory display labels to case-insensitive person identities.
class StudioPersonLabels {
  List<PlexMediaItem>? _inventory;
  final _labels = <(String?, LibraryFilter, String), String>{};

  String label(
    LineupController controller,
    String libraryId,
    LibraryFilter filter,
    String value,
  ) {
    if (filter != LibraryFilter.actor && filter != LibraryFilter.director) {
      return value;
    }
    final inventory = controller.playableInventory.media;
    if (!identical(inventory, _inventory)) {
      _inventory = inventory;
      _labels.clear();
      for (final item in inventory) {
        for (final (key, people) in [
          (LibraryFilter.actor, item.actors),
          (LibraryFilter.director, item.directors),
        ]) {
          for (final name in people) {
            final identity = canonicalFilterIdentity(key, name);
            if (identity.isEmpty) continue;
            final display = name.trim();
            _labels.update(
              (item.libraryId, key, identity),
              (current) => _preferredFacetLabel(key, current, display),
              ifAbsent: () => display,
            );
          }
        }
      }
    }
    return _labels[(
          libraryId,
          filter,
          canonicalFilterIdentity(filter, value),
        )] ??
        value;
  }
}
