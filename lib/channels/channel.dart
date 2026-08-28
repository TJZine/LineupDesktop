import 'dart:convert';
import 'dart:math';

enum PlexLibraryType { movie, show }

enum PlaybackMode { sequential, shuffle, block }

sealed class ContentSource {
  const ContentSource();

  Map<String, Object?> toJson();

  static ContentSource fromJson(Object? value) {
    try {
      final json = _object(value, 'content source');
      return switch (json['type']) {
        'library' => () {
          _requireFields(
            json,
            const {'type', 'libraryId', 'libraryType', 'includeWatched'},
            const {'filters'},
          );
          return LibrarySource(
            libraryId: _string(json['libraryId']),
            libraryType: _enumValue(
              PlexLibraryType.values,
              json['libraryType'],
            ),
            includeWatched: _boolean(json['includeWatched']),
            filters: json.containsKey('filters')
                ? Map<String, String>.from(_nonNull(json, 'filters') as Map)
                : const {},
          );
        }(),
        'manual' => () {
          _requireFields(json, const {'type', 'items'});
          return ManualSource(
            List<Object?>.from(_nonNull(json, 'items') as List)
                .map(ChannelItem.fromJson)
                .toList(),
          );
        }(),
        'playlist' => () {
          _requireFields(json, const {'type', 'playlistId'});
          return PlaylistSource(_string(json['playlistId']));
        }(),
        'mixed' => () {
          _requireFields(json, const {'type', 'interleave', 'sources'});
          return MixedSource(
            sources: List<Object?>.from(_nonNull(json, 'sources') as List)
                .map(ContentSource.fromJson)
                .toList(),
            interleave: _boolean(json['interleave']),
          );
        }(),
        _ => throw const FormatException('Unknown content source type'),
      };
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Invalid content source', error);
    }
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

bool hasNonemptyRetainedManualContent(ContentSource source) => switch (source) {
  ManualSource(:final items) => items.isNotEmpty,
  MixedSource(:final sources) => sources.any(hasNonemptyRetainedManualContent),
  LibrarySource() || PlaylistSource() => false,
};

class ChannelItem {
  const ChannelItem({
    required this.id,
    required this.title,
    required this.duration,
    this.showTitle,
    this.showThumb,
    this.poster,
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
    this.cast = const [],
  });

  final String id;
  final String title;
  final Duration duration;
  final String? showTitle;
  final String? showThumb;

  final Uri? poster;
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
  final List<ChannelCastMember> cast;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'durationMs': duration.inMilliseconds,
    if (showTitle != null) 'showTitle': showTitle,
    if (showThumb != null) 'showThumb': showThumb,
    if (poster != null) 'poster': poster.toString(),
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
    if (cast.isNotEmpty)
      'cast': cast.map((member) => member.toJson()).toList(growable: false),
  };

  factory ChannelItem.fromJson(Object? value) {
    try {
      final json = _object(value, 'channel item');
      _requireFields(
        json,
        const {'id', 'title', 'durationMs'},
        const {
          'showTitle',
          'showThumb',
          'poster',
          'backdrop',
          'clearLogo',
          'summary',
          'contentRating',
          'genres',
          'year',
          'seasonNumber',
          'episodeNumber',
          'resolution',
          'videoCodec',
          'audioCodec',
          'audioChannels',
          'dynamicRange',
          'cast',
        },
      );
      final duration = Duration(milliseconds: _integer(json['durationMs']));
      if (duration <= Duration.zero) {
        throw const FormatException('Invalid item duration');
      }
      return ChannelItem(
        id: _string(json['id']),
        title: _string(json['title']),
        duration: duration,
        showTitle: _optionalString(json, 'showTitle'),
        showThumb: _optionalString(json, 'showThumb'),
        poster: _optionalUri(json, 'poster'),
        backdrop: _optionalUri(json, 'backdrop'),
        clearLogo: _optionalUri(json, 'clearLogo'),
        summary: _optionalString(json, 'summary'),
        contentRating: _optionalString(json, 'contentRating'),
        genres: json.containsKey('genres')
            ? List<String>.from(_nonNull(json, 'genres') as List)
            : const [],
        year: _optionalInteger(json, 'year'),
        seasonNumber: _optionalInteger(json, 'seasonNumber'),
        episodeNumber: _optionalInteger(json, 'episodeNumber'),
        resolution: _optionalString(json, 'resolution'),
        videoCodec: _optionalString(json, 'videoCodec'),
        audioCodec: _optionalString(json, 'audioCodec'),
        audioChannels: _optionalInteger(json, 'audioChannels'),
        dynamicRange: _optionalString(json, 'dynamicRange'),
        cast: json.containsKey('cast')
            ? List<ChannelCastMember>.unmodifiable(
                (_nonNull(json, 'cast') as List).map(
                  ChannelCastMember.fromJson,
                ),
              )
            : const [],
      );
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Invalid channel item', error);
    }
  }
}

class ChannelCastMember {
  ChannelCastMember({required this.name, this.role, Uri? portrait})
    : portrait = canonicalCastPortrait(portrait);

  final String name;
  final String? role;
  final Uri? portrait;

  Map<String, Object?> toJson() => {
    'name': name,
    if (role != null) 'role': role,
    if (portrait != null) 'portrait': portrait.toString(),
  };

  factory ChannelCastMember.fromJson(Object? value) {
    final json = _object(value, 'cast member');
    _requireFields(json, const {'name'}, const {'role', 'portrait'});
    return ChannelCastMember(
      name: _string(json['name']),
      role: _optionalString(json, 'role'),
      portrait: _optionalUri(json, 'portrait'),
    );
  }
}

Uri? canonicalCastPortrait(Uri? value) {
  if (value == null ||
      value.scheme.isNotEmpty ||
      value.hasAuthority ||
      value.hasQuery ||
      value.hasFragment ||
      !value.path.startsWith('/library/metadata/')) {
    return null;
  }
  final suffix = value.path.substring('/library/metadata/'.length);
  if (suffix.isEmpty ||
      suffix
          .split('/')
          .any(
            (segment) => segment.isEmpty || segment == '.' || segment == '..',
          ) ||
      value.pathSegments.any((segment) => segment == '.' || segment == '..')) {
    return null;
  }
  return value.toString() == value.path ? value : null;
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
    try {
      final json = _object(value, 'channel');
      _requireFields(
        json,
        const {
          'id',
          'number',
          'name',
          'source',
          'playbackMode',
          'anchor',
          'shuffleSeed',
        },
        const {'blockSize', 'builderKey'},
      );
      return Channel(
        id: _string(json['id']),
        number: _integer(json['number']),
        name: _string(json['name']),
        source: ContentSource.fromJson(json['source']),
        playbackMode: _enumValue(PlaybackMode.values, json['playbackMode']),
        anchor: DateTime.parse(_string(json['anchor'])).toUtc(),
        shuffleSeed: _integer(json['shuffleSeed']),
        blockSize: _optionalInteger(json, 'blockSize'),
        builderKey: _optionalString(json, 'builderKey'),
      );
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Invalid channel', error);
    }
  }
}

bool canonicalChannelValueEquals(Object? left, Object? right) {
  if (left is Map && right is Map) {
    return left.length == right.length &&
        left.entries.every(
          (entry) =>
              right.containsKey(entry.key) &&
              canonicalChannelValueEquals(entry.value, right[entry.key]),
        );
  }
  if (left is List && right is List) {
    return left.length == right.length &&
        Iterable<int>.generate(left.length).every(
          (index) => canonicalChannelValueEquals(left[index], right[index]),
        );
  }
  return left == right;
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

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map) throw FormatException('Invalid $name');
  try {
    return Map<String, Object?>.from(value);
  } catch (error) {
    throw FormatException('Invalid $name', error);
  }
}

void _requireFields(
  Map<String, Object?> json,
  Set<String> required, [
  Set<String> optional = const {},
]) {
  final keys = json.keys.toSet();
  if (!keys.containsAll(required) ||
      keys.difference({...required, ...optional}).isNotEmpty) {
    throw const FormatException('Fields are not canonical');
  }
}

Object _nonNull(Map<String, Object?> json, String key) =>
    json[key] ?? (throw FormatException('Invalid $key'));

bool _boolean(Object? value) {
  if (value is! bool) throw const FormatException('Invalid Boolean');
  return value;
}

int _integer(Object? value) {
  if (value is! int) throw const FormatException('Invalid integer');
  return value;
}

int? _optionalInteger(Map<String, Object?> json, String key) =>
    json.containsKey(key) ? _integer(_nonNull(json, key)) : null;

String? _optionalString(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) return null;
  final value = _nonNull(json, key);
  if (value is! String) throw FormatException('Invalid $key');
  return value;
}

T _enumValue<T extends Enum>(List<T> values, Object? value) {
  if (value is! String) throw const FormatException('Invalid enum');
  return values.where((candidate) => candidate.name == value).firstOrNull ??
      (throw const FormatException('Invalid enum'));
}

Uri? _optionalUri(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) return null;
  final value = _nonNull(json, key);
  if (value is! String) throw FormatException('Invalid $key');
  return Uri.tryParse(value) ?? (throw FormatException('Invalid $key'));
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
