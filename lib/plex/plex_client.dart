import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
  /// Hard ceiling for JSON/XML control responses. This leaves generous room
  /// for rich metadata and large playlists while keeping every buffered
  /// response finite.
  static const maximumControlResponseBytes = 16 * 1024 * 1024;

  PlexClient({
    required this.clientIdentifier,
    http.Client? httpClient,
    this.requestTimeout = const Duration(seconds: 15),
  }) : _http = httpClient ?? http.Client();

  final String clientIdentifier;
  final http.Client _http;
  final Duration requestTimeout;

  // Match the item pager's 1000 × 100 bound. Both collection records and
  // member occurrences (including duplicates across collections) are bounded.
  static const maximumLibraryCollections = 100000;
  static const maximumLibraryCollectionMembers = 100000;
  final _collectionRequests = _CollectionRequestPool(8);

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
      'POST',
      Uri.https('plex.tv', '/api/v2/pins'),
      headers: _headers(),
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
      'GET',
      Uri.https('plex.tv', '/api/v2/pins/${pin.id}'),
      headers: _headers(),
    );
    final json = _json(response, {200});
    return _optionalText(json['authToken']);
  }

  Future<void> cancelPin(PlexPin pin) async {
    final response = await _send(
      'DELETE',
      Uri.https('plex.tv', '/api/v2/pins/${pin.id}'),
      headers: _headers(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwResponse(response);
    }
  }

  Future<PlexAccount> account(String token) async {
    final response = await _send(
      'GET',
      Uri.https('plex.tv', '/users/account.json'),
      headers: _headers(token),
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
        'GET',
        Uri.https('plex.tv', path),
        headers: _headers(accountToken),
      );
      final v2 = path.contains('/v2/');
      if (v2 &&
          (response.statusCode == 404 ||
              response.statusCode == 405 ||
              response.statusCode >= 500)) {
        continue;
      }
      if (!v2 && (response.statusCode == 404 || response.statusCode == 405)) {
        return const [];
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _throwResponse(response);
      }
      final users = _parseHomeUsers(response.body);
      if (users.isNotEmpty || !v2) return users;
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
        'POST',
        Uri.https('plex.tv', path),
        headers: _headers(accountToken),
        bodyFields: {if (pin != null && pin.isNotEmpty) 'pin': pin},
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
      'GET',
      Uri.https('plex.tv', '/api/v2/resources', {
        'includeHttps': '1',
        'includeRelay': '1',
      }),
      headers: _headers(token),
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
        'GET',
        connection.uri.resolve('/identity'),
        headers: _headers(token),
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
    Future<void>? cancelled,
  }) async {
    final output = <PlexMediaItem>[];
    final seenIds = <String>{};
    var start = 0;
    var rawConsumed = 0;
    int? knownTotal;
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
      final json = await _serverJson(uri, token, cancelled: cancelled);
      if (!isCurrent()) {
        throw const PlexException('cancelled', 'Library scan cancelled.');
      }
      final containerRaw = json['MediaContainer'];
      if (containerRaw is! Map) {
        throw const PlexException(
          'library-page-invalid',
          'Plex returned an invalid library page.',
        );
      }
      final container = Map<String, Object?>.from(containerRaw);
      final pageTotal = _libraryPageCount(container['totalSize']);
      final pageSizeValue = _libraryPageCount(container['size']);
      final pageOffset = _libraryPageCount(container['offset']);
      if (pageOffset != null && pageOffset != start) {
        throw const PlexException(
          'library-page-invalid',
          'Plex returned an invalid library page.',
        );
      }
      if (pageTotal != null) {
        if (knownTotal == null) {
          knownTotal = pageTotal;
        } else if (knownTotal != pageTotal) {
          throw const PlexException(
            'library-page-invalid',
            'Plex returned an invalid library page.',
          );
        }
      }
      final rawMetadata = container['Metadata'];
      final List<Object?> metadata;
      if (rawMetadata == null) {
        if (pageSizeValue == 0) {
          metadata = const [];
        } else {
          throw const PlexException(
            'library-page-invalid',
            'Plex returned an invalid library page.',
          );
        }
      } else if (rawMetadata is List) {
        metadata = rawMetadata;
      } else {
        throw const PlexException(
          'library-page-invalid',
          'Plex returned an invalid library page.',
        );
      }
      if (metadata.length > pageSize) {
        throw const PlexException(
          'library-page-too-large',
          'Plex returned more library items than requested.',
        );
      }
      if (pageSizeValue != null && pageSizeValue != metadata.length) {
        throw const PlexException(
          'library-page-invalid',
          'Plex returned an invalid library page.',
        );
      }
      final known = knownTotal;
      if (known != null) {
        if (rawConsumed + metadata.length > known) {
          throw const PlexException(
            'library-page-invalid',
            'Plex returned an invalid library page.',
          );
        }
        if (metadata.isEmpty && rawConsumed < known) {
          throw const PlexException(
            'library-page-invalid',
            'Plex returned an invalid library page.',
          );
        }
      }
      final pageItems = <PlexMediaItem>[];
      for (final raw in metadata) {
        final item = parseMediaItem(raw, libraryId: libraryId);
        if (!seenIds.add(item.id)) {
          throw const PlexException(
            'library-page-not-progressing',
            'Plex returned a library page without progress.',
          );
        }
        pageItems.add(item);
      }
      output.addAll(pageItems);
      rawConsumed += metadata.length;
      if (!isCurrent()) {
        throw const PlexException('cancelled', 'Library scan cancelled.');
      }
      onProgress((
        completedPages: page + 1,
        completedItems: output.length,
        totalItems: knownTotal,
      ));
      if (knownTotal != null) {
        if (rawConsumed == knownTotal) return output;
      } else if (metadata.isEmpty) {
        return output;
      }
      start += metadata.length;
    }
    throw const PlexException(
      'library-scale-exceeded',
      'This library is too large to scan safely.',
    );
  }

  /// Scans playable inventory, then replaces tag-era collection metadata with
  /// Plex's authoritative membership. Progress remains the item pager's facts.
  Future<PlexLibraryScan> scanLibrary(
    Uri server,
    String token,
    String libraryId,
    PlexLibraryType libraryType, {
    required bool Function() isCurrent,
    required void Function(PlexLibraryPageProgress progress) onProgress,
    void Function(PlexLibraryScanPhase phase)? onPhase,
    Future<void>? cancelled,
  }) async {
    final phase = Stopwatch()..start();
    onPhase?.call(PlexLibraryScanPhase.items);
    final items = await libraryItems(
      server,
      token,
      libraryId,
      libraryType,
      isCurrent: isCurrent,
      onProgress: onProgress,
      cancelled: cancelled,
    );
    final itemsElapsed = phase.elapsed;
    phase.reset();
    if (!isCurrent()) throw _scanCancelledException;
    onPhase?.call(PlexLibraryScanPhase.collections);
    final collections = await libraryCollectionMembership(
      server,
      token,
      libraryId,
      isCurrent: isCurrent,
      cancelled: cancelled,
    );
    final collectionsElapsed = phase.elapsed;
    phase.reset();
    if (!isCurrent()) throw _scanCancelledException;
    if (libraryType == PlexLibraryType.show) {
      onPhase?.call(PlexLibraryScanPhase.showGenres);
    }
    final showGenres = libraryType == PlexLibraryType.show
        ? await libraryShowGenres(
            server,
            token,
            libraryId,
            isCurrent: isCurrent,
            cancelled: cancelled,
          )
        : const <String, List<String>>{};
    final showGenresElapsed = phase.elapsed;
    if (!isCurrent()) throw _scanCancelledException;
    return PlexLibraryScan(
      items: List.unmodifiable([
        for (final item in items)
          _annotateLibraryItem(item, collections.titlesByMember, showGenres),
      ]),
      collections: collections,
      timing: (
        items: itemsElapsed,
        collections: collectionsElapsed,
        showGenres: showGenresElapsed,
        collectionTitles: {
          for (final titles in collections.titlesByMember.values) ...titles,
        }.length,
        collectionMembers: collections.titlesByMember.length,
        shows: showGenres.length,
      ),
    );
  }

  Future<Map<String, List<String>>> libraryShowGenres(
    Uri server,
    String token,
    String libraryId, {
    required bool Function() isCurrent,
    Future<void>? cancelled,
  }) async {
    final rows = await _libraryMetadata(
      server
          .resolve('/library/sections/$libraryId/all')
          .replace(queryParameters: {'type': '2'}),
      token,
      checkCurrent: () {
        if (!isCurrent()) throw _scanCancelledException;
      },
      cancelled: cancelled,
      parseRow: (raw) => _record(raw, 'show'),
    );
    return Map.unmodifiable({
      for (final raw in rows)
        _id(_record(raw, 'show')['ratingKey'], 'show id'):
            List<String>.unmodifiable(_tagNames(_record(raw, 'show')['Genre'])),
    });
  }

  Future<PlexCollectionMembership> libraryCollectionMembership(
    Uri server,
    String token,
    String libraryId, {
    required bool Function() isCurrent,
    Future<void>? cancelled,
  }) async {
    final abort = Completer<void>();
    var callerCancelled = false;
    var finished = false;
    if (cancelled != null) {
      unawaited(
        cancelled.then((_) {
          if (finished) return;
          callerCancelled = true;
          if (!abort.isCompleted) abort.complete();
        }),
      );
    }
    void checkCurrent() {
      if (!isCurrent() || callerCancelled || abort.isCompleted) {
        if (!abort.isCompleted) abort.complete();
        throw _scanCancelledException;
      }
    }

    void stop() {
      if (!abort.isCompleted) abort.complete();
    }

    Future<List<({String key, String title})>> list() async {
      final raws = await _libraryMetadata(
        server
            .resolve('/library/sections/$libraryId/all')
            .replace(queryParameters: {'type': '18'}),
        token,
        checkCurrent: checkCurrent,
        cancelled: abort.future,
        maximumEntries: maximumLibraryCollections,
        parseRow: (raw) => _record(raw, 'collection'),
      );
      final result = <({String key, String title})>[];
      for (final raw in raws) {
        final row = _record(raw, 'collection');
        final key = _id(row['ratingKey'], 'collection id');
        final title = _optionalText(row['title']);
        if (title == null) {
          throw const PlexException(
            'parse-error',
            'Collection title was invalid.',
          );
        }
        if (_optionalInteger(row['childCount']) != 0) {
          result.add((key: key, title: title));
        }
      }
      return result;
    }

    const fatalCodes = {
      'auth-invalid',
      'auth-required',
      'access-denied',
      'cancelled',
    };
    try {
      checkCurrent();
      final List<({String key, String title})> records;
      try {
        records = await list();
      } on PlexException catch (error) {
        if (fatalCodes.contains(error.code)) rethrow;
        return const PlexCollectionMembership(unavailable: true);
      } catch (_) {
        checkCurrent();
        return const PlexCollectionMembership(unavailable: true);
      }
      Future<List<({String key, String title})>>? relisted;
      final members = <String, Set<String>>{};
      final failed = <String>{};
      PlexException? fatal;
      StackTrace? fatalStack;
      var scaleExceeded = false;
      var consumed = 0;
      var next = 0;
      Future<List<String>> children(String key) async {
        await _collectionRequests.acquire(checkCurrent, abort.future);
        try {
          return await _libraryMetadata(
            server.resolve(
              '/library/collections/${Uri.encodeComponent(key)}/children',
            ),
            token,
            checkCurrent: checkCurrent,
            cancelled: abort.future,
            allowOversizedComplete: true,
            parseRow: (raw) => _id(
              _record(raw, 'collection member')['ratingKey'],
              'collection member id',
            ),
            onPage: (count) {
              consumed += count;
              if (consumed > maximumLibraryCollectionMembers) {
                throw _libraryScaleException;
              }
            },
          );
        } finally {
          _collectionRequests.release();
        }
      }

      Future<void> worker() async {
        while (!abort.isCompleted) {
          checkCurrent();
          final index = next++;
          if (index >= records.length) return;
          final record = records[index];
          try {
            List<String> memberIds;
            try {
              memberIds = await children(record.key);
            } on PlexException catch (error) {
              if (error.code != 'resource-not-found') rethrow;
              final fresh = await (relisted ??= list());
              final matches = fresh
                  .where((r) => r.title == record.title)
                  .toList();
              if (matches.isEmpty) continue;
              final replacements = matches
                  .where((r) => r.key != record.key)
                  .toList();
              if (replacements.isEmpty) rethrow;
              memberIds = [];
              for (final replacement in replacements) {
                memberIds.addAll(await children(replacement.key));
              }
            }
            checkCurrent();
            for (final id in memberIds) {
              (members[id] ??= {}).add(record.title);
            }
          } on PlexException catch (error, stack) {
            if (fatalCodes.contains(error.code)) {
              // Sibling cancellation caused by our abort must not replace the
              // authorization or scale failure that caused it.
              if (!abort.isCompleted || callerCancelled || !isCurrent()) {
                fatal ??= error;
                fatalStack ??= stack;
              }
              stop();
              return;
            }
            if (error.code == 'library-scale-exceeded') {
              scaleExceeded = true;
              stop();
              return;
            }
            failed.add(record.title);
          } catch (_) {
            checkCurrent();
            failed.add(record.title);
          }
        }
      }

      await Future.wait(
        List.generate(records.length.clamp(0, 4), (_) => worker()),
      );
      if (fatal != null) Error.throwWithStackTrace(fatal!, fatalStack!);
      if (scaleExceeded) {
        return const PlexCollectionMembership(unavailable: true);
      }
      checkCurrent();
      return PlexCollectionMembership(
        titlesByMember: Map.unmodifiable({
          for (final entry in members.entries)
            if (entry.value.any((title) => !failed.contains(title)))
              entry.key: Set<String>.unmodifiable(
                entry.value.difference(failed),
              ),
        }),
        failedTitles: Set.unmodifiable(failed),
      );
    } finally {
      finished = true;
      stop();
    }
  }

  /// Strict library paging for the collection and show metadata streams.
  /// Children may exceed the requested size only when that page ends at total.
  Future<List<T>> _libraryMetadata<T>(
    Uri base,
    String token, {
    required void Function() checkCurrent,
    required T Function(Object? row) parseRow,
    Future<void>? cancelled,
    bool allowOversizedComplete = false,
    int maximumEntries = 100000,
    void Function(int count)? onPage,
  }) async {
    var wasCancelled = false;
    var finished = false;
    if (cancelled != null) {
      unawaited(
        cancelled.then((_) {
          if (!finished) wasCancelled = true;
        }),
      );
    }
    void check() {
      checkCurrent();
      if (wasCancelled) throw _scanCancelledException;
    }

    try {
      final rows = <T>[];
      final seen = <String>{};
      int? total;
      for (var page = 0; page < 1000; page++) {
        check();
        final start = rows.length;
        final json = await _serverJson(
          base.replace(
            queryParameters: {
              ...base.queryParameters,
              'X-Plex-Container-Start': '$start',
              'X-Plex-Container-Size': '100',
            },
          ),
          token,
          cancelled: cancelled,
        );
        check();
        final rawContainer = json['MediaContainer'];
        if (rawContainer is! Map) throw _libraryPageException;
        final pageTotal = _libraryPageCount(rawContainer['totalSize']);
        final size = _libraryPageCount(rawContainer['size']);
        final offset = _libraryPageCount(rawContainer['offset']);
        if (offset != null && offset != start) throw _libraryPageException;
        if (pageTotal != null) {
          if (total != null && total != pageTotal) {
            throw _libraryPageException;
          }
          total = pageTotal;
          if (total > maximumEntries) throw _libraryScaleException;
        }
        final rawRows = rawContainer['Metadata'];
        final List<Object?> metadata;
        if (rawRows is List) {
          metadata = rawRows;
        } else if (rawRows == null && size == 0) {
          metadata = const [];
        } else {
          throw _libraryPageException;
        }
        if (size != null && size != metadata.length) {
          throw _libraryPageException;
        }
        final end = start + metadata.length;
        if (metadata.length > 100 &&
            !(allowOversizedComplete && total == end)) {
          throw _libraryPageException;
        }
        if (total != null &&
            (end > total || (metadata.isEmpty && start < total))) {
          throw _libraryPageException;
        }
        if (end > maximumEntries) throw _libraryScaleException;
        for (final raw in metadata) {
          final id = _id(
            _record(raw, 'library metadata')['ratingKey'],
            'metadata id',
          );
          if (!seen.add(id)) {
            throw const PlexException(
              'library-page-not-progressing',
              'Plex returned a library page without progress.',
            );
          }
        }
        onPage?.call(metadata.length);
        rows.addAll(metadata.map(parseRow));
        if (total == rows.length || (total == null && metadata.isEmpty)) {
          return rows;
        }
      }
      throw _libraryScaleException;
    } finally {
      finished = true;
    }
  }

  Future<PlexPlaylistCatalog> playlists(
    Uri server,
    String token, {
    required bool Function() isCurrent,
    Future<void>? cancelled,
  }) async {
    void checkCurrent() {
      if (!isCurrent()) {
        throw const PlexException('cancelled', 'Library scan cancelled.');
      }
    }

    checkCurrent();
    // One attempt-local lifetime for this catalog load. The first fatal
    // authorization failure is recorded for propagation and aborts active
    // sibling IO through the existing abortable transport; a fresh retry gets
    // a fresh lifetime. Recoverable per-playlist failures never trigger it.
    final attemptAbort = Completer<void>();
    PlexException? fatal;
    StackTrace? fatalStack;
    void signalAttemptAbort() {
      if (!attemptAbort.isCompleted) attemptAbort.complete();
    }

    final Future<void> attemptCancelled;
    final callerCancelled = cancelled;
    if (callerCancelled == null) {
      attemptCancelled = attemptAbort.future;
    } else {
      final combined = Completer<void>();
      unawaited(
        callerCancelled.then((_) {
          if (!combined.isCompleted) combined.complete();
        }),
      );
      unawaited(
        attemptAbort.future.then((_) {
          if (!combined.isCompleted) combined.complete();
        }),
      );
      attemptCancelled = combined.future;
    }

    void checkAttemptCurrent() {
      checkCurrent();
      if (attemptAbort.isCompleted) {
        throw const PlexException('cancelled', 'Library scan cancelled.');
      }
    }

    // A catalog failure throws and never becomes a successful empty catalog.
    // A later contents-page failure for one playlist marks that playlist's
    // canonical id in failedIds without publishing its accumulated prefix.
    final catalogRecords = await _playlistCatalogRaws(
      server,
      token,
      cancelled: attemptCancelled,
      checkCurrent: checkCurrent,
    );
    checkCurrent();
    final output = <PlexPlaylist>[];
    final failed = <String>{};
    const fatalCodes = {'auth-invalid', 'auth-required', 'access-denied'};
    for (var start = 0; start < catalogRecords.length; start += 4) {
      checkCurrent();
      final batch = catalogRecords.skip(start).take(4).map((record) async {
        // The catalog carries one normalized identity per row; requests,
        // models, and failure accounting all reuse it.
        final id = record.id;
        try {
          final title = _text(record.playlist['title'], 'playlist title');
          final itemRaws = await _playlistItemRaws(
            server,
            token,
            id,
            cancelled: attemptCancelled,
            checkCurrent: checkAttemptCurrent,
          );
          checkAttemptCurrent();
          // Playable filtering applies after raw paging so unplayable records
          // never shift pagination offsets. Repeated media is intentional
          // programming and keeps its order; repeated supplied occurrence
          // identities fail the playlist inside [_playlistItemRaws].
          final items = itemRaws
              .map(parseMediaItem)
              .where((item) => item.isPlayable)
              .toList(growable: false);
          return items.isEmpty
              ? null
              : PlexPlaylist(id: id, title: title, items: items);
        } on PlexException catch (exception, stack) {
          checkCurrent();
          if (exception.code == 'cancelled') {
            if (fatal == null) rethrow;
            // Our own attempt abort converging on a sibling while the
            // recorded fatal propagates.
            return null;
          }
          if (fatalCodes.contains(exception.code)) {
            fatal ??= exception;
            fatalStack ??= stack;
            signalAttemptAbort();
            rethrow;
          }
          failed.add(id);
          return null;
        } catch (_) {
          checkCurrent();
          failed.add(id);
          return null;
        }
      });
      List<PlexPlaylist?> results;
      try {
        results = await Future.wait(batch);
      } on PlexException {
        checkCurrent();
        final firstFatal = fatal;
        if (firstFatal != null) {
          Error.throwWithStackTrace(firstFatal, fatalStack!);
        }
        rethrow;
      }
      checkCurrent();
      for (final playlist in results) {
        if (playlist != null) output.add(playlist);
      }
    }
    return PlexPlaylistCatalog(
      playlists: List.unmodifiable(output),
      failedIds: Set.unmodifiable(failed),
    );
  }

  /// Pages the complete video-playlist catalog as identified records.
  ///
  /// Every row must carry a usable identity before the catalog can complete:
  /// an unidentifiable row fails the whole catalog instead of becoming a
  /// successful absence. Catalog entries carry unique identities, so a
  /// repeated playlist id is a non-progressing page. Playlist *contents* use
  /// [_playlistItemRaws], which preserves repeated media but rejects repeated
  /// supplied occurrence identities.
  Future<List<({String id, Map<String, Object?> playlist})>>
  _playlistCatalogRaws(
    Uri server,
    String token, {
    required void Function() checkCurrent,
    Future<void>? cancelled,
  }) async {
    const pageSize = 100;
    const invalidRow = PlexException(
      'playlist-page-invalid',
      'Plex returned an invalid playlist page.',
    );
    final records = <({String id, Map<String, Object?> playlist})>[];
    final seenIds = <String>{};
    var start = 0;
    var rawConsumed = 0;
    int? knownTotal;
    for (var page = 0; page < 1000; page++) {
      checkCurrent();
      final json = await _serverJson(
        server
            .resolve('/playlists/all')
            .replace(
              queryParameters: {
                'playlistType': 'video',
                'X-Plex-Container-Start': '$start',
                'X-Plex-Container-Size': '$pageSize',
              },
            ),
        token,
        cancelled: cancelled,
      );
      checkCurrent();
      final validated = _validatePlaylistPage(
        json,
        start: start,
        pageSize: pageSize,
        rawConsumed: rawConsumed,
        knownTotal: knownTotal,
      );
      knownTotal = validated.knownTotal;
      for (final raw in validated.metadata) {
        if (raw is! Map) throw invalidRow;
        late final Map<String, Object?> playlist;
        try {
          playlist = Map<String, Object?>.from(raw);
        } catch (_) {
          throw invalidRow;
        }
        final id = _optionalId(playlist['ratingKey']);
        if (id == null) throw invalidRow;
        if (!seenIds.add(id)) {
          throw const PlexException(
            'playlist-page-not-progressing',
            'Plex returned a playlist page without progress.',
          );
        }
        records.add((id: id, playlist: playlist));
      }
      rawConsumed += validated.metadata.length;
      checkCurrent();
      final known = knownTotal;
      if (known != null) {
        if (rawConsumed == known) return records;
      } else if (validated.metadata.isEmpty) {
        return records;
      }
      start += validated.metadata.length;
    }
    throw const PlexException(
      'playlist-scale-exceeded',
      'This playlist catalog is too large to load safely.',
    );
  }

  /// Pages one playlist's complete ordered item stream.
  ///
  /// Repeated media is intentional programming and is preserved in order,
  /// including identical blocks straddling a page boundary. When Plex supplies
  /// a playlist occurrence identity (`playlistItemID`), that identity must be
  /// unique within the stream: a repeated occurrence contradicts the offsets
  /// and fails the whole playlist. Without occurrence identity the
  /// offset/count checks cannot prove an immutable snapshot through every
  /// concurrent edit; they detect available contradictions only.
  Future<List<Object?>> _playlistItemRaws(
    Uri server,
    String token,
    String playlistId, {
    required void Function() checkCurrent,
    Future<void>? cancelled,
  }) async {
    const pageSize = 100;
    const invalidOccurrence = PlexException(
      'playlist-page-invalid',
      'Plex returned an invalid playlist page.',
    );
    final raws = <Object?>[];
    final seenOccurrences = <String>{};
    var start = 0;
    var rawConsumed = 0;
    int? knownTotal;
    for (var page = 0; page < 1000; page++) {
      checkCurrent();
      final json = await _serverJson(
        server
            .resolve('/playlists/${Uri.encodeComponent(playlistId)}/items')
            .replace(
              queryParameters: {
                'X-Plex-Container-Start': '$start',
                'X-Plex-Container-Size': '$pageSize',
              },
            ),
        token,
        cancelled: cancelled,
      );
      checkCurrent();
      final validated = _validatePlaylistPage(
        json,
        start: start,
        pageSize: pageSize,
        rawConsumed: rawConsumed,
        knownTotal: knownTotal,
      );
      knownTotal = validated.knownTotal;
      for (final raw in validated.metadata) {
        final occurrence = raw is Map ? raw['playlistItemID'] : null;
        if (occurrence == null) continue;
        if (!seenOccurrences.add(_playlistOccurrenceId(occurrence))) {
          throw invalidOccurrence;
        }
      }
      raws.addAll(validated.metadata);
      rawConsumed += validated.metadata.length;
      checkCurrent();
      final known = knownTotal;
      if (known != null) {
        if (rawConsumed == known) return raws;
      } else if (validated.metadata.isEmpty) {
        return raws;
      }
      start += validated.metadata.length;
    }
    throw const PlexException(
      'playlist-scale-exceeded',
      'This playlist is too large to load safely.',
    );
  }

  List<PlexPlaybackPartDescriptor> playbackDescriptor({
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
    return List.unmodifiable([
      for (final part in mediaParts)
        (uri: _directPlayUri(server, part.path), duration: part.duration),
    ]);
  }

  Future<Uint8List> artwork(
    Uri server,
    String token,
    Uri path, {
    int maximumBytes = 4 * 1024 * 1024,
  }) async {
    if (canonicalPlexArtworkPath(path) == null) {
      throw const PlexException(
        'artwork-unavailable',
        'Program artwork is unavailable.',
      );
    }
    final uri = server.resolveUri(path);
    if (!_isSameServerUri(server, uri)) {
      throw const PlexException(
        'artwork-unavailable',
        'Program artwork is unavailable.',
      );
    }
    final response = await _send(
      'GET',
      uri,
      headers: _headers(token),
      maximumBytes: maximumBytes,
      oversizedCode: 'artwork-too-large',
      oversizedMessage: 'Program artwork is too large.',
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw PlexException(
        response.statusCode == 401 ? 'auth-invalid' : 'access-denied',
        response.statusCode == 401
            ? 'Plex authentication is no longer valid.'
            : 'This Plex profile cannot access that server.',
      );
    }
    if (response.statusCode != 200) {
      throw const PlexException(
        'artwork-unavailable',
        'Program artwork is unavailable.',
      );
    }
    return response.bodyBytes;
  }

  Future<Uint8List> metadataArtwork(
    Uri uri, {
    int maximumBytes = 4 * 1024 * 1024,
  }) async {
    if (canonicalPlexCastPortrait(uri) != uri || !uri.isAbsolute) {
      throw const PlexException(
        'artwork-unavailable',
        'Program artwork is unavailable.',
      );
    }
    final response = await _send(
      'GET',
      uri,
      headers: const {'Accept': 'image/*'},
      maximumBytes: maximumBytes,
      oversizedCode: 'artwork-too-large',
      oversizedMessage: 'Program artwork is too large.',
    );
    if (response.statusCode != 200) {
      throw const PlexException(
        'artwork-unavailable',
        'Program artwork is unavailable.',
      );
    }
    return response.bodyBytes;
  }

  void _cancel(Stream<List<int>> stream) {
    final subscription = stream.listen(
      null,
      onError: (Object _, StackTrace _) {},
    );
    unawaited(subscription.cancel().onError((_, _) {}));
  }

  Future<Map<String, Object?>> _serverJson(
    Uri uri,
    String token, {
    Future<void>? cancelled,
  }) async {
    final response = await _send(
      'GET',
      uri,
      headers: _headers(token),
      cancelled: cancelled,
    );
    return _json(response, {200});
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    Map<String, String>? bodyFields,
    Future<void>? cancelled,
    Duration? timeout,
    int maximumBytes = maximumControlResponseBytes,
    String oversizedCode = 'response-too-large',
    String oversizedMessage = 'Plex returned too much data.',
  }) async {
    final abort = Completer<void>();
    var finished = false;
    void abortRequest() {
      if (!abort.isCompleted) abort.complete();
    }

    if (cancelled != null) {
      unawaited(
        cancelled.then((_) {
          if (!finished) abortRequest();
        }),
      );
    }
    final request =
        http.AbortableRequest(method, uri, abortTrigger: abort.future)
          ..followRedirects = false
          ..headers.addAll(headers);
    if (bodyFields != null) request.bodyFields = bodyFields;
    final limit = timeout ?? requestTimeout;
    final elapsed = Stopwatch()..start();
    try {
      final pendingResponse = _http.send(request);
      late final http.StreamedResponse streamed;
      try {
        streamed = await pendingResponse.timeout(limit);
      } on TimeoutException {
        abortRequest();
        unawaited(
          pendingResponse
              .then((lateResponse) => _cancel(lateResponse.stream))
              .onError((_, _) {}),
        );
        rethrow;
      }
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        _cancel(streamed.stream);
        return http.Response.bytes(
          const [],
          streamed.statusCode,
          request: streamed.request ?? request,
          headers: streamed.headers,
          isRedirect: streamed.isRedirect,
          persistentConnection: streamed.persistentConnection,
          reasonPhrase: streamed.reasonPhrase,
        );
      }
      if ((streamed.contentLength ?? 0) > maximumBytes) {
        _cancel(streamed.stream);
        throw PlexException(oversizedCode, oversizedMessage);
      }
      final remaining = limit - elapsed.elapsed;
      if (remaining <= Duration.zero) {
        _cancel(streamed.stream);
        throw TimeoutException('Plex response deadline elapsed.');
      }
      final body = await _readBounded(
        streamed.stream,
        maximumBytes: maximumBytes,
        timeout: remaining,
        oversizedCode: oversizedCode,
        oversizedMessage: oversizedMessage,
      );
      return http.Response.bytes(
        body,
        streamed.statusCode,
        request: streamed.request ?? request,
        headers: streamed.headers,
        isRedirect: streamed.isRedirect,
        persistentConnection: streamed.persistentConnection,
        reasonPhrase: streamed.reasonPhrase,
      );
    } on TimeoutException {
      abortRequest();
      throw const PlexException(
        'network-timeout',
        'Plex did not respond in time. Try again.',
      );
    } on http.RequestAbortedException {
      throw const PlexException('cancelled', 'Library scan cancelled.');
    } on SocketException {
      throw const PlexException(
        'network-unavailable',
        'Plex could not be reached.',
      );
    } on http.ClientException {
      throw const PlexException(
        'network-unavailable',
        'Plex could not be reached.',
      );
    } finally {
      finished = true;
    }
  }

  Future<Uint8List> _readBounded(
    Stream<List<int>> stream, {
    required int maximumBytes,
    required Duration timeout,
    required String oversizedCode,
    required String oversizedMessage,
  }) {
    final completer = Completer<Uint8List>();
    final bytes = BytesBuilder(copy: false);
    StreamSubscription<List<int>>? subscription;

    void finishError(Object error, StackTrace stackTrace) {
      if (completer.isCompleted) return;
      final activeSubscription = subscription;
      if (activeSubscription != null) {
        unawaited(activeSubscription.cancel().onError((_, _) {}));
      }
      completer.completeError(error, stackTrace);
    }

    final timer = Timer(
      timeout,
      () => finishError(
        TimeoutException('Plex response deadline elapsed.'),
        StackTrace.current,
      ),
    );
    subscription = stream.listen(
      (chunk) {
        if (bytes.length + chunk.length > maximumBytes) {
          timer.cancel();
          finishError(
            PlexException(oversizedCode, oversizedMessage),
            StackTrace.current,
          );
          return;
        }
        bytes.add(chunk);
      },
      onError: (Object error, StackTrace stackTrace) {
        timer.cancel();
        finishError(error, stackTrace);
      },
      onDone: () {
        timer.cancel();
        if (!completer.isCompleted) completer.complete(bytes.takeBytes());
      },
      cancelOnError: false,
    );
    return completer.future;
  }

  void close() => _http.close();
}

const _scanCancelledException = PlexException(
  'cancelled',
  'Library scan cancelled.',
);
const _libraryPageException = PlexException(
  'library-page-invalid',
  'Plex returned an invalid library page.',
);
const _libraryScaleException = PlexException(
  'library-scale-exceeded',
  'This library is too large to scan safely.',
);

/// Shared by concurrent library attempts on this client, with cancellable
/// waiters. The attempt owns a permit until all pages for that collection end.
class _CollectionRequestPool {
  _CollectionRequestPool(this.limit);
  final int limit;
  int _active = 0;
  final Set<Completer<void>> _waiters = {};

  Future<void> acquire(
    void Function() checkCurrent,
    Future<void> cancelled,
  ) async {
    while (true) {
      checkCurrent();
      if (_active < limit) {
        _active++;
        return;
      }
      final waiter = Completer<void>();
      _waiters.add(waiter);
      try {
        await Future.any([waiter.future, cancelled]);
      } finally {
        _waiters.remove(waiter);
      }
    }
  }

  void release() {
    _active--;
    for (final waiter in _waiters.toList()) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }
}

PlexMediaItem _annotateLibraryItem(
  PlexMediaItem item,
  Map<String, Set<String>> titlesByMember,
  Map<String, List<String>> showGenres,
) {
  final collections = <String>{
    ...?titlesByMember[item.id],
    ...?titlesByMember[item.parentRatingKey],
    ...?titlesByMember[item.grandparentRatingKey],
  };
  final genres = <String>{
    ...item.genres,
    if (item.type == 'episode') ...?showGenres[item.grandparentRatingKey],
  };
  return PlexMediaItem(
    id: item.id,
    title: item.title,
    type: item.type,
    duration: item.duration,
    libraryId: item.libraryId,
    parentTitle: item.parentTitle,
    grandparentTitle: item.grandparentTitle,
    parentRatingKey: item.parentRatingKey,
    grandparentRatingKey: item.grandparentRatingKey,
    thumbPath: item.thumbPath,
    grandparentThumbPath: item.grandparentThumbPath,
    artPath: item.artPath,
    clearLogoPath: item.clearLogoPath,
    parts: item.parts,
    container: item.container,
    videoCodec: item.videoCodec,
    audioCodec: item.audioCodec,
    dynamicRange: item.dynamicRange,
    directors: item.directors,
    actors: item.actors,
    cast: item.cast,
    studio: item.studio,
    year: item.year,
    summary: item.summary,
    contentRating: item.contentRating,
    seasonNumber: item.seasonNumber,
    episodeNumber: item.episodeNumber,
    videoResolution: item.videoResolution,
    audioChannels: item.audioChannels,
    addedAt: item.addedAt,
    viewed: item.viewed,
    collections: List.unmodifiable(collections),
    genres: List.unmodifiable(genres),
  );
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
  final cast = _castMembers(json['Role']);
  final media = (json['Media'] as List? ?? const [])
      .whereType<Map>()
      .firstOrNull;
  final parts = (media?['Part'] as List? ?? const [])
      .whereType<Map>()
      .map(_parseMediaPart)
      .nonNulls
      .toList(growable: false);
  final firstPart = (media?['Part'] as List? ?? const [])
      .whereType<Map>()
      .firstOrNull;
  return PlexMediaItem(
    id: _id(json['ratingKey'], 'media id'),
    title: _text(json['title'], 'media title'),
    type: _text(json['type'], 'media type'),
    duration: Duration(milliseconds: _optionalInteger(json['duration']) ?? 0),
    libraryId: libraryId,
    parentTitle: _optionalText(json['parentTitle']),
    grandparentTitle: _optionalText(json['grandparentTitle']),
    parentRatingKey: _optionalId(json['parentRatingKey']),
    grandparentRatingKey: _optionalId(json['grandparentRatingKey']),
    thumbPath: canonicalPlexArtworkPathText(_optionalText(json['thumb'])),
    grandparentThumbPath: canonicalPlexArtworkPathText(
      _optionalText(json['grandparentThumb']),
    ),
    artPath: canonicalPlexArtworkPathText(_optionalText(json['art'])),
    clearLogoPath: _clearLogoPath(json['Image']),
    parts: List.unmodifiable(parts),
    container: _optionalText(media?['container'])?.toLowerCase(),
    videoCodec: _optionalText(media?['videoCodec'])?.toLowerCase(),
    audioCodec: _optionalText(media?['audioCodec'])?.toLowerCase(),
    dynamicRange: _dynamicRange(media, _streamCodecs(firstPart)),
    genres: _tagNames(json['Genre']),
    collections: _tagNames(json['Collection']),
    directors: _personNames(json['Director']),
    actors: _personNames(json['Role']),
    cast: cast,
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

PlexMediaPart? _parseMediaPart(Map raw) {
  final path = _optionalText(raw['key']);
  if (path == null) return null;
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
    final url = canonicalPlexArtworkPathText(_optionalText(entry['url']));
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

List<String> _personNames(Object? raw) {
  final names = <String>[];
  final seen = <String>{};
  for (final name in _tagNames(raw)) {
    if (seen.add(name.toLowerCase())) names.add(name);
  }
  return names;
}

List<PlexCastMember> _castMembers(Object? raw) {
  final members = <PlexCastMember>[];
  final names = <String>{};
  for (final value in raw as List? ?? const []) {
    if (value is! Map) continue;
    final name = _optionalText(value['tag']);
    if (name == null || !names.add(name.toLowerCase())) continue;
    members.add(
      PlexCastMember(
        name: name,
        role: _optionalText(value['role']),
        thumbPath: canonicalPlexCastPortraitText(_optionalText(value['thumb'])),
      ),
    );
    if (members.length == maxRichCastMembers) break;
  }
  return List.unmodifiable(members);
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

  try {
    final json = jsonDecode(body);
    if (json is! Map && json is! List) {
      throw const PlexException(
        'parse-error',
        'Plex Home response was invalid.',
      );
    }
    visit(json);
  } on FormatException {
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
    } catch (_) {
      throw const PlexException(
        'parse-error',
        'Plex Home response was invalid.',
      );
    }
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
      admin: _boolean(normalized['admin'] ?? normalized['isadmin']),
      restricted: normalized.containsKey('restricted')
          ? _boolean(normalized['restricted'])
          : null,
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
String? _optionalId(Object? value) =>
    value is num ? value.toString() : _optionalText(value);
int _integer(Object? value, String label) => value is num
    ? value.toInt()
    : int.tryParse(value?.toString() ?? '') ??
          (throw PlexException('parse-error', '$label was invalid.'));
const _maxExactJsonInteger = 0x1fffffffffffff;

/// Validates one playlist page against the pagination contract shared by the
/// video-playlist catalog and playlist item streams: container shape,
/// echoed offset, retained total, declared size, oversized pages, and
/// empty/over-total pages. Returns the page records and the retained total.
({List<Object?> metadata, int? knownTotal}) _validatePlaylistPage(
  Map<String, Object?> json, {
  required int start,
  required int pageSize,
  required int rawConsumed,
  required int? knownTotal,
}) {
  const invalid = PlexException(
    'playlist-page-invalid',
    'Plex returned an invalid playlist page.',
  );
  final containerRaw = json['MediaContainer'];
  if (containerRaw is! Map) throw invalid;
  final container = Map<String, Object?>.from(containerRaw);
  final pageTotal = _playlistPageCount(container['totalSize']);
  final pageSizeValue = _playlistPageCount(container['size']);
  final pageOffset = _playlistPageCount(container['offset']);
  if (pageOffset != null && pageOffset != start) throw invalid;
  var known = knownTotal;
  if (pageTotal != null) {
    if (known == null) {
      known = pageTotal;
    } else if (known != pageTotal) {
      throw invalid;
    }
  }
  final rawMetadata = container['Metadata'];
  final List<Object?> metadata;
  if (rawMetadata == null) {
    if (pageSizeValue == 0) {
      metadata = const [];
    } else {
      throw invalid;
    }
  } else if (rawMetadata is List) {
    metadata = rawMetadata;
  } else {
    throw invalid;
  }
  if (metadata.length > pageSize) {
    throw const PlexException(
      'playlist-page-too-large',
      'Plex returned more playlist items than requested.',
    );
  }
  if (pageSizeValue != null && pageSizeValue != metadata.length) throw invalid;
  final total = known;
  if (total != null) {
    if (rawConsumed + metadata.length > total) throw invalid;
    if (metadata.isEmpty && rawConsumed < total) throw invalid;
  }
  return (metadata: metadata, knownTotal: known);
}

/// Normalizes a supplied playlist occurrence identity to its canonical form.
///
/// The documented numeric occurrence id arrives as an integral JSON number or
/// its ordinary decimal-string form. Any other supplied value is contradictory
/// identity evidence and fails the page. Absent identity never reaches this
/// helper; the caller skips it to stay compatible.
String _playlistOccurrenceId(Object? value) {
  const invalid = PlexException(
    'playlist-page-invalid',
    'Plex returned an invalid playlist page.',
  );
  final number = switch (value) {
    num number => number,
    String text => num.tryParse(text.trim()),
    _ => null,
  };
  if (number == null ||
      !number.isFinite ||
      number.abs() > _maxExactJsonInteger ||
      number.toInt() != number) {
    throw invalid;
  }
  return number.toInt().toString();
}

/// Validates an optional playlist container count. Absent values stay absent;
/// present values must be nonnegative integral counts or the page is invalid.
int? _playlistPageCount(Object? value) {
  if (value == null) return null;
  final number = switch (value) {
    num number => number,
    String text => num.tryParse(text.trim()),
    _ => null,
  };
  if (number == null ||
      !number.isFinite ||
      number.isNegative ||
      number.abs() > _maxExactJsonInteger ||
      number.toInt() != number) {
    throw const PlexException(
      'playlist-page-invalid',
      'Plex returned an invalid playlist page.',
    );
  }
  return number.toInt();
}

/// Validates an optional library container count. Absent values stay absent;
/// present values must be nonnegative integral counts or the page is invalid.
int? _libraryPageCount(Object? value) {
  if (value == null) return null;
  final number = switch (value) {
    num number => number,
    String text => num.tryParse(text.trim()),
    _ => null,
  };
  if (number == null ||
      !number.isFinite ||
      number.isNegative ||
      number.abs() > _maxExactJsonInteger ||
      number.toInt() != number) {
    throw const PlexException(
      'library-page-invalid',
      'Plex returned an invalid library page.',
    );
  }
  return number.toInt();
}

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
