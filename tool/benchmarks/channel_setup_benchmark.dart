import 'dart:convert';
import 'dart:io';

import 'package:lineup_desktop/app/channel_setup_projection.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/channel_builder.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

Map<String, Object?> planFacts(Channel c) =>
    Map<String, Object?>.from(c.toJson())
      ..remove('id')
      ..remove('shuffleSeed');

void main() {
  stdout.writeln('Dart ${Platform.version} ${Platform.operatingSystem}');
  for (final size in [10000, 50000]) {
    final libraries = [
      for (var i = 0; i < 4; i++)
        PlexLibrary(
          id: '$i',
          title: 'Library $i',
          type: i.isEven ? PlexLibraryType.show : PlexLibraryType.movie,
        ),
    ];
    final media = [
      for (var i = 0; i < size; i++)
        PlexMediaItem(
          id: '$i',
          title: 'Media $i',
          type: i % 4 == 0 || i % 4 == 2 ? 'episode' : 'movie',
          duration: const Duration(minutes: 30),
          libraryId: '${i % 4}',
          grandparentRatingKey: 'show-${i % 100}',
          seasonNumber: i % 17 == 0 ? 0 : 1,
          episodeNumber: i,
          parts: [PlexMediaPart(path: '/part/$i')],
          genres: ['Genre ${i % 12}', 'Genre ${i % 7}'],
          collections: ['Collection ${i % 20}'],
          actors: ['Actor ${i % 32}'],
          directors: ['Director ${i % 15}'],
          studio: 'Studio ${i % 8}',
          year: 1980 + i % 40,
        ),
    ];
    final playlists = [
      for (var i = 0; i < 8; i++)
        PlexPlaylist(
          id: 'p$i',
          title: 'Playlist $i',
          items: media.skip(i * 10).take(100).toList(),
        ),
    ];
    List<ChannelProposal> classify(Set<BuilderStrategy> strategies) =>
        buildChannelProposals(
          libraries: libraries,
          items: media,
          playlists: playlists,
          strategies: strategies,
          crossLibraryStrategies: {
            BuilderStrategy.genres,
            BuilderStrategy.actors,
          },
          maximumChannels: null,
        );
    final anchor = DateTime.utc(2026, 10, 12);
    ChannelPlanAllocation allocate(List<ChannelProposal> proposals) =>
        materializeChannelPlan(
          proposals: proposals,
          existing: [],
          mode: ChannelBuildMode.replace,
          anchor: anchor,
        );
    final all = classify({...BuilderStrategy.values});
    void measure<T>(String name, T Function() run) {
      for (var i = 0; i < 3; i++) {
        run();
      }
      final times = <int>[];
      for (var i = 0; i < 9; i++) {
        final watch = Stopwatch()..start();
        run();
        times.add(watch.elapsedMicroseconds);
      }
      times.sort();
      stdout.writeln(
        '$size $name median_us=${times[4]} range_us=${times.first}..${times.last}',
      );
    }

    measure('classification', () => classify({...BuilderStrategy.values}));
    measure('allocation', () => allocate(all));
    final enabled = {
      BuilderStrategy.collections,
      BuilderStrategy.recentlyAdded,
      BuilderStrategy.genres,
      BuilderStrategy.studios,
    };
    measure('unchanged-render', () {
      final allocation = allocate(classify(enabled));
      for (final strategy in BuilderStrategy.values.where(
        (s) => !enabled.contains(s),
      )) {
        allocate(classify({strategy}));
      }
      return allocation;
    });
    final projection = ChannelSetupProjection();
    final selected = libraries.map((l) => l.id).toSet();
    final existing = <Channel>[];
    const options = (
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
    List<ChannelProposal> project(
      ChannelSetupProjection owner,
      Set<BuilderStrategy> strategies,
    ) => owner.proposals(
      libraries: libraries,
      items: media,
      playlists: playlists,
      selectedLibraries: selected,
      strategies: strategies,
      strategyOrder: BuilderStrategy.values,
      crossLibraryStrategies: {BuilderStrategy.genres, BuilderStrategy.actors},
      minimumItems: 5,
    );
    measure(
      'candidate-cold-all-strategies',
      () => project(ChannelSetupProjection(), {...BuilderStrategy.values}),
    );
    measure('candidate-cold-render', () {
      final owner = ChannelSetupProjection();
      project(owner, enabled);
      final allocation = owner.configure(existing: existing, options: options);
      for (final strategy in BuilderStrategy.values.where(
        (s) => !enabled.contains(s),
      )) {
        owner.disabledEligibility(strategy);
      }
      return allocation;
    });
    for (var mask = 0; mask < 256; mask++) {
      final strategies = {
        for (var i = 0; i < 8; i++)
          if (mask & (1 << i) != 0) BuilderStrategy.values[i],
      };
      final expected = allocate(classify(strategies));
      final actual = ChannelSetupProjection.allocate(
        project(projection, strategies),
        existing: existing,
        options: options,
        anchor: anchor,
      );
      if (jsonEncode(expected.channels.map((c) => planFacts(c)).toList()) !=
              jsonEncode(actual.channels.map((c) => planFacts(c)).toList()) ||
          jsonEncode(
                expected.eligibleOriginalsByStrategy.map(
                  (k, v) => MapEntry(k.name, v),
                ),
              ) !=
              jsonEncode(
                actual.eligibleOriginalsByStrategy.map(
                  (k, v) => MapEntry(k.name, v),
                ),
              )) {
        throw StateError('Output mismatch size=$size mask=$mask');
      }
    }
    project(projection, enabled);
    final cached = projection.configure(existing: existing, options: options);
    measure('candidate-unchanged-render-1000', () {
      for (var repeat = 0; repeat < 1000; repeat++) {
        project(projection, enabled);
        if (!identical(
          cached.channels,
          projection.configure(existing: existing, options: options).channels,
        )) {
          throw StateError('Preview was rebuilt');
        }
        for (final strategy in BuilderStrategy.values.where(
          (s) => !enabled.contains(s),
        )) {
          projection.disabledEligibility(strategy);
        }
      }
    });
    stdout.writeln(
      '$size output equality: all 256 strategy subsets; unchanged preview identity retained',
    );
    stdout.writeln(
      '$size proposals=${all.length} channels=${allocate(all).channels.length}',
    );
  }
}
