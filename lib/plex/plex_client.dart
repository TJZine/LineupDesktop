import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../app_version.dart';
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

  static const maximumLibraryCollections = 100000;
  static const maximumLibraryCollectionMembers = 100000;
  static const maximumLibraryMetadataPages = 1000;
  static const maximumLibraryItemPages = 1000;
  static const maximumPlaylistCatalogPages = 1000;
  static const maximumPlaylistItemPages = 1000;
  static const maximumLibraryMetadataEntries = 100000;
  final _collectionRequests = _CollectionRequestPool(8);

  Map<String, String> _headers([String? token]) => {
    'Accept': 'application/json',
    'X-Plex-Client-Identifier': clientIdentifier,
    'X-Plex-Product': 'Lineup Desktop',
    'X-Plex-Version': lineupVersion,
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
      expiresAt: _parsePinExpiration(json['expiresAt']),
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
      for (final rawConnection in _optionalList(json['connections'])) {
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
              if (!error.isAuthorizationFailure) {
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

  Future<List<PlexCastMember>> itemCast(
    Uri server,
    String token,
    String ratingKey, {
    Future<void>? cancelled,
  }) async {
    const invalid = PlexException(
      'cast-detail-invalid',
      'Plex returned invalid cast detail.',
    );
    if (ratingKey.trim().isEmpty) throw invalid;
    final uri = server
        .resolve('/library/metadata/')
        .replace(pathSegments: ['library', 'metadata', ratingKey]);
    final json = await _serverJson(uri, token, cancelled: cancelled);
    final container = json['MediaContainer'];
    if (container is! Map) throw invalid;
    final rows = container['Metadata'];
    if (rows is! List || rows.length != 1) throw invalid;
    final row = rows.single;
    if (row is! Map ||
        _optionalId(row['ratingKey']) != ratingKey ||
        (row['Role'] != null && row['Role'] is! List)) {
      throw invalid;
    }
    return _castMembers(row['Role']);
  }

  Future<List<PlexLibrary>> libraries(Uri server, String token) async {
    final json = await _serverJson(server.resolve('/library/sections'), token);
    const invalid = PlexException(
      'parse-error',
      'Plex returned an invalid library inventory.',
    );
    final container = json['MediaContainer'];
    if (container is! Map) throw invalid;
    final size = _pageCount(container['size'], _libraryPageException);
    final rawDirectories = container['Directory'];
    final List<Object?> directories;
    if (!container.containsKey('Directory') && size == 0) {
      directories = const [];
    } else if (rawDirectories is List) {
      directories = rawDirectories;
    } else {
      throw invalid;
    }
    if (size != null && size != directories.length) throw invalid;
    for (final raw in directories) {
      if (raw is! Map || _optionalText(raw['type']) == null) throw invalid;
    }
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
    final seenIds = <String>{};
    void checkCurrent() {
      if (!isCurrent()) throw _scanCancelledException;
    }

    return _pageMetadata(
      request: (start) => server
          .resolve('/library/sections/$libraryId/all')
          .replace(
            queryParameters: {
              'type': libraryType == PlexLibraryType.show ? '4' : '1',
              'X-Plex-Container-Start': '$start',
              'X-Plex-Container-Size': '100',
            },
          ),
      token: token,
      cancelled: cancelled,
      checkCurrent: checkCurrent,
      maximumPages: maximumLibraryItemPages,
      invalid: _libraryPageException,
      oversized: const PlexException(
        'library-page-too-large',
        'Plex returned more library items than requested.',
      ),
      pageLimit: () => const PlexException(
        'library-scale-exceeded',
        'This library is too large to scan safely.',
      ),
      parsePage: (metadata) {
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
        return pageItems;
      },
      onProgress: onProgress,
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
    unawaited(
      _joinCancellation(
        cancelled,
        abort,
        isFinished: () => finished,
        onCallerCancelled: () => callerCancelled = true,
      ),
    );
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
      final List<Map<String, Object?>> raws;
      try {
        raws = await _libraryMetadata(
          server
              .resolve('/library/sections/$libraryId/all')
              .replace(queryParameters: {'type': '18'}),
          token,
          checkCurrent: checkCurrent,
          cancelled: abort.future,
          maximumEntries: maximumLibraryCollections,
          parseRow: (raw) => _record(raw, 'collection'),
        );
      } on PlexException catch (error) {
        if (error is _LibraryMetadataPageLimitException) rethrow;
        if (error.code == 'library-scale-exceeded') {
          throw const _CollectionListingScaleException();
        }
        rethrow;
      }
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

    try {
      checkCurrent();
      final List<({String key, String title})> records;
      try {
        records = await list();
      } on PlexException catch (error) {
        if (error.isAuthorizationFailure || error.isCancellation) rethrow;
        return PlexCollectionMembership(
          failure: error is _LibraryMetadataPageLimitException
              ? PlexCollectionFailure.pagingLimitExceeded
              : error is _CollectionListingScaleException
              ? PlexCollectionFailure.listingLimitExceeded
              : PlexCollectionFailure.transient,
        );
      } catch (_) {
        checkCurrent();
        return const PlexCollectionMembership(
          failure: PlexCollectionFailure.transient,
        );
      }
      Future<List<({String key, String title})>>? relisted;
      final members = <String, Set<String>>{};
      final failed = <String>{};
      PlexException? fatal;
      StackTrace? fatalStack;
      PlexCollectionFailure? scaleFailure;
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
            if (error.isAuthorizationFailure || error.isCancellation) {
              if (!abort.isCompleted || callerCancelled || !isCurrent()) {
                fatal ??= error;
                fatalStack ??= stack;
              }
              stop();
              return;
            }
            if (error.code == 'library-scale-exceeded') {
              if (error is _CollectionListingScaleException) {
                scaleFailure = PlexCollectionFailure.listingLimitExceeded;
              } else {
                scaleFailure ??= error is _LibraryMetadataPageLimitException
                    ? PlexCollectionFailure.pagingLimitExceeded
                    : PlexCollectionFailure.memberLimitExceeded;
              }
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
      if (scaleFailure != null) {
        return PlexCollectionMembership(failure: scaleFailure);
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

  Future<List<T>> _libraryMetadata<T>(
    Uri base,
    String token, {
    required void Function() checkCurrent,
    required T Function(Object? row) parseRow,
    Future<void>? cancelled,
    bool allowOversizedComplete = false,
    int maximumEntries = maximumLibraryMetadataEntries,
    void Function(int count)? onPage,
  }) async {
    final abort = Completer<void>();
    var finished = false;
    final cancellation = _joinCancellation(
      cancelled,
      abort,
      isFinished: () => finished,
    );
    void check() {
      checkCurrent();
      if (abort.isCompleted) throw _scanCancelledException;
    }

    final seen = <String>{};
    try {
      return await _pageMetadata(
        request: (start) => base.replace(
          queryParameters: {
            ...base.queryParameters,
            'X-Plex-Container-Start': '$start',
            'X-Plex-Container-Size': '100',
          },
        ),
        token: token,
        cancelled: cancellation,
        checkCurrent: check,
        maximumPages: maximumLibraryMetadataPages,
        maximumEntries: maximumEntries,
        entryLimit: () => _libraryScaleException,
        invalid: _libraryPageException,
        oversized: _libraryPageException,
        allowOversizedComplete: allowOversizedComplete,
        pageLimit: () => const _LibraryMetadataPageLimitException(),
        // Metadata callbacks may stop sibling work; retain their original
        // ordering without introducing a new currentness check after parsing.
        checkAfterPage: false,
        parsePage: (metadata) {
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
          return metadata.map(parseRow);
        },
      );
    } finally {
      finished = true;
    }
  }

  Future<PlexPlaylistCatalog> playlists(
    Uri server,
    String token, {
    required bool Function() isCurrent,
    Future<void>? cancelled,
    void Function(PlexPlaylistProgress progress)? onProgress,
  }) async {
    void checkCurrent() {
      if (!isCurrent()) {
        throw _scanCancelledException;
      }
    }

    checkCurrent();
    onProgress?.call(const PlexPlaylistProgress());
    final attemptAbort = Completer<void>();
    PlexException? fatal;
    StackTrace? fatalStack;
    void signalAttemptAbort() {
      if (!attemptAbort.isCompleted) attemptAbort.complete();
    }

    final attemptCancelled = _joinCancellation(
      cancelled,
      attemptAbort,
      callerAbortsLocal: false,
    );

    void checkAttemptCurrent() {
      checkCurrent();
      if (attemptAbort.isCompleted) {
        throw _scanCancelledException;
      }
    }

    final catalogRecords = await _playlistCatalogRaws(
      server,
      token,
      cancelled: attemptCancelled,
      checkCurrent: checkCurrent,
    );
    checkCurrent();
    onProgress?.call(
      PlexPlaylistProgress(totalPlaylists: catalogRecords.length),
    );
    final output = <PlexPlaylist>[];
    final failed = <String>{};
    for (var start = 0; start < catalogRecords.length; start += 4) {
      checkCurrent();
      final batch = catalogRecords.skip(start).take(4).map((record) async {
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
          final items = itemRaws
              .map(parseMediaItem)
              .where((item) => item.isPlayable)
              .toList(growable: false);
          return items.isEmpty
              ? null
              : PlexPlaylist(id: id, title: title, items: items);
        } on PlexException catch (exception, stack) {
          checkCurrent();
          if (exception.isCancellation) {
            if (fatal == null) rethrow;
            return null;
          }
          if (exception.isAuthorizationFailure) {
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
      onProgress?.call(
        PlexPlaylistProgress(
          completedPlaylists: (start + results.length).clamp(
            0,
            catalogRecords.length,
          ),
          totalPlaylists: catalogRecords.length,
        ),
      );
      for (final playlist in results) {
        if (playlist != null) output.add(playlist);
      }
    }
    return PlexPlaylistCatalog(
      playlists: List.unmodifiable(output),
      failedIds: Set.unmodifiable(failed),
    );
  }

  Future<List<({String id, Map<String, Object?> playlist})>>
  _playlistCatalogRaws(
    Uri server,
    String token, {
    required void Function() checkCurrent,
    Future<void>? cancelled,
  }) async {
    const invalidRow = PlexException(
      'playlist-page-invalid',
      'Plex returned an invalid playlist page.',
    );
    final seenIds = <String>{};
    return _pageMetadata(
      request: (start) => server
          .resolve('/playlists/all')
          .replace(
            queryParameters: {
              'playlistType': 'video',
              'X-Plex-Container-Start': '$start',
              'X-Plex-Container-Size': '100',
            },
          ),
      token: token,
      cancelled: cancelled,
      checkCurrent: checkCurrent,
      maximumPages: maximumPlaylistCatalogPages,
      invalid: _playlistPageException,
      oversized: _playlistOversizedException,
      pageLimit: () => const PlexException(
        'playlist-scale-exceeded',
        'This playlist catalog is too large to load safely.',
      ),
      parsePage: (metadata) {
        final records = <({String id, Map<String, Object?> playlist})>[];
        for (final raw in metadata) {
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
        return records;
      },
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
    const invalidOccurrence = PlexException(
      'playlist-page-invalid',
      'Plex returned an invalid playlist page.',
    );
    final seenOccurrences = <String>{};
    return _pageMetadata(
      request: (start) => server
          .resolve('/playlists/${Uri.encodeComponent(playlistId)}/items')
          .replace(
            queryParameters: {
              'X-Plex-Container-Start': '$start',
              'X-Plex-Container-Size': '100',
            },
          ),
      token: token,
      cancelled: cancelled,
      checkCurrent: checkCurrent,
      maximumPages: maximumPlaylistItemPages,
      invalid: _playlistPageException,
      oversized: _playlistOversizedException,
      pageLimit: () => const PlexException(
        'playlist-scale-exceeded',
        'This playlist is too large to load safely.',
      ),
      parsePage: (metadata) {
        for (final raw in metadata) {
          final occurrence = raw is Map ? raw['playlistItemID'] : null;
          if (occurrence == null) continue;
          if (!seenOccurrences.add(_playlistOccurrenceId(occurrence))) {
            throw invalidOccurrence;
          }
        }
        return metadata;
      },
    );
  }

  /// Owns envelope validation and raw-row progress, leaving identity and error
  /// classification to each endpoint. Parsed/filtered output never sets offsets.
  Future<List<T>> _pageMetadata<T>({
    required Uri Function(int start) request,
    required String token,
    required void Function() checkCurrent,
    required int maximumPages,
    required PlexException invalid,
    required PlexException oversized,
    required PlexException Function() pageLimit,
    required Iterable<T> Function(List<Object?> metadata) parsePage,
    Future<void>? cancelled,
    int? maximumEntries,
    PlexException Function()? entryLimit,
    bool allowOversizedComplete = false,
    bool checkAfterPage = true,
    void Function(PlexLibraryPageProgress progress)? onProgress,
  }) async {
    final rows = <T>[];
    var rawConsumed = 0;
    int? knownTotal;
    void validateEntries(int count) {
      if (maximumEntries != null && count > maximumEntries) {
        throw entryLimit!();
      }
    }

    for (var page = 0; page < maximumPages; page++) {
      checkCurrent();
      final json = await _serverJson(
        request(rawConsumed),
        token,
        cancelled: cancelled,
      );
      checkCurrent();
      final validated = _validatePageEnvelope(
        json,
        start: rawConsumed,
        pageSize: 100,
        rawConsumed: rawConsumed,
        knownTotal: knownTotal,
        invalid: invalid,
        oversized: oversized,
        allowOversizedComplete: allowOversizedComplete,
        validateDeclaredTotal: validateEntries,
      );
      knownTotal = validated.knownTotal;
      final metadata = validated.metadata;
      validateEntries(rawConsumed + metadata.length);
      rows.addAll(parsePage(metadata));
      rawConsumed += metadata.length;
      if (checkAfterPage) checkCurrent();
      onProgress?.call((
        completedPages: page + 1,
        completedItems: rows.length,
        totalItems: knownTotal,
      ));
      if (rawConsumed == knownTotal ||
          (knownTotal == null && metadata.isEmpty)) {
        return rows;
      }
    }
    throw pageLimit();
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

  /// Fetches program artwork from the selected server. With [width] and
  /// [height], the server's photo transcoder returns the artwork scaled to
  /// cover that physical-pixel box (`minSize=1`) without upscaling, so a
  /// display slot never receives fewer pixels than it paints nor a 4K
  /// original it would only discard.
  Future<Uint8List> artwork(
    Uri server,
    String token,
    Uri path, {
    int? width,
    int? height,
    int maximumBytes = 4 * 1024 * 1024,
  }) async {
    final sized = width != null || height != null;
    if (canonicalPlexArtworkPath(path) == null ||
        (sized &&
            (width == null ||
                height == null ||
                width < 1 ||
                width > 4096 ||
                height < 1 ||
                height > 4096))) {
      throw const PlexException(
        'artwork-unavailable',
        'Program artwork is unavailable.',
      );
    }
    final uri = sized
        ? server
              .resolve('/photo/:/transcode')
              .replace(
                queryParameters: {
                  'width': '$width',
                  'height': '$height',
                  'minSize': '1',
                  'upscale': '0',
                  'url': path.toString(),
                },
              )
        : server.resolveUri(path);
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

  Future<Uint8List> castPortraitArtwork(
    Uri server,
    String token,
    Uri portrait, {
    required int width,
    required int height,
    int maximumBytes = 4 * 1024 * 1024,
  }) async {
    if (canonicalPlexCastPortrait(portrait) != portrait ||
        width < 1 ||
        width > 4096 ||
        height < 1 ||
        height > 4096) {
      throw const PlexException(
        'artwork-unavailable',
        'Cast portrait is unavailable.',
      );
    }
    final uri = server
        .resolve('/photo/:/transcode')
        .replace(
          queryParameters: {
            'width': '$width',
            'height': '$height',
            'minSize': '1',
            'upscale': '1',
            'url': portrait.toString(),
          },
        );
    if (!_isSameServerUri(server, uri)) {
      throw const PlexException(
        'artwork-unavailable',
        'Cast portrait is unavailable.',
      );
    }
    final response = await _send(
      'GET',
      uri,
      headers: _headers(token),
      maximumBytes: maximumBytes,
      oversizedCode: 'artwork-too-large',
      oversizedMessage: 'Cast portrait is too large.',
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw PlexException(
        response.statusCode == 401 ? 'auth-invalid' : 'access-denied',
        'Cast portrait authorization failed.',
      );
    }
    if (response.statusCode != 200) {
      throw const PlexException(
        'artwork-unavailable',
        'Cast portrait is unavailable.',
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

    unawaited(_joinCancellation(cancelled, abort, isFinished: () => finished));
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
      throw _scanCancelledException;
    } on TlsException {
      throw const PlexException(
        'network-unavailable',
        'Plex could not be reached.',
      );
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

/// Joins caller cancellation and a local abort signal, retaining each
/// operation's policy for whether caller cancellation also aborts local work.
Future<void> _joinCancellation(
  Future<void>? caller,
  Completer<void> localAbort, {
  bool callerAbortsLocal = true,
  bool Function()? isFinished,
  void Function()? onCallerCancelled,
}) {
  if (caller == null) return localAbort.future;
  final joined = callerAbortsLocal ? localAbort : Completer<void>();
  void complete() {
    if (!joined.isCompleted) joined.complete();
  }

  if (!callerAbortsLocal) {
    unawaited(localAbort.future.then((_) => complete()));
  }
  unawaited(
    caller.then((_) {
      if (isFinished?.call() ?? false) return;
      onCallerCancelled?.call();
      complete();
    }),
  );
  return joined.future;
}

const _playlistOversizedException = PlexException(
  'playlist-page-too-large',
  'Plex returned more playlist items than requested.',
);

const _libraryPageException = PlexException(
  'library-page-invalid',
  'Plex returned an invalid library page.',
);
const _libraryScaleException = PlexException(
  'library-scale-exceeded',
  'This library is too large to scan safely.',
);

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
  return PlexMediaItem.withTags(
    item,
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
  final media = _structuralList(
    json['Media'],
    'Media',
  ).whereType<Map<Object?, Object?>>().firstOrNull;
  final rawParts = _structuralList(media?['Part'], 'Part');
  final parts = rawParts
      .whereType<Map<Object?, Object?>>()
      .map(_parseMediaPart)
      .nonNulls
      .toList(growable: false);
  final firstPart = rawParts.whereType<Map<Object?, Object?>>().firstOrNull;
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

PlexMediaPart? _parseMediaPart(Map<Object?, Object?> raw) {
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

List<String> _streamCodecs(Map<Object?, Object?>? part) {
  final codecs = <String>[];
  for (final rawStream in _structuralList(part?['Stream'], 'Stream')) {
    if (rawStream case {'codec': final String codec}) codecs.add(codec);
  }
  return codecs;
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
  for (final value in _optionalList(raw)) {
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
  final names = <String, int>{};
  for (final value in _optionalList(raw)) {
    if (value is! Map) continue;
    final name = _optionalText(value['tag']);
    if (name == null) continue;
    final portrait = canonicalPlexCastPortraitText(
      _optionalText(value['thumb']),
    );
    final index = names[name.toLowerCase()];
    if (index != null) {
      final first = members[index];
      if (first.thumbPath == null && portrait != null) {
        members[index] = PlexCastMember(
          name: first.name,
          role: first.role,
          thumbPath: portrait,
        );
      }
    } else if (members.length < maxRichCastMembers) {
      names[name.toLowerCase()] = members.length;
      members.add(
        PlexCastMember(
          name: name,
          role: _optionalText(value['role']),
          thumbPath: portrait,
        ),
      );
    }
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
              ? rawUsers.addAll(List<Object?>.from(entry.value as List))
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

String _text(Object? value, String label) =>
    _optionalText(value) ??
    (throw PlexException('parse-error', '$label was missing.'));
DateTime _parsePinExpiration(Object? value) {
  final parsed = DateTime.tryParse(_text(value, 'PIN expiration'));
  if (parsed != null) return parsed;
  throw const PlexException('parse-error', 'PIN expiration was invalid.');
}

List<Object?> _optionalList(Object? raw) =>
    raw is List ? List<Object?>.from(raw) : const [];

List<Object?> _structuralList(Object? raw, String label) {
  if (raw == null) return const [];
  if (raw is List) return List<Object?>.from(raw);
  throw PlexException('parse-error', '$label was invalid.');
}

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

const _playlistPageException = PlexException(
  'playlist-page-invalid',
  'Plex returned an invalid playlist page.',
);

({List<Object?> metadata, int? knownTotal}) _validatePageEnvelope(
  Map<String, Object?> json, {
  required int start,
  required int pageSize,
  required int rawConsumed,
  required int? knownTotal,
  required PlexException invalid,
  required PlexException oversized,
  bool allowOversizedComplete = false,
  void Function(int total)? validateDeclaredTotal,
}) {
  final containerRaw = json['MediaContainer'];
  if (containerRaw is! Map) throw invalid;
  final container = Map<String, Object?>.from(containerRaw);
  final pageTotal = _pageCount(container['totalSize'], invalid);
  final pageSizeValue = _pageCount(container['size'], invalid);
  final pageOffset = _pageCount(container['offset'], invalid);
  if (pageOffset != null && pageOffset != start) throw invalid;
  var known = knownTotal;
  if (pageTotal != null) {
    if (known != null && known != pageTotal) throw invalid;
    known = pageTotal;
    validateDeclaredTotal?.call(pageTotal);
  }
  final rawMetadata = container['Metadata'];
  final List<Object?> metadata;
  if (rawMetadata is List) {
    metadata = rawMetadata;
  } else if (rawMetadata == null && pageSizeValue == 0) {
    metadata = const [];
  } else {
    throw invalid;
  }
  final end = rawConsumed + metadata.length;
  if (metadata.length > pageSize && !(allowOversizedComplete && known == end)) {
    throw oversized;
  }
  if (pageSizeValue != null && pageSizeValue != metadata.length) throw invalid;
  if (known != null) {
    if (end > known) throw invalid;
    if (metadata.isEmpty && rawConsumed < known) throw invalid;
  }
  return (metadata: metadata, knownTotal: known);
}

String _playlistOccurrenceId(Object? value) {
  const invalid = PlexException(
    'playlist-page-invalid',
    'Plex returned an invalid playlist page.',
  );
  final number = switch (value) {
    final num number => number,
    final String text => num.tryParse(text.trim()),
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

int? _pageCount(Object? value, PlexException invalid) {
  if (value == null) return null;
  final number = switch (value) {
    final num number => number,
    final String text => num.tryParse(text.trim()),
    _ => null,
  };
  if (number == null ||
      !number.isFinite ||
      number.isNegative ||
      number.abs() > _maxExactJsonInteger ||
      number.toInt() != number) {
    throw invalid;
  }
  return number.toInt();
}

int? _optionalInteger(Object? value) {
  final number = switch (value) {
    final num number => number,
    final String text => num.tryParse(text.trim()),
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
          final token = _optionalText(attribute.value);
          if (token != null) return token;
        }
      }
    }
  } catch (_) {}
  return null;
}

DynamicRange _dynamicRange(
  Map<Object?, Object?>? media,
  Iterable<String> streamCodecs,
) {
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

class _CollectionListingScaleException extends PlexException {
  const _CollectionListingScaleException()
    : super(
        'library-scale-exceeded',
        'Collection listing exceeded the supported limit.',
      );
}

class _LibraryMetadataPageLimitException extends PlexException {
  const _LibraryMetadataPageLimitException()
    : super(
        'library-scale-exceeded',
        'Library metadata exceeded the supported page limit.',
      );
}
