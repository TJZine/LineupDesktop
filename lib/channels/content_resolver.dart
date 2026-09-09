import '../plex/plex_models.dart';
import 'channel.dart';

String? channelDecadeForYear(int? year) {
  if (year == null || year < 1000 || year > 9999) return null;
  return '${year ~/ 10 * 10}s';
}

String normalizePersonName(String value) => value.trim().toLowerCase();

List<ChannelItem> resolveContent(
  ContentSource source,
  List<PlexMediaItem> media, [
  List<PlexPlaylist> playlists = const [],
]) {
  final resolved = switch (source) {
    LibrarySource source => _library(source, media),
    ManualSource(:final items) => _manual(items, media, playlists),
    PlaylistSource(:final playlistId) =>
      playlists
          .where((playlist) => playlist.id == playlistId)
          .expand((playlist) => playlist.items)
          .where((item) => item.isPlayable)
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
    if (filter.value.isEmpty) continue;
    items = switch (filter.key) {
      LibraryFilter.genre => items.where(
        (item) => item.genres.any(filter.value.contains),
      ),
      LibraryFilter.collection => items.where(
        (item) => item.collections.any(filter.value.contains),
      ),
      LibraryFilter.studio => items.where(
        (item) => filter.value.contains(item.studio),
      ),
      LibraryFilter.actor => items.where(
        (item) => item.actors.any(
          (actor) => filter.value.any(
            (value) => normalizePersonName(actor) == normalizePersonName(value),
          ),
        ),
      ),
      LibraryFilter.director => items.where(
        (item) => item.directors.any(
          (director) => filter.value.any(
            (value) =>
                normalizePersonName(director) == normalizePersonName(value),
          ),
        ),
      ),
      LibraryFilter.decade
          when filter.value.every(RegExp(r'^\d{3}0s$').hasMatch) =>
        items.where(
          (item) => filter.value.contains(channelDecadeForYear(item.year)),
        ),
      LibraryFilter.decade => throw const FormatException(
        'Unsupported content filter',
      ),
    };
  }
  final unique = <String, PlexMediaItem>{};
  for (final item in items.where((item) => item.isPlayable)) {
    unique.putIfAbsent(item.id, () => item);
  }
  final ordered = unique.values.toList();
  switch (source.order) {
    case LibraryOrder.supplied:
      break;
    case LibraryOrder.addedDescending:
      ordered.sort((a, b) {
        final compared = _addedAt(b).compareTo(_addedAt(a));
        return compared != 0 ? compared : a.id.compareTo(b.id);
      });
    case LibraryOrder.title:
      ordered.sort(_libraryTitleOrder);
  }
  return ordered.map(channelItemFor).toList();
}

DateTime _addedAt(PlexMediaItem item) =>
    item.addedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

int _libraryTitleOrder(PlexMediaItem left, PlexMediaItem right) {
  final leftShow = left.grandparentTitle?.trim().toLowerCase();
  final rightShow = right.grandparentTitle?.trim().toLowerCase();
  final leftTitle = (leftShow?.isNotEmpty == true ? leftShow! : left.title)
      .toLowerCase();
  final rightTitle = (rightShow?.isNotEmpty == true ? rightShow! : right.title)
      .toLowerCase();
  var compared = leftTitle.compareTo(rightTitle);
  if (compared != 0) return compared;
  compared = (left.seasonNumber ?? 0x7fffffff).compareTo(
    right.seasonNumber ?? 0x7fffffff,
  );
  if (compared != 0) return compared;
  compared = (left.episodeNumber ?? 0x7fffffff).compareTo(
    right.episodeNumber ?? 0x7fffffff,
  );
  if (compared != 0) return compared;
  compared = left.title.toLowerCase().compareTo(right.title.toLowerCase());
  return compared != 0 ? compared : left.id.compareTo(right.id);
}

List<ChannelItem> _manual(
  List<ChannelItem> stored,
  List<PlexMediaItem> media,
  List<PlexPlaylist> playlists,
) {
  final current = playableMediaById(media, playlists);
  return [
    for (final item in stored)
      if (current[item.id] case final available?) channelItemFor(available),
  ];
}

Map<String, PlexMediaItem> playableMediaById(
  List<PlexMediaItem> media, [
  List<PlexPlaylist> playlists = const [],
]) {
  final current = <String, PlexMediaItem>{};
  for (final item in media) {
    if (item.isPlayable) current.putIfAbsent(item.id, () => item);
  }
  for (final playlist in playlists) {
    for (final item in playlist.items) {
      if (item.isPlayable) current.putIfAbsent(item.id, () => item);
    }
  }
  return Map.unmodifiable(current);
}

ChannelItem channelItemFor(PlexMediaItem item) => ChannelItem(
  id: item.id,
  title: item.title,
  duration: item.duration,
  showTitle: item.grandparentTitle,
  showThumb: canonicalPlexArtworkPathText(item.grandparentThumbPath),
  poster: _artworkPath(item.thumbPath),
  backdrop: _artworkPath(item.artPath),
  clearLogo: _artworkPath(item.clearLogoPath),
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
  cast: List.unmodifiable(
    item.cast.map(
      (member) => ChannelCastMember(
        name: member.name,
        role: member.role,
        portrait: canonicalPlexCastPortrait(
          member.thumbPath == null ? null : Uri.tryParse(member.thumbPath!),
        ),
      ),
    ),
  ),
  mediaKind: switch (item.type) {
    'movie' => ChannelMediaKind.movie,
    'episode' => ChannelMediaKind.episode,
    _ => ChannelMediaKind.unknown,
  },
  seriesId: item.type == 'episode' ? _seriesIdentity(item) : null,
);

String? _seriesIdentity(PlexMediaItem item) {
  final key = item.grandparentRatingKey?.trim();
  if (key?.isNotEmpty == true) return 'key:$key';
  final title = item.grandparentTitle?.trim();
  return title?.isNotEmpty == true ? 'title:${title!.toLowerCase()}' : null;
}

Uri? _artworkPath(String? path) =>
    canonicalPlexArtworkPath(path == null ? null : Uri.tryParse(path));

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
