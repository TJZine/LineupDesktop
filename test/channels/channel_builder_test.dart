import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/channels/channel_builder.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

void main() {
  test('builder output is deterministic and applies item minimums', () {
    final library = const PlexLibrary(
      id: '1',
      title: 'Movies',
      type: PlexLibraryType.movie,
    );
    final items = List.generate(
      6,
      (index) => PlexMediaItem(
        id: '$index',
        key: '/$index',
        title: 'Movie $index',
        type: 'movie',
        duration: const Duration(minutes: 90),
        libraryId: '1',
        genres: const ['Comedy'],
        year: 1981,
      ),
    );
    final first = buildChannelProposals(libraries: [library], items: items);
    final second = buildChannelProposals(
      libraries: [library],
      items: items.reversed.toList(),
    );
    expect(
      first.map(
        (proposal) =>
            '${proposal.strategy.name}:${proposal.name}:${proposal.itemCount}',
      ),
      second.map(
        (proposal) =>
            '${proposal.strategy.name}:${proposal.name}:${proposal.itemCount}',
      ),
    );
    expect(first.any((proposal) => proposal.name == 'Comedy'), isTrue);
    expect(first.any((proposal) => proposal.name == '1980s'), isTrue);
  });

  test('builder omits tags below the minimum', () {
    const library = PlexLibrary(
      id: '1',
      title: 'Movies',
      type: PlexLibraryType.movie,
    );
    final items = [
      const PlexMediaItem(
        id: '1',
        key: '/1',
        title: 'One',
        type: 'movie',
        duration: Duration(minutes: 1),
        libraryId: '1',
        genres: ['Rare'],
      ),
    ];
    final proposals = buildChannelProposals(
      libraries: [library],
      items: items,
      strategies: const {BuilderStrategy.genres},
    );
    expect(proposals, isEmpty);
  });
}
