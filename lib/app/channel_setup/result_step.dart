import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/app_theme.dart';
import '../../ui/app_ui.dart';
import '../setup_review.dart';
import 'step_scaffold.dart';

class SetupResultStep extends StatefulWidget {
  const SetupResultStep({
    required this.phase,
    required this.totalChannels,
    required this.onBackToReview,
    required this.onViewLineup,
    required this.onAddCustom,
    super.key,
  });

  final SetupPhase phase;
  final int totalChannels;
  final VoidCallback onBackToReview;
  final VoidCallback onViewLineup;
  final VoidCallback onAddCustom;

  @override
  State<SetupResultStep> createState() => _SetupResultStepState();
}

class _SetupResultStepState extends State<SetupResultStep> {
  final _resultFocus = FocusNode(
    debugLabel: 'Setup result',
    onKeyEvent: (_, event) =>
        event is KeyRepeatEvent &&
            const [
              LogicalKeyboardKey.enter,
              LogicalKeyboardKey.numpadEnter,
              LogicalKeyboardKey.space,
              LogicalKeyboardKey.select,
              LogicalKeyboardKey.gameButtonA,
            ].contains(event.logicalKey)
        ? KeyEventResult.handled
        : KeyEventResult.ignored,
  );

  bool get _firstSetup => widget.phase.review.base.isEmpty;
  bool get _failed => widget.phase is Failed;
  bool get _applying => widget.phase is Applying;

  @override
  void initState() {
    super.initState();
    _focusTerminalResult();
  }

  void _focusTerminalResult() {
    if (widget.phase is Applying) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.phase is! Applying) _resultFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _resultFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SetupResultStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase.runtimeType != widget.phase.runtimeType &&
        widget.phase is! Applying) {
      _focusTerminalResult();
    }
  }

  @override
  Widget build(BuildContext context) {
    final review = widget.phase.review;
    final roles = LineupTheme.of(context);
    final headingStyle = LineupTypography.pageTitle.copyWith(
      color: roles.primaryText,
    );
    final infoStyle = Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: roles.secondaryText, fontSize: 24, height: 1.4);
    final detailStyle = Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: roles.secondaryText, fontSize: 18, height: 1.4);
    final changeSummary = [
      if (review.counts.added > 0) '${review.counts.added} Added',
      if (review.counts.updated > 0) '${review.counts.updated} Updated',
      if (review.counts.removed > 0) '${review.counts.removed} Removed',
    ].join(' · ');
    final headline = switch (widget.phase) {
      Applying() =>
        _firstSetup ? 'Creating your lineup…' : 'Updating your lineup…',
      Failed() =>
        _firstSetup
            ? 'We couldn’t create your lineup'
            : 'We couldn’t update your lineup',
      Completed() =>
        _firstSetup ? 'Your lineup is ready' : 'Your lineup is updated',
      Reviewing() => '',
    };
    final copy = Semantics(
      liveRegion: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: _firstSetup ? 116 : 144),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(headline, textAlign: TextAlign.center, style: headingStyle),
            const SizedBox(height: 24),
            if (widget.phase is Completed) ...[
              Text(
                '${widget.totalChannels} ${widget.totalChannels == 1 ? 'channel' : 'channels'} in your lineup',
                textAlign: TextAlign.center,
                style: infoStyle,
              ),
              if (!_firstSetup && changeSummary.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  changeSummary,
                  textAlign: TextAlign.center,
                  style: detailStyle,
                ),
              ],
            ] else if (_applying) ...[
              Text(
                '${_firstSetup ? 'Creating' : 'Updating'} ${review.plan.channels.length} ${review.plan.channels.length == 1 ? 'channel' : 'channels'}',
                textAlign: TextAlign.center,
                style: detailStyle,
              ),
            ] else if (_failed) ...[
              Text(
                _firstSetup
                    ? 'Your lineup wasn’t saved.'
                    : 'Your existing lineup hasn’t changed.',
                textAlign: TextAlign.center,
                style: detailStyle,
              ),
              const SizedBox(height: 4),
              Text(
                'Your setup choices are still here.',
                textAlign: TextAlign.center,
                style: detailStyle,
              ),
              if (widget.phase case Failed(:final error)) ...[
                const SizedBox(height: 14),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: detailStyle.copyWith(color: roles.liveAccent),
                ),
              ],
            ],
          ],
        ),
      ),
    );
    final actions = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 120),
      child: _applying
          ? const SizedBox(height: 120)
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 190),
                  child: FilledButton(
                    focusNode: _resultFocus,
                    onPressed: _failed
                        ? widget.onBackToReview
                        : widget.onViewLineup,
                    child: Text(_failed ? 'Back to review' : 'View lineup'),
                  ),
                ),
                if (!_failed) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: widget.onAddCustom,
                    child: const Text('Add a custom channel'),
                  ),
                ],
              ],
            ),
    );
    final group = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 42,
          height: _failed ? 42 : 0,
          child: _failed
              ? Icon(
                  Icons.error_outline,
                  size: 42,
                  color: Theme.of(context).colorScheme.error,
                )
              : null,
        ),
        const SizedBox(height: 24),
        _reveal(copy, slot: 'copy'),
        const SizedBox(height: 32),
        _reveal(actions, slot: 'actions'),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 0.0;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: SizedBox(width: double.infinity, child: group),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _reveal(Widget child, {required String slot}) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      key: ValueKey('result-$slot-${widget.phase.runtimeType}'),
      tween: Tween(begin: reduced ? 1 : .25, end: 1),
      duration: reduced ? Duration.zero : const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 4),
          child: child,
        ),
      ),
    );
  }
}
