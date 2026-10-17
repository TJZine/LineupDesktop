import '../channels/channel.dart';
import '../channels/content_resolver.dart';
import '../plex/plex_models.dart';

/// Identity of one appearance, including repeated persisted media IDs.
final class ManualOccurrence {
  ManualOccurrence._(this._item, this.occurrence);
  ChannelItem _item;
  final int occurrence;
  String get id => _item.id;
  ChannelItem get item => _item;
}

/// Owns ordered occurrences, retained snapshots, and the last addition's undo.
final class ManualRundown {
  final _entries = <ManualOccurrence>[];
  final _keyCounts = <String, int>{};
  final _undo = <ManualOccurrence>{};

  List<ManualOccurrence> get occurrences => List.unmodifiable(_entries);
  bool get canUndo => _undo.isNotEmpty;
  List<ChannelItem> get snapshotItems =>
      _entries.map((entry) => entry.item).toList(growable: false);

  void replaceFrom(Iterable<ChannelItem> items) {
    _entries.clear();
    _keyCounts.clear();
    _undo.clear();
    _entries.addAll(items.map(_create));
  }

  ManualOccurrence _create(ChannelItem item) {
    final count = (_keyCounts[item.id] ?? 0) + 1;
    _keyCounts[item.id] = count;
    return ManualOccurrence._(item, count);
  }

  void addCurrent(String id, Map<String, PlexMediaItem> available) {
    final item = available[id];
    if (item == null) return;
    final entry = _create(channelItemFor(item));
    _entries.add(entry);
    _undo
      ..clear()
      ..add(entry);
  }

  void addBatch(
    Iterable<String> ids,
    Map<String, PlexMediaItem> available,
    Map<String, PlexMediaItem> captured,
  ) {
    _undo.clear();
    for (final id in ids) {
      if (_entries.any((entry) => entry.id == id)) continue;
      final item = available[id] ?? captured[id];
      if (item == null) continue;
      final entry = _create(channelItemFor(item));
      _entries.add(entry);
      _undo.add(entry);
    }
  }

  void undoLastAddition() {
    _entries.removeWhere(_undo.contains);
    _undo.clear();
  }

  void move(ManualOccurrence entry, int delta) {
    final from = _entries.indexOf(entry);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= _entries.length) return;
    reorder(from, to);
  }

  void moveTo(ManualOccurrence entry, int index, {required bool after}) {
    final from = _entries.indexOf(entry);
    if (from < 0) return;
    _entries.removeAt(from);
    var destination = index;
    if (from < destination) destination--;
    if (after) destination++;
    _entries.insert(destination.clamp(0, _entries.length), entry);
  }

  void reorder(int from, int to) {
    final entry = _entries.removeAt(from);
    _entries.insert(to, entry);
  }

  void remove(ManualOccurrence entry) {
    _entries.remove(entry);
    _undo.remove(entry);
  }

  List<ChannelItem> resolvedItems(Map<String, PlexMediaItem> available) =>
      _entries
          .map((entry) {
            final current = available[entry.id];
            return current == null ? entry.item : channelItemFor(current);
          })
          .toList(growable: false);

  /// A save of another active source cannot overwrite the retained draft.
  void acceptSaved(List<ChannelItem> items) {
    if (items.length != _entries.length) return;
    for (var index = 0; index < items.length; index++) {
      _entries[index]._item = items[index];
    }
  }
}
