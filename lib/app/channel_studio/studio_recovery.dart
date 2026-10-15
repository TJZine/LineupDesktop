part of '../channel_studio_view.dart';

class _StudioRecovery extends StatefulWidget {
  const _StudioRecovery({
    required this.baseDeleted,
    required this.saving,
    required this.error,
    required this.name,
    required this.number,
    required this.currentName,
    required this.onSaveAsNew,
    required this.onReturn,
    required this.onUseSaved,
    required this.onReplace,
    super.key,
  });
  final bool baseDeleted;
  final bool saving;
  final String? error;
  final String name;
  final String number;
  final String? currentName;
  final VoidCallback onSaveAsNew;
  final VoidCallback onReturn;
  final VoidCallback onUseSaved;
  final VoidCallback onReplace;
  @override
  State<_StudioRecovery> createState() => _StudioRecoveryState();
}

class _StudioRecoveryState extends State<_StudioRecovery> {
  final _recoveryFocus = FocusNode(debugLabel: 'Use saved Studio version');
  final _saveFocus = FocusNode(debugLabel: 'Save channel');
  void focusPrimary() =>
      _focusStudioNode(widget.baseDeleted ? _saveFocus : _recoveryFocus);
  @override
  void dispose() {
    _recoveryFocus.dispose();
    _saveFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roles = LineupTheme.of(context);
    final error = Theme.of(context).colorScheme.error;
    final currentName = widget.currentName;

    return Semantics(
      liveRegion: true,
      container: true,
      label: widget.error,
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            error.withValues(alpha: 0.08),
            roles.primarySurface,
          ),
          border: Border.all(color: error.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(roles.panelRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.report_problem_outlined, color: error, size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.baseDeleted
                            ? 'This channel was deleted'
                            : 'Another edit was saved first',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 4),
                      Text(
                        widget.baseDeleted
                            ? 'Your draft is retained for reference, but it will not recreate the deleted channel.'
                            : 'Your complete draft is retained. Choose which version should own channel ${widget.number}.',
                        style: TextStyle(color: roles.secondaryText),
                      ),
                      if (!widget.baseDeleted && currentName != null) ...[
                        SizedBox(height: 10),
                        _recoveryVersion('SAVED NOW', currentName),
                        _recoveryVersion(
                          'YOUR DRAFT',
                          widget.name.trim().isEmpty
                              ? 'Unnamed channel'
                              : widget.name.trim(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (widget.baseDeleted) ...[
                  OutlinedButton(
                    focusNode: _saveFocus,
                    onPressed: widget.saving ? null : widget.onSaveAsNew,
                    child: const Text('Save as new custom channel'),
                  ),
                  OutlinedButton(
                    onPressed: widget.saving ? null : widget.onReturn,
                    child: const Text('Return to Channels'),
                  ),
                ] else ...[
                  OutlinedButton(
                    focusNode: _recoveryFocus,
                    onPressed: widget.saving ? null : widget.onUseSaved,
                    child: const Text('Use saved version…'),
                  ),
                  OutlinedButton(
                    focusNode: _saveFocus,
                    onPressed: widget.saving ? null : widget.onReplace,
                    child: const Text('Replace saved version with my draft…'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _recoveryVersion(String label, String value) => Padding(
    padding: EdgeInsets.only(top: 3),
    child: Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: TextStyle(
              color: LineupTheme.of(context).mutedText,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.7,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
