import 'channel.dart';
import 'channel_builder.dart';

enum ChannelFilterGroup { all, favourites, sourceType, library }

typedef ChannelFilterKey = ({ChannelFilterGroup group, String? value});

typedef ChannelFilterEntry = ({ChannelFilterKey key, String label, int count});

const _sourceTypes = <BuilderStrategy, String>{
  BuilderStrategy.collections: 'Collections',
  BuilderStrategy.recentlyAdded: 'Recently added',
  BuilderStrategy.genres: 'Genres',
  BuilderStrategy.studios: 'Studios',
  BuilderStrategy.actors: 'Actors',
  BuilderStrategy.decades: 'Decades',
  BuilderStrategy.directors: 'Directors',
  BuilderStrategy.playlists: 'Playlists',
};

BuilderStrategy? channelSourceType(Channel channel) =>
    channel.builderKey == null ? null : _generatedSourceType(channel.source);

BuilderStrategy? _generatedSourceType(ContentSource source) {
  switch (source) {
    case PlaylistSource():
      return BuilderStrategy.playlists;
    case MixedSource(:final sources):
      return sources.map(_generatedSourceType).nonNulls.firstOrNull;
    case LibrarySource(:final filters, :final order):
      if (order == LibraryOrder.addedDescending) {
        return BuilderStrategy.recentlyAdded;
      }
      return switch (filters.keys.firstOrNull) {
        LibraryFilter.collection => BuilderStrategy.collections,
        LibraryFilter.genre => BuilderStrategy.genres,
        LibraryFilter.studio => BuilderStrategy.studios,
        LibraryFilter.actor => BuilderStrategy.actors,
        LibraryFilter.decade => BuilderStrategy.decades,
        LibraryFilter.director => BuilderStrategy.directors,
        null => null,
      };
    case ManualSource():
      return null;
  }
}

/// A snapshot of the channels and their filter choices, in presentation order.
class ChannelFilter {
  ChannelFilter(Iterable<Channel> channels) {
    final snapshot = List<Channel>.unmodifiable(channels);
    void add(ChannelFilterKey key, String label, Iterable<Channel> matches) {
      final rows = List<Channel>.unmodifiable(matches);
      if (rows.isEmpty && key != all) return;
      _matches[key] = rows;
      _entries.add((key: key, label: label, count: rows.length));
    }

    add(all, 'All channels', snapshot);
    add(
      favourites,
      'Favourites',
      snapshot.where((channel) => channel.favorite),
    );
    final byType = <BuilderStrategy?, List<Channel>>{};
    final byLibrary = <String, List<Channel>>{};
    final libraries = <String, String>{};
    for (final channel in snapshot) {
      final sourceType = channelSourceType(channel);
      if (channel.builderKey == null || sourceType != null) {
        (byType[sourceType] ??= []).add(channel);
      }
      for (final library in channel.sourceLibraries.entries) {
        libraries[library.key] = library.value;
        (byLibrary[library.key] ??= []).add(channel);
      }
    }
    for (final type in _sourceTypes.entries) {
      add(
        (group: ChannelFilterGroup.sourceType, value: type.key.name),
        type.value,
        byType[type.key] ?? const [],
      );
    }
    add(
      (group: ChannelFilterGroup.sourceType, value: 'custom'),
      'Custom',
      byType[null] ?? const [],
    );
    final libraryEntries = libraries.entries.toList()
      ..sort((a, b) {
        final name = a.value.toLowerCase().compareTo(b.value.toLowerCase());
        return name != 0 ? name : a.key.compareTo(b.key);
      });
    for (final library in libraryEntries) {
      add(
        (group: ChannelFilterGroup.library, value: library.key),
        library.value,
        byLibrary[library.key]!,
      );
    }
  }

  static const ChannelFilterKey all = (
    group: ChannelFilterGroup.all,
    value: null,
  );
  static const ChannelFilterKey favourites = (
    group: ChannelFilterGroup.favourites,
    value: null,
  );

  final _entries = <ChannelFilterEntry>[];
  final _matches = <ChannelFilterKey, List<Channel>>{};

  List<ChannelFilterEntry> get entries => List.unmodifiable(_entries);

  /// A selection that disappeared from the lineup falls back to All channels.
  List<Channel> channelsFor(ChannelFilterKey key) =>
      _matches[key] ?? _matches[all]!;
}
