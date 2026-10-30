import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lineup_desktop/platform/device_profile.dart';

import '../../ui/app_theme.dart';

class SetupStage extends StatelessWidget {
  const SetupStage({
    required this.child,
    required this.footer,
    this.footerGap = 12,
    super.key,
  });

  final Widget child;
  final Widget footer;
  final double footerGap;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final singleScroll =
        !DeviceProfile.of(context).isTv &&
        (media.size.width < 900 ||
            media.size.height < 720 ||
            media.textScaler.scale(14) >= 24);
    if (singleScroll) {
      return Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              key: const ValueKey('channel-setup-single-scroll'),
              child: SizedBox(
                height: math.max(760, media.size.height - 120),
                child: child,
              ),
            ),
          ),
          SizedBox(height: footerGap),
          footer,
        ],
      );
    }
    return Column(
      children: [
        Expanded(child: child),
        SizedBox(height: footerGap),
        footer,
      ],
    );
  }
}

class SetupFooter extends StatelessWidget {
  const SetupFooter({
    required this.leading,
    required this.trailing,
    this.summary,
    this.configuration = false,
    super.key,
  });

  final List<Widget> leading;
  final Widget trailing;
  final Widget? summary;
  final bool configuration;

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    if (configuration) {
      const footerTop = 24.0;
      final actionGroup = Wrap(
        spacing: 20,
        runSpacing: 12,
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [...leading, trailing],
      );
      return DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: roles.subtleBorder)),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: footerTop),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow =
                  constraints.maxWidth < 800 ||
                  MediaQuery.textScalerOf(context).scale(1) >= 1.5;
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ?summary,
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerRight, child: actionGroup),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (summary != null) Expanded(child: summary!),
                  if (summary != null) const SizedBox(width: 24),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: actionGroup,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: roles.subtleBorder)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (leading.isNotEmpty) Wrap(spacing: 8, children: leading),
            if (summary != null) ...[
              const SizedBox(width: 16),
              Expanded(child: summary!),
            ] else
              const Spacer(),
            const SizedBox(width: 16),
            trailing,
          ],
        ),
      ),
    );
  }
}

/// Setup's TV rows form a vertical reading sequence, including nested Retry
/// actions. Geometric traversal can otherwise skip a wide row in favor of a
/// narrow footer aligned with the previous control.
class SetupVerticalTraversalPolicy extends OrderedTraversalPolicy {
  SetupVerticalTraversalPolicy()
    : super(secondary: WidgetOrderTraversalPolicy());
  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    if (direction != TraversalDirection.up &&
        direction != TraversalDirection.down) {
      return super.inDirection(currentNode, direction);
    }
    final nodes =
        currentNode.nearestScope?.traversalDescendants.where((node) {
          final context = node.context;
          return node is! FocusScopeNode &&
              context != null &&
              identical(FocusTraversalGroup.maybeOfNode(node), this);
        }).toList() ??
        <FocusNode>[];
    final ordered = sortDescendants(nodes, currentNode).toList();
    final index = ordered.indexOf(currentNode);
    final next = index + (direction == TraversalDirection.down ? 1 : -1);
    if (index >= 0 && next >= ordered.length) return true;
    if (index < 0 || next < 0) {
      return super.inDirection(currentNode, direction);
    }
    requestFocusCallback(ordered[next]);
    return true;
  }
}
