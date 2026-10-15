import 'package:flutter/material.dart';

import '../../channels/channel.dart';
import '../../channels/channel_builder.dart';
import '../../ui/app_ui.dart';
import '../channel_setup_projection.dart';
import 'step_scaffold.dart';

class SetupConfigureFocus {
  SetupConfigureFocus()
    : playback = {
        for (final mode in PlaybackMode.values)
          mode: FocusNode(debugLabel: 'Setup playback ${mode.name}'),
      },
      order = {
        for (final strategy in BuilderStrategy.values)
          strategy: (earlier: FocusNode(), later: FocusNode()),
      };

  final Map<PlaybackMode, FocusNode> playback;
  final Map<BuilderStrategy, ({FocusNode earlier, FocusNode later})> order;

  void dispose() {
    for (final node in playback.values) {
      node.dispose();
    }
    for (final nodes in order.values) {
      nodes.earlier.dispose();
      nodes.later.dispose();
    }
  }
}

typedef SetupConfigureSectionBuilder = Widget Function(
  SetupConfigureFocus focus,
);

class SetupConfigureStep extends StatefulWidget {
  const SetupConfigureStep({
    required this.allocation,
    required this.section,
    required this.onSectionChanged,
    required this.onBack,
    required this.onReview,
    required this.hasConfirmedMissingSources,
    required this.summary,
    required this.buildSources,
    required this.buildPlayback,
    required this.buildRules,
    super.key,
  });

  final ChannelPlanAllocation allocation;
  final int section;
  final ValueChanged<int> onSectionChanged;
  final VoidCallback onBack;
  final VoidCallback onReview;
  final bool hasConfirmedMissingSources;
  final Widget summary;
  final SetupConfigureSectionBuilder buildSources;
  final SetupConfigureSectionBuilder buildPlayback;
  final SetupConfigureSectionBuilder buildRules;

  @override
  State<SetupConfigureStep> createState() => _SetupConfigureStepState();
}

class _SetupConfigureStepState extends State<SetupConfigureStep> {
  final _focus = SetupConfigureFocus();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SetupStage(
      footerGap: 0,
      footer: SetupFooter(
        configuration: true,
        leading: [
          TextButton(
            onPressed: widget.onBack,
            child: const Text('Back to libraries'),
          ),
        ],
        summary: widget.summary,
        trailing: FilledButton(
          key: const ValueKey('review-channels'),
          onPressed:
              widget.allocation.channels.isNotEmpty ||
                  widget.allocation.existingSkipped > 0 ||
                  widget.hasConfirmedMissingSources
              ? widget.onReview
              : null,
          child: const Text('Review channels'),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const labels = ['Channel sources', 'Playback order', 'Lineup rules'];
          final compact =
              constraints.maxWidth < 1100 ||
              MediaQuery.textScalerOf(context).scale(1) >= 1.6;
          final navigation = [
            for (var index = 0; index < labels.length; index++)
              Semantics(
                selected: widget.section == index,
                child: LineupNavigationRow(
                  selected: widget.section == index,
                  key: ValueKey('configure-section-$index'),
                  onPressed: () => widget.onSectionChanged(index),
                  child: Text(labels[index]),
                ),
              ),
          ];
          final selectedContent = switch (widget.section) {
            0 => widget.buildSources(_focus),
            1 => widget.buildPlayback(_focus),
            _ => widget.buildRules(_focus),
          };
          final content = KeyedSubtree(
            key: const ValueKey('channel-configuration'),
            child: ListView(
              key: ValueKey(widget.section),
              children: [
                if (widget.section != 2)
                  _heading(
                    labels[widget.section],
                    widget.section == 0
                        ? 'Choose which kinds of generated channels to include.'
                        : 'For generated channels containing TV episodes',
                  ),
                selectedContent,
              ],
            ),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(spacing: 8, runSpacing: 4, children: navigation),
                const SizedBox(height: 16),
                Expanded(child: content),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 236,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final item in navigation) ...[
                      item,
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 40),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }

  Widget _heading(String title, String description) {
    final roles = LineupTheme.of(context);
    final titleStyle = TextStyle(
      color: roles.primaryText,
      fontSize: 24,
      fontWeight: FontWeight.w600,
      height: 1.3,
    );
    final descriptionStyle = TextStyle(
      color: roles.secondaryText,
      fontSize: 18,
      height: 1.4,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final inline =
            constraints.maxWidth >= 640 &&
            MediaQuery.textScalerOf(context).scale(1) < 1.4;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: inline
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(title, style: titleStyle),
                    const SizedBox(width: 32),
                    Expanded(child: Text(description, style: descriptionStyle)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: titleStyle),
                    const SizedBox(height: 8),
                    Text(description, style: descriptionStyle),
                  ],
                ),
        );
      },
    );
  }
}
