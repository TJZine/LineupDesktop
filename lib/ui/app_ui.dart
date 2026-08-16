import 'package:flutter/material.dart';

import 'app_theme.dart';

abstract final class LineupLayout {
  static const compact = 900.0;
  static const expandedNavigation = 1100.0;
  static const readableWidth = 1120.0;

  static bool isCompactWidth(double width) => width < compact;
}

class LineupNotice extends StatelessWidget {
  const LineupNotice({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(LineupTheme.radiusSmall),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: color),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class LineupPage extends StatelessWidget {
  const LineupPage({
    required this.title,
    required this.child,
    this.actions,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? actions;

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    child: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = LineupLayout.isCompactWidth(constraints.maxWidth);
          return Padding(
            padding: EdgeInsets.all(compact ? 20 : 32),
            child: Center(
              child: ConstrainedBox(
                key: const ValueKey('lineup-page-content'),
                constraints: const BoxConstraints(
                  maxWidth: LineupLayout.readableWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (compact)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _PageTitle(title),
                          if (actions != null) ...[
                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: actions,
                            ),
                          ],
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(child: _PageTitle(title)),
                          ?actions,
                        ],
                      ),
                    const SizedBox(height: 24),
                    Expanded(child: child),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _PageTitle extends StatelessWidget {
  const _PageTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
  );
}

class LineupSection extends StatelessWidget {
  const LineupSection({required this.title, required this.children, super.key});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          const SizedBox(height: 16),
          const Divider(),
          ...children,
        ],
      ),
    ),
  );
}

class LineupEmptyState extends StatelessWidget {
  const LineupEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    super.key,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    ),
  );
}

class LineupSelectionCard extends StatefulWidget {
  const LineupSelectionCard({
    required this.selected,
    required this.onPressed,
    required this.child,
    this.autofocus = false,
    super.key,
  });
  final bool selected;
  final VoidCallback? onPressed;
  final Widget child;
  final bool autofocus;

  @override
  State<LineupSelectionCard> createState() => _LineupSelectionCardState();
}

class _LineupSelectionCardState extends State<LineupSelectionCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      button: true,
      selected: widget.selected,
      enabled: widget.onPressed != null,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : LineupTheme.fast,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(LineupTheme.radiusLarge + 3),
          border: Border.all(
            color: _focused
                ? LineupTheme.of(context).focusBorder
                : Colors.transparent,
            width: _focused ? LineupTheme.of(context).focusBorderWidth : 1,
          ),
        ),
        child: Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LineupTheme.radiusLarge),
            side: BorderSide(
              color: widget.selected
                  ? LineupTheme.of(context).progressFill
                  : LineupTheme.of(context).subtleBorder,
              width: widget.selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            autofocus: widget.autofocus,
            borderRadius: BorderRadius.circular(LineupTheme.radiusLarge),
            onFocusChange: (focused) => setState(() => _focused = focused),
            onTap: widget.onPressed,
            child: widget.child,
          ),
        ),
      ),
    ),
  );
}

Future<bool> confirmDestructiveAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ) ??
    false;
