import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/setup_review.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/channel_builder.dart';

void main() {
  final custom = _channel('custom', 1, 'Custom', generated: false);
  final retired = _channel('retired', 40, 'Retired');
  final base = [custom, _channel('existing', 2, 'Existing'), retired];
  final planned = [
    _channel('existing', 2, 'Updated'),
    _channel('added', 3, 'Added'),
  ];
  final plan = _allocation(planned, unmatched: [retired]);

  test('materializes final channels, entries, and counts once', () {
    final review = SetupReview(
      base: base,
      plan: plan,
      mode: ChannelBuildMode.merge,
      strategyBySource: const {},
    );

    expect(review.finalChannels.map((channel) => channel.name), [
      'Custom',
      'Updated',
      'Added',
      'Retired',
    ]);
    expect(review.entries.map((entry) => entry.kind), [
      SetupReviewKind.unchanged,
      SetupReviewKind.updated,
      SetupReviewKind.added,
      SetupReviewKind.unchanged,
    ]);
    expect(
      review.counts,
      const SetupReviewCounts(unchanged: 2, updated: 1, added: 1, removed: 0),
    );
  });

  test('withRemoval removes an unmatched generated source and preserves custom channels', () {
    final review = SetupReview(
      base: base,
      plan: plan,
      mode: ChannelBuildMode.merge,
      strategyBySource: const {},
    );
    final removed = review.withRemoval('retired', true);

    expect(removed.removeSourceIds, {'retired'});
    expect(removed.plan.channels.map((channel) => channel.id), [
      'existing',
      'added',
    ]);
    expect(removed.finalChannels.map((channel) => channel.id), [
      'custom',
      'existing',
      'added',
    ]);
    expect(removed.entries.map((entry) => entry.kind), [
      SetupReviewKind.unchanged,
      SetupReviewKind.updated,
      SetupReviewKind.added,
      SetupReviewKind.removed,
    ]);
    expect(removed.entries.last.channel.id, 'retired');
    expect(review.removeSourceIds, isEmpty);
    expect(review.finalChannels.last.id, 'retired');
    expect(removed.withRemoval('retired', false).counts, review.counts);
  });

  test('withMode uses the fresh anchor factory and clears removals', () {
    DateTime? receivedAnchor;
    ChannelBuildMode? receivedMode;
    final replacement = [_channel('replacement', 3, 'Replacement')];
    final review = SetupReview(
      base: base,
      plan: plan,
      mode: ChannelBuildMode.merge,
      strategyBySource: const {},
      removeSourceIds: const {'retired'},
      planFactory: (mode, anchor) {
        receivedMode = mode;
        receivedAnchor = anchor;
        return (plan: _allocation(replacement), strategyBySource: const {});
      },
    );

    final anchor = DateTime.utc(2026, 10, 15);
    final next = review.withMode(ChannelBuildMode.replace, anchor);

    expect(receivedMode, ChannelBuildMode.replace);
    expect(receivedAnchor, anchor);
    expect(next.removeSourceIds, isEmpty);
    expect(next.mode, ChannelBuildMode.replace);
    expect(next.finalChannels.map((channel) => channel.id), [
      'custom',
      'replacement',
    ]);
    expect(
      next.counts,
      const SetupReviewCounts(unchanged: 1, updated: 0, added: 1, removed: 2),
    );
  });

  test(
    'snapshot isolates mutable allocation, source data and review inputs',
    () {
      final baseGenres = ['Drama'];
      final nextGenres = ['Comedy'];
      final baseFilters = {LibraryFilter.genre: baseGenres};
      final nextFilters = {LibraryFilter.genre: nextGenres};
      final before = [
        _channel('existing', 2, 'Existing', filters: baseFilters),
        retired,
      ];
      final channels = [
        _channel('existing', 2, 'Updated', filters: nextFilters),
      ];
      final unmatched = [retired];
      final eligible = {BuilderStrategy.genres: 1};
      final allocated = {BuilderStrategy.genres: 1};
      final totals = {BuilderStrategy.genres: 1};
      final strategies = {'source': BuilderStrategy.genres};
      final removals = {'retired'};
      final review = SetupReview(
        base: before,
        plan: _allocation(
          channels,
          unmatched: unmatched,
          eligible: eligible,
          allocated: allocated,
          totals: totals,
        ),
        mode: ChannelBuildMode.merge,
        strategyBySource: strategies,
        removeSourceIds: removals,
      );
      final originalBase = review.base
          .map((channel) => channel.toJson())
          .toList();
      final originalFinal = review.finalChannels
          .map((channel) => channel.toJson())
          .toList();

      baseGenres.add('Mutated');
      nextGenres.clear();
      baseFilters.clear();
      nextFilters.clear();
      before.clear();
      channels.clear();
      unmatched.clear();
      eligible.clear();
      allocated.clear();
      totals.clear();
      strategies.clear();
      removals.clear();

      expect(
        review.base.map((channel) => channel.toJson()).toList(),
        originalBase,
      );
      expect(
        review.finalChannels.map((channel) => channel.toJson()).toList(),
        originalFinal,
      );
      expect(review.plan.channels.single.name, 'Updated');
      expect(review.plan.unmatchedGenerated.single.id, 'retired');
      expect(review.plan.eligibleOriginalsByStrategy, {
        BuilderStrategy.genres: 1,
      });
      expect(review.plan.allocatedOriginalsByStrategy, {
        BuilderStrategy.genres: 1,
      });
      expect(review.plan.allocatedChannelsByStrategy, {
        BuilderStrategy.genres: 1,
      });
      expect(review.strategyBySource, {'source': BuilderStrategy.genres});
      expect(review.removeSourceIds, {'retired'});
      expect(
        review.counts,
        const SetupReviewCounts(unchanged: 0, updated: 1, added: 0, removed: 1),
      );
      expect(() => review.plan.channels.clear(), throwsUnsupportedError);
      expect(
        () => (review.plan.channels.single.source as LibrarySource).filters
            .clear(),
        throwsUnsupportedError,
      );
      expect(
        () => (review.base.first.source as LibrarySource)
            .filters[LibraryFilter.genre]!
            .clear(),
        throwsUnsupportedError,
      );
    },
  );
}

ChannelPlanAllocation _allocation(
  List<Channel> channels, {
  List<Channel> unmatched = const [],
  Map<BuilderStrategy, int> eligible = const {},
  Map<BuilderStrategy, int> allocated = const {},
  Map<BuilderStrategy, int> totals = const {},
}) => (
  channels: channels,
  allocatedOriginals: channels.length,
  excludedOriginals: 0,
  allocatedExtras: 0,
  excludedExtras: 0,
  numberLimitExcluded: 0,
  existingSkipped: 0,
  unmatchedGenerated: unmatched,
  eligibleOriginalsByStrategy: eligible,
  allocatedOriginalsByStrategy: allocated,
  allocatedChannelsByStrategy: totals,
  truncated: false,
);

Channel _channel(
  String id,
  int number,
  String name, {
  bool generated = true,
  Map<LibraryFilter, List<String>> filters = const {},
}) => Channel(
  id: id,
  number: number,
  name: name,
  source: generated
      ? LibrarySource(
          libraryId: 'movies',
          libraryType: PlexLibraryType.movie,
          filters: filters,
        )
      : const ManualSource([]),
  builderKey: generated ? 'generated-$id' : null,
  playbackMode: PlaybackMode.shuffle,
  anchor: DateTime.utc(2026),
  shuffleSeed: 1,
);
