import '../channels/channel.dart';

enum DynamicRange { sdr, hdr10, hlg, dolbyVision, unknown }

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
    this.admin = false,
    this.restricted,
  });

  final String id;
  final String name;
  final bool protected;
  final Uri? thumb;
  final bool admin;
  final bool? restricted;
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

String plexConnectionDescription(PlexConnection connection) {
  final type = plexConnectionType(connection);
  final latency = connection.latency;
  final milliseconds = latency?.inMilliseconds;
  final warning = milliseconds == null
      ? null
      : milliseconds >= 500
      ? 'Very slow'
      : milliseconds >= 100
      ? 'Slow'
      : null;
  return [
    type,
    if (connection.relay) 'Limited',
    if (milliseconds != null) '$milliseconds ms measured',
    ?warning,
  ].join(' • ');
}

String plexConnectionType(PlexConnection connection) => connection.relay
    ? 'Relay'
    : connection.local
    ? 'Direct local'
    : 'Direct remote';

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

typedef PlexLibraryPageProgress = ({
  int completedPages,
  int completedItems,
  int? totalItems,
});

class PlexMediaPart {
  PlexMediaPart({required this.path, this.duration})
    : assert(duration == null || duration.inMicroseconds > 0);

  final String path;
  final Duration? duration;
}

class PlexMediaItem {
  const PlexMediaItem({
    required this.id,
    required this.title,
    required this.type,
    required this.duration,
    this.libraryId,
    this.parentTitle,
    this.grandparentTitle,
    this.thumbPath,
    this.grandparentThumbPath,
    this.artPath,
    this.clearLogoPath,
    this.parts = const [],
    this.container,
    this.videoCodec,
    this.audioCodec,
    this.dynamicRange = DynamicRange.unknown,
    this.genres = const [],
    this.collections = const [],
    this.directors = const [],
    this.actors = const [],
    this.studio,
    this.year,
    this.summary,
    this.contentRating,
    this.seasonNumber,
    this.episodeNumber,
    this.videoResolution,
    this.audioChannels,
    this.addedAt,
    this.viewed = false,
  });

  final String id;
  final String title;
  final String type;
  final Duration duration;
  final String? libraryId;
  final String? parentTitle;
  final String? grandparentTitle;
  final String? thumbPath;
  final String? grandparentThumbPath;
  final String? artPath;
  final String? clearLogoPath;
  final List<PlexMediaPart> parts;
  final String? container;
  final String? videoCodec;
  final String? audioCodec;
  final DynamicRange dynamicRange;
  final List<String> genres;
  final List<String> collections;
  final List<String> directors;
  final List<String> actors;
  final String? studio;
  final int? year;
  final String? summary;
  final String? contentRating;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? videoResolution;
  final int? audioChannels;
  final DateTime? addedAt;
  final bool viewed;

  bool get isPlayable =>
      duration > Duration.zero && parts.any((part) => part.path.isNotEmpty);
}

typedef PlexPlaybackPartDescriptor = ({Uri uri, Duration? duration});

class PlexException implements Exception {
  const PlexException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}
