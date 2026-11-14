import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/channel_builder.dart';
import 'package:lineup_desktop/channels/channel_filter.dart';
import 'package:lineup_desktop/channels/content_resolver.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

const tv = PlexLibrary(id: 'tv', title: 'TV Shows', type: PlexLibraryType.show);
const film = PlexLibrary(
  id: 'film',
  title: 'Films',
  type: PlexLibraryType.movie,
);
final createdAt = DateTime.utc(2026, 11, 14, 12);

void main() {
  final items = [
    ...media(tv, 'Drama', 6),
    ...media(film, 'Drama', 7),
    ...media(film, 'Comedy', 4),
  ];

  List<ChannelProposal> proposals({
    List<PlexLibrary> libraries = const [tv, film],
    Set<BuilderStrategy> strategies = const {BuilderStrategy.genres},
    Set<BuilderStrategy> combine = const {},
  }) => buildChannelProposals(
    libraries: libraries,
    items: items,
    strategies: strategies,
    minimumItems: 1,
    crossLibraryStrategies: combine,
  );

  ChannelPlanAllocation plan(
    List<ChannelProposal> proposals, {
    List<Channel> existing = const [],
    ChannelBuildMode mode = ChannelBuildMode.replace,
    ChannelOrder order = ChannelOrder.mixed,
    PlaybackMode seriesMode = PlaybackMode.shuffle,
    PlaybackMode? variant,
    int alternates = 0,
    DateTime? time,
  }) => materializeChannelPlan(
    proposals: proposals,
    existing: existing,
    mode: mode,
    seriesMode: seriesMode,
    variantMode: variant,
    alternateCopies: alternates,
    order: order,
    anchor: time ?? createdAt,
    resolve: (source) => resolveContent(source, items),
  );

  test(
    'plain generated names and offline library tags distinguish sources',
    () {
      final single = plan(proposals(libraries: [tv])).channels.single;
      expect(single.name, 'Drama');
      expect(single.kind, ChannelKind.tv);

      final separate = plan(proposals()).channels;
      final drama = separate.where((c) => c.name == 'Drama').toList();
      expect(drama.map((c) => c.kind), [ChannelKind.film, ChannelKind.tv]);
      for (final channel in drama) {
        final offline = Channel.fromJson(channel.immutableCopy().toJson());
        expect(offline.sourceLibraries, channel.sourceLibraries);
        expect(offline.kind, channel.kind);
        expect(offline.libraryTitle, channel.libraryTitle);
      }

      final combined = plan(proposals(combine: {BuilderStrategy.genres}))
          .channels
          .first;
      expect(combined.name, 'Drama');
      expect(combined.libraryTitle, isNull);
      expect(combined.sourceLibraries.keys, unorderedEquals(['tv', 'film']));
      expect(combined.kind, ChannelKind.both);
    },
  );

  test('alternates use twins and extra modes use setup labels', () {
    final source = proposals(libraries: [tv]);
    expect(
      plan(
        source,
        alternates: 2,
        variant: PlaybackMode.sequential,
      ).channels.map((c) => c.name),
      ['Drama', 'Drama In Order', 'Drama 2', 'Drama 3'],
    );
    expect(
      plan(source, variant: PlaybackMode.block).channels.last.name,
      'Drama Mini-marathons',
    );
    expect(
      plan(
        source,
        seriesMode: PlaybackMode.sequential,
        variant: PlaybackMode.shuffle,
      ).channels.last.name,
      'Drama Shuffle',
    );
  });

  test('same-library duplicates get twins while custom names stay intact', () {
    final generated = proposals(
      libraries: [tv],
      strategies: {BuilderStrategy.genres, BuilderStrategy.collections},
    );
    final custom = channel('custom', 8, 'Drama');
    final result = plan(generated, existing: [custom]);
    expect(result.channels.map((c) => c.name), ['Drama 2', 'Drama 3']);
    final roster = composeChannelPlan(
      existing: [custom],
      planned: result.channels,
      mode: ChannelBuildMode.replace,
    );
    expect(roster.last, same(custom));
  });

  test(
    'grouped numbers follow source order and leave custom numbers reserved',
    () {
      final source = proposals(
        strategies: {BuilderStrategy.genres, BuilderStrategy.collections},
      );
      final custom = channel('custom', 2, 'Personal Channel');
      final mixed = plan(source, existing: [custom]).channels;
      final grouped = plan(
        source,
        existing: [custom],
        order: ChannelOrder.grouped,
      ).channels;
      expect(mixed.map(channelSourceType).take(4), [
        BuilderStrategy.collections,
        BuilderStrategy.genres,
        BuilderStrategy.collections,
        BuilderStrategy.genres,
      ]);
      expect(grouped.map(channelSourceType), [
        BuilderStrategy.collections,
        BuilderStrategy.collections,
        BuilderStrategy.collections,
        BuilderStrategy.genres,
        BuilderStrategy.genres,
        BuilderStrategy.genres,
      ]);
      expect(grouped.take(3).map((c) => c.libraryTitle), [
        'Films',
        'TV Shows',
        'Films',
      ]);
      expect(grouped.map((c) => c.number), [1, 3, 4, 5, 6, 7]);
    },
  );

  test('new phases are repeatable and merge retains anchor and favourite', () {
    final source = proposals();
    final first = plan(source).channels;
    final rebuilt = plan(source).channels;
    expect(first.map((c) => c.anchor).toSet(), hasLength(first.length));
    expect(rebuilt.map((c) => c.anchor), first.map((c) => c.anchor));
    for (final row in first) {
      final cycle = buildChannelSchedule(
        row,
        resolveContent(row.source, items),
      ).loopDuration;
      final offset = createdAt.difference(row.anchor);
      expect(offset, greaterThanOrEqualTo(Duration.zero));
      expect(offset, lessThan(cycle));
      expect(Channel.fromJson(row.toJson()).anchor, row.anchor);
    }
    final kept = first.first.copyWith(favorite: true);
    final later = createdAt.add(const Duration(days: 1));
    final update = plan(
      source,
      time: later,
      existing: [kept],
      mode: ChannelBuildMode.merge,
    ).channels;
    final matched = update.singleWhere((c) => c.id == kept.id);
    expect(matched.anchor, kept.anchor);
    expect(matched.favorite, isTrue);
    expect(
      update
          .where((c) => c.id != kept.id)
          .every((c) => c.anchor.isAfter(createdAt)),
      isTrue,
    );
  });

  test('kind includes custom picked items and unclassified sources', () {
    const episode = ChannelItem(
      id: 'e',
      title: 'Episode',
      duration: Duration(minutes: 1),
      mediaKind: ChannelMediaKind.episode,
    );
    const movie = ChannelItem(
      id: 'm',
      title: 'Film',
      duration: Duration(minutes: 1),
      mediaKind: ChannelMediaKind.movie,
    );
    expect(channelKindFor(const ManualSource([episode])), ChannelKind.tv);
    expect(channelKindFor(const ManualSource([movie])), ChannelKind.film);
    expect(
      channelKindFor(const ManualSource([episode, movie])),
      ChannelKind.both,
    );
    expect(
      channelKindFor(const PlaylistSource('unclassified')),
      ChannelKind.unknown,
    );
  });

  test(
    'filters expose ordered entries, library counts and original numbers',
    () {
      final rows = plan(
        proposals(
          strategies: {
            BuilderStrategy.collections,
            BuilderStrategy.genres,
            BuilderStrategy.recentlyAdded,
          },
          combine: {BuilderStrategy.genres},
        ),
      ).channels;
      final custom = channel('custom', 50, 'Personal Channel');
      final filter = ChannelFilter([
        rows.first.copyWith(favorite: true),
        ...rows.skip(1),
        custom,
      ]);
      expect(filter.entries.map((entry) => (entry.label, entry.count)), [
        ('All channels', 8),
        ('Favourites', 1),
        ('Collections', 3),
        ('Recently added', 2),
        ('Genres', 2),
        ('Custom', 1),
        ('Films', 5),
        ('TV Shows', 3),
      ]);
      expect(
        filter.channelsFor(ChannelFilter.favourites).single.number,
        rows.first.number,
      );
      final films = filter.entries.singleWhere(
        (entry) => entry.label == 'Films',
      );
      expect(filter.channelsFor(films.key).map((c) => c.number), [
        for (final row in rows)
          if (row.sourceLibraries.containsKey('film')) row.number,
      ]);
      expect(ChannelFilter([custom]).entries.map((entry) => entry.label), [
        'All channels',
        'Custom',
      ]);
    },
  );
}

Channel channel(String id, int number, String name) => Channel(
  id: id,
  number: number,
  name: name,
  source: const ManualSource([]),
  playbackMode: PlaybackMode.sequential,
  anchor: createdAt,
  shuffleSeed: 1,
);

List<PlexMediaItem> media(PlexLibrary library, String tag, int count) => [
  for (var i = 0; i < count; i++)
    PlexMediaItem(
      id: '${library.id}-$tag-$i',
      title: '$tag $i',
      type: library.type == PlexLibraryType.show ? 'episode' : 'movie',
      duration: Duration(minutes: 25 + i),
      libraryId: library.id,
      genres: [tag],
      collections: [tag],
      parts: [PlexMediaPart(path: '/synthetic/$i')],
    ),
];
