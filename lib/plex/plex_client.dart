import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../channels/channel.dart';
import 'plex_models.dart';

class PlexServerAccess {
  PlexServerAccess({required this.server, required String token})
    : token = _requiredToken(token);

  final PlexServer server;
  final String token;

  @override
  String toString() =>
      'PlexServerAccess(server: ${server.id}, token: <redacted>)';

  static String _requiredToken(String token) {
    final value = token.trim();
    if (value.isEmpty) {
      throw ArgumentError('A PMS resource token is required.');
    }
    return value;
  }
}

class PlexClient {
  PlexClient({
    required this.clientIdentifier,
    http.Client? httpClient,
    this.requestTimeout = const Duration(seconds: 15),
  }) : _http = httpClient ?? http.Client();

  final String clientIdentifier;
  final http.Client _http;
  final Duration requestTimeout;

  Map<String, String> _headers([String? token]) => {
    'Accept': 'application/json',
    'X-Plex-Client-Identifier': clientIdentifier,
    'X-Plex-Product': 'Lineup Desktop',
    'X-Plex-Version': '0.1.0',
    'X-Plex-Platform': Platform.operatingSystem,
    'X-Plex-Device': 'Desktop',
    'X-Plex-Device-Name': 'Lineup Desktop',
    'X-Plex-Token': ?token,
  };

  Future<PlexPin> createPin() async {
    final response = await _send(
      _http.post(Uri.https('plex.tv', '/api/v2/pins'), headers: _headers()),
    );
    final json = _json(response, {200, 201});
    return PlexPin(
      id: _integer(json['id'], 'PIN id'),
      code: _text(json['code'], 'PIN code'),
      expiresAt: DateTime.parse(_text(json['expiresAt'], 'PIN expiration')),
    );
  }

  Future<String?> pollPin(PlexPin pin) async {
    final response = await _send(
      _http.get(
        Uri.https('plex.tv', '/api/v2/pins/${pin.id}'),
        headers: _headers(),
      ),
    );
    final json = _json(response, {200});
    return _optionalText(json['authToken']);
  }

  Future<void> cancelPin(PlexPin pin) async {
    try {
      await _send(
        _http.delete(
          Uri.https('plex.tv', '/api/v2/pins/${pin.id}'),
          headers: _headers(),
        ),
      );
    } catch (_) {}
  }

  Future<PlexAccount> account(String token) async {
    final response = await _send(
      _http.get(
        Uri.https('plex.tv', '/users/account.json'),
        headers: _headers(token),
      ),
    );
    final root = _json(response, {200});
    final json = _record(root['user'] ?? root['User'] ?? root, 'account');
    return PlexAccount(
      id: _id(json['id'] ?? json['uuid'], 'account id'),
      name:
          _optionalText(
            json['username'] ?? json['title'] ?? json['friendlyName'],
          ) ??
          'Plex account',
      email: _optionalText(json['email']) ?? '',
      thumb: Uri.tryParse(_optionalText(json['thumb']) ?? ''),
    );
  }

  Future<List<PlexHomeUser>> homeUsers(String accountToken) async {
    for (final path in ['/api/v2/home/users', '/api/home/users']) {
      final response = await _send(
        _http.get(Uri.https('plex.tv', path), headers: _headers(accountToken)),
      );
      if (response.statusCode == 404 ||
          response.statusCode == 405 ||
          response.statusCode >= 500) {
        continue;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _throwResponse(response);
      }
      final users = _parseHomeUsers(response.body);
      if (users.isNotEmpty || path == '/api/home/users') return users;
    }
    return const [];
  }

  Future<String> switchHomeUser(
    String accountToken,
    String userId,
    String? pin,
  ) async {
    for (final path in [
      '/api/v2/home/users/$userId/switch',
      '/api/home/users/$userId/switch',
    ]) {
      final response = await _send(
        _http.post(
          Uri.https('plex.tv', path),
          headers: {
            ..._headers(accountToken),
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {if (pin != null && pin.isNotEmpty) 'pin': pin},
        ),
      );
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const PlexException(
          'incorrect-pin',
          'That Plex Home PIN was not accepted.',
        );
      }
      if ((response.statusCode == 404 ||
              response.statusCode == 405 ||
              response.statusCode >= 500) &&
          path.contains('/v2/')) {
        continue;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _throwResponse(response);
      }
      final json = _tryJson(response.body);
      final token = _findToken(json) ?? _findTokenInXml(response.body);
      if (token != null) return token;
      if (!path.contains('/v2/')) break;
    }
    throw const PlexException(
      'parse-error',
      'Plex did not return a profile token.',
    );
  }

  Future<List<PlexServerAccess>> discoverServers(String token) async {
    final response = await _send(
      _http.get(
        Uri.https('plex.tv', '/api/v2/resources', {
          'includeHttps': '1',
          'includeRelay': '1',
        }),
        headers: _headers(token),
      ),
    );
    final data = _jsonList(response, {200});
    final servers = <PlexServerAccess>[];
    for (final raw in data) {
      final json = _record(raw, 'resource');
      final provides = _optionalText(json['provides'])
          ?.split(',')
          .map((item) => item.trim());
      if (provides?.contains('server') != true) continue;
      final resourceToken = _optionalText(json['accessToken']);
      if (resourceToken == null) continue;
      final connections = <PlexConnection>[];
      for (final rawConnection in json['connections'] as List? ?? const []) {
        final connection = _record(rawConnection, 'connection');
        final uri = Uri.tryParse(_optionalText(connection['uri']) ?? '');
        if (uri == null ||
            uri.scheme != 'https' ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty) {
          continue;
        }
        connections.add(
          PlexConnection(
            uri: Uri(
              scheme: uri.scheme,
              host: uri.host,
              port: uri.hasPort ? uri.port : null,
            ),
            local: _boolean(connection['local']),
            relay: _boolean(connection['relay']),
          ),
        );
      }
      if (connections.isNotEmpty) {
        servers.add(
          PlexServerAccess(
            server: PlexServer(
              id: _text(json['clientIdentifier'], 'server id'),
              name: _text(json['name'], 'server name'),
              connections: connections,
              owned: _boolean(json['owned']),
            ),
            token: resourceToken,
          ),
        );
      }
    }
    return servers;
  }

  Future<PlexConnection> selectConnection(
    PlexServer server,
    String token,
  ) async {
    final byTier = <int, List<PlexConnection>>{};
    for (final connection in server.connections) {
      byTier.putIfAbsent(_connectionTier(connection), () => []).add(connection);
    }
    final tiers = byTier.keys.toList()..sort();
    final candidates = <PlexConnection>[];
    for (
      var index = 0;
      index < tiers.length && candidates.length < 8;
      index++
    ) {
      final laterFallbacks = tiers.length - index - 1;
      final availableSlots = 8 - candidates.length - laterFallbacks;
      candidates.addAll(byTier[tiers[index]]!.take(availableSlots));
    }
    PlexException? authorizationError;
    for (final tier in {
      for (final connection in candidates) _connectionTier(connection),
    }) {
      final results = await Future.wait(
        candidates.where((candidate) => _connectionTier(candidate) == tier).map(
          (connection) async {
            try {
              return (
                probe: await _probeConnection(server, connection, token),
                authorizationError: null as PlexException?,
              );
            } on PlexException catch (error) {
              if (error.code != 'auth-required' &&
                  error.code != 'access-denied') {
                rethrow;
              }
              return (
                probe: null as (PlexConnection, Duration)?,
                authorizationError: error,
              );
            }
          },
        ),
      );
      authorizationError ??= results
          .map((result) => result.authorizationError)
          .nonNulls
          .firstOrNull;
      final reachable = results.map((result) => result.probe).nonNulls.toList();
      if (reachable.isNotEmpty) {
        reachable.sort((a, b) => a.$2.compareTo(b.$2));
        final selected = reachable.first;
        return PlexConnection(
          uri: selected.$1.uri,
          local: selected.$1.local,
          relay: selected.$1.relay,
          latency: selected.$2,
        );
      }
    }
    if (authorizationError != null) throw authorizationError;
    throw const PlexException(
      'server-unreachable',
      'No reachable connection was found for this server.',
    );
  }

  Future<(PlexConnection, Duration)?> _probeConnection(
    PlexServer server,
    PlexConnection connection,
    String token,
  ) async {
    final watch = Stopwatch()..start();
    late final http.Response response;
    try {
      response = await _send(
        _http.get(
          connection.uri.resolve('/identity'),
          headers: _headers(token),
        ),
        timeout: const Duration(seconds: 4),
      );
    } catch (_) {
      return null;
    }
    if (response.statusCode == 401) {
      throw const PlexException(
        'auth-required',
        'The Plex server requires authentication.',
      );
    }
    if (response.statusCode == 403) {
      throw const PlexException(
        'access-denied',
        'This Plex profile cannot access that server.',
      );
    }
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        _identityId(response.body) == server.id) {
      return (connection, watch.elapsed);
    }
    return null;
  }

  Future<List<PlexLibrary>> libraries(Uri server, String token) async {
    final json = await _serverJson(server.resolve('/library/sections'), token);
    final directories = _containerList(json, 'Directory');
    return [
      for (final raw in directories)
        if (raw is Map && {'movie', 'show'}.contains(raw['type']))
          PlexLibrary(
            id: _id(raw['key'], 'library id'),
            title: _text(raw['title'], 'library title'),
            type: raw['type'] == 'show'
                ? PlexLibraryType.show
                : PlexLibraryType.movie,
          ),
    ];
  }

  Future<List<PlexMediaItem>> libraryItems(
    Uri server,
    String token,
    String libraryId,
    PlexLibraryType libraryType, {
    required bool Function() isCurrent,
    required void Function(PlexLibraryPageProgress progress) onProgress,
  }) async {
    final output = <PlexMediaItem>[];
    var start = 0;
    const pageSize = 100;
    for (var page = 0; page < 1000; page++) {
      if (!isCurrent()) {
        throw const PlexException('cancelled', 'Library scan cancelled.');
      }
      final uri = server
          .resolve('/library/sections/$libraryId/all')
          .replace(
            queryParameters: {
              'type': libraryType == PlexLibraryType.show ? '4' : '1',
              'X-Plex-Container-Start': '$start',
              'X-Plex-Container-Size': '$pageSize',
            },
          );
      final json = await _serverJson(uri, token);
      final metadata = _containerList(json, 'Metadata');
      output.addAll(
        metadata.map((item) => parseMediaItem(item, libraryId: libraryId)),
      );
      if (!isCurrent()) {
        throw const PlexException('cancelled', 'Library scan cancelled.');
      }
      final container = json['MediaContainer'];
      final totalItems = container is Map
          ? _optionalInteger(container['totalSize'])
          : null;
      onProgress((
        completedPages: page + 1,
        completedItems: output.length,
        totalItems: totalItems,
      ));
      if (metadata.length < pageSize ||
          (totalItems != null &&
              totalItems >= 0 &&
              output.length == totalItems)) {
        return output;
      }
      start += metadata.length;
    }
    throw const PlexException(
      'library-scale-exceeded',
      'This library is too large to scan safely.',
    );
  }

  Future<PlexPlaylistCatalog> playlists(Uri server, String token) async {
    final json = await _serverJson(
      server
          .resolve('/playlists/all')
          .replace(queryParameters: const {'playlistType': 'video'}),
      token,
    );
    final output = <PlexPlaylist>[];
    final failed = <String>{};
    final metadata = _containerList(json, 'Metadata');
    for (var start = 0; start < metadata.length; start += 4) {
      final batch = metadata.skip(start).take(4).map((raw) async {
        try {
          final playlist = _record(raw, 'playlist');
          final id = _id(playlist['ratingKey'], 'playlist id');
          final itemsJson = await _serverJson(
            server.resolve('/playlists/${Uri.encodeComponent(id)}/items'),
            token,
          );
          final items = _containerList(itemsJson, 'Metadata')
              .map(parseMediaItem)
              .where((item) => item.duration > Duration.zero)
              .toList(growable: false);
          return items.isEmpty
              ? null
              : PlexPlaylist(
                  id: id,
                  title: _text(playlist['title'], 'playlist title'),
                  items: items,
                );
        } on PlexException catch (exception) {
          if (const {
            'auth-invalid',
            'auth-required',
            'access-denied',
          }.contains(exception.code)) {
            rethrow;
          }
          final value = raw is Map ? raw['ratingKey'] : null;
          if (value != null) failed.add('$value');
          return null;
        } catch (_) {
          final value = raw is Map ? raw['ratingKey'] : null;
          if (value != null) failed.add('$value');
          return null;
        }
      });
      for (final playlist in await Future.wait(batch)) {
        if (playlist != null) output.add(playlist);
      }
    }
    return PlexPlaylistCatalog(
      playlists: List.unmodifiable(output),
      failedIds: Set.unmodifiable(failed),
    );
  }

  PlexPlaybackDescriptor playbackDescriptor({
    required Uri server,
    required PlexMediaItem item,
  }) {
    final mediaParts = item.parts;
    if (mediaParts.isEmpty) {
      throw const PlexException(
        'unsupported',
        'This item has no playable media part.',
      );
    }
    return PlexPlaybackDescriptor(
      parts: List.unmodifiable([
        for (final part in mediaParts)
          PlexPlaybackPartDescriptor(
            uri: _directPlayUri(server, part.path),
            sessionId: _randomId(),
            duration: part.duration,
          ),
      ]),
    );
  }

  Future<Uint8List> artwork(
    Uri server,
    String token,
    Uri path, {
    int maximumBytes = 4 * 1024 * 1024,
  }) async {
    final uri = server.resolveUri(path);
    if (!_isSameServerUri(server, uri)) {
      throw const PlexException(
        'artwork-unavailable',
        'Program artwork is unavailable.',
      );
    }
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers.addAll(_headers(token));
    final response = await _http.send(request).timeout(requestTimeout);
    if (response.statusCode == 401 || response.statusCode == 403) {
      _cancel(response.stream);
      throw PlexException(
        response.statusCode == 401 ? 'auth-invalid' : 'access-denied',
        response.statusCode == 401
            ? 'Plex authentication is no longer valid.'
            : 'This Plex profile cannot access that server.',
      );
    }
    if (response.statusCode != 200) {
      _cancel(response.stream);
      throw const PlexException(
        'artwork-unavailable',
        'Program artwork is unavailable.',
      );
    }
    if ((response.contentLength ?? 0) > maximumBytes) {
      _cancel(response.stream);
      throw const PlexException(
        'artwork-too-large',
        'Program artwork is too large.',
      );
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(requestTimeout)) {
      if (bytes.length + chunk.length > maximumBytes) {
        throw const PlexException(
          'artwork-too-large',
          'Program artwork is too large.',
        );
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  void _cancel(Stream<List<int>> stream) {
    final subscription = stream.listen(
      null,
      onError: (Object _, StackTrace _) {},
    );
    unawaited(subscription.cancel().onError((_, _) {}));
  }

  Future<void> releasePlaybackSession({
    required Uri server,
    required String token,
    required String sessionId,
  }) async {
    try {
      await _send(
        _http.get(
          server
              .resolve('/video/:/transcode/universal/stop')
              .replace(queryParameters: {'session': sessionId}),
          headers: _headers(token),
        ),
      );
    } catch (_) {
      // Lease cleanup is best effort and never replaces playback settlement.
    }
  }

  Future<Map<String, Object?>> _serverJson(Uri uri, String token) async {
    final response = await _send(_http.get(uri, headers: _headers(token)));
    return _json(response, {200});
  }

  Future<http.Response> _send(
    Future<http.Response> request, {
    Duration? timeout,
  }) async {
    try {
      return await request.timeout(timeout ?? requestTimeout);
    } on TimeoutException {
      throw const PlexException(
        'network-timeout',
        'Plex did not respond in time. Try again.',
      );
    }
  }

  void close() => _http.close();
}

Uri _directPlayUri(Uri server, String partPath) {
  final uri = server.resolve(partPath);
  if (_isSameServerUri(server, uri)) return uri;
  throw const PlexException(
    'unsupported',
    'This item has no playable media part.',
  );
}

bool _isSameServerUri(Uri server, Uri uri) =>
    uri.scheme == server.scheme &&
    uri.host == server.host &&
    uri.port == server.port &&
    uri.userInfo.isEmpty;

String? _identityId(String body) {
  final json = _tryJson(body);
  if (json is Map) {
    final root = json['MediaContainer'] is Map
        ? json['MediaContainer'] as Map
        : json;
    final value = root['machineIdentifier'];
    if (value is String && value.isNotEmpty) return value;
  }
  try {
    final value = XmlDocument.parse(body).rootElement
        .getAttribute('machineIdentifier');
    return value == null || value.isEmpty ? null : value;
  } catch (_) {
    return null;
  }
}

PlexMediaItem parseMediaItem(Object? raw, {String? libraryId}) {
  final json = _record(raw, 'media item');
  final media = (json['Media'] as List? ?? const [])
      .whereType<Map>()
      .firstOrNull;
  final parts = [
    for (final rawPart in media?['Part'] as List? ?? const [])
      if (rawPart is Map) _parseMediaPart(rawPart),
  ];
  final firstPart = (media?['Part'] as List? ?? const [])
      .whereType<Map>()
      .firstOrNull;
  return PlexMediaItem(
    id: _id(json['ratingKey'], 'media id'),
    key: _text(json['key'], 'media key'),
    title: _text(json['title'], 'media title'),
    type: _text(json['type'], 'media type'),
    duration: Duration(milliseconds: _optionalInteger(json['duration']) ?? 0),
    libraryId: libraryId,
    parentTitle: _optionalText(json['parentTitle']),
    grandparentTitle: _optionalText(json['grandparentTitle']),
    thumbPath: _optionalText(json['thumb']),
    grandparentThumbPath: _optionalText(json['grandparentThumb']),
    artPath: _optionalText(json['art']),
    clearLogoPath: _clearLogoPath(json['Image']),
    parts: List.unmodifiable(parts),
    container: _optionalText(media?['container'])?.toLowerCase(),
    videoCodec: _optionalText(media?['videoCodec'])?.toLowerCase(),
    audioCodec: _optionalText(media?['audioCodec'])?.toLowerCase(),
    dynamicRange: _dynamicRange(media, _streamCodecs(firstPart)),
    genres: _tagNames(json['Genre']),
    collections: _tagNames(json['Collection']),
    directors: _tagNames(json['Director']),
    actors: _tagNames(json['Role']),
    studio: _optionalText(json['studio']),
    year: _optionalInteger(json['year']),
    summary: _optionalText(json['summary']),
    contentRating: _optionalText(json['contentRating']),
    seasonNumber: _optionalInteger(json['parentIndex']),
    episodeNumber: _optionalInteger(json['index']),
    videoResolution: _optionalText(media?['videoResolution']),
    audioChannels: _optionalInteger(media?['audioChannels']),
    addedAt: _optionalUnixTime(json['addedAt']),
    viewed: (_optionalInteger(json['viewCount']) ?? 0) > 0,
  );
}

PlexMediaPart _parseMediaPart(Map raw) {
  final path = _text(raw['key'], 'media part path');
  final milliseconds = _optionalInteger(raw['duration']);
  return PlexMediaPart(
    path: path,
    duration: milliseconds != null && milliseconds > 0
        ? Duration(milliseconds: milliseconds)
        : null,
  );
}

Iterable<String> _streamCodecs(Map? part) sync* {
  for (final rawStream in part?['Stream'] as List? ?? const []) {
    if (rawStream case {'codec': final String codec}) yield codec;
  }
}

String? _clearLogoPath(Object? raw) {
  if (raw is! List) return null;
  for (final entry in raw) {
    if (entry is! Map || entry['type'] != 'clearLogo') continue;
    final url = _optionalText(entry['url']);
    if (url != null) return url;
  }
  return null;
}

List<String> _tagNames(Object? raw) {
  final names = <String>[];
  for (final value in raw as List? ?? const []) {
    if (value is Map) {
      final name = _optionalText(value['tag']);
      if (name != null) names.add(name);
    }
  }
  return names;
}

int _connectionTier(PlexConnection connection) {
  if (connection.local &&
      connection.uri.scheme == 'https' &&
      !connection.relay) {
    return 0;
  }
  if (!connection.local &&
      connection.uri.scheme == 'https' &&
      !connection.relay) {
    return 1;
  }
  if (connection.relay && connection.uri.scheme == 'https') return 2;
  return 4;
}

List<PlexHomeUser> _parseHomeUsers(String body) {
  final json = _tryJson(body);
  final rawUsers = <Object?>[];
  void visit(Object? value, [int depth = 0]) {
    if (depth > 12) return;
    if (value is List) {
      for (final item in value) {
        visit(item, depth + 1);
      }
    } else if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key.toString().toLowerCase() == 'user') {
          entry.value is List
              ? rawUsers.addAll(entry.value as List)
              : rawUsers.add(entry.value);
        } else {
          visit(entry.value, depth + 1);
        }
      }
    }
  }

  visit(json);
  if (rawUsers.isEmpty) {
    try {
      final document = XmlDocument.parse(body);
      rawUsers.addAll(
        document.descendants
            .whereType<XmlElement>()
            .where((element) => element.name.local.toLowerCase() == 'user')
            .map(
              (element) => {
                for (final attribute in element.attributes)
                  attribute.name.local.toLowerCase(): attribute.value,
              },
            ),
      );
    } catch (_) {}
  }
  final users = <String, PlexHomeUser>{};
  for (final raw in rawUsers) {
    if (raw is! Map) continue;
    final user = Map<String, Object?>.from(raw);
    final normalized = {
      for (final entry in user.entries) entry.key.toLowerCase(): entry.value,
    };
    final id = _optionalText(normalized['id'] ?? normalized['uuid']);
    if (id == null) continue;
    users[id] = PlexHomeUser(
      id: id,
      name:
          _optionalText(
            normalized['title'] ?? normalized['name'] ?? normalized['username'],
          ) ??
          'Plex user',
      protected: _boolean(normalized['protected']),
      thumb: Uri.tryParse(_optionalText(normalized['thumb']) ?? ''),
    );
  }
  return users.values.toList();
}

Map<String, Object?> _json(http.Response response, Set<int> expected) {
  if (!expected.contains(response.statusCode)) _throwResponse(response);
  final value = _tryJson(response.body);
  return _record(value, 'Plex response');
}

List<Object?> _jsonList(http.Response response, Set<int> expected) {
  if (!expected.contains(response.statusCode)) _throwResponse(response);
  final value = _tryJson(response.body);
  if (value is! List) {
    throw const PlexException('parse-error', 'Plex response was not a list.');
  }
  return value;
}

Object? _tryJson(String body) {
  try {
    return jsonDecode(body);
  } catch (_) {
    return null;
  }
}

Never _throwResponse(http.Response response) {
  final code = switch (response.statusCode) {
    401 => 'auth-invalid',
    403 => 'access-denied',
    404 => 'resource-not-found',
    429 => 'rate-limited',
    _ => 'server-unreachable',
  };
  throw PlexException(code, 'Plex request failed (${response.statusCode}).');
}

Map<String, Object?> _record(Object? value, String label) {
  if (value is! Map) throw PlexException('parse-error', '$label was invalid.');
  return Map<String, Object?>.from(value);
}

List<Object?> _containerList(Map<String, Object?> json, String key) {
  final container = json['MediaContainer'];
  final value = container is Map ? container[key] : json[key];
  return value is List ? value : const [];
}

String _text(Object? value, String label) =>
    _optionalText(value) ??
    (throw PlexException('parse-error', '$label was missing.'));
String _id(Object? value, String label) =>
    value is num ? value.toString() : _text(value, label);
String? _optionalText(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;
int _integer(Object? value, String label) => value is num
    ? value.toInt()
    : int.tryParse(value?.toString() ?? '') ??
          (throw PlexException('parse-error', '$label was invalid.'));
const _maxExactJsonInteger = 0x1fffffffffffff;
int? _optionalInteger(Object? value) {
  final number = switch (value) {
    num number => number,
    String text => num.tryParse(text.trim()),
    _ => null,
  };
  return number != null &&
          number.isFinite &&
          number.abs() <= _maxExactJsonInteger
      ? number.toInt()
      : null;
}

DateTime? _optionalUnixTime(Object? value) {
  final seconds = _optionalInteger(value);
  if (seconds == null) return null;
  try {
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  } on RangeError {
    return null;
  }
}

bool _boolean(Object? value) =>
    value == true ||
    value == 1 ||
    {'1', 'true', 'yes'}.contains(value?.toString().toLowerCase());

String? _findToken(Object? value, [int depth = 0]) {
  if (depth > 10) return null;
  if (value is Map) {
    for (final entry in value.entries) {
      if ({
        'authtoken',
        'authenticationtoken',
        'token',
      }.contains(entry.key.toString().toLowerCase())) {
        final token = _optionalText(entry.value);
        if (token != null) return token;
      }
      final nested = _findToken(entry.value, depth + 1);
      if (nested != null) return nested;
    }
  } else if (value is List) {
    for (final item in value) {
      final nested = _findToken(item, depth + 1);
      if (nested != null) return nested;
    }
  }
  return null;
}

String? _findTokenInXml(String body) {
  try {
    for (final element in XmlDocument.parse(
      body,
    ).descendants.whereType<XmlElement>()) {
      for (final attribute in element.attributes) {
        if ({
          'authtoken',
          'authenticationtoken',
          'token',
        }.contains(attribute.name.local.toLowerCase())) {
          return attribute.value;
        }
      }
    }
  } catch (_) {}
  return null;
}

DynamicRange _dynamicRange(Map? media, Iterable<String> streamCodecs) {
  if (_boolean(media?['DOVIPresent']) || media?['DOVIProfile'] != null) {
    return DynamicRange.dolbyVision;
  }
  final facts =
      '${media?['videoDynamicRange']} ${media?['DOVIProfile']} ${media?['DOVIPresent']} ${streamCodecs.join(' ')}'
          .toLowerCase();
  if (facts.contains('dovi') || facts.contains('dolby vision')) {
    return DynamicRange.dolbyVision;
  }
  if (facts.contains('hlg') || facts.contains('arib')) return DynamicRange.hlg;
  if (facts.contains('hdr') ||
      facts.contains('bt2020') ||
      facts.contains('smpte')) {
    return DynamicRange.hdr10;
  }
  return media == null ? DynamicRange.unknown : DynamicRange.sdr;
}

String _randomId() {
  final random = Random.secure();
  return List.generate(24, (_) => random.nextInt(16).toRadixString(16)).join();
}
