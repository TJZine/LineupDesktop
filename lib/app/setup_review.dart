import '../channels/channel.dart';
import '../channels/channel_builder.dart';
import 'channel_setup_projection.dart';

enum SetupReviewKind { unchanged, updated, added, removed }

typedef SetupReviewEntry = ({
  Channel channel,
  Channel? before,
  SetupReviewKind kind,
});

class SetupReviewCounts {
  const SetupReviewCounts({
    required this.unchanged,
    required this.updated,
    required this.added,
    required this.removed,
  });

  final int unchanged;
  final int updated;
  final int added;
  final int removed;

  bool get hasChanges => added != 0 || updated != 0 || removed != 0;

  @override
  bool operator ==(Object other) =>
      other is SetupReviewCounts &&
      other.unchanged == unchanged &&
      other.updated == updated &&
      other.added == added &&
      other.removed == removed;

  @override
  int get hashCode => Object.hash(unchanged, updated, added, removed);
}

typedef SetupReviewPlanFactory =
    ({
      ChannelPlanAllocation plan,
      Map<String, BuilderStrategy> strategyBySource,
    })
    Function(ChannelBuildMode mode, DateTime anchor);

sealed class SetupPhase {
  const SetupPhase(this.review);

  final SetupReview review;
}

final class Reviewing extends SetupPhase {
  const Reviewing(super.review, {required this.confirmed});

  final bool confirmed;
}

final class Applying extends SetupPhase {
  const Applying(super.review);
}

final class Failed extends SetupPhase {
  const Failed(super.review, this.error);

  final String error;
}

final class Completed extends SetupPhase {
  const Completed(super.review);
}

class SetupReview {
  SetupReview({
    required List<Channel> base,
    required ChannelPlanAllocation plan,
    required ChannelBuildMode mode,
    required Map<String, BuilderStrategy> strategyBySource,
    SetupReviewPlanFactory? planFactory,
    Set<String> removeSourceIds = const {},
  }) : this._(
         base: List.unmodifiable(base),
         plan: plan,
         mode: mode,
         removeSourceIds: Set.unmodifiable(removeSourceIds),
         strategyBySource: Map.unmodifiable(strategyBySource),
         planFactory: planFactory,
       );

  SetupReview._({
    required this.base,
    required this.plan,
    required this.mode,
    required this.removeSourceIds,
    required this.strategyBySource,
    required SetupReviewPlanFactory? planFactory,
  }) : finalChannels = _finalChannels(
         base: base,
         planned: plan.channels,
         mode: mode,
         removeSourceIds: removeSourceIds,
       ),
       _planFactory = planFactory {
    final computedEntries = _reviewEntries(
      base: base,
      planned: plan.channels,
      finalChannels: finalChannels,
    );
    entries = List.unmodifiable(computedEntries);
    counts = _countEntries(computedEntries);
  }

  final List<Channel> base;
  final ChannelPlanAllocation plan;
  final ChannelBuildMode mode;
  final Set<String> removeSourceIds;
  final Map<String, BuilderStrategy> strategyBySource;
  final List<Channel> finalChannels;
  late final List<SetupReviewEntry> entries;
  late final SetupReviewCounts counts;
  final SetupReviewPlanFactory? _planFactory;

  SetupReview withMode(ChannelBuildMode mode, DateTime anchor) {
    final factory = _planFactory;
    if (factory == null) {
      throw StateError('A plan factory is required to change setup mode.');
    }
    final result = factory(mode, anchor);
    return SetupReview(
      base: base,
      plan: result.plan,
      mode: mode,
      strategyBySource: result.strategyBySource,
      planFactory: factory,
    );
  }

  SetupReview withRemoval(String id, bool remove) {
    final next = {...removeSourceIds};
    if (remove) {
      next.add(id);
    } else {
      next.remove(id);
    }
    return SetupReview(
      base: base,
      plan: plan,
      mode: mode,
      removeSourceIds: next,
      strategyBySource: strategyBySource,
      planFactory: _planFactory,
    );
  }

  static List<Channel> _finalChannels({
    required List<Channel> base,
    required List<Channel> planned,
    required ChannelBuildMode mode,
    required Set<String> removeSourceIds,
  }) => composeChannelPlan(
    existing: base
        .where((channel) => !removeSourceIds.contains(channel.id))
        .toList(),
    planned: planned,
    mode: mode,
  );

  static List<SetupReviewEntry> _reviewEntries({
    required List<Channel> base,
    required List<Channel> planned,
    required List<Channel> finalChannels,
  }) {
    final before = {for (final channel in base) channel.id: channel};
    final finalIds = finalChannels.map((channel) => channel.id).toSet();
    final plannedIds = planned.map((channel) => channel.id).toSet();
    final entries = <SetupReviewEntry>[
      for (final channel in finalChannels)
        (
          channel: channel,
          before: before[channel.id],
          kind: before[channel.id] == null
              ? SetupReviewKind.added
              : plannedIds.contains(channel.id) &&
                    !canonicalChannelValueEquals(
                      before[channel.id]!.toJson(),
                      channel.toJson(),
                    )
              ? SetupReviewKind.updated
              : SetupReviewKind.unchanged,
        ),
      for (final channel in base.where(
        (channel) => !finalIds.contains(channel.id),
      ))
        (channel: channel, before: channel, kind: SetupReviewKind.removed),
    ];
    entries.sort((left, right) {
      final number = left.channel.number.compareTo(right.channel.number);
      return number != 0 ? number : left.kind.index.compareTo(right.kind.index);
    });
    return entries;
  }

  static SetupReviewCounts _countEntries(List<SetupReviewEntry> entries) =>
      SetupReviewCounts(
        unchanged: entries
            .where((entry) => entry.kind == SetupReviewKind.unchanged)
            .length,
        updated: entries
            .where((entry) => entry.kind == SetupReviewKind.updated)
            .length,
        added: entries
            .where((entry) => entry.kind == SetupReviewKind.added)
            .length,
        removed: entries
            .where((entry) => entry.kind == SetupReviewKind.removed)
            .length,
      );
}
