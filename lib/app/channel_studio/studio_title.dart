part of '../channel_studio_view.dart';

class _StudioTitle extends StatefulWidget {
  const _StudioTitle({
    required this.name,
    required this.number,
    required this.mode,
    required this.saved,
    required this.persisted,
    required this.conflict,
    required this.baseDeleted,
    required this.dirty,
    required this.generated,
    required this.busy,
    required this.saving,
    required this.canSave,
    required this.hasPendingChoice,
    required this.pendingHint,
    required this.onLeave,
    required this.onDuplicate,
    required this.onTune,
    required this.onSaveAndTune,
    required this.onSave,
    super.key,
  });
  final String name;
  final int? number;
  final ChannelStudioMode mode;
  final bool saved;
  final bool persisted;
  final bool conflict;
  final bool baseDeleted;
  final bool dirty;
  final bool generated;
  final bool busy;
  final bool saving;
  final bool canSave;
  final bool hasPendingChoice;
  final String pendingHint;
  final Future<void> Function() onLeave;
  final VoidCallback onDuplicate;
  final VoidCallback onTune;
  final VoidCallback onSaveAndTune;
  final VoidCallback onSave;
  @override
  State<_StudioTitle> createState() => _StudioTitleState();
}

class _StudioTitleState extends State<_StudioTitle> {
  final _backFocus = FocusNode(debugLabel: 'Back to Channels');
  final _saveFocus = FocusNode(debugLabel: 'Save channel');
  void focusSave() => _focusStudioNode(context, _saveFocus);
  @override
  void dispose() {
    _backFocus.dispose();
    _saveFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final number = widget.number;
    final saved = widget.saved;
    final persisted = widget.persisted;
    final roles = LineupTheme.of(context);
    final compact = LineupLayout.isCompactWidth(
      MediaQuery.sizeOf(context).width,
    );
    final name = widget.name.trim().isEmpty
        ? 'New channel'
        : widget.name.trim();
    final status = widget.conflict
        ? 'My draft retained'
        : widget.baseDeleted
        ? 'Source deleted'
        : widget.dirty
        ? 'Unsaved changes'
        : saved
        ? 'Saved'
        : 'Draft';
    final mode = _modeLabel(widget.mode);
    final titleStyle = LineupTypography.pageTitle.copyWith(
      color: roles.primaryText,
    );
    final statusStyle = _studioBodyStyle(
      context,
      color: widget.conflict || widget.baseDeleted
          ? Theme.of(context).colorScheme.error
          : roles.secondaryText,
    );
    final back = FocusTraversalOrder(
      order: const NumericFocusOrder(0),
      child: LineupInlineLink(
        focusNode: _backFocus,
        autofocus: true,
        onPressed: widget.busy ? null : () => unawaited(widget.onLeave()),
        child: const Text('‹ Channels'),
      ),
    );
    final actions = Align(
      widthFactor: 1,
      alignment: Alignment.centerRight,
      child: _studioActions(persisted: persisted, saved: saved),
    );
    final titleAndActions = LayoutBuilder(
      builder: (context, constraints) {
        final narrow = compact || constraints.maxWidth < 1000;
        final title = Semantics(
          header: true,
          excludeSemantics: true,
          label:
              '${number == null ? 'No channel number' : 'Channel $number'}, $name, ${_modeHeaderLabel(widget.mode)}, $mode, $status',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, softWrap: true, style: titleStyle),
              SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(mode, style: statusStyle),
                  Text('·', style: statusStyle),
                  Text(status, style: statusStyle),
                ],
              ),
            ],
          ),
        );
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [title, SizedBox(height: 12), actions],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            SizedBox(width: 24),
            actions,
          ],
        );
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(alignment: Alignment.centerLeft, child: back),
        SizedBox(height: 8),
        titleAndActions,
      ],
    );
  }

  Widget _pendingActionTooltip(Widget child) => widget.hasPendingChoice
      ? Tooltip(message: widget.pendingHint, child: child)
      : child;

  Widget _studioActions({required bool persisted, required bool saved}) {
    final recovering = widget.conflict || widget.baseDeleted;
    final showSave =
        !recovering &&
        (!widget.generated || !persisted || widget.dirty || widget.saving);
    final canSave = widget.canSave;
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (widget.generated && !recovering)
          FocusTraversalOrder(
            order: const NumericFocusOrder(4),
            child: OutlinedButton(
              onPressed: widget.busy ? null : widget.onDuplicate,
              child: const Text('Duplicate as custom'),
            ),
          ),
        if (persisted && !recovering)
          FocusTraversalOrder(
            order: const NumericFocusOrder(4),
            child: _pendingActionTooltip(
              saved
                  ? FilledButton.icon(
                      key: const Key('studio-tune'),
                      onPressed: widget.busy || widget.hasPendingChoice
                          ? null
                          : widget.onTune,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Tune in'),
                    )
                  : OutlinedButton.icon(
                      key: const Key('studio-tune'),
                      onPressed: canSave ? widget.onSaveAndTune : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Tune in'),
                    ),
            ),
          ),
        if (showSave)
          FocusTraversalOrder(
            order: const NumericFocusOrder(4),
            child: _pendingActionTooltip(
              FilledButton(
                focusNode: _saveFocus,
                onPressed: canSave ? widget.onSave : null,
                child: Text(
                  widget.saving
                      ? 'Saving…'
                      : switch (widget.mode) {
                          ChannelStudioMode.editCustom => 'Save changes',
                          ChannelStudioMode.inspectGenerated => 'Save identity',
                          _ => 'Save channel',
                        },
                ),
              ),
            ),
          ),
      ],
    );
  }
}
