import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/channel_setup_projection.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/channel_builder.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

const _options = (
  mode: ChannelBuildMode.replace,
  seriesMode: PlaybackMode.shuffle,
  seriesBlockSize: 3,
  alternateCopies: 0,
  variantMode: null,
  variantBlockSize: 3,
  includeSpecials: false,
  minimumItems: 5,
  maximumChannels: 200,
);

void main() {
  late ChannelSetupProjection projection;
  late List<PlexLibrary> libraries;
  late List<PlexMediaItem> items;
  late List<PlexPlaylist> playlists;
  late Set<String> selected;
  late Set<BuilderStrategy> strategies;
  late Set<BuilderStrategy> grouped;
  late List<BuilderStrategy> order;
  var minimum = 5;
  List<ChannelProposal> project() => projection.proposals(
    libraries: libraries,
    items: items,
    playlists: playlists,
    selectedLibraries: selected,
    strategies: strategies,
    strategyOrder: order,
    crossLibraryStrategies: grouped,
    minimumItems: minimum,
  );
  setUp(() {
    projection = ChannelSetupProjection();
    libraries = [
      for (var i = 0; i < 2; i++)
        PlexLibrary(id: '$i', title: 'Library $i', type: PlexLibraryType.show),
    ];
    items = [
      for (var i = 0; i < 30; i++)
        PlexMediaItem(
          id: '$i',
          title: 'Item $i',
          type: 'episode',
          duration: const Duration(minutes: 20),
          libraryId: '${i % 2}',
          grandparentRatingKey: 'show-$i',
          seasonNumber: 0,
          episodeNumber: i,
          parts: [PlexMediaPart(path: '/part/$i')],
          genres: ['Drama'],
          collections: ['Collection'],
          actors: ['Actor'],
          directors: ['Director'],
          studio: 'Studio',
          year: 2000,
        ),
    ];
    playlists = [PlexPlaylist(id: 'playlist', title: 'Playlist', items: items)];
    selected = {'0', '1'};
    strategies = {...BuilderStrategy.values};
    grouped = {};
    order = [...BuilderStrategy.values];
    minimum = 5;
  });

  test('all strategy subsets preserve builder proposal order and facts', () {
    for (var mask = 0; mask < 256; mask++) {
      strategies = {
        for (var i = 0; i < 8; i++)
          if (mask & (1 << i) != 0) BuilderStrategy.values[i],
      };
      final expected = buildChannelProposals(
        libraries: libraries,
        items: items,
        playlists: playlists,
        strategies: strategies,
        strategyOrder: order,
        crossLibraryStrategies: grouped,
        minimumItems: minimum,
        maximumChannels: null,
      );
      expect(project().map(_facts), expected.map(_facts));
    }
  });

  test(
    'tied playlist titles retain selected-only ordering at sort thresholds',
    () {
      libraries = [
        const PlexLibrary(
          id: 'movies',
          title: 'Movies',
          type: PlexLibraryType.movie,
        ),
      ];
      items = [
        for (var i = 0; i < 5; i++)
          PlexMediaItem(
            id: '$i',
            title: 'Movie $i',
            type: 'movie',
            duration: const Duration(minutes: 90),
            libraryId: 'movies',
            parts: [PlexMediaPart(path: '/part/$i')],
          ),
      ];
      selected = {'movies'};
      for (final count in [31, 32, 33, 34, 35, 36]) {
        playlists = [
          for (var i = 0; i < count; i++)
            PlexPlaylist(id: 'p$i', title: 'Same title', items: items),
        ];
        for (var mask = 1; mask < 256; mask += 2) {
          strategies = {
            for (var i = 0; i < 8; i++)
              if (mask & (1 << i) != 0) BuilderStrategy.values[i],
          };
          final expected = buildChannelProposals(
            libraries: libraries,
            items: items,
            playlists: playlists,
            strategies: strategies,
            minimumItems: 5,
            maximumChannels: null,
          );
          final actual = project();
          expect(
            actual.map(_facts),
            expected.map(_facts),
            reason: 'count=$count mask=$mask',
          );
          final limited = projection.configure(
            existing: const [],
            options: _optionsWith(maximumChannels: 1),
          );
          final direct = ChannelSetupProjection.allocate(
            expected,
            existing: const [],
            options: _optionsWith(maximumChannels: 1),
          );
          expect(
            limited.channels.map(_channelFacts),
            direct.channels.map(_channelFacts),
            reason: 'limit count=$count mask=$mask',
          );
        }
      }
    },
  );

  test('presentation and allocation edits reuse proposals; catalog dependencies invalidate', () {
    var proposals = project();
    final existing = <Channel>[];
    final preview = projection.configure(existing: existing, options: _options);
    expect(identical(project(), proposals), isTrue);
    expect(
      identical(
        projection.configure(existing: existing, options: _options).channels,
        preview.channels,
      ),
      isTrue,
    );
    final changes = <void Function()>[
      () => libraries = List.of(libraries),
      () => items = List.of(items),
      () => playlists = List.of(playlists),
      () => selected.remove('1'),
      () => grouped.add(BuilderStrategy.genres),
      () => order = order.reversed.toList(),
      () => minimum = 20,
      () => strategies.remove(BuilderStrategy.genres),
    ];
    for (final change in changes) {
      change();
      final next = project();
      expect(identical(next, proposals), isFalse);
      expect(
        next.map(_facts),
        buildChannelProposals(
          libraries: libraries.where((l) => selected.contains(l.id)).toList(),
          items: items,
          playlists: playlists,
          strategies: strategies,
          strategyOrder: order,
          crossLibraryStrategies: grouped,
          minimumItems: minimum,
          maximumChannels: null,
        ).map(_facts),
      );
      proposals = next;
    }
  });

  test('every allocation input and lineup replacement refreshes preview', () {
    final proposals = project();
    final existing = <Channel>[];
    var previous = projection.configure(existing: existing, options: _options);
    final changes = <ChannelSetupAllocationOptions>[
      _optionsWith(mode: ChannelBuildMode.append),
      _optionsWith(seriesMode: PlaybackMode.block),
      _optionsWith(seriesBlockSize: 5),
      _optionsWith(alternateCopies: 2),
      _optionsWith(variantMode: PlaybackMode.sequential),
      _optionsWith(variantBlockSize: 6),
      _optionsWith(includeSpecials: true),
      _optionsWith(minimumItems: 20),
      _optionsWith(maximumChannels: 1),
    ];
    for (final options in changes) {
      previous = projection.configure(existing: existing, options: _options);
      final next = projection.configure(existing: existing, options: options);
      expect(identical(next.channels, previous.channels), isFalse);
      expect(identical(project(), proposals), isTrue);
      final direct = ChannelSetupProjection.allocate(
        proposals,
        existing: existing,
        options: options,
      );
      expect(
        next.channels.map(_channelFacts),
        direct.channels.map(_channelFacts),
      );
      expect(
        next.eligibleOriginalsByStrategy,
        direct.eligibleOriginalsByStrategy,
      );
      expect(
        next.allocatedChannelsByStrategy,
        direct.allocatedChannelsByStrategy,
      );
      expect(next.excludedOriginals, direct.excludedOriginals);
      expect(next.excludedExtras, direct.excludedExtras);
      previous = next;
    }
    expect(
      identical(
        projection
            .configure(existing: List.of(existing), options: changes.last)
            .channels,
        previous.channels,
      ),
      isFalse,
    );
  });

  test(
    'disabled counts follow specials and playback; review gets fresh anchors',
    () {
      strategies.remove(BuilderStrategy.collections);
      final proposals = project();
      final existing = <Channel>[];
      const block = (
        mode: ChannelBuildMode.replace,
        seriesMode: PlaybackMode.block,
        seriesBlockSize: 3,
        alternateCopies: 0,
        variantMode: null,
        variantBlockSize: 3,
        includeSpecials: false,
        minimumItems: 5,
        maximumChannels: 200,
      );
      projection.configure(existing: existing, options: block);
      expect(projection.disabledEligibility(BuilderStrategy.collections), 0);
      const specials = (
        mode: ChannelBuildMode.replace,
        seriesMode: PlaybackMode.block,
        seriesBlockSize: 3,
        alternateCopies: 0,
        variantMode: null,
        variantBlockSize: 3,
        includeSpecials: true,
        minimumItems: 5,
        maximumChannels: 200,
      );
      projection.configure(existing: existing, options: specials);
      expect(projection.disabledEligibility(BuilderStrategy.collections), 2);
      final first = ChannelSetupProjection.allocate(
        proposals,
        existing: existing,
        options: _options,
        anchor: DateTime.utc(2026),
      );
      final second = ChannelSetupProjection.allocate(
        proposals,
        existing: existing,
        options: _options,
        anchor: DateTime.utc(2027),
      );
      expect(
        first.channels.every((c) => c.anchor == DateTime.utc(2026)),
        isTrue,
      );
      expect(
        second.channels.every((c) => c.anchor == DateTime.utc(2027)),
        isTrue,
      );
      final merged = ChannelSetupProjection.allocate(
        proposals,
        existing: first.channels,
        options: (
          mode: ChannelBuildMode.merge,
          seriesMode: PlaybackMode.shuffle,
          seriesBlockSize: 3,
          alternateCopies: 0,
          variantMode: null,
          variantBlockSize: 3,
          includeSpecials: false,
          minimumItems: 5,
          maximumChannels: 200,
        ),
        anchor: DateTime.utc(2027),
      );
      expect(merged.channels, first.channels);
    },
  );
}

Object _facts(ChannelProposal p) => [
  p.name,
  p.source.toJson(),
  p.mode,
  p.itemCount,
  p.playableItemCount,
  p.blockItemCountWithoutSpecials,
  p.strategy,
  p.series,
];

Map<String, Object?> _channelFacts(Channel c) =>
    Map<String, Object?>.from(c.toJson())
      ..remove('id')
      ..remove('shuffleSeed')
      ..remove('anchor');

ChannelSetupAllocationOptions _optionsWith({
  ChannelBuildMode mode = ChannelBuildMode.replace,
  PlaybackMode seriesMode = PlaybackMode.shuffle,
  int seriesBlockSize = 3,
  int alternateCopies = 0,
  PlaybackMode? variantMode,
  int variantBlockSize = 3,
  bool includeSpecials = false,
  int minimumItems = 5,
  int maximumChannels = 200,
}) => (
  mode: mode,
  seriesMode: seriesMode,
  seriesBlockSize: seriesBlockSize,
  alternateCopies: alternateCopies,
  variantMode: variantMode,
  variantBlockSize: variantBlockSize,
  includeSpecials: includeSpecials,
  minimumItems: minimumItems,
  maximumChannels: maximumChannels,
);
