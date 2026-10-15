import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/setup_review.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/channel_builder.dart';

void main() {
  final base = [_channel('existing', 1, 'Existing')];
  final planned = [
    _channel('existing', 1, 'Updated'),
    _channel('added', 2, 'Added'),
  ];
  final plan = _allocation(planned);

  test('materializes final channels, entries, and counts once', () {
    final review = SetupReview(
      base: base,
      plan: plan,
      mode: ChannelBuildMode.merge,
      strategyBySource: const {},
    );

    expect(review.finalChannels, planned);
    expect(review.entries.map((entry) => entry.kind), [
      SetupReviewKind.updated,
      SetupReviewKind.added,
    ]);
    expect(
      review.counts,
      const SetupReviewCounts(unchanged: 0, updated: 1, added: 1, removed: 0),
    );
  });

  test('withRemoval recomputes the snapshot and retains the plan', () {
    final review = SetupReview(
      base: base,
      plan: plan,
      mode: ChannelBuildMode.merge,
      strategyBySource: const {},
    );
    final removed = review.withRemoval('existing', true);

    expect(removed.removeSourceIds, {'existing'});
    expect(removed.plan, same(plan));
    expect(removed.finalChannels, [planned[1]]);
    expect(removed.entries.map((entry) => entry.kind), [
      SetupReviewKind.added,
      SetupReviewKind.removed,
    ]);
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
      removeSourceIds: const {'existing'},
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
    expect(next.finalChannels, replacement);
  });
}

ChannelPlanAllocation _allocation(List<Channel> channels) => (
  channels: channels,
  allocatedOriginals: channels.length,
  excludedOriginals: 0,
  allocatedExtras: 0,
  excludedExtras: 0,
  numberLimitExcluded: 0,
  existingSkipped: 0,
  unmatchedGenerated: const [],
  eligibleOriginalsByStrategy: const {},
  allocatedOriginalsByStrategy: const {},
  allocatedChannelsByStrategy: const {},
  truncated: false,
);

Channel _channel(String id, int number, String name) => Channel(
  id: id,
  number: number,
  name: name,
  source: const ManualSource([]),
  playbackMode: PlaybackMode.shuffle,
  anchor: DateTime.utc(2026),
  shuffleSeed: 1,
);
