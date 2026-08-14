import '../channels/channel.dart';
import '../playback/stream_policy.dart';

class PlexAccount {
  const PlexAccount({
    required this.id,
    required this.name,
    required this.email,
    this.thumb,
  });

  final String id;
  final String name;
  final String email;
  final Uri? thumb;
}

class PlexHomeUser {
  const PlexHomeUser({
    required this.id,
    required this.name,
    required this.protected,
    this.thumb,
  });

  final String id;
  final String name;
  final bool protected;
  final Uri? thumb;
}

class PlexPin {
  const PlexPin({
    required this.id,
    required this.code,
    required this.expiresAt,
  });

  final int id;
  final String code;
  final DateTime expiresAt;
}

class PlexServer {
  const PlexServer({
    required this.id,
    required this.name,
    required this.connections,
    this.owned = false,
  });

  final String id;
  final String name;
  final List<PlexConnection> connections;
  final bool owned;
}

class PlexConnection {
  const PlexConnection({
    required this.uri,
    required this.local,
    required this.relay,
    this.latency,
  });

  final Uri uri;
  final bool local;
  final bool relay;
  final Duration? latency;
}

class PlexLibrary {
  const PlexLibrary({
    required this.id,
    required this.title,
    required this.type,
  });

  final String id;
  final String title;
  final PlexLibraryType type;
}

class PlexPlaylist {
  const PlexPlaylist({
    required this.id,
    required this.title,
    required this.items,
  });

  final String id;
  final String title;
  final List<PlexMediaItem> items;
}

class PlexPlaylistCatalog {
  const PlexPlaylistCatalog({required this.playlists, required this.failedIds});
  final List<PlexPlaylist> playlists;
  final Set<String> failedIds;
}

class PlexTrack {
  const PlexTrack({
    required this.id,
    required this.type,
    required this.codec,
    this.language,
    this.selected = false,
    this.isDefault = false,
    this.forced = false,
    this.delivery,
  });

  final String id;
  final int type;
  final String codec;
  final String? language;
  final bool selected;
  final bool isDefault;
  final bool forced;
  final SubtitleDelivery? delivery;
}

class PlexMediaItem {
  const PlexMediaItem({
    required this.id,
    required this.key,
    required this.title,
    required this.type,
    required this.duration,
    this.libraryId,
    this.parentTitle,
    this.grandparentTitle,
    this.thumbPath,
    this.artPath,
    this.partPath,
    this.container,
    this.videoCodec,
    this.audioCodec,
    this.dynamicRange = DynamicRange.unknown,
    this.tracks = const [],
    this.genres = const [],
    this.collections = const [],
    this.directors = const [],
    this.actors = const [],
    this.studio,
    this.year,
    this.addedAt,
    this.viewed = false,
  });

  final String id;
  final String key;
  final String title;
  final String type;
  final Duration duration;
  final String? libraryId;
  final String? parentTitle;
  final String? grandparentTitle;
  final String? thumbPath;
  final String? artPath;
  final String? partPath;
  final String? container;
  final String? videoCodec;
  final String? audioCodec;
  final DynamicRange dynamicRange;
  final List<PlexTrack> tracks;
  final List<String> genres;
  final List<String> collections;
  final List<String> directors;
  final List<String> actors;
  final String? studio;
  final int? year;
  final DateTime? addedAt;
  final bool viewed;
}

class PlexPlaybackDescriptor {
  const PlexPlaybackDescriptor({
    required this.uri,
    required this.decision,
    required this.sessionId,
  });

  final Uri uri;
  final StreamDecision decision;
  final String sessionId;
}

class PlexException implements Exception {
  const PlexException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}
