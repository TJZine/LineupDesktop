import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

void main() {
  test('tagged copy retains every media fact and freezes list values', () {
    final original = PlexMediaItem(
      id: 'synthetic',
      title: 'Synthetic',
      type: 'episode',
      duration: const Duration(seconds: 123),
      libraryId: 'library',
      parentTitle: 'Season',
      grandparentTitle: 'Series',
      parentRatingKey: 'season',
      grandparentRatingKey: 'series',
      thumbPath: '/thumb',
      grandparentThumbPath: '/series-thumb',
      artPath: '/art',
      clearLogoPath: '/logo',
      parts: [
        PlexMediaPart(path: '/part', duration: const Duration(seconds: 123)),
      ],
      container: 'mkv',
      videoCodec: 'hevc',
      audioCodec: 'aac',
      dynamicRange: DynamicRange.hdr10,
      genres: ['Old genre'],
      collections: ['Old collection'],
      directors: ['Director'],
      actors: ['Actor'],
      cast: [
        const PlexCastMember(
          name: 'Actor',
          role: 'Role',
          thumbPath: '/portrait',
        ),
      ],
      studio: 'Studio',
      year: 2026,
      summary: 'Summary',
      contentRating: 'TV-G',
      seasonNumber: 2,
      episodeNumber: 3,
      videoResolution: '1080',
      audioChannels: 6,
      addedAt: DateTime.utc(2026),
      viewed: true,
    );
    final genres = ['New genre'];
    final collections = ['New collection'];
    final copy = PlexMediaItem.withTags(
      original,
      genres: genres,
      collections: collections,
    );
    // Explicitly enumerate the retained facts so a field omitted from the
    // shared copy initializer cannot silently fall back to its default.
    List<Object?> facts(PlexMediaItem item) => [
      item.id,
      item.title,
      item.type,
      item.duration,
      item.libraryId,
      item.parentTitle,
      item.grandparentTitle,
      item.parentRatingKey,
      item.grandparentRatingKey,
      item.thumbPath,
      item.grandparentThumbPath,
      item.artPath,
      item.clearLogoPath,
      item.parts,
      item.container,
      item.videoCodec,
      item.audioCodec,
      item.dynamicRange,
      item.directors,
      item.actors,
      item.cast,
      item.studio,
      item.year,
      item.summary,
      item.contentRating,
      item.seasonNumber,
      item.episodeNumber,
      item.videoResolution,
      item.audioChannels,
      item.addedAt,
      item.viewed,
    ];
    expect(facts(copy), facts(original));
    genres.clear();
    collections.clear();
    expect(copy.genres, ['New genre']);
    expect(copy.collections, ['New collection']);
    expect(original.genres, ['Old genre']);
    expect(original.collections, ['Old collection']);
    final retained = PlexMediaItem.withTags(original);
    expect(facts(retained), facts(original));
    expect(retained.genres, original.genres);
    expect(retained.collections, original.collections);
    expect(identical(copy.immutableCopy(), copy), isTrue);
    for (final values in <List<Object?>>[
      copy.parts,
      copy.genres,
      copy.collections,
      copy.directors,
      copy.actors,
      copy.cast,
    ]) {
      expect(values.clear, throwsUnsupportedError);
    }
  });

  test('exception categories preserve authorization and cancellation sets', () {
    for (final code in [
      'auth-invalid',
      'auth-required',
      'access-denied',
      'cancelled',
      'network-unavailable',
      'library-scale-exceeded',
      'unexpected',
    ]) {
      final error = PlexException(code, 'Synthetic failure.');
      expect(
        error.isAuthorizationFailure,
        ['auth-invalid', 'auth-required', 'access-denied'].contains(code),
      );
      expect(error.isCancellation, code == 'cancelled');
    }
  });
}
