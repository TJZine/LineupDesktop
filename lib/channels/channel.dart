import 'dart:convert';
import 'dart:math';

enum PlexLibraryType { movie, show }

enum PlaybackMode { sequential, shuffle, block }

sealed class ContentSource {
  const ContentSource();

  Map<String, Object?> toJson();

  static ContentSource fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Invalid content source');
    final json = Map<String, Object?>.from(value);
    return switch (json['type']) {
      'library' => LibrarySource(
        libraryId: _string(json['libraryId']),
        libraryType: PlexLibraryType.values.byName(
          _string(json['libraryType']),
        ),
        includeWatched: json['includeWatched'] == true,
        filters: Map<String, String>.from(json['filters'] as Map? ?? const {}),
      ),
      'manual' => ManualSource(
        (json['items'] as List? ?? const []).map(ChannelItem.fromJson).toList(),
      ),
      'playlist' => PlaylistSource(_string(json['playlistId'])),
      'mixed' => MixedSource(
        sources: (json['sources'] as List? ?? const [])
            .map(ContentSource.fromJson)
            .toList(),
        interleave: json['interleave'] == true,
      ),
      _ => throw const FormatException('Unknown content source type'),
    };
  }
}

class PlaylistSource extends ContentSource {
  const PlaylistSource(this.playlistId);

  final String playlistId;

  @override
  Map<String, Object?> toJson() => {
    'type': 'playlist',
    'playlistId': playlistId,
  };
}

class LibrarySource extends ContentSource {
  const LibrarySource({
    required this.libraryId,
    required this.libraryType,
    this.includeWatched = true,
    this.filters = const {},
  });

  final String libraryId;
  final PlexLibraryType libraryType;
  final bool includeWatched;
  final Map<String, String> filters;

  @override
  Map<String, Object?> toJson() => {
    'type': 'library',
    'libraryId': libraryId,
    'libraryType': libraryType.name,
    'includeWatched': includeWatched,
    if (filters.isNotEmpty) 'filters': filters,
  };
}

class ManualSource extends ContentSource {
  const ManualSource(this.items);

  final List<ChannelItem> items;

  @override
  Map<String, Object?> toJson() => {
    'type': 'manual',
    'items': items.map((item) => item.toJson()).toList(),
  };
}

class MixedSource extends ContentSource {
  const MixedSource({required this.sources, this.interleave = false});

  final List<ContentSource> sources;
  final bool interleave;

  @override
  Map<String, Object?> toJson() => {
    'type': 'mixed',
    'interleave': interleave,
    'sources': sources.map((source) => source.toJson()).toList(),
  };
}

class ChannelItem {
  const ChannelItem({
    required this.id,
    required this.title,
    required this.duration,
    this.showTitle,
    this.showThumb,
    this.artwork,
    this.backdrop,
    this.clearLogo,
    this.summary,
    this.contentRating,
    this.genres = const [],
    this.year,
    this.seasonNumber,
    this.episodeNumber,
    this.resolution,
    this.videoCodec,
    this.audioCodec,
    this.audioChannels,
    this.dynamicRange,
  });

  final String id;
  final String title;
  final Duration duration;
  final String? showTitle;
  final String? showThumb;

  /// The poster/thumb path retained under the legacy `artwork` JSON key.
  final Uri? artwork;
  final Uri? backdrop;
  final Uri? clearLogo;
  final String? summary;
  final String? contentRating;
  final List<String> genres;
  final int? year;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? resolution;
  final String? videoCodec;
  final String? audioCodec;
  final int? audioChannels;
  final String? dynamicRange;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'durationMs': duration.inMilliseconds,
    if (showTitle != null) 'showTitle': showTitle,
    if (showThumb != null) 'showThumb': showThumb,
    if (artwork != null) 'artwork': artwork.toString(),
    if (backdrop != null) 'backdrop': backdrop.toString(),
    if (clearLogo != null) 'clearLogo': clearLogo.toString(),
    if (summary != null) 'summary': summary,
    if (contentRating != null) 'contentRating': contentRating,
    if (genres.isNotEmpty) 'genres': genres,
    if (year != null) 'year': year,
    if (seasonNumber != null) 'seasonNumber': seasonNumber,
    if (episodeNumber != null) 'episodeNumber': episodeNumber,
    if (resolution != null) 'resolution': resolution,
    if (videoCodec != null) 'videoCodec': videoCodec,
    if (audioCodec != null) 'audioCodec': audioCodec,
    if (audioChannels != null) 'audioChannels': audioChannels,
    if (dynamicRange != null) 'dynamicRange': dynamicRange,
  };

  factory ChannelItem.fromJson(Object? value) {
    final json = Map<String, Object?>.from(value as Map);
    final duration = Duration(
      milliseconds: (json['durationMs'] as num).toInt(),
    );
    if (duration <= Duration.zero) {
      throw const FormatException('Invalid item duration');
    }
    return ChannelItem(
      id: _string(json['id']),
      title: _string(json['title']),
      duration: duration,
      showTitle: json['showTitle'] as String?,
      showThumb: json['showThumb'] as String?,
      artwork: json['artwork'] is String
          ? Uri.tryParse(json['artwork'] as String)
          : null,
      backdrop: json['backdrop'] is String
          ? Uri.tryParse(json['backdrop'] as String)
          : null,
      clearLogo: json['clearLogo'] is String
          ? Uri.tryParse(json['clearLogo'] as String)
          : null,
      summary: json['summary'] as String?,
      contentRating: json['contentRating'] as String?,
      genres: List<String>.from(json['genres'] as List? ?? const []),
      year: (json['year'] as num?)?.toInt(),
      seasonNumber: (json['seasonNumber'] as num?)?.toInt(),
      episodeNumber: (json['episodeNumber'] as num?)?.toInt(),
      resolution: json['resolution'] as String?,
      videoCodec: json['videoCodec'] as String?,
      audioCodec: json['audioCodec'] as String?,
      audioChannels: (json['audioChannels'] as num?)?.toInt(),
      dynamicRange: json['dynamicRange'] as String?,
    );
  }
}

class Channel {
  const Channel({
    required this.id,
    required this.number,
    required this.name,
    required this.source,
    required this.playbackMode,
    required this.anchor,
    required this.shuffleSeed,
    this.blockSize,
    this.builderKey,
  });

  final String id;
  final int number;
  final String name;
  final ContentSource source;
  final PlaybackMode playbackMode;
  final DateTime anchor;
  final int shuffleSeed;
  final int? blockSize;
  final String? builderKey;

  void validate(Iterable<Channel> existing) {
    if (id.trim().isEmpty || name.trim().isEmpty) {
      throw const FormatException('Channel name is required');
    }
    if (number < 1 || number > 1000) {
      throw const FormatException('Channel number must be between 1 and 1000');
    }
    if (existing.any(
      (channel) => channel.id != id && channel.number == number,
    )) {
      throw const FormatException('Channel number is already in use');
    }
    if (playbackMode == PlaybackMode.block &&
        (blockSize == null || blockSize! < 1)) {
      throw const FormatException('Block size must be positive');
    }
    _validateSource(source, 0);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'number': number,
    'name': name,
    'source': source.toJson(),
    'playbackMode': playbackMode.name,
    'anchor': anchor.toUtc().toIso8601String(),
    'shuffleSeed': shuffleSeed,
    if (blockSize != null) 'blockSize': blockSize,
    if (builderKey != null) 'builderKey': builderKey,
  };

  factory Channel.fromJson(Object? value) {
    final json = Map<String, Object?>.from(value as Map);
    return Channel(
      id: _string(json['id']),
      number: (json['number'] as num).toInt(),
      name: _string(json['name']),
      source: ContentSource.fromJson(json['source']),
      playbackMode: PlaybackMode.values.byName(_string(json['playbackMode'])),
      anchor: DateTime.parse(_string(json['anchor'])).toUtc(),
      shuffleSeed: (json['shuffleSeed'] as num).toInt(),
      blockSize: (json['blockSize'] as num?)?.toInt(),
      builderKey: json['builderKey'] as String?,
    );
  }
}

String createChannelId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

String _string(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Required text is missing');
  }
  return value.trim();
}

void _validateSource(ContentSource source, int depth) {
  if (depth > 25) {
    throw const FormatException('Content source is too deeply nested');
  }
  switch (source) {
    case LibrarySource(:final libraryId):
      if (libraryId.isEmpty) throw const FormatException('Library is required');
    case ManualSource(:final items):
      if (items.isEmpty ||
          items.any((item) => item.duration <= Duration.zero)) {
        throw const FormatException('Manual content cannot be empty');
      }
    case PlaylistSource(:final playlistId):
      if (playlistId.isEmpty) {
        throw const FormatException('Playlist is required');
      }
    case MixedSource(:final sources):
      if (sources.isEmpty) {
        throw const FormatException('Mixed content cannot be empty');
      }
      for (final child in sources) {
        _validateSource(child, depth + 1);
      }
  }
}
